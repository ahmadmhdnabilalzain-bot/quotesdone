// A SITE-VISIT JOB ASKS FOR THE PHOTOS ITS VISIT WOULD CHECK (15 Nov 2026, sales_engineer; founder ledger 1704: "For stuff that
// requires a site visit. The sales engineer should ask for photos. It will make it easier for suppliers to quote.").
//
// WHAT FAILS IF THE CAUSE RETURNS.
//   * every pack's photos_to_ask is exactly what scripts/kb/photos_to_ask.mjs derives from its site-visit sentence today (a
//     hand edit, or a sentence changed without regenerating, is caught), 2 to 6 shots, English and Arabic, and every shot's
//     `from` is words of its own checklist's sentence (a shot can never ask for something the visit does not check);
//   * a checklist whose sentence names a file, a sample or a meeting asks for no photo; every NO_PHOTOS id is a real checklist;
//   * the founder's worked example: an AC replacement asks for each indoor unit, each outdoor unit and where it sits, the
//     nameplate, the pipe route, the drain point and the isolator;
//   * the loader refuses a shot that does not trace to its sentence; the SQL file is ready (Seat header, no transaction control,
//     no routine, a probe that ends PROBE OK, exactly one of a pending note and a MANIFEST line);
//   * the runtime reader selects photos_to_ask, and falls back to the 10 Nov columns (not the narrowest) before it is applied.
//   node --test scripts/checks/a_site_visit_job_asks_for_the_photos_its_visit_would_check.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { photosFor, NO_PHOTOS, MAX_SHOTS, MIN_SHOTS, packsWithPhotos, formatOf } from '../kb/photos_to_ask.mjs';
import { expertFieldsOf, loadDir } from '../kb/load_trade_spec_checklists.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const PACKS = join(REPO, 'knowledge', 'packs');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/a_site_visit_checklist_carries_the_photos_to_ask_for.sql';
const PROBE = 'scripts/sql/a_site_visit_checklist_carries_the_photos_to_ask_for_probe.sql';
const NOTE = 'scripts/sql/pending/a_site_visit_checklist_carries_the_photos_to_ask_for.txt';
const AR = /[؀-ۿ]/;
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const checklists = () => readdirSync(PACKS).filter((f) => f.endsWith('.json') && !f.includes('.draft') && !f.includes('.market'))
  .flatMap((f) => (JSON.parse(readFileSync(join(PACKS, f), 'utf8')).entries ?? []).filter((e) => e.kind === 'spec_checklist').map((e) => ({ f, e })));

test('every pack carries exactly the list its site-visit sentence gives, each shot traced to the sentence', () => {
  let lists = 0, shots = 0;
  for (const { f, e } of checklists()) {
    const want = photosFor(e.id, e.site_visit_required_when);
    assert.deepEqual(e.photos_to_ask ?? [], want, `${f} ${e.id}: photos_to_ask is not what its sentence gives (run node scripts/kb/photos_to_ask.mjs knowledge/packs --write)`);
    if (!want.length) continue;
    lists++; shots += want.length;
    assert.ok(want.length >= MIN_SHOTS && want.length <= MAX_SHOTS, `${e.id}: ${want.length} shots`);
    const sentence = String(e.site_visit_required_when).toLowerCase();
    for (const s of want) {
      assert.ok(sentence.includes(s.from.toLowerCase()), `${e.id}: "${s.shot}" traces to "${s.from}", which its sentence does not say`);
      assert.ok(s.shot.length <= 100 && !/[[\]{}_]|spec_/.test(s.shot), `${e.id}: "${s.shot}" is not plain words`);
      assert.ok(AR.test(s.shot_ar), `${e.id}: "${s.shot}" has no Arabic`);
    }
    assert.equal(new Set(want.map((s) => s.shot)).size, want.length, `${e.id}: a shot is asked twice`);
  }
  assert.ok(lists >= 100 && shots >= 300, `only ${lists} lists, ${shots} shots`);
  // the generator would change nothing, and every pack it would write keeps its own format byte for byte
  for (const p of packsWithPhotos(PACKS)) { assert.equal(p.changed, false, `${p.file} is not regenerated`); assert.ok(formatOf(p.raw), `${p.file}: format not reproducible`); }
});

