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

-- Affix targets are CLASS DATA -- each class ships its own PP.Build.slotTargets
-- (paladin's lives in BuildData.lua next to B.bis). This table is deliberately
-- EMPTY: it used to hold the AotC-I survival map (Ironhide/Iron Will per slot),
-- which quietly kept grading endgame gear against a levelling-phase school long
-- after the meta moved to crit/haste. Worse, it was a silent FALLBACK -- when the
-- class data went missing during a refactor the stale advice came straight back
-- with no error. Empty means a class without affix data shows no affix verdict,
-- which is honest, instead of confidently wrong advice.
local SLOT_TARGETS = {}

local ROMAN = { I=1, II=2, III=3, IV=4, V=5, VI=6, VII=7, VIII=8, IX=9, X=10 }

-- Ebonhold survival/offense affixes cap at VI (6). B.affixDamage lists the
-- endgame targets as "6/5/4" — VI is the ceiling, so anything below VI still
-- has real upgrade room (re-roll at Enchanted Anvil / Dalaran). The old bar was
-- III, a leftover from the AotC-I survival phase; endgame gear should chase VI.
local AFFIX_MAX_RANK = 6

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
  -- Class-aware: use the logged-in class's own affix targets (every class ships
  -- them in PP.Build.slotTargets). SLOT_TARGETS is {} on purpose (see above), so
  -- a class with no affix data simply gets no verdict rather than wrong advice.
  local targets = ((PP.Build and PP.Build.slotTargets) or SLOT_TARGETS)[slot]
  if not targets then return nil end
  local affix, rank = ParseAffix(item.name)
  if not affix and HasAffixLine(item.lines) then
    -- Affix line without a name suffix — show what the line says.
    affix, rank = "?", 0
  end
  local out = { slot = slot, item = item.name, ilvl = item.ilvl,
                affix = affix, rank = rank, want = targets[1],
                target = AFFIX_MAX_RANK }
  if not affix then
    out.status = "missing"
    return out
  end
  for _, t in ipairs(targets) do
    if affix == t then
      out.status = (rank and rank < AFFIX_MAX_RANK) and "rank" or "ok"
      return out
    end
  end
  out.status = "swap"
  return out
end

