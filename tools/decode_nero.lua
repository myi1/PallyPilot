-- Decode Nero's published paladin loadout (EBH1 string from his Google doc,
-- linked in the #paladin forum) against the client's own PerkDatabase dump, and
-- diff it against our build data.
--
-- Why this matters: our target list is 43 names derived from tier letters we
-- assigned. Nero's is 85 echoes he actually plays at HC4/HC5. Where they
-- disagree, one of us is wrong, and it is worth knowing which names those are
-- before rerolling an entire run toward the wrong list.
--
--   node tools/run_lua.js tools/decode_nero.lua
-- Nero's published paladin loadout, verbatim from his Google doc (linked from
-- the "Pala (+Dk) - Nero" thread in #paladin), read 2026-09-01.
local NERO_PALADIN = "EBH1:200020.1.1,200050.2.1,200063.2.1,200227.2.1,"
  .. "200228.3.1,200230.3.1,200232.3.1,200236.3.1,200237.3.1,200240.3.1,"
  .. "200492.2.1,200494.2.1,200496.2.1,200500.2.1,200501.2.1,200507.2.1,"
  .. "200523.2.1,200538.2.1,200539.2.1,200583.3.1,200585.3.1,200592.3.1,"
  .. "200595.3.1,200597.3.1,200599.3.1,200606.3.1,200621.3.1,200627.3.1,"
  .. "200635.3.1,200672.1.1,200677.2.1,200684.2.1,200687.2.1,200693.3.1,"
  .. "200701.2.1,200720.1.1,200722.2.1,200726.2.1,200730.2.1,200738.2.1,"
  .. "200752.3.1,200780.3.1,200792.3.1,200798.3.1,200822.3.1,200826.3.1,"
  .. "200830.3.1,200834.3.1,200844.3.1,200852.2.1,200866.2.1,200882.2.1,"
  .. "200886.2.1,200888.2.1,200894.2.1,200896.2.1,200898.2.1,200900.2.1,"
  .. "200958.3.1,200960.3.1,200962.3.1,201150.2.1,201250.2.1,201254.3.1,"
  .. "201258.3.1,201262.3.1,201272.3.1,201298.3.1,201304.3.1,201308.3.1,"
  .. "201312.3.1,201324.3.1,201336.3.1,201340.3.1,201354.3.1,201356.3.1,"
  .. "201360.3.1,201366.3.1,201398.3.1,201406.3.1,201410.3.1,201416.3.1,"
  .. "201420.3.1,201424.3.1,201428.3.1"
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
local B = assert(PP.Classes.PALADIN)

local raw = string.gsub(NERO_PALADIN, "%s", "")

assert(loadfile(SV))()
local scan = _G.PallyPilotDB.scans.tomes
local ds = assert(scan.dropSources, "scan needs dropSources")

-- spellId -> name / quality / group, from the client's own database.
local nameOf, groupOf, srcGroup = {}, {}, {}
for _, row in ipairs(ds.perks or {}) do
  local id, comment, group = string.match(row, "^(%d+)\t(.-)\t(%d*)\t")
  if id then
    nameOf[tonumber(id)] = comment
    groupOf[tonumber(id)] = tonumber(group)
  end
end
for _, line in ipairs(ds.PerkDropSourceByGroup or {}) do
  local g = tonumber(string.match(line, "^PerkDropSourceByGroup%[(%d+)%]") or "")
  local txt = string.match(line, "%] = (.-)%s+%(string%)$")
  if g then srcGroup[g] = txt end
end

local QUAL = { " %- Epic", " %- Rare", " %- Uncommon", " %- Common" }
local function baseName(n)
  for _, s in ipairs(QUAL) do n = string.gsub(n or "", s .. "$", "") end
  return n or ""
end
local function key(n)
  return string.lower((string.gsub(baseName(n), "\226\128\153", "'")))
end

