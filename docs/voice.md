# Voice

The addon's voiced lines show the Vacuum at work: "Boltgrip's Recipe Vacuum whirs and rattles. Intake complete! 8 recipes from Stephen Ryback!" The second, said when a bag, auction house, bank, trade or mail window closes on new recipes for the character's professions: "Boltgrip's Recipe Vacuum whirs and rattles. 2 recipes seen!" The third, said when a click sets a map pin: "Boltgrip's Recipe Vacuum whirs and rattles. Stephen Ryback located in Stormwind City! Map pin set!" Every line is in `Voice.lua`; a new or changed line goes there, never inline in code. The rules and the delivery are the toolkit's, in the library repository's `docs/standards.md` ("Voice"); this page holds what is the Vacuum's own.

## Rules

1. The shape is the toolkit's: the noise, then the report (owner, 2026-11-25, of this line: "I like the 1 options above, can we apply that to all lines in both addons?").
2. Facts stay exact: real counts, names and places. The announcement counts recipes recorded from that source on this visit, so it never says "new".
3. Development lines (watch, log, scan, perf) are checkout-only and plain, not voiced.

Settings labels and tooltips are not in this voice: they follow Blizzard's wording.

## Plain text

The level choices speak to the player directly, so they are plain: short sentences, everyday words, one idea each, warm, as a friendly game explains itself. A single gnomish touch is welcome (the choices give the scanner's range), never a second in the same text. The verb for what the addon does with a recipe is "tracks". The choices' sentences are the toolkit's (`SourceChoices`; Recipe Vacuum passes "recipes" and "recipes people link in chat").

## Where the voice comes from

Read real in-game gnome text before writing a line, and model on it without copying it.

| Source | Line |
|---|---|
| Homing Robot OOX-17/TN ([Rescue OOX-17/TN!](https://warcraft.wiki.gg/wiki/Rescue_OOX-17/TN!)) | "Flight systems online! CLUCK! Engaging rockets for transport to Booty Bay!" |
| Same | "Threat analyzed! Activating combat plan beta! CLUCK!" |
| Mobile Alert System ([wiki](https://warcraft.wiki.gg/wiki/Mobile_Alert_System)) | "Internalizing subward transport! Defense units inbound!" |
| Tinkmaster Overspark ([wiki](https://warcraft.wiki.gg/wiki/Tinkmaster_Overspark)) | "Our scanners report you are a certified gnomish engineer!" |
| Gnome engineering trainers | "Access secret gnome engineering schemata!" |

## Delivery

`toolkit:Say(ns.module, line, ...)` prints a voiced line (the entry's noise, then its report formatted with the arguments, or `reportOne` for a first argument of 1) and `toolkit:Print(text)` a plain one, both through the toolkit library, which owns the mark, the prefix and the colors. The Vacuum's name takes the Druid class color (`NewModule`, `Core.lua`).

When standing out and matching the game pull in different directions, match the game.
