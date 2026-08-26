-- PallyPilot CombatMeter: measures what stats can't — the damage your echo
-- effects actually deal. Tracks every damage event from you AND your
-- guardians/procs, per spell name, per fight. Anything that isn't the base
-- paladin kit is echo/proc damage, so /pp dps shows exactly how much of
-- your output the echoes contribute.
local PP = PallyPilot
local CM = PP.CombatMeter

local GOLD = "|cffe0b352"
local BRIGHT = "|cfff6d888"
local DIM = "|cffb4a586"
local VERD = "|cff8aa96a"
local EMBER = "|cffd9694a"
local R = "|r"

-- Base paladin kit: damage under these names is YOU; everything else is
-- an echo proc, guardian, trinket, or affix effect.
local BASE_KIT = {
  ["Melee"] = true, ["Judgement of Light"] = true, ["Judgement of Wisdom"] = true,
  ["Judgement of Justice"] = true, ["Judgement"] = true,
  ["Crusader Strike"] = true, ["Divine Storm"] = true, ["Consecration"] = true,
  ["Exorcism"] = true, ["Hammer of Wrath"] = true, ["Holy Wrath"] = true,
  ["Seal of Vengeance"] = true, ["Holy Vengeance"] = true,
  ["Seal of Command"] = true, ["Seal of Righteousness"] = true,
  ["Shield of Righteousness"] = true, ["Avenger's Shield"] = true,
  ["Hammer of the Righteous"] = true, ["Retribution Aura"] = true,
  ["Righteous Vengeance"] = true,
}

-- Proc spell name (lowercase) -> echo name, for procs the log names
-- differently from their echo. Self-named procs (Cyclone of Cold Bones,
-- Static Overflow, Permafrost Aura...) match the catalog directly and need
-- no entry here. Seeded from tooltips + measured fights; extend as we learn.
local PROC_ALIAS = {
  ["fire cyclone"] = "Cinders of the Sanctum",
  ["locust swarm"] = "Crypt Lord's Swarm",
  ["coldflame"] = "Cyclone of Cold Bones",
  ["mutated blight"] = "Slime Spray",
  ["mutated infection"] = "Slime Spray",
  ["sticky ooze"] = "Slime Spray",
  ["decrepit fever"] = "The Unclean's Fever",
  ["starfall"] = "Constellations",
  ["falling star"] = "Constellations",
  ["big bang"] = "Constellations",
  ["shatter"] = "Brittle Forging",
  ["deep breath"] = "Broodmother's Fury",
  ["searing cinders"] = "Broodmother's Fury",
  ["acid breath"] = "Paladin - Corrosive Breath",
  ["chain lightning"] = "Storm Conductor",
  ["pungent blight"] = "Inhaled Blight",
  ["void spike"] = "Idol of Yogg-Saron",
}

local fight = nil          -- { start, total, echo, spells = {name->amt} }
local lastFight = nil
local bestDps = 0

local function StartFight()
  fight = { start = GetTime(), total = 0, echo = 0, spells = {}, targets = {},
            taken = 0, maxHit = 0 }
end

local function AddTaken(amount)
  if not amount or amount <= 0 then return end
  if not fight then StartFight() end
  fight.taken = fight.taken + amount
  if amount > fight.maxHit then fight.maxHit = amount end
end

local function AddDamage(spell, amount, target)
  if not amount or amount <= 0 then return end
  if not fight then StartFight() end
  fight.total = fight.total + amount
  fight.spells[spell] = (fight.spells[spell] or 0) + amount
  if not BASE_KIT[spell] then fight.echo = fight.echo + amount end
  if target then
    fight.targets[target] = (fight.targets[target] or 0) + amount
  end
end

