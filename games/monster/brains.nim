import
  std/[json, math, os, strutils, uri],
  polyworld/llms,
  common

when defined(windows):
  import std/winlean

const
  DefaultMonsterModel* = "gpt-6-sol"
  MaxMessageBytes = 4096
  MaxLessonBytes = 320
  MaxSaveBytes = MaxResponseBytes
  BrainInstructions = """
You are Moss, a curious young elemental creature in a small living landscape.
The player is your teacher and communicates with you in English. Speak briefly,
warmly, and in character. Understand language while learning the teacher's
preferences. You have a physical body with a limited set of real game actions.
Return JSON with speech, actions, and lessons, matching the supplied schema.

In speech, use known place names and the intended action, such as "I'll cross
the Willow Stream." Use "there" or "that spot" only for an unnamed destination.
Omit redundant destination phrases when naming the place is enough. Keep
numeric coordinates, internal landmark IDs, and action fields out of speech,
even when the teacher or earlier replies use them. Coordinates belong only in
the structured actions. Apply this to both acknowledgments and explanations
of what happened.

Choose only actions the teacher asks for or actions needed for their stated
goal. Conversational questions and teaching can have an empty actions list.
Never claim that a physical action already succeeded: your reply acknowledges
an intention. Only the later world events establish actual outcomes. Use
current observations to decide what is possible. Do not invent objects,
abilities, supplies, other creatures, or interactions. Ask a short question if
the request is ambiguous or cannot be performed with the available actions.

Actions execute in order and replace the previous plan when nonempty. Available
actions are move, gather, give, eat, rest, dance, stop, and wait. Every action has
kind, target, x, z, and duration fields. Use an empty target and zero values for
unused fields. Move to any observed place, household, or villager ID, or use
explicit x/z coordinates inside (-32, 32). Places include village (the shared
hall), home (your sleeping glade), river, and forest, plus the resource sources
and households below. Use the names from the observation in your speech.

Gather from berries (wild berries), farm (the villagers' grain), fish (fish at
the riverbank), pine (softwood), oak (hardwood), or stone (loose stone).
Gathering fills your remaining carrying capacity from that source; it does
not take supplies from a house, the hall, or a person. You can carry six units
total, including any mixture of food, wood, and stone. Give delivers ALL your
carried supplies to village or hall (shared storage), miller_hut, weaver_hut,
or mason_hut (household storage), or directly to ada, ben, clara, dara, eli, or
finn. Check observed cargo before promising to give a particular resource.
For different recipients, collect and deliver each load separately. Gather
and give automatically walk to the source or recipient before interacting.
An eat action consumes one carried food, never wood or stone. Rest at home or
where you are. Dance and wait can last up to 30 seconds. Stop cancels the
current plan. Rest at home automatically moves there first.

Villagers are independent people. They walk to gather or withdraw supplies,
eat when hungry, carry supplies home, fuel their hearths with pine or oak,
and repair their homes using stone and oak. They consume household and shared
stocks as needed. Food given to a person can feed them; other supplies go home
with them. Helping a named household means delivering to its hut, not merely
leaving resources in the hall. There are no actions to order villagers, repair
their homes yourself, build, craft, or fight. Use observed household needs,
resource availability, and your teacher's lessons when deciding how to help.
Do not assume a delivery has already been eaten, burned, or used for repairs.

Lessons are only NEW lasting preferences explicitly taught or reinforced by
the player, expressed as concise first-person memories. Do not turn a one-time
order into a standing rule. Preserve existing memories: do not repeat them in
lessons. A newer explicit correction takes precedence over an older lesson.
The full conversation is retained; no compaction or forgetting happens here.
World events and observations are facts about the game, not new player orders.
"""
  FeedbackInstructions = """
An action you intended to perform could not be completed. Read the recent
[Action feedback] records and current world observation, then tell your teacher
what happened in your own voice as Moss. Keep it brief, natural, and first
person. Explain the limitation, not engine terms like "not walkable" or an
error code. Do not invent a cause, a route, a bridge, or abilities that the
feedback does not establish. If the reason is unknown, say you cannot find a
way. You can ask what to do instead, but do not promise an unverified solution.
Focus on the newest reported action failure; older feedback is context.
For a blocked crossing, name only the obstacle you could not cross. Omit any
destination beyond it, including phrases like "to the spot you chose". For a
failed attempt to cross Willow Stream, say:
"I couldn't find a way across the Willow Stream. What should I do instead?"
This is a report, not a new player command. Return empty actions and lessons.
"""

