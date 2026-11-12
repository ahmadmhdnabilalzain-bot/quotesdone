// THE CATALOGUE CAN NAME WHAT SUPPLIERS DO (12 Nov 2026, sales_engineer; founder rulings 1647, 1627, 1628).
//
// scripts/sql/the_catalogue_can_name_what_suppliers_do.sql adds 47 services (no new trade) with their curated aliases.
// What fails if that breaks:
//   * the founder's own example (ruling 1647: a recruitment company supplies "labourers, professional experts,
//     freelancers"), the other staff a UAE manpower company supplies, and each broad area the analysis measured
//     (services/REPORT.md 1.2) stop being expressible as a key                                              -> static
//   * a key the analysis proposed that duplicates an existing one is added instead of linked                 -> static
//   * a name is written in one language only, or Arabic sits in the English column                           -> static
//   * the guard that refuses an alias already naming another service goes                                    -> static
//   * the readers that list a trade's services stop fitting: the inquiry side reads at most 4 trades with
//     limit(200) (_shared/inquiry_trades.ts tradeContext); the supplier reader lists at most 40 a trade
//     (supplier_trade_choice.ts)                                                                             -> static + production
//   * on production, rolled back, ZZ DEMO only: the names resolve, a manpower supplier is matched on the new
//     keys and reached for office staff through the link                                                     -> probe
//
//   node --test scripts/checks/the_catalogue_can_name_what_suppliers_do.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const AR = /[ء-ي]/;
const NAME = 'the_catalogue_can_name_what_suppliers_do';
const FILE = `scripts/sql/${NAME}.sql`;
const PROBE = `scripts/sql/${NAME}_probe.sql`;
const sql = R(FILE);

const SERVICES = [...sql.slice(sql.indexOf('insert into public.taxonomy_trade_service'), sql.indexOf('on conflict (trade_code, code)'))
  .matchAll(/^ {2}\('([a-z_]+)','([a-z_]+)','((?:[^']|'')+)','((?:[^']|'')+)',(\d+)\)/gm)]
  .map(([, trade, code, en, ar]) => ({ key: `${trade}.${code}`, trade, en, ar }));
const SEED = JSON.parse(/seed jsonb := \$s\$([\s\S]*?)\]\$s\$::jsonb/.exec(sql)[1] + ']');
const aliasesOf = new Map(SEED.map(([t, c, a]) => [`${t}.${c}`, a]));