-- Persist every recorded fight for post-session analysis (read from
-- SavedVariables after /reload). Ring-buffered to the last 150 fights.
local MAX_FIGHTS = 150
local function SaveFight(f)
  PP.db.fights = PP.db.fights or {}
  local log = PP.db.fights
  -- Main target = the name that took the most damage (boss identification).
  local topTarget, topAmt = "?", 0
  for name, amt in pairs(f.targets) do
    if amt > topAmt then topTarget, topAmt = name, amt end
  end
  -- Top 15 spells only, to bound the record size.
  local sorted = {}
  for name, amt in pairs(f.spells) do sorted[#sorted + 1] = { name, amt } end
  table.sort(sorted, function(a, b) return a[2] > b[2] end)
  local spells = {}
  for i = 1, math.min(15, #sorted) do
    spells[i] = { n = sorted[i][1], d = math.floor(sorted[i][2]) }
  end
  -- Bench tags only apply in the zone where they were set (an ICC evening
  -- once inherited a stale HoR tag).
  local tag = PP.db.benchTag
  if tag and PP.db.benchZone and PP.db.benchZone ~= (GetRealZoneText() or "") then
    tag = nil
  end
  log[#log + 1] = {
    t = time(),
    tag = tag,
    when = date("%Y-%m-%d %H:%M"),
    zone = GetRealZoneText() or "?",
    target = topTarget,
    lvl = UnitLevel("player"),
    dur = math.floor(f.dur),
    total = math.floor(f.total),
    dps = math.floor(f.dps),
    echoPct = math.floor(f.echo / f.total * 100 + 0.5),
    taken = math.floor(f.taken or 0),
    maxHit = math.floor(f.maxHit or 0),
    spells = spells,
  }
  while #log > MAX_FIGHTS do table.remove(log, 1) end
end

local function Fmt(n)
  if n >= 1000000 then return string.format("%.1fm", n / 1000000) end
  if n >= 1000 then return string.format("%.1fk", n / 1000) end
  return tostring(math.floor(n))
end

local function EndFight()
  if not fight then return end
  local dur = GetTime() - fight.start
  if dur >= 10 and fight.total > 0 then
    lastFight = fight
    lastFight.dur = dur
    lastFight.dps = fight.total / dur
    local echoPct = math.floor(fight.echo / fight.total * 100 + 0.5)
    local tag = ""
    if lastFight.dps > bestDps then
      tag = VERD .. "  NEW BEST" .. R
      bestDps = lastFight.dps
    end
    PP.print(string.format("Fight: %s DPS over %ds — %d%% from echoes · took %s (max hit %s)%s",
      GOLD .. Fmt(lastFight.dps) .. R, math.floor(dur), echoPct,
      EMBER .. Fmt(fight.taken or 0) .. R, Fmt(fight.maxHit or 0), tag))
    PP.safeCall(SaveFight, lastFight)
  end
  fight = nil
end

function CM.Report()
  local f = lastFight
  if not f then
    PP.print("No fight recorded yet (fights under 10s are ignored). Hit something.")
    return
  end
  local echoPct = math.floor(f.echo / f.total * 100 + 0.5)
  local logged = (PP.db.fights and #PP.db.fights) or 0
  PP.print(string.format("Last fight: %s total, %ds, %s DPS — "
    .. EMBER .. "%d%% echo/proc damage" .. R .. DIM .. "  (%d fights logged)" .. R,
    Fmt(f.total), math.floor(f.dur), GOLD .. Fmt(f.dps) .. R, echoPct, logged))
  local sorted = {}
  for name, amt in pairs(f.spells) do sorted[#sorted + 1] = { name, amt } end
  table.sort(sorted, function(a, b) return a[2] > b[2] end)
  for i = 1, math.min(12, #sorted) do
    local name, amt = sorted[i][1], sorted[i][2]
    local pct = amt / f.total * 100
    local tag = BASE_KIT[name] and "" or (EMBER .. "  [echo/proc]" .. R)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s%2d.%s %s — %s (%.1f%%)%s",
      DIM, i, R, BRIGHT .. name .. R, Fmt(amt), pct, tag))
  end
end

local AFFIL_MINE = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x00000001

-- Boss-kill tracker: UNIT_DIED for a name in the raid guide records the kill
-- (per zone, with the saved-instance id when one exists) — the raid map's
-- skulls are static, so this is the only reliable "what's dead" source.
local function SavedIdForZone(zone)
  for i = 1, GetNumSavedInstances() do
    local name, id = GetSavedInstanceInfo(i)
    if name == zone then return id end
  end
  return nil
end

local function KNorm(s)
  s = string.gsub(s or "", "\226\128\153", "'")
  return string.lower(s)
end

function CM.RecordBossKill(dstName)
  if not (PP.GuideData and PP.GuideData.FindBoss) then return end
  -- Multi-body bosses die under their members' names.
  local alias = PP.GuideData.KILL_ALIASES
    and PP.GuideData.KILL_ALIASES[KNorm(dstName)]
  local lookup = alias or dstName
  -- NOTE: multiple returns must come from a direct call — an and-chain
  -- truncates to one value (the bug that silently ate every kill in v0.28).
  local boss, raid = PP.GuideData.FindBoss(lookup)
  if not boss or not raid then return end
  -- Exact-name kills only (FindBoss substring-matches; require normalized
  -- equality so trash with boss-like names can't false-positive).
  if not alias and KNorm(boss.n) ~= KNorm(dstName) then return end
  PP.db.kills = PP.db.kills or {}
  local zone = raid.zone
  PP.db.kills[zone] = PP.db.kills[zone] or {}
  if PP.db.kills[zone][boss.n]
     and (time() - (PP.db.kills[zone][boss.n].t or 0)) < 3600 then
    return -- council members: don't re-announce within the hour
  end
  PP.db.kills[zone][boss.n] = {
    t = time(), when = date("%Y-%m-%d %H:%M"),
    savedId = SavedIdForZone(zone),
  }
  PP.print("|cff8aa96aBoss kill recorded:|r " .. boss.n .. " (" .. raid.name .. ")")
  if PP.Waypoints and PP.Waypoints.OnBossKill then
    PP.safeCall(PP.Waypoints.OnBossKill, boss.n, zone)
  end
end
local RecordBossKill = CM.RecordBossKill

local function OnCLEU(timestamp, event, srcGUID, srcName, srcFlags,
                      dstGUID, dstName, dstFlags, ...)
  if event == "UNIT_DIED" and dstName then
    PP.safeCall(RecordBossKill, dstName)
  end
  -- Damage the PLAYER takes (survivability side of the ledger).
  if dstGUID and dstGUID == UnitGUID("player") then
    if event == "SWING_DAMAGE" then
      AddTaken((select(1, ...)))
    elseif event == "SPELL_DAMAGE" or event == "SPELL_PERIODIC_DAMAGE"
        or event == "RANGE_DAMAGE" or event == "DAMAGE_SHIELD" then
      AddTaken((select(4, ...)))
    elseif event == "ENVIRONMENTAL_DAMAGE" then
      AddTaken((select(2, ...)))
    end
  end
  if not srcFlags or bit.band(srcFlags, AFFIL_MINE) == 0 then return end
  if event == "SWING_DAMAGE" then
    AddDamage("Melee", (select(1, ...)), dstName)
  elseif event == "SPELL_DAMAGE" or event == "SPELL_PERIODIC_DAMAGE"
      or event == "RANGE_DAMAGE" or event == "DAMAGE_SHIELD" then
    local _, spellName, _, amount = ...
    if spellName then AddDamage(spellName, amount, dstName) end
  end
end

-- Build report: aggregate every logged fight's per-spell damage, attribute
-- each source to an echo + its rating, and flag rating/measurement
-- disagreements so the build's direction is validated by data, not theory.
function CM.BuildReport()
  local log = PP.db.fights or {}
  if #log == 0 then
    PP.print("No fights logged yet — the report needs combat data.")
    return
  end
  local agg, grand = {}, 0
  local fights = 0
  for _, f in ipairs(log) do
    if f.spells then
      fights = fights + 1
      for _, s in ipairs(f.spells) do
        agg[s.n] = (agg[s.n] or 0) + (s.d or 0)
        grand = grand + (s.d or 0)
      end
    end
  end
  if grand == 0 then PP.print("Logged fights have no spell data.") return end

  local function Fmt2(n)
    if n >= 1000000 then return string.format("%.1fm", n / 1000000) end
    if n >= 1000 then return string.format("%.0fk", n / 1000) end
    return tostring(math.floor(n))
  end
  -- Attribute a measured spell name to {echo, tier}.
  local function Attribute(name)
    if BASE_KIT[name] then return name, "KIT" end
    local low = string.lower(name)
    local echo = PROC_ALIAS[low] or name
    local tier = PP.EchoAudit and PP.EchoAudit.VerdictFor
      and select(1, PP.EchoAudit.VerdictFor(echo))
    return echo, tier
  end

  local rows = {}
  for name, dmg in pairs(agg) do rows[#rows + 1] = { name = name, d = dmg } end
  table.sort(rows, function(a, b) return a.d > b.d end)

  PP.print(GOLD .. "Build report" .. R .. DIM .. " — " .. fights
    .. " fights, " .. Fmt2(grand) .. " total damage" .. R)
  local TIERC = { CORE = GOLD, S = BRIGHT, A = "|cff9db3bd", B = DIM, C = DIM,
                  KIT = "|cff8899aa", REROLL = EMBER, DISABLE = EMBER }
  local promote = {}
  for i = 1, math.min(14, #rows) do
    local r = rows[i]
    local echo, tier = Attribute(r.name)
    local pct = r.d / grand * 100
    local tc = TIERC[tier or ""] or EMBER
    local label = (tier == "KIT") and (DIM .. "[kit]" .. R)
      or (tc .. "[" .. (tier or "unmapped") .. "]" .. R)
    local via = (echo ~= r.name) and (DIM .. " <- " .. echo .. R) or ""
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  %2d. %s %s%.1f%%%s  %s%s",
      i, BRIGHT .. r.name .. R, DIM, pct, R, label, via))
    -- Promote candidate: real damage from a low/unrated echo (not kit).
    if tier ~= "KIT" and pct >= 3
       and (tier == "B" or tier == "C" or tier == nil
            or tier == "REROLL") then
      promote[#promote + 1] = echo .. " (" .. string.format("%.0f%%", pct)
        .. ", now " .. (tier or "unrated") .. ")"
    end
  end
  if #promote > 0 then
    PP.print(EMBER .. "Rating check — earning their damage but rated low:" .. R)
    for _, p in ipairs(promote) do
      DEFAULT_CHAT_FRAME:AddMessage("  " .. BRIGHT .. p .. R
        .. DIM .. " -> consider promoting" .. R)
    end
    PP.print(DIM .. "Tell Claude these and the ratings get corrected from your data." .. R)
  else
    PP.print(VERD .. "Top damage sources all rated A+ — build direction confirmed." .. R)
  end
end

function CM.Init()
  -- Restore the session-best from the persisted log.
  for _, f in ipairs((PP.db and PP.db.fights) or {}) do
    if (f.dps or 0) > bestDps then bestDps = f.dps end
  end
  local ev = CreateFrame("Frame")
  ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  ev:RegisterEvent("PLAYER_REGEN_DISABLED")
  ev:RegisterEvent("PLAYER_REGEN_ENABLED")
  ev:SetScript("OnEvent", function(_, e, ...)
    if e == "COMBAT_LOG_EVENT_UNFILTERED" then
      local args = { ... }
      PP.safeCall(OnCLEU, unpack(args))
    elseif e == "PLAYER_REGEN_DISABLED" then
      StartFight()
    elseif e == "PLAYER_REGEN_ENABLED" then
      PP.safeCall(EndFight)
    end
  end)
end
