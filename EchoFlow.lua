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
  C    = { 0.45, 0.50, 0.55 },
  DISABLE = { 0.85, 0.25, 0.15 },
  REROLL  = { 0.85, 0.41, 0.29 },
}
local TIP_LABEL = {
  CORE = "CORE — lock, never lose",
  S = "S tier — keep (lock candidate)",
  A = "A tier — keep",
  B = "B tier — fine filler",
  C = "C — breadth filler (+1% Adaptive Power)",
  DISABLE = "DISABLE — bad for this build",
  REROLL = "unrated — reroll fodder",
}

local rail, status
local SetStatus -- forward declaration: defined with the engine below,
                -- used by ApplyPool which sits earlier in the file
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

local function NormEF(name)
  name = string.gsub(name or "", "\226\128\153", "'")
  return string.lower(name)
end

local function RefreshBadges()
  -- Active pool plan: X-mark the tiles to right-click OFF (level-1 ritual).
  -- Expires automatically once you're past the disable window.
  local plan = PP.db.poolPlan
  if plan and (UnitLevel("player") or 1) > 5 then
    PP.db.poolPlan = nil
    plan = nil
  end
  EachTile(Journal(), function(btn, display, verdict)
    if not btn.__ppDot then
      local t = btn:CreateTexture(nil, "OVERLAY")
      t:SetWidth(9); t:SetHeight(9)
      t:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
      btn.__ppDot = t
    end
    if not btn.__ppX then
      local x = btn:CreateTexture(nil, "OVERLAY")
      x:SetWidth(18); x:SetHeight(18)
      x:SetPoint("CENTER", btn, "CENTER", 0, 0)
      x:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
      x:Hide()
      btn.__ppX = x
    end
    if plan and plan.set and plan.set[NormEF(display)] then
      btn.__ppX:Show()
    else
      btn.__ppX:Hide()
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

-- One-click run-start: compute the pool plan, sync the matching build into
-- EBH, and X-mark the disable tiles. No chat commands involved.
function EF.ApplyPool(mode)
  if not (PP.EchoAudit and PP.EchoAudit.DisablePlan) then return end
  -- Direct call: an and-chain would truncate the multiple returns
  -- (the bug class that also ate the kill tracker).
  local keep, disable, set = PP.EchoAudit.DisablePlan(nil, mode)
  if not keep then
    SetStatus("EbonholdHub data not found", EMBER)
    return
  end
  PP.db.poolPlan = { mode = mode, set = set, t = time() }
  if PP.HubSync and PP.HubSync.Push then
    PP.safeCall(PP.HubSync.Push, mode == "farm" and "farm" or nil)
  end
  RefreshBadges()
  SetStatus(string.upper(mode) .. " pool: right-click these " .. #disable
    .. " OFF (level 1)", BRIGHT)
  PP.print(GOLD .. string.upper(mode) .. " POOL" .. R .. " — keep " .. #keep
    .. ", RIGHT-CLICK these " .. #disable .. " OFF (they also show a red X on "
    .. "visible tiles). Build synced to " .. mode .. " mode.")
  -- Print the full numbered list — reliable even across the scrolling catalog
  -- where only on-screen tiles can show an X.
  for i, nm in ipairs(disable) do
    DEFAULT_CHAT_FRAME:AddMessage("  " .. EMBER .. i .. "." .. R .. " " .. nm)
  end
end

local function FindTile(name)
  local hit
  EachTile(RunRoot(), function(btn, display)
    if not hit and display == name then hit = btn end
  end)
  return hit
end

-- Run-panel echoes carrying a given verdict (the Orb's working set).
local function RunByVerdict(want)
  local seen, out = {}, {}
  EachTile(RunRoot(), function(_, display, verdict)
    if verdict == want and not seen[display] then
      seen[display] = true
      out[#out + 1] = display
    end
  end)
  table.sort(out)
  return out
end

-- Junk for the reroll queue = rated-junk AND disable-listed run echoes
-- (disable's right-click only works at level 1; at 80 the Orb is the only
-- way to purge them).
local function RunJunk()
  local out = RunByVerdict("REROLL")
  for _, name in ipairs(RunByVerdict("DISABLE")) do out[#out + 1] = name end
  table.sort(out)
  return out
end

-- ---------------------------------------------------------------------------
-- Outcome toast: after each pick, show what you got, its verdict, and the
-- net power change (HP / AP / crit) since just before the Forget.
local toast
local function ShowToast(main, sub, r, g, b)
  if not toast then
    toast = CreateFrame("Frame", "PallyPilotToast", UIParent)
    toast:SetWidth(400); toast:SetHeight(58)
    toast:SetPoint("TOP", UIParent, "TOP", 0, -96)
    toast:SetFrameStrata("HIGH")
    toast:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 20,
      insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    toast.main = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    toast.main:SetPoint("TOP", toast, "TOP", 0, -12)
    toast.sub = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    toast.sub:SetPoint("TOP", toast.main, "BOTTOM", 0, -4)
    toast:SetScript("OnUpdate", function(self, elapsed)
      self.age = (self.age or 0) + elapsed
      if self.age > 6 then self:Hide() end
    end)
    toast:EnableMouse(true)
    toast:SetScript("OnMouseDown", function(self) self:Hide() end)
  end
  toast.main:SetText(main)
  toast.main:SetTextColor(r, g, b)
  toast.sub:SetText(sub or "")
  toast.age = 0
  toast:Show()
end

local function StatSnap()
  local base, pos, neg = UnitAttackPower("player")
  return {
    hp = UnitHealthMax("player") or 0,
    ap = (base or 0) + (pos or 0) + (neg or 0),
    crit = (GetCritChance and GetCritChance()) or 0,
  }
end

local function StatDeltaText(before)
  if not before then return "" end
  local now = StatSnap()
  local parts = {}
  local dhp, dap, dcrit = now.hp - before.hp, now.ap - before.ap, now.crit - before.crit
  if math.abs(dhp) >= 1 then
    parts[#parts+1] = (dhp > 0 and VERD .. "+" or EMBER) .. dhp .. " HP" .. R
  end
  if math.abs(dap) >= 1 then
    parts[#parts+1] = (dap > 0 and VERD .. "+" or EMBER) .. dap .. " AP" .. R
  end
  if math.abs(dcrit) >= 0.1 then
    parts[#parts+1] = (dcrit > 0 and VERD .. "+" or EMBER)
      .. string.format("%.1f", dcrit) .. "% crit" .. R
  end
  if #parts == 0 then return DIM .. "no stat change (proc/utility echo)" .. R end
  return table.concat(parts, DIM .. " · " .. R)
end

-- ---------------------------------------------------------------------------
-- Auto-pick toasts: EBH's automation answers draws instantly; RunLog's hook
-- on TrackPickStat calls in here so every automated pick shows a verdict
-- toast with the power delta since a rolling baseline.
local rollingStats, lastPickAt = nil, 0
function EF.NotifyPick(name)
  local verdict, display = PP.EchoAudit.VerdictFor(name)
  display = display or name
  -- Signal the reroll engine: the draw was answered (auto-pick path).
  EF.OnPickSignal(display)
  local delta = rollingStats and StatDeltaText(rollingStats) or ""
  local label, r, g, b
  if verdict == "CORE" or verdict == "S" then
    label, r, g, b = (verdict == "CORE" and "CORE!" or "S TIER"), 1, 0.85, 0.35
  elseif verdict == "A" then
    label, r, g, b = "A tier", 0.62, 0.70, 0.74
  elseif verdict == "B" then
    label, r, g, b = "B filler", 0.71, 0.65, 0.53
  elseif verdict == "C" then
    label, r, g, b = "breadth +1%", 0.45, 0.50, 0.55
  else
    label, r, g, b = "junk pick!", 0.85, 0.41, 0.29
  end
  ShowToast("+ " .. display .. " — " .. label, delta, r, g, b)
  rollingStats = StatSnap()
  lastPickAt = GetTime and GetTime() or 0
end

function EF.RefreshBaseline()
  local now = GetTime and GetTime() or 0
  if now - lastPickAt > 3 then rollingStats = StatSnap() end
end

-- ---------------------------------------------------------------------------
-- Reroll engine. Phases: ORB -> TILE -> DIALOG -> FORGET -> DRAW -> next.
-- DRAW advances on ANY of three signals: EBH's pick event (auto-pick), a
-- new tile appearing in the run panel (manual pick), or a new owned tome.
-- Run draws don't change tome ownership, so ownership alone is NOT enough.
local engine = { queue = {}, phase = nil, waited = 0, idx = 0, total = 0 }

function EF.OnPickSignal(name)
  if engine.phase == "DRAW" then
    engine.pickFlag = true
    engine.lastPickName = name
  end
end

-- Set of all echo names currently in the run panel.
local function RunNameSet()
  local set = {}
  EachTile(RunRoot(), function(_, display) set[display] = true end)
  return set
end

function SetStatus(msg, color) -- assigns the forward-declared local
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
  if rail then PP.safeCall(EF.RefreshRail) end
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
    -- Picking a draw closes the journal — reopen it ourselves.
    local j = Journal()
    if not (j and j:IsVisible()) then
      local micro = _G["EchoJournalMicroButton"]
      if micro then
        SmartClick(micro)
        SetStatus("reopening the Echoes window...")
      elseif engine.waited > 3 then
        SetStatus("open the Echoes window to continue", EMBER)
      end
      return
    end
    local orb = OrbBubble()
    if orb and orb:IsVisible() then
      SmartClick(orb)
      engine.phase = "TILE"; engine.waited = 0
      SetStatus("orb clicked — selecting " .. name)
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
      local orbs = engine.orbs or (PP.db.options.rerollOrbs or 1)
      if slider and slider.SetValue then pcall(slider.SetValue, slider, orbs) end
      engine.forgetBtn = forget
      engine.phase = "FORGET"; engine.waited = 0
    end
  elseif engine.phase == "FORGET" then
    engine.prevOwned = PP.EchoAudit.OwnedCopy()
    engine.prevStats = StatSnap()
    engine.runSnapshot = RunNameSet()
    engine.runSnapshot[name] = nil -- the forgotten one leaves; ignore it
    engine.pickFlag = false
    engine.lastPickName = nil
    SmartClick(engine.forgetBtn)
    engine.forgetBtn = nil
    engine.phase = "DRAW"; engine.waited = 0
    engine.drawWait = 0
    engine.idx = engine.idx + 1
    SetStatus("(" .. engine.idx .. "/" .. engine.total .. ") " .. name
      .. " forgotten — waiting for the pick (auto-pick is usually instant)", BRIGHT)
  elseif engine.phase == "DRAW" then
    engine.waited = 0 -- no timeout while waiting on the pick
    engine.drawWait = (engine.drawWait or 0) + elapsed
    -- The pick closes the journal; the tile-diff fallback below is blind
    -- while it's hidden. Reopen it ourselves after a short grace period.
    if engine.drawWait > 2 then
      local j = Journal()
      if not (j and j:IsVisible()) then
        local micro = _G["EchoJournalMicroButton"]
        if micro then SmartClick(micro) end
      end
      if engine.drawWait > 10 then
        SetStatus("(" .. engine.idx .. "/" .. engine.total .. ") still waiting — "
          .. "if the pick already happened, /pp next skips ahead", EMBER)
      end
    end
    local newName, viaAutoPick
    if engine.pickFlag then
      newName, viaAutoPick = engine.lastPickName or "?", true
    else
      -- Tome learned (rare): a new owned key appears.
      local cur = PP.EchoAudit.OwnedCopy()
      if cur and engine.prevOwned then
        for k in pairs(cur) do
          if not engine.prevOwned[k] then newName = k; break end
        end
      end
      -- Manual pick: a new tile shows up in the run panel.
      if not newName and engine.runSnapshot then
        EachTile(RunRoot(), function(_, display)
          if not newName and not engine.runSnapshot[display] then newName = display end
        end)
      end
    end
    if newName then
      engine.pickFlag = false
      table.remove(engine.queue, 1)
      local verdict, display = PP.EchoAudit.VerdictFor(newName)
      display = display or newName
      local delta = StatDeltaText(engine.prevStats)
      local progress = DIM .. "  (" .. engine.idx .. "/" .. engine.total .. ")" .. R
      if verdict == "REROLL" or verdict == "DISABLE" then
        -- Junk again: it's in the run now, so put it at the back of the queue.
        engine.queue[#engine.queue + 1] = display
        engine.total = engine.total + 1
        engine.junkStreak = (engine.junkStreak or 0) + 1
        if not viaAutoPick then
          ShowToast("- " .. display .. " — junk again, requeued",
            delta .. progress, 0.85, 0.41, 0.29)
        end
      else
        engine.junkStreak = 0
        -- Auto-pick already toasted via NotifyPick; only toast the
        -- fallback-detected picks.
        if not viaAutoPick then
          local r2, g2, b2 = 0.71, 0.65, 0.53
          if verdict == "CORE" or verdict == "S" then r2, g2, b2 = 1, 0.85, 0.35
          elseif verdict == "A" then r2, g2, b2 = 0.62, 0.70, 0.74 end
          ShowToast("+ " .. display .. " — " .. tostring(verdict or "?"),
            delta .. progress, r2, g2, b2)
        end
      end
      if (engine.junkStreak or 0) >= 5 then
        StopEngine("Stopped: 5 junk picks in a row. Auto-Pick's choices keep "
          .. "rating as junk — tell Claude before spending more orbs.")
        return
      end
      PP.print("(" .. engine.idx .. "/" .. engine.total .. ") got "
        .. BRIGHT .. display .. R .. " — " .. delta)
      RefreshBadges()
      if #engine.queue == 0 then
        StopEngine(nil)
        SetStatus("done — " .. engine.idx .. " rerolled", VERD)
        PP.print("Queue complete: " .. engine.idx .. " echoes recycled.")
        if rail then EF.RefreshRail() end
      else
        engine.phase = "ORB"; engine.waited = 0
        SetStatus("next: " .. engine.queue[1])
      end
    end
  end
end

local function StartQueue(list, label, orbs)
  engine.queue = list
  engine.total = #list
  engine.idx = 0
  engine.junkStreak = 0
  engine.orbs = orbs  -- per-reroll orb count override (quality-fish uses cap)
  engine.phase = "ORB"
  engine.waited = 0
  if rail and rail.rerollBtn then rail.rerollBtn:SetText("STOP") end
  PP.print(label .. ": " .. #list .. " echoes queued, "
    .. (PP.db.options.rerollOrbs or 1) .. " orb(s) each. Click STOP anytime.")
  SetStatus("starting — " .. engine.queue[1])
end

-- Manual escape hatch: the pick happened but no signal caught it.
-- Advances the queue without verdict processing (no requeue, no toast).
function EF.ForceNext()
  if engine.phase ~= "DRAW" then
    PP.print("Nothing is waiting on a pick right now.")
    return
  end
  table.remove(engine.queue, 1)
  engine.pickFlag = false
  RefreshBadges()
  if #engine.queue == 0 then
    StopEngine(nil)
    SetStatus("done — " .. engine.idx .. " rerolled", VERD)
    PP.print("Queue complete: " .. engine.idx .. " echoes recycled.")
    if rail then EF.RefreshRail() end
  else
    engine.phase = "ORB"; engine.waited = 0
    SetStatus("next: " .. engine.queue[1])
    PP.print("Skipped ahead — next: " .. engine.queue[1])
  end
end

function EF.StartReroll()
  if engine.phase then
    StopEngine("Queue stopped by you.")
    return
  end
  -- The Orb only trades echoes in the CURRENT RUN — queue those, not the
  -- whole owned collection.
  local list = RunJunk()
  if #list == 0 then
    SetStatus("no junk in this run", VERD)
    return
  end
  StartQueue(list, "Reroll queue")
end

-- Context-aware: clear junk if any, else quality-fish sub-Epic keepers.
function EF.StartRerollSmart()
  if engine.phase then StopEngine("Queue stopped by you."); return end
  if #RunJunk() > 0 then EF.StartReroll() else EF.StartQualityFish() end
end

-- Quality fish (mechanics confirmed 2026-08-26): an orb reroll forgets your
-- LOWEST-quality stack and opens a RANDOM 3-echo draw from the enabled pool
-- at boosted quality (~100 orbs = ~100% higher). So it can't target one
-- echo's quality — it churns sub-Epic keeper stacks into higher-quality
-- random pool draws. Banish/shrink the pool FIRST so the randoms stay in
-- your build. Targets CORE/S/A keepers below Epic, best first, orbs at cap.
function EF.StartQualityFish()
  if engine.phase then
    StopEngine("Queue stopped by you.")
    return
  end
  local targets = PP.EchoAudit.RunQualityTargets and PP.EchoAudit.RunQualityTargets()
  if not targets then
    SetStatus("Need EbonholdHub + at level 80 to read run quality", EMBER)
    return
  end
  if #targets == 0 then
    SetStatus("no sub-Epic keepers — build is quality-maxed", VERD)
    return
  end
  local names = {}
  for _, t in ipairs(targets) do names[#names + 1] = t.name end
  PP.print("Quality fish: " .. #names .. " sub-Epic keepers, orbs at cap (100) "
    .. "each. NOTE: rerolls draw RANDOM from your pool — banish unwanted "
    .. "echoes FIRST so replacements stay in-build. STOP anytime.")
  StartQueue(names, "Quality fish", 100)
end

-- ---------------------------------------------------------------------------
-- The rail: PallyPilot advice docked to the journal's right edge.
function EF.RefreshRail()
  if not rail then return end
  -- Active build mode: highlighted button + labeled line. No guessing.
  local mode = PP.db.buildMode
  if rail.poolFarm and rail.poolRaid then
    if mode == "farm" then
      rail.poolFarm:LockHighlight(); rail.poolRaid:UnlockHighlight()
    elseif mode == "raid" then
      rail.poolRaid:LockHighlight(); rail.poolFarm:UnlockHighlight()
    else
      rail.poolFarm:UnlockHighlight(); rail.poolRaid:UnlockHighlight()
    end
  end
  local buckets = PP.EchoAudit.Compute and select(1, PP.EchoAudit.Compute())
  local t = {}
  if mode then
    t[#t+1] = (mode == "farm" and EMBER or VERD) .. "BUILD: "
      .. string.upper(mode) .. R .. DIM
      .. (mode == "farm" and " (repeats uncapped)" or " (breadth)") .. R
    t[#t+1] = " "
  else
    t[#t+1] = DIM .. "BUILD: not synced — click a pool button" .. R
    t[#t+1] = " "
  end
  if buckets then
    t[#t+1] = GOLD .. "LOCK NOW — best "
      .. PP.EchoAudit.LockSlots() .. " owned" .. R
    for _, p in ipairs(PP.EchoAudit.LockNow(buckets)) do
      t[#t+1] = "  " .. p.name
    end
    local junk = #buckets.REROLL
    local inRun = #RunJunk()
    local qt = PP.EchoAudit.RunQualityTargets and PP.EchoAudit.RunQualityTargets()
    local subEpic = qt and #qt or 0
    t[#t+1] = " "
    t[#t+1] = DIM .. #buckets.CORE .. " core · " .. #buckets.S .. " S · "
      .. #buckets.A .. " A · " .. #buckets.B .. " B" .. R
    t[#t+1] = EMBER .. inRun .. " junk in run" .. R .. DIM .. " · " .. R
      .. BRIGHT .. subEpic .. " keepers sub-Epic" .. R
    if rail.rerollBtn and not engine.phase then
      rail.rerollBtn:SetText(inRun > 0 and ("Reroll junk (" .. inRun .. ")")
        or ("Quality fish (" .. subEpic .. ")"))
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
  minus:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 14, 68)
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
  rail.rerollBtn:SetScript("OnClick", function() PP.safeCall(EF.StartRerollSmart) end)

  -- Run-start pool buttons: one click computes the plan, syncs the build
  -- mode, and X-marks the disable tiles.
  rail.poolFarm = CreateFrame("Button", nil, rail, "UIPanelButtonTemplate")
  rail.poolFarm:SetWidth(88); rail.poolFarm:SetHeight(22)
  rail.poolFarm:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 14, 40)
  rail.poolFarm:SetText("Farm pool")
  rail.poolFarm:SetScript("OnClick", function() PP.safeCall(EF.ApplyPool, "farm") end)

  rail.poolRaid = CreateFrame("Button", nil, rail, "UIPanelButtonTemplate")
  rail.poolRaid:SetWidth(88); rail.poolRaid:SetHeight(22)
  rail.poolRaid:SetPoint("LEFT", rail.poolFarm, "RIGHT", 6, 0)
  rail.poolRaid:SetText("Raid pool")
  rail.poolRaid:SetScript("OnClick", function() PP.safeCall(EF.ApplyPool, "raid") end)

  status = rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 14, 94)
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
  driver.engAccum = 0
  driver:SetScript("OnUpdate", function(self, elapsed)
    -- Engine steps at 0.3s, not per frame — tile walks and owned-set diffs
    -- are too heavy for frame rate.
    self.engAccum = self.engAccum + elapsed
    if self.engAccum >= 0.3 then
      PP.safeCall(EngineTick, self.engAccum)
      self.engAccum = 0
    end
    self.elapsed = self.elapsed + elapsed
    if self.elapsed > 1.5 then
      self.elapsed = 0
      if not rail and Journal() then PP.safeCall(BuildRail) end
      PP.safeCall(HookTooltip, "GameTooltip")
      PP.safeCall(HookTooltip, "UtilsSpellTooltip")
      PP.safeCall(EF.RefreshBaseline)
    end
  end)
end
