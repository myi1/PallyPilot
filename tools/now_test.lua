-- /ep now is the front door: ONE action, at most three lines, for every state.
-- If it ever grows into another wall of text or forgets a state, this fails.
--
--   node tools/run_lua.js tools/now_test.lua
PallyPilot = { print = function(s) LINES[#LINES + 1] = s end,
               safeCall = function(fn, ...) return fn(...) end }
EbonPilot = PallyPilot
local PP = PallyPilot
LINES = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, s) LINES[#LINES + 1] = s end }

local level = 80
function UnitLevel() return level end
function GetTime() return 0 end
local function Stub()
  local t = {}
  return setmetatable(t, { __index = function() return function() return t end end })
end
function CreateFrame() return Stub() end
UIParent = Stub()

PP.Build = { locked = {}, ChaseList = function() return { "Alpha" } end,
             ChaseReason = function() return "because" end,
             IsKeep = function() return true end }
PP.EchoAudit = { LockSlots = function() return 6 end, RunQualityTargets = function() return {} end }
PP.EchoFlow = { RunJunkList = function() return { "junk1", "junk2" } end }

assert(loadfile("BisPlan.lua"))()
local BP = PP.BisPlan
assert(BP.Now, "BP.Now must exist")

-- Drive Now() by stubbing Status, so every branch is reachable without a
-- full fake catalog.
local function run(status, why, lvl)
  LINES = {}
  level = lvl or 80
  BP.Status = function() return status, why end
  BP.Now()
  return LINES
end
local function counts(t)
  local c = { LOCKED = 0, EPIC = 0, FISH = 0, INRUN = 0, ROLL = 0, OFF = 0, FARM = 0 }
  for k, v in pairs(t or {}) do c[k] = v end
  return { counts = c, total = 1, done = 0 }
end

-- Corrected model: an orb reroll consumes an echo YOU pick, so a missing echo
-- always has an answer -- "roll, and here is your weakest" -- and FARM is no
-- longer a separate dead end from ROLL.
PP.EchoAudit.FodderRank = function()
  return { { name = "Heavy Incantations", tier = "C", q = 3 },
           { name = "Conjured Flame", tier = "B", q = 1 } }
end

local cases = {
  { "closed",     nil,                  "closed", 80, "Echoes window" },
  { "nohub",      nil,                  "nohub",  80, "EbonholdHub"   },
  { "level 1",    counts{},             nil,       1, "ONLY moment"   },
  { "roll",       counts{ ROLL = 3 },   nil,      80, "Heavy Incantations" },
  { "farm",       counts{ FARM = 4 },   nil,      80, "Roll for the 4" },
  { "fish",       counts{ FISH = 2 },   nil,      80, "Quality%-fish"  },
  { "off",        counts{ OFF = 1 },    nil,      80, "switched off"  },
  { "complete",   counts{},             nil,      80, "complete"      },
}

for _, c in ipairs(cases) do
  local out = run(c[2], c[3], c[4])
  local joined = table.concat(out, " | ")
  print(("%-12s %d line(s)"):format(c[1], #out))
  assert(#out >= 1, c[1] .. ": must say something")
  assert(#out <= 3, c[1] .. ": /ep now must stay under 3 lines, got " .. #out)
  assert(string.find(joined, c[5]), c[1] .. ": expected /" .. c[5] .. "/ in: " .. joined)
end

-- Level 1 outranks everything: the toggle window is the only irreversible one.
local out = run(counts{ ROLL = 5, FISH = 5, FARM = 5 }, nil, 1)
assert(string.find(table.concat(out, " "), "ONLY moment"),
  "at level 1 the pool window must outrank chasing and fishing")

-- "OUT OF FODDER" MUST NEVER BE SAID. You choose the sacrifice, so having no
-- rated junk just means the weakest echo is a decent one -- not that rolling
-- is blocked. This is the assertion that keeps the old wrong model out.
PP.EchoFlow.RunJunkList = function() return {} end
out = run(counts{ ROLL = 2 }, nil, 80)
local j2 = table.concat(out, " ")
assert(not string.find(j2, "fodder left"), "must never claim fodder ran out: " .. j2)
assert(not string.find(j2, "[Nn]othing to do"), "must never dead-end: " .. j2)
assert(string.find(j2, "Heavy Incantations"),
  "must name the weakest echo to feed: " .. j2)

-- With no ranking available it still has to give an instruction, not a shrug.
PP.EchoAudit.FodderRank = function() return {} end
out = run(counts{ ROLL = 2 }, nil, 80)
assert(string.find(table.concat(out, " "), "weakest"),
  "without a ranking it must still say to feed your weakest echo")

print("\nNOW OK -- one action per state, never more than three lines.")

-- Levelling (2-79): EBH's automation does the picking and banishing, so the
-- only correct instruction is "stay synced" -- never "banish these".
PP.EchoFlow.RunJunkList = function() return { "j" } end
out = run(counts{ ROLL = 3, FISH = 2 }, nil, 42)
local j = table.concat(out, " ")
assert(string.find(j, "EBH is auto%-picking"), "levelling must defer to EBH: " .. j)
assert(not string.find(j, "[Bb]anish"), "must never tell the player to banish: " .. j)
assert(#out <= 3, "still at most three lines")
print("levelling    " .. #out .. " line(s) -- defers to EBH")

-- A curated pool produces ZERO rated junk. Under the corrected model that is
-- NOT a blocker: you pick the fodder, so the weakest echo is simply a better
-- one than usual. Rolling must still be the advice.
PP.EchoFlow.RunJunkList = function() return {} end
PP.EchoAudit.FodderRank = function()
  return { { name = "Widow's Venom", tier = "A", q = 1 } }
end
PP.EchoAudit.RunQualityTargets = function() return {} end
out = run(counts{ ROLL = 4, FISH = 0 }, nil, 80)
j = table.concat(out, " ")
assert(string.find(j, "Roll for the 4"), "must still say to roll: " .. j)
assert(string.find(j, "Widow"), "must name the weakest echo: " .. j)
assert(not string.find(j, "[Nn]othing to do"), "must never dead-end: " .. j)
print("no junk      " .. #out .. " line(s) -- still rolls, names the fodder")
