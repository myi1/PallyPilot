-- PallyPilot Talents: snapshot your talent build once, then one-click (or auto)
-- re-apply it every run. Because Ebonhold re-levels you from 1 each run, this
-- removes the biggest per-run chore. Matches by tab+index on your own trees.
local PP = PallyPilot
local T = {}
PP.Talents = T

local GOLD = "|cffe0b352"
local R = "|r"

-- Available talent points (3.3.5 API; fall back gracefully).
local function UnspentPoints()
  if GetUnspentTalentPoints then
    local ok, n = pcall(GetUnspentTalentPoints)
    if ok and n then return n end
  end
  local ok, n = pcall(UnitCharacterPoints, "player")
  if ok and n then return n end
  return 0
end

-- Snapshot current talents into the DB: per tab, target rank by index (+names).
function T.Save()
  if not PP.db then return end
  local snap = { tabs = {}, names = {}, total = 0 }
  for tab = 1, GetNumTalentTabs() do
    snap.tabs[tab] = {}
    snap.names[tab] = {}
    for i = 1, GetNumTalents(tab) do
      local name, _, _, _, rank = GetTalentInfo(tab, i)
      snap.tabs[tab][i] = rank or 0
      snap.names[tab][i] = name
      snap.total = snap.total + (rank or 0)
    end
  end
  PP.db.talentBuild = snap
  PP.print("Talent build saved (" .. snap.total .. " points). Use " .. GOLD ..
    "/pp talents apply" .. R .. " to re-apply it, or " .. GOLD .. "/pp talents auto" ..
    R .. " to auto-apply as you level.")
end

