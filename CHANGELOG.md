# Changelog

Notable changes to PallyPilot. Format based on
[Keep a Changelog](https://keepachangelog.com/); versions match the GitHub
releases and the `.toc`. Full commit-level history is in git.

## [0.68.1] - 2026-08-29
### Fixed
- `/pp snapshot` reads haste from the combat rating (CR_HASTE_MELEE/SPELL) since
  `GetMeleeHaste`/`UnitSpellHaste` return nil on the Ebonhold client — it now
  shows both the % and the rating (the direct measure of your haste gems).

## [0.68.0] - 2026-08-29
### Changed
- **Soul Ash advisor is now prestige-loop aware.** Once your permanent enablers
  are owned (Borrowed Power), it leads with the **AoE farm-survival rebuild** you
  need after each prestige — Splashguard (AoE damage reduction), Undying Spark +
  Refused Requiem (flat hardcore damage reduction), Victory Feast (heal-on-kill),
  Second Wind, Vital Infusion — instead of re-pushing enablers you already keep.
  Node effects verified against the client tree data.

## [0.67.0] - 2026-08-29
### Added
- `/pp snapshot` — one-reload baseline capture: player stats (HP, armor,
  mitigation, Strength/Spell Power, crit) + gear + ash ranks together.

## [0.66.0] - 2026-08-29
### Added
- Reads the new (2026-08-29) orb-reroll panel at runtime — no scan, no hardcoded
  frame names. `/pp orbpreview` shows the 3 offered echoes with verdicts and the
  best pick (read-only).

## [0.65.0] - 2026-08-29
### Added
- `/pp orbscan` — a watcher that captures the transient orb panel automatically.

## [0.64.0] - 2026-08-29
### Changed
- AshData updated for the Aug-2026 skill-tree changes (bankable-ash limit,
  Infinite Nodes uncapped). Endless Growth ranked above Endless Might for
  paladins (Growth feeds Strength → Spell Power; Might gives Ret the weaker AP).

## [0.63.0] - 2026-08-29
### Changed
- Reground the Ash advisor on the Ebonhold meta: your power is your echo build +
  affixes + gear; the tree's job is to enable and survive the prestige loop.
  Plain-language recommendations; the docked rail relaid so it no longer overflows.

## [0.62.0] - 2026-08-29
### Changed
- Configurable fight-history cap, default 1000 (was a fixed 150): `/pp bench cap <n>`.

## [0.61.0] - 2026-08-29
### Added
- Fights **auto-tag with the active saved echo build**, so `/pp bench compare`
  compares your builds with no manual tagging. `/pp bench <name>` still works as a
  manual override.

## Earlier
See the git history for versions before 0.61.0 — the build console, echo audit,
reroll engine, gear/affix/gem/enchant/glyph tools, solo raid guide, farm queue,
rotation HUD, talent helper, and Soul Ash advisor were built up over 0.10–0.60.
