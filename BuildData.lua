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
  },
  A = {
    "Accelerated Decay", "Quickened Tempo", "Quickening Aura", "Arcane Density",
    "Rend the Weak", "Iron Constitution", "Brutal Might", "Scorching Wounds",
    "Battle Rhythm", "Relentless Rhythm", "Tempest Vortex", "Strength Training",
    "Focused Assault", "Mystic Potency", "Reaper's Doom", "Weapon Mastery",
  },
  B = {
    "Steel Brand", "Bolstered Vitality", "Pain Drive", "Holy Brand",
    "Double Strike", "Desperate Escape", "Battle Momentum", "Arcane Weapon",
  },
}

-- Echoes to disable / banish. Rage- and runic-power-scaling echoes are dead for
-- a mana class; the others are traps for this build.
B.disable = {
  "Warded Aegis", "Brittle Armor", "Overcharged", "Paladin - Corrosive Breath",
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
B.talentTemplates = {
  ["prot-ret"] = {
    name = "Prot/Ret Solo Hybrid (44/49)",
    total = 93,
    tabs = {
      [1] = {},
      [2] = { 0,5,2,0,5,0,3,5,0,0,0,1,5,2,3,0,1,3,2,3,3,1,0,0,0,0 },
      [3] = { 0,5,2,3,2,1,5,0,2,2,3,3,0,1,3,2,2,1,3,0,0,3,1,3,2,0 },
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
