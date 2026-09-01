-- BP.Status state machine: the RUN must outrank the catalog.
--
-- The bug: the old order tested "do I own the tome?" first, so six echoes
-- sitting in the run at Epic -- Twilight Equilibrium, Adaptive Power,
-- Ambidexterity, Pandemic among them -- were reported [FARM]. The trap is that
-- `tomeKnown` is false for echoes that need NO tome, so "no tome" and "cannot
-- have it" are different things.
--
--   node tools/run_lua.js tools/status_state_test.lua
PallyPilot = { print = function() end, safeCall = function(fn, ...) return fn(...) end }
EbonPilot = PallyPilot
local PP = PallyPilot
PP.db = {}
local function Stub()
  local t = {}
  return setmetatable(t, { __index = function() return function() return t end end })
end
function CreateFrame() return Stub() end
function UnitLevel() return 80 end
function GetTime() return 0 end
UIParent = Stub()

PP.Build = {
  locked = {},
  ChaseList = function()
    return { "In Run Epic", "In Run Cheap", "Base Pool", "Owned Off",
             "Owned On", "Truly Missing" }
  end,
  ChaseReason = function() return "test" end,
  IsKeep = function() return true end,
}
PP.EchoAudit = { LockSlots = function() return 6 end,
                 RunQualityTargets = function() return {} end }
PP.EchoFlow = { RunJunkList = function() return {} end }

-- The catalog. Note "In Run Epic" and "Base Pool" have NO tome (known=false),
-- which is exactly the case the old ordering mishandled.
local TILES = {
  { name = "In Run Epic",   known = false, disabled = false, locked = false },
  { name = "In Run Cheap",  known = true,  disabled = false, locked = false },
  { name = "Base Pool",     known = false, disabled = false, locked = false },
  { name = "Owned Off",     known = true,  disabled = true,  locked = false },
  { name = "Owned On",      known = true,  disabled = false, locked = false },
  -- "Truly Missing" has no tile at all.
}
PP.TomeManager = { MergedTiles = function() return TILES, "scan+live" end }

-- The run: two of them are actually in the build right now.
EbonholdHub = { EchoOwnership = { CollectOwnedSets = function()
  return { ["in run epic"] = true, ["in run cheap"] = true }
end } }
ProjectEbonhold = { Perks = { grantedPerks = {
  ["in run epic"]  = { quality = 4 },   -- Epic
  ["in run cheap"] = { quality = 1 },   -- sub-Epic -> FISH
} } }

assert(loadfile("BisPlan.lua"))()
local BP = PP.BisPlan
local st = assert(BP.Status(), "Status must resolve")

local got = {}
for _, r in ipairs(st.list) do got[r.name] = r.state end
for _, n in ipairs({ "In Run Epic", "In Run Cheap", "Base Pool", "Owned Off",
                     "Owned On", "Truly Missing" }) do
  print(("  %-14s -> %s"):format(n, tostring(got[n])))
end

-- THE REGRESSION: in the run, no tome, must NOT be FARM.
assert(got["In Run Epic"] == "EPIC",
  "in-run Epic with no tome must be EPIC, got " .. tostring(got["In Run Epic"]))
assert(got["In Run Cheap"] == "FISH",
  "in-run sub-Epic must be FISH, got " .. tostring(got["In Run Cheap"]))
-- A base-pool echo is drawable and cannot be farmed.
assert(got["Base Pool"] == "ROLL",
  "no tome but a tile exists -> rollable, got " .. tostring(got["Base Pool"]))
assert(got["Owned Off"] == "OFF", "owned but disabled -> OFF")
assert(got["Owned On"] == "ROLL", "owned, enabled, not in run -> ROLL")
-- Only a total absence from the catalog is genuinely farmable.
assert(got["Truly Missing"] == "FARM",
  "absent from the catalog -> FARM, got " .. tostring(got["Truly Missing"]))
assert(st.counts.FARM == 1, "exactly one FARM, got " .. st.counts.FARM)

-- And the next action must never dead-end on "no fodder": you choose the
-- sacrifice, so a missing echo always has an answer.
PP.EchoAudit.FodderRank = function()
  return { { name = "Weakest Thing", tier = "C", q = 1 } }
end
local act = BP.NextAction(BP.Status())
assert(string.find(act, "ROLL for"), "must advise rolling: " .. act)
assert(string.find(act, "Weakest Thing"), "must name the fodder: " .. act)
assert(not string.find(act, "fodder in run"), "must not claim fodder ran out: " .. act)

print("\nSTATUS OK -- run outranks catalog; only truly absent echoes are FARM.")
