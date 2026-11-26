{.warning[UnusedImport]: off.}

import
  std/tables,
  zippy/ziparchives,
  polyworld/policies,
  test_bars, test_cli, test_controllers, test_screenshots, test_shader_sources,
  test_backend_boundaries,
  test_render_descriptions, test_texture_uploads, test_shader_metadata,
  test_measurements,
  test_hashes,
  test_rngs, test_mailboxes,
  test_tapes, test_replaysaves, test_replaylibraries,
  test_rooms, test_roomclients, test_generic_relay, test_cosmetic_ready,
  test_room_codes, test_room_resize, test_sparse_rooms, test_opaque_setup,
  test_relay_async_hashes, test_relay_readiness, test_start_intent,
  test_client_loading_gap

echo "Testing bounded policy packages without game-specific fixtures"
block:
  doAssert loadPolicy("end\n").source == "end\n"
  var entries = {
    "nested/policy.bas": "end\n",
    "weights.bin": "binary\0data"
  }.toTable
  let policy = loadPolicy(createZipArchive(move(entries)))
  doAssert policy.source == "end\n"
  doAssert policy.files.len == 1
  doAssert policy.resource("weights.bin") == "binary\0data"
  for path in ["", "../escape", "/absolute", "a\\b", "C:relative",
      "a/./b", "a//b", "a\0b"]:
    var rejected = false
    try:
      discard resourcePath(path)
    except PolicyError:
      rejected = true
    doAssert rejected

echo "All Polyworld unit tests passed"
