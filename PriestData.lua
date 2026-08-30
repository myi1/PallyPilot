-- EbonPilot PriestData: the curated solo Shadow Priest guide for Ebonhold.
-- Mirrors BuildData.lua's shape and registers into the multi-class registry as
-- PP.Classes.PRIEST. Core re-points PP.Build to this table at login for a priest.
--
-- Sourcing note (honesty): the WotLK 3.3.5a backbone (spec/stats/talents/
-- rotation/gear) is researched + wowhead-verified. The ECHO ratings are
-- TRANSFERRED from keepsy's MEASURED paladin engine (BuildData.catalog) + WotLK
-- caster theory -- there is NO measured priest data (keepsy mains paladin). Treat
-- every echo tier here as a starting hypothesis; validate live with /pp bench +
-- /pp dps on a real priest. Automation is BANNED on Ebonhold (perma-ban) -- this
-- is an ADVISOR only: it never presses a key, casts, or buys.
local PP = PallyPilot
local B = {}
PP.Classes = PP.Classes or {}
PP.Classes.PRIEST = B              -- registered in the multi-class registry
-- NB: unlike BuildData.lua we do NOT set PP.Build = B here. BuildData (loaded
-- first) is the intentional pre-login default; Core re-points PP.Build to the
-- logged-in class at PLAYER_LOGIN, so a priest still gets this table.

B.title = "Solo Shadow Priest -- Hardcore climb (DoT caster; VT/DP/SW:P + Mind Flay)"
B.spec = "Shadow"

-- Stat priority. Base WotLK 3.3.5 Shadow is: Spell Hit (to cap) -> Spell Power
-- -> Haste -> Crit -> Spirit (Icy Veins; Almar's ranks SP > Crit > Haste --
-- close, gear-dependent). Ebonhold's affix + echo meta shifts this the SAME way
-- it shifted paladins: it floods Haste/Crit via affixes, so those climb -- but
-- for a CASTER the Spell Hit cap is an immovable FIRST gate (a missed cast/DoT
-- application is zero damage; melee had no such hard wall).
B.statPriority = { "Spell Hit (to cap)", "Haste", "Crit", "Spell Power" }
B.statNote = "Spell Hit to cap FIRST -- vs a raid boss you need 17% hit; Misery "
  .. "(3/3, -3%) + Shadow Focus (3/3, +3%) cover 6%, so gear/gems supply ~11% = "
  .. "about 289 hit rating (26.23 rating = 1%). Don't overstack past ~295. AFTER "
  .. "the cap, Ebonhold leans Haste + Crit (affix-fed, like the paladin meta): "
  .. "Haste speeds the Mind Flay channel + your casts, and with the Accelerated "
  .. "Decay echo it ALSO scales your DoT ticks -- a reversal of retail WotLK, "
  .. "where DoT ticks are fixed and haste never speeds them. Crit feeds Shadow "
  .. "Power, Glyph of Shadow procs, and the crit-gated echoes (Precision Strike, "
  .. "Unstable Infusion). Spell Power is your throughput backbone -- always "
  .. "valuable, mostly off base gear + Runed Cardinal Ruby gems -- so don't pass "
  .. "a big Haste/Crit affix piece just because its raw SP is lower."
