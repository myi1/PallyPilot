-- SHOW ONLY WHAT APPLIES RIGHT NOW.
--
-- Two complaints from the live panel, both the same failure -- the rail showed
-- controls and lists whose state it had never actually checked:
--
--   1. "Curate pool (level 1)" and "Pool plan (level 1)" sat there at every
--      level. Tome toggles are level-1-only and orbs are a level-80 tool, so at
--      any moment at most one of those toolsets can be used and while levelling
--      neither can. Half a narrow rail was permanently inert.
--   2. "LOCK NOW -- best 6 owned" printed the same six names whether or not you
--      had already locked all six, so a finished job looked exactly like an
--      untouched one.
--
--   node tools/run_lua.js tools/rail_conditional_test.lua
PallyPilot = { Classes = {}, print = function() end,
               safeCall = function(fn, ...) return fn(...) end }
EbonPilot = PallyPilot
local PP = PallyPilot
PP.db = { options = { rerollOrbs = 1 }, buildMode = "raid", scans = {} }
local function Stub()
  local t = {}
  return setmetatable(t, { __index = function() return function() return t end end })
end
function CreateFrame() return Stub() end
UIParent = Stub()
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function GetTime() return 0 end
function date() return "2026-09-01 18:00" end
function UnitClass() return "Paladin", "PALADIN" end

local LEVEL = 80
function UnitLevel() return LEVEL end

assert(loadfile("BuildData.lua"))()
PP.Build = PP.Classes.PALADIN

-- ---------------------------------------------------------------------------
-- 1. LOCK LIST: it must empty as you lock things.
PP.TomeManager = PP.TomeManager or {}
local lockedNames = {}
PP.TomeManager.MergedTiles = function()
  local out = {}
  for _, n in ipairs({ "Ambidexterity", "Twilight Equilibrium", "Adaptive Power" }) do
    out[#out + 1] = { name = n, known = true, disabled = false,
                      locked = lockedNames[n] == true }
  end
  return out, "live", {}
end

PP.EchoAudit = PP.EchoAudit or {}
assert(loadfile("EchoAudit.lua"))()
local A = PP.EchoAudit
PP.db.options.lockSlots = 3

local buckets = { CORE = { "Ambidexterity", "Twilight Equilibrium" },
                  S = { "Adaptive Power" }, A = {}, B = {} }

local picks, known = A.LockNow(buckets)
assert(known, "with tiles readable the lock state must be reported")
assert(#picks == 3, "three lock slots, three picks")
for _, p in ipairs(picks) do
  assert(p.locked == false, p.name .. " is not locked yet, so locked must be false")
end
print("none locked : 3 picks, 0 reported as done")

lockedNames["Ambidexterity"] = true
lockedNames["Adaptive Power"] = true
picks = A.LockNow(buckets)
local done, todo = 0, {}
for _, p in ipairs(picks) do
  if p.locked then done = done + 1 else todo[#todo + 1] = p.name end
end
assert(done == 2, "two are locked now, got " .. done)
assert(#todo == 1 and todo[1] == "Twilight Equilibrium",
  "only the unlocked one is still to do, got " .. table.concat(todo, ","))
print("two locked  : 2 done, still to do -> " .. todo[1])

lockedNames["Twilight Equilibrium"] = true
picks = A.LockNow(buckets)
done = 0
for _, p in ipairs(picks) do if p.locked then done = done + 1 end end
assert(done == 3, "all three locked, got " .. done)
print("all locked  : 3 done -- the panel must now say LOCKS SET, not re-list them")

-- UNKNOWN is not FALSE. With the catalog unreadable we must not claim anything
-- is unlocked -- that is how you get told to redo work you already did.
PP.TomeManager.MergedTiles = function() return nil, "closed" end
local blindPicks, blindKnown = A.LockNow(buckets)
assert(blindKnown == false, "an unreadable catalog must report lockKnown = false")
for _, p in ipairs(blindPicks) do
  assert(p.locked == nil,
    p.name .. ": lock state must be nil (unknown), never false, when unreadable")
end
print("catalog shut: lock state reported as unknown, not as unlocked")

-- ---------------------------------------------------------------------------
-- 2. LEVEL-GATED TOOLS. Only one toolset can apply at a time.
PP.EchoFlow = {}
PP.BisPlan = { Status = function() return nil end }
A.RunQualityTargets = function() return {} end
A.FodderRank = function() return {} end
assert(loadfile("EchoFlow.lua"))()
local EF = PP.EchoFlow

-- ResolveNextAction is the level decision in one place; assert each branch
-- offers the tool that is actually usable at that level.
local function labelAt(lvl)
  LEVEL = lvl
  return (EF.ResolveNextAction())
end

local one = labelAt(1)
assert(one == "Curate pool",
  "level 1 leads with pool curation, got " .. tostring(one))
assert(not string.find(one, "level 1", 1, true),
  "the label must not carry a '(level 1)' suffix -- the button only exists at 1")
print("level 1     : " .. one)

local mid = labelAt(42)
assert(mid == "Sync auto-pick",
  "while levelling neither toolset applies, got " .. tostring(mid))
print("level 42    : " .. mid)

LEVEL = 80
local cap = EF.ResolveNextAction()
assert(cap and not string.find(cap, "Curate pool", 1, true),
  "at 80 tome toggles are closed, got " .. tostring(cap))
print("level 80    : " .. cap)

print("\nCONDITIONAL OK -- locks stop re-listing once set, and each level")
print("only offers the toolset it can actually use.")
