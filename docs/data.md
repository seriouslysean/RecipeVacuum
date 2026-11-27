# Data

Where each kind of data lives, and what the saved file holds. Each kind has one home, and none is copied into another.

## Layers

| Layer | Where | Comes from | Changes when |
|---|---|---|---|
| Seed | `Data/Seed.lua` (`ns.seed`), shipped | The game client, through `tools/seed.lua` | A release regenerates it for a new game build |
| Included | `Data/Included.lua` (`ns.included`), shipped | Finds reviewed by the maintainer | A release adds reviewed finds |
| Found | `RecipeVacuumDB.found`, saved | What this account saw in play | Play |
| Shared | `RecipeVacuumDB.shared`, saved | Friends, guild and group | Sharing |
| Links | `RecipeVacuumDB.itemRecipe`, `recipeItems`, saved | The tooltip of a recipe item the seed lacks | Play; dropped at load once the seed covers the item |
| Facts | `RecipeVacuumDB.recipeFacts`, saved | Recipe and item tooltips; a cache | Rebuilt on a new game build |
| Scan | `RecipeVacuumDB.devScan`, working build only | `/recipevacuum scan` | Each scan; a layer over the seed for the session |

Seed data is what the game says about itself: which item teaches which recipe, and the skill its item asks for. Found and Shared are what players saw: where things come from. The export holds Found only.

## Observations

Found, Shared and Included share one layout: `recipes[recipeID]` and `items[recipe itemID]`, each a list of observations.

An observation is `{ kind, one identifying field, faction, seen, build, rev, details }`:

| Kind | Identified by | Details |
|---|---|---|
| `trainer` | `npc` | `skill`, `cost` |
| `vendor` | `npc` | `price`, `limited`, `spellID` |
| `quest` | `quest` | `npc` (giver), `finisher`, `giverItem`, `choice`, `map` |
| `drop` | one of `npc`, `object`, `container` (item ID), `fishing` (map ID), `zone` (map ID, a group roll) | `map`, `x`, `y` |

`faction` is the faction of the character who saw it, `seen` is server time, `rev` is the account's revision counter (Found only). A later sighting updates details and never deletes.

NPCs and objects are stored once: `npcs[npcID]` and `objects[objectID]` hold `name`, `positions[mapID] = { x, y, seen }`, and for an NPC its own `faction`. An NPC is saved only when a source names it.

## Recipe items

A recipe item links to the recipe it teaches by ID, from three places kept apart:

1. The seed, `ns.seed.taught[itemID] = recipeID`.
2. A scan made this session in the working build (`ns.scanned`), ahead of the seed.
3. The item's own tooltip data, for an item newer than the seed. Only these links are saved.

`pendingItems[itemID]` holds a recipe item whose data has not loaded yet.

## Facts

`recipeFacts` keeps what tooltips say that is fixed for a game build, stamped with the build:

- `faction[recipeID]`: `"Alliance"`, `"Horde"` or `false`.
- `spec[recipeID]`: `true` when the item the recipe makes needs a specialization, `false` when it does not.

Whether a specialization is met depends on the character, so those recipes are read again each session. The unlearned-recipe build (`ns.GetUnlearnedRecipes`) reads every recipe of the profession, learned ones included; `spec[recipeID] == false` spares the read, so only a profession's first open on a game build reads them all.

## Sharing

Hidden addon messages only. The transport (probes, requests, batches, limits, who is listened to, logging) is the toolkit's share, described in its [docs/sharing.md](https://github.com/seriouslysean/JigBoltgripToolkit/blob/main/docs/sharing.md); this addon supplies the row shape in `Finds.lua`. The prefixes are `RecipeVacuum2` and `RecipeVacuum2D`: protocol 2, unchanged by the move onto the toolkit, so copies from before and after hear each other. The saved collection (`exchange.id`, `revision`, `received`) is the same layout as before.

1. A probe (collection ID, revision) goes out on joining a guild or group, on reconnecting, and when a friend comes online.
2. A peer that is behind whispers a request for everything after its revision.
3. The owner replies with one batch, capped near 4 kB encoded; the receiver asks again until it reaches the tip.

