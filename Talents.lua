-- PallyPilot Talents: snapshot your talent build once, then one-click (or auto)
-- re-apply it every run. Because Ebonhold re-levels you from 1 each run, this
-- removes the biggest per-run chore. Matches by tab+index on your own trees.
local PP = PallyPilot
local T = {}
PP.Talents = T

local GOLD = "|cffe0b352"
local R = "|r"

-- Available talent points (3.3.5 API; fall back gracefully).
local function UnspentPoints()
  if GetUnspentTalentPoints then
    local ok, n = pcall(GetUnspentTalentPoints)
    if ok and n then return n end
  end
  local ok, n = pcall(UnitCharacterPoints, "player")
  if ok and n then return n end
  return 0
end

-- Build a live index of the current trees: normalized talent name ->
-- { tab, index, maxRank }. Names are unique across paladin trees.
local function LiveIndex()
  local idx = {}
  if not (GetNumTalentTabs and GetTalentInfo) then return idx end
  for tab = 1, GetNumTalentTabs() do
    for i = 1, GetNumTalents(tab) do
      local name, _, _, _, _, maxRank = GetTalentInfo(tab, i)
      if name then idx[string.lower(name)] = { tab = tab, index = i, maxRank = maxRank or 0 } end
    end
  end
  return idx
end

local function PointsInTab(tab)
  local n = 0
  for i = 1, GetNumTalents(tab) do
    local _, _, _, _, rank = GetTalentInfo(tab, i)
    n = n + (rank or 0)
  end
  return n
end

-- Priority when points are scarce: Retribution first (fastest solo clears),
-- then Protection survival, then Holy.
local function TreeRank(tab)
  if tab == 3 then return 1 elseif tab == 2 then return 2 else return 3 end
end

-- All template talents still under target, with live tree info. Sorted by the
-- template's IMPORTANCE priority when present (so scarce points buy the best
-- talents first), else by tree/tier/column. Tier-legality is enforced later in
-- NextLearnable, so a pure importance sort is safe.
local function PlannedSteps()
  local build = PP.db and PP.db.talentBuild
  local wants = build and build.talents
  if not wants then return {} end
  local wl = {}
  for name, rank in pairs(wants) do wl[string.lower(name)] = rank end
  -- Importance index from the priority list (lower = do first).
  local prio = {}
  if build.priority then
    for idx, name in ipairs(build.priority) do prio[string.lower(name)] = idx end
  end
  local steps = {}
  for tab = 1, GetNumTalentTabs() do
    for i = 1, GetNumTalents(tab) do
      local name, _, tier, column, rank, maxRank = GetTalentInfo(tab, i)
      local want = name and wl[string.lower(name)]
      if want then
        local target = math.min(want, maxRank or 0)
        if (rank or 0) < target then
          steps[#steps + 1] = { tab = tab, index = i, name = name,
            tier = tier or 1, column = column or 1, rank = rank or 0, target = target,
            prio = prio[string.lower(name)] or 9999 }
        end
      end
    end
  end
  table.sort(steps, function(a, b)
    if a.prio ~= b.prio then return a.prio < b.prio end
    local ra, rb = TreeRank(a.tab), TreeRank(b.tab)
    if ra ~= rb then return ra < rb end
    if a.tier ~= b.tier then return a.tier < b.tier end
    return a.column < b.column
  end)
  return steps
end

local function TalentAt(tab, tier, column)
  for i = 1, GetNumTalents(tab) do
    local _, _, t, c = GetTalentInfo(tab, i)
    if t == tier and c == column then return i end
  end
end

-- Resolve the actual talent to click to progress toward (tab,index): if an
-- arrow prerequisite isn't fully ranked, walk to that prerequisite (recursively).
-- Decision is by the prereq's actual rank vs max — NOT GetTalentPrereqs's
-- isLearnable flag, whose meaning is unreliable and left the guide pointing at
-- a locked talent (e.g. Fanaticism, which needs a point in Repentance).
local function ResolveClickable(tab, index, depth)
  depth = depth or 0
  if depth > 8 or not GetTalentPrereqs then return tab, index end
  local reqTier, reqColumn = GetTalentPrereqs(tab, index)
  if reqTier and reqColumn then
    local pi = TalentAt(tab, reqTier, reqColumn)
    if pi then
      local _, _, _, _, prank, pmax = GetTalentInfo(tab, pi)
      if (prank or 0) < (pmax or 1) then
        return ResolveClickable(tab, pi, depth + 1)
      end
    end
  end
  return tab, index
