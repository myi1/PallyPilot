-- PallyPilot Waypoints: breadcrumb routes through raids, followed with
-- CallboardHunter's arrow (Ebonhold's client returns map coords INSIDE
-- instances — verified in ICC 2026-08-25, unlike stock 3.3.5).
--   /pp mark <label>   record a breadcrumb at your position (zone+floor+x,y)
--   /pp marks          list this zone's breadcrumbs
--   /pp go             follow the chain from the nearest mark on your floor
--   /pp go off         stop following
-- Recorded marks live in PallyPilotDB.marks[zone] and can be baked into
-- shipped route data later.
local PP = PallyPilot
local W = PP.Waypoints

local GOLD = "|cffe0b352"
local BRIGHT = "|cfff6d888"
local DIM = "|cffb4a586"
local EMBER = "|cffd9694a"
local VERD = "|cff8aa96a"
local R = "|r"

local ARRIVE = 0.02  -- normalized map distance counting as "reached"

local following = nil -- { zone, idx }

local function Marks(zone)
  PP.db.marks = PP.db.marks or {}
  PP.db.marks[zone] = PP.db.marks[zone] or {}
  return PP.db.marks[zone]
end

local function PlayerPos()
  if not WorldMapFrame:IsShown() then SetMapToCurrentZone() end
  local x, y = GetPlayerMapPosition("player")
  if not x or (x == 0 and y == 0) then return nil end
  return x, y, GetCurrentMapDungeonLevel() or 0
end

local function Arrow()
  return CallboardHunter and CallboardHunter.Arrow
end

function W.Mark(label)
  local x, y, floor = PlayerPos()
  if not x then
    PP.print("No map coordinates here — can't mark.")
    return
  end
  local zone = GetRealZoneText()
  local list = Marks(zone)
  list[#list + 1] = { x = x, y = y, floor = floor,
    label = (label and label ~= "" and label) or ("mark " .. (#list + 1)) }
  PP.print("Mark " .. #list .. " set: " .. BRIGHT .. list[#list].label .. R
    .. DIM .. string.format("  (floor %d, %.3f/%.3f)", floor, x, y) .. R)
end

function W.List()
  local zone = GetRealZoneText()
  local list = Marks(zone)
  if #list == 0 then PP.print("No marks in " .. zone .. ".") return end
  PP.print("Marks in " .. zone .. ":")
  for i, m in ipairs(list) do
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  %d. %s (floor %d, %.3f/%.3f)",
      i, m.label, m.floor or 0, m.x, m.y))
  end
end

function W.Stop(msg)
  following = nil
  local a = Arrow()
  if a and a.ClearCustom then a.ClearCustom() end
  if msg then PP.print(msg) end
end

function W.Go()
  local a = Arrow()
  if not (a and a.SetCustom) then
    PP.print("CallboardHunter's arrow isn't available.")
    return
  end
  local zone = GetRealZoneText()
  local list = Marks(zone)
  if #list == 0 then
    PP.print("No marks recorded in " .. zone .. " — drop some with /pp mark <label>.")
    return
  end
  local x, y, floor = PlayerPos()
  if not x then PP.print("No coordinates here.") return end
  -- Start at the nearest mark on this floor (falls back to mark 1).
  local best, bestD = 1, nil
  for i, m in ipairs(list) do
    if (m.floor or 0) == floor then
      local dx, dy = m.x - x, m.y - y
      local d = dx * dx + dy * dy
      if not bestD or d < bestD then best, bestD = i, d end
    end
  end
  following = { zone = zone, idx = best }
  PP.print("Following " .. #list .. " marks from #" .. best
    .. " (" .. list[best].label .. "). /pp go off to stop.")
end

local ticker = CreateFrame("Frame")
ticker.t = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
  self.t = self.t + elapsed
  if self.t < 0.3 then return end
  self.t = 0
  if not following then return end
  local a = Arrow()
  if not a then return end
  local zone = GetRealZoneText()
  if zone ~= following.zone then
    W.Stop("Left " .. following.zone .. " — waypoint chain stopped.")
    return
  end
  local list = Marks(zone)
  local m = list[following.idx]
  if not m then
    W.Stop(VERD .. "Route complete." .. R)
    return
  end
  local x, y, floor = PlayerPos()
  if not x then return end
  if (m.floor or 0) ~= floor then
    -- Different floor: keep pointing at the mark's coords (stairs and
    -- elevators are where the previous same-floor mark led you).
    a.SetCustom(m.x, m.y, m.label .. " (floor " .. (m.floor or 0) .. ")")
    return
  end
  local dx, dy = m.x - x, m.y - y
  if math.abs(dx) < ARRIVE and math.abs(dy) < ARRIVE then
    following.idx = following.idx + 1
    local nxt = list[following.idx]
    if nxt then
      PP.print(DIM .. "Reached " .. m.label .. " — next: " .. nxt.label .. R)
    else
      W.Stop(VERD .. "Route complete — " .. m.label .. " was the last mark." .. R)
    end
    return
  end
  a.SetCustom(m.x, m.y, m.label .. DIM .. "  (" .. following.idx .. "/" .. #list .. ")" .. R)
end)
