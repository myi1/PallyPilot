-- EbonPilot RerollTarget: chase ONE specific echo through orb rerolls.
--
-- This is deliberately NOT a bot. It never loops rerolls for you -- Ebonhold
-- bans automation and that is your main account at risk. Every roll stays your
-- click. What it does instead is attack the part that actually costs you orbs:
-- the ODDS. A reroll is a random draw from your enabled pool, so the only real
-- lever is making that pool smaller, and nothing in the UI tells you that.
--
-- It gives you: your true per-roll chance, a ranked list of what to banish to
-- improve it (banishes persist), instant "STOP - you got it" detection so you
-- don't overshoot, and an orb budget so you know when to walk away.
local PP = PallyPilot
local RT = {}
PP.RerollTarget = RT

local GOLD = "|cffe0b352"
local BRIGHT = "|cfff6d888"
local DIM = "|cffb4a586"
local EMBER = "|cffd9694a"
local VERD = "|cff8aa96a"
local R = "|r"

local DRAW = 3   -- echoes offered per reroll draw

local function Norm(s) return (string.lower(s or ""):gsub("\226\128\153", "'")) end

-- Echoes that can currently come up: owned tome, not already in the run.
-- (Banished ones are also excluded by the server, but the client doesn't expose
-- the banish list -- so this is an UPPER BOUND on the pool. Stated, not hidden.)
local function Pool()
  local A = PP.EchoAudit
  if not (A and A.WantList) then return nil end
  local gp = ProjectEbonhold and ProjectEbonhold.Perks
    and ProjectEbonhold.Perks.grantedPerks
  if not gp then return nil end
  local want = A.WantList()          -- rated + owned + not in run
  local junk = A.RerollList and A.RerollList() or {}
  return want, junk
end

-- ---------------------------------------------------------------------------
-- THE ACTUAL DECISION: reroll, or start a fresh run? These are not equivalent,
-- and the constraints that decide it are mechanical, not preference:
--   * The ORB can only recycle echoes that are IN YOUR RUN. No junk in the run
--     = no fodder = you literally cannot reroll, however many orbs you hold.
--   * LEVEL-UP draws are FREE and draw from the same pool, and EbonholdHub's
--     auto-pick takes whatever our tiers rate highest -- so a fresh run is a
--     long series of free attempts at everything you're missing at once.
--   * A reroll chases ONE echo at a time at pool odds; a relevel chases them
--     ALL. The more you're missing, the worse rerolling looks.
--   * Restarting costs the run's quality (Epic stacks) and the time to climb.
--     At 80 a saved Snapshot restores a build instantly, which softens that.
-- Returns headline, detail.
function RT.Advice()
  local want = Pool()
  if not want then return nil end
  local fodder = (PP.EchoFlow and PP.EchoFlow.RunJunkList and PP.EchoFlow.RunJunkList()) or {}
  local pool = PP.EchoAudit.PoolSize and PP.EchoAudit.PoolSize() or #want
  local missing = 0
  for _, w in ipairs(want) do if not w.disabled then missing = missing + 1 end end
  local lvl = UnitLevel("player") or 80
  local rolls = math.max(1, math.floor((pool or 1) / DRAW + 0.5))

  if lvl < 80 then
    return VERD .. "KEEP LEVELLING -- don't spend orbs.",
      DIM .. "You are level " .. lvl .. ". Every level-up is a FREE draw from the "
      .. "same pool, and auto-pick takes your top-rated echo. Orbs are the "
      .. "level-80 tool, for when free draws have run out." .. R
  end
  if #fodder == 0 then
    return EMBER .. "YOU CANNOT REROLL RIGHT NOW.",
      DIM .. "The orb only recycles echoes that are IN your run, and yours has no "
      .. "junk to spend -- orbs don't help. Your options are a " .. R .. BRIGHT
      .. "fresh run" .. R .. DIM .. " (free draws all the way up; auto-pick takes "
      .. "these for you) or playing on until you draft something junk enough to "
      .. "feed it." .. R
  end
  if missing >= 8 then
    return BRIGHT .. "A FRESH RUN IS PROBABLY BETTER.",
      DIM .. "You're missing " .. missing .. " rated echoes. Rerolling chases ONE "
      .. "at ~" .. rolls .. " rolls each; a relevel draws for all of them free. "
      .. "Reroll only if you want one specific echo NOW and can accept the orb "
      .. "cost." .. R
  end
  return VERD .. "REROLLING IS THE RIGHT CALL.",
    DIM .. "Only " .. missing .. " rated echo(es) missing and you have " .. #fodder
    .. " fodder in run -- cheaper than releveling. ~" .. rolls .. " rolls for a "
    .. "given target." .. R
