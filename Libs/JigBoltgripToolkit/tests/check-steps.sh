#!/usr/bin/env bash
# What the library's scripts/check and the modules' shared check both start from: the client's Lua, the step
# runner and the file-mode step. Sourced, never run.
# The step runner calls each check function by name, and the caller exits with `failed`.
# shellcheck disable=SC2329,SC2034
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

# One line per step with its seconds; a failed step shows its output; `failed` is the script's exit.
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
