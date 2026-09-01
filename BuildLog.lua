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
    -- An id wins when it points at a capture that still EXISTS. A dangling id
    -- (its capture deleted, or written by an older format) must fall through to
    -- the name instead of suppressing the match entirely -- that suppression is
    -- what made hundreds of logged fights unreachable.
    local match
    local live = f.buildId and PP.db and PP.db.buildLog
      and PP.db.buildLog[f.buildId] ~= nil
    if live and key then
      match = (f.buildId == key)
    else
      match = (f.build ~= nil and f.build == name)
    end
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

-- Captures PLUS builds that exist only as a tag on logged fights.
--
-- A capture is a fingerprint of the run at one moment; a fight carries the name
-- of the build that was active. Those are different records, and for most of
-- this addon's history the fights accumulated names the capture table never
-- had -- 427 fights on one build, 247 on another, with a single capture row to
-- show for it. Reporting only captures threw all of that away and printed
-- "nothing here is measured" on top of it.
--
-- Synthesised rows are marked `_fromFights` so the panel can be honest that
-- their build composition was never fingerprinted, only their damage.
local function MergedLog()
  local log = PP.db and PP.db.buildLog
  local out = {}
  for k, v in pairs(log or {}) do out[k] = v end

  local haveName = {}
  for _, r in pairs(out) do
    if r.name then haveName[r.name] = true end
    if r.userName then haveName[r.userName] = true end
  end

  local counts = {}
  for _, f in ipairs((PP.db and PP.db.fights) or {}) do
    if f.build and f.dps and (f.dur or 0) >= 10 and not haveName[f.build] then
      counts[f.build] = (counts[f.build] or 0) + 1
    end
  end
  -- One-off tags ("idk", "36 echoes #160") are noise, not builds.
  for name, n in pairs(counts) do
    if n >= 3 then
      out["fights:" .. name] = { name = name, _fromFights = true, _fightCount = n }
    end
  end
  return out
end

