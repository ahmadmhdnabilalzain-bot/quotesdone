// THE SPEC CHECKLIST LOADER CARRIES THE EXPERT FIELDS (10 Nov 2026, sales_engineer; founder ledger 1587).
//
// WHAT FAILS IF THE CAUSE RETURNS. The 223 trade packs gained spec_guide / blocking / site_visit_required_when on every
// spec_checklist, and neither loader read them, so the live interview could not use them. This pins the mapping:
//   * a pack entry -> the row the loader writes (scripts/kb/load_trade_spec_checklists.mjs checklistsOf): each guide row
//     carries its spec's code, blocking LABELS become CODES, the guide's flag follows the blocking list, an empty site-visit
//     sentence is null, pack_order counts the pack's checklists; a blocking label or a guide row naming no spec is REFUSED;
//   * the repo: every checklist loads with nothing refused, a guide row for every spec, every blocking code among its specs
//     (the table's CHECK), and the row's columns are exactly those the SQL adds plus the owning table's;
//   * the three ends agree on the column names: the SQL file adds them, the loader inserts them, the runtime reader
//     (supabase/functions/_shared/inquiry_trades.ts CHECKLIST_COLS) selects them;
//   * the SQL file is ready to apply: a Seat header, no transaction control, a probe beside it, and exactly one of a pending
//     note and a MANIFEST line;
//   * the verified-pack loader (scripts/kb/verified_packs.mjs rowsOf) carries the same fields and brand_origins on the row.
//   node --test scripts/checks/the_spec_checklist_loader_carries_the_expert_fields.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { checklistsOf, expertFieldsOf, loadDir, loadSql, specCode, summaryOf } from '../kb/load_trade_spec_checklists.mjs';
import { rowsOf } from '../kb/verified_packs.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/a_trades_blocking_specs_and_their_guide_reach_the_interview.sql';
const PROBE = 'scripts/sql/a_trades_blocking_specs_and_their_guide_reach_the_interview_probe.sql';
const NOTE = 'scripts/sql/pending/a_trades_blocking_specs_and_their_guide_reach_the_interview.txt';
const ADDED = ['spec_guide', 'blocking', 'site_visit_required_when', 'pack_order'];
const OWNED = ['trade_code', 'topic_id', 'topic', 'specs', 'source_pack'];   // a_trade_without_a_line_reader_is_held_on_its_packs_required_specs.sql
const PHOTOS = ['photos_to_ask'];   // a_site_visit_checklist_carries_the_photos_to_ask_for.sql (15 Nov 2026, ledger 1704)
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

const entry = (x) => ({ id: 'zz:spec-a', kind: 'spec_checklist', topic: 'ZZ checklist', required_specs: ['unit type (wall / ducted)', 'capacity: per unit', 'refrigerant'], ...x });

test('a pack entry becomes the row the loader writes, field by field', () => {
  const pack = { trade: 'zz_trade', entries: [
    entry({ blocking: ['unit type (wall / ducted)', 'capacity: per unit'], site_visit_required_when: 'ZZ a visit is needed for replacements.',
      spec_guide: [
        { spec: 'unit type (wall / ducted)', why_needed_to_price: 'each type has its own price', uae_options: 'wall; ducted', follow_up_if: 'ducted: ceiling void', blocking: true },
        { spec: 'capacity: per unit', why_needed_to_price: 'price follows capacity', uae_options: '9k-60k BTU/h', follow_up_if: '', blocking: false },
        { spec: 'refrigerant', why_needed_to_price: 'unit price', uae_options: 'R32', follow_up_if: '', blocking: true }] }),
    { id: 'zz:other', kind: 'concept', body_en: 'x' },
    entry({ id: 'zz:spec-b', site_visit_required_when: '   ' }),
  ] };
  const [a, b] = checklistsOf(pack, 'zz_trade.json');
  assert.deepEqual(a.blocking, [specCode('unit type (wall / ducted)'), specCode('capacity: per unit')]);
  assert.deepEqual(a.blocking, ['spec_unit_type', 'spec_capacity']);
  assert.deepEqual(a.spec_guide.map((g) => [g.code, g.blocking]), [['spec_unit_type', true], ['spec_capacity', true], ['spec_refrigerant', false]],
    'each guide row carries its code, and its blocking flag follows the blocking list');
  assert.equal(a.spec_guide[0].why_needed_to_price, 'each type has its own price');
  assert.equal(a.spec_guide[0].uae_options, 'wall; ducted');
  assert.equal(a.spec_guide[0].follow_up_if, 'ducted: ceiling void');
  assert.equal(a.site_visit_required_when, 'ZZ a visit is needed for replacements.');
  assert.deepEqual(a.refused, []);
  assert.deepEqual([a.pack_order, b.pack_order], [0, 1], 'pack_order is not the checklist\'s position in its pack');
  assert.equal(b.site_visit_required_when, null, 'an empty sentence is not null');
  assert.deepEqual([b.blocking, b.spec_guide], [[], []]);
  // refused: a blocking label or a guide row that names no spec of the checklist
  const specs = a.specs;
  const r = expertFieldsOf(entry({ blocking: ['not a spec of this checklist'], spec_guide: [{ spec: 'neither is this' }] }), specs);
  assert.equal(r.refused.length, 2, JSON.stringify(r.refused));
  assert.deepEqual(r.blocking, []);
});

