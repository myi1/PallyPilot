-- PallyPilot EchoFlow: advice rendered where echo decisions happen.
--  * Verdict dots on the Echo Journal's tiles
--  * Verdict lines appended to echo tooltips
--  * A rail bolted onto the journal: Lock Now six + one-click reroll queue
--  * Reroll engine: drives orb -> tile -> slider -> Forget; you only make
--    the draw pick. Pauses in combat, stops loudly on anything unexpected.
local PP = PallyPilot
local EF = PP.EchoFlow

local GOLD = "|cffe0b352"
local BRIGHT = "|cfff6d888"
local DIM = "|cffb4a586"
local EMBER = "|cffd9694a"
local VERD = "|cff8aa96a"
local R = "|r"

-- Verdict -> dot color {r,g,b}. One language everywhere.
local DOT = {
  CORE = { 1.00, 0.72, 0.20 },
  S    = { 0.96, 0.85, 0.53 },
  A    = { 0.62, 0.70, 0.74 },
  B    = { 0.55, 0.48, 0.38 },
  DISABLE = { 0.85, 0.25, 0.15 },
  REROLL  = { 0.85, 0.41, 0.29 },
}
local TIP_LABEL = {
  CORE = "CORE — lock, never lose",
  S = "S tier — keep (lock candidate)",
  A = "A tier — keep",
  B = "B tier — fine filler",
  DISABLE = "DISABLE — bad for this build",
  REROLL = "unrated — reroll fodder",
}

local rail, status
local Journal = function() return _G["ProjectEbonholdEchoJournal"] end
local OrbBubble = function() return _G["EbonholdOrbBubble"] end

-- ---------------------------------------------------------------------------
-- Tooltip verdicts. Echo tooltips ride GameTooltip or the server's
-- UtilsSpellTooltip; append one PallyPilot line when line 1 is a known echo.
local function Annotate(tip, tipName)
  if tip.__ppDone then return end
  local fs = _G[tipName .. "TextLeft1"]
  local text = fs and fs:GetText()
  if not text then return end
  local verdict = PP.EchoAudit.VerdictFor and select(1, PP.EchoAudit.VerdictFor(text))
  if not verdict then return end
  tip.__ppDone = true
  local c = DOT[verdict] or { 1, 1, 1 }
  tip:AddLine("PallyPilot: " .. (TIP_LABEL[verdict] or verdict), c[1], c[2], c[3])
  tip:Show()
end

local function HookTooltip(tipName)
  local tip = _G[tipName]
  if not tip or tip.__ppHooked then return end
  tip.__ppHooked = true
  tip:HookScript("OnShow", function(self) PP.safeCall(Annotate, self, tipName) end)
  tip:HookScript("OnHide", function(self) self.__ppDone = nil end)
end

-- ---------------------------------------------------------------------------
-- Tile discovery. Run-panel tiles carry their RANK ("1"/"2") as a text
-- region alongside the name, so every FontString region is tried against the
-- echo catalog until one matches (handles "Broodmot..." truncation too).
local function TileEcho(btn)
  local regions = { btn:GetRegions() }
  for _, reg in ipairs(regions) do
    if reg.GetText and reg:GetObjectType() == "FontString" then
      local t = reg:GetText()
      if t and t ~= "" then
        local display, verdict = PP.EchoAudit.MatchDisplay(t)
        if display then return display, verdict end
      end
    end
  end
  return nil
end

-- The left "my run" panel — the only tiles the Orb can act on.
local function RunRoot()
  return _G["ProjectEbonholdEchoJournalMyRunScroll"]
    or _G["ProjectEbonholdEchoJournalMyRunInset"]
    or Journal()
end

