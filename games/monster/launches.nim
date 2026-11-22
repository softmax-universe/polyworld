import
  std/os,
  ../../experiments/voice/launches as voiceLaunches

const
  MonsterDir = currentSourcePath().parentDir
  RepositoryDir = MonsterDir.parentDir.parentDir
  MonsterIdentifier = "org.polyworld.monster"

proc restoreMonsterDirectory*() =
  ## Restores the terminal directory before parsing relative game arguments.
  voiceLaunches.restoreApplicationDirectory(MonsterIdentifier)

proc launchMonster*(): bool =
  ## Gives Monster its own microphone identity without changing CLI arguments.
  voiceLaunches.launchApplication(
    name = "Monster",
    identifier = MonsterIdentifier,
    appPath = RepositoryDir / "tmp/Monster.app",
    infoPlist = MonsterDir / "macos.plist",
    binary = "monster",
    includeFonts = false
  )

proc finishMonster*() =
  ## Reports a clean game exit to the terminal that launched the native app.
  voiceLaunches.finishApplication(MonsterIdentifier)