-- Priests have no Expertise (that's a melee stat). The hit-cap detail above is
-- the caster equivalent of the paladin's expertise wall.

-- Gems + weapon enchant + the tier bonus that shapes the set (mirrors the
-- paladin B.enchants field).
B.enchants = "Gems: Runed Cardinal Ruby (+23 SP) in red; meta Chaotic Skyflare "
  .. "Diamond (+SP + 3% crit dmg); use Reckless Ametrine (SP/haste) and Purified "
  .. "Dreadstone (SP/spirit) only to hit socket bonuses or top off Hit. Weapon "
  .. "enchant: Mighty Spellpower (or Black Magic haste-proc). Keep 4pc T10 "
  .. "(Sanctified Crimson Acolyte) -- head+shoulder+chest+hands tier, non-tier legs."

-- "Seal" and "Blessing" are paladin field names the Dashboard renders literally;
-- for a priest they carry the always-on stance and the self-buffs (the Dashboard
-- goes class-aware in a later pass). Phrased so the fixed labels still read.
B.seal = "(your always-on stance) SHADOWFORM -- +15% Shadow damage and the gate "
  .. "for the whole shadow kit. Keep it up ALWAYS: casting any Holy spell (a heal) "
  .. "DROPS it, so heal only between pulls, then recast. Priests have no seal; "
  .. "Shadowform is the equivalent 'always on'."
B.sealWhy = "Shadowform is a flat +15% Shadow damage multiplier and unlocks "
  .. "Mind Flay / VT / VE. Dropping it mid-fight is a huge DPS + sustain loss."
B.blessing = "(self-buffs, no group blessings solo) Power Word: Fortitude (+Stam), "
  .. "Inner Fire (+SP & armor -- refresh when its charges run low), Shadow "
  .. "Protection, and toggle Vampiric Embrace ON before every pull for the self-heal."
B.blessingWhy = "Vampiric Embrace is your solo lifeline: it heals you for 25% "
  .. "(Improved VE 2/2) of your single-target Shadow damage. Inner Fire's SP is "
  .. "free throughput; Fortitude is raw EHP for the hardcore climb."

-- Single-target priority (Shadow is a priority list, not a fixed rotation). Keep
-- DoTs from clipping; fill every gap with Mind Flay.
B.rotation = "Pre-buff Vampiric Embrace. Open: Vampiric Touch (cast it first so it "
  .. "ticks) -> Devouring Plague (instant; also a 30% up-front hit + heal with "
  .. "Improved DP) -> Shadow Word: Pain (apply ONCE) -> Mind Blast -> Mind Flay "
  .. "filler. Maintain: keep VT and DP up (refresh on expiry, never early -- you "
  .. "waste a tick); NEVER recast SW:P -- every Mind Flay refreshes it via Pain "
  .. "and Suffering; Mind Blast on cooldown; Mind Flay fills gaps (don't clip its "
  .. "last tick). Shadow Word: Death is your move/execute filler ONLY -- it hits "
  .. "you back (backlash) if the target lives. Devouring Plague self-heals (up to "
  .. "40% of its damage with Improved VE) -- it's real solo sustain, not just DPS."
B.rotationAoe = "Farm/AoE: channel Mind Sear on a mob in the MIDDLE of the pack "
  .. "(it hits everything AROUND that mob, not the mob itself; Glyph of Mind Sear "
  .. "widens it). If a primary lives, keep SW:P/VT/DP on it while searing the rest. "
  .. "Mind Sear is MANA-HUNGRY and does NOT feed Vampiric Embrace (single-target "
  .. "only) -- lean on Shadowfiend/Dispersion when farming packs."
B.mana = "Mana (the real solo problem): (1) Vampiric Embrace up permanently = "
  .. "constant self-heal off your damage. (2) Shadowfiend on cooldown whenever you "
  .. "dip below ~60-70% mana -- returns 5% max mana per melee hit (Glyph of "
  .. "Shadowfiend adds +5% if it dies). (3) Dispersion when low OR about to eat a "
  .. "big hit -- 90% damage reduction AND ~36% of your mana back over its 6s "
  .. "channel (6%/s), off a ~2min CD (Glyph of Dispersion cuts it to ~1.25min). "
  .. "(4) VT's Replenishment + Meditation refill between pulls. Chained, a solo "
  .. "Shadow Priest almost never truly goes OOM."
B.talents = "14/0/57 Shadow (13/0/58 variant). 14 in Discipline only to reach "
  .. "Meditation (mana regen while casting) + Inner Focus; everything else Shadow, "
  .. "capstone Dispersion. Ebonhold grants far more than 71 points, so the template "
  .. "below is a generous 'take all the good stuff' list -- the applier fills what "
  .. "your points allow, lowest tiers first."

-- Echoes to lock so they persist across runs. ORDER = lock priority; only the
-- top N fit your unlocked lock slots (5 by default). TRANSFERRED from the paladin
-- engine + adapted for a native DoT caster -- validate live.
B.locked = {
  "Twilight Equilibrium",   -- the engine (school-flip). CAVEAT below.
  "Pandemic",               -- DoT extend/spread: BETTER on a native DoT caster
  "Adaptive Power",         -- +1% dmg per unique active echo; class-agnostic
  "Contagion",              -- DoT spreader; pairs with your multi-DoT kit
  "Sanguine Bulwark",       -- hardcore survival (class-agnostic)
  "Accelerated Decay",      -- gives your DoT ticks haste-scaling (see statNote)
  "Cinders of the Sanctum", -- measured #1 proc source on paladin (Fire Cyclone)
}
-- CAVEAT on Twilight Equilibrium: it stacks Light Essence on Holy/Fire/Nature and
-- dumps Darkburst on Shadow/Frost/Arcane. Your kit is ~mono-Shadow, so you only
-- feed the Shadow side -- run the fire/frost proc echoes (Cinders / Malleable Goo
-- / Slime Spray / Cyclone of Cold Bones / Inhaled Blight) to supply the other
-- school, or half the engine starves. That web is also your top raw damage.

-- Draw priority tiers. On a level-up selection (and Orb rerolls) take the highest
-- tier offered. These names are also FarmQueue targets. Curated for a caster.
B.tiers = {
  S = {
    "Twilight Equilibrium", "Pandemic", "Contagion", "Adaptive Power",
    "Accelerated Decay", "Sanguine Bulwark",
    -- the measured fire/frost/plague proc web (cross-class damage procs):
    "Cinders of the Sanctum", "Malleable Goo", "Slime Spray",
    "Cyclone of Cold Bones", "Inhaled Blight", "Necrotic Plague",
    "Curse of the Plaguebringer", "Echoing Tides",
    -- caster stat/tempo engines:
    "Precision Strike", "Temporal Pressure", "Twin Casting", "Spellweave",
    "Energy Overflow", "Storm Conductor", "Temporal Flow", "Chronoboost",
    "Resonant Build",
  },
  A = {
    "Echoing Affliction", "Hungering Curse", "Permafrost Aura", "Permeating Chill",
    "Frostfire Paradox", "Flame Beacon", "Leeching Swarm", "Peak Condition",
    "Scent of Blood", "Undead Bane", "Drained Reserves", "Static Overflow",
    "Sudden Insight", "The Last Wall", "Ruthless Exploiter", "The Unclean's Fever",
    "Arcane Cadence", "Reaper's Reprieve", "Sanctum Sentries",
  },
  B = {
    "Unstable Infusion", "Mana Infusion", "Bolstered Vitality", "Desperate Escape",
    "Battle Momentum", "Arcane Weapon", "Holy Brand", "Pain Drive",
  },
}

-- Full catalog: INHERIT the paladin catalog's breadth ratings (Adaptive Power
-- pays +1% per unique active echo -- that breadth meta is class-agnostic, so the
-- survival/utility/C-tier ratings carry straight over), then OVERRIDE for a
-- caster. This keeps owned breadth echoes out of the Reroll bucket while flipping
-- the melee/Strength/AP/dual-wield echoes that are dead without a weapon swing.
local pala = PP.Classes.PALADIN
B.catalog = {}
if pala and pala.catalog then
  for name, tier in pairs(pala.catalog) do B.catalog[name] = tier end
