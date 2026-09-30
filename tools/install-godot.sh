#!/usr/bin/env bash
# Installs the pinned Godot build to $1 (default /usr/local/bin/godot). The
# Dockerfile and CI both use this, so everything runs the engine the game is
# developed against. Bump the version and hash together; the hash is from
# https://github.com/godotengine/godot/releases/download/<version>-stable/SHA512-SUMS.txt
set -euo pipefail
GODOT_VERSION=4.7.2
GODOT_SHA512=9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65
dest=${1:-/usr/local/bin/godot}
name=Godot_v${GODOT_VERSION}-stable_linux.x86_64
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSLo "$tmp/godot.zip" "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/${name}.zip"
echo "$GODOT_SHA512  $tmp/godot.zip" | sha512sum -c --quiet -
unzip -q "$tmp/godot.zip" -d "$tmp"
install -m 755 "$tmp/$name" "$dest"
echo "installed Godot $GODOT_VERSION to $dest"
