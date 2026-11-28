# Using Recipe Vacuum

Recipe Vacuum tracks where recipes come from and which ones you don't know yet. It leaves Blizzard's profession window alone, so controller navigation and other windows keep working; a panel of its own beside the window lists the recipes you have found and not yet learned, by rank, with a discovery bar and each recipe's details and sources.

It tracks a recipe once you have come across it, and fills in where it comes from as you learn more. Recipe sources are recorded from the trainers, vendors, quests and loot you see. How far it listens beyond that is a choice under Settings → AddOns → Jig Boltgrip's Toolkit → Recipe Vacuum:

- **Self Found**: only what you see yourself.
- **Friends** (the default): also what your party, raid, guild and friends see, link or share.
- **Public**: also recipes linked in public chat.

On a profession's rank bar, a mark appears when the next rank has a known place; clicking it sets a map pin. **Announce New Finds** controls the chat line after a visit with new sources and the line when a bag, auction house, bank, trade or mail window closes on new recipes for your professions.

## Sharing

**Share My Finds** (on by default) sends what you find to your party, guild and friends who use Recipe Vacuum; turn it off to keep your finds to yourself.

What sharing shows them that the game does not: that your characters are one player (your finds carry one ID for the whole account), and, for a drop or a fishing find, where you stood and when. With Share My Finds off, neither is sent.

## Commands

`/recipevacuum help` (or `/boltgrip recipevacuum help`) lists the commands in chat. Player commands also appear in the options page's Commands section.

To contribute discoveries collected while playing alone, type `/recipevacuum export` (or press Run next to it in the options), copy the selected text, and send it to the maintainer as a JSON file. The export contains firsthand observations across the account.
