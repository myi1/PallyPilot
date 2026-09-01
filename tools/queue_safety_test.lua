-- QUEUE SAFETY. A caller bug queued 70 echoes on a finished build, and because
-- EbonholdHub's auto-pick answers the draw there is no pause between items --
-- it would have eaten the build unattended.
--
-- Two invariants:
--   1. With no rated junk, the keeper fallback queues exactly ONE echo. Feeding
--      a keeper is a gamble with a real cost; it is never a batch.
--   2. No queue, from any caller, exceeds the hard cap.
--
--   node tools/run_lua.js tools/queue_safety_test.lua
PallyPilot = { print = function(s) MSG[#MSG + 1] = s end,
               safeCall = function(fn, ...) return fn(...) end }
EbonPilot = PallyPilot
local PP = PallyPilot
MSG = {}
PP.db = { options = { rerollOrbs = 1 }, buildMode = "raid" }
PP.EchoFlow = {}

local function Stub()
  local t = {}
  return setmetatable(t, { __index = function() return function() return t end end })
end
function CreateFrame() return Stub() end
UIParent = Stub()
function GetTime() return 0 end
function UnitLevel() return 80 end
function UnitClass() return "Paladin", "PALADIN" end
function UnitAffectingCombat() return false end

-- No junk in the run; a big pile of keepers that COULD be fed.
local bigRank = {}
for i = 1, 70 do
  bigRank[i] = { name = "Keeper " .. i, tier = (i < 60 and "B" or "A"), q = 1 }
end
PP.EchoAudit = {
  LockSlots = function() return 6 end,
  Compute = function() return nil end,
  RunQualityTargets = function() return {} end,
  FodderRank = function() return bigRank end,
  OwnedCopy = function() return {} end,
  RunVerdicts = function() return {} end,
}
PP.BisPlan = { Status = function() return nil end }

assert(loadfile("EchoFlow.lua"))()
local EF = PP.EchoFlow

-- With no journal present the engine cannot really run; what matters is the
-- QUEUE it builds, which IsRunning/total expose.
MSG = {}
EF.StartReroll()
local msg = table.concat(MSG, " | ")
print("start message: " .. msg)

-- 1. Exactly one echo queued, and it is the weakest.
assert(string.find(msg, "Reroll ONE", 1, true),
  "no-junk path must queue exactly one keeper, got: " .. msg)
assert(string.find(msg, "Keeper 1", 1, true),
  "it must be the weakest-ranked echo, got: " .. msg)
assert(not string.find(msg, "70", 1, true),
  "must never queue the whole fodder ranking: " .. msg)

-- 2. The cap protects any caller. Drive a deliberately oversized batch through
--    the same public entry the fisher uses.
EF.Stop()
MSG = {}
local many = {}
for i = 1, 40 do many[i] = "Fish " .. i end
PP.EchoAudit.RunQualityTargets = function()
  local t = {}
  for i, n in ipairs(many) do t[i] = { name = n } end
  return t
end
EF.StartQualityFish()
msg = table.concat(MSG, " | ")
print("fish message : " .. msg:sub(1, 160))
assert(string.find(msg, "Capped at", 1, true),
  "an oversized batch must be capped, got: " .. msg)

print("\nQUEUE SAFETY OK -- one keeper at a time, and every batch is bounded.")

-- ---------------------------------------------------------------------------
-- HUNT: goal-directed rolling must be bounded and must stop on success.
EF.Stop()
local landed = nil
PP.BisPlan = { Status = function()
  return { list = {
    { name = "Contagion",         state = landed == "Contagion" and "EPIC" or "ROLL" },
    { name = "Crypt Lord's Swarm", state = "ROLL" },
  }, counts = { ROLL = 2, FARM = 0 } }
end }

MSG = {}
EF.StartHunt(3)
local m = table.concat(MSG, " | ")
print("hunt start  : " .. m:sub(1, 150))
assert(string.find(m, "HUNT", 1, true), "must announce the hunt: " .. m)
assert(string.find(m, "3 roll", 1, true), "must state the budget: " .. m)
assert(string.find(m, "Contagion", 1, true), "must name what it chases: " .. m)
assert(string.find(m, "Keeper 1", 1, true), "must name the first fodder: " .. m)

-- Budget is hard-capped even if a caller asks for something silly.
EF.Stop(); MSG = {}
EF.StartHunt(999)
m = table.concat(MSG, " | ")
assert(string.find(m, "12 roll", 1, true), "budget must cap at 12, got: " .. m)
print("hunt cap    : capped a 999-roll request")

-- Landing a target ends it immediately, whatever budget remains.
EF.Stop(); MSG = {}
EF.StartHunt(5)
MSG = {}
local more = EF.HuntStep("Contagion")
m = table.concat(MSG, " | ")
print("hunt land   : " .. m:sub(1, 110))
assert(more == false, "landing a target must end the hunt")
assert(string.find(m, "GOT IT", 1, true), "must announce the win: " .. m)

-- Stopping clears the hunt so an ordinary reroll cannot resume it.
EF.Stop(); MSG = {}
EF.StartHunt(5)
EF.Stop()
assert(EF.HuntStep("anything") == false,
  "Stop must disarm the hunt -- otherwise the next reroll silently resumes it")
print("hunt disarm : Stop clears it")

print("HUNT OK -- bounded, goal-directed, and disarmed by Stop.")
