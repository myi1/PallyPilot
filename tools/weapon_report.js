// WHICH WEAPON SETUP ACTUALLY PERFORMS?
//
// Every fight records the weapons that were equipped and the stats that drive
// swing rate (CombatMeter.WeaponSnapshot), so no bench tag is ever typed --
// swap weapons, play, and this groups the log by what you were holding.
//
// The question it exists to settle: this character's damage is ~94% echo procs
// and only ~3.6% white swings, so the weapon is a proc-delivery device. If that
// is right, a FASTER weapon should out-perform a harder-hitting slow one, and
// procs-per-swing should stay roughly flat while procs-per-SECOND rises.
//
//   node tools/weapon_report.js [path\to\PallyPilot.lua]
//
// Defaults to the KEEPSY SavedVariables path but takes any file, so it works
// for another character or a copied-off log.
const fs = require('fs');
const path = require('path');

const DEFAULT_SV = 'E:\\Games\\Ebonhold\\WTF\\Account\\KEEPSY\\SavedVariables\\PallyPilot.lua';
const file = process.argv[2] || DEFAULT_SV;

if (!fs.existsSync(file)) {
  console.error('No SavedVariables at: ' + file);
  console.error('Pass a path: node tools/weapon_report.js <PallyPilot.lua>');
  process.exit(1);
}
const src = fs.readFileSync(file, 'latin1');

// --- carve the fights array into top-level records -------------------------
function fightsOf(s) {
  const key = '["fights"] = {';
  const at = s.indexOf(key);
  if (at < 0) return [];
  let depth = 1, i = at + key.length, start = i;
  const out = [];
  while (i < s.length && depth > 0) {
    const c = s[i];
    if (c === '{') { if (depth === 1) start = i; depth++; }
    else if (c === '}') { depth--; if (depth === 1) out.push(s.slice(start, i + 1)); }
    i++;
  }
  return out;
}

const num = (r, k) => {
  const m = r.match(new RegExp('\\["' + k + '"\\]\\s*=\\s*(-?[\\d.]+)'));
  return m ? parseFloat(m[1]) : null;
};
const str = (r, k) => {
  const m = r.match(new RegExp('\\["' + k + '"\\]\\s*=\\s*"([^"]*)"'));
  return m ? m[1] : null;
};
// Spell sub-records are flat { ... } blocks each carrying an ["n"].
function spells(r) {
  const out = {};
  for (const m of r.matchAll(/\{([^{}]*\["n"\][^{}]*)\}/g)) {
    const b = m[1];
    const n = b.match(/\["n"\]\s*=\s*"([^"]+)"/);
    if (!n) continue;
    const h = b.match(/\["h"\]\s*=\s*(\d+)/);
    const d = b.match(/\["d"\]\s*=\s*(\d+)/);
    out[n[1]] = { h: h ? +h[1] : 0, d: d ? +d[1] : 0 };
  }
  return out;
}
// The weapon block is a nested table, so slice it out before reading keys --
// otherwise a top-level ["crit"] would shadow the weapon one.
function weapBlock(r) {
  const at = r.indexOf('["weap"] = {');
  if (at < 0) return null;
  let depth = 0, i = r.indexOf('{', at);
  const start = i;
  while (i < r.length) {
    if (r[i] === '{') depth++;
    else if (r[i] === '}') { depth--; if (depth === 0) return r.slice(start, i + 1); }
    i++;
  }
  return null;
}

const median = (a) => a.length ? a.slice().sort((x, y) => x - y)[a.length >> 1] : 0;
const K = (n) => n >= 1e6 ? (n / 1e6).toFixed(1) + 'M' : Math.round(n / 1000) + 'k';

const recs = fightsOf(src);
const rows = [];
for (const r of recs) {
  const dur = num(r, 'dur'), dps = num(r, 'dps');
  if (!dps || !dur || dur < 10) continue;
  const w = weapBlock(r);
  const sp = spells(r);
  const mel = sp['Melee'] ? sp['Melee'].h : 0;
  const te = (sp['Darkburst'] ? sp['Darkburst'].h : 0) + (sp['Lightburst'] ? sp['Lightburst'].h : 0);
  rows.push({
    dps, dur, tgts: num(r, 'tgts'), echoPct: num(r, 'echoPct'), mel, te,
    mh: w ? str(w, 'mh') : null,
    oh: w ? str(w, 'oh') : null,
    mhType: w ? str(w, 'mhType') : null,
    mhSpeed: w ? num(w, 'mhSpeed') : null,
    ohSpeed: w ? num(w, 'ohSpeed') : null,
    crit: w ? num(w, 'crit') : null,
    haste: w ? num(w, 'haste') : null,
    ap: w ? num(w, 'ap') : null,
  });
}

