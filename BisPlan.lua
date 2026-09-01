-- EbonPilot BisPlan: the explicit TARGET BUILD, and the pipeline that drives
-- every tool toward it.
--
-- WHY THIS EXISTS: you cannot pick echoes on Ebonhold -- you draft them
-- (level-ups) or reroll them (orbs, random 3-draw from the ENABLED pool). So
-- "build the BiS loadout" is not one action, it is a pipeline with exactly
-- four levers, each owned by a different module:
--   1. OWN the tome        -> FarmQueue        (can't draw what you don't own)
--   2. CURATE the pool     -> TomeManager      (level-1 only)
--      SCOPE, verified in-game 2026-09-01: only UNLOCKABLE (tome) echoes can be
--      toggled. The pre-unlocked base pool is fixed and cannot be curated at
--      all. So curation does NOT concentrate every draw onto the target list --
--      it removes the tome echoes you unlocked but don't want. Corollary that
--      matters more than the toggling: every tome you unlock PERMANENTLY
--      enlarges your draw pool, so unlocking a non-target tome is a downgrade
--      until you disable it.
--   3. DRAFT / CHASE it    -> auto-pick + RerollTarget (get it into the run)
--   4. POLISH quality      -> EchoFlow fish    (Epic ~10x Common; one-time
--      cost -- a Snapshot save keeps quality forever)
-- Then LOCK the core and SAVE the loadout at 80.
--
-- This module holds the target list and shows, per target echo, exactly which
-- lever is next. Colorblind: every state is a WORD.
local PP = PallyPilot
local BP = {}
PP.BisPlan = BP

local GOLD = "|cffe0b352"
local BRIGHT = "|cfff6d888"
local DIM = "|cffb4a586"
local EMBER = "|cffd9694a"
local VERD = "|cff8aa96a"
local R = "|r"

local function Norm(s)
  s = string.lower(s or "")
  s = s:gsub("\226\128\153", "'")
  return s
end
-- Quality suffixes are stripped explicitly -- Lua patterns have no alternation,
-- so a single (a|b|c) pattern silently matches nothing.
local QUAL_SUFFIX = { "common", "uncommon", "rare", "epic", "legendary", "artifact" }
local function StripQ(s)
  for _, q in ipairs(QUAL_SUFFIX) do
    local cut = s:match("^(.-)%s*%-%s*" .. q .. "$")
    if cut then return cut end
  end
  return s
end

-- ---------------------------------------------------------------------------
-- THE TARGET. Locked cores (in lock-priority order) + the curated S tier +
-- catalog S. This IS the BiS list -- it is the same data auto-pick drafts from
-- (HubSync publishes it), so every part of the addon aims at one list.
-- THE TARGET IS NOW THE **CHASE** LIST, NOT EVERY S-TIER NAME.
--
-- It used to be locked + all S, which is ~43 echoes. That was the wrong shape:
-- it drove pool curation to cut everything else, and pool size is a damage stat
-- (Adaptive Power). Chasing 43 things is also not chasing -- you cannot spend
-- orbs meaningfully across that many.
--
-- So: CHASE (~12, what orbs are for) is the target; KEEP (generous, what stays
-- enabled) lives in BuildData.KeepSet() and drives the tome pool instead.
local targetCache, targetSet
function BP.Target()
  if targetCache then return targetCache end
  local B = PP.Build
  if not (B and B.locked and B.ChaseList) then return nil end
  local out, seen = {}, {}
  local function add(name, role)
    local k = Norm(name)
    if not seen[k] then
      seen[k] = true
      out[#out + 1] = { name = name, role = role, key = k,
        why = B.ChaseReason and B.ChaseReason(name) or nil }
    end
  end
  -- Locks first (they are already committed), then the rest of CHASE in
  -- priority order.
  for _, n in ipairs(B.locked) do add(n, "CORE") end
  for _, n in ipairs(B.ChaseList()) do add(n, "CHASE") end
  targetCache = out
  targetSet = seen
  return out
end

-- KEEP is the wider "leave it enabled" set. Pool curation asks this, never
-- IsTarget -- otherwise it cuts breadth the build is paid for having.
function BP.IsKeep(name)
  local B = PP.Build
  if not (B and B.IsKeep) then return false end
  return B.IsKeep(StripQ(Norm(name or "")))
end

