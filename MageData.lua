-- EbonPilot MageData: the curated solo Fire Mage guide for Ebonhold.
-- Mirrors PriestData.lua's shape and registers into the multi-class registry as
-- PP.Classes.MAGE. Core re-points PP.Build to this table at login for a mage.
--
-- SOURCING (what is measured, what is community, what is inferred):
--  * TALENTS are DECODED, not guessed. Rellex's "600M DPS Mage Guide" (#mage,
--    2026-09-02) links a project-ebonhold talent-calculator string; its two
--    segments decode against the client's own Talent.dbc + custom Spell.dbc to
--    47 Arcane / 49 Fire (96 points). Independently corroborated: iorek's "Mage
--    talents" thread says "47 arcane is mandatory" to reach the row-9 Spell Power
--    talent (+50% spell crit damage). Both agree exactly -- that agreement is why
--    this template is a prescription and not a scaffold (contrast HunterData,
--    where no canonical build existed).
--  * ECHOES are DECODED from Rellex's TWO EBH1 loadout strings (79 and 80 echoes).
--    Every id resolved cleanly against the server PerkDatabase and every one is
--    MAGE-draftable -- no phantoms, no transcription slips. 76 echoes appear in
--    BOTH loadouts; that intersection is the high-conviction core. Lock ORDER is
--    Zedd's ("Pyro Machine Gun Mage V2", 500 replies), who publishes an explicit
--    six-echo lock list.
--  * DRAFTABILITY is ground truth: classMask bit 128 (TomeManager CLASS_BIT.MAGE)
--    says 231 of the 323 echo names in the PerkDatabase are mage-draftable. Echoes
--    the PRIEST file rates highly but a MAGE CANNOT DRAW are deliberately absent:
--    Unstable Infusion, Spellweave, Blighted Sky, Shadow Malice, Holy Revelation,
--    Arcane Rupture, Battle Momentum, Arcane Weapon, Echoes of Celerity.
--  * ROLE TAGS are ground truth too: each perk carries families.N (Caster DPS /
--    Melee DPS / Ranged DPS / Tank / Healer / Survivability). Tagged-but-not-
--    Caster-DPS is the honest "off-role" signal; UNTAGGED is neutral, not bad.
--  * GEAR is Rellex's actual wowhead gear-planner link, read item-by-item (real
--    item ids), not a retail BiS list. It includes PLATE legs and a SHIELD, which
--    is not a mistake: see the ARMOR MASTERY note on B.bis.
--  * ECHO EFFECTS are read from the client's own custom Spell.dbc (echo spellIds
--    live at 200000+; the Description string is field 170), NOT from community
--    prose. That is what settled Armor Mastery ("You can equip all armor types"),
--    Tempest Vortex, Demonic Awakening and Reaper's Reprieve below -- and it
--    corrected two places where the community summary was looser than the game.
--  * BLIZZLIKE FALLBACK: only the plain-English spell descriptions. Retail WotLK
--    mage theorycraft is otherwise WRONG here and is not used.
-- Automation is BANNED on Ebonhold (perma-ban risk) -- this is an ADVISOR only:
-- it never presses a key, casts, or buys. Banish is level-up-only and EbonholdHub
-- automates it, so nothing here ever tells the player to banish.
local PP = PallyPilot
local B = {}
PP.Classes = PP.Classes or {}
PP.Classes.MAGE = B                -- registered in the multi-class registry
-- NB: unlike BuildData.lua we do NOT set PP.Build = B here. BuildData (loaded
-- first) is the intentional pre-login default; Core re-points PP.Build to the
-- logged-in class at PLAYER_LOGIN, so a mage still gets this table.

B.title = "Solo Fire Mage -- Hardcore climb (Frostfire/Pyro; 47 Arcane / 49 Fire)"
B.spec = "Fire"

-- Stat priority. NOT retail. The #mage consensus is a CRIT wall then HASTE:
-- Rellex: "IF YOU ARE NOT CRIT CAP TAKE OUT A RELENTLESS STRIKE OR 2 TO GET TO
-- 100% SPELL CRIT MANDATORY". Zedd: "we are haste stacking" (three of his six
-- locked echoes are haste). Spell power is the backbone but is mostly bought by
-- the Pain affix engine below, not by chasing raw SP on gear.
B.statPriority = { "Spell Crit (to 100%)", "Haste", "Spell Power", "Spell Hit (cap)", "Intellect" }
B.statNote = "Spell CRIT is the wall, not spell hit: the whole Fire kit is Hot "
  .. "Streak -> Pyroblast, and Hot Streak only procs off crits, so crit chance is "
  .. "throughput AND rotation uptime. The #mage consensus target is 100% spell "
  .. "crit; Rellex swaps a Relentless Crits affix (crit SCALING) for Keen Strikes "
  .. "(crit CHANCE) whenever he is under it. AFTER the crit wall it is HASTE -- "
  .. "Zedd's build is explicitly haste-stacking and his gems are Quick King's "
  .. "Amber / Quick Dragon's Eye, not spell-power gems. Haste is worth more here "
  .. "than retail because Accelerated Decay makes your DoT ticks scale with it. "
  .. "Spell hit still matters (a miss is zero damage) but on Ebonhold it is "
  .. "normally bought from ash-tree hit nodes rather than gear, so it sits below "
  .. "crit/haste in the GEAR order -- do not read it as unimportant."

-- The always-on armor buff. RotationHelper's generic upkeep path reads
-- B.rotationUpkeep (below) and will nag if this drops -- same treatment the
-- paladin's Seal gets, but with no hardcoded class branch.
B.seal = "(your always-on armor) MOLTEN ARMOR -- keep it up ALWAYS. Glyph of "
  .. "Molten Armor converts 20% of your spirit into critical strike, which feeds "
  .. "the crit wall the whole build stands on. Mage Armor (mana/resist) is the "
  .. "WRONG pick here: you are crit-gated, not mana-gated."