end

-- The next talent to actually CLICK: highest-priority template step whose tier
-- is unlocked, resolved down its prerequisite arrows to a takeable talent.
local function NextLearnable()
  local steps = PlannedSteps()
  local pts = {}
  for _, s in ipairs(steps) do
    if not pts[s.tab] then pts[s.tab] = PointsInTab(s.tab) end
    if pts[s.tab] >= 5 * (s.tier - 1) then
      local ctab, cindex = ResolveClickable(s.tab, s.index)
      local name, _, _, _, rank, maxRank = GetTalentInfo(ctab, cindex)
      -- If we detoured to a prereq, target is its max (arrows need full rank);
      -- otherwise the template's target.
      local isPrereq = (ctab ~= s.tab or cindex ~= s.index)
      local target = isPrereq and (maxRank or 1) or s.target
      if (rank or 0) < target then
        return { tab = ctab, index = cindex, name = name, rank = rank or 0,
          target = target, prereq = isPrereq and s.name or nil }, steps
      end
    end
  end
  return steps[1], steps
end

-- A saved build is a name -> desired-rank map (order/index proof).
-- Snapshot current talents into that shape.
function T.Save()
  if not PP.db then return end
  local talents, total = {}, 0
  for tab = 1, GetNumTalentTabs() do
    for i = 1, GetNumTalents(tab) do
      local name, _, _, _, rank = GetTalentInfo(tab, i)
      if name and (rank or 0) > 0 then talents[name] = rank; total = total + rank end
    end
  end
  PP.db.talentBuild = { talents = talents, total = total, source = "Your saved build" }
  PP.print("Talent build saved (" .. total .. " points). " .. GOLD .. "/pp talents apply" ..
    R .. " to re-apply, or " .. GOLD .. "/pp talents auto" .. R .. " to auto-apply as you level.")
end

