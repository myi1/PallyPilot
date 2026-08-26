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

-- Colorblind-safe: every tier prints a literal text marker, not just a color.
local MARK = {
  CORE = "[CORE]", S = "[S]", A = "[A]", B = "[B]", C = "[C]",
  DISABLE = "[X]", REROLL = "[X]",
}
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
-- Plan: which owned tomes to disable (junk currently ON) and which to
-- re-enable (keepers currently OFF), for the given mode.
--   "clean" (default): keep breadth — disable only rated junk (X); re-enable
--                       any CORE/S/A you turned off by mistake.
--   "tight"          : curate a fishing pool — keep ON only locks + CORE/S/A;
--                       disable B/C/junk; re-enable disabled keepers.
function TM.Plan(mode)
  local tiles, why = Tiles()
  if not tiles then return nil, why end
  local disable, reenable = {}, {}
  for _, t in ipairs(tiles) do
    local name = TomeName(t)
    local tier = (PP.EchoAudit and PP.EchoAudit.ClassifyName
      and PP.EchoAudit.ClassifyName(name)) or "REROLL"
    local off = (t.tomeDisabled == true)
    local locked = (t.isLocked == true)
    local wantOn
    if mode == "tight" then
      wantOn = locked or KEEP[tier]
    else
      wantOn = locked or (not JUNK[tier])
    end
    if wantOn and off then
      reenable[#reenable + 1] = { tile = t, name = name, tier = tier }
    elseif (not wantOn) and (not off) and (not locked) then
      disable[#disable + 1] = { tile = t, name = name, tier = tier }
    end
  end
  table.sort(reenable, function(a, b)
    if RANK[a.tier] ~= RANK[b.tier] then return RANK[a.tier] < RANK[b.tier] end
    return a.name < b.name
  end)
  table.sort(disable, function(a, b)  -- worst (X) first
    if RANK[a.tier] ~= RANK[b.tier] then return RANK[a.tier] > RANK[b.tier] end
    return a.name < b.name
  end)
  return { disable = disable, reenable = reenable, total = #tiles, mode = mode }
end

local function CantRead(why)
  if why == "closed" or why == "empty" then
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
  if #plan.disable > 0 then
    PP.print("-> DISABLE " .. #plan.disable .. " (junk currently ON):")
    for i, e in ipairs(plan.disable) do
      DEFAULT_CHAT_FRAME:AddMessage("   " .. i .. ". " .. (MARK[e.tier] or "[?]")
        .. " " .. e.name)
    end
  else
    PP.print("-> DISABLE: nothing — no rated junk is currently enabled.")
  end
  if #plan.reenable > 0 then
    PP.print("-> RE-ENABLE " .. #plan.reenable .. " (keepers you turned OFF):")
    for i, e in ipairs(plan.reenable) do
      DEFAULT_CHAT_FRAME:AddMessage("   " .. i .. ". " .. (MARK[e.tier] or "[?]")
        .. " " .. e.name)
    end
  else
    PP.print("-> RE-ENABLE: nothing — all keepers are already ON.")
  end
  if #plan.disable > 0 or #plan.reenable > 0 then
    if lvl == 1 then
      PP.print("Right-click each tile above in the catalog and click Yes. Each "
        .. "tile now shows its verdict LETTER (top-right) so it's easy to find.")
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
-- /pp tomes [tight] [go]
function TM.Command(arg)
  arg = string.lower(arg or "")
  local mode = string.find(arg, "tight") and "tight" or "clean"
  if string.find(arg, "go") then TM.Go(mode) else TM.Preview(mode) end
end
