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

Hidden addon messages only, through AceComm and ChatThrottleLib.

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
| Self Found (1) | The player's own finds | What Share My Finds sends |
| Friends (2), the default | Also the shared layer, and what party, raid, guild and whispers bring | What Share My Finds sends |
| Public (3) | Also what public chat brings | What Share My Finds sends |

Everything is recorded at every level, tagged with the level it arrived at; the level decides what is shown and whether friends' finds are taken in. Sending is its own option, Share My Finds (`shareFinds`, on by default; owner, 2026-11-25: "the opt in for sharing is separate", then "On, can opt out"). A player who does not share offers revision 0, so no one asks for their finds. Schema 9 turned sending off for anyone who had chosen Self Found, which used to stop sending. The options page sets the level.

## Come across

`RecipeVacuumDB.met` holds recipes the player has come across without learning their source: `met.recipes[recipeID]` and `met.items[recipe itemID]` (for an item no recipe is linked to yet), each a level. Nothing else is kept: not who, not which channel, not when. A nearer sighting replaces a farther one.

| Signal | Level |
|---|---|
| A recipe item or recipe link in party, raid, instance, guild or officer chat, or whispered by someone in the party, guild or friends list | Friends |
| A recipe item in a loot line (someone nearby looting) | Friends |
| A recipe item or recipe link in say, yell or a numbered channel, or whispered by anyone else | Public |
| The guild's profession view | Friends |
| A linked profession the player opens | The level its link was seen at this session, else Public |

A recipe with no known source counts as come across once it has been seen within the chosen level (`recipeInfo.met`).

## Show rule

The panel is self-found (owner, 2026-11-26): a recipe appears only once it has been discovered, and the panel keeps no list of everything. A recipe is a candidate when it is unlearned, in the open profession window's skill line (`C_TradeSkillUI.IsRecipeInSkillLine` with `professionInfo.professionID`, so another expansion's recipes never are) and not the other faction's (`Unlearned.lua`). An NPC of the other faction is no source for this character and is left out wherever sources are read (`ns.GetSources`, `ns.IsOtherFactionNPC`): the panel, tooltips, Show Map and the show rule. A candidate is found when it has a known source within the chosen level, or was come across within it (`ns.IsListed`). A recipe with neither is left out; that drops the later-expansion recipes the client holds (518 for Blacksmithing in the owner's log) with no list of them kept.

The panel groups the found recipes by rank band of their required skill (`ns.BandOf`, `Unlearned.lua`): bands of 75, the profession's rank caps (1 to 75, 76 to 150, 151 to 225, 226 to 300). A recipe with no known requirement is placed by its trivial level (`ns.SkillOf`). The band holding the character's skill, and every band below it, start open; higher bands start collapsed. A click on a heading toggles it for the session; nothing about it is saved.

## Discovery

The panel's discovery bar is found over total for the open skill line (`ns.GetListedRecipes`, `Unlearned.lua`). Found is the recipes the show rule lists, ignoring the search and filters. Total is every unlearned candidate of the skill line before the show rule: not the other faction's, nothing of another expansion's. The bar says how much of what the character could still learn has been found, and the panel keeps no list of the rest.

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

The mark sits right of the panel's discovery bar (docs/client-notes.md, "Panel"); it shows when the open profession's cap has a source with a place; the other faction's are left out. Ranks are kept per account and not shared yet. Unverified in game: the 5-second window, a trainer the character has outgrown, and a quest rank (Nat Pagle).

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