Received rows are parsed and checked field by field, never run as code: another addon (2021) ran received text through `loadstring`, which let any sender run code in the receiver's game. A row that fails its checks is dropped on its own and the rest of the batch is kept; a batch that cannot be read at all is skipped. Either way the cursor moves past it, since the same batch would fail the same way every time it was asked for.

Rows carry IDs; each client reads item, recipe and quest names in its own language. NPC and object names are sent, since the client has no lookup by ID. Keys: `k` kind, `r` recipe, `i` item; source `n` npc, `o` object, `ci` container, `fi` fishing zone, `z` roll zone, `q` quest; `nm`, `on` names, `nf` NPC faction; `m`, `x`, `y` place; on drops only `a` subzone area ID, `di` dungeon or raid instance ID, `cn` times seen; `f` faction, `s` seen, `b` build; details `sk`, `c`, `p`, `l`, `sp`, `ch`, `fn`, `gi`. Every received row is validated before it is saved, and received data is never executed.

Who gets a whisper is decided before sending: a friend who is online, and for a Battle.net friend a character in this game, on this realm and of this faction. Nothing is hidden from chat. If a whisper still fails (a friend logging off at that moment), the game prints "No player named '%s' is currently playing."; the addon reads that line so the name is not whispered again until it has been offline.

## Levels

The player chooses how far the addon listens (`sourceLevel`, `ns.LEVEL` in `Core.lua`). Each level includes the ones before it.

| Level | Shows | Sends |
|---|---|---|
| Self Found (1) | Everything the player saw: own finds and every come-across signal below | What Share My Finds sends |
| Friends (2), the default | Also the shared layer: finds from party, raid, guild and friends' addons | What Share My Finds sends |
| Public (3) | Also the data shipped with the addon (`ns.included`), and only here (owner, 2026-11-27: shipped data "Public only"; `VisibleLayers` in `Sources.lua`) | What Share My Finds sends |

