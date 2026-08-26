-- PallyPilot BuildScore: "how optimized is my build, and how much better can
-- it get?" A composite 0-100 across the levers you actually control, plus a
-- ranked list of the improvement headroom. Colorblind-safe (numbers + letter
-- markers, no color-only signal).
--
-- Reads the catalog tiles (via TomeManager.AllTiles) for the keeper universe +
-- ownership, grantedPerks for run-echo quality, and the tome plan for pool
-- hygiene. Needs the Echoes window open (that's where the tiles live).
local PP = PallyPilot
local BS = PP.BuildScore

local GOLD = "|cffe0b352"
local BRIGHT = "|cfff6d888"
local DIM = "|cffb4a586"
local R = "|r"

local KEEP = { CORE = true, S = true, A = true }
local MARK = { CORE = "S+", S = "S", A = "A" }
local RANK = { CORE = 1, S = 2, A = 3 }

-- Weights sum to 1. Keeper pool is the biggest solo lever; Epic quality is ~10x
-- a Common proc so quality is weighted heavily too.
local W = { locks = 0.30, keeper = 0.40, quality = 0.20, hygiene = 0.10 }

local function Grade(n)
  if n >= 95 then return "A+" elseif n >= 90 then return "A"
  elseif n >= 85 then return "A-" elseif n >= 80 then return "B+"
  elseif n >= 75 then return "B" elseif n >= 70 then return "B-"
  elseif n >= 60 then return "C" else return "D" end
end

local function round(x) return math.floor(x + 0.5) end

-- Run-echo quality from grantedPerks: how many keepers are still sub-Epic.
-- Returns total, subEpic — or nil if no run data (e.g. fresh level 1 with only
-- locks loaded, which is fine — quality just drops out of the composite).
local function QualityStats()
  local gp = ProjectEbonhold and ProjectEbonhold.Perks
    and ProjectEbonhold.Perks.grantedPerks
  if not gp then return nil end
  local total, sub = 0, 0
  for key, val in pairs(gp) do
    if type(key) == "string" then
      local tier = PP.EchoAudit and PP.EchoAudit.ClassifyName
        and PP.EchoAudit.ClassifyName(key)
      if KEEP[tier] then
        total = total + 1
        local stacks = (type(val) == "table" and val[1] ~= nil) and val or { val }
        local minq
        for _, e in ipairs(stacks) do
          if type(e) == "table" and e.quality then
            if not minq or e.quality < minq then minq = e.quality end
          end
        end
        if minq and minq < 3 then sub = sub + 1 end
      end
    end
  end
  if total == 0 then return nil end
  return total, sub
end

function BS.Compute()
  local tiles, why = PP.TomeManager and PP.TomeManager.AllTiles
    and PP.TomeManager.AllTiles()
  if not tiles then return nil, why end

  -- Keeper pool: of every keeper-rated tome in this filter, how many owned.
  local universe, owned, missing = 0, 0, {}
  local filled = 0
  for _, t in ipairs(tiles) do
    if t.locked then filled = filled + 1 end
    if KEEP[t.tier] then
      universe = universe + 1
      if t.known then owned = owned + 1 else missing[#missing + 1] = t end
    end
  end
  local keeperScore = universe > 0 and (owned / universe) or 1
  table.sort(missing, function(a, b)
    if RANK[a.tier] ~= RANK[b.tier] then return RANK[a.tier] < RANK[b.tier] end
    return a.name < b.name
  end)

  -- Locks: filled permanent slots / unlocked slot count.
  local slots = (PP.EchoAudit and PP.EchoAudit.LockSlots
    and PP.EchoAudit.LockSlots()) or 6
  local locksScore = slots > 0 and (math.min(filled, slots) / slots) or 1

  -- Quality: keepers at Epic vs sub-Epic (run data).
  local qTotal, qSub = QualityStats()
  local qualityScore = qTotal and ((qTotal - qSub) / qTotal) or nil

  -- Hygiene: junk enabled + keepers wrongly disabled (from the tome plan).
  local junkOn, keepersOff = 0, 0
  local plan = PP.TomeManager and PP.TomeManager.Plan
    and PP.TomeManager.Plan("clean")
  if plan then junkOn = #plan.disable; keepersOff = #plan.reenable end
  local hygieneScore = math.max(0, 1 - (junkOn + keepersOff) / 20)

  -- Composite, renormalized if quality has no data.
  local dims = {
    { key = "locks", w = W.locks, s = locksScore },
    { key = "keeper", w = W.keeper, s = keeperScore },
    { key = "hygiene", w = W.hygiene, s = hygieneScore },
  }
  if qualityScore then
    dims[#dims + 1] = { key = "quality", w = W.quality, s = qualityScore }
  end
  local wsum, ssum = 0, 0
  for _, d in ipairs(dims) do wsum = wsum + d.w; ssum = ssum + d.w * d.s end
  local score = round(ssum / wsum * 100)

  return {
    score = score, grade = Grade(score),
    locksScore = locksScore, filled = filled, slots = slots,
    keeperScore = keeperScore, owned = owned, universe = universe,
    missing = missing,
    qualityScore = qualityScore, qTotal = qTotal, qSub = qSub,
    hygieneScore = hygieneScore, junkOn = junkOn, keepersOff = keepersOff,
    total = #tiles,
  }
end

local function pct(x) return round((x or 0) * 100) end

-- Ranked improvement lines (as a colored text block for the panel's scroll).
local function ImprovementText(r)
  local items = {}
  if #r.missing > 0 and r.keeperScore < 1 then
    items[#items + 1] = { p = round(W.keeper * (1 - r.keeperScore) * 100), kind = "farm" }
  end
  if r.qualityScore and r.qSub > 0 then
    items[#items + 1] = { p = round(W.quality * (r.qSub / r.qTotal) * 100), kind = "quality" }
  end
  if r.locksScore < 1 then
    items[#items + 1] = { p = round(W.locks * (1 - r.locksScore) * 100), kind = "locks" }
  end
  if (r.junkOn + r.keepersOff) > 0 then
    items[#items + 1] = { p = round(W.hygiene * (1 - r.hygieneScore) * 100), kind = "hygiene" }
  end
  table.sort(items, function(a, b) return a.p > b.p end)

  local t = {}
  if #items == 0 then
    t[#t + 1] = BRIGHT .. "Maxed for what you own." .. R .. "\n"
    t[#t + 1] = DIM .. "The way up now is farming new keeper tomes and pushing "
      .. "the ash tree (/pp ash)." .. R
    return table.concat(t)
  end
  for _, it in ipairs(items) do
    if it.kind == "farm" then
      t[#t + 1] = GOLD .. "+" .. it.p .. " pts  " .. R .. "Farm " .. #r.missing
        .. " keeper tome(s):" .. "\n"
      local shown = 0
      for _, m in ipairs(r.missing) do
        shown = shown + 1
        if shown > 10 then
          t[#t + 1] = DIM .. "     ...and " .. (#r.missing - 10) .. " more" .. R .. "\n"
          break
        end
        t[#t + 1] = "     [" .. (MARK[m.tier] or "?") .. "]  " .. m.name .. "\n"
      end
      t[#t + 1] = DIM .. "     -> Farm tomes button / \047pp farm to queue." .. R .. "\n\n"
    elseif it.kind == "quality" then
      t[#t + 1] = GOLD .. "+" .. it.p .. " pts  " .. R .. "Orb-fish " .. r.qSub
        .. " sub-Epic keeper(s) to Epic." .. "\n"
      t[#t + 1] = DIM .. "     -> \047pp fish at level 80." .. R .. "\n\n"
    elseif it.kind == "locks" then
      t[#t + 1] = GOLD .. "+" .. it.p .. " pts  " .. R .. "Fill " .. (r.slots - r.filled)
        .. " lock slot(s)." .. "\n"
      t[#t + 1] = DIM .. "     -> Echo audit for the best owned to lock." .. R .. "\n\n"
    elseif it.kind == "hygiene" then
      t[#t + 1] = GOLD .. "+" .. it.p .. " pts  " .. R .. "Fix the draw pool: "
        .. r.junkOn .. " junk to disable, " .. r.keepersOff .. " keepers to re-enable." .. "\n"
      t[#t + 1] = DIM .. "     -> Tome on/off button." .. R .. "\n\n"
    end
  end
  return table.concat(t)
end

-- ---------------------------------------------------------------------------
-- Panel UI. No chat spam — a movable window with score bars (bar LENGTH, not
-- color, encodes each value — colorblind-safe) and a scrollable to-do list.
local frame

local function MakeRow(parent, y)
  local row = {}
  row.label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.label:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, y)
  row.label:SetWidth(96); row.label:SetJustifyH("LEFT")

  row.barBg = parent:CreateTexture(nil, "ARTWORK")
  row.barBg:SetPoint("TOPLEFT", parent, "TOPLEFT", 124, y - 1)
  row.barBg:SetWidth(240); row.barBg:SetHeight(14)
  row.barBg:SetTexture(0, 0, 0, 0.5)

  row.fill = parent:CreateTexture(nil, "OVERLAY")
  row.fill:SetPoint("LEFT", row.barBg, "LEFT", 0, 0)
  row.fill:SetHeight(14)
  row.fill:SetTexture(0.85, 0.69, 0.32, 1)

  row.val = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.val:SetPoint("CENTER", row.barBg, "CENTER", 0, 0)

  row.detail = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.detail:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, y - 18)
  row.detail:SetWidth(400); row.detail:SetJustifyH("LEFT")
  return row
end

function BS.Init()
  if frame then return end
  frame = CreateFrame("Frame", "PallyPilotScoreFrame", UIParent)
  frame:SetWidth(440); frame:SetHeight(520)
  frame:SetPoint("CENTER", UIParent, "CENTER", 40, 0)
  frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 28,
    insets = { left = 10, right = 10, top = 10, bottom = 10 },
  })

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -16)
  title:SetText(GOLD .. "PallyPilot — Build Score" .. R)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)

  local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  refresh:SetWidth(70); refresh:SetHeight(20)
  refresh:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -14)
  refresh:SetText("Refresh")
  refresh:SetScript("OnClick", function() BS.Refresh() end)

  frame.score = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  frame.score:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -44)

  frame.note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.note:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -78)
  frame.note:SetWidth(400); frame.note:SetJustifyH("LEFT")
  frame.note:SetText(DIM .. "100 = you own and run every keeper available in "
    .. "this view. Farming new tomes raises the ceiling." .. R)

  frame.rows = {
    locks = MakeRow(frame, -108),
    keeper = MakeRow(frame, -150),
    quality = MakeRow(frame, -192),
    hygiene = MakeRow(frame, -234),
  }
  frame.rows.locks.label:SetText("Locks")
  frame.rows.keeper.label:SetText("Keeper pool")
  frame.rows.quality.label:SetText("Quality")
  frame.rows.hygiene.label:SetText("Hygiene")

  local ih = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ih:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -272)
  ih:SetText(GOLD .. "Improvement possible" .. R)
  frame.improveHead = ih

  local scroll = CreateFrame("ScrollFrame", "PallyPilotScoreScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -292)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 18)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetWidth(384); content:SetHeight(10)
  scroll:SetScrollChild(content)
  frame.improve = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.improve:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  frame.improve:SetWidth(380); frame.improve:SetJustifyH("LEFT"); frame.improve:SetJustifyV("TOP")
  frame.improve:SetSpacing(2)
  frame.improveContent = content

  frame:Hide()
end

local function SetBar(row, score, valText, dim)
  if score == nil then
    row.fill:Hide()
    row.val:SetText(DIM .. "n/a" .. R)
  else
    row.fill:Show()
    row.fill:SetWidth(math.max(1, 240 * score))
    row.val:SetText((valText or pct(score)) .. "")
  end
  row.detail:SetText(DIM .. (dim or "") .. R)
end

function BS.Refresh()
  if not frame then return end
  local r, why = BS.Compute()
  if not r then
    frame.score:SetText(GOLD .. "No data" .. R)
    frame.note:SetText(DIM .. ((why == "closed" or why == "empty")
      and "Open the Echoes window (All Echoes tab; filter = All classes for the "
        .. "full picture), then hit Refresh."
      or "Couldn't read the catalog.") .. R)
    for _, key in ipairs({ "locks", "keeper", "quality", "hygiene" }) do
      SetBar(frame.rows[key], 0, "-", "")
    end
    frame.improve:SetText("")
    if frame.improveContent then frame.improveContent:SetHeight(10) end
    return
  end
  frame.score:SetText(GOLD .. r.score .. R .. DIM .. " / 100   " .. R
    .. BRIGHT .. "[" .. r.grade .. "]" .. R)
  frame.note:SetText(DIM .. "100 = you own and run every keeper available in "
    .. "this view. Farming new tomes raises the ceiling." .. R)

  SetBar(frame.rows.locks, r.locksScore, pct(r.locksScore),
    r.filled .. "/" .. r.slots .. " permanent slots filled")
  SetBar(frame.rows.keeper, r.keeperScore, pct(r.keeperScore),
    r.owned .. " of " .. r.universe .. " keeper tomes owned")
  SetBar(frame.rows.quality, r.qualityScore, r.qualityScore and pct(r.qualityScore),
    r.qualityScore and ((r.qTotal - r.qSub) .. " of " .. r.qTotal
      .. " run keepers at Epic") or "no run loaded — check at level 80")
  SetBar(frame.rows.hygiene, r.hygieneScore, pct(r.hygieneScore),
    r.junkOn .. " junk enabled, " .. r.keepersOff .. " keepers disabled")

  frame.improve:SetText(ImprovementText(r))
  if frame.improveContent then
    frame.improveContent:SetHeight((frame.improve:GetHeight() or 200) + 20)
  end
end

function BS.Toggle()
  if not frame then BS.Init() end
  if frame:IsShown() then frame:Hide() else BS.Refresh(); frame:Show() end
end

-- Command / button entry point: always show fresh (no chat output). Close via
-- the panel's X.
function BS.Report()
  if not frame then BS.Init() end
  BS.Refresh()
  frame:Show()
  frame:Raise()
end
