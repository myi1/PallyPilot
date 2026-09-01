-- The rail's NEXT button: one actionable thing per state, and never a live
-- button that does nothing when clicked.
--
--   node tools/run_lua.js tools/rail_next_test.lua
PallyPilot = { print = function() end, safeCall = function(fn, ...) return fn(...) end }
EbonPilot = PallyPilot
local PP = PallyPilot
PP.db = { options = { rerollOrbs = 1 }, buildMode = "raid" }
PP.EchoFlow = {}

local function Stub()
  local t = {}
  return setmetatable(t, { __index = function() return function() return t end end })
end
function CreateFrame() return Stub() end
UIParent = Stub()
function GetTime() return 0 end
function UnitClass() return "Paladin", "PALADIN" end
local level = 80
function UnitLevel() return level end

local rolls, subEpic, hasFodder = 3, 0, true
PP.EchoAudit = {
  LockSlots = function() return 6 end,
  Compute = function() return nil end,
  RunQualityTargets = function()
    local t = {}; for i = 1, subEpic do t[i] = { name = "k" .. i } end; return t
  end,
  FodderRank = function()
    if not hasFodder then return {} end
    return { { name = "Heavy Incantations", tier = "C", q = 1 } }
  end,
}
PP.BisPlan = { Status = function()
  return { counts = { LOCKED = 0, EPIC = 0, FISH = 0, INRUN = 0,
                      ROLL = rolls, OFF = 0, FARM = 0 } }
end }

local called
PP.TomeManager = { Scan = function() called = "scan" end }
PP.HubSync = { Push = function() called = "sync" end }

assert(loadfile("EchoFlow.lua"))()
local EF = PP.EchoFlow
EF.StartReroll = function() called = "reroll" end
EF.StartQualityFish = function() called = "fish" end
assert(EF.ResolveNextAction, "EF.ResolveNextAction must be exposed")

local function at(lvl, r, se, fod)
  level, rolls, subEpic, hasFodder = lvl, r, se, fod
  called = nil
  local label, tip, handler = EF.ResolveNextAction()
  if handler then handler() end
  return label, tip, called
end

-- 1. Level 1 outranks everything, even a pile of missing echoes.
local label, tip, did = at(1, 5, 5, true)
print(("lvl 1    %-28s -> %s"):format(tostring(label), tostring(did)))
assert(label and string.find(label, "Curate"), "level 1 must curate: " .. tostring(label))
assert(did == "scan", "level 1 button must run the tome scan, got " .. tostring(did))

-- 2. Levelling: EBH does the work; the only lever is staying synced.
label, tip, did = at(42, 5, 5, true)
print(("lvl 42   %-28s -> %s"):format(tostring(label), tostring(did)))
assert(label and string.find(label, "Sync"), "levelling must sync: " .. tostring(label))
assert(did == "sync", "levelling button must push the build, got " .. tostring(did))

-- 3. At 80 with echoes missing: roll, and name the fodder in the tooltip.
label, tip, did = at(80, 3, 0, true)
print(("lvl 80/a %-28s -> %s"):format(tostring(label), tostring(did)))
assert(string.find(label, "3 missing"), "must count the missing: " .. label)
assert(string.find(tip, "Heavy Incantations"), "tooltip must name the fodder: " .. tip)
assert(did == "reroll", "must start a reroll, got " .. tostring(did))

-- 4. Nothing missing but keepers below Epic: fish.
label, tip, did = at(80, 0, 12, true)
print(("lvl 80/b %-28s -> %s"):format(tostring(label), tostring(did)))
assert(string.find(label, "Quality fish"), "must fish: " .. label)
assert(did == "fish", "must start fishing, got " .. tostring(did))

-- 5. Done: advice, but NOT a clickable button that silently does nothing.
label, tip, did = at(80, 0, 0, true)
print(("lvl 80/c %-28s -> %s"):format(tostring(label), tostring(did)))
assert(string.find(label, "complete"), "must report completion: " .. label)
assert(did == nil, "the completion state has no automatable action")

-- 6. Genuinely nothing feedable: no label at all, so the button hides rather
--    than offering a click that cannot work.
label, tip, did = at(80, 4, 0, false)
print(("lvl 80/d %-28s -> %s"):format(tostring(label), tostring(did)))
assert(label == nil, "with no fodder and nothing to fish the button must hide")
assert(tip and #tip > 0, "it must still explain why")

print("\nRAIL NEXT OK -- one action per state, no dead buttons.")
