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
  log[#log + 1] = {
    t = time(),
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

local function OnCLEU(timestamp, event, srcGUID, srcName, srcFlags,
                      dstGUID, dstName, dstFlags, ...)
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
