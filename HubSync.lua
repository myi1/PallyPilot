-- PallyPilot HubSync v2: publish the PallyPilot ratings INTO EbonholdHub as
-- the active build, via EBH's own public API — data only, no EBH code copied.
-- Doctrine (Wkpal autopsy + systems reference, 2026-08-25): BREADTH.
--  * echoMaxPicks stays EMPTY (engine default = 1 copy each): the engine
--    natively prefers any fresh non-F echo over any repeat, and at the
--    active cap it degrades into ranking the cores automatically.
--  * F only for negative riders — F-ratings waste the run's ~9 banishes.
--  * Locks are NUMERIC spellIds (EBH matches ids, not names — names never
--    fired; this was silently broken until the autopsy).
--  * echoTierOrder grants position bonuses; echoBundles exploit the unused
--    +40 bundle score. settings pin aggression 4 (the duplicate-banish mode).
local PP = PallyPilot
local HS = PP.HubSync

-- Per-class synced-build title, derived from the active class's guide data, so a
-- priest/hunter sync isn't mislabeled "Solo Ret". Cleanup matches TITLE_PREFIX.
local TITLE_PREFIX = "EbonPilot "
local function SyncedTitle()
  local spec = (PP.Build and PP.Build.spec) or "Solo"
  return TITLE_PREFIX .. spec .. " (synced)"
end

local QUALITY_WORDS = {
  Common = true, Uncommon = true, Rare = true, Epic = true,
  Legendary = true, Artifact = true,
}

local function ToCurly(name)
  return (string.gsub(name, "'", "\226\128\153"))
end
local function Norm(name)
  name = string.gsub(name, "\226\128\153", "'")
  return string.lower(name)
end

local function BothQuotes(t, name, tier)
  t[name] = tier
  local curly = ToCurly(name)
  if curly ~= name then t[curly] = tier end
end

-- Curated lists win over the catalog; locked cores are S; disables are F.
-- C is omitted: unrated names default to C inside EBH anyway.
local function AssembleTiers()
  local B = PP.Build
  local tiers = {}
  for n, t in pairs(B.catalog or {}) do
    if t ~= "C" then BothQuotes(tiers, n, t) end
  end
  for tier, list in pairs(B.tiers) do
    for _, n in ipairs(list) do BothQuotes(tiers, n, tier) end
  end
  for _, n in ipairs(B.locked) do BothQuotes(tiers, n, "S") end
  for _, n in ipairs(B.disable) do BothQuotes(tiers, n, "F") end
  return tiers
end