B.sealWhy = "Molten Armor is crit, and crit is Hot Streak uptime. Zedd's guide "
  .. "runs Glyph of Molten Armor specifically for the spirit-to-crit conversion."
B.blessing = "(self-buffs, no group buffs solo) Arcane Intellect, Molten Armor, "
  .. "and Ice Barrier if you have frost points. Conjure and eat a Mana Gem before "
  .. "each pull -- and keep ICE BLOCK off cooldown, because it is load-bearing "
  .. "(see the survival loop below), not just a panic button."
B.blessingWhy = "Ice Block is the mage's unique engine part: it cleanses the "
  .. "one-hour lockout debuffs left by Demonic Awakening and Reaper's Reprieve, "
  .. "so a mage -- and only a mage -- can re-arm both cheat-deaths on demand."

-- Single-target priority. Fire is a proc-reactive list, not a fixed rotation.
B.rotation = "Keep Molten Armor up. Open with Living Bomb only if you took it "
  .. "(the community 47/49 build does NOT). Cast FROSTFIRE BOLT as your filler; "
  .. "the instant you see HOT STREAK or ARCANE SURGE, spend it on PYROBLAST. Use "
  .. "FIRE BLAST at the end of a cast to fish for another Hot Streak. Combustion "
  .. "on cooldown. That is the whole loop -- Frostfire Bolt until something procs, "
  .. "then Pyroblast. Ignite is a large share of your damage and it keeps ticking "
  .. "(and refreshing) while you are inside Ice Block, so blocking is not a DPS "
  .. "stop the way it looks."
B.rotationAoe = "Farm/AoE: Flamestrike on the pack, then keep Frostfire Bolt / "
  .. "Pyroblast on whichever mob lives longest so Ignite and your proc echoes keep "
  .. "rolling. Blast Wave and Dragon's Breath are NOT in the community build (0 "
  .. "points), so do not plan around them. Your AoE damage comes mostly from the "
  .. "proc-echo web firing off single-target casts, not from mage AoE spells."
B.mana = "Mana is not the mage's solo problem on Ebonhold -- crit and staying "
  .. "alive are. Evocation with Glyph of Evocation is a real HEAL as well as a "
  .. "refill (Zedd runs it for exactly that), Mana Gems cover mid-pull dips, and "
  .. "the Arcane sub-tree already carries Arcane Meditation 3/3. If you are going "
  .. "OOM you are probably standing still too long instead of using the Ice Block "
  .. "loop to reset."
-- THE SURVIVAL LOOP -- this is the mage-exclusive part of the build and the
-- reason a mage can facetank content that kills other classes. Sourced from
-- Marex's "One Gnome Army" guide (1236 replies, #mage).
B.survival = "THE PAIN LOOP (mage-exclusive, and it inverts normal caster "
  .. "advice): the 'Pain' affixes scale your SPELL POWER off damage you have "
  .. "TAKEN, so you deliberately facetank instead of kiting -- Marex reports 3x+ "
  .. "spell power from it. That needs a big HP pool, so stack Ironhide/Thick Hide "
  .. "and the survival echoes. The loop, with each step's real client tooltip: "
  .. "facetank -> Pain stacks -> DEMONIC AWAKENING triggers under a health "
  .. "threshold and turns you into a Demon that LEECHES a share of the damage you "
  .. "deal as health (so it is not a flat heal -- it refills you fast precisely "
  .. "BECAUSE your damage is huge, which is why it pairs with the Pain spike) -> "
  .. "when that ends, REAPER'S REPRIEVE turns the next fatal hit into 1 health "
  .. "plus a short window where you take no damage at all and are healed for a "
  .. "share of max HP, and it does NOT consume a Cheat Death charge -> then ICE "
  .. "BLOCK, which is another immunity AND clears the 60-minute lockout debuffs "
  .. "both of those leave behind -> you come out with both armed again. Ignite "
  .. "keeps ticking and refreshing the whole time you are blocked, so blocking is "
  .. "not the DPS stop it looks like. Only a mage can clear those debuffs; that is "
  .. "what makes this build class-unique rather than just tanky."
B.talents = "47 Arcane / 49 Fire (96 points). You play FIRE -- Hot Streak, "
  .. "Pyroblast, Ignite, Frostfire Bolt -- but you spend 47 points in Arcane to "
  .. "reach the row-9 Spell Power talent (+50% critical strike DAMAGE bonus of "
  .. "spells), which is the single biggest multiplier available to you and is why "
  .. "the Arcane half is not optional. Nobody in #mage plays Frost or pure Arcane "
  .. "for damage; every published guide is this Fire/Arcane hybrid."

