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
local EMBER = "|cffd9694a"   -- warning tone, matches the other panels
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
  -- MergedTiles, not AllTiles: the journal scroll is virtualized, so
  -- AllTiles() returns only the rendered slice and any ownership answer
  -- built on it is a fraction of the collection.
  local tiles = PP.TomeManager and PP.TomeManager.MergedTiles
    and PP.TomeManager.MergedTiles()
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

-- Tome locations come from EbonholdHub's map data (read live, never copied).
-- When Ebonhold MOVES a drop and that data hasn't caught up, the queue sends you
-- to the old mob -- so corrections go here, keyed by lower-cased echo name.
-- Keep the `notes` honest about how confident we are.
local TOME_OVERRIDE = {
  ["demonic awakening"] = {
    placeName = "Black Temple - Shadowmoon Valley",
    -- mobs MUST be a table: the renderer does table.concat(item.mobs, ", ").
    -- A bare string here threw mid-loop, and because Refresh runs under
    -- safeCall the error was swallowed -- the queue just stopped drawing rows
    -- after this entry with no visible failure.
    mobs = { "Illidan Stormrage" },
    notes = "MOVED off Doom Lord Kazzak (his respawn was too slow). "
      .. "Reported in-game, not yet confirmed by me -- verify before a long trip.",
  },

  -- ICC / Ruby Sanctum tomes. EbonholdHub's map data predates those patches, so
  -- every one of them lands in "Location unknown" without an entry here.
  -- Sources: Ebonhold Discord, #paladin and #general, Aug 2026. ICC and RS tomes
  -- are SOULBOUND -- the AH is not an option for these.
  ["necrotic plague"] = {
    placeName = "Icecrown Citadel - The Lich King",
    mobs = { "The Lich King" },
    notes = "SOULBOUND -- must be farmed yourself. LK drops 1 of 3: Necrotic "
      .. "Plague / Frostmourne Hungers / Defile. 10-HEROIC reportedly always "
      .. "drops Necrotic Plague (community report, Aug 2026 -- not dev-confirmed).",
  },
  ["frostmourne hungers"] = {
    placeName = "Icecrown Citadel - The Lich King",
    mobs = { "The Lich King" },
    notes = "SOULBOUND -- must be farmed yourself. LK drops 1 of 3: Necrotic "
      .. "Plague / Frostmourne Hungers / Defile. 25-HEROIC is the reported best "
      .. "odds for Frostmourne (community report, Aug 2026 -- not dev-confirmed).",
  },
  ["gunship barrage"] = {
    placeName = "Icecrown Citadel - Gunship Battle",
    mobs = { "Gunship Battle" },
    notes = "INFERRED, not confirmed: the name matches the ICC Gunship encounter "
      .. "and it sits in the ICC/RS block of the Hub's echo data. Verify before "
      .. "a dedicated trip. Two players in #rogue and #mage called this echo "
      .. "worthless -- consider dropping it off the target list entirely.",
  },

  -- The Reaper trio. The map data has the spawn CONDITION but not the where/how.
  ["reaper's verdict"] = {
    placeName = "Icecrown - Malykriss: The Vile Hold (upper hold, east side)",
    mobs = { "The Reaper" },
    notes = "Tradeable (unlike ICC/RS tomes). Hold Intensity 5 (475) plus "
      .. "UNBROKEN combat for 10 min; he spawns on you and despawns after 15. "
      .. "Wide circles through the upper hold, no pet echoes, let procs do the "
      .. "killing. See /ep guide reaper.",
  },
  ["reaper's doom"] = {
    placeName = "Icecrown - Malykriss: The Vile Hold (upper hold, east side)",
    mobs = { "The Reaper" },
    notes = "Tradeable (unlike ICC/RS tomes). Hold Intensity 5 (475) plus "
      .. "UNBROKEN combat for 10 min; he spawns on you and despawns after 15. "
      .. "Wide circles through the upper hold, no pet echoes, let procs do the "
      .. "killing. See /ep guide reaper.",
  },
  ["reaper's reprieve"] = {
    placeName = "Icecrown - Malykriss: The Vile Hold (upper hold, east side)",
    mobs = { "The Reaper" },
    notes = "Tradeable (unlike ICC/RS tomes). Hold Intensity 5 (475) plus "
      .. "UNBROKEN combat for 10 min; he spawns on you and despawns after 15. "
      .. "See /ep guide reaper.",
  },
}

-- The queue farms CORE/S/A, but the BiS pool keeps only CORE/S -- so without
-- this an A-tier tome reads as "go farm it" here and "switch it off" there, for
-- the same echo on the same evening. Say the disposition on the row instead of
-- letting the two tools contradict each other.
--
-- It matters more than tidiness now that unlocking a tome PERMANENTLY enlarges
-- the draw pool: farming something you will immediately disable is not neutral,
-- it is a trip you did not need to make.
local function PoolFate(name)
  if not name then return nil end
  if PP.BisPlan and PP.BisPlan.IsTarget and PP.BisPlan.IsTarget(name) then
    return "CHASE"   -- short list: worth orbs, worth a dedicated trip
  end
  if PP.BisPlan and PP.BisPlan.IsKeep and PP.BisPlan.IsKeep(name) then
    return "KEEP"    -- stays enabled for breadth; draft it, never reroll for it
  end
  return "CUT"       -- the pool disables it, so farming it is wasted effort
end

