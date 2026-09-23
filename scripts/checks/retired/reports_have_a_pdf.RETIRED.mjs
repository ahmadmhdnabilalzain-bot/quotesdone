// RETIRED 22 Sep 2026 (documents-language audit, DL-13) — WITH ITS SUBJECT, never softened.
// The mechanism this file gates was removed by scripts/sql/the_report_pdf_enqueue_had_no_consumer.sql:
// the report_pdf edge function is not deployed (absent from the 74 ACTIVE functions measured on the
// management API, and no source for it in this repository), action_execution never carried a single
// row of class report.pdf, org_action_executor has no such executor, and the three z_report_pdf_enqueue
// triggers were dropped. This check has been vacuously green since 7 Sep because no report row has been
// created in any 8-day window since; it would have gone red on the next report, naming a renderer that
// does not exist. Bring it back — rename to *.test.mjs and move it out of retired/ — when a renderer
// composes a report again and the trigger is restored.
//
// EVERY REPORT IS A CORPORATE PDF.
//
// Founder's order, 6 Sep 2026: "any report needs to be in PDF format; all finance reports need to be
// extremely organized in corporate PDF format." The mechanism: z_report_pdf_enqueue (AFTER INSERT on
// board_reports / exec_reports / finance_reports) queues an action_execution row for the report.pdf
// executor, fn_action_invoke_dispatch posts it to the report_pdf edge function within five minutes, and
// the function stores <kind>/<period>/<source>_<id>.pdf in the private `reports` bucket and stamps
// pdf_path + pdf_generated_at on the row.
//
//   1. every report_registry row created in the last 8 days — and older than 30 minutes, so a row still
//      waiting for its 5-minute dispatch cannot make the check flap — carries pdf_path and
//      pdf_generated_at, and the object actually exists in storage.objects for the `reports` bucket;
//   2. the newest finance report (finance_reports, or a board_reports row of type finance, whichever is
//      newer — the same rule report_pdf's latest_finance uses) renders to at least 2 pages and its text
//      contains "Cash", "Runway" and "AED". The bytes are read from storage with the project's service
//      key, obtained through the management API, and
//      the text is pulled out with a plain parser (inflate each content stream, read Tj/TJ strings):
//      report_pdf saves with useObjectStreams:false and standard WinAnsi fonts precisely so that this
//      needs no PDF library.
//
// Read-only against production. Skips (and says so) without a management token.
//
//   node --test scripts/checks/reports_have_a_pdf.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { inflateSync } from 'node:zlib';
import { sql, PROJECT_REF } from '../lib/db.mjs';

const tokenPath = join(homedir(), '.supabase', 'access-token');
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(tokenPath);
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

async function rows(q) {
  const r = await sql(`set local statement_timeout = '8s'; ${q}`);
  return Array.isArray(r) ? r : [];
}

test('every report created in the last 8 days (older than 30 min) has a PDF object in the reports bucket', { skip: SKIP }, async () => {
  const r = await rows(`
    select r.source, r.report_type, r.id, r.created_at, r.pdf_path, r.pdf_generated_at,
           exists (select 1 from storage.objects o where o.bucket_id = 'reports' and o.name = r.pdf_path) as object_exists
      from public.report_registry r
     where r.created_at >= now() - interval '8 days'
       and r.created_at <  now() - interval '30 minutes'
     order by r.created_at desc
     limit 200`);
  const bad = r.filter((x) => !x.pdf_path || !x.pdf_generated_at || x.object_exists !== true);
  assert.equal(bad.length, 0, 'reports without a stored PDF (trigger z_report_pdf_enqueue -> action.invoker -> report_pdf):\n' + JSON.stringify(bad, null, 1));
  console.log(`reports in window: ${r.length}, all with a PDF object`);
});

// ---- a plain PDF text reader: enough for a pdf-lib document written with standard fonts ------------
function pdfText(buf) {
  const s = buf.toString('latin1');
  let out = '';
  const re = /stream\r?\n([\s\S]*?)\r?\nendstream/g;
  let m;
  while ((m = re.exec(s))) {
    let body = Buffer.from(m[1], 'latin1');
    try { body = inflateSync(body); } catch (_e) { /* an uncompressed stream, or not a content stream */ }
    const c = body.toString('latin1');
    for (const t of c.matchAll(/<([0-9A-Fa-f]+)>\s*Tj/g)) out += Buffer.from(t[1], 'hex').toString('latin1') + ' ';
    for (const t of c.matchAll(/\(((?:\\.|[^\\)])*)\)\s*Tj/g)) out += t[1].replace(/\\([()\\])/g, '$1') + ' ';
    for (const t of c.matchAll(/\[((?:[^\]])*)\]\s*TJ/g)) { for (const h of t[1].matchAll(/<([0-9A-Fa-f]+)>/g)) out += Buffer.from(h[1], 'hex').toString('latin1'); for (const l of t[1].matchAll(/\(((?:\\.|[^\\)])*)\)/g)) out += l[1]; out += ' '; }
  }
  return out;
}
const pageCount = (buf) => (buf.toString('latin1').match(/\/Type\s*\/Page[^s]/g) || []).length;

test('the newest finance report PDF is at least 2 pages and states Cash, Runway and AED', { skip: SKIP }, async () => {
  const r = await rows(`
    select * from (
      select 'finance' as source, id, created_at, pdf_path, pdf_generated_at from public.finance_reports
      union all
      select 'board', id, created_at, pdf_path, pdf_generated_at from public.board_reports where report_type = 'finance'
    ) x order by created_at desc limit 1`);
  assert.equal(r.length, 1, 'no finance report exists');
  const fin = r[0];
  assert.ok(fin.pdf_path && fin.pdf_generated_at, 'newest finance report has no PDF: ' + JSON.stringify(fin));

  const token = (process.env.SUPABASE_ACCESS_TOKEN || readFileSync(tokenPath, 'utf8')).trim();
  const keys = await (await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/api-keys?reveal=true`, { headers: { Authorization: 'Bearer ' + token } })).json();
  const service = (Array.isArray(keys) ? keys : []).find((k) => k.name === 'service_role' || k.type === 'secret')?.api_key;
  assert.ok(service, 'could not resolve the service_role key through the management API');
  const res = await fetch(`https://${PROJECT_REF}.supabase.co/storage/v1/object/reports/${fin.pdf_path}`, { headers: { apikey: service, Authorization: 'Bearer ' + service } });
  assert.equal(res.status, 200, 'storage GET ' + fin.pdf_path + ' -> ' + res.status);
  const buf = Buffer.from(await res.arrayBuffer());
  assert.equal(buf.subarray(0, 5).toString(), '%PDF-', 'object does not start with %PDF-');
  const pages = pageCount(buf);
  assert.ok(pages >= 2, `finance PDF has ${pages} page(s); expected at least 2`);
  const text = pdfText(buf);
  for (const word of ['Cash', 'Runway', 'AED']) assert.ok(text.includes(word), `finance PDF text does not contain "${word}" (extracted ${text.length} chars)`);
  console.log(`finance ${fin.source}#${fin.id}: ${fin.pdf_path}, ${buf.length} bytes, ${pages} pages, text ${text.length} chars`);
  console.log('sample: ' + text.replace(/\s+/g, ' ').slice(0, 400));
});
