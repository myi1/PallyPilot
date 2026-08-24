-- PallyPilot Core: namespace, saved vars, events, slash commands, main window.
PallyPilot = {
  Dashboard = {}, FarmQueue = {}, DrawHelper = {}, EchoAudit = {}, RaidGuide = {},
  GearAudit = {}, EchoFlow = {}, BossCard = {}, RunLog = {},
}
local PP = PallyPilot

local DB_VERSION = 1
local DEFAULTS = {
  version = DB_VERSION,
  options = { winPos = nil, autoDraw = false, autoTalents = false, rotationHelper = true,
              rerollOrbs = 1, lockSlots = 5 },
  -- Diagnostic captures (gear tooltips, UI frame dumps). Written here so they
  -- land in SavedVariables on /reload and can be read from WTF directly.
  scans = {},
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
    PP.safeCall(PP.EchoFlow.Init)
    PP.safeCall(PP.BossCard.Init)
    PP.safeCall(PP.GearAudit.HookUI)
    PP.safeCall(PP.RunLog.Init)
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

-- Diagnostic: dump equipped-item tooltip lines so we can learn Ebonhold's
-- affix text format (feeds the future gear/affix auditor).
local SLOT_NAMES = {
  [1]="Head",[2]="Neck",[3]="Shoulder",[4]="Shirt",[5]="Chest",[6]="Waist",
  [7]="Legs",[8]="Feet",[9]="Wrist",[10]="Hands",[11]="Ring1",[12]="Ring2",
  [13]="Trinket1",[14]="Trinket2",[15]="Back",[16]="MainHand",[17]="OffHand",
  [18]="Ranged",[19]="Tabard",
}
function PP.GearScan()
  local tip = PPScanTooltip
    or CreateFrame("GameTooltip", "PPScanTooltip", nil, "GameTooltipTemplate")
  tip:SetOwner(UIParent, "ANCHOR_NONE")
  local dump, items = {}, 0
  for slot = 1, 19 do
    local link = GetInventoryItemLink("player", slot)
    if link then
      tip:ClearLines()
      tip:SetInventoryItem("player", slot)
      local itemName = GetItemInfo(link)
      items = items + 1
      dump[#dump + 1] = "== [" .. (SLOT_NAMES[slot] or slot) .. "] " .. (itemName or "?")
      for i = 2, tip:NumLines() do
        local line = _G["PPScanTooltipTextLeft" .. i]
        local txt = line and line:GetText()
        if txt and txt ~= "" then dump[#dump + 1] = txt end
      end
    end
  end
  PP.db.scans = PP.db.scans or {}
  PP.db.scans.gear = dump
  PP.db.scans.gearTime = date("%Y-%m-%d %H:%M")
  PP.print("Gear scan captured " .. items
    .. " equipped items. /reload to save it, then tell Claude — no screenshot needed.")
end

-- Diagnostic: capture all visible named frames (and anonymous buttons with
-- text) into SavedVariables. Run with the Echoes window open to map the
-- reroll UI for one-click automation.
local function NearestNamedAncestor(f)
  local p = f:GetParent()
  local depth = 0
  while p and depth < 8 do
    if p.GetName and p:GetName() then return p:GetName() end
    p = p:GetParent(); depth = depth + 1
  end
  return nil
end

function PP.UiScan()
  local out, count = {}, 0
  local f = EnumerateFrames()
  while f do
    local ok = pcall(function()
      if f.IsVisible and f:IsVisible() then
        local name = f.GetName and f:GetName() or nil
        local ftype = f.GetObjectType and f:GetObjectType() or "?"
        local label
        if ftype == "Button" then
          local fs = f.GetFontString and f:GetFontString()
          label = fs and fs:GetText() or nil
          if not label and f.GetText then label = f:GetText() end
        end
        if name or label then
          count = count + 1
          out[count] = ftype .. " | " .. (name or "(anon)")
            .. (label and (" | txt=" .. label) or "")
            .. " | parent=" .. (NearestNamedAncestor(f) or "?")
        end
      end
    end)
    if not ok then count = count end
    f = EnumerateFrames(f)
  end
  PP.db.scans = PP.db.scans or {}
  PP.db.scans.ui = out
  PP.db.scans.uiTime = date("%Y-%m-%d %H:%M")
  PP.print("UI scan captured " .. count
    .. " visible frames. /reload to save it, then tell Claude — no screenshot needed.")
end

-- Deep scan of the server's Echo Journal subtree: every child frame with its
-- plain-data fields (echo ids live on tile buttons the way checkpoint data
-- lived on map buttons). Run with the Echoes window open.
function PP.UiScanEcho()
  local root = _G["ProjectEbonholdEchoJournal"]
  if not root then
    PP.print("Echo journal frame not found — open the Echoes window first.")
    return
  end
  local out, n = {}, 0
  local MAX = 2500
  local function fieldDump(f)
    local bits = {}
    for k, v in pairs(f) do
      local tv = type(v)
      if tv == "string" or tv == "number" or tv == "boolean" then
        bits[#bits + 1] = tostring(k) .. "=" .. tostring(v)
      end
    end
    table.sort(bits)
    return table.concat(bits, ", ")
  end
  local function walk(f, depth)
    if depth > 7 or n >= MAX then return end
    local kids = { f:GetChildren() }
    for i, c in ipairs(kids) do
      if n >= MAX then return end
      local ok = pcall(function()
        local ctype = c.GetObjectType and c:GetObjectType() or "?"
        local name = c.GetName and c:GetName() or nil
        local label
        if c.GetFontString then
          local cfs = c:GetFontString()
          label = cfs and cfs:GetText() or nil
        end
        if not label and c.GetText then label = c:GetText() end
        n = n + 1
        out[n] = string.rep("  ", depth) .. ctype .. " " .. (name or ("#" .. i))
          .. (label and (" txt=" .. tostring(label)) or "")
          .. (c:IsVisible() and "" or " [hidden]")
        local fd = fieldDump(c)
        if fd ~= "" and n < MAX then
          n = n + 1
          out[n] = string.rep("  ", depth) .. "   {" .. fd .. "}"
        end
      end)
      if ok then walk(c, depth + 1) end
    end
  end
  walk(root, 0)
  PP.db.scans = PP.db.scans or {}
  PP.db.scans.echoUI = out
  PP.db.scans.echoUITime = date("%Y-%m-%d %H:%M")
  PP.print("Echo journal deep scan: " .. n
    .. " lines captured. /reload to save, then tell Claude.")
end

-- Diagnostic: dump the server's echo/perk database to SavedVariables so
-- every echo in the game can be rated into BuildData tiers.
function PP.PerkScan()
  local db = ProjectEbonhold and ProjectEbonhold.PerkDatabase
  if not db then
    PP.print("ProjectEbonhold.PerkDatabase not found on this client.")
    return
  end
  local lines, n = {}, 0
  local MAX = 8000
  local function dump(t, prefix, depth)
    if depth > 3 or n >= MAX then return end
    for k, v in pairs(t) do
      if n >= MAX then return end
      local tv = type(v)
      if tv == "table" then
        dump(v, prefix .. "." .. tostring(k), depth + 1)
      elseif tv == "string" or tv == "number" or tv == "boolean" then
        n = n + 1
        lines[n] = prefix .. "." .. tostring(k) .. " = " .. tostring(v)
      end
    end
  end
  dump(db, "Perk", 0)
  table.sort(lines)
  PP.db.scans = PP.db.scans or {}
  PP.db.scans.perks = lines
  PP.db.scans.perksTime = date("%Y-%m-%d %H:%M")
  PP.print("Perk database dump: " .. n
    .. " lines. /reload to save, then tell Claude — every echo gets rated.")
end

SLASH_PALLYPILOT1 = "/pp"
SLASH_PALLYPILOT2 = "/pallypilot"
SlashCmdList["PALLYPILOT"] = function(line)
  local _, _, cmd, arg = string.find(line or "", "^%s*(%S*)%s*(.-)%s*$")
  cmd = string.lower(cmd or "")
  if cmd == "" or cmd == "show" then
    if PP.Dashboard.Toggle then PP.Dashboard.Toggle() end
  elseif cmd == "farm" then
    if PP.FarmQueue.Toggle then PP.FarmQueue.Toggle() end
  elseif cmd == "audit" or cmd == "echoes" then
    if PP.EchoAudit.Toggle then PP.EchoAudit.Toggle() end
  elseif cmd == "guide" or cmd == "raid" then
    if PP.RaidGuide.Toggle then PP.RaidGuide.Toggle() end
  elseif cmd == "boss" then
    if PP.RaidGuide.BossToChat then PP.RaidGuide.BossToChat(arg) end
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
  elseif cmd == "gearscan" then
    PP.safeCall(PP.GearScan)
  elseif cmd == "uiscan" then
    if arg == "echo" then PP.safeCall(PP.UiScanEcho) else PP.safeCall(PP.UiScan) end
  elseif cmd == "perkscan" then
    PP.safeCall(PP.PerkScan)
  elseif cmd == "run" then
    if arg == "start" then PP.safeCall(PP.RunLog.Start)
    else PP.safeCall(PP.RunLog.Status) end
  elseif cmd == "locks" then
    local n = tonumber(arg)
    if n and n >= 1 and n <= 12 then
      PP.db.options.lockSlots = n
      PP.print("Permanent echo slots set to " .. n .. " — Lock Now recommends that many.")
    else
      PP.print("Usage: /pp locks <n>  (currently " .. (PP.db.options.lockSlots or 5) .. ")")
    end
  elseif cmd == "gear" then
    if PP.GearAudit.Toggle then PP.GearAudit.Toggle() end
  elseif cmd == "reroll" then
    if PP.EchoFlow.StartReroll then PP.safeCall(PP.EchoFlow.StartReroll) end
  else
    PP.print("/pp (dashboard) | /pp farm | /pp audit | /pp gear | /pp guide | /pp boss [name] | /pp rotation | /pp talents recommend|guide|auto")
  end
end
