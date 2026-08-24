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
        if c and (bestCost == nil or c < bestCost) then bestCost = c end
      end
    end
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
    Say("  " .. DIM .. "Keep " .. R .. BRIGHT .. Fmt(math.ceil(run * 0.1))
      .. R .. DIM .. " unspent — 10% of this run's ash is the "
      .. "pay-to-continue price." .. R)
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
