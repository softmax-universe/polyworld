import polyworld/replaysettings as sharedSettings

export sharedSettings.ReplayPreferences

proc readReplayPreferences*(): ReplayPreferences =
  ## Reads LvD's recording choice from its existing device configuration.
  sharedSettings.readReplayPreferences("Polyworld LvD")

proc saveReplayPreferences*(preferences: ReplayPreferences) =
  ## Saves LvD's recording choice separately from shared match settings.
  sharedSettings.saveReplayPreferences(preferences, "Polyworld LvD")
