#!/usr/bin/env bash
# check-entitlements.sh — validate every *.entitlements against AMFI's parser.
#
# Why this exists: `plutil -lint` and the plist parser accept an XML comment
# that contains a double hyphen (`--`), but AMFI (the thing that actually reads
# entitlements at signing time) rejects it:
#
#     Failed to parse entitlements: AMFIUnserializeXML: syntax error near line N
#
# The failure is silent-ish: `codesign` exits non-zero and the binary keeps its
# previous (often linker-signed ad-hoc) signature — so a build can look signed
# but not be. This script probes each file through `codesign`, which uses the
# same AMFI path, and fails fast on the first bad file.
#
# Run:  bash scripts/check-entitlements.sh
set -euo pipefail

cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

shopt -s nullglob
files=(Packaging/*.entitlements)
if [ ${#files[@]} -eq 0 ]; then
  echo "no Packaging/*.entitlements found" >&2
  exit 1
fi

fail=0
for f in "${files[@]}"; do
  cp /bin/ls "$tmp/probe"
  if err="$(codesign --force --sign - --entitlements "$f" "$tmp/probe" 2>&1)"; then
    echo "OK   $f"
  else
    echo "FAIL $f"
    echo "     $err"
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo
  echo "One or more entitlements files are not AMFI-safe."
  echo "Most common cause: a double hyphen inside an XML comment." >&2
  exit 1
fi
echo "all entitlements parse through AMFI"