Self Found is knowing, with the details your own (owner, 2026-11-26: "Remember self found is knowing, but the details are your own"): seeing a recipe anywhere (bags, a tooltip, chat, another player's profession) records only that it exists, and where it comes from (who sells, teaches or drops it, and where) is only ever what the player found in person. Other players' details arrive only through sharing, at Friends.

Everything is recorded at every level, tagged with the level it arrived at; the level decides what is shown and whether friends' finds are taken in. Sending is its own option, Share My Finds (`shareFinds`, on by default; owner, 2026-11-25: "the opt in for sharing is separate", then "On, can opt out"). A player who does not share offers revision 0, so no one asks for their finds. Schema 9 turned sending off for anyone who had chosen Self Found, which used to stop sending. The options page sets the level.

## Come across

`RecipeVacuumDB.met` holds recipes the player has come across without learning their source: `met.recipes[recipeID]` and `met.items[recipe itemID]` (for an item no recipe is linked to yet), each a level. Nothing else is kept: not who, not which channel, not when. A nearer sighting replaces a farther one.

| Signal | Level |
|---|---|
| A recipe item in the character's own bags, read when they change and on entering the world | Self Found |
| A recipe item in the character's bank, read when the bank opens and when its slots change (owner, Deck, 2026-11-26: recipes left in the bank were not counted) | Self Found |
| A recipe item listed in an auction house search, read as the results arrive (`AUCTION_HOUSE_BROWSE_RESULTS_UPDATED` and `_ADDED`; owner, Deck, 2026-11-26: searching and closing the auction house did not count) | Self Found |
| A recipe item on any item tooltip the player hovers (bags, bank, auction house, vendor, chat link, trade, comparison) | Self Found |
| A recipe item or recipe link in any chat: party, raid, instance, guild, officer, say, yell, a numbered channel, a whisper (Battle.net too) or a loot line | Self Found |
| A profession of another player the player opens: a linked one or a guild member's | Self Found |
| A recipe any character on the account knows, written when a profession's recipes are read (the unlearned-recipe pass) and on `NEW_RECIPE_LEARNED` | Self Found |

A known recipe is met account-wide (`RecipeVacuumDB.met` is shared by every character; owner, 2026-11-27: "self found is knowing, but the details are your own"), so an alt lists it with the source-unknown mark until a source is recorded. It costs one table write per known recipe (`ns.NoteKnown`), no login pass, and it adds nothing to a window's count or the refresh queue. `met` is local: nothing of it is sent to friends (`Finds.lua` and the sharing layer read only `found`). The working log has "known id=N found=n new=m no_trainer=…" for each read and "recipe learned id=N" for each new one.

A recipe item in the bags counts as seen by the player (owner, 2026-11-26: "it makes sense to me. I saw them."), so the recipe is kept at Self Found without where the item came from. The scan reads item IDs only and reads each item once a session; an item whose data has not loaded is read again on the next bag event, three times at most a session (`ns.MAX_ITEM_ATTEMPTS`); a late answer to the last request is read once more.

Hovering a recipe item counts the same (owner, 2026-11-26: "seeing them makes sense, if I'm running around and people are hawking their wares, why wouldn't that count? It's like browsing a store. I know they exist but nothing else about them."). The hook is `TooltipDataProcessor.AddTooltipPostCall` for item tooltips (`Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:199`): it reads the item ID from the tooltip data, uses the bag scan's item-to-recipe lookup and its once-a-session memory, and adds nothing to the tooltip.

Chat counts at Self Found for every channel (owner, 2026-11-26: "I think public and anything you see is 'self found'"). Only the sharing between addons (Sharing.lua) brings Friends-level finds. Opening another player's profession, linked or a guild member's, counts the same: the player saw it.

Counts are per window (owner, Deck, 2026-11-26: the auction house counted 150 recipes and said nothing, because the bags it opened were still open). A recipe first met at Self Found credits the most recently opened window that is not the bags and is still open (auction house, bank, trade, mail); only when none is open does it credit the bags. A window's close says its own line, "%d recipes seen!" (Voice.lua, `seen`), whatever else is open, and the bags say theirs when they close. Show Chat Alerts turns the line off. Only a recipe whose profession the character has counts: the recipe's skill line from `C_TradeSkillUI.GetTradeSkillLineForRecipe` (parent line when the game reports a child), against the skill lines of `GetProfessions`. A recipe counts when `Note` adds it or lowers its level, so one already seen is not counted again and nothing new says nothing. Hovers and chat links with no window open stay silent. An item the client has not loaded when a window shows it (an auction search lists many) is answered later by `ITEM_DATA_LOAD_RESULT`: its recipe still counts for the window that saw it, and that window's closing line waits up to 3 s (unmeasured) for such items before it speaks. A window reopened during that wait keeps its count for its next close.

The bags have no open or close event, and the Deck logged no `BAG_CLOSED` when the auction house closed. Their state is asked of `IsAnyBagOpen()` when a bag event or a close can have changed it (the sighting itself reads the open auction house, bank, trade or mail without asking), and when a window closes, on `BAG_CLOSED`, and on the next frame after `OnShow` or `OnHide` of the combined bag frame and `ContainerFrame1` onward (read-only `HookScript`s; names in `Blizzard_UIPanels_Game/Mainline/ContainerFrame.xml:298-313`). A working build's log has a `SEEN` line for each window opening and closing, each recipe counted (and for which window) or skipped with the reason, and each close decision (counted, silent and why, or waiting for items).

| Window | Opens | Closes | Source in the Forever UI |
|---|---|---|---|
| Auction house | `AUCTION_HOUSE_SHOW` | `AUCTION_HOUSE_CLOSED` | `Blizzard_APIDocumentationGenerated/AuctionHouseDocumentation.lua:1159,1237` |
| Bank | `BANKFRAME_OPENED` | `BANKFRAME_CLOSED` | `BankDocumentation.lua:392,398` |
| Trade | `TRADE_SHOW` | `TRADE_CLOSED` | `TradeInfoDocumentation.lua:78,143` |
| Mail | `MAIL_SHOW` | `MAIL_CLOSED` | `MailInfoDocumentation.lua:95,148` |
| Bags | `IsAnyBagOpen()` | `IsAnyBagOpen()` asked again on `BAG_CLOSED`, the bag frames' `OnHide` and each window's close | `ContainerDocumentation.lua:613`, `Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua:2235` |

Not verified in game: that `IsAnyBagOpen()` is false by the next frame after a bag frame's `OnHide`, that the frame names above are the Forever client's, and that the five window events fire as documented on this build.

A recipe with no known source counts as come across once it has been seen within the chosen level (`recipeInfo.met`).

## Show rule

The panel is self-found (owner, 2026-11-26): a recipe appears only once it has been discovered, and the panel keeps no list of everything. A recipe is a candidate when it is unlearned, in the open profession window's skill line (`C_TradeSkillUI.IsRecipeInSkillLine` with `professionInfo.professionID`, so another expansion's recipes never are) and not the other faction's (`Unlearned.lua`). An NPC of the other faction is no source for this character and is left out wherever sources are read (`ns.GetSources`, `ns.IsOtherFactionNPC`): the panel, tooltips, Map Pin and the show rule. A candidate is found when it has a known source within the chosen level, or was come across within it (`ns.IsListed`). A recipe with neither is left out; that drops the later-expansion recipes the client holds (518 for Blacksmithing in the owner's log) with no list of them kept.

