-- PallyPilot AshAdvisor: Soul Ash spending priorities for the solo Ret
-- climb (AotC I -> Hardcore). PROVISIONAL: built from the codex/community
-- consensus in EBONHOLD-SYSTEM.md §6. Node-exact costs and values arrive
-- once /pp uiscan ash maps the tree; then this becomes a real optimizer
-- that reads your banked ash and current ranks.
local PP = PallyPilot
local AA = PP.AshAdvisor

local GOLD = "|cffe0b352"
local BRIGHT = "|cfff6d888"
local DIM = "|cffb4a586"
local VERD = "|cff8aa96a"
local R = "|r"

local PRIORITIES = {
  { "25M milestone — all 5 echo lock slots",
    "If not yet bought, NOTHING beats this: locks persist across every death." },
  { "Stamina (infinite node)",
    "The survival spine. Deaths end runs; effective HP is the currency of solo raiding. Keep feeding it between big buys." },
  { "Cheat Death charges",
    "Each charge is a free run-continuation. Stacks with Reaper's Reprieve for a deep death-protection wall." },
  { "Self-resurrection",
    "Turns a raid wipe into a walk back. Pairs with the pay-10%-to-continue economy — always bank enough to afford it." },
  { "Attack/Spell Power (infinite node)",
    "Offense engine — reads your higher stat, so it always feeds Ret." },
  { "Highest Attribute (infinite node, ramping)",
    "Per-rank value RAMPS with investment (up to +20/rank) — shallow buys are weak, deep buys compound. Commit late, then commit hard." },
  { "Cold Weather Flying + riding",
    "Quality-of-run; flagged 'Carry over Prestige' so it's never wasted ash." },
}

function AA.Report()
  PP.print(GOLD .. "Soul Ash priorities (solo Ret)" .. R .. DIM
    .. " — provisional until /pp uiscan ash maps the tree:" .. R)
  for i, p in ipairs(PRIORITIES) do
    DEFAULT_CHAT_FRAME:AddMessage("  " .. GOLD .. i .. "." .. R .. " "
      .. BRIGHT .. p[1] .. R)
    DEFAULT_CHAT_FRAME:AddMessage("     " .. DIM .. p[2] .. R)
  end
  DEFAULT_CHAT_FRAME:AddMessage("  " .. DIM
    .. "Rules of thumb: survival spine before offense; never spend down below "
    .. "the 10% pay-to-continue cost of a good run; raid-ID resets cost ash "
    .. "and escalate x5 each time — reset sparingly." .. R)
  DEFAULT_CHAT_FRAME:AddMessage("  " .. VERD
    .. "For exact next-best-buy advice: open the Skill Tree tab, run "
    .. "/pp uiscan ash, then /reload and tell Claude." .. R)
end