end

function RT.Set(name)
  if not name or name == "" then
    PP.print("Name the echo to chase: " .. GOLD .. "/ep reroll Temporal Pressure" .. R)
    return
  end
  local want = Pool()
  if not want then
    PP.print("Need your run loaded (level 80, in a run) + EbonholdHub to work out odds.")
    return
  end
  -- Resolve against what can actually be drawn; substring match is fine.
  local n, hit = Norm(name), nil
  for _, w in ipairs(want) do
    if Norm(w.name) == n then hit = w break end
  end
  if not hit then
    for _, w in ipairs(want) do
      if string.find(Norm(w.name), n, 1, true) then hit = w break end
    end
  end
  if not hit then
    -- Say WHICH reason, instead of listing possibilities and hoping.
    local gp = ProjectEbonhold and ProjectEbonhold.Perks
      and ProjectEbonhold.Perks.grantedPerks
    local inRun = false
    for key in pairs(gp or {}) do
      if type(key) == "string" and Norm(key):find(n, 1, true) then inRun = true break end
    end
    if inRun then
      PP.print(VERD .. "You already have " .. name .. " in this build." .. R
        .. DIM .. " Nothing to chase." .. R)
    elseif not (PP.TomeManager and PP.TomeManager.MergedTiles
                and PP.TomeManager.MergedTiles()) then
      PP.print(EMBER .. "Can't read your tome collection." .. R .. DIM
        .. " Open the Echoes window once (the catalog tiles are where the real "
        .. "owned/disabled state lives), then try again." .. R)
    else
      PP.print(EMBER .. "'" .. name .. "' isn't in your chaseable list." .. R .. DIM
        .. " Either you don't own the tome, or it isn't rated CORE/S/A for this "
        .. "class. " .. R .. GOLD .. "/ep want" .. R .. DIM .. " lists what is." .. R)
    end
    return
  end
  -- A disabled tome is never offered, so chasing it would burn orbs for nothing.
  if hit.disabled then
    PP.print(EMBER .. hit.name .. "'s TOME IS SWITCHED OFF." .. R .. DIM
      .. " It cannot be drawn at all -- rolling for it would waste every orb. "
      .. "Tome toggling is LEVEL-1 ONLY, so re-enable it at the start of your next "
      .. "run (" .. R .. GOLD .. "/ep tome" .. R .. DIM .. "), then chase it." .. R)
    return
  end
  PP.db.rerollTarget = { name = hit.name, tier = hit.tier,
                         startOrbs = nil, rolls = 0, set = date("%H:%M") }
  RT.Status()
end

function RT.Status()
  local t = PP.db and PP.db.rerollTarget
  if not t then
    PP.print("No reroll target. " .. GOLD .. "/ep reroll <echo>" .. R .. " to set one.")
    return
  end
  local want = Pool()
  if not want then PP.print("Run not loaded -- can't recompute odds.") return end

  local still = false
  for _, w in ipairs(want) do if Norm(w.name) == Norm(t.name) then still = true break end end
  if not still then
    PP.print(VERD .. "STOP -- you have " .. t.name .. "." .. R
      .. DIM .. " Target cleared after " .. (t.rolls or 0) .. " roll(s) tracked." .. R)
    PP.db.rerollTarget = nil
    return
  end

  -- Odds come from the FULL enabled pool (PoolSize), never #want -- the pool
  -- includes B/C junk the shortlist doesn't, and quoting the shortlist as the
  -- pool overstated the odds ~3x (Codex-review finding). Its junk names are
  -- also the correct banish list: pool entries, not the run's fodder -- the old
  -- code listed run fodder here AND double-subtracted it from a pool that
  -- never contained it.
  local pool, poolJunk, junkNames = PP.EchoAudit.PoolSize and PP.EchoAudit.PoolSize()
  if not pool or pool == 0 then
    PP.print(GOLD .. "CHASING " .. R .. BRIGHT .. "[" .. (t.tier or "?") .. "] "
      .. t.name .. R .. DIM .. " -- pool unreadable (open the Echoes window once), "
      .. "so no odds quoted. The stop-watch is still armed." .. R)
    return
  end

  local chance = math.min(1, DRAW / pool)
  PP.print(GOLD .. "CHASING " .. R .. BRIGHT .. "[" .. (t.tier or "?") .. "] "
    .. t.name .. R)
  PP.print("   " .. DIM .. "pool " .. R .. pool .. DIM .. " enabled echoes · draw "
    .. DRAW .. " per roll -> " .. R .. BRIGHT
    .. string.format("%.0f%%", chance * 100) .. R .. DIM .. " per roll · about " .. R
    .. BRIGHT .. math.max(1, math.floor(pool / DRAW + 0.5)) .. R .. DIM .. " rolls expected" .. R)

  -- BANISH IS NOT A THING YOU DO. Corrected in-game 2026-09-01, twice:
  --   1. Banishes are offered on the 1-80 level-up draws, not on orb rerolls
  --      at 80 -- so at 80 the pool is simply whatever you arrived with.
  --   2. During levelling, EbonholdHub's automation spends them for you
  --      (Automation.lua: TryBanishF / TryBanishDisposable, driven by the
  --      synced tiers). The player never clicks a banish either way.
  -- So the only actionable advice is upstream: make sure the build EBH is
  -- scoring against is ours. Never print a "banish these" list again.
  local lvl = UnitLevel("player") or 80
  if lvl >= 80 then
    PP.print("   " .. DIM .. "At 80 the pool is fixed. Banish only happens on "
      .. "level-up draws, and EBH spends those for you." .. R)
  else
    PP.print("   " .. DIM .. "EBH's automation is picking and banishing for you. "
      .. "Nothing to do here -- just keep the build synced (/ep bis -> Sync)." .. R)
  end
  PP.print("   " .. DIM .. "Each roll is YOUR click. I'll say STOP the moment it lands." .. R)
