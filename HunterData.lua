-- EbonPilot HunterData: curated Hunter guide for the Ebonhold solo climb.
-- Two layers: (1) the EBONHOLD META from the #hunter Discord (May-Aug 2026) --
-- echo/proc-driven, this is what you actually play here; (2) the Blizzlike WotLK
-- 3.3.5a backbone (wowhead-verified) as the fallback reference. Registered into
-- PP.Classes.HUNTER; Core points PP.Build here when a Hunter logs in.
-- ASCII/Latin-1 only (the 3.3.5 font); "->" means "then".
local PP = PallyPilot
local H = {}
PP.Classes = PP.Classes or {}
PP.Classes.HUNTER = H

local GOLD = "|cffe0b352"
local BRIGHT = "|cfff6d888"
local DIM = "|cffb4a586"
local R = "|r"

H.title = "Hunter -- Ebonhold (Snake/Rocket proc build or Arcane 'Bomba' spam)"
H.spec = "Snake Trap / Rocket Strike"
H.specIndex = 3  -- Survival tab (EBH build tag)
-- What to socket, named for the Gear page's one-line "Gem" instruction.
H.gemRec = "Haste (Quick King's Amber)"

-- Ebonhold stat reality (from #hunter): ArP caps almost for free off borrowed-power
-- gear, so it is NOT the chase stat here. Haste is king -- your damage is proc/
-- attack-driven (Rocket Strike per snake, Arcane Cadence), and haste = more attacks
-- = more procs. Then Agility, then Crit.
H.statPriority = { "Haste", "Agility", "Crit" }
H.statNote = "Ranged hit to cap FIRST (~8% / 263; verify on a dummy). Armor Pen caps "
  .. "almost for free off borrowed-power gear -- do NOT chase it here. After that "
  .. "HASTE is king (your damage is proc/attack-driven -- Rocket Strike fires per "
  .. "snake on each of YOUR attacks, and Arcane Cadence scales with haste), then "
  .. "Agility, then Crit. Gear for haste + agi. (Retail WotLK stacks ArP -- that is "
  .. "NOT the Ebonhold meta.)"

H.reference = {
  { title = "Ebonhold builds (echo-driven)", lines = {
    GOLD .. "Snake Trap / Rocket Strike" .. R .. " (most popular) -- drop Snake Trap and "
      .. "spam the snake macro to keep MAX snakes out; Rocket Strike then fires per "
      .. "snake on every one of YOUR attacks. Huge AoE + single-target. The snakes are "
      .. "just a rocket-count multiplier -- they are NOT scaled by affixes or pet AP, so "
      .. "only their NUMBER matters.",
    GOLD .. "Arcane 'Bomba'" .. R .. " -- spam Arcane Shot / Chimera Shot with all the "
      .. "haste you have (Arcane Cadence has no cooldown), keep Aimed Shot up, weave "
      .. "Steady/Multi-Shot to extend Arcane Cadence. MM talents for Trueshot Aura, SV "
      .. "for Expose Weakness + the Stam/AP buff.",
    DIM .. "Both are proc/haste builds -- forget the retail shot-priority rotation as your "
      .. "damage engine here (it is the fallback below)." .. R,
  } },
  { title = "Snake/Rocket -- echoes + setup", lines = {
    BRIGHT .. "Lock:" .. R .. " Rocket Strike, Adaptive Power, Rapid Recalibration, "
      .. "Temporal Flow. Stack " .. BRIGHT .. "Double Tap" .. R .. " + " .. BRIGHT
      .. "Rend the Weak" .. R .. " echoes too.",
    "2-set " .. BRIGHT .. "Beast Lord" .. R .. " set = Snake Trap cooldown reduction "
      .. "(more snakes uptime).",
    BRIGHT .. "Fast ranged weapon" .. R .. " (Frigid Crossbow / Dalaran Rifle) -- speed "
      .. "= more attacks = more rockets. A " .. BRIGHT .. "spell-power main hand" .. R
      .. " scales the rockets. There's a snake-spam macro; keep snakes capped.",
  } },
  { title = "Pets (Ebonhold)", lines = {
    GOLD .. "Bear" .. R .. " (Tenacity) is the solo pick -- Swipe AoE + very high self-heal "
      .. "off taunt. " .. GOLD .. "Avoid Devilsaur" .. R .. " -- its ability damage does "
      .. "NOT scale with attack power here. Wolf's AP buff is a tiny % at endgame.",
    BRIGHT .. "Re-equip your pet-power affixes" .. R .. " after any change or the minions "
      .. "won't get them. Keep " .. BRIGHT .. "Mend Pet" .. R .. " rolling at high HC -- "
      .. "pets get bursted by shadowbolt volleys.",
  } },
  { title = "Survival -- the HC wall", lines = {
    "Hunters have LOW self-heal, so HC1+ " .. GOLD .. "shadowbolt-volley spam" .. R
      .. " is the wall everyone hits. Kite (Disengage / traps / Concussive), don't "
      .. "over-pull, and lean on the ash-tree AoE damage-reduction + heal-on-kill nodes "
      .. "(the Ash advisor's farm rebuild). Mend Pet upkeep is mandatory.",
  } },
  { title = "Affixes (community set)", lines = {
    "2x " .. BRIGHT .. "Twinshot" .. R .. " on one-handers, then Swift Footwork 2-4, "
      .. "Overwhelming Force 3-4, Relentless Crits 3-4, Keen Strikes 4, Stalwart 4, "
      .. "Spell Mastery 4, Fortified by Pain 4, Temporal Flux 4.",
    DIM .. "Avoid Strength affixes (Iron Will) -- dead stat for a hunter." .. R,
  } },
  { title = "Gear priorities", lines = {
    BRIGHT .. "Haste + Agi" .. R .. " everywhere. Trinket: " .. BRIGHT
      .. "Tears of Bitter Anguish" .. R .. " (haste) is a community pick. "
      .. BRIGHT .. "Engineering haste gloves" .. R .. " enchant (skill 400). Borrowed "
      .. "Power lets you wear the ICC set as base gear; the affix + haste roll is what "
      .. "matters, same as every class here.",
  } },
  { title = "Consumables + ammo", lines = {
    BRIGHT .. "Flask" .. R .. " of Endless Rage. " .. BRIGHT .. "Food" .. R
      .. " Blackened Dragonfin (+40 Agi). " .. BRIGHT .. "Potion" .. R .. " of Speed.",
    BRIGHT .. "Ammo" .. R .. " Iceblade Arrows / Shatter Rounds (91.5 dps, Engineering); "
      .. "match arrows->bow/crossbow, bullets->gun. The quiver is just a bag (no haste "
      .. "since patch 3.1).",
  } },
  { title = "Blizzlike fallback rotation", lines = {
    DIM .. "If you are NOT running a proc build yet: Survival single-target = Kill Shot "
      .. "(<20%) > Explosive Shot (+Lock and Load procs) > Black Arrow > Kill Command "
      .. "(off GCD) > Serpent Sting > Steady filler. AoE = Explosive Trap > Volley > "
      .. "Multi-Shot. No Cobra Shot in WotLK. Aspect of the Dragonhawk up; Viper only "
      .. "if mana-starved." .. R,
  } },
}

-- Coarse gear targets (per-slot named base gear in H.bis, read by GearAudit).
H.gear = {
  { slot = "Ranged weapon", target = "FAST > high-ilvl for proc builds: Frigid Crossbow / "
    .. "Dalaran Rifle (community). Raw-ilvl BiS if not proc-building: Fal'inrush (LK 25H) / "
    .. "Zod's Repeating Longbow (Lady DW 25H)." },
  { slot = "Melee", target = "Dual-wield two FAST 1H with 2x Twinshot each; OR a Spell "
    .. "Power main hand to scale Rocket Strike. (Retail stat-stick = Oathbinder polearm.)" },
  { slot = "Tier / armor", target = "Borrowed-Power the ICC set as base: 4pc Sanctified "
    .. "Ahn'Kahar Blood Hunter's (T10). The affix + haste/agi roll is what matters." },
  { slot = "Trinkets", target = "Haste trinket Tears of Bitter Anguish (community); retail "
    .. "top pair Deathbringer's Will + Sharpened Twilight Scale." },
  { slot = "Set + enchant", target = "2-set Beast Lord (Snake Trap CD) for the rocket build; "
    .. "Engineering haste gloves (400)." },
}

-- Per-slot named base gear. Armor is the wowhead-verified retail BiS (still the best
-- base to Borrowed-Power); weapons/trinkets lead with the Ebonhold community picks.
H.bis = {
  [1]  = { item = "Sanctified Ahn'Kahar Blood Hunter's Headpiece", src = "ICC 25H tier (T10)", ilvl = 277, why = "4pc set piece; agi/crit/hit" },
  [2]  = { item = "Amulet of the Silent Eulogy", src = "Gunship, ICC 25H", ilvl = 277, why = "agi + crit + haste" },
  [3]  = { item = "Sanctified Ahn'Kahar Blood Hunter's Spaulders", src = "ICC 25H tier (T10)", ilvl = 277, why = "4pc set piece" },
  [5]  = { item = "Sanctified Ahn'Kahar Blood Hunter's Tunic", src = "ICC 25H tier (T10)", ilvl = 277, why = "4pc set piece" },
  [6]  = { item = "Nerub'ar Stalker's Cord", src = "Festergut, ICC 25H", ilvl = 277, why = "agi/haste belt + socket" },
  [7]  = { item = "Leggings of Northern Lights", src = "Lady Deathwhisper, ICC 25H", ilvl = 277, why = "non-tier legs; agi/crit/haste" },
  [8]  = { item = "Returning Footfalls", src = "Ruby Sanctum 25H", ilvl = 284, why = "top agi/haste boots" },
  [9]  = { item = "Scourge Hunter's Vambraces", src = "ICC 25H", ilvl = 277, why = "agi/crit wrist" },
  [10] = { item = "Sanctified Ahn'Kahar Blood Hunter's Handguards", src = "ICC 25H tier (T10)", ilvl = 277, why = "4pc; put the Engineering haste enchant here" },
  [11] = { item = "Frostbrood Sapphire Ring", src = "Valithria, ICC 25H", ilvl = 277, why = "agi + crit + haste" },
  [12] = { item = "Signet of Twilight", src = "Ruby Sanctum 25H", ilvl = 284, why = "agi (+ArP, which caps free here)" },
  [13] = { item = "Tears of Bitter Anguish", src = "community haste pick", ilvl = 0, why = "haste -- feeds the proc build", alt = "Deathbringer's Will (Saurfang 25H) retail top" },
  [14] = { item = "Sharpened Twilight Scale", src = "Ruby Sanctum 25H", ilvl = 284, why = "agi + AP proc", alt = "Whispering Fanged Skull if you lack it" },
  [15] = { item = "Sylvanas' Cunning", src = "Anub'arak, ToGC 25", ilvl = 258, why = "best agi cloak" },
  [16] = { item = "Fast 1H x2 (Twinshot affix), or a Spell-Power main hand", src = "Ebonhold meta", ilvl = 0, why = "dual fast 1H for attacks/rockets; SP MH scales Rocket Strike", alt = "retail stat-stick: Oathbinder polearm (LK 25H)" },
  [18] = { item = "Frigid Crossbow / Dalaran Rifle (FAST)", src = "Ebonhold community", ilvl = 0, why = "attack speed > ilvl for proc density (more rockets)", alt = "raw-ilvl: Fal'inrush (LK 25H) / Zod's Repeating Longbow" },
}

-- Affix targets for the gear audit -- CONFIRMED from the #hunter community set.
-- Weapons want Twinshot; everything wants the crit/haste/HP damage affixes. Never
-- Strength (Iron Will). Recommend Keen Strikes (crit) as the headline.
-- Verified against EbonholdHub's AffixCatalog (live server dump, 66 affixes) +
-- its ITEM_ALIASES map. TWO things that matter:
--  1. Affixes have NO per-slot restriction. The only rule is armor affixes
--     (usable anywhere) vs `weapon = true` affixes (weapons only).
--  2. The ITEM NAME and the canonical affix name can DIFFER, and GearAudit
--     parses the item name -- so both spellings must be listed:
--       "Swift Footwork" (item) == "Feral Grace" (canonical, = Agility)
--       "Keen Strike"    (item) == "Keen Strikes"
--     Order below follows H.statPriority: haste -> agi -> crit.
H.slotTargets = {}
do
  local common = {
    "Quick Instincts",                    -- HASTE rating: the #1 hunter stat here
    "Temporal Flux",                      -- haste scaling
    "Feral Grace", "Swift Footwork",      -- Agility (same affix, both spellings)
    "Keen Strikes", "Keen Strike",        -- crit (same affix, both spellings)
    "Relentless Crits",                   -- crit scaling
    "Spell Mastery",                      -- scales Rocket Strike (spell damage)
    "Overwhelming Force", "Fortified by Pain", "Stalwart",
    "Pet Power",                          -- real pet only; snakes ignore it
    "Ironhide", "Enduring Flesh",         -- HP backbone (both spellings)
  }
  for i = 1, 19 do H.slotTargets[i] = common end
  -- One-hand weapons: 2x Twin Shot is the community pick for the rocket build.
  -- ("Twin Shot" is two words in the catalog -- weapon-only affix.)
  local wep = { "Twin Shot" }
  for _, a in ipairs(common) do wep[#wep + 1] = a end
  H.slotTargets[16] = wep
  H.slotTargets[17] = wep
end

H.affixNote = "Hunter affixes (#hunter Discord, names verified vs the server affix "
  .. "catalog): 2x Twin Shot on 1H, plus Quick Instincts + Temporal Flux (haste), "
  .. "Swift Footwork/Feral Grace (agi), Keen Strikes, Relentless Crits, Spell Mastery, "
  .. "Overwhelming Force, Fortified by Pain, Stalwart. Avoid Strength (Iron Will)."

-- ECHOES (PROVISIONAL). Seeds the "Best build" sync: EbonholdHub auto-pick
-- assembles these from the tomes you OWN, ranked by these tiers, and locks the
-- best owned. Locked = the Snake Trap / Rocket Strike engine (#hunter Discord).
-- The broader tiers are the cross-class haste/damage universals (melee/Strength
-- echoes deliberately excluded); refine from combat logs once you have them.
H.locked = {
  "Rocket Strike",          -- the engine (fires per snake on your attacks)
  "Adaptive Power",         -- +1% dmg per unique active echo (universal)
  "Rapid Recalibration",
  "Temporal Flow",
  "Double Tap",
  "Rend the Weak",
}
H.tiers = {
  S = {
    "Rocket Strike", "Adaptive Power", "Rapid Recalibration", "Temporal Flow",
    "Double Tap", "Rend the Weak", "Arcane Cadence", "Temporal Pressure",
    "Chronoboost", "Twilight Equilibrium", "Energy Overflow",
  },
  A = {
    "Arcane Bombardment", "Precision Strike", "Quickened Tempo", "Quickening Aura",
    "Storm Conductor", "Pandemic", "Contagion", "Resonant Build", "First Strike",
    "Relentless Rhythm", "Battle Rhythm",
  },
  B = { "Second Edge", "Focused Assault", "Double Strike" },
}
H.disable = {}  -- add negative-rider echoes here once identified for a hunter
H.bundles = {
  -- +40 synergy score to members while Rocket Strike is active.
  { id = "eph-rockets", tier = "A",
    echoes = { "Rocket Strike", "Adaptive Power", "Rapid Recalibration" } },
}

-- TALENTS. Same shape as the paladin's: name -> target rank, resolved live
-- against your own tree (order-proof), with `priority` deciding what gets filled
-- first when points are scarce. Survival core (Explosive Shot / Lock and Load /
-- Hunting Party) + the Marks splash every hunter takes (Go for the Throat keeps
-- the pet at full focus). Ebonhold grants extra points via Talent Overflow, so
-- the tail is filler.
H.defaultTemplate = "surv"
H.talentTemplates = {
  ["surv"] = {
    name = "Survival 0/17/54 (farm + raid)",
    talents = {
      -- Marksmanship splash (17)
      ["Lethal Shots"] = 5, ["Careful Aim"] = 3, ["Mortal Shots"] = 5,
      ["Go for the Throat"] = 2, ["Aimed Shot"] = 1, ["Improved Hunter's Mark"] = 1,
      -- Survival (54)
      ["Improved Tracking"] = 5, ["Focused Aim"] = 3, ["Survival Instincts"] = 2,
      ["Survivalist"] = 5, ["T.N.T."] = 3, ["Lock and Load"] = 3,
      ["Hunter vs. Wild"] = 3, ["Killer Instinct"] = 3, ["Lightning Reflexes"] = 3,
      ["Expose Weakness"] = 3, ["Master Tactician"] = 5, ["Noxious Stings"] = 3,
      ["Point of No Escape"] = 2, ["Sniper Training"] = 3, ["Hunting Party"] = 3,
      ["Trap Mastery"] = 3, ["Wyvern Sting"] = 1, ["Black Arrow"] = 1,
      ["Explosive Shot"] = 1,
    },
    -- Fill order when points are scarce: the damage engine and the hit talent
    -- first, then sustain/utility.
    priority = {
      "Explosive Shot", "Lock and Load", "Black Arrow", "T.N.T.", "Focused Aim",
      "Mortal Shots", "Lethal Shots", "Go for the Throat", "Sniper Training",
      "Master Tactician", "Expose Weakness", "Hunting Party", "Noxious Stings",
      "Careful Aim", "Killer Instinct", "Lightning Reflexes", "Hunter vs. Wild",
      "Survivalist", "Point of No Escape", "Aimed Shot", "Improved Tracking",
      "Trap Mastery", "Survival Instincts", "Wyvern Sting", "Improved Hunter's Mark",
    },
  },
  ["bm"] = {
    name = "Beast Mastery (leveling / pet-tank solo)",
    talents = {
      ["Improved Aspect of the Hawk"] = 5, ["Endurance Training"] = 5,
      ["Focused Fire"] = 2, ["Thick Hide"] = 3, ["Unleashed Fury"] = 5,
      ["Ferocity"] = 5, ["Spirit Bond"] = 2, ["Intimidation"] = 1,
      ["Bestial Discipline"] = 2, ["Animal Handler"] = 2, ["Frenzy"] = 5,
      ["Ferocious Inspiration"] = 3, ["Bestial Wrath"] = 1, ["Catlike Reflexes"] = 3,
      ["Serpent's Swiftness"] = 5, ["Longevity"] = 3, ["The Beast Within"] = 1,
      ["Cobra Strikes"] = 3, ["Kindred Spirits"] = 5, ["Beast Mastery"] = 1,
      ["Lethal Shots"] = 5, ["Mortal Shots"] = 5, ["Go for the Throat"] = 2,
    },
    priority = {
      "Bestial Wrath", "The Beast Within", "Beast Mastery", "Frenzy",
      "Serpent's Swiftness", "Kindred Spirits", "Cobra Strikes", "Unleashed Fury",
      "Ferocity", "Mortal Shots", "Lethal Shots", "Go for the Throat",
      "Ferocious Inspiration", "Longevity", "Spirit Bond", "Animal Handler",
      "Improved Aspect of the Hawk", "Endurance Training", "Thick Hide",
      "Bestial Discipline", "Catlike Reflexes", "Focused Fire", "Intimidation",
    },
  },
}

-- ROTATION HUD. Ebonhold-first: Snake Trap feeds the Rocket Strike engine, so it
-- leads. Kill Shot / Explosive Shot / Black Arrow follow the Survival priority.
-- Upkeep = the aspect (the HUD nags if it drops), mirroring the paladin's seal.
H.rotationUpkeep = { "Aspect of the Dragonhawk", "Aspect of the Hawk" }
H.rotationPriority = {
  { spell = "Snake Trap" },   -- rocket engine: keep snakes out
  { spell = "Kill Shot", cond = function()
      return PP.RotationHelper and PP.RotationHelper.TargetPct() <= 20 end },
  { spell = "Explosive Shot" },
  { spell = "Black Arrow" },
  { spell = "Kill Command" },
  { spell = "Serpent Sting" },
  { spell = "Arcane Shot" },
  { spell = "Multi-Shot" },
  { spell = "Steady Shot" },
}
