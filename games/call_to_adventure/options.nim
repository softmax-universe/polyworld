## Pure command-line configuration for Call to Adventure.

import
  std/[os, strutils],
  polyworld/cli,
  content

const SupportedFlags =
  when defined(headless):
    AllCommonFlags - {ServerFlag, RoomFlag}
  else:
    AllCommonFlags - {ServerFlag, RoomFlag, LlmModeFlag, HeadlessTickRateFlag}

proc fail(message: string) {.noreturn.} =
  ## Reports invalid launch options without starting a game.
  raise newException(CliError, message)

proc usage() =
  ## Prints shared options and Call to Adventure's arena extensions.
  echo "Call to Adventure"
  echo commonUsageFor(SupportedFlags)
  echo "Live expeditions have four slots; --player occupies one of them."
  echo "  --arena                 Debug fight in one 10x10 room."
  echo "  --hero CLASS[,CLASS]    Arena party; default mage,fighter."
  echo "  --monster NAME[,NAME]   Arena species, cycled; default dustling."
  echo "  --monsters N            Arena monster count, 1 to 24; default 10."
  echo "Screenshot captures use bundled bots when no roster is supplied."
  echo "Audio flags are accepted; this client currently has no audio output."

type ArenaOptions* = object
  ## The debug fight that replaces the dungeon when enabled.
  enabled*: bool
  heroes*: seq[HeroClass]
  species*: seq[Species]
  count*: int

proc defaultArenaOptions*(): ArenaOptions =
  ## Returns a fresh arena configuration for one command-line parse.
  ArenaOptions(
    heroes: @[WizardClass, FighterClass],
    species: @[DustlingSpecies],
    count: 10
  )

proc squashed(name: string): string =
  ## Lowercases a name and drops spaces, dashes and underscores.
  for ch in name:
    if ch.isAlphaNumeric:
      result.add ch.toLowerAscii

proc heroName*(class: HeroClass): string =
  ## A class's plain name, such as Fighter.
  ($class)[0 ..< ($class).len - "Class".len]

proc parseArenaHero(name: string): HeroClass =
  ## Reads a hero class by its plain name, in any case. The rogue, who
  ## carries the bow, also answers to archer and ranger, the wizard to mage
  ## and arcanist, and the cleric to druid.
  if name.squashed in ["archer", "ranger"]:
    return RogueClass
  if name.squashed in ["mage", "arcanist"]:
    return WizardClass
  if name.squashed == "druid":
    return ClericClass
  for class in HeroClass:
    if class.heroName.squashed == name.squashed:
      return class
  fail("unknown --hero " & name & "; use mage, archer, fighter or druid")

proc parseArenaMonster(name: string): Species =
  ## Reads a species by its display name, ignoring case, spaces and dashes.
  for species in Species:
    if SpeciesNames[species].squashed == name.squashed:
      return species
  var names: seq[string]
  for species in Species:
    names.add SpeciesNames[species].toLowerAscii.replace(' ', '_')
  fail("unknown --monster " & name & "; use one of " & names.join(", "))

proc parseArenaHeroes(names: string): seq[HeroClass] =
  ## Reads a comma-separated party, each class at most once.
  for name in names.split(','):
    let class = parseArenaHero(name)
    if class in result:
      fail("--hero names the " & class.heroName & " twice")
    result.add class

proc parseArenaCount(value: string): int =
  ## Reads how many monsters the arena spawns.
  try:
    result = parseInt(value)
  except ValueError:
    fail("--monsters takes a count; pick species with --monster:" & value)
  if result notin 1 .. ArenaMonsterLimit:
    fail("--monsters takes 1 to " & $ArenaMonsterLimit)

proc arenaMonsters*(arenaOptions: ArenaOptions): seq[Species] =
  ## The arena's monsters, cycling through the chosen species.
  for index in 0 ..< arenaOptions.count:
    result.add arenaOptions.species[index mod arenaOptions.species.len]

proc takeArenaFlag(
    arenaOptions: var ArenaOptions,
    arguments: seq[string],
    index: var int,
    argument: string
): bool =
  ## Handles the debug arena flags. Picking heroes or monsters implies it.
  if argument == "--arena":
    arenaOptions.enabled = true
    return true
  for flag in ["--hero", "--monsters", "--monster"]:
    var value = ""
    if argument == flag:
      value = arguments.argumentValue(index, argument)
    elif argument.startsWith(flag & ":") or argument.startsWith(flag & "="):
      value = argument[flag.len + 1 .. ^1]
    else:
      continue
    arenaOptions.enabled = true
    case flag
    of "--hero":
      arenaOptions.heroes = parseArenaHeroes(value)
    of "--monsters":
      arenaOptions.count = parseArenaCount(value)
    else:
      arenaOptions.species = @[]
      for name in value.split(','):
        arenaOptions.species.add parseArenaMonster(name)
    return true

proc parseGameOptions*(
    arguments = commandLineParams()
): tuple[options: GameOptions, arena: ArenaOptions] =
  ## Parses runtime game, bot, replay, and renderer configuration.
  var options = GameOptions(
    seed: 2026,
    seconds: DefaultMinutes * 60,
    maximumTicks: DefaultDurationTicks,
    speed: 1
  )
  var arenaOptions = defaultArenaOptions()
  var index = 0
  while index < arguments.len:
    let argument = arguments[index]
    if options.takeCommonFlag(arguments, index, argument):
      discard
    elif arenaOptions.takeArenaFlag(arguments, index, argument):
      discard
    else:
      case argument
      of "--help", "-h":
        usage()
        quit(0)
      else:
        fail("unknown argument: " & argument)
    inc index
  when not defined(headless) and not defined(emscripten):
    if options.capture.path.len > 0 and options.botGroups.len == 0 and
      options.replayPath.len == 0 and options.playerSlot == 0:
        options.botGroups.add BotGroup(
          path: currentSourcePath().parentDir / "players" / "base.bas",
          count: PartySize
        )
  options.rejectUnsupportedFlags(SupportedFlags)
  options.resolveGamePaths()
  if options.playerName.len > 0 and options.playerSlot == 0:
    fail("--name requires --player in Call to Adventure")
  options.validateGameOptions(
    PartySize,
    "a live expedition requires exactly four bots"
  )
  if arenaOptions.enabled and
      (options.recordPath.len > 0 or options.replayPath.len > 0):
    fail("--arena is a debug fight and cannot record or replay")
  (options, arenaOptions)
