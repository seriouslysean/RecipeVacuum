# Client notes

What WoW Forever's client does, where the addon depends on it. Measured in game on build 1.60.1.71037 unless a file is named. Blizzard's UI source for this client: [Gethe/wow-ui-source, `forever` branch](https://github.com/Gethe/wow-ui-source/tree/forever).

## Gamepad

With the Gamepad UI (Steam Deck), Blizzard's own code refuses to run on anything an addon wrote, so Recipe Vacuum writes nothing into Blizzard's frames, lists, menus or panels and opens none of its windows (owner decision; the same rule for every input method, not a gamepad mode). Measured in game on WoW Forever:

- `SmartNavigation.lua` `EnsureIsSecure` stops when it reads anything addon code wrote. After rows were inserted into the profession recipe list, the d-pad stopped moving (stack: `Navigate`, `SelectButton`, `EnsureIsSecure`).
- `ADDON_ACTION_FORBIDDEN` named Recipe Vacuum for `SetPreferredGamepadInteractTarget`.
- Opening the character window from the gamepad radial failed with "attempt to compare a secret number value (execution tainted by 'RecipeVacuum')".
- `OpenWorldMap` from addon code taints (TrainerSpells, pull request 9), and so do `MenuUtil.CreateContextMenu` and `Menu.ModifyMenu` entries. A map pin is `C_Map.SetUserWaypoint` plus `C_SuperTrack.SetSuperTrackedUserWaypoint(true)`, with nothing opened.
- Other addons that show recipes for unlearned professions (SkillUp Forever, TrainerSpells, Macro Assist) keep their own frames beside Blizzard's.

What is no longer done: unlearned rows in the recipe list, source marks on rows, the source line, item row and Show Map button in the recipe pane, the Recipe Vacuum section of the filter menu, the first-run help tip, and any call that refreshes Blizzard's list. Unlearned recipes will live in Recipe Vacuum's own panel beside the window, fed by `ns.GetUnlearnedRecipes`.

## Panel

Prototype seen on the Steam Deck (owner, 2026-11-26): the d-pad reaches the panel, scrolls to the bottom, nothing is blocked. `Panel.lua` anchors to `ProfessionsFrame.ProfessionsOverviewTab` (top right, 60 px up to the window's top), the first of the profession tabs in the right-hand column (Camelot `Blizzard_ProfessionsFrame.xml`; all tabs share one x). About 230 px are free right of that column at 1280x800 before the quest tracker; the panel is 270 wide and may overlap the tracker a little. The list is `UIPanelScrollFrameTemplate` with one own Button per row, as Field Guide Forever's list (`UI/List.lua`); SmartNavigation only calls `SetVerticalScroll` on a plain scroll frame. Content margins are the inset template's own border atlas sizes (`NineSliceLayouts.lua`, `InsetFrameTemplate`).

What it follows, and why:

- Build cost. The prototype's first Deck run froze the profession window for about 6 s: 518 rows (every unlearned Blacksmithing recipe in the client, later expansions included) built three times in one second, because the crafting page's `Init` fires several times when the window opens, then again on a 1 s polling retry. Now every trigger only asks for a rebuild on the next frame (one build however many asks), rows are made in steps of at most 4 ms and 40 rows (`BUILD_BUDGET_MS`, `ROWS_PER_STEP`), the list is filtered before any row exists, and rows are kept across professions. The trace line "UI panel shown" and the `panel build` timing give the real cost. Expected, not yet measured on the Deck: under 100 rows, a few ms in total.
- Which recipes: the show rule in `docs/data.md` ("Show rule").
- Order and number: ascending `maxTrivialLevel`, then name. `TradeSkillRecipeInfo` (`TradeSkillUITypesDocumentation.lua`) has no field for the skill a recipe is learned at; the trivial level is the nearest threshold, so the number at the row's right is that, not the learn skill. Unverified: how closely it follows learn order.
- Color: `relativeDifficulty` through Blizzard's own table (`Blizzard_ProfessionsRecipeList.lua`, `DifficultyColors`: Optimal `DIFFICULT_DIFFICULTY_COLOR`, Medium `FAIR_`, Easy `EASY_`), trivial in `TRIVIAL_DIFFICULTY_COLOR`, and `DISABLED_FONT_COLOR` when the recipe is `disabled` or locked by a specialization. The client gives no "needs a higher skill to learn" field, so that case is not grey. Unverified: what `relativeDifficulty` is for an unlearned recipe far above the character's skill.
- Filters, read from `C_TradeSkillUI` as `Blizzard_Professions.lua` reads them (`GetCurrentFilterSet`): the search box text (folded with `CaseAccentInsensitiveParse`; `HookScript` on the recipe list's `SearchBox` `OnTextChanged`), `GetOnlyShowMakeableRecipes` (hides everything), `GetShowUnlearned` (off hides everything), `GetOnlyShowSkillUpRecipes` (`canSkillUp`), `GetOnlyShowFirstCraftRecipes` (`firstCraft`). Not applied: inventory slot, category and source filters, which have getters for the filter state but none that places a recipe in a slot or category. Refresh events: the page's `Init` (a filter change makes the client send `TRADE_SKILL_LIST_UPDATE`, which rebuilds the page), `TRADE_SKILL_LIST_UPDATE`, `TRADE_SKILL_DATA_SOURCE_CHANGED`, `NEW_RECIPE_LEARNED`, `SKILL_LINES_CHANGED`. One retry after 1 s when the client's names or factions were still loading.
- Tooltip: the game's own tooltip for the item the recipe makes (`GetRecipeSchematic`, `outputItemID`, `GameTooltip:SetItemByID`), or the recipe's spell when it makes none, so other addons' tooltip hooks (another addon) add their lines; our source lines follow. The row icon is `recipeInfo.icon`.
- Other windows: a post-hook on `UpdateUIPanelPositions` reads `GetUIPanel("center")`; the panel hides while another window holds it. Unverified on the Deck: whether Professions itself ever sits in the center slot (the code ignores that case).

To check on the Deck: d-pad reaches the panel and back, scrolls, no "Interface action failed" or `ADDON_ACTION_FORBIDDEN`, no stall when the window opens.

## Profession window

- The client leaves unlearned recipes out of `C_TradeSkillUI.GetFilteredRecipeIDs()` even with Show Unlearned on, so the addon works them out itself from `C_TradeSkillUI.GetAllRecipeIDs()`.
- Blizzard's source line (`RecipeSourceButton`) is never filled on this client, because `C_TradeSkillUI.GetRecipeSourceText` returns nothing.
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
- Row marks (owner's pick, 2026-11-24, from in-game previews of candidates): padlock `AdventureMapIcon-Lock`, trainer `Class` (book), vendor `Auctioneer` (coin stack), quest `Interface\GossipFrame\AvailableQuestIcon`, drop `lootroll-icon-need` (dice), unknown `common-search-magnifyingglass`. All exist on build 71037. Atlas marks keep the art's own shape, read from `C_Texture.GetAtlasInfo` (the padlock is 28 by 37). Sizes aim at the magnifier's visible height: measured from screenshots at about 1.16 UI scale, the magnifier drawn at 11 shows 13 pixels, the padlock at 13 showed 12, the quest mark at 16 shows 16, and the book and coin stack at 16 showed 14 to 15, so they are drawn at 14. The 14 for book, coin stack, dice and padlock is predicted from those measurements and not yet measured itself.
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
| Unlearned-recipe build with the old list insertion, first after a reload, before tooltip facts were kept | 34 ms (Tailoring, 417 unlearned), 42 ms (Blacksmithing, 501), 56 ms (Leatherworking, 585) |
| of which reading recipes and their tooltips | about two thirds |
| Same, later | 4 to 8 ms |
| Trainer read | 3 ms average; vendor read 0.06 ms |

## Places

- Subzones have IDs: `C_MapExplorationInfo.GetExploredAreaIDsAtPosition(mapID, position)` returned `{ 42 }` in Darkshire, and `C_Map.GetAreaInfo(42)` returned "Darkshire" (build 71091, 2026-11-25). Overlap, unexplored areas and dungeons are being measured by a capture in the working build (`RecipeVacuumDB.devAreas`).
- The dungeon journal does not load on Forever: `C_EncounterJournal and EJ_GetNumTiers` is nil (owner, build 71091, 2026-11-25), so boss loot cannot be read from the client.

## Saved data size and the facts cache

Measured on build 71091, 2026-11-25, one character, one run each (working build timings):

| Run | Saved file | Saved variables load | Cold unlearned-recipe build | Of which reading recipes |
|---|---|---|---|---|
| With the old item scan | 219 KB | 2.7 ms | 13.0 ms | 1.5 ms |
| Scan cleared | 153 KB | 1.7 ms | 8.9 ms | 0.6 ms |
| Facts cache dropped | 153 KB | 1.7 ms | 29.7 ms | 17.9 ms |

Size costs little: about 1 ms per 66 KB at load. The recipe facts cache saves about 20 ms on a profession's first unlearned-recipe build per game build, so it stays.

## Rank books

A rank book (Expert Fishing - The Bass and You, item 16083) is a recipe item whose item spell is the rank it teaches (`C_Item.GetItemSpell`: 19889, Expert Fishing; not the trainer-style rank spell, and `IsPlayerSpell` is the same check as `C_SpellBook.IsSpellKnown`, Blizzard_DeprecatedSpellBook/Deprecated_SpellBook.lua); its recipe subclass names the profession, and "Requires Fishing (125)" and "Already known" come as tooltip data (build 71091, 2026-11-25). The books are sold by a few vendors spread across the world, not by trainers (owner, 2026-11-25), so they are recorded as vendor sources like any recipe item. Primary profession ranks come from trainers instead: a trainer lists them as services with a spell and no category (Apprentice Alchemist 2259, Journeyman Alchemist 3101, Expert Alchemist 3464; build 71091, 2026-11-25), each shown once the one before it is learned. The addon keeps the step (docs/data.md, "Ranks"). Trainers have tiers, and a trainer lists ranks only up to the next one the character can learn: in Darnassus with Journeyman Alchemy, Milla Fairancora listed Apprentice only, Sylvanna Forestmoon up to Journeyman, Ainethil up to Expert (build 71091, 2026-11-25). So a trainer's top rank is learned only by visiting with the rank below it; Forever guides list Ainethil as an Artisan trainer (WoW-Professions, "WoW Forever Alchemy Trainer Locations"). Forever guides (Wowhead Forever profession overviews, Warcraft Tavern Forever trainer list; not yet checked in game) agree on the Expert book vendors above and add two more paths: Artisan Cooking, First Aid and Fishing come from quests (Triage for First Aid), and Forever adds manuals that teach a gathering profession without a trainer (Wowhead's Forever profession guides; Overgear, "WoW Forever professions changes").
