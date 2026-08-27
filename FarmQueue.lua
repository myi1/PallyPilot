-- PallyPilot FarmQueue: the keeper tomes you're missing, where to farm them,
-- sorted easiest-first, with one-click porting to the farm zone.
--   * Ownership from the catalog tiles (tomeKnown) — the same accurate source
--     the build score uses, not the transient run set.
--   * Missing keepers (CORE/S/A not learned) cross-referenced with EbonholdHub's
--     tome map for place/mobs, and classified by farm difficulty.
--   * Grouped Open world -> World -> Dungeon -> Raid -> Unknown, colorblind-safe
--     letter markers, Port buttons via CallboardHunter.
local PP = PallyPilot
local F = PP.FarmQueue

local GOLD = "|cffe0b352"
local BRIGHT = "|cfff6d888"
local DIM = "|cffb4a586"
local R = "|r"

local MARK = { CORE = "S+", S = "S", A = "A", B = "B" }
local TIER_RANK = { CORE = 1, S = 2, A = 3, B = 4 }

local frame, rows = nil, {}

local function Norm(name)
  if not name then return nil end
  name = name:gsub("\226\128\153", "'"):gsub("\226\128\152", "'"):gsub("`", "'")
  return string.lower(name)
end

-- Owned = learned tomes, read off the catalog tiles (accurate). Returns a set
-- of normalized names, or nil if the Echoes window isn't open.
local function OwnedTomeNames()
  local tiles = PP.TomeManager and PP.TomeManager.AllTiles and PP.TomeManager.AllTiles()
  if not tiles then return nil end
  local set = {}
  for _, t in ipairs(tiles) do
    if t.known then set[Norm(t.name)] = true end
  end
  return set, tiles
end

local function LocationFor(name)
  local data = EbonholdHub and EbonholdHub.EchoMapData and EbonholdHub.EchoMapData.Locations
  if not data then return nil end
  local target = Norm(name)
  for continent, list in pairs(data) do
    for _, loc in ipairs(list) do
      if Norm(loc.name) == target then return loc, continent end
    end
  end
  return nil
end

-- Farm-difficulty class from the map notes + place. Lower rank = easier.
local RAID_KEYS = { "ulduar", "naxxramas", "onyxia", "hellfire citadel",
  "trial of the crusader", "icecrown citadel", "tomb of lights", "sunwell" }
local DUNGEON_KEYS = { "shattered halls", "scarlet monastery", "stratholme",
  "dungeon" }
local function EaseOf(item)
  if not item.hasLoc then return 5, "Location unknown" end
  local s = string.lower((item.notes or "") .. " " .. (item.place or ""))
  if string.find(s, "open world", 1, true) then return 1, "Open world" end
  if string.find(s, "everywhere", 1, true) or string.find(s, "anywhere", 1, true) then
    return 1, "Open world (anywhere)"
  end
  for _, k in ipairs(RAID_KEYS) do
    if string.find(s, k, 1, true) then return 4, "Raid" end
  end
  for _, k in ipairs(DUNGEON_KEYS) do
    if string.find(s, k, 1, true) then return 3, "Dungeon" end
  end
  return 2, "Open world"
end