The panel groups the found recipes by rank band of their required skill (`ns.BandOf`, `Unlearned.lua`): bands of 75, the profession's rank caps (1 to 75, 76 to 150, 151 to 225, 226 to 300). A recipe with no known requirement is placed by its trivial level (`ns.SkillOf`). Every band starts open, as Blizzard's categories do (owner, 2026-11-26: "We need to match blizzard"). A click on a heading toggles it for the session; nothing about it is saved.

## Discovery

The panel's discovery bar is found over total for the open skill line (`ns.GetListedRecipes`, `Unlearned.lua`). Found is the recipes the show rule lists, ignoring the search and filters. Total is every unlearned candidate of the skill line before the show rule: not the other faction's, nothing of another expansion's. Those candidates come from Recipe Vacuum's own data (the seed, the layers and what the client lists), not from every recipe in the game, so the Public tooltip says "Recipes you have found, out of those Recipe Vacuum knows you can still learn." (owner, 2026-11-27: "it's all the recipes we _know_ about, not that exist"). The Self Found and Friends tooltip, "Recipes you have found and can still learn in this profession.", claims no total and stays. The bar says how much of what the character could still learn has been found, and the panel keeps no list of the rest.

The total is a spoiler for a player who has not chosen public data (owner, 2026-11-26), so it follows the source level (`sourceLevel`):

| Level | Bar text | Fill | Tooltip |
|---|---|---|---|
| Self Found, Friends | "%d discovered" | none, the empty frame | the recipes found that can still be learned |
| Public | "%d / %d discovered" | found over total | found out of all that can still be learned |

Known gap: the alts' lists and counts grow account-wide, since a recipe any character on the account knows is met at Self Found (`ns.NoteKnown`).

The bar changes when the setting does. With nothing found and no search or filter, the panel itself is hidden (docs/client-notes.md, "Panel").

## Skill-up arrows

A row shows no number. It shows Blizzard's skill-up arrow (`docs/client-notes.md`, "Panel") only when the client says the recipe gives skill-ups: `C_TradeSkillUI.GetRecipeInfo(recipeID).canSkillUp` true, and the arrow by `relativeDifficulty` (Optimal high, Medium medium, Easy low; Trivial none). A recipe above the character's skill keeps the dim name and no arrow; its required skill is in the details ("Requires Engineering (20)"). The seed holds no thresholds: the client's answer is real for an unlearned recipe (Deck, Corvus, 2026-11-27: Alchemy at skill 206, 43 unlearned recipes, `relativeDifficulty` 0 x29, 1 x3, 2 x2, 3 x9, equal to the `SkillLineAbility` thresholds read earlier; Leatherworking at 150, 35 recipes with 0 to 3; `canSkillUp` true at Alchemy 206 and false for every recipe at a rank cap, First Aid and Cooking 150/150). Earlier readings at skill 16 to 24 showed only value 0 because every recipe there was above the skill.

The difficulty depends on the skill, so the list is read again when `SKILL_LINES_CHANGED` clears the unlearned cache (`Unlearned.lua`).

## Rank spells

