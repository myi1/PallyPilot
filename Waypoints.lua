-- PallyPilot Waypoints: raid navigation via CallboardHunter's arrow.
-- Ebonhold's client returns map coords INSIDE instances (verified in ICC).
--
-- AUTO-LEARNED ROUTES (the main system — no typing): while you're inside a
-- guide raid your path records itself; the moment a boss dies, the walked
-- trail snapshots as the route to that boss. Next run: /pp go <boss> and
-- the arrow leads you there. Manual /pp mark breadcrumbs remain as a
-- fallback for routes you want without a kill.
local PP = PallyPilot
local W = PP.Waypoints

local GOLD = "|cffe0b352"
local BRIGHT = "|cfff6d888"
local DIM = "|cffb4a586"
local VERD = "|cff8aa96a"
local R = "|r"

local ARRIVE = 0.02

local following = nil -- { zone, idx, points = {{x,y,floor,label}}, name }

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

-- ------------------------------------------------------------ auto trail
local trail, trailZone = {}, nil

local function SampleTrail()
  if WorldMapFrame:IsShown() then return end -- don't fight the user's map
  local zone = GetRealZoneText()
  local raid = PP.GuideData and PP.GuideData.RaidForZone
    and PP.GuideData.RaidForZone(zone)
  if not raid then
    trailZone, trail = nil, {}
    return
  end
  local x, y, floor = PlayerPos()
  if not x then return end
  if trailZone ~= zone then trailZone, trail = zone, {} end
  local last = trail[#trail]
  if last and last.floor == floor
     and math.abs(last.x - x) < 0.008 and math.abs(last.y - y) < 0.008 then
    return
  end
  trail[#trail + 1] = { x = x, y = y, floor = floor }
  -- Amortised prune, not table.remove(trail, 1). This samples every 2s and only
  -- inside a RAID zone, so once the trail filled it was shifting 1500 elements
  -- down by one, every two seconds, for the entire raid -- the one place the
  -- cost lands is the one place it is least welcome. Drop the oldest quarter in
  -- one pass instead: same bound, 1/375th of the work per sample.
  if #trail > 1500 then
    local keep, out = 375, {}
    for i = keep + 1, #trail do out[#out + 1] = trail[i] end
    trail = out
  end
end

-- Keep endpoints, floor changes, and real turns; cap the point count.
local function SimplifyTrail(t)
  local out = {}
  local function push(p) out[#out + 1] = { x = p.x, y = p.y, floor = p.floor } end
  for i, p in ipairs(t) do
    if i == 1 or i == #t then
      push(p)
    else
      local a, b = t[i - 1], t[i + 1]
      if p.floor ~= a.floor or p.floor ~= b.floor then
        push(p)
      else
        local v1x, v1y = p.x - a.x, p.y - a.y
        local v2x, v2y = b.x - p.x, b.y - p.y
        local d1 = math.sqrt(v1x * v1x + v1y * v1y)
        local d2 = math.sqrt(v2x * v2x + v2y * v2y)
        if d1 > 0 and d2 > 0
           and (v1x * v2x + v1y * v2y) / (d1 * d2) < 0.9 then
          push(p)
        end
      end
    end
  end
  while #out > 120 do table.remove(out, 2 + math.floor((#out - 2) / 2)) end
  return out
end

-- Called by CombatMeter when a guide boss dies: the walked trail becomes
-- the learned route to that boss.
function W.OnBossKill(bossName, zone)
  if trailZone ~= zone or #trail < 2 then return end
  PP.db.routes = PP.db.routes or {}
  PP.db.routes[zone] = PP.db.routes[zone] or {}
  PP.db.routes[zone][bossName] = SimplifyTrail(trail)
  PP.print("Route learned: " .. #PP.db.routes[zone][bossName]
    .. " waypoints to " .. BRIGHT .. bossName .. R .. " — next run: /pp go "
    .. string.lower(bossName))
end

-- ------------------------------------------------------------ manual marks
function W.Mark(label)
  local x, y, floor = PlayerPos()
  if not x then PP.print("No map coordinates here — can't mark.") return end
  local zone = GetRealZoneText()
  local list = Marks(zone)
  list[#list + 1] = { x = x, y = y, floor = floor,
    label = (label and label ~= "" and label) or ("mark " .. (#list + 1)) }
  PP.print("Mark " .. #list .. " set: " .. BRIGHT .. list[#list].label .. R)
end

function W.List()
  local zone = GetRealZoneText()
  local list = Marks(zone)
  local routes = PP.db.routes and PP.db.routes[zone]
  if routes and next(routes) then
    PP.print("Learned routes in " .. zone .. ":")
    for boss, pts in pairs(routes) do
      DEFAULT_CHAT_FRAME:AddMessage("  " .. VERD .. boss .. R .. DIM
        .. " (" .. #pts .. " wps) — /pp go " .. string.lower(boss) .. R)
    end
  end
  if #list > 0 then
    PP.print("Manual marks in " .. zone .. ": " .. #list .. " (/pp go follows them)")
  elseif not (routes and next(routes)) then
    PP.print("Nothing recorded in " .. zone .. " yet — routes learn "
      .. "themselves when a boss dies.")
  end
end

-- ------------------------------------------------------------ following
function W.Stop(msg)
  following = nil
  local a = Arrow()
  if a and a.ClearCustom then a.ClearCustom() end
  if msg then PP.print(msg) end
end

function W.Go(arg)
  local a = Arrow()
  if not (a and a.SetCustom) then
    PP.print("CallboardHunter's arrow isn't available.")
    return
  end
  local zone = GetRealZoneText()
  local points, name

  if arg and arg ~= "" then
    -- Follow a learned route to a boss.
    local boss = PP.GuideData and PP.GuideData.FindBoss
      and PP.GuideData.FindBoss(arg)
    local routes = PP.db.routes and PP.db.routes[zone]
    local key = boss and boss.n or arg
    local route = routes and (routes[key] or routes[arg])
    if not route then
      PP.print("No learned route to '" .. tostring(arg) .. "' in " .. zone
        .. ". Kill it once while walking there and the route records itself.")
      return
    end
    points = {}
    for i, p in ipairs(route) do
      points[i] = { x = p.x, y = p.y, floor = p.floor,
        label = key .. " " .. i .. "/" .. #route }
    end
    name = key
  else
    local list = Marks(zone)
    if #list == 0 then
      W.List()
      return
    end
    points = {}
    for i, m in ipairs(list) do
      points[i] = { x = m.x, y = m.y, floor = m.floor,
        label = m.label .. " (" .. i .. "/" .. #list .. ")" }
    end
    name = "marks"
  end

  local x, y, floor = PlayerPos()
  if not x then PP.print("No coordinates here.") return end
  local best, bestD = 1, nil
  for i, p in ipairs(points) do
    if (p.floor or 0) == floor then
      local dx, dy = p.x - x, p.y - y
      local d = dx * dx + dy * dy
      if not bestD or d < bestD then best, bestD = i, d end
    end
  end
  following = { zone = zone, idx = best, points = points, name = name }
  PP.print("Following " .. name .. " from waypoint " .. best .. "/" .. #points
    .. ". /pp go off to stop.")
end

local ticker = CreateFrame("Frame")
ticker.t, ticker.s = 0, 0
ticker:SetScript("OnUpdate", function(self, elapsed)
  self.s = self.s + elapsed
  if self.s >= 2 then
    self.s = 0
    PP.safeCall(SampleTrail)
  end
  self.t = self.t + elapsed
  if self.t < 0.3 then return end
  self.t = 0
  if not following then return end
  local a = Arrow()
  if not a then return end
  local zone = GetRealZoneText()
  if zone ~= following.zone then
    W.Stop("Left " .. following.zone .. " — navigation stopped.")
    return
  end
  local p = following.points[following.idx]
  if not p then
    W.Stop(VERD .. "Route complete." .. R)
    return
  end
  local x, y, floor = PlayerPos()
  if not x then return end
  if (p.floor or 0) ~= floor then
    a.SetCustom(p.x, p.y, p.label .. " (floor " .. (p.floor or 0) .. ")")
    return
  end
  local dx, dy = p.x - x, p.y - y
  if math.abs(dx) < ARRIVE and math.abs(dy) < ARRIVE then
    following.idx = following.idx + 1
    if not following.points[following.idx] then
      W.Stop(VERD .. "Arrived — " .. following.name .. " route complete." .. R)
    end
    return
  end
  a.SetCustom(p.x, p.y, p.label)
end)