end

function RT.Clear()
  PP.db.rerollTarget = nil
  PP.print("Reroll target cleared.")
end

function RT.Command(arg)
  arg = arg or ""
  local low = string.lower(arg)
  if low == "" or low == "status" then RT.Status()
  elseif low == "clear" or low == "stop" then RT.Clear()
  else RT.Set(arg) end
end

-- ---------------------------------------------------------------------------
-- PANEL. Same job as /ep reroll, but you click the echo instead of typing it --
-- and the odds and banish list stay on screen while you roll, which is when you
-- actually need them.
local frame, content, rows = nil, nil, {}
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function GetRow(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Frame", nil, content)
  r:SetWidth(430); r:SetHeight(18)
  r.tier = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.tier:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -2); r.tier:SetWidth(48)
  r.tier:SetJustifyH("LEFT")
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 50, -2)
  r.name:SetWidth(180); r.name:SetJustifyH("LEFT")
  r.odds = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.odds:SetPoint("TOPLEFT", r, "TOPLEFT", 232, -2)
  r.odds:SetWidth(96); r.odds:SetJustifyH("LEFT")
  r.btn = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
  r.btn:SetWidth(74); r.btn:SetHeight(18)
  r.btn:SetPoint("TOPLEFT", r, "TOPLEFT", 330, 0)
  rows[i] = r
  return r
end

