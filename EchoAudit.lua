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

-- EbonholdHub's owned set includes quality-suffixed variants of the same echo
-- ("adaptive power - epic"). Strip the suffix so they match the build ratings.
local QUALITIES = {
  epic = true, rare = true, uncommon = true, common = true,
  legendary = true, artifact = true,
}
local function StripQuality(norm)
  local base, q = string.match(norm, "^(.-)%s*%-%s*(%a+)$")
  if base and q and QUALITIES[string.lower(q)] then
    return base, string.lower(q)
  end
  return norm, nil
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
  for n in pairs(B.catalog or {}) do add(n) end
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

-- Priority index within the build: curated list position beats alphabetical.
-- Lower = more valuable. Catalog-only names fall after all curated ones.
local tierOrderCache
local function TierOrderIndex(base)
  if not tierOrderCache then
    tierOrderCache = {}
    local i = 0
    for _, list in ipairs({ PP.Build.locked, PP.Build.tiers.S,
                            PP.Build.tiers.A, PP.Build.tiers.B }) do
      for _, n in ipairs(list) do
        i = i + 1
        local k = Norm(n)
        if not tierOrderCache[k] then tierOrderCache[k] = i end
      end
    end
  end
  return tierOrderCache[base] or 9999
end

-- Full-catalog lookup (BuildData.catalog), normalized keys, built lazily.
local catalogNorm
local function CatalogTier(norm)
  if not catalogNorm then
    catalogNorm = {}
    for n, tier in pairs(PP.Build.catalog or {}) do
      catalogNorm[Norm(n)] = tier
    end
  end
  return catalogNorm[norm]
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
  local ct = CatalogTier(norm)
  if ct and ct ~= "F" then return ct end
  return "REROLL"
end

