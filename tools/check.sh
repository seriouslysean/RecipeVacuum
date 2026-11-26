#!/bin/sh
# Every check, in one command. Run from the repository root before each commit; CI runs the same file.
#
#   tools/check.sh <ui-source> [old-save] [current-save]
#
# ui-source: a checkout of Gethe/wow-ui-source (branch forever), for the scroll spec.
# The saves default to the made-up files in tests/fixtures; a real saved-variables file can be given
# instead. Every spec runs: a missing input fails the run rather than skipping a spec. The specs read these
# inputs from RV_UI_SOURCE, RV_OLD_SAVE and RV_SAVE, which this script sets from its arguments.
set -eu

# Absolute paths: the release-build tests run from another directory.
absolute() { case "$1" in /*) echo "$1" ;; *) echo "$PWD/$1" ;; esac; }
[ -n "${1:-}" ] || { echo "usage: tools/check.sh <ui-source> [old-save] [current-save]" >&2; exit 2; }
ui=$(absolute "$1")
old_save=$(absolute "${2:-tests/fixtures/schema2.lua}")
new_save=$(absolute "${3:-tests/fixtures/current.lua}")

ours() { git ls-files '*.lua' | grep -v '^Libs/AceLocale-3.0/\|^Libs/AceComm-3.0/\|^Libs/CallbackHandler-1.0/\|^Libs/LibStub/'; }

echo "== syntax (Lua 5.1, via LuaJIT)"
for file in $(ours); do luajit -bl "$file" > /dev/null; done

echo "== luacheck"
luacheck . -q

echo "== toolkit conformance (the kit's shared rules, run on this addon's files)"
luajit Libs/JigBoltgripToolkit/tests/conformance.lua .

echo "== release build (debug blocks removed) still compiles"
stripped=$(mktemp -d)
trap 'rm -rf "$stripped"' EXIT
cp -R Libs "$stripped/" # third-party libraries as they are; the tests load them
for file in $(ours); do
	mkdir -p "$stripped/$(dirname "$file")"
	awk '/--@debug@/{skip=1} !skip{print} /--@end-debug@/{skip=0}' "$file" > "$stripped/$file"
	luajit -bl "$stripped/$file" > /dev/null
done

echo "== specs (busted: scroll, upgrade, simulation)"
export RV_UI_SOURCE="$ui" RV_OLD_SAVE="$old_save" RV_SAVE="$new_save"
busted
echo "== specs, release build (scroll, simulation)"
cp .busted "$stripped/"
(cd "$stripped" && busted tests/scroll_spec.lua tests/simulate_spec.lua)

echo "ALL CHECKS RAN AND PASSED"
