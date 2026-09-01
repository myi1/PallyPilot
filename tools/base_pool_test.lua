-- BASE-POOL ECHOES ARE NOT "UNOBTAINABLE".
--
-- Roughly 400 of the ~550 echoes need no tome at all: they are permanently in
-- the draw pool. Their catalog tiles report tomeKnown = false, and the addon
-- used to read that as "you cannot have this" -- so WantList never suggested
-- chasing one and PoolSize left every one of them out of the odds. Both
-- answers were wrong by hundreds of entries.
--
-- The separator is the client's own drop-source table: an echo with a drop
-- source is tome-gated, one without is base pool. This asserts all three
-- states, including the one that must stay conservative -- when the client
-- tables are missing we cannot tell, so we fall back to the old reading rather
-- than inventing a pool.
--
-- Also covers FishStatus, whose unique count feeds the Adaptive Power readout:
-- grantedPerks omits LOCKED echoes, so counting it alone was short by up to six.
--
--   node tools/run_lua.js tools/base_pool_test.lua
PallyPilot = { Classes = {}, print = function() end,
               safeCall = function(fn, ...) return fn(...) end }
EbonPilot = PallyPilot
local PP = PallyPilot
PP.db = { options = {}, scans = {} }
local function Stub()
  local t = {}
  return setmetatable(t, { __index = function() return function() return t end end })
end
function CreateFrame() return Stub() end
function UnitLevel() return 80 end
function GetTime() return 0 end
function date() return "2026-09-01 18:00" end
function UnitClass() return "Paladin", "PALADIN" end
UIParent = Stub()
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
ProjectEbonholdEchoJournalScroll = { GetScrollChild = function() return nil end }

assert(loadfile("BuildData.lua"))()
PP.Build = PP.Classes.PALADIN
PP.TomeManager = PP.TomeManager or {}
assert(loadfile("TomeManager.lua"))()
local TM = PP.TomeManager

-- Two echoes, one gated behind a tome (it has a drop source), one not.
ProjectEbonhold = {
  PerkDatabase = {
    [1] = { comment = "Contagion", groupId = 7 },          -- tome-gated
    [2] = { comment = "Widow's Venom" },                   -- base pool, no group
    [3] = { comment = "Heavy Incantations", groupId = 99 },-- group with no source
  },
  PerkDropSourceByGroup = { [7] = { "Naxxramas" } },
  Perks = { grantedPerks = {} },
}

assert(TM.TomeGated("Contagion") == true, "an echo with a drop source is gated")
assert(TM.TomeGated("Widow's Venom") == false, "no drop source = base pool")
assert(TM.TomeGated("Heavy Incantations") == false,
  "a groupId with no drop source is still base pool")
print("gating:      Contagion=gated, Widow's Venom=base, Heavy Incantations=base")

-- ---------------------------------------------------------------------------
-- The pool count itself. Three tiles: one owned tome, one un-owned base-pool
-- echo (must COUNT), one un-owned gated echo (must not).
PP.EchoAudit = PP.EchoAudit or {}
assert(loadfile("EchoAudit.lua"))()
local A = PP.EchoAudit

PP.db.scans.tomes = { tomes = {
  { name = "Twilight Equilibrium", off = 0, locked = 0 },
  { name = "Widow's Venom",        off = 0, locked = 0 },
  { name = "Contagion",            off = 0, locked = 0 },
} }
-- MergedTiles marks everything from a scan snapshot as known, so drive the
-- known flag from AllTiles instead -- that is the shape the live client has.
local tiles = {
  { name = "Twilight Equilibrium", known = true,  disabled = false, locked = false },
  { name = "Widow's Venom",        known = false, disabled = false, locked = false },
  { name = "Contagion",            known = false, disabled = false, locked = false },
}
PP.db.scans.tomes = nil
TM.MergedTiles = function() return tiles, "live", {} end

ProjectEbonhold.Perks.grantedPerks = { ["Conjured Flame"] = { { quality = 1 } } }
-- The run set comes from EbonholdHub, not the addon.
local runSet = { ["conjured flame"] = true }
EbonholdHub = { EchoOwnership = {
  CollectOwnedSets = function() return runSet end } }

local total, junk = A.PoolSize()
assert(total, "PoolSize must resolve with tiles and a run present")
print("pool size:   " .. total .. " drawable (" .. tostring(junk) .. " rated junk)")
assert(total == 2,
  "expected the owned tome + the base-pool echo, got " .. total
  .. " -- a gated echo with no tome must stay out, a base-pool one must not")

-- Conservative fallback: with the client tables gone we cannot tell base from
-- gated, so an unknown tome must NOT be counted rather than guessed in.
local savedDb = ProjectEbonhold.PerkDatabase
ProjectEbonhold.PerkDatabase = nil
TM.TomeGated = function() return nil end
local fallback = A.PoolSize()
assert(fallback == 1,
  "without the client tables only the OWNED tome may count, got " .. tostring(fallback))
ProjectEbonhold.PerkDatabase = savedDb
print("fallback:    " .. fallback .. " (owned only -- no guessing)")

-- ---------------------------------------------------------------------------
-- FishStatus: locked echoes are active echoes, so Adaptive Power counts them.
ProjectEbonhold.Perks.grantedPerks = {
  ["Conjured Flame"] = { { quality = 3 } },
  ["Widow's Venom"]  = { { quality = 3 } },
}
runSet = { ["ambidexterity"] = true, ["pandemic"] = true,
           ["conjured flame"] = true }

local st = A.FishStatus()
assert(st, "FishStatus must resolve with grantedPerks present")
print("uniques:     " .. st.uniques .. " (2 granted + 2 locks not in grantedPerks)")
assert(st.uniques == 4,
  "locked echoes must count toward Adaptive Power; got " .. st.uniques
  .. " (grantedPerks alone would say 2)")

-- ---------------------------------------------------------------------------
-- CHAT WALLS. /ep want used to print up to twelve list lines plus three
-- multi-sentence paragraphs, which scrolls its own headline out of view.
local OUT = {}
PP.print = function(x) OUT[#OUT + 1] = tostring(x) end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, x) OUT[#OUT + 1] = tostring(x) end }
A.WantReport()
print("want lines:  " .. #OUT)
assert(#OUT <= 4, "/ep want must stay within 4 lines, printed " .. #OUT)

print("\nBASE POOL OK -- no tome does not mean no echo, locks count, want is terse.")