-- Echoes to lock so they persist across runs. ORDER = lock priority, and this is
-- Zedd's published six-echo lock list VERBATIM and IN HIS ORDER (his stated
-- reasons kept as comments). Entry 7 is the deliberate ranked fallback the parity
-- contract asks for -- Adaptive Power, which Zedd calls an "80%+ dmg boost" and
-- which sits in BOTH of Rellex's loadouts.
B.locked = {
  "Chronoboost",       -- Zedd: more haste
  "Quickened Tempo",   -- Zedd: lower GCD = faster casting; also lets you fit more
                       -- spells into an Arcane Surge window
  "Accelerated Decay", -- Zedd: DoTs are the main damage source and the build is
                       -- haste-stacking -- this is what makes haste scale ticks
  "Twin Casting",      -- Zedd: works on Frostfire Bolt and Pyroblast, your 2 casts
  "Quickening Aura",   -- Zedd: more haste
  "Armor Mastery",     -- THE GEAR UNLOCK. Real tooltip (Spell.dbc 201270): 'You
                       -- can equip all armor types'. Zedd calls it better
                       -- Haste/Crit/Int options, which is what that buys: you
                       -- pick items on stats, not on cloth. B.bis depends on it.
  "Adaptive Power",    -- FALLBACK (7th): +1% per unique active echo; Zedd rates
                       -- it an 80%+ damage boost. In both Rellex loadouts.
}
-- WHY TWILIGHT EQUILIBRIUM IS BETTER FOR YOU THAN FOR A PRIEST: it stacks Light
-- Essence on Holy/Fire/Nature casts and dumps Darkburst on Shadow/Frost/Arcane.
-- A Shadow Priest is ~mono-school and only ever feeds one side. You are not:
-- Frostfire Bolt and Pyroblast are Fire while Arcane procs cover the other half,
-- so a Fire mage flips the engine natively. It is in both Rellex loadouts.

-- Draw priority tiers. On a level-up selection (and Orb rerolls) take the highest
-- tier offered. These names are also FarmQueue targets.
-- S = in BOTH decoded Rellex loadouts AND/OR named by Zedd as locked/mandatory.
-- A = in the decoded loadouts but without published reasoning, or strong caster
--     echoes the server tags Caster DPS that his build simply did not roll.
-- B = off-role for a caster but genuinely run for Adaptive Power breadth.
B.tiers = {
  S = {
    -- Locked core, duplicated so DrawHelper/TierOf rate them S (paladin convention):
    "Chronoboost", "Quickened Tempo", "Accelerated Decay", "Twin Casting",
    "Quickening Aura", "Armor Mastery", "Adaptive Power",
    -- Zedd's explicitly MANDATORY list (his reasons in the catalog below):
    "Arcane Surge", "Burning Cataclysm", "Resonant Build", "Contagion",
    "Harbringer of Doom", "Inhaled Blight", "Malleable Goo", "Overtime Conversion",
    "Ruthless Exploiter",
    -- the school-flip engine (see note above -- natively better for a Fire mage):
    "Twilight Equilibrium",
    -- fire / frost / plague proc web, all present in BOTH decoded loadouts:
    "Cinders of the Sanctum", "Slime Spray", "Cyclone of Cold Bones",
    "Necrotic Plague", "Curse of the Plaguebringer", "Frostfire Paradox",
    "Flame Beacon", "Chill of the Bone Wyrm", "Permeating Chill", "Conjured Flame",
    "Emberlord's Gift", "Broodmother's Fury", "Entropic Fusion", "Scorching Wounds",
    -- damage engines / edicts / constructs (both loadouts):
    "Constellations", "Edict of the Four", "Edict of the Iron Council",
    "Nether Lord's Command", "Sanctum Sentries", "Dark Nucleus",
    "The Harvester's Tithe", "Crypt Lord's Swarm",
    -- caster tempo / stat (both loadouts):
    "Temporal Flow", "Perfect Timing", "Polarity Shift", "Third Time's the Charm",
    "Unbroken Focus", "Tunnel Vision", "Peak Condition", "Sudden Insight",
    "Heavy Incantations", "Arcane Cadence", "Arcane Burn", "Arcane Density",
    "Archmage's Mark", "Mind Expansion", "Quick Hands", "Echoing Tides",
    -- SOLO survival keystones (both loadouts; the Pain loop needs the HP pool):
    "The Last Wall", "Sanguine Bulwark", "Demonic Awakening", "Iron Constitution",
    "Spiritual Fortitude", "The Sporelord's Gift", "Grim Resolve",
    -- the tanky-variant additions: Rellex swaps these IN for the squishy picks.
    -- For a hardcore solo climb they are the correct half of that trade.
    "Reaper's Reprieve", "Deathwhisper's Barrier", "Leeching Swarm", "Slimebound Husk",
  },
  A = {
    -- mage-only proc variants: the Mage-prefixed form is the one that procs for
    -- YOU (every other class prefix is not even draftable by you).
    "Mage - Arcane Bombardment", "Mage - Corrosive Breath", "Mage - Ember Spark",
    "Mage - Stonefist Barrage",
    -- in the decoded loadouts, no published reasoning:
    "Battle Rhythm", "Chaotic Convergence", "Drained Reserves", "Leadfoot",
    "Rolling Momentum", "Scent of Blood", "Lethal Precision",
    -- server-tagged Caster DPS, mage-draftable, simply not rolled in his build:
    "Storm of the Spellweaver", "Tempo Weave", "Unstable Missiles", "Arcane Bond",
    "Arcane Brand", "Arcane Hazard", "Arcane Snare", "Fire Brand", "Frost Brand",
    "Riven Sky", "Scorched Sky", "Shattered Sky", "Storm Hazard", "Killing Chill",
    "Stone Shatter", "Storm Conductor", "Wild Hazard", "Shadow Crash",
    "Burning Touch", "Reap the Weak", "Mystic Potency", "Steady Casting",
    "Steady Channeling", "Subtle Presence", "Undead Bane", "Vital Bond",
    "Widow's Venom", "Essence Tap", "Mutagenic Fumes", "Idol of Yogg-Saron",
    "Call of the Lich King", "Brittle Forging", "Echoing Afflictions",
    "Hungering Curse", "Static Overflow", "Efficient Casting",
  },
  B = {
    -- Off-role for a caster (the server tags these Melee/Ranged/Tank, not Caster
    -- DPS) but Rellex genuinely runs them for Adaptive Power breadth -- so keep
    -- and draft happily, just never spend orbs chasing them.
    "First Strike", "Rage of the Colossus", "Focused Assault", "Exposed Heart",
    "Reaper's Doom", "Reaper's Verdict", "Immolation Aura", "Twilight Combustion",
    -- movement quality-of-life, from Zedd's nice-to-have list. NAME CORRECTED:
    -- he writes Calvary Instincts, which is a phantom; the PerkDatabase name is
    -- Cavalry Instincts.
    "Cavalry Instincts", "Swift Step",
    -- mana echoes: live for a caster but you are not mana-gated (see B.mana):
    "Mana Infusion", "Mana Regeneration", "Mana Reservoir", "Meditative Flow",
  },
}
-- Deliberate STACKS. maxStack is read straight off the PerkDatabase so this can
-- never recommend stacking past the server's own cap. Rellex's decoded loadout
-- stacks exactly one echo: Quick Hands x7 (server cap 80).
B.stackTargets = { ["Quick Hands"] = 7 }

