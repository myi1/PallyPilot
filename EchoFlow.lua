-- PallyPilot EchoFlow: advice rendered where echo decisions happen.
--  * Verdict LETTER badges on the Echo Journal's tiles (colorblind-safe)
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

-- Verdict -> dot color {r,g,b}. Used only for tooltip text now; the tile
-- badges use LETTERS (below) because the user is colorblind.
local DOT = {
  CORE = { 1.00, 0.72, 0.20 },
  S    = { 0.96, 0.85, 0.53 },
  A    = { 0.62, 0.70, 0.74 },
  B    = { 0.55, 0.48, 0.38 },
  C    = { 0.45, 0.50, 0.55 },
  DISABLE = { 0.85, 0.25, 0.15 },
  REROLL  = { 0.85, 0.41, 0.29 },
}
-- Colorblind-safe tile badge: a LETTER, not a color. CORE shows "S+" so it
-- never collides with the C tier. Junk (disable/reroll) shows "X".
local LETTER = {
  CORE = "S+", S = "S", A = "A", B = "B", C = "C",
  DISABLE = "X", REROLL = "X",
}
local TIP_LABEL = {
  CORE = "Keystone — lock, never lose",
  S = "Carry — does the heavy lifting",
  A = "Staple — strong, always keep",
  B = "Filler — keep until something better",
  C = "Breadth — kept for +1% Adaptive Power",
  DISABLE = "Turn off — bad for this build",
  REROLL = "Fodder — feed to an Orb",
}

local rail, status
local SetStatus -- forward declaration: defined with the engine below,
                -- used by ApplyPool which sits earlier in the file
local FishSubLine -- forward declaration: defined with the engine below,
                  -- used by NotifyPick which sits earlier in the file
local engine      -- forward declaration: the reroll engine state, read by
                  -- NotifyPick (engine.fishing) which sits earlier in the file
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
  tip:AddLine("EbonPilot: " .. (TIP_LABEL[verdict] or verdict), c[1], c[2], c[3])
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

-- Forward-declared so it stays a local (no global pollution) while still being
-- reachable from EF.RefreshBadges below.
local RefreshBadges

-- Exposed so TomeManager can re-mark the catalog after it builds a plan. The
-- badges ARE the instruction list, which is why no module should print a
-- hundred-line "right-click these" dump to chat.
function EF.RefreshBadges() return PP.safeCall(RefreshBadges) end

