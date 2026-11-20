#!/bin/sh
set -eu

voice_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$voice_dir/../.." && pwd)
dependency_dir=${POLYWORLD_DEPS:-"$repo_dir/.."}

if ! command -v emcc >/dev/null 2>&1; then
  echo 'Emscripten is required. Activate your emsdk or install emscripten.' >&2
  exit 1
fi

# Use the browser microphone PR when it is available beside Polyworld.
if [ -z "${SLAPPY_PATH:-}" ]; then
  for candidate in "$dependency_dir/slappy/src" \
    "$dependency_dir/slappy-wasm-microphone/src"; do
    if [ -f "$candidate/slappy/browsermicrophones.nim" ]; then
      SLAPPY_PATH=$candidate
      export SLAPPY_PATH
      break
    fi
  done
fi
if [ -z "${SLAPPY_PATH:-}" ] || \
  [ ! -f "$SLAPPY_PATH/slappy/browsermicrophones.nim" ]; then
  echo 'Slappy browser capture is required (treeform/slappy PR #29).' >&2
  echo 'Set SLAPPY_PATH to the src directory of that checkout.' >&2
  exit 1
fi

nim c --hints:off -d:emscripten "$@" "$voice_dir/voice.nim"
printf 'Built %s\n' "$voice_dir/emscripten/voice.html"
printf 'Run: nim r %s/serve.nim\n' "$voice_dir"
printf 'Open: http://localhost:8001/\n'
