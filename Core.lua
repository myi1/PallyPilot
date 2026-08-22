-- PallyPilot Core: namespace, saved vars, events, slash commands, main window.
PallyPilot = {
  Dashboard = {}, FarmQueue = {}, DrawHelper = {},
}
local PP = PallyPilot

local DB_VERSION = 1
local DEFAULTS = {
  version = DB_VERSION,
  options = { winPos = nil, autoDraw = false, autoTalents = false, rotationHelper = true },
}

local function CopyDefaults(src, dst)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      CopyDefaults(v, dst[k])
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

function PP.print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffe0b352PallyPilot|r: " .. tostring(msg))
end

local seenErr = {}
function PP.safeCall(fn, ...)
  if not fn then return end
  local ok, err = pcall(fn, ...)
  if not ok and not seenErr[tostring(err)] then
    seenErr[tostring(err)] = true
    PP.print("|cffff5050ERROR:|r " .. tostring(err))
  end
end

-- Integration helpers (all nil-guarded; addon works without the others).
function PP.HasEbonholdHub()
  return EbonholdHub ~= nil and EbonholdHub.EchoMapData ~= nil
end
function PP.HasCallboardHunter()
  return CallboardHunter ~= nil and CallboardHunter.Advisor ~= nil
    and CallboardHunter.Advisor.Port ~= nil
end
-- Ask CallboardHunter to travel toward a zone's nearest checkpoint.
function PP.PortToZone(zone)
  if PP.HasCallboardHunter() and zone then
    PP.safeCall(CallboardHunter.Advisor.Port, zone)
  else
    PP.print("Porting needs the CallboardHunter addon. Zone: " .. tostring(zone))
  end
end

local function OnEvent(self, event, ...)
  if event == "ADDON_LOADED" then
    if ... == "PallyPilot" then
      if type(PallyPilotDB) ~= "table" then PallyPilotDB = {} end
      if PallyPilotDB.version ~= DB_VERSION then
        PallyPilotDB = {}
      end
      CopyDefaults(DEFAULTS, PallyPilotDB)
      PP.db = PallyPilotDB
    end
  elseif event == "PLAYER_LOGIN" then
    PP.safeCall(PP.Dashboard.Init)
    PP.safeCall(PP.DrawHelper.Init)
    if PP.RotationHelper then PP.safeCall(PP.RotationHelper.Init) end
    local paladin = select(2, UnitClass("player")) == "PALADIN"
    if not paladin then
      PP.print("Heads up: this build is tuned for Paladins. You're playing "
        .. (UnitClass("player") or "?") .. " — the dashboard still opens, but advice won't fit.")
    end
    PP.print("loaded. |cffe0b352/pp|r for the dashboard, |cffe0b352/pp farm|r for missing tomes.")
  end
end

PP.frame = CreateFrame("Frame")
PP.frame:SetScript("OnEvent", OnEvent)
PP.frame:RegisterEvent("ADDON_LOADED")
PP.frame:RegisterEvent("PLAYER_LOGIN")

SLASH_PALLYPILOT1 = "/pp"
SLASH_PALLYPILOT2 = "/pallypilot"
SlashCmdList["PALLYPILOT"] = function(line)
  local _, _, cmd, arg = string.find(line or "", "^%s*(%S*)%s*(.-)%s*$")
  cmd = string.lower(cmd or "")
  if cmd == "" or cmd == "show" then
    if PP.Dashboard.Toggle then PP.Dashboard.Toggle() end
  elseif cmd == "farm" then
    if PP.FarmQueue.Toggle then PP.FarmQueue.Toggle() end
  elseif cmd == "echoscan" then
    if PP.DrawHelper.Scan then PP.DrawHelper.Scan() end
  elseif cmd == "draw" then
    PP.db.options.autoDraw = not PP.db.options.autoDraw
    PP.print("Draw helper " .. (PP.db.options.autoDraw and "ON" or "OFF"))
  elseif cmd == "talents" then
    if PP.Talents and PP.Talents.Command then PP.Talents.Command(arg) end
  elseif cmd == "rotation" or cmd == "rot" then
    if PP.RotationHelper then PP.RotationHelper.Toggle() end
  elseif cmd == "keyscan" then
    if PP.RotationHelper and PP.RotationHelper.KeyScan then PP.RotationHelper.KeyScan() end
  else
    PP.print("/pp (dashboard) | /pp farm | /pp rotation | /pp talents recommend|guide|auto")
  end
end