function GA.Compute()
  local results = {}
  -- Slots 4 (shirt) and 19 (tabard) carry no stats and cannot take an affix,
  -- so grading them produced red "no affix" dots on the paperdoll and a
  -- tooltip telling you to re-roll an affix onto your tabard.
  local COSMETIC = { [4] = true, [19] = true }
  for slot = 1, 19 do
    local item = not COSMETIC[slot] and ScanSlot(slot) or nil
    if item then
      local j = Judge(slot, item)
      if j then results[#results + 1] = j end
    end
  end
  return results
end

-- ---------------------------------------------------------------------------
-- Per-class BiS now lives in each class's data file (PP.Build.bis), read below
-- via ((PP.Build and PP.Build.bis) or GA.BIS). GA.BIS stays EMPTY on purpose --
-- same reasoning as SLOT_TARGETS: a populated paladin-flavored fallback would
-- SILENTLY hand paladin plate to any class missing its own bis, instead of just
-- showing no upgrade line. Empty = honest (no line) over confidently wrong.
-- (Paladin's list moved verbatim to BuildData B.bis.)
GA.BIS = {}

-- ---------------------------------------------------------------------------
-- Gear view: an action-first fix list. Each slot leads with a plain-word state
-- (FIX / UP / OK) and the exact thing to do, worst-first. Done slots hide by
-- default. Colorblind: the state is a WORD, never colour alone.

local ASH = "|cff9db3bd"
local gearRows, expandedSlot, showAll = {}, nil, false

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
      -- Affix credit is fractional: a rank-4-of-6 affix is 2/3 kitted, not a
      -- pass/fail -- otherwise moving the target from III to VI would crater
      -- the score. Right affix at VI = full; missing/wrong = none.
      if a then
        totChk = totChk + 1
        if not affixGap then okChk = okChk + math.min(1, (a.rank or 0) / (a.target or AFFIX_MAX_RANK)) end
      end
      if g and g.enchantable then totChk = totChk + 1; if not encMiss then okChk = okChk + 1 end end
      if g and (g.sockets or 0) > 0 then totChk = totChk + 1; if empty == 0 then okChk = okChk + 1 end end
      local n = (affixGap and 1 or 0) + (encMiss and 1 or 0) + (empty > 0 and 1 or 0)
      gapN = gapN + n
      rows[#rows + 1] = {
        slot = slot, name = SLOT_NAMES[slot] or ("slot " .. slot),
        item = a and a.item, ilvl = ilvl,
        affix = a and a.affix, rank = a and a.rank, affixStatus = a and a.status,
        want = a and a.want, target = a and a.target,
        affixGap = affixGap, affixLow = affixLow,
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

-- State per slot: "fix" (something missing/wrong -- cheap, do now), "up"
-- (works, can be stronger: affix below VI or ilvl behind the set), "ok" (done).
-- Every state is a WORD, never colour alone (colorblind-safe).
local function StateOf(r)
  if r.affixGap or r.encMiss or (r.empty or 0) > 0 then return "fix" end
  if r.affixLow or (r.lag or 0) >= 6 then return "up" end
  return "ok"
end

local STATE_TAG = {
  fix = EMBER .. "[FIX]" .. R,
  up  = ASH .. "[UP]" .. R,
  ok  = VERD .. "[OK]" .. R,
}

-- The one plain-language "what to do" line for a slot's row.
local function NeedsText(r)
  -- Keep the row short: the affix NAME/target lives in the expanded detail.
  local t = {}
  if r.affixGap then
    t[#t + 1] = (r.affixStatus == "swap") and "wrong affix" or "no affix"
  elseif r.affixLow then
    t[#t + 1] = "affix " .. (r.rank or 0) .. "/" .. (r.target or AFFIX_MAX_RANK)
  end
  if r.encMiss then t[#t + 1] = "enchant" end
  if (r.empty or 0) > 0 then t[#t + 1] = r.empty .. (r.empty > 1 and " gems" or " gem") end
  if #t == 0 and (r.lag or 0) >= 6 then t[#t + 1] = "upgrade item" end
  return table.concat(t, DIM .. "  ·  " .. R)
end

local function GetRow(i)
  local row = gearRows[i]
  if row then return row end
  row = CreateFrame("Button", nil, content)
  row:SetWidth(432); row:SetHeight(22)
  row.hl = row:CreateTexture(nil, "BACKGROUND")
  row.hl:SetAllPoints(); row.hl:SetTexture(1, 1, 1, 0.05); row.hl:Hide()
  row:SetScript("OnEnter", function(s) s.hl:Show() end)
  row:SetScript("OnLeave", function(s) s.hl:Hide() end)
  local function fs(x, w, font)
    local f = row:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    f:SetPoint("TOPLEFT", row, "TOPLEFT", x, -4); f:SetWidth(w); f:SetJustifyH("LEFT")
    return f
  end
  row.cTag = fs(4, 42)
  row.cName = fs(50, 88, "GameFontNormalSmall")
  row.cIlvl = fs(140, 56)
  row.cNeeds = fs(198, 232)
  row.cName:SetWordWrap(false)
  row.cNeeds:SetWordWrap(false)
  row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.detail:SetPoint("TOPLEFT", row, "TOPLEFT", 50, -22)
  row.detail:SetWidth(376); row.detail:SetJustifyH("LEFT"); row.detail:SetSpacing(2)
  gearRows[i] = row
  return row
end

function GA.Refresh()
  if not frame or not content then return end
  local rows, avg, _, score = CollectRows()
  for _, r in ipairs(rows) do r.state = StateOf(r) end
  table.sort(rows, function(a, b)
    if a.prio ~= b.prio then return a.prio > b.prio end
    return a.slot < b.slot
  end)

  local needWork = 0
  for _, r in ipairs(rows) do if r.state ~= "ok" then needWork = needWork + 1 end end

  frame.gsScore:SetText(GOLD .. score .. R .. DIM .. " /100" .. R)
  frame.gsBar:SetWidth(math.max(1, 150 * score / 100))
  frame.gsSub:SetText(DIM .. "avg ilvl " .. R .. BRIGHT .. math.floor(avg + 0.5) .. R
    .. DIM .. "  ·  " .. R .. (needWork > 0 and EMBER or VERD) .. needWork .. R
    .. DIM .. " to fix" .. R)
  frame.showBtn:SetText(showAll and "Hide done" or "Show all")

  -- Fix-first strip: the top-3 actionable slots by priority.
  local byPrio = {}
  for _, r in ipairs(rows) do if r.state ~= "ok" then byPrio[#byPrio + 1] = r end end
  table.sort(byPrio, function(a, b) return a.prio > b.prio end)
  local top = {}
  for i = 1, math.min(3, #byPrio) do
    top[#top + 1] = BRIGHT .. i .. "·" .. byPrio[i].name .. R
  end
  frame.top3:SetText(#top > 0 and (DIM .. "Fix first:  " .. R .. table.concat(top, DIM .. "   " .. R))
    or (VERD .. "Every slot is kitted — nothing to fix." .. R))

  for _, r in ipairs(gearRows) do r:Hide() end
  local y, i = 0, 0
  for _, r in ipairs(rows) do
    if showAll or r.state ~= "ok" then
      i = i + 1
      local row = GetRow(i)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
      row.cTag:SetText(STATE_TAG[r.state] or "")
      row.cName:SetText(BRIGHT .. r.name .. R)
      local lag = (r.lag and r.lag >= 6 and r.ilvl > 0)
        and (EMBER .. " -" .. math.floor(r.lag + 0.5) .. R) or ""
      row.cIlvl:SetText(r.ilvl > 0 and (DIM .. r.ilvl .. R .. lag) or (DIM .. "—" .. R))
      row.cNeeds:SetText(r.state == "ok" and (VERD .. "kitted" .. R) or NeedsText(r))
      local slot = r.slot
      row:SetScript("OnClick", function()
        expandedSlot = (expandedSlot == slot) and nil or slot
        GA.Refresh()
      end)
      if expandedSlot == r.slot then
        -- One imperative per line, verb first, no rationale. "DO THIS."
        local d = {}
        local function act(label, what)
          d[#d + 1] = BRIGHT .. label .. R .. "  " .. what
        end
        d[#d + 1] = DIM .. (r.item or "(empty)") .. R
        if r.encMiss then act("Enchant", EMBER .. (r.encRec or "add one") .. R) end
        if r.empty > 0 then
          -- The belt buckle is a WAIST-only item (slot 6) -- it was previously
          -- printed on every socketed slot, which is just wrong.
          local gem = (PP.Build and PP.Build.gemRec) or "Haste"
          local txt = r.empty .. "x " .. gem
          if r.slot == 6 then txt = txt .. DIM .. "  + Eternal Belt Buckle" .. R end
          act("Gem", EMBER .. txt .. R)
        end
        if r.affixGap then
          act("Affix", EMBER .. "re-roll to " .. (r.want or "?") .. R)
        elseif r.affixLow then
          act("Affix", ASH .. "raise " .. (r.affix or "") .. " to "
            .. (r.target or AFFIX_MAX_RANK) .. R)
        end
        local b = ((PP.Build and PP.Build.bis) or GA.BIS)[r.slot]
        if b then
          act("Upgrade", b.item .. DIM .. "  (" .. b.src .. ")" .. R)
        end
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
  title:SetText(GOLD .. "Gear — fix list" .. R)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
  frame.ppClose = close

  -- Header: kit score + bar, avg/needs, show-all toggle.
  frame.gsScore = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.gsScore:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -40)
  frame.gsBar = frame:CreateTexture(nil, "ARTWORK")
  frame.gsBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -62); frame.gsBar:SetHeight(4)
  frame.gsBar:SetTexture(0.878, 0.702, 0.322, 1)
  local barBg = frame:CreateTexture(nil, "BACKGROUND")
  barBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -62); barBg:SetWidth(150); barBg:SetHeight(4)
  barBg:SetTexture(1, 1, 1, 0.08)
  frame.gsSub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.gsSub:SetPoint("TOPLEFT", frame, "TOPLEFT", 150, -44)

  -- Toggle: hide fully-kitted slots (the page is a to-do list) vs show all.
  frame.showBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.showBtn:SetWidth(88); frame.showBtn:SetHeight(20)
  frame.showBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -40)
  frame.showBtn:SetText("Show all")
  frame.showBtn:SetScript("OnClick", function()
    showAll = not showAll
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
  ColLabel(22, "STATE"); ColLabel(68, "SLOT"); ColLabel(158, "ILVL")
  ColLabel(216, "NEEDS")

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
-- Colour AND a letter. Three shades of orange-red is not a distinction a
-- colourblind reader can make, and the paperdoll has no legend to consult:
--   X = no affix at all   S = wrong affix, swap it   R = right affix, low rank
local DOT_MARK = {
  missing = { 0.85, 0.25, 0.15, "X" },
  swap    = { 0.85, 0.41, 0.29, "S" },
  rank    = { 0.96, 0.85, 0.53, "R" },
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
  -- Clear EVERY slot first. Iterating only the slots with results left a stale
  -- dot on any slot that stopped producing advice -- you fixed the affix, the
  -- warning stayed until the next /reload.
  for _, name in pairs(SLOT_BUTTON) do
    local btn = _G[name]
    if btn and btn.__ppDot then btn.__ppDot:Hide() end
    if btn and btn.__ppMark then btn.__ppMark:Hide() end
  end
  for _, r in ipairs(CachedResults()) do
    local btn = _G[SLOT_BUTTON[r.slot]]
    local c = btn and DOT_MARK[r.status]
    if c then
      if not btn.__ppDot then
        local t = btn:CreateTexture(nil, "OVERLAY")
        t:SetWidth(12); t:SetHeight(12)
        t:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
        btn.__ppDot = t
      end
      if not btn.__ppMark then
        local fs = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        fs:SetPoint("CENTER", btn.__ppDot, "CENTER", 0, 0)
        btn.__ppMark = fs
      end
      btn.__ppDot:SetTexture(c[1], c[2], c[3], 0.95)
      btn.__ppDot:Show()
      btn.__ppMark:SetText(c[4])
      btn.__ppMark:Show()
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
          tip:AddLine("EbonPilot: no affix — add " .. r.want, 0.85, 0.25, 0.15)
        elseif r.status == "swap" then
          -- Not "survival plan" any more: the affix targets moved to the
          -- crit/haste damage list when Ret's Ebonhold meta was pinned down.
          tip:AddLine("EbonPilot: re-affix to " .. r.want, 0.85, 0.41, 0.29)
        elseif r.status == "rank" then
          tip:AddLine("EbonPilot: raise affix to VI (now " .. (r.rank or "?") .. "/" .. (r.target or 6) .. ")", 0.96, 0.85, 0.53)
        end
        tip:Show()
      end)
    end)
  end
end
