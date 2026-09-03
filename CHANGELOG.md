# Changelog

Notable changes to PallyPilot. Format based on
[Keep a Changelog](https://keepachangelog.com/); versions match the GitHub
releases and the `.toc`. Full commit-level history is in git.

## [0.82.0] - 2026-09-04
### Fixed
- **The item tooltip only ever talked about affixes.** Hovering a ring with a
  5/6 affix AND an empty red socket printed one line about the affix and nothing
  about the socket -- and an item whose affix was already VI printed nothing at
  all, which reads as "this item is done" when it still had an empty gem slot and
  no enchant. The Gear page knew all of this; the tooltip just never said it.

  Tooltips now cover all three axes -- **affix, gems, enchant** -- naming the
  specific gem (from the class's own `gemRec`) and the specific enchant plus
  where to get it. Silence still means finished; it just means it truthfully now.
- **Off-class characters were never told to gem anything.** `GearOpt.SlotReport`
  returned *nothing* for a non-paladin, because its enchant table is
  Retribution-specific (Strength/AP plate) and a wrong "missing enchant" flag is
  worse than silence. But that threw out the factual half with the opinionated
  half: an empty socket is an empty socket on any class.

  It now separates the two. Item level and sockets are reported for everyone;
  only the enchant *recommendation* stays gated. Off-class there is still no
  enchant flag and no enchant check in the gear score -- but empty sockets are
  now counted and advised, using the class's own gem recommendation. Priest,
  Hunter and Mage gear scores will move as a result.

### Added
- `tooltip_advice_test`, pinning the reported case (affix rank *and* empty socket
  on one ring), the silent-when-finished rule, the off-class split (gem line yes,
  enchant line no), and that every line leads with a WORD rather than relying on
  colour. 26 tests green.

## [0.81.0] - 2026-09-03
### Fixed
- **The gear advisor was hiding a free affix slot.** Shirt and Tabard were
  skipped outright, on the assumption that they carry no stats and cannot take
  an affix. That is true of a plain shirt -- and skipping them is what stopped
  the advisor telling you to re-roll an affix onto your tabard -- but it is NOT
  true of an **Epic** one, which on Ebonhold takes an affix like any other slot.
  So the one case where the slot was worth something was the one case that was
  invisible.

  The gate is now the item's **quality**, not the slot number: cosmetic slots are
  graded only when what is equipped there is Epic or better. A plain shirt still
  shows nothing; an Epic Purple Shirt with no affix now shows up as a FIX with
  the affix to chase. Expect your gear score to dip slightly and your fix count
  to go up by one -- that is a real gap becoming visible, not a regression.
- `PriestData` only defined affix targets for slots 1-18, so a priest would have
  had no verdict on an Epic tabard even after the above. All four classes now
  cover 1-19.

### Changed
- **Orbs per roll walks a ladder instead of counting to 100.** An orb reroll's
  quality boost scales with the orbs you spend (~100 orbs is roughly double), and
  the rail's own NEXT line tells you to crank it up first -- but the `-`/`+`
  buttons stepped by **one**, so taking that advice meant about 99 clicks. They
  now step 1 / 5 / 10 / 25 / 50 / 75 / 100, so any setting is at most six clicks,
  and **shift-click jumps straight to 1 or 100**.
- New **`/ep orbs <n>`** sets an exact value between the rungs; bare `/ep orbs`
  reports the current setting. It clamps to 1-100, floors fractions and rejects
  non-numbers rather than writing junk into SavedVariables -- a nil or a float
  there would have broken every later reroll line that formats it.

### Added
- `orb_ladder_test` and `cosmetic_affix_test`. The ladder one asserts the thing
  the change exists for (1 to 100 in <= 6 clicks) and the case a naive
  find-the-index implementation gets wrong: stepping from an off-ladder value
  typed via `/ep orbs`. The affix one pins BOTH directions -- an Epic shirt is
  graded, a plain shirt is still silent -- so neither bug can come back alone.
  25 tests green.

## [0.80.0] - 2026-09-03
### Added
- **MAGE is the fourth supported class** (`MageData.lua`, `PP.Classes.MAGE`) at
  the same parity bar as Paladin/Hunter/Priest -- a solo Fire mage guide for the
  hardcore climb. Almost none of it is retail theorycraft:
  - **Talents are 47 Arcane / 49 Fire, DECODED rather than chosen.** Rellex's
    "600M DPS" guide in #mage links a talent-calculator string; it decodes
    against the client's own `Talent.dbc` + custom `Spell.dbc`. 47 Arcane is a
    hard floor because Arcane row 9 needs 45 in-tree points and holds Spell
    Power 2/2 (+50% spell crit damage) -- iorek's thread reaches the same number
    independently.
  - **Echoes are decoded from two published EBH1 loadouts** (79 and 80 echoes,
    zero unresolved ids). The 76 that appear in BOTH are the high-conviction
    core. The lock list is Zedd's published six, in his order, plus Adaptive
    Power as the ranked seventh.
  - **The stat line is a crit wall, then haste** -- not spell power. The
    community target is 100% spell crit (Hot Streak only procs off crits), and
    the reference build gems haste, not SP.
  - **The survival engine is class-unique.** The "Pain" affixes scale spell
    power off damage TAKEN, so a mage facetanks on purpose; Ice Block then
    clears the 60-minute lockout debuffs that Demonic Awakening and Reaper's
    Reprieve leave behind, which no other class can do, re-arming both.
- **Echo effects are now read from the client's custom `Spell.dbc`** (echo
  spellIds live at 200000+; Description is field 170) instead of from community
  prose. That is what established that Armor Mastery literally reads "You can
  equip all armor types" -- which is why the reference build wears plate legs
  and a shield, and why that echo holds a permanent lock slot: the whole gear
  plan stops being equippable without it. It also corrected Brittle Armor (a
  +crit / -armor TRADE, not the pure loss it was described as), Demonic
  Awakening (leech, not a flat heal) and Reaper's Reprieve (60 min lockout, and
  it spends no Cheat Death charge).