A band heading is the rank named by the game's rank spell for the profession and step ("Journeyman", `ns.BandTitle`): the spell's subtext, read with `C_Spell.GetSpellSubtext` so it is in the player's language (the spell's name is just the profession's, "Engineering", seen on the Deck 2026-11-26); "Skill 76 to 150" is the fallback where no rank spell is known. `ns.seed.rankSpell[skillLine][step]` holds the spell IDs. `tools/seed.lua` reads them from wago.tools' `SpellEffect` table for the seed's build: a rank spell is a row with `Effect` 118 (SKILL_STEP), the skill line in `EffectMiscValue_0` and the step in `EffectBasePointsF`. Checked against known spells: Blacksmithing (164) Apprentice 2018 is step 1 and Journeyman 3100 step 2; Engineering (202) Apprentice 4036 and Journeyman 4037. Build 71091: 106 skill line and step pairs. Three steps (Tailoring 182, Leatherworking 186, Engineering 202, step 1) have a second spell with an ID above 1,235,000, which Forever adds beside the classic one; the lower ID is kept. Band n is step n, so bands past the fourth have no rank spell.

## Required skill

The skill a recipe is learned at, `recipeInfo.requiredSkill` (`ns.SummarizeSources`), is the lowest of:

- `ns.seed.learnSkill[recipeID]`: the lowest `RequiredSkillRank` of the recipe items that teach it. `tools/seed.lua` reads it from Blizzard's `ItemSparse` table (wago.tools DB2 CSV for the seed's build) for each item in `taught`. A rank of 0 is no requirement given and is left out. Build 71091: 1,814 of 2,114 taught recipes have one.
- A recorded trainer's `skill` (`GetTrainerServiceSkillReq`) in the visible layers; a value of 0 or none is ignored.

A recipe with neither has no required skill: it is placed and ordered by its trivial level. The list is in skill-up order by required skill where known, else `maxTrivialLevel`. Where the items of one recipe ask for different ranks, the lowest wins.

Seeing an item a recipe makes is not coming across the recipe: it says nothing about the recipe or where to learn it, and the player's own loot would count. Crafted items are ignored.

A shared observation keeps the time each of its fields was learned (`at`, by field name), so reports about different fields merge to the same result in whatever order they arrive; when two values for one field carry the same time, the one that sorts higher is kept. `at` is saved with the shared layer and is not sent.

## Drops

Each drop is one creature (or object) in one place: the item, the creature, the zone, and either the subzone at the kill (`area`, from `C_MapExplorationInfo.GetExploredAreaIDsAtPosition`, named by `C_Map.GetAreaInfo`) or the dungeon or raid (`instance`, from `GetInstanceInfo`), with the spot where it was last killed there (`x`, `y`) and how many times it was seen (`count`). The same creature in another subzone is another sighting.

A recipe's drop label comes from all its drop sightings, own and shared (`ns.DropScope`, `Sources.lua`):

| Sightings | Label | Map pin |
|---|---|---|
| One creature | Drop | Pinned where it was killed; the pin's label names the creature and its subzone |
| 2 or more creatures, one zone or dungeon | Zone Drop: <place> | No pin; the tooltip names the place |
| 3 or more zones or dungeons | World Drop | Nothing to show; the tooltip lists the zones |
| Anything else | Drop | Pins only fishing spots |

The tooltip ends with the evidence: "Seen N times from N creatures in N zones". Fishing and container drops keep their own lines and do not count toward the label.