type
  Brain* = ref object
    messages*: seq[Message]
    lessons*: seq[string]
    pending*: bool
    explanationPending*: bool
    failure*: string
    model*: string
    reply*: BrainReply
    client: LlmClient
    savePath: string
    request: int32
    requestBody, fallbackKeyFile: string
    triedFileKey: bool
    explaining: bool

proc document(body: string): JsonNode {.raises: [MonsterError].} =
  ## Parses bounded JSON and maps transport parsing errors to MonsterError.
  try:
    result = parseDocument(body)
  except LlmError:
    raise newException(MonsterError, getCurrentExceptionMsg())

proc field(node: JsonNode, key: string): JsonNode
    {.raises: [MonsterError].} =
  ## Reads a required JSON object field without coercing malformed input.
  if node == nil or node.kind != JObject or not node.hasKey(key):
    raise newException(MonsterError, "Missing creature field: " & key)
  node{key}

proc stringField(node: JsonNode, key: string, limit: int): string
    {.raises: [MonsterError].} =
  ## Reads a bounded string from a required JSON object field.
  let value = node.field(key)
  if value.kind != JString:
    raise newException(MonsterError, "Creature field must be text: " & key)
  result = value.getStr().strip()
  if result.len > limit or '\0' in result:
    raise newException(MonsterError, "Creature text exceeds limit: " & key)

proc numberField(node: JsonNode, key: string): float32
    {.raises: [MonsterError].} =
  ## Reads a finite action number without accepting string coercions.
  let value = node.field(key)
  if value.kind notin {JInt, JFloat}:
    raise newException(MonsterError, "Creature field must be numeric: " & key)
  let number = value.getFloat()
  if classify(number) in {fcNan, fcInf, fcNegInf} or
    abs(number) > 1000000:
      raise newException(MonsterError, "Invalid creature number: " & key)
  number.float32

proc parseAction(node: JsonNode): CreatureAction
    {.raises: [MonsterError].} =
  ## Validates one physical action before it reaches the simulation.
  let kind = node.stringField("kind", 16)
  result.kind =
    case kind
    of "move": MoveAction
    of "gather": GatherAction
    of "give": GiveAction
    of "eat": EatAction
    of "rest": RestAction
    of "dance": DanceAction
    of "stop": StopAction
    of "wait": WaitAction
    else:
      raise newException(MonsterError, "Unknown creature action: " & kind)
  result.target = node.stringField("target", 64)
  result.x = node.numberField("x")
  result.z = node.numberField("z")
  result.duration = node.numberField("duration")
  if result.duration < 0 or result.duration > 30:
    raise newException(MonsterError, "Action duration must be 0 to 30 seconds")
  case result.kind
  of MoveAction:
    if result.target.len == 0:
      if abs(result.x) >= MapHalf or abs(result.z) >= MapHalf:
        raise newException(MonsterError, "Move coordinates leave the map")
    elif result.target notin SourceIds and
      result.target notin DeliveryIds and
      result.target notin ["home", "river", "forest"]:
        raise newException(MonsterError, "Unknown move target: " & result.target)
  of GatherAction:
    if result.target notin SourceIds:
      raise newException(MonsterError, "Unknown gather source: " & result.target)
  of GiveAction:
    if result.target notin DeliveryIds:
      raise newException(MonsterError, "Unknown delivery recipient: " &
        result.target)
  of RestAction:
    if result.target notin ["", "home"]:
      raise newException(MonsterError, "Rest target must be home or empty")
  of EatAction, DanceAction, StopAction, WaitAction:
    if result.target.len > 0:
      raise newException(MonsterError, "This action has no target: " & kind)

