-- PallyPilot Dashboard: the always-on curated build reference (feature 2).
local PP = PallyPilot
local D = PP.Dashboard

local GOLD = "|cffe0b352"
local BRIGHT = "|cfff6d888"
local DIM = "|cffb4a586"
local ASH = "|cff9db3bd"
local EMBER = "|cffd9694a"
local VERD = "|cff8aa96a"
local R = "|r"

local frame, fs, content

local function H(t) return "\n" .. GOLD .. string.upper(t) .. R .. "\n" end
local function line(t) return t .. "\n" end

-- The focal element: one context-aware "what do I do right now?" line.
-- Reads live state (level, zone, build mode, ash, raid) so the player never
-- has to remember which of the tools/commands fits the moment.
function D.NextAction()
  local lvl = UnitLevel("player") or 80
  local zone = GetRealZoneText() or ""
  local mode = PP.db.buildMode
  local modeWord = (mode == "farm" and "Farm pool") or "Raid pool"

  -- 1. Run start — level to 80, banishing junk; the saved build restores at 80.
  if lvl <= 5 then
    return GOLD .. "Run start. " .. R
      .. "Level to 80 (" .. BRIGHT .. modeWord .. R
      .. " + banish junk as it appears). Your saved build restores by "
      .. BRIGHT .. "activating its Snapshot AT 80" .. R
      .. " (full swap, Epic quality included) — the old level-1 guarantee is gone."
  end
  -- 2. Prestige ready — spend into permanents, then reset.
  local st = PP.AshAdvisor and PP.AshAdvisor.GetState and PP.AshAdvisor.GetState()
  local gate = PP.AshData and PP.AshData.PRESTIGE and PP.AshData.PRESTIGE.gate
  if st and st.committed and gate and st.committed >= gate then
    return GOLD .. "Prestige ready. " .. R
      .. "Skill Tree \226\134\146 pour banked ash into the infinites (permanent), then prestige."
  end
  -- 3. Inside a known raid — route + boss cards.
  local raid = PP.GuideData and PP.GuideData.RaidForZone
    and PP.GuideData.RaidForZone(zone)
  if raid then
    local kills, n = PP.db.kills and PP.db.kills[zone], 0
    if kills then for _ in pairs(kills) do n = n + 1 end end
    return GOLD .. "In " .. raid.name .. ". " .. R
      .. "Raid guide for the route; target a boss for its card."
      .. (n > 0 and (DIM .. "  " .. n .. " down this lockout." .. R) or "")
  end
  -- 4. At 80 — activate a snapshot for full restore, or polish + save.
  if lvl >= 80 then
    return GOLD .. "At 80. " .. R
      .. "Have a saved build? " .. BRIGHT .. "activate its Snapshot now" .. R
      .. " for a full swap (Epic restored). Else polish (Reroll junk / orb-fish "
      .. "on a banished pool) and " .. BRIGHT .. "save at 80" .. R .. "."
  end
  -- 5. Leveling.
  return GOLD .. "Leveling (" .. (mode and string.upper(mode) or "?") .. "). " .. R
    .. "Auto-Pick is drafting — Rotation HUD for combat, Talents to guide points."
end

