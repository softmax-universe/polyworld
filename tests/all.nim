## Builds the focused CI checks once per operating system.

when not defined(replayEvents):
  {.error: "CI checks require replay events.".}

{.warning[UnusedImport]: off.}

# These fixtures expect the initial terrain dimensions.
import ../games/gods_of_the_arena/tests/test_abilities as TestGotaAbilities
# Recording subprocesses exit here before running the remaining unit tests.
import determinism
import
  test_cli,
  ../games/crewrift/tests/test_sim as TestCrewrift,
  ../games/crewrift/tests/test_bots as TestCrewriftBots,
  ../games/crewrift/tests/test_skins as TestCrewriftSkins,
  test_annotations,
  test_policy_hosts,
  test_tapes,
  test_policy_packages,
  test_tensors,
  ../games/gods_of_the_arena/tests/test_tensor_matches as TestTensorMatches,
  ../games/gods_of_the_arena/tests/test_neural as TestGotaNeural,
  ../games/gods_of_the_arena/tests/test_andre as TestGotaAndre,
  ../games/gods_of_the_arena/tests/test_fly as TestGotaFly,
  ../games/gods_of_the_arena/tests/test_host as TestGotaHost,
  ../games/gods_of_the_arena/tests/test_structures as TestGotaStructures,
  ../games/gods_of_the_arena/tests/test_observations as TestGotaObservations,
  ../games/gods_of_the_arena/tests/test_targets as TestGotaTargets,
  ../games/gods_of_the_arena/tests/test_replays as TestGotaReplays,
  ../games/gods_of_the_arena/tests/test_attacks as TestGotaAttacks,
  ../games/gods_of_the_arena/tests/test_decisions as TestGotaDecisions,
  ../games/gods_of_the_arena/tests/test_events as TestGotaEvents,
  ../games/gods_of_the_arena/tests/test_phases as TestGotaPhases,
  ../games/gods_of_the_arena/tests/test_controls as TestGotaControls,
  ../games/gods_of_the_arena/tests/test_camps as TestGotaCamps,
  ../games/gods_of_the_arena/tests/test_portals as TestGotaPortals,
  ../games/gods_of_the_arena/tests/test_potions as TestGotaPotions,
  ../games/gods_of_the_arena/tests/test_progression as TestGotaProgression,
  ../games/gods_of_the_arena/tests/test_scores as TestGotaScores,
  ../games/gods_of_the_arena/tests/test_gods as TestGotaGods,
  ../games/gods_of_the_arena/tests/test_drafts as TestGotaDrafts,
  ../games/gods_of_the_arena/tests/test_training as TestGotaTraining,
  test_llms,
  test_llm_hosts,
  test_rooms,
  test_generic_relay,
  test_cosmetic_ready,
  test_room_codes,
  test_relay_async_hashes,
  test_relay_readiness,
  test_start_intent,
  test_sparse_rooms,
  test_room_resize,
  test_opaque_setup,
  test_client_loading_gap,
  test_roomclients,
  test_networks,
  ../games/gods_of_the_arena/tests/test_multiplayer as TestGotaMultiplayer

# Exercise game adapters against the shared relay, including live ownership,
# reconnect recovery, and warnings derived only from the local simulation.
import
  ../games/gods_of_the_arena/tests/test_live_slots as TestGotaLiveSlots,
  ../games/gods_of_the_arena/tests/test_auto_seats as TestGotaAutoSeats,
  ../games/gods_of_the_arena/tests/test_match_notice_network as TestGotaLocalNotices,
  ../games/light_vs_dark/tests/test_live_slots as TestLvdLiveSlots,
  ../games/light_vs_dark/tests/test_match_clock as TestLvdLocalNotices,
  ../games/cac/tests/test_network as TestCacNetwork,
  ../games/cac/tests/test_network_catchup as TestCacCatchup

import test_ordered_replays

echo "CI tests passed"