local function EachTile(root, fn)
  if not root then return end
  local function walk(f, depth)
    if depth > 6 then return end
    if f.GetScrollChild then
      local sc = f:GetScrollChild()
      if sc then walk(sc, depth + 1) end
    end
    local kids = { f:GetChildren() }
    for _, c in ipairs(kids) do
      local ok, ctype = pcall(c.GetObjectType, c)
      if ok and (ctype == "Button" or ctype == "CheckButton") and c:IsVisible() then
        local display, verdict = TileEcho(c)
        if display then fn(c, display, verdict) end
      end
      if ok then walk(c, depth + 1) end
    end
  end
  PP.safeCall(walk, root, 0)
end

-- Click a frame through whatever handler it actually uses.
local function SmartClick(f)
  if not f then return false end
  if f.Click and f:GetScript("OnClick") then f:Click(); return true end
  local up = f:GetScript("OnMouseUp")
  if up then pcall(up, f, "LeftButton"); return true end
  local down = f:GetScript("OnMouseDown")
  if down then pcall(down, f, "LeftButton"); return true end
  if f.Click then f:Click(); return true end
  return false
end

local function RefreshBadges()
  EachTile(Journal(), function(btn, _, verdict)
    if not btn.__ppDot then
      local t = btn:CreateTexture(nil, "OVERLAY")
      t:SetWidth(9); t:SetHeight(9)
      t:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
      btn.__ppDot = t
    end
    local c = DOT[verdict]
    if c then
      btn.__ppDot:SetTexture(c[1], c[2], c[3], 0.95)
      btn.__ppDot:Show()
    else
      btn.__ppDot:Hide()
    end
  end)
end

local function FindTile(name)
  local hit
  EachTile(RunRoot(), function(btn, display)
    if not hit and display == name then hit = btn end
  end)
  return hit
end