-- Trimmed reference: only what you actually re-read (stats, seal, rotation,
-- locks, gear). Echo tiers + affix schools were removed — that data now
-- lives as verdict dots on the journal tiles and character-sheet slots.
local function BuildText()
  local B = PP.Build
  local t = {}
  t[#t+1] = H("Stat priority")
  t[#t+1] = line(GOLD .. table.concat(B.statPriority, "  >  ") .. R)
  t[#t+1] = line(DIM .. B.statNote .. R)

  t[#t+1] = H("Seal · blessing · rotation")
  t[#t+1] = line(GOLD .. "Seal " .. R .. B.seal)
  t[#t+1] = line(GOLD .. "Blessing " .. R .. B.blessing)
  t[#t+1] = line(BRIGHT .. "Rotation  " .. R .. B.rotation)

  t[#t+1] = H("Lock these six")
  local locked = {}
  for _, n in ipairs(B.locked) do locked[#locked + 1] = n end
  t[#t+1] = line("  " .. BRIGHT .. table.concat(locked, DIM .. " · " .. BRIGHT) .. R)

  t[#t+1] = H("Gear targets")
  for _, g in ipairs(B.gear) do
    t[#t+1] = line("  " .. BRIGHT .. g.slot .. R .. " — " .. g.target)
  end

  t[#t+1] = "\n" .. DIM .. "Echo verdicts show as LETTER badges on the journal "
    .. "tiles (S+/S/A/B/C/X — Echo audit for the list). Gear + affix verdicts "
    .. "show on your character sheet (Gear audit)." .. R
  return table.concat(t)
end

function D.Refresh()
  if frame and frame.now then
    frame.now:SetText(PP.safeCall and D.NextAction and D.NextAction() or "")
    if frame.status then
      local mode = PP.db.buildMode
      -- Mode chip carries the WORD (FARM/RAID) so it reads without color;
      -- FARM=ember, RAID=ash deliberately avoids a red/green pair.
      frame.status:SetText(DIM .. "Lv " .. (UnitLevel("player") or "?")
        .. "  ·  build " .. R
        .. (mode == "farm" and (EMBER .. "[FARM]") or (mode == "raid" and (ASH .. "[RAID]") or (DIM .. "[unsynced]")))
        .. R)
    end
  end
  if not fs then return end
  fs:SetText(BuildText())
  if content then content:SetHeight((fs:GetHeight() or 600) + 20) end
end

function D.Init()
  if frame then return end
  frame = CreateFrame("Frame", "PallyPilotFrame", UIParent)
  frame:SetWidth(480); frame:SetHeight(580)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint()
    PP.db.options.winPos = { x = x, y = y }
  end)
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 28,
    insets = { left = 10, right = 10, top = 10, bottom = 10 },
  })
  if PP.db.options.winPos then
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", PP.db.options.winPos.x, PP.db.options.winPos.y)
  end

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -16)
  title:SetText(GOLD .. "PallyPilot" .. R)

  frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.status:SetPoint("LEFT", title, "RIGHT", 10, 0)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)

  -- Focal NOW card: a bordered panel holding the one next-action line.
  local nowCard = CreateFrame("Frame", nil, frame)
  nowCard:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -42)
  nowCard:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -42)
  nowCard:SetHeight(58)
  nowCard:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  nowCard:SetBackdropColor(0.12, 0.10, 0.06, 0.9)
  nowCard:SetBackdropBorderColor(0.55, 0.45, 0.20, 0.8)
  local nowHead = nowCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  nowHead:SetPoint("TOPLEFT", nowCard, "TOPLEFT", 10, -8)
  nowHead:SetText(GOLD .. "NEXT" .. R)
  frame.now = nowCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.now:SetPoint("TOPLEFT", nowCard, "TOPLEFT", 10, -22)
  frame.now:SetPoint("BOTTOMRIGHT", nowCard, "BOTTOMRIGHT", -10, 8)
  frame.now:SetJustifyH("LEFT"); frame.now:SetJustifyV("TOP")

  -- Tool buttons, grouped left-to-right by concern. 4 per row, 108 wide.
  local tools = {
    { "Echo audit", function() if PP.EchoAudit then PP.EchoAudit.Toggle() end end },
    { "Gear audit", function() if PP.GearAudit then PP.GearAudit.Toggle() end end },
    { "Farm tomes", function() if PP.FarmQueue then PP.FarmQueue.Toggle() end end },
    { "Raid guide", function() if PP.RaidGuide then PP.RaidGuide.Toggle() end end },
    { "Rotation HUD", function() if PP.RotationHelper then PP.RotationHelper.Toggle() end end },
    { "Guide talents", function() if PP.Talents then PP.Talents.Guide() end end },
    { "Save talents", function() if PP.Talents then PP.Talents.Save() end end },
    { "Ash: /pp ash", function() if PP.AshAdvisor and PP.AshAdvisor.Command then PP.AshAdvisor.Command() end end },
  }
  for i, tb in ipairs(tools) do
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetWidth(108); b:SetHeight(21)
    local col = (i - 1) % 4
    local row = math.floor((i - 1) / 4)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", 18 + col * 112, -108 - row * 25)
    b:SetText(tb[1])
    b:SetScript("OnClick", tb[2])
  end

  local scroll = CreateFrame("ScrollFrame", "PallyPilotScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -164)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 18)

  content = CreateFrame("Frame", nil, scroll)
  content:SetWidth(420); content:SetHeight(10)
  scroll:SetScrollChild(content)

  fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  fs:SetWidth(416); fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
  fs:SetSpacing(2)
  fs:SetText("")

  -- Keep the focal NOW line current while the panel is open (cheap, 3s).
  frame.elapsed = 0
  frame:SetScript("OnUpdate", function(self, e)
    self.elapsed = self.elapsed + e
    if self.elapsed > 3 then
      self.elapsed = 0
      if self.now then self.now:SetText(D.NextAction()) end
    end
  end)

  D.Refresh()
  frame:Hide()
end

function D.Toggle()
  if not frame then D.Init() end
  if frame:IsShown() then frame:Hide() else D.Refresh(); frame:Show() end
end
