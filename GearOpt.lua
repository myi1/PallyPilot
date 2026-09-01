-- PallyPilot GearOpt: enchant / gem / glyph audit for the Strength-stacking
-- Retribution build. Flags the always-actionable gaps (an unenchanted slot or
-- an empty socket is free power on any server) and recommends the standard
-- WotLK Ret choices, weighted toward Strength/AP per the build's stat plan.
-- Chat report: /pp gems (aliases: enchants, glyphs, gearopt).
local PP = PallyPilot
local GO = PP.GearOpt

local GOLD = "|cffe0b352"
local BRIGHT = "|cfff6d888"
local DIM = "|cffb4a586"
local EMBER = "|cffd9694a"
local VERD = "|cff8aa96a"
local R = "|r"

local function Print(msg) PP.print(msg) end

local SLOT_NAMES = {
  [1]="Head",[3]="Shoulder",[5]="Chest",[6]="Waist",[7]="Legs",[8]="Feet",
  [9]="Wrist",[10]="Hands",[15]="Back",[16]="Main Hand",[17]="Off Hand",
  [11]="Ring 1",[12]="Ring 2",[18]="Ranged",
}

-- Enchant recommendation per slot. `optional` slots aren't flagged as MISSING
-- (rings need an enchanter; ranged/off-hand depend on the item type).
local ENCH = {
  [1]  = { rec = "Arcanum of Torment (+50 AP, +20 crit)", src = "Knights of the Ebon Blade (Revered)" },
  [3]  = { rec = "Inscription of the Axe (+40 AP, +15 crit)", src = "Sons of Hodir (Honored) / scribe" },
  [5]  = { rec = "Powerful Stats (+10 all stats)", src = "profession enchant" },
  [7]  = { rec = "Icescale Leg Armor (+75 AP, +22 crit)", src = "Leatherworking / AH" },
  [8]  = { rec = "Icewalker (+12 hit, +12 crit)", src = "until hit-capped, then Greater Assault (+32 AP)" },
  [9]  = { rec = "Greater Assault (+50 AP)", src = "Enchanting / AH" },
  [10] = { rec = "Crusher (+44 AP)", src = "Enchanting / AH" },
  [15] = { rec = "Major Agility (+22 agi)", src = "or Greater Speed (+23 haste)" },
  [16] = { rec = "Black Magic (haste proc)", src = "Ebonhold Ret default; or Berserking/Massacre for AP" },
  [17] = { rec = "Black Magic (if a weapon)", src = "Enchanting", optional = true },
  [11] = { rec = "Assault (+40 AP)", src = "enchanters only", optional = true },
  [12] = { rec = "Assault (+40 AP)", src = "enchanters only", optional = true },
}
local ENCH_ORDER = { 1, 3, 5, 7, 8, 9, 10, 15, 16, 17, 11, 12 }