The thresholds are the owner's choice (2026-11-25): no source publishes one. Wowhead's observed behaviour labels a zone drop at 2 creatures; "World Drop" is the wording of another addon, another addon and the Warcraft wiki (research: the session folder's drop-scope-research.md and drop-locations-research.md). "World Drop" and "Drop" are Blizzard's strings (`TRANSMOG_SOURCE_4`, `BATTLE_PET_SOURCE_1`); "Zone Drop" and the evidence line are English only. The times seen add one per loot window on the player's own client; across layers the first layer's count is used, so friends' counts do not add up yet.

Drop details from the Astra review (2026-11-25): a drop is placed by its own spot only, or by none, never by the creature's latest position elsewhere; positions of a fishing spot or a creature or object drop are merged as one pair, so two reports never combine into a spot nobody stood at; one loot window is one sighting per recipe item and source, however many slots hold it; a world drop's tooltip summarizes the creature zones while fishing and containers keep their own lines; a dungeon zone drop is named by the dungeon.

A source can be known in part. The tooltip shows "Unknown" in the place column for a source whose location is not known (a roll in a zone, a peer's report without a position), and a pin needs a position.

Not measured on build 71037: the profession link format (`|Htrade:<GUID>:`), that `recipeInfo.learned` in a linked or guild view means the other player knows the recipe.

## Ranks

Profession ranks come only from what the client shows; no rank list ships (owner, 2026-11-25, on the Astra review: "Build it"). A rank is a profession's skill line plus the cap it raises from, kept in `ranks[skill line][cap]` with three kinds of source:

| Source | Recorded when |
|---|---|
| Trainer | The trainer window offers a next rank: its skill step (`GetTrainerServiceStepIndex`, which Blizzard's trainer window shows apart). The rank's skill line comes from the step's spell; the cap is the character's at the visit. |
| Book | A recipe item used from the bags is followed within 5 seconds by a cap rise. The book's vendors come from the items layer, as for any recipe item. |
| Quest | A turn-in is followed within 5 seconds by a cap rise. The NPC at the completion window is kept as the giver. |

Migration 10 (2026-11-25, Astra review): trainer rank records made before the skill-step check could name a rank already known, under a child skill line. They cannot be told apart now, so all trainer records were removed and the next visits record them again; book and quest records stay, and sources left empty are dropped. A rank is titled with the game's own name for what is learned (a book, the trainer's rank, or the quest; owner, 2026-11-25), read at hover because item and quest names can arrive after the window opens.

The mark sits right of the window's link button, as our own Button under `UIParent` that follows the crafting page by hooks (docs/client-notes.md, "Panel"); it shows when the open profession's cap has a source with a place; the other faction's are left out. Ranks are kept per account and not shared yet. Unverified in game: the 5-second window, a trainer the character has outgrown, and a quest rank (Nat Pagle).

## Trainer spells

`RecipeVacuumDB.trainerSpells[npcID][service name] = spellID` is the spell a trainer's service teaches, taken from the service's tooltip (`C_TooltipInfo.GetTrainerService`; docs/client-notes.md, "Trainers"). It is account-wide, so a trainer is read once on any character, and it is a cache, not a source: a trainer source is saved by recipe ID only after the ID is matched to a profession recipe. The name is only the key; it is the client's own text, so another language reads its names again and finds the same IDs. Nothing clears it; a wrong entry would need a trainer to change a service's spell under the same name (not seen).

## Schema

`RecipeVacuumDB.schema` is the saved layout's version; `Core.lua` runs the migrations in order.

| Schema | Change |
|---|---|
| 2, 3 | Sources split into found and shared layers; NPCs stored once |
| 4 | Name-keyed trainer entries dropped |
| 5 | NPCs and objects no source names are removed |
| 6 | Recipe item links are made again from the ID in the item's tooltip data |
| 7 | The Full Color Source Icons option is removed |
| 8 | The two source modes become three levels (`sourceLevel`); an earlier Self Found choice is kept |
| 9 | Sending becomes its own option (`shareFinds`), off for anyone at Self Found |
| 10 | Trainer rank records are dropped, to be recorded again with the skill-step check |
| 11 | The options of the rows once added to Blizzard's recipe list (`showUnlearned`, `showUnavailable`, `sourceFilter`) and the first-run tip flag (`levelTipSeen`) are removed |
| 12 | The panel step (`panelStep`) is removed; the panel groups by rank band instead |
| 13 | `trainerSpells` is added, the spell cache below; nothing is converted |
| 14 | `learnedReads` and `unsourcedKnown` are added (Learned reads, below); nothing is converted |

## Learned reads

`RecipeVacuumDB.learnedReads[npcID] = { line = skill line, revs = { [character GUID] = n } }` marks a trainer whose learned ("used") services were read to the end, for the whole account (owner, 2026-11-27: "I won't see something different than you or another at a trainer"). `RecipeVacuumDB.unsourcedKnown[character GUID][skill line] = { rev = n, ids = { [recipeID] = true } }` holds each character's known recipes that had no trainer source when the profession window read them (`ns.NoteUnsourced`); `rev` counts them. A done trainer is read again on a character only when that character's `rev` for the trainer's skill line is above the one kept for it in `revs`. Both are local and never shared. Both grow with trainers visited and recipes known; nothing clears them.