-- Priority-ordered S/A name arrays (EBH grants position bonuses we were
-- forfeiting). Curated order first, catalog names after, server spelling.
local function AssembleTierOrder()
  local B = PP.Build
  local order = { S = {}, A = {} }
  local seen = {}
  local function add(tier, n)
    local c = ToCurly(n)
    if not seen[c] then
      seen[c] = true
      table.insert(order[tier], c)
    end
  end
  for _, n in ipairs(B.locked) do add("S", n) end
  for _, n in ipairs(B.tiers.S) do add("S", n) end
  for _, n in ipairs(B.tiers.A) do add("A", n) end
  local cs, ca = {}, {}
  for n, t in pairs(B.catalog or {}) do
    if t == "S" then cs[#cs + 1] = n elseif t == "A" then ca[#ca + 1] = n end
  end
  table.sort(cs); table.sort(ca)
  for _, n in ipairs(cs) do add("S", n) end
  for _, n in ipairs(ca) do add("A", n) end
  return order
end

-- Locks must be numeric perk spellIds. Resolve display names against the
-- live PerkDatabase (highest quality variant wins), with known fallbacks.
local FALLBACK_IDS = {
  ["pandemic"] = 201256, ["adaptive power"] = 200960,
  ["constellations"] = 200844, ["twilight equilibrium"] = 201324,
}
local function ResolveSpellIds(names)
  local db = ProjectEbonhold and ProjectEbonhold.PerkDatabase
  local best = {}
  if db then
    for id, e in pairs(db) do
      if type(id) == "number" and type(e) == "table" and e.comment then
        local base, q = string.match(e.comment, "^(.-)%s*%-%s*(%a+)$")
        if not (base and QUALITY_WORDS[q]) then base = e.comment end
        local key = Norm(base)
        local quality = e.quality or 0
        if not best[key] or quality > best[key].q then
          best[key] = { id = id, q = quality }
        end
      end
    end
  end
  local out = {}
  for _, name in ipairs(names) do
    local hit = best[Norm(name)]
    local id = (hit and hit.id) or FALLBACK_IDS[Norm(name)]
    if id then out[#out + 1] = id end
  end
  return out
end

-- Synergy bundles: +40 score to members while the main (first) echo is active --
-- a scoring lever no community build uses. Each class now ships its own set in
-- its guide data (PP.Build.bundles); we read the active class's here (empty for a
-- class that hasn't defined any).
local function AssembleBundles()
  local out = {}
  local bundles = (PP.Build and PP.Build.bundles) or {}
  for i, b in ipairs(bundles) do
    local echoes = {}
    for j, n in ipairs(b.echoes) do echoes[j] = ToCurly(n) end
    out[i] = { id = b.id, tier = b.tier, echoes = echoes }
  end
  return out
end

function HS.Push(mode)
  local B = PP.Build
  if not (B and B.tiers and B.locked) then
    PP.print("No synced echo build for " .. (UnitClass("player") or "this class")
      .. " yet -- this class's guide has no echo tiers/locks to publish.")
    return
  end
  local TITLE = SyncedTitle()
  if mode == "depth" then
    PP.print("Depth mode is retired — at the active cap the engine ranks the "
      .. "cores automatically (see wkpal-vs-pallypilot.md). Syncing breadth.")
    mode = nil
  end
  if mode == "farm" then
    PP.print("FARM sync: repeats uncapped so auto-pick drafts through "
      .. "repeat windows (rank-ups). Use with the /pp startrun farm pool; "
      .. "/pp hubsync for the raid/breadth build.")
  end
  local EB = EbonholdHub and EbonholdHub.Build
  if not (EB and EB.Create and EB.SetActive and EbonholdHubDB) then
    PP.print("EbonholdHub not loaded — can't sync a build into it.")
    return
  end
  local slots = (EB.GetLockedSlotCount and EB.GetLockedSlotCount())
    or PP.EchoAudit.LockSlots()
  local lockedNames = PP.EchoAudit.BestOwned and PP.EchoAudit.BestOwned(slots) or {}
  local lockedIds = ResolveSpellIds(lockedNames)

  -- An open Hub edit session would commit its pending tiers over ours.
  if EbonholdHub.TierData and EbonholdHub.TierData.ClearPending then
    pcall(EbonholdHub.TierData.ClearPending)
  end

  -- Replace any prior EbonPilot synced build (old "Solo Ret" title included).
  for id, b in pairs(EbonholdHubDB.builds or {}) do
    if b.title and string.find(b.title, TITLE_PREFIX, 1, true) == 1
       and (not b.author or b.author == "EbonPilot") and EB.Delete then
      pcall(EB.Delete, id)
    end
  end

  local ok, build = pcall(EB.Create, {
    title = TITLE,
    class = PP.class or select(2, UnitClass("player")) or "PALADIN",
    spec = (B.specIndex or 3),
    comments = "EbonPilot " .. (B.spec or "") .. " "
      .. (mode == "farm" and "FARM" or "breadth")
      .. " build: " .. (mode == "farm"
        and "repeats uncapped for rank-ups with a curated pool. "
        or "uniques first for Adaptive Power. ")
      .. "F only for negative riders; spellId locks; tier order + bundles. "
      .. "/pp hubsync [farm] to switch.",
    lockedEchoes = lockedIds,
    echoTiers = AssembleTiers(),
    echoTierOrder = AssembleTierOrder(),
    echoBundles = AssembleBundles(),
    echoMaxPicks = (function()
      if mode ~= "farm" then return {} end -- empty = 1 copy each = breadth
      -- Farm mode: the enabled pool is tiny (locks + epics), so nearly
      -- every window is repeats — and repeats ARE the goal (rank-ups).
      -- Uncap everything rated so auto-pick drafts through repeat windows
      -- instead of stalling on them (post-prestige field bug 2026-08-25).
      local mp = {}
      for name, tier in pairs(AssembleTiers()) do
        if tier ~= "F" then mp[name] = 0 end
      end
      return mp
    end)(),
    settings = { aggressionLevel = 4, banishFamilyWhitelist = {} },
    automationEnabled = true,
    author = "EbonPilot",
  })
  if not ok or not build then
    PP.print("Sync failed inside EbonholdHub.Build.Create: " .. tostring(build))
    return
  end
  local okA, err = pcall(EB.SetActive, build.id)
  if not okA then
    PP.print("Build created but SetActive failed: " .. tostring(err)
      .. " — select '" .. TITLE .. "' manually in EbonholdHub.")
    return
  end
  PP.db.buildMode = (mode == "farm") and "farm" or "raid"
  PP.print("Synced and ACTIVE: '" .. TITLE .. "' — "
    .. string.upper(PP.db.buildMode) .. " mode, "
    .. slots .. " lock slots, lock ids: " .. table.concat(lockedIds, ", "))
  PP.print("Locks: " .. table.concat(lockedNames, ", "))
end

-- ---------------------------------------------------------------------------
-- Shareable EBH1 loadout string. Format read from EbonholdHub's own decoder
-- (modules/weights/EchoLoadoutCodec.lua):
--   EBH1:<spellId>.<code>.<stack>,...:<CLASS>:<Title>
-- where code 1=B, 2=A, 3/4=S, spellId must be >= 200000 and resolve in the
-- server's PerkDatabase. This is the same string people paste in Discord and
-- that EbonholdHub's Import dialog accepts.
local CODE_FOR_TIER = { S = 3, A = 2, B = 1 }

-- name -> best (highest-quality) perk spellId, from the live PerkDatabase.
local function BestIdByName()
  local db = ProjectEbonhold and ProjectEbonhold.PerkDatabase
  local best = {}
  if not db then return best end
  for id, e in pairs(db) do
    if type(id) == "number" and id >= 200000 and type(e) == "table" and e.comment then
      local base, q = string.match(e.comment, "^(.-)%s*%-%s*(%a+)$")
      if not (base and QUALITY_WORDS[q]) then base = e.comment end
      local key = Norm(base)
      local quality = e.quality or 0
      if not best[key] or quality > best[key].q then best[key] = { id = id, q = quality } end
    end
  end
  return best
end

-- Build the string for the logged-in class's curated S/A/B echoes.
function HS.ExportString()
  local B = PP.Build
  if not (B and B.tiers) then
    return nil, "No echo build for " .. (UnitClass("player") or "this class") .. " yet."
  end
  local best = BestIdByName()
  if not next(best) then
    return nil, "Can't read the server's echo database yet -- log in fully, then retry."
  end
  -- Highest tier wins per echo; locks are S.
  local tierOf = {}
  for tier, list in pairs(B.tiers) do
    if CODE_FOR_TIER[tier] then
      for _, n in ipairs(list) do
        local k = Norm(n)
        if not tierOf[k] or CODE_FOR_TIER[tier] > CODE_FOR_TIER[tierOf[k]] then tierOf[k] = tier end
      end
    end
  end
  for _, n in ipairs(B.locked or {}) do tierOf[Norm(n)] = "S" end

  local parts, missing = {}, 0
  for key, tier in pairs(tierOf) do
    local hit = best[key]
    if hit then
      parts[#parts + 1] = hit.id .. "." .. CODE_FOR_TIER[tier] .. ".1"
    else
      missing = missing + 1
    end
  end
  if #parts == 0 then return nil, "None of this class's echoes resolved to spell ids." end
  table.sort(parts)
  local class = PP.class or select(2, UnitClass("player")) or "PALADIN"
  -- The decoder strips ALL whitespace, so pre-hyphenate or the title runs
  -- together ("EbonPilotSnakeTrap/RocketStrike").
  local title = "EbonPilot-" .. string.gsub(B.spec or "build", "%s+", "-")
  return "EBH1:" .. table.concat(parts, ",") .. ":" .. class .. ":" .. title,
         nil, #parts, missing
end

-- Show the string in a copy box (reuses the ash advisor's paste/copy popup).
function HS.ShowExport()
  local str, err, n, missing = HS.ExportString()
  if not str then PP.print(err or "Couldn't build a string.") return end
  local box = PP.AshAdvisor and PP.AshAdvisor.ShowBuildBox
  if box then
    box("Share this build (EBH1 -- paste into EbonholdHub Import)", str, false)
  else
    PP.print(str)
  end
  PP.print("Build string: " .. n .. " echoes"
    .. (missing and missing > 0 and (" (" .. missing .. " unresolved)") or "") .. ".")
end
