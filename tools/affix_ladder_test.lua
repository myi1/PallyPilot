-- ONLY DIFFERENT RANKS STACK.
--
-- Verified on the Ebonhold Discord 2026-09-04 (#players-forum, "Question about
-- affixes", posted 2026-08-28), corroborated by two people:
--
--   Rinzler: "If you stack let's say a 'Fortified by Pain V' with another one,
--   you will only get the benefits of one. 'Stacking' them efficiently would be
--   getting VI, V, IV, III, etc"
--   FernagioxXx: "Its the same for every affixes, only different tiers can stack"
--
-- Corroborated again by Rellex's 600M mage guide, which writes its affixes as
-- ranges -- "Pain 3-6", "Relentless 4-6" -- i.e. one item per rung, and says
-- "TAKE OUT A RELENTLESS STRIKE OR 2" to shed crit.
--
-- The addon used to grade each slot independently and want rank VI on all of
-- them. Under this rule that is the worst possible advice: follow it and every
-- copy past the first contributes exactly nothing. These tests exist so nobody
-- "simplifies" the ladder back into a flat VI target.
--
--   node tools/run_lua.js tools/affix_ladder_test.lua
PallyPilot = { Classes = {}, print = function() end,
               safeCall = function(fn, ...) return fn(...) end }
EbonPilot = PallyPilot
local PP = PallyPilot
PP.db = { options = {} }
local function Stub()
  local t = {}
  return setmetatable(t, { __index = function() return function() return t end end })
end
function CreateFrame() return Stub() end
-- ScanSlot reads the item's tooltip lines. Only the NAME matters here (the
-- affix is parsed out of it), so a zero-line tooltip is enough -- but NumLines
-- must return a NUMBER or the `for` loop over it blows up.
PPScanTooltip = setmetatable({ NumLines = function() return 0 end },
  { __index = function(t, k)
      if k == "NumLines" then return rawget(t, "NumLines") end
      return function() return t end
    end })
UIParent = Stub()
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function GetTime() return 0 end
function UnitClass() return "Paladin", "PALADIN" end
function UnitLevel() return 80 end

-- The equipped set under test: slot -> "Item of <Affix> <Roman>".
local EQUIPPED = {}
function GetInventoryItemLink(_, slot) return EQUIPPED[slot] and ("link" .. slot) or nil end
function GetItemInfo(link)
  local slot = tonumber(tostring(link):match("^link(%d+)$"))
  local name = slot and EQUIPPED[slot]
  if not name then return nil end
  return name, link, 4, 264      -- name, link, quality(Epic), ilvl
end

PP.GearAudit = PP.GearAudit or {}
assert(loadfile("GearAudit.lua"))()
local GA = PP.GearAudit

-- Every slot wants the same affix, so duplicates are possible and the ladder
-- is the only thing that can separate useful copies from dead ones.
PP.Build = { slotTargets = {}, bis = {}, gemRec = "x" }
for slot = 1, 19 do PP.Build.slotTargets[slot] = { "Fortified by Pain" } end

local function run(set)
  EQUIPPED = {}
  for slot, spec in pairs(set) do EQUIPPED[slot] = spec end
  GA.__cacheBust = (GA.__cacheBust or 0) + 1
  local res = GA.Compute()
  local by = {}
  for _, r in ipairs(res) do by[r.slot] = r end
  return by
end

-- 1. THE LADDER. Four items, four distinct ranks: all four count.
local by = run({
  [1] = "Helm of Fortified by Pain VI",
  [3] = "Pauldrons of Fortified by Pain V",
  [5] = "Chest of Fortified by Pain IV",
  [7] = "Legs of Fortified by Pain III",
})
for _, slot in ipairs({ 1, 3, 5, 7 }) do
  assert(by[slot], "slot " .. slot .. " must be graded")
  assert(by[slot].status ~= "dupe",
    "distinct ranks all stack; slot " .. slot .. " was called a duplicate")
end
assert(by[1].status == "ok", "rank VI with nothing above it is done, got " .. by[1].status)
print("1. VI/V/IV/III ladder -- all four count, none flagged")

-- 2. THE MISTAKE. Same affix, SAME rank, on four items: one counts, three are
--    dead weight. This is precisely what "put VI on everything" produces.
by = run({
  [1] = "Helm of Fortified by Pain VI",
  [3] = "Pauldrons of Fortified by Pain VI",
  [5] = "Chest of Fortified by Pain VI",
  [7] = "Legs of Fortified by Pain VI",
})
local dupes, keep = 0, 0
for _, slot in ipairs({ 1, 3, 5, 7 }) do
  if by[slot].status == "dupe" then dupes = dupes + 1 else keep = keep + 1 end
end
print("2. four items at VI -> " .. keep .. " counts, " .. dupes .. " dead")
assert(keep == 1, "exactly one copy of a rank may count, got " .. keep)
assert(dupes == 3, "the other three must be flagged as duplicates, got " .. dupes)

-- 3. And each dead one must be told a DIFFERENT free rung to move to -- sending
--    them all to V would just rebuild the same collision one rank down.
local targets = {}
for _, slot in ipairs({ 1, 3, 5, 7 }) do
  local r = by[slot]
  if r.status == "dupe" then
    assert(r.ladderTarget, "a duplicate must be given a target rank")
    assert(not targets[r.ladderTarget],
      "two duplicates were both sent to rank " .. tostring(r.ladderTarget))
    targets[r.ladderTarget] = true
    assert(r.ladderTarget ~= 6, "rank VI is taken; nothing may be sent there")
  end
end
print("3. duplicates routed to distinct free rungs, none back onto VI")

-- 4. A LOW rung with free room above it should climb...
by = run({
  [1] = "Helm of Fortified by Pain VI",
  [3] = "Pauldrons of Fortified by Pain II",
})
assert(by[3].status == "rank", "a low rung with room above should want raising")
assert(by[3].ladderTarget == 5,
  "it should climb to the highest FREE rung (V), got " .. tostring(by[3].ladderTarget))
print("4. a low rung climbs to the highest free rung, not to VI")

-- 5. ...but a rung with everything above it already held is DONE. Telling it to
--    "raise to VI" would only create a collision.
by = run({
  [1] = "Helm of Fortified by Pain VI",
  [3] = "Pauldrons of Fortified by Pain V",
  [5] = "Chest of Fortified by Pain IV",
})
assert(by[5].status == "ok",
  "IV under a held V and VI is finished, got " .. by[5].status)
print("5. a rung boxed in from above is finished, not 'raise to VI'")

-- 6. Different affixes never collide with each other.
by = run({
  [1] = "Helm of Fortified by Pain VI",
  [3] = "Pauldrons of Keen Strikes VI",
})
PP.Build.slotTargets[3] = { "Keen Strikes" }
by = run({
  [1] = "Helm of Fortified by Pain VI",
  [3] = "Pauldrons of Keen Strikes VI",
})
assert(by[1].status ~= "dupe" and by[3].status ~= "dupe",
  "two DIFFERENT affixes at the same rank are independent and both count")
print("6. different affixes at the same rank do not collide")

print("\nAFFIX LADDER OK -- same rank twice is dead weight; the target is a")
print("ladder of distinct ranks, never rank VI on everything.")