function BP.IsTarget(name)
  if not targetSet then BP.Target() end
  return targetSet and targetSet[StripQ(Norm(name or ""))] or false
end

-- ---------------------------------------------------------------------------
-- Live status per target echo. Sources chosen per this project's hard-won
-- rules: TILES = tome collection (owned/disabled/locked; needs the Echoes
-- window opened once); EBH CollectOwnedSets = the RUN set, locks included;
-- grantedPerks = per-echo QUALITY, but it omits locked echoes.
local function RunSet()
  if EbonholdHub and EbonholdHub.EchoOwnership
     and EbonholdHub.EchoOwnership.CollectOwnedSets then
    local ok, owned = pcall(EbonholdHub.EchoOwnership.CollectOwnedSets)
    if ok and type(owned) == "table" then
      local set = {}
      for lower in pairs(owned) do set[StripQ(Norm(lower))] = true end
      return set
    end
  end
  return nil
end

local function QualityMap()
  local gp = ProjectEbonhold and ProjectEbonhold.Perks
    and ProjectEbonhold.Perks.grantedPerks
  if not gp then return nil end
  local q = {}
  for key, value in pairs(gp) do
    if type(key) == "string" then
      local stacks = (type(value) == "table" and value[1] ~= nil) and value or { value }
      local minq
      for _, e in ipairs(stacks) do
        if type(e) == "table" and e.quality and (not minq or e.quality < minq) then
          minq = e.quality
        end
      end
      if minq then
        -- Variant keys ("X - Rare" / "X - Epic") collapse to one base key; keep
        -- the MINIMUM across them so a sub-Epic stack can't hide behind an Epic.
        local k = StripQ(Norm(key))
        if not q[k] or minq < q[k] then q[k] = minq end
      end
    end
  end
  return q
end

