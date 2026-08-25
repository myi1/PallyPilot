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
    at = GetTime(),
  }
end

local function OnLoadouts(body)
  local parsed = ParseLoadouts(body)
  if not parsed then return end
  state = parsed
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

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------
local function Say(msg) DEFAULT_CHAT_FRAME:AddMessage(msg) end

local function RunAsh()
  local rd = _G.EbonholdPlayerRunData
  return rd and tonumber(rd.soulPoints) or nil
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
  local i = 0
  local lastTier = nil
  for _, entry in ipairs(AD.NODES) do
    local cur, total, cost = NextBuy(entry, ranks)
    local capped = (cur ~= nil and cur >= total)
    if not capped then
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

local function ClearGlows()
  for _, t in ipairs(glowing) do t:Hide() end
  glowing = {}
end

local function GlowNode(id, r, g, b)
  local btn = _G["skillTreeNode" .. id]
  if not btn then return end
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
end

-- Uncapped entries in priority order with cost/affordability/frontier id.
local function BuyQueue(ranks, spendable)
  local out = {}
  for _, entry in ipairs(AD.NODES) do
    entry._bestId = nil
    local cur, total, cost = NextBuy(entry, ranks)
    local capped = (cur ~= nil and cur >= total)
    if not capped then
      out[#out + 1] = {
        name = entry.name, tier = entry.tier, effect = entry.effect,
        cur = cur, total = total, cost = cost, id = entry._bestId,
        infinite = entry.infinite, perm = entry.perm,
        locked = entry._locked or false,
        afford = (cost and spendable and cost <= spendable
          and not entry._locked) or false,
      }
    end
  end
  return out
end

