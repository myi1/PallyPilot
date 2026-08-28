-- PallyPilot GearAudit: per-slot affix verdicts for equipped gear.
-- Ebonhold affix format (learned from live tooltips): the item name carries
-- "of <Affix> <RomanRank>" and the tooltip has a line tagged "@affix@".
local PP = PallyPilot
local GA = PP.GearAudit

local GOLD = "|cffe0b352"
local BRIGHT = "|cfff6d888"
local DIM = "|cffb4a586"
local EMBER = "|cffd9694a"
local VERD = "|cff8aa96a"
local R = "|r"

local frame, content

local SLOT_NAMES = {
  [1]="Head",[2]="Neck",[3]="Shoulder",[4]="Shirt",[5]="Chest",[6]="Waist",
  [7]="Legs",[8]="Feet",[9]="Wrist",[10]="Hands",[11]="Ring 1",[12]="Ring 2",
  [13]="Trinket 1",[14]="Trinket 2",[15]="Back",[16]="Main Hand",[17]="Off Hand",
  [18]="Ranged",[19]="Tabard",
}

-- Survival-first school (AotC I phase): acceptable affixes per slot,
-- preferred first. From B.affixSurvival slot lists.
local SLOT_TARGETS = {
  [1] = { "Ironhide" },
  [2] = { "Overwhelming Force" },
  [3] = { "Ironhide" },
  [4] = { "Iron Will" },
  [5] = { "Iron Will" },
  [6] = { "Fortified by Pain" },
  [7] = { "Ironhide" },
  [8] = { "Iron Will" },
  [9] = { "Iron Will" },
  [10] = { "Fortified by Pain" },
  [11] = { "Ironhide", "Fortified by Pain" },
  [12] = { "Ironhide", "Fortified by Pain" },
  [13] = { "Overwhelming Force" },
  [14] = { "Overwhelming Force" },
  [15] = { "Overwhelming Force" },
  [16] = { "Iron Will" },
  [17] = { "Fortified by Pain", "Iron Will" },
  [18] = { "Ironhide" },
  [19] = { "Overwhelming Force" },
}

local ROMAN = { I=1, II=2, III=3, IV=4, V=5, VI=6, VII=7, VIII=8, IX=9, X=10 }

-- Parse "Anything of <Affix> <Roman>" (last 'of' wins:
-- "Greaves of Ancient Evil of Ironhide III" -> Ironhide, 3).
local function ParseAffix(itemName)
  if not itemName then return nil end
  local affix, roman = string.match(itemName, "^.*%s[oO]f%s(.-)%s([IVX]+)$")
  if affix and ROMAN[roman] then return affix, ROMAN[roman] end
  return nil
end

local function HasAffixLine(tipLines)
  for _, l in ipairs(tipLines) do
    if string.find(l, "@affix@", 1, true) then return l end
  end
  return nil
end

