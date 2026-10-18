// Founder rulings 1228 and 1229 (13 Oct 2026): a supplier may quote by upload, by the quote form or by a photo in the
// chat (1228), but what the customer gets is always our template quotation as a PDF (1229) - never the supplier's own
// file. Before this check, customer_api (reveal, supplier profile) and stripe_confirm signed the supplier's stored file
// in the quote storage bucket and returned it after the reveal, so a photographed quotation reached the customer raw.
// Assigned: sales_engineer.
//
// WHAT IT SCANS: every edge function (supabase/functions, tests excluded, _shared included because customer functions
// import it) and the customer portal (src/components/me, src/app). The ONE exception is supplier_api: the supplier's
// own surface, where a supplier sees the file they themselves sent. Any other file that touches the quote storage
// bucket, or carries the raw-file fields, fails - a new customer path cannot add it back unseen.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const SUPPLIER_OWN = new Set(['supabase/functions/supplier_api']);
// The bucket name as a string literal, or the raw-file fields by name. Patterns are built so this header cannot match.
const BUCKET = new RegExp(['[\'"`]quote', 'files[\'"`]'].join('-'));
const FIELDS = new RegExp(['original', 'file', 'url'].join('_') + '|' + ['has', 'original'].join('_'));

const walk = (dir, out = []) => {
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.posix.join(dir, e.name);
    if (e.isDirectory()) { if (e.name !== 'node_modules') walk(p, out); }
    else if (/\.(ts|tsx|mjs|js)$/.test(e.name) && !/\.test\.|\.fixture\./.test(e.name)) out.push(p);
  }
  return out;
};

test('no customer-facing function or page hands out the supplier\'s own quotation file (rulings 1228, 1229)', () => {
  const files = [...walk('supabase/functions'), ...walk('src/components/me'), ...walk('src/app')]
    .filter((f) => ![...SUPPLIER_OWN].some((d) => f.startsWith(d + '/')));
  assert.ok(files.length > 50, 'the scan found too few files to mean anything: ' + files.length);
  const hits = [];
  for (const f of files) fs.readFileSync(f, 'utf8').split('\n').forEach((l, i) => {
    if (BUCKET.test(l) || FIELDS.test(l)) hits.push(`${f}:${i + 1}  ${l.trim().slice(0, 120)}`);
  });
  assert.deepEqual(hits, [], 'the customer only ever gets our template PDF, never the supplier\'s file:\n' + hits.join('\n'));
});
