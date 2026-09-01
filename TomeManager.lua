-- PallyPilot TomeManager: level-1 tome enable/disable ADVISOR.
--
-- THE KEY FIX: the real learned-tome collection and each tome's true on/off
-- state live on the Echo Journal CATALOG TILES (each tile carries .spellId /
-- .tomeKnown / .tomeDisabled / .isLocked), NOT in EbonholdHub's run-echo set.
-- At level 1 the run set is just your 6 locks, which is why the old farm plan
-- returned "disable 0". We read the tiles directly. The catalog renders ALL
-- tiles at once (not virtualized), so every owned tome is readable.
--
-- ADVISOR-ONLY, by design. The game's tile handler toggles the tome under the
-- CURSOR (not the frame it's called with — proven when a programmatic call
-- popped "Enable Contagion?", a tome that wasn't in the plan) AND pops a
-- per-toggle Yes/No confirm. So a clicker would hit the wrong tome and still
-- need a manual Yes. Instead we identify precisely what to change; the tile
-- LETTER badges (EchoFlow) make each target easy to spot; you do the few
-- right-clicks. This also stays on the safe side of the automation ban.
local PP = PallyPilot
local TM = PP.TomeManager

-- (The per-tier text markers that used to live here went with the chat lists.
-- Tier letters are shown on the tiles themselves by EchoFlow's badge layer.)
local RANK = { CORE = 1, S = 2, A = 3, B = 4, C = 5, DISABLE = 6, REROLL = 7 }
local KEEP = { CORE = true, S = true, A = true }   -- always want these ON
local JUNK = { REROLL = true, DISABLE = true }      -- always want these OFF

-- ---------------------------------------------------------------------------
-- Reading the catalog tiles.
local function ScrollChild()
  local scroll = _G.ProjectEbonholdEchoJournalScroll
  if not scroll or not scroll.GetScrollChild then return nil end
  return scroll:GetScrollChild()
end

-- Returns a list of the owned-tome tiles, or nil + reason ("closed"/"empty").
local function Tiles()
  local child = ScrollChild()
  if not child or not child.GetChildren then return nil, "closed" end
  local out = {}
  for _, f in ipairs({ child:GetChildren() }) do
    if type(f) == "table" and f.spellId and f.tomeKnown then
      out[#out + 1] = f
    end
  end
  if #out == 0 then return nil, "empty" end
  return out
end

-- MUST match EchoFlow's NormEF byte for byte: the badge layer looks tiles up in
-- the set this file builds, so any difference in normalisation silently marks
-- nothing. Curly apostrophe (U+2019) -> straight, then lowercase.
local function Norm(name)
  name = string.gsub(name or "", "\226\128\153", "'")
  return string.lower(name)
end

-- PerkDatabase comments carry a quality suffix on some entries ("Hardened Skin
-- - Rare"), so counting distinct ECHOES means collapsing those first. Explicit
-- loop: Lua patterns have no alternation.
local QUAL_SUFFIX = { " %- epic", " %- rare", " %- uncommon", " %- common" }
local function StripQ(lowered)
  for _, suf in ipairs(QUAL_SUFFIX) do
    lowered = string.gsub(lowered, suf .. "$", "")
  end
  return lowered
end

local function TomeName(tile)
  local id = tile.spellId
  local pd = _G.PerkDatabase and id and _G.PerkDatabase[id]
  if pd and pd.comment and pd.comment ~= "" then return pd.comment end
  local n = id and GetSpellInfo and GetSpellInfo(id)
  return n or ("Echo " .. tostring(id))
end

-- Public: every catalog tile in the current filter as records (owned AND
-- unowned), for the build scorer. nil + reason ("closed"/"empty") if the
-- Echoes window isn't showing tiles.
function TM.AllTiles()
  local child = ScrollChild()
  if not child or not child.GetChildren then return nil, "closed" end
  local out = {}
  for _, f in ipairs({ child:GetChildren() }) do
    if type(f) == "table" and f.spellId then
      local name = TomeName(f)
      out[#out + 1] = {
        spellId = f.spellId, name = name,
        tier = (PP.EchoAudit and PP.EchoAudit.ClassifyName
          and PP.EchoAudit.ClassifyName(name)) or "REROLL",
        known = (f.tomeKnown == true),
        disabled = (f.tomeDisabled == true),
        locked = (f.isLocked == true),
      }
    end
  end
  if #out == 0 then return nil, "empty" end
  return out
end

-- ---------------------------------------------------------------------------
-- MERGED TILES: the complete catalog, not the rendered slice.
--
-- AllTiles() returns only what the virtualized scroll has drawn, so ANY caller
-- that asks "do I own this tome?" gets a slice-shaped answer. That produced a
-- Target-build panel claiming 10 owned echoes needed farming.
--
-- So: start from the last full-catalog scan (complete, possibly a little
-- stale), then overlay the live tiles on top (fresher, partial). Ownership is
-- permanent so staleness cannot un-own anything; only the on/off and locked
-- flags can drift, and the live overlay corrects those wherever they render.
-- Returns records plus a source word for the caller to report honestly.
function TM.MergedTiles()
  local byKey, order = {}, {}
  local function put(name, known, disabled, locked, fresh)
    if not name then return end
    local k = StripQ(Norm(name))
    if k == "" then return end
    local e = byKey[k]
    if not e then
      e = { name = name, known = false, disabled = false, locked = false }
      byKey[k] = e
      order[#order + 1] = k
    end
    e.known = e.known or known
    if fresh then
      e.disabled = disabled
      e.locked = locked
    else
      e.disabled = e.disabled or disabled
      e.locked = e.locked or locked
    end
  end

  local snap = PP.db and PP.db.scans and PP.db.scans.tomes
  local fromScan = 0
  if snap and snap.tomes then
    for _, t in ipairs(snap.tomes) do
      put(t.name, true, t.off == 1, t.locked == 1, false)
      fromScan = fromScan + 1
    end
  end

  local live, why = TM.AllTiles()
  local fromLive = 0
  if live then
    for _, t in ipairs(live) do
      put(t.name, t.known, t.disabled, t.locked, true)
      fromLive = fromLive + 1
    end
  end

  if #order == 0 then return nil, (why or "closed") end
  local out = {}
  for _, k in ipairs(order) do out[#out + 1] = byKey[k] end
  local source
  if fromScan > 0 and fromLive > 0 then source = "scan+live"
  elseif fromScan > 0 then source = "scan"
  else source = "live-partial" end
  return out, source, { scan = fromScan, live = fromLive, when = snap and snap.when }
end

-- ---------------------------------------------------------------------------
-- Plan: which owned tomes to disable (junk currently ON) and which to
-- re-enable (keepers currently OFF), for the given mode.
--   "clean" (default): keep breadth — disable only rated junk (X); re-enable
--                       any CORE/S/A you turned off by mistake.
--   "tight"          : curate a fishing pool — keep ON only locks + CORE/S/A;
--                       disable B/C/junk; re-enable disabled keepers.
--   "bis"            : THE target-build pool — keep ON only locks + the
--                       explicit BiS target list (BisPlan).
--
-- SCOPE OF TOGGLING, verified in-game 2026-09-01: only UNLOCKABLE (tome) echoes
-- can be enabled/disabled. Echoes that come PRE-UNLOCKED are permanently in the
-- draw pool and have no toggle at all. That is why even "bis" mode returns a
-- modest list (24 on the reference Paladin) and not "disable everything but the
-- target list". Curation trims the tome echoes you unlocked and don't want; it
-- cannot concentrate the base pool onto BiS. The bigger lever is upstream:
-- every tome you unlock permanently ENLARGES your pool, so unlocking a
-- non-target tome dilutes every future draw until you disable it here.
-- Plans from PLAIN RECORDS ({name, known, disabled, locked}) rather than live
-- frames, so the same logic serves both the on-screen read and the full-catalog
-- scan. Records must already be filtered to known tomes.
function TM.PlanRecords(records, mode)
  -- Guard hard: if KEEP can't be built, IsKeep says false for EVERYTHING and
  -- the plan becomes "disable every tome you own". Refuse instead of advising
  -- that. (Checks the KEEP set specifically -- it is what the plan reads.)
  if mode == "bis" then
    local B = PP.Build
    local keep = B and B.KeepSet and B.KeepSet()
    if not keep or not next(keep) then return nil, "notarget" end
  end
  local disable, reenable = {}, {}
  for _, r in ipairs(records) do
    local name = r.name
    local tier = (PP.EchoAudit and PP.EchoAudit.ClassifyName
      and PP.EchoAudit.ClassifyName(name)) or "REROLL"
    local off = (r.disabled == true)
    local locked = (r.locked == true)
    local wantOn
    if mode == "bis" then
      -- KEEP, not CHASE. Curating down to the reroll targets throws away
      -- breadth, and Adaptive Power pays +1% per unique echo -- so the pool
      -- should hold everything worth drafting, while orbs chase the short list.
      wantOn = locked or (PP.BisPlan and PP.BisPlan.IsKeep
        and PP.BisPlan.IsKeep(name)) or false
    elseif mode == "tight" then
      wantOn = locked or KEEP[tier]
    else
      wantOn = locked or (not JUNK[tier])
    end
    if wantOn and off then
      reenable[#reenable + 1] = { tile = r.tile, name = name, tier = tier,
        spellId = r.spellId }
    elseif (not wantOn) and (not off) and (not locked) then
      disable[#disable + 1] = { tile = r.tile, name = name, tier = tier,
        spellId = r.spellId }
    end
  end
  table.sort(reenable, function(a, b)
    if RANK[a.tier] ~= RANK[b.tier] then return RANK[a.tier] < RANK[b.tier] end
    if a.name ~= b.name then return a.name < b.name end
    return (a.spellId or 0) < (b.spellId or 0)
  end)
  table.sort(disable, function(a, b)  -- worst (X) first
    if RANK[a.tier] ~= RANK[b.tier] then return RANK[a.tier] > RANK[b.tier] end
    if a.name ~= b.name then return a.name < b.name end
    return (a.spellId or 0) < (b.spellId or 0)
  end)
  return { disable = disable, reenable = reenable, total = #records, mode = mode }
end

-- WARNING: this reads only the tiles rendered RIGHT NOW. The journal scroll is
-- virtualized (proven 2026-09-01), so this plan is a slice, never the whole
-- collection. TM.Scan() walks the full list; prefer it.
function TM.Plan(mode)
  local tiles, why = Tiles()
  if not tiles then return nil, why end
  local records = {}
  for _, t in ipairs(tiles) do
    records[#records + 1] = {
      tile = t, spellId = t.spellId, name = TomeName(t),
      disabled = (t.tomeDisabled == true), locked = (t.isLocked == true),
    }
  end
  return TM.PlanRecords(records, mode)
end

-- ---------------------------------------------------------------------------
-- The disable list belongs ON THE TILES, not in chat. This feeds EchoFlow's
-- badge layer (red X + the word "OFF") so the instruction is wherever you are
-- looking, and survives scrolling a virtualized catalog for free.
function TM.Mark(plan)
  if not plan then return 0 end
  local set, onSet = {}, {}
  for _, e in ipairs(plan.disable or {}) do set[Norm(e.name)] = true end
  -- Re-enables get badged too. Printing them was the other half of the chat
  -- wall, and "switch this back ON" is just as much a per-tile instruction as
  -- "switch this OFF".
  for _, e in ipairs(plan.reenable or {}) do onSet[Norm(e.name)] = true end
  PP.db = PP.db or _G.PallyPilotDB
  if type(PP.db) == "table" then
    PP.db.poolPlan = { mode = plan.mode or "bis", set = set, onSet = onSet,
      t = time(), source = "tomes",
      n = #(plan.disable or {}), nOn = #(plan.reenable or {}) }
  end
  if PP.EchoFlow and PP.EchoFlow.RefreshBadges then
    PP.safeCall(PP.EchoFlow.RefreshBadges)
  end
  return #(plan.disable or {}) + #(plan.reenable or {})
end

-- "How many left?" without re-printing anything. Counts against the CURRENT
-- catalog read, so it is a lower bound while the scroll is virtualized -- run
-- /ep tomes scan for the true remaining figure.
function TM.Left()
  local marked = PP.db and PP.db.poolPlan
  if not (marked and marked.set) then
    PP.print("No pool plan marked. Run /ep tomes bis first.")
    return
  end
  local tiles = Tiles()
  local seen, still = {}, 0
  if tiles then
    for _, t in ipairs(tiles) do
      local n = Norm(TomeName(t))
      if marked.set[n] and not seen[n] then
        seen[n] = true
        if t.tomeDisabled ~= true then still = still + 1 end
      end
    end
  end
  PP.print("Pool plan: " .. tostring(marked.n or "?") .. " tiles marked; "
    .. still .. " still ON in the part of the catalog on screen now. Scroll to "
    .. "check the rest, or /ep tomes scan for the exact figure.")
end

local function CantRead(why)
  if why == "notarget" then
    PP.print("No target build for this class yet -- the bis pool needs the "
      .. "class's locked/S-tier data. Nothing was planned.")
  elseif why == "closed" or why == "empty" then
    PP.print("Open the Echoes window first (All Echoes tab; set the filter to "
      .. "All classes to cover every tome), then run the command again.")
  else
    PP.print("Couldn't read the echo catalog.")
  end
end

-- ---------------------------------------------------------------------------
function TM.Preview(mode)
  mode = mode or "clean"
  local plan, why = TM.Plan(mode)
  if not plan then CantRead(why); return end
  local lvl = UnitLevel("player") or 1
  PP.print("TOME PLAN (" .. string.upper(mode) .. ") — read " .. plan.total
    .. " known tomes. Toggles apply at LEVEL 1 only"
    .. (lvl == 1 and " (you are level 1 — ready)." or (" — you are level " .. lvl
        .. ", so this is preview-only.")))
  -- NO LISTS IN CHAT. Both halves of the plan are per-tile instructions, so
  -- both get badged and chat gets counts only. A scrollback wall is unusable
  -- while you are clicking through a catalog, and it pushes everything else
  -- out of view. Full lists live in SavedVariables via /ep tomes scan.
  TM.Mark(plan)
  if #plan.disable == 0 and #plan.reenable == 0 then
    PP.print("-> Pool already matches the plan. Nothing to toggle.")
  else
    PP.print(("-> %d to switch OFF (X badge), %d to switch back ON (tick "
      .. "badge). Scroll the catalog and right-click every badged tile."):format(
      #plan.disable, #plan.reenable))
  end
  -- Adaptive Power turns pool size into a damage stat, so a curation plan that
  -- never mentions breadth is only telling half the story.
  local base, on, off, uniq, pool = TM.PoolBreadth()
  if base and mode == "bis" then
    local after = pool - #plan.disable + #plan.reenable
    -- Round explicitly. "%d" with a float truncates on 5.1 and is an outright
    -- error on stricter Lua, which is how the offline suite catches it.
    local uNow = math.floor(uniq + 0.5)
    local uAfter = math.floor(TM.ExpectedUniques(after, 79) + 0.5)
    PP.print(("BREADTH: pool %d -> %d (%d base pool is fixed). Unique echoes "
      .. "over a run ~%d -> ~%d, i.e. Adaptive Power ~+%d%% -> ~+%d%%."):format(
      pool, after, base, uNow, uAfter, uNow, uAfter))
  end
  if #plan.disable > 0 or #plan.reenable > 0 then
    if lvl == 1 then
      PP.print("Tiles also carry their verdict LETTER (top-right). "
        .. "/ep tomes left = progress; /ep tomes scan = full list to disk.")
    else
      PP.print("Start a fresh run (level 1) to apply these toggles.")
    end
  end
end

-- ---------------------------------------------------------------------------
-- Advisor-only, by design. The game's catalog tile handler toggles the tome
-- under the CURSOR (not the tile passed to it) and pops a per-toggle Yes/No
-- confirm, so a programmatic clicker would (a) hit the wrong tome and (b) still
-- need a manual Yes — worse than nothing. Instead we identify exactly what to
-- change and the tile LETTER badges make each target easy to find; you do the
-- handful of right-clicks. This is also the safe side of the automation ban.
function TM.Go(mode)
  mode = mode or "clean"
  PP.print("Toggling is manual (the game confirms each one and targets by "
    .. "cursor, so it can't be safely automated). Here's exactly what to do:")
  TM.Preview(mode)
end

-- ---------------------------------------------------------------------------
-- Diagnostic for "I disabled the list and it found MORE".
--
-- There are only two explanations and they need different fixes, so measure
-- instead of guessing:
--   (a) QUALITY VARIANTS -- one echo has several catalog tiles (separate
--       spellIds) and each carries its own toggle. Then a repeat listing is
--       correct and the fix is to say so in the output.
--   (b) PARTIAL VIEW -- the scroll child only hands us the tiles rendered right
--       now (scroll position or an active filter), so every plan is computed
--       over a subset. Then the module's "renders ALL tiles at once" assumption
--       is wrong and the plan must never be trusted as complete.
-- Duplicate names sharing ONE spellId means (b); duplicates with DIFFERENT
-- spellIds means (a).
function TM.Debug()
  local all, why = TM.AllTiles()
  if not all then CantRead(why); return end

  local known, off, locked = 0, 0, 0
  local byName, order = {}, {}
  for _, t in ipairs(all) do
    if t.known then
      known = known + 1
      if t.disabled then off = off + 1 end
      if t.locked then locked = locked + 1 end
      local k = string.lower(t.name or "?")
      local rec = byName[k]
      if not rec then
        rec = { name = t.name, ids = {}, offs = 0 }
        byName[k] = rec
        order[#order + 1] = k
      end
      rec.ids[#rec.ids + 1] = t.spellId
      if t.disabled then rec.offs = rec.offs + 1 end
    end
  end
  table.sort(order)

  local uniq, sameId, diffId = 0, 0, 0
  local dupes = {}
  for _, k in ipairs(order) do
    local rec = byName[k]
    uniq = uniq + 1
    if #rec.ids > 1 then
      local allSame = true
      for i = 2, #rec.ids do
        if rec.ids[i] ~= rec.ids[1] then allSame = false; break end
      end
      if allSame then sameId = sameId + 1 else diffId = diffId + 1 end
      dupes[#dupes + 1] = { rec = rec, allSame = allSame }
    end
  end

  PP.print("TOME CATALOG DEBUG -- " .. #all .. " tiles rendered, " .. known
    .. " known (" .. off .. " already OFF, " .. locked .. " locked), "
    .. uniq .. " distinct names.")
  if #dupes == 0 then
    PP.print("No duplicate names. A repeat plan therefore means the view is "
      .. "PARTIAL -- scroll the catalog to the very top and re-run.")
  else
    PP.print("Duplicate names: " .. #dupes .. " (" .. diffId
      .. " with DIFFERENT spellIds = real quality variants, each needing its "
      .. "own toggle; " .. sameId .. " with the SAME spellId = the same tile "
      .. "counted twice, which is a read bug).")
    for i = 1, math.min(#dupes, 12) do
      local d = dupes[i]
      DEFAULT_CHAT_FRAME:AddMessage("   " .. i .. ". " .. d.rec.name .. "  x"
        .. #d.rec.ids .. "  ids: " .. table.concat(d.rec.ids, ", ")
        .. "  off: " .. d.rec.offs .. "/" .. #d.rec.ids
        .. (d.allSame and "  [SAME ID -- read bug]" or "  [variants]"))
    end
  end
  PP.print("If 'tiles rendered' changes when you scroll the catalog, the list "
    .. "is virtualized and no single plan is ever complete.")
end

-- ---------------------------------------------------------------------------
-- BREADTH. Adaptive Power pays +1% damage per UNIQUE active echo, so shrinking
-- the pool is not free: fewer distinct echoes get drawn over a 1-80 run. The
-- curation trade is real and it should be visible, not implied.
--
-- The saving grace is that only tome-gated echoes toggle -- the base pool is
-- always in the hat -- so the floor is much higher than it looks. Measure it
-- rather than assume it.
local CLASS_BIT = {
  WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
  DEATHKNIGHT = 32, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}

-- Lua 5.1 in this client has no bitwise operators.
local function MaskHas(mask, bit)
  mask = tonumber(mask)
  if not mask or not bit then return false end
  return (mask % (bit * 2)) >= bit
end

-- Expected distinct results from `draws` uniform draws over `pool` entries.
-- Auto-pick takes the best of three rather than one at random, which biases
-- toward the target list, so treat this as a comparison tool between pool
-- sizes -- not a prediction of your final echo count.
-- On TM, not a file-local: Preview() is defined ABOVE this point, so a local
-- would compile to a global lookup there and blow up at runtime with
-- "attempt to call a nil value". Table fields resolve at call time.
function TM.ExpectedUniques(pool, draws)
  if not pool or pool <= 0 then return 0 end
  return pool * (1 - ((pool - 1) / pool) ^ (draws or 79))
end
local ExpectedUniques = TM.ExpectedUniques

-- Returns basePool, enabledTomes, ownedOff, expectedUniques -- or nil if the
-- client tables needed to separate base from tome-gated aren't available.
function TM.PoolBreadth()
  local PE = _G.ProjectEbonhold
  local db = PE and PE.PerkDatabase
  local byGroup = PE and PE.PerkDropSourceByGroup
  if type(db) ~= "table" or type(byGroup) ~= "table" then return nil end

  local _, classToken = UnitClass("player")
  local bit = CLASS_BIT[classToken or ""] or nil
  if not bit then return nil end

  local seen, basePool = {}, 0
  for _, d in pairs(db) do
    if type(d) == "table" and d.comment and MaskHas(d.classMask, bit) then
      local k = StripQ(Norm(d.comment))
      if k ~= "" and not seen[k] then
        seen[k] = true
        -- No drop source => not tome-gated => permanently in the pool.
        if not (d.groupId and byGroup[d.groupId]) then basePool = basePool + 1 end
      end
    end
  end

  local on, off = 0, 0
  local tiles = Tiles()
  if tiles then
    local counted = {}
    for _, t in ipairs(tiles) do
      local k = StripQ(Norm(TomeName(t)))
      if not counted[k] then
        counted[k] = true
        if t.tomeDisabled == true then off = off + 1 else on = on + 1 end
      end
    end
  end
  local pool = basePool + on
  return basePool, on, off, ExpectedUniques(pool, 79), pool
end

function TM.Breadth()
  local base, on, off, uniq, pool = TM.PoolBreadth()
  if not base then
    PP.print("Can't measure breadth -- need the client's perk tables and the "
      .. "Echoes window open.")
    return
  end
  PP.print(("POOL BREADTH: %d drawable = %d base (never toggleable) + %d "
    .. "enabled tomes. %d tomes are off."):format(pool, base, on, off))
  local u = math.floor(uniq + 0.5)
  PP.print(("Expect about %d UNIQUE echoes over a 1-80 run, so Adaptive Power "
    .. "lands near +%d%%."):format(u, u))
  if off > 0 then
    local wasU = TM.ExpectedUniques(pool + off, 79)
    PP.print(("Turning all %d back on would give ~%d uniques (+%.1f%% Adaptive "
      .. "Power) but dilute every draw. Breadth is a stat; concentration is a "
      .. "hit rate. Pick knowingly."):format(off, math.floor(wasU + 0.5),
      wasU - uniq))
  end
end

-- ---------------------------------------------------------------------------
-- DROP SOURCES. The client ships ProjectEbonhold.PerkDropSources and
-- .PerkDropSourceByGroup -- the game's OWN answer to "where does this tome come
-- from". That beats EbonholdHub's EchoMapData (which predates ICC/RS and leaves
-- those tomes as "Location unknown") and beats guessing from echo names.
-- Shape is unknown from outside the client, so dump it flat and join it up
-- offline rather than assuming a schema.
local function Flatten(v, prefix, out, depth, budget)
  if #out >= budget then return end
  local t = type(v)
  if t ~= "table" then
    out[#out + 1] = prefix .. " = " .. tostring(v) .. "  (" .. t .. ")"
    return
  end
  if depth <= 0 then
    local n = 0
    for _ in pairs(v) do n = n + 1 end
    out[#out + 1] = prefix .. " = table(n=" .. n .. ") [depth cut]"
    return
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do
    if #out >= budget then
      out[#out + 1] = prefix .. " ... truncated at " .. budget .. " lines"
      return
    end
    Flatten(v[k], prefix .. "[" .. tostring(k) .. "]", out, depth - 1, budget)
  end
end

function TM.DropSourceDump()
  local PE = _G.ProjectEbonhold
  if type(PE) ~= "table" then return { note = "no ProjectEbonhold" } end
  local res = {}

  for _, field in ipairs({ "PerkDropSources", "PerkDropSourceByGroup" }) do
    local tbl = PE[field]
    local lines = {}
    if type(tbl) ~= "table" then
      lines[1] = field .. " = " .. type(tbl)
    else
      local n = 0
      for _ in pairs(tbl) do n = n + 1 end
      lines[1] = field .. ": " .. n .. " entries"
      Flatten(tbl, field, lines, 4, 4000)
    end
    res[field] = lines
  end

  -- Every perk with its groupId, so the source table can be joined to names
  -- offline no matter which key it is indexed by.
  local db = PE.PerkDatabase
  if type(db) == "table" then
    local perks = {}
    for id, d in pairs(db) do
      if type(d) == "table" then
        perks[#perks + 1] = table.concat({
          tostring(id), tostring(d.comment or "?"), tostring(d.groupId or ""),
          tostring(d.quality or ""), tostring(d.classMask or ""),
          tostring(d.minLevel or ""),
        }, "\t")
      end
    end
    table.sort(perks)
    res.perks = perks
    res.perksFormat = "spellId\tcomment\tgroupId\tquality\tclassMask\tminLevel"
  end
  return res
end

-- ---------------------------------------------------------------------------
-- FULL-CATALOG SCAN -> SavedVariables.
--
-- The journal scroll is virtualized, so any single read is a slice. This walks
-- the scroll from top to bottom, accumulating tiles by spellId, restores your
-- scroll position, and writes the complete picture to
-- PallyPilotDB.scans.tomes for reading off disk after a /reload -- no chat
-- output to copy out by hand.
--
-- Scrolling a frame is a read operation: it moves a UI view, touches no game
-- state, and sends nothing to the server. The enable/disable clicks stay manual
-- for the reasons in the file header.
local walker

local function Harvest(scroll, acc, order)
  local child = scroll:GetScrollChild()
  if not child or not child.GetChildren then return 0 end
  local added = 0
  for _, f in ipairs({ child:GetChildren() }) do
    if type(f) == "table" and f.spellId then
      local id = f.spellId
      if not acc[id] then
        acc[id] = {
          spellId = id, name = TomeName(f),
          known = (f.tomeKnown == true),
          disabled = (f.tomeDisabled == true),
          locked = (f.isLocked == true),
        }
        order[#order + 1] = id
        added = added + 1
      else
        -- A tile can be re-read at a later scroll position; keep the freshest
        -- flags rather than whichever pass happened to see it first.
        local rec = acc[id]
        rec.known = (f.tomeKnown == true)
        rec.disabled = (f.tomeDisabled == true)
        rec.locked = (f.isLocked == true)
      end
    end
  end
  return added
end

local function WriteScan(acc, order, meta)
  PP.db = PP.db or _G.PallyPilotDB
  if type(PP.db) ~= "table" then
    PP.print("No saved-variables table -- can't write the scan.")
    return
  end
  PP.db.scans = PP.db.scans or {}

  -- UNION with the previous snapshot, never replace it.
  --
  -- A scan can legitimately see less than a previous one -- a filtered journal
  -- view, a shorter scroll range, a different tab -- and tome ownership is
  -- permanent, so a narrow scan must not be able to shrink the recorded
  -- collection. Carry forward anything this pass did not see; take the fresh
  -- on/off and locked flags for anything it did. (Observed: a 355-tile scan
  -- recording 114 known tomes, then a 224-tile scan recording 90 and wiping
  -- the difference.)
  local prev = PP.db.scans.tomes
  local merged, mOrder, freshSeen = {}, {}, {}
  local function put(name, spellId, disabled, lockedFlag, fresh)
    local k = StripQ(Norm(name or ""))
    if k == "" then return end
    if fresh then freshSeen[k] = true end
    if not merged[k] then
      merged[k] = { name = name, spellId = spellId, disabled = disabled,
                    locked = lockedFlag }
      mOrder[#mOrder + 1] = k
    elseif fresh then
      merged[k].name = name
      merged[k].spellId = spellId or merged[k].spellId
      merged[k].disabled = disabled
      merged[k].locked = lockedFlag
    end
  end
  if prev and prev.tomes then
    for _, t in ipairs(prev.tomes) do
      put(t.name, t.id, t.off == 1, t.locked == 1, false)
    end
  end
  for _, id in ipairs(order) do
    local r = acc[id]
    if r.known then put(r.name, r.spellId, r.disabled, r.locked, true) end
  end

  local records, known, off, locked, carried = {}, 0, 0, 0, 0
  for _, k in ipairs(mOrder) do
    local r = merged[k]
    known = known + 1
    if r.disabled then off = off + 1 end
    if r.locked then locked = locked + 1 end
    if not freshSeen[k] then carried = carried + 1 end
    records[#records + 1] = r
  end

  local out = {
    when = date("%Y-%m-%d %H:%M:%S"),
    character = (UnitName("player") or "?") .. "-"
      .. (GetRealmName and GetRealmName() or "?"),
    level = UnitLevel("player"),
    class = select(1, UnitClass("player")),
    passes = meta.passes, scrollRange = meta.range,
    tilesSeen = #order, known = known, disabledAlready = off, lockedTiles = locked,
    -- how much of `known` this pass actually saw vs inherited from the last one
    carriedFromPrevious = carried,
    tomes = {},
    plans = {},
  }
  for _, r in ipairs(records) do
    local tier = (PP.EchoAudit and PP.EchoAudit.ClassifyName
      and PP.EchoAudit.ClassifyName(r.name)) or "REROLL"
    out.tomes[#out.tomes + 1] = {
      id = r.spellId, name = r.name, tier = tier,
      off = r.disabled and 1 or 0, locked = r.locked and 1 or 0,
    }
  end
  local wanted = TM.scanMode or "bis"
  local markPlan
  for _, mode in ipairs({ "bis", "tight", "clean" }) do
    local plan = TM.PlanRecords(records, mode)
    if mode == wanted then markPlan = plan end
    if plan then
      local d, e = {}, {}
      for _, x in ipairs(plan.disable) do
        d[#d + 1] = "[" .. x.tier .. "] " .. x.name .. " #" .. tostring(x.spellId)
      end
      for _, x in ipairs(plan.reenable) do
        e[#e + 1] = "[" .. x.tier .. "] " .. x.name .. " #" .. tostring(x.spellId)
      end
      out.plans[mode] = { disable = d, reenable = e }
    else
      out.plans[mode] = { error = "could not plan" }
    end
  end

  -- Spellbook cross-check: EchoOwnership treats spellId+100000 as the tome's
  -- spell, so this counts ownership WITHOUT the catalog. A big gap between the
  -- two numbers means the scan still missed part of the list.
  local db = _G.ProjectEbonhold and _G.ProjectEbonhold.PerkDatabase
  if type(db) == "table" and _G.IsSpellKnown then
    local n, total, names = 0, 0, {}
    for id, data in pairs(db) do
      total = total + 1
      local ok, res = pcall(_G.IsSpellKnown, id + 100000)
      if ok and res then
        n = n + 1
        local nm = (type(data) == "table" and data.comment) or ("Echo " .. tostring(id))
        names[#names + 1] = nm .. " #" .. tostring(id)
      end
    end
    table.sort(names)
    out.spellbook = { ownedTomes = n, perkDatabase = total, names = names }
  end

  -- Structural probe rides along: if a non-frame catalog source exists, this is
  -- what identifies it, and it costs nothing to capture in the same pass.
  if TM.ProbeLines then out.probe = TM.ProbeLines() end
  -- The client's own tome-source table: this is what fixes every
  -- "Location unknown" row in the farm queue.
  if TM.DropSourceDump then out.dropSources = TM.DropSourceDump() end

  -- RUN SET diagnostics. The Target-build panel showed "in-run 0" at level 80
  -- with a full run, which means whatever it asks for the current echoes came
  -- back empty. Capture every candidate source so the broken one is obvious.
  local runDiag = { }
  local EO = _G.EbonholdHub and _G.EbonholdHub.EchoOwnership
  if not EO then
    runDiag.note = "EbonholdHub.EchoOwnership absent"
  else
    local fns = {}
    for k, v in pairs(EO) do
      if type(v) == "function" then fns[#fns + 1] = k end
    end
    table.sort(fns)
    runDiag.functions = fns
    for _, fname in ipairs({ "CollectOwnedSets", "CollectTomeOwnedSets" }) do
      if type(EO[fname]) == "function" then
        local ok, res = pcall(EO[fname])
        if not ok then
          runDiag[fname] = "ERROR: " .. tostring(res)
        elseif type(res) ~= "table" then
          runDiag[fname] = "returned " .. type(res)
        else
          local n, sample = 0, {}
          for k in pairs(res) do
            n = n + 1
            if #sample < 8 then sample[#sample + 1] = tostring(k) end
          end
          table.sort(sample)
          runDiag[fname] = { count = n, sample = sample }
        end
      else
        runDiag[fname] = "not a function"
      end
    end
  end
  -- The perk service is the other route to "what is in my run right now".
  local PS = _G.ProjectEbonhold and _G.ProjectEbonhold.Perks
  if type(PS) == "table" and type(PS.grantedPerks) == "table" then
    local n = 0
    for _ in pairs(PS.grantedPerks) do n = n + 1 end
    runDiag.grantedPerks = n
  else
    runDiag.grantedPerks = "absent"
  end
  out.runSet = runDiag

  -- THE REROLL/BANISH BUDGETS, straight from the server's run data. Every
  -- description of this system so far has been inference from addon comments,
  -- and it has been wrong more than once. EbonholdPlayerRunData carries the
  -- actual counters EBH's automation reads (totalRerolls / usedRerolls /
  -- remainingBanishes), so dump the whole table and stop guessing.
  local rd = _G.EbonholdPlayerRunData
  if type(rd) ~= "table" then
    out.runData = { note = "EbonholdPlayerRunData absent (type "
      .. type(rd) .. ")" }
  else
    local keys, dump = {}, {}
    for k in pairs(rd) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local v = rd[k]
      local tv = type(v)
      if tv == "table" then
        local n = 0
        for _ in pairs(v) do n = n + 1 end
        dump[#dump + 1] = k .. " = table(n=" .. n .. ")"
      elseif tv ~= "function" then
        dump[#dump + 1] = k .. " = " .. tostring(v) .. "  (" .. tv .. ")"
      end
    end
    out.runData = dump
  end

  PP.db.scans.tomes = out
  -- The scan is the COMPLETE list, so it is the right thing to badge with.
  if markPlan then TM.Mark(markPlan) end

  local nOff = #((markPlan and markPlan.disable) or {})
  local nOn = #((markPlan and markPlan.reenable) or {})
  local lvl = UnitLevel("player") or 1
  PP.print(("TOME SCAN (%s): %d tiles over %d passes, %d known, %d already OFF.")
    :format(string.upper(wanted), out.tilesSeen, meta.passes, known, off))
  if nOff == 0 and nOn == 0 then
    PP.print("Pool already matches the plan -- nothing to toggle.")
  elseif lvl > 1 then
    -- The level gate lived in Preview and was lost when everything moved to
    -- Scan. Telling someone at level 79 to "right-click every badged tile" is
    -- worse than useless: the toggles will not apply and the run is spent.
    PP.print(("LEVEL %d -- the toggle window is CLOSED (level 1 only). %d want "
      .. "switching OFF and %d ON, but none of it can be applied until your "
      .. "next reset. Badged anyway so you can see the gap."):format(
      lvl, nOff, nOn))
  else
    PP.print(("-> %d to switch OFF (X badge), %d to switch back ON (tick "
      .. "badge). Scroll and right-click every badged tile."):format(nOff, nOn))
  end
end

function TM.Scan(mode)
  TM.scanMode = mode or TM.scanMode or "bis"
  local scroll = _G.ProjectEbonholdEchoJournalScroll
  if not scroll or not scroll.GetScrollChild or not scroll.SetVerticalScroll then
    PP.print("Open the Echoes window first (All Echoes tab, filter = All "
      .. "classes), then run the scan again.")
    return
  end
  if walker and walker.running then
    PP.print("A scan is already running -- let it finish.")
    return
  end
  walker = walker or CreateFrame("Frame")
  walker.running = true

  local acc, order = {}, {}
  local startPos = scroll:GetVerticalScroll() or 0
  local range = scroll:GetVerticalScrollRange() or 0
  local step = 120
  local pos, passes, settle, idle = 0, 0, 0, 0

  scroll:SetVerticalScroll(0)
  walker:SetScript("OnUpdate", function(self, elapsed)
    settle = settle + (elapsed or 0)
    if settle < 0.06 then return end   -- let the journal redraw before reading
    settle = 0
    local added = Harvest(scroll, acc, order)
    passes = passes + 1
    if added == 0 then idle = idle + 1 else idle = 0 end
    -- Stop at the bottom, or if several passes in a row find nothing new
    -- (guards a range that never reports the true end).
    if pos >= range or idle >= 3 or passes > 400 then
      self:SetScript("OnUpdate", nil)
      self.running = false
      pcall(scroll.SetVerticalScroll, scroll, startPos)
      WriteScan(acc, order, { passes = passes, range = range })
      return
    end
    pos = math.min(pos + step, range)
    scroll:SetVerticalScroll(pos)
  end)
  PP.print("Scanning the full catalog -- don't touch the Echoes window...")
end

-- ---------------------------------------------------------------------------
-- PROBE: find a catalog source that isn't the rendered frames.
--
-- Scraping ProjectEbonholdEchoJournalScroll's children is provably partial (the
-- scroll is virtualized: measured 63 tiles / 46 known at the top and 81 / 13
-- lower down on the same collection, 2026-09-01). Everything downstream --
-- ownership, pool size, reroll odds, the BiS panel -- inherits that error, so
-- the fix is to read whatever table the journal itself renders FROM.
-- This dumps the shape of the candidates so that source can be identified.
local function Shape(v, depth)
  local t = type(v)
  if t ~= "table" then return t end
  local n, keys = 0, {}
  for k in pairs(v) do
    n = n + 1
    if n <= 6 then keys[#keys + 1] = tostring(k) end
  end
  table.sort(keys)
  local arr = #v
  local desc = "table(n=" .. n .. (arr > 0 and (", array=" .. arr) or "") .. ")"
  if depth and depth > 0 and n > 0 then
    desc = desc .. " keys{" .. table.concat(keys, ",") .. "}"
  end
  return desc
end

-- Returns the probe as an array of strings so the SAME data can go to chat or
-- into SavedVariables. Never throws: every lookup is guarded.
function TM.ProbeLines()
  local L = {}
  local function add(s) L[#L + 1] = s end

  local PE = _G.ProjectEbonhold
  if type(PE) ~= "table" then
    add("ProjectEbonhold table not present -- nothing to probe.")
    return L
  end

  -- 1. Top-level namespaces.
  local names = {}
  for k in pairs(PE) do names[#names + 1] = tostring(k) end
  table.sort(names)
  add("namespaces: " .. table.concat(names, ", "))

  -- 2. The journal object -- the thing that renders the catalog. If it holds
  --    the entry list, that list is the authoritative source we want.
  local ej = PE.EchoJournal
  if type(ej) ~= "table" then
    add("EchoJournal: " .. type(ej) .. " -- not a table.")
  else
    local ks = {}
    for k in pairs(ej) do ks[#ks + 1] = tostring(k) end
    table.sort(ks)
    add("EchoJournal fields (" .. #ks .. "):")
    for _, k in ipairs(ks) do
      add("   ." .. k .. " = " .. Shape(ej[k], 1))
      -- One level deeper on array-ish fields: an entry's key names are what
      -- tell us whether known/disabled live here.
      local v = ej[k]
      if type(v) == "table" and #v > 0 and type(v[1]) == "table" then
        local fs = {}
        for fk in pairs(v[1]) do fs[#fs + 1] = tostring(fk) end
        table.sort(fs)
        add("      [1] keys: " .. table.concat(fs, ", "))
      end
    end
  end

  -- 3. PerkDatabase entry shape -- the full echo list, keyed by spellId.
  local db = PE.PerkDatabase
  if type(db) == "table" then
    local count, sampleId, sample = 0, nil, nil
    for id, data in pairs(db) do
      count = count + 1
      if not sampleId and type(data) == "table" then sampleId, sample = id, data end
    end
    add("PerkDatabase: " .. count .. " entries. Sample id " .. tostring(sampleId) .. ":")
    if sample then
      local fs = {}
      for k in pairs(sample) do fs[#fs + 1] = tostring(k) end
      table.sort(fs)
      for _, k in ipairs(fs) do
        add("   ." .. k .. " = " .. tostring(sample[k])
          .. "  (" .. type(sample[k]) .. ")")
      end
    end
  else
    add("PerkDatabase: absent.")
  end

  -- 4. Spellbook path: EchoOwnership treats spellId+100000 as the tome's spell,
  --    so this answers ownership for the WHOLE database with no scrolling.
  if type(db) == "table" and _G.IsSpellKnown then
    local known, checked = 0, 0
    for id in pairs(db) do
      checked = checked + 1
      local ok, res = pcall(_G.IsSpellKnown, id + 100000)
      if ok and res then known = known + 1 end
    end
    add("IsSpellKnown(id+100000): owns " .. known .. " of " .. checked .. ".")
  else
    add("IsSpellKnown unavailable -- spellbook path untestable.")
  end
  return L
end

function TM.Probe()
  for _, line in ipairs(TM.ProbeLines()) do
    DEFAULT_CHAT_FRAME:AddMessage(line)
  end
end

-- ---------------------------------------------------------------------------
-- /pp tomes [bis|tight] [go|scan|debug|probe]
function TM.Command(arg)
  arg = string.lower(arg or "")
  if string.find(arg, "left") then TM.Left(); return end
  if string.find(arg, "breadth") then TM.Breadth(); return end
  if string.find(arg, "probe") then TM.Probe(); return end
  if string.find(arg, "debug") then TM.Debug(); return end
  local mode = (string.find(arg, "bis") and "bis")
    or (string.find(arg, "tight") and "tight") or "clean"
  -- ALWAYS walk the full catalog. The journal scroll is virtualized, so a plan
  -- built from the rendered tiles is a slice -- which is how a run once
  -- reported "nothing to do" while 28 tomes were still wrong. There is no
  -- slice-only path any more; "scan" is kept only as a familiar alias.
  TM.Scan(mode)
end