### Changed
- `validate_echoes.js` and `validate_talents.js` now cover MAGE (talent tabs
  81/41/61). Without this the new file would have been shipped unchecked --
  which is how two community names slipped in as phantoms and were caught:
  "Temporal Vortex" is really Tempest Vortex, "Calvary Instincts" is Cavalry
  Instincts.
- Molten Armor is kept up through the generic `B.rotationUpkeep` path, so
  RotationHelper gains no new hardcoded class branch.
- `GearOpt` is deliberately NOT generalised per class. Its enchant/gem/glyph
  tables are Retribution-specific, the existing guard already prints a
  text-marked "NOT FOR MAGE", and the mage's gems, glyphs and weapon enchant
  live in `MageData` -- generalising would create two sources of truth for the
  same advice.

### Note
- Releases 0.79.0 through 0.79.4 shipped without CHANGELOG entries; their
  commit subjects are the record. This entry does not attempt to backfill them.

## [0.78.1] - 2026-09-01
### Fixed
- **The journal rail overlapped itself into an unreadable mess.** It mixed two
  layout systems: the body anchored from the TOP and growing with its text,
  the button cluster anchored from the BOTTOM at fixed offsets. Nothing
  coordinated them, so as soon as the body ran long -- six lock names plus
  counts plus fodder -- they collided. Everything is now placed by one
  top-down pass from MEASURED heights, run last so the heights are real, with
  empty elements collapsing instead of leaving holes. A new test asserts no
  two elements share vertical space at any content length.
- **Farm / Raid silently overwrote the pool plan.** Those buttons also ran
  `EchoAudit.DisablePlan` -- the pre-BiS planner, which reads the RUN's echo
  set with no tome gating, so it named echoes that have no toggle -- and wrote
  `PP.db.poolPlan`, re-badging every tile from the wrong source. Two pool
  planners, and the older wronger one won. They are now purely an aim toggle
  plus the EbonholdHub sync, which is the half that was always right.

### Removed
- `EchoAudit.DisablePlan` (83 lines) and `/ep pool <n>`, which only existed to
  tune it. There is now exactly ONE pool-planning path: TomeManager, on
  CHASE/KEEP/CUT via `MergedTiles()`.

### Changed
- **Build score moved to the Builds page** as "Score this run". It rates
  composition -- a prediction -- so it belongs beside the measured DPS
  comparison rather than sitting as an unexplained button on the rail.
- Rail captions cut to one short line each; "Pool plan" says "(level 1)" on the
  button itself instead of relying on a caption below it.

