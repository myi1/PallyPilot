-- The Builds page answers ONE question: which build should I run?
--
-- It used to be a metric x build matrix -- thirteen labelled rows, three
-- columns -- which answered "what are all the numbers" and left the reader to
-- do the comparison themselves. Worse, it led with PREDICTED composition while
-- the measured damage sat below it.
--
-- These assert it names an answer, never ranks a guess above evidence,
-- surfaces builds that exist only as fight tags, and filters one-off noise.
--
--   node tools/run_lua.js tools/buildpage_test.lua
OUT = {}
PallyPilot = { print = function(x) OUT[#OUT + 1] = tostring(x) end,
               safeCall = function(fn, ...) return fn(...) end }
EbonPilot = PallyPilot
local PP = PallyPilot

local function Stub()
  local t = {}
  return setmetatable(t, { __index = function() return function() return t end end })
end
function CreateFrame() return Stub() end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, x) OUT[#OUT + 1] = tostring(x) end }
UIParent = Stub()
function GetTime() return 0 end
function date() return "2026-09-01 18:00" end
function UnitClass() return "Paladin", "PALADIN" end
function UnitLevel() return 80 end
PP.BuildLog = {}
PP.EchoAudit = { LockSlots = function() return 6 end }

PP.db = { buildLog = {}, fights = {} }
local function fight(build, dps)
  PP.db.fights[#PP.db.fights + 1] = { build = build, dps = dps, dur = 30 }
end

assert(loadfile("BuildLog.lua"))()
local BL = PP.BuildLog

local function report()
  OUT = {}
  BL.Report()
  return table.concat(OUT, "\n")
end

-- 1. A clear winner over a real sample must be named, ahead of the loser.
PP.db.buildLog = { ["k1"] = { name = "Loadout 7", id = "k1" },
                   ["k2"] = { name = "Bis build", id = "k2" } }
for _ = 1, 40 do fight("Loadout 7", 320000) end
for _ = 1, 40 do fight("Bis build", 250000) end
local out = report()
assert(string.find(out, "Loadout 7", 1, true), "must name the winner:\n" .. out)
assert(string.find(out, "Bis build", 1, true), "must list the loser too:\n" .. out)
assert(string.find(out, "Loadout 7", 1, true) < string.find(out, "Bis build", 1, true),
  "the measured winner must come first:\n" .. out)
print("1. winner named and ordered first")

-- 2. A high-scoring build with NO fights must never outrank a measured one.
--    This is the whole point of separating MEASURED from PREDICTED.
PP.db.buildLog["k3"] = { name = "Never Played", id = "k3", score = 99, S = 40 }
out = report()
local iNever = string.find(out, "Never Played", 1, true)
assert(iNever, "an unmeasured build should still be listed:\n" .. out)
assert(string.find(out, "Loadout 7", 1, true) < iNever,
  "a prediction must never rank above evidence:\n" .. out)
print("2. prediction ranked below evidence")

-- 3. Builds that exist only as a fight tag must appear -- that is where most of
--    the logged history actually lives (427 fights on one, in the real data).
PP.db.buildLog = {}
PP.db.fights = {}
for _ = 1, 12 do fight("arm3-hor-hc2", 300000) end
out = report()
assert(string.find(out, "arm3", 1, true), "tag-only builds must surface:\n" .. out)
print("3. tag-only build surfaced")

-- 4. A throwaway tag with two fights is noise, not a build.
PP.db.buildLog = {}
PP.db.fights = {}
fight("idk", 1)
fight("idk", 2)
out = report()
assert(not string.find(out, "idk", 1, true), "one-off tags must be filtered:\n" .. out)
print("4. one-off tag filtered")

-- 5. It is a chat GLANCE, not the page. Six lines per build with no cap meant
--    the ranking scrolled out of view before you could read it.
PP.db.buildLog = {}
PP.db.fights = {}
for i = 1, 9 do
  for _ = 1, 5 do fight("build-" .. i, 100000 + i) end
end
OUT = {}
BL.Report()
print("report lines: " .. #OUT .. " for 9 builds")
assert(#OUT <= 8, "/ep builds must stay within 8 chat lines, printed " .. #OUT)
assert(string.find(table.concat(OUT, "\n"), "more on the Builds page", 1, true),
  "the truncated tail must point at the page that has room for it")
print("5. chat output capped, overflow signposted")

print("\nBUILD PAGE OK -- names an answer, ranks evidence over prediction,")
print("surfaces tag-only builds, filters noise, and stays out of the scrollback.")
