-- SHARING THE BUILD YOU ARE ACTUALLY RUNNING.
--
-- /ep buildcode exports the class's CURATED build -- the same string for
-- everyone playing that class. That is not what people mean when they ask how
-- to share a build, and answering with it is misleading. /ep buildcode run
-- reads the live run instead.
--
-- The format is EbonholdHub's own: EBH1:<spellId>.<code>.<stack>,...:<CLASS>:<Title>
-- with code 1=B, 2=A, 3=S, and spell ids >= 200000 that resolve in the
-- server's PerkDatabase.
--
--   node tools/run_lua.js tools/runexport_test.lua
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
UIParent = Stub()
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function GetTime() return 0 end
function UnitLevel() return 80 end
function UnitClass() return "Paladin", "PALADIN" end
PP.class = "PALADIN"

assert(loadfile("BuildData.lua"))()
PP.Build = PP.Classes.PALADIN

-- The server's echo database. Quality suffixes on the comment are what the
-- live client actually ships, and the exporter has to see through them.
ProjectEbonhold = {
  PerkDatabase = {
    [200001] = { comment = "Twilight Equilibrium", quality = 3 },
    [200002] = { comment = "Ambidexterity", quality = 3 },
    [200003] = { comment = "Mind Expansion", quality = 1 },
    [200004] = { comment = "Pandemic - Epic", quality = 3 },
    -- Below the 200000 floor: must never appear in a string.
    [1234]   = { comment = "Bogus Low Id", quality = 3 },
  },
}

-- CollectOwnedSets keys are lowercased and CARRY QUALITY SUFFIXES. That
-- mismatch against the bare-name id lookup is exactly what would silently drop
-- echoes from the string, so it is the important case here.
local owned = {
  ["twilight equilibrium"] = true,
  ["ambidexterity - epic"] = true,
  ["mind expansion"] = true,
  ["pandemic - epic"] = true,
  ["bogus low id"] = true,
  ["something not in the database"] = true,
}
EbonholdHub = { EchoOwnership = { CollectOwnedSets = function() return owned end } }

PP.EchoAudit = { ClassifyName = function(n)
  if n == "twilight equilibrium" then return "CORE" end
  if n == "ambidexterity" then return "S" end
  if n == "mind expansion" then return "C" end   -- unrated for export purposes
  return "A"
end }

-- Core.lua normally creates the namespaces; the module is loaded alone here.
PP.HubSync = PP.HubSync or {}
assert(loadfile("HubSync.lua"))()
local HS = PP.HubSync
assert(HS.ExportRunString, "HS.ExportRunString must exist")

local str, err, n, missing = HS.ExportRunString()
assert(str, "export failed: " .. tostring(err))
print("string : " .. str)
print(("echoes : %d resolved, %d unresolved"):format(n, missing))

-- 1. Shape.
assert(string.find(str, "^EBH1:"), "must start with the EBH1 magic")
local body, class, title = string.match(str, "^EBH1:(.-):(%u+):(.+)$")
assert(body and class and title, "must have body:CLASS:Title -- got " .. str)
assert(class == "PALADIN", "class segment wrong: " .. class)
print("shape  : body / " .. class .. " / " .. title)

-- 2. Quality-suffixed run keys must still resolve. "ambidexterity - epic" and
--    "pandemic - epic" are in the run; if the suffix is not stripped before the
--    id lookup they vanish from the string without a word.
assert(string.find(body, "200002%.", 1), "Ambidexterity (suffixed key) must resolve")
assert(string.find(body, "200004%.", 1), "Pandemic (suffixed key) must resolve")
print("suffix : quality-suffixed run keys resolved")

-- 3. Ids below the server's 200000 floor are not real perks.
assert(not string.find(body, "1234%.", 1), "sub-200000 ids must never ship")
print("floor  : sub-200000 id excluded")

-- 4. An echo the database cannot resolve is COUNTED, not silently dropped --
--    the caller reports it so you know the string is incomplete.
assert(missing >= 1, "an unresolvable echo must be counted as missing")
print("missing: unresolved echoes are reported, not hidden")

-- 5. Tier codes: S ships as 3, and an unrated echo ships as B (1) rather than
--    being dropped -- it IS in the build, and omitting it misrepresents it.
assert(string.find(body, "200002%.3%.", 1), "an S echo must ship with code 3")
-- CORE is our top rating but the wire format has no code for it, so it must be
-- mapped to S. Left to the default it shipped as B and the receiving auto-pick
-- ranked the build-defining echoes below every A.
assert(string.find(body, "200001%.3%.", 1),
  "a CORE echo must ship as S (3), not fall through to B: " .. body)
assert(string.find(body, "200003%.1%.", 1), "an unrated echo must ship as B (1)")
print("tiers  : S=3, unrated=B")

-- 6. It must differ from the curated export -- that is the entire point.
local curated = HS.ExportString()
if curated then
  assert(curated ~= str,
    "the run export must not be identical to the curated one:\n" .. curated)
  print("differs: run string is not the curated string")
end

-- 7. No run, no string -- and an error that names the cause.
EbonholdHub = nil
local bad, why = HS.ExportRunString()
assert(not bad and why and string.find(why, "EbonholdHub", 1, true),
  "with no run it must fail and say why, got: " .. tostring(why))
print("no run : fails with a cause, not a broken string")

print("\nRUN EXPORT OK -- the live run, in EbonholdHub's own format.")
