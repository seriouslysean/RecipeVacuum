# Development

## Setup

Link the repository into the Forever client, then `/reload` after each change:

```sh
ln -s "$PWD" "/Applications/World of Warcraft/_forever_/Interface/AddOns/RecipeVacuum"
```

`luacheck` comes from LuaRocks and `luajit` from Homebrew; both match the client's Lua 5.1.

## Checks

Run before every commit:

```sh
for f in $(git ls-files '*.lua' | grep -v '^Libs/A\|^Libs/C\|^Libs/L'); do luajit -bl "$f" > /dev/null || exit 1; done
luacheck .
luajit tests/upgrade.lua . <a schema 1 save>
luajit tests/simulate.lua . <a current save>
luajit tests/scroll.lua <wow-ui-source Interface/AddOns> Unlearned.lua
```

The simulations need a real saved-variables file (`WTF/Account/<account>/SavedVariables/RecipeVacuum.lua`), which stays out of the repository. `tests/scroll.lua` runs the addon's list code against Blizzard's real ScrollBox and tree data provider.

## Working build

Code between `--@debug@` and `--@end-debug@` exists in a checkout and is stripped from released builds by the BigWigs packager, as other addons use the same markers. A checkout build:

- has the development commands `perf` and `scan`;
- times its own work all session (list builds, row marks, loot, vendor, trainer and quest reads, tooltips, linking) and writes the table to the saved log at logout or `/reload`, as `PERF` lines in `RecipeVacuumDB.devLog`;
- uses a scan from the current game build ahead of the seed.

A file must still compile with the marked blocks removed.

## Troubleshooting commands

`/recipevacuum help` lists the commands. `watch on` logs where loot, quest rewards, vendor stock and trainer lists come from, to the log only, with one chat line when recipes are involved. `log` shows the current run in a window to copy from; `log all` shows the last 2,000 lines; `log clear` empties it. The log is written with the saved variables on `/reload` or logout.

## Seeding

`Data/Seed.lua` comes from the game, not from us. For each new game build, before a release:

1. In game on a checkout build, open any profession, run `/recipevacuum scan`, then `/reload`.
2. `luajit tools/seed.lua <WTF/Account/<account>/SavedVariables/RecipeVacuum.lua> Data/Seed.lua`
3. The script adds new pairs by itself. If the scan would remove a pair or change what an item teaches, it writes nothing and lists the differences; check them in game, then run it again with `--accept`.
4. Commit the file with the release.

The file holds IDs only. Names are left out on purpose: they differ by language and change between builds.

## Release

Packaging is `.pkgmeta` (BigWigs packager). Repository-only files and folders are excluded from the addon zip there.
