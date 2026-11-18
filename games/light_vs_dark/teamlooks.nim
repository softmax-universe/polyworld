## Keeps fixed-team colors consistent across units, buildings, and portraits.

import
  diplomacies, factions

proc appearanceSlot*(settings: DiplomacySettings, player: int32): int =
  ## Selects one of the eight looks without changing the player's unit roles.
  let identity =
    if settings.enabled: player
    else: settings.teamFor(player)
  int(max(identity, 0)) mod FactionFiles.len

proc playerFactions*(seed: int32, settings: DiplomacySettings,
    players: int): seq[Faction] =
  ## Assigns the same seeded color to every member of a fixed team.
  let order = factionOrder(seed.int64)
  result = newSeq[Faction](players)
  for player in 0 ..< players:
    result[player] = order[Faction(settings.appearanceSlot(player.int32))]

proc teamLabel*(settings: DiplomacySettings, player: int32): string =
  ## Presents zero-based stored team identifiers as player-facing numbers.
  "Team " & $(settings.teamFor(player) + 1)
