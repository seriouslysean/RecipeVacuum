## Toolkit

A module of Jig Boltgrip's Toolkit. Every module follows the toolkit's shared [standards](https://github.com/seriouslysean/JigBoltgripToolkit/blob/main/docs/standards.md) and meets its [quality bar](https://github.com/seriouslysean/JigBoltgripToolkit/blob/main/docs/quality-bar.md) before a release; this file adds only what is specific to this module. `Libs/JigBoltgripToolkit` is the toolkit's own file: change it in the toolkit repository, never here.

- `scripts/check` runs everything CI runs. Turn on the pre-push hook once per clone with `git config core.hooksPath .githooks`, and never skip it.
- Mouse and keyboard and gamepad are both first-class: nothing releases until both are checked in game.
- Comments say why, never history; measurements go in `docs/`, decisions in the toolkit's [docs/decisions](https://github.com/seriouslysean/JigBoltgripToolkit/tree/main/docs/decisions).
