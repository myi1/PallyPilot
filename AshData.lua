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
AD.TREE_CAP = 428303860
-- Soul Ashes MILESTONES: each one unlocks ONE permanent Echo (lock) slot —
-- spells 101259-101263 "Echo Attunement Slot". They trigger on COMMITTED
-- (lifetime banked) ash, not spendable. So: slot 1 at 1M, slot 2 at 2M,
-- slot 3 at 25M, slot 4 at 100M, slot 5 at 215M. (The old codex note
-- "all 5 slots at 25M" is wrong — 25M is the THIRD slot.)
AD.MILESTONES = { 1000000, 2000000, 25000000, 100000000, 215000000 }
-- Infinite nodes (Endless Vitality / Might / Growth): rank cost is
-- ceil(base * growth^(rank-1)), capped per rank, max 255 ranks.
-- Mirrors SkillTreeNode::GetSoulPointsCostForRank server-side.
AD.INFINITE = { base = 2000, growth = 1.25, maxRank = 255, rankCostCap = 100000000 }
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

-- Curated advisor targets, in priority order for the solo Ret climb.
-- ids   = TalentDatabase node ids (ascending cost; chains ascend along links)
-- costs = every rank's cost across those nodes, ascending (extract)
-- tier  = 1 survival spine, 2 echo economy, 3 offense, 4 quality of life
-- perm  = survives a prestige ("Carry over Prestige" flag in the DB)
AD.NODES = {
  { key = "secondwind", name = "Second Wind", tier = 1,
    ids = { 391 }, costs = { 1500, 3000, 5000 },
    effect = "Out-of-combat self-heal (% max HP per tick)" },
  { key = "victoryfeast", name = "Victory Feast", tier = 1,
    ids = { 388 }, costs = { 7500, 15000, 25000 },
    effect = "Restore % max HP on every XP/honor kill — solo sustain engine" },
  { key = "borrowedtime", name = "Borrowed Time", tier = 1,
    ids = { 335, 336, 337, 338, 339 },
    costs = { 5000, 10000, 15000, 20000, 25000 },
    effect = "Cheat Death: survive a killing blow, restored to % max HP (once per life, refreshes on reset)" },
  { key = "reserveoflife", name = "Reserve of Life", tier = 1,
    ids = { 342, 343, 344, 345, 346, 530, 849, 911 },
    costs = { 7500, 12500, 20000, 25000, 30000, 300000, 600000, 900000 },
    effect = "+1 Cheat Death charge per rank" },
  { key = "undyingspark", name = "Undying Spark", tier = 1,
    ids = { 347, 348, 349, 531, 850, 910 },
    costs = { 5000, 15000, 50000, 500000, 750000, 1000000 },
    effect = "+1 FREE resurrect per run per rank (skips the 10% ash toll; Hardcore: becomes damage reduction)" },
  { key = "refusedrequiem", name = "Refused Requiem", tier = 1,
    ids = { 340, 341, 628, 848, 909 },
    costs = { 25000, 25000, 250000, 500000, 750000 },
    effect = "+1 resurrection accept per rank (more pay-to-continue uses; Hardcore: damage reduction)" },
  { key = "vitality", name = "Endless Vitality", tier = 1, infinite = true,
    ids = { 2000 }, costs = {},
    effect = "+5 Stamina per rank, forever (2,000 x 1.25^rank)", perm = true },
  { key = "steadfast", name = "Steadfast Recovery", tier = 1,
    ids = { 1024 }, costs = { 20000, 50000, 100000, 150000, 250000, 500000 },
    effect = "+healing received while below 35% health" },
  { key = "lastresort", name = "Last Resort", tier = 1,
    ids = { 654 }, costs = { 1000000 },
    effect = "Fatal blow -> immune + teleport to safety (escape a wipe intact)" },

  { key = "twistoffate", name = "Twist of Fate", tier = 2, perm = true,
    ids = { 407, 408, 409, 410, 411, 412, 413, 414, 415, 514, 515, 776, 792,
            819, 820, 921, 922, 1047 },
    costs = { 10000, 10000, 10000, 10000, 10000, 10000, 10000, 10000, 10000,
              100000, 100000, 200000, 200000, 200000, 200000, 300000, 300000,
              300000 },
    effect = "+1 Echo reroll per run per rank" },
  { key = "severance", name = "Echo Severance", tier = 2, perm = true,
    ids = { 630, 631, 632, 633, 634, 635, 636, 637, 638, 639, 818, 1049 },
    costs = { 50000, 50000, 50000, 50000, 50000, 50000, 50000, 50000, 50000,
              50000, 100000, 200000 },
    effect = "+1 Echo banish per run per rank" },
  { key = "carefulsel", name = "Careful Selection", tier = 2, perm = true,
    ids = { 815, 816, 814, 817, 948, 813 },
    costs = { 75000, 75000, 150000, 250000, 350000, 500000 },
    effect = "+1 Echo freeze per run per rank" },
  { key = "luckydraw", name = "Lucky Draw", tier = 2, perm = true,
    ids = { 181, 182, 183, 184, 185, 498, 764, 807, 808 },
    costs = { 50000, 50000, 50000, 50000, 50000, 500000, 500000, 750000,
              750000 },
    effect = "+% chance of higher-quality Echo offers on level-up" },
  { key = "talentoverflow", name = "Talent Overflow", tier = 2, perm = true,
    ids = { 726, 727, 728, 742, 729, 734, 736, 743, 744, 735, 737, 738, 745,
            732, 733, 867, 739, 747, 749, 771, 741, 740, 942, 943, 946 },
    costs = { 25000, 25000, 25000, 25000, 50000, 50000, 50000, 50000, 75000,
              100000, 100000, 100000, 100000, 150000, 200000, 250000, 500000,
              500000, 500000, 500000, 750000, 1000000, 1000000, 1000000,
              1000000 },
    effect = "+1 talent point per rank" },

  { key = "might", name = "Endless Might", tier = 3, infinite = true,
    ids = { 2001 }, costs = {},
    effect = "+10 AP (or +5 SP) per rank, forever (2,000 x 1.25^rank)",
    perm = true },
  { key = "growth", name = "Endless Growth", tier = 3, infinite = true,
    ids = { 2002 }, costs = {},
    effect = "+highest attribute, RAMPING: +1/rank early, later ranks +2, +3... up to +20/rank — commit deep, not shallow",
    perm = true },
  { key = "borrowedpower", name = "Borrowed Power", tier = 3, perm = true,
    ids = { 582, 583, 584, 585 },
    costs = { 100000, 200000, 300000, 400000, 500000, 600000, 700000, 800000,
              900000, 1000000, 1250000, 1500000, 1750000, 2000000, 2500000,
              5000000, 10000000 },
    effect = "Equip +1 item per rank IGNORING level requirement — endgame weapons on level-1 restarts" },
  { key = "braceforimpact", name = "Brace for Impact", tier = 3,
    ids = { 1026 },
    costs = { 100000, 200000, 300000, 400000, 500000, 750000, 1000000,
              1250000 },
    effect = "While above % health, direct hits deal reduced damage" },

  { key = "riding", name = "Riding + Cold Weather Flying", tier = 4, perm = true,
    ids = { 416, 417, 418, 419 },
    costs = { 1500, 5000, 20000, 50000 },
    effect = "Journeyman 1.5k -> Expert 5k -> Cold Weather Flying 20k -> Artisan 50k; all survive prestige" },
  { key = "rapidtransit", name = "Rapid Transit", tier = 4, perm = true,
    ids = { 405 }, costs = { 1000 },
    effect = "Mount speed QoL for 1,000 ash" },
  { key = "boundless", name = "Boundless Growth", tier = 4, perm = true,
    ids = { 191, 192, 193 }, costs = { 75000, 75000, 75000 },
    effect = "+XP% per rank — faster climbs to 80" },
  { key = "provisions", name = "Raider's Provisions", tier = 4,
    ids = { 1001 }, costs = { 1000000 },
    effect = "Food/flask/elixir effects persist through death" },
  { key = "appetite", name = "Bottomless Appetite", tier = 4,
    ids = { 812 }, costs = { 750000 },
    effect = "Benefit from ANY number of food + elixir effects at once" },
  { key = "escape", name = "Prepared Escape", tier = 4,
    ids = { 643, 644, 645, 646, 647, 648, 725, 936 },
    costs = { 35000, 35000, 35000, 35000, 35000, 350000, 750000, 1000000 },
    effect = "Reduce Emergency Exit cooldown per rank" },
}

AD.TIER_NAMES = {
  [1] = "Survival spine",
  [2] = "Echo economy (survives prestige)",
  [3] = "Offense",
  [4] = "Quality of life",
}
