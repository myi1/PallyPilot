-- Offline smoke test for TomeManager.Probe: it must survive a realistic
-- ProjectEbonhold stub, and also the degenerate cases (missing EchoJournal,
-- missing IsSpellKnown) without throwing inside the client.
PallyPilot = { TomeManager = {}, print = function(s) print("[EP] " .. s) end }
EbonPilot = PallyPilot
local PP = PallyPilot
DEFAULT_CHAT_FRAME = { AddMessage = function(_, s) print(s) end }
function date() return "2026-09-01 18:00" end
function UnitLevel() return 1 end
function GetSpellInfo(id) return "Spell" .. tostring(id) end
PP.EchoAudit = { ClassifyName = function() return "A" end }
PP.BisPlan = { Target = function() return {} end, IsTarget = function() return false end }
PerkDatabase = {}
ProjectEbonholdEchoJournalScroll = { GetScrollChild = function() return nil end }

ProjectEbonhold = {
  PerkDatabase = {
    [5001] = { comment = "Twilight Equilibrium", quality = 3, groupId = 12,
               requiredSpell = 999 },
    [5002] = { comment = "Rocket Strike", quality = 1, groupId = 13 },
    [5003] = { comment = "Quickened Tempo", quality = 2, groupId = 14 },
  },
  EchoJournal = {
    OnDataChanged = function() end,
    entries       = { {}, {}, {} },
    filter        = "all",
    selectedTab   = 2,
  },
  PerkService = {}, Perks = {}, PlayerRunService = {},
}
-- Only the middle echo's tome is "known".
function IsSpellKnown(id) return id == 105002 end

local chunk = assert(loadfile("TomeManager.lua"))
chunk()
local TM = PP.TomeManager

print("=== Probe: full stub ===")
TM.Probe()

print("\n=== Probe: no EchoJournal, no IsSpellKnown ===")
ProjectEbonhold.EchoJournal = nil
IsSpellKnown = nil
TM.Probe()

print("\n=== Probe: no ProjectEbonhold at all ===")
ProjectEbonhold = nil
TM.Probe()

print("\nPROBE SMOKE OK -- no errors in any of the three states.")
