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

local TITLE = "PallyPilot Solo Ret (synced)"

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

-- Synergy bundles: +40 score for members while the main (first) is active.
-- A mechanic no community build uses — our edge.
local BUNDLES = {
  { id = "ppb-resonant", tier = "S",
    echoes = { "Resonant Build", "Strength Training", "Agility Boost",
               "Iron Constitution" } },
  { id = "ppb-dots", tier = "S",
    echoes = { "Contagion", "Echoing Tides", "Scorching Wounds", "Open Wounds",
               "Hungering Curse", "Necrotic Plague", "Accelerated Decay" } },
  { id = "ppb-blades", tier = "S",
    echoes = { "Ambidexterity", "Second Edge", "First Strike",
               "Expertise Drills", "Armor Penetration", "Weapon Mastery" } },
  -- Measured on the arm3 HoR-HC2 benchmark: the fire/frost proc web (Fire
  -- Cyclone #1 source) feeds itself — echoes' own fire/frost damage triggers
  -- the school-stack echoes.
  { id = "ppb-cyclones", tier = "S",
    echoes = { "Cinders of the Sanctum", "Cyclone of Cold Bones",
               "Permafrost Aura", "Frostfire Paradox", "Scorched Path",
               "Conjured Flame", "Flame Beacon" } },
}
local function AssembleBundles()
  local out = {}
  for i, b in ipairs(BUNDLES) do
    local echoes = {}
    for j, n in ipairs(b.echoes) do echoes[j] = ToCurly(n) end
    out[i] = { id = b.id, tier = b.tier, echoes = echoes }
  end
  return out
end

function HS.Push(mode)
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

  for id, b in pairs(EbonholdHubDB.builds or {}) do
    if b.title == TITLE and EB.Delete then pcall(EB.Delete, id) end
  end

  local ok, build = pcall(EB.Create, {
    title = TITLE,
    class = "PALADIN",
    spec = 3,
    comments = "PallyPilot " .. (mode == "farm" and "FARM" or "breadth")
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
    author = "PallyPilot",
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
