# Recipe Vacuum

A WoW Forever addon that shows the recipes you don't know yet in Blizzard's profession window, and where they come from. It builds on the window Forever ships and follows Blizzard's design language.

By default, **Everything** records recipe sources from trainers, vendors, quests and loot, and quietly exchanges missing finds with friends, guildmates and group members running Recipe Vacuum. Choose **Self Found** under Settings → AddOns → Jig Boltgrip's Toolkit → Recipe Vacuum to pause sharing and show only firsthand finds. **Announce New Finds** controls the chat line after a visit with new sources.

To contribute discoveries collected while playing alone, type `/recipevacuum export` (or press Run next to it in the options), copy the selected text, and send it to the maintainer as a JSON file. The export contains firsthand observations across the account.

## Commands

`/recipevacuum help` (or `/boltgrip recipevacuum help`) lists the commands in chat. Player commands also appear in the options page's Commands section. Two troubleshooting commands help when reporting a problem: `watch on` logs where loot, quest rewards, vendor stock and trainer lists come from as you play, and `log` shows that log in a window to copy from. The log keeps its last 2,000 lines in `RecipeVacuumDB.devLog` (`WTF/Account/<account>/SavedVariables/RecipeVacuum.lua`, written on `/reload` or logout).

## Development

- [docs/development.md](docs/development.md): setup, checks, the working build and seeding.
- [docs/data.md](docs/data.md): where each kind of data lives.
- [docs/client-notes.md](docs/client-notes.md): what the Forever client does, as measured.
- [docs/voice.md](docs/voice.md): the chat voice.

## Jig Boltgrip's Toolkit

Recipe Vacuum is a standalone module of Jig Boltgrip's Toolkit. Every module:

- sets `## Category: Jig Boltgrip's Toolkit` in its TOC, so Blizzard's AddOns list groups them;
- embeds `Libs/LibStub` and `Libs/JigBoltgripToolkit`, which give the toolkit one category in Blizzard's Settings panel, with a subcategory per installed module.
