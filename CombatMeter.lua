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
  -- Twilight Equilibrium (CORE) alternates schools: Light Essence unleashes
  -- Darkburst (Shadow), Dark Essence unleashes Lightburst (Holy). The log names
  -- the bursts, not the echo — without these two lines its ~33% of your damage
  -- shows as "unmapped" and the build report undersells its own top pick.
  ["darkburst"] = "Twilight Equilibrium",
  ["lightburst"] = "Twilight Equilibrium",
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
  -- Edict of the Iron Council cycles these three:
  ["rune of death"] = "Edict of the Iron Council",
  ["overload"] = "Edict of the Iron Council",
  ["fusion punch"] = "Edict of the Iron Council",
  -- Edict of the Four cycles these:
  ["meteor"] = "Edict of the Four",
  ["void zone"] = "Edict of the Four",
  ["unholy shadow"] = "Edict of the Four",
}

local fight = nil          -- { start, total, echo, spells = {name->amt}, ... }
local lastFight = nil
local bestDps = 0
local BUCKET_SEC = 5       -- damage-over-time window size (for the DPS curve)

-- Kit spells whose CASTS we count, to audit rotation execution (WCL-style
-- active time / ability usage). Keyed spell name -> short bucket key.
local KIT_CAST = {
  ["Crusader Strike"] = "cs", ["Divine Storm"] = "ds",
  ["Judgement of Light"] = "judge", ["Judgement of Wisdom"] = "judge",
  ["Judgement of Justice"] = "judge", ["Judgement"] = "judge",
  ["Consecration"] = "cons", ["Exorcism"] = "exo",
  ["Hammer of Wrath"] = "how", ["Holy Wrath"] = "holyw",
  ["Hammer of the Righteous"] = "hotr", ["Divine Plea"] = "plea",
}

local function StartFight()
  fight = { start = GetTime(), total = 0, echo = 0,
            spells = {}, hits = {}, crits = {}, smax = {},
            targets = {}, taken = 0, maxHit = 0,
            casts = {}, buckets = {}, blows = {}, active = {}, died = false }
end

