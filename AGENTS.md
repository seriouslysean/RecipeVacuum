# Recipe Vacuum

A WoW Forever addon. It lists the recipes a character hasn't learned inside Blizzard's own profession window and shows where each one comes from: trainer, vendor, quest or drop. First module of Jig Boltgrip's Toolkit.

Client: WoW Forever 1.60.1 (build 71037, Interface 16001), the modern client with Forever's `Camelot` overrides. Blizzard's UI source for this client: [Gethe/wow-ui-source, `forever` branch](https://github.com/Gethe/wow-ui-source/tree/forever).

## Rules

The standards shared by every toolkit addon are in the library repository: [docs/standards.md](https://github.com/seriouslysean/JigBoltgripToolkit/blob/main/docs/standards.md). The rules below are the short form.

- Build on Blizzard's frames and look: its templates, atlases, fonts, colors, global strings, enums and APIs. Copy a Blizzard value only when no API exposes it, and mark the copy with the file it came from.
- Use patterns established addons use, and say which one in a short comment. Nothing custom without a real need.
- Keep it simple and in one place (DRY). Data lives in tables, not in branches.
- Fast: no per-row or per-rebuild work that can be cached. Non-recipe loot costs one item-class check.
- Quiet: no chat output except the one line after a visit with new recipe sources, which players can turn off.
- No named magic numbers inline: name them at the top of the file.
- Works in every client language: identify things by ID, never by matching English text. Names are for display only. Where the game gives no ID, say so in a comment and list it under known gaps.
- Sit nicely with other addons: hooks run after Blizzard's code (`hooksecurefunc`, `Menu.ModifyMenu`), state on Blizzard frames goes in weak side tables, and the only globals are the saved variables, slash commands and one named frame (see `.luacheckrc`).
- Comments say why, in a line or two. Explanations, measurements and history go in `docs/`, and the comment points there.

## Layout

| File | What it does |
|---|---|
| `Core.lua` | Saved data, schema number, ordered migrations |
| `Data/Seed.lua` | Seed data read from the game client; generated, never edited by hand |
| `Data/Included.lua` | Reviewed finds shipped with the addon (empty for now) |
| `tools/seed.lua` | Generates `Data/Seed.lua` from a scan (repository only) |
| `Voice.lua` | Every chat line the addon says, with the voice rules |
| `Sources.lua` | Source types, lookups across data layers, tooltips, row marks |
| `Record.lua` | Records trainers, vendors, loot and quest rewards |
| `Finds.lua` | Revisions, wire rows, validation, merge, export |
| `Sharing.lua` | Automatic sharing with guild, group and friends (AceComm) |
| `Unlearned.lua` | Adds unlearned recipes to Blizzard's recipe list |
| `RecipeList.lua` | Source marks on list rows |
| `RecipePanel.lua` | Source line and Show on Map for a selected unlearned recipe |
| `Filter.lua` | The Recipe Vacuum section of Blizzard's filter menu |
| `Settings.lua` | Options page and player commands |
| `Troubleshooting.lua` | Troubleshooting commands and their log |
| `Libs/JigBoltgripToolkit` | Shared toolkit page, commands, help and copy window |

## Docs

Reference material lives in `docs/`; code comments stay short and point there.

| Doc | Holds |
|---|---|
| [docs/data.md](docs/data.md) | Data layers, the saved layout, recipe item links, sharing, schema history |
| [docs/client-notes.md](docs/client-notes.md) | What the Forever client does where the addon depends on it, as measured |
| [docs/voice.md](docs/voice.md) | The chat voice: rules, sources, delivery |
| [docs/development.md](docs/development.md) | Setup, checks, the working build, troubleshooting commands, seeding, release |

Run the checks in `docs/development.md` before every commit.
