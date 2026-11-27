#!/usr/bin/env bash
# Copies a module's working build to the Steam Deck for in-game testing, shared so every module copies and labels
# builds the same way. A module's scripts/deploy-deck runs it from the module's root:
#   exec Libs/JigBoltgripToolkit/tests/deploy-deck.sh "$@"
# It runs the module's checks first, copies only what the game loads, and stamps the copied TOC's version with the
# copy's time and commit ("1126.1403 bf8fe64-dirty"): the module shows the time, the session log both (docs/standards.md,
# "Working build"). The release packager fills the version from the tag instead; the repository's TOC keeps its token.
#   scripts/deploy-deck [ssh-host]
set -euo pipefail

host=${1:-deck-host}
addons='/home/deck/.local/share/Steam/steamapps/compatdata/4077668031/pfx/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns'
name=$(basename "$PWD")
scripts/check
stamp="$(date +%m%d.%H%M) $(git describe --tags --always --dirty --abbrev=7)"
rsync -a --delete --exclude='.*' --exclude=AGENTS.md --exclude=CLAUDE.md --exclude=HANDOFF.md --exclude=docs \
	--exclude=tests --exclude=tools --exclude=scripts --exclude=research_notes --exclude=reports \
	--exclude='Libs/JigBoltgripToolkit/tests' -e "ssh -o BatchMode=yes -o ConnectTimeout=8" ./ "$host:$addons/$name/"
ssh -o BatchMode=yes "$host" "sed -i 's/^## Version: .*/## Version: $stamp/' \"$addons/$name/$name.toc\""
echo "deployed $name $stamp to $host"
