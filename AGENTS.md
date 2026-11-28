# Recipe Vacuum

A WoW Forever addon. It records where recipes come from (trainer, vendor, quest or drop) and works out which recipes a character hasn't learned. It writes nothing into Blizzard's profession window; the player-facing list is a panel of its own (docs/client-notes.md, "Gamepad"). First module of Jig Boltgrip's Toolkit.

Client: WoW Forever 1.60.1 (Interface 16001; measured on builds 71037 to 71139), the modern client with Forever's `Camelot` overrides. Blizzard's UI source for this client: [Gethe/wow-ui-source, `forever` branch](https://github.com/Gethe/wow-ui-source/tree/forever).

## Toolkit

A module of Jig Boltgrip's Toolkit. Every module follows the toolkit's shared [standards](https://github.com/seriouslysean/JigBoltgripToolkit/blob/main/docs/standards.md) and meets its [quality bar](https://github.com/seriouslysean/JigBoltgripToolkit/blob/main/docs/quality-bar.md) before a release; this file adds only what is specific to this module. `Libs/JigBoltgripToolkit` is the toolkit's own file: change it in the toolkit repository, never here.

- `scripts/check` runs everything CI runs. Turn on the pre-push hook once per clone with `git config core.hooksPath .githooks`, and never skip it.
- Mouse and keyboard and gamepad are both first-class: nothing releases until both are checked in game.
- Comments say why, never history; measurements go in `docs/`, decisions in the toolkit's [docs/decisions](https://github.com/seriouslysean/JigBoltgripToolkit/tree/main/docs/decisions).

## Rules

The short form of the shared standards, as they apply here.

- Build on Blizzard's frames and look: its templates, atlases, fonts, colors, global strings, enums and APIs. Copy a Blizzard value only when no API exposes it, and mark the copy with the file it came from.
- Use patterns established addons use, and say which one in a short comment. Nothing custom without a real need.
- Keep it simple and in one place (DRY). Data lives in tables, not in branches.
- Fast: no per-row or per-rebuild work that can be cached. Non-recipe loot costs one item-class check.
- Quiet: no chat output except the one line after a visit with new recipe sources and the one line when a window closes on recipes seen for the character's professions (both turned off by Show Chat Alerts), and the one line when a click sets a map pin.
- Never write into Blizzard's frames, lists, menus or panels, and open none of its windows except the world map, which Map Pin opens out of combat through the game's own `/mappin` in a secure button (kit decision 0068); while the map pushes the profession window out of the left slot the panel steps aside (kit decision 0077): it taints Blizzard's gamepad navigation and secure code (docs/client-notes.md, "Gamepad"). Reading Blizzard's state through post-hooks is fine.
- No named magic numbers inline: name them at the top of the file.
- Works in every client language: identify things by ID, never by matching English text. Names are for display only. Where the game gives no ID, say so in a comment and list it under known gaps.
- Sit nicely with other addons: hooks that read Blizzard's state run after its code (`hooksecurefunc`), and the only globals are the saved variables, slash commands and one named frame (see `.luacheckrc`).
- Comments say why, in a line or two. Explanations, measurements and history go in `docs/`, and the comment points there.

## Layout

| File | What it does |
|---|---|
| `Core.lua` | Saved data, schema number, ordered migrations |
| `Data/Seed.lua` | Seed data read from the game client; generated, never edited by hand |
| `Data/Included.lua` | Reviewed finds shipped with the addon (empty for now) |
| `tools/seed.lua` | Generates `Data/Seed.lua` from the item scan (repository only) |
| `Voice.lua` | Every chat line the addon says, with the voice rules |
| `Sources.lua` | Source types, lookups across data layers, tooltips, marks, linking recipe items |
| `Record.lua` | Records trainers, vendors, loot and quest rewards |
| `Heard.lua` | Recipes come across without a source: chat links, nearby loot, shown professions |
| `Finds.lua` | The row shape for the toolkit's share: wire rows, validation, merge, export |
| `Unlearned.lua` | Which recipes the character hasn't learned, by category (`ns.GetUnlearnedRecipes`), the panel's flat list in skill-up order (`ns.GetListedRecipes`) and rank bands (`ns.BandOf`); no UI |
| `Ranks.lua` | Profession ranks: sources from trainers, book use and quest turn-ins, and the mark right of the window's link button, our own Button that follows the crafting page by hooks |
| `RecipePanel.lua` | Map pins for sources (`ns.MapTargets`, `ns.ShowOnMap`) and the details' source rows (`ns.SourceRows`) |
| `Panel.lua` | The unlearned recipes panel beside the Professions window: follows its search and filters, groups by rank band under the game's rank spell names, shows a discovery bar and the selected recipe's details with a Map Pin button, hides when nothing found is left, builds rows a few a frame, rebuilds only when its content changes |
| `Settings.lua` | Options page and player commands |
| `Troubleshooting.lua` | Development commands and their log; checkout builds only |
| `Libs/JigBoltgripToolkit` | Shared toolkit page, commands, help, copy window and the sharing transport |

## Docs

Reference material lives in `docs/`; code comments stay short and point there.

| Doc | Holds |
|---|---|
| [docs/data.md](docs/data.md) | Data layers, the saved layout, recipe item links, sharing, schema history |
| [docs/client-notes.md](docs/client-notes.md) | What the Forever client does where the addon depends on it, as measured |
| [docs/voice.md](docs/voice.md) | The chat voice: rules, sources, delivery |
| [docs/development.md](docs/development.md) | Setup, checks, the working build, troubleshooting commands, seeding, release |
| [Toolkit docs/decisions/](https://github.com/seriouslysean/JigBoltgripToolkit/blob/main/docs/decisions/README.md) | Every choice, Recipe Vacuum's included, one file each with dates, cited reasons, versions and tests; add Recipe Vacuum's there |

Run `scripts/check` before every commit (docs/development.md, "Checks").