-- item:itemId:enchant:gem1:gem2:gem3:gem4:...
local function ParseLink(link)
  if not link then return nil end
  local nums = {}
  local body = string.match(link, "item:([%-:%d]+)")
  if not body then return nil end
  for part in string.gmatch(body, "(%-?%d+)") do nums[#nums + 1] = tonumber(part) end
  return {
    id = nums[1],
    enchant = nums[2] or 0,
    gems = { nums[3] or 0, nums[4] or 0, nums[5] or 0, nums[6] or 0 },
  }
end

-- Socket count from the item template (all colors count as gemmable).
local SOCKET_KEYS = { "EMPTY_SOCKET_RED", "EMPTY_SOCKET_YELLOW",
  "EMPTY_SOCKET_BLUE", "EMPTY_SOCKET_META", "EMPTY_SOCKET_PRISMATIC" }
local function SocketCount(link)
  if not GetItemStats then return 0 end
  local ok, t = pcall(GetItemStats, link)
  if not ok or type(t) ~= "table" then return 0 end
  local n = 0
  for _, k in ipairs(SOCKET_KEYS) do n = n + (tonumber(t[k]) or 0) end
  return n
end

-- Best-effort glyph read. 3.3.5 GetGlyphSocketInfo returns
-- (enabled, glyphType, glyphSpellID, icon) on most cores; we defensively find
-- the numeric return that resolves to a spell name.
local function GlyphState()
  if not (GetNumGlyphSockets and GetGlyphSocketInfo and GetSpellInfo) then return nil end
  local ok, count = pcall(GetNumGlyphSockets)
  if not ok or not count or count == 0 then return nil end
  local filled, empty, names = 0, 0, {}
  for i = 1, count do
    local rets = { pcall(GetGlyphSocketInfo, i) }
    if rets[1] then
      local enabled = rets[2]
      local spellName
      for j = 3, #rets do
        local v = rets[j]
        if type(v) == "number" and v > 0 then
          local nm = GetSpellInfo(v)
          if nm then spellName = nm; break end
        end
      end
      if enabled == nil or enabled then
        if spellName then filled = filled + 1; names[#names + 1] = spellName
        else empty = empty + 1 end
      end
    end
  end
  return { filled = filled, empty = empty, names = names }
end

local GEM_REC = {
  "Haste gems in (almost) every socket \226\128\148 the Ebonhold #paladin default for the",
  "DoT/haste build (ticks scale with haste via Accelerated Decay).",
  "Chaotic Skyflare Diamond meta (3% crit): feed it 2 Haste/Stam gems to activate.",
  "Eternal Belt Buckle on the waist for a free extra socket.",
}
local GEM_NOTE = "Prefer Strength (Bold Cardinal Ruby) only if you're chasing the "
  .. "Str->Spellpower multiplier over raw haste \226\128\148 the community leans haste. "
  .. "Ignore off-color socket bonuses unless they're crit/haste/Str worth the loss."

local GLYPH_MAJOR = { "Glyph of Judgement (+10% Judgement dmg)",
  "Glyph of Exorcism (+20% Exorcism dmg)",
  "Glyph of Consecration (or Glyph of Divine Storm)" }
local GLYPH_MINOR = { "Glyph of Sense Undead (+1% dmg vs undead — huge for AotC/ICC)",
  "Glyph of Blessing of Kings", "Glyph of Lay on Hands" }

-- WHO THIS ADVICE IS FOR. Every table below (enchants, gems, glyphs) is
-- Retribution-paladin specific: Strength/AP plate. The Gear page is shared by
-- every class, so without a guard a priest was being told to put Icescale Leg
-- Armor and +AP plate enchants on cloth. Gate it rather than pretend.
local ADVICE_SPEC = "Retribution Paladin"
local ADVICE_CLASS = "PALADIN"
local function AdviceApplies()
  local _, token = UnitClass("player")
  return token == ADVICE_CLASS
end

function GO.Report()
  Print(GOLD .. "Gear optimizer" .. R .. DIM
    .. " — enchants / gems / glyphs (" .. ADVICE_SPEC .. ")" .. R)
  if not AdviceApplies() then
    local name = UnitClass("player") or "this class"
    Print(EMBER .. "NOT FOR " .. string.upper(tostring(name)) .. "." .. R .. DIM
      .. " These are " .. ADVICE_SPEC .. " enchants and gems (Strength/AP plate). "
      .. "Shown for reference only -- do not follow them on " .. tostring(name)
      .. "." .. R)
  end

  -- ENCHANTS -----------------------------------------------------------------
  local missing, empties = {}, {}
  for _, slot in ipairs(ENCH_ORDER) do
    local link = GetInventoryItemLink("player", slot)
    if link then
      local it = ParseLink(link)
      local rec = ENCH[slot]
      if it and rec and (it.enchant or 0) == 0 and not rec.optional then
        missing[#missing + 1] = slot
      end
    end
  end
  if #missing == 0 then
    Print(VERD .. "Enchants: every core slot is enchanted." .. R)
  else
    Print(EMBER .. "Enchants MISSING (" .. #missing .. ") — free power:" .. R)
    for _, slot in ipairs(missing) do
      local rec = ENCH[slot]
      DEFAULT_CHAT_FRAME:AddMessage("  " .. BRIGHT .. SLOT_NAMES[slot] .. R .. ": "
        .. rec.rec .. DIM .. "  (" .. rec.src .. ")" .. R)
    end
  end

  -- GEMS ---------------------------------------------------------------------
  for slot = 1, 18 do
    local link = GetInventoryItemLink("player", slot)
    if link then
      local it = ParseLink(link)
      local sockets = SocketCount(link)
      if it and sockets > 0 then
        local slotted = 0
        for _, g in ipairs(it.gems) do if (g or 0) ~= 0 then slotted = slotted + 1 end end
        local empty = sockets - slotted
        if empty > 0 then empties[#empties + 1] = { slot = slot, n = empty } end
      end
    end
  end
  if #empties == 0 then
    Print(VERD .. "Gems: no empty sockets detected." .. R)
  else
    local total = 0
    for _, e in ipairs(empties) do total = total + e.n end
    Print(EMBER .. "Empty sockets (" .. total .. ") — free power:" .. R)
    for _, e in ipairs(empties) do
      DEFAULT_CHAT_FRAME:AddMessage("  " .. BRIGHT .. (SLOT_NAMES[e.slot] or ("slot " .. e.slot))
        .. R .. DIM .. ": " .. e.n .. " empty" .. R)
    end
  end
  Print(DIM .. "Gem plan:" .. R)
  for _, l in ipairs(GEM_REC) do DEFAULT_CHAT_FRAME:AddMessage("  " .. l) end
  Print(DIM .. "  " .. GEM_NOTE .. R)

  -- GLYPHS -------------------------------------------------------------------
  local g = GlyphState()
  if g and g.empty > 0 then
    Print(EMBER .. "Glyphs: " .. g.empty .. " empty slot(s)." .. R)
  elseif g then
    Print(VERD .. "Glyphs: all " .. g.filled .. " slots filled." .. R
      .. DIM .. " (compare to the recommendations below)." .. R)
  else
    Print(DIM .. "Glyphs: couldn't read your glyph sockets — recommendations:" .. R)
  end
  Print(BRIGHT .. "Major glyphs:" .. R)
  for _, l in ipairs(GLYPH_MAJOR) do DEFAULT_CHAT_FRAME:AddMessage("  " .. l) end
  Print(BRIGHT .. "Minor glyphs:" .. R)
  for _, l in ipairs(GLYPH_MINOR) do DEFAULT_CHAT_FRAME:AddMessage("  " .. l) end
  Print(DIM .. "Enchants/gems/glyphs are standard WotLK — verify names at your "
    .. "trainer/AH; the picks lean Strength/AP per your build." .. R)
end

-- ------------------------------------------------------------ /pp upgrades

-- Ebonhold gear is affix-driven: base items follow standard WotLK tiers (server
-- is in the Ulduar phase), quest/crafted gear is stat-boosted, and the real
-- per-slot power lever is the affix. So the "upgrade finder" isn't a BiS list —
-- it ranks your slots by item level (where a base upgrade helps most) and folds
-- in the affix + enchant + gem gaps (free power on any slot).
local UP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local BASE_SRC_DEFAULT = "Crit/Haste piece from ICC 10/25 Heroic (or a well-affixed boosted quest/craft)"
local BASE_SRC = {
  [16] = "Lich King 25H (SP + off) / Librarian's Paper Cutter x2 / Eashandar's Right Claw (MC)",
  [17] = "Lich King 25H (off-hand) / 2nd Librarian's Paper Cutter",
  [13] = "Tiny Abomination in a Jar (ICC) / Algalon trinket (Ulduar)",
  [14] = "Tiny Abomination in a Jar (ICC) / Algalon trinket (Ulduar)",
  [18] = "Crit/Haste gun (ToC 25H) or Corpse-Impaling Spike / Libram of Valiance (ToC emblems)",
  [6]  = "Triumph-emblem belt (weak slot) + Eternal Belt Buckle",
  [8]  = "Alga / Ulduar craft boots (weak slot)",
  [2]  = "Crit/Haste from ICC 10/25 Heroic / Emblem vendor",
  [11] = "Crit/Haste from ICC 10/25 Heroic / Emblem vendor",
  [12] = "Crit/Haste from ICC 10/25 Heroic / Emblem vendor",
  [15] = "Crit/Haste from ICC 10/25 Heroic / Emblem vendor",
}

-- Per-slot enchant/gem gap data for the unified Gear view. Keyed by inventory
-- slot: { ilvl, encMiss, encRec, encSrc, enchantable, sockets, emptyGems }.
function GO.SlotReport()
  local out = {}
  -- Return nothing off-class: GearAudit renders these as MISSING/gap markers on
  -- the paperdoll, and a wrong "missing enchant" flag is worse than silence.
  if not AdviceApplies() then return out end
  for slot = 1, 18 do
    local link = GetInventoryItemLink("player", slot)
    if link then
      local _, _, _, ilvl = GetItemInfo(link)
      local it = ParseLink(link)
      local rec = ENCH[slot]
      local encMiss = it and rec and not rec.optional and (it.enchant or 0) == 0 or false
      local sockets = SocketCount(link)
      local slotted = 0
      if it then for _, g in ipairs(it.gems) do if (g or 0) ~= 0 then slotted = slotted + 1 end end end
      out[slot] = {
        ilvl = ilvl or 0, encMiss = encMiss,
        encRec = rec and rec.rec, encSrc = rec and rec.src,
        enchantable = (rec ~= nil and not rec.optional),
        sockets = sockets, emptyGems = math.max(0, sockets - slotted),
      }
    end
  end
  return out
end

function GO.Upgrades()
  Print(GOLD .. "Gear health" .. R .. DIM
    .. " — where your upgrades are (Ebonhold: Ulduar tier, affix-driven)" .. R)

  -- Affix verdicts by slot (from GearAudit).
  local affix = {}
  if PP.GearAudit and PP.GearAudit.Compute then
    local ok, res = pcall(PP.GearAudit.Compute)
    if ok and type(res) == "table" then
      for _, r in ipairs(res) do affix[r.slot] = r end
    end
  end

  -- Per-slot scan: ilvl + enchant/gem gaps.
  local rows, sum, cnt = {}, 0, 0
  for _, slot in ipairs(UP_SLOTS) do
    local link = GetInventoryItemLink("player", slot)
    if link then
      local _, _, _, ilvl = GetItemInfo(link)
      ilvl = ilvl or 0
      local it = ParseLink(link)
      local encMiss = false
      local rec = ENCH[slot]
      if it and rec and not rec.optional and (it.enchant or 0) == 0 then encMiss = true end
      local sockets = SocketCount(link)
      local slotted = 0
      if it then for _, g in ipairs(it.gems) do if (g or 0) ~= 0 then slotted = slotted + 1 end end end
      local emptyGems = math.max(0, sockets - slotted)
      local a = affix[slot]
      local affixGap = a and (a.status == "missing" or a.status == "swap")
      rows[#rows + 1] = { slot = slot, ilvl = ilvl, enc = encMiss, gems = emptyGems,
        affix = affixGap, affixStatus = a and a.status, name = a and a.item }
      if ilvl > 0 then sum = sum + ilvl; cnt = cnt + 1 end
    end
  end
  if cnt == 0 then Print("No gear detected.") return end
  local avg = sum / cnt
  Print(DIM .. "Average item level: " .. R .. BRIGHT .. string.format("%.0f", avg) .. R
    .. DIM .. " across " .. cnt .. " slots." .. R)

  -- BIGGEST BASE UPGRADES: lowest item level, most below average first.
  local byIlvl = {}
  for _, r in ipairs(rows) do byIlvl[#byIlvl + 1] = r end
  table.sort(byIlvl, function(x, y) return x.ilvl < y.ilvl end)
  Print(EMBER .. "Biggest base upgrades (lowest item level):" .. R)
  local shown = 0
  for _, r in ipairs(byIlvl) do
    if shown < 5 and r.ilvl > 0 then
      shown = shown + 1
      local lag = avg - r.ilvl
      local lagTxt = (lag >= 13) and (EMBER .. " (-" .. string.format("%.0f", lag) .. " vs avg)" .. R)
        or (lag >= 6 and (DIM .. " (-" .. string.format("%.0f", lag) .. ")" .. R) or "")
      DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s%-10s%s ilvl %s%d%s%s",
        BRIGHT, SLOT_NAMES[r.slot] or ("slot " .. r.slot), R, GOLD, r.ilvl, R, lagTxt))
      DEFAULT_CHAT_FRAME:AddMessage("      " .. DIM .. (BASE_SRC[r.slot] or BASE_SRC_DEFAULT) .. R)
    end
  end

  -- QUICK WINS: gaps that are free power at any item level.
  local wins = {}
  for _, r in ipairs(rows) do
    local parts = {}
    if r.affix then parts[#parts + 1] = (r.affixStatus == "missing" and "no affix" or "wrong affix") end
    if r.enc then parts[#parts + 1] = "no enchant" end
    if r.gems > 0 then parts[#parts + 1] = r.gems .. " empty socket" .. (r.gems > 1 and "s" or "") end
    if #parts > 0 then wins[#wins + 1] = { slot = r.slot, txt = table.concat(parts, ", ") } end
  end
  if #wins > 0 then
    Print(BRIGHT .. "Quick wins (free power, any slot):" .. R)
    for _, w in ipairs(wins) do
      DEFAULT_CHAT_FRAME:AddMessage("  " .. BRIGHT .. (SLOT_NAMES[w.slot] or ("slot " .. w.slot))
        .. R .. DIM .. ": " .. w.txt .. R)
    end
    Print(DIM .. "Fix affixes in /pp gear, enchants/gems in /pp gems." .. R)
  else
    Print(VERD .. "No affix/enchant/gem gaps — every slot is fully kitted." .. R)
  end

  Print(DIM .. "On Ebonhold the affix usually beats a small base-ilvl bump, and "
    .. "quest/crafted gear is boosted — a well-affixed quest piece can outrun a "
    .. "raw raid drop. You keep gear across runs, so invest in the slot, not the run." .. R)
end
