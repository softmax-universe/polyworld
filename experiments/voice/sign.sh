#!/bin/sh
set -eu

# Keeps the app's privacy identity stable across local rebuilds.
if [ "$#" -ne 1 ]; then
  printf '%s\n' 'Usage: sign.sh /path/to/Application.app' >&2
  exit 1
fi

identity=${VOICE_SIGNING_IDENTITY:-}
if [ -z "$identity" ]; then
  available=$(/usr/bin/security find-identity -v -p codesigning)
  identities=$(printf '%s\n' "$available" | awk '
    $1 ~ /^[0-9]+\)$/ && length($2) == 40 &&
      $2 ~ /^[[:xdigit:]]+$/ && !seen[$2]++ { print $2 }
  ')
  count=$(printf '%s\n' "$identities" | awk 'NF { count++ } END { print count+0 }')
  case "$count" in
    0) identity=- ;;
    1) identity=$identities ;;
    *)
      printf '%s\n' \
        'Multiple signing identities are available. Set VOICE_SIGNING_IDENTITY to the certificate name or SHA-1 hash to use for each build.' >&2
      exit 1
      ;;
  esac
fi

if [ "$identity" = - ]; then
  printf '%s\n' \
    'Using ad-hoc signing; changed builds may ask for microphone permission again.' >&2
fi

exec /usr/bin/codesign --force --sign "$identity" --timestamp=none "$1"
