-- Orbs-per-roll: the rail's -/+ walk a ladder instead of stepping by 1, because
-- the quality boost scales with orbs spent (~100 orbs ~= ~100% higher) and the
-- rail's own NEXT line tells you to "crank orbs/reroll up first". Stepping by one
-- meant ~99 clicks to reach a roll worth making.
--
--   node tools/run_lua.js tools/orb_ladder_test.lua
PallyPilot = { print = function() end, safeCall = function(fn, ...) return fn(...) end }
EbonPilot = PallyPilot
local PP = PallyPilot
PP.db = { options = { rerollOrbs = 1 }, buildMode = "raid" }
PP.EchoFlow = {}

local function Stub()
  local t = {}
  return setmetatable(t, { __index = function() return function() return t end end })
end
function CreateFrame() return Stub() end
UIParent = Stub()
function GetTime() return 0 end
function UnitClass() return "Paladin", "PALADIN" end
function UnitLevel() return 80 end
PP.EchoAudit = { LockSlots = function() return 6 end, Compute = function() return nil end,
  RunQualityTargets = function() return {} end, FodderRank = function() return {} end }
PP.BisPlan = { Status = function() return { counts = {} } end }

assert(loadfile("EchoFlow.lua"))()
local EF = PP.EchoFlow
assert(EF.StepOrbs, "EF.StepOrbs must be public so the ladder is testable without the rail")
assert(EF.SetOrbs, "EF.SetOrbs must be public for /ep orbs")

local function set(n) PP.db.options.rerollOrbs = n end
local function up(toEnd) return EF.StepOrbs(1, toEnd) end
local function down(toEnd) return EF.StepOrbs(-1, toEnd) end

-- 1. Walking up from the floor reaches 100 in a handful of clicks. The whole
--    point: 1 -> 100 must not take ~99 presses.
set(1)
local clicks, seen = 0, { 1 }
while (PP.db.options.rerollOrbs or 1) < 100 and clicks < 50 do
  clicks = clicks + 1
  seen[#seen + 1] = up(false)
end
assert(PP.db.options.rerollOrbs == 100, "must reach 100, got " .. tostring(PP.db.options.rerollOrbs))
assert(clicks <= 6, "1 -> 100 must take <= 6 clicks, took " .. clicks)
print("  ladder up: " .. table.concat(seen, " -> ") .. "  (" .. clicks .. " clicks)")

-- 2. Both ends are stable -- clicking past them must not wrap or go out of range.
set(100); assert(up(false) == 100, "must clamp at the top, not wrap")
set(1);   assert(down(false) == 1, "must clamp at the bottom, not wrap")

-- 3. Shift jumps straight to an end.
set(25); assert(up(true) == 100, "shift-up must jump to 100")
set(25); assert(down(true) == 1, "shift-down must jump to 1")

-- 4. Stepping from an OFF-ladder value (typed via /ep orbs 37) must move to the
--    neighbouring rung, NOT snap to the floor. This is the case a naive
--    "find exact index then +1" implementation gets wrong.
set(37); assert(up(false) == 50, "37 should step up to 50, got " .. PP.db.options.rerollOrbs)
set(37); assert(down(false) == 25, "37 should step down to 25, got " .. PP.db.options.rerollOrbs)
set(3);  assert(down(false) == 1, "3 should step down to 1")
set(99); assert(up(false) == 100, "99 should step up to 100")

-- 5. SetOrbs clamps into 1..100 and rejects non-numbers rather than writing junk
--    into SavedVariables (a nil/NaN here would break every later reroll line).
assert(EF.SetOrbs(37) == 37, "exact value must be kept")
assert(EF.SetOrbs(0) == 1, "0 must clamp to 1")
assert(EF.SetOrbs(-5) == 1, "negative must clamp to 1")
assert(EF.SetOrbs(9999) == 100, "over-max must clamp to 100")
assert(EF.SetOrbs(12.7) == 12, "fractional must floor (string.format %d errors on a float)")
assert(EF.SetOrbs("50") == 50, "numeric string from a slash arg must work")
assert(EF.SetOrbs("abc") == nil, "non-numeric must return nil so the caller can report it")
assert(EF.SetOrbs(nil) == nil, "nil must return nil, not error")
-- A rejected value must leave the setting untouched.
EF.SetOrbs(42); EF.SetOrbs("nonsense")
assert(PP.db.options.rerollOrbs == 42, "a rejected value must not clobber the setting")

-- 6. The value stays an integer in range no matter how it was reached -- every
--    reroll line formats it, and a float would error under string.format("%d").
for _, v in ipairs({ 1, 5, 10, 25, 50, 75, 100 }) do
  assert(EF.SetOrbs(v) == v, "ladder rung " .. v .. " must be settable exactly")
  assert(math.floor(v) == v, "rung must be an integer")
end

print("\nORB LADDER OK -- 1 to 100 in " .. clicks .. " clicks, ends clamp, "
  .. "off-ladder values step to a neighbour, /ep orbs clamps and rejects junk.")
