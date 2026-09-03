-- The item tooltip must say ALL of what to do to an item -- affix, gems, enchant
-- -- not just the affix. A ring with a perfect affix and an empty red socket
-- used to print nothing at all, which reads as "this item is done".
--
-- Colorblind rule: every line leads with a WORD, never colour alone.
--
--   node tools/run_lua.js tools/tooltip_advice_test.lua
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
local now = 0
function GetTime() return now end
PPScanTooltip = setmetatable({
  SetOwner = function() end, ClearLines = function() end,
  SetInventoryItem = function() end, NumLines = function() return 1 end,
}, { __index = function() return function() end end })

local EQUIPPED = {}
function GetInventoryItemLink(_, slot) return EQUIPPED[slot] and ("link" .. slot) or nil end
function GetItemInfo(link)
  local slot = tonumber(string.match(link or "", "^link(%d+)$"))
  local e = slot and EQUIPPED[slot]
  if not e then return nil end
  return e.name, link, e.quality or 4, e.ilvl or 277
end

-- Stand-in for GearOpt: the FACTS half (sockets) is class-agnostic, the ENCHANT
-- half is nil off-class. Driven per test.
local SLOTREPORT = {}
PP.GearOpt = { SlotReport = function() return SLOTREPORT end }

PP.Build = { gemRec = "Haste (Quick King's Amber)", slotTargets = {} }
for i = 1, 19 do PP.Build.slotTargets[i] = { "Ironhide", "Keen Strikes" } end

assert(loadfile("GearAudit.lua"))()
local GA = PP.GearAudit
assert(GA.TooltipLines, "GA.TooltipLines must be public")

-- Caches inside GearAudit live 10s; bump the clock between scenarios.
local function reset() now = now + 100 end
local function linesFor(name)
  reset()
  local out = {}
  for _, l in ipairs(GA.TooltipLines(name)) do out[#out + 1] = l[1] end
  return out
end
local function joined(name) return table.concat(linesFor(name), " | ") end

-- 1. THE REPORTED CASE: affix at 5/6 AND an empty red socket. Both must show.
EQUIPPED = { [11] = { name = "Juggernaut Band of Ironhide V" } }
SLOTREPORT = { [11] = { sockets = 1, emptyGems = 1, encMiss = false } }
local txt = joined("Juggernaut Band of Ironhide V")
assert(string.find(txt, "raise affix to VI", 1, true), "must still nag the affix rank: " .. txt)
assert(string.find(txt, "empty socket", 1, true), "must ALSO name the empty socket: " .. txt)
assert(string.find(txt, "Quick King's Amber", 1, true), "must say WHICH gem: " .. txt)
print("  ring 5/6 + empty socket -> " .. txt)

-- 2. A perfect affix with an empty socket must NOT be silent. This is the bug.
EQUIPPED = { [11] = { name = "Juggernaut Band of Ironhide VI" } }
SLOTREPORT = { [11] = { sockets = 1, emptyGems = 1, encMiss = false } }
txt = joined("Juggernaut Band of Ironhide VI")
assert(string.find(txt, "empty socket", 1, true),
  "a maxed affix with an empty socket must still speak, got: '" .. txt .. "'")
assert(not string.find(txt, "affix", 1, true), "must not nag an affix that is already VI")

-- 3. Enchant advice appears with its source when the table covers the slot.
EQUIPPED = { [5] = { name = "Chestplate of Ironhide VI" } }
SLOTREPORT = { [5] = { sockets = 0, emptyGems = 0, encMiss = true,
                       encRec = "Powerful Stats (+10 all stats)", src = nil,
                       encSrc = "profession enchant" } }
txt = joined("Chestplate of Ironhide VI")
assert(string.find(txt, "no enchant", 1, true), "must flag the missing enchant: " .. txt)
assert(string.find(txt, "Powerful Stats", 1, true), "must say WHICH enchant: " .. txt)
assert(string.find(txt, "profession enchant", 1, true), "must say where to get it: " .. txt)
print("  chest, no enchant -> " .. txt)

-- 4. OFF-CLASS: GearOpt returns sockets but NO encRec (its table is Ret-only).
--    The gem line must still appear; the enchant line must not -- that is the
--    whole point of splitting facts from advice.
EQUIPPED = { [5] = { name = "Robe of Ironhide VI" } }
SLOTREPORT = { [5] = { sockets = 2, emptyGems = 2, encMiss = false, encRec = nil } }
txt = joined("Robe of Ironhide VI")
assert(string.find(txt, "2 empty sockets", 1, true), "off-class must still get gem advice: " .. txt)
assert(not string.find(txt, "enchant", 1, true),
  "off-class must NOT get Retribution enchant advice: " .. txt)
print("  off-class, 2 empty sockets -> " .. txt)

-- 5. A fully kitted item says NOTHING. A tooltip that repeats "all good" on
--    every mouseover is noise, and silence has to keep meaning "done".
EQUIPPED = { [5] = { name = "Chestplate of Ironhide VI" } }
SLOTREPORT = { [5] = { sockets = 2, emptyGems = 0, encMiss = false } }
assert(#linesFor("Chestplate of Ironhide VI") == 0, "a finished item must be silent")

-- 6. Unknown / bag items and nil must not error or invent advice.
assert(#GA.TooltipLines(nil) == 0, "nil name must return no lines, not error")
assert(#linesFor("Some Random Quest Item") == 0, "an unequipped item must be silent")

-- 7. Colorblind: every line leads with a word, and carries a real colour triple
--    (colour is a redundant hint, never the only signal).
EQUIPPED = { [11] = { name = "Juggernaut Band of Ironhide V" } }
SLOTREPORT = { [11] = { sockets = 1, emptyGems = 1, encMiss = true,
                        encRec = "Assault (+40 AP)", encSrc = "Enchanting" } }
reset()
local all = GA.TooltipLines("Juggernaut Band of Ironhide V")
assert(#all >= 3, "affix + gem + enchant should all be present, got " .. #all)
for _, l in ipairs(all) do
  assert(type(l[1]) == "string" and #l[1] > 0, "every line needs text")
  assert(type(l[2]) == "number" and type(l[3]) == "number" and type(l[4]) == "number",
    "every line needs an r,g,b triple: " .. tostring(l[1]))
  assert(string.find(l[1], "%a"), "every line must carry words, not colour alone")
end

-- 8. No non-ASCII: these strings reach the 3.3.5 client font.
for _, l in ipairs(all) do
  for i = 1, #l[1] do
    assert(string.byte(l[1], i) < 127,
      "non-ASCII byte in tooltip line: " .. l[1])
  end
end
print("  all three axes at once -> " .. #all .. " lines, ASCII-clean")

print("\nTOOLTIP ADVICE OK -- affix, gems and enchant on one item; silent when done.")
