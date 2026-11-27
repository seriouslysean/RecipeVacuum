# Decisions

Recipe Vacuum's own choices, grouped by kind, so each can be revisited with its reasons in hand. Choices that hold for every toolkit module are in the toolkit's [docs/decisions.md](https://github.com/seriouslysean/JigBoltgripToolkit/blob/main/docs/decisions.md). Each entry gives the decision, why (with its data), what was rejected and what would reopen it. The detail lives in the doc the entry points to.

## Trainers

- **Learned read: once per trainer, account-wide** (2026-11-27, `4dcc30e`, [client-notes.md](client-notes.md) "Trainers"):
  - **Decision:**
    - The learned ("used") services are read after the visible scan, once a visit.
    - A read that finds no rows is done, and done is saved per trainer for the whole account.
    - A trainer is read again only when the visiting character knows a recipe of that profession with no trainer source.
    - No profession gate, no purchase hook.
  - **Why:**
    - Each read flips Blizzard's "used" filter, and each flip rebuilds its list: 26 to 32 ms a pass on the Deck (log 2026-11-27 10:41, npc 1241).
    - Three passes over two visits found nothing, because the trainer taught Blacksmithing and the character had none.
    - Fable, Grok and Astra agreed on three things: the 0 was correct, the same-visit retry and the pre-scan trigger were bugs, and a hook adds nothing because the scan records rows before a purchase.
    - Owner: "I still think we need it"; "I don't think the gate is useful, it's only once anyway and is good for data gathering and if I want to switch professions by looking first"; "Does per character matter? I'd argue not".
  - **Rejected:**
    - Dropping the read (Astra).
    - A profession gate.
    - A `BuyTrainerService` hook.
    - Skipping when every known recipe has a source. Owner: "Not learning new recipes doesn't mean they'll never have them".
  - **Reopen if:**
    - The Learned Services [Read] test at a trainer whose recipes the character knows finds 0 rows; then the read itself is broken.
    - Flips show up as a measured cost.
- **Not built: trainer seed list** (2026-11-27): ship each trainer's spell IDs, flip only when a hidden seed spell lacks a source, and flag visible spells missing from the seed as new content. Owner: "I'd prefer not to, but worth thinking through". Reopen if flips become a measured cost.
- **Not built: trainer groups** (2026-11-27):
  - Trainers of one tier teach the same list. Owner: "journey man never teach different stuff usually ... The westfall odd girl is different".
  - Grouping them by identical spell-ID lists, never title text, would let one read or source cover the whole group.
  - Owner: "If it's too complicated we skip, it's a very minor cost".
  - Reopen if saved lists from several same-profession trainers turn out identical.

## Data

- **Known recipes count as met** (2026-11-26): a recipe the account knows counts as discovered, with nothing shared. Owner: "If I know 75 recipes from the trainer ... Me knowing them means public doesn't matter, it's assumed since I learned it".
- **Difficulty re-read uncapped** (2026-11-27): a skill change is read again until every candidate answers. A recipe that never reports a difficulty would keep being re-read in 2 ms slices. All 89 of Corvus's recipes answered, so this is a known risk, not built against.

## Panel

- **Skill-up arrows, not numbers** (2026-11-26): rows show Blizzard's arrows from `GetRecipeInfo().relativeDifficulty`; the required skill is in the details pane; the list sorts by required skill. Corvus gave 0 mismatches against the seed. Owner: "Arrows only, as now".
