-- PallyPilot RaidGuide: per-raid, per-boss solo Ret guides (data in GuideData).
-- Panel: raid selector row + scrollable all-boss text. /pp boss prints the
-- guide for your current target (or a named boss) straight to chat.
local PP = PallyPilot
local RG = PP.RaidGuide

local GOLD = "|cffe0b352"
local BRIGHT = "|cfff6d888"
local DIM = "|cffb4a586"
local EMBER = "|cffd9694a"
local VERD = "|cff8aa96a"
local R = "|r"

local frame, fs, content, raidButtons
local selectedKey

local function SelectedRaid()
  for _, raid in ipairs(PP.GuideData.raids) do
    if raid.key == selectedKey then return raid end
  end
  return PP.GuideData.raids[1]
end

local function BuildText()
  local raid = SelectedRaid()
  local t = {}
  t[#t+1] = BRIGHT .. raid.name .. R .. "\n"
  t[#t+1] = DIM .. raid.note .. R .. "\n"
  if raid.route then
    t[#t+1] = "\n" .. GOLD .. "ROUTE" .. R .. "\n"
    t[#t+1] = raid.route .. "\n"
  end
  local kills = (PP.db.kills and PP.db.kills[raid.zone]) or {}
  for _, boss in ipairs(raid.bosses) do
    local k = kills[boss.n]
    local mark = k and (VERD .. "[DEAD " .. (k.when or "") .. "]  " .. R) or ""
    t[#t+1] = "\n" .. mark .. GOLD .. string.upper(boss.n) .. R .. "\n"
    t[#t+1] = EMBER .. boss.t .. R .. "\n"
    for _, tip in ipairs(boss.tips) do
      t[#t+1] = "  " .. BRIGHT .. "* " .. R .. tip .. "\n"
    end
  end
  t[#t+1] = "\n" .. VERD .. "Target a boss and /pp boss prints its guide to chat mid-fight." .. R .. "\n"
  return table.concat(t)
end

function RG.Refresh()
  if not fs then return end
  for _, btn in ipairs(raidButtons or {}) do
    if btn.raidKey == selectedKey then btn:LockHighlight() else btn:UnlockHighlight() end
  end
  fs:SetText(BuildText())
  if content then content:SetHeight((fs:GetHeight() or 600) + 20) end
end

function RG.Select(key)
  selectedKey = key
  RG.Refresh()
end

function RG.Init()
  if frame then return end
  frame = CreateFrame("Frame", "PallyPilotGuideFrame", UIParent)
  frame:SetWidth(520); frame:SetHeight(600)
  frame:SetPoint("CENTER", UIParent, "CENTER", 60, 0)
  frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 28,
    insets = { left = 10, right = 10, top = 10, bottom = 10 },
  })

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", frame, "TOP", 0, -16)
  title:SetText(GOLD .. "Solo Raid Guide — Ret" .. R)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
  frame.ppClose = close

  -- Raid selector: one small button per raid, wrapped in two rows.
  raidButtons = {}
  local perRow, bw, bh = 4, 115, 20
  for i, raid in ipairs(PP.GuideData.raids) do
    local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btn:SetWidth(bw); btn:SetHeight(bh)
    local row = math.floor((i - 1) / perRow)
    local col = (i - 1) - row * perRow
    btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 18 + col * (bw + 4), -40 - row * (bh + 4))
    btn:SetText(raid.name == "Trial of the Crusader" and "Trial (ToC)" or raid.name)
    btn.raidKey = raid.key
    btn:SetScript("OnClick", function(self) RG.Select(self.raidKey) end)
    raidButtons[#raidButtons + 1] = btn
  end
  local rowsUsed = math.ceil(#PP.GuideData.raids / perRow)
  local topOffset = 46 + rowsUsed * (bh + 4)

  local scroll = CreateFrame("ScrollFrame", "PallyPilotGuideScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -topOffset)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 18)
  content = CreateFrame("Frame", nil, scroll)
  content:SetWidth(460); content:SetHeight(10)
  scroll:SetScrollChild(content)

  fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  fs:SetWidth(456); fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
  fs:SetSpacing(2)

  frame:Hide()
end

-- Embeddable: return the frame (built on demand) for the console shell.
function RG.GetFrame()
  if not frame then RG.Init() end
  return frame
end

-- Called by the shell just before showing: auto-select the raid you're in.
function RG.OnShow()
  local here = PP.GuideData.RaidForZone(GetRealZoneText())
  if here then selectedKey = here.key end
  if not selectedKey then selectedKey = PP.GuideData.raids[1].key end
  RG.Refresh()
end

function RG.Toggle()
  if PP.Dashboard and PP.Dashboard.Open then PP.Dashboard.Open("raid") end
end

-- /pp boss [name] — chat-print the guide for the named or targeted boss.
function RG.BossToChat(arg)
  local query = arg and arg ~= "" and arg or UnitName("target")
  if not query then
    PP.print("Target a boss (or /pp boss <name>) and I'll print its solo guide.")
    return
  end
  local boss, raid = PP.GuideData.FindBoss(query)
  if not boss then
    PP.print("No guide for '" .. tostring(query) .. "'. /pp guide opens the full browser.")
    return
  end
  PP.print(GOLD .. boss.n .. R .. DIM .. "  (" .. raid.name .. ")" .. R)
  DEFAULT_CHAT_FRAME:AddMessage(EMBER .. "  " .. boss.t .. R)
  for _, tip in ipairs(boss.tips) do
    DEFAULT_CHAT_FRAME:AddMessage(BRIGHT .. "  * " .. R .. tip)
  end
end