-- Incoming damage (survival ledger). Tracks the biggest blows with source/spell.
local function AddTaken(amount, spell, src)
  if not amount or amount <= 0 then return end
  if not fight then StartFight() end
  fight.taken = fight.taken + amount
  if amount > fight.maxHit then fight.maxHit = amount end
  local b = fight.blows
  b[#b + 1] = { s = spell or "Melee", src = src, a = amount }
  if #b > 24 then  -- amortized prune to the biggest 6
    table.sort(b, function(x, y) return x.a > y.a end)
    for i = #b, 7, -1 do b[i] = nil end
  end
end

-- Outgoing damage. Also tracks hits, crits, max hit, the DPS curve and active
-- seconds so we can see crit%, proc frequency and ramp per fight.
local function AddDamage(spell, amount, target, isCrit)
  if not amount or amount <= 0 then return end
  if not fight then StartFight() end
  fight.total = fight.total + amount
  fight.spells[spell] = (fight.spells[spell] or 0) + amount
  fight.hits[spell] = (fight.hits[spell] or 0) + 1
  if isCrit then fight.crits[spell] = (fight.crits[spell] or 0) + 1 end
  if amount > (fight.smax[spell] or 0) then fight.smax[spell] = amount end
  if not BASE_KIT[spell] then fight.echo = fight.echo + amount end
  if target then fight.targets[target] = (fight.targets[target] or 0) + amount end
  local t = GetTime() - fight.start
  local bi = math.floor(t / BUCKET_SEC) + 1
  if bi > 24 then bi = 24 end
  fight.buckets[bi] = (fight.buckets[bi] or 0) + amount
  fight.active[math.floor(t)] = true
end

local function CastTrack(spellName)
  local key = KIT_CAST[spellName]
  if not key then return end
  if not fight then StartFight() end
  fight.casts[key] = (fight.casts[key] or 0) + 1
end

-- Persist every recorded fight for post-session analysis (read from
-- SavedVariables after /reload). Ring-buffered to the last N fights, where N is
-- PP.db.fightCap (default 1000, ~1.75 KB/fight => ~1.7 MB). Configurable via
-- /pp bench cap <n>, hard-clamped to a safe range so the SavedVariables file
-- can't grow into logout-hitch / corruption-loss territory.
local DEFAULT_FIGHT_CAP = 1000
local FIGHT_CAP_MIN, FIGHT_CAP_MAX = 50, 20000
function CM.FightCap()
  local n = PP.db and PP.db.fightCap
  if type(n) ~= "number" then return DEFAULT_FIGHT_CAP end
  if n < FIGHT_CAP_MIN then return FIGHT_CAP_MIN end
  if n > FIGHT_CAP_MAX then return FIGHT_CAP_MAX end
  return n
end
CM.FIGHT_CAP_MIN, CM.FIGHT_CAP_MAX = FIGHT_CAP_MIN, FIGHT_CAP_MAX
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
    local nm = sorted[i][1]
    spells[i] = { n = nm, d = math.floor(sorted[i][2]),
                  h = f.hits and f.hits[nm] or nil,
                  c = f.crits and f.crits[nm] or nil,
                  mx = f.smax and math.floor(f.smax[nm] or 0) or nil }
  end
  -- Distinct targets damaged (AoE vs single-target normalization).
  local tCount = 0
  for _ in pairs(f.targets) do tCount = tCount + 1 end
  -- Damage-over-time curve (floored per-window totals).
  local buckets, maxB = {}, 0
  for i in pairs(f.buckets or {}) do if i > maxB then maxB = i end end
  for i = 1, maxB do buckets[i] = math.floor(f.buckets[i] or 0) end
  -- Top-3 incoming blows (survival).
  local blows = f.blows or {}
  table.sort(blows, function(x, y) return x.a > y.a end)
  local topBlows = {}
  for i = 1, math.min(3, #blows) do
    topBlows[i] = { s = blows[i].s, src = blows[i].src, a = math.floor(blows[i].a) }
  end
  -- Bench tags only apply in the zone where they were set (an ICC evening
  -- once inherited a stale HoR tag).
  local tag = PP.db.benchTag
  if tag and PP.db.benchZone and PP.db.benchZone ~= (GetRealZoneText() or "") then
    tag = nil
  end
  -- Auto build tag: the active saved echo build (read lazily — AshAdvisor loads
  -- after this file). A manual bench tag overrides it for within-build A/B.
  local buildId, buildName
  if PP.AshAdvisor and PP.AshAdvisor.ActiveBuild then
    buildId, buildName = PP.AshAdvisor.ActiveBuild()
  end
  log[#log + 1] = {
    t = time(),
    tag = tag,
    build = tag or buildName,                 -- grouping label used by compare
    buildId = (not tag) and buildId or nil,   -- stable id when auto-tagged
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
    -- Richer WCL-style fields (all additive; older readers ignore them):
    active = f.activePct,          -- % of fight seconds you dealt damage
    tgts = tCount,                 -- distinct targets damaged
    casts = f.casts,               -- kit cast counts {cs,ds,judge,cons,exo,...}
    buckets = buckets,             -- damage per BUCKET_SEC window (DPS curve)
    bsec = BUCKET_SEC,
    blows = topBlows,              -- top-3 incoming hits {s=spell, src, a=amount}
    died = f.died or nil,
  }
  local cap = CM.FightCap()
  while #log > cap do table.remove(log, 1) end
end

-- Set the history cap. Clamps to [MIN, MAX], persists, and trims the log now if
-- the new cap is smaller. Returns (appliedCap, dropped, clamped).
function CM.SetFightCap(n)
  n = tonumber(n)
  if not n then return nil end
  n = math.floor(n)
  local clamped = false
  if n < FIGHT_CAP_MIN then n = FIGHT_CAP_MIN; clamped = true end
  if n > FIGHT_CAP_MAX then n = FIGHT_CAP_MAX; clamped = true end
  PP.db.fightCap = n
  local log = PP.db.fights or {}
  local dropped = 0
  while #log > n do table.remove(log, 1); dropped = dropped + 1 end
  return n, dropped, clamped
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
    local activeN = 0
    for _ in pairs(fight.active) do activeN = activeN + 1 end
    lastFight.activePct = math.floor(100 * activeN / math.max(1, dur) + 0.5)
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
  -- WCL-style second line: uptime, crit, target count, biggest blow, death.
  local hitsN, critsN, tN = 0, 0, 0
  for _, h in pairs(f.hits or {}) do hitsN = hitsN + h end
  for _, c in pairs(f.crits or {}) do critsN = critsN + c end
  for _ in pairs(f.targets or {}) do tN = tN + 1 end
  local blows = {}
  for _, x in ipairs(f.blows or {}) do blows[#blows + 1] = x end
  table.sort(blows, function(a, b) return a.a > b.a end)
  local tb = blows[1]
  DEFAULT_CHAT_FRAME:AddMessage(string.format("  %sactive %d%%%s · %scrit %d%%%s · %d target%s%s%s",
    BRIGHT, f.activePct or 0, R,
    BRIGHT, hitsN > 0 and math.floor(100 * critsN / hitsN + 0.5) or 0, R,
    tN, tN == 1 and "" or "s",
    tb and (DIM .. " · worst hit taken " .. R .. EMBER .. Fmt(tb.a) .. R
      .. (tb.s and (DIM .. " (" .. tb.s .. ")" .. R) or "")) or "",
    f.died and (EMBER .. " · DIED" .. R) or ""))
  local sorted = {}
  for name, amt in pairs(f.spells) do sorted[#sorted + 1] = { name, amt } end
  table.sort(sorted, function(a, b) return a[2] > b[2] end)
  for i = 1, math.min(12, #sorted) do
    local name, amt = sorted[i][1], sorted[i][2]
    local pct = amt / f.total * 100
    local tag = BASE_KIT[name] and "" or (EMBER .. " [echo]" .. R)
    local hh = (f.hits and f.hits[name]) or 0
    local cc = (f.crits and f.crits[name]) or 0
    local crit = hh > 0 and (DIM .. "  " .. hh .. " hits, " .. math.floor(100 * cc / hh + 0.5) .. "% crit" .. R) or ""
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s%2d.%s %s — %s (%.1f%%)%s%s",
      DIM, i, R, BRIGHT .. name .. R, Fmt(amt), pct, tag, crit))
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
    if dstGUID == UnitGUID("player") and fight then fight.died = true end
  end
  -- Damage the PLAYER takes (survivability side of the ledger).
  if dstGUID and dstGUID == UnitGUID("player") then
    if event == "SWING_DAMAGE" then
      AddTaken((select(1, ...)), "Melee", srcName)
    elseif event == "SPELL_DAMAGE" or event == "SPELL_PERIODIC_DAMAGE"
        or event == "RANGE_DAMAGE" or event == "DAMAGE_SHIELD" then
      AddTaken((select(4, ...)), (select(2, ...)), srcName)
    elseif event == "ENVIRONMENTAL_DAMAGE" then
      AddTaken((select(2, ...)), "Environment", nil)
    end
  end
  if not srcFlags or bit.band(srcFlags, AFFIL_MINE) == 0 then return end
  -- Crit flag is the 7th damage param for swings, 10th for spells (the 3-field
  -- spell prefix shifts it by 3).
  if event == "SWING_DAMAGE" then
    AddDamage("Melee", (select(1, ...)), dstName, (select(7, ...)))
  elseif event == "SPELL_DAMAGE" or event == "SPELL_PERIODIC_DAMAGE"
      or event == "RANGE_DAMAGE" or event == "DAMAGE_SHIELD" then
    local _, spellName, _, amount = ...
    if spellName then AddDamage(spellName, amount, dstName, (select(10, ...))) end
  elseif event == "SPELL_CAST_SUCCESS" then
    CastTrack((select(2, ...)))
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
  -- Attribute a measured spell name to {echo, tier}. Procs roll up to the echo
  -- that grants them (PROC_ALIAS), so e.g. Darkburst+Lightburst -> Twilight
  -- Equilibrium instead of two "unmapped" rows.
  local function Attribute(name)
    if BASE_KIT[name] then return name, "KIT" end
    local low = string.lower(name)
    local echo = PROC_ALIAS[low] or name
    local tier = PP.EchoAudit and PP.EchoAudit.VerdictFor
      and select(1, PP.EchoAudit.VerdictFor(echo))
    return echo, tier
  end

  -- Roll up BY ECHO (merge each proc into its parent), tracking fights seen.
  local echoDmg, echoTier, echoFights = {}, {}, {}
  for _, f in ipairs(log) do
    if f.spells then
      local seen = {}
      for _, s in ipairs(f.spells) do
        local echo, tier = Attribute(s.n)
        echoDmg[echo] = (echoDmg[echo] or 0) + (s.d or 0)
        echoTier[echo] = tier
        if not seen[echo] then seen[echo] = true
          echoFights[echo] = (echoFights[echo] or 0) + 1 end
      end
    end
  end
  local rows = {}
  for echo, dmg in pairs(echoDmg) do
    rows[#rows + 1] = { echo = echo, d = dmg, tier = echoTier[echo],
                        seen = echoFights[echo] or 0 }
  end
  table.sort(rows, function(a, b) return a.d > b.d end)

  PP.print(GOLD .. "Build report" .. R .. DIM .. " — " .. fights
    .. " fights, " .. Fmt2(grand) .. " total damage (by echo)" .. R)
  local TIERC = { CORE = GOLD, S = BRIGHT, A = "|cff9db3bd", B = DIM, C = DIM,
                  KIT = "|cff8899aa", REROLL = EMBER, DISABLE = EMBER }
  local kitPct = 0
  for _, r in ipairs(rows) do if r.tier == "KIT" then kitPct = kitPct + r.d end end
  kitPct = kitPct / grand * 100

  local promote, demote, unmapped = {}, {}, {}
  for i = 1, math.min(16, #rows) do
    local r = rows[i]
    local pct = r.d / grand * 100
    local tier = r.tier
    local tc = TIERC[tier or ""] or EMBER
    local mark = (tier == "KIT") and (DIM .. "[kit]" .. R)
      or (tc .. "[" .. (tier or "?") .. "]" .. R)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  %2d. %s%-24s%s %s%4.1f%%%s  %s",
      i, BRIGHT, r.echo, R, DIM, pct, R, mark))
  end
  -- Two-way rating check across ALL echoes, not just the printed top rows.
  for _, r in ipairs(rows) do
    local pct = r.d / grand * 100
    local tier = r.tier
    if tier ~= "KIT" then
      if tier == nil and pct >= 1.5 then
        unmapped[#unmapped + 1] = string.format("%s (%.0f%%)", r.echo, pct)
      elseif pct >= 3 and (tier == "B" or tier == "C" or tier == "REROLL") then
        promote[#promote + 1] = string.format("%s (%.0f%%, now %s)", r.echo, pct, tier)
      elseif pct < 0.5 and r.seen >= 8
             and (tier == "CORE" or tier == "S" or tier == "A") then
        demote[#demote + 1] = string.format("%s (%.1f%% over %d fights, rated %s)",
          r.echo, pct, r.seen, tier)
      end
    end
  end

  PP.print(DIM .. "Kit " .. string.format("%.0f%%", kitPct) .. " / echoes "
    .. string.format("%.0f%%", 100 - kitPct) .. R)
  if #unmapped > 0 then
    PP.print(EMBER .. "Unmapped carries — real damage, no echo mapping:" .. R)
    for _, p in ipairs(unmapped) do
      DEFAULT_CHAT_FRAME:AddMessage("  " .. BRIGHT .. p .. R
        .. DIM .. " -> tell Claude the echo that grants this proc" .. R)
    end
  end
  if #promote > 0 then
    PP.print(BRIGHT .. "Earning their damage but rated low:" .. R)
    for _, p in ipairs(promote) do
      DEFAULT_CHAT_FRAME:AddMessage("  " .. VERD .. p .. R .. DIM .. " -> promote?" .. R)
    end
  end
  if #demote > 0 then
    PP.print(EMBER .. "Rated high but barely earning (dead weight, or utility?):" .. R)
    for _, p in ipairs(demote) do
      DEFAULT_CHAT_FRAME:AddMessage("  " .. p)
    end
  end
  if #unmapped == 0 and #promote == 0 and #demote == 0 then
    PP.print(VERD .. "Ratings match measured damage — build direction confirmed." .. R)
  else
    PP.print(DIM .. "Tell Claude these lines and the ratings get corrected from your data." .. R)
  end
end

-- ------------------------------------------------------------ /pp bench compare

local function Median(t)
  local n = #t
  if n == 0 then return 0 end
  local s = {}
  for i = 1, n do s[i] = t[i] end
  table.sort(s)
  if n % 2 == 1 then return s[(n + 1) / 2] end
  return (s[n / 2] + s[n / 2 + 1]) / 2
end

-- Compare BUILDS: group logged fights by the saved echo build that was active
-- (auto-tagged from the server's loadout), or by a manual bench tag when one was
-- set. Shows per-build median/best dps, echo%, damage taken, level range and the
-- most-fought target — a real side-by-side read instead of a blended number.
-- Grouping key: stable buildId when present, else the build/tag name.
function CM.BenchReport()
  local log = PP.db.fights or {}
  local arms, order = {}, {}
  for _, f in ipairs(log) do
    if (f.dur or 0) >= 8 and (f.total or 0) > 0 then
      local key, label
      if f.buildId ~= nil then
        key = "id:" .. tostring(f.buildId)
        label = f.build or f.tag or ("build " .. tostring(f.buildId))
      else
        key = f.build or f.tag or "(untagged)"
        label = key
      end
      local a = arms[key]
      if not a then
        a = { tag = label, dps = {}, echo = {}, taken = {}, lo = 999, hi = 0, targets = {} }
        arms[key] = a; order[#order + 1] = a
      else
        a.tag = label -- keep the most recent display name (survives a rename)
      end
      a.dps[#a.dps + 1] = f.dps or 0
      a.echo[#a.echo + 1] = f.echoPct or 0
      a.taken[#a.taken + 1] = f.taken or 0
      local lv = f.lvl or 0
      if lv > 0 then
        if lv < a.lo then a.lo = lv end
        if lv > a.hi then a.hi = lv end
      end
      if f.target then a.targets[f.target] = (a.targets[f.target] or 0) + 1 end
    end
  end
  if #order == 0 then
    PP.print("No benchmark fights logged yet (fights under ~8s are ignored).")
    return
  end
  for _, a in ipairs(order) do
    a.n = #a.dps
    a.medDps = Median(a.dps); a.medEcho = Median(a.echo); a.medTaken = Median(a.taken)
    a.bestDps = 0
    for _, v in ipairs(a.dps) do if v > a.bestDps then a.bestDps = v end end
    local top, topN = "?", 0
    for name, c in pairs(a.targets) do if c > topN then top, topN = name, c end end
    a.top = top
  end
  table.sort(order, function(x, y) return x.medDps > y.medDps end)

  PP.print(GOLD .. "Build compare" .. R .. DIM .. " — median dps per build, best first" .. R)
  for i, a in ipairs(order) do
    local lead = (i == 1 and #order > 1) and (VERD .. "> " .. R) or "  "
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
      "%s%s%s%s  %sn=%d  med %s  best %s  echo %d%%  taken %s  L%s%s",
      lead, BRIGHT, a.tag, R, DIM, a.n, R,
      GOLD .. Fmt(a.medDps) .. R, Fmt(a.bestDps), a.medEcho, Fmt(a.medTaken),
      (a.lo <= a.hi and (a.lo == a.hi and tostring(a.lo) or (a.lo .. "-" .. a.hi)) or "?"),
      DIM .. "  vs " .. tostring(a.top) .. R))
  end

  if #order < 2 then
    PP.print(DIM .. "Only one build logged so far. Fights tag themselves with your "
      .. "active saved build — just play a second build and they'll compare here." .. R)
    PP.print(DIM .. "Compare builds on the SAME target + level for a fair read." .. R)
  else
    local a, b = order[1], order[2]
    local gap = (b.medDps > 0) and ((a.medDps - b.medDps) / b.medDps * 100) or 0
    PP.print(string.format("%s%s%s leads %s%s%s by %s%.0f%%%s median dps.",
      BRIGHT, a.tag, R, BRIGHT, b.tag, R, GOLD, gap, R))
    if a.top ~= b.top or math.abs(a.lo - b.lo) >= 4 then
      PP.print(EMBER .. "Careful:" .. R .. DIM .. " these builds weren't fought on the "
        .. "same target/level — the gap may be conditions, not the build." .. R)
    end
  end
  -- Footer: what's being tagged right now (manual override vs auto build).
  if PP.db.benchTag then
    PP.print(DIM .. "Now tagging (manual): " .. R .. BRIGHT .. PP.db.benchTag .. R
      .. DIM .. "  (/pp bench off to return to auto)." .. R)
  else
    local bName
    if PP.AshAdvisor and PP.AshAdvisor.ActiveBuild then
      local _; _, bName = PP.AshAdvisor.ActiveBuild()
    end
    if bName then
      PP.print(DIM .. "Auto-tagging active build: " .. R .. BRIGHT .. bName .. R
        .. DIM .. "  (/pp bench <name> to pin a manual A/B)." .. R)
    end
  end
end

-- Attribute a measured spell name -> (echo, tier). Procs roll up to the echo
-- that grants them; kit stays itself with tier "KIT". Shared by the live meter.
local function AttributeSpell(name)
  if BASE_KIT[name] then return name, "KIT" end
  local echo = PROC_ALIAS[string.lower(name)] or name
  local tier = PP.EchoAudit and PP.EchoAudit.VerdictFor
    and select(1, PP.EchoAudit.VerdictFor(echo)) or nil
  return echo, tier
end

-- Live snapshot for the meter HUD. mode = "damage"|"dps"|"taken";
-- segment = "current"|"last". Returns nil if there's no data yet.
function CM.MeterData(mode, segment)
  local f = (segment == "last") and lastFight or (fight or lastFight)
  if not f then return nil end
  local live = (f == fight)
  local dur = live and math.max(0.1, GetTime() - f.start) or math.max(0.1, f.dur or 1)

  if mode == "taken" then
    local blows = {}
    for _, b in ipairs(f.blows or {}) do blows[#blows + 1] = b end
    table.sort(blows, function(a, b) return a.a > b.a end)
    local rows = {}
    for i = 1, math.min(12, #blows) do
      rows[i] = { name = blows[i].s or "?", sub = blows[i].src, dmg = blows[i].a, kit = false }
    end
    return { rows = rows, total = f.taken or 0, dps = (f.taken or 0) / dur, dur = dur,
             maxHit = f.maxHit or 0, live = live, mode = "taken", died = f.died }
  end

  local byEcho, tierOf, hitsOf, critsOf, mxOf = {}, {}, {}, {}, {}
  for name, amt in pairs(f.spells or {}) do
    local echo, tier = AttributeSpell(name)
    byEcho[echo] = (byEcho[echo] or 0) + amt
    tierOf[echo] = tier
    hitsOf[echo] = (hitsOf[echo] or 0) + ((f.hits and f.hits[name]) or 0)
    critsOf[echo] = (critsOf[echo] or 0) + ((f.crits and f.crits[name]) or 0)
    if ((f.smax and f.smax[name]) or 0) > (mxOf[echo] or 0) then mxOf[echo] = f.smax[name] end
  end
  local total = f.total or 0
  local rows, kit, uniq = {}, 0, 0
  for echo, amt in pairs(byEcho) do
    local isKit = (tierOf[echo] == "KIT")
    if isKit then kit = kit + amt else uniq = uniq + 1 end
    rows[#rows + 1] = { name = echo, tier = tierOf[echo], dmg = amt, kit = isKit,
                        hits = hitsOf[echo] or 0, crit = critsOf[echo] or 0, mx = mxOf[echo] or 0 }
  end
  table.sort(rows, function(a, b) return a.dmg > b.dmg end)
  return { rows = rows, total = total, dps = total / dur, dur = dur,
           kitPct = total > 0 and math.floor(100 * kit / total + 0.5) or 0,
           echoPct = total > 0 and math.floor(100 * (total - kit) / total + 0.5) or 0,
           uniq = uniq, live = live, mode = (mode == "dps") and "dps" or "damage" }
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
