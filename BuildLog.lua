-- EbonPilot BuildLog: reliable comparison BETWEEN saved builds.
--
-- THE CONSTRAINT that shapes this: the server will not let an addon read a
-- saved build's CONTENTS without activating it. So a live side-by-side of all
-- your builds is impossible. Instead we fingerprint whichever build is active
-- and keep the history, so after you have worn each build once you can compare
-- them properly.
--
-- Two kinds of "better", and they are NOT the same:
--   MEASURED  -- real DPS from logged fights, auto-tagged by build. Ground truth.
--   COMPOSITION -- score, tier counts, what is missing. A prediction.
-- The report shows both side by side, and says plainly when a build has no
-- measured fights yet -- an unmeasured build is a guess, however good it looks.
local PP = PallyPilot
local BL = {}
PP.BuildLog = BL

local GOLD = "|cffe0b352"
local BRIGHT = "|cfff6d888"
local DIM = "|cffb4a586"
local EMBER = "|cffd9694a"
local VERD = "|cff8aa96a"
local R = "|r"

local function num(v) return v and string.format("%.1f", v) or "?" end
local function K(n)
  if not n or n == 0 then return "-" end
  if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
  if n >= 1000 then return string.format("%.0fk", n / 1000) end
  return tostring(math.floor(n))
end

-- Live power numbers -- the same reads the snapshot uses.
local function PowerNow()
  local p = {}
  pcall(function() p.hp = UnitHealthMax("player") end)
  pcall(function() p.crit = GetCritChance and GetCritChance() end)
  pcall(function()
    p.haste = (GetMeleeHaste and GetMeleeHaste())
      or (GetCombatRatingBonus and GetCombatRatingBonus(18))
  end)
  pcall(function()
    local b, pos, neg = UnitAttackPower("player")
    p.ap = (b or 0) + (pos or 0) + (neg or 0)
  end)
  pcall(function() p.sp = GetSpellBonusDamage and GetSpellBonusDamage(2) end)
  return p
end

-- Measured DPS for a build, joined from the tagged fight log.
-- NOTE the fight log is tagged by the SKILL-TREE loadout name, which is a
-- coarser bucket than an echo set -- so this can under-attribute. Shown as
-- measured only when it matches; never invented.
local function Measured(key, name)
  local best, sum, n = 0, 0, 0
  for _, f in ipairs((PP.db and PP.db.fights) or {}) do
    -- ID is authoritative when BOTH sides have one; name matching is ONLY the
    -- legacy fallback for fights logged before ids existed. The old `id-match
    -- OR name-match` let two different builds sharing a label inherit each
    -- other's DPS (Codex-review finding).
    local match
    if f.buildId and key then match = (f.buildId == key)
    else match = (f.build ~= nil and f.build == name) end
    if match and f.dps and (f.dur or 0) >= 10 then
      n = n + 1; sum = sum + f.dps
      if f.dps > best then best = f.dps end
    end
  end
  if n == 0 then return nil end
  return { n = n, avg = sum / n, best = best }
end

-- The run's actual echo list, and a stable key derived from it.
-- WHY CONTENT AND NOT NAME: AshAdvisor.ActiveBuild() reports the SKILL-TREE
-- loadout (it parses SEND_LOADOUTS, whose payload is node:rank pairs), which is
-- almost always "Default" -- so keying on it made every capture overwrite the
-- same row. The echoes themselves are the only identity we can read reliably.
--
-- IDENTITY SOURCE (Codex-review fix): CollectOwnedSets, NOT grantedPerks.
-- grantedPerks OMITS LOCKED ECHOES and its keys carry quality suffixes -- so
-- the old fingerprint (a) merged builds that differ only by locks, and (b)
-- CHANGED whenever quality-fishing upgraded a stack, splitting one build into
-- a trail of duplicate records that never accumulate fights. Names are
-- normalized (curly apostrophes, quality suffixes stripped) and deduped so the
-- identity is what the build IS, not how it is currently polished.
local function Norm(s)
  return (string.lower(s or ""):gsub("\226\128\153", "'"))
end
local QUAL_SUFFIX = { "common", "uncommon", "rare", "epic", "legendary", "artifact" }
local function StripQ(s)
  for _, q in ipairs(QUAL_SUFFIX) do
    local cut = s:match("^(.-)%s*%-%s*" .. q .. "$")
    if cut then return cut end
  end
  return s
