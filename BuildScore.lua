-- PallyPilot BuildScore: "how optimized is my build, and how much better can
-- it get?" A composite 0-100 across the levers you actually control, plus a
-- ranked list of the improvement headroom. Colorblind-safe (numbers + letter
-- markers, no color-only signal).
--
-- Reads the catalog tiles (via TomeManager.AllTiles) for the keeper universe +
-- ownership, grantedPerks for run-echo quality, and the tome plan for pool
-- hygiene. Needs the Echoes window open (that's where the tiles live).
local PP = PallyPilot
local BS = PP.BuildScore

local GOLD = "|cffe0b352"
local BRIGHT = "|cfff6d888"
local DIM = "|cffb4a586"
local R = "|r"

local KEEP = { CORE = true, S = true, A = true }
local MARK = { CORE = "S+", S = "S", A = "A" }
local RANK = { CORE = 1, S = 2, A = 3 }

-- Weights sum to 1. Keeper pool is the biggest solo lever; Epic quality is ~10x
-- a Common proc so quality is weighted heavily too.
local W = { locks = 0.30, keeper = 0.40, quality = 0.20, hygiene = 0.10 }

local function Grade(n)
  if n >= 95 then return "A+" elseif n >= 90 then return "A"
  elseif n >= 85 then return "A-" elseif n >= 80 then return "B+"
  elseif n >= 75 then return "B" elseif n >= 70 then return "B-"
  elseif n >= 60 then return "C" else return "D" end
end

local function round(x) return math.floor(x + 0.5) end

-- Run-echo quality from grantedPerks: how many keepers are still sub-Epic.
-- Returns total, subEpic — or nil if no run data (e.g. fresh level 1 with only
-- locks loaded, which is fine — quality just drops out of the composite).
local function QualityStats()
  local gp = ProjectEbonhold and ProjectEbonhold.Perks
    and ProjectEbonhold.Perks.grantedPerks
  if not gp then return nil end
  local total, sub = 0, 0
  for key, val in pairs(gp) do
    if type(key) == "string" then
      local tier = PP.EchoAudit and PP.EchoAudit.ClassifyName
        and PP.EchoAudit.ClassifyName(key)
      if KEEP[tier] then
        total = total + 1
        local stacks = (type(val) == "table" and val[1] ~= nil) and val or { val }
        local minq
        for _, e in ipairs(stacks) do
          if type(e) == "table" and e.quality then
            if not minq or e.quality < minq then minq = e.quality end
          end
        end
        if minq and minq < 3 then sub = sub + 1 end
      end
    end
  end
  if total == 0 then return nil end
  return total, sub
end

function BS.Compute()
  local tiles, why = PP.TomeManager and PP.TomeManager.AllTiles
    and PP.TomeManager.AllTiles()
  if not tiles then return nil, why end

  -- Keeper pool: of every keeper-rated tome in this filter, how many owned.
  local universe, owned, missing = 0, 0, {}
  local filled = 0
  for _, t in ipairs(tiles) do
    if t.locked then filled = filled + 1 end
    if KEEP[t.tier] then
      universe = universe + 1
      if t.known then owned = owned + 1 else missing[#missing + 1] = t end
    end
  end
  local keeperScore = universe > 0 and (owned / universe) or 1
  table.sort(missing, function(a, b)
    if RANK[a.tier] ~= RANK[b.tier] then return RANK[a.tier] < RANK[b.tier] end
    return a.name < b.name
  end)

  -- Locks: filled permanent slots / unlocked slot count.
  local slots = (PP.EchoAudit and PP.EchoAudit.LockSlots
    and PP.EchoAudit.LockSlots()) or 6
  local locksScore = slots > 0 and (math.min(filled, slots) / slots) or 1

  -- Quality: keepers at Epic vs sub-Epic (run data).
  local qTotal, qSub = QualityStats()
  local qualityScore = qTotal and ((qTotal - qSub) / qTotal) or nil

  -- Hygiene: junk enabled + keepers wrongly disabled (from the tome plan).
  local junkOn, keepersOff = 0, 0
  local plan = PP.TomeManager and PP.TomeManager.Plan
    and PP.TomeManager.Plan("clean")
  if plan then junkOn = #plan.disable; keepersOff = #plan.reenable end
  local hygieneScore = math.max(0, 1 - (junkOn + keepersOff) / 20)

  -- Composite, renormalized if quality has no data.
  local dims = {
    { key = "locks", w = W.locks, s = locksScore },
    { key = "keeper", w = W.keeper, s = keeperScore },
    { key = "hygiene", w = W.hygiene, s = hygieneScore },
  }
  if qualityScore then
    dims[#dims + 1] = { key = "quality", w = W.quality, s = qualityScore }
  end
  local wsum, ssum = 0, 0
  for _, d in ipairs(dims) do wsum = wsum + d.w; ssum = ssum + d.w * d.s end
  local score = round(ssum / wsum * 100)

  return {
    score = score, grade = Grade(score),
    locksScore = locksScore, filled = filled, slots = slots,
    keeperScore = keeperScore, owned = owned, universe = universe,
    missing = missing,
    qualityScore = qualityScore, qTotal = qTotal, qSub = qSub,
    hygieneScore = hygieneScore, junkOn = junkOn, keepersOff = keepersOff,
    total = #tiles,
  }
end

local function pct(x) return round((x or 0) * 100) end

function BS.Report()
  local r, why = BS.Compute()
  if not r then
    if why == "closed" or why == "empty" then
      PP.print("Open the Echoes window first (All Echoes tab; filter = All "
        .. "classes for the full picture), then /pp score.")
    else
      PP.print("Couldn't read the catalog to score the build.")
    end
    return
  end
  PP.print(GOLD .. "BUILD SCORE  " .. r.score .. "/100  [" .. r.grade .. "]" .. R)
  DEFAULT_CHAT_FRAME:AddMessage(DIM .. "  (100 = you own & run every keeper "
    .. "available in this view; farming new tomes raises the ceiling)" .. R)
  DEFAULT_CHAT_FRAME:AddMessage("  Locks ...... " .. pct(r.locksScore)
    .. "/100   " .. r.filled .. "/" .. r.slots .. " slots filled")
  DEFAULT_CHAT_FRAME:AddMessage("  Keeper pool  " .. pct(r.keeperScore)
    .. "/100   " .. r.owned .. " of " .. r.universe .. " keeper tomes owned")
  if r.qualityScore then
    DEFAULT_CHAT_FRAME:AddMessage("  Quality .... " .. pct(r.qualityScore)
      .. "/100   " .. (r.qTotal - r.qSub) .. " of " .. r.qTotal
      .. " run keepers at Epic")
  else
    DEFAULT_CHAT_FRAME:AddMessage("  Quality .... " .. DIM
      .. "n/a (no run loaded — check at 80)" .. R)
  end
  DEFAULT_CHAT_FRAME:AddMessage("  Hygiene .... " .. pct(r.hygieneScore)
    .. "/100   " .. r.junkOn .. " junk on, " .. r.keepersOff .. " keepers off")

  -- Improvement headroom, ranked by point impact.
  local items = {}
  local farmPts = round(W.keeper * (1 - r.keeperScore) * 100)
  if #r.missing > 0 and farmPts > 0 then
    items[#items + 1] = { p = farmPts, kind = "farm" }
  end
  if r.qualityScore and r.qSub > 0 then
    items[#items + 1] = { p = round(W.quality * (r.qSub / r.qTotal) * 100),
      kind = "quality" }
  end
  if r.locksScore < 1 then
    items[#items + 1] = { p = round(W.locks * (1 - r.locksScore) * 100),
      kind = "locks" }
  end
  if (r.junkOn + r.keepersOff) > 0 then
    items[#items + 1] = { p = round(W.hygiene * (1 - r.hygieneScore) * 100),
      kind = "hygiene" }
  end
  table.sort(items, function(a, b) return a.p > b.p end)

  if #items == 0 then
    PP.print(BRIGHT .. "Maxed for what you own — the way up now is farming new "
      .. "keeper tomes and pushing the ash tree." .. R)
    return
  end
  local gap = 100 - r.score
  PP.print(GOLD .. "IMPROVEMENT POSSIBLE: about +" .. gap .. " pts" .. R)
  for _, it in ipairs(items) do
    if it.kind == "farm" then
      DEFAULT_CHAT_FRAME:AddMessage("  * Farm " .. #r.missing .. " keeper tome(s) "
        .. "(+" .. it.p .. " pts) — top targets:")
      local shown = 0
      for _, m in ipairs(r.missing) do
        shown = shown + 1
        if shown > 8 then break end
        DEFAULT_CHAT_FRAME:AddMessage("      [" .. (MARK[m.tier] or "?") .. "] "
          .. m.name)
      end
      DEFAULT_CHAT_FRAME:AddMessage(DIM .. "      -> /pp farm to queue them." .. R)
    elseif it.kind == "quality" then
      DEFAULT_CHAT_FRAME:AddMessage("  * Orb-fish " .. r.qSub .. " sub-Epic keeper(s) "
        .. "to Epic (+" .. it.p .. " pts) — /pp fish at 80.")
    elseif it.kind == "locks" then
      DEFAULT_CHAT_FRAME:AddMessage("  * Fill " .. (r.slots - r.filled)
        .. " lock slot(s) (+" .. it.p .. " pts) — /pp audit for the best owned.")
    elseif it.kind == "hygiene" then
      DEFAULT_CHAT_FRAME:AddMessage("  * Fix the pool (+" .. it.p .. " pts): "
        .. r.junkOn .. " junk to disable, " .. r.keepersOff
        .. " keepers to re-enable — /pp tomes.")
    end
  end
end