-- Spend available points toward the saved build. Multi-pass so tier
-- prerequisites resolve themselves (LearnTalent no-ops when a tier isn't met).
function T.Apply(silent)
  if not (PP.db and PP.db.talentBuild) then
    PP.print("No saved talent build yet — set your talents, then " .. GOLD .. "/pp talents save" .. R .. ".")
    return
  end
  if InCombatLockdown() then
    if not silent then PP.print("Can't change talents in combat.") end
    return
  end
  local build = PP.db.talentBuild
  local spent, blocked = 0, false
  local changed = true
  local guard = 0
  while changed and UnspentPoints() > 0 and guard < 200 do
    changed = false
    guard = guard + 1
    for tab = 1, GetNumTalentTabs() do
      local targets = build.tabs[tab]
      if targets then
        for i = 1, GetNumTalents(tab) do
          local _, _, _, _, rank = GetTalentInfo(tab, i)
          local want = targets[i] or 0
          if (rank or 0) < want and UnspentPoints() > 0 then
            local before = rank or 0
            local ok = pcall(LearnTalent, tab, i)
            if not ok then blocked = true end
            local _, _, _, _, after = GetTalentInfo(tab, i)
            if (after or 0) > before then
              spent = spent + ((after or 0) - before)
              changed = true
            end
          end
        end
      end
    end
  end
  if blocked and spent == 0 then
    PP.print("|cffff5050LearnTalent was blocked on this client|r — open your talent " ..
      "pane and I'll fall back to guiding your clicks (tell me if you see this).")
  elseif spent > 0 then
    if not silent then PP.print("Applied talent build: spent " .. spent .. " point" ..
      (spent == 1 and "" or "s") .. ".") end
  elseif not silent then
    PP.print("Talent build already matches (nothing to spend).")
  end
end

-- Load a baked recommended template into the saved slot (then Apply spends it).
function T.Recommend(key)
  key = (key ~= "" and key) or PP.Build.defaultTemplate
  local tpl = PP.Build.talentTemplates and PP.Build.talentTemplates[key]
  if not tpl then
    PP.print("Unknown template '" .. tostring(key) .. "'. Available: prot-ret.")
    return
  end
  local snap = { tabs = {}, names = {}, total = tpl.total or 0, source = tpl.name }
  for tab = 1, 3 do
    snap.tabs[tab] = {}
    for i, rank in ipairs(tpl.tabs[tab] or {}) do snap.tabs[tab][i] = rank end
  end
  PP.db.talentBuild = snap
  PP.print("Loaded recommended build: " .. GOLD .. tpl.name .. R .. ". Run " ..
    GOLD .. "/pp talents preview" .. R .. " to sanity-check, then " .. GOLD ..
    "/pp talents apply" .. R .. ".")
end

-- Print the saved build's non-zero targets with the LIVE in-game talent names,
-- so you can confirm the indices line up before spending points.
function T.Preview()
  local b = PP.db and PP.db.talentBuild
  if not b then PP.print("No build loaded. Try /pp talents recommend.") return end
  PP.print("Build preview" .. (b.source and (" — " .. b.source) or "") .. ":")
  local tabName = { "Holy", "Protection", "Retribution" }
  for tab = 1, GetNumTalentTabs() do
    local targets = b.tabs[tab]
    if targets then
      local pts = 0
      for _, r in pairs(targets) do pts = pts + r end
      if pts > 0 then
        DEFAULT_CHAT_FRAME:AddMessage(GOLD .. (tabName[tab] or ("Tab " .. tab)) .. " (" .. pts .. ")" .. R)
        for i = 1, GetNumTalents(tab) do
          local want = targets[i] or 0
          if want > 0 then
            local name, _, _, _, rank, maxRank = GetTalentInfo(tab, i)
            DEFAULT_CHAT_FRAME:AddMessage("   " .. tostring(name) .. "  " ..
              (rank or 0) .. "/" .. want .. (maxRank and (" (max " .. maxRank .. ")") or ""))
          end
        end
      end
    end
  end
  PP.print("If those names don't look like a Prot/Ret build, the tree indices differ — tell me and I'll fix the template.")
end

-- Status / next-to-learn readout.
function T.Status()
  if not (PP.db and PP.db.talentBuild) then
    PP.print("No saved talent build. Set talents you like, then " .. GOLD .. "/pp talents save" .. R .. ".")
    return
  end
  local b = PP.db.talentBuild
  PP.print("Saved build: " .. b.total .. " points. Auto-apply: " ..
    ((PP.db.options.autoTalents and "ON") or "OFF") .. ". Unspent now: " .. UnspentPoints() .. ".")
end

-- Auto-apply on level-up (the per-run win). Deferred out of combat.
local pending = false
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
  if not (PP.db and PP.db.options.autoTalents and PP.db.talentBuild) then return end
  if event == "PLAYER_LEVEL_UP" then
    if InCombatLockdown() then pending = true else PP.safeCall(T.Apply, true) end
  elseif event == "PLAYER_REGEN_ENABLED" and pending then
    pending = false
    PP.safeCall(T.Apply, true)
  end
end)

-- Slash sub-command dispatch, called from Core.
function T.Command(arg)
  arg = string.lower(arg or "")
  local sub, rest = string.match(arg, "^(%S*)%s*(.-)$")
  if sub == "save" then T.Save()
  elseif sub == "recommend" or sub == "rec" then T.Recommend(rest)
  elseif sub == "preview" then T.Preview()
  elseif sub == "apply" then T.Apply(false)
  elseif sub == "auto" then
    PP.db.options.autoTalents = not PP.db.options.autoTalents
    PP.print("Auto-apply talents on level-up: " .. (PP.db.options.autoTalents and "ON" or "OFF")
      .. (PP.db.options.autoTalents and (PP.db.talentBuild and "" or " (save/recommend a build first!)") or ""))
  elseif sub == "clear" then
    PP.db.talentBuild = nil
    PP.print("Saved talent build cleared.")
  else
    T.Status()
    PP.print(GOLD .. "/pp talents recommend|preview|apply|save|auto|clear" .. R)
  end
end
