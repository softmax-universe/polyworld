#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
web_dir="${CAC_WEB_DIR:-$project_dir/emscripten}"
nim_command="${NIM:-nim}"
# Homebrew's preinstalled Emscripten cache may be read-only.
export EM_CACHE="${EM_CACHE:-$project_dir/build/emscripten-cache}"
mkdir -p "$EM_CACHE"

for tool in "$nim_command" emcc; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing $tool. Install Nim and Emscripten, then put both on PATH." >&2
    exit 1
  fi
done

mkdir -p "$web_dir"
export CAC_WEB_DIR="$(cd -- "$web_dir" && pwd)"
"$nim_command" c -d:emscripten "$@" "$project_dir/cac.nim"
echo "Browser game built: $CAC_WEB_DIR/cac.html"
