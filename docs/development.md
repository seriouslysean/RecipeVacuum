# Development

## Setup

Link the repository into the Forever client, then `/reload` after each change:

```sh
ln -s "$PWD" "/Applications/World of Warcraft/_forever_/Interface/AddOns/RecipeVacuum"
```

`luacheck` and `busted` come from LuaRocks (`luarocks --lua-version 5.1 install busted`, the community's test runner, as other addons use) and `luajit` from Homebrew; all match the client's Lua 5.1.

## Checks

One script runs every check; the pre-push hook and CI run it too. Turn the hook on once per clone with `git config core.hooksPath .githooks`.

```sh
scripts/check [an old save] [a current save]
```

The steps are the toolkit's shared module check (`Libs/JigBoltgripToolkit/tests/module-check.sh`), one line each with its seconds: Lua 5.1 syntax (through LuaJIT; the `luac` on a current machine is a newer Lua and accepts syntax the client rejects), ShellCheck and shfmt on `scripts/check`, `luacheck`, the toolkit's conformance check, that every file still compiles with the `--@debug@` blocks removed, then the specs (`busted`, `tests/*_spec.lua`, set up by `.busted`) on the source and on the stripped release build. A failed step shows its output, and any failure fails the run.

- The script passes its inputs to the specs as `RV_OLD_SAVE` and `RV_SAVE`; one spec alone runs with them set, for example `RV_SAVE=tests/fixtures/current.lua busted tests/simulate_spec.lua`.
- The upgrade and simulation specs run on the made-up saved files in `tests/fixtures` (schema 2 and the current schema). A real saved-variables file (`WTF/Account/<account>/SavedVariables/RecipeVacuum.lua`) can be given instead, to try the code on real data; real saves stay out of the repository.
- CI (`.github/workflows/ci.yml`) runs the same script through the toolkit's shared workflow on every pull request and push to `main`.
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
| AceLocale-3.0 | MINOR 6 | Ace3 commit 075bafb (master; newer than the last release tag, r981, and what other addons such as Scrap ship, so it is the copy that runs) |
| JigBoltgripToolkit-1.0 | MINOR 43 | the toolkit repository; change it there, raise MINOR, copy the file and its `tests/stubs.lua` and `tests/conformance.lua` |

The Ace3 copies came from a repository checkout, not a tagged release, and that revision was not recorded; record the release tag at the next update. At run time LibStub uses the highest version of each library among all installed addons, so another addon's newer copy can be the one that runs.

## Working build

Code between `--@debug@` and `--@end-debug@` exists in a checkout and is stripped from released builds by the BigWigs packager, as other addons use the same markers. A checkout build:

- has the development commands `perf`, `scan` and `sharetest` (a one-account check of sharing: every reply is built, decoded, merged into a scratch copy and whispered to the same character);
- times its own work all session (unlearned-recipe builds, loot, vendor, trainer and quest reads, tooltips, linking) and writes the table to the saved log at logout or `/reload`, as `PERF` lines in `RecipeVacuumDB.devLog`;
- turns on the game's Lua error display (`scriptErrors`) at load and leaves it on;
- uses a scan from the current game build ahead of the seed.

A file must still compile with the marked blocks removed.

## Development commands

In a checkout build only; releases have none of these (owner, 2026-11-25: "Watch should stay a command and only be for debug builds"). `/recipevacuum help` lists them. Watch and log are the toolkit's, shared by every Boltgrip addon (owner, 2026-11-25: "Go, kit commands only"): The log is on from the start in a working build (owner, 2026-11-25: "don't I want an always on debug mode while testing?"): it records where loot, quest rewards, vendor stock and trainer lists come from, and every sharing step (lines starting `SHARE`: probes sent and heard, finds asked for, batches sent and received with row counts, merged or rejected), with one chat line when recipes are involved. `/boltgrip watch off` pauses it and is remembered; `/boltgrip watch on` resumes. `/boltgrip log` shows each addon's current run in a window to copy from; `/boltgrip log all` shows the last 20,000 lines of each; `/boltgrip log clear` empties them. The log is written with the saved variables on `/reload` or logout.

## Seeding

`Data/Seed.lua` comes from the game, not from us. For each new game build, before a release:

1. In game on a checkout build, open any profession, run `/recipevacuum scan`, then `/reload`. This reads which recipe each recipe item teaches (`taught`).
2. `luajit tools/seed.lua <WTF/Account/<account>/SavedVariables/RecipeVacuum.lua> Data/Seed.lua`. The script also fetches Blizzard's `ItemSparse` table for the seed's build from wago.tools (needs the network) and writes `learnSkill[recipeID]`, the lowest `RequiredSkillRank` of the recipe items that teach it. A saved file without a scan keeps `taught` and still refreshes `learnSkill`.
3. The script adds new pairs by itself. If a read would remove a pair or change one, it writes nothing and lists the differences; check them in game, then run it again with `--accept`.
4. Commit the file with the release.

A scan cut short loses pairs; the seed header's counts show how many items gave no answer.

The generated header in `Data/Seed.lua` is three lines: the generator, the taught note and the learnSkill note. `learnSkill[recipeID] = rank` is what each recipe's items ask for (docs/data.md, "Required skill"). The table is `taught[recipe itemID] = recipeID`: which recipe each recipe item teaches, as each recipe item's tooltip names it (read by `ns.GetTaughtRecipe` in `Sources.lua`). It is the game's data: nothing in the file comes from players and nothing in it is copied into saved variables. The table only grows unasked.

The file holds IDs only. Names are left out on purpose: they differ by language and change between builds.

## Translations

Every string a player reads is looked up in `Locales/enUS.lua` (AceLocale-3.0; the key is the English text), so the addon can be translated without touching code (owner, 2026-11-25: "English as the default. Let's only ship English to start though, but I want the strings pulled out for localization"). v0.1.0 ships English only. A language is one more file in `Locales/`, listed in the TOC after `enUS.lua`; translations will be made with Opus against Blizzard's own translated game terms. Working-build lines (watch, log, scan, perf) stay English in the code. Known gap: the drop evidence line joins three counted phrases, so a language with other word order cannot reorder them.

## Known gaps

Recorded from the Astra review of 2026-11-25 (RecipeVacuum a763a62..434c27a); none is fixed until what would make it real happens.

| Gap | Who can reach it today | What would make it worth fixing |
|---|---|---|
| AceComm buffers a multipart message before Recipe Vacuum checks the sender or its size; the 64 KiB expanded limit is checked after decompression | Any player who can send addon messages to our prefixes | A measured memory or frame cost from it, or a report |
| Options card rows on Blizzard's pooled settings list may leave hidden buttons when switching between toolkit pages | Switching between two toolkit addons' pages many times | A measured growth in game |
| Kit calls from versions between MINOR 19 and 29 are not kept | No one: those versions were never released | Not applicable; from the first release the kit keeps every call under `-1.0` (toolkit standards) |
| The "blocked from an action" popup when learning a recipe from the bags (`cairn:h57tf`) | Seen once | It happening again: the log then names the function |
| Ranks are not shared with friends | Everyone | A decision to share them (older versions skip a new row kind, so adding one is safe) |

## Release

Packaging is `.pkgmeta` (BigWigs packager). Repository-only files and folders are excluded from the addon zip there.
