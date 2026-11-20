import polyworld/replaysettings as sharedSettings

export sharedSettings.ReplayPreferences

proc readReplayPreferences*(): ReplayPreferences =
  ## Reads CaC's recording choice from its existing device configuration.
  sharedSettings.readReplayPreferences("Polyworld CaC")

proc saveReplayPreferences*(preferences: ReplayPreferences) =
  ## Saves CaC's recording choice separately from shared match settings.
  sharedSettings.saveReplayPreferences(preferences, "Polyworld CaC")
