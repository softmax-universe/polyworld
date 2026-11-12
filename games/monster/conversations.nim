import
  std/strutils,
  common, sim, brains

proc outcomes*(world: var World, brain: Brain, savePath: string) =
  ## Delivers world results and lets Moss explain failures in its own words.
  let changed = world.events.len > 0 or world.problems.len > 0
  for text in world.events:
    brain.addEvent(text)
  for text in world.problems:
    brain.reportProblem(text)
  world.events.setLen(0)
  world.problems.setLen(0)
  if changed and savePath.len > 0:
    world.saveWorld(savePath)
  if brain.explanationPending and not brain.pending:
    discard brain.explainProblems(world.observation())

proc receive*(world: var World, brain: Brain): bool =
  ## Validates proposed actions and returns rejected plans to the creature.
  if not brain.pollBrain(world.tick):
    return false
  try:
    world.instruct(brain.reply.actions)
  except MonsterError:
    brain.reportProblem(
      "The proposed plan was rejected before any of its actions started. " &
        getCurrentExceptionMsg()
    )
  true

proc speak*(world: var World, brain: Brain, text: string): bool =
  ## Sends teacher speech with the latest grounded state of the world.
  if text.strip().len == 0:
    return false
  brain.submit(text, world.observation())

proc sendPrompt*(
  world: var World,
  brain: Brain,
  prompt: string,
  attempted: var bool
): bool =
  ## Waits for restored feedback before attempting one automatic instruction.
  if attempted or prompt.len == 0 or brain.pending or brain.explanationPending:
    return false
  attempted = true
  world.speak(brain, prompt)
