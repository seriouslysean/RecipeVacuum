# Voice

The addon's chat lines speak as a gnomish machine reporting to its owner. Every line is in `Voice.lua`; a new or changed line goes there, never inline in code.

## Rules

1. Two beats. First a state, shouted as fact ("Suction enabled!"). Then what the machine is doing about it, or the reading it took ("Calibrating recipe sensors!").
2. Every beat ends with an exclamation mark. No doubled words, no questions, no jokes.
3. At most one machine part per line (suction, sensors, nozzle, intake, scanners, memory banks), and a part belongs to one line only.
4. Facts stay exact: real counts, names and times. A line never explains what the addon will do.
5. Switches say "enabled" and "disabled". Failures say "Malfunction!" or "aborted!".
6. Close to the game's machines, never their words: no "Warning! Warning!", "Intruder alert!", "systems online", "CLUCK!".
7. The words carry the voice. Delivery never imitates the game's own formats ("says:", "whispers:").

Settings labels and tooltips are not in this voice: they follow Blizzard's wording.

## Plain text

The help tip and the level cards speak to the player directly, so they are plain: short sentences, everyday words, one idea each, warm, as a friendly game explains itself. A single gnomish touch is welcome (the cards give the scanner's range), never a second in the same text. The verb for what the addon does with a recipe is "tracks". The wording lives in `Core.lua` (`ns.levelText`, `ns.levelHeard`) and the tip in `Heard.lua`.

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

A line is printed by `ns.Log` as the addon's name, a colon and the text, all in the color the game gives an NPC's speech (`ChatTypeInfo.MONSTER_SAY`). One color throughout, as an NPC's line is. No brackets around the name: Forever writes player names that way.

When standing out and matching the game pull in different directions, match the game.
