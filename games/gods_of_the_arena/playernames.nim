import std/strutils
import polyworld/rooms

proc eligiblePlayerName*(name: string): bool =
  ## A GotA human must choose a printable name, not the legacy placeholder.
  ## Compare a trimmed copy only: valid saved/wire names remain opaque.
  name.len <= 64 and name.validName and
    name.strip().toLowerAscii() != "player"
