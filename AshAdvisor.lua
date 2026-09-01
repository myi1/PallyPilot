-- PallyPilot AshAdvisor v2: a real next-best-buy optimizer for the Soul Ash
-- permanent tree. Data sources, in order of preference:
--   1. _G.TalentDatabase (the server addon's own node DB: exact costs,
--      infinite-node growth, max ranks) — see AshData.lua header.
--   2. Live account state sniffed from the server's SEND_LOADOUTS addon
--      message (prefix AAM0x9, event 3): spendable ash, lifetime committed
--      ash, echo slot count, and PER-NODE PURCHASED RANKS. The stock addon
--      only requests this when the Skill Tree tab opens, so /pp ash triggers
--      its public ProjectEbonhold.RequestLoadoutFromServer() itself and
--      prints when the reply lands (a fraction of a second).
--   3. AshData baked tables when the client DB is unavailable.
-- Run ash comes from EbonholdPlayerRunData.soulPoints. Everything nil-guarded;
-- nothing here writes to or replaces any ProjectEbonhold handler.
local PP = PallyPilot
local AA = PP.AshAdvisor
local AD = PP.AshData

local GOLD = "|cffe0b352"
local BRIGHT = "|cfff6d888"
local DIM = "|cffb4a586"
local EMBER = "|cffd9694a"
local VERD = "|cff8aa96a"
local R = "|r"

local PE_PREFIX = "AAM0x9"
local STALE_AFTER = 60 -- seconds before /pp ash re-requests account state

-- Live account state, filled by the SEND_LOADOUTS listener below.
-- { spendable, committed, maxEchoes, nodeRanks = {[nodeId]=rank}, name, at }
local state = nil
local pendingReport = false

