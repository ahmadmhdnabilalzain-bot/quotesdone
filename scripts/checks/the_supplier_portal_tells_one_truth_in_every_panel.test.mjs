// the_supplier_portal_tells_one_truth_in_every_panel.test.mjs — the supplier-portal audit of 21 Sep 2026
// (sales_engineer seat, ZZ DEMO Interiors gypsum founderdemo) found panels telling the supplier
// different things about the same subject. Each test below replays one finding against the source and
// FAILS if its cause comes back. The .tsx cannot be imported by node (JSX), so the rules are read from
// the source, the same way WhatsAppChoice.test.mjs checks its placements.
// node --test scripts/checks/the_supplier_portal_tells_one_truth_in_every_panel.test.mjs
// Seat: it_engineer. Nothing here reads a database or reaches a person.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = join(import.meta.dirname, '..', '..');
// Comments are stripped: a check that greps source must not match the comment that explains the fix.
const strip = (src) => src.replace(/^\s*\/\/.*$/gm, '').replace(/\{\/\*[\s\S]*?\*\/\}/g, '');
const read = (p) => strip(readFileSync(join(ROOT, p), 'utf8'));
const no = (re, src, msg) => assert.ok(!re.test(src), msg || 'must not match ' + re);
const PORTAL = read('src/components/portal/SupplierPortal.tsx');
const FN = read('supabase/functions/supplier_portal/index.ts');
const OVERVIEW = read('supabase/functions/supplier_portal/overview.ts');
const COPY = read('src/components/portal/supplier/serverCopy.ts');
const body = (src, head) => { const i = src.indexOf(head); assert.ok(i >= 0, 'not found: ' + head); return src.slice(i, src.indexOf('\nfunction ', i + head.length)); };

test('5/6: the bell opens portal tabs only and shows the notices the estate wrote to this supplier', () => {
  const bell = body(PORTAL, 'function NotificationBell(');
  no(/href=|window\.location|\/me\b/, bell, 'the bell must route with go(tab), never a URL');
  assert.match(bell, /n\.notices/, 'the bell must render buildNotifications().notices (a reveal changed nothing on it)');
  assert.match(bell, /MAIN_TABS\.includes\(x\.tab\)/, 'a notice without a supplier-portal tab must not render');
  const tabs = OVERVIEW.slice(OVERVIEW.indexOf('NOTICE_TAB'), OVERVIEW.indexOf('};', OVERVIEW.indexOf('NOTICE_TAB')));
  for (const type of [...tabs.matchAll(/([a-z_]+): '(?:messages|rfqs|quotes|documents|services|insights)'/g)].map((m) => m[1])) {
    assert.match(COPY, new RegExp('notice_' + type + ':'), 'notice type ' + type + ' has a tab but no words in serverCopy.ts');
  }
});

test('6: the new-RFQ count says what it is out of', () => {
  assert.match(OVERVIEW, /params: \{ count: openIds\.length, total:/);
  assert.match(COPY, /new_rfq_title: s\(\(p\) => .*p\.total/);
});

test('16: every document write answers with the fresh list, and the tab paints from it', () => {
  for (const action of ['save_documents', 'remove_document', 'set_expiry']) {
    const i = FN.indexOf(`action === '${action}'`); assert.ok(i >= 0, action);
    const block = FN.slice(i, FN.indexOf("if (action === '", i + 20));
    assert.match(block, /await listDocuments\(/, action + ' must return listDocuments() — a second round trip raced the write');
  }
  const docs = body(PORTAL, 'function Documents(');
  no(/\n\s+load\(\);\n/, docs, 'Documents repainted from a second read after upload');
  assert.match(docs, /take\(j\)/);
});

test('17: one home per document subject — a certificate filed as a supporting document counts in its slot', () => {
  assert.match(FN, /admin\.rpc\('fn_supplier_document_home'/);
  assert.match(FN, /source = own \? 'leads' : \(stand && stand\.path \? 'supporting' : null\)/);
  assert.match(body(PORTAL, 'function DocRow('), /d\.source === 'supporting'/, 'a supporting-source row must say where it is managed');
});

test('18/19: one name for the EGR; no IBAN or bank slot anywhere in the supplier portal', () => {
  for (const [f, src] of [['SupplierPortal.tsx', PORTAL], ['serverCopy.ts', COPY], ['supplier_portal/index.ts', FN]]) {
    no(/Emirates Green|immigration establishment|المباني الخضراء/, src, f + ': the EGR is the establishment card');
  }
  no(/^\s+iban:\s*\{/m, FN, 'IBAN was removed estate-wide (founder instruction 527)');
});

test('20: no ranking hint names a field the supplier cannot reach', () => {
  const elig = OVERVIEW.slice(OVERVIEW.indexOf('const improving'), OVERVIEW.indexOf('no_emirate'));
  no(/no_sector|kwCols|capability_summary/, elig);
});

test('32/34: Profile starts from what the portal holds and says when it saved', () => {
  assert.match(PORTAL, /<ProfilePanel token=\{token\} lang=\{lang\} initial=\{me\}/);
  assert.match(body(PORTAL, 'function ProfilePanel('), /if \(!initial\) load\(\)/);
  assert.match(body(PORTAL, 'function ProfileForm('), /role="status"[^\n]*Changes saved/);
});

test('41/43: the tab title and the Settings language follow the language on screen', () => {
  assert.match(PORTAL, /applyShellChrome\(lang, 'portal'\)/);
  const settings = read('src/components/portal/supplier/SupplierSettings.tsx');
  no(/setLocale\(x\.locale/, settings, 'Settings showed the stored locale, not the interface language');
});

test('44/48: no check-mark glyph inside a heading; the licence fields keep a visible name', () => {
  no(/<h3[^>]*>\{ok\(/, PORTAL, 'state belongs after the heading name, as words');
  no(/_verified:'✓/, PORTAL);
  assert.match(PORTAL, /<Lbl [^>]*visible[^>]*text=\{t\(lang, 'lic_no'\)\}/);
  assert.match(PORTAL, /<Lbl [^>]*visible[^>]*text=\{t\(lang, 'authority'\)\}/);
});

test('45: one "Attach quotation" control, not two', () => {
  const chat = read('src/components/portal/supplier/QuoteReviewChat.tsx');
  no(/<input ref=\{fileRef\}[^>]*aria-label=/, chat);
});