function F.Compute()
  local owned, tiles = OwnedTomeNames()
  local list = {}

  local function record(name, tier, loc, continent)
    local ov = name and TOME_OVERRIDE[string.lower(name)]
    if ov then
      -- Override wins, but keep any coords we had; they're wrong for the new
      -- place, so drop them rather than point the arrow at the old mob.
      loc = { placeName = ov.placeName, mobs = ov.mobs, notes = ov.notes }
    end
    local item = {
      name = name, tier = tier,
      place = loc and loc.placeName or nil,
      mobs = loc and loc.mobs or nil,
      notes = loc and loc.notes or nil,
      x = loc and loc.x, y = loc and loc.y,
      continent = continent, hasLoc = loc ~= nil,
    }
    item.easeRank, item.easeLabel = EaseOf(item)
    item.fate = PoolFate(name)
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

  -- BiS targets outrank everything: a trip for a tome the pool will disable is
  -- the last thing you should be doing with an evening.
  local FATE_RANK = { CHASE = 1, KEEP = 2, CUT = 4 }
  table.sort(list, function(a, b)
    local fa, fb = FATE_RANK[a.fate] or 2, FATE_RANK[b.fate] or 2
    if fa ~= fb then return fa < fb end
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
-- ORDERED overrides, checked FIRST and in this exact order. PLACE_ZONE below is
-- a plain hash scanned with pairs(), whose order is UNDEFINED -- so when two of
-- its keys both appear in a placeName the winner is arbitrary and can differ
-- between sessions. Anything ambiguous must live here, not there.
--
-- The case that forced this: "Caverns of Time - The Culling of Stratholme"
-- contains "stratholme", so it matched Eastern Plaguelands and ported a whole
-- continent away. Every Caverns of Time instance is THEMATICALLY set somewhere
-- else but its physical ENTRANCE is in Tanaris -- always route to Tanaris.
local PLACE_ZONE_FIRST = {
  { "caverns of time", "Tanaris" },
  { "culling of stratholme", "Tanaris" },
  { "old hillsbrad", "Tanaris" },          -- thematically Hillsbrad Foothills
  { "escape from durnholde", "Tanaris" },
  { "black morass", "Tanaris" },           -- thematically Blasted Lands
  { "opening of the dark portal", "Tanaris" },
  { "battle for mount hyjal", "Tanaris" },
  { "mount hyjal", "Tanaris" },
}

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
  -- Ordered overrides win outright (Caverns of Time etc; see PLACE_ZONE_FIRST).
  for _, e in ipairs(PLACE_ZONE_FIRST) do
    if string.find(low, e[1], 1, true) then return e[2] end
  end
  -- Landmark override next (raids, sub-zones). Unordered -- keep keys here
  -- mutually exclusive, or move the ambiguous one into PLACE_ZONE_FIRST.
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
    -- A degraded count must not look like a real one. The accurate path reads
    -- your tome CATALOG (every unowned keeper); the fallback only knows a small
    -- curated list, so the number silently collapses -- 19 became 2 -- while the
    -- old copy explained it in a parenthetical nobody reads. Say it loudly.
    if accurate then
      frame.status:SetText(GOLD .. #list .. R .. " keeper tome(s) to farm")
    else
      frame.status:SetText(EMBER .. "PARTIAL LIST -- this is not your real count."
        .. R .. "\n" .. DIM .. "Your tome catalog isn't loaded, so only " .. #list
        .. " curated target(s) can be checked. " .. R .. BRIGHT
        .. "Open the Echoes window once" .. R .. DIM .. ", then Refresh." .. R)
    end
  end

  -- Status is 1 line when accurate, 2-3 when warning -- anchor the list under
  -- whatever height it actually took, or the warning overlaps the first row.
  if frame.scroll then
    local top = 44 + (frame.status:GetStringHeight() or 16) + 12
    frame.scroll:ClearAllPoints()
    frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -top)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 14)
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
    -- Words, not colour: the fate has to survive a colourblind read.
    local fate = ""
    if item.fate == "CHASE" then
      fate = DIM .. "  -- CHASE: reroll toward this" .. R
    elseif item.fate == "KEEP" then
      fate = DIM .. "  -- KEEP: draft it, don't spend orbs on it" .. R
    elseif item.fate == "CUT" then
      fate = DIM .. "  -- CUT: the pool disables this; farming it is wasted" .. R
    end
    row.name:SetText("[" .. (MARK[item.tier] or "?") .. "]  " .. BRIGHT
      .. item.name .. R .. fate)
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
      -- Accept a string or a list -- upstream data (and overrides) supply both,
      -- and a bare table.concat on a string aborts the whole render.
      local mobsTxt
      if type(item.mobs) == "table" then mobsTxt = table.concat(item.mobs, ", ")
      elseif type(item.mobs) == "string" then mobsTxt = item.mobs end
      local mobs = mobsTxt and (DIM .. "kill: " .. mobsTxt .. R) or nil
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
  -- 360 keeps the two-line warning clear of the Refresh button on the right.
  frame.status:SetWidth(360); frame.status:SetJustifyH("LEFT")
  frame.status:SetSpacing(2)

  local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  refresh:SetWidth(80); refresh:SetHeight(20)
  refresh:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -34, -40)
  refresh:SetText("Refresh")
  refresh:SetScript("OnClick", function() F.Refresh() end)

  local scroll = CreateFrame("ScrollFrame", "PallyPilotFarmScroll", frame, "UIPanelScrollFrameTemplate")
  frame.scroll = scroll        -- Refresh re-anchors it under the status text
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
