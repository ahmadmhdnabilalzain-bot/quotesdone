// THE CATALOGUE KNOWS THE PLAIN WORDS SUPPLIERS USE (12 Nov 2026, sales_engineer; founder ruling 1647).
//
// scripts/sql/the_catalogue_knows_the_plain_words_suppliers_use.sql gives the services that had no name but their label
// (874 of 1,151 on 12 Nov 2026) the plain words a UAE supplier writes, and the recruitment card and the hard profiles the
// words they were missing. What fails if that breaks:
//   * a service is left with no name except the 15 the file names, and why                                   -> static
//   * the founder's staff words (office staff, supervisors, professionals, chefs, drivers, nurses, security guards) do
//     not reach their key BY THE READING'S OWN CODE (supplier_profile_reading.ts nameIndex / codeKeysOf)      -> static
//   * one name is given to two keys, a bare generic word becomes a name, Arabic sits in an English slot        -> static
//   * the guards (one name, one key; the queue's own decisions are not overruled) go                           -> static
//   * the two notes of the catalogue review (the moved Arabic names, the reverse thermal rows) are dropped     -> static
//   * on production, rolled back, ZZ DEMO only: the names resolve, a collision is refused, the reverse rows reach a
//     roof-insulation specialist, nothing real is written                                                     -> probe
//
//   node --test scripts/checks/the_catalogue_knows_the_plain_words_suppliers_use.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const AR = /[ء-ي]/;
const NAME = 'the_catalogue_knows_the_plain_words_suppliers_use';
const FILE = `scripts/sql/${NAME}.sql`;
const PROBE = `scripts/sql/${NAME}_probe.sql`;
const sql = R(FILE);
const SEED = JSON.parse(/seed jsonb := \$s\$([\s\S]*?)\]\$s\$::jsonb/.exec(sql)[1] + ']');
const names = new Map(SEED.map(([t, c, a]) => [`${t}.${c}`, a]));
const LEFT = ['masonry_blockwork.blockwork', 'masonry_blockwork.plastering', 'tents_shades.tensile_structures', 'tents_shades.shade_sails',
  'thermal_insulation.acoustic_insulation', 'water_treatment.tank_cleaning_disinfection', 'machinery_repair.motor_rewinding',
  'motors_drives.motor_rewinding', 'flexible_packaging.bubble_wrap_air_cushions', 'protective_packaging.bubble_wrap',
  'packaging.shrink_sleeves', 'packaging.strapping', 'packaging.woven_sacks', 'packaging.fibc_bags', 'playground_equipment.shade_sails'];

test('911 services gain 3,870 names; every name is plain, in one language, and named once', () => {
  const all = SEED.flatMap(([t, c, a]) => a.map((x) => [x, `${t}.${c}`]));
  assert.equal(SEED.length, 911);
  assert.equal(all.length, 3870);
  assert.match(sql, /= 3870\n/, 'the verdict counts a different number of names');
  const owner = new Map();
  const bad = [];
  for (const [a, k] of all) {
    if (a !== a.toLowerCase().trim()) bad.push(`${k}: "${a}" is not written as the queue stores it`);
    if (a.length < 3 || a.length > 120) bad.push(`${k}: "${a}" length`);
    if (/^(staff|supply|services?|maintenance|works?|repairs?|installation|equipment|supplies|materials|systems|products|trading|general|electricians|masons|carpenters|accountants)$/.test(a)) {
      bad.push(`${k}: "${a}" is a bare generic word`);
    }
    if (AR.test(a) && /[a-z]{4,}/.test(a)) bad.push(`${k}: "${a}" mixes the languages`);
    if (AR.test(a) && /[ء-ي][,;?]/.test(a)) bad.push(`${k}: a Latin comma after an Arabic letter`);
    if (owner.has(a) && owner.get(a) !== k) bad.push(`"${a}" names ${owner.get(a)} and ${k}`);
    owner.set(a, k);
  }
  assert.deepEqual(bad, []);
  // every LEFT key is said, with its reason, in the file's head, and given nothing
  for (const k of LEFT) { assert.ok(sql.includes(`'${k}'`) || sql.includes(k.split('.')[1]), `${k} is not named as left without a name`); assert.ok(!names.has(k), `${k} is given a name`); }
});

