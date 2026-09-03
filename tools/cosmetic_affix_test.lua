-- Shirt (slot 4) and Tabard (slot 19) on Ebonhold: an EPIC one DOES take an
-- affix, so the gear advisor must grade it. It used to skip both slots outright
-- -- correct for a plain shirt (it stopped red "no affix" dots on a tabard), but
-- it silently hid a real, free affix slot on an Epic one. The gate is now the
-- item's QUALITY, not the slot number.
--
--   node tools/run_lua.js tools/cosmetic_affix_test.lua
PallyPilot = { print = function() end, safeCall = function(fn, ...) return fn(...) end }
EbonPilot = PallyPilot
local PP = PallyPilot
PP.GearAudit = {}
PP.db = { options = {} }

local function Stub()
  local t = {}
  return setmetatable(t, { __index = function() return function() return t end end })
end
function CreateFrame() return Stub() end
UIParent = Stub()
-- Real tooltip stub: NumLines MUST return a number or GearAudit's `for i = 2,
-- tip:NumLines()` blows up. 1 = no body lines, so affixes come from the NAME,
-- which is how Ebonhold encodes them ("... of <Affix> <Roman>").
PPScanTooltip = setmetatable({
  SetOwner = function() end, ClearLines = function() end,
  SetInventoryItem = function() end, NumLines = function() return 1 end,
}, { __index = function() return function() end end })

-- The equipped set under test: slot -> {name, quality, ilvl}.
-- Quality: 0 Poor .. 3 Rare, 4 Epic, 5 Legendary.
local EQUIPPED = {}
function GetInventoryItemLink(_, slot) return EQUIPPED[slot] and ("link" .. slot) or nil end
function GetItemInfo(link)
  local slot = tonumber(string.match(link or "", "^link(%d+)$"))
  local e = slot and EQUIPPED[slot]
  if not e then return nil end
  return e.name, link, e.quality, e.ilvl      -- 3rd = quality, 4th = ilvl in 3.3.5
end

-- Minimal class data: every slot wants the same affix list, Ironhide first.
local common = { "Ironhide", "Keen Strikes", "Thick Hide" }
PP.Build = { slotTargets = {} }
for i = 1, 19 do PP.Build.slotTargets[i] = common end

assert(loadfile("GearAudit.lua"))()
local GA = PP.GearAudit
assert(GA.Compute, "GA.Compute must exist")

local function bySlot()
  local out = {}
  for _, r in ipairs(GA.Compute()) do out[r.slot] = r end
  return out
end

-- 1. A PLAIN shirt/tabard is still skipped. This is the original bug and it must
--    not come back: no red "put an affix on your tabard" verdict.
EQUIPPED = {
  [4]  = { name = "White Linen Shirt", quality = 1, ilvl = 1 },
  [19] = { name = "Tabard of the Argent Crusade", quality = 3, ilvl = 1 },
  [5]  = { name = "Breastplate of Ancient Evil of Ironhide VI", quality = 4, ilvl = 277 },
}
local r = bySlot()
assert(r[4] == nil, "a common shirt must NOT be graded")
assert(r[19] == nil, "a rare tabard must NOT be graded")
assert(r[5] and r[5].status == "ok", "a normal slot must still be graded")
print("  plain shirt/tabard: skipped (no phantom 'missing affix')")

-- 2. An EPIC shirt with no affix is a REAL gap -- this is the case that was
--    invisible before. Yahya's Epic Purple Shirt, exactly.
EQUIPPED = { [4] = { name = "Epic Purple Shirt", quality = 4, ilvl = 1 } }
r = bySlot()
assert(r[4], "an EPIC shirt must be graded")
assert(r[4].status == "missing", "bare Epic shirt must report a missing affix, got "
  .. tostring(r[4].status))
assert(r[4].want == "Ironhide", "must name the affix to chase")
print("  epic shirt, no affix: FIX -- missing, wants " .. r[4].want)

-- 3. An Epic shirt WITH the right affix at max rank is done, not nagged.
EQUIPPED = { [4] = { name = "Epic Purple Shirt of Ironhide VI", quality = 4, ilvl = 1 } }
r = bySlot()
assert(r[4].status == "ok", "right affix at VI must be ok, got " .. tostring(r[4].status))
assert(r[4].rank == 6, "rank must parse from the roman numeral")

-- 4. Under-ranked and wrong affixes are distinguished, same as any other slot.
EQUIPPED = { [4] = { name = "Epic Purple Shirt of Ironhide III", quality = 4, ilvl = 1 } }
assert(bySlot()[4].status == "rank", "under-rank must report 'rank', not 'ok'")
EQUIPPED = { [4] = { name = "Epic Purple Shirt of Spirit Surge IV", quality = 4, ilvl = 1 } }
assert(bySlot()[4].status == "swap", "off-list affix must report 'swap'")
print("  epic shirt rank/swap verdicts: correct")

-- 5. An Epic TABARD is graded too -- same rule, no special-casing.
EQUIPPED = { [19] = { name = "Tabard of Flame", quality = 4, ilvl = 1 } }
assert(bySlot()[19], "an EPIC tabard must be graded")

-- 6. Legendary (quality 5) is above Epic and must also qualify -- a `== 4` test
--    instead of `>= 4` would silently drop it.
EQUIPPED = { [4] = { name = "Shirt of the Phoenix", quality = 5, ilvl = 1 } }
assert(bySlot()[4], "a legendary shirt must be graded (>= Epic, not == Epic)")

-- 7. A missing quality must not crash or silently grade -- an unloaded
--    GetItemInfo returns nil for everything on first call in a real client.
EQUIPPED = { [4] = { name = "Mystery Shirt", quality = nil, ilvl = 1 } }
assert(bySlot()[4] == nil, "unknown quality must be treated as not-Epic, not graded")

-- 8. An empty cosmetic slot is simply absent -- no nil-index error.
EQUIPPED = { [5] = { name = "Plain Chest", quality = 4, ilvl = 200 } }
r = bySlot()
assert(r[4] == nil and r[19] == nil, "empty shirt/tabard slots must produce no rows")
assert(r[5] and r[5].status == "missing", "affixless chest is still a gap")

print("\nCOSMETIC AFFIX OK -- Epic shirts/tabards are graded, plain ones are not.")
