-- The farm queue used to say "go get this" about the very same tome the pool
-- plan said "switch this off" (caught in-game on Arcane Density). Since the
-- CHASE / KEEP / CUT restructure, every farmable echo must land in exactly one
-- of three declared states, and the two tools must read the SAME data.
--
--   node tools/run_lua.js tools/farm_pool_agree_test.lua
PallyPilot = { Classes = {}, print = function() end }
EbonPilot = PallyPilot
local PP = PallyPilot
function UnitExists() return false end
function UnitCanAttack() return false end
function UnitDebuff() return nil end
function UnitBuff() return nil end
function UnitHealth() return 0 end
function UnitHealthMax() return 0 end
function GetTime() return 0 end
PP.RotationHelper = { TargetPct = function() return 100 end }
assert(loadfile("BuildData.lua"))()
local B = assert(PP.Classes.PALADIN, "paladin data")
PP.Build = B

local function norm(s) return string.lower((string.gsub(s or "", "\226\128\153", "'"))) end

-- --- structure -------------------------------------------------------------
assert(type(B.chase) == "table" and #B.chase > 0, "B.chase must exist")
assert(#B.chase <= 20, "CHASE must stay short -- it is what orbs are for, got " .. #B.chase)
for i, e in ipairs(B.chase) do
  assert(type(e) == "table" and type(e[1]) == "string" and e[1] ~= "",
    "chase[" .. i .. "] needs a name")
  assert(type(e[2]) == "string" and #e[2] > 10,
    "chase[" .. i .. "] (" .. e[1] .. ") needs a real reason, not a stub")
end
assert(B.community and B.community.source and #(B.community.names or {}) > 0,
  "community reference build must carry its provenance")

-- --- CHASE must be a subset of KEEP ----------------------------------------
-- If an echo were chase-but-not-keep, the pool would DISABLE the very thing
-- orbs are told to reroll toward: unwinnable.
local keep = B.KeepSet()
for _, n in ipairs(B.ChaseList()) do
  assert(keep[norm(n)], "CHASE echo not in KEEP (pool would disable it): " .. n)
end

-- Locks likewise must never be cut.
for _, n in ipairs(B.locked or {}) do
  assert(keep[norm(n)], "locked core not in KEEP: " .. n)
end

-- --- the three states are total and disjoint -------------------------------
local chaseSet = {}
for _, n in ipairs(B.ChaseList()) do chaseSet[norm(n)] = true end
local function fate(name)
  if chaseSet[norm(name)] then return "CHASE" end
  if B.IsKeep(name) then return "KEEP" end
  return "CUT"
end

local counts = { CHASE = 0, KEEP = 0, CUT = 0 }
local seen = {}
local function consider(n)
  if seen[norm(n)] then return end
  seen[norm(n)] = true
  counts[fate(n)] = counts[fate(n)] + 1
end
for n in pairs(B.catalog or {}) do consider(n) end
for _, tier in ipairs({ "S", "A", "B", "C" }) do
  for _, n in ipairs((B.tiers or {})[tier] or {}) do consider(n) end
end
for _, n in ipairs(B.locked or {}) do consider(n) end
for _, n in ipairs((B.community or {}).names or {}) do consider(n) end

print(("CHASE=%d  KEEP=%d  CUT=%d   (of %d distinct echoes considered)"):format(
  counts.CHASE, counts.KEEP, counts.CUT,
  counts.CHASE + counts.KEEP + counts.CUT))

assert(counts.CHASE == #B.chase, "every CHASE entry should classify as CHASE")
assert(counts.KEEP > counts.CHASE, "KEEP must be the broad tier -- breadth is a stat")
assert(counts.CUT > 0, "nothing being cut means the pool plan does nothing")

-- --- the specific echoes that exposed the original bug ---------------------
-- Arcane Density: keepsy farmed it and Nero runs it, so it must not be CUT.
assert(fate("Arcane Density") ~= "CUT", "Arcane Density must not be cut")
-- Demonic Awakening: locked by both published warrior builds; it was disabled
-- in keepsy's live pool, which is exactly what this restructure fixes.
assert(fate("Demonic Awakening") == "CHASE", "Demonic Awakening should be CHASE")
-- Twilight Equilibrium: 33% of measured damage. If this ever leaves CHASE,
-- something has gone badly wrong.
assert(fate("Twilight Equilibrium") == "CHASE", "Twilight Equilibrium must be CHASE")
-- Every echo Nero actually plays should survive curation.
local cutFromNero = {}
for _, n in ipairs((B.community or {}).names or {}) do
  if fate(n) == "CUT" then cutFromNero[#cutFromNero + 1] = n end
end
assert(#cutFromNero == 0,
  "pool would cut " .. #cutFromNero .. " echoes Nero runs: "
  .. table.concat(cutFromNero, ", "))

print("\nAGREE OK -- CHASE subset of KEEP, three states total and disjoint,")
print("and nothing in the reference build gets cut.")
