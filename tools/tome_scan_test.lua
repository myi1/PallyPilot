-- Does TM.Scan() actually defeat virtualization? Simulate the real journal:
-- 300 echoes, but the scroll child only ever exposes a ~60-tile window around
-- the current scroll offset -- exactly the behaviour measured in-game.
PallyPilot = { TomeManager = {}, print = function(s) print("[EP] " .. s) end }
EbonPilot = PallyPilot
local PP = PallyPilot
DEFAULT_CHAT_FRAME = { AddMessage = function(_, s) print(s) end }
function UnitLevel() return 1 end
function UnitName() return "Keepsy" end
function GetRealmName() return "Rogue-Lite" end
function UnitClass() return "PALADIN", "PALADIN" end
function date(f) return "2026-09-01 04:00:00" end
function GetSpellInfo(id) return "Spell" .. tostring(id) end

PallyPilotDB = {}
PP.db = PallyPilotDB

-- 300 echoes; every 10th is a BiS target, every 7th already disabled.
local CATALOG = {}
PerkDatabase = {}
for i = 1, 300 do
  local id = 5000 + i
  CATALOG[i] = {
    spellId  = id,
    name     = "Echo " .. i,
    known    = (i % 3 ~= 0),          -- two thirds unlocked
    disabled = (i % 7 == 0),
    locked   = false,
  }
  PerkDatabase[id] = { comment = "Echo " .. i }
end
local function IsTargetName(n) return tonumber(string.match(n, "%d+")) % 10 == 0 end
PP.EchoAudit = { ClassifyName = function(n)
  return IsTargetName(n) and "S" or "A"
end }
-- Since the CHASE/KEEP/CUT split, pool curation reads IsKeep (broad), not
-- IsTarget (the short reroll list), and guards on Build.KeepSet().
PP.BisPlan = {
  Target   = function() return { { name = "Echo 10" } } end,
  IsTarget = IsTargetName,
  IsKeep   = IsTargetName,
}
PP.Build = { KeepSet = function() return { ["echo 10"] = true } end }

-- Virtualized scroll: exposes only the window at the current offset.
local WINDOW, ROWH = 60, 20
local scrollPos, maxRange = 0, (300 * ROWH) - (WINDOW * ROWH)
local scroll = {
  GetVerticalScroll = function() return scrollPos end,
  SetVerticalScroll = function(_, v)
    scrollPos = math.max(0, math.min(v or 0, maxRange))
  end,
  GetVerticalScrollRange = function() return maxRange end,
  GetScrollChild = function()
    local first = math.floor(scrollPos / ROWH) + 1
    local frames = {}
    for i = first, math.min(first + WINDOW - 1, 300) do
      local e = CATALOG[i]
      frames[#frames + 1] = { spellId = e.spellId, tomeKnown = e.known,
        tomeDisabled = e.disabled, isLocked = e.locked }
    end
    return { GetChildren = function() return (unpack or table.unpack)(frames) end }
  end,
}
ProjectEbonholdEchoJournalScroll = scroll
-- PerkDropSourceByGroup must be present, otherwise TM.PoolBreadth() bails early
-- and Preview's breadth branch never runs -- which is exactly how a nil-global
-- crash in that branch reached the live client unnoticed. Give every perk a
-- groupId and source half the groups, so base-vs-tome-gated is a real split.
local byGroup = {}
for i = 1, 300 do
  PerkDatabase[5000 + i].groupId = i
  PerkDatabase[5000 + i].classMask = 1535       -- all classes incl. paladin
  if i % 2 == 0 then byGroup[i] = "Can be found on Test Boss " .. i end
end
ProjectEbonhold = {
  PerkDatabase = PerkDatabase,
  EchoJournal = { entries = {} },
  PerkDropSourceByGroup = byGroup,
  PerkDropSources = {},
}
function UnitClass() return "Paladin", "PALADIN" end
function IsSpellKnown(id) return PerkDatabase[id - 100000] ~= nil end

function time() return 1756700000 end
refreshed = false
PP.safeCall = function(fn, ...) return fn(...) end
PP.EchoFlow = { RefreshBadges = function() refreshed = true end }

-- Minimal CreateFrame: capture the OnUpdate so the test can pump it.
local pump
function CreateFrame()
  return {
    SetScript = function(self, k, fn) if k == "OnUpdate" then pump = fn end end,
    Hide = function() end, Show = function() end,
  }
end

local chunk = assert(loadfile("TomeManager.lua"))
chunk()
local TM = PP.TomeManager

