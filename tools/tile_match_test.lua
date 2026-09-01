-- The engine stalled forever on "Stonefist Barrage": the perk database calls it
-- "Paladin - Stonefist Barrage - Rare" while the journal tile just says
-- "Stonefist Barrage", and EachTile only yields tiles our catalog can RATE --
-- so the tile was invisible to every consumer including the one that just
-- needed to click it.
--
-- Clicking must never require a rating, and a class prefix or quality suffix on
-- either side must not cause a miss.
--
--   node tools/run_lua.js tools/tile_match_test.lua
PallyPilot = { print = function() end, safeCall = function(fn, ...) return fn(...) end }
EbonPilot = PallyPilot
local PP = PallyPilot
PP.db = { options = { rerollOrbs = 1 } }
PP.EchoFlow = {}

local function Stub()
  local t = {}
  return setmetatable(t, { __index = function() return function() return t end end })
end
function CreateFrame() return Stub() end
UIParent = Stub()
function GetTime() return 0 end
function UnitLevel() return 80 end
function UnitClass() return "Paladin", "PALADIN" end
function date() return "2026-09-01 17:30" end

-- Catalog knows ONLY the class-prefixed form, exactly like the real BuildData.
PP.EchoAudit = {
  MatchDisplay = function(text)
    if text == "Paladin - Stonefist Barrage" then return text, "A" end
    if text == "Contagion" then return "Contagion", "S" end
    return nil        -- a bare "Stonefist Barrage" is UNRATED -> skipped
  end,
  VerdictFor = function() return nil end,
  LockSlots = function() return 6 end,
  Compute = function() return nil end,
  RunQualityTargets = function() return {} end,
  FodderRank = function() return {} end,
}
PP.BisPlan = { Status = function() return nil end }

-- One run tile whose visible label is the BARE name.
local function Region(text)
  local r = { t = text }
  function r:GetText() return self.t end
  function r:GetObjectType() return "FontString" end
  return r
end
local function Tile(label)
  local b = { clicked = false, __label = label }
  function b:GetObjectType() return "Button" end
  function b:IsVisible() return true end
  function b:GetRegions() return Region(label) end
  function b:GetChildren() return end
  function b:GetScript() return nil end
  function b:Click() self.clicked = true end
  return b
end
local stonefist = Tile("Stonefist Barrage")
local contagion = Tile("Contagion")
local unpackFn = unpack or table.unpack
local runRoot = {}
function runRoot:GetChildren() return unpackFn({ stonefist, contagion }) end
function runRoot:GetScrollChild() return nil end
function runRoot:GetObjectType() return "Frame" end
_G.ProjectEbonholdEchoJournalMyRunScroll = runRoot
_G.ProjectEbonholdEchoJournal = runRoot

assert(loadfile("EchoFlow.lua"))()
local EF = PP.EchoFlow

-- Drive the engine into the TILE phase for the prefixed+qualified name and
-- confirm it resolves to the bare-labelled tile.
EF.TileDiag("Paladin - Stonefist Barrage - Rare")
local diag = PP.db.scans and PP.db.scans.tileDiag or {}
local joined = table.concat(diag, "\n")
print(joined)

-- EachTile (rating-gated) sees only Contagion...
assert(string.find(joined, "tile Contagion", 1, true),
  "the rated tile must be visible to the walker")
assert(not string.find(joined, "tile Stonefist", 1, true),
  "an unrated tile is invisible to EachTile -- that is the bug being worked around")

-- ...but FindTile MUST still locate it, because clicking needs no rating.
local hit = EF.FindTile("Paladin - Stonefist Barrage - Rare")
assert(hit == stonefist,
  "FindTile must match the bare-labelled tile despite the class prefix and "
  .. "quality suffix on the queued name")
print("\nFindTile('Paladin - Stonefist Barrage - Rare') -> matched the "
  .. "'Stonefist Barrage' tile")

-- The rated path still works unchanged.
assert(EF.FindTile("Contagion") == contagion, "rated tiles must still resolve")

-- A genuinely absent echo still returns nil, so the skip logic can fire rather
-- than the engine pretending it found something.
assert(EF.FindTile("Echo That Does Not Exist") == nil,
  "an absent echo must return nil so the queue can skip it")

print("TILE MATCH OK -- clicking no longer requires a rating, and prefix or")
print("quality differences on either side no longer cause a stall.")