function AA.RefreshRail()
  if not (rail and rail:IsShown()) then return end
  local ranks = state and state.nodeRanks or nil
  local spendable = state and state.spendable or nil
  local committed = state and state.committed or nil

  local queue = BuyQueue(ranks, spendable)

  -- Prestige-loop awareness: once you're at/past the gate you'll reset soon,
  -- so temp (non-perm) nodes are near-worthless — permanent nodes rise to
  -- the top and temp nodes are flagged. This is why callboard deaths after a
  -- prestige mean "buy permanent HP", not "rebuy cheat-deaths".
  local prestigeReady = committed and committed >= AD.PRESTIGE.gate
  if prestigeReady then
    local perm, temp = {}, {}
    for _, q in ipairs(queue) do
      if q.perm then perm[#perm + 1] = q else temp[#temp + 1] = q end
    end
    queue = {}
    for _, q in ipairs(perm) do queue[#queue + 1] = q end
    for _, q in ipairs(temp) do queue[#queue + 1] = q end
  end
  ClearGlows()

  -- Split: what you can buy NOW (priority order) vs what you're saving for.
  local affordable, saving = {}, nil
  local affordTotal = 0
  for _, q in ipairs(queue) do
    if q.afford then
      affordable[#affordable + 1] = q
      affordTotal = affordTotal + (q.cost or 0)
    elseif not saving and q.cost and not q.locked then
      saving = q -- highest-priority AFFORDABLE-someday thing (not path-locked)
    end
  end

  rail.hero:SetText(spendable and (GOLD .. Fmt(spendable) .. R) or (DIM .. "—" .. R))
  rail.heroSub:SetText(spendable
    and (DIM .. "banked · " .. R .. VERD .. #affordable .. R .. DIM
      .. " buys in reach (" .. Fmt(affordTotal) .. ")" .. R)
    or (DIM .. "waiting for server state..." .. R))

  -- Focal: the top thing you can actually buy right now.
  local top = affordable[1]
  if top then
    rail.nextHead:SetText(GOLD .. "BUY NOW"
      .. (prestigeReady and (EMBER .. "  · PRESTIGE READY: permanent only" .. R) or "") .. R)
    rail.nextName:SetText(BRIGHT .. top.name .. R)
    local rankStr = top.infinite and ("r" .. (top.cur or "?"))
      or ((top.cur or "?") .. "/" .. top.total)
    rail.nextCost:SetText(VERD .. Fmt(top.cost) .. R .. DIM .. "  ·  " .. rankStr
      .. (top.perm and ("  ·  " .. VERD .. "prestige-proof" .. R)
          or (EMBER .. "  ·  TEMP (prestige wipes)" .. R)) .. R)
    rail.nextWhy:SetText(DIM .. (top.effect or "") .. R)
    if top.id then GlowNode(top.id, 1, 0.72, 0.20) end
  elseif #queue > 0 then
    rail.nextHead:SetText(GOLD .. "BUY NOW" .. R)
    local anyLocked = false
    for _, q in ipairs(queue) do if q.locked then anyLocked = true break end end
    if anyLocked then
      rail.nextName:SetText(EMBER .. "Paths not connected" .. R)
      rail.nextCost:SetText(DIM .. "fresh tree: buy outward from the START" .. R)
      rail.nextWhy:SetText(DIM .. "Recommendations unlock as your purchases "
        .. "reach each branch. The infinites at the center are start nodes." .. R)
    else
      rail.nextName:SetText(DIM .. "nothing in reach" .. R)
      rail.nextCost:SetText(DIM .. "bank more ash" .. R)
      rail.nextWhy:SetText("")
    end
  else
    rail.nextHead:SetText(GOLD .. "BUY NOW" .. R)
    rail.nextName:SetText(VERD .. "Everything tracked is maxed" .. R)
    rail.nextCost:SetText(DIM .. "feed the infinites" .. R)
    rail.nextWhy:SetText("")
  end

  -- Saving target: top priority buy that's out of reach.
  if saving and spendable then
    rail.saveLine:SetText(GOLD .. "SAVING FOR  " .. R .. BRIGHT .. saving.name
      .. R .. DIM .. " — " .. R .. EMBER .. Fmt(saving.cost) .. R .. DIM
      .. " (" .. Fmt(saving.cost - spendable) .. " short)" .. R)
  else
    rail.saveLine:SetText("")
  end

  -- Rest of the in-reach list + green glows; then the next few dims.
  local t = {}
  for i = 2, math.min(#affordable, 7) do
    local q = affordable[i]
    t[#t+1] = "  " .. BRIGHT .. q.name .. R .. DIM .. " — " .. R
      .. VERD .. Fmt(q.cost) .. R
  end
  for _, q in ipairs(affordable) do
    if q.id and q ~= top then GlowNode(q.id, 0.54, 0.66, 0.42) end
  end
  local dimmed = 0
  for _, q in ipairs(queue) do
    if not q.afford and q ~= saving and q.cost and dimmed < 4 then
      dimmed = dimmed + 1
      if dimmed == 1 then t[#t+1] = DIM .. "later:" .. R end
      t[#t+1] = DIM .. "  " .. q.name .. " — " .. Fmt(q.cost)
        .. (q.locked and "  [path locked]" or "") .. R
    end
  end
  rail.body:SetText(table.concat(t, "\n"))

  -- Footer: only what the native UI doesn't say — prestige math + reserve.
  local bits = {}
  if committed and committed >= AD.PRESTIGE.gate then
    local worths = math.min(committed, AD.PRESTIGE.destroyedCap) / AD.PRESTIGE.gate
    local bonus = AD.PRESTIGE.gainPerGate * (worths ^ AD.PRESTIGE.exponent) * 100
    bits[#bits+1] = DIM .. "prestige now: " .. R .. VERD
      .. string.format("+%.1f%%", bonus) .. R .. DIM .. " ash gain" .. R
  end
  local run = RunAsh()
  if run and run > 0 then
    -- Hardcore runs have NO pay-to-continue: death is final there.
    bits[#bits+1] = DIM .. "continue price (non-HC only): "
      .. Fmt(math.ceil(run * 0.1)) .. R
  end
  rail.footer:SetText(table.concat(bits, "\n"))
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

  local title = rail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", rail, "TOP", 0, -14)
  title:SetText(GOLD .. "PallyPilot" .. R)

  rail.hero = rail:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  rail.hero:SetPoint("TOP", rail, "TOP", 0, -32)
  rail.heroSub = rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rail.heroSub:SetPoint("TOP", rail.hero, "BOTTOM", 0, -2)
  rail.heroSub:SetWidth(180)

  rail.nextHead = rail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  rail.nextHead:SetPoint("TOPLEFT", rail, "TOPLEFT", 18, -78)
  rail.nextHead:SetText(GOLD .. "BUY NOW" .. R)
  rail.nextName = rail:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  rail.nextName:SetPoint("TOPLEFT", rail.nextHead, "BOTTOMLEFT", 0, -4)
  rail.nextName:SetWidth(174); rail.nextName:SetJustifyH("LEFT")
  rail.nextCost = rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rail.nextCost:SetPoint("TOPLEFT", rail.nextName, "BOTTOMLEFT", 0, -2)
  rail.nextWhy = rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rail.nextWhy:SetPoint("TOPLEFT", rail.nextCost, "BOTTOMLEFT", 0, -3)
  rail.nextWhy:SetWidth(174); rail.nextWhy:SetJustifyH("LEFT")

  rail.saveLine = rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rail.saveLine:SetPoint("TOPLEFT", rail, "TOPLEFT", 18, -156)
  rail.saveLine:SetWidth(174); rail.saveLine:SetJustifyH("LEFT")

  rail.body = rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rail.body:SetPoint("TOPLEFT", rail, "TOPLEFT", 18, -186)
  rail.body:SetWidth(174); rail.body:SetJustifyH("LEFT"); rail.body:SetJustifyV("TOP")
  rail.body:SetSpacing(2)

  rail.footer = rail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rail.footer:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 18, 40)

  local refresh = CreateFrame("Button", nil, rail, "UIPanelButtonTemplate")
  refresh:SetWidth(174); refresh:SetHeight(20)
  refresh:SetPoint("BOTTOM", rail, "BOTTOM", 0, 14)
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