const withWeap = rows.filter((r) => r.mh);
console.log('fights in log        : ' + rows.length + '  (>=10s, with a dps reading)');
console.log('carrying weapon data : ' + withWeap.length);
if (!withWeap.length) {
  console.log('\nNothing to group yet. Weapon capture is new -- fights logged before it');
  console.log('have no `weap` block. Play a few fights, /reload, and re-run.');
  process.exit(0);
}

// --- group by the weapon PAIR ----------------------------------------------
const groups = new Map();
for (const r of withWeap) {
  const key = (r.mh || '?') + ' + ' + (r.oh || '(none)');
  if (!groups.has(key)) groups.set(key, []);
  groups.get(key).push(r);
}

const rankable = [...groups.entries()].sort((a, b) => b[1].length - a[1].length);
console.log('\n' + '='.repeat(78));
for (const [key, g] of rankable) {
  const st = g.filter((r) => r.tgts === 1).map((r) => r.dps);
  const aoe = g.filter((r) => r.tgts >= 3).map((r) => r.dps);
  const swings = g.reduce((a, r) => a + r.mel, 0);
  const secs = g.reduce((a, r) => a + r.dur, 0);
  const procs = g.reduce((a, r) => a + r.te, 0);
  const w = g[0];
  console.log(key);
  console.log('  ' + g.length + ' fights   ' + w.mhType +
    '   speed ' + (w.mhSpeed || '?') + (w.ohSpeed ? ' / ' + w.ohSpeed : '') +
    '   crit ' + (w.crit ?? '?') + '%  haste ' + (w.haste ?? '?') + '%  AP ' + (w.ap ?? '?'));
  console.log('  single-target ' + (st.length ? K(median(st)) + ' (' + st.length + ')' : '--') +
    '      AoE ' + (aoe.length ? K(median(aoe)) + ' (' + aoe.length + ')' : '--'));
  console.log('  swings/sec ' + (secs ? (swings / secs).toFixed(2) : '?') +
    '   TE procs/swing ' + (swings ? (procs / swings).toFixed(2) : '?') +
    '   TE procs/sec ' + (secs ? (procs / secs).toFixed(2) : '?') +
    '   echo share ' + Math.round(median(g.map((r) => r.echoPct))) + '%');
  console.log('');
}

// --- the actual verdict -----------------------------------------------------
// Only compare setups with a real sample, and only within the same bucket:
// an AoE-heavy sample against a single-target one says nothing.
console.log('='.repeat(78));
const MIN = 8;
for (const [label, pick] of [['SINGLE TARGET', (r) => r.tgts === 1], ['AoE', (r) => r.tgts >= 3]]) {
  const cand = rankable
    .map(([k, g]) => {
      const v = g.filter(pick).map((r) => r.dps);
      const sw = g.filter(pick).reduce((a, r) => a + r.mel, 0);
      const sec = g.filter(pick).reduce((a, r) => a + r.dur, 0);
      return { k, n: v.length, dps: median(v), sps: sec ? sw / sec : 0 };
    })
    .filter((c) => c.n >= MIN)
    .sort((a, b) => b.dps - a.dps);
  if (cand.length < 2) {
    console.log(label + ': need ' + MIN + '+ fights on two setups to compare (have ' +
      cand.length + ').');
    continue;
  }
  console.log(label + ':');
  for (const c of cand) {
    console.log('  ' + K(c.dps).padStart(6) + '  ' + c.sps.toFixed(2) + ' swings/s  n=' +
      String(c.n).padStart(3) + '  ' + c.k);
  }
  const [best, worst] = [cand[0], cand[cand.length - 1]];
  const dD = (best.dps / worst.dps - 1) * 100;
  const dS = worst.sps ? (best.sps / worst.sps - 1) * 100 : 0;
  console.log('  -> ' + dD.toFixed(0) + '% more damage on ' + dS.toFixed(0) +
    '% more swings/sec.');
  console.log('     Damage tracking swings supports the proc-delivery model;');
  console.log('     damage rising while swings do not means something else is carrying it.');
  console.log('');
}
