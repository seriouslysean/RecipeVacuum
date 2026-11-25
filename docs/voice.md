# Voice

The addon's chat lines say what the Vacuum just did: "Boltgrip's Recipe Vacuum sucks up 8 recipes from Stephen Ryback!" Every line is in `Voice.lua`; a new or changed line goes there, never inline in code. The rules and the delivery are the toolkit's, in the library repository's `docs/standards.md` ("Voice"); this page holds what is the Vacuum's own.

## Rules

1. One action per line, present tense, one exclamation mark. The library puts "Boltgrip's Recipe Vacuum" in front, so a line here is the rest of the sentence.
2. The verb never repeats the device's name: "sucks up", not "vacuums".
3. Facts stay exact: real counts, names and places. The announcement counts recipes recorded from that person on this visit, so it never says "new".
4. A failure is the voiced line, then the error's text on a plain line.
5. Development-only lines are plain, not voiced.

Settings labels and tooltips are not in this voice: they follow Blizzard's wording.

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

`ns.Say(action)` prints a voiced line and `ns.Log(text)` a plain one, both through the toolkit library, which owns the mark, the prefix and the colors. The Vacuum's device color is brown (`ns.device.color`, `Core.lua`).

When standing out and matching the game pull in different directions, match the game.
