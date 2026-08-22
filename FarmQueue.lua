-- PallyPilot FarmQueue: which build tomes you're missing, where to farm them,
-- and one-click porting (feature 1). Reads EbonholdHub's live data if present
-- (integration only — nothing is copied) and ports via CallboardHunter.
local PP = PallyPilot
local F = PP.FarmQueue

local GOLD = "|cffe0b352"
local BRIGHT = "|cfff6d888"
local DIM = "|cffb4a586"
local VERD = "|cff8aa96a"
local R = "|r"

local frame, rows = nil, {}

-- Normalize an echo name for comparison (mirror EbonholdHub's rules loosely).
local function Norm(name)
  if not name then return nil end
  name = name:gsub("’", "'"):gsub("‘", "'"):gsub("`", "'")
  return string.lower(name)
end

-- Which build echoes do we already own? Prefer EbonholdHub's computed set.
local function OwnedSet()
  if EbonholdHub and EbonholdHub.EchoOwnership
     and EbonholdHub.EchoOwnership.CollectOwnedSets then
    local ok, ownedLower = pcall(EbonholdHub.EchoOwnership.CollectOwnedSets)
    if ok and type(ownedLower) == "table" then return ownedLower end
  end
  return nil -- unknown; we'll show everything as "check in game"
end

-- Find a tome's location entry in EbonholdHub's map data by echo name.
local function LocationFor(name)
  local data = EbonholdHub and EbonholdHub.EchoMapData and EbonholdHub.EchoMapData.Locations
  if not data then return nil end
  local target = Norm(name)
  for continent, list in pairs(data) do
    for _, loc in ipairs(list) do
      if Norm(loc.name) == target then
        return loc, continent
      end
    end
  end
  return nil
end

-- Build the missing-tome list: {name, place, zone, mobs, notes, hasLoc}
function F.Compute()
  local owned = OwnedSet()
  local out = {}
  for _, name in ipairs(PP.Build.FarmTargets()) do
    local isOwned = owned and owned[Norm(name)] or false
    if not isOwned then
      local loc, continent = LocationFor(name)
      out[#out + 1] = {
        name = name,
        place = loc and loc.placeName or nil,
        continent = continent,
        mobs = loc and loc.mobs or nil,
        notes = loc and loc.notes or nil,
        x = loc and loc.x, y = loc and loc.y,
        hasLoc = loc ~= nil,
      }
    end
  end
  -- Known locations first, then unknowns.
  table.sort(out, function(a, b)
    if a.hasLoc ~= b.hasLoc then return a.hasLoc end
    return a.name < b.name
  end)
  return out, (owned ~= nil)
end

-- Best-effort zone name for porting from a place name. CallboardHunter ports by
-- GetRealZoneText zone; EbonholdHub stores continent + landmark, so we map the
-- common landmarks the build cares about. Falls back to the place text.
local PLACE_ZONE = {
  ["hearthglen"] = "Western Plaguelands",
  ["blackrock stronghold"] = "Burning Steppes",
  ["render's rock"] = "Redridge Mountains",
  ["dreadmaul rock"] = "Burning Steppes",
  ["scarlet encampments"] = "Tirisfal Glades",
  ["alterac mountains"] = "Alterac Mountains",
  ["booty bay"] = "The Cape of Stranglethorn",
  ["mosh'ogg"] = "Northern Stranglethorn",
}
local function ZoneForPlace(place)
  if not place then return nil end
  local p = string.lower(place)
  for key, zone in pairs(PLACE_ZONE) do
    if string.find(p, key, 1, true) then return zone end
  end
  return place -- let CallboardHunter try to match it as a zone
end

local function ClearRows()
  for _, r in ipairs(rows) do r:Hide() end
end

function F.Refresh()
  if not frame then return end
  ClearRows()
  local list, ownershipKnown = F.Compute()
  frame.status:SetText(ownershipKnown
    and (GOLD .. #list .. R .. " build tomes still missing")
    or (DIM .. "EbonholdHub not detected — showing all build tomes; learned ones won't be filtered." .. R))

  local y = -8
  for i, item in ipairs(list) do
    local row = rows[i]
    if not row then
      row = CreateFrame("Frame", nil, frame.content)
      row:SetWidth(430); row:SetHeight(46)
      row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 2, 0)
      row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      row.info:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -16)
      row.info:SetWidth(320); row.info:SetJustifyH("LEFT")
      row.port = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
      row.port:SetWidth(70); row.port:SetHeight(20)
      row.port:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -2)
      rows[i] = row
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 4, y)
    row.name:SetText(BRIGHT .. item.name .. R)
    if item.hasLoc then
      local mobs = item.mobs and (" — " .. table.concat(item.mobs, ", ")) or ""
      local notes = (item.notes and item.notes ~= "Source: Open World") and ("  " .. DIM .. item.notes .. R) or ""
      row.info:SetText(DIM .. (item.place or "?") .. R .. mobs .. notes)
      local zone = ZoneForPlace(item.place)
      row.port:SetText("Port")
      row.port:Enable()
      row.port:SetScript("OnClick", function()
        PP.print("Farming " .. item.name .. " at " .. (item.place or "?") .. " — porting toward " .. tostring(zone))
        PP.PortToZone(zone)
      end)
    else
      row.info:SetText(DIM .. "location unknown (not in the tome map) — check World of Echoes" .. R)
      row.port:SetText("—"); row.port:Disable()
      row.port:SetScript("OnClick", nil)
    end
    row:Show()
    y = y - 50
  end
  frame.content:SetHeight(math.max(10, -y + 10))
end

function F.Init()
  if frame then return end
  frame = CreateFrame("Frame", "PallyPilotFarmFrame", UIParent)
  frame:SetWidth(500); frame:SetHeight(560)
  frame:SetPoint("CENTER", UIParent, "CENTER", 40, -20)
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
  title:SetText(GOLD .. "Missing Tomes — Farm Queue" .. R)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)

  frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.status:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -44)

  local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  refresh:SetWidth(80); refresh:SetHeight(20)
  refresh:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -34, -40)
  refresh:SetText("Refresh")
  refresh:SetScript("OnClick", function() F.Refresh() end)

  local scroll = CreateFrame("ScrollFrame", "PallyPilotFarmScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -70)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 18)
  frame.content = CreateFrame("Frame", nil, scroll)
  frame.content:SetWidth(440); frame.content:SetHeight(10)
  scroll:SetScrollChild(frame.content)

  frame:Hide()
end

function F.Toggle()
  if not frame then F.Init() end
  if frame:IsShown() then frame:Hide() else F.Refresh(); frame:Show() end
end
