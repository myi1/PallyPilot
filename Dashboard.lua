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

local frame, fs

local function H(t) return "\n" .. GOLD .. string.upper(t) .. R .. "\n" end
local function line(t) return t .. "\n" end

local function BuildText()
  local B = PP.Build
  local t = {}
  t[#t+1] = BRIGHT .. B.title .. R .. "\n"
  t[#t+1] = DIM .. B.talents .. R .. "\n"

  t[#t+1] = H("Stat Priority")
  t[#t+1] = line(GOLD .. table.concat(B.statPriority, "  >  ") .. R)
  t[#t+1] = line(DIM .. B.statNote .. R)
  t[#t+1] = line(DIM .. B.enchants .. R)

  t[#t+1] = H("Lock These Six Echoes")
  for _, n in ipairs(B.locked) do t[#t+1] = line("  " .. BRIGHT .. "* " .. R .. n) end

  t[#t+1] = H("Draw Priority — take highest offered")
  t[#t+1] = line(BRIGHT .. "S  " .. R .. table.concat(B.tiers.S, ", "))
  t[#t+1] = line(ASH .. "A  " .. R .. table.concat(B.tiers.A, ", "))
  t[#t+1] = line(DIM .. "B  " .. R .. table.concat(B.tiers.B, ", "))

  t[#t+1] = H("Disable / Banish")
  t[#t+1] = line(EMBER .. table.concat(B.disable, ", ") .. R)
  t[#t+1] = line(DIM .. B.disableNote .. R)

  t[#t+1] = H("Affixes — Survival first (AotC I)")
  for _, a in ipairs(B.affixSurvival) do
    t[#t+1] = line("  " .. BRIGHT .. a.affix .. R .. " — " .. a.role .. DIM .. "  [" .. a.slots .. "]" .. R)
  end
  t[#t+1] = H("Affixes — Damage max (HC4+)")
  for _, a in ipairs(B.affixDamage) do
    t[#t+1] = line("  " .. BRIGHT .. a.affix .. R .. " — " .. a.role)
  end
  t[#t+1] = line(DIM .. B.affixNote .. R)

  t[#t+1] = H("Gear Targets")
  for _, g in ipairs(B.gear) do
    t[#t+1] = line("  " .. BRIGHT .. g.slot .. R .. ": " .. g.target)
  end

  t[#t+1] = "\n" .. VERD .. "Tip: /pp farm shows which build tomes you're missing and ports you to farm them." .. R .. "\n"
  return table.concat(t)
end

function D.Refresh()
  if fs then fs:SetText(BuildText()) end
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
  title:SetPoint("TOP", frame, "TOP", 0, -16)
  title:SetText(GOLD .. "PallyPilot" .. R)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)

  local farmBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  farmBtn:SetWidth(150); farmBtn:SetHeight(22)
  farmBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -40)
  farmBtn:SetText("Missing tomes to farm")
  farmBtn:SetScript("OnClick", function() if PP.FarmQueue.Toggle then PP.FarmQueue.Toggle() end end)

  local scroll = CreateFrame("ScrollFrame", "PallyPilotScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -72)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 18)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetWidth(420); content:SetHeight(10)
  scroll:SetScrollChild(content)

  fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  fs:SetWidth(416); fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
  fs:SetSpacing(2)
  fs:SetText("")
  fs:SetScript("OnShow", function() D.Refresh() end)

  -- keep content height in sync so the scrollbar works
  content:SetScript("OnUpdate", function(self)
    local h = fs:GetStringHeight() + 10
    if math.abs((self:GetHeight() or 0) - h) > 2 then self:SetHeight(h) end
  end)

  D.Refresh()
  frame:Hide()
end

function D.Toggle()
  if not frame then D.Init() end
  if frame:IsShown() then frame:Hide() else D.Refresh(); frame:Show() end
end
