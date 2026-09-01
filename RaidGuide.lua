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

-- A 3.3.5 FontString silently CLIPS very long strings -- the ICC guide is
-- ~20,000 characters and was being cut off mid-sentence ("Val'kyr Shadowguard
-- grabs you ("). Nothing errors; the tail just never draws. So the text is
-- split across a pool of FontStrings, chunked on line boundaries.
local CHUNK = 1800          -- comfortably under where clipping starts
-- chunkFS is indexed from 2 -- chunk 1 is the base `fs`. That hole at [1]
-- makes `#chunkFS` return 0 no matter how many strings exist, which silently
-- disabled the stale-chunk cleanup: a short guide selected after a long one
-- kept the long one's tail on screen. Track the high-water mark instead.
local chunkFS = {}
local chunkMax = 0

local function ChunkFS(i)
  if chunkFS[i] then return chunkFS[i] end
  local f = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  -- Must match the base `fs` exactly (width AND spacing) or line rhythm jumps
  -- at every chunk boundary and the seams become visible.
  f:SetWidth(456); f:SetJustifyH("LEFT"); f:SetJustifyV("TOP"); f:SetSpacing(2)
  chunkFS[i] = f
  if i > chunkMax then chunkMax = i end
  return f
end

-- Split on newlines so a chunk boundary never lands mid-line (which would
-- break a colour code across two FontStrings and leak escape text).
local function Split(text)
  local out, buf = {}, ""
  for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
    if #buf + #line + 1 > CHUNK and buf ~= "" then
      out[#out + 1] = buf; buf = line
    else
      buf = (buf == "") and line or (buf .. "\n" .. line)
    end
  end
  if buf ~= "" then out[#out + 1] = buf end
  return out
end

function RG.Refresh()
  if not fs then return end
  for _, btn in ipairs(raidButtons or {}) do
    if btn.raidKey == selectedKey then btn:LockHighlight() else btn:UnlockHighlight() end
  end
  local parts = Split(BuildText())
  fs:SetText(parts[1] or "")

  -- CHAIN the anchors instead of computing offsets. A FontString's GetHeight()
  -- is not valid in the same frame as its SetText -- it returns the PREVIOUS
  -- layout's value -- so accumulating it stacked chunks on top of each other.
  -- Anchoring each chunk to the previous one's BOTTOMLEFT hands the layout to
  -- WoW, which resolves it after the text is measured. No arithmetic to get
  -- wrong.
  local prev = fs
  for i = 2, #parts do
    local f = ChunkFS(i)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2)
    f:SetText(parts[i])
    f:Show()
    prev = f
  end
  for i = math.max(2, #parts + 1), chunkMax do
    if chunkFS[i] then chunkFS[i]:SetText(""); chunkFS[i]:Hide() end
  end

  -- Scroll extent only: GetStringHeight IS derived from the text, so it's safe
  -- here, and being a little off just changes how far you can scroll.
  local h = 0
  for i = 1, #parts do
    local f = (i == 1) and fs or chunkFS[i]
    h = h + (f:GetStringHeight() or 0) + 2
  end
  if content then content:SetHeight(math.max(10, h + 24)) end
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
