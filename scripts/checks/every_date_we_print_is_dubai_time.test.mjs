// EVERY DATE WE PRINT IS DUBAI TIME (10 Nov 2026, it_engineer, founder ledger 1605).
//
// MEASURED. Edge functions run with TZ=UTC. A date formatted without a zone is the UTC date, which is the previous
// Dubai day from 20:00 to 24:00 UTC (UAE is UTC+4, no daylight saving). On 10 Nov 2026 five formatters printed a
// customer- or supplier-facing date that way: pdf_native/render.ts (both languages), _shared/quote_documents/kit.ts,
// _shared/quote_documents/inquiry_document.ts and customer_api/actions/reviews.ts; plus fmtDate in
// _shared/supplier_charge_documents.ts, which sliced the UTC day out of a timestamp. All were fixed in the same
// change (behaviour test: supabase/functions/_shared/document_dates_are_dubai_dates.test.ts).
//
// WHAT THIS FAILS ON. A Date formatter in supabase/functions/** (not a test) whose call carries no timeZone:
// .toLocaleDateString(, .toLocaleTimeString(, new Date(...).toLocaleString( and Intl.DateTimeFormat(. A number's
// .toLocaleString (AED 1,200) is not a date and is not matched unless the receiver is a `new Date(`.
//
// LIMIT, stated: a text scan over the call and the two lines after it. Options built in a variable elsewhere read as
// missing the zone; give such a call its timeZone inline. The browser app (src/) is not scanned: it formats in the
// reader's own zone, which for a UAE reader is Dubai.
//
//   node --test scripts/checks/every_date_we_print_is_dubai_time.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const ROOT = join(import.meta.dirname, '..', '..');
const FN = join(ROOT, 'supabase', 'functions');
const walk = (d) => readdirSync(d).flatMap((e) => {
  const p = join(d, e);
  return statSync(p).isDirectory() ? walk(p) : (/\.tsx?$/.test(e) && !/\.(test|check)\.tsx?$/.test(e) ? [p] : []);
});

const FORMATTER = /\.toLocale(Date|Time)String\(|new Date\([^)]*\)\.toLocaleString\(|Intl\.DateTimeFormat\(/;

/** Every date-formatter call in `src` with no timeZone in the call or the two lines after it. */
export function zonelessDateFormats(src) {
  const lines = src.split('\n'); const hits = [];
  lines.forEach((l, i) => {
    if (/^\s*(\/\/|\*)/.test(l) || !FORMATTER.test(l)) return;
    const from = l.search(FORMATTER);
    const call = [l.slice(from), lines[i + 1] ?? '', lines[i + 2] ?? ''].join('\n');
    if (!/\btimeZone\s*:/.test(call)) hits.push({ line: i + 1, text: l.trim().slice(0, 140) });
  });
  return hits;
}

test('the scanner catches a zoneless date and passes a zoned one or a number', () => {
  assert.equal(zonelessDateFormats("const d = new Date().toLocaleDateString('en-GB', { day: 'numeric' });").length, 1);
  assert.equal(zonelessDateFormats('const d = x.toLocaleTimeString();').length, 1);
  assert.equal(zonelessDateFormats("const d = new Date(t).toLocaleString('en-GB');").length, 1);
  assert.equal(zonelessDateFormats("const f = new Intl.DateTimeFormat('en-GB', {\n  day: 'numeric' });").length, 1);
  assert.equal(zonelessDateFormats("const d = new Date().toLocaleDateString('en-GB', { timeZone: 'Asia/Dubai' });").length, 0);
  assert.equal(zonelessDateFormats("const f = new Intl.DateTimeFormat('en-GB', {\n  timeZone: 'Asia/Dubai', day: 'numeric' });").length, 0);
  assert.equal(zonelessDateFormats("const s = `AED ${n.toLocaleString('en-US')}`;").length, 0);
});

test('no edge function prints a date in the runtime zone (UTC)', () => {
  const found = walk(FN).flatMap((f) => zonelessDateFormats(readFileSync(f, 'utf8'))
    .map((h) => `${relative(ROOT, f).replace(/\\/g, '/')}:${h.line}  ${h.text}`));
  assert.deepEqual(found, [], `a date formatted without timeZone prints the UTC day; add timeZone: 'Asia/Dubai':\n${found.join('\n')}`);
});
