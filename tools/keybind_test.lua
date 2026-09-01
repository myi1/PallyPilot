-- Shadowform keybinds. Third attempt at this bug, so it gets a test.
--
-- The failure: in a form, main-bar buttons 1-12 stop showing slots 1-12 and
-- show a BONUS BAR instead. The old lookup scanned slots 1..120 and took the
-- first match, so a spell that also sits on the main bar reported the main-bar
-- key while the player was actually looking at the Shadowform page.
--
-- The rule now: whatever the on-screen button DISPLAYS as its hotkey is the
-- answer, because that is literally the key the player presses.
--
--   node tools/run_lua.js tools/keybind_test.lua
PallyPilot = { print = function() end,
               safeCall = function(fn, ...) return fn(...) end }
EbonPilot = PallyPilot
local PP = PallyPilot
PP.db = { options = { rotationHelper = false }, scans = {} }
PP.Classes = {}

-- ---- fake action bars -----------------------------------------------------
-- Slot 4   : Mind Blast on the MAIN bar,       bound to "4"
-- Slot 76  : Mind Blast on the SHADOWFORM bar, shown on button 4, bound "SHIFT-4"
local SLOT = {}
SLOT[4]  = { atype = "spell", id = 100, tex = "TEX_MINDBLAST" }
SLOT[76] = { atype = "spell", id = 100, tex = "TEX_MINDBLAST" }
SLOT[30] = { atype = "spell", id = 200, tex = "TEX_SWP" }

local shapeshift, bonusOffset, barPage = 0, 0, 1

function GetShapeshiftForm() return shapeshift end
function GetBonusBarOffset() return bonusOffset end
function GetActionBarPage() return barPage end
function HasAction(s) return SLOT[s] ~= nil end
function GetActionTexture(s) return SLOT[s] and SLOT[s].tex end
function GetActionInfo(s)
  local e = SLOT[s]; if not e then return nil end
  return e.atype, e.id
end
function GetSpellInfo(id)
  if id == 100 then return "Mind Blast" end
  if id == 200 then return "Shadow Word: Pain" end
end
function GetSpellTexture(n)
  if n == "Mind Blast" then return "TEX_MINDBLAST" end
  if n == "Shadow Word: Pain" then return "TEX_SWP" end
end
function GetMacroInfo() return nil end
function GetBindingKey(cmd)
  if cmd == "ACTIONBUTTON4" then return "4" end
  if cmd == "MULTIACTIONBAR3BUTTON6" then return "CTRL-6" end
end
RANGE_INDICATOR = "*"

-- On-screen buttons. ActionButton4 shows whatever slot is currently paged in,
-- and its HotKey text reflects the real binding under a form.
local buttons = {}
local function MakeBtn(name, slotFn, hotkey, visible)
  local hk = { text = hotkey }
  function hk:GetText() return self.text end
  _G[name .. "HotKey"] = hk
  local b = {}
  function b:IsVisible() return visible ~= false end
  function b:GetAttribute(a) if a == "action" then return slotFn() end end
  _G[name] = b
  buttons[name] = { hk = hk, b = b }
  return b
end
for i = 1, 12 do
  local idx = i
  MakeBtn("ActionButton" .. idx, function()
    if bonusOffset > 0 then return 72 + (bonusOffset - 1) * 12 + idx end
    return (barPage - 1) * 12 + idx
  end, nil)
end
-- Give button 4 a hotkey that CHANGES with form, the way the real UI does.
local function SyncBtn4Hotkey()
  buttons["ActionButton4"].hk.text = (bonusOffset > 0) and "s-4" or "4"
end
SyncBtn4Hotkey()

-- Minimal frame/UI surface so the file loads.
local function Stub()
  local t = {}
  local mt = { __index = function() return function() return t end end }
  return setmetatable(t, mt)
end
function CreateFrame() return Stub() end
function UnitExists() return false end
function UnitCanAttack() return false end
function UnitDebuff() return nil end
function UnitBuff() return nil end
function UnitHealth() return 0 end
function UnitHealthMax() return 0 end
function UnitPower() return 0 end
function UnitPowerMax() return 0 end
function GetTime() return 0 end
function GetSpellCooldown() return 0, 0 end
function IsUsableSpell() return true end
function UnitClass() return "Priest", "PRIEST" end
function date() return "2026-09-01 06:00" end
UIParent = Stub()

assert(loadfile("RotationHelper.lua"))()
local RH = PP.RotationHelper
assert(RH and RH.KeyScan, "RotationHelper must load")

-- KeybindFor is local; reach it through the diagnostic, which prints HUDkey.
local function hudKeyFor(spell)
  local lines = {}
  RH.KeyScanOne(spell, function(s) lines[#lines + 1] = s end)
  for _, l in ipairs(lines) do
    local k = string.match(l, "HUDkey=(%S+)")
    if k then return k end
  end
end

-- 1. Out of form: button 4 shows slot 4, bound "4".
bonusOffset, shapeshift, barPage = 0, 0, 1
SyncBtn4Hotkey()
local outOfForm = hudKeyFor("Mind Blast")
print("no form   -> " .. tostring(outOfForm))
assert(outOfForm == "4", "expected 4 out of form, got " .. tostring(outOfForm))

-- 2. IN SHADOWFORM: button 4 now shows slot 76 and reads "s-4". The old code
--    returned "4" here -- the whole bug.
bonusOffset, shapeshift = 1, 1
SyncBtn4Hotkey()
local inForm = hudKeyFor("Mind Blast")
print("shadowform-> " .. tostring(inForm))
assert(inForm == "s-4",
  "SHADOWFORM REGRESSION: expected s-4, got " .. tostring(inForm))

-- 3. The scan must record the live button -> slot mapping, since that is the
--    evidence needed to debug this without the player pasting anything.
RH.KeyScan("Mind Blast")
local dump = table.concat(PP.db.scans.keyscan or {}, "\n")
assert(string.find(dump, "bonusOffset=1", 1, true), "scan must record the form state")
assert(string.find(dump, "BTN4", 1, true), "scan must record button->slot mapping")
assert(string.find(dump, "slot 76", 1, true),
  "scan must show button 4 pointing at the shadowform slot")

print("\nKEYBIND OK -- on-screen hotkey wins, shadowform page resolved.")
