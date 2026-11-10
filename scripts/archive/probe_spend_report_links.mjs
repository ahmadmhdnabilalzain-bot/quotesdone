// PROVE THE SPEND REPORT'S LINKS BY OPENING THE DOCUMENT IT PRODUCED.
//
//   node scripts/archive/probe_spend_report_links.mjs
//
// The founder, 9 September 2026: "can the pdf have clickable links for the actual invoices or
// receipts or at least a pdf print of the email". A render returning ok:true says nothing about
// whether the PDF is clickable — pdf_native rendered text and only text until today, and it still
// returns ok:true for a document with no annotation in it at all. So this probe:
//
//   1. asserts its fixtures FIRST — expense_entries is non-empty and some of it carries documents,
//      because zero links out of zero rows is not a passing result, it is an idle system;
//   2. renders the report through the LIVE accountant seat (deliver:false — NOTHING is mailed);
//   3. downloads the produced object from storage by the path pdf_native NAMED, never a composed one;
//   4. parses the PDF and asserts a /Annot /Link with a real URI exists for every row that has a
//      document, and that the count matches what the seat says it resolved.
//
// The PDF parsing is a separate Deno step (scripts/checks/read_pdf_links.ts) because pdf-lib is
// not an npm dependency of this repository and Deno is what the edge runtime uses anyway.
import { spawnSync } from 'node:child_process';
import { writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { sql, PROJECT_REF } from '../lib/db.mjs';

const die = (m) => { console.error('FAIL  ' + m); process.exit(1); };
const ok = (m) => console.log('ok    ' + m);

// ---------------------------------------------------------------- 1. fixtures, asserted first
const fx = (await sql(`select (select count(*) from public.expense_entries) as entries,
                              (select count(*) from public.expense_entries where doc_path is not null) as with_doc,
                              (select count(*) from public.expense_entries where doc_path is null) as without_doc`))[0];
if (Number(fx.entries) === 0) die('expense_entries is empty — a zero-link result here would prove nothing.');
if (Number(fx.with_doc) === 0) die('no expense row carries a document — there is nothing for a link to point at.');
ok(`fixtures: ${fx.entries} expense entries, ${fx.with_doc} with a document, ${fx.without_doc} without`);

const secrets = Object.fromEntries((await sql(
  `select key, value from public.app_secrets where key in ('cred_fn_accountant','anon_key')`))
  .map((r) => [r.key, r.value]));
for (const k of ['cred_fn_accountant', 'anon_key']) if (!secrets[k]) die(`app_secrets.${k} is unreadable`);

// ---------------------------------------------------------------- 2. render through the live seat
const res = await fetch(`https://${PROJECT_REF}.supabase.co/functions/v1/accountant`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', apikey: secrets.anon_key, Authorization: 'Bearer ' + secrets.anon_key },
  // deliver is DELIBERATELY absent. Delivery is owned elsewhere; this probe proves the document.
  body: JSON.stringify({ __secret: secrets.cred_fn_accountant, action: 'spend_report' }),
});
const j = await res.json();
if (!res.ok || j?.ok !== true) die(`accountant spend_report ${res.status}: ${JSON.stringify(j).slice(0, 600)}`);
if (j.pdf_error) die('pdf_native refused: ' + j.pdf_error);
if (!j.pdf?.path) die('the seat returned no document path');
ok(`rendered ${j.pdf.path} (${j.pdf.bytes} bytes, glyphs dropped ${j.pdf.glyphs_dropped})`);
ok(`the seat resolved ${j.links.resolved} link(s), ${j.links.unavailable} unavailable, expiring ${j.links.expires_at}`);
if (j.links.error) die('the signing call reported: ' + j.links.error);

const withDoc = Number(j.report?.receipts_with_document);
const withoutDoc = Number(j.report?.receipts_without_document);
if (!Number.isFinite(withDoc)) die('the report carries no receipts_with_document count');
ok(`the report itself says ${withDoc} receipt(s) carry a document and ${withoutDoc} say they have none`);
if (j.links.resolved !== withDoc) die(`the seat resolved ${j.links.resolved} links for ${withDoc} documented receipts`);

