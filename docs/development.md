# Development

## Setup

Link the repository into the Forever client, then `/reload` after each change:

```sh
ln -s "$PWD" "/Applications/World of Warcraft/_forever_/Interface/AddOns/RecipeVacuum"
```

`luacheck` comes from LuaRocks and `luajit` from Homebrew; both match the client's Lua 5.1.

## Checks

One script runs every check; run it before every commit:

```sh
tools/check.sh <wow-ui-source checkout> <a schema 1 save> <a current save>
```

It checks, in order: Lua 5.1 syntax (through LuaJIT; the `luac` on a current machine is a newer Lua and accepts syntax the client rejects), `luacheck`, that every file still compiles with the `--@debug@` blocks removed, then the scroll, upgrade and simulation tests, the scroll and simulation tests on the stripped build too. An argument left out skips its test and says so.

- The simulations need a real saved-variables file (`WTF/Account/<account>/SavedVariables/RecipeVacuum.lua`), which stays out of the repository.
- `tests/scroll.lua` runs the addon's list code against Blizzard's real ScrollBox and tree data provider, from a checkout of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source) at the commit `.github/workflows/ci.yml` pins.
- CI (`.github/workflows/ci.yml`) runs the same script on every push and pull request, without the two save-file tests.
- `luacheck` reports any global the code reads that is not listed in `.luacheckrc` (`read_globals`), so a misspelled API name fails the check. Add a name there when the code starts using a new one.
- `.editorconfig` sets indentation and line endings for every editor.

## Embedded libraries

Vendored copies under `Libs/`, loaded in TOC order; nothing is fetched at packaging time, so a release cannot pick up a different version by itself.

| Library | Version in the file | Upstream |
|---|---|---|
| LibStub | 2 | [Ace3](https://github.com/WoWUIDev/Ace3) |
| CallbackHandler-1.0 | MINOR 8 | Ace3 |
| ChatThrottleLib | 32 | Ace3 (with AceComm-3.0) |
| AceComm-3.0 | MINOR 14 | Ace3 |
| JigBoltgripToolkit-1.0 | MINOR 8 | the toolkit repository; change it there, raise MINOR, copy the file |

The Ace3 copies came from a repository checkout, not a tagged release, and that revision was not recorded; record the release tag at the next update. At run time LibStub uses the highest version of each library among all installed addons, so another addon's newer copy can be the one that runs.

## Working build

Code between `--@debug@` and `--@end-debug@` exists in a checkout and is stripped from released builds by the BigWigs packager, as other addons use the same markers. A checkout build:

- has the development commands `perf`, `scan` and `sharetest` (a one-account check of sharing: every reply is built, decoded, merged into a scratch copy and whispered to the same character);
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
