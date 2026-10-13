#!/bin/sh
# Runs the game on the pinned LÖVE 12 build, never `love` on PATH (that is
# 11.5). See docs/memory/love-12-pinned-build.md.
LOVE_BIN="/Applications/love12.app/Contents/MacOS/love"

if [ ! -x "$LOVE_BIN" ]; then
	echo "error: LÖVE 12 not found at $LOVE_BIN (see docs/memory/love-12-pinned-build.md)."
	exit 1
fi

# LÖVE needs the folder holding main.lua, whatever the caller's cwd.
exec "$LOVE_BIN" "$(cd "$(dirname "$0")" && pwd)" "$@"