## [0.78.0] - 2026-09-01
### Fixed
- **A reroll queued 70 echoes.** The no-junk fallback queued the ENTIRE fodder
  ranking, and since EbonholdHub's auto-pick answers the draw there is no pause
  between items -- it would have fed most of a finished build to the orb
  unattended. The keeper fallback now queues exactly ONE echo and names it, and
  a hard cap of 12 bounds every queue from every caller.
- **The engine stalled forever on a tile that was plainly on screen.** The perk
  database calls an echo "Paladin - Stonefist Barrage - Rare" while the journal
  tile reads "Stonefist Barrage", and tile discovery only yielded tiles the
  catalog could RATE -- so an unrated echo was invisible to the one consumer
  that just needed to click it. Clicking no longer requires a rating, and a
  class prefix or quality suffix on either side no longer causes a miss. A tile
  that genuinely is not there is skipped instead of wedging the queue.
- **The Builds page reported "nothing is measured" while sitting on 907 logged
  fights.** A migration deleted old-format capture rows but left `buildId` on
  the fights pointing at them, and an id was treated as authoritative -- so a
  dangling id suppressed name matching and orphaned hundreds of fights. Dead
  ids are cleared on load, a dangling id now falls through to the name, and
  builds that exist only as a tag on logged fights appear as real rows.
- Rolling showed "RUNNING" at the top of the rail while the live instruction sat
  pinned to the bottom, out of view.
- Stopping mid-hunt left the hunt armed, so the next ordinary reroll silently
  resumed it.

### Added
- **Hunt: goal-directed rolling.** Chases the CHASE list with a roll budget and
  stops the moment one lands. Re-picks the weakest fodder each roll, refuses to
  feed a CORE/S echo, and names every echo and target before it starts.
  `/ep hunt [rolls]`, or the NEXT button.
- **`/ep tilediag`** -- records what the engine can actually see in the run
  panel, to SavedVariables, so a stall is diagnosed from disk rather than
  guessed at.

### Changed
- **The Builds page is a ranked list, not a spreadsheet.** It was a metric x
  build matrix that answered "what are all the numbers" when the question is
  "which build should I run" -- and it led with predicted composition while the
  measured damage sat below. Now: the answer in one sentence with the gap and
  how much to trust it, then one card per build (rank, name, dps, evidence,
  delta), with composition as a single quiet line.
- **The journal rail is grouped and captioned.** Five identical buttons with no
  indication of purpose became four labelled groups, each with the one sentence
  that says whether it applies right now. "Tome on/off" is "Pool plan" and says
  it only works at level 1; Farm/Raid name the active mode in words rather than
  relying on a highlight.
- The rail names **what you are chasing**, not just how many are missing.

## [0.77.0] - 2026-09-01
### Added
- **`/ep now` and a NEXT button on the journal rail.** One answer, two lines:
  what to do and what to press. The rail button *performs* the action, so the
  advice and the doing are one click. It resolves per state (curate at level 1,
  sync while levelling, roll, fish, lock and save) and hides rather than
  offering a click that cannot work.
- **CHASE / KEEP / CUT build model.** The old flat "43 S-tier targets" list
  conflated what you spend orbs on with what you keep in the pool. CHASE is now
  ~12 echoes ranked by evidence (measured combat log first, then cross-build
  consensus, then our tier letters); KEEP is deliberately broad because pool
  breadth is a damage stat via Adaptive Power; CUT is the rest.
- **Nero's published paladin build decoded and baked in** as a reference tier,
  from the EBH1 loadout string in his Google doc (85 echoes).
- **Fodder ranking** (`EchoAudit.FodderRank`): the run's echoes weakest-first,
  excluding chase targets and locks, so the panel can name the echo to feed.
- **Full-catalog tome scan** (`/ep tomes scan`) that walks the virtualized
  journal scroll and writes the complete picture, drop sources and run
  diagnostics to SavedVariables.

### Fixed
- **Every crit counter read zero, always.** The combat-log payload was
  round-tripped through `{...}` and `unpack()`, which truncates at the first
  nil, and a CLEU line is full of nil holes -- the crit flag never arrived.
- **Five lock slots recommended instead of six**, since the shipped default
  persisted into saved variables. Corrected with a targeted migration rather
  than a DB wipe, so fight history survives.
- **The Echo Journal scroll is virtualized** and five modules were reading only
  the rendered slice to answer "do I own this". All now go through
  `TomeManager.MergedTiles()`. This is what made the Target build panel report
  owned echoes as `[FARM]`.
