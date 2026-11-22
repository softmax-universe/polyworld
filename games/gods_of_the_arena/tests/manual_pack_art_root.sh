#!/usr/bin/env bash
# Run with POLYWORLD_ART pointing to the pinned, LFS-populated art checkout.
set -euo pipefail
game=$(cd "$(dirname "$0")/.." && pwd)
art=$(cd "${POLYWORLD_ART:?set POLYWORLD_ART to the art checkout}" && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/run"
nim c --hints:off --nimcache:"$scratch/nimcache" -o:"$scratch/pack_assets" "$game/pack_assets.nim"
cd "$scratch/run" # No ../polyworld_art fallback here.
"$scratch/pack_assets" "$art" "$scratch/output"
for name in manifest.json cta.json; do
  cmp "$art/characters/chargen/$name" "$scratch/output/stage/characters/chargen/$name"
done
