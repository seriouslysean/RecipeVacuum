#!/usr/bin/env bash
# Every check a toolkit module runs, shared so the modules cannot drift apart. A module's scripts/check
# exports what its specs read, then runs this from the module's root:
#   exec Libs/JigBoltgripToolkit/tests/module-check.sh
# One line per step with its seconds; a failed step shows its output; the exit is nonzero if any failed.
# The step runner calls each check function by name.
# shellcheck disable=SC2329
set -uo pipefail
# The client's Lua is PUC Lua 5.1, and so is CI's; tools/setup-lua.sh builds it here with CI's busted and
# luacheck. LuaJIT differs where it matters (string.format takes nil for %s), so nothing else runs a check.
[[ -d $HOME/.local/share/lua51/bin ]] && PATH="$HOME/.local/share/lua51/bin:$PATH"
lua=$(command -v lua5.1 || command -v lua || true)
luac=$(command -v luac5.1 || command -v luac || true)
lua51() { [[ -n $lua && -n $luac ]] && "$lua" -e 'assert(_VERSION == "Lua 5.1" and not jit)' 2>/dev/null && [[ $("$luac" -v 2>&1) == "Lua 5.1"* ]]; }
if ! lua51; then
	echo "The checks need PUC Lua 5.1 (the client's): run tools/setup-lua.sh from the toolkit repository." >&2
	exit 1
fi

failed=0
step() {
	local name=$1 started output
	shift
	started=$SECONDS
	if output=$("$@" 2>&1); then
		[[ $output == "no specs yet" ]] && name="$name: none yet"
		printf 'ok   %s (%d s)\n' "$name" $((SECONDS - started))
	else
		printf 'FAIL %s (%d s)\n%s\n' "$name" $((SECONDS - started)) "$output"
		failed=1
	fi
}

# The module's own Lua and the kit's file; other embedded libraries are checked by their authors.
ours() {
	git ls-files '*.lua' | grep -v '^Libs/' || true
	echo Libs/JigBoltgripToolkit/JigBoltgripToolkit.lua
}

syntax() { ours | tr '\n' '\0' | xargs -0 "$luac" -p; }

# The release build: the addon as packaged, with --@debug@ blocks dropped, so every shipped file must
# still compile and the specs run against it. The TOC and its XML come as they are, since specs load the
# addon through the TOC; the specs themselves never ship, so they are copied unchanged.
stripped=$(mktemp -d)
trap 'rm -rf "$stripped"' EXIT
release_build() {
	local file
	cp -R Libs .busted "$stripped/" || return 1
	for file in $(git ls-files '*.toc' '*.xml' 'tests/*' | grep -v '^Libs/'); do
		mkdir -p "$stripped/$(dirname "$file")"
		cp "$file" "$stripped/$file" || return 1
	done
	for file in $(ours); do
		[[ $file == tests/* ]] && continue
		mkdir -p "$stripped/$(dirname "$file")"
		awk '/--@debug@/{skip=1} !skip{print} /--@end-debug@/{skip=0}' "$file" >"$stripped/$file"
		"$luac" -p "$stripped/$file" || return 1
	done
}

shell() { shellcheck scripts/check && shfmt -d scripts/check; }
# The client reads Bindings.xml by name, outside the TOC, so no other step parses it.
xml() {
	local files
	files=$(git ls-files '*.xml' | grep -v '^Libs/' || true)
	[[ -z $files ]] && return 0
	# shellcheck disable=SC2086 # one path per word
	xmllint --noout $files
}
# The execute bit is for scripts only: a clone's file modes can be rewritten from outside (the launcher does it through
# the AddOns symlink), and a commit would then carry them.
modes() {
	local mode path bad=0
	while read -r mode _ _ path; do
		[[ $mode == 100755 ]] || continue
		[[ $(head -c 2 "$path") == '#!' ]] && continue
		echo "$path is executable and not a script: git update-index --chmod=-x $path"
		bad=1
	done < <(git ls-files -s)
	return "$bad"
}
# A new module may have no specs yet; its line says so rather than passing quietly.
specs() {
	if compgen -G "tests/*_spec.lua" >/dev/null; then busted --lua="$lua"; else echo "no specs yet"; fi
}
release_specs() { (cd "$stripped" && specs); }

step "syntax (Lua 5.1)" syntax
step "shell (ShellCheck, shfmt)" shell
step "XML well-formed" xml
step "file modes" modes
step "luacheck" luacheck . -q
step "conformance" "$lua" Libs/JigBoltgripToolkit/tests/conformance.lua .
step "release build compiles" release_build
step "specs" specs
step "specs, release build" release_specs

exit $failed
