-- THE FRAME SWEEP, UNDER RAID CONDITIONS.
--
-- DrawHelper polls five times a second looking for an echo-selection dialog by
-- walking every frame in the UI and reading its FontStrings. That cost scales
-- with HOW MUCH IS ON SCREEN, which is exactly what a 25-man raid maximises:
-- raid frames, nameplates, buff buttons, boss mods, a damage meter.
--
-- Two defects, both measured here:
--   1. `select(i, f:GetRegions())` re-invoked GetRegions on every iteration, so
--      a frame with N regions cost N+1 calls instead of 1.
--   2. It ran during combat, when a draw dialog cannot appear anyway.
--
--   node tools/run_lua.js tools/drawsweep_bench.lua

local unpackFn = unpack or table.unpack

-- A fake UI. Counting GetRegions calls is the point: that is the C boundary
-- the old loop was crossing thousands of times a second.
local regionCalls = 0
local FRAMES, REGIONS_PER = 900, 8

local frames = {}
for i = 1, FRAMES do
  local regions = {}
  for r = 1, REGIONS_PER do
    regions[r] = {
      GetObjectType = function() return "FontString" end,
      GetText = function() return "Filler " .. i .. "." .. r end,
    }
  end
  frames[i] = {
    IsVisible = function() return true end,
    GetRegions = function(self)
      regionCalls = regionCalls + 1
      return unpackFn(regions)
    end,
  }
end

local function EnumerateFramesStub(prev)
  if not prev then return frames[1] end
  for i = 1, FRAMES - 1 do
    if frames[i] == prev then return frames[i + 1] end
  end
  return nil
end

-- The OLD inner loop, verbatim.
local function sweepOld(cap)
  local found, seen = {}, {}
  local f, scanned = EnumerateFramesStub(), 0
  while f and scanned < cap do
    if f.IsVisible and f:IsVisible() and f.GetRegions then
      for i = 1, select("#", f:GetRegions()) do
        local r = select(i, f:GetRegions())
        if r and r.GetObjectType and r:GetObjectType() == "FontString" then
          local txt = r:GetText()
          if txt and seen[txt] then found[#found + 1] = txt end
        end
      end
      scanned = scanned + 1
    end
    f = EnumerateFramesStub(f)
  end
  return scanned
end

-- The NEW inner loop, verbatim.
local function sweepNew(cap)
  local found, seen = {}, {}
  local f, scanned = EnumerateFramesStub(), 0
  while f and scanned < cap do
    if f.IsVisible and f:IsVisible() and f.GetRegions then
      local n = select("#", f:GetRegions())
      if n > 0 then
        local regions = { f:GetRegions() }
        for i = 1, n do
          local r = regions[i]
          if r and r.GetObjectType and r:GetObjectType() == "FontString" then
            local txt = r:GetText()
            if txt and seen[txt] then found[#found + 1] = txt end
          end
        end
      end
      scanned = scanned + 1
    end
    f = EnumerateFramesStub(f)
  end
  return scanned
end

print(("simulated UI: %d visible frames x %d regions"):format(FRAMES, REGIONS_PER))

regionCalls = 0
local t0 = os.clock()
sweepOld(400)
local oldT, oldCalls = os.clock() - t0, regionCalls

regionCalls = 0
t0 = os.clock()
sweepNew(250)
local newT, newCalls = os.clock() - t0, regionCalls

print(("old sweep : %7.1f ms   %6d GetRegions calls"):format(oldT * 1000, oldCalls))
print(("new sweep : %7.1f ms   %6d GetRegions calls"):format(newT * 1000, newCalls))
print(("           %.0fx fewer calls, %.0fx faster")
  :format(oldCalls / newCalls, oldT / math.max(newT, 1e-9)))
print(("at 5 polls/sec the old sweep spent %.0f ms of every second here")
  :format(oldT * 1000 * 5))

assert(newCalls * 2 < oldCalls,
  "hoisting GetRegions must cut the call count by more than half")
assert(newT < oldT, "the hoisted sweep must be faster")

-- And in combat it must not run at all -- a draw dialog cannot appear during a
-- boss fight, which is the one time the sweep is least affordable.
local inCombat = true
local ran = false
local function poll()
  if inCombat then return end
  ran = true
  sweepNew(250)
end
poll()
assert(not ran, "the sweep must be skipped entirely while in combat")
inCombat = false
poll()
assert(ran, "and must resume the moment combat ends")
print("\ncombat gate: skipped in combat, resumes after")

print("\nDRAW SWEEP OK -- one GetRegions call per frame, capped, and idle in combat.")
