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

local frame, fs, content

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

local STATUS_ORDER = { missing = 1, swap = 2, rank = 3, ok = 4 }

local function BuildText()
  local results = GA.Compute()
  table.sort(results, function(a, b)
    local oa, ob = STATUS_ORDER[a.status], STATUS_ORDER[b.status]
    if oa ~= ob then return oa < ob end
    return a.slot < b.slot
  end)
  local counts = { missing = 0, swap = 0, rank = 0, ok = 0 }
  for _, r in ipairs(results) do counts[r.status] = counts[r.status] + 1 end

  local t = {}
  t[#t+1] = DIM .. "Survival-first school (AotC I). " .. R .. GOLD .. counts.ok .. R
    .. DIM .. " ok, " .. R .. EMBER .. counts.missing .. R .. DIM .. " missing, "
    .. R .. EMBER .. counts.swap .. R .. DIM .. " wrong slot, " .. R
    .. BRIGHT .. counts.rank .. R .. DIM .. " low rank." .. R .. "\n"
  local lastStatus
  local HEADERS = {
    missing = EMBER .. "MISSING AFFIX — free power sitting empty" .. R,
    swap = EMBER .. "WRONG AFFIX FOR SLOT — re-affix per the plan" .. R,
    rank = BRIGHT .. "LOW RANK — upgrade the affix rank" .. R,
    ok = VERD .. "CORRECT" .. R,
  }
  for _, r in ipairs(results) do
    if r.status ~= lastStatus then
      t[#t+1] = "\n" .. HEADERS[r.status] .. "\n"
      lastStatus = r.status
    end
    local slotName = SLOT_NAMES[r.slot] or tostring(r.slot)
    local cur = r.affix and (r.affix .. (r.rank and r.rank > 0 and (" " .. r.rank) or "")) or "none"
    local line = "  " .. BRIGHT .. slotName .. R .. ": " .. (r.item or "?")
    if r.ilvl then line = line .. DIM .. " (ilvl " .. r.ilvl .. ")" .. R end
    t[#t+1] = line .. "\n"
    if r.status == "missing" then
      t[#t+1] = "      " .. EMBER .. "add " .. r.want .. R .. "\n"
    elseif r.status == "swap" then
      t[#t+1] = "      " .. EMBER .. cur .. " -> " .. r.want .. R .. "\n"
    elseif r.status == "rank" then
      t[#t+1] = "      " .. BRIGHT .. cur .. " -> rank 3+ (endgame chains run to 6)" .. R .. "\n"
    else
      t[#t+1] = "      " .. VERD .. cur .. R .. "\n"
    end
  end
  t[#t+1] = "\n" .. DIM .. "Affix schools: Enchanted Anvil / Dalaran. "
    .. "Weapons can instead carry the Judgement affix as an echo trigger "
    .. "(see dashboard affix notes). Low-ilvl items are flagged inline — "
    .. "replacing the item beats re-affixing it." .. R .. "\n"
  return table.concat(t)
end

function GA.Refresh()
  if not fs then return end
  fs:SetText(BuildText())
  if content then content:SetHeight((fs:GetHeight() or 600) + 20) end
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
  title:SetPoint("TOP", frame, "TOP", 0, -16)
  title:SetText(GOLD .. "Gear Audit — affixes" .. R)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
  frame.ppClose = close

  local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  refresh:SetWidth(80); refresh:SetHeight(20)
  refresh:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -40)
  refresh:SetText("Refresh")
  refresh:SetScript("OnClick", function() GA.Refresh() end)

  local scroll = CreateFrame("ScrollFrame", "PallyPilotGearScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -66)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 18)
  content = CreateFrame("Frame", nil, scroll)
  content:SetWidth(420); content:SetHeight(10)
  scroll:SetScrollChild(content)

  fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  fs:SetWidth(416); fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
  fs:SetSpacing(2)

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