proc parseReply*(body: string): BrainReply {.raises: [MonsterError].} =
  ## Validates speech, physical plans, and new memories as one transaction.
  let
    node = document(body)
    actions = node.field("actions")
    lessons = node.field("lessons")
  result.speech = node.stringField("speech", MaxMessageBytes)
  if result.speech.len == 0:
    raise newException(MonsterError, "Creature reply is empty")
  if actions.kind != JArray or actions.len > MaxActions:
    raise newException(MonsterError, "Creature action plan exceeds its limit")
  if lessons.kind != JArray or lessons.len > MaxLessons:
    raise newException(MonsterError, "Creature memory exceeds its lesson limit")
  for action in actions:
    result.actions.add parseAction(action)
  for value in lessons:
    if value.kind != JString:
      raise newException(MonsterError, "Creature lessons must be text")
    let lesson = value.getStr().strip()
    if lesson.len == 0 or lesson.len > MaxLessonBytes or '\0' in lesson:
      raise newException(MonsterError, "Creature lesson is empty or too long")
    if lesson notin result.lessons:
      result.lessons.add lesson

proc roleName(role: MessageRole): string {.raises: [].} =
  ## Gives saved message roles a stable readable representation.
  case role
  of PlayerMessage: "player"
  of CreatureMessage: "creature"
  of EventMessage: "event"
  of FeedbackMessage: "feedback"

when not defined(windows):
  ## Calls the C runtime's same-filesystem atomic file replacement.
  proc renameMemory(source, destination: cstring): cint
    {.importc: "rename", header: "<stdio.h>", raises: [].}

proc replaceMemory(source, destination: string) {.raises: [OSError].} =
  ## Replaces a same-directory save without a non-atomic copy fallback.
  when defined(windows):
    if moveFileExW(
      newWideCString(source),
      newWideCString(destination),
      MOVEFILE_REPLACE_EXISTING
    ) == 0:
      raiseOSError(osLastError())
  else:
    if renameMemory(source.cstring, destination.cstring) != 0:
      raiseOSError(osLastError())

proc saveBrain*(brain: Brain) {.raises: [MonsterError].} =
  ## Atomically saves conversation and lessons without credentials or secrets.
  if brain == nil or brain.savePath.len == 0:
    return
  var messages = newJArray()
  for message in brain.messages:
    messages.add %*{"role": roleName(message.role), "text": message.text}
  let
    body = $(%*{
      "version": 1, "messages": messages, "lessons": brain.lessons,
      "explanationPending": brain.explanationPending or brain.explaining
    })
    temporary = brain.savePath & ".tmp"
  if body.len > MaxSaveBytes:
    raise newException(MonsterError, "Creature save exceeds its byte limit")
  try:
    let directory = brain.savePath.parentDir()
    if directory.len > 0:
      createDir(directory)
    writeFile(temporary, body)
    replaceMemory(temporary, brain.savePath)
  except OSError, IOError:
    raise newException(MonsterError,
      "Could not save creature memory: " & getCurrentExceptionMsg())

