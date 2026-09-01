-- PallyPilot RotationHelper: a HUD that suggests your next ability (with its
-- keybind) from the Ret priority, watching cooldowns, procs, seal and target HP.
local PP = PallyPilot
local RH = {}
PP.RotationHelper = RH

local SEAL = "Seal of Vengeance"   -- Alliance; Horde clients use Seal of Corruption
local SEAL_ALT = "Seal of Corruption"

-- The paladin single-target priority now lives in BuildData (B.rotationPriority)
-- and is read via RH.ActivePriority() like every class -- no baked class list here.

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

-- Class-aware: a class's guide data can supply its own shot/spell priority
-- (B.rotationPriority) and its "always keep this up" buff (B.rotationUpkeep --
-- the paladin's Seal, a hunter's Aspect). The baked Ret list stays the paladin
-- fallback; a class with neither gets no HUD.
function RH.ActivePriority()
  local B = PP.Build
  return (B and B.rotationPriority) or nil
end

local function UpkeepNames()
  local B = PP.Build
  if B and B.rotationUpkeep then return B.rotationUpkeep end
  if (PP.class or select(2, UnitClass("player"))) == "PALADIN" then
    return { ActiveSealName(), SEAL, SEAL_ALT }
  end
  return nil
end

local function Suggest()
  local prio = RH.ActivePriority()
  if not prio then return nil end
  local upkeep = UpkeepNames()
  if upkeep then
    local have, castable = false, nil
    for _, n in ipairs(upkeep) do
      if RH.HasBuff(n) then have = true; break end
      if not castable and GetSpellInfo(n) and Ready(n) then castable = n end
    end
    if not have and castable then return castable end
  end
  for _, e in ipairs(prio) do
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

-- Does action `slot` hold `spell`? Match by icon texture (robust to id quirks
-- and macros), then by GetActionInfo name as a secondary.
local function SlotHasSpell(slot, spell, wantTex)
  if wantTex and GetActionTexture(slot) == wantTex then return true end
  local atype, id = GetActionInfo(slot)
  if atype == "spell" and id and GetSpellInfo(id) == spell then return true end
  -- Macro on the bar (e.g. a Shadowform macro): match by its body text, so a
  -- "/cast Vampiric Touch" macro with a custom icon still resolves.
  if atype == "macro" and id and GetMacroInfo then
    local _, _, body = GetMacroInfo(id)
    if body and spell and string.find(body, spell, 1, true) then return true end
  end
  return false
end

-- Which action slot is physically displayed on main-bar button `i` RIGHT NOW?
--
-- Buttons 1-12 do not show slots 1-12 unconditionally. A stance/form pushes a
-- bonus bar in front of them (Shadowform is one), and paging shifts them too.
-- Getting this wrong is what made the HUD report a main-bar key for a spell
-- that is actually sitting on the Shadowform page.
local function CurrentSlotForButton(i)
  local offset = GetBonusBarOffset and GetBonusBarOffset() or 0
  if offset and offset > 0 then
    return 72 + (offset - 1) * 12 + i        -- bonus/stance bar in front
  end
  local page = (GetActionBarPage and GetActionBarPage()) or 1
  return (page - 1) * 12 + i
end