-- Full audit: buckets of display names, sorted, plus counts. Quality-suffixed
-- variants ("adaptive power - epic") merge into one base entry that lists its
-- owned qualities.
function A.Compute()
  local owned = OwnedSet()
  if not owned then return nil end
  local names = DisplayNames()
  local merged = {}  -- base norm -> { qualities = {..}, hasBase = bool }
  for norm in pairs(owned) do
    local base, quality = StripQuality(norm)
    local e = merged[base]
    if not e then e = { qualities = {} }; merged[base] = e end
    if quality then
      e.qualities[#e.qualities + 1] = quality
    else
      e.hasBase = true
    end
  end
  local buckets = { CORE = {}, S = {}, A = {}, B = {}, C = {},
                    DISABLE = {}, REROLL = {} }
  local ordOf = {}
  local total = 0
  for base, e in pairs(merged) do
    total = total + 1
    local verdict = Classify(base)
    local display = names[base] or TitleCase(base)
    if #e.qualities > 0 then
      table.sort(e.qualities)
      display = display .. DIM .. " (" .. table.concat(e.qualities, ", ") .. ")" .. R
    end
    ordOf[display] = TierOrderIndex(base)
    table.insert(buckets[verdict], display)
  end
  -- Curated priority order within each bucket, alphabetical among peers.
  for _, list in pairs(buckets) do
    table.sort(list, function(a, b)
      if ordOf[a] ~= ordOf[b] then return (ordOf[a] or 9999) < (ordOf[b] or 9999) end
      return a < b
    end)
  end
  return buckets, total
end

-- "Maximize what I have": the best owned echoes to LOCK right now — owned
-- core first, then S, then A, then B — sized to the permanent slots the
-- player has actually unlocked (/pp locks <n>).
function A.LockSlots()
  -- Server truth first (EBH queries GetMaximumPermanentEchoes live);
  -- the manual /pp locks setting is only a fallback.
  local EB = EbonholdHub and EbonholdHub.Build
  if EB and EB.GetLockedSlotCount then
    local ok, n = pcall(EB.GetLockedSlotCount)
    if ok and type(n) == "number" and n > 0 then return n end
  end
  return (PP.db and PP.db.options and PP.db.options.lockSlots) or 5
end

function A.LockNow(buckets)
  local pick, max = {}, A.LockSlots()
  for _, key in ipairs({ "CORE", "S", "A", "B" }) do
    for _, name in ipairs(buckets[key]) do
      if #pick >= max then return pick end
      pick[#pick + 1] = { name = name, tier = key }
    end
  end
  return pick
end

-- ---------------------------------------------------------------------------
-- Public lookups for EchoFlow (tooltips, tile badges, reroll queue).
local nameCache, nameCacheAt = nil, 0
local function CachedNames()
  local now = GetTime and GetTime() or 0
  if not nameCache or (now - nameCacheAt) > 10 then
    nameCache = DisplayNames(); nameCacheAt = now
  end
  return nameCache
end

-- Verdict for any display text (quality suffixes ok). Returns nil for text
-- that isn't a known echo, so tooltip hooks stay quiet on ordinary tooltips.
function A.VerdictFor(text)
  if not text or text == "" then return nil end
  local norm = Norm(text)
  local base = StripQuality(norm)
  local names = CachedNames()
  local owned = OwnedSet()
  local known = names[base] ~= nil
    or (owned and (owned[norm] or owned[base])) or false
  if not known then return nil end
  return Classify(base), names[base] or TitleCase(base)
end

-- Match possibly-truncated tile text ("Broodmot...") to a known echo.
function A.MatchDisplay(text)
  if not text or text == "" then return nil end
  local norm = Norm(text)
  local base = StripQuality(norm)
  local names = CachedNames()
  if names[base] then return names[base], Classify(base) end
  local prefix = string.match(norm, "^(.-)%.%.%.$")
  if prefix and prefix ~= "" then
    local hit
    for key, display in pairs(names) do
      if string.sub(key, 1, string.len(prefix)) == prefix then
        if hit then return nil end -- ambiguous
        hit = { display, key }
      end
    end
    if hit then return hit[1], Classify(hit[2]) end
  end
  return nil
end

-- Plain (uncolored) reroll queue: owned, unrated, junk.
function A.RerollList()
  local owned = OwnedSet()
  if not owned then return {} end
  local names, seen, out = CachedNames(), {}, {}
  for norm in pairs(owned) do
    local base = StripQuality(norm)
    if not seen[base] then
      seen[base] = true
      if Classify(base) == "REROLL" then
        out[#out + 1] = names[base] or TitleCase(base)
      end
    end
  end
  table.sort(out)
  return out
end

-- Cheap change signature for "did I just learn something?" polling.
function A.OwnedSignature()
  local owned = OwnedSet()
  if not owned then return nil end
  local n = 0
  for _ in pairs(owned) do n = n + 1 end
  return n
end

-- Best N owned echoes as PLAIN display names (no colors/quality tags) —
-- verdict order CORE > S > A > B. Used by HubSync's lockedEchoes.
function A.BestOwned(n)
  local owned = OwnedSet()
  if not owned then return {} end
  local names, seen = CachedNames(), {}
  local buckets = { CORE = {}, S = {}, A = {}, B = {} }
  for norm in pairs(owned) do
    local base = StripQuality(norm)
    if not seen[base] then
      seen[base] = true
      local v = Classify(base)
      if buckets[v] then
        table.insert(buckets[v], names[base] or TitleCase(base))
      end
    end
  end
  local ordOf = {}
  for _, l in pairs(buckets) do
    for _, nm in ipairs(l) do ordOf[nm] = ordOf[nm] or TierOrderIndex(Norm(nm)) end
    table.sort(l, function(a, b)
      if ordOf[a] ~= ordOf[b] then return (ordOf[a] or 9999) < (ordOf[b] or 9999) end
      return a < b
    end)
  end
  local out = {}
  for _, key in ipairs({ "CORE", "S", "A", "B" }) do
    for _, nm in ipairs(buckets[key]) do
      if #out >= n then return out end
      out[#out + 1] = nm
    end
  end
  return out
end

-- Level-1 pool curation: owned echoes feed the run's draw pool, and
-- disabling (right-click, level 1 only) removes them from it. Optimal pool =
-- the best ~(active cap + margin) owned echoes: breadth stays maxed, but
-- every draw offers something worth taking. Returns keep, disable lists
-- (plain display names, priority-ordered).
-- mode "farm" (community doctrine, Sanavesa/Qvintus): disable EVERYTHING
-- except your locks and Epic-quality owned echoes — a near-empty pool means
-- every draw during a 1-80 farm leg is a wanted echo. mode "raid" (default)
-- keeps the best keepN for Adaptive breadth.
function A.DisablePlan(keepN, mode)
  keepN = keepN or (PP.db and PP.db.options and PP.db.options.poolSize) or 82
  local owned = OwnedSet()
  if not owned then return nil end
  if mode == "farm" then
    local names = CachedNames()
    local keepSet, keep, disable = {}, {}, {}
    for _, nm in ipairs(A.BestOwned(A.LockSlots())) do keepSet[Norm(nm)] = true end
    -- Epic-quality ownership shows as "<base> - epic" keys.
    for norm in pairs(owned) do
      local base, q = StripQuality(norm)
      if q == "epic" then keepSet[base] = true end
    end
    local seen, disableSet = {}, {}
    for norm in pairs(owned) do
      local base = StripQuality(norm)
      if not seen[base] then
        seen[base] = true
        local display = names[base] or TitleCase(base)
        if keepSet[base] then
          keep[#keep + 1] = display
        else
          disable[#disable + 1] = display
          disableSet[base] = true
        end
      end
    end
    table.sort(keep); table.sort(disable)
    return keep, disable, disableSet
  end
  local names, seen = CachedNames(), {}
  local buckets = { CORE = {}, S = {}, A = {}, B = {}, C = {},
                    DISABLE = {}, REROLL = {} }
  for norm in pairs(owned) do
    local base = StripQuality(norm)
    if not seen[base] then
      seen[base] = true
      local v = Classify(base)
      local display = names[base] or TitleCase(base)
      if buckets[v] then
        table.insert(buckets[v], display)
      end
    end
  end
  local ordOf = {}
  for _, l in pairs(buckets) do
    for _, nm in ipairs(l) do ordOf[nm] = TierOrderIndex(Norm(nm)) end
    table.sort(l, function(a, b)
      if ordOf[a] ~= ordOf[b] then return (ordOf[a] or 9999) < (ordOf[b] or 9999) end
      return a < b
    end)
  end
  local keep, disable, disableSet = {}, {}, {}
  for _, key in ipairs({ "CORE", "S", "A", "B", "C" }) do
    for _, nm in ipairs(buckets[key]) do
      if #keep < keepN then
        keep[#keep + 1] = nm
      else
        disable[#disable + 1] = nm .. " (" .. key .. ")"
        disableSet[Norm(nm)] = true
      end
    end
  end
  -- Traps and rated-junk always go on the disable list.
  for _, nm in ipairs(buckets.DISABLE) do
    disable[#disable + 1] = nm .. " (trap)"
    disableSet[Norm(nm)] = true
  end
  for _, nm in ipairs(buckets.REROLL) do
    disable[#disable + 1] = nm .. " (junk)"
    disableSet[Norm(nm)] = true
  end
  return keep, disable, disableSet
end

-- Snapshot copy of the owned set, for precise added/removed diffing.
function A.OwnedCopy()
  local owned = OwnedSet()
  if not owned then return nil end
  local c = {}
  for k in pairs(owned) do c[k] = true end
  return c
end

local SECTIONS = {
  { key = "REROLL", color = EMBER, title = "Reroll / feed to an Orb",
    note = "Not in the build. These are your reroll currency — no build slot wants them." },
  { key = "DISABLE", color = EMBER, title = "Disable / banish",
    note = "Actively bad for this build. Turn them off; banish from draws when offered." },
  { key = "C", color = DIM, title = "Breadth filler — keep active",
    note = "No build value on their own, but every unique active echo is +1% "
      .. "damage via Adaptive Power. Never reroll these below the active cap." },
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
    .. #buckets.B .. " B, " .. #buckets.C .. " C, " .. #buckets.DISABLE
    .. " to disable, " .. #buckets.REROLL .. " unrated/reroll." .. R .. "\n"

  -- Maximize current potential: best six OWNED echoes to lock today.
  local lockNow = A.LockNow(buckets)
  if #lockNow > 0 then
    t[#t+1] = "\n" .. GOLD .. "LOCK NOW — BEST " .. A.LockSlots()
      .. " YOU OWN" .. R .. "\n"
    t[#t+1] = DIM .. "Your current-potential lock set, from what you actually have. "
      .. "As farmed tomes land, better echoes push weaker ones out — new learns are "
      .. "announced in chat with their verdict." .. R .. "\n"
    for _, p in ipairs(lockNow) do
      local tag = (p.tier == "CORE") and (GOLD .. "core" .. R)
        or (p.tier == "S" and (BRIGHT .. "S" .. R))
        or (p.tier == "A" and (ASH .. "A" .. R))
        or (DIM .. "B" .. R)
      t[#t+1] = "  " .. GOLD .. "* " .. R .. p.name .. "  [" .. tag .. "]" .. "\n"
    end
  end
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
  t[#t+1] = VERD .. "The full 323-echo catalog is rated (PerkDatabase dump). Reroll "
    .. "now means rated-junk, not unknown. Disagree with a verdict? Ratings live in "
    .. "BuildData.lua." .. R .. "\n"
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

-- ---------------------------------------------------------------------------
-- Upgrade watcher: every 30s, diff the live owned set against the saved
-- snapshot. New learns are announced in chat with their build verdict, so
-- farmed tomes report in the moment they're read.
local VERDICT_LABEL = {
  CORE = GOLD .. "CORE — lock it" .. R,
  S = BRIGHT .. "S tier — KEEP (lock candidate)" .. R,
  A = ASH .. "A tier — keep" .. R,
  B = DIM .. "B tier — fine" .. R,
  C = DIM .. "C — breadth filler (+1% Adaptive)" .. R,
  DISABLE = EMBER .. "DISABLE — bad for the build" .. R,
  REROLL = EMBER .. "unrated — reroll fodder unless it reads strong" .. R,
}

local function Snapshot()
  return PP.db and PP.db.audit
end

local function CheckForNewEchoes()
  local owned = OwnedSet()
  local snap = Snapshot()
  if not owned or not snap then return end
  if not snap.known then snap.known = {} end
  -- First run: seed silently instead of announcing the whole collection.
  if not snap.seeded then
    for norm in pairs(owned) do snap.known[norm] = true end
    snap.seeded = true
    return
  end
  local names
  for norm in pairs(owned) do
    if not snap.known[norm] then
      snap.known[norm] = true
      names = names or DisplayNames()
      local base = StripQuality(norm)
      local verdict = Classify(base)
      local display = names[base] or TitleCase(base)
      PP.print("New echo: " .. BRIGHT .. display .. R .. " — "
        .. (VERDICT_LABEL[verdict] or verdict))
      if A.onNewEcho then pcall(A.onNewEcho, display, verdict) end
      if verdict == "CORE" or verdict == "S" then
        PP.print(VERD .. "  That's an upgrade — /pp audit to see your refreshed Lock Now six." .. R)
      end
      if frame and frame:IsShown() then A.Refresh() end
    end
  end
end

local watch = CreateFrame("Frame")
watch.elapsed = 0
watch:RegisterEvent("PLAYER_LOGIN")
watch:SetScript("OnEvent", function(self)
  self:SetScript("OnUpdate", function(f, elapsed)
    f.elapsed = f.elapsed + elapsed
    if f.elapsed < 30 then return end
    f.elapsed = 0
    PP.safeCall(CheckForNewEchoes)
  end)
  -- Seed shortly after login once EbonholdHub has its data up.
  f = self
  f.elapsed = 25
end)
