-- How expensive is a MISS on the boss index?
--
-- CombatMeter runs RecordBossKill on every UNIT_DIED, which calls FindBoss.
-- In a raid that is every trash mob, add, pet and totem that dies -- dozens
-- per second on an AoE pull -- and every one of those is a MISS, so every one
-- of them falls all the way through to the substring scan.
--
--   node tools/run_lua.js tools/findboss_bench.lua
PallyPilot = {}
local PP = PallyPilot
dofile("GuideData.lua")
local G = PP.GuideData

local MISSES = {
  "Frostwing Whelp", "Nerub'ar Broodkeeper", "Servant of the Throne",
  "Ancient Skeletal Soldier", "Deathbound Ward", "Vengeful Fleshreaper",
  "Water Elemental", "Shadowfiend", "Ghoul", "Spirit Wolf",
}

local N = 20000
local function bench(fn)
  local t0 = os.clock()
  local hits = 0
  for i = 1, N do
    if fn(MISSES[(i % #MISSES) + 1]) then hits = hits + 1 end
  end
  return os.clock() - t0, hits
end

-- Warm both index builds so we time the lookup, not the one-off build.
G.FindBoss("Lord Marrowgar"); G.BossByName("Lord Marrowgar")

local slow, sHits = bench(G.FindBoss)
local fast, fHits = bench(G.BossByName)

print(("%d lookups of names that are NOT bosses"):format(N))
print(("false hits   : FindBoss %d, BossByName %d"):format(sHits, fHits))
print(("FindBoss     : %.3f s  (%.2f us each)"):format(slow, slow / N * 1e6))
print(("BossByName   : %.3f s  (%.2f us each)"):format(fast, fast / N * 1e6))
print(("speedup      : %.0fx"):format(slow / math.max(fast, 1e-9)))
assert(fast < slow / 5,
  "the combat-log path must be dramatically cheaper than the fuzzy scan")

-- A real boss name must still resolve, and a partial must still work for the
-- human-typed `/ep boss marrowgar` case the fallback exists for.
local b = G.FindBoss("Lord Marrowgar")
assert(b, "exact boss lookup must still work")
local p = G.FindBoss("marrowgar")
assert(p, "partial lookup must still work -- that is what the fallback is for")
print("\nexact + partial lookups still resolve")