proc loadBrain(brain: Brain) {.raises: [MonsterError].} =
  ## Restores the complete bounded transcript and lessons from disk.
  if brain.savePath.len == 0 or not fileExists(brain.savePath):
    return
  var body: string
  try:
    if getFileSize(brain.savePath) > MaxSaveBytes:
      raise newException(MonsterError, "Creature save exceeds its byte limit")
    body = readFile(brain.savePath)
  except OSError, IOError:
    raise newException(MonsterError,
      "Could not read creature memory: " & getCurrentExceptionMsg())
  let
    node = document(body)
    version = node.field("version")
    messages = node.field("messages")
    lessons = node.field("lessons")
  if version.kind != JInt or version.getInt() != 1:
    raise newException(MonsterError, "Unsupported creature memory version")
  if messages.kind != JArray or messages.len > MaxMessages:
    raise newException(MonsterError, "Saved conversation exceeds its limit")
  if lessons.kind != JArray or lessons.len > MaxLessons:
    raise newException(MonsterError, "Saved lessons exceed their limit")
  for value in messages:
    let role = value.stringField("role", 16)
    var message = Message(text: value.stringField("text", MaxMessageBytes))
    message.role =
      case role
      of "player": PlayerMessage
      of "creature": CreatureMessage
      of "event": EventMessage
      of "feedback": FeedbackMessage
      else:
        raise newException(MonsterError, "Unknown saved message role: " & role)
    brain.messages.add message
  if node.hasKey("explanationPending"):
    let pending = node.field("explanationPending")
    if pending.kind != JBool:
      raise newException(MonsterError, "Saved feedback state must be boolean")
    brain.explanationPending = pending.getBool()
  else:
    brain.explanationPending = brain.messages.len > 0 and
      brain.messages[^1].role == FeedbackMessage
  for value in lessons:
    if value.kind != JString:
      raise newException(MonsterError, "Saved lessons must be text")
    let lesson = value.getStr().strip()
    if lesson.len == 0 or lesson.len > MaxLessonBytes or '\0' in lesson:
      raise newException(MonsterError, "Saved lesson is empty or too long")
    brain.lessons.add lesson

proc newBrain*(
  savePath: string,
  client: LlmClient,
  model = DefaultMonsterModel,
  fallbackKeyFile = ""
): Brain {.raises: [MonsterError].} =
  ## Constructs a creature with an injectable asynchronous inference client.
  if client == nil or model.strip().len == 0:
    raise newException(MonsterError, "Creature requires a client and model")
  result = Brain(
    client: client, savePath: savePath, model: model,
    fallbackKeyFile: fallbackKeyFile
  )
  result.loadBrain()

proc keyFilePath(): string =
  ## Resolves the optional key file without reading credentials.
  let configured = getEnv("MONSTER_KEY_FILE").strip()
  if configured.len > 0: expandTilde(configured)
  else: getHomeDir() / "secrets" / "openai.key"

proc fileKey(path: string): string {.raises: [MonsterError].} =
  ## Reads one raw key while keeping its contents out of error messages.
  try:
    result = readFile(path).strip()
  except IOError:
    raise newException(MonsterError, "Could not read Monster key file: " & path)
  if result.len == 0:
    raise newException(MonsterError, "Monster key file is empty: " & path)

proc openaiKey(): string {.raises: [MonsterError].} =
  ## Uses the environment first, then reads the configured local key file.
  result = getEnv("OPENAI_API_KEY").strip()
  if result.len > 0:
    return
  let
    configured = getEnv("MONSTER_KEY_FILE").strip()
    path = keyFilePath()
  if configured.len == 0 and not fileExists(path):
    return
  result = fileKey(path)

proc directOpenai(config: LlmConfig): bool =
  ## Limits automatic file credentials to the validated native OpenAI route.
  not config.sidecar and config.baseUrl.len > 0 and
    parseUri(config.baseUrl).hostname.toLowerAscii() == "api.openai.com"

proc brainConfig*(
  model = DefaultMonsterModel,
  enabled = true
): LlmConfig {.raises: [MonsterError].} =
  ## Adds native OpenAI credentials without changing configured provider routes.
  if not enabled or not NativeRequests or
    getEnv("COGAME_LLM").toLowerAscii() == "off":
      return LlmConfig(model: model)
  try:
    result = llmConfig()
    if result.baseUrl.len == 0:
      let key = openaiKey()
      if key.len > 0:
        result = LlmConfig(
          baseUrl: "https://api.openai.com",
          key: key,
          interval: 1,
          timeoutMs: 30000
        )
    elif result.directOpenai() and result.key.strip().len == 0:
        result.key = openaiKey()
    result.model = model
  except LlmError, ValueError:
    raise newException(MonsterError, getCurrentExceptionMsg())

