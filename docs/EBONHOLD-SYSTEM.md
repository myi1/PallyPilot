# Project Ebonhold — Rogue-Lite Systems Reference

**Living document.** Keep this updated as patches land and in-game findings accumulate.
Character context: **keepsy** (also Keepc, Keepsi), solo Retribution Paladin, realm `Rogue-Lite (Live)`, WoW 3.3.5a client with server-side custom UI shipped in the MPQ patches (`E:\Games\Ebonhold\Data\patch-4/5/6.MPQ`). **These ARE extractable** — `mpyq` unpacks them, and `patch-4.MPQ` yielded `Interface/AddOns/ProjectEbonhold/` including the extraction module, which settled the affix questions in §5. Earlier revisions of this doc assumed they were opaque and inferred the client API from its consumers; prefer the real source now.

**Last full revision:** 2026-08-25.
**Section 5 (item affixes) substantially corrected 2026-09-04** — the old stacking
rule was wrong in a way that produced actively harmful gearing advice. See §5.2.

## Source legend (used in citations throughout)

| Key | Source |
|---|---|
| `EBH:<file>` | `E:\Games\Ebonhold\Interface\AddOns\EbonholdHub\modules\<file>` — community addon by Gangek (read-only reference; never copy its code) |
| `PP:<file>` | `E:\Games\Ebonhold\Interface\AddOns\PallyPilot\<file>` — our own addon |
| `CBH` | `E:\Games\Ebonhold\Interface\AddOns\CallboardHunter\` (ours) |
| `SV:PE` | `E:\Games\Ebonhold\WTF\Account\KEEPSY\SavedVariables\ProjectEbonhold.lua` (server addon's saved state) |
| `SV:EBH` | `...\SavedVariables\EbonholdHub.lua` (1.8 MB; includes 17 recorded run sessions with 1,301 logged draw actions) |
| `SV:PP` | `...\SavedVariables\PallyPilot.lua` (includes a full `/pp perkscan` dump of the server's PerkDatabase — 546 perks with all fields — and one fully logged run) |
| `dump:effects` | scratchpad `echo-effects.txt` — all 546 echo tooltips extracted via SetHyperlink, raw `@…@` scaling tokens intact |
| `dump:perks` | scratchpad `perk-table.txt` — 323 distinct echo names with paladin-usability, family, minLevel |
| `codex` | scratchpad `solo-paladin-codex.html` — our synthesis of the official player guide, Nero's #paladin Discord build doc, and top EbonholdHub builds |
| `in-game` | keepsy's direct observation, not yet verified in any file |

---

## 1. The core loop (run lifecycle)

> Run → stack Echoes on the way to 80 → die → bank Soul Ash into the permanent tree → come back stronger. (`codex`)

1. **Start at level 1.** Every new run begins at level 1 regardless of previous progress.
2. **Catch-up leveling is near-instant at the front.** Measured run (keepsy, 2026-08-25, `SV:PP` run log): level 1 → 39 in **7 seconds** standing in Stormwind, 50 at 0:23, 57 at 1:17 (Western Plaguelands), 70 at 6:34 (Borean Tundra), **80 at 8:42** (Icecrown). Full run ≈ **9 minutes** (`PP:RunLog.lua` prints minutes at 80; the logged run reported 9). End-of-run stats that day: 111k HP, 51k AP, ~75% crit (buffed).
3. **Every level-up opens an echo draw window** (3 choices — see §2). Catch-up bursts fire one `PLAYER_LEVEL_UP` per level and queue draws; a full run produces on the order of **60–80 picks** (17 sessions in `SV:EBH` average ~60 Select actions each).
4. **Dying ends the run.** On death you choose (`codex`):
   - **Accept** — bank the entire run's Soul Ash into the account-wide Soul Ash Tree, run over; or
   - **Pay 10%** of the run's Soul Ash to resurrect and continue the same run (the "pay-to-continue" economy — always keep enough banked that this is affordable mid-raid). **HARDCORE EXCEPTION (field-confirmed, keepsy 2026-08-25): in Hardcore there is NO pay-to-continue option — death is final, the run ends, ash banks.**
   - Deliberate run-ending is normal play: a cliff, a mob, or the **Self-Execution** ability in the *Ebonhold Abilities* tab (`codex`).
5. **What resets on death:** all run echoes (the granted/stacked set from that run's draws), level, run Soul Ash (if accepted).
6. **What persists across runs:**
   - **Locked (permanent) echoes** — up to `GetMaximumPermanentEchoes()` slots (see §2.6).
   - **Tome-learned echo ownership** — echoes learned from Tomes live in the spellbook's **"Echoes" tab** and survive death (`EBH:weights/EchoOwnership.lua` scans that tab; `SV:PE` `echoDiscovery` lists 73 discovered echo spellIDs for Keepsy).
   - **The Soul Ash Tree**, learned **item affixes** (account-wide), achievements/multipliers, gold, gear, professions, Orbs of Lost Memories.
7. Run state is exposed to addons via `ProjectEbonhold.PlayerRunService.GetCurrentData()` / global `EbonholdPlayerRunData` with fields `soulPoints` (run Soul Ash), `remainingBanishes`, `totalRerolls`, `usedRerolls`, `totalFreezes`, `usedFreezes` (`EBH:automation/Automation.lua`, `EBH:session/Session.lua`).

---

## 2. Echoes (the perk system)

### 2.1 What an echo is, technically

- Echoes are server-granted passive spells, spell IDs **200000–201428** (546 perk entries in `ProjectEbonhold.PerkDatabase`; consumers treat the ID range as 200000–299999) (`SV:PP` perkscan; `EBH:weights/EchoOwnership.lua`).
- The 546 entries collapse to **323 distinct echo names** (multi-quality variants and per-class variants share a name); **242 are paladin-usable** (`dump:perks`, `PP:BuildData.lua`).
- `PerkDatabase[spellId]` schema (`SV:PP` perkscan, all 546 verified):

| Field | Meaning | Observed values |
|---|---|---|
| `comment` | "Name - Quality" display string | e.g. `Immolation Aura - Common` |
| `quality` | 0–4 quality index | 0×112, 1×136, 2×186, 3×112, **4×0** (see §2.3) |
| `maxStack` | max rank via repeat picks | 80×333, 1×196, 5×7, 10×4, 15×2, 20×4 |
| `groupId` | groups quality variants of one echo | e.g. Immolation Aura group 50 |
| `classMask` | class-usability bitmask | WARRIOR 1, PALADIN 2, HUNTER 4, ROGUE 8, PRIEST 16, DK 32, SHAMAN 64, MAGE 128, WARLOCK 256, DRUID 1024; 1535 = all |
| `families` | role tags used by the draw UI | Tank / Survivability / Healer / Caster DPS / Melee DPS / Ranged DPS (`EBH:build/Scoring.lua`) |
| `minLevel` | level gate | 1 for 542 perks; 10 (Entropic Fusion), 20 (Cavalry Instincts ×3) (`dump:perks`) |
| `requiredSpell` | tome spell that unlocks it; 0 = base pool | 351 perks need no tome; 195 are tome-gated; tome spellID = **perk spellID + 100000** (`EBH:weights/EchoOwnership.lua`) |

- Tooltip text uses raw scaling tokens the client substitutes at display time: `@flat10+lvl0.2@`, `@sp0.4+ap0.2@`, `@armor0.01@`, `@stamina0.1@`, `@critRating0.0066@`, and capped forms like `@armor0.05LOWERintellect1.5@` (= 5% of Armor, capped at 150% of Intellect) (`dump:effects`).

### 2.2 Draw windows (the level-up choice)

- Each draw offers **3 choices** (`ProjectEbonhold.PerkService.GetCurrentChoice()` returns a list of `{spellId, quality, isRepeat, isFrozen, isCarried}`; server UI is `ProjectEbonhold.PerkUI` with `Show(choices)` / `UpdateSinglePerk` / `Hide`) (`EBH:automation/Automation.lua`).
- **A pick is final** — the in-game tooltip says choices are final (`in-game`; consistent with the addon never attempting to undo a Select).
- Three run-limited manipulation actions, driven via `PerkService`:
  - **Banish** (`BanishPerk(index)`) — permanently removes that echo from this run's draw pool. Server setting `perkDirectBanish` exists (`SV:PE`).
  - **Reroll** (`RequestReroll()`) — replaces the whole 3-choice offer.
  - **Freeze** (`FreezePerk(index)`) — holds a choice so it is **carried** into the next draw window (`isFrozen`/`isCarried` flags; a frozen echo re-appears next window).
- **Per-run charge budget (measured, `SV:EBH` session logs):** a fresh run starts with **9 banishes, 9 rerolls, 5 freezes**; they deplete over the run and do not visibly refill (by the 60s most runs sit at 0 ban / 0 reroll / 0–2 freeze). Exposed live via `PlayerRunService` fields above.
- **Repeats:** an already-owned echo can be offered again flagged `isRepeat`; picking it **ranks it up** (stack +1, up to `maxStack`). Repeat picks are sent as `SelectPerk(index)` instead of `SelectPerk(spellId)` (`EBH:automation/Automation.lua`).
- Granted run echoes are readable at `ProjectEbonhold.Perks.grantedPerks` (name → array of `{spellId, quality, stack, maxStack}`) and via `PerkService.GetGrantedPerks([unit])`; locked ones at `Perks.lockedPerks` / `GetLockedPerks()` (`EBH:weights/EchoOwnership.lua`).
- Server QoL toggles in `SV:PE` settings: `echoesVisibleOnLevelUp`, `noRerollConfirm`, `rerollAutoRepopulate`, `autoAcceptLoadoutEchoes`, `perkShowSelectCount`, `hideOrbAlert`, `hideNewEchoAlert`, `hideTomeLearnedAlert`.

### 2.3 Quality tiers and coefficient scaling

Quality indices and labels (`EBH:analysis/EchoAnalyzer.lua`, `EBH:ui/SettingsView.lua`):

| Index | Label | Populated? | Typical shape |
|---|---|---|---|
| 0 | Common | 112 perks | base pool multi-variant echoes |
| 1 | Uncommon | 136 perks | ≈ **×1.5–×2** the Common coefficients |
| 2 | Rare | 186 perks | ≈ **×10** the Common coefficients (procs) / ×3 flat (stats) |
| 3 | Epic | 112 perks | single-variant boss-themed uniques, `maxStack 1`, tome-gated |
| 4 | Legendary | **0 perks currently** | defined in every label table (color `ff8000`) but no perk in the live DB has quality 4 (`SV:PP` perkscan) |

**"Artifact" quality does not exist anywhere in the data** — not in the Hub, the perkscan, or the tooltips. If an Artifact tier appears in-game it is new; verify and update this table.

Verified scaling examples (`dump:effects` + `SV:PP` quality fields):

| Echo | Common (q0) | Uncommon (q1) | Rare (q2) |
|---|---|---|---|
| Immolation Aura (AoE pulse) | `sp0.02+ap0.01` | `sp0.04+ap0.02` | `sp0.2+ap0.1` |
| Scorching Wounds (DoT) | `sp0.06` | `sp0.12` | `sp0.6` |
| Reap the Weak (proc nuke) | `sp0.04` | `sp0.08` | `sp0.4` |
| Spiteful Shard (retaliation) | `sp0.05+ap0.025` | `sp0.1+ap0.05` | `sp0.5+ap0.25` |
| Strength Training (flat stat) | `10 + 0.2/lvl` | `15 + 0.3/lvl` | `30 + 1.5/lvl` |
| Keen Aim (rating) | `5 + 0.15/lvl` | `8 + 0.24/lvl` | `15 + 1.06/lvl` |

Rule of thumb: **Rare = 10× Common for proc coefficients, ~3× for flat stats.** Quality is a much bigger lever than one extra rank.

Epic (q3) singletons are raid-boss-themed with fixed large numbers in the tooltip (Naxx wing bosses at 200583–200639, Ulduar/ToC/ICC themes at 201300–201428: Crypt Lord's Swarm, Edict of the Four, Defile, Necrotic Plague, Frostmourne Hungers, etc.) (`dump:effects`).

### 2.4 Ranks / stacking

- Repeat picks add stacks: most multi-variant echoes have **`maxStack = 80`** (333 of 546); Epic uniques have `maxStack = 1` (196 entries incl. some Rare uniques); a handful sit at 5/10/15/20 (e.g. Opening Split 5, Double Tap 10, Enhanced Recovery 15, Steady Channeling 20) (`SV:PP` perkscan).
- Stack counts per echo are visible in `grantedPerks[name][i].stack` and cached account-side in `ProjectEbonholdDB.cachedPerkCounts` (name → count) (`EBH:weights/EchoOwnership.lua`).

### 2.5 Active-echo cap and breadth vs depth economics

- **Active-echo cap ≈ 72 (field estimate, unverified server-side)** — at some point the run can hold no more unique echoes and repeats become the only progression (`PP:HubSync.lua` comment; treat the exact number as to-verify).
- **Adaptive Power** (Epic, tome-gated, spellID 200960): "+1% damage for each **unique** Echo you have active. Additional ranks or qualities of the same Echo do not increase this bonus." (`dump:effects` #358).
- **Measured field lesson (keepsy, 2026-08-25):** 71 uniques beat 34 uniques with deeper ranks — breadth is itself a damage multiplier while Adaptive Power is active. PallyPilot therefore pushes "breadth mode" (cap every echo at 1 copy) until the active cap is reached, then "depth mode" (S uncapped, A to 5) (`PP:HubSync.lua`).
- **Resonant Build** (Epic, 200962): "+15% damage while at least **3 different Base Stat Echo types** are active (Strength, Agility, Intellect, Spirit, or Stamina)" — the reason a junk-looking Agility Boost can be a real pick (`dump:effects` #359, `PP:BuildData.lua`).

### 2.6 Locked (permanent) echoes

- Server API: `ProjectEbonhold.PerkService.GetMaximumPermanentEchoes()` (fallback `Perks.maximumPermanentEchoes`); EbonholdHub defaults to **6 slots** when the API is unavailable (`EBH:build/Build.lua` `LOCKED_SLOTS_DEFAULT = 6`).
- The Soul Ash Tree's **25,000,000** milestone is documented as unlocking "all 5 echo lock slots" (`codex`), and keepsy currently runs **5 slots** (`PP:Core.lua` default `lockSlots = 5`; `EBH:weights/EchoOwnership.lua` fingerprints exactly 5 slots). Whether/how a 6th slot unlocks (prestige? later milestone?) is **unverified** — see §10.
- Locked echoes survive death and are never part of the reroll/banish economy. PallyPilot's locked six: Sanguine Bulwark, Twilight Equilibrium, Constellations, Pandemic, Adaptive Power, Exposed Heart (`PP:BuildData.lua`).

### 2.7 Synergy webs (school-trigger chains)

The catalog is built around **schools feeding triggers**. EbonholdHub models this as a tag graph (`EBH:data/SynergyData.lua` `EchoTags`: each echo has `tags` and `synergiesWith`), and its analyzer also derives tags from tooltip keywords ("burn"→fire, "chance to"→proc, etc., `EBH:analysis/EchoAnalyzer.lua`). The real in-game chains this represents:

- **Generators** deal school-tagged damage: Immolation Aura / Scorched Path (fire), Permafrost Aura (frost), Toxic Phials (poison/nature), Static Overflow (nature), Hungering Curse (shadow)…
- **Accumulators** count that school's hits: Cinders of the Sanctum (12 Fire stacks → Fire Cyclone), Chill of the Bone Wyrm (12 Frost → Frost Breath), Widow's Venom (12 Nature → Poison Bolt Volley), Curse of the Plaguebringer (12 Shadow → spreading curse), Storm of the Spellweaver (10 Arcane → missiles), Brittle Forging (10 Heat → Shatter) (`dump:effects`).
- **Cross-school combos**: Frostfire Paradox (Frost stacks shattered by Fire), Twilight Equilibrium (alternate Holy/Fire/Nature vs Shadow/Frost/Arcane essences), Entropic Fusion (Fire+Shadow within 3s), Archmage's Mark (Fire+Frost+Arcane within 6s), Twilight Combustion (Fire DoT + Shadow DoT → Twilight Rift).
- **DoT engine**: Pandemic (death-spread), Contagion (cross-class DoT procs), Echoing Afflictions/Echoing Tides (extra ticks), Accelerated Decay (DoTs gain haste), Overtime Conversion (detonate on kill), Necrotic Plague (jumping mega-DoT). Paladin relevance: Seal of Vengeance's Holy Vengeance is a stacking DoT, so the whole DoT web multiplies it (`PP:BuildData.lua`).
- A fire generator (any source, even an off-school aura) turns every fire accumulator live — this is why B-rated school echoes become synergy picks when the build already carries that school (`PP:BuildData.lua` comments).

Class gating on top of the web: `classMask` hard-gates variants; `SynergyData.ClassExclusiveEchoes` (Hazard/Surge families are one-class each: Sanctified Hazard & Crusader's Surge = paladin) and per-class F-list blacklists (rage/runic echoes are dead for mana classes, etc.) (`EBH:data/SynergyData.lua`).

### 2.8 EbonholdHub's auto-pick engine (how draws get played for us)

Not a server system, but it defines how keepsy's draws are actually resolved (`EBH:automation/Automation.lua`):

- Scores each choice: tier base S=100/A=70/B=40/C=20/F=0, + quality bonus (q0/1/2/3/4 → 0/5/10/20/30), + tier-list position bonus (up to +10), bundle-combo boost +40; repeats score half their base tier; frozen/carried choices ×0.9.
- **Aggression levels 1–5** gate behavior: banish tiers ({F} at 1–3, {F,C} at 4–5), reroll-below-tier (none/none/C/B/A), freeze enabled from 3+. Per-pick-window reroll budget 2/3/5 by level, additionally capped at remaining-rerolls/3. First 5 picks of a run run one aggression level lower (ramp).
- Order of operations per window: banish F → reroll if best offer is at/below threshold (unless a desired echo or a high-synergy C is present) → banish duplicates/C as reroll substitute → freeze the runner-up when two A/S-grade offers appear → select best.
- All-repeat offers trigger a reroll if any remain; otherwise pick the best repeat. Locked-echo offers override everything.
- Every offer and action is logged to `SV:EBH` `sessions[].logs` (1,301 actions recorded to date) and `offerLog`.

---

## 3. Orbs of Lost Memories (targeted reroll currency)

- **Flow** (`PP:EchoFlow.lua`, driving the real server frames): open the Echoes journal (`ProjectEbonholdEchoJournal`, micro button `EchoJournalMicroButton`) → click the **orb bubble** (`EbonholdOrbBubble`) → click a **run-echo tile** (only *current-run* echoes are eligible — locked and tome-owned ones are not offered) → a **Forget dialog** opens with a **slider for how many orbs to spend** and a Forget button → Forget removes that echo (one stack) and immediately opens a fresh 3-choice draw window.
- **Spending more orbs on one Forget raises the odds the replacement offer is higher quality** — the slider shows "chance of a higher quality +N%" and ranges 1–100 (`in-game`; `codex` phrases it "stacking multiple Orbs on one draw raises the odds … the same way Luck does" — note the implied **Luck** stat, unverified). PallyPilot's engine caps its own per-forget spend setting at 25 (`PP:EchoFlow.lua`).
- **Economics / sources** (`codex`): Maerys the Ashen Archivist's **callboard dailies** (the main faucet — the whole CallboardHunter addon exists to grind these), weekly boss quests, Random Dungeon Finder (1 per run, scaled by Hardcore tier), ICC Lich King (up to 5×).
- Use: delete forced B/C-tier picks and refish for S-tier; PallyPilot's "Reroll junk" engine batch-processes the whole junk queue, pausing in combat, and stops after a 5-junk streak (`PP:EchoFlow.lua`).

---

## 4. Tomes (permanent echo learning)

- **195 of 546 perks are tome-gated** (`requiredSpell ≠ 0`); the tome's spellID is always **perk spellID + 100000** (300xxx range). Learning the tome puts it in the spellbook's **"Echoes" tab** and permanently adds that echo (at that quality) to your draw pool across all future runs (`EBH:weights/EchoOwnership.lua`, `SV:PP` perkscan).
- Tome items drop in the world with varied name prefixes: **Tome of / Codex of / Scroll of / Manual of / Grimoire of / Libram of / Tablet of** `<Echo Name>` (`EBH:weights/EchoOwnership.lua` PREFIXES).
- **Quality variants are separate tomes** — the same echo name exists as separate Rare/Epic tomes; names may carry a " - Quality" suffix (`EBH:build/Scoring.lua` suffix strippers; `EBH:ui/EchoMapView.lua`).
- Discovery is tracked account-side: `ProjectEbonholdDB.echoDiscovery["<realm>\t<char>"]` (Keepsy: 73 spellIDs) and `PerkService.GetDiscoveredEchoes()` (`SV:PE`, `EBH:weights/EchoOwnership.lua`).
- **Farm locations** — `EBH:data/EchoMapData.lua` mirrors the community map (**https://worldofechoes.pages.dev**): `Locations` keyed by continent (`eastern-kingdoms`, `kalimdor`, `outland`, `northrend`), **173 pinned tome spots** (106 rare, 67 epic), each entry `{tomeId, name, quality, description, x, y, placeName, mobs, notes}`. Notes distinguish Open World / Dungeon / Raid sources; a few are marked "to be confirmed" or "extremely common, cheap on the AH".
- **The Reaper**: holding **Intensity 5 for 10 straight minutes** spawns the Reaper, a hard fight that drops Tomes ("permanently boost you") (`codex`; 3 map notes in `EBH:data/EchoMapData.lua` repeat this).
- Epic-tier boss echoes are farmed from their thematic raid bosses (e.g. Stone Shatter from Kologarn/Ulduar, Twilight Equilibrium from Fjola/ToC) (`EBH:data/EchoMapData.lua`).
- **Loadouts**: the Echo Journal has My Echoes / All Echoes / **Loadouts** tabs (`SV:PP` echoUI scan). Loadouts export as `EBH1:` / `EWL1:` strings; EbonholdHub auto-imports them as builds (`EBH:integration/JournalLoadoutHook.lua`, `EBH:weights/EchoLoadoutCodec.lua`). Server setting `autoAcceptLoadoutEchoes` exists (`SV:PE`) — exact in-game loadout mechanics (cost? applies at run start?) unverified.

---

## 5. Item affixes ("of Ironhide III")

The crafting/enchant layer: extract affixes from drops at the **Enchanted Anvil in Dalaran**, pay a fee, learn them **account-wide**, then stamp them onto gear (`codex`).

### 5.1 Structure (`EBH:data/AffixData.lua`, `EBH:data/AffixCatalog.lua` — live ExtractionService dump 2026-07-10, 66 affixes)

- **25 armor affixes with ranks I–VI** (`MAX_RANK = 6`). Item names read `<Item> of <Affix> <Roman>`; item tooltips carry a dedicated line tagged **`@affix@`** describing the effect (`PP:GearAudit.lua`).
- **41 weapon affixes, rank-less** (`weapon = true`): named after famous weapons/effects — Thunderfury, Sulfuras, Azzinoth, Val'anyr, Shahram, Vampirism, Execution, Flurry, Vulnerability, Judgement, etc.
- Affixes are implemented as **item enchant IDs**: ranks I–IV in 900925–901034, rank V in 102200–102226, rank VI in 102257–102282, weapon affixes in 700078–700130 (`EBH:data/AffixData.lua` `IsAffixEnchantId`). They ride the item link like an enchant, so addons parse them straight off the link.
- Server-side surfaces: `_G.ExtractionService.learnedAffixes` (`{name, id, difficulty=rank, weaponOnly, icon}`) and the affix book UI `_G.EbonholdAffixBookPanel`.
- The affix book's green **"(xN)"** is the **applied** count — how many items currently carry that affix — **not** a count of copies you hold. `patch-4.MPQ` `extraction.lua` renders it from the wire field `appliedCount` and its tooltip reads `"Applied: N time(s)"`. Corroborated by the *Project Ebonhold Enhanced* v37.2 changelog: *"Affix Book tooltips now count currently equipped items instead of showing the server's application total."* There is no copies-held concept — see §5.5.
- 19 stampable slots — all equipment including Shirt and Tabard (`EBH:data/AffixData.lua` SLOTS). ⚠️ A player counted **18** usable in practice (Kraffer, #rogue "Bear Solo", 2026-07-10: *"didnt u write up 19 affixes but we can only equip 18?"*) — unresolved, possibly Ranged. Count it in-game before relying on 19.

### 5.2 Stacking rules (VERIFIED 2026-09-04 — Discord + the server's own client code)

- **The same affix at the SAME rank does not stack.** Two items both carrying
  Fortified by Pain V give you the benefit of **one**. The duplicate is dead
  weight.
- **The same affix at DIFFERENT ranks does stack.** The target is a **ladder**:
  VI + V + IV + III across separate slots. This applies to *every* affix —
  there is no "unique" subset.
  - Source: Discord #players-forum, "Question about affixes" (2026-08-28).
    Rinzler: *"If you stack let's say a 'Fortified by Pain V' with another one,
    you will only get the benefits of one. 'Stacking' them efficiently would be
    getting VI, V, IV, III, etc"*. FernagioxXx: *"Its the same for every
    affixes, only different tiers can stack"*.
  - Corroborated by Rellex's 600M mage guide writing affixes as ranges
    ("Pain 3-6", "Relentless 4-6") — one item per rung.
- **`maxLearnedCount` is NOT a cap and must never be read as one.** It is a
  stale snapshot of `appliedCount` — how many items *this account* had that
  affix stamped on when EbonholdHub's catalog was generated (2026-07-10).
  - The server's own client addon (`ProjectEbonhold/modules/extraction/`,
    extracted from `Data/patch-4.MPQ`) documents the wire format for
    `SEND_LEARNED_AFFIXES`: `spellId:applyCost:appliedCount:difficulty:weaponOnly:learned`.
    **There is no cap field in the protocol at all.**
  - `extraction.lua` renders that number as the green `(xN)` in the affix book
    and its tooltip reads `"Applied: N time(s)"`.
  - It is a strict subset of `learned = true`, and none of the 41 weapon
    affixes carry it — a design rule cannot come into being because one player
    learned something.
  - **The previous version of this section had it backwards**, and contradicted
    itself in consecutive lines by calling Ironhide unique and then using
    Ironhide as the spread-across-slots example. `BuildData.lua` ships
    `Ironhide 6/5/4` and `Fortified by Pain 6/5/4` — both allegedly "capped
    at 1" — while `Thick Hide` (allegedly "allows 3") runs a single rank.
- **Weapon affixes stack across hands** — dual-wield carries the same affix twice.
- Profession enchants and affixes **stack on the same item**.
- Hardcore tiers add **predefined affix tiers** as bonus power (see §8).

### 5.3 The 25 ranked armor affixes (names + one-line effects, `EBH:data/AffixCatalog.lua` descriptions)

Arcane Mind (Int), Armor Rend (armor shred on hit), Bulwark (block), Cold (Frost dmg), Feral Grace (Agi), Fortified by Pain (stacking DR when hit), Frost Breath (slow proc), Frozen Pulse (AoE frost pulse), Infinite Star (bouncing arcane star), Iron Will (Stam), Ironhide (Armor/%HP), Keen Strikes (melee/ranged crit), Living Tide (healing), Mender's Surge (heal proc), Overwhelming Force (AP), Pet Power, Quick Instincts (haste), Relentless Crits (crit rating), Shield Block, Spell Mastery (spell dmg/heal — ranks I–IV only), Spirit Surge (Spi), Stalwart (flat DR%), Temporal Flux (haste), Thick Hide (armor, ×3), Wellspring (mana regen).

### 5.4 Paladin schools (our curated loadouts, `PP:BuildData.lua`)

- **Survival-first (AotC I phase):** Ironhide (Head/Shoulder/Legs/Ring/Ranged), Iron Will (Chest/Shirt/Wrist/Feet), Fortified by Pain (Hands/Waist/Ring/Off-hand), Overwhelming Force (Neck/Back/Tabard/Trinket).
- **Damage-max (Nero's HC4+ farm build):** Iron Will 6→2 chain, Ironhide 6/5/4, Thick Hide 6, Keen Strike 6/5, Crits 6, Pain 6/5/4, Spell Mastery 4, Force 6.
- **Judgement (weapon affix) is an echo trigger, not a damage source** — keep it for the proc, ignore its tooltip number (`PP:BuildData.lua`, #paladin Discord).

---

### 5.5 The extraction economy (VERIFIED 2026-09-04 — Discord + `patch-4.MPQ`)

How you actually acquire and spend affixes. Most of this was previously guessed.

- **Extraction DESTROYS the item.** `extraction.lua`: *"This will destroy the item and extract its affix."* Multiple players warn about it in caps, so it evidently catches people.
- **Extraction costs GOLD**, scaling incrementally, **reset every 3 days** (#announcements, "Thread", 2026-03-05, PTR notes). One live sighting: *"once you put it in anvil it says extract - 500g"* (Radu, #general, 2026-06-30).
- **Source items must be ilvl 200+** (Tempez, #general, 2026-04-06).
- **Learning is PERMANENT and ACCOUNT-WIDE, and infinitely reusable.** *"its permanent"* / *"affix book is acc wide"* / *"you do not delete anything from it"* (Reyz, DuckKnight, #general 2026-08-19). Stamping a learned affix onto gear consumes nothing.
- **Learning is boolean per (affix, rank)** — the Extract button is **disabled** when `alreadyLearned` (`extraction.lua:322`), so you cannot hold two copies even deliberately. The Grimoire *"always retains the highest version of an affix you have learned"* (official announcement).
- **Therefore: never farm duplicates.** Once a rank is known, further drops of that item are vendor/delete fodder. The community runs auto-sell addons for exactly this (*AutoDelete* v3.23: *"Duplicate missing affixes keep one and clear extras"*).
- **Rank availability is content-gated, not grindable at will**: armor affix ranks are RNG, **T5 drops in HC4 raids**, **T6 is exclusive to HC5 ICC**. Weapon affixes are tied to the specific weapon they are extracted from (Huggies the Exalted, #general, 2026-08-02).
- **No cross-patch restriction**: *"There are no restrictions on the 'patch' from which the item comes from… (only weapons affixes can only be used on weapons)"* (Argon, #ptr-chat, 2026-04-08).
- The anvil sits in **Dalaran next to the blacksmith hut**; untick **"Show Known Only"** / **"learned"** to see unlearned affixes.
- **Applying costs GOLD** — confirmed in-game by Yahya, 2026-09-04, and matching what live players say (Waffle Masta 2026-08-30; Shionne Gitzune 2026-07-01: *"lets you extract affixes from items and put it on others (for a gold cost)"*). The March 2026 PTR announcement said **Soul Ashes**; that either never shipped or was reverted. **Trust the live behaviour, not the PTR note** — both steps are gold.

## 6. Soul Ash and the permanent tree

- **Earned** by killing anything green/yellow/red during a run; **banked to the account-wide tree only on death-accept** (see §1). Run total is `EbonholdPlayerRunData.soulPoints` (`EBH:session/Session.lua`).
- **Intensity (I–V)**: an uptime-based combat meter; higher Intensity multiplies Soul Ash gain; Intensity V held 10 minutes spawns the Reaper (`codex`).
- **Multiplier achievements**: "Permanent Soul Ashes Multiplier" achievements from leveling (10→80), quests, exploration; **all-slots-epic (ilvl 213+) grants the "Epic" multiplier achievement (+5%)** (`codex`, mirrored in `PP:BuildData.lua` gear notes).
- **Tree shape** (`codex`): cheap at the front, steep later; **full cap 428,303,860 Soul Ash**. Notable nodes:
  - **25M milestone**: unlocks all 5 echo lock slots.
  - Three **infinite nodes**: Stamina; Attack/Spell Power (reads your higher stat); **Highest Attribute** (per-rank value ramps with investment up to +20/rank — deep buys compound).
  - **Cheat Death charges** and self-resurrection nodes.
  - **Cold Weather Flying & riding** — flagged **"Carry over Prestige"** (stay free after a prestige).
- **Raid ID reset**: `O` → Raid tab → **Clear IDs** costs Soul Ash and the cost **rises ×5 per reset** (must be out of group) (`codex`).
- Spend philosophy (solo): survival spine first — Stamina infinite, Cheat Death, self-res; offense second (`codex`).

---

## 7. Prestige

Confirmed to exist: `SV:PE` has `seenPrestigeTour2` / `seenPermanentNodeIntro` / `seenSkillTreeSpendWarning` flags, and tree nodes are labeled "Carry over Prestige" (`codex`) — implying prestige **resets the Soul Ash tree** in exchange for something, with flagged nodes exempt. **Everything else about Prestige (what it grants, thresholds, whether it touches echo locks/affixes) is unverified** — see §10.

---

## 8. Hardcore tiers and AotC

- **Ahead of the Curve I = kill Kel'Thuzad in Naxxramas 25** (solo). This **unlocks Hardcore 1** (`codex`, `PP:GuideData.lua` "AotC I. Divine Shield exists for exactly one thing here: Frost Blast").
- Switch modes from a starter zone, inn, or capital via the mode popup — slide to Hardcore 1 (`codex`).
- Hardcore effects: creatures hit harder; drops scale up — more gold, XP, Soul Ash, reagents, extra loot, and **predefined affix tiers** on drops. RDF orb rewards also scale with Hardcore (`codex`).
- Community ceiling data points: Nero's paladin logged ~170M damage on Lich King, calls **HC4 ICC 25H "easy"** and **HC5 Callboard raids soloable**; 1M+ DPS builds exist (`codex`). Presumably tiers continue upward (HC5+); progression between tiers unverified.
- Achievement ladder presumption: AotC II+ (later raid milestones) → higher Hardcore tiers — **unverified**, see §10.

---

## 9. World systems: Callboard, checkpoints, vendors

- **Objectives Board ("callboard")**: pick-a-card daily objectives (rare kills "Rare Kill in <Zone>", kill counts "<Name> slain: n/m", collections, dungeon/raid cards). Cards can be **Selected or Rerolled** at the board. Rewards are the Orb faucet (§3). Quest giver: **Maerys the Ashen Archivist** (`CBH:README.md`, `codex`).
- Server UI frames: `ObjectivesMainFrame` > `ObjectiveFrame1..3` (`CBH:README.md`).
- **Checkpoint fast-travel network**: unlocked checkpoints are clickable buttons on the world map (`ProjectEbonholdCheckpointTooltip` shows "Click to travel to this checkpoint." / "Not yet unlocked"); CallboardHunter one-click routes through them (`CBH:README.md`).
- **Enchanted Anvil** (affix extraction/stamping): Dalaran (`codex`).
- Client conveniences (`SV:PE` settings): auto-learn talents, auto-place spells, auto-equip items, auto-sell junk (with per-quality/type filters), custom nameplates, floating combat text — all server-addon features.

---

## 10. Gaps / unknowns — verify in-game

| # | Unknown | How to verify |
|---|---|---|
| 1 | **Active-echo cap exact value** (~72 per field estimate, `PP:HubSync.lua`) | Fill a run to the cap; note the count and what the UI says when full |
| 2 | **6th lock slot** — `GetMaximumPermanentEchoes()` live return vs the 5 unlocked at the 25M milestone; EbonholdHub defaults 6 | `/run print(ProjectEbonhold.PerkService.GetMaximumPermanentEchoes())`; inspect the Soul Ash tree for a 6th-slot node |
| 3 | **Legendary (q4) echoes** — labels/colors exist, zero perks populated. Is Legendary reachable (event? Reaper? orb upgrades)? "Artifact" tier: no evidence at all | Watch for any q4 drop; re-run `/pp perkscan` after patches and diff quality counts |
| 4 | **Orb slider exact math** — "chance of a higher quality +N%" per orb; cap at 100? Does the implied **Luck** stat exist elsewhere (gear? tree?)? | Screenshot the Forget dialog at several orb counts; grep new client patches for "Luck" |
| 5 | **Draw cadence precisely** — one window per level always? Windows queued during catch-up bursts? Extra windows from other sources? | Count windows across one clean run vs levels gained |
| 6 | **Prestige mechanics** — trigger, cost, what resets, what it grants, relation to the 6th lock slot | Open the Prestige tab and transcribe it; the tour flags (`seenPrestigeTour2`) mean there's an in-game tour to replay |
| 7 | **Soul Ash tree full node list** — only the codex highlights are recorded here | Transcribe the tree (screenshots per branch) |
| 8 | **Hardcore tier ladder** — does each AotC unlock the next HC tier? What exactly changes per tier (multipliers, affix tiers)? | Read the mode popup text at each unlock |
| 9 | **Reaper loot table** — which tomes, what quality | Kill it, log drops |
| 10 | **Intensity mechanics** — decay rules, gain multiplier per level | Watch the meter with a timer |
| 11 | **Freeze charge regen** — logs show freeze occasionally back at 1–2 late-run after hitting 0; new-run boundary or actual regen? | Watch `EbonholdPlayerRunData.usedFreezes/totalFreezes` across a run |
| 12 | **Loadouts tab** — does applying a loadout cost orbs / auto-grant echoes at run start (`autoAcceptLoadoutEchoes`)? | Use it once and note the flow |
| 13 | ~~Affix extraction fee scaling / does stamping consume the learned copy~~ **ANSWERED 2026-09-04**: stamping is infinite reuse and costs only copper (`applyCost`) — `RequestApplyAffix(spellId, bag, slot)` takes no reagent and decrements nothing. EXTRACTION is the destructive step ("This will destroy the item and extract its affix"), and the Extract button is disabled when `alreadyLearned`, so learning is boolean per (affix, rank). The only apply-time block is stamping an affix onto an item that already has it. | Settled from `patch-4.MPQ` client code |
| 14 | **perkPicksMade counter semantics** (`SV:PE`: Keepsy 94 — far fewer than lifetime picks) | Compare before/after one run |

---

## 11. Client API quick reference (for future tooling)

All under global `ProjectEbonhold` unless noted (`EBH:*` consumers, `SV:PP` scans):

- `PerkDatabase[spellId]` → `{comment, quality, maxStack, groupId, classMask, families, minLevel, requiredSpell}`
- `PerkService`: `GetCurrentChoice()`, `SelectPerk(spellIdOrIndex)`, `BanishPerk(i)`, `FreezePerk(i)`, `RequestReroll()`, `GetGrantedPerks([unit])`, `RequestGrantedPerks()`, `GetLockedPerks([unit])`, `GetDiscoveredEchoes()`, `GetMaximumPermanentEchoes()`, `GetRollsDebugInfo()`
- `Perks`: `grantedPerks`, `lockedPerks`, `maximumPermanentEchoes`
- `PlayerRunService.GetCurrentData()` / `_G.EbonholdPlayerRunData` — **full field list, live dump `in-game (2026-09-01)` via EbonScan**. This is the authoritative run-state source; everything the server's run HUD displays is here as a real number, so **no FontString scraping is needed**:

| Field | Observed | Meaning |
|---|---|---|
| `soulPoints` | 25840 | run Soul Ash |
| `soulPointsMax` | 100000000 | run cap |
| `soulPointsMultiplier` | 8.27 | **the `+827%` bonus-ash figure on the run HUD** |
| `catchupMultiplierPct` | 0 | **the "new player"/catch-up bonus, separately exposed** |
| `costNextReset` | 2584 | Soul Ash cost of the next raid-ID reset (§6) |
| `nbResetAvoided` | 0 | resets avoided |
| `countCanAvoidFatalAttacks` | 7 | Cheat Death charges |
| `countCanSelfRezs` / `countCanClassRezs` / `countCanAcceptedRezs` | 4 / 1 / 4 | resurrection charges |
| `totalFreezes` / `usedFreezes` | 8 / 7 | draw freezes |
| `totalRerolls` / `usedRerolls` | 16 / 14 | draw rerolls |
| `remainingBanishes` | 10 | draw banishes |
| `hasReachedMaxLevel` | true | run reached 80 |

### 11.1 Quest system (`in-game (2026-09-01)`, EbonScan)

- Ebonhold custom quests use IDs in the **600000–601999** range. Quest IDs ARE reachable: `GetQuestLink(index)` **exists on 3.3.5a** and returns `|Hquest:<id>:-1|h`. `GetQuestID` and `GetQuestLogIndexByID` do **not** exist.
- Custom quests are all filed under a quest-log header literally named **`"Missing header! (quest designers)"`** — a server bug. This is why the Objectives tracker renders them as one undifferentiated pile.
- **`isDaily = 1` is set on every repeatable ladder quest and does NOT mean daily** ("Complete 4 Prestiges" is flagged daily). It is a repeatable marker. **Cadence cannot be read from the API** — it must be observed.
- Quests come in **ladder families** sharing one title, each tier a separate quest ID with its **own independent counter**: *A Life, Lived Through* (601101/601102/601104/601109/601112 — 3/4/6/11/14 runs to 80), *One More Door* (601202/4/6/8 — 4/6/8/10 DF dungeons), *The Whole Board* (601003/601400/601401/601403 — 1/2/3/5 contracts of each type), *Everything, Given Up* (601300/601302 — 2/4 prestiges).
- Standard reward APIs return **zero** for these quests; the "Rewards by Difficulty" table is server-custom. `QuestInfoSoulPointsFrameIcon` / `QuestInfoSoulPointsFramePoints` are named globals and the likely route to per-quest ash rewards.
- Observed reward scaling is **linear in Hardcore tier**: `reward(tier) = base × (1 + 0.8846 × tier)`, with XP and ash sharing the ratio 0.88462 exactly (one quest sampled — confirm on a second before trusting).
- **Soul Ash is not a currency** (`GetCurrencyListInfo` returns stock emblems only), and the "Permanent Soul Ashes Multiplier" achievements are **not in the achievement API** — every category was walked, only substring false positives. Those multiplier components cannot be enumerated client-side.
- Frames: `EbonholdQuestTracker` (rows anonymous, pooled items named `EbonholdQTItem<N>`), `ProjectEbonholdIntensityButton`, `EbonholdGetSetting()`.
- `PerkUI` (`Show/UpdateSinglePerk/Hide` — hookable), `EchoJournal` (`OnDataChanged`)
- `_G.ExtractionService.learnedAffixes`; `_G.EbonholdAffixBookPanel.affixRows`
- Frames: `ProjectEbonholdEchoJournal` (+Tabs 1–3, SearchBox, FilterButton), `EchoJournalMicroButton`, `EbonholdOrbBubble`, Forget dialog (Button "Forget" + sibling Slider), `ObjectivesMainFrame`/`ObjectiveFrame1..3`, `ProjectEbonholdCheckpointTooltip`, `UtilsSpellTooltip`
- SavedVariables: `ProjectEbonholdDB` (`cachedPerkCounts`, `echoDiscovery`, `perkPicksMade`, `perkLastLevel`, settings), `EbonholdHubDB` (builds/sessions/offerLog/affixCatalog), `PallyPilotDB` (runs/fights/scans)

## 12. Community tooling map

- **EbonholdHub** (Gangek; read-only): build manager + tier lists + auto-pick automation (§2.8), echo map, affix planner, gear sets, talents, session history, public build catalog. Never copy its code; read its live globals.
- **PallyPilot** (ours): curated Ret build + full 546-tooltip-verified catalog rating (`BuildData.lua`), draw/reroll co-pilot, farm queue, raid guides, gear/affix audit, run logger, DPS meter, HubSync (pushes our ratings in as the active EBH build so EBH's engine executes them).
- **CallboardHunter** (ours, released): callboard grind loop — port/arrow/rare-detect/kill-learning.
- **worldofechoes.pages.dev**: community tome map (EchoMapData's upstream).

---

*Update discipline: when a Gaps item is resolved, move the fact into its section with an `in-game (date)` citation and delete the row. When a patch changes numbers (coefficients, budgets, affix IDs), re-run `/pp perkscan` + `/pp echotext` and diff against `SV:PP`.*