function RT.Refresh()
  if not (frame and content) then return end
  local want, junk = Pool()
  local t = PP.db and PP.db.rerollTarget

  if not want then
    frame.head:SetText(EMBER .. "Can't read your tome collection yet." .. R .. DIM
      .. "  Open the " .. R .. BRIGHT .. "Echoes" .. R .. DIM .. " window once this "
      .. "session -- the catalog tiles are the only place the real learned/disabled "
      .. "state lives -- then come back." .. R)
    for _, r in ipairs(rows) do r:Hide() end
    frame.now:SetText(""); content:SetHeight(10)
    return
  end

  -- Odds must use the FULL enabled pool -- the game draws from every learned,
  -- enabled tome not in the run, not just the ones worth having. Counting only
  -- the rated shortlist (as this did at first) overstates your chances badly.
  local pool, poolJunk = PP.EchoAudit.PoolSize()
  if not pool or pool == 0 then
    local n = 0
    for _, w in ipairs(want) do if not w.disabled then n = n + 1 end end
    pool, poolJunk = math.max(1, n), 0
  end
  local chance = math.min(1, DRAW / pool)
  local after = math.max(1, pool - (poolJunk or 0))
  local chanceAfter = math.min(1, DRAW / after)

  -- Ebonhold's echo system is genuinely confusing, so this panel is written to
  -- TEACH as well as compute: what to do, why, and the one rule that explains
  -- it -- in that order, because the decision matters more than the mechanic.
  local verdict, why = RT.Advice()
  frame.head:SetText((verdict or "") .. R .. "\n" .. (why or "") .. "\n"
    -- Corrected 2026-09-01: you DO pick the sacrifice, and it need not be junk.
    -- The old text claimed a reroll "EATS one junk echo... you can't pick",
    -- which is wrong twice over and is what produced the "out of fodder"
    -- dead ends.
    .. DIM .. "How it works: YOU pick an echo to feed the orb; it is consumed "
    .. "and rerolled into a fresh draw. More orbs, better draw. Level-ups draw "
    .. "the same way, but free." .. R)

  -- What the orb would actually consume: junk that is IN YOUR RUN right now.
  local fodder = (PP.EchoFlow and PP.EchoFlow.RunJunkList and PP.EchoFlow.RunJunkList()) or {}
  local running = PP.EchoFlow and PP.EchoFlow.IsRunning and PP.EchoFlow.IsRunning()

  if t then
    -- Keep this to THREE short lines; it sits above the list and the list is
    -- repositioned under it, so verbose copy squeezes the thing you came for.
    local msg = GOLD .. "CHASING " .. R .. BRIGHT .. t.name .. R .. DIM
      .. "  " .. string.format("%.0f%%", chance * 100) .. "/roll, ~"
      .. math.max(1, math.floor(pool / DRAW + 0.5)) .. " rolls (pool " .. pool .. ")" .. R
    -- Banish is a LEVELLING lever and EBH spends it automatically, so quoting
    -- a post-banish rate to someone at 80 is advice they cannot act on.
    if (poolJunk or 0) > 0 and (UnitLevel("player") or 80) < 80 then
      msg = msg .. "\n" .. DIM .. "EBH will banish ~" .. poolJunk .. " pool junk -> "
        .. R .. VERD .. string.format("%.0f%%", chanceAfter * 100) .. R
        .. DIM .. "/roll" .. R
    end
    if #fodder > 0 then
      local shown = {}
      for i = 1, math.min(#fodder, 2) do shown[#shown + 1] = tostring(fodder[i]) end
      msg = msg .. "\n" .. DIM .. "Feeds: " .. R .. table.concat(shown, ", ")
        .. (#fodder > 2 and (DIM .. " +" .. (#fodder - 2) .. R) or "")
    else
      msg = msg .. "\n" .. EMBER .. "No junk in run -- nothing safe to feed the orb." .. R
    end
    frame.now:SetText(msg)
    frame.stop:Show()
    frame.roll:Show()
    frame.roll:SetText(running and "STOP rolling" or ("Roll (" .. #fodder .. ")"))
    if #fodder == 0 and not running then frame.roll:Disable() else frame.roll:Enable() end
  else
    frame.now:SetText(DIM .. "Nothing being chased. Pick one below." .. R)
    frame.stop:Hide()
    frame.roll:Hide()
  end

  -- Reposition the list UNDER the header block. The header wraps to a variable
  -- number of lines, so a fixed offset (what this had) let it overlap the rows.
  -- Stack everything downward from the header, since each block's height
  -- depends on how far its text wrapped. Fixed offsets are what caused the
  -- overlap: the header grew and the blocks below stayed put.
  local headBottom = 54 + (frame.head:GetStringHeight() or 24) + 8
  frame.now:ClearAllPoints()
  frame.now:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -headBottom)
  frame.roll:ClearAllPoints()
  frame.roll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -32, -headBottom + 2)
  frame.stop:ClearAllPoints()
  frame.stop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -32, -headBottom - 24)

  if frame.scroll then
    local top = headBottom + (frame.now:GetStringHeight() or 0) + 14
    frame.scroll:ClearAllPoints()
    frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -top)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 14)
  end

  for _, r in ipairs(rows) do r:Hide() end
  local y, i = 0, 0
  for _, w in ipairs(want) do
    i = i + 1
    local r = GetRow(i)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    r.tier:SetText(BRIGHT .. "[" .. w.tier .. "]" .. R)
    r.name:SetText(w.name)
    local chasing = t and Norm(t.name) == Norm(w.name)
    if w.disabled then
      -- Can never be drawn; say why instead of offering a useless button.
      r.odds:SetText(EMBER .. "TOME OFF" .. R)
      r.btn:Hide()
    else
      r.odds:SetText(chasing and (VERD .. "chasing" .. R)
        or (DIM .. string.format("%.0f%%", chance * 100) .. "/roll" .. R))
      r.btn:Show()
      r.btn:SetText(chasing and "Stop" or "Chase")
      local nm = w.name
      r.btn:SetScript("OnClick", function()
        if PP.db.rerollTarget and Norm(PP.db.rerollTarget.name) == Norm(nm) then
          PP.db.rerollTarget = nil
        else
          RT.Set(nm)
        end
        PP.safeCall(RT.Refresh)
      end)
    end
    r:Show()
    y = y + 19
  end
  if i == 0 then
    frame.now:SetText(VERD .. "Nothing to chase" .. R .. DIM
      .. " -- every rated echo you own is already in this build." .. R)
  end
  content:SetHeight(math.max(10, y + 4))
