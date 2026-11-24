# Recipe Vacuum

A WoW Forever addon. It lists the recipes a character hasn't learned inside Blizzard's own profession window and shows where each one comes from: trainer, vendor, quest or drop. First module of Jig Boltgrip's Toolkit.

Client: WoW Forever 1.60.1 (build 71037, Interface 16001), the modern client with Forever's `Camelot` overrides. Blizzard's UI source for this client: [Gethe/wow-ui-source, `forever` branch](https://github.com/Gethe/wow-ui-source/tree/forever).

## Rules

- Build on Blizzard's frames and look: its templates, atlases, fonts, colors, global strings, enums and APIs. Copy a Blizzard value only when no API exposes it, and mark the copy with the file it came from.
- Use patterns established addons use, and say which one in a short comment. Nothing custom without a real need.
- Keep it simple and in one place (DRY). Data lives in tables, not in branches.
- Fast: no per-row or per-rebuild work that can be cached. Non-recipe loot costs one item-class check.
- Quiet: no chat output except the one "new recipe sources" line, which players can turn off.
- No named magic numbers inline: name them at the top of the file.
- Sit nicely with other addons: hooks run after Blizzard's code (`hooksecurefunc`, `Menu.ModifyMenu`), state on Blizzard frames goes in weak side tables, and the only globals are the saved variables, slash commands and one named frame (see `.luacheckrc`).
- Comments say why, briefly. Decision history goes in `HANDOFF.md`, not in code.

## Layout

| File | What it does |
|---|---|
| `Core.lua` | Saved data, schema number, ordered migrations |
| `Data/Included.lua` | Reviewed finds shipped with the addon (empty for now) |
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

## Checks

Run before every commit:

```sh
for f in $(git ls-files '*.lua' | grep -v '^Libs/A\|^Libs/C\|^Libs/L'); do luac -p "$f" || exit 1; done
luacheck .
luajit tests/upgrade.lua . <a schema 1 save>
luajit tests/simulate.lua . <a current save>
luajit tests/scroll.lua <wow-ui-source Interface/AddOns> Unlearned.lua
```

`luacheck` comes from LuaRocks, `luajit` from Homebrew; both match the client's Lua 5.1. The simulations need a real saved-variables file (`WTF/Account/<account>/SavedVariables/RecipeVacuum.lua`), which stays out of the repository.

In game, `/recipevacuum help` lists every command. `/recipevacuum watch on` logs loot and quest sources, and the log is written with the saved variables on `/reload` or logout.

## Where things are recorded

- `HANDOFF.md`: status, owner decisions with their wording, measurements from the game, open questions, and an inventory of everything custom or copied from Blizzard.
- `README.md`: what players and contributors read.
- Release packaging: `.pkgmeta` (BigWigs packager). Repository-only files are excluded from the addon zip there.