-- Side-by-side of every build we've fingerprinted.
function BL.Report()
  local log = MergedLog()
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

  -- ONE line per build, five builds, then a pointer. This is the chat glance;
  -- the Builds page is where the comparison actually lives, and six lines per
  -- build meant the top of the list had scrolled away before you read it.
  PP.print(GOLD .. "BUILD COMPARISON" .. R .. DIM .. "  (" .. #rows
    .. " tracked -- " .. R .. GOLD .. "/ep builds" .. R .. DIM
    .. " for the full page)" .. R)
  for i = 1, math.min(#rows, 5) do
    local r = rows[i]
    local detail
    if r._m then
      detail = VERD .. "avg " .. K(r._m.avg) .. R .. DIM .. " dps over " .. r._m.n
        .. " fight" .. (r._m.n == 1 and "" or "s") .. R
    else
      detail = EMBER .. "not measured" .. R
        .. (r.score and (DIM .. ", predicted " .. r.score .. "/100" .. R) or "")
    end
    DEFAULT_CHAT_FRAME:AddMessage("  " .. BRIGHT .. i .. ". " .. r.name .. R
      .. DIM .. " -- " .. R .. detail)
  end
  if #rows > 5 then
    PP.print(DIM .. "  +" .. (#rows - 5) .. " more on the Builds page." .. R)
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
-- A build CARD, not a spreadsheet row.
--
-- The page used to be a metric x build matrix: thirteen labelled rows, three
-- columns, winners flagged per row. It answered "what are all the numbers"
-- when the player is asking "which build should I run". Reading it meant
-- holding three columns in your head and doing the comparison yourself, and it
-- led with PREDICTED composition while the measured damage sat further down.
--
-- One card per build instead, ranked, damage first:
--
--    1  Loadout 7                            312k
--       MEASURED - 247 fights                best
--       19 S - 5 core - +70% adaptive - 106k hp
--
-- Rank, name and dps read in one pass; the evidence line says how much to
-- trust it; composition is one quiet line, only when we actually captured it.
-- Colourblind: rank numerals, "best"/"-4%", and the MEASURED/PREDICTED words
-- all carry the meaning without colour.
local function GetRow(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Frame", nil, content)
  r:SetWidth(430); r:SetHeight(46)

  r.rank = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  r.rank:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -1)
  r.rank:SetWidth(22); r.rank:SetJustifyH("RIGHT")

  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 32, 0)
  r.name:SetWidth(250); r.name:SetJustifyH("LEFT")

  r.dps = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  r.dps:SetPoint("TOPRIGHT", r, "TOPRIGHT", -4, -1)
  r.dps:SetWidth(120); r.dps:SetJustifyH("RIGHT")

  r.meta = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.meta:SetPoint("TOPLEFT", r, "TOPLEFT", 32, -17)
  r.meta:SetWidth(250); r.meta:SetJustifyH("LEFT")

  r.delta = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.delta:SetPoint("TOPRIGHT", r, "TOPRIGHT", -4, -18)
  r.delta:SetWidth(120); r.delta:SetJustifyH("RIGHT")

  r.detail = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.detail:SetPoint("TOPLEFT", r, "TOPLEFT", 32, -30)
  r.detail:SetWidth(370); r.detail:SetJustifyH("LEFT")

  -- Hairline separator: structure without drawing attention to itself.
  r.line = r:CreateTexture(nil, "ARTWORK")
  r.line:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
  r.line:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
  r.line:SetHeight(1)
  r.line:SetTexture(1, 1, 1, 0.07)

  rows[i] = r
  return r
end

function BL.Refresh()
  if not (frame and content) then return end
  local log = MergedLog()
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
    -- ONE sentence, and it must be the answer to "which build should I run".
    -- Everything else on this page is supporting evidence for this line.
    local m = 0
    for _, r in ipairs(list) do if r._m then m = m + 1 end end
    local top = list[1]

    if m == 0 then
      frame.verdict:SetText(BRIGHT .. "No build has been measured yet" .. R)
      frame.hint:SetText(DIM .. "Fight for 10s or more on two different builds and "
        .. "the real answer replaces the guesswork. " .. #list .. " build"
        .. (#list == 1 and "" or "s") .. " known." .. R)
    elseif m == 1 then
      frame.verdict:SetText(BRIGHT .. tostring(top.name or "?") .. R .. DIM
        .. " is the only measured build" .. R)
      frame.hint:SetText(DIM .. K(top._m.avg) .. " over " .. top._m.n .. " fight"
        .. (top._m.n == 1 and "" or "s") .. ". Play a second build to get a "
        .. "comparison." .. R)
    else
      -- The gap matters as much as the winner: a 2% lead over 40 fights is
      -- noise, and saying so is more useful than crowning it.
      local second = nil
      for i = 2, #list do if list[i]._m then second = list[i] break end end
      local gap = (second and second._m.avg > 0)
        and ((top._m.avg / second._m.avg - 1) * 100) or nil
      frame.verdict:SetText(VERD .. "Best: " .. R .. BRIGHT
        .. tostring(top.name or "?") .. R .. GOLD .. "  " .. K(top._m.avg) .. R)
      local conf
      if not gap then
        conf = ""
      elseif gap < 3 then
        conf = "  Too close to call -- keep playing both."
      elseif top._m.n < 10 then
        conf = "  Only " .. top._m.n .. " fights though; treat it as provisional."
      else
        conf = "  A real gap."
      end
      frame.hint:SetText(DIM .. "Ahead of " .. tostring(second and second.name or "?")
        .. " by " .. string.format("%.0f%%", gap or 0) .. " over " .. top._m.n
        .. " fights." .. conf .. R)
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

  -- Rank every build; show them all rather than an arbitrary top three. A
  -- card is compact enough that six still read cleanly, and hiding a build the
  -- player is asking about is worse than a slightly longer list.
  local best = list[1] and list[1]._m and list[1]._m.avg or nil

  local function Detail(b)
    -- One quiet line of composition, only for builds we actually fingerprinted.
    -- A synthesised row (damage logged, never captured) says so instead of
    -- showing a row of dashes pretending to be data.
    if b._fromFights then
      return DIM .. "composition was never captured -- damage only" .. R
    end
    local bits = {}
    if b.S then bits[#bits + 1] = b.S .. " S" end
    if b.core then bits[#bits + 1] = b.core .. " core" end
    if b.uniques then bits[#bits + 1] = "+" .. b.uniques .. "% adaptive" end
    local pw = b.power or {}
    if pw.hp then bits[#bits + 1] = K(pw.hp) .. " hp" end
    if pw.crit then bits[#bits + 1] = num(pw.crit) .. "% crit" end
    if #bits == 0 then return "" end
    return DIM .. table.concat(bits, "  9483  ") .. R
  end

  local y, n = 0, 0
  for i, b in ipairs(list) do
    n = n + 1
    local r = GetRow(n)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)

    -- Rank numeral for measured builds; a dash for ones with no evidence, so
    -- an unmeasured build never looks like it placed in a contest it sat out.
    r.rank:SetText(b._m and (GOLD .. i .. R) or (DIM .. "-" .. R))
    r.name:SetText(BRIGHT .. tostring(b.name or "?") .. R)

    if b._m then
      r.dps:SetText(((i == 1) and GOLD or BRIGHT) .. K(b._m.avg) .. R)
      local thin = (b._m.n < 10) and (EMBER .. "  thin sample" .. R) or ""
      r.meta:SetText(VERD .. "MEASURED" .. R .. DIM .. "  9483  "
        .. b._m.n .. " fight" .. (b._m.n == 1 and "" or "s") .. R .. thin)
      if i == 1 then
        r.delta:SetText(VERD .. "best" .. R)
      elseif best and best > 0 then
        r.delta:SetText(DIM .. string.format("%.0f%%", (b._m.avg / best - 1) * 100) .. R)
      else
        r.delta:SetText("")
      end
    else
      r.dps:SetText(DIM .. "--" .. R)
      r.meta:SetText(EMBER .. "PREDICTED" .. R .. DIM .. "  9483  no fights yet" .. R)
      r.delta:SetText("")
    end

    local det = Detail(b)
    r.detail:SetText(det)
    local h = (det ~= "" ) and 46 or 34
    r:SetHeight(h)
    r.line:Show()
    r:Show()
    y = y + h
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

  -- Build score belongs HERE, not on the journal rail. It rates COMPOSITION --
  -- a prediction -- and this is the page that already shows measured damage,
  -- so the two forms of evidence sit together and their relative weight is
  -- obvious. On the rail it was a lone button with no context.
  local score = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  score:SetWidth(110); score:SetHeight(22)
  score:SetPoint("TOPRIGHT", cap, "BOTTOMRIGHT", 0, -4)
  score:SetText("Score this run")
  score:SetScript("OnClick", function()
    if PP.BuildScore then PP.safeCall(PP.BuildScore.Report) end
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

  -- ORPHANED FIGHTS. The migration above deleted the old-format capture rows
  -- but left `buildId` on the FIGHTS pointing at them. Because Measured()
  -- treats an id as authoritative, those fights then matched nothing at all --
  -- not even by name -- so 338 real fights went permanently invisible and the
  -- comparison declared "nothing here is measured" while sitting on a year of
  -- data. Strip the dead ids so those fights fall back to name matching.
  if PP.db and PP.db.fights then
    local freed = 0
    for _, f in ipairs(PP.db.fights) do
      if type(f.buildId) == "string" and f.buildId:match("^b%d") then
        f.buildId = nil
        freed = freed + 1
      end
    end
    if freed > 0 then
      PP.print(DIM .. "Builds: recovered " .. freed .. " fight(s) that were "
        .. "pointing at deleted captures -- they match by name again." .. R)
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