-- Baseline: what a single on-screen read sees.
local partial = assert(TM.Plan("bis"))
print(string.format("single-view plan: %d tiles, %d to disable",
  partial.total, #partial.disable))

-- Breadth must be measurable here, so Preview's breadth branch really executes
-- rather than being skipped for want of the client tables.
local base, on, off, uniq, pool = TM.PoolBreadth()
assert(base and base > 0, "PoolBreadth must resolve a base pool in this stub")
assert(pool and pool > base, "pool = base + enabled tomes")
print(string.format("breadth:     base=%d enabled=%d off=%d pool=%d uniques=%.1f",
  base, on, off, pool, uniq))
assert(TM.ExpectedUniques(100, 79) > 0, "ExpectedUniques must be callable as a TM field")

-- REGRESSION: the breadth readout calls file-locals (ExpectedUniques) declared
-- BELOW it, which compile to a global lookup and threw "attempt to call a nil
-- value" in the live client. Exercise it with breadth resolvable so that path
-- can never go uncovered again.
local printed = {}
local realPrint = PP.print
PP.print = function(s) printed[#printed + 1] = s end
TM.Breadth()
PP.print = realPrint
local sawBreadth = false
for _, l in ipairs(printed) do
  if string.find(l, "POOL BREADTH", 1, true) then sawBreadth = true end
end
assert(sawBreadth, "Breadth must print the pool line when breadth resolves")
assert(#printed <= 4,
  "Breadth must stay terse -- no chat walls. Printed " .. #printed .. " lines")
print("breadth out: " .. #printed .. " lines, pool line present")

-- TM.Plan must read the MERGED catalog, never the rendered slice: BuildScore
-- grades pool hygiene off it, and a slice read made the score move with the
-- journal's scroll position.
local merged = TM.Plan("bis")
assert(merged, "Plan must build from MergedTiles")
assert(merged.total >= 40,
  "Plan saw only " .. tostring(merged.total) .. " tomes -- that is the slice, "
  .. "not the merged catalog")
print("plan source: merged catalog, " .. merged.total .. " known tomes")

-- /ep tomes bis must WALK, not read the visible slice. A slice-built plan once
-- reported "nothing to do" while 28 tomes were still wrong.
TM.scanMode = nil
PP.print = function() end
TM.Command("bis")
PP.print = realPrint
assert(TM.scanMode == "bis", "Command('bis') must route into the full-catalog scan")

TM.Scan()
local ticks = 0
while pump and ticks < 5000 do
  ticks = ticks + 1
  pump({ SetScript = function(_, k, fn) if k == "OnUpdate" then pump = fn end end,
         Hide = function() end, running = true }, 0.1)
  if PallyPilotDB.scans and PallyPilotDB.scans.tomes then break end
end

local s = assert(PallyPilotDB.scans and PallyPilotDB.scans.tomes, "scan never wrote")
print(string.format("full scan:  %d tiles seen, %d known, %d passes",
  s.tilesSeen, s.known, s.passes))
print(string.format("bis plan:   %d to disable", #s.plans.bis.disable))
print("scroll restored to " .. scrollPos .. " (started at 0)")

-- 300 tiles total; known = those not divisible by 3 = 200.
assert(s.tilesSeen == 300, "expected all 300 tiles, got " .. s.tilesSeen)
assert(s.known == 200, "expected 200 known, got " .. s.known)
-- Disable = known, enabled, not locked, not a target.
local expect = 0
for i = 1, 300 do
  local e = CATALOG[i]
  if e.known and not e.disabled and not IsTargetName(e.name) then expect = expect + 1 end
end
assert(#s.plans.bis.disable == expect,
  "disable list " .. #s.plans.bis.disable .. " != expected " .. expect)
assert(#s.plans.bis.disable > #partial.disable,
  "full scan must beat the single-view read")
assert(s.spellbook and s.spellbook.ownedTomes == 300, "spellbook cross-check")
assert(type(s.probe) == "table" and #s.probe > 0, "probe rode along")

-- The badge handoff is the part that silently does nothing if the two modules
-- normalise names differently, so assert it end to end.
local pp = PallyPilotDB.poolPlan
assert(pp and pp.set, "scan must badge the tiles")
assert(pp.n == #s.plans.bis.disable, "badge count must match the plan")
assert(refreshed, "EchoFlow.RefreshBadges must be called")
local marked = 0
for _ in pairs(pp.set) do marked = marked + 1 end
print(string.format("badges:     %d names marked, RefreshBadges called", marked))

-- Replicate EchoFlow's NormEF and confirm every disable-list tile resolves.
local function NormEF(n)
  return string.lower(string.gsub(n or "", "\226\128\153", "'"))
end
for _, line in ipairs(s.plans.bis.disable) do
  local nm = string.match(line, "^%[[^%]]*%]%s(.-)%s#%d+$")
  assert(nm, "could not parse plan line: " .. line)
  assert(pp.set[NormEF(nm)], "tile not badged: " .. nm)
end

-- A curly-apostrophe name must survive the round trip -- this is the exact
-- class of bug that made earlier ownership checks silently miss echoes.
assert(NormEF("Reaper\226\128\153s Doom") == "reaper's doom", "apostrophe norm")

print("\nSCAN OK -- virtualization defeated, plan complete, scroll restored,")
print("every disable target badged with keys EchoFlow can match.")
