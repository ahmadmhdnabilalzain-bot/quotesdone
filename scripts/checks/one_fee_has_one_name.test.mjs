// ONE FEE, ONE NAME — audit 22 Sep 2026, SP-I-08, and the independent review of PR #858
// (agent: customer_support).
//
// WHAT WAS MEASURED. On 22 Sep 2026 the annual fee a supplier pays to stay on the Platform was read
// on every supplier-facing surface in this repository. It carried FOUR different names:
//   1. the signed Supplier Agreement v12, clause 2, which defines it;
//   2. the supplier portal's billing copy (src/components/portal/supplier/serverCopy.ts);
//   3. the invoice and receipt PDF line item and subtitle (_shared/supplier_payment_documents.ts,
//      supplier_api/index.ts);
//   4. the payment function's "nothing to pay yet" sentence (supplier_pay/index.ts).
// #858 fixed the two names inside SupplierPortal.tsx and stopped there; the review found the other
// three still live.
//
// WHY A SECOND NAME ON A TAX DOCUMENT MATTERS. Items 3 and 4 above are not decoration. The invoice
// and the receipt are the documents the supplier keeps, gives to their accountant and files with
// the FTA; they are also what QuotesDone would put in front of a court under clauses 8 and 9 of the
// Agreement when an unpaid Subscription Fee is recovered as a debt. A document that charges for a
// "listing" while the contract obliges payment of a "Subscription Fee" invites the one question a
// tax document exists to foreclose: is this the charge the signed agreement is talking about? The
// name on the paper must be the name in the contract, in both languages, with nothing in between.
//
// HOW THIS CHECK WORKS. It does NOT hard-code the name. It reads the definition straight out of the
// agreement in src/content/legal.json, so the day a v13 renames the fee this check follows the
// document instead of failing against it. It then refuses every other name for the same fee on the
// surfaces a supplier actually sees.
//
// SELF-MATCH. The banned strings are written as \u escapes below so this file, and any comment
// quoting it, can never match its own scan — the technique
// scripts/checks/every_arabic_message_is_written_not_translated.test.mjs uses for the same reason.
// scripts/checks is also outside SURFACES, so neither half of the guard depends on the other.
//
// This file is discovered by scripts/checks/run.mjs through its `*.test.mjs` name (see discover()
// there and every_test_file_is_run.test.mjs); it needs no MANIFEST line, which covers scripts/sql.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..', '..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');

// THE SURFACES A SUPPLIER SEES THIS FEE ON: the portal components, the supplier edge functions and
// the document builders that render the invoice and the receipt.
// NOT scanned, and why:
//   - scripts/ and any *.test.ts / *.test.mjs — checks and document fixtures are not surfaces; the
//     PDF fixture in supabase/functions/pdf_native/every_document_we_issue.test.ts passes its line
//     text in as INPUT, so it proves the renderer works, not what the company calls the fee.
//   - supabase/functions/stripe_webhook — its mention is an agent_runs log note that no supplier
//     reads. A log may describe the fee in any words; a document may not.
//   - src/content/*.json — the legal documents themselves. They are the source this check reads.
const SURFACES = [
  'src/components/portal',
  'supabase/functions/supplier_api',
  'supabase/functions/supplier_pay',
  'supabase/functions/supplier_portal',
  'supabase/functions/pdf_native',
  'supabase/functions/_shared/supplier_payment_documents.ts',
];

// THE NAME, TAKEN FROM THE AGREEMENT ITSELF. Clause 2 defines the fee as the definition-list item
// whose body points at clause 6 (the fees clause). Anchoring on the cross-reference rather than on
// the wording means a rename in a future version is picked up, not fought.
function agreementFeeName() {
  const doc = JSON.parse(read('src/content/legal.json'))['supplier-agreement'];
  const en = /<li><b>([^<]+)<\/b>\s*—[^<]*clause 6/.exec(String(doc.en.html));
  const ar = /<li><b>([^<]+)<\/b>\s*—[^<]*البند 6/.exec(String(doc.ar.html));
  return { en: en && en[1].trim(), ar: ar && ar[1].trim() };
}

