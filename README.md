# Recipe Vacuum

A WoW Forever addon that tracks where recipes come from and which ones you don't know yet. It leaves Blizzard's profession window alone, so controller navigation and other windows keep working; a panel of its own beside the window lists the recipes you have found and not yet learned, by rank, with a discovery bar and each recipe's details and sources.

It tracks a recipe once you have come across it, and fills in where it comes from as you learn more. Recipe sources are recorded from the trainers, vendors, quests and loot you see. How far it listens beyond that is a choice under Settings → AddOns → Jig Boltgrip's Toolkit → Recipe Vacuum:

- **Self Found**: only what you see yourself.
- **Friends** (the default): also what your party, raid, guild and friends see, link or share. 
- **Public**: also recipes linked in public chat.

**Share My Finds** (on by default) sends what you find to your party, guild and friends who use Recipe Vacuum; turn it off to keep your finds to yourself. On a profession's rank bar, a mark appears when the next rank has a known place; clicking it sets a map pin. **Announce New Finds** controls the chat line after a visit with new sources.

To contribute discoveries collected while playing alone, type `/recipevacuum export` (or press Run next to it in the options), copy the selected text, and send it to the maintainer as a JSON file. The export contains firsthand observations across the account.

## Commands

`/recipevacuum help` (or `/boltgrip recipevacuum help`) lists the commands in chat. Player commands also appear in the options page's Commands section.

## Development

- [docs/development.md](docs/development.md): setup, checks, the working build and seeding.
- [docs/data.md](docs/data.md): where each kind of data lives.
- [docs/client-notes.md](docs/client-notes.md): what the Forever client does, as measured.
- [docs/voice.md](docs/voice.md): the chat voice.

## Jig Boltgrip's Toolkit

Recipe Vacuum is a standalone module of Jig Boltgrip's Toolkit. Every module:

- sets `## Category: Jig Boltgrip's Toolkit` in its TOC, so Blizzard's AddOns list groups them;
- embeds `Libs/LibStub` and `Libs/JigBoltgripToolkit`, which give the toolkit one category in Blizzard's Settings panel, with a subcategory per installed module.
