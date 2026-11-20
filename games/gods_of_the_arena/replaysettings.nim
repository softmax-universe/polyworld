import polyworld/replaysettings as sharedSettings

export sharedSettings.ReplayPreferences

proc readReplayPreferences*(): ReplayPreferences =
  ## Reads GotA's recording choice from its existing device configuration.
  sharedSettings.readReplayPreferences("Polyworld GotA")

proc saveReplayPreferences*(preferences: ReplayPreferences) =
  ## Saves GotA's recording choice separately from shared match settings.
  sharedSettings.saveReplayPreferences(preferences, "Polyworld GotA")
