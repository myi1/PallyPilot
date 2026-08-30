-- PallyPilot Dashboard: the always-on curated build reference (feature 2).
local PP = PallyPilot
local D = PP.Dashboard

local GOLD = "|cffe0b352"
local BRIGHT = "|cfff6d888"
local DIM = "|cffb4a586"
local ASH = "|cff9db3bd"
local EMBER = "|cffd9694a"
local VERD = "|cff8aa96a"
local R = "|r"

local frame, fs, content

local function H(t) return "\n" .. GOLD .. string.upper(t) .. R .. "\n" end
local function line(t) return t .. "\n" end

-- The focal element: one context-aware "what do I do right now?" line.
-- Reads live state (level, zone, build mode, ash, raid) so the player never
-- has to remember which of the tools/commands fits the moment.
function D.NextAction()
  local lvl = UnitLevel("player") or 80
  local zone = GetRealZoneText() or ""
  local mode = PP.db.buildMode
  local modeWord = (mode == "farm" and "Farm pool") or "Raid pool"

  -- 1. Run start — level to 80, banishing junk; the saved build restores at 80.
  if lvl <= 5 then
    return GOLD .. "Run start. " .. R
      .. "Level to 80 (" .. BRIGHT .. modeWord .. R
      .. " + banish junk as it appears). Your saved build restores by "
      .. BRIGHT .. "activating its Snapshot AT 80" .. R
      .. " (full swap, Epic quality included) — the old level-1 guarantee is gone."
  end
  -- 2. Prestige ready — spend into permanents, then reset.
  local st = PP.AshAdvisor and PP.AshAdvisor.GetState and PP.AshAdvisor.GetState()
  local gate = PP.AshData and PP.AshData.PRESTIGE and PP.AshData.PRESTIGE.gate
  if st and st.committed and gate and st.committed >= gate then
    return GOLD .. "Prestige ready. " .. R
      .. "Skill Tree \226\134\146 pour banked ash into the infinites (permanent), then prestige."
  end
  -- 3. Inside a known raid — route + boss cards.
  local raid = PP.GuideData and PP.GuideData.RaidForZone
    and PP.GuideData.RaidForZone(zone)
  if raid then
    local kills, n = PP.db.kills and PP.db.kills[zone], 0
    if kills then for _ in pairs(kills) do n = n + 1 end end
    return GOLD .. "In " .. raid.name .. ". " .. R
      .. "Raid guide for the route; target a boss for its card."
      .. (n > 0 and (DIM .. "  " .. n .. " down this lockout." .. R) or "")
  end
  -- 4. At 80 — activate a snapshot for full restore, or polish + save.
  if lvl >= 80 then
    return GOLD .. "At 80. " .. R
      .. "Have a saved build? " .. BRIGHT .. "activate its Snapshot now" .. R
      .. " for a full swap (Epic restored). Else polish (Reroll junk / orb-fish "
      .. "on a banished pool) and " .. BRIGHT .. "save at 80" .. R .. "."
  end
  -- 5. Leveling.
  return GOLD .. "Leveling (" .. (mode and string.upper(mode) or "?") .. "). " .. R
    .. "Auto-Pick is drafting — Rotation HUD for combat, Talents to guide points."
end

