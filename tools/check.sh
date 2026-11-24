#!/bin/sh
# Every check, in one command. Run from the repository root before each commit; CI runs the same file.
#
#   tools/check.sh [ui-source] [schema-1-save] [current-save]
#
# ui-source: a checkout of Gethe/wow-ui-source (branch forever); without it the scroll test is skipped.
# The two saves are real saved-variables files, which stay out of the repository; without them the
# upgrade and simulation tests are skipped. A skipped test is reported, never counted as passed.
set -eu

ours() { git ls-files '*.lua' | grep -v '^Libs/AceComm-3.0/\|^Libs/CallbackHandler-1.0/\|^Libs/LibStub/'; }

echo "== syntax (Lua 5.1, via LuaJIT)"
for file in $(ours); do luajit -bl "$file" > /dev/null; done

echo "== luacheck"
luacheck . -q

echo "== release build (debug blocks removed) still compiles"
stripped=$(mktemp -d)
trap 'rm -rf "$stripped"' EXIT
for file in $(ours); do
	mkdir -p "$stripped/$(dirname "$file")"
	awk '/--@debug@/{skip=1} !skip{print} /--@end-debug@/{skip=0}' "$file" > "$stripped/$file"
	luajit -bl "$stripped/$file" > /dev/null
done

skipped=0
if [ -n "${1:-}" ]; then
	echo "== scroll test"
	luajit tests/scroll.lua "$1/Interface/AddOns" Unlearned.lua
	echo "== scroll test, release build"
	(cd "$stripped" && luajit tests/scroll.lua "$1/Interface/AddOns" Unlearned.lua)
else
	echo "-- SKIPPED scroll test: no ui-source given"; skipped=1
fi
if [ -n "${2:-}" ]; then
	echo "== upgrade test"
	luajit tests/upgrade.lua . "$2"
else
	echo "-- SKIPPED upgrade test: no schema 1 save given"; skipped=1
fi
if [ -n "${3:-}" ]; then
	echo "== simulation"
	luajit tests/simulate.lua . "$3"
	echo "== simulation, release build"
	(cd "$stripped" && luajit tests/simulate.lua . "$3")
else
	echo "-- SKIPPED simulation: no current save given"; skipped=1
fi

[ "$skipped" -eq 0 ] && echo "ALL CHECKS RAN AND PASSED" || echo "PASSED, WITH SKIPS ABOVE"
