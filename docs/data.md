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

Seed data is what the game says about itself: which item teaches which recipe. Found and Shared are what players saw: where things come from. The export holds Found only.

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

Whether a specialization is met depends on the character, so those recipes are read again each session.

## Sharing

Hidden addon messages only, through AceComm and ChatThrottleLib.

1. A probe (collection ID, revision) goes out on joining a guild or group, on reconnecting, and when a friend comes online.
2. A peer that is behind whispers a request for everything after its revision.
3. The owner replies with one batch, capped near 4 kB encoded; the receiver asks again until it reaches the tip.

Rows carry IDs; each client reads item, recipe and quest names in its own language. NPC and object names are sent, since the client has no lookup by ID. Keys: `k` kind, `r` recipe, `i` item; source `n` npc, `o` object, `ci` container, `fi` fishing zone, `z` roll zone, `q` quest; `nm`, `on` names, `nf` NPC faction; `m`, `x`, `y` place; `f` faction, `s` seen, `b` build; details `sk`, `c`, `p`, `l`, `sp`, `ch`, `fn`, `gi`. Every received row is validated before it is saved, and received data is never executed.

Who gets a whisper is decided before sending: a friend who is online, and for a Battle.net friend a character in this game, on this realm and of this faction. Nothing is hidden from chat. If a whisper still fails (a friend logging off at that moment), the game prints "No player named '%s' is currently playing."; the addon reads that line so the name is not whispered again until it has been offline.

## Schema

`RecipeVacuumDB.schema` is the saved layout's version; `Core.lua` runs the migrations in order.

| Schema | Change |
|---|---|
| 2, 3 | Sources split into found and shared layers; NPCs stored once |
| 4 | Name-keyed trainer entries dropped |
| 5 | NPCs and objects no source names are removed |
| 6 | Recipe item links are made again from the ID in the item's tooltip data |
