-- PallyPilot RunLog: records a full run (death -> level 80) automatically.
-- Every level-up logs time / HP / AP / crit / zone; every new echo logs
-- name + verdict + level. Data lands in SavedVariables for post-run
-- analysis and run-over-run comparison.
local PP = PallyPilot
local RL = PP.RunLog

local GOLD = "|cffe0b352"
local BRIGHT = "|cfff6d888"
local DIM = "|cffb4a586"
local R = "|r"

local function Runs()
  PP.db.runs = PP.db.runs or { history = {} }
  return PP.db.runs
end

local function Snap()
  local base, pos, neg = UnitAttackPower("player")
  return {
    lvl = UnitLevel("player"),
    t = time(),
    hp = UnitHealthMax("player") or 0,
    ap = (base or 0) + (pos or 0) + (neg or 0),
    crit = math.floor(((GetCritChance and GetCritChance()) or 0) * 10 + 0.5) / 10,
    zone = GetRealZoneText() or "?",
  }
end

function RL.Start()
  local runs = Runs()
  if runs.current and not runs.current.finished then
    runs.history[#runs.history + 1] = runs.current
  end
  runs.current = {
    started = date("%Y-%m-%d %H:%M"),
    startedAt = time(),
    levels = { Snap() },
    echoes = {},
  }
  PP.print("Run log started at level " .. UnitLevel("player")
    .. ". Level-ups and echo learns record automatically. /pp run for status.")
end

function RL.OnLevelUp()
  local runs = Runs()
  if not runs.current or runs.current.finished then return end
  local s = Snap()
  -- Catch-up bursts fire one event per level gained; collapse same-level
  -- snapshots into the latest reading instead of appending duplicates.
  local prev = runs.current.levels[#runs.current.levels]
  if prev and prev.lvl == s.lvl then
    runs.current.levels[#runs.current.levels] = s
    return
  end
  runs.current.levels[#runs.current.levels + 1] = s
  if s.lvl >= 80 then
    runs.current.finished = date("%Y-%m-%d %H:%M")
    local mins = math.floor((time() - (runs.current.startedAt or time())) / 60)
    PP.print(GOLD .. "Run logged: level 80 in " .. mins .. " minutes. "
      .. "/reload and tell Claude for the run report." .. R)
  end
end

function RL.OnNewEcho(display, verdict)
  local runs = Runs()
  if not runs.current or runs.current.finished then return end
  runs.current.echoes[#runs.current.echoes + 1] = {
    name = display, verdict = verdict, lvl = UnitLevel("player"), t = time(),
  }
end

function RL.Status()
  local runs = Runs()
  local c = runs.current
  if not c then
    PP.print("No run being logged. /pp run start to begin one.")
    return
  end
  local mins = math.floor((time() - (c.startedAt or time())) / 60)
  local last = c.levels[#c.levels]
  PP.print("Run: started " .. c.started .. " — " .. BRIGHT .. "level "
    .. (last and last.lvl or "?") .. R .. DIM .. " · " .. mins .. " min · "
    .. #c.echoes .. " echoes learned · " .. #c.levels .. " level snapshots" .. R
    .. (c.finished and (GOLD .. " · FINISHED" .. R) or ""))
end

function RL.Init()
  local ev = CreateFrame("Frame")
  ev:RegisterEvent("PLAYER_LEVEL_UP")
  ev:SetScript("OnEvent", function()
    -- Stats settle a moment after the ding.
    local wait = CreateFrame("Frame")
    wait.age = 0
    wait:SetScript("OnUpdate", function(self, elapsed)
      self.age = self.age + elapsed
      if self.age > 1 then
        self:SetScript("OnUpdate", nil)
        PP.safeCall(RL.OnLevelUp)
      end
    end)
  end)
  -- Echo learns arrive via the audit watcher's callback (tome ownership)...
  PP.EchoAudit.onNewEcho = function(display, verdict)
    PP.safeCall(RL.OnNewEcho, display, verdict)
  end
  -- ...but run DRAWS don't change ownership, so also tap EbonholdHub's own
  -- pick tracker (post-hook only, behavior untouched).
  if EbonholdHub and EbonholdHub.Build and EbonholdHub.Build.TrackPickStat
     and hooksecurefunc then
    hooksecurefunc(EbonholdHub.Build, "TrackPickStat", function(pick)
      if pick and pick.name then
        local verdict = PP.EchoAudit.VerdictFor
          and select(1, PP.EchoAudit.VerdictFor(pick.name)) or "?"
        PP.safeCall(RL.OnNewEcho, pick.name, "pick:" .. tostring(verdict))
        if PP.EchoFlow and PP.EchoFlow.NotifyPick then
          PP.safeCall(PP.EchoFlow.NotifyPick, pick.name)
        end
      end
    end)
  end
end