-- Full catalog: INHERIT the paladin catalog's breadth ratings (Adaptive Power
-- pays +1% per unique active echo -- that breadth meta is class-agnostic), then
-- OVERRIDE for a Fire mage.
local pala = PP.Classes.PALADIN
B.catalog = {}
if pala and pala.catalog then
  for name, tier in pairs(pala.catalog) do B.catalog[name] = tier end
end
local OVERRIDE = {
  -- Zedd's MANDATORY echoes, with his stated reasons:
  ["Arcane Surge"] = "S",        -- tooltip: a cast has a chance to make your next
                                 -- spell INSTANT, and Pyroblast is on its
                                 -- eligible list -- hence Zedd's 'Hot Streak on
                                 -- crack'. This is why the HUD spends it below.
  ["Burning Cataclysm"] = "S",   -- tooltip: your FIRE damage-over-time effects can
                                 -- now critically strike. Fire-specific, so it is
                                 -- mandatory for this spec and dead for others.
  ["Resonant Build"] = "S",      -- % damage; draft one spirit/int/stam to feed it
  ["Contagion"] = "S",           -- pairs with Harbringer of Doom for a big % boost
  ["Harbringer of Doom"] = "S",  -- the other half of that combo
  ["Inhaled Blight"] = "S",      -- Inhaled + Malleable Goo is the new LK combo
  ["Malleable Goo"] = "S",
  ["Overtime Conversion"] = "S", -- massive if there are adds near the boss
  ["Ruthless Exploiter"] = "S",  -- "20% dmg boost"
  ["Adaptive Power"] = "S",      -- "80%+ dmg boost"
  -- haste engine (the locked six):
  ["Chronoboost"] = "S", ["Quickened Tempo"] = "S", ["Accelerated Decay"] = "S",
  ["Twin Casting"] = "S", ["Quickening Aura"] = "S", ["Armor Mastery"] = "S",
  -- solo survival: the Pain loop is HP-hungry, so these are damage, not comfort.
  ["The Last Wall"] = "S",       -- big % max HP, but it also REDUCES HEALING
                                 -- RECEIVED -- worth knowing, since Demonic
                                 -- Awakening's leech is healing. Both Rellex
                                 -- loadouts run them together anyway.
  ["Demonic Awakening"] = "S",   -- demon form under a health threshold: +damage
                                 -- and leech damage-dealt as health
  ["Reaper's Reprieve"] = "S",   -- fatal hit -> 1 HP + a no-damage window + a heal;
                                 -- 60 min lockout, no Cheat Death charge spent
  ["Sanguine Bulwark"] = "S", ["Iron Constitution"] = "S",
  ["Deathwhisper's Barrier"] = "S", ["Leeching Swarm"] = "S", ["Slimebound Husk"] = "S",
  -- mage-only proc variants (the other classes' prefixes are not draftable by you):
  ["Mage - Arcane Bombardment"] = "A", ["Mage - Corrosive Breath"] = "A",
  ["Mage - Ember Spark"] = "A", ["Mage - Stonefist Barrage"] = "A",
  -- caster promotions the paladin catalog rated as dead weight for Ret:
  ["Unstable Missiles"] = "A", ["Heavy Incantations"] = "A", ["Tempo Weave"] = "A",
  ["Storm of the Spellweaver"] = "A", ["Arcane Bond"] = "A", ["Arcane Brand"] = "A",
  ["Efficient Casting"] = "B", ["Mana Infusion"] = "B", ["Mana Regeneration"] = "B",
  ["Mana Reservoir"] = "B", ["Meditative Flow"] = "B",
  -- melee/physical echoes a mage CAN draw but cannot use. Kept at B (not C) on
  -- purpose: Rellex's 600M loadout actually runs these for Adaptive breadth.
  ["First Strike"] = "B", ["Rage of the Colossus"] = "B", ["Focused Assault"] = "B",
  ["Exposed Heart"] = "B", ["Reaper's Doom"] = "B", ["Reaper's Verdict"] = "B",
  ["Immolation Aura"] = "B",
  -- pure ally-heal echoes stay dead: solo means no allies. (Purifying Touch is
  -- NOT rated here on purpose -- a mage cannot draw it at all, so it is nil-ed
  -- below instead. Rating an undraftable echo is dead weight.)
  ["Crusader's Surge"] = "C", ["Healing Cadence"] = "C",
  ["Inspiring Mending"] = "C", ["Lingering Inspiration"] = "C",
  ["Overwhelming Restoration"] = "C", ["Champion's Rally"] = "C", ["Eonar's Seed"] = "C",
}
for name, tier in pairs(OVERRIDE) do B.catalog[name] = tier end
-- GROUNDING: drop every catalog entry a MAGE can never draw, so the catalog never
-- rates a phantom. These are classMask-verified NOT-draftable by mage (bit 128) --
-- several were inherited from the paladin/priest catalogs, which is exactly the
-- silent-wrong-advice failure this pass exists to kill. Nil-ed, not down-rated.
for _, n in ipairs({
  "Armor Penetration", "Brutal Might", "Expertise Drills", "Second Edge",
  "Strength Training", "Sweeping Blows", "Crimson Reprisal", "Battle Momentum",
  "Arcane Weapon", "Arcane Rupture", "Unstable Infusion", "Spellweave",
  "Blighted Sky", "Shadow Malice", "Holy Revelation", "Divine Resonance",
  "Echoes of Celerity", "Storm Surge", "Vitality", "Accelerated Spirit",
  "Rhythm of Power", "Rite of Quickening", "Nature Quickness", "Healing Echo",
  "Pulse of Renewal", "Reinforced Shielding", "Double Strike", "Double Tap",
  "Anger Management", "Blood Frenzy", "Crippling Strikes", "Heavy Blows",
  "Open Wounds", "Rend the Weak", "Dirge", "Flow of Battle", "Forged in Combat",
  "Agility Boost", "Bola Shot", "Burning Flames", "Ferocious Bond", "Holy Brand",
  "Momentum Chant", "Nature Brand", "Shadow Brand", "Steel Brand", "Sanctified Sky",
  "Reactive Retaliation", "Relentless Rhythm", "Runic Empowerment", "Stormtorn Sky",
  "Unbridled Fury", "Rapid Recalibration", "Purifying Touch",
}) do B.catalog[n] = nil end
-- NB: Divine Surge is deliberately NOT in that list -- despite the holy-sounding
-- name the server tags it Caster DPS and a mage CAN draw it, so it keeps whatever
-- rating it inherited rather than being thrown away.
-- Dual-wield enabler: hard-skip for a mage (staff or 1H + off-hand, never two 1H).
B.catalog["Ambidexterity"] = "F"
--
-- TWO DELIBERATE COMMUNITY DEVIATIONS, both stated rather than hidden:
--
-- 1. LETHAL PRECISION -- held at A, NOT S and NOT disabled. Zedd calls it
--    mandatory ("30% crit damage is huge") and it is in both of Rellex's
--    loadouts, because a mage runs 80-100% native crit and can afford the
--    tooltip's -50% crit CHANCE for +30% crit DAMAGE. But the paladin catalog
--    rates it F off a MEASURED result (it field-zeroed keepsy's crit), and this
--    guide is for a solo climb that relevels from 1 -- at low gear you are NOT
--    near the crit cap and the trade inverts. So: draft it happily once your crit
--    is high, never spend orbs chasing it, and confirm with /pp dps before
--    trusting it early in a run.
-- 2. GLASS CANON -- kept at F (disabled). Rellex runs it in BOTH loadouts, but
--    Zedd bans it outright ("not worth losing a ton of HP") and Marex's Pain loop
--    is built on a large HP pool -- -30% max HP fights the engine that both your
--    damage and your survival depend on. For a HARDCORE solo climb the HP is
--    load-bearing, so this follows Zedd. Flip it only for a geared raid parse.
B.catalog["Lethal Precision"] = "A"
B.catalog["Glass Canon"] = "F"

-- Echoes to disable: ONLY true negative riders (breadth meta -- every other echo,
-- even a functionally dead one, is worth +1% via Adaptive Power). This is Zedd's
-- published ban list, minus his phantom (see note).
B.disable = {
  "Brittle Armor",    -- Zedd bans it. NB the real tooltip is a TRADE, not a pure
                      -- loss: +crit chance for -armor. That is a genuinely
                      -- arguable pick for a crit-gated mage, and it is dropped
                      -- here only because you facetank for the Pain affix, so
                      -- armor is doing real work. Re-enable if you ever stop
                      -- facetanking and are still short of the crit wall.
  "Overcharged",      -- Zedd: +30% damage taken is a straight loss
  "Glass Canon",      -- Zedd: not worth losing a ton of HP (see deviation 2)
  "Opening Split",    -- Zedd: a recurring rare worth clearing out of the pool
  "Tempest Vortex",   -- NAME CORRECTED. Zedd bans it as Temporal Vortex, which is
                      -- a PHANTOM -- no such echo exists in the PerkDatabase. The
                      -- real name is Tempest Vortex and it matches his stated
                      -- reason (he does not want mobs pulled to him): Tank-tagged.
}
B.disableNote = "Only negative-rider echoes are disabled. Everything else -- even "
  .. "melee echoes a caster cannot use -- stays enabled: each unique active echo "
  .. "pays +1% damage via Adaptive Power, so breadth is a damage stat. NOTE the "
  .. "one real argument against disabling Overcharged: the Pain affix engine "
  .. "scales your spell power off damage TAKEN, so +30% damage taken arguably "
  .. "feeds it. It stays disabled anyway because a hardcore run ends permanently "
  .. "the one time that maths is wrong, and Zedd bans it too. Never banish "
  .. "anything by hand -- banish is level-up-only and EbonholdHub spends it."

-- Item affixes. Rellex publishes an exact list with ranks; Marex explains WHY
-- Pain is first (it multiplies spell power off damage taken -- 3x or more).
B.affixSurvival = {
  { affix = "Ironhide", role = "Flat % HP -- feeds the Pain loop", slots = "Head - Shoulder - Legs - Ring - Ranged" },
  { affix = "Thick Hide", role = "Flat % HP (Rellex runs rank 6)", slots = "Chest - Wrist - Feet" },
  { affix = "Fortified by Pain", role = "THE damage engine: spell power off damage taken", slots = "Hands - Waist - Ring - Off-hand" },
  { affix = "Overwhelming Force", role = "Damage / pressure", slots = "Neck - Back - Tabard - Trinket" },
}
B.affixDamage = {
  { affix = "Fortified by Pain 3-6", role = "Spell power off damage taken -- Marex: 3x+ damage. Take it first." },
  { affix = "Overwhelming Force 3-6", role = "Damage / pressure" },
  { affix = "Relentless Crits 4-6", role = "Crit scaling (Rellex lists it as 'Relentless')" },
  { affix = "Ironhide 4-6", role = "HP -- the Pain loop needs the pool" },
  { affix = "Thick Hide 6", role = "HP" },
  { affix = "Spell Mastery 4", role = "Spell damage" },
  { affix = "Temporal Flux 6", role = "Haste (stat priority #2)" },
  { affix = "Keen Strikes", role = "Crit CHANCE -- swap in over Relentless until you are at 100% spell crit" },
}
B.affixWeapon = "Weapon: Venom + Vulnerability (Rellex). Then the spell/crit "
  .. "affixes."
B.affixNote = "Take Fortified by Pain FIRST -- it is the multiplier the whole "
  .. "build rests on, and it only pays if you are actually taking damage, so pair "
  .. "it with the HP chain (Ironhide / Thick Hide) rather than trying to avoid "
  .. "hits. Then get to 100% spell crit (Keen Strikes for crit CHANCE; Relentless "
  .. "Crits is crit SCALING and does not help you reach the cap), then haste "
  .. "(Temporal Flux). Verify exact item suffixes in-client via /ep gear; highest "
  .. "rank is best. Item text and canonical affix names differ for some affixes, "
  .. "so both spellings are listed in slotTargets."

-- Coarse gear targets for the Dashboard summary. The full per-slot list is B.bis.
B.gear = {
  { slot = "Weapons", target = "Bloodsurge, Kel'Thuzad's Blade of Agony (LK 25H) main hand + Bulwark of Smouldering Steel off-hand. See the UNVERIFIED note on B.bis -- that off-hand is a SHIELD." },
  { slot = "Trinkets", target = "Dislodged Foreign Object (Rotface 25H) + Charred Twilight Scale (Ruby Sanctum 25H)." },
  { slot = "Ranged", target = "Corpse-Impaling Spike -- caster WAND (Rotface 25H)." },
  { slot = "Armor", target = "Sanctified Bloodmage (T10 Mage) head + shoulder + chest + hands for the 4pc; Ruby Sanctum belt/boots. NOT 'Crimson Acolyte' -- that is the Priest T10. Once you hold the Armor Mastery echo you can equip ALL armor types, so pick every non-tier slot on stats alone (Rellex runs plate legs and a shield)." },
}

-- Per-socket gem recommendation shown on empty sockets (GearAudit reads gemRec).
-- HASTE, not spell power: Rellex's own planner gems are Quick King's Amber and
-- Quick Dragon's Eye, and Zedd's build is explicitly haste-stacking. This is a
-- real divergence from the priest (who gems Runed Cardinal Ruby for spell power).
B.gemRec = "Haste (Quick King's Amber); meta Chaotic Skyflare Diamond"

-- Per-slot affix targets (GearAudit Judge reads PP.Build.slotTargets; preferred
-- first). Rellex's published set. Both spellings are listed wherever the item
-- text differs from the canonical affix name -- membership is just a lookup, so
-- listing both kills the false "wrong affix" verdict.
B.slotTargets = {}
do
  local common = {
    "Fortified by Pain", "Afflicted by Pain",  -- THE engine (both spellings seen)
    "Overwhelming Force",
    "Keen Strikes", "Keen Strike",             -- crit CHANCE (both spellings)
    "Relentless Crits",                        -- crit scaling
    "Temporal Flux", "Quick Instincts",        -- haste
    "Spell Mastery",
    "Ironhide", "Enduring Flesh",              -- HP backbone (both spellings)
    "Thick Hide", "Stalwart",
  }
  for i = 1, 19 do B.slotTargets[i] = common end
  -- Weapon/off-hand/wand: Venom + Vulnerability first (Rellex), then the rest.
  local wep = { "Venom", "Vulnerability" }
  for _, a in ipairs(common) do wep[#wep + 1] = a end
  B.slotTargets[16] = wep
  B.slotTargets[17] = wep
  B.slotTargets[18] = wep
end

-- Per-slot named BiS, keyed by inventory slot {item,src,ilvl,why,alt}.
-- SOURCE: read item-by-item off the wowhead gear-planner link in Rellex's 600M
-- guide -- i.e. the gear a 600M-DPS Ebonhold mage is ACTUALLY wearing, not a
-- retail BiS list.
--
-- READ THIS FIRST: slot 7 is PLATE and slot 17 is a SHIELD. That is not a mistake
-- and not a planner artifact -- it is the ARMOR MASTERY echo, whose real client
-- tooltip (Spell.dbc 201270) is exactly "You can equip all armor types". That is
-- why Armor Mastery is a permanent LOCK and not just a nice stat echo: this whole
-- gear list is only equippable while you hold it. Until you draw it, use the
-- cloth/off-hand alternates in the `alt` fields -- and if you ever drop it, your
-- plate and shield unequip with it.
B.bis = {
  [1]  = { item = "Sanctified Bloodmage Hood", src = "ICC 25H tier (T10)", ilvl = 277, why = "T10 mage; anchors the 4pc" },
  [2]  = { item = "Blood Queen's Crimson Choker", src = "Blood-Queen Lana'thel 25H", ilvl = 277, why = "SP + crit + haste" },
  [3]  = { item = "Sanctified Bloodmage Shoulderpads", src = "ICC 25H tier (T10)", ilvl = 277, why = "T10 mage; 4pc" },
  [5]  = { item = "Sanctified Bloodmage Robe", src = "ICC 25H tier (T10)", ilvl = 277, why = "T10 mage; 4pc" },
  [6]  = { item = "Split Shape Belt", src = "Ruby Sanctum 25H", ilvl = 284, why = "SP/crit/haste waist" },
  [7]  = { item = "Puresteel Legplates", src = "Blacksmithing", ilvl = 264, why = "PLATE -- needs the Armor Mastery echo (equip all armor types)", alt = "Leggings of Woven Death (Sindragosa 25H) -- cloth, for before you draw Armor Mastery" },
  [8]  = { item = "Foreshadow Steps", src = "Ruby Sanctum 25H", ilvl = 284, why = "SP/haste feet" },
  [9]  = { item = "Crypt Keeper's Bracers", src = "ICC 25H", ilvl = 277, why = "SP/crit wrist" },
  [10] = { item = "Sanctified Bloodmage Gloves", src = "ICC 25H tier (T10)", ilvl = 277, why = "T10 mage; 4pc" },
  [11] = { item = "Ring of Rapid Ascent", src = "Gunship 25H", ilvl = 277, why = "SP + crit + haste" },
  [12] = { item = "Ashen Band of Endless Destruction", src = "Ashen Verdict - Exalted", ilvl = 277, why = "SP + hit + haste" },
  [13] = { item = "Dislodged Foreign Object", src = "Rotface 25H", ilvl = 277, why = "stacking SP proc trinket" },
  [14] = { item = "Charred Twilight Scale", src = "Ruby Sanctum 25H", ilvl = 284, why = "SP proc trinket", alt = "Muradin's Spyglass (Gunship 25H)" },
  [15] = { item = "Greatcloak of the Turned Champion", src = "ICC 25H", ilvl = 277, why = "SP/crit/haste cloak" },
  [16] = { item = "Bloodsurge, Kel'Thuzad's Blade of Agony", src = "The Lich King 25H", ilvl = 284, why = "top caster 1H; enchant Black Magic (haste proc)" },
  [17] = { item = "Bulwark of Smouldering Steel", src = "ICC 25H", ilvl = 277, why = "SHIELD -- needs Armor Mastery; enchant it Greater Intellect", alt = "Shadow Silk Spindle (Blood Prince Council 25H) -- a normal caster off-hand" },
  [18] = { item = "Corpse-Impaling Spike", src = "Rotface 25H", ilvl = 277, why = "caster wand" },
}

-- Baked talent templates: talent NAME -> desired rank (order-proof; the applier
-- resolves names against the live tree). DECODED from Rellex's talent-calculator
-- string and validated against the client's Talent.dbc via tools/validate_talents.js.
-- Mage tabs are 1=Arcane, 2=Fire, 3=Frost.
--
-- EBONHOLD RENAMES, confirmed against the custom Spell.dbc (not retail):
--   Arcane Subtlety      -> Arcane Affinity     (max 1, not retail's 2)
--   Improved Arcane Missiles -> Arcane Salvo
--   Improved Counterspell -> Aether Attunement  (max 1)
--   plus a CUSTOM "Improved Arcane Barrage" at the bottom of Arcane.
-- A template naming a talent that does not exist SILENTLY SKIPS, so these names
-- came from the client's own DBCs, never from a retail guide.
B.talentTemplates = {
  ["fire"] = {
    name = "Community Fire/Arcane 47/49 (decoded from Rellex's 600M build)",
    talents = {
      -- ARCANE 47 -- taken for the row-9 "Spell Power" talent (+50% spell crit
      -- DAMAGE). Row 9 needs 45 points in-tree, which is exactly why 47 Arcane is
      -- the community's mandatory floor.
      ["Arcane Affinity"] = 1, ["Arcane Focus"] = 3, ["Arcane Salvo"] = 1,
      ["Arcane Fortitude"] = 3, ["Magic Absorption"] = 2, ["Spell Impact"] = 3,
      ["Student of the Mind"] = 3, ["Arcane Shielding"] = 1,
      ["Arcane Meditation"] = 3, ["Torment the Weak"] = 3,
      ["Presence of Mind"] = 1, ["Arcane Mind"] = 5, ["Arcane Instability"] = 3,
      ["Arcane Empowerment"] = 3, ["Arcane Power"] = 1,
      ["Incanter's Absorption"] = 3, ["Arcane Flows"] = 1, ["Mind Mastery"] = 5,
      ["Spell Power"] = 2,
      -- FIRE 49 -- the spec you actually play: Hot Streak -> Pyroblast, Ignite,
      -- Frostfire Bolt.
      ["Improved Fire Blast"] = 2, ["Improved Fireball"] = 5, ["Ignite"] = 5,
      ["Burning Determination"] = 2, ["Flame Throwing"] = 2, ["Impact"] = 3,
      ["Pyroblast"] = 1, ["Burning Soul"] = 2, ["Playing with Fire"] = 3,
      ["Critical Mass"] = 3, ["Fire Power"] = 5, ["Pyromaniac"] = 3,
      ["Combustion"] = 1, ["Molten Fury"] = 2, ["Empowered Fire"] = 3,
      ["Hot Streak"] = 3,
      -- NB: the Fire tree contains TWO DIFFERENT talents both named "Burnout"
      -- (row 7 max 1, row 9 max 5). Rellex puts 4 into the row-9 one. Because the
      -- applier resolves by NAME it cannot tell them apart, so this asks for 1 --
      -- the only rank that is legal for whichever one it finds. Put the remaining
      -- points in by hand.
      ["Burnout"] = 1,
    },
    -- Importance order (most valuable first); the applier fills these first,
    -- always tier-legally, so scarce points buy the best talents.
    priority = {
      "Ignite", "Hot Streak", "Pyroblast", "Improved Fireball", "Fire Power",
      "Critical Mass", "Playing with Fire", "Empowered Fire", "Pyromaniac",
      "Molten Fury", "Combustion", "Impact", "Improved Fire Blast",
      "Burning Soul", "Flame Throwing", "Burning Determination", "Burnout",
      "Spell Power", "Mind Mastery", "Arcane Mind", "Torment the Weak",
      "Arcane Instability", "Arcane Empowerment", "Arcane Power",
      "Incanter's Absorption", "Arcane Meditation", "Spell Impact",
      "Student of the Mind", "Arcane Focus", "Arcane Fortitude",
      "Magic Absorption", "Presence of Mind", "Arcane Flows", "Arcane Shielding",
      "Arcane Affinity", "Arcane Salvo",
    },
  },
}
B.defaultTemplate = "fire"

-- Glyphs -- Zedd's published set.
B.glyphs = "Major: Glyph of Frostfire (+2% Frostfire Bolt damage), Glyph of "
  .. "Molten Armor (20% of spirit as critical strike -- feeds the crit wall), "
  .. "Glyph of Evocation (makes Evocation heal you, which is real solo sustain). "
  .. "Minor: Glyph of Slow Fall / Arcane Intellect / Frost Ward."

-- Dashboard sections (Dashboard.BuildText renders B.reference in place of the
-- legacy paladin Seal/Blessing layout). Reuses the prose fields above.
B.reference = {
  { title = "Armor + buffs", lines = { B.seal, B.blessing } },
  { title = "Rotation (single target)", lines = { B.rotation } },
  { title = "AoE / farm", lines = { B.rotationAoe } },
  { title = "Survival (the Pain loop)", lines = { B.survival } },
  { title = "Mana", lines = { B.mana } },
  { title = "Lock these echoes", lines = {
      table.concat(B.locked, ", "),
      "Zedd's published lock list (#mage) plus Adaptive Power as the 7th fallback.",
  } },
  { title = "Glyphs", lines = { B.glyphs } },
}

-- Rotation HUD (RotationHelper reads PP.Build.rotationPriority + rotationUpkeep).
-- Upkeep goes through the GENERIC path -- no hardcoded class branch is added to
-- RotationHelper for the mage.
-- cond gates WHEN to suggest; RotationHelper's Ready() gates castability.
local function hasBuff(spellName)
  -- true = the named buff is on the player right now. Nil-safe with no target and
  -- with a stubbed API: UnitBuff returning nil just ends the scan.
  for i = 1, 40 do
    local name = UnitBuff("player", i)
    if not name then return false end
    if name == spellName then return true end
  end
  return false
end
B.rotationUpkeep = { "Molten Armor" }
B.rotationPriority = {
  -- Spend a proc the moment you have one: Pyroblast becomes instant.
  { spell = "Pyroblast", cond = function()
      return hasBuff("Hot Streak") or hasBuff("Arcane Surge") end },
  { spell = "Combustion" },        -- Ready() gates its cooldown
  { spell = "Fire Blast" },        -- fish for another Hot Streak at end of cast
  { spell = "Frostfire Bolt" },    -- filler; the cast you spend most time on
}

-- EBH synergy bundles -- +40 bundle score to members while the main (first) echo
-- is active. HubSync reads PP.Build.bundles. Every name here is mage-draftable.
B.bundles = {
  -- the haste engine -- Zedd's locked six are three haste echoes plus the two
  -- that make haste scale your ticks.
  { id = "ppb-haste", tier = "S",
    echoes = { "Chronoboost", "Quickened Tempo", "Quickening Aura",
               "Accelerated Decay", "Temporal Flow", "Quick Hands" } },
  -- fire/frost proc web -- feeds Twilight Equilibrium's non-fire school.
  { id = "ppb-embers", tier = "S",
    echoes = { "Cinders of the Sanctum", "Cyclone of Cold Bones", "Frostfire Paradox",
               "Flame Beacon", "Permeating Chill", "Conjured Flame", "Emberlord's Gift" } },
  -- plague/goo web -- what Zedd calls the new Lich King echo combo.
  { id = "ppb-plague", tier = "S",
    echoes = { "Inhaled Blight", "Malleable Goo", "Slime Spray",
               "Necrotic Plague", "Curse of the Plaguebringer" } },
  -- the Pain survival loop: these are what let you facetank for the affix.
  { id = "ppb-painloop", tier = "S",
    echoes = { "Demonic Awakening", "Reaper's Reprieve", "The Last Wall",
               "Sanguine Bulwark", "Iron Constitution", "Deathwhisper's Barrier" } },
}
-- EBH build spec tab HubSync tags the synced build with (mage: 2 = Fire).
B.specIndex = 2

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
-- Rellex runs 47 of his 79 echoes at Epic or better, so quality is where the orbs
-- go once the names are right. Validate with /ep dps before Epic-fishing.
function B.TopProcs()
  return {
    "Arcane Surge", "Burning Cataclysm", "Cinders of the Sanctum",
    "Malleable Goo", "Inhaled Blight", "Slime Spray", "Cyclone of Cold Bones",
    "Necrotic Plague", "Curse of the Plaguebringer", "Frostfire Paradox",
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