end

function RT.InitPanel()
  if frame then return end
  frame = CreateFrame("Frame", "EbonPilotChaseFrame", UIParent)
  frame:SetWidth(480); frame:SetHeight(560)
  frame:SetPoint("CENTER", UIParent, "CENTER", -30, 0)
  frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  frame:SetBackdropColor(0.086, 0.078, 0.067, 0.96)
  frame:SetBackdropBorderColor(1, 1, 1, 0.12)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
  title:SetText(GOLD .. "Chase an echo" .. R)
  local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -34)
  sub:SetWidth(430); sub:SetJustifyH("LEFT")
  sub:SetText(DIM .. "Get a specific echo into your build." .. R)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
  frame.ppClose = close

  frame.head = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.head:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -54)
  frame.head:SetWidth(430); frame.head:SetJustifyH("LEFT"); frame.head:SetSpacing(2)

  frame.now = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  -- Width stops short of the buttons on the right (they start at x=344) --
  -- at 346 the text ran under them, which is what the overlap was.
  frame.now:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -74)
  frame.now:SetWidth(310); frame.now:SetJustifyH("LEFT"); frame.now:SetSpacing(2)

  -- The action button: runs the SAME engine as the rail's "Reroll junk", but
  -- from here, with the chase target armed so it halts the moment you get it.
  frame.roll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.roll:SetWidth(104); frame.roll:SetHeight(22)
  frame.roll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -32, -72)
  frame.roll:SetText("Roll")
  frame.roll:SetScript("OnClick", function()
    if PP.EchoFlow and PP.EchoFlow.StartReroll then
      PP.safeCall(PP.EchoFlow.StartReroll)   -- toggles: starts, or stops if running
      PP.safeCall(RT.Refresh)
    end
  end)

  frame.stop = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.stop:SetWidth(104); frame.stop:SetHeight(18)
  frame.stop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -32, -96)
  frame.stop:SetText("Stop chase")
  frame.stop:SetScript("OnClick", function()
    PP.db.rerollTarget = nil; PP.safeCall(RT.Refresh)
  end)

  local scroll = CreateFrame("ScrollFrame", "EbonPilotChaseScroll", frame,
    "UIPanelScrollFrameTemplate")
  frame.scroll = scroll                     -- Refresh re-anchors this each pass
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -118)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 14)
  content = CreateFrame("Frame", nil, scroll)
  content:SetWidth(430); content:SetHeight(10)
  scroll:SetScrollChild(content)

  -- Keep it live while open: the fodder count drops and the Roll button flips
  -- to STOP as the queue runs, so a static panel would lie within a second.
  frame.acc = 0
  frame:SetScript("OnUpdate", function(self, e)
    self.acc = self.acc + e
    if self.acc > 1 then self.acc = 0; PP.safeCall(RT.Refresh) end
  end)
  frame:SetScript("OnShow", function() PP.safeCall(RT.Refresh) end)
  frame:Hide()
end

function RT.GetFrame()
  if not frame then RT.InitPanel() end
  return frame
end

-- Watch for the target landing so you stop rolling the instant you have it.
function RT.Init()
  if RT.__hooked then return end
  RT.__hooked = true
  local f, acc = CreateFrame("Frame"), 0
  f:SetScript("OnUpdate", function(_, e)
    local t = PP.db and PP.db.rerollTarget
    if not t then return end
    acc = acc + e
    if acc < 1 then return end
    acc = 0
    local gp = ProjectEbonhold and ProjectEbonhold.Perks
      and ProjectEbonhold.Perks.grantedPerks
    if not gp then return end
    for key in pairs(gp) do
      if type(key) == "string" and Norm(key):find(Norm(t.name), 1, true) then
        -- Halt the queue FIRST -- otherwise it keeps chewing fodder (and orbs)
        -- through the rest of its list after you've already won.
        if PP.EchoFlow and PP.EchoFlow.Stop then
          PP.safeCall(PP.EchoFlow.Stop, "Got " .. t.name .. " -- queue halted.")
        end
        PP.print(VERD .. "STOP -- " .. t.name .. " is in your build." .. R
          .. DIM .. " Rolling halted." .. R)
        PP.db.rerollTarget = nil
        if PP.EchoFlow and PP.EchoFlow.RefreshRail then
          PP.safeCall(PP.EchoFlow.RefreshRail)
        end
        PP.safeCall(RT.Refresh)
        return
      end
    end
  end)
end
