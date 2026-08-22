-- PallyPilot RotationHelper: a HUD that suggests your next ability (with its
-- keybind) from the Ret priority, watching cooldowns, procs, seal and target HP.
local PP = PallyPilot
local RH = {}
PP.RotationHelper = RH

local SEAL = "Seal of Vengeance"   -- Alliance; Horde clients use Seal of Corruption
local SEAL_ALT = "Seal of Corruption"
local AOW = "The Art of War"

-- Single-target priority (highest first). cond() gates situational casts.
local PRIORITY = {
  { spell = "Judgement of Light" },
  { spell = "Crusader Strike" },
  { spell = "Divine Storm" },
  { spell = "Hammer of Wrath", cond = function() return RH.TargetPct() <= 20 end },
  { spell = "Exorcism", cond = function() return RH.HasBuff(AOW) end },
  { spell = "Holy Wrath" },
  { spell = "Consecration" },
}

local frame, icon, nameFS, keyFS

function RH.HasBuff(name)
  for i = 1, 40 do
    local b = UnitBuff("player", i)
    if not b then return false end
    if b == name then return true end
  end
  return false
end

function RH.TargetPct()
  if not UnitExists("target") or UnitIsDead("target") then return 100 end
  local max = UnitHealthMax("target")
  if not max or max == 0 then return 100 end
  return (UnitHealth("target") / max) * 100
end

local function OffCooldown(spell)
  local start, dur = GetSpellCooldown(spell)
  if not start then return false end
  if start == 0 then return true end
  if dur and dur <= 1.5 then return true end          -- just the GCD
  return (start + dur - GetTime()) <= 0.3
end

local function Ready(spell)
  local usable = IsUsableSpell(spell)                  -- false if unknown / no mana
  if not usable then return false end
  return OffCooldown(spell)
end

-- Which seal name exists on this client (faction differs).
local function ActiveSealName()
  if GetSpellInfo(SEAL) then return SEAL end
  if GetSpellInfo(SEAL_ALT) then return SEAL_ALT end
  return SEAL
end

local function Suggest()
  local seal = ActiveSealName()
  if not (RH.HasBuff(seal) or RH.HasBuff(SEAL) or RH.HasBuff(SEAL_ALT)) and Ready(seal) then
    return seal
  end
  for _, e in ipairs(PRIORITY) do
    if (not e.cond or e.cond()) and Ready(e.spell) then return e.spell end
  end
  return nil
end

-- Map each action slot (1-120) to its keybinding command name (default UI).
local SLOT_BIND = {}
do
  local function set(base, from) for i = 1, 12 do SLOT_BIND[from + i - 1] = base .. i end end
  set("ACTIONBUTTON", 1)              -- main bar (keys 1-=)
  set("MULTIACTIONBAR3BUTTON", 25)    -- Right bar
  set("MULTIACTIONBAR4BUTTON", 37)    -- Left bar
  set("MULTIACTIONBAR2BUTTON", 49)    -- Bottom Right bar
  set("MULTIACTIONBAR1BUTTON", 61)    -- Bottom Left bar
end

local function AbbrevKey(k)
  if not k then return nil end
  k = k:gsub("SHIFT%-", "s-"):gsub("CTRL%-", "c-"):gsub("ALT%-", "a-")
  k = k:gsub("BUTTON", "m"):gsub("NUMPAD", "n")
  return k
end

-- Custom-bar fallback frames (Bartender/Dominos reuse these names).
local BARS = {
  "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
  "MultiBarRightButton", "MultiBarLeftButton", "BT4Button", "DominosActionButton",
}

-- Find the keybind for the action slot holding `spell`.
local function KeybindFor(spell)
  for slot = 1, 120 do
    local atype, id = GetActionInfo(slot)
    if atype == "spell" and id and GetSpellInfo(id) == spell then
      local bind = SLOT_BIND[slot]
      if bind then
        local key = GetBindingKey(bind)
        if key then return AbbrevKey(key) end
      end
    end
  end
  -- Fallback: read the displayed HotKey off a named button (custom bar addons).
  for _, prefix in ipairs(BARS) do
    for i = 1, 12 do
      local btn = _G[prefix .. i]
      local slot = btn and (btn.action or (btn.GetAttribute and btn:GetAttribute("action")))
      if slot then
        local atype, id = GetActionInfo(slot)
        if atype == "spell" and id and GetSpellInfo(id) == spell then
          local hk = _G[prefix .. i .. "HotKey"]
          local txt = hk and hk:GetText()
          if txt and txt ~= "" and txt ~= RANGE_INDICATOR then return AbbrevKey(txt) end
        end
      end
    end
  end
  return nil
end

local function OnUpdate(self, elapsed)
  self.t = (self.t or 0) + elapsed
  if self.t < 0.15 then return end
  self.t = 0
  if not (PP.db and PP.db.options.rotationHelper) then frame:Hide() return end
  local spell = Suggest()
  if not spell then
    icon:SetTexture(nil)
    nameFS:SetText("|cffb4a586…|r")
    keyFS:SetText("")
    return
  end
  icon:SetTexture(GetSpellTexture(spell))
  nameFS:SetText(spell)
  local key = KeybindFor(spell)
  keyFS:SetText(key and ("|cffe0b352" .. key .. "|r") or "|cff8a7c63no bind|r")
end

function RH.Init()
  if frame then return end
  frame = CreateFrame("Frame", "PallyPilotRotation", UIParent)
  frame:SetWidth(190); frame:SetHeight(64)
  frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(s) s:StartMoving() end)
  frame:SetScript("OnDragStop", function(s)
    s:StopMovingOrSizing()
    local _, _, _, x, y = s:GetPoint()
    PP.db.options.rotPos = { x = x, y = y }
  end)
  frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 } })
  frame:SetBackdropColor(0, 0, 0, 0.8)
  local pos = PP.db.options.rotPos
  if pos then frame:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)
  else frame:SetPoint("CENTER", UIParent, "CENTER", 0, -140) end

  icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetWidth(44); icon:SetHeight(44)
  icon:SetPoint("LEFT", frame, "LEFT", 10, 0)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  nameFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  nameFS:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -4)
  nameFS:SetWidth(120); nameFS:SetJustifyH("LEFT")

  keyFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  keyFS:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 4)

  frame:SetScript("OnUpdate", OnUpdate)
  if select(2, UnitClass("player")) ~= "PALADIN" then
    PP.db.options.rotationHelper = false
  end
  if PP.db.options.rotationHelper then frame:Show() else frame:Hide() end
end

function RH.Toggle()
  if not frame then RH.Init() end
  PP.db.options.rotationHelper = not PP.db.options.rotationHelper
  if PP.db.options.rotationHelper then frame:Show() else frame:Hide() end
  PP.print("Rotation helper " .. (PP.db.options.rotationHelper and "ON" or "OFF"))
end