end
-- Priest overrides. DEAD-for-caster echoes drop to C (kept enabled for the
-- Adaptive breadth +1%, NOT rerolled -- only true negative riders get disabled).
-- Caster/DoT/mana echoes get promoted (mana especially -- the paladin catalog
-- rated caster/mana/spirit echoes as dead weight for Ret; for a mana-hungry
-- Shadow Priest they are LIVE. Pure ALLY-heal echoes stay low: solo = no allies).
local OVERRIDE = {
  -- melee / Strength / attack-power / physical / dual-wield / expertise = dead:
  ["Blade Tempest"] = "C",        -- physical whirlwind clone scales with AP/weapon
  ["Armor Penetration"] = "C", ["Expertise Drills"] = "C", ["Weapon Mastery"] = "C",
  ["Strength Training"] = "C", ["Brutal Might"] = "C", ["Rage of the Colossus"] = "C",
  ["First Strike"] = "C", ["Second Edge"] = "C", ["Crushing Finish"] = "C",
  ["Sweeping Blows"] = "C", ["Sundered Formation"] = "C", ["Focused Assault"] = "C",
  ["Undead Slayer"] = "C",        -- +AP vs undead is dead; use Undead Bane (+SP)
  -- key off PALADIN holy/heal abilities you don't have = dead:
  ["Crimson Reprisal"] = "C", ["Crusader's Surge"] = "C", ["Purifying Touch"] = "C",
  ["Sanctified Hazard"] = "C",
  -- caster promotions (live for a Shadow Priest):
  ["Undead Bane"] = "A",          -- +600 SP vs undead = all of Naxx/ICC
  ["Echoing Tides"] = "S",        -- 30% double-tick on periodics -- the DoT kit loves it
  ["Accelerated Decay"] = "S",    -- promoted: DoT haste-scaling (see statNote)
  ["Curse of the Plaguebringer"] = "S",
  ["Hungering Curse"] = "A",      -- auto Siphon Life = DoT + sustain, great solo
  -- mana sustain: dead weight for Ret, USEFUL for a mana-hungry caster:
  ["Mana Infusion"] = "B", ["Efficient Casting"] = "B", ["Mana Regeneration"] = "B",
  ["Mana Reservoir"] = "B", ["Meditative Flow"] = "B",
}
for name, tier in pairs(OVERRIDE) do B.catalog[name] = tier end
-- Dual-wield enabler: hard-skip for a priest (you wield a staff/1H+offhand, not
-- two 1H melee). Never draft it; if owned, it's reroll fodder.
B.catalog["Ambidexterity"] = "F"
-- CLASS-PREFIX PROC ECHOES (Corrosive Breath / Arcane Bombardment / Stonefist
-- Barrage / Ember Spark): the "Priest - X" variant is the one that procs for you;
-- the "Paladin - X" variants are dead. All kept at A for breadth (each unique =
-- +1% Adaptive), same as the paladin file's cross-class block.
B.catalog["Priest - Corrosive Breath"] = "A"
B.catalog["Priest - Arcane Bombardment"] = "A"
B.catalog["Priest - Stonefist Barrage"] = "A"
B.catalog["Priest - Ember Spark"] = "A"