local function Fmt(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  while true do
    local replaced
    s, replaced = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
    if replaced == 0 then break end
  end
  return s
end

-- ---------------------------------------------------------------------------
-- Client node DB access (_G.TalentDatabase, tree 0 = "Default Soul Tree")
-- ---------------------------------------------------------------------------
local byId
local function NodeById(id)
  if byId == nil then
    local db = _G.TalentDatabase
    local tree = db and db[0]
    local nodes = tree and tree.nodes
    if not nodes then return nil end
    byId = {}
    for _, nd in ipairs(nodes) do
      if nd.id then byId[nd.id] = nd end
    end
  end
  return byId[id]
end

local function HaveClientDb()
  local db = _G.TalentDatabase
  return db ~= nil and db[0] ~= nil and db[0].nodes ~= nil
end

-- Reachability (matters post-prestige, when the tree is empty): a node is
-- purchasable only if it's a start node, already ranked, or adjacent to an
-- owned rank. Adjacency comes from the DB's links edge list.
local adj
local function BuildAdj()
  if adj then return adj end
  local db = _G.TalentDatabase
  local tree = db and db[0]
  local links = (tree and tree.links) or (db and db.links)
  adj = {}
  if links then
    for _, e in ipairs(links) do
      local a, b = e[1], e[2]
      if a and b then
        adj[a] = adj[a] or {}
        adj[a][#adj[a] + 1] = b
        adj[b] = adj[b] or {}
        adj[b][#adj[b] + 1] = a
      end
    end
  end
  return adj
end

local function Purchasable(id, ranks)
  local nd = NodeById(id)
  if not nd then return true end             -- unknown node: don't block
  if nd.isStart then return true end
  if not ranks then return true end          -- no server state: can't judge
  if (ranks[id] or 0) > 0 then return true end
  local a = BuildAdj()[id]
  if not a then return true end              -- no edges known: don't block
  for _, nb in ipairs(a) do
    if (ranks[nb] or 0) > 0 then return true end
  end
  return false
end

-- Runtime node name via its spell id (client knows custom spells).
local function NodeName(id)
  local nd = NodeById(id)
  if nd and nd.spells and nd.spells[1] then
    local nm = GetSpellInfo(nd.spells[1])
    if nm then return nm end
  end
  return "node #" .. tostring(id)
end

-- BFS the links graph from owned/start nodes to targetId; return the first
-- UNOWNED node on a shortest path — the concrete next click toward a
-- path-locked target. Turns "path locked" into "buy THIS next".
local function PathNextBuy(targetId, ranks)
  if not targetId then return nil end
  if Purchasable(targetId, ranks) then return targetId end
  local db = _G.TalentDatabase
  local tree = db and db[0]
  local nodes = tree and tree.nodes
  if not nodes then return nil end
  local adjG = BuildAdj()
  local function isOwned(id)
    local n = NodeById(id)
    return (n and n.isStart) or (ranks and (ranks[id] or 0) > 0)
  end
  local seen, queue, head = {}, {}, 1
  for _, n in ipairs(nodes) do
    if n.id and isOwned(n.id) then
      seen[n.id] = true
      for _, nb in ipairs(adjG[n.id] or {}) do
        if not seen[nb] then
          seen[nb] = true
          queue[#queue + 1] = { id = nb, first = nb }
        end
      end
    end
  end
  while head <= #queue do
    local cur = queue[head]; head = head + 1
    if cur.id == targetId then return cur.first end
    for _, nb in ipairs(adjG[cur.id] or {}) do
      if not seen[nb] then
        seen[nb] = true
        queue[#queue + 1] = { id = nb, first = cur.first }
      end
    end
  end
  return nil
end

-- Max purchasable rank of a DB node.
local function NodeMaxRank(nd)
  if not nd then return 0 end
  if nd.infinite then return AD.INFINITE.maxRank end
  if nd.spells then return #nd.spells end
  if nd.soulPointsCosts then return #nd.soulPointsCosts end
  return 0
end

-- Cost of buying rank `rank` (1-based) of a DB node.
local function NodeRankCost(nd, rank)
  if not nd or not nd.soulPointsCosts then return nil end
  if nd.infinite then
    return AD.InfiniteCost(rank, nd.soulPointsCosts[1], nd.infiniteGrowth)
  end
  return nd.soulPointsCosts[rank] or nd.soulPointsCosts[#nd.soulPointsCosts]
end

-- For a curated AshData entry: current total ranks + the cheapest next
-- purchase across its node chain (chains ascend in cost along their links,
-- so cheapest-unbought is the frontier).
local function NextBuy(entry, ranks)
  local cur, total = 0, 0
  local bestCost = nil
  local lockedCost, lockedId = nil, nil
  entry._locked = nil
  for _, id in ipairs(entry.ids) do
    local nd = NodeById(id)
    if nd then
      local maxR = NodeMaxRank(nd)
      total = total + maxR
      local r = (ranks and ranks[id]) or 0
      if r > maxR then r = maxR end
      cur = cur + r
      if r < maxR then
        local c = NodeRankCost(nd, r + 1)
        if c then
          if Purchasable(id, ranks) then
            if bestCost == nil or c < bestCost then
              bestCost = c
              entry._bestId = id
            end
          elseif lockedCost == nil or c < lockedCost then
            lockedCost, lockedId = c, id
          end
        end
      end
    end
  end
  if bestCost == nil and lockedCost then
    -- Frontier exists but nothing is connected yet (fresh post-prestige
    -- tree): report it, flagged locked, so the rail can say so.
    bestCost = lockedCost
    entry._bestId = lockedId
    entry._locked = true
  end
  if total == 0 then
    -- client DB missing: fall back to baked extract, ranks unknowable
    total = entry.infinite and AD.INFINITE.maxRank or #entry.costs
    cur = nil
    bestCost = entry.infinite and AD.InfiniteCost(1) or entry.costs[1]
  elseif ranks == nil then
    -- DB present but no server reply yet: rank-1 costs are right, the
    -- "you own nothing" zeros would not be — show unknown instead.
    cur = nil
  end
  return cur, total, bestCost
end

-- ---------------------------------------------------------------------------
-- SEND_LOADOUTS listener: our own CHAT_MSG_ADDON frame, fully parallel to the
-- server addon's single-handler bus (never touches ProjectEbonhold handlers).
-- Payload: "sel,spendable,committed,maxEchoes_id,name,points,node:rank,...;..."
-- Long replies arrive chunked as "@mmmm\tiii/ttt\tslice" (hex), reassembled
-- exactly like the stock dispatch() does.
-- ---------------------------------------------------------------------------
local function ParseLoadouts(body)
  local globalPart, loadoutsPart = string.match(body or "", "([^_]+)_?(.*)")
  if not globalPart then return nil end
  local sel, spend, committed, maxEchoes =
    string.match(globalPart, "(%d+),(%d+),(%d+),(%d+)")
  spend = tonumber(spend)
  if not spend then return nil end
  sel = tonumber(sel)

  local loadouts = {}
  if loadoutsPart and loadoutsPart ~= "" then
    for loadoutString in string.gmatch(loadoutsPart, "([^;]+)") do
      local parts = {}
      for part in string.gmatch(loadoutString, "([^,]+)") do
        parts[#parts + 1] = part
      end
      if #parts >= 3 then
        local lo = { id = tonumber(parts[1]), name = parts[2], nodeRanks = {} }
        for i = 4, #parts do
          local nodeId, rank = string.match(parts[i], "(%d+):(%d+)")
          if nodeId then lo.nodeRanks[tonumber(nodeId)] = tonumber(rank) end
        end
        loadouts[#loadouts + 1] = lo
      end
    end
  end

  local chosen = nil
  for _, lo in ipairs(loadouts) do
    if lo.id == sel then chosen = lo break end
  end
  if not chosen then
    for _, lo in ipairs(loadouts) do
      if lo.id == 0 then chosen = lo break end
    end
  end
  if not chosen then chosen = loadouts[1] end

  return {
    spendable = spend,
    committed = tonumber(committed) or 0,
    maxEchoes = tonumber(maxEchoes),
    nodeRanks = chosen and chosen.nodeRanks or {},
    name = chosen and chosen.name or "?",
    buildId = chosen and chosen.id or nil, -- stable saved-build identity
    at = GetTime(),
  }
end

-- Last saved-build id we announced, so a switch prints exactly once. Starts
-- false (not nil) so the very first known build after login doesn't spam a
-- "switch" notice for a build you never left.
local lastBuildId = false

local function OnLoadouts(body)
  local parsed = ParseLoadouts(body)
  if not parsed then return end
  state = parsed
  -- Announce a genuine switch between saved builds (not the first read).
  local bId = parsed.buildId
  if bId ~= nil and bId ~= lastBuildId then
    if lastBuildId ~= false then
      PP.print("build -> " .. BRIGHT .. "\"" .. (parsed.name or "?") .. "\"" .. R
        .. DIM .. "  (fights now tag automatically)" .. R)
    end
    lastBuildId = bId
    -- Reflect the new build in the dashboard if it's open.
    if PP.Dashboard and PP.Dashboard.RefreshCurrent then
      PP.safeCall(PP.Dashboard.RefreshCurrent)
    end
  end
  if pendingReport then
    pendingReport = false
    AA.Render()
  end
  if AA.RefreshRail then PP.safeCall(AA.RefreshRail) end
end

local inflight = {}
local listener = CreateFrame("Frame")
listener:RegisterEvent("CHAT_MSG_ADDON")
listener:SetScript("OnEvent", function(_, _, prefix, payload)
  if prefix ~= PE_PREFIX or not payload then return end
  local evtStr, rest = string.match(payload, "^(%d+)\t(.*)$")
  if not evtStr then return end
  local wantEvt = (ProjectEbonhold and ProjectEbonhold.SS
    and ProjectEbonhold.SS.SEND_LOADOUTS) or 3
  if tonumber(evtStr) ~= wantEvt then return end

  local mid, idx, tot, slice =
    string.match(rest, "^@(%x%x%x%x)\t(%x%x%x)/(%x%x%x)\t(.*)$")
  if mid then
    local rec = inflight[mid]
    if not rec then
      rec = { total = tonumber(tot, 16), got = 0, parts = {}, t0 = GetTime() }
      inflight[mid] = rec
    end
    local i = tonumber(idx, 16)
    if i and i >= 1 and i <= rec.total and not rec.parts[i] then
      rec.parts[i] = slice
      rec.got = rec.got + 1
    end
    if rec.got == rec.total then
      local out = table.concat(rec.parts, "", 1, rec.total)
      inflight[mid] = nil
      PP.safeCall(OnLoadouts, out)
    end
    local t = GetTime()
    for k, v in pairs(inflight) do
      if t - (v.t0 or t) > 20 then inflight[k] = nil end
    end
    return
  end
  PP.safeCall(OnLoadouts, rest)
end)

local function RequestState()
  if ProjectEbonhold and ProjectEbonhold.RequestLoadoutFromServer then
    local ok = pcall(ProjectEbonhold.RequestLoadoutFromServer)
    return ok
  end
  return false
end

function AA.GetState() return state end

-- Active saved-build identity for auto fight-tagging. Returns (id, name) or nil
-- when no loadout reply has landed yet. Read lazily at runtime (CombatMeter
-- loads before this file), never captured at load.
function AA.ActiveBuild()
  if not state then return nil end
  return state.buildId, state.name
end

-- Keep the active build fresh so fights stamp the right one. Echo builds can
-- only be swapped out of combat, so a request on login + on combat-start (with
-- a throttle) is enough; any server push is caught by the listener regardless.
local lastReq = 0
local function RefreshBuild()
  local now = GetTime()
  if now - lastReq < 15 then return end
  lastReq = now
  RequestState()
end

local buildWatch = CreateFrame("Frame")     -- one reused frame (never GC'd)
local settleTimer = CreateFrame("Frame")    -- one reused settle timer
local settleElapsed = 0
settleTimer:Hide()
settleTimer:SetScript("OnUpdate", function(self, dt)
  settleElapsed = settleElapsed + dt
  if settleElapsed >= 4 then self:Hide(); RefreshBuild() end
end)
buildWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
buildWatch:RegisterEvent("PLAYER_REGEN_DISABLED")
buildWatch:SetScript("OnEvent", function(_, evt)
  if evt == "PLAYER_ENTERING_WORLD" then
    settleElapsed = 0; settleTimer:Show() -- let ProjectEbonhold load, then ask once
  else
    RefreshBuild() -- entering combat: the fight ahead tags with the current build
  end
end)

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------
local function Say(msg) DEFAULT_CHAT_FRAME:AddMessage(msg) end

local function RunAsh()
  local rd = _G.EbonholdPlayerRunData
  return rd and tonumber(rd.soulPoints) or nil
end

-- One clear model now: the priority order lives in AD.NODES (Borrowed Power ->
-- echo economy -> permanent stats -> QoL). The only option is whether to also
-- show the optional temp-survival tier (tier 5) -- worth it on a long stay-at-80
-- push or for hardcore DR, wiped on the prestige loop. Hidden by default.
local function ShowSurvival()
  return (PP.db and PP.db.options and PP.db.options.ashShowSurvival) and true or false
end

function AA.Command(arg)
  arg = arg and string.lower(arg) or ""
  local cmd, rest = arg:match("^(%S*)%s*(.-)$")
  if cmd == "import" then
    if rest ~= "" then AA.ImportPlan(rest)
    else AA.ShowBuildBox("Paste your build string from the web builder", "", true) end
    return
  elseif cmd == "export" then AA.ExportPlan(); return
  elseif cmd == "next" or cmd == "guide" then AA.GuideNext(); return
  elseif cmd == "clearbuild" then
    PP.db.ashPlan = nil; PP.print("Build plan cleared.")
    if AA.RefreshRail then PP.safeCall(AA.RefreshRail) end
    return
  end
  if arg == "survival" or arg == "push" or arg == "loop" then
    if not (PP.db.options) then PP.db.options = {} end
    -- "survival" toggles; "push"/"loop" kept as aliases (push showed temp,
    -- loop hid it) so old muscle memory still works.
    if arg == "survival" then
      PP.db.options.ashShowSurvival = not ShowSurvival()
    else
      PP.db.options.ashShowSurvival = (arg == "push")
    end
    PP.print("Ash survival nodes: " .. GOLD
      .. (ShowSurvival() and "SHOWN" or "HIDDEN") .. R .. DIM
      .. " — optional temp survival (long stay-at-80 push / hardcore DR)." .. R)
    if AA.RefreshRail then PP.safeCall(AA.RefreshRail) end
    return
  end
  AA.Report()
end

function AA.Render()
  local ranks = state and state.nodeRanks or nil
  local spendable = state and state.spendable or nil
  local committed = state and state.committed or nil
  local run = RunAsh()

  local head = GOLD .. "Soul Ash advisor" .. R
  if spendable then
    head = head .. DIM .. " — banked " .. R .. BRIGHT .. Fmt(spendable) .. R
      .. DIM .. " | lifetime committed " .. R .. BRIGHT .. Fmt(committed) .. R
  else
    head = head .. DIM .. " — account state not received yet" .. R
  end
  if run then
    head = head .. DIM .. " | this run " .. R .. BRIGHT .. Fmt(run) .. R
  end
  PP.print(head)

  -- Echo slot milestones (each = ONE permanent echo slot, on COMMITTED ash)
  if committed then
    local slots, nextAt = 0, nil
    for _, m in ipairs(AD.MILESTONES) do
      if committed >= m then slots = slots + 1
      elseif not nextAt then nextAt = m end
    end
    local line = "  " .. GOLD .. "Echo slots " .. slots .. "/"
      .. #AD.MILESTONES .. R
    if state and state.maxEchoes then
      line = line .. DIM .. " (server says " .. state.maxEchoes .. ")" .. R
    end
    if nextAt then
      line = line .. DIM .. " — next slot at " .. R .. BRIGHT .. Fmt(nextAt)
        .. R .. DIM .. " committed (" .. R .. EMBER
        .. Fmt(nextAt - committed) .. DIM .. " to go)" .. R
    else
      line = line .. VERD .. " — all milestone slots earned." .. R
    end
    Say(line)
  end

  local haveDb = HaveClientDb()
  if not haveDb then
    Say("  " .. EMBER .. "Client node DB not loaded" .. R .. DIM
      .. " — costs below are from the baked extract; ranks unknown." .. R)
  elseif not ranks then
    Say("  " .. DIM .. "Ranks unknown (no server reply yet) — costs are "
      .. "exact, ownership isn't." .. R)
  end

  Say("  " .. GOLD .. "Next best buys" .. R .. DIM
    .. " (priority order, exact node costs):" .. R)
  local showSurv = ShowSurvival()
  local vet = AA.PrestigeVeteran(ranks)
  local i = 0
  local lastTier = nil
  for _, entry in ipairs(AD.NODES) do
    local cur, total, cost = NextBuy(entry, ranks)
    local capped = (cur ~= nil and cur >= total)
    local hideSurv = entry.survival and not showSurv and not (entry.farm and vet)
    if not capped and not hideSurv then
      i = i + 1
      if entry.tier ~= lastTier then
        lastTier = entry.tier
        Say("   " .. DIM .. "-- " .. (AD.TIER_NAMES[entry.tier] or "")
          .. " --" .. R)
      end
      local rankStr
      if entry.infinite then
        rankStr = cur and ("r" .. cur) or "r?"
      else
        rankStr = (cur and cur or "?") .. "/" .. total
      end
      local costStr
      if cost then
        local afford = spendable and cost <= spendable
        costStr = (afford and VERD or EMBER) .. Fmt(cost) .. R
      else
        costStr = EMBER .. "cost unknown" .. R
      end
      Say("   " .. GOLD .. i .. "." .. R .. " " .. BRIGHT .. entry.name .. R
        .. DIM .. " " .. rankStr .. (entry.perm and " [prestige-proof]" or "")
        .. " — next " .. R .. costStr)
      Say("      " .. DIM .. entry.effect .. R)
    end
  end
  if i == 0 then
    Say("   " .. VERD .. "Every tracked node is maxed. Feed the infinites." .. R)
  end

  if run and run > 0 then
    Say("  " .. DIM .. "Non-hardcore continue price: " .. R .. BRIGHT
      .. Fmt(math.ceil(run * 0.1)) .. R .. DIM
      .. " (10% of run ash). HARDCORE death is final — no continue." .. R)
  end
  if committed then
    local g = AD.PRESTIGE.gate
    if committed >= g then
      local worths = math.min(committed, AD.PRESTIGE.destroyedCap) / g
      local bonus = AD.PRESTIGE.gainPerGate
        * (worths ^ AD.PRESTIGE.exponent) * 100
      Say("  " .. DIM .. "Prestige is OPEN: resetting now burns " .. R
        .. BRIGHT .. Fmt(committed) .. R .. DIM .. " committed for about " .. R
        .. VERD .. string.format("+%.1f%%", bonus) .. R .. DIM
        .. " permanent ash gain. Spending does NOT reduce the payout — "
        .. "only [prestige-proof] nodes survive." .. R)
    else
      Say("  " .. DIM .. "Prestige gate: " .. Fmt(g) .. " committed ("
        .. Fmt(g - committed) .. " away)." .. R)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Ash rail: the advisor docked INSIDE the Skill Tree tab (parent
-- skillTreeFrame, so it shows exactly when the tree does) + glows on the
-- recommended node buttons themselves (they're named skillTreeNode<id>).
-- ---------------------------------------------------------------------------
local rail
local glowing = {}

local claimed = {}

local function ClearGlows()
  for _, t in ipairs(glowing) do t:Hide() end
  glowing = {}
  claimed = {}
end

-- A glow that says WHICH one it is.
--
-- Buy-next versus later-in-the-plan used to be gold-vs-green glow and nothing
-- else, which is invisible to a colourblind reader -- and the two glows share
-- one texture per node, so an imported plan repainted the very node the
-- buy-next glow had just claimed. `mark` fixes both: it is drawn over the node
-- as a number, and the first caller to claim a node keeps it for that frame.
local function GlowNode(id, r, g, b, mark)
  local btn = _G["skillTreeNode" .. id]
  if not btn then return end
  if claimed[id] then return end
  claimed[id] = true
  local t = btn.__ppGlow
  if not t then
    t = btn:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface\\Buttons\\CheckButtonGlow")
    t:SetPoint("CENTER", btn, "CENTER", 0, 0)
    t:SetWidth((btn:GetWidth() or 24) * 1.7)
    t:SetHeight((btn:GetHeight() or 24) * 1.7)
    btn.__ppGlow = t
  end
  t:SetVertexColor(r, g, b, 0.9)
  t:Show()
  glowing[#glowing + 1] = t

  local fs = btn.__ppMark
  if not fs then
    fs = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    fs:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 3, 3)
    btn.__ppMark = fs
  end
  fs:SetText(mark or "")
  if mark then fs:Show() else fs:Hide() end
  glowing[#glowing + 1] = fs
end

-- You've prestiged at least once (Borrowed Power owned) => the enablers are
-- kept, so the useful recommendation is the TEMP rebuild, AoE-farm-survival
-- first. On the very first climb (no Borrowed Power) the enablers lead instead.
function AA.PrestigeVeteran(ranks)
  return ranks and ((ranks[582] or 0) > 0) or false
end

-- Uncapped entries in priority order with cost/affordability/frontier id.
local function BuyQueue(ranks, spendable)
  local out = {}
  local showSurv = ShowSurvival()
  local vet = AA.PrestigeVeteran(ranks)
  for _, entry in ipairs(AD.NODES) do
    entry._bestId = nil
    local cur, total, cost = NextBuy(entry, ranks)
    local capped = (cur ~= nil and cur >= total)
    -- Farm-survival nodes always show for a prestige veteran (that's their
    -- whole reason to open the tree post-reset); other survival stays behind
    -- the toggle.
    local hideSurv = entry.survival and not showSurv and not (entry.farm and vet)
    if not capped and not hideSurv then
      out[#out + 1] = {
        name = entry.name, tier = entry.tier, effect = entry.effect,
        cur = cur, total = total, cost = cost, id = entry._bestId,
        infinite = entry.infinite, perm = entry.perm, farm = entry.farm,
        locked = entry._locked or false,
        afford = (cost and spendable and cost <= spendable
          and not entry._locked) or false,
      }
    end
  end
  -- Reorder for the actual farm-this-cycle goal:
  --  * Endless Might is DROPPED -- it grants attack power, the dead stat for a
  --    paladin (Endless Growth's Strength -> SP is the power pick).
  --  * Infinites go LAST. They are the "feed leftover ash" sink, not the lead
  --    buy: at deep ranks a single rank costs millions for +5 stat, which must
  --    never outrank a 1k Splashguard. Cheap high-impact buys lead.
  --  * For a prestige veteran the AoE-farm-survival rebuild floats to the very
  --    top (enablers already owned); on a first climb the enablers lead instead.
  local lead, mid, inf = {}, {}, {}
  for _, q in ipairs(out) do
    if q.name == "Endless Might" then -- dropped: AP is the dead stat for us
    elseif q.infinite then inf[#inf + 1] = q
    elseif vet and q.farm then lead[#lead + 1] = q
    else mid[#mid + 1] = q end
  end
  out = {}
  for _, q in ipairs(lead) do out[#out + 1] = q end
  for _, q in ipairs(mid) do out[#out + 1] = q end
  for _, q in ipairs(inf) do out[#out + 1] = q end
  return out
end

function AA.RefreshRail()
  if not (rail and rail:IsShown()) then return end
  local ranks = state and state.nodeRanks or nil
  local spendable = state and state.spendable or nil
  local committed = state and state.committed or nil

  -- AD.NODES is already in priority order (Borrowed Power -> echo economy ->
  -- permanent stats -> QoL -> optional survival), so the queue is the plan.
  local queue = BuyQueue(ranks, spendable)
  local prestigeReady = committed and committed >= AD.PRESTIGE.gate
  ClearGlows()

  -- Split: what you can buy NOW (priority order) vs what you're saving for.
  local affordable, saving = {}, nil
  for _, q in ipairs(queue) do
    if q.afford then
      affordable[#affordable + 1] = q
    elseif not saving and q.cost and not q.locked then
      saving = q -- highest-priority buy that's out of reach (not path-locked)
    end
  end

  -- Header: banked ash + how many buys are in reach.
  rail.hero:SetText(spendable and (GOLD .. Fmt(spendable) .. R) or (DIM .. "—" .. R))
  rail.heroSub:SetText(spendable
    and (DIM .. "ash banked · " .. R .. VERD .. #affordable .. R .. DIM
      .. " buys in reach" .. R)
    or (DIM .. "waiting for server state..." .. R))

  -- Echo slots (permanent, unlocked by committed ash) -- more slots = stronger
  -- build, and they persist through a prestige.
  if committed then
    local slots, nextAt = 0, nil
    for _, m in ipairs(AD.MILESTONES) do
      if committed >= m then slots = slots + 1 elseif not nextAt then nextAt = m end
    end
    local s = DIM .. "Echo slots " .. R .. BRIGHT .. slots .. "/" .. #AD.MILESTONES .. R
    if nextAt then
      s = s .. DIM .. " · next at " .. Fmt(nextAt) .. R
    else
      s = s .. VERD .. " · all earned" .. R
    end
    rail.slots:SetText(s)
  else
    rail.slots:SetText("")
  end

  -- Focal: the top thing to buy. If you've imported a build, the PLAN drives the
  -- panel -- AA.NextPlanNode only ever returns a node that's purchasable now (or
  -- the connector toward one), so it never recommends an unreachable node the way
  -- the tier auto-heuristic can on incomplete server state. The auto-heuristic is
  -- the fallback for when no build is loaded.
  local vet = AA.PrestigeVeteran(ranks)
  local planIds = PP.db and PP.db.ashPlan and PP.db.ashPlan.ids
  local top = nil
  if planIds then
    local nId, why, remaining = AA.NextPlanNode(ranks)
    rail.heroSub:SetText(spendable
      and (DIM .. "ash banked · " .. R .. VERD .. (remaining or 0) .. R .. DIM
        .. " nodes left in your build" .. R)
      or (DIM .. "waiting for server state..." .. R))
    if nId then
      local nd = NodeById(nId)
      local curR = (ranks and ranks[nId]) or 0
      local cost = nd and NodeRankCost(nd, curR + 1)
      local afford = cost and spendable and cost <= spendable
      rail.nextHead:SetText(GOLD .. "BUY NEXT" .. R
        .. (why == "connector" and (DIM .. "  · connector" .. R) or (VERD .. "  · your build" .. R)))
      rail.nextName:SetText(BRIGHT .. NodeName(nId) .. R)
      rail.nextCost:SetText((afford and VERD or EMBER) .. (cost and Fmt(cost) or "?") .. R
        .. DIM .. " ash" .. (why == "connector" and " · on the way to your build" or "") .. R)
      rail.nextWhy:SetText(DIM .. (why == "connector"
        and "Buy this to reach the next node in your build."
        or "Next node in your imported build.") .. R)
      GlowNode(nId, 1, 0.72, 0.20, "1")
    else
      rail.nextHead:SetText(GOLD .. "BUY NEXT" .. R)
      rail.nextName:SetText(why == "done" and (VERD .. "Build complete" .. R)
        or (EMBER .. "Blocked — bank ash, or buy a connector node" .. R))
      rail.nextCost:SetText(""); rail.nextWhy:SetText("")
    end
    rail.saveLine:SetText("")
    -- "then:" the next few unbought nodes from your build, in order.
    local t = {}
    for _, id in ipairs(planIds) do
      local nd = NodeById(id); local cr = (ranks and ranks[id]) or 0
      if nd and cr < NodeMaxRank(nd) and id ~= nId then
        local c = NodeRankCost(nd, cr + 1)
        t[#t + 1] = BRIGHT .. NodeName(id) .. R .. DIM .. (c and (" — " .. Fmt(c)) or "") .. R
        GlowNode(id, 0.54, 0.66, 0.42, tostring(#t + 1))
        if #t >= 3 then break end
      end
    end
    rail.body:SetText(#t > 0 and (DIM .. "then:" .. R .. "\n" .. table.concat(t, "\n")) or "")
  else
    top = affordable[1]
    if top then
      rail.nextHead:SetText(GOLD .. "BUY NEXT" .. R
        .. ((vet and top.farm) and (VERD .. "  · farm rebuild" .. R) or ""))
      rail.nextName:SetText(BRIGHT .. top.name .. R)
      local rankStr = top.infinite and ("rank " .. (top.cur or "?"))
        or ((top.cur or "?") .. "/" .. top.total)
      rail.nextCost:SetText(VERD .. Fmt(top.cost) .. R .. DIM .. " ash · " .. rankStr
        .. (top.perm and (" · keeps thru prestige") or (" · temp")) .. R)
      rail.nextWhy:SetText(DIM .. (top.effect or "") .. R)
      if top.id then GlowNode(top.id, 1, 0.72, 0.20) end
    elseif #queue > 0 then
      -- Nothing directly reachable: route toward the top target by finding the
      -- next connector node to buy along the tree's links.
      rail.nextHead:SetText(GOLD .. "WORK TOWARD" .. R)
      local target = queue[1]
      local step = target and target.id and PathNextBuy(target.id, ranks)
      if step and step ~= target.id then
        local nd = NodeById(step)
        local c = nd and NodeRankCost(nd, ((ranks and ranks[step]) or 0) + 1)
        rail.nextName:SetText(BRIGHT .. NodeName(step) .. R)
        rail.nextCost:SetText((c and ((spendable and c <= spendable and VERD or EMBER)
          .. Fmt(c) .. R) or (DIM .. "?" .. R))
          .. DIM .. " · on the way to " .. (target.name or "?") .. R)
        rail.nextWhy:SetText(DIM .. "Buy this to reach "
          .. (target.name or "your next target") .. "." .. R)
        GlowNode(step, 1, 0.72, 0.20)
      else
        rail.nextName:SetText(DIM .. "bank ash, then buy from the center" .. R)
        rail.nextCost:SetText("")
        rail.nextWhy:SetText("")
      end
    else
      rail.nextHead:SetText(GOLD .. "BUY NEXT" .. R)
      rail.nextName:SetText(VERD .. "Everything tracked is maxed" .. R)
      rail.nextCost:SetText(DIM .. "feed the infinite stat nodes" .. R)
      rail.nextWhy:SetText("")
    end

    -- Saving target: top priority buy that's out of reach.
    if saving and spendable then
      rail.saveLine:SetText(GOLD .. "Saving for " .. R .. BRIGHT .. saving.name
        .. R .. DIM .. " — " .. R .. EMBER .. Fmt(saving.cost) .. R .. DIM
        .. " (" .. Fmt(saving.cost - spendable) .. " to go)" .. R)
    else
      rail.saveLine:SetText("")
    end

    -- "Then:" the next few affordable buys, capped short so nothing overflows.
    local t = {}
    for i = 2, math.min(#affordable, 4) do
      local q = affordable[i]
      t[#t+1] = BRIGHT .. q.name .. R .. DIM .. " — " .. Fmt(q.cost) .. R
    end
    for _, q in ipairs(affordable) do
      if q.id and q ~= top then GlowNode(q.id, 0.54, 0.66, 0.42) end
    end
    rail.body:SetText(#t > 0 and (DIM .. "then:" .. R .. "\n" .. table.concat(t, "\n")) or "")
  end

  -- Footer: plain prestige note (the native UI covers the rest).
  if prestigeReady then
    rail.footer:SetText(DIM .. "At the prestige gate. Farming now? Do the survival rebuild above. Prestiging? Feed leftover into the infinites (kept)." .. R)
  else
    rail.footer:SetText("")
  end
  if rail.survivalBtn then
    rail.survivalBtn:SetText(ShowSurvival() and "Survival: ON" or "Survival: OFF")
  end
  if rail.guideBtn then
    local plan = PP.db and PP.db.ashPlan and PP.db.ashPlan.ids
    if plan then
      local left = 0
      for _, id in ipairs(plan) do
        local nd = NodeById(id)
        if nd and ((ranks and ranks[id] or 0) < NodeMaxRank(nd)) then left = left + 1 end
      end
      rail.guideBtn:SetText(left > 0 and ("Next node (" .. left .. " left)") or "Build complete")
      rail.guideBtn:SetScript("OnClick", function() AA.GuideNext() end)
      -- Auto-advance: glow the plan's next node GREEN so it moves along as you
      -- buy (each purchase pushes a loadout update that re-runs this refresh).
      -- Marked "1" too: with a plan imported this IS the buy-next node, and
      -- GlowNode's claim stops it repainting one that is already marked.
      local nid = AA.NextPlanNode(ranks)
      if nid then GlowNode(nid, 0.42, 0.95, 0.45, "1") end
    else
      rail.guideBtn:SetText("Import build")
      rail.guideBtn:SetScript("OnClick", function()
        AA.ShowBuildBox("Paste your build string from the web builder", "", true)
      end)
    end
  end
end

-- ======================= Build import / guided fill =======================
-- A plan is a list of node ids from the web builder (EBASH1:id.id...). We NEVER
-- buy nodes for you (that is bannable input automation) -- we center the tree on
-- the next node and glow it; your click makes the purchase.
local EBASH_PFX = "EBASH1:"
local function PlanIds() return PP.db and PP.db.ashPlan and PP.db.ashPlan.ids or nil end

function AA.ImportPlan(str)
  str = (str or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local body = str:find(":") and str:sub(str:find(":") + 1) or str
  local ids, seen = {}, {}
  for tok in string.gmatch(body, "[^%.,%s]+") do
    local id = tonumber(tok)
    if id and NodeById(id) and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
  end
  if #ids == 0 then
    PP.print(EMBER .. "Couldn't read that build string." .. R .. DIM
      .. " Paste the EBASH1:... string from the web builder." .. R)
    return
  end
  PP.db.ashPlan = PP.db.ashPlan or {}
  PP.db.ashPlan.ids = ids
  PP.print("Build imported: " .. GOLD .. #ids .. " nodes" .. R .. DIM
    .. ". Open the Skill Tree and click " .. R .. BRIGHT .. "Guide" .. R .. DIM
    .. " (or /pp ash next) to fill it node by node." .. R)
  if AA.RefreshRail then PP.safeCall(AA.RefreshRail) end
end

function AA.ExportPlan()
  local ranks = state and state.nodeRanks
  if not ranks then
    PP.print("No tree state yet — open the Skill Tree once, then /pp ash export.")
    return
  end
  local ids = {}
  for id, r in pairs(ranks) do if r and r > 0 then ids[#ids + 1] = id end end
  table.sort(ids)
  AA.ShowBuildBox("Your current tree (copy into the web builder)", EBASH_PFX .. table.concat(ids, "."), false)
end

-- Next planned node to buy: an under-max planned node purchasable now (cheapest),
-- else a connector step toward the first unreachable planned node.
function AA.NextPlanNode(ranks)
  local ids = PlanIds(); if not ids then return nil, "noplan" end
  local best, bestCost, remaining = nil, nil, 0
  for _, id in ipairs(ids) do
    local nd = NodeById(id)
    if nd then
      local cur = (ranks and ranks[id]) or 0
      if cur < NodeMaxRank(nd) then
        remaining = remaining + 1
        if Purchasable(id, ranks) then
          local c = NodeRankCost(nd, cur + 1)
          if not best or (c and bestCost and c < bestCost) or (c and not bestCost) then best, bestCost = id, c end
        end
      end
    end
  end
  if best then return best, "buy", remaining end
  for _, id in ipairs(ids) do
    local nd = NodeById(id); local cur = (ranks and ranks[id]) or 0
    if nd and cur < NodeMaxRank(nd) then
      local step = PathNextBuy(id, ranks)
      if step then return step, "connector", remaining end
    end
  end
  if remaining == 0 then return nil, "done" end
  return nil, "blocked", remaining
end

-- Center the Skill Tree scroll on a node (replicates the server layout math).
function AA.PointAtNode(id)
  local scroll = _G["skillTreeScroll"]; local canvas = _G["skillTreeCanvas"]
  local nd = NodeById(id)
  if not (scroll and canvas and nd and nd.x and nd.y) then return false end
  local db = _G.TalentDatabase; local nodes = db and db[0] and db[0].nodes
  if not nodes then return false end
  local minX, maxY
  for _, n in ipairs(nodes) do
    if n.x and (not minX or n.x < minX) then minX = n.x end
    if n.y and (not maxY or n.y > maxY) then maxY = n.y end
  end
  local SPACING, MARGIN = 0.8, 300
  local ox = MARGIN + (nd.x - minX) * SPACING
  local oy = MARGIN + (maxY - nd.y) * SPACING
  local zoom = (canvas.GetScale and canvas:GetScale()) or 0.6
  local h = math.max(0, math.min(scroll:GetHorizontalScrollRange() or 0, ox * zoom - scroll:GetWidth() / 2))
  local v = math.max(0, math.min(scroll:GetVerticalScrollRange() or 0, oy * zoom - scroll:GetHeight() / 2))
  scroll:SetHorizontalScroll(h); scroll:SetVerticalScroll(v)
  return true
end

-- Guided step: find the next node, bring it into view, glow it. No purchase.
function AA.GuideNext()
  local ranks = state and state.nodeRanks
  local id, why, remaining = AA.NextPlanNode(ranks)
  if why == "noplan" then
    PP.print("No build loaded. Import one first: " .. BRIGHT .. "/pp ash import" .. R
      .. DIM .. " (paste the string from the web builder)." .. R)
    return
  end
  if why == "done" then PP.print(VERD .. "Build complete — every planned node is bought." .. R) return end
  if not id then
    PP.print(EMBER .. "No reachable planned node right now." .. R .. DIM
      .. " Open the Skill Tree so ranks load, or the build may need a connector it doesn't include." .. R)
    return
  end
  ClearGlows()
  local moved = AA.PointAtNode(id)
  GlowNode(id, 1, 0.72, 0.20)
  local tag = (why == "connector") and (DIM .. " (connector toward your build)" .. R) or ""
  PP.print(GOLD .. "Next: " .. R .. BRIGHT .. NodeName(id) .. R .. tag
    .. (remaining and (DIM .. "  — " .. remaining .. " planned left" .. R) or "")
    .. (moved and "" or (EMBER .. "  (open the Skill Tree to jump to it)" .. R)))
end

-- Reusable copy/paste box (export shows text selected; import takes a paste).
function AA.ShowBuildBox(title, text, isImport)
  local f = AA.buildBox
  if not f then
    f = CreateFrame("Frame", "PallyPilotAshBuildBox", UIParent)
    f:SetSize(460, 190); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32,
      edgeSize = 24, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    -- StopMovingOrSizing, not StopMoving: there is no Frame:StopMoving in the
    -- 3.3.5 API, so the handler was nil and the frame stayed glued to the
    -- cursor after the first drag.
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.title:SetPoint("TOP", 0, -14)
    f.title:SetWidth(420)
    local sf = CreateFrame("ScrollFrame", "PallyPilotAshBuildScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 16, -40); sf:SetPoint("BOTTOMRIGHT", -34, 46)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal); eb:SetWidth(400)
    eb:SetAutoFocus(false); eb:EnableMouse(true)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    sf:SetScrollChild(eb); f.eb = eb
    f.ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.ok:SetSize(120, 22); f.ok:SetPoint("BOTTOM", 0, 14)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -4, -4)
    AA.buildBox = f
  end
  f.title:SetText(GOLD .. title .. R)
  f.eb:SetText(text or "")
  f.ok:SetText(isImport and "Import" or "Close")
  f.ok:SetScript("OnClick", function()
    if isImport then AA.ImportPlan(f.eb:GetText()) end
    f:Hide()
  end)
  f:Show()
  f.eb:SetFocus()
  if not isImport then f.eb:HighlightText() end
end

function AA.InitRail()
  local host = _G["skillTreeFrame"]
  if not host or rail then return end
  rail = CreateFrame("Frame", "PallyPilotAshRail", host)
  rail:SetWidth(210)
  rail:SetPoint("TOPLEFT", host, "TOPRIGHT", 10, 0)
  rail:SetPoint("BOTTOMLEFT", host, "BOTTOMRIGHT", 10, 0)
  rail:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 24,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })

  -- Layout is a TOP-DOWN ANCHORED CHAIN: every line anchors below the previous
  -- one, so a long wrapped "why" line pushes the rest down instead of colliding.
  -- Width 186 (rail 210 - 12 each side); word-wrap is on by default once a width
  -- is set. This replaces the old fixed-offset stack that overflowed the panel.
  local W = 186
  local title = rail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", rail, "TOPLEFT", 12, -12)
  title:SetText(GOLD .. "EbonPilot — Ash" .. R)

  rail.hero = rail:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  rail.hero:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  rail.hero:SetWidth(W); rail.hero:SetJustifyH("LEFT")
  rail.heroSub = rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rail.heroSub:SetPoint("TOPLEFT", rail.hero, "BOTTOMLEFT", 0, -2)
  rail.heroSub:SetWidth(W); rail.heroSub:SetJustifyH("LEFT")
  rail.slots = rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rail.slots:SetPoint("TOPLEFT", rail.heroSub, "BOTTOMLEFT", 0, -1)
  rail.slots:SetWidth(W); rail.slots:SetJustifyH("LEFT")

  rail.nextHead = rail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  rail.nextHead:SetPoint("TOPLEFT", rail.slots, "BOTTOMLEFT", 0, -12)
  rail.nextHead:SetText(GOLD .. "BUY NEXT" .. R)
  rail.nextName = rail:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  rail.nextName:SetPoint("TOPLEFT", rail.nextHead, "BOTTOMLEFT", 0, -4)
  rail.nextName:SetWidth(W); rail.nextName:SetJustifyH("LEFT")
  rail.nextCost = rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rail.nextCost:SetPoint("TOPLEFT", rail.nextName, "BOTTOMLEFT", 0, -2)
  rail.nextCost:SetWidth(W); rail.nextCost:SetJustifyH("LEFT")
  rail.nextWhy = rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rail.nextWhy:SetPoint("TOPLEFT", rail.nextCost, "BOTTOMLEFT", 0, -3)
  rail.nextWhy:SetWidth(W); rail.nextWhy:SetJustifyH("LEFT")

  rail.saveLine = rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rail.saveLine:SetPoint("TOPLEFT", rail.nextWhy, "BOTTOMLEFT", 0, -10)
  rail.saveLine:SetWidth(W); rail.saveLine:SetJustifyH("LEFT")

  rail.body = rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rail.body:SetPoint("TOPLEFT", rail.saveLine, "BOTTOMLEFT", 0, -8)
  rail.body:SetWidth(W); rail.body:SetJustifyH("LEFT"); rail.body:SetJustifyV("TOP")
  rail.body:SetSpacing(2)

  rail.footer = rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rail.footer:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 12, 64)
  rail.footer:SetWidth(W); rail.footer:SetJustifyH("LEFT")

  -- Guided fill / import: full-width button just above the bottom row. When a
  -- build is loaded it steps you to the next node; otherwise it opens the paste
  -- box. It never buys a node -- your click on the glowing node does.
  rail.guideBtn = CreateFrame("Button", nil, rail, "UIPanelButtonTemplate")
  rail.guideBtn:SetHeight(20)
  rail.guideBtn:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 12, 38)
  rail.guideBtn:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", -12, 38)
  rail.guideBtn:SetText("Import build")

  -- Toggle the optional temp-survival tier (tier 5) in/out of the list.
  rail.survivalBtn = CreateFrame("Button", nil, rail, "UIPanelButtonTemplate")
  rail.survivalBtn:SetWidth(96); rail.survivalBtn:SetHeight(20)
  rail.survivalBtn:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 12, 14)
  rail.survivalBtn:SetScript("OnClick", function()
    AA.Command("survival")
  end)

  local refresh = CreateFrame("Button", nil, rail, "UIPanelButtonTemplate")
  refresh:SetWidth(84); refresh:SetHeight(20)
  refresh:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", -14, 14)
  refresh:SetText("Refresh")
  refresh:SetScript("OnClick", function()
    RequestState()
    PP.safeCall(AA.RefreshRail)
  end)

  rail:SetScript("OnShow", function()
    local fresh = state and (GetTime() - (state.at or 0)) < STALE_AFTER
    if not fresh then RequestState() end
    PP.safeCall(AA.RefreshRail)
  end)
  rail:SetScript("OnHide", function() ClearGlows() end)
  if rail:IsShown() then PP.safeCall(AA.RefreshRail) end
end

function AA.Report()
  local fresh = state and (GetTime() - (state.at or 0)) < STALE_AFTER
  if fresh then
    AA.Render()
    return
  end
  if RequestState() then
    pendingReport = true
    PP.print(DIM .. "Asking the server for your tree state..." .. R)
    -- If the reply never lands (e.g. loading screen), still show something:
    -- print the DB-only view after a beat. One reused frame — WoW frames
    -- are never garbage-collected.
    AA.waiter = AA.waiter or CreateFrame("Frame")
    local t0 = GetTime()
    AA.waiter:SetScript("OnUpdate", function(self)
      if not pendingReport then self:SetScript("OnUpdate", nil) return end
      if GetTime() - t0 > 2 then
        self:SetScript("OnUpdate", nil)
        pendingReport = false
        AA.Render()
      end
    end)
  else
    AA.Render()
  end
end
