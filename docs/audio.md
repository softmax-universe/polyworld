# Game sounds

Gota uses a shared sound mixer with separate UI and effects
volumes. Slappy decodes OGG Vorbis recordings for native OpenAL and
the browser's Web Audio implementation, resuming playback after a
pointer or keyboard gesture. A missing output device disables playback
without preventing the game from running.

Native playback uses the system OpenAL framework on macOS, OpenAL on Linux,
and Slappy's `soft_oal.dll` beside the game executable on Windows. Linux
builds need the OpenAL development package, such as `libopenal-dev` on
Debian and Ubuntu. Both lockfiles pin the merged `master` revision from
[Slappy PR #27](https://github.com/treeform/slappy/pull/27), including reusable
voices, lifecycle and macOS replay fixes, PCM loading, and gain fades.

Only recordings referenced by `src/polyworld/soundassets.nim` belong in the
sibling `polyworld_art/sounds` checkout. Keep recordings in their original
pack directories. Each imported pack includes its original license and a
provenance record identifying the creator, source URL, original filenames,
hashes and any audio processing. Browser asset manifests include these
notices with the recordings. Full downloaded packs remain in
`~/Downloads/polyworld-cc0-audio`, outside both repositories.

The selection contains 42 mono OGG Vorbis files at 44.1 kHz, from
twelve sources, encoded at quality 6 and occupying 523 KiB. Source recordings
remain untouched in the download library. Per-file provenance records the
crop, normalization, edge fades and encoding used for the imported clips.
Gota's browser asset budget is 46 MiB, including the additional 10 MiB
allowed for audio.

`sounds.nim` owns cue selection, gain, distance attenuation, stereo pan and
burst limits. Variation selection uses a presentation-only counter, so it
never consumes simulation randomness. Gota observes rendered state
changes and emits audible events only for visible activity. Seeking and world
replacement reset the observations, and fast-forward suppresses battle
audio. Unit orders and menu actions are local UI feedback.

Enabled buttons play a quiet cloth whoosh when the pointer enters them.
Remaining over a button, dragging and disabled controls stay silent. Hover
feedback uses the UI volume, with a short cooldown for fast pointer movement.
Gota also plays selection feedback when changing draft portraits and a
confirmation when locking in a hero.

Gota plays distinct result fanfares once when a match resolves: a
2.4-second trumpet phrase for victory and a 6-second orchestral cue for
defeat. They use UI volume, with a moderate gain and normalized recordings.
Fixed teammates share the winning result; spectators hear the victory cue.
Draws retain neutral feedback. Loading or seeking a completed match stays
silent, and a new match resets the one-shot observation. Result events take
priority over combat and ordinary notifications in a crowded final frame.

The recordings come from Graciano Choc's CC0
[Trumpet Fanfare](https://opengameart.org/node/161646) and Robin Lamb's CC0
[Lose Game Short Music Clip](https://opengameart.org/content/lose-game-short-music-clip).
Each has its own source folder, license record and exact processing history.
The old door-close defeat effect remains only in the download archive;
the wooden chime still serves healing.

Gota announces dawn at 06:00 with a rooster and dusk at 18:00 with a
quiet, 2.8-second distant wolf howl, using the same clock as the HUD and
lighting. The dusk cue uses Sacha.Julien's CC0
[distant wolf recording](https://freesound.org/people/Sacha.Julien/sounds/753896/),
cropped with a gentle onset and ending and reduced to a -14 dBFS peak.
The former 10.2-second solitary howl remains only in the download archive.
These global notices
use the UI volume and are protected from combat burst limits. They play
once when normal playback crosses the boundary, never on initial load,
replay seeks or fast-forward catch-up. Gota's clock excludes preparation.
The source format and any trimming are recorded explicitly in each
recording's provenance. Unused recordings stay in the download library.

The mixer allocates 24 voices at startup: twenty for world effects, three
for ordinary UI feedback, and one protected result-fanfare voice so hovering
over buttons cannot cut off the ending. Recordings decode once, and cues
sharing a recording reuse one buffer. Slappy keeps the same OpenAL sources
until shutdown. In the browser,
Emscripten continues to use Web Audio's standard one-shot playback nodes;
the game keeps its preloaded recordings and Slappy voice objects.

Gota reserves audio snapshots before match playback and return fixed
event buffers. Playback, voice reuse, gain changes, and sound observation
are checked with `-d:nimAllocStats` for zero Nim allocations and frees after
initialization. Browser one-shot nodes, engine internals and audio-driver
allocations are outside these measurements; match setup,
replacement and teardown may allocate.

Playback never queues events while browser audio is suspended. The Music
preference is retained for settings-file compatibility. The game ships effects
rather than a soundtrack, so the sound panel exposes Main, FX and UI controls.

Run the focused checks from the Polyworld repository root:

```sh
nim check src/polyworld/sounds.nim
nim r -d:audioTest -d:nimAllocStats tests/test_sounds.nim
nim r -d:audioTest -d:nimAllocStats games/gods_of_the_arena/tests/test_audio.nim
nim r -d:nimAllocStats tests/manual_sound_allocations.nim
nim r tests/manual_sound_fanfares.nim
```

To audition a mix, run Gota normally, open Settings > Sound, and use
Test combat sound. Main, FX, UI and Mute apply immediately and persist.
