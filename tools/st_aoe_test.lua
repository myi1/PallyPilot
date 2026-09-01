-- SINGLE-TARGET AND AoE ARE DIFFERENT QUESTIONS.
--
-- Measured against the real 1000-fight log on 2026-09-02:
--
--   single-target fights   125   median  77k   max   324k
--   AoE fights (3+ tgts)   556   median 394k   max 14.9M
--
-- Nothing in there is corrupt. A 14.9M reading is a genuine ICC trash pull.
-- But it means a BLENDED average ranks builds by how much trash they happened
-- to fight -- and that is exactly what the page was doing. It crowned a build
-- with seven AoE-only fights over one with 249 mixed fights and reported a
-- "761%" lead with no hedging at all.
--
-- These assert the split exists, that each bucket names its own winner, and
-- that a build measured in only one bucket does not silently imply the other.
--
--   node tools/run_lua.js tools/st_aoe_test.lua
OUT = {}
PallyPilot = { print = function(x) OUT[#OUT + 1] = tostring(x) end,
               safeCall = function(fn, ...) return fn(...) end }
EbonPilot = PallyPilot
local PP = PallyPilot

-- Capture what the page WRITES, not just what it prints: the verdict and the
-- per-row text are the things the player actually reads.
local written = {}
local NUMERIC = { GetStringHeight = 14, GetHeight = 20, GetWidth = 430,
                  GetVerticalScroll = 0, GetNumPoints = 0 }
local function Recorder()
  local t = {}
  t.SetText = function(_, s) written[#written + 1] = tostring(s or "") end
  return setmetatable(t, { __index = function(tbl, k)
    -- Layout code does arithmetic on measured heights, so those have to come
    -- back as numbers rather than the generic chainable stub.
    local n = NUMERIC[k]
    if n then return function() return n end end
    return function() return tbl end
  end })
end
function CreateFrame() return Recorder() end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, x) OUT[#OUT + 1] = tostring(x) end }
UIParent = Recorder()
function GetTime() return 0 end
function date() return "2026-09-02 01:00" end
function UnitClass() return "Paladin", "PALADIN" end
function UnitLevel() return 80 end
PP.BuildLog = {}
PP.EchoAudit = { LockSlots = function() return 6 end }
PP.db = { buildLog = {}, fights = {} }

local function fight(build, dps, tgts)
  PP.db.fights[#PP.db.fights + 1] =
    { build = build, dps = dps, dur = 30, tgts = tgts }
end

assert(loadfile("BuildLog.lua"))()
local BL = PP.BuildLog

-- "Cleaver" is an AoE monster and mediocre on a boss.
-- "Focus" is the reverse. A blended average would rank Cleaver far ahead
-- purely because AoE numbers are an order of magnitude bigger.
for _ = 1, 20 do fight("Cleaver", 60000, 1) end
for _ = 1, 20 do fight("Cleaver", 900000, 6) end
for _ = 1, 20 do fight("Focus", 150000, 1) end
for _ = 1, 20 do fight("Focus", 300000, 6) end

PP.db.buildLog = { ["k1"] = { name = "Cleaver", id = "k1" },
                   ["k2"] = { name = "Focus",   id = "k2" } }

-- Refresh no-ops without the frame, so stand the page up first.
assert(BL.Init2, "BL.Init2 builds the page")
PP.safeCall(BL.Init2)
written = {}
PP.safeCall(BL.Refresh)
local page = table.concat(written, "\n")
assert(#page > 0, "the page rendered nothing -- the harness is not driving it")

-- 1. Both buckets appear, with their own numbers.
assert(string.find(page, "ST ", 1, true), "rows must show a single-target number:\n" .. page)
assert(string.find(page, "AoE ", 1, true), "rows must show an AoE number:\n" .. page)
print("1. rows carry both numbers")

-- 2. The header names the winner OF EACH BUCKET -- they are different builds
--    here, and that is the whole point.
local iSt = string.find(page, "Single target:", 1, true)
local iAoe = string.find(page, "AoE:", 1, true)
assert(iSt and iAoe, "the header must answer per bucket:\n" .. page)
local stLine = string.sub(page, iSt, iSt + 90)
local aoeLine = string.sub(page, iAoe, iAoe + 90)
assert(string.find(stLine, "Focus", 1, true),
  "Focus wins single target (150k vs 60k):\n" .. stLine)
assert(string.find(aoeLine, "Cleaver", 1, true),
  "Cleaver wins AoE (900k vs 300k):\n" .. aoeLine)
print("2. header: ST -> Focus, AoE -> Cleaver")

-- 3. And it must SAY they differ, rather than leaving the reader to notice.
assert(string.find(page, "Different builds win", 1, true),
  "the page must call out that the two answers disagree:\n" .. page)
print("3. the disagreement is stated, not implied")

-- 4. No "N% ahead" between builds measured on different mixes. That number was
--    the actual complaint: 761%, quoted with complete confidence, comparing
--    seven AoE fights against 249 mixed ones.
assert(not string.find(page, "Ahead of", 1, true),
  "a cross-mix gap claim must not survive:\n" .. page)
print("4. no cross-mix percentage claim")

-- 5. A build with only AoE fights must not imply a single-target answer.
PP.db.fights = {}
PP.db.buildLog = { ["k3"] = { name = "TrashOnly", id = "k3" } }
for _ = 1, 8 do fight("TrashOnly", 800000, 7) end
written = {}
PP.safeCall(BL.Refresh)
page = table.concat(written, "\n")
assert(string.find(page, "AoE", 1, true), "its AoE number must show:\n" .. page)
assert(not string.find(page, "Single target:", 1, true),
  "with no ST fights there is no ST winner to name:\n" .. page)
print("5. an unmeasured bucket stays silent")

-- 6. Two targets is neither bucket: usually a boss plus one add, and forcing it
--    into either just adds noise.
PP.db.fights = {}
PP.db.buildLog = { ["k4"] = { name = "Cleave2", id = "k4" } }
for _ = 1, 8 do fight("Cleave2", 500000, 2) end
written = {}
PP.safeCall(BL.Refresh)
page = table.concat(written, "\n")
assert(not string.find(page, "Single target:", 1, true)
   and not string.find(page, "AoE:", 1, true),
  "2-target fights must land in neither bucket:\n" .. page)
print("6. two targets counts as neither")

-- 7. WHICH ONE AM I RUNNING? The page ranked eight builds and left you to work
--    out which one you were standing in. It must say so, in WORDS -- colour
--    alone carries nothing here.
PP.db.fights = {}
PP.db.buildLog = { ["live"] = { name = "Cleaver", id = "live" },
                   ["other"] = { name = "Focus",  id = "other" } }
for _ = 1, 10 do fight("Cleaver", 100000, 1) end
for _ = 1, 10 do fight("Focus", 200000, 1) end
BL.CurrentKey = function() return "live", "Cleaver" end
written = {}
PP.safeCall(BL.Refresh)
page = table.concat(written, "\n")
assert(string.find(page, "RUNNING NOW", 1, true),
  "the live build must be marked:\n" .. page)
local mark = string.find(page, "RUNNING NOW", 1, true)
local before = string.sub(page, math.max(1, mark - 60), mark)
assert(string.find(before, "Cleaver", 1, true),
  "the marker must sit on the LIVE build, not another row:\n" .. before)
assert(select(2, string.gsub(page, "RUNNING NOW", "")) == 1,
  "exactly one row may be marked")
print("7. the running build is named, once, in words")

-- And when the run cannot be read, nothing is marked rather than guessing.
BL.CurrentKey = function() return nil, nil end
written = {}
PP.safeCall(BL.Refresh)
page = table.concat(written, "\n")
assert(not string.find(page, "RUNNING NOW", 1, true),
  "with no readable run, no row may claim to be live:\n" .. page)
print("8. unreadable run marks nothing")

print("\nST/AoE OK -- each bucket answered on its own evidence, no percentage")
print("claim spans two fight mixes, and the live build is named.")