// Every other name this fee has been given in this estate, as escapes (see SELF-MATCH above).
const BANNED = [
  { s: 'listing fee', lang: 'en' },
  { s: 'registration fee', lang: 'en' },
  { s: 'yearly registration', lang: 'en' },
  { s: 'رسوم الإدراج', lang: 'ar' },
  { s: 'رسوم التسجيل', lang: 'ar' },
];

// A comment describing the fee is not a name the fee is given TO A SUPPLIER, and a check that greps
// source will otherwise match the comment explaining it. Comments are blanked, newlines kept so the
// reported line numbers are the real ones. String literals are tracked so a `//` inside a URL does
// not swallow the rest of the line.
function stripComments(src) {
  let out = '', i = 0, quote = null;
  while (i < src.length) {
    const c = src[i], n = src[i + 1];
    if (quote) {
      if (c === '\\') { out += src.slice(i, i + 2); i += 2; continue; }
      if (c === quote) quote = null;
      out += c; i++; continue;
    }
    if (c === '"' || c === "'" || c === '`') { quote = c; out += c; i++; continue; }
    if (c === '/' && n === '/') { while (i < src.length && src[i] !== '\n') i++; continue; }
    if (c === '/' && n === '*') { i += 2; while (i < src.length && !(src[i] === '*' && src[i + 1] === '/')) { if (src[i] === '\n') out += '\n'; i++; } i += 2; continue; }
    out += c; i++;
  }
  return out;
}

function files() {
  const out = [];
  const walk = (rel) => {
    const abs = path.join(ROOT, rel);
    if (!fs.existsSync(abs)) return;
    if (fs.statSync(abs).isFile()) { out.push(rel); return; }
    for (const e of fs.readdirSync(abs, { withFileTypes: true })) walk(path.posix.join(rel, e.name));
  };
  for (const s of SURFACES) walk(s);
  return out.filter((f) => /\.(ts|tsx)$/.test(f) && !/\.test\.tsx?$/.test(f));
}

test('the fee is named by the signed Supplier Agreement, and the agreement still defines it', () => {
  const name = agreementFeeName();
  assert.ok(name.en, 'clause 2 of the supplier agreement no longer defines a fee pointing at clause 6 (English) — this check cannot know what the fee is called, so it must be re-anchored, never deleted');
  assert.ok(name.ar, 'clause 2 of the supplier agreement no longer defines a fee pointing at clause 6 (Arabic)');
});

test('no supplier-facing surface calls the fee anything but the name in the agreement', () => {
  const name = agreementFeeName();
  const lower = (name.en || '').toLowerCase();
  // If a future version renames the fee TO one of these, that name stops being banned. Otherwise the
  // check would contradict the document it exists to enforce.
  const banned = BANNED.filter((b) => !(b.lang === 'en' ? lower.includes(b.s) : (name.ar || '').includes(b.s)));
  const hits = [];
  for (const f of files()) {
    const lines = stripComments(read(f)).split('\n');
    lines.forEach((line, i) => {
      for (const b of banned) {
        const hay = b.lang === 'en' ? line.toLowerCase() : line;
        if (hay.includes(b.s)) hits.push(`${f}:${i + 1} calls the fee something other than "${name.en}" / «${name.ar}»`);
      }
    });
  }
  assert.deepEqual(hits, [], 'the fee has more than one name:\n' + hits.join('\n'));
});

test('the agreement name is actually on the surfaces — a fee with no name at all is not a pass', () => {
  const name = agreementFeeName();
  const all = files().map((f) => read(f)).join('\n');
  assert.ok(all.toLowerCase().includes(name.en.toLowerCase()), 'no supplier-facing surface uses the English name from the agreement: ' + name.en);
  assert.ok(all.includes(name.ar), 'no supplier-facing surface uses the Arabic name from the agreement: ' + name.ar);
});