-- Echoes to disable / banish: ONLY true negative riders (breadth meta -- every
-- other echo, even a functionally dead one, is worth +1% via Adaptive Power).
B.disable = {
  "Brittle Armor",   -- -30% armor rider
  "Overcharged",     -- +30% damage taken rider
}
B.disableNote = "Only negative-rider echoes are disabled. Everything else -- even "
  .. "melee/Strength echoes a caster can't use -- stays enabled: each unique "
  .. "active echo pays +1% damage via Adaptive Power. Melee/AP/dual-wield echoes "
  .. "are rated C (keep, don't draft), NOT rerolled."

-- Item affixes -- class-agnostic system; a caster wants the spell-side damage
-- affixes + the same survival affixes. (Reference data; the Gear page's live
-- affix dots are paladin-tuned for now.)
B.affixSurvival = {
  { affix = "Ironhide", role = "Flat % HP", slots = "Head - Shoulder - Legs - Ring - Ranged" },
  { affix = "Iron Will", role = "Effective HP", slots = "Chest - Shirt - Wrist - Feet" },
  { affix = "Fortified by Pain", role = "Defensive scaling", slots = "Hands - Waist - Ring - Off-hand" },
  { affix = "Overwhelming Force", role = "Damage / pressure", slots = "Neck - Back - Tabard - Trinket" },
}
B.affixDamage = {
  { affix = "Keen Strike 6/5/4", role = "Crit (top offense affix)" },
  { affix = "Relentless Crits 6", role = "Crit scaling" },
  { affix = "Temporal Flux 6", role = "Haste scaling (speeds Mind Flay + DoT ticks w/ Accelerated Decay)" },
  { affix = "Spell Mastery 4", role = "Feeds your whole spell/DoT damage" },
  { affix = "Accuracy / Hit", role = "Toward the ~289 spell-hit cap -- do this FIRST" },
  { affix = "Overwhelming Force 6", role = "Damage / pressure" },
  { affix = "Iron Will 6->2", role = "Effective-HP chain" },
  { affix = "Ironhide 6/5/4", role = "HP backbone" },
}
B.affixWeapon = "Weapon/wand: Spell Mastery + Temporal Flux (haste). No physical "
  .. "affixes (Flurry/Vulnerability were the paladin's melee picks)."