end

local function RunEchoes()
  if not (EbonholdHub and EbonholdHub.EchoOwnership
          and EbonholdHub.EchoOwnership.CollectOwnedSets) then return nil end
  local ok, owned = pcall(EbonholdHub.EchoOwnership.CollectOwnedSets)
  if not (ok and type(owned) == "table") then return nil end
  local seen, list = {}, {}
  for lower in pairs(owned) do
    local base = StripQ(Norm(lower))
    if base ~= "" and not seen[base] then
      seen[base] = true
      list[#list + 1] = base
    end
  end
  table.sort(list)
  return list
end

local function SigOf(list)
  -- Two independent rolling checksums + count. Collisions are further guarded
  -- at the store: each record keeps its full name string (rec.sig) and a
  -- mismatch probes to a fresh key instead of overwriting a different build.
  local a, b = 0, 0
  for i, s in ipairs(list) do
    for c = 1, #s do
      local v = s:byte(c)
      a = (a + v * (i % 7 + 1)) % 2147483647
      b = (b * 31 + v) % 1000000007
    end
  end
  return string.format("c%d_%d_%d", #list, a, b)
end

-- The ECHO build's real name, off the journal's loadout dropdown
-- (ProjectEbonholdEchoJournalLoadoutDD, found via the UI frame scan). This is
-- the "push 2" you pick from -- NOT AshAdvisor.ActiveBuild(), which reports the
-- skill-tree loadout and is almost always "Default". Tries the three ways a
-- 3.3.5 dropdown can expose its label, rather than betting on one.
local DD = "ProjectEbonholdEchoJournalLoadoutDD"
local function LoadoutName()
  local dd = _G[DD]
  if not dd then return nil end
  local txt
  if UIDropDownMenu_GetText then
    local ok, v = pcall(UIDropDownMenu_GetText, dd)
    if ok and type(v) == "string" then txt = v end
  end
  if not txt or txt == "" then
    local fs = _G[DD .. "Text"]
    if fs and fs.GetText then txt = fs:GetText() end
  end
  if (not txt or txt == "") and dd.GetRegions then
    for _, rgn in ipairs({ dd:GetRegions() }) do
      if rgn and rgn.GetObjectType and rgn:GetObjectType() == "FontString" then
        local t = rgn:GetText()
        if t and t ~= "" then txt = t; break end
      end
    end
  end
  if not txt then return nil end
  txt = txt:gsub("^%s+", ""):gsub("%s+$", "")
  -- Placeholder labels aren't names.
  local low = string.lower(txt)
  if txt == "" or low == "select a loadout" or low == "none" then return nil end
  return txt
end

-- Stable id + display name for whatever build is live RIGHT NOW. Public so the
-- combat meter can stamp each fight with the same identity the comparison uses.
-- Resolve the storage key for an identity: same checksum + same name string =
-- same build; a checksum collision with a DIFFERENT name string probes to a
-- fresh key instead of silently merging two builds into one record.
local function KeyFor(echoes)
  local key = SigOf(echoes)
  local sig = table.concat(echoes, ";")
  local logt = PP.db and PP.db.buildLog
  while logt and logt[key] and logt[key].sig and logt[key].sig ~= sig do
    key = key .. "x"
  end
  return key, sig
end

function BL.CurrentKey()
  local echoes = RunEchoes()
  if not echoes or #echoes == 0 then return nil end
  local key = KeyFor(echoes)
  local rec = PP.db and PP.db.buildLog and PP.db.buildLog[key]
  local name = (rec and (rec.userName or rec.name)) or LoadoutName()
    or (#echoes .. " echoes #" .. string.sub(key, -3))
  return key, name
end

-- Fingerprint the ACTIVE build. Cheap enough to run on every build swap.
function BL.Capture(reason)
  if not PP.db then return end
  local echoes = RunEchoes()
  if not echoes or #echoes == 0 then
    PP.print("No run loaded -- can't fingerprint a build (need level 80, in a run).")
    return
  end
  local key, sig = KeyFor(echoes)

  -- Name priority: what you called it (/ep builds name X) > the loadout
  -- dropdown's real label > a short stable stand-in. Never the skill-tree name.
  local prev = PP.db.buildLog and PP.db.buildLog[key]
  local name = (prev and prev.userName)
    or LoadoutName()
    or (prev and prev.name)
    or (#echoes .. " echoes #" .. string.sub(key, -3))

  -- rec.sig (the full normalized name string) is the collision guard AND the
  -- future A-vs-B differ; the raw echo LIST is deliberately not stored -- at
  -- ~80 names per capture it was pure SavedVariables bloat.
  local rec = { name = name, userName = prev and prev.userName, id = key,
                sig = sig, n = #echoes, when = date("%Y-%m-%d %H:%M"), why = reason }

  local ok, r = pcall(function() return PP.BuildScore and PP.BuildScore.Compute() end)
  if ok and r then
    rec.score, rec.grade = r.score, r.grade
    rec.filled, rec.slots = r.filled, r.slots
    rec.owned, rec.universe, rec.missing = r.owned, r.universe, r.missing
    rec.qTotal, rec.qSub = r.qTotal, r.qSub
    rec.junkOn, rec.keepersOff = r.junkOn, r.keepersOff
  end

  local okb, buckets = pcall(function() return select(1, PP.EchoAudit.Compute()) end)
  if okb and buckets then
    rec.core = buckets.CORE and #buckets.CORE or nil
    rec.S = buckets.S and #buckets.S or nil
    rec.A = buckets.A and #buckets.A or nil
    rec.B = buckets.B and #buckets.B or nil
  end

  local oks, st = pcall(function() return PP.EchoAudit.FishStatus() end)
  if oks and st then rec.uniques = st.uniques end

  -- What this build is MISSING: owned tomes, rated, but not drafted in it.
  local okw, want = pcall(function() return PP.EchoAudit.WantList() end)
  if okw and want then
    rec.missingN = #want
    local top = {}
    for i = 1, math.min(#want, 4) do top[#top + 1] = want[i].tier .. " " .. want[i].name end
    rec.missingTop = table.concat(top, ", ")
  end

  rec.power = PowerNow()
  PP.db.buildLog = PP.db.buildLog or {}
  PP.db.buildLog[key] = rec
  return rec
end

-- Side-by-side of every build we've fingerprinted.
function BL.Report()
  local log = PP.db and PP.db.buildLog
  if not log or not next(log) then
    PP.print("No builds captured yet. A build is fingerprinted whenever you "
      .. "APPLY it -- swap between your saved builds once each, then run this again. "
      .. GOLD .. "/ep builds now" .. R .. " captures the active one immediately.")
    return
  end
  local rows = {}
  for key, r in pairs(log) do
    r._key = key
    r._m = Measured(r.id, r.name)
    rows[#rows + 1] = r
  end
  -- Measured builds first (ground truth), best avg DPS on top; then by score.
  table.sort(rows, function(a, b)
    if (a._m ~= nil) ~= (b._m ~= nil) then return a._m ~= nil end
    if a._m and b._m then return a._m.avg > b._m.avg end
    return (a.score or 0) > (b.score or 0)
  end)

  PP.print(GOLD .. "BUILD COMPARISON" .. R .. DIM .. "  (" .. #rows .. " captured)" .. R)
  for i, r in ipairs(rows) do
    local head = BRIGHT .. i .. ". " .. r.name .. R
    if r.score then head = head .. DIM .. "  score " .. R .. r.score .. "/100 (" .. (r.grade or "?") .. ")" end
    DEFAULT_CHAT_FRAME:AddMessage(head)

    -- MEASURED first: this is the only line that is evidence rather than theory.
    if r._m then
      DEFAULT_CHAT_FRAME:AddMessage("     " .. VERD .. "measured " .. R
        .. "avg " .. BRIGHT .. K(r._m.avg) .. R .. " dps, best " .. K(r._m.best)
        .. DIM .. "  over " .. r._m.n .. " fight" .. (r._m.n == 1 and "" or "s") .. R)
    else
      DEFAULT_CHAT_FRAME:AddMessage("     " .. EMBER .. "NOT MEASURED" .. R .. DIM
        .. " -- no logged fights on this build; everything below is prediction." .. R)
    end

    local comp = {}
    if r.core then comp[#comp + 1] = r.core .. " core" end
    if r.S then comp[#comp + 1] = r.S .. " S" end
    if r.A then comp[#comp + 1] = r.A .. " A" end
    if r.B then comp[#comp + 1] = r.B .. " B" end
    if r.uniques then comp[#comp + 1] = r.uniques .. " uniques (+" .. r.uniques .. "% Adaptive)" end
    if #comp > 0 then
      DEFAULT_CHAT_FRAME:AddMessage("     " .. DIM .. "has:  " .. R .. table.concat(comp, " · "))
    end

    local gaps = {}
    if r.missingN and r.missingN > 0 then gaps[#gaps + 1] = r.missingN .. " draftable not taken" end
    if r.qSub and r.qSub > 0 then gaps[#gaps + 1] = r.qSub .. " keeper(s) sub-Epic" end
    if r.junkOn and r.junkOn > 0 then gaps[#gaps + 1] = r.junkOn .. " junk enabled" end
    if r.filled and r.slots then gaps[#gaps + 1] = "locks " .. r.filled .. "/" .. r.slots end
    if #gaps > 0 then
      DEFAULT_CHAT_FRAME:AddMessage("     " .. DIM .. "gaps: " .. R .. table.concat(gaps, " · "))
    end
    if r.missingTop and r.missingTop ~= "" then
      DEFAULT_CHAT_FRAME:AddMessage("     " .. DIM .. "want: " .. r.missingTop .. R)
    end

    local p = r.power or {}
    DEFAULT_CHAT_FRAME:AddMessage("     " .. DIM .. "power: " .. R
      .. K(p.hp) .. " hp · " .. num(p.crit) .. "% crit · " .. num(p.haste) .. "% haste · "
      .. K(p.ap) .. " ap · " .. K(p.sp) .. " sp"
      .. DIM .. "   [" .. (r.when or "?") .. "]" .. R)
  end

  local anyMeasured = false
  for _, r in ipairs(rows) do if r._m then anyMeasured = true break end end
  if not anyMeasured then
    PP.print(EMBER .. "None of these have logged fights." .. R .. DIM .. " Composition "
      .. "score predicts; it does not measure. Run the same fight on each build "
      .. "(" .. R .. GOLD .. "/ep bench <tag>" .. R .. DIM .. " or just fight for 10s+) "
      .. "and compare again -- that is the number that settles it." .. R)
  end
end

-- ---------------------------------------------------------------------------
-- PANEL. Chat output is fine for a glance but useless for comparing, so this is
-- the real interface: one card per build, ranked, with MEASURED dps drawn as a
-- bar you can compare by LENGTH (never colour alone -- and every state is also
-- spelled out as a word, because colour carries no meaning here).
local frame, content, rows = nil, nil, {}
local WHITE = "Interface\\Buttons\\WHITE8X8"

-- COLUMN TABLE, not stacked cards: the whole point is comparing the SAME metric
-- across builds, which only works if they line up on one row. Label column on
-- the left, one column per build, best value in each row marked with a ">"
-- prefix (a symbol, never colour alone).
local LABEL_W, COL_W = 104, 106
local function GetRow(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Frame", nil, content)
  r:SetWidth(430); r:SetHeight(14)
  r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.label:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
  r.label:SetWidth(LABEL_W); r.label:SetJustifyH("LEFT")
  r.cells = {}
  for c = 1, 3 do
    local f = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f:SetPoint("TOPLEFT", r, "TOPLEFT", LABEL_W + (c - 1) * COL_W, 0)
    f:SetWidth(COL_W - 4); f:SetJustifyH("LEFT")
    r.cells[c] = f
  end
  rows[i] = r
  return r
end

function BL.Refresh()
  if not (frame and content) then return end
  local log = PP.db and PP.db.buildLog
  local list = {}
  for key, r in pairs(log or {}) do
    r._key = key; r._m = Measured(r.id, r.name); list[#list + 1] = r
  end
  table.sort(list, function(a, b)
    if (a._m ~= nil) ~= (b._m ~= nil) then return a._m ~= nil end
    if a._m and b._m then return a._m.avg > b._m.avg end
    return (a.score or 0) > (b.score or 0)
  end)


  if #list == 0 then
    frame.verdict:SetText(DIM .. "Nothing captured yet" .. R)
    frame.hint:SetText(DIM .. "A build is fingerprinted automatically whenever you "
      .. "APPLY it -- swap between your saved builds once each." .. R)
  else
    -- SAY WHICH ONE. A table of numbers isn't an answer to "which is better".
    local m = 0
    for _, r in ipairs(list) do if r._m then m = m + 1 end end
    -- Verdict (focal) and its caveat live on separate lines with separate
    -- weights, so the answer reads at a glance and the hedge doesn't dilute it.
    local top = list[1]
    if m > 0 then
      frame.verdict:SetText(VERD .. "Best: " .. R .. BRIGHT .. (top.name or "?") .. R)
      frame.hint:SetText(DIM .. "Highest measured dps -- " .. R .. BRIGHT
        .. K(top._m.avg) .. R .. DIM .. " avg over " .. top._m.n .. " fights. "
        .. "Evidence, not a guess." .. R
        .. "\n" .. DIM .. #list .. " captured · showing " .. math.min(#list, 3) .. R)
    else
      local why = {}
      if top.S then why[#why + 1] = top.S .. " S-tier" end
      if top.uniques then why[#why + 1] = "+" .. top.uniques .. "% Adaptive" end
      frame.verdict:SetText(BRIGHT .. "Likely best: " .. (top.name or "?") .. R
        .. (#why > 0 and (DIM .. "  " .. table.concat(why, ", ") .. R) or ""))
      frame.hint:SetText(EMBER .. "Nothing here is measured." .. R .. DIM
        .. " Fight 10s+ on two builds and the real answer replaces this guess." .. R
        .. "\n" .. DIM .. #list .. " captured · showing " .. math.min(#list, 3) .. R)
    end
  end

  -- Anchor the table under the header, whose height depends on how far the
  -- verdict and caveat wrapped. Fixed offsets here are what caused the overlap.
  if frame.scroll then
    local top = 16 + (frame.verdict:GetStringHeight() or 14) + 6
                   + (frame.hint:GetStringHeight() or 26) + 14
    frame.scroll:ClearAllPoints()
    frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -top)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 14)
  end

  for _, r in ipairs(rows) do r:Hide() end
  -- Only three columns fit legibly; show the top three and say so.
  local show = {}
  for i = 1, math.min(#list, 3) do show[i] = list[i] end

  -- Each metric: how to read it off a record, and whether higher is better
  -- (nil = don't mark a winner, it isn't a contest).
  -- Grouped, because 13 evenly-spaced rows read as one undifferentiated block.
  -- Tight inside a group (13px), real air between groups (+10px) -- so "these
  -- belong together" is carried by rhythm instead of by reading every label.
  -- `g` starts a new group.
  local METRICS = {
    { "",          function(b) return b._m and (VERD .. "MEASURED" .. R)
                                           or (EMBER .. "PREDICTED" .. R) end },
    { "dps avg",   function(b) return b._m and K(b._m.avg) or (DIM .. "-" .. R) end,
                   function(b) return b._m and b._m.avg or nil end },
    { "dps best",  function(b) return b._m and K(b._m.best) or (DIM .. "-" .. R) end,
                   function(b) return b._m and b._m.best or nil end },

    { "score",     function(b) return b.score and (b.score .. " " .. (b.grade or "")) or "-" end,
                   function(b) return b.score end, g = "BUILD" },
    { "core",      function(b) return b.core or "-" end, function(b) return b.core end },
    { "S",         function(b) return b.S or "-" end, function(b) return b.S end },
    { "A",         function(b) return b.A or "-" end, function(b) return b.A end },
    { "uniques",   function(b) return b.uniques and ("+" .. b.uniques .. "%") or "-" end,
                   function(b) return b.uniques end },
    { "not taken", function(b) return b.missingN or "-" end,
                   function(b) return b.missingN and -b.missingN or nil end },
    { "sub-Epic",  function(b) return b.qSub or "-" end,
                   function(b) return b.qSub and -b.qSub or nil end },
    { "locks",     function(b) return (b.filled and b.slots)
                     and (b.filled .. "/" .. b.slots) or "-" end,
                   function(b) return b.filled end },

    { "hp",        function(b) return K((b.power or {}).hp) end,
                   function(b) return (b.power or {}).hp end, g = "STATS" },
    { "crit",      function(b) return num((b.power or {}).crit) .. "%" end,
                   function(b) return (b.power or {}).crit end },
    { "haste",     function(b) return num((b.power or {}).haste) .. "%" end,
                   function(b) return (b.power or {}).haste end },
    { "ap",        function(b) return K((b.power or {}).ap) end,
                   function(b) return (b.power or {}).ap end },
    { "sp",        function(b) return K((b.power or {}).sp) end,
                   function(b) return (b.power or {}).sp end },
  }

  -- PRUNE THE TABLE. Two rules, both about respecting attention:
  --  1. Drop dps rows entirely when nothing is measured -- empty rows read as
  --     "broken", not "no data", and the hint already says so.
  --  2. Drop any row where every shown build has the SAME value. A row of three
  --     identical numbers teaches nothing; the differences are the whole point.
  local anyMeasured = false
  for _, b in ipairs(show) do if b._m then anyMeasured = true break end end
  local pruned, pendingGroup = {}, nil
  for _, m in ipairs(METRICS) do
    local isDps = (m[1] == "dps avg" or m[1] == "dps best")
    if isDps and not anyMeasured then
      -- skip
    else
      local first, differs = nil, false
      for i, b in ipairs(show) do
        local v = tostring(m[2](b))
        if i == 1 then first = v elseif v ~= first then differs = true end
      end
      -- Always keep the state row; keep others only when they differ.
      if m[1] == "" or differs or #show < 2 then
        -- A pruned row must not take its group heading with it: hand any
        -- pending label to the next row that actually survives.
        if pendingGroup then m = setmetatable({ m[1], m[2], m[3], g = pendingGroup },
                                              { __index = m }) end
        pendingGroup = nil
        pruned[#pruned + 1] = m
      elseif m.g then
        pendingGroup = pendingGroup or m.g
      end
    end
  end
  METRICS = pruned

  local y, n = 0, 0
  -- Header row: build names.
  n = n + 1
  local hr = GetRow(n)
  hr:ClearAllPoints(); hr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
  hr.label:SetText(GOLD .. "metric" .. R)
  -- Two saved builds can carry the same label ("pp new" twice) while being
  -- different echo sets. Suffix the duplicates so the columns are tellable apart.
  local nameCount = {}
  for _, b in ipairs(show) do
    nameCount[b.name or "?"] = (nameCount[b.name or "?"] or 0) + 1
  end
  local nameSeen = {}
  for c = 1, 3 do
    local b = show[c]
    if b then
      local nm = b.name or "?"
      if (nameCount[nm] or 0) > 1 then
        nameSeen[nm] = (nameSeen[nm] or 0) + 1
        nm = nm .. " #" .. nameSeen[nm]
      end
      hr.cells[c]:SetText(BRIGHT .. string.sub(nm, 1, 14) .. R)
    else hr.cells[c]:SetText("") end
  end
  hr:Show(); y = y + 18

  for _, m in ipairs(METRICS) do
    -- Air BEFORE a new group, plus a quiet label. Grouping is carried by
    -- rhythm; the label is only there to name what the gap already separated.
    if m.g then
      y = y + 10
      n = n + 1
      local gr = GetRow(n)
      gr:ClearAllPoints(); gr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
      gr.label:SetText("|cff85817a" .. m.g .. "|r")
      for c = 1, 3 do gr.cells[c]:SetText("") end
      gr:Show(); y = y + 15
    end
    n = n + 1
    local r = GetRow(n)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    r.label:SetText(DIM .. m[1] .. R)
    -- Find the winner for this row, if the metric has a direction.
    local bestV, bestI = nil, nil
    if m[3] then
      for c, b in ipairs(show) do
        local v = m[3](b)
        if v and (bestV == nil or v > bestV) then bestV, bestI = v, c end
      end
    end
    for c = 1, 3 do
      local b = show[c]
      if b then
        local txt = tostring(m[2](b))
        -- ">" marks the best in the row: a SYMBOL, readable without colour.
        r.cells[c]:SetText((bestI == c and #show > 1) and (VERD .. "> " .. R .. txt)
          or ("  " .. txt))
      else r.cells[c]:SetText("") end
    end
    r:Show(); y = y + 13
  end
  content:SetHeight(math.max(10, y + 4))

end

function BL.Init2()
  if frame then return end
  frame = CreateFrame("Frame", "EbonPilotBuildsFrame", UIParent)
  frame:SetWidth(480); frame:SetHeight(560)
  frame:SetPoint("CENTER", UIParent, "CENTER", -30, 0)
  frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  frame:SetBackdropColor(0.086, 0.078, 0.067, 0.96)
  frame:SetBackdropBorderColor(1, 1, 1, 0.12)

  -- No panel title: the shell's breadcrumb already says "Builds". A second
  -- heading two lines below the first is the most common way a panel wastes its
  -- most valuable space. That space goes to the VERDICT instead -- the focal
  -- element, and the only line here that answers the question.
  frame.verdict = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.verdict:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -16)
  frame.verdict:SetWidth(300); frame.verdict:SetJustifyH("LEFT")

  frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -38)
  -- 300 wide, not 430: the Capture button occupies the right edge and the old
  -- width ran the text underneath it.
  frame.hint:SetWidth(300); frame.hint:SetJustifyH("LEFT"); frame.hint:SetSpacing(2)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
  frame.ppClose = close

  local cap = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  cap:SetWidth(110); cap:SetHeight(22)
  cap:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -32, -16)
  cap:SetText("Capture now")
  cap:SetScript("OnClick", function()
    PP.safeCall(BL.Capture, "manual"); PP.safeCall(BL.Refresh)
  end)

  local scroll = CreateFrame("ScrollFrame", "EbonPilotBuildsScroll", frame,
    "UIPanelScrollFrameTemplate")
  frame.scroll = scroll          -- Refresh re-anchors under the header block
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -84)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 14)
  content = CreateFrame("Frame", nil, scroll)
  content:SetWidth(430); content:SetHeight(10)
  scroll:SetScrollChild(content)
  frame:Hide()
end

function BL.GetFrame()
  if not frame then BL.Init2() end
  return frame
end

function BL.Command(arg)
  arg = string.lower(arg or "")
  if arg == "now" or arg == "capture" then
    local r = BL.Capture("manual")
    if r then PP.print("Captured " .. BRIGHT .. r.name .. R
      .. (r.score and (" -- score " .. r.score .. "/100") or "") .. ".")
    else PP.print("Couldn't read the active build.") end
  elseif string.sub(arg, 1, 5) == "name " then
    -- Manual label for the ACTIVE build, in case the dropdown can't be read.
    local label = string.sub(arg, 6):gsub("^%s+", ""):gsub("%s+$", "")
    local echoes = RunEchoes()
    if not echoes or label == "" then
      PP.print("Usage (with the run loaded): " .. GOLD .. "/ep builds name My Build" .. R)
      return
    end
    local key, sig = KeyFor(echoes)
    PP.db.buildLog = PP.db.buildLog or {}
    PP.db.buildLog[key] = PP.db.buildLog[key] or { sig = sig }
    PP.db.buildLog[key].userName = label
    PP.db.buildLog[key].name = label
    PP.print("This build is now called " .. BRIGHT .. label .. R .. ".")
    PP.safeCall(BL.Refresh)
  elseif arg == "clear" then
    PP.db.buildLog = nil
    PP.print("Build comparison history cleared.")
  else
    BL.Report()
  end
end

-- Auto-capture whenever the server swaps your echoes, so the comparison fills
-- itself in as you play instead of needing you to remember.
function BL.Init()
  if BL.__hooked then return end
  BL.__hooked = true
  -- One-time migration: old "b"-prefixed captures used the quality-unstable
  -- grantedPerks fingerprint (locks omitted, keys shifting as quality changed).
  -- They can never match the new identity, so they'd sit as permanent
  -- [PREDICTED] ghosts. None ever accumulated a measured fight, so drop them.
  if PP.db and PP.db.buildLog then
    local dropped = 0
    for key in pairs(PP.db.buildLog) do
      if type(key) == "string" and key:match("^b%d") then
        PP.db.buildLog[key] = nil
        dropped = dropped + 1
      end
    end
    if dropped > 0 then
      PP.print(DIM .. "Builds: cleared " .. dropped .. " old-format capture(s) "
        .. "(their identity changed with echo quality, so they could never "
        .. "accumulate fights). Swap builds once each to re-capture." .. R)
    end
  end
  local f = CreateFrame("Frame")
  f:RegisterEvent("CHAT_MSG_SYSTEM")
  f:SetScript("OnEvent", function(_, _, msg)
    if not msg then return end
    local m = string.lower(msg)
    if string.find(m, "echoes were replaced", 1, true)
       or string.find(m, "build applied", 1, true) then
      -- Let the server finish applying before we read the run.
      local t = CreateFrame("Frame")
      local acc = 0
      t:SetScript("OnUpdate", function(self, e)
        acc = acc + e
        if acc > 1.5 then
          self:SetScript("OnUpdate", nil)
          PP.safeCall(BL.Capture, "build applied")
        end
      end)
    end
  end)
end