-- Trimmed reference: only what you actually re-read (stats, seal, rotation,
-- locks, gear). Echo tiers + affix schools were removed — that data now
-- lives as verdict dots on the journal tiles and character-sheet slots.
local function BuildText()
  local B = PP.Build
  local t = {}
  if not B then
    t[#t+1] = "\n" .. DIM .. "No EbonPilot guide for this class yet -- the tools "
      .. "(Ash advisor, Gear audit, Combat meter) still work." .. R
    return table.concat(t)
  end

  t[#t+1] = H("Stat priority")
  t[#t+1] = line(GOLD .. table.concat(B.statPriority or {}, "  >  ") .. R)
  if B.statNote then t[#t+1] = line(DIM .. B.statNote .. R) end

  if B.reference then
    -- Class-provided ordered sections (Hunter + future classes).
    for _, sec in ipairs(B.reference) do
      t[#t+1] = H(sec.title)
      for _, ln in ipairs(sec.lines or {}) do t[#t+1] = line("  " .. ln) end
    end
  else
    -- Legacy Paladin layout (Seal / Blessing / Rotation / locked echoes).
    t[#t+1] = H("Seal · blessing · rotation")
    t[#t+1] = line(GOLD .. "Seal " .. R .. (B.seal or "?"))
    t[#t+1] = line(GOLD .. "Blessing " .. R .. (B.blessing or "?"))
    t[#t+1] = line(BRIGHT .. "Rotation  " .. R .. (B.rotation or "?"))
    if B.locked then
      t[#t+1] = H("Lock these six")
      local locked = {}
      for _, n in ipairs(B.locked) do locked[#locked + 1] = n end
      t[#t+1] = line("  " .. BRIGHT .. table.concat(locked, DIM .. " · " .. BRIGHT) .. R)
    end
  end

  if B.gear then
    t[#t+1] = H("Gear targets")
    for _, g in ipairs(B.gear) do
      t[#t+1] = line("  " .. BRIGHT .. g.slot .. R .. " — " .. g.target)
    end
  end

  t[#t+1] = "\n" .. DIM .. "Echo verdicts show as LETTER badges on the journal "
    .. "tiles: S+ Keystone, S Carry, A Staple, B Filler, C Breadth, X Fodder "
    .. "(Echo audit for the list). Gear + affix verdicts show on your character "
    .. "sheet (Gear audit)." .. R
  return table.concat(t)
end

function D.Refresh()
  if frame and frame.now then
    frame.now:SetText(PP.safeCall and D.NextAction and D.NextAction() or "")
    if frame.status then
      local mode = PP.db.buildMode
      -- Mode chip carries the WORD (FARM/RAID) so it reads without color;
      -- FARM=ember, RAID=ash deliberately avoids a red/green pair.
      frame.status:SetText(DIM .. "Lv " .. (UnitLevel("player") or "?")
        .. "  ·  build " .. R
        .. (mode == "farm" and (EMBER .. "[FARM]") or (mode == "raid" and (ASH .. "[RAID]") or (DIM .. "[unsynced]")))
        .. R)
    end
  end
  if not fs then return end
  fs:SetText(BuildText())
  if content then content:SetHeight((fs:GetHeight() or 600) + 20) end
end

-- Palette (RGBA) for the solid-texture chrome. One warm-neutral hue, shifted
-- only in lightness across surfaces; gold is the single accent, used sparingly.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local C = {
  bg      = { 0.086, 0.078, 0.067, 0.96 }, -- window ground
  header  = { 0.135, 0.122, 0.102, 1 },    -- top strip (one step up)
  card    = { 0.125, 0.112, 0.090, 1 },     -- NEXT hero card
  divider = { 1, 1, 1, 0.09 },              -- hairline separators
  hover   = { 1, 1, 1, 0.06 },              -- nav hover wash
  bar     = { 0.878, 0.702, 0.322, 1 },     -- gold active accent
}
local TX = {
  active    = { 0.96, 0.85, 0.53 },  -- active nav / focal
  primary   = { 0.87, 0.83, 0.74 },  -- default nav
  secondary = { 0.72, 0.66, 0.56 },  -- tools
  muted     = { 0.55, 0.50, 0.42 },  -- section labels
}

-- Viewport views: sub-panels that swap into the shell in place. Each module
-- exposes GetFrame() (built on demand) + Refresh() (and optionally OnShow()).
local VIEWS = {
  audit = { label = "Echo Audit", mod = function() return PP.EchoAudit end },
  score = { label = "Build Score", mod = function() return PP.BuildScore end },
  gear  = { label = "Gear", mod = function() return PP.GearAudit end },
  farm  = { label = "Farm Queue", mod = function() return PP.FarmQueue end },
  raid  = { label = "Raid Guide", mod = function() return PP.RaidGuide end },
}

-- Swap the viewport to a view id ("home" or a VIEWS key). Reparents the target
-- panel into the shell, strips its window chrome, marks the active rail item.
function D.ShowView(id)
  if not frame then return end
  id = id or "home"
  if frame.shownFrame then frame.shownFrame:Hide(); frame.shownFrame = nil end
  frame.home:Hide()

  if id == "home" then
    frame.home:Show()
    frame.crumb:SetText("Home")
  else
    local v = VIEWS[id]
    local m = v and v.mod()
    if not m or not m.GetFrame then
      frame.home:Show(); frame.crumb:SetText("Home"); id = "home"
    else
      local f = m.GetFrame()
      f:SetParent(frame.viewport)
      f:ClearAllPoints(); f:SetAllPoints(frame.viewport)
      f:SetBackdrop(nil); f:SetMovable(false)
      if f.ppClose then f.ppClose:Hide() end
      if m.OnShow then PP.safeCall(m.OnShow) elseif m.Refresh then PP.safeCall(m.Refresh) end
      f:Show()
      frame.shownFrame = f
      frame.crumb:SetText(v.label)
    end
  end
  frame.view = id
  -- Active state: gold left bar + brighter label on the current view; the
  -- ">" text prefix carries it too, so it reads without color.
  if frame.navBtns then
    for vid, b in pairs(frame.navBtns) do
      local on = (vid == id)
      if on then b.bar:Show() else b.bar:Hide() end
      b.label:SetText((on and "> " or "") .. b.ppLabel)
      b.label:SetTextColor(unpack(on and TX.active or TX.primary))
    end
  end
end

-- Re-run whatever view is currently open, so the pane reflects a new build
-- instead of showing stale echoes. Called when the active build changes (server
-- "echoes were replaced" message, and the AshAdvisor loadout-switch signal).
function D.RefreshCurrent()
  if not (frame and frame:IsShown()) then return end
  PP.safeCall(D.Refresh)
  local id = frame.view
  if id and id ~= "home" then
    local v = VIEWS[id]
    local m = v and v.mod and v.mod()
    if m then
      if m.OnShow then PP.safeCall(m.OnShow)
      elseif m.Refresh then PP.safeCall(m.Refresh) end
    end
  end
end

-- The one public entry: open the shell and show a view (default home).
function D.Open(id)
  if not frame then D.Init() end
  D.Refresh()
  frame:Show(); frame:Raise()
  D.ShowView(id or "home")
end

-- Flat nav item: hover wash + gold active bar. Returns the button.
local function NavItem(parent, y, label, secondary)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(142); b:SetHeight(23)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
  local hl = b:CreateTexture(nil, "BACKGROUND")
  hl:SetPoint("TOPLEFT", b, "TOPLEFT", 6, 0)
  hl:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  hl:SetTexture(unpack(C.hover)); hl:Hide()
  b.bar = b:CreateTexture(nil, "OVERLAY")
  b.bar:SetPoint("LEFT", b, "LEFT", 3, 0); b.bar:SetWidth(3); b.bar:SetHeight(15)
  b.bar:SetTexture(unpack(C.bar)); b.bar:Hide()
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.label:SetPoint("LEFT", b, "LEFT", 14, 0)
  b.label:SetText(label)
  b.label:SetTextColor(unpack(secondary and TX.secondary or TX.primary))
  b:SetScript("OnEnter", function() hl:Show() end)
  b:SetScript("OnLeave", function() hl:Hide() end)
  return b
end

local function SectionLabel(parent, y, text)
  local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
  f:SetText(text); f:SetTextColor(unpack(TX.muted))
end

function D.Init()
  if frame then return end
  frame = CreateFrame("Frame", "PallyPilotFrame", UIParent)
  frame:SetWidth(640); frame:SetHeight(560)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint()
    PP.db.options.winPos = { x = x, y = y }
  end)
  -- Clean dark panel + hairline border (no parchment).
  frame:SetBackdrop({
    bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  frame:SetBackdropColor(unpack(C.bg))
  frame:SetBackdropBorderColor(1, 1, 1, 0.12)
  if PP.db.options.winPos then
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", PP.db.options.winPos.x, PP.db.options.winPos.y)
  end

  -- Header strip.
  local header = frame:CreateTexture(nil, "ARTWORK")
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
  header:SetHeight(36); header:SetTexture(unpack(C.header))
  local hdrLine = frame:CreateTexture(nil, "OVERLAY")
  hdrLine:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
  hdrLine:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
  hdrLine:SetHeight(1); hdrLine:SetTexture(unpack(C.divider))

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("LEFT", frame, "TOPLEFT", 16, -19)
  title:SetText(GOLD .. "EbonPilot" .. R)

  frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.status:SetPoint("LEFT", title, "RIGHT", 12, 0)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

  -- Left rail divider.
  local railLine = frame:CreateTexture(nil, "OVERLAY")
  railLine:SetPoint("TOPLEFT", frame, "TOPLEFT", 158, -37)
  railLine:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 158, 8)
  railLine:SetWidth(1); railLine:SetTexture(unpack(C.divider))

  -- Left nav rail: Views (swap the viewport) then Tools (fire their own thing).
  frame.navBtns = {}
  SectionLabel(frame, -46, "VIEWS")
  local views = {
    { "Home", "home" }, { "Build score", "score" }, { "Echo audit", "audit" },
    { "Farm tomes", "farm" }, { "Gear", "gear" }, { "Raid guide", "raid" },
  }
  local y = -64
  for _, v in ipairs(views) do
    local b = NavItem(frame, y, v[1], false)
    b.ppLabel = v[1]
    frame.navBtns[v[2]] = b
    local vid = v[2]
    b:SetScript("OnClick", function() D.ShowView(vid) end)
    y = y - 24
  end

  SectionLabel(frame, y - 8, "TOOLS")
  y = y - 26
  local tools = {
    -- Import the optimal build for THIS class from your available tomes: writes
    -- the class's tier ratings + best-owned locks into EbonholdHub, whose auto-pick
    -- then drafts it from the echoes you own. Class-aware; prints a note if the
    -- logged-in class has no echo data yet.
    { "Best build", function() if PP.HubSync and PP.HubSync.Push then PP.HubSync.Push() end end },
    { "Copy build code", function() if PP.HubSync and PP.HubSync.ShowExport then PP.HubSync.ShowExport() end end },
    { "Tome on/off", function() if PP.TomeManager then PP.TomeManager.Command("") end end },
    { "Rotation HUD", function() if PP.RotationHelper then PP.RotationHelper.Toggle() end end },
    { "Talents", function() if PP.Talents then PP.Talents.Guide() end end },
    { "Ash tree", function() if PP.AshAdvisor and PP.AshAdvisor.Command then PP.AshAdvisor.Command() end end },
  }
  for _, t in ipairs(tools) do
    local b = NavItem(frame, y, t[1], true)
    b:SetScript("OnClick", t[2])
    y = y - 24
  end

  -- Content header: the current view name (breadcrumb).
  frame.crumb = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.crumb:SetPoint("TOPLEFT", frame, "TOPLEFT", 172, -48)
  frame.crumb:SetTextColor(unpack(TX.active))

  -- Viewport: the swappable region every view lives in.
  frame.viewport = CreateFrame("Frame", nil, frame)
  frame.viewport:SetPoint("TOPLEFT", frame, "TOPLEFT", 168, -74)
  frame.viewport:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)

  -- Home lives inside the viewport: focal NEXT hero + reference scroll.
  frame.home = CreateFrame("Frame", nil, frame.viewport)
  frame.home:SetAllPoints(frame.viewport)

  local nowCard = CreateFrame("Frame", nil, frame.home)
  nowCard:SetPoint("TOPLEFT", frame.home, "TOPLEFT", 0, 0)
  nowCard:SetPoint("TOPRIGHT", frame.home, "TOPRIGHT", -6, 0)
  nowCard:SetHeight(66)
  nowCard:SetBackdrop({
    bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  nowCard:SetBackdropColor(unpack(C.card))
  nowCard:SetBackdropBorderColor(1, 1, 1, 0.08)
  local nowBar = nowCard:CreateTexture(nil, "OVERLAY")
  nowBar:SetPoint("TOPLEFT", nowCard, "TOPLEFT", 0, 0)
  nowBar:SetPoint("BOTTOMLEFT", nowCard, "BOTTOMLEFT", 0, 0)
  nowBar:SetWidth(3); nowBar:SetTexture(unpack(C.bar))
  local nowHead = nowCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  nowHead:SetPoint("TOPLEFT", nowCard, "TOPLEFT", 14, -10)
  nowHead:SetText(GOLD .. "NEXT" .. R)
  frame.now = nowCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.now:SetPoint("TOPLEFT", nowCard, "TOPLEFT", 14, -26)
  frame.now:SetPoint("BOTTOMRIGHT", nowCard, "BOTTOMRIGHT", -12, 8)
  frame.now:SetJustifyH("LEFT"); frame.now:SetJustifyV("TOP")

  local scroll = CreateFrame("ScrollFrame", "PallyPilotScroll", frame.home, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame.home, "TOPLEFT", 0, -78)
  scroll:SetPoint("BOTTOMRIGHT", frame.home, "BOTTOMRIGHT", -26, 2)
  content = CreateFrame("Frame", nil, scroll)
  content:SetWidth(430); content:SetHeight(10)
  scroll:SetScrollChild(content)
  fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  fs:SetWidth(426); fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
  fs:SetSpacing(3)
  fs:SetText("")

  -- Keep the focal NOW line current while the shell is open (cheap, 3s).
  frame.elapsed = 0
  frame:SetScript("OnUpdate", function(self, e)
    self.elapsed = self.elapsed + e
    if self.elapsed > 3 then
      self.elapsed = 0
      if self.now and self.view == "home" then self.now:SetText(D.NextAction()) end
    end
  end)

  -- Auto-refresh the open pane when the server swaps your echoes (build change).
  local ev = CreateFrame("Frame")
  ev:RegisterEvent("CHAT_MSG_SYSTEM")
  ev:SetScript("OnEvent", function(_, _, msg)
    if msg and (string.find(string.lower(msg), "echoes were replaced", 1, true)
      or string.find(string.lower(msg), "build applied", 1, true)) then
      PP.safeCall(D.RefreshCurrent)
    end
  end)

  D.Refresh()
  D.ShowView("home")
  frame:Hide()
end

function D.Toggle()
  if not frame then D.Init() end
  if frame:IsShown() then frame:Hide() else D.Open("home") end
end