test('the founder\'s staff words and the hard profiles\' phrases reach their key by the reading\'s own code', async () => {
  // the real reading (Node strips its types), over the recorded catalogue of the hard-profile run with this file's names
  // added (and the keys that run predates, the catalogue file's, added as services): what a supplier's phrase is placed on
  // by code, before any model is asked.
  const { nameIndex, codeKeysOf } = await import(pathToFileURL(join(ROOT, 'supabase/functions/_shared/supplier_profile_reading.ts')).href);
  const tax = structuredClone(JSON.parse(R('scripts/e2e/services_hard_profiles/recorded.json')).taxonomy);
  for (const [t, c, a] of SEED) {
    let tr = tax.trades.find((x) => x.code === t);
    if (!tr) { tr = { code: t, label: t, services: [] }; tax.trades.push(tr); }
    let sv = tr.services.find((s) => s.key === `${t}.${c}`);
    if (!sv) { sv = { key: `${t}.${c}`, label: c.replace(/_/g, ' '), aliases: [] }; tr.services.push(sv); }
    sv.aliases = [...(sv.aliases ?? []), ...a];
  }
  // "ZZ DEMO Gulf Manpower & Interiors: we supply office staff, supervisors, truck drivers, chefs, nurses and security
  //  guards; we build mall kiosks, fit gypsum cornices and SMDB panels" (the probe asks the same words on production)
  const said = {
    'office staff': 'labour_supply.office_admin_staff', 'supervisors': 'labour_supply.supervisors', 'professionals': 'labour_supply.professional_staff',
    'Truck drivers': 'labour_supply.drivers_operators', 'chefs': 'labour_supply.hospitality_staff', 'Steel fixers': 'labour_supply.skilled',
    'nurses': 'occupational_health.onsite_clinic_nurse', 'Security guards': 'security_guarding.manned_guarding',
    'Mall kiosks': 'exhibition_stands.kiosks_pop_ups', 'Cornices': 'gypsum.decorative', 'SMDB panels': 'electrical.db_panels',
    'Termite control': 'pest_control.termite_treatment', 'Shopfront signs': 'signage.shop_signs', 'تنظيف خزانات': 'water_treatment_services.water_tank_cleaning_disinfection',
  };
  const wrong = [];
  for (const [words, key] of Object.entries(said)) {
    const got = codeKeysOf({ n: 1, text: words, words, trade: key.split('.')[0] }, tax);
    if (JSON.stringify(got) !== JSON.stringify([key])) wrong.push(`"${words}" -> ${JSON.stringify(got)}, not ${key}`);
  }
  assert.deepEqual(wrong, []);
  // no name of this file is, in the reading's shape, also a name of a second key of the recorded catalogue
  const { quoteKey } = await import(pathToFileURL(join(ROOT, 'supabase/functions/_shared/supplier_trade_choice.ts')).href);
  const nameKey = (x) => quoteKey(x).split(' ').filter((w) => w && w !== 'and' && w !== 'the').join(' ');
  const idx = nameIndex(tax);
  const two = SEED.flatMap(([t, c, a]) => a.filter((x) => nameKey(x).length >= 3 && (idx.get(nameKey(x)) ?? []).length > 1)
    .map((x) => `"${x}" (${t}.${c}): ${idx.get(nameKey(x)).join('+')}`));
  assert.deepEqual(two, []);
});

test('one name, one key: the guards refuse a name another service holds and a phrase the queue decided otherwise', () => {
  assert.match(sql, /join names nm on nm\.n = p\.n and nm\.k <> p\.k/);
  assert.match(sql, /raise exception 'a curated alias already names another service: %'/);
  assert.match(sql, /raise exception 'the queue already decided a curated alias otherwise: %'/);
  assert.match(sql, /'curated', 'approved', 'sales_engineer', now\(\)/);
  assert.match(sql, /on conflict \(phrase_norm, trade_code, code\) do nothing/);
  // twins share work through `same` rows, never a name: security_systems.guarding keeps "security guard"
  assert.ok(!names.get('security_guarding.manned_guarding').includes('security guard'));
  assert.ok(!names.get('hr_outsourcing.office_staff_outsourcing'), 'the twin of office_admin_staff is given a name');
});

test('the two notes of the catalogue review: the moved Arabic names are rejected, thermal insulation is reached from both sides', () => {
  assert.match(sql, /set status = 'rejected', decided_by = 'sales_engineer'/);
  assert.match(sql, /q\.trade_code = 'cleaning' and q\.code = 'deep_cleaning' and q\.status = 'approved'/);
  for (const n of ['تنظيف فلل', 'تنظيف شقق']) assert.ok(sql.includes(`'${n}'`));
  for (const from of ['thermal_insulation.roof_insulation', 'thermal_insulation.wall_insulation']) {
    assert.ok(sql.includes(`('${from}','waterproofing','thermal',`) && /,false\)/.test(sql), `${from} -> waterproofing.thermal is not a plain row`);
  }
  const mirror = JSON.parse(R('supabase/functions/_shared/service_implications.json'));
  for (const from of ['thermal_insulation.roof_insulation', 'thermal_insulation.wall_insulation']) {
    assert.ok(mirror.some((g) => g.from === from && g.to.includes('waterproofing.thermal') && !g.same), `${from} is not in the mirror`);
  }
});

test('the change is pending until the release applies it, the probe is never applied, and the re-embed is said', () => {
  const notes = pendingNotes();
  const inManifest = R('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim()).includes(FILE);
  assert.ok(inManifest || notes.has(FILE), 'the change is neither applied (MANIFEST) nor pending');
  if (notes.has(FILE)) assert.match(notes.get(FILE), /embed_taxonomy_services\.mjs --write/, 'the note does not say the vectors are re-embedded at merge');
  assert.match(notes.get(PROBE) || '', /^A PROBE\b/, 'the probe must carry a probe note so it is never applied');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production, rolled back, ZZ DEMO only: the names resolve, a collision is refused, nothing real is written', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const pre = pendingNotes().has(FILE) ? R(FILE) + '\n' : '';
  let verdict = null;
  try { await replaySql(pre + R(PROBE), { label: PROBE }); } catch (e) {
    const m = String(e.body ?? e.message ?? e).match(/CHK<<([\s\S]*?)>>/);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.body ?? e.message ?? e).slice(0, 800));
    verdict = m[1].replace(/\\"/g, '"');
  }
  assert.ok(verdict, 'the probe committed instead of rolling back');
  assert.match(verdict, /"verdict": "PROBE OK"/, verdict);
});
