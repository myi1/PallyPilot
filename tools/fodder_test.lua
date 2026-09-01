-- FODDER RANKING. Corrected model (player, 2026-09-01): an orb reroll consumes
-- an echo YOU SELECT. So "out of fodder" cannot happen while you hold echoes --
-- the only question is which one you can most afford to lose.
--
-- Guards three things the old code got wrong:
--   1. never offer a CHASE target as fodder (feeding what you hunt)
--   2. never offer a locked echo (they persist across runs)
--   3. order weakest-first, so a same-tier draw is a wash and not a loss
--
--   node tools/run_lua.js tools/fodder_test.lua
PallyPilot = { Classes = {}, print = function() end,
               safeCall = function(fn, ...) return fn(...) end }
EbonPilot = PallyPilot
local PP = PallyPilot
PP.db = { options = {} }
local function Stub()
  local t = {}
  return setmetatable(t, { __index = function() return function() return t end end })
end
function CreateFrame() return Stub() end
function UnitLevel() return 80 end
function GetTime() return 0 end
function UnitClass() return "Paladin", "PALADIN" end
UIParent = Stub()

assert(loadfile("BuildData.lua"))()
PP.Build = PP.Classes.PALADIN

-- Classify comes from the real build data, so use real echo names.
--   Twilight Equilibrium = locked core AND chase  -> excluded
--   Contagion            = chase                  -> excluded
--   Widow's Venom        = A                      -> mid
--   Conjured Flame       = B                      -> weak
--   Heavy Incantations   = C                      -> weakest
ProjectEbonhold = { Perks = { grantedPerks = {
  ["Twilight Equilibrium"] = { { quality = 1 } },
  ["Contagion"]            = { { quality = 1 } },
  ["Widow's Venom"]        = { { quality = 1 } },
  ["Conjured Flame"]       = { { quality = 3 } },
  ["Heavy Incantations"]   = { { quality = 3 } },
  ["Conjured Flame - Rare"] = { { quality = 1 } },
} } }

PP.BisPlan = { IsTarget = function(n)
  local k = string.lower((string.gsub(n or "", "\226\128\153", "'")))
  for _, t in ipairs(PP.Build.ChaseList()) do
    if string.lower((string.gsub(t, "\226\128\153", "'"))) == k then return true end
  end
  return false
end }

-- Core.lua normally creates the namespaces; the data files are loaded alone
-- here, so stand them up first.
PP.EchoAudit = PP.EchoAudit or {}
assert(loadfile("EchoAudit.lua"))()
local A = PP.EchoAudit
assert(A.FodderRank, "FodderRank must exist")

local rank = assert(A.FodderRank(), "FodderRank must resolve with grantedPerks present")
for i, f in ipairs(rank) do
  print(("  %d. %-24s tier=%-2s q=%s"):format(i, f.name, f.tier, tostring(f.q)))
end

local byName = {}
for i, f in ipairs(rank) do byName[f.name] = i end

-- 1. Never feed a locked core or a chase target.
assert(not byName["Twilight Equilibrium"],
  "a locked CHASE core must never be offered as fodder")
assert(not byName["Contagion"], "a CHASE target must never be offered as fodder")

-- 2. Something must remain, or the advice dead-ends again.
assert(#rank > 0, "there must always be fodder while echoes exist")

-- 3. Weakest first: the worst-tier entry outranks better-tier ones.
local worstRank = { CORE = 1, S = 2, A = 3, B = 4, C = 5, REROLL = 6, DISABLE = 7 }
for i = 2, #rank do
  local prev, cur = rank[i - 1], rank[i]
  local pr, cr = worstRank[prev.tier] or 6, worstRank[cur.tier] or 6
  assert(pr >= cr, ("order broken at %d: %s(%s) before %s(%s)")
    :format(i, prev.name, prev.tier, cur.name, cur.tier))
  if pr == cr then
    assert(prev.q <= cur.q, "within a tier, lower quality is fed first")
  end
end

-- 4. The top pick must be genuinely expendable -- never CORE or S.
assert(rank[1].tier ~= "CORE" and rank[1].tier ~= "S",
  "the first fodder suggestion must not be a core/S echo, got " .. rank[1].tier)
print("\nfirst fodder: " .. rank[1].name .. " [" .. rank[1].tier .. "]")

print("FODDER OK -- weakest first, chase targets and locks protected.")
