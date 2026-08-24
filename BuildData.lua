-- PallyPilot BuildData: the curated solo-Retribution paladin build.
-- This is OUR data (synthesized from EbonholdHub builds + the #paladin Discord
-- + the player guide). All PallyPilot features read from this one table.
local PP = PallyPilot
local B = {}
PP.Build = B

B.title = "Solo Retribution — Road to AotC I"
B.spec = "Retribution"

-- Stat priority (Nero's endgame build): Strength is the keystone (AP -> SP),
-- then Crit + Haste. One non-Strength exception: a ToC25H Crit/Haste gun.
B.statPriority = { "Strength", "Critical Strike", "Haste" }
B.statNote = "Strength is king: it gives Attack Power, and AP converts to Spell "
  .. "Power, feeding your whole hybrid kit. Reject gear with no Strength — the "
  .. "only exception is a Crit/Haste (Agility) gun from ToC 25H in the ranged slot."

-- Weapon enchants and talent flex notes.
B.enchants = "Weapons: Flurry + Vulnerability. Talent flex points into Divine "
  .. "Storm for extra Arcane Cadence triggers."

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
B.talents = "≈ 44 Protection / 49 Retribution hybrid for soloing (survivability "
  .. "under full Ret damage). Pure-damage farmers drop the Prot side once the "
  .. "Soul Ash tree carries survival."

-- The six echoes to lock so they persist across runs.
B.locked = {
  "Sanguine Bulwark", "Twilight Equilibrium", "Constellations",
  "Pandemic", "Adaptive Power", "Exposed Heart",
}

-- Draw priority tiers. On a level-up selection (and Orb rerolls), take the
-- highest tier offered. These names are also the farm targets (see FarmQueue).
B.tiers = {
  S = {
    "Twilight Equilibrium", "Constellations", "Pandemic", "Sanguine Bulwark",
    "Adaptive Power", "Exposed Heart", "Edict of the Four", "Edict of the Iron Council",
    "Harbringer of Doom", "Blood Mirror", "Contagion", "Resonant Build",
    "Temporal Flow", "Chronoboost", "Energy Overflow", "Storm Conductor",
    "Flame Vents", "Nether Lord's Command", "Twin Casting", "Second Edge",
    "First Strike", "Perfect Timing", "Crypt Lord's Swarm", "Rage of the Colossus",
    "Burning Flames", "Spellweave",
    -- Catalog finds promoted to curated S (priority order matters for locks):
    "Sanctum Sentries", "Arcane Cadence", "Reaper's Reprieve",
    -- Dual-wield enabler — the weapon setup depends on it. Never reroll.
    "Ambidexterity",
  },
  A = {
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
  ["Arcane Bombardment"] = "A", ["Paladin - Arcane Bombardment"] = "A", -- CS/Judgement fire 2 big arcane missiles
  ["Stonefist Barrage"] = "A", ["Paladin - Stonefist Barrage"] = "A",   -- every Judgement hurls an AoE boulder
  ["Blade Tempest"] = "A",      -- phys-on-DoT summons 36k/s whirlwind clone
  ["Broodmother's Fury"] = "A", -- cinder stacks into 121k Deep Breath
  ["Call of the Lich King"] = "A",
  ["Crimson Reprisal"] = "A",   -- JoL/FoL heals deal 15% as damage
  ["Crusader's Surge"] = "A",   -- chance for instant Exorcism/FoL/HL
  ["Crushing Finish"] = "A",    -- execute, scales with Expertise
  ["Crushing Force"] = "A",     -- crit-rating stat echo (stat prio #2)
  ["Cyclone of Cold Bones"] = "A",
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
  ["Sweeping Blows"] = "A", ["The Harvester's Tithe"] = "A",
  ["Tunnel Vision"] = "A",      -- +8% sustained single-target (bosses)
  -- B: fine filler (verified minor/situational; several trigger only off
  -- OTHER echoes' fire/frost/shadow/nature damage — synergy picks)
  ["Archmage's Mark"] = "B", ["Arcane Ward"] = "B",
  ["Backstabber's Edge"] = "B", ["Battle Tempo"] = "B",
  ["Battlefield Hazard"] = "B", ["Beast Slayer"] = "B",
  ["Blighted Hazard"] = "B", ["Broodmother's Webbing"] = "B",
  ["Champion's Rally"] = "B", ["Chaotic Convergence"] = "B",
  ["Chill of the Bone Wyrm"] = "B", ["Cinders of the Sanctum"] = "B",
  ["Conjured Flame"] = "B", ["Crippling Strikes"] = "B",
  ["Curse of the Plaguebringer"] = "B", ["Dark Nucleus"] = "B",
  ["Demon Slayer"] = "B", ["Divine Resonance"] = "B", ["Dragon Slayer"] = "B",
  ["Drillmaster's Rebuke"] = "B", ["Earthen Snap"] = "B",
  ["Earthen Spike"] = "B", ["Earthen Stability"] = "B",
  ["Elemental Slayer"] = "B", ["Ember Spark"] = "B",
  ["Paladin - Ember Spark"] = "B",
  ["Ember Ward"] = "B", ["Emberlord's Gift"] = "B",
  ["Emerald Vigor"] = "B",      -- ally-targeted; self may not count solo
  ["Eonar's Seed"] = "B", ["Essence Tap"] = "B",
  ["Flame Beacon"] = "B", ["Forged in Combat"] = "B", ["Fortress Soul"] = "B",
  ["Frost Bite"] = "B", ["Frost Ward"] = "B", ["Frostfire Paradox"] = "B",
  ["Frostguard Carapace"] = "B", ["Giant Slayer"] = "B", ["Grim Resolve"] = "B",
  ["Hardened Resolve"] = "B", ["Hardened Skin"] = "B",
  ["Harpoon Barrage"] = "B", ["Holy Hazard"] = "B",
  ["Inhaled Blight"] = "B", ["Insulated Soul"] = "B",
  ["Lightning Charged"] = "B", ["Machine Slayer"] = "B", ["Malleable Goo"] = "B",
  ["Mana Infusion"] = "B",      -- verified: mana returns also heal above 80% mana
  ["Mutagenic Fumes"] = "B", ["Opening Split"] = "B",
  ["Permafrost Aura"] = "B", ["Permeating Chill"] = "B", ["Polarity Shift"] = "B",
  ["Prismatic Guard"] = "B", ["Raging Momentum"] = "B",
  ["Ravenous Bellow"] = "B", ["Reactive Retaliation"] = "B",
  ["Reinforced Shielding"] = "B", ["Relentless Energy"] = "B",
  ["Rocket Strike"] = "B", ["Rootbreaker"] = "B",
  ["Ruthless Exploiter"] = "B", -- +20% vs CC'd only; raid bosses are CC-immune
  ["Sanctified Sky"] = "B", ["Scorched Path"] = "B",
  ["Shadow Crash"] = "B", ["Shadow Hazard"] = "B", ["Shadow Ward"] = "B",
  ["Sharpened Edge"] = "B",     -- verified: small flat adder, not % damage
  ["Shielded Steps"] = "B", ["Shock Vortex"] = "B", ["Slime Spray"] = "B",
  ["Slimebound Husk"] = "B", ["Spell Harmony"] = "B", ["Spiteful Shard"] = "B",
  ["Spiteful Thorns"] = "B", ["Steady Grip"] = "B",
  ["Stone Shatter"] = "B", ["Stoneskin Threads"] = "B",
  ["Stored Momentum"] = "B", ["Storm Hazard"] = "B", ["Sundered Will"] = "B",
  ["Swift Step"] = "B",
  ["The Sporelord's Gift"] = "B", -- buffs "nearby allies"; solo value unclear
  ["The Unclean's Fever"] = "B",
  ["Titan's Grip"] = "B",       -- 2H-in-one-hand at -20% dmg; test vs 1H pair
  ["Toxic Phials"] = "B", ["Twilight Combustion"] = "B",
  ["Undead Bane"] = "B",        -- +600 SP vs undead; SP is secondary but real
  ["Verdant Ward"] = "B", ["Warm-Blooded"] = "B",
  ["Widow's Venom"] = "B", ["Wild Hazard"] = "B",
  -- F: verified dead weight or traps for this build
  ["Accelerated Spirit"] = "F", ["Agility Boost"] = "F", ["Arcane Burn"] = "F",
  ["Arcane Hazard"] = "F", ["Arcane Surge"] = "F",
  ["Armor Mastery"] = "F",      -- you already wear plate
  ["Beast Bane"] = "F",
  ["Bolstered Vitality"] = "F", -- +175 flat HP on a 111k pool
  ["Burning Touch"] = "F", ["Cavalry Instincts"] = "F", ["Demon Bane"] = "F",
  ["Divine Surge"] = "F", ["Dragonkin Bane"] = "F", ["Drained Reserves"] = "F",
  ["Efficient Casting"] = "F", ["Elemental Bane"] = "F",
  ["Enhanced Recovery"] = "F",  -- verified: it's +1% healing received. One.
  ["Entropic Fusion"] = "F", ["Fel Hazard"] = "F", ["Fel Surge"] = "F",
  ["Giant Bane"] = "F", ["Glass Canon"] = "F", -- +dmg taken kills Hardcore runs
  ["Healing Cadence"] = "F", ["Healing Echo"] = "F",
  ["Heavy Blows"] = "F",        -- verified: -30% attack speed; dual-wield poison
  ["Heavy Incantations"] = "F", ["Holy Revelation"] = "F",
  ["Hunting Hazard"] = "F", ["Inspiring Mending"] = "F", ["Leadfoot"] = "F",
  -- Tooltip-verified trap: -50% crit CHANCE for +30% crit damage. Zeroes a
  -- ~44% crit build; only sane at 90%+ crit. (Field report 2026-08-25.)
  ["Lethal Precision"] = "F",
  ["Lingering Inspiration"] = "F",
  ["Mana Regeneration"] = "F", ["Mana Reservoir"] = "F",
  ["Mechanical Bane"] = "F", ["Meditative Flow"] = "F", ["Mind Expansion"] = "F",
  ["Nature's Surge"] = "F", ["Overwhelming Restoration"] = "F",
  ["Provoking Presence"] = "F", -- threat is meaningless solo
  ["Runic Momentum"] = "F",     -- runic power: dead resource for a paladin
  ["Spiritual Fortitude"] = "F", ["Steady Casting"] = "F",
  ["Steady Channeling"] = "F", ["Stitched Fury"] = "F", -- requires living <15% HP
  ["Storm of the Spellweaver"] = "F", ["Subtle Presence"] = "F",
  ["The Last Wall"] = "F",      -- verified: -60% healing received guts JoL sustain
  ["Unbroken Focus"] = "F",     -- needs 5s without damage; solo melee never has it
  ["Unstable Missiles"] = "F",
}

-- Echoes to disable / banish. Rage- and runic-power-scaling echoes are dead for
-- a mana class; the others are traps for this build.
B.disable = {
  "Warded Aegis", "Brittle Armor", "Overcharged",
  -- Ebonhold lists this one both ways depending on the UI.
  "Paladin - Corrosive Breath", "Corrosive Breath",
}
B.disableNote = "Also disable any echo that scales with RAGE or RUNIC POWER — "
  .. "you're a mana class, so they do nothing. The mana-resource echo DOES work."

-- Item affixes — two schools (Enchanted Anvil, Dalaran).
B.affixSurvival = {
  { affix = "Ironhide", role = "Flat % HP", slots = "Head · Shoulder · Legs · Ring · Ranged" },
  { affix = "Iron Will", role = "Effective HP / Strength", slots = "Chest · Shirt · Wrist · Feet" },
  { affix = "Fortified by Pain", role = "Defensive scaling", slots = "Hands · Waist · Ring · Off-hand" },
  { affix = "Overwhelming Force", role = "Damage / pressure", slots = "Neck · Back · Tabard · Trinket" },
}
B.affixDamage = {
  { affix = "Iron Will 6→2", role = "Primary Strength conversion chain" },
  { affix = "Iron Hide 6/5/4", role = "HP backbone" },
  { affix = "Thick Hide 6", role = "Mitigation" },
  { affix = "Keen Strike 6/5", role = "Offense" },
  { affix = "Crits 6", role = "Crit scaling" },
  { affix = "Pain 6/5/4", role = "Damage scaling" },
  { affix = "Spell Mastery 4", role = "Feeds spell/DoT side" },
  { affix = "Force 6", role = "Offense" },
}
B.affixNote = "Judgement affix is an ECHO TRIGGER, not a damage source — keep it "
  .. "on the weapon(s) for the proc, not the tooltip number. Weapon affixes stack; "
  .. "dual-wield can carry the same affix on both hands."

-- Gear targeting (per-slot guidance for the AotC I push).
B.gear = {
  { slot = "Weapon(s)", target = "Highest-Str one-handers (dual-wield for Ambidex); enchant Flurry + Vulnerability" },
  { slot = "Head / Shoulder / Chest", target = "Set pieces with Crit + Haste + Strength" },
  { slot = "Ranged", target = "ToC 25H Crit/Haste gun (the one Agility exception)" },
  { slot = "Everything else", target = "Epic (ilvl 213+) in every slot with Strength — also completes the Epic +5% multiplier" },
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
B.talentTemplates = {
  ["prot-ret"] = {
    name = "Prot/Ret Solo Hybrid",
    talents = {
      -- Retribution core (damage)
      ["Deflection"] = 5, ["Benediction"] = 5, ["Improved Blessing of Might"] = 2,
      ["Heart of the Crusader"] = 3, ["Improved Judgements"] = 2, ["Conviction"] = 5,
      ["Seal of Command"] = 1, ["Crusade"] = 3,
      ["Sanctified Retribution"] = 1, ["Vengeance"] = 3, ["The Art of War"] = 2,
      ["Repentance"] = 1, ["Judgements of the Wise"] = 3, ["Fanaticism"] = 3,
      ["Swift Retribution"] = 3, ["Sheath of Light"] = 3, ["Righteous Vengeance"] = 3,
      ["Divine Storm"] = 1, ["Divine Purpose"] = 2, ["Crusader Strike"] = 1,
      -- Protection survival
      ["Divinity"] = 5, ["Divine Strength"] = 5, ["Stoicism"] = 3,
      ["Guardian's Favor"] = 2, ["Anticipation"] = 5, ["Improved Righteous Fury"] = 3,
      ["Toughness"] = 5, ["Reckoning"] = 5,
      ["Sacred Duty"] = 2, ["Ardent Defender"] = 3, ["Redoubt"] = 3,
      ["Combat Expertise"] = 3, ["Touched by the Light"] = 3, ["Shield of the Templar"] = 3,
      ["Judgements of the Just"] = 2, ["Spiritual Attunement"] = 2,
    },
  },
}
B.defaultTemplate = "prot-ret"

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

-- Tier lookup for a given echo name (for DrawHelper).
function B.TierOf(name)
  if not name then return nil end
  for tier, list in pairs(B.tiers) do
    for _, n in ipairs(list) do if n == name then return tier end end
  end
  for _, n in ipairs(B.disable) do if n == name then return "F" end end
  return nil
end