proc newBrain*(
  savePath: string,
  model = DefaultMonsterModel,
  enabled = true
): Brain {.raises: [MonsterError].} =
  ## Reuses configured inference or falls back to the native OpenAI API.
  try:
    let config = brainConfig(model, enabled)
    result = newBrain(
      savePath, newLlmClient(0, config), model,
      if config.directOpenai(): keyFilePath() else: ""
    )
  except LlmError, ValueError:
    raise newException(MonsterError, getCurrentExceptionMsg())
  if not result.client.available():
    result.failure =
      if not enabled or getEnv("COGAME_LLM").toLowerAscii() == "off":
        "Creature conversation is disabled."
      else:
        "Set OPENAI_API_KEY, add ~/secrets/openai.key, or configure a " &
          "Polyworld LLM endpoint to talk."

proc available*(brain: Brain): bool {.raises: [].} =
  ## Reports whether the creature has a configured native inference endpoint.
  brain != nil and brain.client.available()

proc replySchema(): JsonNode =
  ## Defines the narrow physical action vocabulary for structured generation.
  %*{
    "type": "object",
    "properties": {
      "speech": {"type": "string"},
      "actions": {
        "type": "array", "maxItems": MaxActions,
        "items": {
          "type": "object",
          "properties": {
            "kind": {"type": "string", "enum": [
              "move", "gather", "give", "eat", "rest", "dance", "stop", "wait"
            ]},
            "target": {"type": "string"},
            "x": {"type": "number"},
            "z": {"type": "number"},
            "duration": {"type": "number"}
          },
          "required": ["kind", "target", "x", "z", "duration"],
          "additionalProperties": false
        }
      },
      "lessons": {
        "type": "array", "maxItems": MaxLessons,
        "items": {"type": "string"}
      }
    },
    "required": ["speech", "actions", "lessons"],
    "additionalProperties": false
  }

proc requestBody(
  brain: Brain,
  text, observation: string,
  explaining = false
): string =
  ## Includes every retained message and lesson in the next physical decision.
  var input = newJArray()
  input.add %*{"role": "system", "content": BrainInstructions}
  if explaining:
    input.add %*{"role": "system", "content": FeedbackInstructions}
  input.add %*{
    "role": "system", "content": "Standing lessons, oldest first:\n" &
      brain.lessons.join("\n")
  }
  for message in brain.messages:
    case message.role
    of PlayerMessage:
      input.add %*{"role": "user", "content": message.text}
    of CreatureMessage:
      input.add %*{"role": "assistant", "content": message.text}
    of EventMessage:
      input.add %*{
        "role": "user", "content": "[World event] " & message.text
      }
    of FeedbackMessage:
      input.add %*{
        "role": "user", "content": "[Action feedback] " & message.text
      }
  let request =
    if explaining:
      "\n[Explain action feedback]\nTell your teacher what happened."
    else:
      "\n[Teacher says]\n" & text
  input.add %*{
    "role": "user", "content": "[Current world observation]\n" & observation &
      request
  }
  let schema = replySchema()
  if explaining:
    schema["properties"]["actions"]["maxItems"] = %0
    schema["properties"]["lessons"]["maxItems"] = %0
  $(%*{
    "model": brain.model,
    "input": input,
    "store": false,
    "reasoning": {"effort": "low"},
    "max_output_tokens": 1800,
    "text": {"format": {
      "type": "json_schema", "name": "creature_decision",
      "strict": true, "schema": schema
    }}
  })

proc saveVisible(brain: Brain) =
  ## Keeps a persistence failure visible without hiding an accepted command.
  try:
    brain.saveBrain()
  except MonsterError:
    brain.failure = getCurrentExceptionMsg()