-- Spend available points toward the saved build. Multi-pass so tier
-- prerequisites resolve themselves (LearnTalent no-ops when a tier isn't met).
function T.Apply(silent)
  if not (PP.db and PP.db.talentBuild) then
    PP.print("No saved talent build yet — set your talents, then " .. GOLD .. "/pp talents save" .. R .. ".")
    return
  end
  if InCombatLockdown() then
    if not silent then PP.print("Can't change talents in combat.") end
    return
  end
  local spent, blocked = 0, 0
  -- Spend in priority order (Ret-first, tier-legal, prereq-resolved), one point
  -- at a time, until nothing changes (out of points or blocked by protection).
  local guard = 0
  while guard < 400 do
    guard = guard + 1
    local step = NextLearnable()
    if not step then break end
    local before = step.rank
    local ok = pcall(LearnTalent, step.tab, step.index)
    local _, _, _, _, after = GetTalentInfo(step.tab, step.index)
    if (after or 0) > before then
      spent = spent + ((after or 0) - before)
    else
      if not ok then blocked = blocked + 1 end
      break -- no progress: out of points or blocked
    end
  end
  if not silent then
    PP.print("Applied build: spent " .. GOLD .. spent .. R .. " point" .. (spent == 1 and "" or "s")
      .. ". Unspent now: " .. UnspentPoints() .. "."
      .. (spent == 0 and " |cffff5050LearnTalent is blocked on this client — use |r|cffe0b352/pp talents guide|r|cffff5050 to click it in yourself (auto-advances).|r" or ""))
  end
end

-- Load a baked recommended template into the saved slot (then Apply spends it).
function T.Recommend(key)
  key = (key ~= "" and key) or PP.Build.defaultTemplate
  local tpl = PP.Build.talentTemplates and PP.Build.talentTemplates[key]
  if not tpl then
    PP.print("Unknown template '" .. tostring(key) .. "'. Available: prot-ret.")
    return
  end
  local talents, total = {}, 0
  for name, rank in pairs(tpl.talents or {}) do talents[name] = rank; total = total + rank end
  PP.db.talentBuild = { talents = talents, total = total, source = tpl.name,
    priority = tpl.priority }
  PP.print("Loaded " .. GOLD .. tpl.name .. R .. " (" .. total .. " pts of targets). " ..
    GOLD .. "/pp talents preview" .. R .. " to check, then " .. GOLD .. "/pp talents apply" .. R .. ".")
end

-- Print the saved build's non-zero targets with the LIVE in-game talent names,
-- so you can confirm the indices line up before spending points.
function T.Preview()
  local b = PP.db and PP.db.talentBuild
  if not b then PP.print("No build loaded. Try /pp talents recommend.") return end
  PP.print("Build preview" .. (b.source and (" — " .. b.source) or "") .. ":")
  local live = LiveIndex()
  local tabName = { "Holy", "Protection", "Retribution" }
  local byTab, missing = { {}, {}, {} }, {}
  for name, want in pairs(b.talents or {}) do
    local loc = live[string.lower(name)]
    if loc then
      table.insert(byTab[loc.tab], { name = name, want = math.min(want, loc.maxRank),
        rank = select(5, GetTalentInfo(loc.tab, loc.index)) or 0 })
    else
      missing[#missing + 1] = name
    end
  end
  for tab = 1, 3 do
    if #byTab[tab] > 0 then
      table.sort(byTab[tab], function(a, b2) return a.name < b2.name end)
      DEFAULT_CHAT_FRAME:AddMessage(GOLD .. (tabName[tab] or ("Tab " .. tab)) .. R)
      for _, e in ipairs(byTab[tab]) do
        DEFAULT_CHAT_FRAME:AddMessage("   " .. e.name .. "  " .. e.rank .. "/" .. e.want)
      end
    end
  end
  if #missing > 0 then
    PP.print("|cffff5050Not found in your tree (name mismatch):|r " .. table.concat(missing, ", "))
  else
    PP.print("All template talents matched your tree. /pp talents apply to spend.")
  end
end

-- ============ GUIDED CLICK MODE ============
-- LearnTalent is protected on this client (throttled after a few calls), so we
-- guide the player's own clicks instead. Names/indices resolved live; the next
-- talent needing a point (lowest tier first) is highlighted until the build is done.

local guideFrame, guideText, glow

local function Remaining()
  local left = 0
  for _, s in ipairs(PlannedSteps()) do left = left + (s.target - s.rank) end
  return left
end

local TAB_NAME = { "Holy", "Protection", "Retribution" }

local function HideGlow()
  if glow then glow:Hide(); glow:ClearAllPoints() end
end

-- Best-effort: glow the Blizzard talent button for this talent, if that tab is shown.
local function GlowButton(step)
  if not glow then
    glow = CreateFrame("Frame", "PallyPilotTalentGlow", UIParent)
    glow:SetFrameStrata("HIGH")
    local t = glow:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints(glow)
    t:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    t:SetBlendMode("ADD"); t:SetVertexColor(1, 0.85, 0.2)
    glow.tex = t
  end
  HideGlow()
  local btn = _G["PlayerTalentFrameTalent" .. step.index]
  -- Only valid if the talent frame is open AND showing this step's tab.
  local shownTab = PlayerTalentFrame and PlayerTalentFrame.selectedPlayerSpec
  if btn and btn:IsVisible() then
    -- Confirm the button currently maps to our talent (name match via tooltip is
    -- costly; rely on tab check where available, else just glow by index).
    glow:SetPoint("CENTER", btn, "CENTER", 0, 0)
    glow:SetWidth((btn:GetWidth() or 36) + 16)
    glow:SetHeight((btn:GetHeight() or 36) + 16)
    glow:Show()
  end
end

local function GuideUpdate()
  if not (PP.db and PP.db.talentBuild) then return end
  local step = NextLearnable()
  if not step then
    guideText:SetText("|cff8aa96aBuild complete!|r")
    HideGlow()
    PP.print("Guided talents: build complete.")
    if guideFrame then guideFrame:UnregisterEvent("CHARACTER_POINTS_CHANGED") end
    guideFrame.done = true
    return
  end
  local prereqLine = step.prereq
    and ("\n|cffd9694aprereq for " .. step.prereq .. "|r") or ""
  guideText:SetText("Click |cfff6d888" .. tostring(step.name) .. "|r\n" ..
    "|cffb4a586" .. (TAB_NAME[step.tab] or "?") .. " tab · " ..
    step.rank .. "/" .. step.target .. "|r" .. prereqLine ..
    "\n|cffb4a586" .. Remaining() .. " points left in build|r")
  GlowButton(step)
end

function T.Guide()
  if not (PP.db and PP.db.talentBuild) then
    PP.print("Load a build first: /pp talents recommend (or /pp talents save).")
    return
  end
  if not guideFrame then
    guideFrame = CreateFrame("Frame", "PallyPilotTalentGuide", UIParent)
    guideFrame:SetWidth(230); guideFrame:SetHeight(100)
    guideFrame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    guideFrame:SetMovable(true); guideFrame:EnableMouse(true); guideFrame:RegisterForDrag("LeftButton")
    guideFrame:SetScript("OnDragStart", function(s) s:StartMoving() end)
    guideFrame:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    guideFrame:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 14,
      insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    guideFrame:SetBackdropColor(0, 0, 0, 0.85)
    local head = guideFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head:SetPoint("TOP", guideFrame, "TOP", 0, -8)
    head:SetText("|cffe0b352PallyPilot — talent guide|r")
    guideText = guideFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    guideText:SetPoint("TOP", head, "BOTTOM", 0, -6)
    guideText:SetWidth(210); guideText:SetJustifyH("CENTER")
    local close = CreateFrame("Button", nil, guideFrame, "UIPanelCloseButton")
    close:SetScale(0.8); close:SetPoint("TOPRIGHT", guideFrame, "TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() T.GuideStop() end)
    guideFrame:SetScript("OnEvent", function() PP.safeCall(GuideUpdate) end)
  end
  guideFrame.done = nil
  guideFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
  guideFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
  guideFrame:Show()
  GuideUpdate()
  PP.print("Guided talents on — open your talent pane and click the highlighted talent. It advances as you spend.")
end

function T.GuideStop()
  if guideFrame then
    guideFrame:UnregisterEvent("CHARACTER_POINTS_CHANGED")
    guideFrame:UnregisterEvent("PLAYER_TALENT_UPDATE")
    guideFrame:Hide()
  end
  HideGlow()
end

-- Status / next-to-learn readout.
function T.Status()
  if not (PP.db and PP.db.talentBuild) then
    PP.print("No saved talent build. Set talents you like, then " .. GOLD .. "/pp talents save" .. R .. ".")
    return
  end
  local b = PP.db.talentBuild
  PP.print("Saved build: " .. b.total .. " points. Auto-apply: " ..
    ((PP.db.options.autoTalents and "ON") or "OFF") .. ". Unspent now: " .. UnspentPoints() .. ".")
end

-- Auto-apply on level-up (the per-run win). Deferred out of combat.
local pending = false
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
  if not (PP.db and PP.db.options.autoTalents and PP.db.talentBuild) then return end
  if event == "PLAYER_LEVEL_UP" then
    if InCombatLockdown() then pending = true else PP.safeCall(T.Apply, true) end
  elseif event == "PLAYER_REGEN_ENABLED" and pending then
    pending = false
    PP.safeCall(T.Apply, true)
  end
end)

-- Slash sub-command dispatch, called from Core.
function T.Command(arg)
  arg = string.lower(arg or "")
  local sub, rest = string.match(arg, "^(%S*)%s*(.-)$")
  if sub == "save" then T.Save()
  elseif sub == "recommend" or sub == "rec" then T.Recommend(rest)
  elseif sub == "preview" then T.Preview()
  elseif sub == "apply" then T.Apply(false)
  elseif sub == "guide" then T.Guide()
  elseif sub == "stop" then T.GuideStop()
  elseif sub == "auto" then
    PP.db.options.autoTalents = not PP.db.options.autoTalents
    PP.print("Auto-apply talents on level-up: " .. (PP.db.options.autoTalents and "ON" or "OFF")
      .. (PP.db.options.autoTalents and (PP.db.talentBuild and "" or " (save/recommend a build first!)") or ""))
  elseif sub == "clear" then
    PP.db.talentBuild = nil
    PP.print("Saved talent build cleared.")
  else
    T.Status()
    PP.print(GOLD .. "/pp talents recommend|preview|guide|apply|save|auto|clear" .. R)
  end
end
