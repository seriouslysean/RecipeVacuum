#!/bin/sh
# Every check, in one command. Run from the repository root before each commit; CI runs the same file.
#
#   tools/check.sh [ui-source] [schema-1-save] [current-save]
#
# ui-source: a checkout of Gethe/wow-ui-source (branch forever); without it the scroll test is skipped.
# The two saves are real saved-variables files, which stay out of the repository; without them the
# upgrade and simulation tests are skipped. A skipped test is reported, never counted as passed.
set -eu

# Absolute paths: the release-build tests run from another directory.
absolute() { case "$1" in /*) echo "$1" ;; "") echo "" ;; *) echo "$PWD/$1" ;; esac; }
ui=$(absolute "${1:-}"); old_save=$(absolute "${2:-}"); new_save=$(absolute "${3:-}")

ours() { git ls-files '*.lua' | grep -v '^Libs/AceComm-3.0/\|^Libs/CallbackHandler-1.0/\|^Libs/LibStub/'; }

echo "== syntax (Lua 5.1, via LuaJIT)"
for file in $(ours); do luajit -bl "$file" > /dev/null; done

echo "== luacheck"
luacheck . -q

echo "== release build (debug blocks removed) still compiles"
stripped=$(mktemp -d)
trap 'rm -rf "$stripped"' EXIT
cp -R Libs "$stripped/" # third-party libraries as they are; the tests load them
for file in $(ours); do
	mkdir -p "$stripped/$(dirname "$file")"
	awk '/--@debug@/{skip=1} !skip{print} /--@end-debug@/{skip=0}' "$file" > "$stripped/$file"
	luajit -bl "$stripped/$file" > /dev/null
done

skipped=0
if [ -n "$ui" ]; then
	echo "== scroll test"
	luajit tests/scroll.lua "$ui/Interface/AddOns" Unlearned.lua
	echo "== scroll test, release build"
	(cd "$stripped" && luajit tests/scroll.lua "$ui/Interface/AddOns" Unlearned.lua)
else
	echo "-- SKIPPED scroll test: no ui-source given"; skipped=1
fi
if [ -n "$old_save" ]; then
	echo "== upgrade test"
	luajit tests/upgrade.lua . "$old_save"
else
	echo "-- SKIPPED upgrade test: no schema 1 save given"; skipped=1
fi
if [ -n "$new_save" ]; then
	echo "== simulation"
	luajit tests/simulate.lua . "$new_save"
	echo "== simulation, release build"
	(cd "$stripped" && luajit tests/simulate.lua . "$new_save")
else
	echo "-- SKIPPED simulation: no current save given"; skipped=1
fi

[ "$skipped" -eq 0 ] && echo "ALL CHECKS RAN AND PASSED" || echo "PASSED, WITH SKIPS ABOVE"
