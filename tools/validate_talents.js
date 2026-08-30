"use strict";
// Validate every class's talentTemplates against Ebonhold's ACTUAL talent trees
// (the client's custom Talent.dbc). Catches the silent-skip failure: a template
// naming a talent that doesn't exist on this server is quietly ignored by the
// applier, so the player just never gets those points -- with no error anywhere.
// Ebonhold both RENAMES retail talents and ADDS custom ones (priest: retail
// "Shadow Affinity" -> "Shadow Eruption"; hunter gains "Wild Thrash"/"Lacerate").
//
// Usage:  node tools/validate_talents.js <dir-with-Talent.dbc-and-Spell.dbc>
const fs = require("fs"), path = require("path");
const DBC = process.argv[2];
if (!DBC) { console.error("usage: node tools/validate_talents.js <dbc-dir>"); process.exit(2); }

function readDBC(p) {
  const b = fs.readFileSync(p);
  if (b.toString("ascii", 0, 4) !== "WDBC") throw new Error("not WDBC: " + p);
  const rows = b.readUInt32LE(4), rs = b.readUInt32LE(12), ss = b.readUInt32LE(16);
  const d = 20, so = d + rows * rs;
  return { rows,
    u32: (r, f) => b.readUInt32LE(d + r * rs + f * 4),
    str: (r, f) => { const o = b.readUInt32LE(d + r * rs + f * 4);
      if (!o || o >= ss) return ""; let e = so + o; while (e < b.length && b[e] !== 0) e++;
      return b.toString("utf8", so + o, e); } };
}
const spell = readDBC(path.join(DBC, "Spell.dbc"));
const sname = {};
for (let r = 0; r < spell.rows; r++) { const n = spell.str(r, 136); if (n) sname[spell.u32(r, 0)] = n; }

// tab -> { talentName: maxRank }
const T = readDBC(path.join(DBC, "Talent.dbc"));
const tabs = {};
for (let r = 0; r < T.rows; r++) {
  const tab = T.u32(r, 1);
  let name = "", ranks = 0;
  for (let k = 0; k < 9; k++) { const s = T.u32(r, 4 + k); if (s) { ranks++; if (!name) name = sname[s] || ""; } }
  if (name) ((tabs[tab] ||= {}))[name] = ranks;
}
// 3.3.5 TalentTab ids per class.
const CLASS_TABS = {
  PALADIN: [382, 383, 381], HUNTER: [361, 363, 362], PRIEST: [201, 202, 203],
};

// Load the class data files (pure tables).
global.PallyPilot = { Classes: {} }; global.EbonPilot = global.PallyPilot;
const ADDON = path.resolve(__dirname, "..");
const { execFileSync } = require("child_process");
// Read talentTemplates straight out of the Lua source (no interpreter needed):
// name = rank pairs inside each template's `talents = { ... }` block.
function templatesOf(file) {
  const src = fs.readFileSync(path.join(ADDON, file), "utf8");
  const out = {};
  for (const m of src.matchAll(/\["([\w-]+)"\]\s*=\s*\{\s*\n\s*name\s*=\s*"([^"]*)"[\s\S]*?talents\s*=\s*\{([\s\S]*?)\n\s*\}/g)) {
    const t = {};
    for (const p of m[3].matchAll(/\["([^"]+)"\]\s*=\s*(\d+)/g)) t[p[1]] = +p[2];
    out[m[1]] = { name: m[2], talents: t };
  }
  return out;
}
const FILES = { PALADIN: "BuildData.lua", HUNTER: "HunterData.lua", PRIEST: "PriestData.lua" };

let bad = 0;
for (const [cls, file] of Object.entries(FILES)) {
  if (!fs.existsSync(path.join(ADDON, file))) continue;
  const valid = {};
  for (const tab of CLASS_TABS[cls] || []) Object.assign(valid, tabs[tab] || {});
  const tpls = templatesOf(file);
  const n = Object.keys(tpls).length;
  if (!n) { console.log(`  --   ${cls}: no talentTemplates`); continue; }
  for (const [key, tpl] of Object.entries(tpls)) {
    const missing = [], over = [];
    for (const [name, rank] of Object.entries(tpl.talents)) {
      const max = valid[name];
      if (max === undefined) missing.push(name);
      else if (rank > max) over.push(`${name} ${rank}>${max}`);
    }
    if (missing.length || over.length) {
      bad++;
      console.log(`  FAIL ${cls}/${key}`);
      if (missing.length) console.log(`         NOT IN TREE (silently skipped): ${missing.join(", ")}`);
      if (over.length) console.log(`         RANK TOO HIGH (clamped): ${over.join(", ")}`);
    } else {
      console.log(`  OK   ${cls}/${key}  (${Object.keys(tpl.talents).length} talents)`);
    }
  }
}
console.log(bad === 0 ? "\nTALENTS OK" : `\nTALENT PROBLEMS: ${bad} template(s)`);
process.exit(bad === 0 ? 0 : 1);
