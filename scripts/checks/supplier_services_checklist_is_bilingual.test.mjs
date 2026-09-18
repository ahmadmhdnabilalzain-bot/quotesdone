// THE SERVICES CHECKLIST IS COMPLETE AND BILINGUAL (15 Sep 2026, sales_engineer).
//
// What is held equal, by reading the files (no database):
//   1. every one of the 40 trade codes the Arabic-label migration lists has at least five services in
//      the seed, each with an English label free of Arabic and an Arabic label that carries Arabic;
//   2. the Services tab's copy table has the same keys in English and Arabic, and no Arabic line is
//      left in English;
//   3. the tab records and sends audio to the server action — founder, 15 Sep 2026: the browser's own
//      speech engine is not used, because a mobile app must use the same path;
//   4. the service emirates at sign-up are seven checkboxes plus "All emirates", each with Arabic;
//   5. supplier_api routes the five documented actions.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');
const AR = /[؀-ۿ]/;

// Both seed files: the original 200 rows, and interior_fitout.decoration added 18 Sep with the
// rewrite (the founder's own cross-matching example needs a decoration service to state).
const seed = read('scripts/sql/a_supplier_states_its_services_from_a_checklist_the_sales_engineer_prepares.sql')
  + read('scripts/sql/a_supplier_describes_its_services_in_its_own_words_and_the_sales_engineer_rewrites_them.sql');
const rows = [...seed.matchAll(/\('([a-z_]+)','([a-z][a-z0-9_]*)','([^']+)','([^']+)',(\d+)\)/g)]
  .map(([, trade, code, en, ar]) => ({ trade, code, en, ar }));
const labelsFile = read('scripts/sql/a_suppliers_documents_propose_trades_and_a_new_trade_is_reviewed_not_dropped.sql');
const block = labelsFile.slice(labelsFile.indexOf('update public.taxonomy_trade t set label_ar'), labelsFile.indexOf(') v(code, ar)'));
const TRADES = [...block.matchAll(/\('([a-z_]+)','[^']+'\)/g)].map((m) => m[1]);

test('the seed covers all 40 trades with five services each, EN and AR', () => {
  assert.equal(TRADES.length, 40);
  for (const t of TRADES) assert.ok(rows.filter((r) => r.trade === t).length >= 5, `${t} has fewer than five services`);
  const keys = rows.map((r) => r.trade + '.' + r.code);
  assert.equal(new Set(keys).size, keys.length, 'a service key repeats');
  for (const r of rows) {
    assert.ok(TRADES.includes(r.trade), `unknown trade ${r.trade}`);
    assert.ok(AR.test(r.ar), `${r.trade}.${r.code} has no Arabic`);
    assert.ok(!AR.test(r.en), `${r.trade}.${r.code} has Arabic in English`);
  }
});

test('the Services tab copy has the same keys in both languages and Arabic in Arabic', () => {
  const src = read('src/components/portal/supplier/servicesCopy.ts');
  const en = src.slice(src.indexOf('  en: {'), src.indexOf('  ar: {'));
  const ar = src.slice(src.indexOf('  ar: {'), src.indexOf('} as const'));
  const keys = (s) => [...s.matchAll(/^ {4}([a-z_]+):/gm)].map((m) => m[1]).sort();
  assert.deepEqual(keys(ar), keys(en));
  assert.ok(keys(en).length >= 40);
  for (const [, k, v] of ar.matchAll(/^ {4}([a-z_]+): '([^']*)'/gm)) assert.ok(AR.test(v), `ar.${k} is not Arabic`);
});

test('voice is recorded and sent to the server, never the browser speech engine', () => {
  const tab = read('src/components/portal/supplier/ServicesTab.tsx');
  assert.ok(!/SpeechRecognition/.test(tab));
  assert.ok(tab.includes("'transcribe_service_note'"));
  assert.ok(tab.includes('MediaRecorder'));
  for (const a of ['services_state', 'services_rewrite', 'services_save_rewrite']) assert.ok(tab.includes(`'${a}'`), a);
});

// ADDING A SERVICE IS A TEXT BOX, NOT A PICKER (founder, instruction 438, 15 Sep 2026). This fails if
// a dropdown or a per-service "add" checkbox comes back. The PREPARED checklist's own checkboxes stay:
// they are the sales engineer's proposal being corrected, not the supplier adding something.
test('services are added by free text and voice, never by a dropdown', () => {
  const tab = read('src/components/portal/supplier/ServicesTab.tsx');
  const jsx = tab.slice(tab.indexOf('return ('));           // the markup only, so a comment cannot pass this
  assert.ok(!/<select/.test(jsx), 'the Services tab has a <select> again');
  assert.ok(!/add_trade/.test(tab), 'the "add a trade" picker is back');
  assert.ok(/<textarea/.test(jsx), 'the free text box is gone');
  assert.ok(tab.includes("'services_rewrite'"), 'the rewrite preview is gone');
  const copy = read('src/components/portal/supplier/servicesCopy.ts');
  for (const k of ['describe_title', 'rewrite_title', 'implied_title', 'implied_because', 'own_words_title']) {
    assert.ok(copy.includes(`${k}:`), `the copy table lost ${k}`);
  }
});

test('service emirates are seven checkboxes and All emirates, with Arabic', () => {
  const src = read('src/components/portal/supplier/EmirateCheckboxes.tsx');
  const copy = read('src/components/portal/supplier/serverCopy.ts');
  const list = src.match(/UAE_EMIRATES = \[([^\]]+)\]/)[1].match(/'([^']+)'/g).map((s) => s.slice(1, -1));
  assert.equal(list.length, 7);
  for (const e of list) assert.ok(new RegExp(`'${e}': '[^']*[\\u0600-\\u06FF]`).test(copy), `${e} has no Arabic label`);
  assert.ok(src.includes('type="checkbox"'));
  assert.ok(src.includes('كل الإمارات') && src.includes('All emirates'));
  assert.ok(!src.includes('aria-pressed'));
  assert.ok(read('src/components/portal/SupplierPortal.tsx').includes('<EmirateCheckboxes '));
});

test('supplier_api routes the five documented actions', () => {
  const api = read('supabase/functions/supplier_api/index.ts');
  const doc = read('docs/api/supplier_portal_services.md');
  for (const a of ['services_state', 'services_resolve', 'services_rewrite', 'services_save_rewrite', 'transcribe_service_note']) {
    assert.ok(api.includes(`'${a}'`), `supplier_api does not route ${a}`);
    assert.ok(doc.includes('`' + a + '`'), `the API doc does not describe ${a}`);
  }
});
