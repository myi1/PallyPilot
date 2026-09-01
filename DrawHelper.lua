-- PallyPilot DrawHelper: on an echo selection, tell you what to take / banish
-- (feature 3). Frame names for the echo-select UI aren't known yet, so v1 uses
-- a heuristic: when several build-known echo names are visible at once, that's a
-- selection — overlay each option's tier. Use /pp echoscan to reveal the real
-- frame so this can become a precise hook.
local PP = PallyPilot
local DH = PP.DrawHelper

local BRIGHT = "|cfff6d888"
local ASH = "|cff9db3bd"
local DIM = "|cffb4a586"
local EMBER = "|cffd9694a"
local R = "|r"

local overlay, nameSet

local function BuildNameSet()
  if nameSet then return nameSet end
  nameSet = {}
  local B = PP.Build
  local function add(list) for _, n in ipairs(list) do nameSet[n] = true end end
  add(B.locked); add(B.tiers.S); add(B.tiers.A); add(B.tiers.B); add(B.disable)
  return nameSet
end

local TIER_COLOR = { S = BRIGHT, A = ASH, B = DIM, F = EMBER }

-- Collect echo names currently visible on screen (heuristic detection).
--
-- THIS IS THE MOST EXPENSIVE THING IN THE ADDON and it runs on a timer, so the
-- shape of it matters more than anywhere else. Two things were wrong:
--
--   * `select(i, f:GetRegions())` re-invoked GetRegions on EVERY iteration of
--     the loop, each call returning the frame's whole region list again. A
--     frame with ten regions cost eleven GetRegions calls instead of one.
--   * The visible-frame cap was 400, but a raid UI blows straight through that
--     -- raid frames, nameplates, buff buttons, boss mods, a damage meter --
--     so the sweep ran at full cost exactly where the frame budget is tightest,
--     five times a second, looking for a dialog that cannot appear mid-fight.
--
-- Hoisted, capped on TOTAL frames walked (not just visible ones), and the
-- caller skips it entirely in combat.
local MAX_VISIBLE, MAX_WALK = 250, 3000
local function VisibleEchoOptions()
  local set = BuildNameSet()
  local found, seen = {}, {}
  local f, scanned, walked = EnumerateFrames(), 0, 0
  while f and scanned < MAX_VISIBLE and walked < MAX_WALK do
    walked = walked + 1
    if f.IsVisible and f:IsVisible() and f.GetRegions then
      -- ONE call, results held as a vararg.
      local n = select("#", f:GetRegions())
      if n > 0 then
        local regions = { f:GetRegions() }
        for i = 1, n do
          local r = regions[i]
          if r and r.GetObjectType and r:GetObjectType() == "FontString" then
            local txt = r:GetText()
            if txt and set[txt] and not seen[txt] then
              seen[txt] = true
              found[#found + 1] = txt
            end
          end
        end
      end
      scanned = scanned + 1
    end
    f = EnumerateFrames(f)
  end
  return found
end

local function EnsureOverlay()
  if overlay then return end
  overlay = CreateFrame("Frame", "PallyPilotDrawOverlay", UIParent)
  overlay:SetWidth(240); overlay:SetHeight(120)
  overlay:SetPoint("RIGHT", UIParent, "RIGHT", -40, 120)
  overlay:SetMovable(true); overlay:EnableMouse(true); overlay:RegisterForDrag("LeftButton")
  overlay:SetScript("OnDragStart", function(self) self:StartMoving() end)
  overlay:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  overlay:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  overlay:SetBackdropColor(0, 0, 0, 0.82)
  overlay.head = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  overlay.head:SetPoint("TOPLEFT", overlay, "TOPLEFT", 10, -8)
  overlay.head:SetText("|cffe0b352EbonPilot — pick|r")
  overlay.body = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  overlay.body:SetPoint("TOPLEFT", overlay, "TOPLEFT", 10, -26)
  overlay.body:SetWidth(220); overlay.body:SetJustifyH("LEFT"); overlay.body:SetJustifyV("TOP")
  overlay:Hide()
end

local function Advise(options)
  EnsureOverlay()
  local B = PP.Build
  local best, bestRank
  local RANK = { S = 4, A = 3, B = 2 }
  local lines = {}
  for _, name in ipairs(options) do
    local tier = B.TierOf(name) or "-"
    local col = TIER_COLOR[tier] or DIM
    lines[#lines + 1] = col .. "[" .. tier .. "]" .. R .. " " .. name
    local rank = RANK[tier]
    if rank and (not bestRank or rank > bestRank) then best, bestRank = name, rank end
  end
  local verdict
  if best then verdict = "\n|cff8aa96aTake:|r " .. best
  else verdict = "\n" .. DIM .. "No build pick here — take a quality/utility echo, or reroll." .. R end
  overlay.body:SetText(table.concat(lines, "\n") .. verdict)
  overlay:SetHeight(40 + #lines * 14 + 20)
  overlay:Show()
end

function DH.Init()
  if not PP.db or not PP.db.options.autoDraw then end
  local poll = CreateFrame("Frame")
  poll.t = 0
  poll:SetScript("OnUpdate", function(self, e)
    self.t = self.t + e
    if self.t < 0.3 then return end
    self.t = 0
    if not (PP.db and PP.db.options.autoDraw) then if overlay then overlay:Hide() end return end
    -- Never sweep in combat. An echo draw is a level-up or out-of-combat
    -- dialog; it cannot appear during a boss fight, and this is precisely when
    -- the screen is fullest and the frame budget tightest.
    if UnitAffectingCombat and UnitAffectingCombat("player") then
      if overlay then overlay:Hide() end
      return
    end
    local opts = VisibleEchoOptions()
    -- A real selection shows a few distinct choices at once. 2+ = likely a draw.
    if #opts >= 2 then
      PP.safeCall(Advise, opts)
    elseif overlay then
      overlay:Hide()
    end
  end)
end

-- Discovery: dump visible frames whose text matches a build echo name, with
-- parent chain, so we can find the real echo-select frame for a precise hook.
function DH.Scan()
  local set = BuildNameSet()
  PP.print("Echo-select scan (open a level-up echo choice first):")
  local function chain(f)
    local names, p, d = {}, f, 0
    while p and d < 5 do
      names[#names + 1] = tostring(p.GetName and p:GetName() or "?")
      p = p.GetParent and p:GetParent() or nil; d = d + 1
    end
    return table.concat(names, " < ")
  end
  local f, hits = EnumerateFrames(), 0
  while f and hits < 40 do
    if f.IsVisible and f:IsVisible() and f.GetRegions then
      for i = 1, select("#", f:GetRegions()) do
        local r = select(i, f:GetRegions())
        if r and r.GetObjectType and r:GetObjectType() == "FontString" then
          local txt = r:GetText()
          if txt and set[txt] then
            hits = hits + 1
            DEFAULT_CHAT_FRAME:AddMessage("  '" .. txt .. "' in [" .. chain(f) .. "]")
            break
          end
        end
      end
    end
    f = EnumerateFrames(f)
  end
  PP.print("Found " .. hits .. " echo-name frames. Screenshot this to build a precise hook.")
end