- **Shadowform keybinds.** A form swaps buttons 1-12 to a bonus bar; the lookup
  took the first matching slot instead of the key the on-screen button shows.
- `/pp bench compare` errored out (12 format specifiers, 13 arguments).
- The new-echo watcher had never fired: `PP.db.audit` was never created.
- Gear optimizer served Retribution-paladin enchants to every class.
- Ash build-import frame stuck to the cursor (`StopMoving` is not an API).
- Boss card sized itself one boss behind (`GetHeight` after `SetText`).

### Changed
- **Mechanics corrections throughout.** An orb reroll consumes an echo *you
  select* -- there is no junk requirement and no "out of fodder" state. Banish
  is offered only on level-up draws and EbonholdHub's automation spends it for
  you, so the addon never tells you to banish. `tomeKnown == false` no longer
  means "must farm": base-pool echoes need no tome.
- **No chat walls.** Tome plans badge the tiles instead of dumping lists;
  diagnostics go to SavedVariables.
- Badges are state-aware and clear the moment a tile is toggled, refreshed off
  the journal's own change signal instead of a 2-second tick.

## [0.75.0] - 2026-08-30
### Removed
- **The prestige route runner moved to CallboardHunter** (`/cbh route`, CBH
  1.8.0). It leaned on CBH's checkpoint port layer and guidance arrow, so it
  belongs there rather than reaching across addons for both. `/pp route` now
  points at the new command; your route state (harvested checkpoints, learned
  quest givers) migrates itself on first login. Everything below about
  `/pp route` in 0.71–0.74 applies to `/cbh route` now.

## [0.74.0] - 2026-08-30
### Fixed
- **Steps stopped advancing after a hand-in.** Turn-in detection relied on a
  `QUEST_COMPLETE` → quest-leaves-the-log handshake that gets missed when the
  hand-in is automatic or when a catch-up level burst floods the event queue.
  It now watches three independent signals — the server's own
  `"<quest> completed."` chat line (primary, and the one the client always
  emits), a route quest that was complete in your log and then vanished, and the
  old reward-screen path — all funnelling into one idempotent recorder.
- **Learned quest givers could be completely wrong.** When no dialog NPC was
  available the code fell back to `UnitName("target")`, happily recording
  whatever you were hitting at the time as the quest giver. That name then drove
  the guide text and the coordinates. Only the actual dialog NPC is trusted now;
  **`/pp route forget`** throws away a bad one so it re-learns.

### Added
- **The button targets and marks the step's NPC.** It's now a secure macro
  button running `/targetexact <npc>` and then placing a raid marker (skull by
  default, `/pp route mark <1-8>`; markers read by shape, not colour). If raid
  icons no-op — they need a party on this client — it says so instead of leaving
  you hunting for a skull that was never placed. Out of range, it says that too.
- **`/pp route why`** — dumps everything the addon believes about the step
  you're stuck on: whether the quest is in your log, whether it reads complete,
  the learned NPC, the auto toggle, and the exact quest titles the client is
  reporting, so a spelling mismatch is visible rather than mysterious.

### Changed
- The compact panel is now genuinely **one** button — the separate Self-Execute
  button is gone, folded into the single secure button via attributes.
  Attribute changes are queued during combat and replayed on regen, and the
  button never overrides `OnClick` (doing so silently kills a secure button's
  action dispatch).

## [0.73.0] - 2026-08-30
### Added
- **Auto accept and auto turn-in for the route quests.** Walk to the NPC, open
  their dialog, and the quest accepts and hands in by itself — including through
  gossip menus and multi-quest greetings. Deliberately narrow: it fires **only
  for the three quests in the route**, only inside a window you opened, and never
  moves or targets anything. `/pp route auto` toggles it; the panel header shows
  `[auto OFF]` when it's off.
  - A quest with a genuine **choice of rewards is left alone** — picking wrong
    isn't undoable, and none of the route quests should have one, so it's a
    signal that this server's version differs from the route's.
  - Gossip quest lists are matched by **counting strings** rather than assuming
    a vararg stride, since that stride has differed between 3.3.5 builds.
- **Guide line** under the button spelling out what to do next — who to talk to,
  where they are, and their coordinates once learned.
- **The arrow points itself.** Entering the zone for a quest step sets
  CallboardHunter's arrow at the learned giver/turn-in with no click. Only ever
  clears an arrow it set, so callboard routing isn't stomped.

