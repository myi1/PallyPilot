-- Offline exercise of TomeManager.Preview + TomeManager.Debug against a fake
-- Echo Journal, covering the exact shape keepsy hit: quality variants of one
-- echo (same name, DIFFERENT spellIds) sitting next to a same-id read bug.
PallyPilot = { TomeManager = {}, print = function(s) print("[EP] " .. s) end }
EbonPilot = PallyPilot
local PP = PallyPilot

DEFAULT_CHAT_FRAME = { AddMessage = function(_, s) print(s) end }
function UnitLevel() return 1 end
function GetSpellInfo(id) return "Spell" .. tostring(id) end

-- name -> tier, so the plan has something to rate against.
local TIER = {
  ["Quickened Tempo"] = "A", ["Rocket Strike"] = "A", ["Mana Infusion"] = "B",
  ["Twilight Equilibrium"] = "S", ["Ghost Tile"] = "A",
}
PP.EchoAudit = { ClassifyName = function(n) return TIER[n] or "REROLL" end }
-- Pool curation reads IsKeep since the CHASE/KEEP/CUT split; IsTarget is now
-- only the short reroll list.
local function isTE(n) return n == "Twilight Equilibrium" end
PP.BisPlan = { Target = function() return { { name = "Twilight Equilibrium" } } end,
               IsTarget = isTE, IsKeep = isTE }
PP.Build = { KeepSet = function() return { ["twilight equilibrium"] = true } end }

-- Fake catalog. Each entry becomes a tile frame.
local FAKE = {
  { id = 101, name = "Quickened Tempo",      known = true },
  { id = 102, name = "Quickened Tempo",      known = true },  -- real variant
  { id = 201, name = "Rocket Strike",        known = true },
  { id = 201, name = "Rocket Strike",        known = true },  -- SAME id: bug
  { id = 301, name = "Mana Infusion",        known = true },
  { id = 401, name = "Twilight Equilibrium", known = true },  -- target, stays
  { id = 501, name = "Ghost Tile",           known = false }, -- unowned
  { id = 601, name = "Quickened Tempo",      known = true, disabled = true },
}
PerkDatabase = {}
local children = {}
for _, e in ipairs(FAKE) do
  PerkDatabase[e.id] = { comment = e.name }
  children[#children + 1] = {
    spellId = e.id, tomeKnown = e.known,
    tomeDisabled = e.disabled or false, isLocked = false,
  }
end
local unpackFn = unpack or table.unpack
ProjectEbonholdEchoJournalScroll = {
  GetScrollChild = function()
    return { GetChildren = function() return unpackFn(children) end }
  end,
}

local chunk = assert(loadfile("TomeManager.lua"))
chunk()
local TM = PP.TomeManager

print("=== Preview(bis) ===")
TM.Preview("bis")
print("\n=== Debug ===")
TM.Debug()

-- Assertions: the plan must list every enabled non-target TILE (variants are
-- separate toggles), and must never list an already-disabled or unowned tile.
local plan = assert(TM.Plan("bis"), "plan should build")
local names = {}
for _, e in ipairs(plan.disable) do names[#names + 1] = e.name end
table.sort(names)
local got = table.concat(names, "|")
local want = "Mana Infusion|Quickened Tempo|Quickened Tempo|Rocket Strike|Rocket Strike"
assert(got == want, "disable list wrong:\n  got  " .. got .. "\n  want " .. want)
assert(#plan.reenable == 0, "nothing was disabled-but-wanted")
print("\nASSERTIONS OK -- variants listed separately, disabled/unowned skipped.")