proc requestFailure(brain: Brain): string =
  ## Explains service failures without exposing raw provider bodies or keys.
  case brain.client.status(brain.request)
  of 401:
    "LLM authentication failed (HTTP 401). Set a valid OPENAI_API_KEY " &
      "or key file, or check the configured endpoint credentials."
  of 403:
    "LLM access denied (HTTP 403). Check account access to " & brain.model & "."
  of 404:
    "LLM model or route unavailable (HTTP 404). Check " & brain.model &
      " and the configured endpoint."
  of 429:
    "LLM rate or spend limit reached (HTTP 429). Retry later or check " &
      "the account limits."
  of 500 .. 599:
    "The LLM service is unavailable. Try again shortly."
  else:
    "Moss could not answer: " & brain.client.error(brain.request)

proc retryAuthentication(brain: Brain, tick: int32): bool =
  ## Retries one rejected credential with the local file, preserving the turn.
  if brain.client.status(brain.request) != 401 or brain.triedFileKey or
    brain.fallbackKeyFile.len == 0:
      return false
  brain.triedFileKey = true
  let key = fileKey(brain.fallbackKeyFile)
  if key == brain.client.config.key:
    return false
  var config = brain.client.config
  config.key = key
  let client = newLlmClient(brain.client.slot, config)
  client.beginTick(tick)
  let request = client.ask("POST", "/v1/responses", brain.requestBody)
  if request == 0:
    client.close()
    raise newException(MonsterError, "Could not retry LLM authentication.")
  brain.client.close()
  brain.client = client
  brain.request = request
  true

proc submit*(brain: Brain, text, observation: string): bool =
  ## Starts one conversation turn while keeping the world responsive.
  if brain == nil:
    return false
  if brain.pending:
    brain.failure = "Moss is still thinking. Wait for the current reply."
    return false
  if not brain.available():
    if brain.failure.len == 0:
      brain.failure = "No LLM connection is configured."
    return false
  let spoken = text.strip()
  if spoken.len == 0:
    return false
  if spoken.len > MaxMessageBytes:
    brain.failure = "That message is too long. Use at most 4096 bytes."
    return false
  if brain.messages.len > MaxMessages - 2:
    brain.failure = "Conversation memory is full. No history was discarded."
    return false
  let body = brain.requestBody(spoken, observation)
  if body.len > MaxRequestBytes:
    brain.failure = "Conversation exceeds the LLM request limit. " &
      "No history was discarded; start a new creature to continue."
    return false
  try:
    brain.request = brain.client.ask("POST", "/v1/responses", body)
  except LlmError:
    brain.failure = getCurrentExceptionMsg()
    return false
  if brain.request == 0:
    brain.failure = "The LLM connection is still settling its last request."
    return false
  brain.failure.setLen(0)
  brain.requestBody = body
  brain.pending = true
  brain.explaining = false
  brain.messages.add Message(role: PlayerMessage, text: spoken)
  brain.saveVisible()
  true

proc reportProblem*(brain: Brain, text: string) =
  ## Retains private execution feedback and schedules the creature's response.
  if brain == nil or text.len == 0:
    return
  if brain.messages.len >= MaxMessages - 1:
    brain.failure = "Conversation memory is full. No history was discarded."
    return
  if text.len > MaxMessageBytes:
    brain.failure = "Action feedback exceeds the creature message limit."
    return
  brain.messages.add Message(role: FeedbackMessage, text: text)
  brain.explanationPending = true
  brain.saveVisible()

