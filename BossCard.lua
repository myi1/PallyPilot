-- PallyPilot BossCard: target a known raid boss and the solo guide appears
-- as a compact card — once per boss per session, dismissable, no command.
local PP = PallyPilot
local BC = PP.BossCard

local GOLD = "|cffe0b352"
local BRIGHT = "|cfff6d888"
local DIM = "|cffb4a586"
local EMBER = "|cffd9694a"
local R = "|r"

local frame, fs
local shown = {}   -- bossName -> true (this session)
local HIDE_AFTER = 30

local function BuildCard()
  if frame then return end
  frame = CreateFrame("Frame", "PallyPilotBossCard", UIParent)
  frame:SetWidth(380)
  frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
  frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 24,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  frame:SetFrameStrata("HIGH")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

  fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
  fs:SetWidth(336)
  fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
  fs:SetSpacing(2)

  frame.elapsed = 0
  frame:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed > HIDE_AFTER then self:Hide() end
  end)
  frame:Hide()
end

function BC.Show(boss, raid)
  BuildCard()
  local t = {}
  t[#t+1] = GOLD .. string.upper(boss.n) .. R .. DIM .. "  · " .. raid.name .. R
  t[#t+1] = EMBER .. boss.t .. R
  for _, tip in ipairs(boss.tips) do
    t[#t+1] = BRIGHT .. "* " .. R .. tip
  end
  t[#t+1] = DIM .. "(/pp boss reprints this · card fades in " .. HIDE_AFTER .. "s)" .. R
  fs:SetText(table.concat(t, "\n"))
  -- GetStringHeight, not GetHeight: GetHeight is stale immediately after
  -- SetText, so the card was sized to the PREVIOUS boss (and to zero on the
  -- first one of a session).
  frame:SetHeight(fs:GetStringHeight() + 34)
  frame.elapsed = 0
  frame:Show()
end

local function OnTarget()
  local name = UnitName("target")
  if not name or shown[name] then return end
  -- Only fire on actual raid bosses: elite + max-level-skull or boss unit.
  if UnitIsPlayer("target") or UnitIsFriend("player", "target") then return end
  local boss, raid = PP.GuideData.FindBoss(name)
  if not boss then return end
  shown[name] = true
  BC.Show(boss, raid)
end

function BC.Init()
  local ev = CreateFrame("Frame")
  ev:RegisterEvent("PLAYER_TARGET_CHANGED")
  ev:SetScript("OnEvent", function() PP.safeCall(OnTarget) end)
end
