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
  [16] = { rec = "Berserking or Massacre (+110 AP)", src = "Enchanting / AH" },
  [17] = { rec = "Berserking / Massacre (if a weapon)", src = "Enchanting", optional = true },
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
  "Bold Cardinal Ruby (+20 Strength) in every socket you don't need for a meta,",
  "Chaotic Skyflare Diamond (+21 crit, +3% crit dmg) as the meta,",
  "and Eternal Belt Buckle on the waist for a free extra socket.",
}
local GEM_NOTE = "Ignore socket-color bonuses unless the bonus is Strength/AP/crit "
  .. "worth more than the ~10 Str you lose from an off-color gem."

local GLYPH_MAJOR = { "Glyph of Judgement (+10% Judgement dmg)",
  "Glyph of Exorcism (+20% Exorcism dmg)",
  "Glyph of Consecration (or Glyph of Divine Storm)" }
local GLYPH_MINOR = { "Glyph of Sense Undead (+1% dmg vs undead — huge for AotC/ICC)",
  "Glyph of Blessing of Kings", "Glyph of Lay on Hands" }

function GO.Report()
  Print(GOLD .. "Gear optimizer" .. R .. DIM
    .. " — enchants / gems / glyphs (Strength-priority Ret)" .. R)

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
