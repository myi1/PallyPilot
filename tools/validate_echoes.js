"use strict";
// Validate every class's CURATED echo names against the server's PerkDatabase
// dump, on two axes:
//   1. NAME EXISTS  -- a curated name not in the DB is a phantom rating: it can
//      never match, so the echo it was meant to cover stays unrated forever.
//      (Real example: "Echoing Affliction" is a phantom; the echo is the PLURAL
//      "Echoing Afflictions".)
//   2. DRAFTABLE    -- each perk carries a `classMask` bitmask of the classes
//      that can draw it. Rating an echo your class cannot draw is dead weight.
// classMask bits are 1<<(classId-1): Warrior 1, Paladin 2, Hunter 4, Rogue 8,
// Priest 16, DK 32, Shaman 64, Mage 128, Warlock 256, Druid 1024.
//
// Usage: node tools/validate_echoes.js [path-to-SavedVariables/PallyPilot.lua]
const fs = require("fs"), path = require("path");
const SV = process.argv[2] ||
  "E:/Games/Ebonhold/WTF/Account/KEEPSY/SavedVariables/PallyPilot.lua";
const ADDON = path.resolve(__dirname, "..");

const CLASS_BIT = { WARRIOR: 1, PALADIN: 2, HUNTER: 4, ROGUE: 8, PRIEST: 16,
  DEATHKNIGHT: 32, SHAMAN: 64, MAGE: 128, WARLOCK: 256, DRUID: 1024 };

const norm = s => s.replace(/\u2019/g, "'").trim().toLowerCase();
const stripQ = s => s.replace(/\s*-\s*(Common|Uncommon|Rare|Epic|Legendary|Artifact)\s*$/i, "").trim();

// --- perk DB: name -> union of classMask across its quality variants ---
const sv = fs.readFileSync(SV, "utf8");
const byId = {};
for (const m of sv.matchAll(/Perk\.(\d+)\.comment = ([^"]+)"/g)) byId[m[1]] = { name: stripQ(m[2].trim()) };
for (const m of sv.matchAll(/Perk\.(\d+)\.classMask = (\d+)/g)) if (byId[m[1]]) byId[m[1]].mask = +m[2];
const maskByName = {};
for (const id of Object.keys(byId)) {
  const e = byId[id]; if (!e.name) continue;
  const k = norm(e.name);
  maskByName[k] = (maskByName[k] || 0) | (e.mask || 0);
}
const dbCount = Object.keys(maskByName).length;
if (!dbCount) { console.error("No perk dump found in " + SV + " (run /ep perkscan, then /reload)"); process.exit(2); }

// --- curated names per class, straight out of the Lua source ---
function curated(file, prefix) {
  const src = fs.readFileSync(path.join(ADDON, file), "utf8");
  const out = new Map();                       // normalized -> {shown, where[]}
  const add = (raw, where) => {
    const k = norm(raw);
    if (!out.has(k)) out.set(k, { shown: raw, where: new Set() });
    out.get(k).where.add(where);
  };
  const block = (re, where) => {
    const m = src.match(re); if (!m) return;
    for (const n of m[1].matchAll(/"([^"]+)"/g)) add(n[1], where);
  };
  block(new RegExp(`\\${prefix}\\.locked = \\{([\\s\\S]*?)\\n\\}`), "locked");
  block(new RegExp(`\\${prefix}\\.disable = \\{([\\s\\S]*?)\\n\\}`), "disable");
  const tiers = src.match(new RegExp(`\\${prefix}\\.tiers = \\{([\\s\\S]*?)\\n\\}`));
  if (tiers) for (const t of tiers[1].matchAll(/\b([SAB]) = \{([\s\S]*?)\}/g))
    for (const n of t[2].matchAll(/"([^"]+)"/g)) add(n[1], "tiers." + t[1]);
  const bundles = src.match(new RegExp(`\\${prefix}\\.bundles = \\{([\\s\\S]*?)\\n\\}`));
  if (bundles) for (const n of bundles[1].matchAll(/"([^"]+)"/g))
    if (!/^(eph|ppb)-/.test(n[1]) && !/^[SAB]$/.test(n[1])) add(n[1], "bundles");
  // catalog: ["Name"] = "S"
  for (const c of src.matchAll(/\["([^"]+)"\]\s*=\s*"([SABCF])"/g)) add(c[1], "catalog");
  return out;
}
const FILES = { PALADIN: ["BuildData.lua", "B"], HUNTER: ["HunterData.lua", "H"],
                PRIEST: ["PriestData.lua", "B"] };

let problems = 0;
console.log(`perk DB: ${dbCount} distinct echo names\n`);
for (const [cls, [file, prefix]] of Object.entries(FILES)) {
  if (!fs.existsSync(path.join(ADDON, file))) continue;
  const bit = CLASS_BIT[cls];
  const names = curated(file, prefix);
  const phantom = [], undraftable = [];
  for (const [k, v] of names) {
    const mask = maskByName[k];
    if (mask === undefined) phantom.push(`${v.shown}  [${[...v.where].join(",")}]`);
    else if (bit && mask && !(mask & bit)) undraftable.push(`${v.shown}  [${[...v.where].join(",")}]`);
  }
  const draftable = Object.entries(maskByName).filter(([, m]) => !m || (m & bit)).length;
  console.log(`=== ${cls} === curated ${names.size} | ${draftable}/${dbCount} echoes draftable by this class`);
  if (phantom.length) { problems += phantom.length;
    console.log(`  PHANTOM NAMES -- not in the perk DB, can never match (${phantom.length}):`);
    phantom.sort().forEach(p => console.log("    " + p)); }
  if (undraftable.length) { problems += undraftable.length;
    console.log(`  NOT DRAFTABLE by ${cls} -- classMask excludes it (${undraftable.length}):`);
    undraftable.sort().forEach(p => console.log("    " + p)); }
  if (!phantom.length && !undraftable.length) console.log("  OK -- every curated name exists and is draftable");
  console.log("");
}
console.log(problems === 0 ? "ECHOES OK" : `ECHO PROBLEMS: ${problems}`);
process.exit(problems === 0 ? 0 : 1);
