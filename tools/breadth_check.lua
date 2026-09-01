-- BREADTH vs CONCENTRATION.
--
-- Adaptive Power pays +1% damage per UNIQUE active echo, so breadth is a real
-- damage stat, not a nice-to-have. Curating the pool trades breadth for hit
-- rate on the target list. This measures the actual trade using the live scan:
-- how big is the draw pool really, and how many uniques does a 1-80 run land?
--
-- The crux: only tome-gated echoes can be toggled. Base-pool echoes are always
-- drawable. If the base pool dominates, curation barely moves breadth and the
-- worry is theoretical; if it does not, the BiS pool is costing real damage.
--
--   node tools/run_lua.js tools/breadth_check.lua
local SV = "E:/Games/Ebonhold/WTF/Account/KEEPSY/SavedVariables/PallyPilot.lua"
local f = loadfile(SV)
if not f then print("cannot read " .. SV); return end
f()
local scan = _G.PallyPilotDB and _G.PallyPilotDB.scans and _G.PallyPilotDB.scans.tomes
if not scan or not scan.dropSources then
  print("need a scan WITH dropSources -- run /ep tomes scan then /reload")
  return
end
local ds = scan.dropSources

local PALADIN_BIT = 2                    -- Lua 5.1: no bitwise ops here
local function hasPaladin(mask)
  mask = tonumber(mask)
  if not mask then return false end
  return (mask % (PALADIN_BIT * 2)) >= PALADIN_BIT
end

local QUAL = { " %- Epic", " %- Rare", " %- Uncommon", " %- Common" }
local function base(n)
  for _, s in ipairs(QUAL) do n = string.gsub(n, s .. "$", "") end
  return string.lower((string.gsub(n, "\226\128\153", "'")))
end

-- Which groups have a drop source (i.e. are tome-gated)?
local sourced = {}
for _, line in ipairs(ds.PerkDropSourceByGroup or {}) do
  local g = tonumber(string.match(line, "^PerkDropSourceByGroup%[(%d+)%]") or "")
  if g then sourced[g] = true end
end

-- Distinct paladin-draftable echoes, split by gating.
local seen, gated, free = {}, {}, {}
for _, row in ipairs(ds.perks or {}) do
  local _, comment, group, _, mask = string.match(row, "^(%d+)\t(.-)\t(%d*)\t(%d*)\t(%d*)\t")
  local k = base(comment or "")
  if k ~= "" and hasPaladin(mask) and not seen[k] then
    seen[k] = true
    if group ~= "" and sourced[tonumber(group)] then gated[k] = true else free[k] = true end
  end
end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- Your live tome state.
local ownedOn, ownedOff = 0, 0
for _, t in ipairs(scan.tomes or {}) do
  if t.off == 1 then ownedOff = ownedOff + 1 else ownedOn = ownedOn + 1 end
end

local nFree, nGated = count(free), count(gated)
print(("paladin-draftable echoes: %d total  =  %d always-on (base pool, NOT "
  .. "toggleable)  +  %d tome-gated"):format(nFree + nGated, nFree, nGated))
print(("your tomes: %d owned, %d enabled, %d disabled"):format(
  ownedOn + ownedOff, ownedOn, ownedOff))

-- Expected distinct echoes after D draws from a pool of P, sampling with
-- replacement: P * (1 - ((P-1)/P)^D). Good enough to compare scenarios.
local function uniques(pool, draws)
  if pool <= 0 then return 0 end
  return pool * (1 - ((pool - 1) / pool) ^ draws)
end

local DRAWS = 79                          -- one echo per level, 1 -> 80
print(("\nexpected UNIQUE echoes after %d level-up draws (= Adaptive Power %%):")
  :format(DRAWS))
local scenarios = {
  { "everything enabled",      nFree + nGated },
  { "your pool now",           nFree + ownedOn },
  { "pool BEFORE you curated", nFree + ownedOn + ownedOff },
  { "keep the 6 A-tier back",  nFree + ownedOn + 6 },
  { "tome-gated only (hypothetical)", ownedOn },
}
for _, sc in ipairs(scenarios) do
  print(("  %-34s pool=%-4d  uniques=%.1f"):format(sc[1], sc[2], uniques(sc[2], DRAWS)))
end

local nowU = uniques(nFree + ownedOn, DRAWS)
local wasU = uniques(nFree + ownedOn + ownedOff, DRAWS)
print(("\ncost of curating: %.1f fewer unique echoes = %.1f%% less damage from "
  .. "Adaptive Power"):format(wasU - nowU, wasU - nowU))
print(("benefit: chance a given draw is a BiS target went from %.1f%% to %.1f%%")
  :format(100 * 23 / (nFree + ownedOn + ownedOff), 100 * 23 / (nFree + ownedOn)))
print("\n(23 = your enabled S/CORE tomes. Base-pool targets are in both figures,")
print(" so this understates the gain slightly -- the direction is what matters.)")
