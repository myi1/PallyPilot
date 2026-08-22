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

-- Build a live index of the current trees: normalized talent name ->
-- { tab, index, maxRank }. Names are unique across paladin trees.
local function LiveIndex()
  local idx = {}
  if not (GetNumTalentTabs and GetTalentInfo) then return idx end
  for tab = 1, GetNumTalentTabs() do
    for i = 1, GetNumTalents(tab) do
      local name, _, _, _, _, maxRank = GetTalentInfo(tab, i)
      if name then idx[string.lower(name)] = { tab = tab, index = i, maxRank = maxRank or 0 } end
    end
  end
  return idx
end

-- A saved build is a name -> desired-rank map (order/index proof).
-- Snapshot current talents into that shape.
function T.Save()
  if not PP.db then return end
  local talents, total = {}, 0
  for tab = 1, GetNumTalentTabs() do
    for i = 1, GetNumTalents(tab) do
      local name, _, _, _, rank = GetTalentInfo(tab, i)
      if name and (rank or 0) > 0 then talents[name] = rank; total = total + rank end
    end
  end
  PP.db.talentBuild = { talents = talents, total = total, source = "Your saved build" }
  PP.print("Talent build saved (" .. total .. " points). " .. GOLD .. "/pp talents apply" ..
    R .. " to re-apply, or " .. GOLD .. "/pp talents auto" .. R .. " to auto-apply as you level.")
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
  local wants = PP.db.talentBuild.talents or {}
  local spent, blocked = 0, 0
  -- Multi-pass: one LearnTalent attempt per under-target talent per pass. Do
  -- NOT gate on GetUnspentTalentPoints (unreliable on this client); instead
  -- stop when a whole pass changes no rank (out of points OR fully applied).
  local changed = true
  local guard = 0
  while changed and guard < 400 do
    changed = false
    guard = guard + 1
    local live = LiveIndex()  -- ranks/maxrank refresh as we spend
    for name, want in pairs(wants) do
      local loc = live[string.lower(name)]
      if loc then
        local _, _, _, _, rank = GetTalentInfo(loc.tab, loc.index)
        local target = math.min(want, loc.maxRank)
        if (rank or 0) < target then
          local before = rank or 0
          local ok = pcall(LearnTalent, loc.tab, loc.index)
          local _, _, _, _, after = GetTalentInfo(loc.tab, loc.index)
          if (after or 0) > before then
            spent = spent + ((after or 0) - before)
            changed = true
          elseif not ok then
            blocked = blocked + 1
          end
        end
      end
    end
  end
  if not silent then
    PP.print("Applied build: spent " .. GOLD .. spent .. R .. " point" .. (spent == 1 and "" or "s")
      .. ". Unspent now: " .. UnspentPoints() .. "."
      .. (spent == 0 and " |cffff5050(LearnTalent appears blocked — tell me and I'll add a guided click-mode.)|r" or ""))
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
  local talents, total = {}, 0
  for name, rank in pairs(tpl.talents or {}) do talents[name] = rank; total = total + rank end
  PP.db.talentBuild = { talents = talents, total = total, source = tpl.name }
  PP.print("Loaded " .. GOLD .. tpl.name .. R .. " (" .. total .. " pts of targets). " ..
    GOLD .. "/pp talents preview" .. R .. " to check, then " .. GOLD .. "/pp talents apply" .. R .. ".")
end

-- Print the saved build's non-zero targets with the LIVE in-game talent names,
-- so you can confirm the indices line up before spending points.
function T.Preview()
  local b = PP.db and PP.db.talentBuild
  if not b then PP.print("No build loaded. Try /pp talents recommend.") return end
  PP.print("Build preview" .. (b.source and (" — " .. b.source) or "") .. ":")
  local live = LiveIndex()
  local tabName = { "Holy", "Protection", "Retribution" }
  local byTab, missing = { {}, {}, {} }, {}
  for name, want in pairs(b.talents or {}) do
    local loc = live[string.lower(name)]
    if loc then
      table.insert(byTab[loc.tab], { name = name, want = math.min(want, loc.maxRank),
        rank = select(5, GetTalentInfo(loc.tab, loc.index)) or 0 })
    else
      missing[#missing + 1] = name
    end
  end
  for tab = 1, 3 do
    if #byTab[tab] > 0 then
      table.sort(byTab[tab], function(a, b2) return a.name < b2.name end)
      DEFAULT_CHAT_FRAME:AddMessage(GOLD .. (tabName[tab] or ("Tab " .. tab)) .. R)
      for _, e in ipairs(byTab[tab]) do
        DEFAULT_CHAT_FRAME:AddMessage("   " .. e.name .. "  " .. e.rank .. "/" .. e.want)
      end
    end
  end
  if #missing > 0 then
    PP.print("|cffff5050Not found in your tree (name mismatch):|r " .. table.concat(missing, ", "))
  else
    PP.print("All template talents matched your tree. /pp talents apply to spend.")
  end
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
