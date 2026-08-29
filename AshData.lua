-- PallyPilot AshData: the Soul Ash permanent tree, mapped from the server's
-- own client addon (ProjectEbonhold in patch-4.MPQ, modules/skillTree/
-- TalentDatabase.lua — a bare GLOBAL `TalentDatabase` at runtime — joined
-- offline with the custom Spell.dbc in patch-5.MPQ for names). 816 nodes,
-- 191 distinct effects; the advisor tracks the ones that matter for a solo
-- Ret climb. Source tags:
--   "client-db" — read live from _G.TalentDatabase (authoritative)
--   "extract"   — baked here from that same DB, extracted 2026-08-25
--   "codex"     — community consensus only (no exact numbers)
-- AshAdvisor.lua prefers client-db at runtime and falls back to these tables.
local PP = PallyPilot
PP.AshData = {}
local AD = PP.AshData

-- Tree-wide constants (ProjectEbonhold.Constants + skillTree.lua, extract).
-- The bankable soul-ash limit was raised to 2^64-1 in the 2026-08-27 update
-- (effectively unlimited). Stored as a Lua double so it's approximate; this is
-- only a documentation ceiling, not used in cost math.
AD.TREE_CAP = 18446744073709551615
-- Soul Ashes MILESTONES: each one unlocks ONE permanent Echo (lock) slot —
-- spells 101259-101263 "Echo Attunement Slot". They trigger on COMMITTED
-- (lifetime banked) ash, not spendable. So: slot 1 at 1M, slot 2 at 2M,
-- slot 3 at 25M, slot 4 at 100M, slot 5 at 215M. (The old codex note
-- "all 5 slots at 25M" is wrong — 25M is the THIRD slot.)
AD.MILESTONES = { 1000000, 2000000, 25000000, 100000000, 215000000 }
-- Infinite nodes (Endless Vitality / Might / Growth): rank cost is
-- ceil(base * growth^(rank-1)), capped per rank at rankCostCap.
-- The old 255-rank hard cap was REMOVED in the 2026-08-29 update -- infinite
-- nodes are now uncapped (limited only by cost). maxRank is a large sentinel so
-- they never read as "maxed"; it is never looped over, only used as a scalar
-- total for the capped check / fallback display.
AD.INFINITE = { base = 2000, growth = 1.25, maxRank = 100000, rankCostCap = 100000000 }
-- Prestige: unlocks at 10,771,440 committed; resets the tree (only
-- permanent-flagged nodes survive) and converts the DESTROYED committed pool
-- into a permanent ash-gain bonus: +20% per "gate worth", sqrt curve,
-- destroyed pool counted up to 400M. Spent vs unspent makes no difference to
-- the prestige payout — the whole committed pool burns either way.
AD.PRESTIGE = { gate = 10771440, gainPerGate = 0.20, exponent = 0.5,
                destroyedCap = 400000000 }

-- Cost of buying rank `rank` (1-based) of an infinite node.
function AD.InfiniteCost(rank, base, growth)
  base = base or AD.INFINITE.base
  growth = growth or AD.INFINITE.growth
  local cost = math.ceil(base * growth ^ (rank - 1) - 0.000001)
  if cost >= AD.INFINITE.rankCostCap then return AD.INFINITE.rankCostCap end
  if cost < 1 then return 1 end
  return cost
end

-- Endless Growth's ramping gain: +1/rank for ranks 1-4, then +2, +3, ...
-- one step every 3 ranks, capped at +20/rank. Mirrors the server's
-- spell_skilltree_general_endless_growth::TotalForRank.
function AD.GrowthGainAtRank(rank)
  if rank <= 4 then return 1 end
  local g = 2 + math.floor((rank - 5) / 3)
  if g > 20 then return 20 end
  return g
end

function AD.GrowthTotal(rank)
  local total = 0
  for r = 1, rank do total = total + AD.GrowthGainAtRank(r) end
  return total
end

