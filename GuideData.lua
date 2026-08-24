-- PallyPilot GuideData: per-raid, per-boss solo guides for a Ret paladin on
-- Ebonhold. Written for the solo lens: which mechanic kills a solo player,
-- where Divine Shield is RESERVED, what Cleanse (poison+disease+magic) removes,
-- and where echo-level damage lets you skip mechanics entirely.
-- Zone names must match GetRealZoneText for auto-selection.
local PP = PallyPilot
local G = {}
PP.GuideData = G

-- Recurring paladin notes referenced by many fights:
--  * JoL   = Judgement of Light active (self-sustain off boss swings)
--  * DS    = Divine Shield; each fight says what it is SAVED for
--  * Cleanse removes one poison + one disease + one magic effect
--  * Holy Wrath STUNS undead adds (bosses immune) — huge in Naxx/ICC

G.raids = {
  {
    key = "naxx", name = "Naxxramas", zone = "Naxxramas",
    note = "All undead: Exorcism always crits, Holy Wrath stuns every add pack. "
      .. "This raid is paladin home turf. AotC I = Kel'Thuzad on 25.",
    bosses = {
      { n = "Anub'Rekhan", t = "Face-tank in the middle, AoE the scarabs.",
        tips = {
          "Ignore the kiting strat — that's for tanks without your HP. Stand and hit.",
          "Locust Swarm silences your casts; keep swinging, JoL carries you through.",
          "Corpse scarabs: Divine Storm + Consecration + Holy Wrath (they're undead — stunned).",
        } },
      { n = "Grand Widow Faerlina", t = "Burn her through Frenzy — you can't sacrifice worshippers solo.",
        tips = {
          "The worshipper-sacrifice Frenzy dispel needs a priest MC. Solo answer: cooldowns and speed.",
          "Frenzy every ~60s: pop a defensive / LoH if she frenzies while you're low.",
          "Rain of Fire is lazy — sidestep it, don't tank it.",
        } },
      { n = "Maexxna", t = "Web Spray is a 6s stun she attacks through — be topped before it.",
        tips = {
          "Web Spray every ~40s: enter it full HP; JoL heals you passively while stunned.",
          "If a spray will land while you're low, bubble it (DS is free this fight otherwise).",
          "Spiderlings after each spray: Consecration handles them while you're stunned.",
          "Web Wrap targets non-aggro players — solo, that's likely nobody. Confirm on pull 1.",
        } },
      { n = "Noth the Plaguebringer", t = "Trivial — AoE the teleport-phase skeletons.",
        tips = {
          "Cleanse his curse if you see one land (Curse of the Plaguebringer — magic school on some cores; try it).",
          "Balcony phases: skeleton waves. Holy Wrath stun + Divine Storm = free healing window.",
        } },
      { n = "Heigan the Unclean", t = "THE Dance. Your gear does not excuse you from it.",
        tips = {
          "Platform phase: stand at his hitbox edge, dodge Decrepit Fever puddles.",
          "Dance phase: safe zones sweep 1-2-3-4-3-2-1 across the room. Move early, not on the eruption.",
          "Your Ebonhold HP eats ONE eruption tick. Never two. Treat one as your mulligan.",
          "Cleanse Decrepit Fever — it's a disease.",
        } },
      { n = "Loatheb", t = "Necrotic Aura turns healing OFF — this disables your JoL sustain.",
        tips = {
          "Healing only works in the 3s window after each Spore (every ~20s). FoL/Holy Light IN the window, nothing outside it.",
          "Take every Spore — the crit buff stacks and this is a pure burn fight.",
          "No sustain = your one Naxx fight where damage taken is real. Keep LoH for a missed window.",
        } },
      { n = "Instructor Razuvious", t = "Raw EHP check — he's tuned for MC'd understudies you don't have.",
        tips = {
          "Unbalancing Strike hits for a lot and drops your defense — this is the hardest-hitting melee in Naxx.",
          "Full survival kit: Ardent Defender, JoL, FoL on Art of War procs between his slow swings.",
          "Open with Avenging Wrath — the shorter the fight, the fewer Unbalancing Strikes exist.",
          "If he's flatly out-damaging your sustain, this is your signal to buy more Iron Will/Ironhide affixes.",
        } },
      { n = "Gothik the Harvester", t = "Kill live-side waves; big AoE burst when the gate opens.",
        tips = {
          "Stay on the LIVE side. Dead-side spectral adds pile up unattended — that's fine.",
          "When the central gate opens, everything converges: Holy Wrath (mass stun) + Divine Storm + Consecration.",
          "Gothik lands at 4:30 — he's a pushover, the adds were the fight.",
        } },
      { n = "The Four Horsemen", t = "The Naxx solo wall: 4 bosses, stacking Marks. Answer = speed.",
        tips = {
          "Marks stack per boss hit/pulse and the damage ramps forever. Rotating corners solo is impossible — kill fast instead.",
          "Order: Thane Korth'azz -> Baron Rivendare (front melee pair), then run to the back: Lady Blaumeux, Sir Zeliek.",
          "Test on pull 1 whether Divine Shield clears your Mark stacks on this core — if yes, bubble between pairs and the fight is solved.",
          "Back two damage you at range regardless (Void Zone / Holy Wrath bolts) — don't dawdle up front.",
        } },
      { n = "Patchwerk", t = "Pure DPS race. Hateful Strike doesn't exist solo.",
        tips = {
          "Hateful Strike needs a 2nd person in melee — solo he just swings normally. JoL out-heals him.",
          "This is your DPS benchmark fight: 6min enrage. Time your kill — it calibrates the rest of the tier.",
        } },
      { n = "Grobbulus", t = "Walk the room edge; drop injection clouds behind you.",
        tips = {
          "Mutating Injection (on you, solo): run to the wall, let it pop there, return. Clouds are forever — place them tidy.",
          "It's a disease when it triggers — Cleanse the fallout.",
          "Slime adds from Slime Spray die to one Divine Storm. Kite pace: slow circle, never cross old clouds.",
        } },
      { n = "Gluth", t = "Decimate drops you to 5% — then zombies sprint to heal him.",
        tips = {
          "Post-Decimate: you're at 5% but JoL + one FoL fixes you. The REAL job is the zombie wave — Consecration + Holy Wrath before they reach him (each zombie eaten = 5% boss heal).",
          "Fight him at the far end from the zombie chute to buy AoE time.",
          "Cleanse Mortal Wound if it stacks high (it's a physical debuff on some cores — if uncleansable, just note your healing is reduced).",
        } },
      { n = "Thaddius", t = "Polarity doesn't exist solo. Kill the minibosses within 5s of each other.",
        tips = {
          "Feugen & Stalagg resurrect each other unless they die ~5s apart: drop one to 10%, kill the other, snap back and finish. Your burst makes this easy.",
          "MAKE THE JUMP to his platform — missing means tesla-coil death. Run, don't hesitate.",
          "Polarity Shift only damages OTHER players of opposite charge. Solo: ignore it completely and just DPS through every shift.",
          "6min enrage — with polarity ignored you'll beat it by minutes.",
        } },
      { n = "Sapphiron", t = "Bubble the air-phase Frost Breath. Cleanse Life Drain.",
        tips = {
          "Air phase: he casts a room-wide Frost Breath you normally LoS behind an Ice Tomb. If YOU get tombed, you're safe inside it. If not — Divine Shield the breath. DS is reserved for this.",
          "Life Drain is a MAGIC debuff that heals him off you — Cleanse it every time, instantly.",
          "Blizzards chase you on the ground — keep moving, never tank the frost aura low.",
          "Frost resistance affixes/echoes shine here if you have any banked.",
        } },
      { n = "Kel'Thuzad", t = "AotC I. Divine Shield exists for exactly one thing here: Frost Blast.",
        tips = {
          "Frost Blast ice-blocks you and deals ~104% of your HP over 4s. Solo it is lethal — Divine Shield removes/immunes it. NEVER spend bubble on anything else this fight.",
          "Between bubbles (Forbearance gap): stay topped so a Blast + one FoL after is survivable, or eat LoH.",
          "Detonate Mana: it drains and explodes — it's why you stay above 80% HP at all times.",
          "Shadow Fissure (void zone under you): move immediately, it one-shots.",
          "P1: don't touch the adds, he pulls you in himself. P3 Guardians of Icecrown: ignore, burn him — this is the kill window race.",
        } },
    },
  },
  {
    key = "os", name = "Obsidian Sanctum", zone = "The Obsidian Sanctum",
    note = "One boss + three optional drakes. Drakes left alive buff Sartharion hard.",
    bosses = {
      { n = "Sartharion", t = "Kill the three drakes around the ledge first, then it's a lava-wave dodge.",
        tips = {
          "Each living twilight drake = a big buff to him (this is the 'Sarth +N' hard mode). Clear Tenebron, Shadron, Vesperon unless you're deliberately hard-moding for loot.",
          "Flame Wall: lava waves sweep the platform with visible gaps — stand in the gap, keep hitting.",
          "Fire elemental adds during waves: Divine Storm food.",
        } },
    },
  },
  {
    key = "eoe", name = "Eye of Eternity", zone = "The Eye of Eternity",
    note = "Malygos P3 puts you on a drake — your echoes and gear stop mattering. Mechanics only.",
    bosses = {
      { n = "Malygos", t = "P1/P2 are trivial; P3 is a vehicle fight your power can't skip.",
        tips = {
          "P1: burn; Power Sparks fly to him — kill them ON you so you eat the damage buff.",
          "P2: nexus lords on discs die to your burst; stay in an Anti-Magic bubble zone during deep breath.",
          "P3 (drake): keep ability 1's DoT stacked x5, refresh with 1, dump combo points with 2, and hold 5 (shield) for every Surge of Power he aims at you. This phase is practice, not gear.",
          "Solo P3 tip: it's a DPS race against his Static Field spam — DoT uptime is everything.",
        } },
    },
  },
  {
    key = "ony", name = "Onyxia's Lair", zone = "Onyxia's Lair",
    note = "A victory lap at your power level.",
    bosses = {
      { n = "Onyxia", t = "Whelps in P2, don't stand in front (breath) or behind (tail).",
        tips = {
          "P2 air phase: Deep Breath telegraphs — run to a side wall. Whelp waves: Consecration + Holy Wrath.",
          "P3: fear — bubble drops it if it chains badly; otherwise stand on her flank and end it.",
        } },
    },
  },
  {
    key = "ulduar", name = "Ulduar", zone = "Ulduar",
    note = "The mechanics tier. Several fights ignore raw power — read before pulling.",
    bosses = {
      { n = "Flame Leviathan", t = "Vehicle fight — take a Siege Engine, kill towers first for easy mode.",
        tips = {
          "Your gear barely matters in a vehicle. Kill the four towers on the approach or he gains hard-mode buffs.",
          "Siege Engine: ram him, interrupt Flame Vents with the ram, keep moving when Pursued.",
        } },
      { n = "Ignis the Furnace Master", t = "Ignore constructs, heal through Slag Pot, burn.",
        tips = {
          "Slag Pot grabs you for 10s of heavy fire damage — be topped, FoL after. Bubble it if you're low.",
          "Constructs he summons only matter with Strength of the Creator stacking — with your kill speed he dies before it counts.",
          "Flame Jets interrupt casts — swing timing only, melee doesn't care.",
        } },
      { n = "Razorscale", t = "Solo you run the harpoons yourself between add waves.",
        tips = {
          "Air phase: kill dark rune adds (Holy Wrath stun does NOT work — they're not undead; use Repentance on the sentinel), then fire each repaired harpoon to drag her down.",
          "Grounded phase is your burn window — Avenging Wrath here, every time.",
          "Two grounding cycles should end it at your damage. Move out of Devouring Flame circles.",
        } },
      { n = "XT-002 Deconstructor", t = "Heart phases are bonus damage — but killing the heart STARTS HARD MODE.",
        tips = {
          "During Heart exposure: damage the heart for massive bonus boss damage, but STOP before it dies unless you want the hard-mode fight.",
          "Gravity Bomb / Light Bomb on you: run away from where you were standing (solo: just keep moving outward).",
          "Tantrum: heavy raid damage for 12s — JoL plus one FoL covers it.",
          "Scrapbots heal him if they reach him: Consecration across the bot lanes.",
        } },
      { n = "Assembly of Iron", t = "Kill Steelbreaker FIRST. Cleanse Fusion Punch — it's magic.",
        tips = {
          "Steelbreaker's Fusion Punch is the killer, and Cleanse removes the debuff it leaves. Kill him first so the fight de-fangs.",
          "Then Runemaster Molgeim (Rune of Death: move out), Brundir last (Chain Lightning; run out of his Lightning Whirl).",
          "Each death empowers the survivors — order matters more than speed here.",
        } },
      { n = "Kologarn", t = "You can attack the arm WHILE it grips you.",
        tips = {
          "Stone Grip: he squeezes you; keep DPSing the right arm from inside the grip — arm dies, you drop.",
          "Focused Eyebeam chases you — walk it in a line away, don't panic-sprint.",
          "Killing arms deals him 15% each and spawns rubble adds — Divine Storm them.",
        } },
      { n = "Auriaya", t = "The pull is the fight — sentry cats pounce hard.",
        tips = {
          "Pull her WITH the cats deliberately: bubble the pounce burst, then Consecration + Holy Wrath ground them.",
          "Terrifying Screech fear: bubble breaks it, but you likely used DS on the pull — position against a wall so you don't fear-walk into packs.",
          "Feral Defender add revives itself 4 times: ignore it, burn her, it dies with her.",
        } },
      { n = "Hodir", t = "Stand on a snow mound when Flash Freeze casts.",
        tips = {
          "Icicles drop snow piles: when Flash Freeze begins (long cast), get ON a pile or you're frozen solid and the fight resets on you.",
          "Frozen Blows: heavy frost phase — JoL through it or bubble one.",
          "Don't bother freeing NPCs at your power — pure solo burn is simpler.",
        } },
      { n = "Thorim", t = "Clear the arena start, run the gauntlet solo, he descends.",
        tips = {
          "The fight is a split (arena team + gauntlet team). Solo: kill the starting arena pack, then run the gauntlet corridor yourself — arena adds keep spawning but nobody's there to die to them.",
          "Gauntlet: iron dwarves + a mini-boss; burn through, hit the end, Thorim jumps down.",
          "Descended: Unbalancing Strike again (Razuvious rules) + Chain Lightning. Kill him before Sif's blizzard stacks make the arena unlivable.",
        } },
      { n = "Freya", t = "Six minutes of add waves, then a naked boss.",
        tips = {
          "Three wave types rotate: the healing trio must die TOGETHER (drop all three low, Divine Storm finish); the Ancient Conservator drops healing spores — stand in one to keep casting; snaplasher/lashers just die.",
          "Eonar's Gift (the tree): kill it instantly, it heals her massively.",
          "After wave 6 she has no protection — burn phase.",
        } },
      { n = "Mimiron", t = "Four phases of pure mechanics. Slow is smooth here.",
        tips = {
          "P1 (tank): Proximity Mines — walk around them; Plasma Blast is huge damage — FoL through or bubble; Napalm Shell hits where you aren't — stay near the tank.",
          "P2 (head): Rocket Strike red circles = one-shot, move; kill turrets if the barrage overwhelms, otherwise burn head.",
          "P3 (aerial): kill the assault bots, ignore swarms, burn the head when magnetically grounded.",
          "P4 (all three): parts must die within ~10s of each other — drop each to ~15%, then finish them in one Avenging Wrath sweep.",
        } },
      { n = "General Vezax", t = "His aura kills your mana regen. Shadow Crash puddles give it back.",
        tips = {
          "Judgements of the Wise and Divine Plea are dead under his aura. Stand in a SPENT Shadow Crash green puddle for the leech buff — that's your mana this fight (dodge the crash itself).",
          "Mark of the Faceless: run AWAY from him while marked — it leeches your healing to him.",
          "Kite past Saronite Vapors clouds; pop one only if truly OOM (it damages while restoring).",
        } },
      { n = "Yogg-Saron", t = "Hardest solo fight in Ulduar. Sanity is the resource, not HP.",
        tips = {
          "BEFORE the pull: talk to all four Keepers so their sanity auras are active.",
          "P1: kill the green clouds' spawned Guardians ON Sara — their death explosions damage her (don't walk through clouds: more spawns).",
          "P2: melee the tentacles; when Brain Link ties you to no one (solo) it should self-clear — confirm pull 1. Enter the portal when it opens: inside, burst the tentacles/brain, LEAVE before the 60s insanity timer.",
          "Sanity low? Stand in a green Sanity Well and DON'T look at Yogg (face away during Lunatic Gaze).",
          "P3: kill Immortal Guardians to 1hp (they can't die — Thorim's aura finishes them if he's up), burn the exposed brain.",
        } },
      { n = "Algalon the Observer", t = "Optional. One-hour weekly window, hard enrage feel.",
        tips = {
          "Cosmic Smash craters: move. Black Holes spawn from Collapsing Stars — kill stars AWAY from you (the explosion hurts).",
          "During Big Bang: JUMP INTO a Black Hole to survive it, kill the void adds inside, come out.",
          "Solo he's a sustained check of everything Ulduar taught — bring him your best affix set.",
        } },
    },
  },
  {
    key = "toc", name = "Trial of the Crusader", zone = "Trial of the Crusader",
    note = "Short raid, no trash. Cleanse is the star: it removes the two nastiest debuffs in here.",
    bosses = {
      { n = "Northrend Beasts", t = "Three acts. Cleanse the Paralytic Toxin — it solves the solo-killer.",
        tips = {
          "Gormok: kill the Snobolds that jump on your head (they interrupt); Impale bleed stacks — JoL out-heals 2-3 stacks.",
          "Jormungars: Acidmaw's Paralytic Toxin normally needs a fire-debuffed ally to touch you — solo that's nobody. CLEANSE IT (it's a poison). Kill Acidmaw first anyway.",
          "Icehowl: when he charges, RUN from the wall he threw you at — getting hit = enrage = probable death. Massive Crash stun into charge is the whole fight.",
        } },
      { n = "Lord Jaraxxus", t = "FoL off the Incinerate Flesh debuff or it detonates.",
        tips = {
          "Incinerate Flesh must be HEALED off (absorbs your healing until removed) — spam FoL/Holy Light immediately; LoH clears it instantly if deep.",
          "Cleanse Fel Fireball's burn (magic). Move from Legion Flame trails.",
          "Mistress of Pain / Infernal adds: at your damage, ignore and burn him — he dies before they stack.",
        } },
      { n = "Faction Champions", t = "A PvP team fights you. Kill healers first, bubble their burst.",
        tips = {
          "This is the one fight where enemy count beats raw power. Open with Repentance on a healer, burst the OTHER healer.",
          "Divine Shield when their CC/burst chains onto you — it's a PvP trinket here, not a mechanic answer.",
          "Their damage is player-like: erratic, interruptible, fearful of Consecration. Fight dirty, use LoS around the pillars.",
        } },
      { n = "Twin Val'kyr", t = "Take one essence color, attack the OPPOSITE twin, soak your-color orbs.",
        tips = {
          "Click a Dark essence portal, then attack the LIGHT twin (opposite color = full damage). Dark orbs floating around now HEAL/energize you — walk through them; Light orbs hurt.",
          "Twin's Pact (the big heal): you can't interrupt it as Ret — burn harder through the shield; breaking the shield stops the cast.",
          "During Light Vortex, be holding Light essence (swap at a portal) or bubble it.",
        } },
      { n = "Anub'arak", t = "Fight him ON permafrost patches; P3 he eats your HP to heal.",
        tips = {
          "Don't kill the Frost Spheres wastefully — pop them to make permafrost where you'll stand. During burrow, spikes chasing you shatter on permafrost.",
          "Adds: Burrowers cast Shadow Strike from underground lines — Consecration flushes; Swarm Scarabs are Divine Storm food.",
          "P3 Leeching Swarm heals him off your HP every second — it's a pure race: Avenging Wrath, trinkets, everything at 30%.",
        } },
    },
  },
  {
    key = "icc", name = "Icecrown Citadel", zone = "Icecrown Citadel",
    note = "Undead again — Exorcism/Holy Wrath territory. Several fights have hard solo timers; they're marked.",
    bosses = {
      { n = "Lord Marrowgar", t = "Bubble is reserved for Bone Spike impale. Everything else is footwork.",
        tips = {
          "Bone Spike usually skips the aggro target (you, solo) — confirm pull 1. If it DOES spike you: Divine Shield removes Impaled. Never spend DS on anything else.",
          "Bone Slice hits you for its full split damage solo — JoL + 5-stack Vengeance mostly cancels it.",
          "Coldflame lines: strafe circles, never backpedal. In Bone Storm, chase him and keep hitting; fire is the real killer, not the storm damage.",
        } },
      { n = "Lady Deathwhisper", t = "P1 burn the mana shield; adds are undead — stun-lock them.",
        tips = {
          "P1: her Mana Barrier absorbs damage — adds spawn while you chew it. Holy Wrath STUNS the whole add wave (all undead); Divine Storm + Consecration during the stun.",
          "Death and Decay isn't cleansable — just move out of the green. Cleanse any chill the adds land on you.",
          "P2: Frostbolts hurt (no Ret interrupt) — face-tank with JoL, dodge the Vengeful Shade ghosts (they detonate).",
        } },
      { n = "Gunship Battle", t = "Jetpack over, kill the enemy sorcerer, come home. Repeat.",
        tips = {
          "Your cannons freeze when their sorcerer channels: rocket-pack to their ship, kill the Battle-Mage, jump back.",
          "Kill boarding axethrowers/sergeants between crossings — Battle Fury stacking on unattended adds adds up.",
          "Functionally unlosable at your power. Enjoy the loot chest.",
        } },
      { n = "Deathbringer Saurfang", t = "Blood Beasts must not touch you — every touch feeds his Blood Power.",
        tips = {
          "Blood Beasts (2 per wave): the moment they spawn, Hammer of Wrath/Exorcism/Judgement one at range and Holy Wrath-stun the pack — they're undead. Beasts reaching you = Blood Power = faster Marks.",
          "Mark of the Fallen Champion (at 100 BP) heals him off damage YOU take — one Mark is sustainable with JoL, two is a race.",
          "Boiling Blood/Rune of Blood: Cleanse what's cleansable, out-heal the rest. This fight is add discipline, nothing else.",
        } },
      { n = "Festergut", t = "Easiest ICC boss solo — spores come to you by default.",
        tips = {
          "Gas Spores land on players — solo, that's always you, so you build Inoculation stacks naturally. Have 3 stacks before his 3rd Inhale, or Pungent Blight kills you.",
          "Between inhales his damage ramps — JoL sustains through even 3-inhale melee.",
          "Vile Gas only targets ranged — you're melee, it doesn't exist. Burn.",
        } },
      { n = "Rotface", t = "Cleanse controls the ooze timing; kite the big ooze while bossing.",
        tips = {
          "Mutated Infection is a DISEASE — Cleanse it ON YOUR TIMING (removal spawns the little ooze; cleanse when you're positioned, not when it expires on top of you).",
          "Little oozes chase you and merge into a Big Ooze — walk it in a slow circle around him while you DPS.",
          "Big Ooze's Unstable explosion at 5 merges: be elsewhere. Slime Spray: sidestep. If your DPS is high enough, he dies around merge 2-3.",
        } },
      { n = "Professor Putricide", t = "Kill the Volatile Ooze that fixates you; race P3.",
        tips = {
          "Green Volatile Ooze fixates and explodes on reaching you — it's slow: Hammer of Wrath/Exorcism it down at range, kite backward. Orange Gas Cloud same idea.",
          "Malleable Goo (thrown bouncing goo): dodge — 20s of half-speed attacks otherwise.",
          "P3 (35%): Mutated Plague stacks on you forever — it's the enrage. Everything you have at 36%: Wings, trinkets, LoH as a second HP bar.",
          "Tear Gas at 80/35% freezes the room — free breather, drink if you need mana.",
        } },
      { n = "Blood Prince Council", t = "One HP pool, three bodies. Attack whoever glows.",
        tips = {
          "Only the EMPOWERED prince (glowing, rotates ~30s) takes real damage — swap targets when the glow moves.",
          "Kinetic Bombs falling to the floor = raid explosion: hit the bomb once (any attack) to bounce it back up. Watch for them while bossing.",
          "Keleseth's Dark Nuclei: at your power, skip nucleus-collecting — out-heal his shadow damage with JoL.",
          "Empowered Vortex (Valanar): spread means nothing solo; just don't stand in Shock Vortex zones.",
        } },
      { n = "Blood-Queen Lana'thel", t = "SOLO TIMER: ~75s. The bite has no one to pass to.",
        tips = {
          "Frenzied Bloodthirst hits YOU (highest damage = you). Solo there is nobody to bite, so when the timer ends you're mind-controlled = wipe. Kill her before it ends.",
          "That means: full burst opener, Wings on pull, every cooldown, Bloodlust-tier echoes if you have them. This is THE DPS check of the wing.",
          "Pact of the Darkfallen (links players): solo it should fizzle/self-clear — if it ticks on you anyway, stand ON her hitbox to break it.",
          "Swarming Shadows: drop the shadow flames at the room edge, keep uptime.",
        } },
      { n = "Valithria Dreamwalker", t = "You WIN by healing her to full. Ret can, slowly.",
        tips = {
          "Kill adds (Blazing Skeletons FIRST — Lay Waste wrecks her; Suppressers channel on her — they die to one hit) and heal her in the gaps.",
          "Take every Nightmare Portal: inside, pop Emerald Vigor clouds — each stack = +10% healing done and mana back. Stack high, then Holy Light spam her.",
          "Sheath of Light means your AP makes your Holy Lights real. It's a long fight solo — it's add control + portal greed, not a race.",
        } },
      { n = "Sindragosa", t = "Bubble answers either an Ice Tomb or a Mystic Buffet reset — pick per attempt.",
        tips = {
          "Air phase: Frost Beacon marks you -> Ice Tomb. Solo: bubble the beacon to skip the tomb, or eat the tomb and cooldown through Frost Bomb (the tomb blocks bomb LoS if positioned on the bomb line... solo, bubble is simpler).",
          "P3: Mystic Buffet stacks magic-taken forever — normally reset by hiding behind a tomb; solo, Divine Shield wipes the stacks. Save it for stack 5-6+.",
          "Unchained Magic mostly hits casters — your instants rarely trigger backlash; keep Cleanse ready for Frost Fever-style chill.",
          "Blistering Cold (the big suck-in): SPRINT out — it's a one-shot. Tail/breath positioning: fight her flank, always.",
        } },
      { n = "The Lich King", t = "The final exam. Defile placement decides it; Val'kyr is the solo coin-flip.",
        tips = {
          "Necrotic Plague (P1): Cleanse it INSTANTLY (disease) — it jumps to a ghoul and snowballs through the adds, which is fine.",
          "Defile: the moment it casts, RUN — drop it at the platform edge, far from center. A grown Defile ends the attempt. This is the #1 wipe cause at any power level.",
          "Val'kyr Shadowguard grabs you (solo: always you) and flies you toward the edge — burst her down before the drop (she releases at 50% on 10N). All damage, immediately, every time. If your burst can't do it, this is the wall.",
          "Soul Reaper: 5s later it hits huge — be topped or bubble one late-fight.",
          "P3: Vile Spirits rain — kite through, don't tank clouds. Harvest Soul pulls you into Frostmourne: kill the Spirit Warden inside with Terenas, you pop back out.",
          "At 10%: he kills you. Scripted. Terenas rezzes you and you win. Do not release.",
        } },
    },
  },
}

-- Flat lookup: normalized boss name -> { boss = entry, raid = raidEntry }.
local index
local function Norm(s)
  return s and string.lower((s:gsub("’", "'"))) or nil
end
local function BuildIndex()
  index = {}
  for _, raid in ipairs(G.raids) do
    for _, boss in ipairs(raid.bosses) do
      index[Norm(boss.n)] = { boss = boss, raid = raid }
    end
  end
end

-- Exact, then substring match ("marrowgar" finds "Lord Marrowgar").
function G.FindBoss(name)
  if not name or name == "" then return nil end
  if not index then BuildIndex() end
  local q = Norm(name)
  if index[q] then return index[q].boss, index[q].raid end
  for key, hit in pairs(index) do
    if string.find(key, q, 1, true) or string.find(q, key, 1, true) then
      return hit.boss, hit.raid
    end
  end
  return nil
end

function G.RaidForZone(zone)
  if not zone then return nil end
  for _, raid in ipairs(G.raids) do
    if raid.zone == zone then return raid end
  end
  return nil
end
