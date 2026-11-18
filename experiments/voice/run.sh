#!/bin/sh
set -eu

# Builds and runs the experiment without changing engine configuration.
experimentDir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
buildDir="$experimentDir/build"
nimBin=${NIM:-nim}
buildOnly=false

if [ "${1:-}" = "--build-only" ]; then
  buildOnly=true
  shift
fi
if [ "${1:-}" = "--" ]; then
  shift
fi

if ! command -v "$nimBin" >/dev/null 2>&1; then
  printf '%s\n' 'Nim was not found. Put Nim on PATH or set NIM to its path.' >&2
  exit 1
fi

mkdir -p "$buildDir"
case "$(uname -s)" in
  Darwin)
    appDir="$buildDir/Voice Lab.app"
    executable="$appDir/Contents/MacOS/voice"
    mkdir -p "$appDir/Contents/MacOS" "$appDir/Contents/Resources/assets"
    cp "$experimentDir/assets/IBMPlexSans-Regular.ttf" \
      "$experimentDir/assets/OFL-IBMPlexSans.txt" \
      "$appDir/Contents/Resources/assets/"
    cp "$experimentDir/macos.plist" "$appDir/Contents/Info.plist"
    ;;
  *)
    executable="$buildDir/voice"
    mkdir -p "$buildDir/assets"
    cp "$experimentDir/assets/IBMPlexSans-Regular.ttf" \
      "$experimentDir/assets/OFL-IBMPlexSans.txt" "$buildDir/assets/"
    ;;
esac

temporaryExecutable="$executable.new.$$"
trap 'rm -f "$temporaryExecutable"' EXIT HUP INT TERM
"$nimBin" c --nimcache:"$buildDir/nimcache" --out:"$temporaryExecutable" \
  "$experimentDir/voice.nim"
mv -f "$temporaryExecutable" "$executable"

if [ "$(uname -s)" = Darwin ]; then
  /usr/bin/codesign --force --sign - "$appDir"
fi

if [ "$buildOnly" = true ]; then
  printf '%s\n' "$executable"
  exit 0
fi

# The executable launches through LaunchServices on macOS, preserving its env.
exec "$executable" "$@"