test('a sentence that names a file, a sample or a meeting asks for no photo; every NO_PHOTOS id is a checklist', () => {
  const all = checklists();
  const ids = new Set(all.map(({ e }) => e.id));
  for (const id of NO_PHOTOS) assert.ok(ids.has(id), `NO_PHOTOS names ${id}, no checklist of the packs`);
  assert.deepEqual(photosFor('cnc_machining:spec-checklist', 'a machined part always needs the drawing or a sample part before a firm price.'), []);
  assert.deepEqual(photosFor('zz:x', 'a firm fee needs the scope; a briefing meeting comes first.'), []);
  assert.deepEqual(photosFor('staff_transport:spec-checklist', 'a site survey is not normally needed.'), []);
  assert.deepEqual(photosFor('zz:none', null), []);
  // every checklist with no sentence asks for nothing
  for (const { e } of all) if (!e.site_visit_required_when) assert.equal(e.photos_to_ask, undefined, `${e.id}: photos without a site-visit sentence`);
});

test('the founder\'s worked example: an AC replacement asks for the six shots a visit would check', () => {
  const hvac = checklists().find(({ e }) => e.id === 'hvac:spec-split-ac').e;
  const shots = hvac.photos_to_ask.map((s) => s.shot.toLowerCase());
  for (const w of ['indoor unit', 'outdoor unit and where it sits', 'nameplate', 'pipes', 'drains', 'isolator']) assert.ok(shots.some((s) => s.includes(w)), `no shot of ${w}: ${shots.join(' | ')}`);
  assert.equal(shots.length, 6);
  // a repaint of damp walls asks for the walls and the damp; a roof refurbishment asks for the roof, its falls and the leaks
  const paint = checklists().find(({ e }) => e.id === 'painting:interior-repaint-spec').e.photos_to_ask.map((s) => s.shot.toLowerCase()).join(' | ');
  assert.match(paint, /wall/); assert.match(paint, /damp/);
  const roof = checklists().find(({ e }) => e.id === 'waterproofing:spec-roof-waterproofing').e.photos_to_ask.map((s) => s.shot.toLowerCase()).join(' | ');
  assert.match(roof, /roof/); assert.match(roof, /slopes/); assert.match(roof, /leak/);
});

test('the loader carries the list and refuses a shot that does not trace to its sentence', () => {
  const specs = [{ code: 'spec_a', label_en: 'a' }];
  const ok = expertFieldsOf({ id: 'zz:a', blocking: ['a'], site_visit_required_when: 'A visit checks the drainage.', photos_to_ask: [{ shot: 'The drain', shot_ar: 'الصرف', from: 'drainage' }] }, specs);
  assert.deepEqual(ok.photos_to_ask, [{ shot: 'The drain', shot_ar: 'الصرف', from: 'drainage' }]);
  assert.deepEqual(ok.refused, []);
  const bad = expertFieldsOf({ id: 'zz:a', blocking: ['a'], site_visit_required_when: 'A visit checks the drainage.', photos_to_ask: [{ shot: 'Your passport', from: 'passport' }] }, specs);
  assert.equal(bad.refused.length, 1);
  assert.deepEqual(bad.photos_to_ask, []);
  const rows = loadDir(PACKS);
  assert.deepEqual(rows.flatMap((r) => r.refused), []);
  assert.ok(rows.filter((r) => r.photos_to_ask.length).length >= 100);
});

test('the SQL file is ready to apply, and the runtime reads the column with a fallback to the 10 Nov columns', () => {
  const text = read(FILE);
  assert.match(text, /^-- Seat: sales_engineer/m);
  assert.doesNotMatch(code(text), /^\s*(begin|commit)\s*;/im);
  assert.doesNotMatch(code(text), /create (or replace )?function/i);
  assert.match(code(text), /add column if not exists photos_to_ask jsonb not null default '\[\]'::jsonb/);
  assert.ok(existsSync(join(REPO, PROBE)) && /PROBE OK/.test(read(PROBE)), 'no probe');
  const inManifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).includes(FILE);
  assert.ok(existsSync(join(REPO, NOTE)) !== inManifest, 'exactly one of a pending note and a MANIFEST line');
  const ts = read('supabase/functions/_shared/inquiry_trades.ts');
  const wide = ts.match(/const CHECKLIST_COLS = '([^']+)'/)[1].split(',');
  assert.ok(wide.includes('photos_to_ask'), 'the runtime does not select photos_to_ask');
  const before = ts.match(/const CHECKLIST_COLS_10_NOV = '([^']+)'/);
  assert.ok(before && !before[1].includes('photos_to_ask') && before[1].includes('blocking'), 'no fallback to the 10 Nov columns before the column is applied');
});
