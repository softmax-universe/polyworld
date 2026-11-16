# Game sounds

Gota and Light vs Dark use a shared sound mixer with separate Music, UI and FX
volumes. Slappy decodes OGG Vorbis recordings for native OpenAL and
the browser's Web Audio implementation, resuming playback after a
pointer or keyboard gesture. A missing output device disables playback
without preventing the game from running.

Settings > Sound saves Master, Music, Sound effects and UI effects separately.
Native and browser launches restore these levels. New settings start at 100%.
Master at 0% silences every source; raising it restores the other channel levels.
Older saved mute-checkbox settings become Master 0% on load.

Explicit `--mute` or `--mute=true` launches show Master at 0% for that session.
`--unmute` or `--mute=false` uses the saved nonzero Master level, or 100% if it
was zero. The browser equivalents are `?mute=true` and `?mute=false`.
Without an explicit flag, saved levels always win. Changing Master saves the
new value and clears the launch override. Other settings changes preserve the
saved Master value. A pointer or keyboard gesture unlocks browser playback.

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

The effects selection contains 42 mono OGG Vorbis files at 44.1 kHz, from
twelve sources, encoded at quality 6 and occupying 523 KiB. Source recordings
remain untouched in the download library. Per-file provenance records the
crop, normalization, edge fades and encoding used for the imported clips.
Gota's browser asset budget is 46 MiB, including the additional 10 MiB
allowed for audio.

`sounds.nim` owns cue selection, gain, distance attenuation, stereo pan and
burst limits. Variation selection uses a presentation-only counter, so it
never consumes simulation randomness. Each game observes rendered state
changes and emits audible events only for visible activity. Seeking and world
replacement reset the observations, and fast-forward suppresses battle
audio. Unit orders and menu actions are local UI feedback.

Enabled buttons play a quiet cloth whoosh when the pointer enters them.
Remaining over a button, dragging and disabled controls stay silent. Hover
feedback uses the UI volume, with a short cooldown for fast pointer movement.
Gota also plays selection feedback when changing draft portraits and a
confirmation when locking in a hero.

Both games play distinct result fanfares once when a match resolves: a
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

Light vs Dark plays chopping and mining beats during active harvesting, and
wood or coin delivery cues when a worker deposits its load. Mining sounds
come from the source mine, with current-sight checks so neutral mine art does
not reveal unseen enemy workers. Routine work has a separate, quieter burst
limit that cannot consume the combat or construction sound budget.

A new construction site plays a soft placement thud. Its first actual work
progress plays one short hammer burst; continued work, replacement builders
and resuming an interrupted site never repeat that burst. If placement and
work begin together, only the hammer burst plays. These positional effects
use FX volume and fade with camera distance.

Both games announce dawn at 06:00 with a rooster and dusk at 18:00 with a
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

Both games reserve audio snapshots before match playback and return fixed
event buffers. Playback, voice reuse, gain changes, and sound observation
are checked with `-d:nimAllocStats` for zero Nim allocations and frees after
initialization. Browser one-shot nodes, engine internals and audio-driver
allocations are outside these measurements; match setup,
replacement and teardown may allocate.

Effects never queue events while browser audio is suspended. Light vs Dark
starts "Yearning of the Deep Woods" at application startup and loops it across
menus, matches, pauses and replay seeks. In the browser, playback begins after
the first pointer or keyboard gesture unlocks audio. One dedicated stereo source
keeps music separate from the effects pool and its burst limits. Music volume
changes apply immediately without restarting the song; Master also applies.
Master volume and mute are applied directly to every playback source, including
stereo music. Music, sound effects and UI gains stay independent. The Sound panel
provides separate combat and UI preview buttons that play alongside the track.
The listener stays at unity: [Apple's OpenAL implementation](https://github.com/apple-oss-distributions/OpenAL/blob/main/Source/OpenAL/oalContext.cpp#L804)
converts listener gain zero to negative infinity, which its mixer rejects.
Source gain zero uses an explicit silence path, avoiding audible music while
the application has blocked muted effects.

The soundtrack is `polyworld_art/music/yearning-of-the-deep-woods.ogg`.
The full 3:23 recording retains its stereo 48 kHz format, converted from WAV to
OGG Vorbis quality 4: 39,097,348 bytes became 2,786,804 bytes. The adjacent JSON
records source metadata, hashes and conversion details. LvD's asset declarations
include both files in normal and replay WASM bundles. The original WAV stays in
Downloads.

Run the focused checks from the Polyworld repository root:

```sh
nim check src/polyworld/sounds.nim
nim r -d:audioTest -d:nimAllocStats tests/test_sounds.nim
nim r -d:audioTest tests/test_sound_startup.nim
node tests/test_webinputs.js
node tests/test_replay_audio.js
nim r -d:audioTest -d:nimAllocStats games/gods_of_the_arena/tests/test_audio.nim
nim r -d:audioTest -d:nimAllocStats games/light_vs_dark/tests/test_battle_sounds.nim
nim r -d:nimAllocStats tests/manual_sound_allocations.nim
nim r tests/manual_sound_fanfares.nim
nim r tests/manual_music.nim
nim r tests/test_sound_mixing.nim
```

To audition a mix, run either game normally, open Settings > Sound, and use
Test combat sound or Test UI sound. Master, Music, Sound effects and UI effects
apply immediately and persist across launches. Set Master to 0% for silence.
The native music check uses a muted device without opening a window.