local function ScanSlot(slot)
  local link = GetInventoryItemLink("player", slot)
  if not link then return nil end
  local tip = PPScanTooltip
    or CreateFrame("GameTooltip", "PPScanTooltip", nil, "GameTooltipTemplate")
  tip:SetOwner(UIParent, "ANCHOR_NONE")
  tip:ClearLines()
  tip:SetInventoryItem("player", slot)
  local lines = {}
  for i = 2, tip:NumLines() do
    local fsL = _G["PPScanTooltipTextLeft" .. i]
    local txt = fsL and fsL:GetText()
    if txt and txt ~= "" then lines[#lines + 1] = txt end
  end
  local name, _, _, ilvl = GetItemInfo(link)
  -- GetItemInfo's 4th return is item level in 3.3.5.
  return { name = name, ilvl = ilvl, lines = lines }
end

-- One slot's verdict: status is "ok" | "rank" | "swap" | "missing".
local function Judge(slot, item)
  local targets = SLOT_TARGETS[slot]
  if not targets then return nil end
  local affix, rank = ParseAffix(item.name)
  if not affix and HasAffixLine(item.lines) then
    -- Affix line without a name suffix — show what the line says.
    affix, rank = "?", 0
  end
  local out = { slot = slot, item = item.name, ilvl = item.ilvl,
                affix = affix, rank = rank, want = targets[1] }
  if not affix then
    out.status = "missing"
    return out
  end
  for _, t in ipairs(targets) do
    if affix == t then
      out.status = (rank and rank < 3) and "rank" or "ok"
      return out
    end
  end
  out.status = "swap"
  return out
end

function GA.Compute()
  local results = {}
  for slot = 1, 19 do
    local item = ScanSlot(slot)
    if item then
      local j = Judge(slot, item)
      if j then results[#results + 1] = j end
    end
  end
  return results
end

-- ---------------------------------------------------------------------------
-- Unified Gear view: per-slot health (item level + affix + enchant + gem),
-- worst-first, with a kit score, a top-3 fixes strip, and click-to-expand
-- recommendations. Colorblind: every status is a bracketed WORD, not a color.

local ASH = "|cff9db3bd"
local gearRows, sortMode, expandedSlot = {}, "priority", nil

-- Paperdoll display order (skip shirt 4 / tabard 19).
local PD_ORDER = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }

-- Merge affix verdicts (Compute) with enchant/gem gaps (GearOpt.SlotReport).
local function CollectRows()
  local affix = {}
  for _, r in ipairs(GA.Compute()) do affix[r.slot] = r end
  local gaps = (PP.GearOpt and PP.GearOpt.SlotReport and PP.GearOpt.SlotReport()) or {}
  local rows, sum, cnt, gapN, okChk, totChk = {}, 0, 0, 0, 0, 0
  for _, slot in ipairs(PD_ORDER) do
    local a, g = affix[slot], gaps[slot]
    if a or g then
      local ilvl = (a and a.ilvl) or (g and g.ilvl) or 0
      local affixGap = (a and (a.status == "missing" or a.status == "swap")) or false
      local affixLow = (a and a.status == "rank") or false
      local encMiss = (g and g.encMiss) or false
      local empty = (g and g.emptyGems) or 0
      if a then totChk = totChk + 1; if not (affixGap or affixLow) then okChk = okChk + 1 end end
      if g and g.enchantable then totChk = totChk + 1; if not encMiss then okChk = okChk + 1 end end
      if g and (g.sockets or 0) > 0 then totChk = totChk + 1; if empty == 0 then okChk = okChk + 1 end end
      local n = (affixGap and 1 or 0) + (encMiss and 1 or 0) + (empty > 0 and 1 or 0)
      gapN = gapN + n
      rows[#rows + 1] = {
        slot = slot, name = SLOT_NAMES[slot] or ("slot " .. slot),
        item = a and a.item, ilvl = ilvl,
        affix = a and a.affix, rank = a and a.rank, affixStatus = a and a.status,
        want = a and a.want, affixGap = affixGap, affixLow = affixLow,
        encMiss = encMiss, encRec = g and g.encRec, encSrc = g and g.encSrc,
        enchantable = g and g.enchantable, empty = empty,
        sockets = (g and g.sockets) or 0, gaps = n,
      }
      if ilvl > 0 then sum = sum + ilvl; cnt = cnt + 1 end
    end
  end
  local avg = cnt > 0 and (sum / cnt) or 0
  for _, r in ipairs(rows) do
    r.lag = avg - r.ilvl
    r.prio = r.gaps * 1000 + (r.affixLow and 200 or 0) + (r.lag > 0 and r.lag or 0)
  end
  local score = totChk > 0 and math.floor(100 * okChk / totChk + 0.5) or 100
  return rows, avg, gapN, score
end

-- Colorblind bracketed markers (word leads; color is redundant).
local function AffixMark(r)
  if not (r.affix or r.affixStatus) then return DIM .. "[-]" .. R end
  if r.affixGap then return EMBER .. "[none]" .. R end
  local txt = (r.affix or "?") .. (r.rank and r.rank > 0 and (" " .. r.rank) or "")
  if r.affixLow then return ASH .. "[" .. txt .. " low]" .. R end
  return VERD .. "[" .. txt .. "]" .. R
end
local function EnchMark(r)
  if r.encMiss then return EMBER .. "[none]" .. R end
  if r.enchantable then return VERD .. "[ok]" .. R end
  return DIM .. "[-]" .. R
end
local function GemMark(r)
  if (r.sockets or 0) == 0 then return DIM .. "[-]" .. R end
  if r.empty > 0 then return EMBER .. "[" .. r.empty .. " empty]" .. R end
  return VERD .. "[ok]" .. R
end

local function GetRow(i)
  local row = gearRows[i]
  if row then return row end
  row = CreateFrame("Button", nil, content)
  row:SetWidth(416); row:SetHeight(22)
  row.hl = row:CreateTexture(nil, "BACKGROUND")
  row.hl:SetAllPoints(); row.hl:SetTexture(1, 1, 1, 0.05); row.hl:Hide()
  row:SetScript("OnEnter", function(s) s.hl:Show() end)
  row:SetScript("OnLeave", function(s) s.hl:Hide() end)
  local function fs(x, w, font)
    local f = row:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    f:SetPoint("TOPLEFT", row, "TOPLEFT", x, -4); f:SetWidth(w); f:SetJustifyH("LEFT")
    return f
  end
  row.cName = fs(4, 92)
  row.cIlvl = fs(98, 46)
  row.cAffix = fs(146, 124)
  row.cEnch = fs(272, 78)
  row.cGem = fs(352, 62)
  row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.detail:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -22)
  row.detail:SetWidth(396); row.detail:SetJustifyH("LEFT"); row.detail:SetSpacing(2)
  gearRows[i] = row
  return row