B.affixNote = "Cap Spell Hit first (miss = zero damage), then stack Crit/Haste on "
  .. "offense pieces and the Iron Will/Ironhide chain on survival slots. Highest "
  .. "affix rank is best (diminishing down the ranks)."

-- Gear targeting, per-slot ICC-25-Heroic BiS. Every item wowhead-verified on the
-- WotLK Classic DB (wowhead.com/wotlk/item=<id>). All cloth = spell power / hit /
-- haste / crit; ranged = wand. Rendered as the Dashboard "Gear targets" list.
-- Coarse gear targets for the Dashboard summary (grouped, like the paladin's).
-- The full per-slot named BiS lives in B.bis (read by GearAudit, with affix
-- verdicts + upgrade lines) -- same split as BuildData/HunterData.
B.gear = {
  { slot = "Weapons", target = "Royal Scepter of Terenas II (SP 1H mace, LK 25H, i284) main + Shadow Silk Spindle off-hand (Blood Prince Council 25H). No caster staff beats 1H+OH here (Nibelung is a healer staff)." },
  { slot = "Trinkets", target = "Dislodged Foreign Object (Rotface 25H) + Phylactery of the Nameless Lich (Sindragosa 25H); Muradin's Spyglass is the alt. AVOID Sindragosa's Flawless Fang (survival) + Whispering Fanged Skull (melee)." },
  { slot = "Ranged", target = "Corpse-Impaling Spike -- caster WAND (Rotface 25H)." },
  { slot = "Armor", target = "Sanctified Crimson Acolyte (T10 shadow) for the 4pc: head+shoulder+chest+hands tier, non-tier Plaguebringer's Stained Pants legs. Full per-slot BiS on the Gear page." },
}
-- Tier set: Sanctified Crimson Acolyte's Regalia (T10 Shadow; item-set=-231). NOT
-- "Bloodmage Regalia" (that's the Mage T10). 2pc: +5% crit to SW:P/DP/VT. 4pc:
-- Mind Flay channel -0.5s (your most-cast spell) -- worth keeping (head+shoulder+
-- chest+hands tier, non-tier legs). BiS weapon is the 1H mace + off-hand above,
-- NOT a staff (Nibelung is a healer staff). UNVERIFIED as shadow-BiS, do not
-- assert: Charred Twilight Scale, Abyssal Rune, Reign of the Unliving, Comet's
-- Trail. AVOID for shadow DPS: Sindragosa's Flawless Fang (survival trinket),
-- Whispering Fanged Skull (melee trinket).

-- Per-socket gem recommendation shown on empty sockets (GearAudit reads gemRec).
B.gemRec = "Spell Power (Runed Cardinal Ruby)"

-- Per-slot affix targets (GearAudit Judge reads PP.Build.slotTargets; preferred
-- first). Caster offense affixes on gear, spell-damage + haste on weapon/wand.
-- No Twinshot/Strength -- those are melee. (Affix name spellings match the
-- HunterData set the community confirmed.)
B.slotTargets = {}
do
  local common = { "Keen Strikes", "Relentless Crits", "Temporal Flux",
                   "Spell Mastery", "Overwhelming Force", "Fortified by Pain", "Stalwart" }
  for i = 1, 18 do B.slotTargets[i] = common end
  B.slotTargets[16] = { "Spell Mastery", "Temporal Flux", "Keen Strikes", "Relentless Crits" }
  B.slotTargets[18] = { "Spell Mastery", "Temporal Flux", "Keen Strikes", "Relentless Crits" }
end

-- Per-slot named BiS (GearAudit reads PP.Build.bis; format {item,src,ilvl,why,alt}
-- keyed by inventory slot). All wowhead-verified on the WotLK Classic DB; cloth
-- SP/hit/haste/crit, ranged = wand. 4 tier pieces (1/3/5/10) hold 4pc T10.
B.bis = {
  [1]  = { item = "Sanctified Crimson Acolyte Cowl", src = "ICC 25H tier (T10)", ilvl = 277, why = "T10 shadow; SP/hit/haste; anchors 4pc" },
  [2]  = { item = "Amulet of the Silent Eulogy", src = "Gunship 25H", ilvl = 277, why = "SP + hit + crit + haste" },
  [3]  = { item = "Sanctified Crimson Acolyte Mantle", src = "ICC 25H tier (T10)", ilvl = 277, why = "T10 shadow; 4pc" },
  [5]  = { item = "Sanctified Crimson Acolyte Raiments", src = "ICC 25H tier (T10)", ilvl = 277, why = "T10 shadow; 4pc" },
  [6]  = { item = "Crushing Coldwraith Belt", src = "Marrowgar 25H", ilvl = 277, why = "SP/crit/haste + socket" },
  [7]  = { item = "Plaguebringer's Stained Pants", src = "Festergut 25H", ilvl = 277, why = "non-tier legs; SP/crit/haste; keeps 4pc" },
  [8]  = { item = "Plague Scientist's Boots", src = "Festergut 25H", ilvl = 277, why = "SP/hit/haste" },
  [9]  = { item = "Bracers of Fiery Night", src = "Ruby Sanctum 25H", ilvl = 284, why = "top SP/haste wrist" },
  [10] = { item = "Sanctified Crimson Acolyte Handwraps", src = "ICC 25H tier (T10)", ilvl = 277, why = "T10 shadow; 4pc" },
  [11] = { item = "Ashen Band of Endless Destruction", src = "Ashen Verdict - Exalted", ilvl = 277, why = "SP + hit + haste" },
  [12] = { item = "Ring of Rapid Ascent", src = "Gunship 25H", ilvl = 277, why = "SP + crit + haste" },
  [13] = { item = "Dislodged Foreign Object", src = "Rotface 25H", ilvl = 277, why = "stacking SP proc trinket" },
  [14] = { item = "Phylactery of the Nameless Lich", src = "Sindragosa 25H", ilvl = 277, why = "SP proc trinket", alt = "Muradin's Spyglass (Gunship 25H)" },
  [15] = { item = "Cloak of Burning Dusk", src = "Ruby Sanctum 25H", ilvl = 284, why = "SP/crit/haste cloak" },
  [16] = { item = "Royal Scepter of Terenas II", src = "The Lich King 25H", ilvl = 284, why = "SP 1H mace; +893 SP, crit, haste" },
  [17] = { item = "Shadow Silk Spindle", src = "Blood Prince Council 25H", ilvl = 277, why = "SP/hit/haste off-hand" },
  [18] = { item = "Corpse-Impaling Spike", src = "Rotface 25H", ilvl = 277, why = "caster wand; SP/haste" },
}

-- Baked talent templates: talent NAME -> desired rank (order-proof; the applier
-- resolves names against the live tree). Standard 3.3.5 Shadow (14 Discipline /
-- 57 Shadow). Priest tabs are 1=Discipline, 2=Holy, 3=Shadow. Ebonhold kept
-- standard WotLK names + positions (effects rebalanced), so these resolve; it
-- also grants far more than 71 points, so this is a generous "take the good
-- stuff" list filled in `priority` order, tier-legally.
B.talentTemplates = {
  ["shadow"] = {
    name = "Solo Shadow (14/0/57, Dispersion)",
    talents = {
      -- Discipline (14) -- mana/utility only
      ["Twin Disciplines"] = 5, ["Improved Inner Fire"] = 3,
      ["Improved Power Word: Fortitude"] = 2, ["Meditation"] = 3, ["Inner Focus"] = 1,
      -- Shadow (57) -- the damage core, capstone Dispersion
      ["Spirit Tap"] = 3, ["Improved Spirit Tap"] = 2, ["Darkness"] = 5,
      ["Shadow Affinity"] = 3, ["Improved Shadow Word: Pain"] = 2, ["Shadow Focus"] = 3,
      ["Improved Mind Blast"] = 5, ["Mind Flay"] = 1, ["Veiled Shadows"] = 2,
      ["Shadow Weaving"] = 3, ["Shadow Reach"] = 2, ["Focused Mind"] = 3,
      ["Vampiric Embrace"] = 1, ["Improved Vampiric Embrace"] = 2,
      ["Improved Devouring Plague"] = 3, ["Shadowform"] = 1, ["Shadow Power"] = 5,
      ["Improved Shadowform"] = 2, ["Misery"] = 3, ["Vampiric Touch"] = 1,
      ["Pain and Suffering"] = 3, ["Twisted Faith"] = 5, ["Dispersion"] = 1,
    },
    -- Importance order (most valuable first); the applier fills these first,
    -- always tier-legally, so scarce points buy the best talents.
    priority = {
      "Shadowform", "Mind Flay", "Vampiric Touch", "Vampiric Embrace", "Misery",
      "Improved Devouring Plague", "Darkness", "Shadow Weaving", "Shadow Power",
      "Twisted Faith", "Pain and Suffering", "Dispersion", "Shadow Focus",
      "Twin Disciplines", "Meditation", "Improved Shadow Word: Pain",
      "Improved Mind Blast", "Improved Vampiric Embrace", "Improved Shadowform",
      "Shadow Affinity", "Focused Mind", "Shadow Reach", "Spirit Tap",
      "Improved Spirit Tap", "Veiled Shadows", "Inner Focus", "Improved Inner Fire",
      "Improved Power Word: Fortitude",
    },
  },
}
B.defaultTemplate = "shadow"

-- Glyphs (major): Glyph of Shadow (SP proc off periodic crits), Glyph of Mind
-- Flay, and Glyph of Dispersion (solo -- cuts the CD) or Glyph of Shadow Word:
-- Pain. Minor: Fortitude, Shadowfiend, Levitate. Farm swap: Glyph of Mind Sear.
B.glyphs = "Major: Glyph of Shadow + Glyph of Mind Flay + Glyph of Dispersion "
  .. "(solo) or Glyph of Shadow Word: Pain. Minor: Fortitude / Shadowfiend / "
  .. "Levitate. Pack-farming swap: Glyph of Mind Sear."

-- Dashboard sections (Dashboard.BuildText renders B.reference in place of the
-- legacy paladin Seal/Blessing layout, so the priest reads cleanly). Reuses the
-- prose fields above -- no duplication.
B.reference = {
  { title = "Form + buffs", lines = { B.seal, B.blessing } },
  { title = "Rotation (single target)", lines = { B.rotation } },
  { title = "AoE / farm", lines = { B.rotationAoe } },
  { title = "Mana (solo)", lines = { B.mana } },
  { title = "Lock these echoes", lines = {
      table.concat(B.locked, ", "),
      "Transferred from the measured paladin engine -- validate with /pp bench + /pp dps.",
  } },
  { title = "Glyphs", lines = { B.glyphs } },
}

-- Rotation HUD (RotationHelper reads PP.Build.rotationPriority + rotationUpkeep).
-- Upkeep = Shadowform (the HUD nags if it drops, like the paladin's seal).
-- cond gates WHEN to suggest; RotationHelper's Ready() gates castability, so DoTs
-- are suggested only when missing/expiring on the target.
local function dotDown(spellName)
  -- true = my DoT is absent or expiring within 1.5s on the current target.
  if not (UnitExists("target") and UnitCanAttack("player", "target")) then return false end
  for i = 1, 40 do
    local name, _, _, _, _, _, expires, caster = UnitDebuff("target", i)
    if not name then break end
    if name == spellName and caster == "player" then
      return (not expires) or (expires - GetTime() < 1.5)
    end
  end
  return true
end
B.rotationUpkeep = { "Shadowform" }
B.rotationPriority = {
  { spell = "Vampiric Touch", cond = function() return dotDown("Vampiric Touch") end },
  { spell = "Devouring Plague", cond = function() return dotDown("Devouring Plague") end },
  { spell = "Shadow Word: Pain", cond = function() return dotDown("Shadow Word: Pain") end },
  { spell = "Mind Blast" },   -- Ready() gates its cooldown
  { spell = "Shadow Word: Death", cond = function()
      local rh = PP.RotationHelper
      return rh and rh.TargetPct and (rh.TargetPct() or 100) <= 25 end },
  { spell = "Mind Flay" },    -- filler channel
}

-- EBH synergy bundles (caster set) -- +40 bundle score to members while the main
-- (first) echo is active. HubSync reads PP.Build.bundles. NO melee bundles: the
-- paladin's ppb-blades / ppb-resonant (Ambidexterity / ArP / Strength / Agility)
-- are dead for a caster, so a priest sync no longer boosts them.
B.bundles = {
  -- DoT web -- your native strength; the main (Pandemic) extends the rest.
  { id = "ppb-dots", tier = "S",
    echoes = { "Pandemic", "Contagion", "Echoing Tides", "Hungering Curse",
               "Curse of the Plaguebringer", "Necrotic Plague", "Accelerated Decay" } },
  -- fire/frost proc web -- feeds Twilight Equilibrium's non-shadow school.
  { id = "ppb-cyclones", tier = "S",
    echoes = { "Cinders of the Sanctum", "Cyclone of Cold Bones", "Permafrost Aura",
               "Permeating Chill", "Frostfire Paradox", "Flame Beacon", "Brittle Forging" } },
  -- plague/goo web (measured paladin top damage; procs off your spell damage).
  { id = "ppb-plague", tier = "S",
    echoes = { "Malleable Goo", "Slime Spray", "Inhaled Blight",
               "Curse of the Plaguebringer", "Necrotic Plague" } },
  -- caster tempo engine (replaces the melee ppb-blades): the engine + haste/crit.
  { id = "ppb-tempo", tier = "S",
    echoes = { "Twilight Equilibrium", "Adaptive Power", "Precision Strike",
               "Temporal Pressure", "Twin Casting", "Spellweave" } },
}
-- EBH build spec tab HubSync tags the synced build with (priest: 3 = Shadow).
B.specIndex = 3

-- Echoes FarmQueue should treat as farm targets (locked core + S-tier). Returns
-- a de-duplicated array of names. (Same body as BuildData.)
function B.FarmTargets()
  local seen, out = {}, {}
  local function add(name)
    if name and not seen[name] then seen[name] = true; out[#out + 1] = name end
  end
  for _, n in ipairs(B.locked) do add(n) end
  for _, n in ipairs(B.tiers.S) do add(n) end
  return out
end

-- The proc echoes worth spending orbs to Epic-ify (quality >> rank for procs).
-- The cross-class fire/frost/plague web -- TRANSFERRED from the paladin measured
-- engine; these proc off your damage/ticks, so they should carry to a caster.
-- Validate which actually top your meters with /pp dps before Epic-fishing.
function B.TopProcs()
  return {
    "Cinders of the Sanctum", "Malleable Goo", "Slime Spray",
    "Cyclone of Cold Bones", "Inhaled Blight", "Necrotic Plague",
    "Curse of the Plaguebringer", "Permafrost Aura",
  }
end

-- Tier lookup for a given echo name (for DrawHelper). Same body as BuildData.
function B.TierOf(name)
  if not name then return nil end
  for tier, list in pairs(B.tiers) do
    for _, n in ipairs(list) do if n == name then return tier end end
  end
  for _, n in ipairs(B.disable) do if n == name then return "F" end end
  return nil
end