test('the repo: every checklist loads, nothing refused, a guide row for every spec, every blocking code among its specs', () => {
  const rows = loadDir(join(REPO, 'knowledge', 'packs'));
  assert.ok(rows.length >= 305, `only ${rows.length} checklists`);
  assert.deepEqual(rows.flatMap((r) => r.refused), []);
  const s = summaryOf(rows);
  assert.ok(s.length >= 223, `only ${s.length} trades`);
  for (const r of rows) {
    const codes = r.specs.map((x) => x.code);
    assert.ok(r.blocking.length > 0, `${r.topic_id}: no blocking spec`);
    assert.ok(r.blocking.every((c) => codes.includes(c)), `${r.topic_id}: a blocking code outside its specs`);
    assert.deepEqual(r.spec_guide.map((g) => g.code), codes, `${r.topic_id}: the guide does not cover its specs in order`);
    const { refused: _r, ...row } = r;
    assert.deepEqual(Object.keys(row).sort(), [...OWNED, ...ADDED, ...PHOTOS].sort(), `${r.topic_id}: the row is not the table's columns`);
  }
});

test('the SQL adds, the loader inserts and the runtime selects the same columns', () => {
  const sql = code(read(FILE));
  for (const c of ADDED) assert.match(sql, new RegExp(`add column if not exists ${c}\\b`), `the SQL does not add ${c}`);
  const ins = loadSql(loadDir(join(REPO, 'knowledge', 'packs')).slice(0, 1).map(({ refused: _r, ...r }) => r)).match(/insert into public\.trade_spec_checklist \(([^)]+)\)/)[1].split(',').map((x) => x.trim());
  assert.deepEqual(ins.sort(), [...OWNED, ...ADDED, ...PHOTOS].sort());
  const ts = read('supabase/functions/_shared/inquiry_trades.ts');
  const cols = ts.match(/const CHECKLIST_COLS = '([^']+)'/)[1].split(',');
  for (const c of [...ADDED, 'trade_code', 'topic_id', 'topic', 'specs']) assert.ok(cols.includes(c), `the runtime does not select ${c}`);
});

test('the SQL file is ready to apply', () => {
  const text = read(FILE);
  assert.match(text, /^-- Seat: sales_engineer/m);
  assert.doesNotMatch(code(text), /^\s*(begin|commit)\s*;/im);
  assert.doesNotMatch(code(text), /create (or replace )?function/i, 'a routine here needs its revoke and pinned search_path');
  assert.match(code(text), /check \(to_jsonb\(blocking\) <@ jsonb_path_query_array\(specs, '\$\[\*\]\.code'\)\)/, 'the blocking codes are not held to the specs');
  assert.ok(existsSync(join(REPO, PROBE)), 'no probe');
  assert.match(read(PROBE), /PROBE OK/);
  const inManifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).includes(FILE);
  assert.ok(existsSync(join(REPO, NOTE)) !== inManifest, 'exactly one of a pending note and a MANIFEST line');
});

test('the verified-pack rows carry the same fields and brand_origins', () => {
  const p = { kind: 'trade', code: 'zz', key: 'zz', rel: 'packs/zz.json', version: 'v', pack_id: 'verified:trade:zz', pack: { entries: [
    { id: 'zz:spec', topic: 't', kind: 'spec_checklist', body_en: 'b', body_ar: 'ب', sources: ['https://example.invalid'], confidence: 'high', as_of: '2026-11-10',
      required_specs: ['a'], blocking: ['a'], spec_guide: [{ spec: 'a', blocking: true }], site_visit_required_when: 'ZZ' },
    { id: 'zz:brands', topic: 't', kind: 'uae_market_brands', body_en: 'b', body_ar: 'ب', sources: ['https://example.invalid'], confidence: 'high', as_of: '2026-11-10',
      brand_origins: [{ brand: 'ZZ Brand', origin: 'Germany', tier: 'premium', generic_en: 'a premium German brand', generic_ar: 'علامة' }] }] } };
  const [spec, , brands] = rowsOf(p);
  assert.deepEqual(spec.cols.structured_data.blocking, ['a']);
  assert.equal(spec.cols.structured_data.site_visit_required_when, 'ZZ');
  assert.equal(spec.cols.structured_data.spec_guide.length, 1);
  assert.equal(brands.cols.structured_data.brand_origins[0].brand, 'ZZ Brand');
});
