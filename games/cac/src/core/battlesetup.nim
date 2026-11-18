## Shared battle choices for local play and universal relay rooms.
import
  jsony,
  sim

const
  MinBattlePlayers* = 2
  MaxBattlePlayers* = 7
  DefaultBattleActions* = 100_000'u32

type
  BattleSetupError* = object of CatchableError
  BattleSetup* = object
    seed*: int32 = 2026
    classes*: seq[HeroClass]
    maxActions*: uint32 = DefaultBattleActions

proc validateBattleSetup*(setup: BattleSetup) =
  ## Reject impossible rosters and limits before constructing any game.
  if setup.classes.len notin MinBattlePlayers .. MaxBattlePlayers:
    raise newException(BattleSetupError, "Choose between two and seven seats")
  if setup.maxActions notin 1'u32 .. 1_000_000'u32:
    raise newException(BattleSetupError, "Invalid battle action limit")

proc defaultBattleSetup*(players = 2): BattleSetup =
  ## Offer alternating class precons with a stable editable seed.
  if players notin MinBattlePlayers .. MaxBattlePlayers:
    raise newException(BattleSetupError, "Choose between two and seven seats")
  result = BattleSetup()
  for player in 0 ..< players:
    result.classes.add HeroClass(player mod (HeroClass.high.ord + 1))

proc resizeSetup*(setup: var BattleSetup, count: int) =
  ## Preserves existing classes and alternates newly added slots.
  if count notin MinBattlePlayers .. MaxBattlePlayers:
    raise newException(BattleSetupError, "Choose between two and seven seats")
  var classes = newSeq[HeroClass](count)
  for index in 0 ..< count:
    classes[index] =
      if index < setup.classes.len: setup.classes[index]
      else: HeroClass(index mod (HeroClass.high.ord + 1))
  setup.classes = classes

proc encodeBattleSetup*(setup: BattleSetup): string =
  ## Serialize only public class and match settings, never policy source.
  setup.validateBattleSetup()
  setup.toJson()

proc parseBattleSetup*(bytes: string): BattleSetup =
  ## Parse the bounded public setup with an actionable game-owned error.
  if bytes.len == 0 or bytes.len > 4096:
    raise newException(BattleSetupError, "Missing or oversized battle setup")
  try:
    result = bytes.fromJson(BattleSetup)
  except JsonError as error:
    raise newException(BattleSetupError, "Invalid battle setup: " & error.msg)
  result.validateBattleSetup()

proc battleSeats*(setup: BattleSetup): seq[Seat] =
  ## Materialize the selected canonical forty-card decks for local play.
  setup.validateBattleSetup()
  for heroClass in setup.classes:
    result.add precon(heroClass)
