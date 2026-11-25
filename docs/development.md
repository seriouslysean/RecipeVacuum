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
- turns on the game's Lua error display (`scriptErrors`) at load and leaves it on;
- uses a scan from the current game build ahead of the seed;
- reads what each recipe makes whenever a profession list opens, once per profession per game build, into `RecipeVacuumDB.devMade`, with nothing to run.

A file must still compile with the marked blocks removed.

## Development commands

In a checkout build only; releases have none of these (owner, 2026-11-25: "Watch should stay a command and only be for debug builds"). `/recipevacuum help` lists them. Watch and log are the toolkit's, shared by every Boltgrip addon (owner, 2026-11-25: "Go, kit commands only"): The log is on from the start in a working build (owner, 2026-11-25: "don't I want an always on debug mode while testing?"): it records where loot, quest rewards, vendor stock and trainer lists come from, and every sharing step (lines starting `SHARE`: probes sent and heard, finds asked for, batches sent and received with row counts, merged or rejected), with one chat line when recipes are involved. `/boltgrip watch off` pauses it and is remembered; `/boltgrip watch on` resumes. `/boltgrip log` shows each addon's current run in a window to copy from; `/boltgrip log all` shows the last 2,000 lines of each; `/boltgrip log clear` empties them. The log is written with the saved variables on `/reload` or logout.

## Seeding

`Data/Seed.lua` comes from the game, not from us. For each new game build, before a release:

1. In game on a checkout build, open any profession, run `/recipevacuum scan`, then `/reload`. This reads which recipe each recipe item teaches (`taught`).
2. Open every profession on characters that have them; the checkout build reads what each recipe makes (`made`) once per game build, then `/reload`. The made table grows across runs, since a character reads only its own professions; the seed's header lists the skill lines read so far.
3. `luajit tools/seed.lua <WTF/Account/<account>/SavedVariables/RecipeVacuum.lua> Data/Seed.lua`
4. The script adds new pairs by itself. If a read would remove a pair or change one, it writes nothing and lists the differences; check them in game, then run it again with `--accept`.
5. Commit the file with the release.

A scan cut short loses pairs: one scan answered for 630 of 2,974 items (2026-11-23).

The file holds IDs only. Names are left out on purpose: they differ by language and change between builds.

## Release

Packaging is `.pkgmeta` (BigWigs packager). Repository-only files and folders are excluded from the addon zip there.
