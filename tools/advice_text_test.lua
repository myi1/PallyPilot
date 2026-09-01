-- ADVICE TEXT GUARD.
--
-- The Dashboard's focal NEXT card told the player to "banish junk as it
-- appears" while levelling and to "Reroll junk / orb-fish on a banished pool"
-- at 80. Both are impossible: EbonholdHub's automation spends banishes during
-- 1-80 and banish is never offered on an orb reroll. Nothing tested this file,
-- so the wrong copy survived every earlier correction elsewhere.
--
-- This asserts the player is never instructed to banish, and never told a
-- reroll needs junk, at any level.
--
--   node tools/run_lua.js tools/advice_text_test.lua
PallyPilot = { print = function() end, safeCall = function(fn, ...) return fn(...) end }
EbonPilot = PallyPilot
local PP = PallyPilot
PP.db = { buildMode = "raid", kills = {} }

local function Stub()
  local t = {}
  return setmetatable(t, { __index = function() return function() return t end end })
end
function CreateFrame() return Stub() end
UIParent = Stub()
local level, zone = 80, "Icecrown"
function UnitLevel() return level end
function GetRealZoneText() return zone end
function UnitClass() return "Paladin", "PALADIN" end
function GetTime() return 0 end

-- Core.lua normally creates the namespaces; stand up the ones Dashboard needs.
PP.Dashboard = PP.Dashboard or {}
PP.EchoAudit = { LockSlots = function() return 6 end }
PP.GuideData = { RaidForZone = function() return nil end }
PP.AshAdvisor = { GetState = function() return nil end }
PP.AshData = {}

assert(loadfile("Dashboard.lua"))()
local D = PP.Dashboard
assert(D and D.NextAction, "Dashboard.NextAction must exist")

-- Words that describe an action the player cannot take. "banish" is allowed
-- ONLY when the sentence attributes it to EBH.
local function check(lvl, label)
  level = lvl
  local s = D.NextAction() or ""
  local low = string.lower(s)
  print(("  lvl %-3d %s"):format(lvl, label))
  if string.find(low, "banish", 1, true) then
    assert(string.find(low, "ebh", 1, true) or string.find(low, "for you", 1, true),
      ("lvl %d instructs the player to banish: %s"):format(lvl, s))
  end
  assert(not string.find(low, "reroll junk", 1, true),
    ("lvl %d says 'reroll junk' -- a reroll consumes any echo you pick: %s")
      :format(lvl, s))
  assert(not string.find(low, "banished pool", 1, true),
    ("lvl %d references a 'banished pool' at endgame: %s"):format(lvl, s))
  assert(#s > 0, "NextAction must always say something")
  return s
end

local one = check(1, "pool curation window")
assert(string.find(string.lower(one), "level 1"),
  "level 1 must lead with the toggle window, got: " .. one)

check(3, "run start")
check(42, "levelling")
local eighty = check(80, "endgame")
assert(string.find(string.lower(eighty), "weakest")
    or string.find(string.lower(eighty), "you pick"),
  "endgame advice must say you choose the fodder, got: " .. eighty)

print("\nADVICE OK -- no un-actionable banish or junk-fodder instructions.")
