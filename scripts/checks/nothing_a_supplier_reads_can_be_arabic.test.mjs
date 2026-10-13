// NOTHING A SUPPLIER READS CAN BE ARABIC (13 Oct 2026, it_engineer; founder ruling 1008, 28 Sep 2026).
//
// Suppliers are always English, on every channel. The portal's language toggle went on 12 Oct
// (the_supplier_portal_is_always_english.test.mjs), but Arabic still reached a supplier other ways,
// read on main 678cd00: the receipt row offered "النسخة العربية", the inquiry and
// quotation tabs offered an "Arabic" PDF button, the quotation chat attached an Arabic print beside the
// English one, supplier_portal's remove_document answered in Arabic when the request said lang 'ar',
// and create_company stored the page language as the supplier's locale.
//
// The files are not listed here: they are every file reachable by relative import from the supplier
// portal page and from the supplier_portal, supplier_api and supplier_catalog_ingest functions,
// excluding _shared/ and src/lib (shared with customers, who keep their inquiry language). In each:
//   1. no language is read from the request or a stored row (body.lang, b.lang, asLocale, ...);
//   2. no 'ar' is produced as a value, only compared against - so every Arabic branch is gated on a
//      language that is the constant English (lang = 'en' / SUPPLIER_LOCALE) and never runs;
//   3. no control offers the Arabic copy of a document.
//   node --test scripts/checks/nothing_a_supplier_reads_can_be_arabic.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, resolve, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const ENTRIES = [
  'src/components/portal/SupplierPortal.tsx',
  'supabase/functions/supplier_portal/index.ts',
  'supabase/functions/supplier_api/index.ts',
  'supabase/functions/supplier_catalog_ingest/index.ts',
];
const SHARED = /^(supabase\/functions\/_shared\/|src\/lib\/|src\/components\/(ui|me)\/)/;

function resolveImport(from, spec) {
  const base = resolve(dirname(from), spec);
  for (const c of [base, base + '.ts', base + '.tsx', base + '/index.ts', base + '/index.tsx']) if (existsSync(c) && /\.tsx?$/.test(c)) return c;
  return null;
}
export function supplierFiles() {
  const seen = new Set(); const out = [];
  const stack = ENTRIES.map((e) => resolve(ROOT, e));
  while (stack.length) {
    const f = stack.pop(); if (seen.has(f)) continue; seen.add(f);
    const rel = relative(ROOT, f).replace(/\\/g, '/');
    if (SHARED.test(rel)) continue;
    out.push(rel);
    const src = readFileSync(f, 'utf8');
    for (const m of src.matchAll(/(?:import|export)[^'"]*?from\s*['"](\.{1,2}\/[^'"]+)['"]|import\(\s*['"](\.{1,2}\/[^'"]+)['"]\s*\)/g)) {
      const r = resolveImport(f, m[1] || m[2]); if (r) stack.push(r);
    }
  }
  return out.sort();
}

// Comments are not code that runs; they are blanked with their line breaks kept so line numbers hold.
const code = (src) => src.replace(/\/\*[\s\S]*?\*\//g, (c) => c.replace(/[^\n]/g, ' ')).replace(/(^|[^:'"`\\])\/\/.*$/gm, '$1');
const FROM_REQUEST_OR_ROW = /\b(?:b|body|params|payload|sup|lead|row)\.(?:lang|locale)\b|\basLocale\(|\bdocumentLocale\(|\bregisteredLocale\(|fn_registered_locale|\burlLocale\(/;
// Rendered or sent, not a copy-table entry: a key no code reads offers nothing.
const OFFERS_ARABIC = /\bt\.pdfAr\b|\bt\.pdfHeld\b/;
// A function's JSON answer carrying an Arabic field (message_ar, title_ar, ...) for the supplier.
const SENDS_ARABIC_FIELD = /\bJ\(.*\b\w+_ar\b/;
const ARABIC_SCRIPT = /[؀-ۿ]/;

const files = supplierFiles();

test('the supplier-facing files are derived from the code, not listed', () => {
  assert.ok(files.length >= 30, `only ${files.length} supplier files found - the import walk is broken`);
  for (const e of ENTRIES) assert.ok(files.includes(e), e + ' missing');
  assert.ok(files.some((f) => f.startsWith('src/components/portal/supplier/')), 'portal tabs not reached');
});

for (const f of files) {
  test(`${f}: a supplier can never be given Arabic`, () => {
    const lines = code(readFileSync(resolve(ROOT, f), 'utf8')).split('\n');
    const bad = [];
    lines.forEach((l, i) => {
      if (FROM_REQUEST_OR_ROW.test(l) && !/SUPPLIER_LOCALE/.test(l)) bad.push(`${i + 1}: language read from the request or a stored row: ${l.trim().slice(0, 160)}`);
      if (OFFERS_ARABIC.test(l)) bad.push(`${i + 1}: offers the Arabic copy: ${l.trim().slice(0, 160)}`);
      if (f.startsWith('supabase/') && SENDS_ARABIC_FIELD.test(l)) bad.push(`${i + 1}: answers with an Arabic field: ${l.trim().slice(0, 160)}`);
      // A line that is itself Arabic copy is the gated Arabic branch (its 'ar' arguments only format it).
      if (!ARABIC_SCRIPT.test(l)) for (const m of l.matchAll(/'ar'/g)) {
        const before = l.slice(0, m.index), after = l.slice(m.index + 4);
        const compared = /[=!]==?\s*$/.test(before) || /^\s*[=!]==?/.test(after);
        const typed = /\|\s*$/.test(before) || /^\s*\|/.test(after) || /Record<\s*$/.test(before) || /\bas\s*$/.test(before);
        const branch = /\?\s*$/.test(before) || /^\s*:/.test(after) && /\?\s*\S*\s*$/.test(before);
        // `{ en: f('en'), ar: f('ar') }`: both copies built, the caller picks one by the gated language.
        const slot = /\bar:\s*[\w.]+\(\s*$/.test(before);
        if (!compared && !typed && !branch && !slot) bad.push(`${i + 1}: 'ar' produced as a value: ${l.trim().slice(0, 160)}`);
      }
    });
    assert.deepEqual(bad, [], `${f} can give a supplier Arabic (founder ruling 1008):\n` + bad.join('\n'));
  });
}

test('the language every supplier branch is gated on is the constant English', () => {
  assert.match(readFileSync(resolve(ROOT, 'supabase/functions/_shared/registered_locale.ts'), 'utf8'), /export const SUPPLIER_LOCALE: Locale = 'en';/);
  assert.match(readFileSync(resolve(ROOT, 'src/components/portal/SupplierPortal.tsx'), 'utf8'), /const lang: string = 'en';/);
});