proc explainProblems*(brain: Brain, observation: string): bool =
  ## Sends pending feedback once inference is ready without inventing a turn.
  if brain == nil or not brain.explanationPending or brain.pending:
    return false
  if brain.failure.len > 0:
    brain.explanationPending = false
    brain.saveVisible()
    return false
  if not brain.available():
    brain.explanationPending = false
    if brain.failure.len == 0:
      brain.failure = "No LLM connection is configured."
    return false
  if brain.messages.len >= MaxMessages:
    brain.explanationPending = false
    brain.failure = "Conversation memory is full. No history was discarded."
    return false
  let body = brain.requestBody("", observation, explaining = true)
  if body.len > MaxRequestBytes:
    brain.explanationPending = false
    brain.failure = "Conversation exceeds the LLM request limit. " &
      "No history was discarded; start a new creature to continue."
    return false
  try:
    brain.request = brain.client.ask("POST", "/v1/responses", body)
  except LlmError:
    brain.explanationPending = false
    brain.failure = getCurrentExceptionMsg()
    return false
  if brain.request == 0:
    return false
  brain.explanationPending = false
  brain.explaining = true
  brain.pending = true
  brain.requestBody = body
  brain.failure.setLen(0)
  true

proc pollBrain*(brain: Brain, tick: int32): bool =
  ## Consumes a completed valid decision exactly once without waiting for HTTP.
  if brain == nil:
    return false
  brain.client.beginTick(tick)
  if not brain.pending:
    return false
  let state = brain.client.poll(brain.request)
  if state == 0:
    return false
  if state < 0:
    brain.failure = brain.requestFailure()
    try:
      if brain.retryAuthentication(tick):
        brain.failure.setLen(0)
        return false
    except MonsterError, LlmError:
      brain.failure.add " " & getCurrentExceptionMsg()
    brain.pending = false
    brain.explaining = false
    brain.explanationPending = false
    brain.request = 0
    brain.requestBody.setLen(0)
    brain.saveVisible()
    return false
  brain.pending = false
  brain.requestBody.setLen(0)
  try:
    let envelope = document(brain.client.response(brain.request))
    if envelope.kind != JObject:
      raise newException(MonsterError, "Creature response must be an object")
    if envelope.hasKey("status") and
      envelope{"status"}.getStr() notin ["", "completed"]:
        raise newException(MonsterError, "Creature response did not complete")
    var answer = parseReply(brain.client.text(brain.request))
    if brain.explaining:
      answer.actions.setLen(0)
      answer.lessons.setLen(0)
    var additions: seq[string]
    for lesson in answer.lessons:
      if lesson notin brain.lessons:
        additions.add lesson
    if brain.lessons.len + additions.len > MaxLessons:
      raise newException(MonsterError,
        "Creature lesson memory is full. No memories were discarded.")
    if brain.messages.len >= MaxMessages:
      raise newException(MonsterError,
        "Conversation memory is full. No history was discarded.")
    brain.reply = answer
    brain.lessons.add additions
    brain.messages.add Message(role: CreatureMessage, text: answer.speech)
    brain.failure.setLen(0)
    brain.explaining = false
    brain.saveVisible()
    result = true
  except MonsterError, LlmError:
    brain.failure = "Moss could not form a valid plan: " &
      getCurrentExceptionMsg()
    brain.explaining = false
    brain.explanationPending = false
    brain.saveVisible()
  brain.request = 0
  brain.explaining = false

proc addEvent*(brain: Brain, text: string) =
  ## Records a real simulation outcome so later plans use what actually happened.
  if brain == nil or text.len == 0:
    return
  let limit = MaxMessages - int(brain.pending)
  if brain.messages.len >= limit:
    brain.failure = "Conversation memory is full. No history was discarded."
    return
  if text.len > MaxMessageBytes:
    brain.failure = "World event exceeds the creature message limit."
    return
  brain.messages.add Message(role: EventMessage, text: text)
  brain.saveVisible()

proc close*(brain: Brain) =
  ## Saves memories and releases the outstanding inference worker symmetrically.
  if brain == nil:
    return
  brain.saveVisible()
  brain.client.close()
  brain.pending = false
  brain.request = 0
  brain.requestBody.setLen(0)