-- Junk actually present in the current run — the only rerollable junk.
local function RunJunk()
  local seen, out = {}, {}
  EachTile(RunRoot(), function(_, display, verdict)
    if verdict == "REROLL" and not seen[display] then
      seen[display] = true
      out[#out + 1] = display
    end
  end)
  table.sort(out)
  return out
end

-- ---------------------------------------------------------------------------
-- Reroll engine. Phases: ORB -> TILE -> DIALOG -> FORGET -> DRAW -> next.
-- DRAW waits for the owned-set to change (you picked) before continuing.
local engine = { queue = {}, phase = nil, waited = 0, baseline = nil, idx = 0, total = 0 }

local function SetStatus(msg, color)
  if status then status:SetText((color or DIM) .. msg .. R) end
end

local function StopEngine(msg)
  engine.phase = nil
  engine.queue = {}
  if msg then
    PP.print(msg)
    SetStatus(msg, EMBER)
  end
  if rail and rail.rerollBtn then rail.rerollBtn:SetText("Reroll junk") end
end

-- Find the visible Forget dialog: a Button labeled "Forget" plus a Slider
-- somewhere on the same parent.
local function FindForgetDialog()
  local f = EnumerateFrames()
  while f do
    local ok, hit = pcall(function()
      if f:IsVisible() and f:GetObjectType() == "Button" then
        local t = f.GetText and f:GetText()
        local fs = f.GetFontString and f:GetFontString()
        t = t or (fs and fs:GetText())
        if t == "Forget" then return f end
      end
      return nil
    end)
    if ok and hit then
      local parent = hit:GetParent()
      local slider
      if parent then
        for _, c in ipairs({ parent:GetChildren() }) do
          if c.GetObjectType and c:GetObjectType() == "Slider" then slider = c; break end
        end
      end
      return hit, slider
    end
    f = EnumerateFrames(f)
  end
  return nil
end

local function EngineTick(elapsed)
  if not engine.phase then return end
  if UnitAffectingCombat("player") then
    SetStatus("paused — in combat")
    return
  end
  engine.waited = engine.waited + elapsed
  if engine.waited > 12 then
    StopEngine("Reroll stopped: timed out during '" .. engine.phase
      .. "'. UI may have changed — tell Claude what was on screen.")
    return
  end

  local name = engine.queue[1]
  if not name then StopEngine(nil); SetStatus("queue empty — done!", VERD); return end

  if engine.phase == "ORB" then
    local orb = OrbBubble()
    if orb and orb:IsVisible() then
      SmartClick(orb)
      engine.phase = "TILE"; engine.waited = 0
      SetStatus("orb clicked — selecting " .. name)
    else
      StopEngine("Reroll stopped: Orb bubble not visible.")
    end
  elseif engine.phase == "TILE" then
    local tile = FindTile(name)
    if tile then
      SmartClick(tile)
      engine.phase = "DIALOG"; engine.waited = 0
    elseif engine.waited > 2 then
      SetStatus("can't see '" .. name .. "' — scroll your run list to it", EMBER)
    end
  elseif engine.phase == "DIALOG" then
    local forget, slider = FindForgetDialog()
    if forget then
      local orbs = (PP.db.options.rerollOrbs or 1)
      if slider and slider.SetValue then pcall(slider.SetValue, slider, orbs) end
      engine.forgetBtn = forget
      engine.phase = "FORGET"; engine.waited = 0
    end
  elseif engine.phase == "FORGET" then
    engine.baseline = PP.EchoAudit.OwnedSignature()
    SmartClick(engine.forgetBtn)
    engine.forgetBtn = nil
    engine.phase = "DRAW"; engine.waited = 0
    engine.idx = engine.idx + 1
    SetStatus("(" .. engine.idx .. "/" .. engine.total .. ") " .. name
      .. " forgotten — PICK YOUR NEW ECHO", BRIGHT)
    PP.print("Rerolled " .. BRIGHT .. name .. R .. " — pick your replacement (draw advice applies).")
  elseif engine.phase == "DRAW" then
    engine.waited = 0 -- no timeout while waiting on the player's pick
    local sig = PP.EchoAudit.OwnedSignature()
    if sig and engine.baseline and sig ~= engine.baseline then
      table.remove(engine.queue, 1)
      RefreshBadges()
      if #engine.queue == 0 then
        StopEngine(nil)
        SetStatus("done — " .. engine.idx .. " rerolled", VERD)
        PP.print("Reroll queue complete: " .. engine.idx .. " echoes recycled.")
        if rail then EF.RefreshRail() end
      else
        engine.phase = "ORB"
        SetStatus("next: " .. engine.queue[1])
      end
    end
  end
end

function EF.StartReroll()
  if engine.phase then
    StopEngine("Reroll stopped by you.")
    return
  end
  -- The Orb only trades echoes in the CURRENT RUN — queue those, not the
  -- whole owned collection.
  local list = RunJunk()
  if #list == 0 then
    SetStatus("no junk in this run — nothing to reroll", VERD)
    return
  end
  engine.queue = list
  engine.total = #list
  engine.idx = 0
  engine.phase = "ORB"
  engine.waited = 0
  if rail and rail.rerollBtn then rail.rerollBtn:SetText("STOP") end
  PP.print("Reroll queue: " .. #list .. " junk echoes in this run, "
    .. (PP.db.options.rerollOrbs or 1) .. " orb(s) each. You only make the picks. "
    .. "Click STOP anytime.")
  SetStatus("starting — " .. engine.queue[1])
end

-- ---------------------------------------------------------------------------
-- The rail: PallyPilot advice docked to the journal's right edge.
function EF.RefreshRail()
  if not rail then return end
  local buckets = PP.EchoAudit.Compute and select(1, PP.EchoAudit.Compute())
  local t = {}
  if buckets then
    t[#t+1] = GOLD .. "LOCK NOW — best six owned" .. R
    for _, p in ipairs(PP.EchoAudit.LockNow(buckets)) do
      t[#t+1] = "  " .. p.name
    end
    local junk = #buckets.REROLL
    local inRun = #RunJunk()
    t[#t+1] = " "
    t[#t+1] = DIM .. #buckets.CORE .. " core · " .. #buckets.S .. " S · "
      .. #buckets.A .. " A · " .. #buckets.B .. " B" .. R
    t[#t+1] = EMBER .. inRun .. " junk in this run" .. R
      .. DIM .. " (" .. junk .. " owned)" .. R
    if rail.rerollBtn and not engine.phase then
      rail.rerollBtn:SetText("Reroll junk (" .. inRun .. ")")
    end
  else
    t[#t+1] = EMBER .. "EbonholdHub data not found" .. R
  end
  rail.body:SetText(table.concat(t, "\n"))
end

local function BuildRail()
  local journal = Journal()
  if not journal or rail then return end
  rail = CreateFrame("Frame", "PallyPilotJournalRail", journal)
  rail:SetWidth(210)
  rail:SetPoint("TOPLEFT", journal, "TOPRIGHT", 10, 0)
  rail:SetPoint("BOTTOMLEFT", journal, "BOTTOMRIGHT", 10, 0)
  rail:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 24,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })

  local title = rail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", rail, "TOP", 0, -14)
  title:SetText(GOLD .. "PallyPilot" .. R)

  rail.body = rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rail.body:SetPoint("TOPLEFT", rail, "TOPLEFT", 14, -34)
  rail.body:SetWidth(182)
  rail.body:SetJustifyH("LEFT"); rail.body:SetJustifyV("TOP")
  rail.body:SetSpacing(2)

  -- Orb spend per reroll: [-] n [+]
  local minus = CreateFrame("Button", nil, rail, "UIPanelButtonTemplate")
  minus:SetWidth(22); minus:SetHeight(20)
  minus:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 14, 42)
  minus:SetText("-")
  local orbLabel = rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  orbLabel:SetPoint("LEFT", minus, "RIGHT", 6, 0)
  local plus = CreateFrame("Button", nil, rail, "UIPanelButtonTemplate")
  plus:SetWidth(22); plus:SetHeight(20)
  plus:SetPoint("LEFT", orbLabel, "RIGHT", 6, 0)
  plus:SetText("+")
  local function orbText()
    orbLabel:SetText(DIM .. "orbs/reroll: " .. R .. GOLD
      .. (PP.db.options.rerollOrbs or 1) .. R)
  end
  minus:SetScript("OnClick", function()
    PP.db.options.rerollOrbs = math.max(1, (PP.db.options.rerollOrbs or 1) - 1); orbText()
  end)
  plus:SetScript("OnClick", function()
    PP.db.options.rerollOrbs = math.min(25, (PP.db.options.rerollOrbs or 1) + 1); orbText()
  end)
  orbText()

  rail.rerollBtn = CreateFrame("Button", nil, rail, "UIPanelButtonTemplate")
  rail.rerollBtn:SetWidth(182); rail.rerollBtn:SetHeight(22)
  rail.rerollBtn:SetPoint("BOTTOM", rail, "BOTTOM", 0, 16)
  rail.rerollBtn:SetText("Reroll junk")
  rail.rerollBtn:SetScript("OnClick", function() PP.safeCall(EF.StartReroll) end)

  status = rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 14, 68)
  status:SetWidth(182)
  status:SetJustifyH("LEFT")

  -- Refresh badges + rail while the journal is open; run the engine always.
  rail.elapsed = 0
  rail:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed > 2 then
      self.elapsed = 0
      PP.safeCall(RefreshBadges)
    end
  end)
  rail:SetScript("OnShow", function()
    PP.safeCall(EF.RefreshRail)
    PP.safeCall(RefreshBadges)
  end)
  EF.RefreshRail()
end

-- ---------------------------------------------------------------------------
-- Init: the journal frame may not exist until the Collections UI loads,
-- so poll lightly until it appears. The engine ticker runs independently.
function EF.Init()
  local driver = CreateFrame("Frame")
  driver.elapsed = 0
  driver:SetScript("OnUpdate", function(self, elapsed)
    PP.safeCall(EngineTick, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed > 1.5 then
      self.elapsed = 0
      if not rail and Journal() then PP.safeCall(BuildRail) end
      PP.safeCall(HookTooltip, "GameTooltip")
      PP.safeCall(HookTooltip, "UtilsSpellTooltip")
    end
  end)
end
