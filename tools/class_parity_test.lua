-- Offline parity test: load every class data file and assert the multi-class
-- interfaces are populated for each registered class. Run:
--   node tools/run_lua.js tools/class_parity_test.lua
-- Stubs only what the data files touch at LOAD time (they are pure tables).

PallyPilot = { Classes = {} }
EbonPilot = PallyPilot
local PP = PallyPilot

-- Minimal WoW API stub so rotation `cond` closures are genuinely exercised
-- (they legitimately call UnitExists/UnitDebuff/GetTime). "No target" state:
-- every cond must return cleanly, never error.
function UnitExists() return false end
function UnitCanAttack() return false end
function UnitDebuff() return nil end
function UnitBuff() return nil end
function UnitHealth() return 0 end
function UnitHealthMax() return 0 end
function GetTime() return 0 end
PP.RotationHelper = { TargetPct = function() return 100 end }

-- Data files are declarative; nothing below should need a real WoW API.
local function load(f)
  local chunk, err = loadfile(f)
  if not chunk then error("PARSE " .. f .. ": " .. tostring(err)) end
  local ok, e = pcall(chunk)
  if not ok then error("LOAD " .. f .. ": " .. tostring(e)) end
end

load("BuildData.lua")
load("HunterData.lua")
load("PriestData.lua")
load("MageData.lua")

local FIELDS = {
  { "statPriority", "table" }, { "bis", "table" }, { "slotTargets", "table" },
  { "gemRec", "string" }, { "tiers", "table" }, { "locked", "table" },
  { "talentTemplates", "table" }, { "defaultTemplate", "string" },
  { "rotationPriority", "table" }, { "specIndex", "number" },
}

-- Per-class exemptions for fields a class legitimately doesn't ship. EMPTY now:
-- the paladin used to be exempt for bis/slotTargets/rotationPriority because
-- those lived in the shared modules, but they were migrated into BuildData
-- (2026-08-30) and the module-side tables are deliberately empty, so all three
-- classes are symmetric. Keep this empty unless a real exemption appears --
-- every entry here is an assertion NOT being made.
local USES_MODULE_DEFAULTS = {}

local classes, fail = {}, 0
for name in pairs(PP.Classes) do classes[#classes + 1] = name end
table.sort(classes)
print("registered classes: " .. table.concat(classes, ", "))

for _, cls in ipairs(classes) do
  local B = PP.Classes[cls]
  local exempt = USES_MODULE_DEFAULTS[cls] or {}
  local missing, deferred = {}, {}
  for _, f in ipairs(FIELDS) do
    local v = B[f[1]]
    if v == nil then
      if exempt[f[1]] then deferred[#deferred + 1] = f[1]
      else missing[#missing + 1] = f[1] end
    elseif type(v) ~= f[2] then
      missing[#missing + 1] = f[1] .. "(" .. type(v) .. "~=" .. f[2] .. ")"
    end
  end
  -- bis/slotTargets must be keyed by slot with sane shapes.
  local bisN = 0
  for slot, e in pairs(B.bis or {}) do
    bisN = bisN + 1
    if type(slot) ~= "number" or type(e) ~= "table" or not e.item then
      missing[#missing + 1] = "bis[" .. tostring(slot) .. "] malformed"
    end
  end
  -- rotation conds must be callable and nil-safe with no target.
  for i, e in ipairs(B.rotationPriority or {}) do
    if not e.spell then missing[#missing + 1] = "rotationPriority[" .. i .. "].spell nil" end
    if e.cond then
      local ok = pcall(e.cond)
      if not ok then missing[#missing + 1] = "rotationPriority[" .. i .. "].cond errors" end
    end
  end
  -- talent templates must carry real target ranks.
  local tplN = 0
  for key, t in pairs(B.talentTemplates or {}) do
    tplN = tplN + 1
    if type(t.talents) ~= "table" or not next(t.talents) then
      missing[#missing + 1] = "talentTemplates." .. key .. " empty"
    end
  end
  if #missing == 0 then
    print(string.format("  OK   %-8s bis=%2d templates=%d locks=%d rotation=%d%s",
      cls, bisN, tplN, #(B.locked or {}), #(B.rotationPriority or {}),
      #deferred > 0 and ("   [module defaults: " .. table.concat(deferred, ", ") .. "]") or ""))
  else
    fail = fail + 1
    print("  FAIL " .. cls .. ": " .. table.concat(missing, ", "))
  end
end

-- Non-ASCII scan. NOTE: string.byte only ever returns 0-255, so a ">255" test
-- is a no-op -- multi-byte UTF-8 arrives as SEPARATE bytes (an em-dash is
-- 226,128,148, each < 256). Detect the high bytes themselves (>126) and report
-- the actual sequences.
--
-- WARN, not FAIL: em-dashes are already used throughout the shipped paladin data
-- and do render in this client, so failing on them would be wrong. A human
-- decides -- this just makes what's there visible instead of invisible.
local warn, seen = 0, {}
local function scan(v, path)
  if type(v) == "string" then
    local i = 1
    while i <= #v do
      local b = v:byte(i)
      if b > 126 then
        -- Capture the whole multi-byte sequence for a readable report.
        local seq, j = "", i
        while j <= #v and v:byte(j) > 126 do
          seq = seq .. string.format("\\%d", v:byte(j)); j = j + 1
        end
        if not seen[seq] then
          seen[seq] = path
          warn = warn + 1
        end
        i = j
      else
        i = i + 1
      end
    end
  elseif type(v) == "table" then
    for k, sub in pairs(v) do
      if type(sub) ~= "function" then scan(sub, path .. "." .. tostring(k)) end
    end
  end
end
for _, cls in ipairs(classes) do scan(PP.Classes[cls], cls) end

if warn > 0 then
  print("\nnon-ASCII byte sequences in class data (" .. warn .. " distinct):")
  local keys = {}
  for s in pairs(seen) do keys[#keys + 1] = s end
  table.sort(keys)
  for _, s in ipairs(keys) do print("   " .. s .. "   first seen: " .. seen[s]) end
  print("   (advisory -- verify each renders in the 3.3.5 client)")
end

print(fail == 0 and "\nPARITY OK" or ("\nFAILURES: " .. fail))