-- Find the keybind for the action slot holding `spell`.
--
-- ORDER MATTERS, and it used to be wrong. The old version scanned slots 1..120
-- and took the FIRST match, so a spell that also sits on the main bar reported
-- the main-bar key even while a form had swapped the buttons to another page.
-- What the player actually presses is whatever the on-screen button says, so
-- read THAT first and treat the slot maths as a fallback.
local function KeybindFor(spell)
  local wantTex = GetSpellTexture(spell)

  -- 1. Ground truth: an on-screen button currently holding this spell. Its
  --    displayed HotKey is, by definition, the key that casts it -- including
  --    modifier bindings ("s-4") and any custom bar addon.
  for _, prefix in ipairs(BARS) do
    for i = 1, 12 do
      local btn = _G[prefix .. i]
      if btn and btn.IsVisible and btn:IsVisible() then
        local slot = btn.action or (btn.GetAttribute and btn:GetAttribute("action"))
        if slot and SlotHasSpell(slot, spell, wantTex) then
          local hk = _G[prefix .. i .. "HotKey"]
          local txt = hk and hk.GetText and hk:GetText()
          if txt and txt ~= "" and txt ~= RANGE_INDICATOR then
            return AbbrevKey(txt)
          end
        end
      end
    end
  end

  -- 2. The page/bonus-bar the main buttons are showing right now.
  for i = 1, 12 do
    local slot = CurrentSlotForButton(i)
    if slot and HasAction(slot) and SlotHasSpell(slot, spell, wantTex) then
      local key = GetBindingKey("ACTIONBUTTON" .. i)
      if key then return AbbrevKey(key) end
    end
  end

  -- 3. Static slot -> binding map for the always-visible side bars.
  for slot = 1, 120 do
    if HasAction(slot) and SlotHasSpell(slot, spell, wantTex) then
      local bind = SLOT_BIND[slot]
      -- Bonus/stance bars (73-120) and main-bar pages 2+ (13-24) display on the
      -- main ActionButton1-12, so their bind IS "ACTIONBUTTON<n>" -- but SLOT_BIND
      -- only maps 1-72. Derive the physical button from the slot. This is the
      -- Shadowform bar: a priest's shadow spells sit at 73+ (measured: Vampiric
      -- Touch at slot 74 -> button 2 -> the "2" key), where the lookup returned nil.
      if not bind and (slot > 72 or (slot >= 13 and slot <= 24)) then
        bind = "ACTIONBUTTON" .. (((slot - 1) % 12) + 1)
      end
      if bind then
        local key = GetBindingKey(bind)
        if key then return AbbrevKey(key) end
      end
      -- slot found but unmapped (custom bar) -> try its button HotKey below
      break
    end
  end
  -- Fallback: read the displayed HotKey off a named button (custom bar addons).
  for _, prefix in ipairs(BARS) do
    for i = 1, 12 do
      local btn = _G[prefix .. i]
      local slot = btn and (btn.action or (btn.GetAttribute and btn:GetAttribute("action")))
      if slot and SlotHasSpell(slot, spell, wantTex) then
        local hk = _G[prefix .. i .. "HotKey"]
        local txt = hk and hk:GetText()
        if txt and txt ~= "" and txt ~= RANGE_INDICATOR then return AbbrevKey(txt) end
      end
    end
  end
  return nil
end

