-- PallyPilot EchoAudit: verdicts for the echoes you actually OWN.
-- Reads EbonholdHub's live ownership set (integration only — nothing copied)
-- and sorts every owned echo into: REROLL / DISABLE / FINE / KEEP / CORE.
local PP = PallyPilot
local A = PP.EchoAudit

local GOLD = "|cffe0b352"
local BRIGHT = "|cfff6d888"
local DIM = "|cffb4a586"
local EMBER = "|cffd9694a"
local VERD = "|cff8aa96a"
local ASH = "|cff9db3bd"
local R = "|r"

local frame, fs, content

local function Norm(name)
  if not name then return nil end
  name = name:gsub("’", "'"):gsub("‘", "'"):gsub("`", "'")
  return string.lower(name)
end

local function OwnedSet()
  if EbonholdHub and EbonholdHub.EchoOwnership
     and EbonholdHub.EchoOwnership.CollectOwnedSets then
    local ok, ownedLower = pcall(EbonholdHub.EchoOwnership.CollectOwnedSets)
    if ok and type(ownedLower) == "table" then return ownedLower end
  end
  return nil
end

-- lowercase name -> proper display name, built from every source we know.
local function DisplayNames()
  local map = {}
  local B = PP.Build
  local function add(n) if n then map[Norm(n)] = n end end
  for _, n in ipairs(B.locked) do add(n) end
  for _, list in pairs(B.tiers) do
    for _, n in ipairs(list) do add(n) end
  end
  for _, n in ipairs(B.disable) do add(n) end
  local data = EbonholdHub and EbonholdHub.EchoMapData and EbonholdHub.EchoMapData.Locations
  if data then
    for _, list in pairs(data) do
      for _, loc in ipairs(list) do add(loc.name) end
    end
  end
  return map
end

-- Fallback prettifier for names we only have in lowercase.
local function TitleCase(lower)
  return (lower:gsub("(%a)([%w']*)", function(head, rest)
    return string.upper(head) .. rest
  end))
end

-- Verdict for one owned echo (by normalized name).
-- Returns key: "CORE" | "S" | "A" | "B" | "DISABLE" | "REROLL"
local function Classify(norm)
  local B = PP.Build
  for _, n in ipairs(B.disable) do
    if Norm(n) == norm then return "DISABLE" end
  end
  for _, n in ipairs(B.locked) do
    if Norm(n) == norm then return "CORE" end
  end
  for tier, list in pairs(B.tiers) do
    for _, n in ipairs(list) do
      if Norm(n) == norm then return tier end
    end
  end
  return "REROLL"
end

-- Full audit: buckets of display names, sorted, plus counts.
function A.Compute()
  local owned = OwnedSet()
  if not owned then return nil end
  local names = DisplayNames()
  local buckets = { CORE = {}, S = {}, A = {}, B = {}, DISABLE = {}, REROLL = {} }
  local total = 0
  for norm in pairs(owned) do
    total = total + 1
    local verdict = Classify(norm)
    local display = names[norm] or TitleCase(norm)
    table.insert(buckets[verdict], display)
  end
  for _, list in pairs(buckets) do table.sort(list) end
  return buckets, total
end

local SECTIONS = {
  { key = "REROLL", color = EMBER, title = "Reroll / feed to an Orb",
    note = "Not in the build. These are your reroll currency — no build slot wants them." },
  { key = "DISABLE", color = EMBER, title = "Disable / banish",
    note = "Actively bad for this build. Turn them off; banish from draws when offered." },
  { key = "B", color = DIM, title = "Fine — keep, low priority",
    note = "B tier. Fill slots when nothing better is available; replace as S/A arrive." },
  { key = "A", color = ASH, title = "Keep — A tier", note = nil },
  { key = "S", color = BRIGHT, title = "Keep — S tier", note = nil },
  { key = "CORE", color = GOLD, title = "Core — LOCK these",
    note = "The six that persist across runs. If any here isn't locked in the Echoes UI, lock it now." },
}

local function BuildText()
  local buckets, total = A.Compute()
  local t = {}
  if not buckets then
    t[#t+1] = EMBER .. "EbonholdHub not detected" .. R .. "\n"
    t[#t+1] = DIM .. "The audit reads your owned echoes from EbonholdHub's live data. "
      .. "Install/enable EbonholdHub, then reopen this window." .. R .. "\n"
    return table.concat(t)
  end
  t[#t+1] = DIM .. "You own " .. R .. GOLD .. total .. R .. DIM .. " echoes — "
    .. #buckets.CORE .. " core, " .. #buckets.S .. " S, " .. #buckets.A .. " A, "
    .. #buckets.B .. " B, " .. #buckets.DISABLE .. " to disable, "
    .. #buckets.REROLL .. " to reroll." .. R .. "\n"
  for _, sec in ipairs(SECTIONS) do
    local list = buckets[sec.key]
    if #list > 0 then
      t[#t+1] = "\n" .. sec.color .. string.upper(sec.title)
        .. "  (" .. #list .. ")" .. R .. "\n"
      if sec.note then t[#t+1] = DIM .. sec.note .. R .. "\n" end
      for _, name in ipairs(list) do
        t[#t+1] = "  " .. sec.color .. "* " .. R .. name .. "\n"
      end
    end
  end
  t[#t+1] = "\n" .. DIM .. PP.Build.disableNote .. R .. "\n"
  t[#t+1] = VERD .. "Unrated echoes default to Reroll. If one reads strong for the "
    .. "build, it may just be missing a tier — ratings live in BuildData.lua." .. R .. "\n"
  return table.concat(t)
end

function A.Refresh()
  if not fs then return end
  fs:SetText(BuildText())
  if content then content:SetHeight((fs:GetHeight() or 600) + 20) end
end

function A.Init()
  if frame then return end
  frame = CreateFrame("Frame", "PallyPilotAuditFrame", UIParent)
  frame:SetWidth(440); frame:SetHeight(540)
  frame:SetPoint("CENTER", UIParent, "CENTER", -60, 0)
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
  title:SetText(GOLD .. "Echo Audit — keep or reroll?" .. R)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)

  local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  refresh:SetWidth(80); refresh:SetHeight(20)
  refresh:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -40)
  refresh:SetText("Refresh")
  refresh:SetScript("OnClick", function() A.Refresh() end)

  local scroll = CreateFrame("ScrollFrame", "PallyPilotAuditScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -66)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 18)
  content = CreateFrame("Frame", nil, scroll)
  content:SetWidth(380); content:SetHeight(10)
  scroll:SetScrollChild(content)

  fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  fs:SetWidth(376); fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
  fs:SetSpacing(2)

  frame:Hide()
end

function A.Toggle()
  if not frame then A.Init() end
  if frame:IsShown() then frame:Hide() else A.Refresh(); frame:Show() end
end