-- Parse EBH1:<id>.<quality>.<stacks>,...
local body = string.match(raw, "^EBH1:(.*)$") or raw
local nero, neroOrder, unknown = {}, {}, 0
for entry in string.gmatch(body, "[^,]+") do
  local id, q = string.match(entry, "^(%d+)%.(%d+)")
  id = tonumber(id)
  if id then
    local nm = nameOf[id]
    if nm then
      local k = key(nm)
      if not nero[k] then
        nero[k] = { name = baseName(nm), q = tonumber(q), id = id }
        neroOrder[#neroOrder + 1] = k
      end
    else
      unknown = unknown + 1
    end
  end
end
print(("Nero's paladin loadout: %d entries -> %d distinct echoes (%d ids not in "
  .. "PerkDatabase)"):format(select(2, string.gsub(body, ",", ",")) + 1,
  #neroOrder, unknown))

-- Our target list.
local targets, tOrder = {}, {}
local function addT(n, role)
  local k = key(n)
  if not targets[k] then targets[k] = role; tOrder[#tOrder + 1] = n end
end
for _, n in ipairs(B.locked or {}) do addT(n, "CORE") end
for _, n in ipairs((B.tiers or {}).S or {}) do addT(n, "S") end
do
  local cs = {}
  for n, t in pairs(B.catalog or {}) do if t == "S" then cs[#cs + 1] = n end end
  table.sort(cs)
  for _, n in ipairs(cs) do addT(n, "S") end
end

local function ourTier(n)
  local k = key(n)
  for name, t in pairs(B.catalog or {}) do if key(name) == k then return t end end
  for _, tier in ipairs({ "S", "A", "B", "C" }) do
    for _, name in ipairs((B.tiers or {})[tier] or {}) do
      if key(name) == k then return tier end
    end
  end
  return "-"
end

-- Your live tome state.
local owned, off = {}, {}
for _, t in ipairs(scan.tomes or {}) do
  owned[key(t.name)] = true
  if t.off == 1 then off[key(t.name)] = true end
end

print("\n=== [1] NERO RUNS IT, WE DO NOT TARGET IT ===")
print("(candidates to promote; 'OFF' means you have the tome but disabled it)")
table.sort(neroOrder)
local promote = 0
for _, k in ipairs(neroOrder) do
  if not targets[k] then
    promote = promote + 1
    local e = nero[k]
    local g = groupOf[e.id]
    print(("  %-30s ourTier=%-6s tome=%-9s %s"):format(e.name, ourTier(e.name),
      owned[k] and (off[k] and "OWNED-OFF" or "OWNED-ON") or "not owned",
      (g and srcGroup[g]) and "" or "(base pool)"))
  end
end
print("  total: " .. promote)

print("\n=== [2] WE TARGET IT, NERO DOES NOT RUN IT ===")
print("(candidates to demote from CHASE to KEEP)")
local demote = 0
for _, n in ipairs(tOrder) do
  if not nero[key(n)] then
    demote = demote + 1
    print(("  %-30s role=%s"):format(n, targets[key(n)]))
  end
end
print("  total: " .. demote)

print("\n=== [3] AGREEMENT (both lists) ===")
local agree = 0
for _, n in ipairs(tOrder) do if nero[key(n)] then agree = agree + 1 end end
print(("  %d of our %d targets are in Nero's %d-echo build"):format(
  agree, #tOrder, #neroOrder))

print("\n=== [4] OWNED BUT DISABLED, AND NERO RUNS IT ===")
print("(the actionable set: tomes you already have, switched off, that a")
print(" proven HC4/HC5 paladin actually plays)")
local reenable = {}
for _, k in ipairs(neroOrder) do
  if owned[k] and off[k] then reenable[#reenable + 1] = nero[k].name end
end
table.sort(reenable)
for i, n in ipairs(reenable) do print(("  %2d. %s"):format(i, n)) end
print("  total: " .. #reenable)

print("\n=== [5] LUA SOURCE: Nero's build for BuildData ===")
local out, line = {}, "  "
local names = {}
for _, k in ipairs(neroOrder) do names[#names + 1] = nero[k].name end
table.sort(names)
for _, n in ipairs(names) do
  -- straighten the curly apostrophe so BuildData stays ASCII; Norm() matches
  local safe = string.gsub(n, "\226\128\153", "'")
  local piece = string.format('%q, ', safe)
  if #line + #piece > 76 then out[#out + 1] = line; line = "  " end
  line = line .. piece
end
if line ~= "  " then out[#out + 1] = line end
for _, l in ipairs(out) do print(l) end