RefreshBadges = function()
  -- Active pool plan: X-mark the tiles to right-click OFF, tick-mark the ones
  -- to switch back ON.
  --
  -- This used to DELETE the plan above level 5 ("it's a level-1 ritual"), which
  -- threw away the one piece of state you want to survive until the next reset
  -- -- and made the badges vanish exactly when you wanted to see the remaining
  -- gap. Keep it; the level gate lives in the advice text, not in the data.
  local plan = PP.db.poolPlan
  local pendingOff, pendingOn = 0, 0
  EachTile(Journal(), function(btn, display, verdict)
    -- Dark backing chip so the letter reads on any icon art.
    if not btn.__ppDot then
      local t = btn:CreateTexture(nil, "ARTWORK")
      t:SetWidth(16); t:SetHeight(13)
      t:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
      t:SetTexture(0, 0, 0, 0.72)
      btn.__ppDot = t
    end
    -- The verdict LETTER, white with a black outline: legible without color.
    if not btn.__ppLtr then
      local ls = btn:CreateFontString(nil, "OVERLAY")
      ls:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE")
      ls:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
      ls:SetTextColor(1, 1, 1, 1)
      btn.__ppLtr = ls
    end
    if not btn.__ppX then
      local x = btn:CreateTexture(nil, "OVERLAY")
      x:SetWidth(18); x:SetHeight(18)
      x:SetPoint("CENTER", btn, "CENTER", 0, 0)
      x:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
      x:Hide()
      btn.__ppX = x
    end
    -- Re-enable marker: a separate texture so "turn this back ON" is not the
    -- same glyph as "turn this OFF".
    if not btn.__ppOn then
      local c = btn:CreateTexture(nil, "OVERLAY")
      c:SetWidth(18); c:SetHeight(18)
      c:SetPoint("CENTER", btn, "CENTER", 0, 0)
      c:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
      c:Hide()
      btn.__ppOn = c
    end
    -- The X and tick are shapes, but pair them with a WORD: colour and glyph
    -- alone are not enough to read at a glance across a wall of icons.
    if not btn.__ppOff then
      local o = btn:CreateFontString(nil, "OVERLAY")
      o:SetFont("Fonts\\ARIALN.TTF", 11, "OUTLINE")
      o:SetPoint("BOTTOM", btn, "BOTTOM", 0, 1)
      o:SetTextColor(1, 1, 1, 1)
      o:Hide()
      btn.__ppOff = o
    end
    -- STATE-AWARE, not just set membership. The plan is a static list of names;
    -- the tile knows whether the work is already done. Comparing them means a
    -- badge clears the instant its tile redraws after you toggle it, instead of
    -- lingering until the next plan run and making you doubt the click landed.
    local k = NormEF(display)
    local isOff = (btn.tomeDisabled == true)
    local wantOff = plan and plan.set and plan.set[k] and not isOff
    local wantOn  = plan and plan.onSet and plan.onSet[k] and isOff
    if wantOff then
      btn.__ppX:Show(); btn.__ppOn:Hide()
      btn.__ppOff:SetText("OFF"); btn.__ppOff:Show()
      pendingOff = pendingOff + 1
    elseif wantOn then
      btn.__ppX:Hide(); btn.__ppOn:Show()
      btn.__ppOff:SetText("ON"); btn.__ppOff:Show()
      pendingOn = pendingOn + 1
    else
      btn.__ppX:Hide(); btn.__ppOn:Hide(); btn.__ppOff:Hide()
    end
    local letter = LETTER[verdict]
    if letter then
      btn.__ppLtr:SetText(letter)
      btn.__ppLtr:Show()
      btn.__ppDot:Show()
    else
      btn.__ppLtr:Hide()
      btn.__ppDot:Hide()
    end
  end)
  -- Only counts what is currently RENDERED, so it is a floor, not a total --
  -- the scroll is virtualized. Still the fastest honest progress signal there
  -- is: it ticks down as you click, with no command to run.
  EF.pendingOff, EF.pendingOn = pendingOff, pendingOn
  if rail and rail.poolLeft then
    if not plan then
      rail.poolLeft:SetText("")
    elseif pendingOff == 0 and pendingOn == 0 then
      rail.poolLeft:SetText(VERD .. "pool: done on screen" .. R)
    else
      rail.poolLeft:SetText(GOLD .. "pool: " .. pendingOff .. " OFF, "
        .. pendingOn .. " ON left here" .. R)
    end
  end
end

-- Re-badge NOW rather than on the next tick. Toggling a tome changes the
-- journal's data, and the server UI exposes OnDataChanged for exactly this;
-- scrolling recycles frames, so their badges are stale until redrawn.
local function HookJournalRefresh()
  if EF.__journalHooked then return end
  local ej = _G.ProjectEbonhold and _G.ProjectEbonhold.EchoJournal
  if type(ej) == "table" and type(ej.OnDataChanged) == "function" then
    local orig = ej.OnDataChanged
    local unpackFn = unpack or table.unpack
    ej.OnDataChanged = function(...)
      local r = { orig(...) }
      PP.safeCall(RefreshBadges)
      return unpackFn(r)
    end
    EF.__journalHooked = true
  end
  local scroll = _G.ProjectEbonholdEchoJournalScroll
  if scroll and scroll.HookScript and not EF.__scrollHooked then
    -- HookScript, never SetScript: the journal's own scroll handler is what
    -- draws the tiles, and replacing it would break the catalog outright.
    local ok = pcall(scroll.HookScript, scroll, "OnVerticalScroll", function()
      PP.safeCall(RefreshBadges)
    end)
    if ok then EF.__scrollHooked = true end
  end
end
EF.HookJournalRefresh = HookJournalRefresh

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
  -- onSet must be present even when empty: RefreshBadges reads it, and leaving
  -- it nil here let a rail Farm/Raid-pool click silently strip the tick badges
  -- TomeManager had set for the re-enable half of a plan.
  PP.db.poolPlan = { mode = mode, set = set, onSet = {}, t = time() }
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
    label, r, g, b = (verdict == "CORE" and "KEYSTONE!" or "CARRY"), 1, 0.85, 0.35
  elseif verdict == "A" then
    label, r, g, b = "STAPLE", 0.62, 0.70, 0.74
  elseif verdict == "B" then
    label, r, g, b = "FILLER", 0.71, 0.65, 0.53
  elseif verdict == "C" then
    label, r, g, b = "BREADTH +1%", 0.45, 0.50, 0.55
  else
    label, r, g, b = "FODDER — reroll", 0.85, 0.41, 0.29
  end
  -- During quality fishing, the AP/HP delta is misleading (it ignores Adaptive
  -- and proc quality) — show the breadth-vs-quality readout instead.
  local sub = delta
  if engine.fishing then sub = FishSubLine() end
  ShowToast("+ " .. display .. " — " .. label, sub, r, g, b)
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
engine = { queue = {}, phase = nil, waited = 0, idx = 0, total = 0 }

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

