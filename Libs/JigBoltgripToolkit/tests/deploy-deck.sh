#!/usr/bin/env bash
# Copies a module's working build to the Steam Deck for in-game testing, shared so every module copies and labels
# builds the same way. A module's scripts/deploy-deck runs it from the module's root:
#   exec Libs/JigBoltgripToolkit/tests/deploy-deck.sh "$@"
# It runs the module's checks first, copies only what the game loads, and stamps the copied TOC's version (below): the
# corner line shows its first word, the session log all of it (docs/standards.md, "Working build"). The release
# packager fills the version from the tag instead; the repository's TOC keeps its token.
#   scripts/deploy-deck [ssh-host]
set -euo pipefail

host=${1:-deck-host}
addons='/home/deck/.local/share/Steam/steamapps/compatdata/4077668031/pfx/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns'
name=$(basename "$PWD")
scripts/check
# The copy names its code by commit, so a log line traces to the code that ran: "a81c4ef@08", or "7bd31fa+@42" when it carries
# uncommitted work. That work is kept as a snapshot commit (parent HEAD, the working tree's files) under refs/deck/, so the
# hash always resolves to the code that ran; an identical tree reuses its snapshot. @SS is the copy's second.
full=$(git rev-parse HEAD)
mark=""
if [ -n "$(git status --porcelain)" ]; then
	index=$(mktemp)
	GIT_INDEX_FILE=$index git read-tree HEAD
	GIT_INDEX_FILE=$index git add -A
	tree=$(GIT_INDEX_FILE=$index git write-tree)
	rm -f "$index"
	full=$(git for-each-ref refs/deck --format='%(objectname) %(tree) %(parent)' | awk -v t="$tree" -v p="$(git rev-parse HEAD)" '$2 == t && $3 == p { print $1; exit }')
	if [ -z "$full" ]; then
		full=$(git commit-tree "$tree" -p HEAD -m "deck snapshot of uncommitted work")
		git update-ref "refs/deck/$full" "$full"
	fi
	mark="+"
fi
second=$(date +%S)
# Two copies in the same second would read alike: the second one gets tenths.
now=$(date +%Y%m%d%H%M%S)
marker="$(git rev-parse --git-dir)/deck-last"
last=$(cat "$marker" 2>/dev/null || true)
if [ "$last" = "$now" ]; then second="$second.$(python3 -c 'import time; print(int(time.time() * 10) % 10)')"; fi
echo "$now" >"$marker"
stamp="$(git rev-parse --short=7 "$full")$mark@$second $full $(date -u +%Y-%m-%dT%H:%M:%SZ)"
rsync -a --delete --exclude='.*' --exclude=AGENTS.md --exclude=CLAUDE.md --exclude=HANDOFF.md --exclude=docs \
	--exclude=tests --exclude=tools --exclude=scripts --exclude=research_notes --exclude=reports \
	--exclude='Libs/JigBoltgripToolkit/tests' -e "ssh -o BatchMode=yes -o ConnectTimeout=8" ./ "$host:$addons/$name/"
ssh -o BatchMode=yes "$host" "sed -i 's/^## Version: .*/## Version: $stamp/' \"$addons/$name/$name.toc\""
echo "deployed $name $stamp to $host"
