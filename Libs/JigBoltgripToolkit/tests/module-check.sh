#!/usr/bin/env bash
# Every check a toolkit module runs, shared so the modules cannot drift apart. A module's scripts/check
# exports what its specs read, then runs this from the module's root:
#   exec Libs/JigBoltgripToolkit/tests/module-check.sh
# One line per step with its seconds; a failed step shows its output; the exit is nonzero if any failed.
# The step runner calls each check function by name.
# shellcheck disable=SC2329
set -uo pipefail
# luarocks --local installs luacheck and busted here, which a login shell does not put on PATH.
[[ -d $HOME/.luarocks/bin ]] && PATH="$HOME/.luarocks/bin:$PATH"

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

# The client runs Lua 5.1; LuaJIT reads 5.1, where a current luac accepts syntax the client rejects.
syntax() {
	local file
	for file in $(ours); do luajit -bl "$file" >/dev/null || return 1; done
}

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
		luajit -bl "$stripped/$file" >/dev/null || return 1
	done
}

shell() { shellcheck scripts/check && shfmt -d scripts/check; }
# A new module may have no specs yet; its line says so rather than passing quietly.
specs() {
	if compgen -G "tests/*_spec.lua" >/dev/null; then busted; else echo "no specs yet"; fi
}
release_specs() { (cd "$stripped" && specs); }

step "syntax (Lua 5.1)" syntax
step "shell (ShellCheck, shfmt)" shell
step "luacheck" luacheck . -q
step "conformance" luajit Libs/JigBoltgripToolkit/tests/conformance.lua .
step "release build compiles" release_build
step "specs" specs
step "specs, release build" release_specs

exit $failed
