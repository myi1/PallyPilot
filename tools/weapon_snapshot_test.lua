-- MEASURE THE WEAPON AUTOMATICALLY, OR THE DATA IS WORTHLESS LATER.
--
-- ~94% of this character's damage is echo procs and ~3.6% is white swings, so
-- the weapon is a proc-delivery device and swing RATE is the variable that
-- matters. Testing that used to need a manual `/ep bench <tag>` before every
-- swap, which nobody keeps up. CombatMeter now records the weapons on every
-- fight, so tools/weapon_report.js can group the log with nothing typed.
--
-- The failure mode this guards is silence: if a WoW API is missing or renamed,
-- a pcall-wrapped snapshot happily records nothing and you discover the hole
-- weeks later with a log full of untagged fights. So: assert the fields are
-- really populated, and assert graceful degradation is PARTIAL, never a crash.
--
--   node tools/run_lua.js tools/weapon_snapshot_test.lua
PallyPilot = { print = function() end, safeCall = function(fn, ...) return fn(...) end }
EbonPilot = PallyPilot
local PP = PallyPilot
PP.db = { options = {}, fights = {} }
PP.CombatMeter = {}
local function Stub()
  local t = {}
  return setmetatable(t, { __index = function() return function() return t end end })
end
function CreateFrame() return Stub() end
UIParent = Stub()
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function GetTime() return 1000 end
function time() return 1750000000 end
function date() return "2026-09-04 01:00" end
function UnitLevel() return 80 end
function UnitClass() return "Paladin", "PALADIN" end
function GetRealZoneText() return "Icecrown Citadel" end
function UnitHealth() return 100000 end
function UnitHealthMax() return 100000 end
function UnitGUID() return "player-guid" end
-- The CLEU handler gates on COMBATLOG_OBJECT_AFFILIATION_MINE; a band of 0
-- makes it treat every event as somebody else's and bail.
bit = { band = function(a, b) return b end }

-- A dual-wield dagger setup, hasted.
local APIS = {
  UnitAttackSpeed  = function() return 1.3987, 1.4012 end,
  UnitDamage       = function() return 900, 1300, 700, 1100, 0, 0, 1 end,
  UnitAttackPower  = function() return 6000, 3483, 0 end,
  GetCritChance    = function() return 59.63 end,
  GetMeleeHaste    = function() return nil end,          -- nil on this client
  GetCombatRatingBonus = function(id) return id == 18 and 21.44 or 0 end,
  GetInventoryItemLink = function(_, slot)
    if slot == 16 then return "|cffa335ee|Hitem:50361::::::::80:::::|h[Paper Cutter]|h|r" end
    if slot == 17 then return "|cffa335ee|Hitem:50362::::::::80:::::|h[Havoc's Call]|h|r" end
    return nil
  end,
  GetItemInfo = function(link)
    if string.find(link, "50361", 1, true) then return "Librarian's Paper Cutter", link, 4, 277, 80, "Weapon", "Daggers" end
    return "Havoc's Call", link, 4, 264, 80, "Weapon", "One-Handed Maces"
  end,
}
for k, v in pairs(APIS) do _G[k] = v end

assert(loadfile("CombatMeter.lua"))()
local CM = PP.CombatMeter

-- The module does not export its frame, so drive SaveFight the way the game
-- does: through the OnEvent closure the module registered. Grab it off the
-- CreateFrame stub instead of reaching into the module.
local captured
do
  local realCreate = CreateFrame
  function CreateFrame()
    local f = Stub()
    function f:SetScript(k, fn) if k == "OnEvent" then captured = fn end return f end
    function f:RegisterEvent() return f end
    return f
  end
  PP.CombatMeter = {}
  assert(loadfile("CombatMeter.lua"))()
  CM = PP.CombatMeter
  assert(CM.Init, "CombatMeter.Init must exist")
  PP.safeCall(CM.Init)
  CreateFrame = realCreate
end
assert(captured, "the harness must capture CombatMeter's OnEvent handler")

captured(nil, "PLAYER_REGEN_DISABLED")
captured(nil, "COMBAT_LOG_EVENT_UNFILTERED", 0, "SWING_DAMAGE", "player-guid", "You",
  0x1, "boss-guid", "Boss", 0x0, 5000, 0, 0, 0, 0, 0, true)
