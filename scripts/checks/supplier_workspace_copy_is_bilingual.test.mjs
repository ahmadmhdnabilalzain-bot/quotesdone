// The supplier portal's Messages, Documents and Insights words exist in BOTH languages (15 Sep 2026,
// sales_engineer).
//
// The server returns codes (hint codes, supporting-document types, band names, funnel stages); the words
// are src/components/portal/supplier/workspaceCopy.ts. This proves: every English key has an Arabic twin
// that is really Arabic and carries the same {placeholders}; every code the server can emit has both a
// title and a body; and the navigation labels follow the founder's tab order. It reads source only.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const ROOT = process.cwd();
const { WORKSPACE_COPY: C, ws } = await import(pathToFileURL(join(ROOT, 'src/components/portal/supplier/workspaceCopy.ts')).href);
const ph = (s) => [...String(s).matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort().join(',');
const ARABIC = /[؀-ۿ]/;

test('every key exists in both languages with the same placeholders, and the Arabic is Arabic', () => {
  const en = Object.keys(C.en), ar = Object.keys(C.ar);
  assert.deepEqual(en.filter((k) => !ar.includes(k)), [], 'English keys with no Arabic');
  assert.deepEqual(ar.filter((k) => !en.includes(k)), [], 'Arabic keys with no English');
  for (const k of en) {
    assert.equal(ph(C.ar[k]), ph(C.en[k]), `placeholders differ for ${k}`);
    assert.ok(ARABIC.test(C.ar[k]), `${k} is not Arabic: ${C.ar[k]}`);
    assert.ok(C.en[k].trim() && !ARABIC.test(C.en[k]), `${k} English is empty or Arabic`);
  }
});

test('every code the server emits has words', () => {
  const ins = readFileSync(join(ROOT, 'supabase/functions/supplier_portal/insights_summary.ts'), 'utf8');
  const hintCodes = [...new Set([...ins.matchAll(/code: '(hint_\w+)'/g)].map((m) => m[1]))];
  // e.status === 'expired' ? 'hint_doc_expired' : 'hint_doc_expiring'
  for (const m of ins.matchAll(/'(hint_\w+)'/g)) if (!hintCodes.includes(m[1])) hintCodes.push(m[1]);
  assert.ok(hintCodes.length >= 10, 'found ' + hintCodes.length + ' hint codes');
  for (const c of hintCodes) for (const part of ['_t', '_b']) assert.ok(C.en[c + part] && C.ar[c + part], `no words for ${c}${part}`);
  for (const b of ['below', 'around', 'above', 'no_data']) assert.ok(C.en['band_' + b] && C.ar['band_' + b], 'band ' + b);
  for (const s of ['received', 'quoted', 'revealed', 'won']) assert.ok(C.en['st_' + s] && C.ar['st_' + s], 'stage ' + s);
  const sd = readFileSync(join(ROOT, 'supabase/functions/supplier_portal/supporting_documents.ts'), 'utf8');
  const types = JSON.parse(sd.match(/SUPPORTING_TYPES = (\[[^\]]+\])/)[1].replace(/'/g, '"'));
  for (const t of types) assert.ok(C.en['sd_t_' + t] && C.ar['sd_t_' + t], 'type ' + t);
  for (const e of ['label_required', 'file_required', 'too_large', 'file_refused', 'limit_reached', 'generic']) assert.ok(C.ar['sd_err_' + e], 'error ' + e);
});

test('the tabs read in the founder\'s order, in both languages', () => {
  const src = readFileSync(join(ROOT, 'src/components/portal/SupplierPortal.tsx'), 'utf8');
  assert.match(src, /const MAIN_TABS = \['services', 'rfqs', 'quotes', 'messages', 'documents', 'insights'\];/);
  assert.match(src, /const ACCOUNT_TABS = \['profile', 'billing', 'settings'\];/);
  assert.deepEqual(['services', 'rfqs', 'quotes', 'messages', 'documents', 'insights'].map((k) => ws('en', 'tab_' + k)),
    ['Services', 'Inquiries received', 'Quotations submitted', 'Messages', 'Documents', 'Insights']);
  assert.equal(ws('ar', 'mb_respond_by', { date: '22' }), 'الرد قبل 22');
});