end

function GA.Refresh()
  if not frame or not content then return end
  local rows, avg, gapN, score = CollectRows()
  if sortMode == "priority" then
    table.sort(rows, function(a, b)
      if a.prio ~= b.prio then return a.prio > b.prio end
      return a.slot < b.slot
    end)
  end

  frame.gsScore:SetText(GOLD .. score .. R .. DIM .. " /100" .. R)
  frame.gsBar:SetWidth(math.max(1, 150 * score / 100))
  frame.gsSub:SetText(DIM .. "avg ilvl " .. R .. BRIGHT .. math.floor(avg + 0.5) .. R
    .. DIM .. "  ·  " .. R .. (gapN > 0 and EMBER or VERD) .. gapN .. R
    .. DIM .. " gap" .. (gapN == 1 and "" or "s") .. R)
  frame.sortBtn:SetText(sortMode == "priority" and "Sort: Priority" or "Sort: Paperdoll")

  -- Top-3 fixes (always by priority, regardless of the list sort).
  local byPrio = {}
  for _, r in ipairs(rows) do byPrio[#byPrio + 1] = r end
  table.sort(byPrio, function(a, b) return a.prio > b.prio end)
  local top = {}
  for i = 1, math.min(3, #byPrio) do
    local r = byPrio[i]
    if r.gaps > 0 or r.affixLow or r.lag >= 13 then
      top[#top + 1] = BRIGHT .. i .. "·" .. r.name .. R
    end
  end
  frame.top3:SetText(#top > 0 and (DIM .. "Fix first:  " .. R .. table.concat(top, DIM .. "   " .. R))
    or (VERD .. "No gaps — every slot is kitted." .. R))

  for _, r in ipairs(gearRows) do r:Hide() end
  local y = 0
  for i, r in ipairs(rows) do
    local row = GetRow(i)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    row.cName:SetText(BRIGHT .. r.name .. R)
    local lag = (r.lag and r.lag >= 6 and r.ilvl > 0) and (EMBER .. " -" .. math.floor(r.lag + 0.5) .. R) or ""
    row.cIlvl:SetText(r.ilvl > 0 and (DIM .. r.ilvl .. R .. lag) or (DIM .. "—" .. R))
    row.cAffix:SetText(AffixMark(r))
    row.cEnch:SetText(EnchMark(r))
    row.cGem:SetText(GemMark(r))
    local slot = r.slot
    row:SetScript("OnClick", function()
      expandedSlot = (expandedSlot == slot) and nil or slot
      GA.Refresh()
    end)
    if expandedSlot == r.slot then
      local d = {}
      d[#d + 1] = DIM .. (r.item or "(empty)") .. R
      if r.affixGap then d[#d + 1] = EMBER .. "Affix → " .. (r.want or "?") .. R
      elseif r.affixLow then d[#d + 1] = ASH .. "Affix → raise rank (endgame runs to VI)" .. R end
      if r.encMiss then d[#d + 1] = EMBER .. "Enchant → " .. (r.encRec or "add one") .. R end
      if r.empty > 0 then d[#d + 1] = EMBER .. "Gems → fill " .. r.empty
        .. " socket" .. (r.empty > 1 and "s" or "") .. " (Haste; buckle on waist)" .. R end
      d[#d + 1] = DIM .. "Base upgrades: /pp upgrades for this slot's source." .. R
      row.detail:SetText(table.concat(d, "\n"))
      row.detail:Show()
      row:SetHeight(24 + (row.detail:GetStringHeight() or 12) + 6)
    else
      row.detail:SetText(""); row.detail:Hide()
      row:SetHeight(22)
    end
    row:Show()
    y = y + row:GetHeight() + 1
  end
  content:SetHeight(math.max(10, y + 4))
end

function GA.Init()
  if frame then return end
  frame = CreateFrame("Frame", "PallyPilotGearFrame", UIParent)
  frame:SetWidth(480); frame:SetHeight(560)
  frame:SetPoint("CENTER", UIParent, "CENTER", -30, 0)
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
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
  title:SetText(GOLD .. "Gear — health & upgrades" .. R)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
  frame.ppClose = close

  -- Header: kit score + bar, avg/gaps, sort toggle.
  frame.gsScore = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.gsScore:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -40)
  frame.gsBar = frame:CreateTexture(nil, "ARTWORK")
  frame.gsBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -62); frame.gsBar:SetHeight(4)
  frame.gsBar:SetTexture(0.878, 0.702, 0.322, 1)
  local barBg = frame:CreateTexture(nil, "BACKGROUND")
  barBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -62); barBg:SetWidth(150); barBg:SetHeight(4)
  barBg:SetTexture(1, 1, 1, 0.08)
  frame.gsSub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.gsSub:SetPoint("TOPLEFT", frame, "TOPLEFT", 190, -44)

  frame.sortBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.sortBtn:SetWidth(104); frame.sortBtn:SetHeight(20)
  frame.sortBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -34, -40)
  frame.sortBtn:SetText("Sort: Priority")
  frame.sortBtn:SetScript("OnClick", function()
    sortMode = (sortMode == "priority") and "paperdoll" or "priority"
    GA.Refresh()
  end)

  frame.top3 = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.top3:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -78)
  frame.top3:SetWidth(430); frame.top3:SetJustifyH("LEFT")

  -- Column header — labels aligned to the row columns (frame x = 18 + row x).
  local function ColLabel(x, text)
    local f = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -98)
    f:SetText("|cff85817a" .. text .. "|r")
  end
  ColLabel(22, "SLOT"); ColLabel(116, "ILVL"); ColLabel(164, "AFFIX")
  ColLabel(290, "ENCH"); ColLabel(370, "GEM")

  local scroll = CreateFrame("ScrollFrame", "PallyPilotGearScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -112)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 16)
  content = CreateFrame("Frame", nil, scroll)
  content:SetWidth(420); content:SetHeight(10)
  scroll:SetScrollChild(content)

  frame:Hide()
end

-- Embeddable: return the frame (built on demand) for the console shell.
function GA.GetFrame()
  if not frame then GA.Init() end
  return frame
end

function GA.Toggle()
  if PP.Dashboard and PP.Dashboard.Open then PP.Dashboard.Open("gear") end
end

-- ---------------------------------------------------------------------------
-- In-place integrations: verdict dots on the character sheet's slot buttons
-- and advice lines on equipped-item tooltips.
local SLOT_BUTTON = {
  [1]="CharacterHeadSlot",[2]="CharacterNeckSlot",[3]="CharacterShoulderSlot",
  [4]="CharacterShirtSlot",[5]="CharacterChestSlot",[6]="CharacterWaistSlot",
  [7]="CharacterLegsSlot",[8]="CharacterFeetSlot",[9]="CharacterWristSlot",
  [10]="CharacterHandsSlot",[11]="CharacterFinger0Slot",[12]="CharacterFinger1Slot",
  [13]="CharacterTrinket0Slot",[14]="CharacterTrinket1Slot",[15]="CharacterBackSlot",
  [16]="CharacterMainHandSlot",[17]="CharacterSecondaryHandSlot",
  [18]="CharacterRangedSlot",[19]="CharacterTabardSlot",
}
local DOT_COLOR = {
  missing = { 0.85, 0.25, 0.15 },
  swap = { 0.85, 0.41, 0.29 },
  rank = { 0.96, 0.85, 0.53 },
}

local cache, cacheAt = nil, 0
local function CachedResults()
  local now = GetTime and GetTime() or 0
  if not cache or (now - cacheAt) > 10 then
    cache = GA.Compute(); cacheAt = now
  end
  return cache
end

function GA.MarkPaperDoll()
  for _, r in ipairs(CachedResults()) do
    local btn = _G[SLOT_BUTTON[r.slot]]
    if btn then
      if not btn.__ppDot then
        local t = btn:CreateTexture(nil, "OVERLAY")
        t:SetWidth(10); t:SetHeight(10)
        t:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
        btn.__ppDot = t
      end
      local c = DOT_COLOR[r.status]
      if c then
        btn.__ppDot:SetTexture(c[1], c[2], c[3], 0.95)
        btn.__ppDot:Show()
      else
        btn.__ppDot:Hide()
      end
    end
  end
end

local function AdviceFor(itemName)
  if not itemName then return nil end
  for _, r in ipairs(CachedResults()) do
    if r.item == itemName and r.status ~= "ok" then return r end
  end
  return nil
end

function GA.HookUI()
  if PaperDollFrame and not GA.__pdHooked then
    GA.__pdHooked = true
    PaperDollFrame:HookScript("OnShow", function() PP.safeCall(GA.MarkPaperDoll) end)
  end
  if GameTooltip and not GA.__ttHooked then
    GA.__ttHooked = true
    GameTooltip:HookScript("OnTooltipSetItem", function(tip)
      PP.safeCall(function()
        local name = tip:GetItem()
        local r = AdviceFor(name)
        if not r then return end
        if r.status == "missing" then
          tip:AddLine("PallyPilot: no affix — add " .. r.want, 0.85, 0.25, 0.15)
        elseif r.status == "swap" then
          tip:AddLine("PallyPilot: re-affix to " .. r.want .. " (survival plan)", 0.85, 0.41, 0.29)
        elseif r.status == "rank" then
          tip:AddLine("PallyPilot: upgrade affix rank (currently " .. (r.rank or "?") .. ")", 0.96, 0.85, 0.53)
        end
        tip:Show()
      end)
    end)
  end
end
