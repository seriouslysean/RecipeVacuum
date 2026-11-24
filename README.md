# Recipe Vacuum

A WoW Forever addon that shows the recipes you don't know yet in Blizzard's profession window, and where they come from. It builds on the window Forever ships and follows Blizzard's design language.

By default, **Everything** records trainer and vendor finds and quietly exchanges missing observations with friends, guildmates and group members running Recipe Vacuum. Choose **Self Found** under Settings → AddOns → Jig Boltgrip's Toolkit → Recipe Vacuum to pause sharing and show only firsthand finds. **Announce new finds** controls personal visit messages.

To contribute discoveries collected while playing alone, type `/recipevacuum export` (or press Run next to it in the options), copy the selected text, and send it to the maintainer as a JSON file. The export contains firsthand observations across the account.

## Commands

`/recipevacuum help` (or `/boltgrip recipevacuum help`) lists every command in chat. Player commands also appear in the options page's Commands section. Troubleshooting commands (`checks`, `watch`, `dump`, `requirements`, `perf` and others) print to chat, open their output in a copy window, and keep the last 2,000 lines in `RecipeVacuumDB.devLog` (`WTF/Account/<account>/SavedVariables/RecipeVacuum.lua`, written on `/reload` or logout).

## Development

Link the repository into the Forever client, then `/reload` after each change:

```
ln -s "$PWD" "/Applications/World of Warcraft/_forever_/Interface/AddOns/RecipeVacuum"
```

Forever's UI source, for reference: [Gethe/wow-ui-source, `forever` branch](https://github.com/Gethe/wow-ui-source/tree/forever).


## Jig Boltgrip's Toolkit

Recipe Vacuum is a standalone module of Jig Boltgrip's Toolkit. Every module:

- sets `## Category: Jig Boltgrip's Toolkit` in its TOC, so Blizzard's AddOns list groups them;
- embeds `Libs/LibStub` and `Libs/JigBoltgripToolkit`, which give the toolkit one category in Blizzard's Settings panel, with a subcategory per installed module.