function F.Compute()
  local owned, tiles = OwnedTomeNames()
  local list = {}

  local function record(name, tier, loc, continent)
    local item = {
      name = name, tier = tier,
      place = loc and loc.placeName or nil,
      mobs = loc and loc.mobs or nil,
      notes = loc and loc.notes or nil,
      x = loc and loc.x, y = loc and loc.y,
      continent = continent, hasLoc = loc ~= nil,
    }
    item.easeRank, item.easeLabel = EaseOf(item)
    list[#list + 1] = item
  end

  if tiles then
    -- Accurate path: every unowned keeper tile.
    for _, t in ipairs(tiles) do
      if (t.tier == "CORE" or t.tier == "S" or t.tier == "A") and not t.known then
        local loc, continent = LocationFor(t.name)
        record(t.name, t.tier, loc, continent)
      end
    end
  else
    -- Fallback (Echoes window closed): curated targets, cross-checked against
    -- the Hub's learned-echo sets so tomes you've already read aren't listed.
    -- Union CollectTomeOwnedSets (discovered echoes — the authoritative "have I
    -- read this tome" signal) with CollectOwnedSets (active/granted); a tome you
    -- read but haven't slotted (e.g. Arcane Cadence) is in the former only, and
    -- without it the queue wrongly tells you to farm a tome you own.
    local EO = EbonholdHub and EbonholdHub.EchoOwnership
    local runOwned = {}
    if EO then
      for _, fn in ipairs({ "CollectTomeOwnedSets", "CollectOwnedSets" }) do
        if EO[fn] then
          local ok, s = pcall(EO[fn])
          if ok and type(s) == "table" then
            for k in pairs(s) do runOwned[k] = true end
          end
        end
      end
    end
    -- Match both our Norm() and the Hub's own NormalizeName(), since the owned
    -- sets are keyed by the latter (which also strips tome/quality affixes).
    local function ownedHas(name)
      if runOwned[Norm(name)] then return true end
      if EO and EO.NormalizeName then
        local nn = EO.NormalizeName(name)
        if nn and runOwned[nn] then return true end
      end
      return false
    end
    for _, name in ipairs(PP.Build.FarmTargets()) do
      if not ownedHas(name) then
        local loc, continent = LocationFor(name)
        local tier = (PP.EchoAudit and PP.EchoAudit.ClassifyName
          and PP.EchoAudit.ClassifyName(name)) or "S"
        record(name, tier, loc, continent)
      end
    end
  end

  table.sort(list, function(a, b)
    if a.easeRank ~= b.easeRank then return a.easeRank < b.easeRank end
    local ra, rb = TIER_RANK[a.tier] or 9, TIER_RANK[b.tier] or 9
    if ra ~= rb then return ra < rb end
    return a.name < b.name
  end)
  return list, (owned ~= nil)
end

-- Place -> portable zone. Landmark overrides first (many places are sub-zone
-- landmarks or instances); otherwise the map's "Zone - sublocation" convention
-- puts the real zone in the first segment.
-- Landmarks / instances / sub-zones that name a spot but not a portable zone;
-- map them to the zone the checkpoint system can actually reach (raid entrances
-- map to their outdoor zone).
local PLACE_ZONE = {
  ["hearthglen"] = "Western Plaguelands",
  ["sorrow hill"] = "Western Plaguelands",
  ["writhing haunt"] = "Western Plaguelands",
  ["dalson's tears"] = "Western Plaguelands",
  ["blackrock stronghold"] = "Burning Steppes",
  ["dreadmaul rock"] = "Burning Steppes",
  ["grinding quarry"] = "Burning Steppes",
  ["render's rock"] = "Redridge Mountains",
  ["redrige mountain"] = "Redridge Mountains",
  ["redridge mountain"] = "Redridge Mountains",
  ["scarlet encampments"] = "Tirisfal Glades",
  ["scarlet monastery"] = "Tirisfal Glades",
  ["booty bay"] = "Stranglethorn Vale",
  ["mosh'ogg"] = "Stranglethorn Vale",
  ["malykriss"] = "Icecrown",
  ["bash'ir landing"] = "Blade's Edge Mountains",
  ["forge camp"] = "Blade's Edge Mountains",
  ["throne of kil'jaeden"] = "Hellfire Peninsula",
  ["pyrewood village"] = "Silverpine Forest",
  ["tyr's hand"] = "Eastern Plaguelands",
  ["tyr''s hand"] = "Eastern Plaguelands",
  ["pestilent scar"] = "Eastern Plaguelands",
  ["stratholme"] = "Eastern Plaguelands",
  ["southwind village"] = "Silithus",
  ["skulk rock"] = "The Hinterlands",
  ["bonechewer ruins"] = "Terokkar Forest",
  ["drak'sotra"] = "Zul'Drak",
  ["shattered halls"] = "Hellfire Peninsula",
  ["hellfire citadel"] = "Hellfire Peninsula",
  ["black temple"] = "Shadowmoon Valley",
  ["naxxramas"] = "Dragonblight",
  ["ulduar"] = "The Storm Peaks",
  ["onyxia"] = "Dustwallow Marsh",
  ["trial of the crusader"] = "Icecrown",
  ["icecrown citadel"] = "Icecrown",
  ["sunwell"] = "Isle of Quel'Danas",
}

-- Real WoW 3.3.5a zones that appear in the tome map (as a segment we can port
-- to). Lower-cased for matching. Used to pick the true zone out of a placeName
-- like "X - Hellfire Peninsula" regardless of which segment it's in.
local KNOWN_ZONES = {}
for _, z in ipairs({
  "Eastern Plaguelands", "Western Plaguelands", "Stranglethorn Vale",
  "Elwynn Forest", "Westfall", "Redridge Mountains", "Burning Steppes",
  "Silverpine Forest", "Tirisfal Glades", "The Hinterlands", "Alterac Mountains",
  "Silithus", "Feralas", "Dustwallow Marsh", "Tanaris",
  "Hellfire Peninsula", "Zangarmarsh", "Terokkar Forest", "Nagrand",
  "Blade's Edge Mountains", "Netherstorm", "Shadowmoon Valley", "Isle of Quel'Danas",
  "Borean Tundra", "Howling Fjord", "Dragonblight", "Grizzly Hills",
  "Zul'Drak", "Sholazar Basin", "Crystalsong Forest", "Icecrown",
  "The Storm Peaks", "Wintergrasp", "Dalaran",
}) do KNOWN_ZONES[string.lower(z)] = z end

-- Resolve a placeName to a portable zone, or nil if none (open-world-anywhere,
-- unknown, or a custom Ebonhold spot with no zone map).
local function ZoneForPlace(place)
  if not place then return nil end
  local low = string.lower(place)
  if string.find(low, "everywhere", 1, true) or string.find(low, "anywhere", 1, true)
     or string.find(low, "unknown", 1, true) then
    return nil
  end
  -- Landmark override wins (raids, sub-zones).
  for key, zone in pairs(PLACE_ZONE) do
    if string.find(low, key, 1, true) then return zone end
  end
  -- Split on " - " and take the last segment that is a real zone (the data
  -- often ends with the zone: "Sublocation - Hellfire Peninsula").
  local segs = {}
  for seg in string.gmatch(place, "[^%-]+") do
    seg = seg:gsub("^%s+", ""):gsub("%s+$", "")
    if seg ~= "" then segs[#segs + 1] = seg end
  end
  for i = #segs, 1, -1 do
    local z = KNOWN_ZONES[string.lower(segs[i])]
    if z then return z end
  end
  return nil
end

local function ClearRows()
  for _, r in ipairs(rows) do r:Hide() end
end

local function GetRow(i)
  local row = rows[i]
  if row then return row end
  row = CreateFrame("Frame", nil, frame.content)
  row:SetWidth(440)
  row.header = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.header:SetJustifyH("LEFT")
  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.name:SetWidth(330); row.name:SetJustifyH("LEFT")
  row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.info:SetWidth(324); row.info:SetJustifyH("LEFT")
  row.port = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.port:SetWidth(80); row.port:SetHeight(20)
  rows[i] = row
  return row
end

function F.Refresh()
  if not frame then return end
  ClearRows()
  local list, accurate = F.Compute()

  if #list == 0 then
    frame.status:SetText(BRIGHT .. "No keeper tomes missing" .. R .. DIM
      .. " — you own every S+/S/A in this view. Push the ash tree next." .. R)
  else
    frame.status:SetText(GOLD .. #list .. R .. " keeper tome(s) to farm"
      .. (accurate and "" or (DIM .. "  (open the Echoes window for exact "
        .. "ownership; showing curated targets)" .. R)))
  end

  local y, lastRank = -4, nil
  for i, item in ipairs(list) do
    local row = GetRow(i)
    row:ClearAllPoints()
    row.name:ClearAllPoints()
    row.info:ClearAllPoints()
    row.port:ClearAllPoints()

    local top = 0
    if item.easeRank ~= lastRank then
      lastRank = item.easeRank
      row.header:Show()
      row.header:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
      row.header:SetText(GOLD .. string.upper(item.easeLabel)
        .. (item.easeRank == 1 and "  (easiest)" or "") .. R)
      top = -20
    else
      row.header:Hide()
    end

    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 8, top)
    row.name:SetText("[" .. (MARK[item.tier] or "?") .. "]  " .. BRIGHT
      .. item.name .. R)
    row.port:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, top)

    local info
    if item.hasLoc then
      local zone = ZoneForPlace(item.place)
      -- Line 1: the portable ZONE (bright); then the specific spot if it adds
      -- detail beyond the zone name.
      local place = item.place or "?"
      local head
      if zone then
        head = BRIGHT .. zone .. R
        if string.lower(place) ~= string.lower(zone) then
          head = head .. DIM .. "  \194\183  " .. place .. R
        end
      else
        head = BRIGHT .. place .. R
      end
      local mobs = item.mobs and (DIM .. "kill: " .. table.concat(item.mobs, ", ") .. R) or nil
      info = head
      if mobs then info = info .. "\n" .. mobs end
      local note = item.notes
      if note and note ~= "" and not string.find(string.lower(note), "^source:") then
        info = info .. "\n" .. DIM .. note .. R
      end
      if zone then
        row.port:SetText("Port"); row.port:Enable()
        row.port:SetScript("OnClick", function()
          PP.print("Farm " .. item.name .. " \226\134\146 porting to " .. zone .. ".")
          PP.PortToZone(zone)
        end)
      else
        row.port:SetText("Anywhere"); row.port:Disable()
        row.port:SetScript("OnClick", nil)
      end
    else
      info = DIM .. "location not in the tome map — check World of Echoes" .. R
      row.port:SetText("\226\128\148"); row.port:Disable()
      row.port:SetScript("OnClick", nil)
    end
    row.info:SetPoint("TOPLEFT", row, "TOPLEFT", 8, top - 16)
    row.info:SetText(info)

    local h = -top + 16 + (row.info:GetStringHeight() or 12) + 12
    row:SetHeight(h)
    row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 4, y)
    row:Show()
    y = y - h - 2
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
  title:SetText(GOLD .. "Farm Queue — missing keepers, easiest first" .. R)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
  frame.ppClose = close

  frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.status:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -44)
  frame.status:SetWidth(380); frame.status:SetJustifyH("LEFT")

  local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  refresh:SetWidth(80); refresh:SetHeight(20)
  refresh:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -34, -40)
  refresh:SetText("Refresh")
  refresh:SetScript("OnClick", function() F.Refresh() end)

  local scroll = CreateFrame("ScrollFrame", "PallyPilotFarmScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -70)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 18)
  frame.content = CreateFrame("Frame", nil, scroll)
  frame.content:SetWidth(444); frame.content:SetHeight(10)
  scroll:SetScrollChild(frame.content)

  frame:Hide()
end

-- Embeddable: return the frame (built on demand) for the console shell.
function F.GetFrame()
  if not frame then F.Init() end
  return frame
end

function F.Toggle()
  if PP.Dashboard and PP.Dashboard.Open then PP.Dashboard.Open("farm") end
end