// ---------------------------------------------------------------- 3. the object, by the path it named
// finance-reports is private too, so the object is read back through the signed URL pdf_native
// returned FOR THE PATH IT NAMED — never a path composed here. Composing one is how an attachment
// reference comes to point at nothing.
if (!j.pdf.url) die('the seat returned no signed URL for the report it stored');
if (!j.pdf.url.includes(encodeURI(j.pdf.path)) && !j.pdf.url.includes(j.pdf.path)) die('the signed URL does not name the stored path');
const obj = await fetch(j.pdf.url);
if (!obj.ok) die(`could not download the produced object: ${obj.status} ${await obj.text()}`);
const bytes = Buffer.from(await obj.arrayBuffer());
if (bytes.length !== Number(j.pdf.bytes)) die(`downloaded ${bytes.length} bytes, the seat said ${j.pdf.bytes}`);
ok(`downloaded ${bytes.length} bytes from ${j.pdf.bucket}/${j.pdf.path}`);

// ---------------------------------------------------------------- 4. read the annotations back
const dir = mkdtempSync(join(tmpdir(), 'spend-report-links-'));
const file = join(dir, 'report.pdf');
writeFileSync(file, bytes);
const r = spawnSync('deno', ['run', '-A', 'scripts/checks/read_pdf_links.ts', file], { encoding: 'utf8' });
if (r.status !== 0) die('read_pdf_links failed: ' + (r.stdout || '') + (r.stderr || ''));
const parsed = JSON.parse(r.stdout);
ok(`the document itself carries ${parsed.links.length} /Annot /Link dictionaries across ${parsed.pages} page(s)`);

// ONE ANNOTATION PER DRAWN LINE, NOT PER LINK. A cell whose text wraps onto two lines needs two
// rectangles — one per line — or half of it is not clickable. So the count that must match the
// number of documented receipts is the number of DISTINCT destinations, and the annotation count is
// allowed to be larger. (Measured the hard way: the first run reported 91 annotations for 48 rows
// and that was the renderer being right, not wrong.)
const uris = [...new Set(parsed.links.map((l) => l.uri))];
if (uris.length !== withDoc) die(`the PDF links to ${uris.length} distinct documents, for ${withDoc} documented receipts`);
if (parsed.links.length < uris.length) die(`${parsed.links.length} annotations cannot cover ${uris.length} destinations`);
if (Number(j.pdf.links) !== parsed.links.length) die(`pdf_native reported ${j.pdf.links} annotations, the file holds ${parsed.links.length}`);
ok(`those ${parsed.links.length} annotations point at ${uris.length} distinct documents — one per documented receipt`);
const bad = parsed.links.filter((l) => !/^https:\/\/[a-z0-9-]+\.supabase\.co\/storage\/v1\/object\/sign\/receipt-files\//.test(l.uri));
if (bad.length) die(`${bad.length} link(s) do not point at a signed receipt-files object, e.g. ${bad[0].uri.slice(0, 120)}`);
const degenerate = parsed.links.filter((l) => !(l.rect[2] - l.rect[0] > 1) || !(l.rect[3] - l.rect[1] > 1));
if (degenerate.length) die(`${degenerate.length} link rect(s) are too small to click`);
ok('every link points at a signed object in receipt-files and covers a clickable rectangle');

// The first link, in full, so the URI is a measurement in the transcript and not a claim about one.
console.log('\nfirst link  ' + parsed.links[0].uri);
console.log('rect        [' + parsed.links[0].rect.join(', ') + ']  page ' + parsed.links[0].page);
const probe = await fetch(parsed.links[0].uri, { method: 'GET' });
if (!probe.ok) die(`the first link does not resolve: ${probe.status}`);
const ct = probe.headers.get('content-type');
ok(`the first link was FOLLOWED and returned ${probe.status} ${ct}, ${(await probe.arrayBuffer()).byteLength} bytes`);

console.log(`\nEVERY DOCUMENTED RECEIPT IN THE SPEND REPORT IS CLICKABLE  (${uris.length} documents behind ${parsed.links.length} annotations, `
  + `${withoutDoc} row(s) print "NO DOCUMENT" instead)`);