-- states: LOCKED | EPIC | FISH | INRUN | ROLL | OFF | FARM  (all words)
function BP.Status()
  local target = BP.Target()
  if not target then return nil, "nodata" end
  -- MergedTiles, never AllTiles: the journal scroll is virtualized, so the live
  -- read is whatever happens to be on screen. Asking it "do I own this?" is how
  -- this panel once reported 10 owned echoes as FARM.
  -- Call it on its own line. An `a and b and f()` chain is a single-value
  -- expression, so the second return (tileSource) was always nil and the
  -- PARTIAL READ warning could never fire. Same multi-return truncation that
  -- has bitten this project before -- never wrap a multi-return call in a
  -- guard chain.
  local tiles, tileSource
  if PP.TomeManager and PP.TomeManager.MergedTiles then
    tiles, tileSource = PP.TomeManager.MergedTiles()
  end
  if not tiles then return nil, "closed" end
  local tmap = {}
  for _, t in ipairs(tiles) do
    if t.name then
      local k = StripQ(Norm(t.name))
      local e = tmap[k]
      if not e then e = { known = false, anyOn = false, locked = false }; tmap[k] = e end
      e.known = e.known or t.known
      -- Drawable if ANY quality variant is enabled. (The review caught the
      -- previous and/or ternary here: with a FALSE middle operand the whole
      -- expression collapses to the else-branch's nil, so the merge silently
      -- inverted depending on tile order. Lua's a-and-b-or-c is only a ternary
      -- when b can never be falsy -- track the positive fact instead.)
      e.anyOn = e.anyOn or (t.known and not t.disabled)
      e.locked = e.locked or t.locked
    end
  end
  -- The RUN set is the ground truth for "already have it". If the hub can't be
  -- read, say so -- an empty table here would mark everything [ROLL] and tell
  -- the user to chase echoes they may already have. Confidently wrong > absent.
  local run = RunSet()
  if not run then return nil, "nohub" end
  local qual = QualityMap()
  local qualUnknown = (qual == nil)
  qual = qual or {}

  local out = { list = {}, counts = { LOCKED = 0, EPIC = 0, FISH = 0, INRUN = 0,
                                      ROLL = 0, OFF = 0, FARM = 0 } }
  for _, tgt in ipairs(target) do
    local t = tmap[tgt.key]
    local st, q
    -- THE RUN OUTRANKS THE CATALOG. If an echo is in your run, no tome question
    -- can matter -- you demonstrably have it. Checking "known" first meant six
    -- echoes sitting in the run at Epic (Twilight Equilibrium, Adaptive Power,
    -- Ambidexterity, Pandemic among them) were reported as [FARM].
    --
    -- The underlying trap: `tomeKnown` is false for echoes that need no tome at
    -- all, so "no tome" and "cannot have it" are NOT the same thing, and the
    -- old ordering conflated them.
    if run[tgt.key] then
      if t and t.locked then
        st = "LOCKED"
      else
        q = qual[tgt.key]
        if q and q >= 3 then st = "EPIC"
        elseif q then st = "FISH"
        else st = "INRUN" end
      end
    elseif t and t.locked then
      st = "LOCKED"
    elseif t and t.known and not t.anyOn then
      st = "OFF"
    elseif t and t.known then
      st = "ROLL"
    elseif t then
      -- Tile exists but no tome: it may still be a base-pool echo, which is
      -- drawable and cannot be farmed. Rollable, not farmable.
      st = "ROLL"
    else
      st = "FARM"
    end
    out.counts[st] = out.counts[st] + 1
    out.list[#out.list + 1] = { name = tgt.name, role = tgt.role, state = st, q = q }
  end
  out.total = #target
  out.done = out.counts.LOCKED + out.counts.EPIC
  out.qualUnknown = qualUnknown
  -- "live-partial" means no full scan has been taken, so FARM counts are only
  -- as complete as whatever the scroll had rendered. The panel says so rather
  -- than presenting a slice as fact.
  out.tileSource = tileSource
  out.runEmpty = (next(run) == nil)
  return out
end

-- ---------------------------------------------------------------------------
-- The focal NEXT action -- one sentence, picked by leverage at the current
-- moment. Level 1 is special: it is the ONLY time the pool can be curated.
function BP.NextAction(st)
  local lvl = UnitLevel("player") or 80
  local c = st.counts
  if lvl == 1 and (c.OFF > 0 or true) then
    return GOLD .. "LEVEL 1 -- curate the pool NOW." .. R .. DIM
      .. " This is the only moment tome toggles work. Apply the BiS pool "
      .. "(button below) to switch OFF the unlockable echoes that aren't "
      .. "targets. Note the base (pre-unlocked) pool can't be toggled, so this "
      .. "trims dilution -- it doesn't make every draw a target." .. R
  end
  -- Broad sub-Epic count, same as /ep now: counts.FISH only sees the target
  -- echoes and reads 0 while the run still has fishable keepers.
  local qt = PP.EchoAudit and PP.EchoAudit.RunQualityTargets
    and PP.EchoAudit.RunQualityTargets()
  -- max, not fallback: #qt is 0 (truthy in Lua) when the broad list is
  -- empty, which would silently hide target echoes that counts.FISH sees.
  local subEpic = math.max((qt and #qt) or 0, c.FISH or 0)

  local missing = c.ROLL + c.FARM
  if missing > 0 then
    -- An orb reroll consumes an echo YOU pick, so there is always fodder while
    -- you have echoes. The job is choosing the one you can most afford to lose.
    local rank = PP.EchoAudit and PP.EchoAudit.FodderRank and PP.EchoAudit.FodderRank()
    if rank and #rank > 0 then
      local f = rank[1]
      local second = rank[2] and (", then " .. rank[2].name) or ""
      return GOLD .. "ROLL for the " .. missing .. " missing echo(es)." .. R .. DIM
        .. " Feed your weakest: " .. BRIGHT .. f.name .. R .. DIM .. " [" .. f.tier
        .. ", quality " .. tostring(f.q) .. "]" .. second .. ". Crank orbs/reroll "
        .. "up first -- more orbs means a better draw. All " .. st.total
        .. " in the run IS the BiS build." .. R
    end
    return GOLD .. "ROLL for the " .. missing .. " missing echo(es)." .. R .. DIM
      .. " Pick your weakest echo as the fodder and reroll it." .. R
  end
  if subEpic > 0 then
    return GOLD .. "QUALITY-FISH the " .. subEpic .. " sub-Epic keeper(s)." .. R
      .. DIM .. " Epic is ~10x Common on procs, and a Snapshot save keeps the "
      .. "quality forever -- this polish is a one-time cost." .. R
  end
  if c.FARM > 0 then
    return GOLD .. "FARM the " .. c.FARM .. " missing tome(s)." .. R .. DIM
      .. " A reroll can never offer an echo you don't own. Farm queue has "
      .. "locations. Most tomes are tradeable (check the AH) -- but ICC and "
      .. "Ruby Sanctum tomes are SOULBOUND, so those you farm yourself." .. R
  end
  if c.OFF > 0 then
    return GOLD .. c.OFF .. " target tome(s) are switched OFF." .. R .. DIM
      .. " Re-enable them at level 1 next run (they cannot be drawn while off)." .. R
  end
  return VERD .. "TARGET COMPLETE." .. R .. DIM .. " Every target echo is in the "
    .. "run at Epic (or locked). Lock the best "
    .. ((PP.EchoAudit and PP.EchoAudit.LockSlots and PP.EchoAudit.LockSlots()) or 6)
    .. ", then SAVE the loadout at 80 -- the snapshot preserves everything." .. R
end

-- ---------------------------------------------------------------------------
-- /ep now -- ONE answer, two lines: what to do, and what to press.
--
-- This exists because the rest of this addon grew a command per problem
-- (tomes/scan/left/breadth/chase/rolljunk/fish/bis...) and remembering which
-- one applies right now is its own chore. Everything else is optional depth;
-- this is the front door. It must never print more than three lines.
function BP.Now()
  local lvl = UnitLevel("player") or 80
  local function say(what, doThis)
    PP.print(GOLD .. what .. R)
    if doThis then DEFAULT_CHAT_FRAME:AddMessage("   " .. BRIGHT .. doThis .. R) end
  end

  local st, why = BP.Status()
  if not st then
    if why == "closed" then
      say("Open the Echoes window first.", "All Echoes tab, filter = All classes")
    elseif why == "nohub" then
      say("EbonholdHub isn't loaded -- can't read your run.", "Enable it, then /reload")
    else
      say("No build data for this class yet.", nil)
    end
    return
  end

  local c = st.counts
  -- Level 1 is the only moment the pool can be changed, so it outranks
  -- everything else regardless of what else is pending.
  if lvl == 1 then
    say("Curate the pool -- this is the ONLY moment toggles apply.",
      "/ep tomes bis  then right-click every badged tile")
    return
  end
  -- 2-79: EbonholdHub's automation drafts, rerolls and banishes on its own,
  -- scored against the tiers we push it. There is nothing to click, so the
  -- only useful instruction is "make sure it's aiming at the right build".
  if lvl < 80 then
    say("Levelling -- EBH is auto-picking. Nothing to do but stay synced.",
      "/ep bis  ->  Sync auto-pick   (once per run is enough)")
    return
  end
  -- How many sub-Epic keepers can be fished? This is the BROAD set (every
  -- CORE/S/A keeper below Epic), not just the target echoes -- st.counts.FISH
  -- only sees the 13 targets and reads 0 while 23 keepers are fishable.
  local qt = PP.EchoAudit and PP.EchoAudit.RunQualityTargets
    and PP.EchoAudit.RunQualityTargets()
  -- max, not fallback: #qt is 0 (truthy in Lua) when the broad list is
  -- empty, which would silently hide target echoes that counts.FISH sees.
  local subEpic = math.max((qt and #qt) or 0, c.FISH or 0)

  if c.ROLL > 0 or c.FARM > 0 then
    -- You pick the fodder, so "out of fodder" is not a state that exists while
    -- you still have echoes. Name the weakest one and get on with it.
    local rank = PP.EchoAudit and PP.EchoAudit.FodderRank and PP.EchoAudit.FodderRank()
    local missing = c.ROLL + c.FARM
    if rank and #rank > 0 then
      local f = rank[1]
      say(("Roll for the %d missing echo(es). Feed your weakest: %s [%s]."):format(
        missing, f.name, f.tier),
        "/ep chase   -- crank orbs/reroll up first; more orbs = better draw")
    else
      say(("%d echo(es) still missing."):format(missing),
        "/ep chase   -- pick your weakest echo as the fodder")
    end
    return
  end
  if subEpic > 0 then
    say(("Quality-fish %d sub-Epic keeper(s). Epic is ~10x Common."):format(subEpic),
      "/ep fish   (crank orbs/reroll to ~100 first for the quality jump)")
    return
  end
  if c.FARM > 0 then
    say(("Farm %d missing tome(s)."):format(c.FARM),
      "/ep farm   (ICC and Ruby Sanctum tomes are soulbound -- no AH)")
    return
  end
  if c.OFF > 0 then
    say(("%d target tome(s) are switched off."):format(c.OFF),
      "Can only be fixed at level 1 -- note it for your next reset.")
    return
  end
  say("Build complete. Lock and save it.",
    ("Lock your best %d, then SAVE the loadout -- the snapshot keeps quality."):format(
      (PP.EchoAudit and PP.EchoAudit.LockSlots and PP.EchoAudit.LockSlots()) or 6))
end

-- ---------------------------------------------------------------------------
-- Panel.
local frame, content, rows = nil, nil, {}
local WHITE = "Interface\\Buttons\\WHITE8X8"
local STATE_TXT = {
  LOCKED = VERD .. "[LOCKED]" .. R,   EPIC = VERD .. "[EPIC]" .. R,
  FISH = "|cff9db3bd[FISH]" .. R,     INRUN = "|cff9db3bd[IN RUN]" .. R,
  ROLL = EMBER .. "[ROLL]" .. R,      OFF = EMBER .. "[OFF]" .. R,
  FARM = EMBER .. "[FARM]" .. R,
}

local function GetRow(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Frame", nil, content)
  r:SetWidth(430); r:SetHeight(18)
  r.state = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.state:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -2)
  r.state:SetWidth(64); r.state:SetJustifyH("LEFT")
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 66, -2)
  r.name:SetWidth(250); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
  r.btn = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
  r.btn:SetWidth(70); r.btn:SetHeight(18)
  r.btn:SetPoint("TOPRIGHT", r, "TOPRIGHT", -4, 0)
  rows[i] = r
  return r
end

function BP.Refresh()
  if not (frame and content) then return end
  local st, why = BP.Status()
  if not st then
    local msg
    if why == "closed" then
      msg = EMBER .. "Can't read your tome collection." .. R .. DIM
        .. " Open the Echoes window once -- All Echoes tab, filter set to All "
        .. "classes (a filtered view reads as missing tomes) -- then come back." .. R
    elseif why == "nohub" then
      msg = EMBER .. "Can't read your run from EbonholdHub." .. R .. DIM
        .. " Without it, what's already in your build is unknown -- refusing to "
        .. "guess. Is EbonholdHub loaded?" .. R
    else
      msg = DIM .. "No guide data for this class yet." .. R
    end
    frame.head:SetText(msg)
    frame.next:SetText("")
    for _, r in ipairs(rows) do r:Hide() end
    content:SetHeight(10)
    return
  end

  frame.head:SetText(GOLD .. st.done .. "/" .. st.total .. R .. DIM
    .. " target echoes done (locked or Epic in run)" .. R .. "\n" .. DIM
    .. "locked " .. st.counts.LOCKED .. " · epic " .. st.counts.EPIC
    .. " · fish " .. st.counts.FISH .. " · in-run " .. st.counts.INRUN
    .. " · roll " .. st.counts.ROLL .. " · off " .. st.counts.OFF
    .. " · farm " .. st.counts.FARM .. R
    .. (st.qualUnknown and ("\n" .. DIM .. "(quality unreadable -- no run loaded; "
        .. "in-run echoes shown without Epic/fish split)" .. R) or "")
    -- Say when the numbers rest on a partial read, rather than letting a slice
    -- masquerade as the whole collection.
    .. ((st.tileSource == "live-partial") and ("\n" .. EMBER
        .. "PARTIAL READ: no full catalog scan yet, so [FARM] may be wrong. "
        .. "Run /ep tomes scan." .. R) or "")
    .. (st.runEmpty and ("\n" .. EMBER .. "RUN IS EMPTY: EbonholdHub reports no "
        .. "echoes in this run, so nothing can show as in-run. If you do have "
        .. "echoes, that read is broken." .. R) or ""))
  frame.next:SetText(BP.NextAction(st))

  -- Stack everything below the variable-height header (the recurring lesson:
  -- never a fixed offset under wrapping text).
  local top = 16 + (frame.head:GetStringHeight() or 26) + 8
             + (frame.next:GetStringHeight() or 26) + 30
  frame.scroll:ClearAllPoints()
  frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -top)
  -- Bottom offset 40, NOT 14: the three pipeline buttons occupy y 14..34, and
  -- the review caught this re-anchor overwriting Init's correct 40 on first
  -- show, sliding the list under the buttons.
  frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 40)

  for _, r in ipairs(rows) do r:Hide() end
  -- Actionable first: ROLL, FISH, OFF, FARM, then INRUN, then done states.
  local ORDER = { ROLL = 1, FISH = 2, OFF = 3, FARM = 4, INRUN = 5, EPIC = 6, LOCKED = 7 }
  local list = {}
  for _, e in ipairs(st.list) do list[#list + 1] = e end
  table.sort(list, function(a, b)
    if ORDER[a.state] ~= ORDER[b.state] then return ORDER[a.state] < ORDER[b.state] end
    return a.name < b.name
  end)
  local y = 0
  for i, e in ipairs(list) do
    local r = GetRow(i)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    r.state:SetText(STATE_TXT[e.state] or e.state)
    r.name:SetText((e.role == "CORE" and (BRIGHT .. e.name .. R .. DIM .. "  (core)" .. R))
      or e.name)
    if e.state == "ROLL" then
      r.btn:Show(); r.btn:SetText("Chase")
      local nm = e.name
      r.btn:SetScript("OnClick", function()
        if PP.RerollTarget and PP.RerollTarget.Set then
          PP.safeCall(PP.RerollTarget.Set, nm)
          if PP.Dashboard and PP.Dashboard.ShowView then PP.Dashboard.ShowView("chase") end
        end
      end)
    elseif e.state == "FARM" then
      r.btn:Show(); r.btn:SetText("Farm")
      r.btn:SetScript("OnClick", function()
        if PP.Dashboard and PP.Dashboard.ShowView then PP.Dashboard.ShowView("farm") end
      end)
    else
      r.btn:Hide()
    end
    r:Show()
    y = y + 19
  end
  content:SetHeight(math.max(10, y + 4))
end

function BP.Init()
  if frame then return end
  frame = CreateFrame("Frame", "EbonPilotBisFrame", UIParent)
  frame:SetWidth(480); frame:SetHeight(560)
  frame:SetPoint("CENTER", UIParent, "CENTER", -30, 0)
  frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  frame:SetBackdropColor(0.086, 0.078, 0.067, 0.96)
  frame:SetBackdropBorderColor(1, 1, 1, 0.12)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
  frame.ppClose = close

  frame.head = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.head:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -16)
  frame.head:SetWidth(400); frame.head:SetJustifyH("LEFT"); frame.head:SetSpacing(2)

  frame.next = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.next:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -58)
  frame.next:SetWidth(430); frame.next:SetJustifyH("LEFT"); frame.next:SetSpacing(2)

  -- The three pipeline tools, one click each.
  local function btn(x, w, label, fn)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetWidth(w); b:SetHeight(20)
    b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, 14)
    b:SetText(label)
    b:SetScript("OnClick", fn)
    return b
  end
  btn(18, 130, "Pool plan (L1)", function()
    -- Scan, not Preview: the journal scroll is virtualized, so a plan built
    -- from the rendered tiles covers only what is on screen.
    if PP.TomeManager and PP.TomeManager.Scan then
      PP.safeCall(PP.TomeManager.Scan, "bis")
    end
  end)
  btn(152, 130, "Quality fish", function()
    if PP.EchoFlow and PP.EchoFlow.StartQualityFish then
      PP.safeCall(PP.EchoFlow.StartQualityFish)
    end
  end)
  btn(286, 130, "Sync auto-pick", function()
    if PP.HubSync and PP.HubSync.Push then PP.safeCall(PP.HubSync.Push) end
  end)

  frame.scroll = CreateFrame("ScrollFrame", "EbonPilotBisScroll", frame,
    "UIPanelScrollFrameTemplate")
  frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -120)
  frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 40)
  content = CreateFrame("Frame", nil, frame.scroll)
  content:SetWidth(430); content:SetHeight(10)
  frame.scroll:SetScrollChild(content)

  frame:SetScript("OnShow", function() PP.safeCall(BP.Refresh) end)
  frame:Hide()
end

function BP.GetFrame()
  if not frame then BP.Init() end
  return frame
end

function BP.OnShow() BP.Refresh() end

function BP.Command()
  if PP.Dashboard and PP.Dashboard.Open then PP.Dashboard.Open("bis") end
end
