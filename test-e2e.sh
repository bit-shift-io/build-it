#!/bin/sh
# Runs the e2e tier: launches one real LÖVE 12 process per tests/e2e/*_test.lua
# file and aggregates each file's outcome into one summary and exit status.
# Always the pinned LÖVE 12 build, never `love` on PATH (that is 11.5); see
# docs/memory/love-12-pinned-build.md.
#
# Flags forwarded to LÖVE as launch arguments:
#   --paced              pace playback to real time (one simulated frame per drawn frame)
#   --filmstrip[=N]       capture every Nth simulated frame (default interval 10)

LOVE_BIN="/Applications/love12.app/Contents/MacOS/love"

# LÖVE needs the folder holding main.lua; anchor to it so the tier runs from any cwd.
cd "$(dirname "$0")" || exit 1

if [ ! -x "$LOVE_BIN" ]; then
	echo "error: LÖVE 12 not found at $LOVE_BIN."
	echo "Install the pinned build (docs/memory/love-12-pinned-build.md) to run the e2e tier."
	exit 1
fi

love_args=""
for a in "$@"; do
	case "$a" in
		--paced)
			love_args="$love_args e2e-paced"
			;;
		--filmstrip)
			love_args="$love_args e2e-filmstrip"
			;;
		--filmstrip=*)
			interval="${a#--filmstrip=}"
			love_args="$love_args e2e-filmstrip e2e-filmstrip-interval=$interval"
			;;
		*)
			# assume a specific test file path
			love_args="$love_args $a"
			;;
	esac
done

E2E_DIR="tests/e2e"
files=$(ls "$E2E_DIR"/*_test.lua 2>/dev/null)

if [ -z "$files" ]; then
	echo "no e2e test files found under $E2E_DIR"
	exit 0
fi

overall_status=0
passed_files=0
failed_files=0
cancelled_files=0

for f in $files; do
	echo "== $f =="
	"$LOVE_BIN" "$PWD" "e2e=$f" $love_args
	status=$?

	if [ $status -eq 0 ]; then
		passed_files=$((passed_files + 1))
	elif [ $status -eq 2 ]; then
		echo "== $f: CANCELLED =="
		cancelled_files=$((cancelled_files + 1))
	else
		echo "== $f: FAILED =="
		failed_files=$((failed_files + 1))
		overall_status=1
	fi
	echo
done

echo "e2e summary: ${passed_files} file(s) passed, ${failed_files} file(s) failed, ${cancelled_files} file(s) cancelled"

exit $overall_status
