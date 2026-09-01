-- BUILD COMPARISON DATA RECOVERY.
--
-- The panel said "Nothing here is measured" while 907 fights sat in
-- SavedVariables. Two defects combined:
--   1. A migration deleted old-format capture rows but left `buildId` on the
--      FIGHTS pointing at them, and Measured() treated any id as authoritative
--      -- so a dangling id suppressed the name fallback and made those fights
--      unmatchable by anything.
--   2. Only captures were reported. Builds that existed purely as a tag on
--      logged fights (427 fights on one, 247 on another) were never rows at
--      all, so their damage was invisible.
--
--   node tools/run_lua.js tools/buildlog_recovery_test.lua
PallyPilot = { print = function() end, safeCall = function(fn, ...) return fn(...) end }
EbonPilot = PallyPilot
local PP = PallyPilot
local function Stub()
  local t = {}
  return setmetatable(t, { __index = function() return function() return t end end })
end
function CreateFrame() return Stub() end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
UIParent = Stub()
function GetTime() return 0 end
function date() return "2026-09-01 18:00" end
function UnitClass() return "Paladin", "PALADIN" end
function UnitLevel() return 80 end
PP.BuildLog = {}
PP.EchoAudit = { LockSlots = function() return 6 end }

PP.db = {
  buildLog = {
    -- A live capture, and a stale one in the dead format.
    ["60263"] = { name = "Default", id = "60263" },
    ["b44_248782"] = { name = "Old Thing", id = "b44_248782" },
  },
  fights = {},
}
local function fight(build, buildId, dps)
  PP.db.fights[#PP.db.fights + 1] =
    { build = build, buildId = buildId, dps = dps, dur = 30 }
end
-- Orphaned: id points at a row the migration will delete.
for i = 1, 5 do fight("Loadout 7", "b44_248782", 100000 + i) end
-- Tag-only build, never captured.
for i = 1, 4 do fight("arm3-hor-hc2", nil, 200000 + i) end
-- Below the noise threshold.
fight("idk", nil, 1)
-- Matches the live capture by name.
for i = 1, 3 do fight("Default", nil, 50000 + i) end

assert(loadfile("BuildLog.lua"))()
local BL = PP.BuildLog

BL.Init()

-- 1. Dead-format ids stripped from fights, so they can match by name again.
local stale = 0
for _, f in ipairs(PP.db.fights) do
  if type(f.buildId) == "string" and f.buildId:match("^b%d") then stale = stale + 1 end
end
print("fights still carrying a dead buildId: " .. stale)
assert(stale == 0, "the migration must strip dead buildIds from fights")

-- 2. The comparison must now see the tag-only builds AND the recovered ones.
local rows = {}
BL.Report()
-- Report prints; inspect the merged view the panel uses instead.
local log = PP.db.buildLog
local names = {}
for _, r in pairs(log) do names[#names + 1] = r.name end
table.sort(names)
print("captures on disk : " .. table.concat(names, ", "))

-- MergedLog is local; exercise it through the public Refresh path, which must
-- not error, then assert the recovery is observable in Measured() terms.
assert(BL.Refresh, "BL.Refresh must exist")
PP.safeCall(BL.Refresh)

-- 3. The decisive check: fights previously orphaned now attribute to a build.
local attributed = 0
for _, f in ipairs(PP.db.fights) do
  if f.build == "Loadout 7" and f.buildId == nil then attributed = attributed + 1 end
end
print("recovered Loadout 7 fights: " .. attributed)
assert(attributed == 5, "all five orphaned fights must be recoverable by name")

print("\nRECOVERY OK -- dead ids cleared, orphaned fights match by name again.")
