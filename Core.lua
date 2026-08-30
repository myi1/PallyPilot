-- EbonPilot Core: namespace, saved vars, events, slash commands, main window.
-- (Formerly PallyPilot -- now a multi-class Ebonhold co-pilot. This "local"
-- rename keeps the folder / SavedVariables / repo named PallyPilot so no data
-- migrates and nothing breaks; the folder + repo rename come in a later pass.)
EbonPilot = {
  Dashboard = {}, FarmQueue = {}, DrawHelper = {}, EchoAudit = {}, RaidGuide = {},
  GearAudit = {}, EchoFlow = {}, BossCard = {}, RunLog = {}, HubSync = {},
  CombatMeter = {}, AshAdvisor = {}, Waypoints = {}, TomeManager = {},
  BuildScore = {}, GearOpt = {},
  Classes = {},  -- per-class guide data, keyed by UnitClass token (PALADIN, HUNTER, ...)
}
-- Back-compat alias: every module still does `local PP = PallyPilot`.
PallyPilot = EbonPilot
local PP = EbonPilot

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
  DEFAULT_CHAT_FRAME:AddMessage("|cffe0b352EbonPilot|r: " .. tostring(msg))
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
    PP.safeCall(PP.CombatMeter.Init)
    if PP.AshAdvisor.InitRail then PP.safeCall(PP.AshAdvisor.InitRail) end
    -- Class dispatch: load the guide data for whoever is logged in. Modules read
    -- PP.Build; we re-point it to this class's data (falling back to whatever a
    -- data file registered, so nothing nil-errors on an unsupported class).
    PP.class = select(2, UnitClass("player"))
    if PP.Classes[PP.class] then PP.Build = PP.Classes[PP.class] end
    local cname = UnitClass("player") or "?"
    if PP.Classes[PP.class] then
      PP.print("loaded — " .. cname .. " guide active. |cffe0b352/ep|r for the dashboard, "
        .. "|cffe0b352/ep farm|r for missing tomes.")
    else
      PP.print("loaded. No EbonPilot guide for " .. cname .. " yet — the tools still open, "
        .. "but class advice is limited. |cffe0b352/ep|r for the dashboard.")
    end
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

