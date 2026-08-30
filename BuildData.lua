-- PallyPilot BuildData: the curated solo-Retribution paladin build.
-- This is OUR data (synthesized from EbonholdHub builds + the #paladin Discord
-- + the player guide). All PallyPilot features read from this one table.
local PP = PallyPilot
local B = {}
PP.Build = B                       -- default; Core re-points PP.Build per class at login
PP.Classes = PP.Classes or {}
PP.Classes.PALADIN = B             -- registered in the multi-class registry

B.title = "Solo Retribution — Hardcore climb (AotC 1+2 done, HC2 unlocked)"
B.spec = "Retribution"

-- Stat priority (Ebonhold #paladin consensus, Aug 2026 — Absolim/Spooh/Nero):
-- Crit (to ~100%) -> Haste -> Strength -> Spellpower -> Attack Power.
B.statPriority = { "Critical Strike", "Haste", "Strength" }
B.statNote = "Crit -> Haste -> Strength. Push Crit toward ~100% (mostly from "
  .. "affixes: Keen Strike / Relentless Crits). Haste has NO real cap here — "
  .. "Accelerated Decay scales your DoT ticks past the GCD floor, so it keeps "
  .. "paying. Strength is the keystone stat because it feeds BOTH Attack Power "
  .. "AND Spellpower (Prot's Touched by the Light: 1 Str ~= 1.2 SP), so it "
  .. "multiplies the whole hybrid kit — but don't pass a big Crit/Haste upgrade "
  .. "just because its Strength is lower."
-- Expertise: reach the 14% (56) HARDCAP for HC4/5 (no boss parry-haste) — but
-- from the ash tree + Combat Expertise (Prot) + food, NOT gear stats.
B.statExpertise = "Expertise hardcap 14% (56) for HC4/5; get it from ash tree + "
  .. "Combat Expertise + food, not gear."

-- Weapon enchant + gems. (Flurry/Vulnerability are AFFIXES — see affixWeapon.)
-- What to socket, named for the Gear page's one-line "Gem" instruction.
B.gemRec = "Haste (Quick King's Amber)"
B.enchants = "Weapon ENCHANTS (you dual-wield): Black Magic on ONE weapon, "
  .. "Mongoose on the OTHER. They do NOT stack -- each is a single buff -- so one "
  .. "of each gives you TWO independent proc chances instead of one. (Community "
  .. "finding, #hunter weapons thread; applies to any dual-wielder.) Separate from "
  .. "the Judgement/Vulnerability AFFIX. Gems: Haste in every socket + 2 Haste/Stam "
  .. "to activate the Chaotic Skyflare Diamond (3% crit) meta."

-- Seal, blessing & rotation (asked a lot; not obvious from the echo list).
B.seal = "Seal of Vengeance (Alliance) / Seal of Corruption (Horde) — the stacking-DoT seal."
B.sealWhy = "Ebonhold's core echoes are DoT-centric — Pandemic extends your DoTs, "
  .. "Contagion/Accelerated Decay spread and speed them — and Vengeance/Corruption IS a "
  .. "stacking DoT (Holy Vengeance, 5 stacks), so those echoes multiply it. Swap to Seal of "
  .. "Command only for pure trash-cleave where nothing lives long enough to stack the DoT."
B.blessing = "Blessing of Kings (use the Greater version with a Symbol of Kings)."
B.blessingWhy = "+10% to all stats = +10% Strength (AP -> SP, your damage) AND +10% Stamina "
  .. "(survival) in one buff. Beats Might (AP only) and Sanctuary (3% DR only) for soloing."
B.rotation = "Keep Seal of Vengeance stacked. Priority: Judgement of Light (on CD — the "
  .. "self-heal; mana is already covered by Judgements of the Wise, and Judgement TRIGGERS your "
  .. "echoes) > Crusader Strike > Divine Storm > "
  .. "Consecration > Holy Wrath (huge vs undead/demons — all of Naxx) > Exorcism when The Art "
  .. "of War procs (instant, free) > Hammer of Wrath below 20% HP. For packs, lead with Divine "
  .. "Storm + Consecration + Holy Wrath."
B.talents = "~44 Protection / 49 Retribution hybrid for soloing (survivability "
  .. "under full Ret damage). Pure-damage farmers drop the Prot side once the "
  .. "Soul Ash tree carries survival."

-- Echoes to lock so they persist across runs. ORDER = lock priority: only the
-- top N fit your unlocked lock slots (5 as of the 2026-08-28 rebuild), so the
-- proven engine + scaling enablers + survival come first; Edict/Exposed Heart
-- lock as more slots open.
--
-- Grounded in the 150-fight combat log (2026-08-28): Twilight Equilibrium is
-- the damage ENGINE (~33% of all damage). It is a school-flip machine — Light
-- Essence stacks on Holy/Fire/Nature and dumps Darkburst on Shadow/Frost/Arcane
-- (and mirror). The build must keep BOTH damage schools flowing or half the
-- engine starves. Constellations was dropped from the locks: measured 0.2%, a
-- wasted lock slot vs. Edict of the Iron Council (a real S carry).
B.locked = {
  -- Ambidexterity first: it's an ENABLER, not a damage echo — with dual 1H
  -- gear, the off-hand is dead weight until it's drafted, so it must be
  -- guaranteed from level 1. (If you ever swap to a 2H, drop this.)
  "Ambidexterity",
  "Twilight Equilibrium",       -- the engine (~33% measured)
  "Adaptive Power",             -- +1% dmg per unique active echo; compounds, want it early
  "Pandemic",                   -- DoT engine: extends/spreads every periodic
  "Sanguine Bulwark",           -- hardcore survival
  "Edict of the Iron Council",  -- proven S carry (measured, in your best fights)
  "Exposed Heart",
}

-- Draw priority tiers. On a level-up selection (and Orb rerolls), take the
-- highest tier offered. These names are also the farm targets (see FarmQueue).
B.tiers = {
  S = {
    "Twilight Equilibrium", "Constellations", "Pandemic", "Sanguine Bulwark",
    "Adaptive Power", "Exposed Heart", "Edict of the Four", "Edict of the Iron Council",
    "Blade Tempest",   -- measured top-3 carry (whirlwind clone)
    "Brittle Forging", -- promoted A->S: measured ~5% (Heat -> Brittle -> Shatter AoE)
    "Blood Mirror", "Contagion", "Resonant Build",
    "Temporal Flow", "Chronoboost", "Energy Overflow", "Storm Conductor",
    "Flame Vents", "Nether Lord's Command", "Twin Casting",
    "First Strike", "Perfect Timing", "Crypt Lord's Swarm", "Rage of the Colossus",
    "Burning Flames", "Spellweave",
    -- Catalog finds promoted to curated S (priority order matters for locks):
    "Sanctum Sentries", "Arcane Cadence", "Reaper's Reprieve",
    -- Dual-wield enabler — the weapon setup depends on it. Never reroll.
    "Ambidexterity",
  },
  A = {
    -- Demoted S->A (measured ~0.2% over many fights, 2026-08-29 log). Revert if
    -- they're execute/burst echoes that only shine in specific fights.
    "Harbringer of Doom", "Second Edge",
    "Accelerated Decay", "Quickened Tempo", "Quickening Aura", "Arcane Density",
    "Rend the Weak", "Iron Constitution", "Brutal Might", "Scorching Wounds",
    "Battle Rhythm", "Relentless Rhythm", "Tempest Vortex", "Strength Training",
    "Focused Assault", "Mystic Potency", "Reaper's Doom", "Weapon Mastery",
    -- Physical dual-wield scaling: ArP multiplies white/CS/DS damage,
    -- expertise removes dodge/parry from two swing streams.
    "Armor Penetration", "Expertise Drills",
  },
  B = {
    "Steel Brand", "Bolstered Vitality", "Pain Drive", "Holy Brand",
    "Double Strike", "Desperate Escape", "Battle Momentum", "Arcane Weapon",
  },
}

-- Full-catalog ratings (from the server's PerkDatabase dump, 2026-08-25:
-- 323 echoes, 242 paladin-usable). Names NOT in the curated lists above are
-- rated here: S/A/B = tiers, F = junk (reroll fodder). Anything absent from
-- both stays unrated-junk. Rationale: DoT echoes ride Pandemic/Contagion,
-- leech/sustain enables solo, caster/mana/spirit/healer-only echoes are dead
-- weight for Ret, undead-flavored damage is the whole AotC path.
-- TOOLTIP-VERIFIED (2026-08-25): every rating below is grounded in the real
-- effect text from /pp echotext (546 tooltips). No name inference remains.
B.catalog = {
  -- S: build-defining (verified numbers)
  ["Precision Strike"] = "S",   -- +100% crit chance for 3s, every 10s
  ["Temporal Pressure"] = "S",  -- haste reduces CDs of the entire Ret rotation
  ["Necrotic Plague"] = "S",    -- 36k/s DoT-proc plague; jumps +25% per death
  ["Undead Slayer"] = "S",      -- up to +900 AP vs undead = all of Naxx/ICC
  -- A: strong, verified
  ["Paladin - Arcane Bombardment"] = "A", -- CS/Judgement fire 2 big arcane missiles
  ["Paladin - Stonefist Barrage"] = "A",   -- every Judgement hurls an AoE boulder
  ["Blade Tempest"] = "A",      -- phys-on-DoT summons 36k/s whirlwind clone
  ["Broodmother's Fury"] = "A", -- cinder stacks into 121k Deep Breath
  ["Brittle Forging"] = "A",    -- fire-web: Heat -> Brittle (+20% crit) -> Shatter AoE
  ["Call of the Lich King"] = "A",
  -- ("Crimson Reprisal" removed: no echo by that name exists in the perk DB.)
  ["Crusader's Surge"] = "A",   -- chance for instant Exorcism/FoL/HL
  ["Crushing Finish"] = "A",    -- execute, scales with Expertise
  ["Crushing Force"] = "A",     -- crit-rating stat echo (stat prio #2)
  ["Deathwhisper's Barrier"] = "A",
  ["Defile"] = "A", ["Demonic Awakening"] = "A",
  ["Echoing Tides"] = "A",      -- 30% double-tick on periodics (DoT build)
  ["Frostmourne Hungers"] = "A", ["Gunship Barrage"] = "A",
  ["Hungering Curse"] = "A",    -- auto Siphon Life: DoT + sustain
  ["Idol of Yogg-Saron"] = "A", ["Immolation Aura"] = "A",
  ["Impaler's Tribute"] = "A", ["Keen Aim"] = "A", ["Leeching Swarm"] = "A",
  ["Open Wounds"] = "A",
  ["Peak Condition"] = "A",     -- +10% dmg above 75% HP; JoL keeps you there
  ["Purifying Touch"] = "A",    -- direct heals auto-dispel magic (free Cleanse)
  ["Quick Hands"] = "A",        -- haste-rating stat echo (stat prio #3)
  ["Reaper's Verdict"] = "A", ["Rolling Momentum"] = "A",
  ["Sanctified Hazard"] = "A",  -- +20% Consecration/DS at 4+ enemies
  ["Scent of Blood"] = "A",     -- +15% attack/cast speed in execute range
  ["Static Overflow"] = "A", ["Sudden Insight"] = "A",
  ["Sundered Formation"] = "A", -- +10% phys taken + cleave rider
  -- MEASURED (150-fight build report 2026-08-26): the plague/goo web is
  -- keepsy's top damage. Malleable Goo was #1 overall at 14.5% (rated B!),
  -- Inhaled Blight's Pungent Blight 4.5%.
  -- Double-validated (our 150-fight measured damage AND Nero's published
  -- build both rate S at Epic): the plague/frost core.
  ["Malleable Goo"] = "S",
  ["Slime Spray"] = "S",
  ["Cyclone of Cold Bones"] = "S",
  ["Inhaled Blight"] = "S",
  ["Curse of the Plaguebringer"] = "A", -- plague-web DoT spreader (Nero: S)
  ["Sweeping Blows"] = "A", ["The Harvester's Tithe"] = "A",
  ["Tunnel Vision"] = "A",      -- +8% sustained single-target (bosses)
  -- B: fine filler (verified minor/situational; several trigger only off
  -- OTHER echoes' fire/frost/shadow/nature damage — synergy picks)
  ["Archmage's Mark"] = "B", ["Arcane Ward"] = "B",
  -- The PALADIN variant procs off Consecration/Divine Storm (the cross-class
  -- ones are dead — they key off other classes' abilities).
  ["Paladin - Corrosive Breath"] = "B",
  ["Backstabber's Edge"] = "B", ["Battle Tempo"] = "B",
  ["Battlefield Hazard"] = "B", ["Beast Slayer"] = "B",
  ["Blighted Hazard"] = "B", ["Broodmother's Webbing"] = "B",
  ["Champion's Rally"] = "F", ["Chaotic Convergence"] = "B",  -- pure healer, useless solo Ret
  -- A: Frost damage -> Rime -> Frost Breath + Brittle (+10% Frost dmg). Pairs
  -- with Brittle Forging and the Darkburst (Frost) half of the engine. Nero: S.
  ["Chill of the Bone Wyrm"] = "A",
  -- MEASURED (arm3 HoR-HC2 benchmark): its Fire Cyclone proc was the #1
  -- damage source (10-14% per fight) — the fire/frost echo web feeds it.
  ["Cinders of the Sanctum"] = "S",
  ["Conjured Flame"] = "B", ["Crippling Strikes"] = "B",
  ["Dark Nucleus"] = "B",
  ["Demon Slayer"] = "B", ["Divine Resonance"] = "B", ["Dragon Slayer"] = "B",
  -- S: 350% weapon damage on a melee proc AND leaves the target Unbalanced
  -- (+10% damage taken) -- a multiplier on the whole kit, and dual-wield rolls
  -- the proc twice as often. Nero: S.
  ["Drillmaster's Rebuke"] = "S", ["Earthen Snap"] = "B",
  ["Earthen Spike"] = "B", ["Earthen Stability"] = "B",
  ["Elemental Slayer"] = "B",  -- (bare "Ember Spark" removed: class-prefixed only)
  ["Paladin - Ember Spark"] = "B",
  ["Ember Ward"] = "B", ["Emberlord's Gift"] = "B",
  ["Emerald Vigor"] = "F",      -- pure healer, ally-targeted; useless solo Ret
  ["Eonar's Seed"] = "B", ["Essence Tap"] = "B",
  -- Nero Epic build keeper: Fire proc + AoE Fire Nova on death; feeds the fire web.
  ["Flame Beacon"] = "A", ["Forged in Combat"] = "B", ["Fortress Soul"] = "B",
  -- Nero Epic build keeper: Frost+Fire shatter combo; synergizes with the frost web.
  ["Frost Bite"] = "B", ["Frost Ward"] = "B", ["Frostfire Paradox"] = "A",
  ["Frostguard Carapace"] = "B", ["Giant Slayer"] = "B", ["Grim Resolve"] = "B",
  ["Hardened Resolve"] = "B", ["Hardened Skin"] = "B",
  ["Harpoon Barrage"] = "B", ["Holy Hazard"] = "B",
  ["Insulated Soul"] = "B",
  -- S (2026-08-30 community pass): Nero's canonical build rates it S and the
  -- tooltip backs it for dual-wield -- 5 stacks = +10% attack speed AND its Nature
  -- auto-attack damage feeds Twilight Equilibrium's Light Essence side.
  ["Lightning Charged"] = "S", ["Machine Slayer"] = "B",
  ["Mana Infusion"] = "B",      -- verified: mana returns also heal above 80% mana
  ["Mutagenic Fumes"] = "B", ["Opening Split"] = "B",
  ["Permafrost Aura"] = "A",    -- measured: steady 3-4% + feeds the frost web
  -- Nero Epic build keeper: +10% Frost damage-taken amp + shatter on death.
  -- S: +10% CRIT (our #1 stat) and +5% damage while Positive, 10% damage taken
  -- reduction while Negative. A solo melee paladin flips constantly, so it is
  -- offence AND hardcore survival in one echo. Nero: S.
  ["Permeating Chill"] = "A", ["Polarity Shift"] = "S",
  ["Prismatic Guard"] = "B", ["Raging Momentum"] = "B",
  ["Ravenous Bellow"] = "B", ["Reactive Retaliation"] = "B",
  ["Reinforced Shielding"] = "B", ["Relentless Energy"] = "B",
  -- A (CONDITIONAL): 5% melee/ranged proc, and it fires +1 extra Rocket PER
  -- ACTIVE PET OR GUARDIAN. It is the hunter's whole engine because they field
  -- snakes; for us it only scales if we are running the guardian echoes we
  -- already rate S (Sanctum Sentries, Crypt Lord's Swarm). Scales off SP+AP.
  -- Rate S in your head if that guardian package is up; A otherwise. Nero: S.
  ["Rocket Strike"] = "A", ["Rootbreaker"] = "B",
  ["Ruthless Exploiter"] = "A", -- measured 6-8% of total on HC2 trash; my
                                -- CC-only read was too narrow (procs off the
                                -- echo web's freezes/roots/stuns constantly)
  ["Sanctified Sky"] = "B", ["Scorched Path"] = "B",
  -- A: procs off SHADOW DOT damage for a 10yd AoE hit -- we are DoT-centric
  -- (Pandemic/Contagion) and Twilight Equilibrium keeps Shadow flowing. Nero: S;
  -- held at A because it only fires off the Shadow half of the rotation.
  ["Shadow Crash"] = "A", ["Shadow Hazard"] = "B", ["Shadow Ward"] = "B",
  ["Sharpened Edge"] = "B",     -- verified: small flat adder, not % damage
  ["Shielded Steps"] = "B", ["Shock Vortex"] = "B",
  -- A: taking damage builds Molten Blood -> AoE slime + 10% damage taken
  -- reduction + speed. Solo pack-farm sustain; triggers naturally in HC. Nero: S.
  ["Slimebound Husk"] = "A", ["Spell Harmony"] = "B", ["Spiteful Shard"] = "B",
  ["Spiteful Thorns"] = "B", ["Steady Grip"] = "B",
  ["Stone Shatter"] = "B", ["Stoneskin Threads"] = "B",
  ["Stored Momentum"] = "B", ["Storm Hazard"] = "B", ["Sundered Will"] = "B",
  ["Swift Step"] = "B",
  -- A: +10% CRIT DAMAGE from summoned Spores. Nero rates it S, but he plays
  -- grouped and the buff reads "nearby allies" -- solo it is a party of one, so
  -- it is worth strictly less to us than to him. Still good with our crit, hence
  -- A not S. A clear case where the canonical build's CONTEXT differs from ours.
  ["The Sporelord's Gift"] = "A",
  ["The Unclean's Fever"] = "A",  -- measured: consistent ~3% while tanking packs
  ["Titan's Grip"] = "B",       -- 2H-in-one-hand at -20% dmg; test vs 1H pair
  -- S: near-perfect fit for the locked engine. Fire DoT + Shadow DoT on the same
  -- target merge into a Twilight Rift (3467/s AoE) -- and Twilight Equilibrium
  -- exists precisely to keep BOTH schools flowing. Nero rates it S too.
  ["Toxic Phials"] = "B", ["Twilight Combustion"] = "S",
  ["Undead Bane"] = "B",        -- +600 SP vs undead; SP is secondary but real
  ["Agility Boost"] = "B",      -- weak alone, but a 3rd base-stat TYPE turns
                                -- Resonant Build's +15% damage ON (with Str+Stam)
  ["Verdant Ward"] = "B", ["Warm-Blooded"] = "B",
  -- A: Nature damage -> 12 stacks -> Poison Bolt Volley (10yd AoE + DoT). Real
  -- pack-farm value; Lightning Charged now feeds the Nature stacks. Nero: S.
  ["Widow's Venom"] = "A", ["Wild Hazard"] = "B",
  -- Promotions from the Wkpal autopsy (2026-08-25): field data over theory.
  ["The Last Wall"] = "A",      -- +50% max HP; Wkpal runs it — losing it = -17k HP
  ["Drained Reserves"] = "A",   -- +15% spell dmg; -30% mana irrelevant with JotW
  ["Bolstered Vitality"] = "B", ["Warded Aegis"] = "B",
  -- F: ONLY true negative riders. Merely-useless echoes are C instead — every
  -- unique active echo pays +1% damage via Adaptive Power, and F-ratings also
  -- waste the engine's banishes (Wkpal spends banishes on duplicates).
  ["Glass Canon"] = "F",        -- -30% max HP rider
  ["Heavy Blows"] = "F",        -- -30% attack speed rider (dual-wield poison)
  ["Brittle Armor"] = "F", ["Overcharged"] = "F",
  -- Tooltip-verified trap: -50% crit CHANCE for +30% crit damage. Zeroes a
  -- ~44% crit build; only sane at 90%+ crit. (Field report 2026-08-25.)
  ["Lethal Precision"] = "F",
  -- C: breadth filler — no build value, but KEEP them active for Adaptive.
  ["Accelerated Spirit"] = "C", ["Arcane Burn"] = "C", ["Arcane Hazard"] = "C",
  ["Arcane Surge"] = "C", ["Armor Mastery"] = "C", ["Beast Bane"] = "C",
  ["Burning Touch"] = "C", ["Cavalry Instincts"] = "C", ["Demon Bane"] = "C",
  ["Divine Surge"] = "C", ["Dragonkin Bane"] = "C", ["Efficient Casting"] = "C",
  ["Elemental Bane"] = "C", ["Enhanced Recovery"] = "C", ["Entropic Fusion"] = "C",
  ["Fel Hazard"] = "C", ["Fel Surge"] = "C", ["Giant Bane"] = "C",
  ["Healing Cadence"] = "C", ["Healing Echo"] = "C", ["Heavy Incantations"] = "C",
  ["Holy Revelation"] = "C", ["Hunting Hazard"] = "C", ["Inspiring Mending"] = "C",
  ["Leadfoot"] = "C", ["Lingering Inspiration"] = "C", ["Mana Regeneration"] = "C",
  ["Mana Reservoir"] = "C", ["Mechanical Bane"] = "C", ["Meditative Flow"] = "C",
  ["Mind Expansion"] = "C", ["Nature's Surge"] = "C",
  ["Overwhelming Restoration"] = "C", ["Provoking Presence"] = "C",
  ["Runic Momentum"] = "C", ["Spiritual Fortitude"] = "C",
  ["Steady Casting"] = "C", ["Steady Channeling"] = "C", ["Stitched Fury"] = "C",
  ["Storm of the Spellweaver"] = "C", ["Subtle Presence"] = "C",
  ["Unbroken Focus"] = "C", ["Unstable Missiles"] = "C",
  -- Reworked in the 2028-08-27 patch (were talent-conflicting):
  -- Echoing Affliction now echoes 20% of your DoT damage to a 2nd enemy (30%
  -- chance) — free AoE cleave for the plague/DoT school. Strong for pack farming.
  -- ("Echoing Afflictions" removed. Two separate errors here, both caught by the
  -- echo validator: we had it as the SINGULAR "Echoing Affliction" (a phantom key
  -- -- the DB name is plural), and once corrected the classMask says PALADINS
  -- CANNOT DRAW IT: mask 1533 = every class except bit 2 (Paladin). It is a fine
  -- echo -- just not one of ours. Hunter/priest keep it.)
  -- Unstable Infusion: crits have 30% chance for an AoE explosion (sp0.44+ap0.22).
  -- Crit-gated, so only as good as your crit — B until your crit is real.
  -- ("Unstable Infusion" removed: it exists as 8 per-class variants (Warrior,
  -- Hunter, Rogue, Priest, DK, Shaman, Warlock, Druid) and there is NO Paladin
  -- one -- classMask never includes bit 2. A paladin can't draw it.)
}

-- Cross-class proc variants (Wkpal insight): they never proc for a paladin,
-- but each is a unique active echo = +1% Adaptive Power. All A for breadth.
do
  local classes = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest",
    "Death Knight", "Shaman", "Mage", "Warlock", "Druid" }
  local procs = { "Corrosive Breath", "Arcane Bombardment",
    "Stonefist Barrage", "Ember Spark" }
  for _, c in ipairs(classes) do
    for _, p in ipairs(procs) do
      B.catalog[c .. " - " .. p] = "A"
    end
  end
  -- (No BARE "Arcane Bombardment"/"Corrosive Breath"/"Stonefist Barrage"/
  -- "Ember Spark" entries: the perk DB only ever carries these CLASS-PREFIXED
  -- ("Paladin - Ember Spark" etc, one per class), so a bare key is a phantom
  -- rating that can never match. The loop above already covers every class.)
  -- Nero-endorsed damage echoes (Ebonhold #paladin, Aug 2026 — see
  -- docs/ebonhold-paladin/echoes.md for his full import string + de-prioritized
  -- list: Archmage / Echoing Tides / Emberlord).
  B.catalog["Entropic Fusion"] = "A"
  B.catalog["The Last Wall"] = "A"
  B.catalog["Static Overflow"] = "A"
  B.catalog["Hungering Curse"] = "A"
end

-- Echoes to disable / banish. Rage- and runic-power-scaling echoes are dead for
-- a mana class; the others are traps for this build.
-- BREADTH META (Wkpal autopsy 2026-08-25): Adaptive Power pays +1% per unique
-- ACTIVE echo, so even a do-nothing echo is worth +1% damage. Disable ONLY
-- echoes with true negative riders. Rage/runic echoes do nothing functionally
-- but still count as uniques — keep them.
B.disable = {
  "Brittle Armor",   -- -30% armor rider
  "Overcharged",     -- +30% damage taken rider
}
B.disableNote = "Only negative-rider echoes are disabled. Everything else — even "
  .. "functionally dead rage/runic echoes — feeds Adaptive Power +1% per unique."

-- Item affixes — two schools (Enchanted Anvil, Dalaran).
B.affixSurvival = {
  { affix = "Ironhide", role = "Flat % HP", slots = "Head · Shoulder · Legs · Ring · Ranged" },
  { affix = "Iron Will", role = "Effective HP / Strength", slots = "Chest · Shirt · Wrist · Feet" },
  { affix = "Fortified by Pain", role = "Defensive scaling", slots = "Hands · Waist · Ring · Off-hand" },
  { affix = "Overwhelming Force", role = "Damage / pressure", slots = "Neck · Back · Tabard · Trinket" },
}
B.affixDamage = {
  { affix = "Keen Strike 6/5/4", role = "Crit toward ~100% (top offense affix)" },
  { affix = "Relentless Crits 6", role = "Crit scaling (RaSeT)" },
  { affix = "Crits 6", role = "Crit scaling" },
  { affix = "Temporal Flux 6", role = "Haste scaling (RaSeT)" },
  { affix = "Spell Mastery 4", role = "Feeds spell/DoT side" },
  { affix = "Overwhelming Force 6", role = "Damage / pressure" },
  { affix = "Fortified by Pain 6/5/4", role = "Damage + defensive scaling" },
  { affix = "Iron Will 6->2", role = "Strength / effective-HP chain" },
  { affix = "Ironhide 6/5/4", role = "HP backbone" },
  { affix = "Thick Hide 6", role = "Mitigation" },
}
B.affixWeapon = "Weapons: Judgement + Vulnerability (Nero uses Flurry + Vulnerability)."
B.affixNote = "Judgement affix is an ECHO TRIGGER (procs Arcane Cadence), not a "
  .. "damage number — keep it on the weapon(s). Weapon affixes stack; dual-wield "
  .. "can carry the same on both hands. Highest rank is best (diminishing returns "
  .. "down the ranks). Tuned right you're NOT armor-capped; without the Lethal "
  .. "Precision talent (-50% crit chance) you can crit-OVERCAP — swap low crit "
  .. "affixes for armor/damage if so."

-- (B.slotTargets lives further down, next to B.bis -- a duplicate definition
-- that used to sit here was removed; Lua takes the last assignment, so two
-- blocks silently meant only one was live.)

-- Gear targeting (per-slot, endgame ICC-HC4 — Ebonhold #paladin, Aug 2026).
-- Base items are standard WotLK; the affix + crit/haste roll is what matters.
B.gear = {
  { slot = "Weapons", target = "Royal Scepter of Terenas II (SP mace, LK 25H) main; fast crit/haste dagger off (Heaven's Fall) or a 2nd Scepter. Judgement + Vulnerability affix. NB Librarian's Paper Cutter is ilvl 200 (Halls of Lightning HC), not ICC." },
  { slot = "Trinkets", target = "Tiny Abomination in a Jar (Putricide 25H) + Comet's Trail (Algalon, Ulduar) for haste; Deathbringer's Will (Saurfang 25H) is the no-haste alt" },
  { slot = "Ranged", target = "Corpse-Impaling Spike (caster wand, Rotface 25H) or Zod's Repeating Longbow (ICC 25H); Libram of Valiance if a relic is forced" },
  { slot = "Armor", target = "Sanctified Lightsworn (T10.5) from ICC 25H for the 4pc; crit + haste rolls. Weak slots: Coldwraith Links belt + Frostbitten Fur Boots (leather). Full per-slot BiS on the Gear page." },
}

-- Baked talent templates: target rank per (tab, index). Paladin tabs are
-- 1=Holy, 2=Protection, 3=Retribution. Ranks are in talent-index order (tier by
-- tier), taken from the top-rated EbonholdHub build. Verify names with
-- /pp talents preview before trusting the apply — if Ebonhold reordered its
-- trees, indices shift and we correct the arrays.
-- Talent templates keyed by talent NAME -> desired rank (order-proof; the
-- applier resolves names to the live tree). Ebonhold uses standard WotLK
-- paladin trees. Ebonhold grants far more than 71 points, so these are
-- generous "take all the good stuff" lists; the applier fills what your points
-- allow, lowest tiers first.
-- Exact 71-point dual-wield survival spec for the reworked (2026-08-27) trees,
-- built from the live /pp talentscan (tiers/columns verified). 43 Ret / 28 Prot.
-- Ret goes to tier 9 for Crusader Strike (the CS gate is 40 pts) + Sheath of
-- Light; Prot funds survival (Divinity/Anticipation/Toughness) and reaches
-- One-Handed Weapon Specialization (tier 6 = the dual-wield damage talent for
-- Ambidexterity's two 1H weapons — never the Two-Handed one). Divine Storm
-- (tier 11 / 50 Ret) is skipped: the echoes already carry the AoE.
-- Full 96-point spec (base 71 + the 25 max ranks of the ash "Talent Overflow"
-- node). 52 Ret / 44 Prot: deep Ret through Divine Storm PLUS a full Prot
-- survival spine (Ardent Defender cheat-death) and One-Handed Weapon Spec for
-- the dual-wield. The `priority` list is the IMPORTANCE order the applier fills
-- in (tier-legal): with only ~83-87 points unlocked you still get every key
-- talent; the last ~9 (climbing to 96) go to the filler at the tail.
B.talentTemplates = {
  ["prot-ret"] = {
    name = "Dual-Wield Ret/Prot (96pt, ash-extended)",
    talents = {
      -- Retribution (52) — through Divine Storm
      ["Deflection"] = 5, ["Improved Judgements"] = 2, ["Heart of the Crusader"] = 3,
      ["Improved Blessing of Might"] = 2, ["Conviction"] = 5, ["Seal of Command"] = 1,
      ["Crusade"] = 3, ["Sanctity of Battle"] = 3, ["Sanctified Retribution"] = 1,
      ["Vengeance"] = 3, ["Divine Purpose"] = 2, ["Judgements of the Wise"] = 3,
      ["The Art of War"] = 2, ["Repentance"] = 1, ["Fanaticism"] = 3,
      ["Sanctified Wrath"] = 2, ["Crusader Strike"] = 1, ["Sheath of Light"] = 3,
      ["Swift Retribution"] = 3, ["Righteous Vengeance"] = 3, ["Divine Storm"] = 1,
      -- Protection (44) — survival spine + dual-wield
      ["Divinity"] = 5, ["Divine Strength"] = 5, ["Anticipation"] = 5,
      ["Guardian's Favor"] = 2, ["Stoicism"] = 1, ["Toughness"] = 5,
      ["Improved Righteous Fury"] = 3, ["Improved Devotion Aura"] = 3,
      ["Divine Guardian"] = 2, ["Reckoning"] = 5,
      ["One-Handed Weapon Specialization"] = 3, ["Sacred Duty"] = 2,
      ["Ardent Defender"] = 3,
    },
    -- Importance order (most valuable first); the applier fills these first,
    -- always tier-legally, so scarce points buy the best talents.
    priority = {
      "Divinity", "Divine Strength", "Anticipation", "Toughness",
      "One-Handed Weapon Specialization", "Conviction", "Ardent Defender",
      "Heart of the Crusader", "Crusader Strike", "Sheath of Light",
      "Judgements of the Wise", "Fanaticism", "Vengeance", "Crusade",
      "Sanctity of Battle", "Divine Purpose", "Righteous Vengeance",
      "Seal of Command", "The Art of War", "Sanctified Wrath", "Swift Retribution",
      "Deflection", "Improved Blessing of Might", "Improved Judgements",
      "Sanctified Retribution", "Reckoning", "Improved Devotion Aura",
      "Sacred Duty", "Divine Storm", "Guardian's Favor", "Stoicism",
      "Divine Guardian", "Improved Righteous Fury", "Repentance",
    },
  },
}
B.defaultTemplate = "prot-ret"
-- The full reworked (2028-08-27) Paladin trees, scraped from the site's Talent
-- Calculator: NAME = maxRank, per tree. Reference for building/validating
-- templates (the trees kept standard WotLK names + positions; effects were
-- rebalanced). Used by nothing at runtime yet — data for the next tune.
B.talentTrees = {
  Retribution = {
    ["Deflection"]=5, ["Benediction"]=5, ["Improved Judgements"]=2,
    ["Heart of the Crusader"]=3, ["Improved Blessing of Might"]=2, ["Vindication"]=2,
    ["Conviction"]=5, ["Seal of Command"]=1, ["Divine Steed"]=1, ["Eye for an Eye"]=2,
    ["Sanctity of Battle"]=3, ["Crusade"]=3, ["Two-Handed Weapon Specialization"]=3,
    ["Sanctified Retribution"]=1, ["Vengeance"]=3, ["Divine Purpose"]=2,
    ["The Art of War"]=2, ["Repentance"]=1, ["Judgements of the Wise"]=3,
    ["Fanaticism"]=3, ["Sanctified Wrath"]=2, ["Swift Retribution"]=3,
    ["Crusader Strike"]=1, ["Sheath of Light"]=3, ["Righteous Vengeance"]=3,
    ["Divine Storm"]=1,
  },
  Protection = {
    ["Divinity"]=5, ["Divine Strength"]=5, ["Stoicism"]=1, ["Guardian's Favor"]=2,
    ["Anticipation"]=5, ["Divine Sacrifice"]=1, ["Improved Righteous Fury"]=3,
    ["Toughness"]=5, ["Divine Guardian"]=2, ["Improved Hammer of Justice"]=2,
    ["Improved Devotion Aura"]=3, ["Blessing of Sanctuary"]=1, ["Reckoning"]=5,
    ["Sacred Duty"]=2, ["One-Handed Weapon Specialization"]=3, ["Spiritual Attunement"]=2,
    ["Holy Shield"]=1, ["Ardent Defender"]=3, ["Redoubt"]=3, ["Combat Expertise"]=3,
    ["Touched by the Light"]=3, ["Avenger's Shield"]=1, ["Guarded by the Light"]=2,
    ["Shield of the Templar"]=3, ["Judgements of the Just"]=2, ["Hammer of the Righteous"]=1,
  },
}

-- Per-slot named BiS (GearAudit reads PP.Build.bis). Moved here from GearAudit's
-- GA.BIS so the paladin ships its own data like every other class. Crit/haste ICC
-- bases (Ebonhold meta, not retail Ret); 4 tier pieces (1/3/5/7/10) hold T10.5 4pc.
B.bis = {
  [1]  = { item = "Sanctified Lightsworn Helmet", src = "ICC 25H tier", ilvl = 277, why = "T10.5 str/crit/haste; anchors 4pc" },
  [2]  = { item = "Ahn'kahar Onyx Neckguard", src = "Lady Deathwhisper 25H", ilvl = 277, why = "str + crit + haste + socket" },
  [3]  = { item = "Sanctified Lightsworn Shoulderplates", src = "ICC 25H tier", ilvl = 277, why = "T10.5 str/crit/haste; 4pc" },
  [5]  = { item = "Sanctified Lightsworn Battleplate", src = "ICC 25H tier", ilvl = 277, why = "T10.5 str/crit/haste; 4pc" },
  [6]  = { item = "Coldwraith Links", src = "Valithria cache 25H", ilvl = 277, why = "plate belt w/ crit+haste; fixes weak waist" },
  [7]  = { item = "Sanctified Lightsworn Legplates", src = "ICC 25H tier", ilvl = 277, why = "T10.5 str/crit/haste; keeps 4pc" },
  [8]  = { item = "Frostbitten Fur Boots", src = "Marrowgar 25H", ilvl = 277, why = "leather, but max crit+haste (no str-plate boot)" },
  [9]  = { item = "Polar Bear Claw Bracers", src = "Gunship 25H", ilvl = 277, why = "best crit/haste plate wrist + socket" },
  [10] = { item = "Sanctified Lightsworn Gauntlets", src = "ICC 25H tier", ilvl = 277, why = "T10.5 str/crit/haste; 4pc", alt = "Fleshrending Gauntlets (Festergut 25H) if not running 4pc" },
  [11] = { item = "Ashen Band of Endless Vengeance", src = "Ashen Verdict - Exalted", ilvl = 277, why = "crit + hit + AP-on-hit proc" },
  [12] = { item = "Frostbrood Sapphire Ring", src = "Valithria cache 25H", ilvl = 277, why = "top crit+haste ring" },
  [13] = { item = "Tiny Abomination in a Jar", src = "Putricide 25H", ilvl = 277, why = "hit + Mote of Anger proc; top melee trinket" },
  [14] = { item = "Comet's Trail", src = "Algalon, Ulduar 25", ilvl = 239, why = "str + on-hit haste proc", alt = "Deathbringer's Will (Saurfang 25H, 277) if you drop the haste" },
  [15] = { item = "Shadowvault Slayer's Cloak", src = "Gunship 25H", ilvl = 277, why = "most crit+haste for the slot" },
  [16] = { item = "Royal Scepter of Terenas II", src = "Lich King 25H", ilvl = 284, why = "SP mace: crit+haste; maces always usable" },
  [17] = { item = "Heaven's Fall, Kryss of a Thousand Lies", src = "Lich King 25H", ilvl = 284, why = "fast dagger, max crit/haste OH", alt = "2nd Royal Scepter -- no weapon unlock needed" },
  [18] = { item = "Corpse-Impaling Spike", src = "Rotface 25H", ilvl = 277, why = "caster wand: crit+haste+SP", alt = "Zod's Repeating Longbow (277), or Libram of Valiance relic" },
}

-- Rotation HUD priority (RotationHelper reads PP.Build.rotationPriority). Moved
-- here from RotationHelper's baked PRIORITY. Upkeep stays MODULE-SIDE (its dynamic
-- ActiveSealName() handles Alliance/Horde), so there is deliberately no
-- B.rotationUpkeep here -- a static list would break Horde seal detection.
B.rotationPriority = {
  { spell = "Judgement of Light" },
  { spell = "Crusader Strike" },
  { spell = "Divine Storm" },
  { spell = "Hammer of Wrath", cond = function()
      local rh = PP.RotationHelper
      return rh and rh.TargetPct and (rh.TargetPct() or 100) <= 20 end },
  { spell = "Exorcism", cond = function()
      local rh = PP.RotationHelper
      return rh and rh.HasBuff and rh.HasBuff("The Art of War") end },
  { spell = "Holy Wrath" },
  { spell = "Consecration" },
}

-- EBH synergy bundles (moved here from HubSync so each class ships its own).
-- +40 bundle score to members while the main (first) echo is active -- a scoring
-- lever no community build uses. HubSync reads PP.Build.bundles. These are the
-- MEASURED paladin packages (blades = the dual-wield melee core; cyclones/plague
-- = the fire/frost/plague proc webs).
B.bundles = {
  { id = "ppb-resonant", tier = "S",
    echoes = { "Resonant Build", "Strength Training", "Agility Boost",
               "Iron Constitution" } },
  { id = "ppb-dots", tier = "S",
    echoes = { "Contagion", "Echoing Tides", "Scorching Wounds", "Open Wounds",
               "Hungering Curse", "Necrotic Plague", "Accelerated Decay" } },
  { id = "ppb-blades", tier = "S",
    echoes = { "Ambidexterity", "Second Edge", "First Strike",
               "Expertise Drills", "Armor Penetration", "Weapon Mastery" } },
  { id = "ppb-cyclones", tier = "S",
    echoes = { "Cinders of the Sanctum", "Cyclone of Cold Bones",
               "Permafrost Aura", "Frostfire Paradox", "Scorched Path",
               "Conjured Flame", "Flame Beacon", "Brittle Forging" } },
  { id = "ppb-plague", tier = "S",
    echoes = { "Malleable Goo", "Slime Spray", "Inhaled Blight",
               "Hungering Curse", "Curse of the Plaguebringer",
               "Necrotic Plague", "Mutagenic Fumes" } },
}
-- EBH build spec tab HubSync tags the synced build with (paladin: 3 = Retribution).
B.specIndex = 3

-- Per-slot affix targets for the Gear page (GearAudit.Judge reads
-- PP.Build.slotTargets, preferred first; position 1 is what "re-roll to X" names).
--
-- REFRESHED off the stale AotC-I SURVIVAL school (Ironhide / Iron Will) that the
-- Gear page used to grade against -- that was the right answer when the goal was
-- AotC I, and wrong for the crit/haste HC climb. Survival affixes stay in the list
-- as ACCEPTABLE (tail) so existing defensive pieces read "ok, raise the rank"
-- rather than a wall of "wrong affix" telling you to re-roll good gear.
--
-- SLOTS: EbonholdHub's AffixCatalog (live server dump, 66 affixes) carries NO
-- per-slot restriction on any entry -- the only real rule is armor affixes (legal
-- on anything, weapons included) vs `weapon = true` affixes (weapons only). The
-- old one-affix-per-slot map was curated advice, not a game rule; keepsy's own
-- Main Hand carries Iron Will, which that map disallowed. So: one ordered list
-- for every slot, weapon-only affixes pushed to the front on the weapon slots.
--
-- SPELLINGS: Judge() matches the ITEM NAME text, and per EbonholdHub's
-- AffixData.ITEM_ALIASES the item text differs from the canonical affix name for
-- several affixes ("Keen Strike"->Keen Strikes, "Enduring Flesh"->Ironhide,
-- "Judgment"->Judgement, "Swift Footwork"->Feral Grace, "Precision"->Cold).
-- Membership is just a lookup, so BOTH spellings are listed -- that kills the
-- false-"wrong affix" failure mode instead of leaving it for the player to hit.
B.slotTargets = {}
do
  local common = {
    "Keen Strikes", "Keen Strike",        -- crit: top offence affix (both spellings)
    "Relentless Crits",                   -- crit scaling
    "Quick Instincts", "Temporal Flux",   -- haste (stat priority #2)
    "Overwhelming Force",                 -- damage / pressure
    "Fortified by Pain",                  -- damage + defensive scaling
    "Spell Mastery",                      -- feeds the spell/DoT half of the kit
    "Iron Will",                          -- Strength / effective-HP chain
    "Ironhide", "Enduring Flesh",         -- HP backbone (both spellings)
    "Thick Hide", "Stalwart",
  }
  for slot = 1, 19 do B.slotTargets[slot] = common end
  -- Weapons: Judgement is an ECHO TRIGGER (procs Arcane Cadence), not a damage
  -- number -- keep it on a weapon. Vulnerability/Flurry are the damage pair.
  local wep = { "Judgement", "Judgment", "Vulnerability", "Flurry" }
  for _, a in ipairs(common) do wep[#wep + 1] = a end
  B.slotTargets[16] = wep   -- Main Hand
  B.slotTargets[17] = wep   -- Off Hand
end

-- Echoes that FarmQueue should treat as build targets worth farming Tomes for
-- (locked core + S-tier). Returns a de-duplicated array of names.
function B.FarmTargets()
  local seen, out = {}, {}
  local function add(name)
    if name and not seen[name] then seen[name] = true; out[#out + 1] = name end
  end
  for _, n in ipairs(B.locked) do add(n) end
  for _, n in ipairs(B.tiers.S) do add(n) end
  return out
end

-- The measured damage engine: the procs that carried 81-96% of keepsy's damage
-- across the benchmark logs (fire/frost/plague school). These are the echoes
-- whose EPIC quality actually moves your DPS — the ones worth spending orbs to
-- Epic-ify. Everything else is breadth (keep it, don't fish it).
function B.TopProcs()
  return {
    "Cinders of the Sanctum", "Malleable Goo", "Slime Spray",
    "Cyclone of Cold Bones", "Inhaled Blight", "Necrotic Plague",
    "Crypt Lord's Swarm", "Permafrost Aura",
  }
end

-- Tier lookup for a given echo name (for DrawHelper).
function B.TierOf(name)
  if not name then return nil end
  for tier, list in pairs(B.tiers) do
    for _, n in ipairs(list) do if n == name then return tier end end
  end
  for _, n in ipairs(B.disable) do if n == name then return "F" end end
  return nil
end
