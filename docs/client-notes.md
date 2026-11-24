# Client notes

What WoW Forever's client does, where the addon depends on it. Measured in game on build 1.60.1.71037 unless a file is named. Blizzard's UI source for this client: [Gethe/wow-ui-source, `forever` branch](https://github.com/Gethe/wow-ui-source/tree/forever).

## Profession window

- The client leaves unlearned recipes out of `C_TradeSkillUI.GetFilteredRecipeIDs()` even with Show Unlearned on, so the addon adds them after Blizzard builds the list.
- The list's group number for learned recipes is 2 (the local `Group` enum in `Blizzard_Professions.lua`).
- The recipe list keeps a pixel scroll offset. Detaching the data provider scrolls to the top, so the offset is saved before a rebuild and reapplied after.
- `ValidateControls` runs on every bag and skill update while the window is open.
- Blizzard's source line (`RecipeSourceButton`) is never filled on this client, because `C_TradeSkillUI.GetRecipeSourceText` returns nothing. Its layout values in `ProfessionsRecipeSchematicFormMixin:Init`: 10 below the description, reagents 50 below while it shows.
- `AllocateBestQualityCheckbox` is anchored at the form's bottom left (x 30); Forever moves Track Recipe to the bottom right.
- The client carries recipe categories nobody can be shown to have learned or found, such as fifteen Alchemy recipes under "Season of Discovery".

## Recipe items

- `C_Item.GetItemSpell` on a recipe item returns a generic "Learning" spell (402265), not the recipe.
- The item's tooltip data has an `ItemSpellTriggerLearn` line ("Use: Teaches you how to...") whose `spellID` is the recipe. Every loaded recipe item of every profession carries it, except items named Deprecated. The tooltip is only complete once the item's data is cached.
- Walking item IDs with `C_Item.GetItemInfoInstant` reads the client's own data and asks the server nothing: 342,000 IDs, 31,013 items, 2,974 of the Recipe class, in about 150 ms of work. Of those, 2,478 name a recipe, 253 teach nothing and 243 never answer a data request.

## Requirements

- The other faction's version of a recipe is marked only in the recipe's tooltip data: a `UsageRequirement` line of the `Faction` type.
- A specialization ("Requires Goblin Engineer") is a requirement of the item the recipe makes, not of the recipe. The recipe's tooltip shows it only once that item has loaded.
- That requirement line carries no ID for the specialization. Its fields on build 71037 (item 18984, Dimensional Ripper - Everlook): `leftText`, `requirementType` (Skill), `type` (UsageRequirement), `usable` (`false` when unmet).
- Whether a specialization has been picked is inferred, with no list of specializations: it is picked when the character meets a specialization requirement on any made item of the profession. Before that every such line is unmet and nothing locks. Not yet measured on build 71037: that a specialized character's own lines come back met (white), and which event fires on picking one; a lock can be stale after picking until the next skill change or reload.
- A skill requirement with a rank ("Requires Engineering (300)", `ITEM_MIN_SKILL`) has a number in it; one without ("Requires Goblin Engineer", `ITEM_REQ_SKILL`) does not.
- A requirement the character meets is drawn white (`ffffffff`), one it does not is red (`ffff2020`). That red is not `RED_FONT_COLOR`.

## Trainers

- Trainers list recipes up to their own rank.
- `IsTradeskillTrainer()` is false for some NPCs that teach recipes (Westfall's Odd Child, six Alchemy recipes).
- `C_TradeSkillUI.GetTradeSkillLineForRecipe(spellID)` returns a profession line for recipes and for rank spells, and nothing for class spells. `C_TradeSkillUI.GetRecipeInfo` is non-nil for rank spells too.
- `GetTrainerServiceInfo` returns a category as its sixth value. Recipes have one ("Elixirs", "Camping"); ranks ("Journeyman Herbalism") have none. Blizzard's trainer window groups by the same value. `GetTrainerServiceStepIndex` marks only the next rank.
- The service list can arrive a moment after `TRAINER_SHOW`, and the window's filter hides known recipes.

## Loot, quests and vendors

- `GetLootSourceInfo(slot)` works. Field 6 of a Creature or GameObject GUID is its ID.
- Fishing: `IsFishingLoot()` is true and the source is the bobber object, so fishing finds are kept by zone.
- A container opened from bags reports an Item GUID; `C_Item.GetItemIDByGUID` gives its item ID.
- `LOOT_READY` can fire twice before `LOOT_OPENED`.
- A group roll (`START_LOOT_ROLL`) names the item but not what dropped it. Its loot handle is resolved by no documented function, and Blizzard's roll window shows no source either.
- Quest giver: `UnitGUID("questnpc")`. `GetQuestItemInfo` returns the item ID as its sixth value, before the name loads.
- A merchant row's details can arrive after the window opens.
- `UnitFactionGroup("npc")` reports "Alliance" for Alliance trainers and vendors. Neutral NPCs are not measured yet.

## Chat and names

- Forever writes player names in brackets ("[Name] says:") and has surnames; the full name with a space is a valid whisper target.
- The game's chat colors are in `ChatTypeInfo` and follow the player's settings.
- Whispers do not reach a Battle.net friend's character on another realm.
- Forever tags its own loot lines "[Loot]:" (`LOOT_ROLL_ALL_PASSED`).

## Timing

Recorded by the working build on low-level characters:

| Piece | Time |
|---|---|
| Profession window, show to ready | 9 to 14 ms |
| List build, first after a reload, before tooltip facts were kept | 34 ms (Tailoring, 417 unlearned), 42 ms (Blacksmithing, 501), 56 ms (Leatherworking, 585) |
| of which reading recipes and their tooltips | about two thirds |
| List build, later | 4 to 8 ms |
| Marks on one row | under 0.01 ms |
| Trainer read | 3 ms average; vendor read 0.06 ms |
