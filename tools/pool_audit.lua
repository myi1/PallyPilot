-- POOL AUDIT: did the BiS plan disable anything it should have kept?
--
-- The dangerous failure is silent: BisPlan.IsTarget() is called with the TILE's
-- name, and if that name does not match the target list byte-for-byte after
-- normalisation, the tile looks like a non-target and gets put on the DISABLE
-- list. A curly apostrophe, a "The " prefix or a stray quality suffix is enough.
--
-- So: join the real catalog (from the SavedVariables scan) against the real
-- target list (from BuildData) using the addon's own normalisation, then join
-- again with a much looser one. Anything that matches loosely but NOT strictly
-- is a wrongly-disabled echo.
--
--   node tools/run_lua.js tools/pool_audit.lua
local SV = "E:/Games/Ebonhold/WTF/Account/KEEPSY/SavedVariables/PallyPilot.lua"

PallyPilot = { Classes = {}, print = function() end }
EbonPilot = PallyPilot
local PP = PallyPilot
function UnitExists() return false end
function UnitCanAttack() return false end
function UnitDebuff() return nil end
function UnitBuff() return nil end
function UnitHealth() return 0 end
function UnitHealthMax() return 0 end
function GetTime() return 0 end
PP.RotationHelper = { TargetPct = function() return 100 end }
assert(loadfile("BuildData.lua"))()
local B = assert(PP.Classes.PALADIN, "paladin build data")

local ok = loadfile(SV)
if not ok then print("cannot read SavedVariables: " .. SV); return end
ok()
local scan = _G.PallyPilotDB and _G.PallyPilotDB.scans and _G.PallyPilotDB.scans.tomes
if not scan then print("no scans.tomes -- run /ep tomes scan then /reload"); return end

-- The addon's normalisation, reproduced exactly (TomeManager.Norm + BisPlan).
local QUAL = { " %- Epic", " %- Rare", " %- Uncommon", " %- Common" }
local function stripQ(n)
  for _, suf in ipairs(QUAL) do n = string.gsub(n, suf .. "$", "") end
  return n
end
local function strict(n)
  return string.lower(stripQ(string.gsub(n or "", "\226\128\153", "'")))
end
-- Deliberately brutal: drop every non-alphanumeric and a leading "the".
local function loose(n)
  n = string.lower(stripQ(string.gsub(n or "", "\226\128\153", "'")))
  n = string.gsub(n, "[^%w]", "")
  n = string.gsub(n, "^the", "")
  return n
end

-- Target list = locked + S tiers + catalog S (same as BisPlan.Target).
local targets, tOrder = {}, {}
local function addTarget(n)
  if not targets[strict(n)] then
    targets[strict(n)] = n
    tOrder[#tOrder + 1] = n
  end
end
for _, n in ipairs(B.locked or {}) do addTarget(n) end
for _, n in ipairs((B.tiers or {}).S or {}) do addTarget(n) end
do
  local cs = {}
  for n, t in pairs(B.catalog or {}) do if t == "S" then cs[#cs + 1] = n end end
  table.sort(cs)
  for _, n in ipairs(cs) do addTarget(n) end
end
local looseTargets = {}
for k, orig in pairs(targets) do looseTargets[loose(orig)] = orig end

print(("targets=%d   catalog tomes=%d   (scan %s)")
  :format(#tOrder, #(scan.tomes or {}), tostring(scan.when)))

-- 1. THE BUG WE ARE HUNTING: an OFF tile that loosely matches a target but was
--    not recognised strictly.
local mismatched, offTargets = {}, {}
for _, t in ipairs(scan.tomes or {}) do
  local isStrict = targets[strict(t.name)] ~= nil
  local looseHit = looseTargets[loose(t.name)]
  if isStrict then
    if t.off == 1 then offTargets[#offTargets + 1] = t.name .. " [" .. t.tier .. "]" end
  elseif looseHit then
    mismatched[#mismatched + 1] = string.format(
      "%s  (catalog)  vs  %s  (target list)%s",
      t.name, looseHit, t.off == 1 and "   *** CURRENTLY OFF ***" or "   (still on)")
  end
end

print("\n[1] Targets recognised but switched OFF -- fix by re-enabling:")
if #offTargets == 0 then print("    none") end
for _, x in ipairs(offTargets) do print("    " .. x) end

print("\n[2] NAME-MISMATCHED targets (the silent bug) -- loose match, strict miss:")
if #mismatched == 0 then
  print("    none -- every catalog name that resembles a target matched exactly")
end
for _, x in ipairs(mismatched) do print("    " .. x) end

-- 2. Sanity on the other side: tier disagreement. Anything the addon rates
--    CORE/S in the catalog scan but which is NOT on the target list means the
--    two rating paths have drifted apart.
print("\n[3] Catalog says CORE/S but not on the target list (rating drift):")
local drift = 0
for _, t in ipairs(scan.tomes or {}) do
  if (t.tier == "CORE" or t.tier == "S") and not targets[strict(t.name)] then
    drift = drift + 1
    print(("    [%s] %s%s"):format(t.tier, t.name,
      t.off == 1 and "   *** OFF ***" or ""))
  end
end
if drift == 0 then print("    none") end

-- 3. What is actually enabled, and is every enabled non-target explainable?
local on, off = 0, 0
for _, t in ipairs(scan.tomes or {}) do
  if t.off == 1 then off = off + 1 else on = on + 1 end
end
print(("\n[4] pool: %d enabled, %d disabled, %d owned"):format(on, off, on + off))

if #mismatched > 0 then
  error("\nAUDIT FAILED: " .. #mismatched .. " target(s) not matched by name.")
end
print("\nAUDIT OK -- no target was disabled through a name mismatch.")