### Changed
- **Compact panel is now exactly one button.** The port bar and the
  Back/Done/Skip/All-steps row are gone; those live on `/pp route back`,
  `/pp route cp <id>`, and `/pp route full`.
- **Dropped the ash-tree refill step** and its button. The route starts at the
  Hardcore swap now, so a fresh run opens straight onto the levelling leg.

### Fixed
- `Back` couldn't undo a port step while you were standing in that zone — it
  re-satisfied instantly and the click looked dead. It now suppresses that step
  until you leave the zone, and says so plainly when a step genuinely can't be
  stepped back onto.

## [0.72.0] - 2026-08-30
### Added
- **One-button compact panel, now the default view for `/pp route`.** A single
  large button that always does the next thing — ports you, arrows you at the
  quest, glows the next ash node, or confirms a Hardcore swap — with the step
  counter, the current step's note, and what's coming next. `All steps` opens
  the full thirteen-row checklist; `Compact` goes back. `/pp route mini` and
  `/pp route full` do the same from chat.
- **Port bar** — Dalaran / Zul'Drak / Unu'pe buttons on the compact panel, so
  you can jump anywhere on the route regardless of which step you're on. Locked
  checkpoints are marked `[!]` (letters, not colour).
- **`Back` / `/pp route back`** — undoes the last step for the mis-click, clearing
  both the latch and the underlying record so it doesn't instantly re-complete.
- Compact panel re-renders on a 1s tick, so arriving somewhere updates the button
  even when no event fires. The tick scans the quest log **read-only** — it never
  expands or re-collapses headers, which would otherwise make the quest log visibly
  jump once a second.

### Fixed
- `/pp route` said nothing at all if `PrestigeRoute.lua` hadn't loaded (`safeCall`
  swallows a nil function). It now tells you a full client restart is needed —
  a `/reload` does not pick up a newly added file.
- `/pp route` and `/pp ash` were missing from the `/pp` help line.

## [0.71.0] - 2026-08-30
### Added
- **Prestige route runner (`/pp route`)** — a guided runner for the community
  fast-prestige route, focused on the levelling leg: Hardcore 5 → Dalaran →
  the three-quest chain → Zul'Drak, which lands a fresh run around 64. The panel
  works out which step you are on from live state (quest log, zone, level, run
  ash) rather than making you keep a cursor, and survives `/reload`, doing steps
  by hand, or doing them out of order. A new run resets the lap automatically.
  - One-click checkpoint travel (Dalaran 310, Zul'Drak 304, Borean Tundra 296)
    via the server's own `REQUEST_USE_CHECKPOINT`, falling back to
    CallboardHunter's map port, then to printing the macro.
  - **Checkpoint ids are verified, not trusted.** Opening the world map harvests
    every checkpoint button's id/name/unlocked state, so the panel can say
    "310: Dalaran, unlocked" — and flags `NAME MISMATCH` if the server ever
    renumbers one. `/pp route checkpoints` lists everything harvested.
  - The Zul'Drak step **blocks itself** when checkpoint 304 reads locked, naming
    the missing Argent Stand flight path instead of failing at the port.
  - Quest giver and turn-in locations are **learned** the first time you run the
    chain, so later laps can point CallboardHunter's arrow at them. Each quest
    row shows what it was worth last lap (`last lap 41->58`).
  - `/pp route api` probes what this client actually exposes;
    `/pp route macro` prints the raw checkpoint macros.
  - Self-Execution sits on a secure button that is **disarmed by default** —
    arming is a separate deliberate click, because it ends the run for good.
  - Quest titles are matched apostrophe-insensitively (straight `'` vs curly `’`)
    and case-insensitively. Two of the three route quests contain an apostrophe
    and this server mixes both forms in its own data, so a raw compare would have
    parked the route on one step with nothing to explain why.
- **Offline test harness** (`tools/`) — the route state machine now runs head-first
  against a stubbed WoW API on a Lua VM (fengari), so route changes are testable
  without logging in. 29 checks, `npm install && node run_lua.js route_test.lua`;
  see `tools/README.md`.

### Notes
- Still an advisor: it reads state and draws the next step. Every action is your
  own click. Hardcore tier swaps have no client API, so those steps are guided
  and ticked off by hand rather than detected.

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
