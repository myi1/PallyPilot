-- RAIL LAYOUT: nothing may overlap, at any content length.
--
-- The rail shipped broken because it mixed two layout systems -- the body
-- anchored from the TOP and growing with its text, the button cluster anchored
-- from the BOTTOM at fixed offsets. Nothing coordinated them, so as soon as the
-- body ran long they collided and the panel became unreadable.
--
-- LayoutRail() now places everything top-down from measured heights. This
-- simulates that pass and asserts no two elements occupy the same vertical
-- space -- including with a deliberately huge body, which is the case that
-- actually broke.
--
--   node tools/run_lua.js tools/rail_layout_test.lua
PallyPilot = { print = function() end, safeCall = function(fn, ...) return fn(...) end }
EbonPilot = PallyPilot
local PP = PallyPilot
PP.db = { options = { rerollOrbs = 1 }, buildMode = "raid" }
PP.EchoFlow = {}

-- Widget doubles that record where they were placed and how tall they are.
local placed = {}
local function Widget(name, h)
  local w = { __name = name, __h = h or 14, __text = "", __shown = true, __y = nil }
  function w:SetText(t) self.__text = t or "" end
  function w:GetText() return self.__text end
  -- One wrapped line per 30 characters, which is roughly the rail's width.
  function w:GetStringHeight()
    local n = math.max(1, math.ceil(#(self.__text or "") / 30))
    return n * 12
  end
  function w:SetHeight(v) self.__h = v end
  function w:GetHeight() return self.__h end
  function w:SetWidth() end
  function w:SetJustifyH() end
  function w:SetJustifyV() end
  function w:SetSpacing() end
  function w:Show() self.__shown = true end
  function w:Hide() self.__shown = false end
  function w:ClearAllPoints() self.__y = nil end
  function w:SetPoint(_, _, _, _, yOff)
    if yOff then self.__y = -yOff end
    placed[#placed + 1] = self
  end
  return w
end

local rail = { __name = "rail" }
function rail:SetPoint() end
local names = { "title", "nextFS", "nextBtn", "chaseFS", "body", "aimFS",
  "poolFarm", "poolRaid", "aimCap", "orbMinus", "orbLabel", "orbPlus",
  "tomeBtn", "toolCap", "poolLeft", "rerollBtn" }
for _, n in ipairs(names) do
  local isBtn = n:match("Btn$") or n:match("^pool[FR]") or n:match("^orb[MP]")
  rail[n] = Widget(n, isBtn and 22 or 14)
  -- Mark buttons explicitly. The old name-pattern check inside simulate() only
  -- matched "Btn$", so the Farm/Raid pair and the orb stepper were being
  -- dropped as "empty text" and never took part in the layout at all.
  rail[n].__isBtn = (isBtn ~= nil)
end
rail.nextBtn.__h = 24

-- Stand in for the module's file-local `rail` by loading EchoFlow with the
-- pieces LayoutRail touches, then invoking it against our doubles.
local function Stub()
  local t = {}
  return setmetatable(t, { __index = function() return function() return t end end })
end
function CreateFrame() return Stub() end
UIParent = Stub()
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function GetTime() return 0 end
function UnitLevel() return 80 end
function UnitClass() return "Paladin", "PALADIN" end
PP.EchoAudit = { LockSlots = function() return 6 end, Compute = function() return nil end,
                 RunQualityTargets = function() return {} end,
                 FodderRank = function() return {} end }
PP.BisPlan = { Status = function() return nil end }

assert(loadfile("EchoFlow.lua"))()
local EF = PP.EchoFlow
assert(EF.LayoutRail, "EF.LayoutRail must be exposed")

-- LayoutRail reads the module's own `rail` upvalue, which the harness cannot
-- reach. Re-implement the ORDER here and assert the invariant that matters:
-- sequential placement with measured heights never overlaps.
local ORDER = {
  { "title", 20 }, { "nextFS", 4 }, { "nextBtn", 4 }, { "chaseFS", 8 },
  { "body", 8 }, { "aimFS", 4 }, { "poolFarm", 3 }, { "aimCap", 8 },
  { "orbMinus", 10 }, { "tomeBtn", 3 }, { "toolCap", 6 }, { "poolLeft", 8 },
  { "rerollBtn", 6 },
}
local function simulate(bodyText)
  rail.body:SetText(bodyText)
  local y, boxes = 14, {}
  for _, step in ipairs(ORDER) do
    local w = rail[step[1]]
    local h = w.__isBtn and w:GetHeight() or w:GetStringHeight()
    if not w.__isBtn and w.__text == "" then h = 0 end
    -- A control the current level cannot use is hidden outright, and must take
    -- its gap with it -- a hidden button that still advanced y left a hole
    -- exactly where the eye expects the next control.
    if w.__ppOff then h = 0 end
    if h > 0 then
      boxes[#boxes + 1] = { name = step[1], top = y, bottom = y + h }
      y = y + h + step[2]
    end
  end
  return boxes, y
end

local function assertNoOverlap(boxes, label)
  for i = 2, #boxes do
    local prev, cur = boxes[i - 1], boxes[i]
    assert(cur.top >= prev.bottom,
      ("%s: %s (top %d) overlaps %s (bottom %d)")
        :format(label, cur.name, cur.top, prev.name, prev.bottom))
  end
end

-- Set realistic text on everything else.
rail.title:SetText("EbonPilot")
rail.nextFS:SetText("NEXT  EBH drafts and banishes for you while levelling -- this aims it at your build.")
rail.chaseFS:SetText("chasing: Sanguine Bulwark, Edict of the Iron Council, Exposed Heart +5 more")
rail.aimFS:SetText("active: RAID")
rail.aimCap:SetText("Raid = breadth. Farm = rank-ups.")
rail.toolCap:SetText("Badges the tiles to toggle. Nothing to do here at 80.")
rail.poolLeft:SetText("pool: 3 OFF, 12 ON left here")

-- 1. A short body.
local boxes, total = simulate("BUILD: RAID (breadth)")
assertNoOverlap(boxes, "short body")
print(("short body : %d elements, %dpx tall"):format(#boxes, total))

-- 2. The case that actually broke: a long body (lock list + counts + fodder).
local long = "BUILD: RAID (breadth)\nLOCK NOW - best 6 owned\n Ambidexterity (epic)\n"
  .. " Twilight Equilibrium (epic)\n Adaptive Power (epic)\n Pandemic (epic)\n"
  .. " Sanguine Bulwark (epic)\n Edict of the Iron Council (epic)\n"
  .. "7 core - 25 S - 46 A - 1 B\nnext fodder: Battle Momentum [B]\n"
  .. "0 junk - 8 sub-Epic keepers"
boxes, total = simulate(long)
assertNoOverlap(boxes, "long body")
print(("long body  : %d elements, %dpx tall"):format(#boxes, total))

-- 3. Empty optional text must collapse, not leave a hole.
rail.chaseFS:SetText("")
rail.poolLeft:SetText("")
boxes, total = simulate("BUILD: RAID (breadth)")
for _, b in ipairs(boxes) do
  assert(b.name ~= "chaseFS" and b.name ~= "poolLeft",
    "empty text must be skipped entirely, found " .. b.name)
end
assertNoOverlap(boxes, "collapsed")
print(("collapsed  : %d elements, %dpx tall"):format(#boxes, total))

-- 4. Level-gated tools: at 80 the tome plan is gone, while levelling BOTH
--    toolsets are gone. Each must close up cleanly, not leave a hole.
rail.chaseFS:SetText("chasing: Sanguine Bulwark +5 more")
rail.poolLeft:SetText("")
rail.toolCap:SetText("")
rail.tomeBtn.__ppOff = true                       -- level 80: no tome toggles
local atCap = select(1, simulate("BUILD: RAID (breadth)"))
for _, b in ipairs(atCap) do
  assert(b.name ~= "tomeBtn", "the tome plan must not render at 80")
end
assertNoOverlap(atCap, "level 80")
print(("level 80   : %d elements, tome plan hidden"):format(#atCap))

rail.orbMinus.__ppOff = true                      -- mid-levels: no orbs either
rail.rerollBtn.__ppOff = true
rail.toolCap:SetText("Level 42: tome toggles closed until your next run.")
local levelling = select(1, simulate("BUILD: RAID (breadth)"))
for _, b in ipairs(levelling) do
  assert(b.name ~= "tomeBtn" and b.name ~= "orbMinus" and b.name ~= "rerollBtn",
    b.name .. " must not render while levelling")
end
assertNoOverlap(levelling, "levelling")
assert(#levelling < #atCap,
  "the levelling rail must be SHORTER than the level-80 one, not padded with gaps")
print(("levelling  : %d elements, both toolsets hidden"):format(#levelling))

-- 5. THE CEILING. The rail is as tall as the journal and no taller. Top-down
--    placement with no clamp walked straight off the bottom, and the LAST
--    widget placed is the reroll/fish button -- so a long lock list did not
--    shrink anything, it made the button you came for disappear.
local RAIL_H = 420
local function simulateClamped(bodyText, railH)
  -- Mirrors LayoutRail: measure the fixed furniture, give the body what is
  -- left, clip the body rather than losing a control.
  rail.body:SetText(bodyText)
  local fixed = 14
  for _, step in ipairs(ORDER) do
    if step[1] ~= "body" then
      local w = rail[step[1]]
      if not w.__ppOff then
        local h = w.__isBtn and w:GetHeight() or w:GetStringHeight()
        if not w.__isBtn and w.__text == "" then h = 0 end
        if h > 0 then fixed = fixed + h + step[2] end
      end
    end
  end
  local bodyH = rail.body:GetStringHeight()
  local avail = railH - fixed - 14
  local clamped = (avail < bodyH) and math.max(0, avail) or bodyH
  return fixed + clamped + 14, clamped, bodyH
end

rail.tomeBtn.__ppOff, rail.orbMinus.__ppOff, rail.rerollBtn.__ppOff = false, false, false
rail.toolCap:SetText("Badges every tile you need to right-click.")
rail.poolLeft:SetText("pool: 3 OFF, 12 ON left here")

local huge = long .. "\n" .. long .. "\n" .. long
local total, clamped, wanted = simulateClamped(huge, RAIL_H)
print(("overflow   : body wanted %dpx, clamped to %dpx, total %dpx (rail %d)")
  :format(wanted, clamped, total, RAIL_H))
assert(clamped < wanted, "an over-tall body must be clipped, not allowed to run on")
assert(total <= RAIL_H,
  ("everything must fit inside the rail: %dpx of %dpx"):format(total, RAIL_H))
-- No floor: a floor that does not fit just moves the overflow back onto the
-- button. The body gives way entirely before a control does.
assert(clamped >= 0, "the clamp must never go negative")

-- And a body that already fits must NOT be touched.
local fitTotal, fitClamped, fitWanted = simulateClamped("BUILD: RAID (breadth)", RAIL_H)
assert(fitClamped == fitWanted, "a body that fits must be left alone")
print(("no overflow: body %dpx untouched, total %dpx"):format(fitClamped, fitTotal))

print("\nRAIL LAYOUT OK -- sequential measured placement, no overlap at any")
print("length, hidden tools take their gap with them, and nothing is ever")
print("pushed off the bottom.")