local QNAME = { [0] = "Common", [1] = "Uncommon", [2] = "Rare", [3] = "Epic", [4] = "Legend" }

-- One-line fishing verdict for the pick toast's sub-line (glanceable).
-- Assigns the forward-declared local so NotifyPick (earlier) can call it.
FishSubLine = function()
  local st = PP.EchoAudit and PP.EchoAudit.FishStatus and PP.EchoAudit.FishStatus()
  if not st then return "" end
  local d = engine.fishBaseUniques and (st.uniques - engine.fishBaseUniques) or nil
  local adapt = "Adaptive " .. st.uniques
    .. (d and (" (" .. (d >= 0 and "+" or "") .. d .. ")") or "")
  if st.allEpic then
    return VERD .. "STOP" .. R .. DIM .. " · " .. R .. adapt .. DIM
      .. " · top procs all Epic" .. R
  end
  return BRIGHT .. "KEEP" .. R .. DIM .. " · " .. R .. adapt .. DIM .. " · "
    .. R .. EMBER .. st.subEpic .. " top sub-Epic" .. R
end

-- Full on-demand readout: /pp fishstatus. Lists only what still needs fishing.
function EF.FishReadout()
  local st = PP.EchoAudit and PP.EchoAudit.FishStatus and PP.EchoAudit.FishStatus()
  if not st then
    PP.print("Fishing readout needs your run loaded — check at level 80 in a run.")
    return
  end
  local d = engine.fishBaseUniques and (st.uniques - engine.fishBaseUniques) or nil
  local epicCount = #st.procs - st.subEpic - st.missing
  PP.print(GOLD .. "FISH STATUS" .. R .. " — Adaptive " .. BRIGHT .. st.uniques
    .. " uniques" .. R .. DIM .. " (+" .. st.uniques .. "% dmg"
    .. (d and (", " .. (d >= 0 and "+" or "") .. d .. " since fishing start") or "")
    .. ")" .. R .. "  ·  top procs Epic: " .. epicCount .. "/" .. #st.procs)
  for _, p in ipairs(st.procs) do
    if not p.owned then
      DEFAULT_CHAT_FRAME:AddMessage("   " .. DIM .. "[--] " .. p.name
        .. " — not in this run (draw/farm it first)" .. R)
    elseif not p.epic then
      DEFAULT_CHAT_FRAME:AddMessage("   " .. EMBER .. "[X] " .. p.name .. " — "
        .. (QNAME[p.q] or ("q" .. tostring(p.q))) .. ", fish it" .. R)
    end
  end
  if st.allEpic then
    PP.print(VERD .. "STOP FISHING." .. R .. " Every top proc you own is Epic. "
      .. "More rolls now just trade breadth (Adaptive) for little — save the build.")
  else
    PP.print(BRIGHT .. "KEEP FISHING." .. R .. " " .. st.subEpic .. " top proc(s) "
      .. "above are still sub-Epic — each outweighs the ~1% Adaptive a roll costs.")
  end
end

local function StopEngine(msg)
  engine.phase = nil
  engine.fishing = false
  engine.queue = {}
  if msg then
    PP.print(msg)
    SetStatus(msg, EMBER)
  end
  if rail and rail.rerollBtn then rail.rerollBtn:SetText("Reroll junk") end
  if rail then PP.safeCall(EF.RefreshRail) end
end

-- Recursively find the first visible Slider under a frame (the orb-count
-- slider is not always a direct child of the Forget button's parent — when we
-- missed it, the orb count was never set and the game used its own default,
-- which is why the first reroll spent the max and the rest spent 1).
local function FindSliderIn(root, depth)
  if not root or depth > 5 then return nil end
  local ok, kids = pcall(function() return { root:GetChildren() } end)
  if not ok then return nil end
  for _, c in ipairs(kids) do
    local okt, t = pcall(function() return c:GetObjectType() end)
    if okt and t == "Slider" then
      local okv, vis = pcall(function() return c:IsVisible() end)
      if okv and vis then return c end
    end
    local nested = FindSliderIn(c, depth + 1)
    if nested then return nested end
  end
  return nil
end

-- Set an orb slider to `orbs`, clamped to its range, and fire OnValueChanged so
-- the game registers the value even when SetValue alone doesn't. Returns the
-- value actually applied (clamped) or nil.
local function SetSlider(slider, orbs)
  if not slider or not slider.SetValue then return nil end
  local applied
  pcall(function()
    if slider.GetMinMaxValues then
      local lo, hi = slider:GetMinMaxValues()
      if hi and hi > 0 and orbs > hi then orbs = hi end
      if lo and orbs < lo then orbs = lo end
    end
    slider:SetValue(orbs)
    local h = slider.GetScript and slider:GetScript("OnValueChanged")
    if h then pcall(h, slider, orbs) end
    applied = orbs
  end)
  return applied
end

-- Find the visible Forget dialog: a Button labeled "Forget" plus its orb slider
-- (searched through the whole dialog subtree, then one ancestor up).
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
      local slider = FindSliderIn(parent, 0)
      if not slider and parent then
        slider = FindSliderIn(parent:GetParent(), 0)
      end
      return hit, slider
    end
    f = EnumerateFrames(f)
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- New (2026-08-29) orb reroll panel: a 3-choice "Select" offer with a
-- "Use Orbs" button to reroll the whole offer. Found at RUNTIME by button text
-- (exactly like FindForgetDialog), and each card's echo is read with the same
-- region-matching TileEcho uses -- so NO frame scan or hardcoded names needed.

-- Read the echo shown on a choice card: scan the card's own font regions, then
-- one level of children (the name may sit on a child fontstring).
local function ReadCardEcho(cardFrame)
  if not cardFrame then return nil end
  local function scanRegions(f)
    local ok, regions = pcall(function() return { f:GetRegions() } end)
    if not ok then return nil end
    for _, reg in ipairs(regions) do
      local okt, t = pcall(function()
        if reg.GetObjectType and reg:GetObjectType() == "FontString" then
          return reg:GetText()
        end
      end)
      if okt and t and t ~= "" then
        local display, verdict = PP.EchoAudit.MatchDisplay(t)
        if display then return display, verdict end
      end
    end
    return nil
  end
  local d, v = scanRegions(cardFrame)
  if d then return d, v end
  local okk, kids = pcall(function() return { cardFrame:GetChildren() } end)
  if okk then
    for _, c in ipairs(kids) do
      d, v = scanRegions(c)
      if d then return d, v end
    end
  end
  return nil
end

-- Returns { useOrbs = <button|nil>, choices = { {btn, name, verdict}, ... } }
-- or nil when the panel isn't on screen.
local function FindRerollPanel()
  local choices, useOrbs = {}, nil
  local f = EnumerateFrames()
  while f do
    pcall(function()
      if f:IsVisible() and f:GetObjectType() == "Button" then
        local t = f.GetText and f:GetText()
        local fs = f.GetFontString and f:GetFontString()
        t = t or (fs and fs:GetText())
        if t then
          local low = string.lower(t)
          if string.find(low, "use orb", 1, true) then
            useOrbs = f
          elseif string.find(low, "^select") then -- "Select", "Select (1)"
            local card = f:GetParent()
            local name, verdict = ReadCardEcho(card)
            if not name and card then
              name, verdict = ReadCardEcho(card:GetParent())
            end
            choices[#choices + 1] = { btn = f, name = name, verdict = verdict }
          end
        end
      end
    end)
    f = EnumerateFrames(f)
  end
  if #choices == 0 and not useOrbs then return nil end
  return { useOrbs = useOrbs, choices = choices }
end

-- Verdict -> pick rank (higher = keep). Junk (X) and unread sort to the bottom.
local PICK_RANK = { CORE = 6, S = 5, A = 4, B = 3, C = 2, DISABLE = 0, REROLL = 0 }
local function BestChoice(panel)
  local best, bestRank = nil, -1
  for _, ch in ipairs(panel.choices) do
    local v = ch.verdict
    if not v and ch.name then v = select(1, PP.EchoAudit.VerdictFor(ch.name)) end
    ch.verdict = v
    local r = ch.name and (PICK_RANK[v or "?"] or 1) or -1
    if r > bestRank then best, bestRank = ch, r end
  end
  return best, bestRank
end

-- Safe dry run: read the live panel and report what it sees + what it WOULD
-- pick. No clicks. Proves the runtime reader works with no scan needed.
function EF.OrbPreview()
  local panel = FindRerollPanel()
  if not panel then
    PP.print("No reroll panel visible. Open the Use Orbs / Select panel, then /pp orbpreview.")
    return
  end
  PP.print(GOLD .. "Reroll panel" .. R .. DIM .. " — " .. #panel.choices
    .. " choice(s)" .. (panel.useOrbs and ", Use Orbs button found" or ", NO Use Orbs button")
    .. R)
  local best = BestChoice(panel)
  for i, ch in ipairs(panel.choices) do
    DEFAULT_CHAT_FRAME:AddMessage("  " .. GOLD .. i .. "." .. R .. " " .. BRIGHT
      .. (ch.name or "(name unread)") .. R .. DIM .. " — "
      .. tostring(ch.verdict or "?") .. R)
  end
  if best and best.name then
    PP.print("Would pick: " .. BRIGHT .. best.name .. R .. DIM
      .. " (" .. tostring(best.verdict or "?") .. ", best rating)." .. R)
  else
    PP.print(EMBER .. "Couldn't read the choices' names off the cards — tell Claude "
      .. "(the catalog may not cover these, or the card layout differs)." .. R)
  end
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
      local orbs = PP.db.options.rerollOrbs or 1
      local applied = SetSlider(slider, orbs)
      engine.forgetBtn = forget
      engine.forgetSlider = slider
      engine.phase = "FORGET"; engine.waited = 0
      if slider then
        SetStatus("spending " .. (applied or orbs) .. " orb(s) on " .. name)
      else
        SetStatus("orb slider not found — using the game default", EMBER)
      end
    end
  elseif engine.phase == "FORGET" then
    -- Re-assert the orb count right before committing: the dialog can reset the
    -- slider to 1 between opening and our click, which is what made every
    -- reroll after the first spend only 1 orb.
    if engine.forgetSlider then
      SetSlider(engine.forgetSlider, PP.db.options.rerollOrbs or 1)
    end
    engine.prevOwned = PP.EchoAudit.OwnedCopy()
    engine.prevStats = StatSnap()
    engine.runSnapshot = RunNameSet()
    engine.runSnapshot[name] = nil -- the forgotten one leaves; ignore it
    engine.pickFlag = false
    engine.lastPickName = nil
    SmartClick(engine.forgetBtn)
    engine.forgetBtn = nil
    engine.forgetSlider = nil
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

-- Every reroll spends the orbs/reroll toggle value (PP.db.options.rerollOrbs) —
-- one source of truth, applied fresh at each dialog. No per-queue override.
local function StartQueue(list, label)
  engine.queue = list
  engine.total = #list
  engine.idx = 0
  engine.junkStreak = 0
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
  -- Junk first, but do NOT stop there. You choose what the orb consumes, so an
  -- absence of rated junk just means your weakest echo is a better one -- it
  -- never means rerolling is unavailable. Falling back to the weakest-first
  -- fodder ranking is what keeps the endgame loop moving.
  local list = RunJunk()
  if #list == 0 then
    local rank = PP.EchoAudit and PP.EchoAudit.FodderRank and PP.EchoAudit.FodderRank()
    if rank then
      for _, f in ipairs(rank) do list[#list + 1] = f.name end
    end
  end
  if #list == 0 then
    SetStatus("nothing in the run can be fed to the orb", VERD)
    return
  end
  StartQueue(list, "Reroll queue")
end

-- Public accessors so the Chase panel can show what WOULD be fed to the orb and
-- can halt the queue the instant the chased echo lands.
function EF.RunJunkList() return RunJunk() end
function EF.IsRunning() return engine.phase ~= nil end
function EF.Stop(msg) if engine.phase then StopEngine(msg or "Stopped.") end end

-- Context-aware: clear junk if any, else quality-fish sub-Epic keepers.
function EF.StartRerollSmart()
  if engine.phase then StopEngine("Queue stopped by you."); return end
  if #RunJunk() > 0 then EF.StartReroll() else EF.StartQualityFish() end
end

-- Quality fish (mechanics confirmed 2026-08-26): an orb reroll forgets your
-- LOWEST-quality stack and opens a RANDOM 3-echo draw from the enabled pool
-- at boosted quality (~100 orbs = ~100% higher). So it can't target one
-- echo's quality — it churns sub-Epic keeper stacks into higher-quality
-- random pool draws. Targets CORE/S/A keepers below Epic, best first.
--
-- The pool it draws from is fixed by now: banishes only happen on level-up
-- draws (and EbonholdHub spends those automatically), so "shrink the pool
-- first" is not something you can act on at 80. Pool curation is the level-1
-- tome pass; by the time you are fishing, the hat is what it is.
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
  local orbs = PP.db.options.rerollOrbs or 1
  PP.print("Quality fish: " .. #names .. " sub-Epic keepers at " .. orbs
    .. " orb(s) each" .. (orbs < 50 and " — crank orbs/reroll up (to ~100) for a "
      .. "bigger quality jump" or "") .. ". Each roll forgets your lowest stack "
    .. "and draws 3 RANDOM from the pool, so it can land missing echoes too. "
    .. "STOP anytime.")
  StartQueue(names, "Quality fish")
  -- Fishing mode: the pick toast switches to the breadth-vs-quality readout,
  -- baselined to your unique count right now so you can see Adaptive drift.
  engine.fishing = true
  local st = PP.EchoAudit.FishStatus and PP.EchoAudit.FishStatus()
  engine.fishBaseUniques = st and st.uniques or nil
  PP.safeCall(EF.FishReadout)
end

-- ---------------------------------------------------------------------------
-- The rail: PallyPilot advice docked to the journal's right edge.
-- ---------------------------------------------------------------------------
-- THE NEXT ACTION, rendered in the rail with a button that performs it.
--
-- Typing a slash command to be told what to do, then typing a second one to do
-- it, is two steps too many when the Echoes window is already open in front of
-- you. This resolves the same decision BisPlan.Now() makes and binds it to one
-- button, so the answer and the action are the same click.
--
-- Returns label, tooltip, handler (handler nil = nothing to do right now).
-- Exposed (not file-local) so the decision can be tested without standing
-- up the whole journal rail.
function EF.ResolveNextAction()
  local lvl = UnitLevel("player") or 80

  if lvl == 1 then
    return "Curate pool (level 1)",
      "The ONLY moment tome toggles apply. Badges every tile to switch.",
      function() if PP.TomeManager then PP.safeCall(PP.TomeManager.Scan, "bis") end end
  end
  if lvl < 80 then
    return "Sync auto-pick",
      "EBH drafts and banishes for you while levelling -- this aims it at your build.",
      function() if PP.HubSync then PP.safeCall(PP.HubSync.Push) end end
  end

  local st = PP.BisPlan and PP.BisPlan.Status and PP.BisPlan.Status()
  local missing = st and ((st.counts.ROLL or 0) + (st.counts.FARM or 0)) or 0
  local rank = PP.EchoAudit.FodderRank and PP.EchoAudit.FodderRank()
  local weakest = rank and rank[1]
  local qt = PP.EchoAudit.RunQualityTargets and PP.EchoAudit.RunQualityTargets()
  local subEpic = (qt and #qt) or 0

  if missing > 0 and weakest then
    return "Roll for " .. missing .. " missing",
      "Feeds " .. weakest.name .. " [" .. weakest.tier .. "] -- your weakest echo.",
      function() PP.safeCall(EF.StartReroll) end
  end
  if subEpic > 0 then
    return "Quality fish (" .. subEpic .. ")",
      "Churn sub-Epic keepers toward Epic. Crank orbs/reroll up first.",
      function() PP.safeCall(EF.StartQualityFish) end
  end
  if missing > 0 then
    return nil, "Nothing left in the run can be fed to the orb.", nil
  end
  return "Build complete -- lock & save",
    "Lock your best " .. (PP.EchoAudit.LockSlots and PP.EchoAudit.LockSlots() or 6)
      .. ", then save the loadout. The snapshot keeps Epic quality.",
    nil
end

function EF.RefreshNextAction()
  if not (rail and rail.nextFS and rail.nextBtn) then return end
  -- While the engine is running, the only useful action is stopping it.
  if engine and engine.phase then
    rail.nextFS:SetText(GOLD .. "RUNNING" .. R .. DIM
      .. " -- each roll is still your click." .. R)
    rail.nextBtn:SetText("Stop")
    rail.nextBtn:Enable()
    rail.nextBtn:SetScript("OnClick", function() PP.safeCall(EF.Stop) end)
    return
  end
  local ok, label, tip, handler = pcall(EF.ResolveNextAction)
  if not ok then return end
  rail.nextFS:SetText(GOLD .. "NEXT" .. R .. DIM .. "  " .. (tip or "") .. R)
  -- Pin the height from GetStringHeight so the button below lands under the
  -- wrapped text. GetHeight() is stale right after SetText -- the recurring
  -- overlap bug in this project -- and everything else in the rail stacks off
  -- this anchor.
  rail.nextFS:SetHeight(rail.nextFS:GetStringHeight() + 2)
  if label then
    rail.nextBtn:SetText(label)
    rail.nextBtn:Show()
    if handler then
      rail.nextBtn:Enable()
      rail.nextBtn:SetScript("OnClick", function() PP.safeCall(handler) end)
    else
      -- Advice with no automatable step (lock and save is done in the game's
      -- own UI). Show it, but do not pretend the button does it.
      rail.nextBtn:Disable()
      rail.nextBtn:SetScript("OnClick", nil)
    end
  else
    rail.nextBtn:Hide()
  end
end

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
  -- THE NEXT ACTION, first and in-line. This is the thing you came to the
  -- panel for; everything below it is supporting detail. It also drives the
  -- big button, so the answer and the way to act on it are the same widget.
  EF.RefreshNextAction()

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
    local inRun = #RunJunk()
    local qt = PP.EchoAudit.RunQualityTargets and PP.EchoAudit.RunQualityTargets()
    local subEpic = qt and #qt or 0
    t[#t+1] = " "
    t[#t+1] = DIM .. #buckets.CORE .. " core · " .. #buckets.S .. " S · "
      .. #buckets.A .. " A · " .. #buckets.B .. " B" .. R

    -- "0 junk in run" was the headline here, which reads as a dead end -- and
    -- since you choose what the orb eats, it never was one. Lead with the echo
    -- you would actually feed.
    local rank = PP.EchoAudit.FodderRank and PP.EchoAudit.FodderRank()
    local weakest = rank and rank[1]
    if weakest then
      t[#t+1] = DIM .. "next fodder: " .. R .. BRIGHT .. weakest.name .. R
        .. DIM .. " [" .. weakest.tier .. "]" .. R
    else
      t[#t+1] = DIM .. "no echo can be fed to the orb" .. R
    end
    t[#t+1] = DIM .. inRun .. " junk · " .. subEpic .. " sub-Epic keepers" .. R

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
  title:SetText(GOLD .. "EbonPilot" .. R)

  -- NEXT ACTION sits at the very top, above the build detail: it is the
  -- question you actually opened this panel to answer.
  rail.nextFS = rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rail.nextFS:SetPoint("TOPLEFT", rail, "TOPLEFT", 14, -34)
  rail.nextFS:SetWidth(182)
  rail.nextFS:SetJustifyH("LEFT"); rail.nextFS:SetJustifyV("TOP")
  rail.nextFS:SetSpacing(2)

  rail.nextBtn = CreateFrame("Button", nil, rail, "UIPanelButtonTemplate")
  rail.nextBtn:SetWidth(182); rail.nextBtn:SetHeight(24)
  rail.nextBtn:SetPoint("TOPLEFT", rail.nextFS, "BOTTOMLEFT", 0, -4)
  rail.nextBtn:SetText("...")

  rail.body = rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rail.body:SetPoint("TOPLEFT", rail.nextBtn, "BOTTOMLEFT", 0, -10)
  rail.body:SetWidth(182)
  rail.body:SetJustifyH("LEFT"); rail.body:SetJustifyV("TOP")
  rail.body:SetSpacing(2)

  -- Orb spend per reroll: [-] n [+]
  local minus = CreateFrame("Button", nil, rail, "UIPanelButtonTemplate")
  minus:SetWidth(22); minus:SetHeight(20)
  minus:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 14, 90)
  minus:SetText("-")
  local orbLabel = rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  orbLabel:SetPoint("LEFT", minus, "RIGHT", 6, 0)
  local plus = CreateFrame("Button", nil, rail, "UIPanelButtonTemplate")
  plus:SetWidth(22); plus:SetHeight(20)
  plus:SetPoint("LEFT", orbLabel, "RIGHT", 6, 0)
  plus:SetText("+")
  local function orbText()
    orbLabel:SetText(DIM .. "orbs/reroll: " .. R .. GOLD
      .. (PP.db.options.rerollOrbs or 1) .. R .. DIM .. "  (shift +/-10)" .. R)
  end
  -- Shift-click steps by 10 (1..100) so fishing values are reachable fast.
  minus:SetScript("OnClick", function()
    local step = IsShiftKeyDown() and 10 or 1
    PP.db.options.rerollOrbs = math.max(1, (PP.db.options.rerollOrbs or 1) - step); orbText()
  end)
  plus:SetScript("OnClick", function()
    local step = IsShiftKeyDown() and 10 or 1
    PP.db.options.rerollOrbs = math.min(100, (PP.db.options.rerollOrbs or 1) + step); orbText()
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

  -- Level-1 tome enable/disable advisor + build score. Both read the catalog
  -- tiles, so the rail (only up while the Echoes window is open) is their home.
  rail.tomeBtn = CreateFrame("Button", nil, rail, "UIPanelButtonTemplate")
  rail.tomeBtn:SetWidth(88); rail.tomeBtn:SetHeight(22)
  rail.tomeBtn:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 14, 64)
  rail.tomeBtn:SetText("Tome on/off")
  rail.tomeBtn:SetScript("OnClick", function()
    if PP.TomeManager then PP.safeCall(PP.TomeManager.Command, "") end
  end)

  rail.scoreBtn = CreateFrame("Button", nil, rail, "UIPanelButtonTemplate")
  rail.scoreBtn:SetWidth(88); rail.scoreBtn:SetHeight(22)
  rail.scoreBtn:SetPoint("LEFT", rail.tomeBtn, "RIGHT", 6, 0)
  rail.scoreBtn:SetText("Build score")
  rail.scoreBtn:SetScript("OnClick", function()
    if PP.BuildScore then PP.safeCall(PP.BuildScore.Report) end
  end)

  -- Live pool progress: counts what is badged on screen right now, so it ticks
  -- down as you click. No command, no chat line.
  rail.poolLeft = rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rail.poolLeft:SetPoint("TOPLEFT", rail.tomeBtn, "BOTTOMLEFT", 0, -6)
  rail.poolLeft:SetWidth(182)
  rail.poolLeft:SetJustifyH("LEFT")

  status = rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 14, 116)
  status:SetWidth(182)
  status:SetJustifyH("LEFT")

  -- Refresh badges AND the rail while the journal is open. The rail used to
  -- refresh only on OnShow, so with the window left open (which is exactly what
  -- you do while swapping saved builds) its summary was computed once and then
  -- never again -- the tiles updated but "LOCK NOW / core-S-A-B / junk in run"
  -- stayed frozen from whenever you opened it.
  -- Two clocks, not one. Badges are cheap and need to feel instant while you
  -- are clicking through the catalog; the rail summary is heavy and 2s is
  -- fine. Sharing a 2s tick made every toggle look like it had not registered.
  rail.elapsed = 0
  rail.badgeElapsed = 0
  rail:SetScript("OnUpdate", function(self, elapsed)
    self.badgeElapsed = self.badgeElapsed + elapsed
    if self.badgeElapsed > 0.2 then
      self.badgeElapsed = 0
      PP.safeCall(RefreshBadges)
    end
    self.elapsed = self.elapsed + elapsed
    if self.elapsed > 2 then
      self.elapsed = 0
      PP.safeCall(EF.RefreshRail)
    end
  end)
  rail:SetScript("OnShow", function()
    PP.safeCall(EF.RefreshRail)
    PP.safeCall(RefreshBadges)
  end)

  -- Instant refresh when the server swaps your echoes, rather than waiting out
  -- the tick. Same messages the dashboard listens for.
  if not EF.__swapListener then
    EF.__swapListener = CreateFrame("Frame")
    EF.__swapListener:RegisterEvent("CHAT_MSG_SYSTEM")
    EF.__swapListener:SetScript("OnEvent", function(_, _, msg)
      if not msg then return end
      local m = string.lower(msg)
      if string.find(m, "echoes were replaced", 1, true)
         or string.find(m, "build applied", 1, true) then
        PP.safeCall(EF.RefreshRail)
        PP.safeCall(RefreshBadges)
      end
    end)
  end

  -- Hook the journal's own change signal so a toggle repaints immediately
  -- rather than waiting out a timer.
  PP.safeCall(HookJournalRefresh)

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
      -- Keep retrying: EchoJournal and the scroll frame are created by the
      -- server UI and may not exist when we first load. Both hooks are
      -- idempotent, so a repeat call is free.
      PP.safeCall(HookJournalRefresh)
      PP.safeCall(HookTooltip, "GameTooltip")
      PP.safeCall(HookTooltip, "UtilsSpellTooltip")
      PP.safeCall(EF.RefreshBaseline)
    end
  end)
end
