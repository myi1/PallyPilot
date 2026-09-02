# PallyPilot

A solo **Retribution Paladin co-pilot** for Project Ebonhold (WoW 3.3.5a). It
reads Ebonhold's live systems — echoes, affixes, tomes, the Soul Ash tree — and
turns them into plain, actionable advice: what to buy, what to reroll, what to
farm, and what's actually killing you.

It's an **advisor**, not a bot. Nothing here plays the game for you; it tells you
what the best move is and gets out of the way.

## What it does

- **Build console** (`/pp`) — your stat priority, gear, and affix picture at a
  glance, with a gear score and the biggest upgrades called out.
- **Echo tools** — `/pp audit` buckets every echo you own into keep / reroll /
  banish against a curated tier list; `/pp reroll` drives the orb reroll for the
  junk; `/pp fishstatus` tells you when to stop fishing a stack for higher
  quality (and when more rolls just trade power for breadth).
- **Gear, gems, enchants, glyphs** — `/pp gear` audits your affixes worst-first;
  `/pp gems` finds your missing/soft gem, enchant and glyph slots; `/pp upgrades`
  flags what to replace next.
- **Soul Ash advisor** (`/pp ash`) — a real next-best-buy optimizer that reads
  your live tree. It's **prestige-loop aware**: once your permanent enablers are
  bought, it leads with the AoE farm-survival rebuild you need after each reset,
  so you can start farming ash without dying. Plan a build up front in the
  **[Ash Tree planner](https://myi1.github.io/PallyPilot/)** — click nodes, watch
  the permanent vs temporary cost add up, copy the string, then `/pp ash import`
  and `/pp ash next` walks you through buying it node by node.
- **Combat meter + build comparison** — `/pp dps` and `/pp report` break your
  damage down by echo (procs roll up to their parent echo). Fights **auto-tag
  with the saved echo build that was active**, so `/pp bench compare` gives you a
  real side-by-side of your builds with zero manual tagging.
- **Solo raid guide** (`/pp guide`, `/pp boss <name>`) — per-boss, solo-Ret
  TL;DRs for the raids you can solo (bubble timings, Cleanse solutions, soft
  enrages), auto-selecting the raid you're standing in.
- **Missing-tome farm queue** (`/pp farm`) — the keeper echoes you don't own yet,
  cross-referenced with EbonholdHub's tome locations, with **one-click porting**
  when [CallboardHunter](https://github.com/myi1/CallboardHunter) is installed.
- **Rotation HUD** (`/pp rotation`) and **talent helper** (`/pp talents`) —
  a keybind-aware rotation reminder and a recommend / guided-apply talent flow.

## What makes it Ebonhold-specific

- **Reads your live account state.** Echo and affix ownership come from
  **EbonholdHub**; tree ranks and your active saved build come from the server's
  own loadout data. Advice reflects what you *actually* own, not a generic list.
- **It understands the rogue-lite layer** — echo draws/rerolls/quality and
  Adaptive Power, affix ranks I–VI (extract vs apply), tomes, and the Soul Ash
  tree + prestige loop (what carries over, the farm-survival rebuild, the gate).
- **Colorblind-safe by design.** Every verdict reads by **letter, word or shape**
  (S+/S/A/B/C/X, `[ON]`/`[OFF]`, ✓/✗) — color is only ever a redundant hint.
- **Client-side only.** It reads game/addon data at runtime; it never modifies
  the server and isn't affiliated with the Ebonhold team.

## Slash commands

| Command | Effect |
| --- | --- |
| `/pp` | build console / dashboard |
| `/pp farm` | missing-tome farm queue (one-click port with CallboardHunter) |
| `/pp audit` | rate every owned echo: keep / reroll / banish |
| `/pp reroll` | drive the orb reroll for your junk echoes |
| `/pp fishstatus` | quality-fishing readout (when to stop rolling a stack) |
| `/pp gear` | affix audit, worst-first |
| `/pp gems` | missing enchants / gems / glyphs |
| `/pp upgrades` | gear-health / next-upgrade finder |
| `/pp ash` | Soul Ash next-best-buy advisor (prestige-loop aware) |
| `/pp ash import` / `/pp ash next` | load a build from the [Ash Tree planner](https://myi1.github.io/PallyPilot/), then buy it node by node |
| `/pp dps` / `/pp report` | combat breakdown by echo |
| `/pp bench compare` | compare your saved builds from logged fights |
| `/pp bench cap <n>` | set how many fights to keep (default 1000) |
| `/pp guide` / `/pp boss <name>` | solo raid guide |
| `/pp rotation` | rotation HUD |
| `/pp talents recommend｜guide｜auto` | talent recommend / guided apply |
| `/pp hubsync` | publish your ratings into EbonholdHub's Auto-Pick |

Diagnostic scans (`/pp snapshot`, `/pp uiscan`, `/pp orbpreview`, …) dump state
to SavedVariables for troubleshooting — you won't need them day to day.

## Requirements

- **World of Warcraft 3.3.5a** on **Project Ebonhold**.
- **[EbonholdHub](https://ebonholdhub.icu) — required for the core features.**
  PallyPilot reads EbonholdHub's live data for your echo and affix ownership and
  tome locations, so the echo audit, reroll, farm queue and gear/affix advice all
  depend on it. Install and enable EbonholdHub first. Without it, PallyPilot still
  loads but the intelligence falls back to baked data or goes quiet.
- **Optional:** [CallboardHunter](https://github.com/myi1/CallboardHunter) —
  adds one-click porting from the farm queue.

## Install

1. Download the zip from the [latest release](https://github.com/myi1/PallyPilot/releases/latest).
2. Extract the `PallyPilot` folder into `World of Warcraft\Interface\AddOns\`.
3. `/reload` (or restart) — type `/pp` in-game to open the console.

See [CHANGELOG.md](CHANGELOG.md) for the per-version history. Client-side only;
not affiliated with the Project Ebonhold team.