-- Curated advisor targets, in PRIORITY ORDER for the solo Ret climb.
-- ids   = TalentDatabase node ids (ascending cost; chains ascend along links)
-- costs = every rank's cost across those nodes, ascending (extract)
-- tier  = 1 gear enabler, 2 echo power, 3 permanent stats, 4 QoL,
--         5 situational survival (optional; hidden by default)
-- perm  = survives a prestige ("Carry over Prestige" flag in the DB)
--
-- Priority model (from the Ebonhold community, 2026-08-29): this is a
-- "borrowed-power game where it's all about echoes and affixes." Your power is
-- your ECHO BUILD + AFFIXES + GEAR, not the ash tree. The ash tree's job is to
-- get that power online at any level and survive a prestige. So the enablers
-- lead: Borrowed Power (wear your endgame gear at any level -> strong right after
-- a prestige) > echo economy (roll a strong build every run) > permanent stats >
-- QoL. The temp survival spine is WIPED every prestige and is NOT what carries
-- hardcore content, so it drops to an optional tier. See
-- docs/superpowers/specs/2026-08-29-ash-advisor-redesign-design.md.
AD.NODES = {
  -- TIER 1 -- GEAR ENABLER. The single most important node for a solo Ret: it
  -- is what makes you strong again right after a prestige/relevel.
  { key = "borrowedpower", name = "Borrowed Power", tier = 1, perm = true,
    ids = { 582, 583, 584, 585 },
    costs = { 100000, 200000, 300000, 400000, 500000, 600000, 700000, 800000,
              900000, 1000000, 1250000, 1500000, 1750000, 2000000, 2500000,
              5000000, 10000000 },
    effect = "Wear gear above your level: +1 over-level item per rank. How you re-equip your endgame set after a prestige. Rank it until your whole set fits." },

  -- TIER 2 -- ECHO POWER (survives prestige). Lets you assemble a strong echo
  -- set every run -- the real damage lever in this game.
  { key = "twistoffate", name = "Twist of Fate", tier = 2, perm = true,
    ids = { 407, 408, 409, 410, 411, 412, 413, 414, 415, 514, 515, 776, 792,
            819, 820, 921, 922, 1047 },
    costs = { 10000, 10000, 10000, 10000, 10000, 10000, 10000, 10000, 10000,
              100000, 100000, 200000, 200000, 200000, 200000, 300000, 300000,
              300000 },
    effect = "+1 echo reroll per run per rank -- reroll toward a stronger build" },
  { key = "severance", name = "Echo Severance", tier = 2, perm = true,
    ids = { 630, 631, 632, 633, 634, 635, 636, 637, 638, 639, 818, 1049 },
    costs = { 50000, 50000, 50000, 50000, 50000, 50000, 50000, 50000, 50000,
              50000, 100000, 200000 },
    effect = "+1 echo banish per run per rank -- drop junk offers" },
  { key = "carefulsel", name = "Careful Selection", tier = 2, perm = true,
    ids = { 815, 816, 814, 817, 948, 813 },
    costs = { 75000, 75000, 150000, 250000, 350000, 500000 },
    effect = "+1 echo freeze per run per rank -- hold a good offer for later" },
  { key = "luckydraw", name = "Lucky Draw", tier = 2, perm = true,
    ids = { 181, 182, 183, 184, 185, 498, 764, 807, 808 },
    costs = { 50000, 50000, 50000, 50000, 50000, 500000, 500000, 750000,
              750000 },
    effect = "Better odds of higher-quality echo offers on level-up" },
  { key = "talentoverflow", name = "Talent Overflow", tier = 2, perm = true,
    ids = { 726, 727, 728, 742, 729, 734, 736, 743, 744, 735, 737, 738, 745,
            732, 733, 867, 739, 747, 749, 771, 741, 740, 942, 943, 946 },
    costs = { 25000, 25000, 25000, 25000, 50000, 50000, 50000, 50000, 75000,
              100000, 100000, 100000, 100000, 150000, 200000, 250000, 500000,
              500000, 500000, 500000, 750000, 1000000, 1000000, 1000000,
              1000000 },
    effect = "+1 talent point per rank" },

  -- TIER 3 -- PERMANENT STATS. Prestige-proof raw power (and real, permanent
  -- survival via Stamina) that compounds across every reset.
  { key = "vitality", name = "Endless Vitality", tier = 3, infinite = true,
    ids = { 2000 }, costs = {},
    effect = "+5 Stamina per rank, permanent -- the survival that compounds across prestiges and never needs rebuying", perm = true },
  -- Growth before Might for a paladin: Growth feeds your highest stat (Strength
  -- -> SP, the stat that actually scales our damage), while Might gives Ret AP,
  -- which does almost nothing for us except via AP->SP conversion.
  { key = "growth", name = "Endless Growth", tier = 3, infinite = true,
    ids = { 2002 }, costs = {},
    effect = "+highest stat, ramping (+1/rank early, up to +20/rank) -- for us that's Strength -> SP. Commit deep, permanent.",
    perm = true },
  { key = "might", name = "Endless Might", tier = 3, infinite = true,
    ids = { 2001 }, costs = {},
    effect = "+10 AP per rank for Ret (+5 SP for casters), permanent. Ret gets AP -- the weak stat for us; prefer Endless Growth (Strength -> SP).",
    perm = true },

  -- TIER 4 -- QUALITY OF LIFE.
  { key = "boundless", name = "Boundless Growth", tier = 4, perm = true,
    ids = { 191, 192, 193 }, costs = { 75000, 75000, 75000 },
    effect = "+XP% per rank -- faster re-climb to 80 after a prestige" },
  { key = "riding", name = "Riding + Cold Weather Flying", tier = 4, perm = true,
    ids = { 416, 417, 418, 419 },
    costs = { 1500, 5000, 20000, 50000 },
    effect = "Riding -> Cold Weather Flying -> Artisan; all permanent" },
  { key = "rapidtransit", name = "Rapid Transit", tier = 4, perm = true,
    ids = { 405 }, costs = { 1000 },
    effect = "Mount speed, for 1,000 ash" },
  { key = "provisions", name = "Raider's Provisions", tier = 4,
    ids = { 1001 }, costs = { 1000000 },
    effect = "Food/flask/elixir effects persist through death" },
  { key = "appetite", name = "Bottomless Appetite", tier = 4,
    ids = { 812 }, costs = { 750000 },
    effect = "Benefit from any number of food + elixir effects at once" },
  { key = "escape", name = "Prepared Escape", tier = 4,
    ids = { 643, 644, 645, 646, 647, 648, 725, 936 },
    costs = { 35000, 35000, 35000, 35000, 35000, 350000, 750000, 1000000 },
    effect = "Reduce Emergency Exit cooldown per rank" },

  -- TIER 5 -- SITUATIONAL SURVIVAL (optional; hidden by default). WIPED every
  -- prestige, and not what carries hardcore -- your echoes + gear do that. Worth
  -- it only on a long stay-at-80 push, or the hardcore-DR nodes when pushing HC.
  { key = "undyingspark", name = "Undying Spark", tier = 5, survival = true,
    ids = { 347, 348, 349, 531, 850, 910 },
    costs = { 5000, 15000, 50000, 500000, 750000, 1000000 },
    effect = "Hardcore: becomes damage reduction -- worth it if you're pushing HC (wiped on prestige)" },
  { key = "refusedrequiem", name = "Refused Requiem", tier = 5, survival = true,
    ids = { 340, 341, 628, 848, 909 },
    costs = { 25000, 25000, 250000, 500000, 750000 },
    effect = "Hardcore: damage reduction per rank -- for HC pushes (wiped on prestige)" },
  { key = "braceforimpact", name = "Brace for Impact", tier = 5, survival = true,
    ids = { 1026 },
    costs = { 100000, 200000, 300000, 400000, 500000, 750000, 1000000,
              1250000 },
    effect = "Above % health, direct hits deal reduced damage (wiped on prestige)" },
  { key = "secondwind", name = "Second Wind", tier = 5, survival = true,
    ids = { 391 }, costs = { 1500, 3000, 5000 },
    effect = "Out-of-combat self-heal -- optional, wiped on prestige, skip on the loop" },
  { key = "victoryfeast", name = "Victory Feast", tier = 5, survival = true,
    ids = { 388 }, costs = { 7500, 15000, 25000 },
    effect = "Restore % max HP on every kill -- optional, wiped on prestige" },
  { key = "borrowedtime", name = "Borrowed Time", tier = 5, survival = true,
    ids = { 335, 336, 337, 338, 339 },
    costs = { 5000, 10000, 15000, 20000, 25000 },
    effect = "Cheat Death: survive a killing blow -- optional, wiped on prestige" },
  { key = "reserveoflife", name = "Reserve of Life", tier = 5, survival = true,
    ids = { 342, 343, 344, 345, 346, 530, 849, 911 },
    costs = { 7500, 12500, 20000, 25000, 30000, 300000, 600000, 900000 },
    effect = "+1 Cheat Death charge per rank -- optional, wiped on prestige" },
  { key = "steadfast", name = "Steadfast Recovery", tier = 5, survival = true,
    ids = { 1024 }, costs = { 20000, 50000, 100000, 150000, 250000, 500000 },
    effect = "+healing received below 35% health -- optional, wiped on prestige" },
  { key = "lastresort", name = "Last Resort", tier = 5, survival = true,
    ids = { 654 }, costs = { 1000000 },
    effect = "Fatal blow -> immune + teleport -- optional, wiped on prestige" },
}

AD.TIER_NAMES = {
  [1] = "Gear enabler",
  [2] = "Echo power (survives prestige)",
  [3] = "Permanent stats",
  [4] = "Quality of life",
  [5] = "Survival (optional: long push / hardcore)",
}
