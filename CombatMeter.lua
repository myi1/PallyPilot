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
  fight = { start = GetTime(), total = 0, echo = 0, spells = {} }
end

local function AddDamage(spell, amount)
  if not amount or amount <= 0 then return end
  if not fight then StartFight() end
  fight.total = fight.total + amount
  fight.spells[spell] = (fight.spells[spell] or 0) + amount
  if not BASE_KIT[spell] then fight.echo = fight.echo + amount end
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
    PP.print(string.format("Fight: %s DPS over %ds — %d%% from echoes%s  (/pp dps for breakdown)",
      GOLD .. Fmt(lastFight.dps) .. R, math.floor(dur), echoPct, tag))
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
  PP.print(string.format("Last fight: %s total, %ds, %s DPS — "
    .. EMBER .. "%d%% echo/proc damage" .. R,
    Fmt(f.total), math.floor(f.dur), GOLD .. Fmt(f.dps) .. R, echoPct))
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
  if not srcFlags or bit.band(srcFlags, AFFIL_MINE) == 0 then return end
  if event == "SWING_DAMAGE" then
    AddDamage("Melee", (select(1, ...)))
  elseif event == "SPELL_DAMAGE" or event == "SPELL_PERIODIC_DAMAGE"
      or event == "RANGE_DAMAGE" or event == "DAMAGE_SHIELD" then
    local _, spellName, _, amount = ...
    if spellName then AddDamage(spellName, amount) end
  end
end

function CM.Init()
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