-- Diagnostic: /pp keyscan [spell] — dump where a spell sits on the bars and why
-- the bind lookup does (or doesn't) resolve. Defaults to the HUD's current
-- suggestion, else this class's top rotation spell. Prints BOTH the SLOT_BIND
-- path AND the on-screen button's live HotKey text, so a Shadowform / stance /
-- paged bar (slots outside SLOT_BIND's 1-72 range) is visible.
-- With no argument it now dumps the WHOLE rotation, because a keybind bug is
-- rarely about one spell -- and a second round trip to scan the next one is a
-- second /reload. Output goes to SavedVariables only; chat gets one line.
function RH.KeyScan(spellArg)
  local B = PP.Build
  local list = {}
  if spellArg and spellArg ~= "" then
    list[1] = spellArg
  else
    local seen = {}
    local function push(s)
      if s and s ~= "" and not seen[s] then seen[s] = true; list[#list + 1] = s end
    end
    push(Suggest())
    for _, e in ipairs((B and B.rotationPriority) or {}) do push(e.spell) end
  end
  if #list == 0 then
    PP.print("Keyscan: nothing to scan. Usage: |cffe0b352/pp keyscan <exact spell name>|r.")
    return
  end
  local out = {}
  -- Accumulate, never print: the whole point is that it lands on disk.
  local function add(s) out[#out + 1] = s end
  add(("keyscan  form=%s barPage=%s bonusOffset=%s  spells=%d"):format(
    tostring(GetShapeshiftForm and GetShapeshiftForm()),
    tostring(GetActionBarPage and GetActionBarPage()),
    tostring(GetBonusBarOffset and GetBonusBarOffset()), #list))
  -- What each physical main-bar button is actually showing right now. This is
  -- the mapping the old code got wrong under Shadowform.
  for i = 1, 12 do
    local slot = CurrentSlotForButton(i)
    local atype, id = GetActionInfo(slot)
    -- Capture into locals first: these APIs can return NOTHING rather than
    -- nil, and tostring() with no argument is an error, not "nil".
    local nm
    if atype == "spell" and id then nm = GetSpellInfo(id) end
    local bind = GetBindingKey("ACTIONBUTTON" .. i)
    add(("  BTN%-2d -> slot %-3d %-7s %-24s bind=%s"):format(i, slot,
      tostring(atype), tostring(nm), tostring(bind)))
  end
  for _, spell in ipairs(list) do RH.KeyScanOne(spell, add) end
  PP.db = PP.db or {}; PP.db.scans = PP.db.scans or {}
  PP.db.scans.keyscan = out
  PP.db.scans.keyscanTime = date("%Y-%m-%d %H:%M")
  PP.print(("Keyscan saved (%d spells, %d lines). |cffe0b352/reload|r and it's on disk.")
    :format(#list, #out))
end

function RH.KeyScanOne(spell, add)
  local wantTex = GetSpellTexture(spell)
  if not wantTex then
    add("Keyscan '" .. tostring(spell) .. "': not a known spell")
    return
  end
  add("Keyscan '" .. spell .. "' tex=" .. tostring(wantTex)
    .. " form=" .. tostring(GetShapeshiftForm and GetShapeshiftForm())
    .. " barPage=" .. tostring(GetActionBarPage and GetActionBarPage())
    .. " bonusOffset=" .. tostring(GetBonusBarOffset and GetBonusBarOffset())
    .. " HUDkey=" .. tostring(KeybindFor(spell)))
  local hits = 0
  for slot = 1, 120 do
    if HasAction(slot) then
      local tex = GetActionTexture(slot)
      local match = SlotHasSpell(slot, spell, wantTex)
      if match or tex == wantTex then      -- show near-matches too, for diagnosis
        hits = hits + 1
        local atype, id = GetActionInfo(slot)
        local hk
        for _, prefix in ipairs(BARS) do
          for i = 1, 12 do
            local btn = _G[prefix .. i]
            local bslot = btn and (btn.action or (btn.GetAttribute and btn:GetAttribute("action")))
            if bslot == slot then
              local fs = _G[prefix .. i .. "HotKey"]
              local txt = fs and fs:GetText()
              if txt and txt ~= "" and txt ~= RANGE_INDICATOR then
                hk = prefix .. i .. "='" .. txt .. "'"; break
              end
            end
          end
          if hk then break end
        end
        add("  slot " .. slot .. " type=" .. tostring(atype) .. " id=" .. tostring(id)
          .. " match=" .. tostring(match) .. " SLOT_BIND=" .. tostring(SLOT_BIND[slot])
          .. " GetBindingKey=" .. tostring(SLOT_BIND[slot] and GetBindingKey(SLOT_BIND[slot]))
          .. " btnHotKey=" .. tostring(hk))
      end
    end
  end
  -- Bar-type-agnostic pass: any on-screen button whose icon is this spell.
  for _, prefix in ipairs(BARS) do
    for i = 1, 12 do
      local btn = _G[prefix .. i]
      local bslot = btn and (btn.action or (btn.GetAttribute and btn:GetAttribute("action")))
      if bslot and GetActionTexture(bslot) == wantTex then
        local fs = _G[prefix .. i .. "HotKey"]
        add("  BTN " .. prefix .. i .. " action=" .. tostring(bslot)
          .. " HotKey='" .. tostring(fs and fs:GetText()) .. "'")
      end
    end
  end
  if hits == 0 then add("  '" .. spell .. "' not found on slots 1-120 (icon or macro).") end
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
  -- No HUD for a class whose guide has no rotation priority yet.
  if not RH.ActivePriority() then PP.db.options.rotationHelper = false end
  if PP.db.options.rotationHelper then frame:Show() else frame:Hide() end
end

function RH.Toggle()
  if not frame then RH.Init() end
  PP.db.options.rotationHelper = not PP.db.options.rotationHelper
  if PP.db.options.rotationHelper then frame:Show() else frame:Hide() end
  PP.print("Rotation helper " .. (PP.db.options.rotationHelper and "ON" or "OFF"))
end
