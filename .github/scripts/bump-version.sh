#!/usr/bin/env bash
# Works out the next release version from the vX.Y git tags and writes it into
# pubspec.yaml as X.Y.0+CODE, where CODE (the Android versionCode) is
# major * 10000 + minor, so every release installs over the previous one.
#
#   no vX.Y tag yet            -> release the version already in pubspec.yaml
#   pubspec.yaml ahead of tags -> release pubspec.yaml as is (manual jump, e.g. 2.0)
#   otherwise                  -> latest tag + 1 minor (or + 1 major with "major")
#
# Usage: bump-version.sh [minor|major]
# Prints "version=X.Y" and "code=N" lines, ready to append to $GITHUB_OUTPUT.
set -euo pipefail

bump="${1:-minor}"
pubspec="${PUBSPEC:-pubspec.yaml}"

by_version() { sort -t. -k1,1n -k2,2n; }

current=$(sed -nE 's/^version:[[:space:]]*([0-9]+)\.([0-9]+).*/\1.\2/p' "$pubspec")
if [ -z "$current" ]; then
  echo "No 'version: X.Y.Z' line found in $pubspec" >&2
  exit 1
fi

latest=$(git tag --list 'v*' | sed 's/^v//' | grep -E '^[0-9]+\.[0-9]+$' | by_version | tail -n 1 || true)

if [ -z "$latest" ] || { [ "$current" != "$latest" ] &&
     [ "$(printf '%s\n%s\n' "$current" "$latest" | by_version | tail -n 1)" = "$current" ]; }; then
  next="$current"
elif [ "$bump" = "major" ]; then
  next="$(( ${latest%%.*} + 1 )).0"
else
  next="${latest%%.*}.$(( ${latest#*.} + 1 ))"
fi

major="${next%%.*}"
minor="${next#*.}"
code=$(( major * 10000 + minor ))

if git rev-parse -q --verify "refs/tags/v$next" > /dev/null; then
  echo "Tag v$next already exists" >&2
  exit 1
fi

sed -i -E "s/^version:.*/version: $major.$minor.0+$code/" "$pubspec"

echo "version=$next"
echo "code=$code"
