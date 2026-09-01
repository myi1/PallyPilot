-- MergedTiles must give callers the WHOLE collection, not the rendered slice.
--
-- The bug this guards: BisPlan.Status() asked AllTiles() "do I own this tome?"
-- while the journal scroll is virtualized, so 10 owned echoes rendered as
-- [FARM] in the Target-build panel. The merge takes ownership from the last
-- full scan (permanent, so staleness is safe) and the live on/off + locked
-- flags from whatever is currently drawn.
--
--   node tools/run_lua.js tools/merged_tiles_test.lua
PallyPilot = { TomeManager = {}, print = function(s) print("[EP] " .. s) end }
EbonPilot = PallyPilot
local PP = PallyPilot
DEFAULT_CHAT_FRAME = { AddMessage = function(_, s) print(s) end }
function UnitLevel() return 80 end
function UnitClass() return "Paladin", "PALADIN" end
function GetSpellInfo(id) return "Spell" .. tostring(id) end
PP.EchoAudit = { ClassifyName = function() return "A" end }
PP.BisPlan = { IsKeep = function() return true end }
PP.Build = { KeepSet = function() return { x = true } end }

-- Saved scan: the complete collection (four owned tomes).
PP.db = { scans = { tomes = { when = "2026-09-01 03:55:19", tomes = {
  { id = 1, name = "Alpha",   tier = "S", off = 0, locked = 0 },
  { id = 2, name = "Beta",    tier = "A", off = 1, locked = 0 },
  { id = 3, name = "Gamma",   tier = "A", off = 0, locked = 0 },
  { id = 4, name = "Delta",   tier = "B", off = 1, locked = 0 },
} } } }

-- Live view renders only TWO of them, and Beta has since been switched back ON.
PerkDatabase = {
  [11] = { comment = "Alpha" },
  [12] = { comment = "Beta" },
}
local children = {
  { spellId = 11, tomeKnown = true, tomeDisabled = false, isLocked = true },
  { spellId = 12, tomeKnown = true, tomeDisabled = false, isLocked = false },
}
local unpackFn = unpack or table.unpack
ProjectEbonholdEchoJournalScroll = {
  GetScrollChild = function()
    return { GetChildren = function() return unpackFn(children) end }
  end,
}

assert(loadfile("TomeManager.lua"))()
local TM = PP.TomeManager

local merged, source, stats = TM.MergedTiles()
assert(merged, "merge must produce records")
local by = {}
for _, t in ipairs(merged) do by[string.lower(t.name)] = t end

print(("source=%s  scan=%d live=%d  merged=%d"):format(
  source, stats.scan, stats.live, #merged))

-- 1. Completeness: tomes the live view never rendered must still be present.
assert(by["gamma"], "Gamma came only from the scan and must survive the merge")
assert(by["delta"], "Delta came only from the scan and must survive the merge")
assert(#merged == 4, "expected all four owned tomes, got " .. #merged)

-- 2. Ownership is never lost to staleness.
for _, n in ipairs({ "alpha", "beta", "gamma", "delta" }) do
  assert(by[n].known, n .. " must read as owned")
end

-- 3. The live view WINS on mutable flags: Beta was off in the scan and is on
--    now, so the merge must report it enabled -- otherwise the plan would tell
--    you to re-enable something already enabled.
assert(by["beta"].disabled == false, "live state must override the stale scan")
assert(by["alpha"].locked == true, "live locked flag must come through")
-- ...but a tome the live view cannot see keeps its scanned flags.
assert(by["delta"].disabled == true, "unrendered tome keeps its scanned state")

-- 4. With no scan at all, the caller must be told the read is partial.
PP.db.scans = nil
local m2, s2 = TM.MergedTiles()
assert(m2 and s2 == "live-partial",
  "with no scan the source must be flagged live-partial, got " .. tostring(s2))
print("no-scan source=" .. s2 .. " (" .. #m2 .. " tiles)")

-- 5. A NARROWER scan must not shrink the recorded collection. Ownership is
--    permanent, so WriteScan unions with the previous snapshot. Drive a real
--    scan whose visible catalog is a strict subset of the saved one.
PP.db = { scans = { tomes = { when = "old", tomes = {
  { id = 1, name = "Alpha", tier = "S", off = 0, locked = 0 },
  { id = 2, name = "Beta",  tier = "A", off = 1, locked = 0 },
  { id = 3, name = "Gamma", tier = "A", off = 0, locked = 0 },
  { id = 4, name = "Delta", tier = "B", off = 1, locked = 0 },
} } } }
function UnitName() return "Keepsy" end
function GetRealmName() return "Test" end
function date() return "2026-09-01 05:00:00" end
function time() return 1756700000 end
PP.safeCall = function(fn, ...) return fn(...) end
PP.EchoFlow = { RefreshBadges = function() end }
local pump
function CreateFrame()
  return { SetScript = function(_, k, fn) if k == "OnUpdate" then pump = fn end end,
           Hide = function() end, Show = function() end }
end
-- Only Alpha and Beta are visible this time; Beta is now ON.
ProjectEbonholdEchoJournalScroll.GetVerticalScroll = function() return 0 end
ProjectEbonholdEchoJournalScroll.SetVerticalScroll = function() end
ProjectEbonholdEchoJournalScroll.GetVerticalScrollRange = function() return 0 end

TM.Scan("bis")
local ticks = 0
while pump and ticks < 200 do
  ticks = ticks + 1
  pump({ SetScript = function() end, Hide = function() end }, 0.1)
  if PP.db.scans.tomes.when == "2026-09-01 05:00:00" then break end
end
local after = PP.db.scans.tomes
print(("after narrow scan: known=%d (carried %s) tilesSeen=%d"):format(
  after.known, tostring(after.carriedFromPrevious), after.tilesSeen))
assert(after.known == 4,
  "narrow scan must not shrink the collection; got " .. after.known)
local seen = {}
for _, t in ipairs(after.tomes) do seen[string.lower(t.name)] = t end
assert(seen["gamma"] and seen["delta"], "unseen tomes must be carried forward")
assert(seen["beta"].off == 0, "a tome seen this pass takes its fresh state")
assert(seen["delta"].off == 1, "a tome not seen keeps its previous state")
assert(after.carriedFromPrevious == 2,
  "only Gamma and Delta were unseen; carried=" .. tostring(after.carriedFromPrevious))

print("\nMERGE OK -- complete collection, live flags win, partial read flagged,")
print("and a narrower scan never shrinks what is recorded.")