-- A fight must last >=10s to be saved; GetTime is fixed, so move it.
GetTime = function() return 1120 end
captured(nil, "PLAYER_REGEN_ENABLED")

local f = PP.db.fights[#PP.db.fights]
assert(f, "the fight must have been saved")
local w = f.weap
assert(w, "every saved fight must carry a weapon snapshot")

print("main hand : " .. tostring(w.mh) .. "  [" .. tostring(w.mhType) .. "] ilvl " .. tostring(w.mhIlvl))
print("off hand  : " .. tostring(w.oh) .. "  [" .. tostring(w.ohType) .. "] ilvl " .. tostring(w.ohIlvl))
print("speeds    : " .. tostring(w.mhSpeed) .. " / " .. tostring(w.ohSpeed))
print("stats     : crit " .. tostring(w.crit) .. "%  haste " .. tostring(w.haste)
  .. "%  AP " .. tostring(w.ap))

-- 1. Identity: without the NAME the grouping in weapon_report.js has no key.
assert(w.mh == "Librarian's Paper Cutter", "main-hand name wrong: " .. tostring(w.mh))
assert(w.oh == "Havoc's Call", "off-hand name wrong: " .. tostring(w.oh))
assert(w.mhType == "Daggers", "weapon subtype must be recorded for grouping")
assert(w.mhIlvl == 277, "ilvl must be recorded, got " .. tostring(w.mhIlvl))

-- 2. Speed is THE measurement. UnitAttackSpeed reports the HASTED timer, which
--    is what sets proc rate -- not the tooltip's base speed.
assert(w.mhSpeed == 1.4, "main-hand speed must round to 1.4, got " .. tostring(w.mhSpeed))
assert(w.ohSpeed == 1.4, "off-hand speed must be recorded, got " .. tostring(w.ohSpeed))

-- 3. Confounders. A weapon comparison is worthless if a gear swap moved crit or
--    haste at the same time and nothing recorded it.
assert(w.crit == 59.6, "crit must be recorded to 1dp, got " .. tostring(w.crit))
assert(w.haste == 21.4,
  "haste must fall back to the combat rating (GetMeleeHaste is nil here), got "
  .. tostring(w.haste))
assert(w.ap == 9483, "attack power must be recorded, got " .. tostring(w.ap))
print("\n1. weapons, speeds and confounding stats all captured")

-- 4. GRACEFUL DEGRADATION. A missing API must cost that one field, not the
--    whole snapshot and certainly not the fight.
GetInventoryItemLink = function() return nil end
UnitAttackSpeed = nil
GetTime = function() return 2000 end
captured(nil, "PLAYER_REGEN_DISABLED")
captured(nil, "COMBAT_LOG_EVENT_UNFILTERED", 0, "SWING_DAMAGE", "player-guid", "You",
  0x1, "boss-guid", "Boss", 0x0, 5000, 0, 0, 0, 0, 0, true)
GetTime = function() return 2120 end
captured(nil, "PLAYER_REGEN_ENABLED")
local f2 = PP.db.fights[#PP.db.fights]
assert(f2 and f2 ~= f, "the fight must still save with the weapon APIs gone")
assert(f2.weap, "a partial snapshot must still be recorded, not dropped whole")
assert(f2.weap.mh == nil, "the unavailable field is simply absent")
assert(f2.weap.crit == 59.6, "the fields that DO work must still be captured")
print("2. a missing API costs one field, not the snapshot and not the fight")

-- 5. Cost. This runs once per fight, never per combat-log event -- the whole
--    point of putting it in SaveFight rather than the CLEU handler.
local calls = 0
UnitAttackSpeed = function() calls = calls + 1; return 1.4, 1.4 end
GetTime = function() return 3000 end
captured(nil, "PLAYER_REGEN_DISABLED")
for i = 1, 200 do
  captured(nil, "COMBAT_LOG_EVENT_UNFILTERED", 0, "SWING_DAMAGE", "player-guid", "You",
    0x1, "boss-guid", "Boss", 0x0, 100, 0, 0, 0, 0, 0, true)
end
GetTime = function() return 3120 end
captured(nil, "PLAYER_REGEN_ENABLED")
print("3. 200 combat-log events -> " .. calls .. " weapon read(s)")
assert(calls == 1,
  "the snapshot must run ONCE per fight, not per event -- got " .. calls)

print("\nWEAPON SNAPSHOT OK -- automatic, degrades in pieces, and off the hot path.")