-- One-shot CURRENT snapshot for diagnosis: player stats (HP / mitigation /
-- offense -- the survival data no other scan captures) + gear + ash ranks, in a
-- single /reload. Read by Claude from PallyPilotDB.scans.{snapshot,gear,ashTree}.
function PP.Snapshot()
  PP.db.scans = PP.db.scans or {}
  local out = {}
  local function add(s) out[#out + 1] = s end
  local function num(v) return v and string.format("%.1f", v) or "?" end
  local function estat(i) -- effective attribute (2nd return of UnitStat)
    local ok, _, eff = pcall(UnitStat, "player", i)
    return ok and eff or "?"
  end
  add("level=" .. tostring(UnitLevel("player"))
    .. " class=" .. tostring(select(1, UnitClass("player"))))
  local okhp, hp = pcall(UnitHealthMax, "player")
  add("HPmax=" .. tostring(okhp and hp or "?"))
  add("Strength=" .. tostring(estat(1)) .. " Stamina=" .. tostring(estat(3))
    .. " Intellect=" .. tostring(estat(4)))
  pcall(function()
    local base, pos, neg = UnitAttackPower("player")
    add("AttackPower=" .. tostring((base or 0) + (pos or 0) + (neg or 0)))
  end)
  pcall(function()
    add("SpellPower(Holy)=" .. tostring(GetSpellBonusDamage and GetSpellBonusDamage(2) or "?"))
  end)
  pcall(function() add("MeleeCrit%=" .. num(GetCritChance and GetCritChance())) end)
  pcall(function() add("SpellCrit(Holy)%=" .. num(GetSpellCritChance and GetSpellCritChance(2))) end)
  -- Haste: GetMeleeHaste/UnitSpellHaste return nil on this client, so fall back
  -- to the combat rating (CR_HASTE_MELEE=18, CR_HASTE_SPELL=20). The RATING is
  -- the direct measure of your haste gems; the % is what it converts to now.
  pcall(function()
    local pct = (GetMeleeHaste and GetMeleeHaste())
      or (GetCombatRatingBonus and GetCombatRatingBonus(18))
    local rating = GetCombatRating and GetCombatRating(18)
    add("MeleeHaste%=" .. num(pct) .. " (rating " .. tostring(rating or "?") .. ")")
  end)
  pcall(function()
    local pct = (UnitSpellHaste and UnitSpellHaste("player"))
      or (GetCombatRatingBonus and GetCombatRatingBonus(20))
    local rating = GetCombatRating and GetCombatRating(20)
    add("SpellHaste%=" .. num(pct) .. " (rating " .. tostring(rating or "?") .. ")")
  end)
  pcall(function() add("ExpertiseRating=" .. tostring(GetCombatRating and GetCombatRating(24) or "?")) end)
  pcall(function() add("MeleeHitBonus%=" .. num(GetCombatRatingBonus and GetCombatRatingBonus(6))) end)
  pcall(function()
    local _, eff = UnitArmor("player")
    add("Armor=" .. tostring(eff or "?"))
  end)
  pcall(function() add("Dodge%=" .. num(GetDodgeChance and GetDodgeChance())) end)
  pcall(function() add("Parry%=" .. num(GetParryChance and GetParryChance())) end)
  pcall(function() add("Block%=" .. num(GetBlockChance and GetBlockChance())) end)
  pcall(function() add("BlockValue=" .. tostring(GetShieldBlock and GetShieldBlock() or 0)) end)
  pcall(function() add("Resilience%=" .. num(GetCombatRatingBonus and GetCombatRatingBonus(15))) end)
  pcall(function()
    local rs = {}
    for i = 1, 6 do local _, r = UnitResistance("player", i); rs[#rs + 1] = tostring(r or 0) end
    add("Resist(Holy/Fire/Nature/Frost/Shadow/Arcane)=" .. table.concat(rs, "/"))
  end)
  PP.db.scans.snapshot = out
  PP.db.scans.snapshotTime = date("%Y-%m-%d %H:%M")
  if PP.GearScan then PP.safeCall(PP.GearScan) end
  if PP.AshTreeScan then PP.safeCall(PP.AshTreeScan) end
  PP.print("Snapshot captured: stats + gear + ash ranks. /reload, then tell Claude.")
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

-- The new orb-reroll panel (Use Orbs / Select cards) is transient: triggering a
-- reroll can auto-select and close it before you can type a command. So ARM this
-- first, THEN trigger the reroll -- it polls ~10x/sec for up to 12s and captures
-- the panel the instant its signature buttons ("Use Orbs" / "Select (") are
-- visible. Saves a generic snapshot (scans.ui) plus a deep dump of the panel's
-- top-level frame with data fields (scans.orbUI).
local orbWatcher
function PP.OrbScan()
  PP.db.scans = PP.db.scans or {}
  orbWatcher = orbWatcher or CreateFrame("Frame")
  local elapsed, acc = 0, 0
  local WINDOW = 12
  PP.print("Orb scan ARMED for 12s — now trigger the reroll (bring up the Use Orbs / Select panel).")
  orbWatcher:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    acc = acc + dt
    if acc < 0.1 and elapsed < WINDOW then return end
    acc = 0
    local hit = nil
    local f = EnumerateFrames()
    while f do
      local found = pcall(function()
        if f.IsVisible and f:IsVisible()
           and f.GetObjectType and f:GetObjectType() == "Button" then
          local fs = f.GetFontString and f:GetFontString()
          local label = (fs and fs:GetText()) or (f.GetText and f:GetText()) or nil
          if label then
            local low = string.lower(label)
            if string.find(low, "use orb", 1, true)
               or string.find(low, "select (", 1, true) then
              hit = f
            end
          end
        end
      end)
      if hit then break end
      f = EnumerateFrames(f)
    end
    if hit then
      self:SetScript("OnUpdate", nil)
      -- Generic snapshot of everything visible (names + parents).
      PP.UiScan()
      -- Climb to the panel's top-level frame, then deep-dump it with data fields.
      local root, guard = hit, 0
      while root and root.GetParent and guard < 12 do
        local p = root:GetParent()
        if not p or p == UIParent or p == WorldFrame then break end
        root = p; guard = guard + 1
      end
      local out, n = {}, 0
      local function fieldDump(fr)
        local bits = {}
        for k, v in pairs(fr) do
          local tv = type(v)
          if tv == "string" or tv == "number" or tv == "boolean" then
            bits[#bits + 1] = tostring(k) .. "=" .. tostring(v)
          end
        end
        table.sort(bits); return table.concat(bits, ", ")
      end
      local function walk(fr, depth)
        if depth > 7 or n >= 1500 then return end
        local kids = { fr:GetChildren() }
        for i, c in ipairs(kids) do
          if n >= 1500 then return end
          local okc = pcall(function()
            local ctype = c.GetObjectType and c:GetObjectType() or "?"
            local name = c.GetName and c:GetName() or nil
            local fs = c.GetFontString and c:GetFontString()
            local label = (fs and fs:GetText()) or (c.GetText and c:GetText()) or nil
            n = n + 1
            out[n] = string.rep("  ", depth) .. ctype .. " " .. (name or ("#" .. i))
              .. (label and (" txt=" .. tostring(label)) or "")
              .. (c:IsVisible() and "" or " [hidden]")
            local fd = fieldDump(c)
            if fd ~= "" and n < 1500 then
              n = n + 1
              out[n] = string.rep("  ", depth) .. "   {" .. fd .. "}"
            end
          end)
          if okc then walk(c, depth + 1) end
        end
      end
      out[1] = "PANEL ROOT: " .. ((root.GetName and root:GetName()) or "(anonymous)")
        .. " type=" .. ((root.GetObjectType and root:GetObjectType()) or "?")
      n = 1
      walk(root, 1)
      PP.db.scans.orbUI = out
      PP.db.scans.orbUITime = date("%Y-%m-%d %H:%M")
      PP.print("Captured the ORB panel (" .. n .. " lines). /reload, then tell Claude — no dump needed.")
    elseif elapsed >= WINDOW then
      self:SetScript("OnUpdate", nil)
      PP.print("Orb scan: never saw the panel in 12s. Re-run /pp orbscan, then trigger the reroll during the window.")
    end
  end)
end

-- Deep scan of a server-UI subtree: every child frame with its plain-data
-- fields (node/echo data lives on buttons the way checkpoint data lived on
-- map buttons). rootName + saveKey select the target.
function PP.UiScanTree(rootName, saveKey, hint)
  local root = _G[rootName]
  if not root then
    PP.print(rootName .. " not found — " .. (hint or "open the window first."))
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
  PP.db.scans[saveKey] = out
  PP.db.scans[saveKey .. "Time"] = date("%Y-%m-%d %H:%M")
  PP.print(rootName .. " deep scan: " .. n
    .. " lines captured. /reload to save, then tell Claude.")
end

function PP.UiScanEcho()
  PP.UiScanTree("ProjectEbonholdEchoJournal", "echoUI",
    "open the Echoes window first.")
end

-- Soul Ash tree scan: open the Skill Tree tab, then run this. The tree
-- panel's frame name is unknown, so we dump the whole CollectionsJournal
-- subtree — node buttons carry their data as fields.
function PP.UiScanAsh()
  PP.UiScanTree("CollectionsJournal", "ashUI",
    "open the Collections window (Skill Tree tab) first.")
end

-- Diagnostic: dump the server's echo/perk database to SavedVariables so
-- every echo in the game can be rated into BuildData tiers.
-- Dump the CHARACTER talent trees (the class talents, not the Soul Ash tree).
-- After the 2028-08-27 talent overhaul the baked recommendation is stale; this
-- captures the new trees so a correct Ret template can be rebuilt.
function PP.TalentScan()
  if not GetNumTalentTabs then
    PP.print("Talent API not available on this client.")
    return
  end
  local lines, n = {}, 0
  local tabs = GetNumTalentTabs() or 0
  for tab = 1, tabs do
    local tabName = (GetTalentTabInfo and select(1, GetTalentTabInfo(tab))) or ("Tab" .. tab)
    n = n + 1; lines[n] = "== TAB " .. tab .. ": " .. tostring(tabName) .. " =="
    local num = (GetNumTalents and GetNumTalents(tab)) or 0
    for i = 1, num do
      local name, _, tier, col, rank, maxRank = GetTalentInfo(tab, i)
      if name then
        n = n + 1
        lines[n] = string.format("t%d.i%d  tier%s col%s  %s/%s  %s",
          tab, i, tostring(tier), tostring(col), tostring(rank),
          tostring(maxRank), tostring(name))
      end
    end
  end
  PP.db.scans = PP.db.scans or {}
  PP.db.scans.talents = lines
  PP.db.scans.talentsTime = date("%Y-%m-%d %H:%M")
  PP.print("Talent tree dump: " .. n .. " lines across " .. tabs
    .. " tabs. /reload to save, then tell Claude — I'll rebuild the Ret template.")
end

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

-- Diagnostic: dump the server's Soul Ash tree DB (global TalentDatabase from
-- the ProjectEbonhold addon) with spell names and the advisor's live rank
-- state, so offline analysis can refine node ratings.
function PP.AshTreeScan()
  local db = _G.TalentDatabase
  local tree = db and db[0]
  if not tree or not tree.nodes then
    PP.print("TalentDatabase not found on this client — is the ProjectEbonhold addon loaded?")
    return
  end
  local st = PP.AshAdvisor and PP.AshAdvisor.GetState and PP.AshAdvisor.GetState()
  local ranks = st and st.nodeRanks or {}
  local lines, n = {}, 0
  lines[1] = "tree=" .. tostring(tree.name) .. " nodes=" .. #tree.nodes
    .. (st and (" spendable=" .. tostring(st.spendable)
      .. " committed=" .. tostring(st.committed)
      .. " maxEchoes=" .. tostring(st.maxEchoes)) or " state=none")
  n = 1
  for _, nd in ipairs(tree.nodes) do
    local name = nd.spells and nd.spells[1] and GetSpellInfo(nd.spells[1])
    local costs = {}
    for i, c in ipairs(nd.soulPointsCosts or {}) do costs[i] = tostring(c) end
    n = n + 1
    lines[n] = "node " .. tostring(nd.id) .. " | " .. (name or "?")
      .. " | ranks=" .. (nd.spells and #nd.spells or 0)
      .. " | rank=" .. tostring(ranks[nd.id] or 0)
      .. " | costs=" .. table.concat(costs, "/")
      .. (nd.infinite and (" | INFINITE growth=" .. tostring(nd.infiniteGrowth or 1.15)) or "")
      .. (nd.permanent and " | PERM" or "")
      .. (nd.isStart and " | START" or "")
  end
  PP.db.scans = PP.db.scans or {}
  PP.db.scans.ashTree = lines
  PP.db.scans.ashTreeTime = date("%Y-%m-%d %H:%M")
  PP.print("Soul Ash tree dump: " .. (n - 1)
    .. " nodes. /reload to save, then tell Claude — ratings get refined.")
end

-- Diagnostic: render every perk spell's REAL tooltip text (off-screen) and
-- save it, so the echo catalog can be rated from actual effects, not names.
function PP.EchoTextScan()
  local db = ProjectEbonhold and ProjectEbonhold.PerkDatabase
  if not db then
    PP.print("ProjectEbonhold.PerkDatabase not found.")
    return
  end
  local ids = {}
  for id in pairs(db) do
    if type(id) == "number" then ids[#ids + 1] = id end
  end
  table.sort(ids)
  local tip = PPScanTooltip
    or CreateFrame("GameTooltip", "PPScanTooltip", nil, "GameTooltipTemplate")
  tip:SetOwner(UIParent, "ANCHOR_NONE")
  local out, idx = {}, 0
  local runner = CreateFrame("Frame")
  runner:SetScript("OnUpdate", function(self)
    local batch = 0
    while batch < 25 and idx < #ids do
      idx = idx + 1; batch = batch + 1
      local id = ids[idx]
      tip:ClearLines()
      local ok = pcall(tip.SetHyperlink, tip, "spell:" .. id)
      local parts = {}
      if ok then
        for i = 1, tip:NumLines() do
          local fs = _G["PPScanTooltipTextLeft" .. i]
          local txt = fs and fs:GetText()
          if txt and txt ~= "" then parts[#parts + 1] = txt end
        end
      end
      out[#out + 1] = id .. " || "
        .. (#parts > 0 and table.concat(parts, " | ") or "<no tooltip>")
    end
    if idx >= #ids then
      self:SetScript("OnUpdate", nil)
      PP.db.scans = PP.db.scans or {}
      PP.db.scans.echoText = out
      PP.db.scans.echoTextTime = date("%Y-%m-%d %H:%M")
      PP.print("Echo tooltip dump: " .. #out .. " spells captured. /reload to "
        .. "save, then tell Claude — the catalog gets re-rated from real text.")
    end
  end)
  PP.print("Scanning " .. #ids .. " echo tooltips (a few seconds)...")
end

-- Diagnostic: dump the current run's granted echoes with their QUALITY, so
-- the quality-fish reroll can target sub-Epic stacks. Reads
-- ProjectEbonhold.Perks.grantedPerks and resolves each spellId against
-- PerkDatabase (name + quality). Also captures the orb dialog's slider cap
-- if the Forget window is open. Writes to PallyPilotDB.scans.quality.
function PP.QualityScan()
  local out = {}
  local function add(s) out[#out + 1] = s end
  local db = ProjectEbonhold and ProjectEbonhold.PerkDatabase
  local gp = ProjectEbonhold and ProjectEbonhold.Perks
    and ProjectEbonhold.Perks.grantedPerks
  if not gp then
    add("grantedPerks NOT FOUND (ProjectEbonhold.Perks.grantedPerks nil)")
  else
    local QNAME = { [0] = "Common", [1] = "Uncommon", [2] = "Rare",
                    [3] = "Epic", [4] = "Legendary" }
    local function dumpEntry(prefix, e)
      if type(e) ~= "table" then
        add(prefix .. " = " .. tostring(e)); return
      end
      local bits = {}
      for k, v in pairs(e) do
        local tv = type(v)
        if tv == "string" or tv == "number" or tv == "boolean" then
          bits[#bits + 1] = tostring(k) .. "=" .. tostring(v)
        end
      end
      table.sort(bits)
      -- resolve quality/name from PerkDatabase via spellId if present
      local sid = e.spellId or e.spell or e.id
      local resolved = ""
      if sid and db and db[sid] then
        local d = db[sid]
        resolved = "  || DB: " .. tostring(d.comment or "?")
          .. " q=" .. tostring(d.quality) .. " (" .. (QNAME[d.quality or -1] or "?") .. ")"
      end
      add(prefix .. " { " .. table.concat(bits, ", ") .. " }" .. resolved)
    end
    local n = 0
    for key, value in pairs(gp) do
      n = n + 1
      if type(value) == "table" and value[1] ~= nil then
        for i, e in ipairs(value) do dumpEntry("[" .. tostring(key) .. "][" .. i .. "]", e) end
      else
        dumpEntry("[" .. tostring(key) .. "]", value)
      end
    end
    add("-- grantedPerks keys: " .. n)
  end
  -- Orb dialog slider cap (open the Forget dialog first to capture it).
  local f = EnumerateFrames()
  while f do
    local ok = pcall(function()
      if f.IsVisible and f:IsVisible() and f.GetObjectType and f:GetObjectType() == "Slider"
         and f.GetMinMaxValues then
        local lo, hi = f:GetMinMaxValues()
        if hi and hi > 1 then
          add("SLIDER visible: min=" .. tostring(lo) .. " max=" .. tostring(hi)
            .. " name=" .. tostring(f.GetName and f:GetName() or "?"))
        end
      end
    end)
    if not ok then end
    f = EnumerateFrames(f)
  end
  PP.db.scans = PP.db.scans or {}
  PP.db.scans.quality = out
  PP.db.scans.qualityTime = date("%Y-%m-%d %H:%M")
  PP.print("Quality scan: " .. #out .. " lines (run echoes + qualities). "
    .. "/reload to save, then tell Claude. Open the orb Forget dialog first "
    .. "to also capture the orb slider cap.")
end

SLASH_EBONPILOT1 = "/ep"
SLASH_EBONPILOT2 = "/ebonpilot"
SLASH_EBONPILOT3 = "/pp"          -- back-compat aliases
SLASH_EBONPILOT4 = "/pallypilot"
SlashCmdList["EBONPILOT"] = function(line)
  local _, _, cmd, arg = string.find(line or "", "^%s*(%S*)%s*(.-)%s*$")
  cmd = string.lower(cmd or "")
  if cmd == "" or cmd == "show" then
    if PP.Dashboard.Toggle then PP.Dashboard.Toggle() end
  elseif cmd == "farm" then
    if PP.FarmQueue.Toggle then PP.FarmQueue.Toggle() end
  elseif cmd == "audit" or cmd == "echoes" then
    if PP.EchoAudit.Toggle then PP.EchoAudit.Toggle() end
  elseif cmd == "tomes" or cmd == "tome" then
    -- Reads the real learned-tome collection off the catalog tiles and can
    -- apply the enable/disable toggles for you (attended, level 1 only).
    PP.safeCall(PP.TomeManager.Command, arg)
  elseif cmd == "score" or cmd == "optimize" then
    if PP.BuildScore and PP.BuildScore.Report then PP.safeCall(PP.BuildScore.Report) end
  elseif cmd == "startrun" or cmd == "disable" then
    -- Old command names -> the new tile-based plan. "farm" -> tight pool.
    local a = (arg == "farm") and "tight" or ""
    PP.safeCall(PP.TomeManager.Command, a)
  elseif cmd == "pool" then
    local n = tonumber(arg)
    if n and n >= 60 and n <= 200 then
      PP.db.options.poolSize = n
      PP.print("Enabled-pool target set to " .. n .. ".")
    else
      PP.print("Usage: /pp pool <60-200>  (currently "
        .. (PP.db.options.poolSize or 82) .. ")")
    end
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
    if arg == "echo" then PP.safeCall(PP.UiScanEcho)
    elseif arg == "ash" then PP.safeCall(PP.UiScanAsh)
    else PP.safeCall(PP.UiScan) end
  elseif cmd == "orbscan" then
    PP.safeCall(PP.OrbScan)
  elseif cmd == "snapshot" then
    PP.safeCall(PP.Snapshot)
  elseif cmd == "orbpreview" or cmd == "orb" then
    if PP.EchoFlow and PP.EchoFlow.OrbPreview then PP.safeCall(PP.EchoFlow.OrbPreview) end
  elseif cmd == "ash" then
    if PP.AshAdvisor and PP.AshAdvisor.Command then PP.safeCall(PP.AshAdvisor.Command, arg)
    elseif PP.AshAdvisor and PP.AshAdvisor.Report then PP.safeCall(PP.AshAdvisor.Report) end
  elseif cmd == "ashscan2" then
    PP.safeCall(PP.AshTreeScan)
  elseif cmd == "perkscan" then
    PP.safeCall(PP.PerkScan)
  elseif cmd == "talentscan" then
    PP.safeCall(PP.TalentScan)
  elseif cmd == "qualityscan" then
    PP.safeCall(PP.QualityScan)
  elseif cmd == "echotext" then
    PP.safeCall(PP.EchoTextScan)
  elseif cmd == "run" then
    if arg == "start" then PP.safeCall(PP.RunLog.Start)
    else PP.safeCall(PP.RunLog.Status) end
  elseif cmd == "hubsync" then
    if PP.HubSync.Push then PP.safeCall(PP.HubSync.Push, arg) end
  elseif cmd == "buildcode" or cmd == "export" then
    -- Shareable EBH1 loadout string for this class's curated build.
    if PP.HubSync.ShowExport then PP.safeCall(PP.HubSync.ShowExport) end
  elseif cmd == "locks" then
    local n = tonumber(arg)
    if n and n >= 1 and n <= 12 then
      PP.db.options.lockSlots = n
      PP.print("Permanent echo slots set to " .. n .. " — Lock Now recommends that many.")
    else
      PP.print("Usage: /pp locks <n>  (currently " .. (PP.db.options.lockSlots or 5) .. ")")
    end
  elseif cmd == "gems" or cmd == "enchants" or cmd == "glyphs" or cmd == "gearopt" then
    if PP.GearOpt.Report then PP.safeCall(PP.GearOpt.Report) end
  elseif cmd == "upgrades" or cmd == "upgrade" or cmd == "health" or cmd == "gearhealth" then
    if PP.GearOpt.Upgrades then PP.safeCall(PP.GearOpt.Upgrades) end
  elseif cmd == "gear" then
    if PP.GearAudit.Toggle then PP.GearAudit.Toggle() end
  elseif cmd == "reroll" then
    if PP.EchoFlow.StartReroll then PP.safeCall(PP.EchoFlow.StartReroll) end
  elseif cmd == "qualityfish" or cmd == "fish" then
    if string.lower(arg or "") == "status" then
      if PP.EchoFlow.FishReadout then PP.safeCall(PP.EchoFlow.FishReadout) end
    elseif PP.EchoFlow.StartQualityFish then
      PP.safeCall(PP.EchoFlow.StartQualityFish)
    end
  elseif cmd == "fishstatus" then
    if PP.EchoFlow.FishReadout then PP.safeCall(PP.EchoFlow.FishReadout) end
  elseif cmd == "next" then
    if PP.EchoFlow.ForceNext then PP.safeCall(PP.EchoFlow.ForceNext) end
  elseif cmd == "dps" then
    if PP.CombatMeter.Report then PP.safeCall(PP.CombatMeter.Report) end
  elseif cmd == "buildreport" or cmd == "report" then
    if PP.CombatMeter.BuildReport then PP.safeCall(PP.CombatMeter.BuildReport) end
  elseif cmd == "killed" then
    if arg and arg ~= "" then
      -- Manual seed for kills the tracker missed (e.g. pre-fix kills).
      if PP.CombatMeter.RecordBossKill then
        PP.safeCall(PP.CombatMeter.RecordBossKill, arg)
      end
      return
    end
    local zone = GetRealZoneText()
    local kills = PP.db.kills and PP.db.kills[zone]
    if kills and next(kills) then
      PP.print("Recorded kills in " .. zone .. ":")
      for boss, k in pairs(kills) do
        DEFAULT_CHAT_FRAME:AddMessage("  |cff8aa96a" .. boss .. "|r — " .. (k.when or "?"))
      end
    else
      PP.print("No kills recorded in " .. tostring(zone)
        .. " (tracking started v0.28 — earlier kills weren't captured).")
    end
  elseif cmd == "route" or cmd == "prestige" then
    -- The prestige route runner moved into CallboardHunter, which already owns
    -- the checkpoint port layer and the arrow it depends on. Muscle memory
    -- lands here for a while, so point rather than fail silently.
    PP.print("The route runner lives in CallboardHunter now: use "
      .. "|cffe0b352/cbh route|r." .. (CallboardHunter and "" or
      " (CallboardHunter isn't loaded.)"))
  elseif cmd == "mark" then
    PP.safeCall(PP.Waypoints.Mark, arg)
  elseif cmd == "marks" then
    PP.safeCall(PP.Waypoints.List)
  elseif cmd == "go" then
    if arg == "off" then PP.safeCall(PP.Waypoints.Stop, "Waypoint chain stopped.")
    else PP.safeCall(PP.Waypoints.Go) end
  elseif cmd == "where" then
    SetMapToCurrentZone()
    local x, y = GetPlayerMapPosition("player")
    PP.print("Zone: " .. tostring(GetRealZoneText()) .. " — map position: "
      .. string.format("%.3f, %.3f", x or 0, y or 0)
      .. ((not x or (x == 0 and y == 0)) and " (no coords here — waypoint arrows can't work in this map)" or " (coords WORK here — arrows possible!)"))
  elseif cmd == "bench" then
    local capWord, capNum = string.match(arg, "^(%a+)%s+(%d+)$")
    if arg == "" or arg == "compare" or arg == "report" then
      if PP.CombatMeter.BenchReport then PP.safeCall(PP.CombatMeter.BenchReport) end
    elseif string.lower(arg) == "cap" or (capWord and string.lower(capWord) == "cap") then
      local CM = PP.CombatMeter
      if capNum then
        local applied, dropped, clamped = CM.SetFightCap(capNum)
        if applied then
          local mb = applied * 1750 / 1024 / 1024
          PP.print(string.format("Fight history cap set to %d (~%.2f MB max).%s%s",
            applied,
            mb,
            clamped and string.format(" Clamped to the safe range %d-%d.", CM.FIGHT_CAP_MIN, CM.FIGHT_CAP_MAX) or "",
            dropped > 0 and (" Trimmed " .. dropped .. " oldest fight(s) now.") or ""))
        end
      else
        local cur = CM.FightCap and CM.FightCap() or 1000
        local have = (PP.db.fights and #PP.db.fights) or 0
        PP.print(string.format("Fight history cap: %d  (%d logged now, ~%.2f MB at cap). "
          .. "Set with /pp bench cap <n> (range %d-%d).",
          cur, have, cur * 1750 / 1024 / 1024, CM.FIGHT_CAP_MIN, CM.FIGHT_CAP_MAX))
      end
    elseif arg == "off" then
      PP.db.benchTag = nil
      PP.print("Manual tag cleared — fights auto-tag with your active saved build again.")
    else
      PP.db.benchTag = arg
      PP.db.benchZone = GetRealZoneText()
      PP.print("Manual tag set: '" .. arg .. "' for "
        .. tostring(PP.db.benchZone) .. " — overrides auto build-tagging in this zone. "
        .. "/pp bench compare to compare, /pp bench off for auto.")
    end
  else
    PP.print("/pp (dashboard) | /pp farm | /pp audit | /pp gear (affixes) | /pp gems (enchants/gems/glyphs) | /pp upgrades (gear health) | /pp guide | /pp boss [name] | /pp rotation | /pp talents recommend|guide|auto | /pp ash | /pp dps | /pp bench <name>|off|compare|cap <n>")
  end
end