test('47 services under existing trades, each named in English and in Arabic, each with curated aliases in both', () => {
  assert.equal(SERVICES.length, 47);
  assert.equal(new Set(SERVICES.map((s) => s.key)).size, 47, 'a key twice');
  // every trade, as every_trade_is_named_grouped_and_serviceable.test.mjs reads the sign-up mirror
  const body = /const TRADE_EN: Record<string, string> = \{([\s\S]*?)\n\};/.exec(R('src/components/portal/supplier/serverCopy.ts'))[1];
  const known = new Set([...body.matchAll(/(?:^|[\s,{])([a-z_]+):\s*'/g)].map((m) => m[1]));
  const bad = [];
  for (const s of SERVICES) {
    if (!known.has(s.trade)) bad.push(`${s.key}: ${s.trade} is not a trade (no new trade is added here)`);
    if (AR.test(s.en) || !s.en.trim()) bad.push(`${s.key}: English name`);
    if (!AR.test(s.ar)) bad.push(`${s.key}: Arabic name`);
    if (/[ء-ي][,;?]/.test(s.ar)) bad.push(`${s.key}: a Latin comma, semicolon or question mark after an Arabic letter`);
    const a = aliasesOf.get(s.key) ?? [];
    if (a.filter((x) => !AR.test(x)).length < 3) bad.push(`${s.key}: fewer than 3 English aliases`);
    if (a.filter((x) => AR.test(x)).length < 2) bad.push(`${s.key}: fewer than 2 Arabic aliases`);
  }
  assert.deepEqual(bad, []);
});

test('the founder\'s staff kinds and every broad area of the analysis can be named', () => {
  const keys = new Set(SERVICES.map((s) => s.key));
  // ruling 1647: "labourers, professional experts, freelancers" (labourers and skilled trades existed: labour_supply.general/skilled)
  for (const k of ['labour_supply.professional_staff', 'labour_supply.freelancers', 'labour_supply.engineers_technicians',
                   'labour_supply.drivers_operators', 'labour_supply.cleaners_housekeeping', 'labour_supply.hospitality_staff',
                   'labour_supply.office_admin_staff', 'labour_supply.office_boys', 'labour_supply.delivery_riders', 'labour_supply.receptionists']) {
    assert.ok(keys.has(k), `${k} (a kind of staff a UAE manpower company supplies) is missing`);
  }
  // REPORT.md 1.2, the broad areas: each gains what a real supplier there could not say
  const areas = { decoration_fitout: 'interior_fitout.', landscaping: 'landscaping.', pools: 'swimming_pools.', manpower: 'labour_supply.',
    facilities: 'facilities_management.', maintenance: 'joinery.repairs', trading: 'building_materials.', mep: 'electrical.earthing_lightning',
    cleaning: 'cleaning.', transport: 'logistics_moving.', events: 'event_management.', signage: 'signage.' };
  for (const [area, prefix] of Object.entries(areas)) assert.ok([...keys].some((k) => k.startsWith(prefix)), `${area}: nothing added`);
  // the probe asks the founder's own words on production
  const probe = R(PROBE);
  for (const w of ['"labourers"', '"professional staffing"', '"freelancers"', '"office staff supply"']) assert.ok(probe.includes(w), `the probe does not ask ${w}`);
});

test('a key that duplicates an existing one is linked: not added, or added under the trade whose checklist needs it and marked the same work', () => {
  const keys = new Set(SERVICES.map((s) => s.key));
  assert.ok(!keys.has('logistics_moving.trucking'), 'logistics_moving.trucking duplicates logistics_moving.site_delivery');
  assert.ok((aliasesOf.get('logistics_moving.site_delivery') ?? []).length >= 3, 'site_delivery is not given the dropped key\'s names');
  // a manpower firm's checklist lists his own trade's services only: the office-staff key is added there, as the same work
  const same = R('scripts/sql/the_same_work_under_two_keys_meets_at_the_service_gate.sql');
  for (const [mine, theirs] of [['labour_supply.office_admin_staff', 'hr_outsourcing.office_staff_outsourcing'],
                                ['labour_supply.receptionists', 'facilities_management.concierge_reception']]) {
    assert.ok(keys.has(mine), `${mine} is missing`);
    const [t, c] = theirs.split('.'), [mt, mc] = mine.split('.');
    assert.ok(same.includes(`('${mine}','${t}','${c}',`) && same.includes(`('${theirs}','${mt}','${mc}',`), `${mine} and ${theirs} are not the same work both ways`);
  }
  assert.match(sql, /values \('hr_outsourcing', 'labour_supply',/, 'manpower firms cannot be reached for office staff');
});

test('names that sat on the wrong service move; names too generic for one service are not used', () => {
  for (const [from, names] of [["('interior_fitout', 'retail',", ['restaurant fit out', 'تجهيز مطاعم']], ["('chemicals', 'coatings',", ['paint supply', 'توريد دهانات']],
                               ["('cleaning', 'deep_cleaning',", ['villa cleaning', 'تنظيف فلل', 'تنظيف شقق']]]) {
    assert.ok(sql.includes(from), `${from} is not a source of a move`);
    for (const n of names) assert.ok(sql.includes(`'${n}'`), `${n} does not move`);
  }
  assert.ok((aliasesOf.get('building_materials.paints') ?? []).includes('paint supply'));
  assert.ok((aliasesOf.get('cleaning.residential') ?? []).includes('villa cleaning'));
  const all = SEED.flatMap(([, , a]) => a);
  for (const g of ['mixers', 'خلاطات', 'nails and screws', 'عدد وأدوات', 'temporary staffing', 'contract staffing', 'توظيف مؤقت', 'مضيفين', 'أبلكاش']) {
    assert.ok(!all.includes(g), `"${g}" is too generic (or not Gulf usage) to be a service's name`);
  }
  for (const [k, w] of [['labour_supply.drivers_operators', 'دريول'], ['building_materials.paints', 'أصباغ'], ['logistics_moving.site_delivery', 'دينا'],
                        ['building_materials.timber_plywood', 'بلايوود']]) assert.ok((aliasesOf.get(k) ?? []).includes(w), `${k} does not say ${w}`);
});

test('an alias that already names another service refuses the whole file; the queue records who decided each', () => {
  assert.match(sql, /join names nm on nm\.n = p\.n and nm\.k <> p\.k/);
  assert.match(sql, /raise exception 'a curated alias already names another service: %'/);
  assert.match(sql, /'curated', 'approved', 'sales_engineer', now\(\)/);
  const all = SEED.flatMap(([t, c, a]) => a.map((x) => [x.toLowerCase().trim(), `${t}.${c}`]));
  const owner = new Map();
  for (const [a, k] of all) { assert.ok(!owner.has(a) || owner.get(a) === k, `"${a}" names ${owner.get(a)} and ${k}`); owner.set(a, k); }
});

test('the readers that list a trade\'s services still fit', () => {
  const inq = R('supabase/functions/_shared/inquiry_trades.ts');
  assert.match(inq, /\.slice\(0, 4\)/, 'tradeContext no longer caps the trades at 4');
  assert.match(inq, /\.in\('trade_code', cs\)\.order\('trade_code'\)\.order\('sort'\)\.limit\(200\)/, 'tradeContext reads the services differently');
  // added here per trade; the production test below adds the live counts
  const added = {}; for (const s of SERVICES) added[s.trade] = (added[s.trade] ?? 0) + 1;
  // the supplier reader lists 40 services a trade and the largest trade held 10 on 12 Nov 2026: 30 more still fit
  // (labour_supply gains the most here, 12: 5 -> 17); the production test below adds the live counts
  assert.ok(Math.max(...Object.values(added)) <= 30, 'one trade gains more than 30 services here');
});

test('the change is pending until the release applies it, and the probe is never applied', () => {
  const notes = pendingNotes();
  const inManifest = R('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim()).includes(FILE);
  assert.ok(inManifest || notes.has(FILE), 'the change is neither applied (MANIFEST) nor pending');
  assert.match(notes.get(PROBE) || '', /^A PROBE\b/, 'the probe must carry a probe note so it is never applied');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production: no trade lists more than 40 services and 4 of the largest fit the inquiry read', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql: q } = await import('../lib/db.mjs');
  const rows = await q(`select trade_code, count(*)::int as n from public.taxonomy_trade_service where active group by 1`);
  const live = Object.fromEntries(rows.map((r) => [r.trade_code, r.n]));
  const after = { ...live };   // while the file is pending, its services are added to the live counts
  if (pendingNotes().has(FILE)) for (const s of SERVICES) after[s.trade] = (after[s.trade] ?? 0) + 1;
  const sorted = Object.values(after).sort((a, b) => b - a);
  assert.ok(sorted[0] <= 40, `a trade lists ${sorted[0]} services (the supplier reader lists 40)`);
  assert.ok(sorted.slice(0, 4).reduce((a, b) => a + b, 0) <= 200, 'the 4 largest trades exceed the inquiry read of 200');
});

test('production, rolled back, ZZ DEMO only: the names resolve and the new keys match', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
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
