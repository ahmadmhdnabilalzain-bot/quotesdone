#!/usr/bin/env node
// EVERY EXPENSE RECORD CAN BE OPENED — read against PRODUCTION, proved by fetching the bytes.
//
// The founder, 9 September 2026: "the accountant should actually have the pdfs in the records.
// cause later when we build the OS i wanna be able to click any record and see the actual invoice
// or receipt or email print pdf if none exist".
//
// WHAT THIS ASSERTS, and each line is here because its absence has been a real defect somewhere in
// this estate:
//
//   1. NO ROW POINTS AT NOTHING. A doc_path naming an object that is not in the bucket is worse
//      than a null one: the OS renders a link, the link 404s, and the record looks filed. Every
//      stored object is FETCHED and its bytes are checked, not counted from a column.
//   2. NO DOCUMENT IS UNCLASSIFIED. doc_kind must say whether the evidence is the vendor's own
//      invoice or a print of the covering email. "application/pdf" cannot tell those apart, and a
//      surface that infers provenance from a filename is guessing about evidence.
//   3. THE DOOR ANSWERS. fn_expense_document and the accountant's `document` action must mint a
//      signed url for a real row, and must ANSWER — not error — for a row with no document.
//
// WHAT IT DELIBERATELY DOES NOT FAIL ON: the number of records that carry no document yet. This
// table is written by live mail handlers and by the accountant's sweep, so a row can legitimately
// exist for a few seconds before its document does, and an absolute business count as a gate is the
// trap this estate has already paid for. The count is REPORTED, loudly, and the backfill closes it:
//   node scripts/expense_documents_backfill.mjs --report
//
// Exit 0 = every document that is claimed is really there and really says what it is.
import { readFileSync } from 'node:fs';
import { sql, PROJECT_REF } from '../lib/db.mjs';

let fails = 0;
const ok = (cond, what) => { console.log(`${cond ? 'ok  ' : 'FAIL'}  ${what}`); if (!cond) fails++; };

// ---------------------------------------------------------------------------------------------
// 0. The subject must exist. A check that passes because it found nothing to check is not a check.
// ---------------------------------------------------------------------------------------------
const [cov] = await sql('select public.fn_expense_document_coverage() j');
const C = cov.j;
console.log('coverage: ' + JSON.stringify(C.by_channel) + '  entries=' + C.entries
  + ' vendor_document=' + C.vendor_document + ' email_print=' + C.email_print
  + ' unclassified=' + C.unclassified + ' missing=' + C.missing);
ok(Number(C.entries) > 0, 'public.expense_entries holds rows to check');

// ---------------------------------------------------------------------------------------------
// 1. Nothing points at nothing. Every stored object is fetched.
// ---------------------------------------------------------------------------------------------
const mgmt = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
const kj = await (await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/api-keys?reveal=true`,
  { headers: { Authorization: 'Bearer ' + mgmt } })).json();
const ANON = kj.find((x) => x.name === 'anon')?.api_key;
const SERVICE = kj.find((x) => x.name === 'service_role')?.api_key;
if (!ANON || !SERVICE) { console.error('FAIL  could not read the project api keys'); process.exit(1); }

const rows = await sql('select id, vendor, doc_path, doc_kind, doc_content_type '
  + 'from public.expense_entries where doc_path is not null order by id');
const bad = [];
for (const r of rows) {
  const g = await fetch(`https://${PROJECT_REF}.supabase.co/storage/v1/object/receipt-files/${encodeURI(r.doc_path)}`,
    { headers: { Authorization: 'Bearer ' + SERVICE } });
  if (!g.ok) { bad.push(`#${r.id} ${r.vendor}: HTTP ${g.status} on ${r.doc_path}`); continue; }
  const b = new Uint8Array(await g.arrayBuffer());
  if (!b.length) bad.push(`#${r.id} ${r.vendor}: the object is empty`);
  else if (r.doc_content_type === 'application/pdf'
    && !(b[0] === 0x25 && b[1] === 0x50 && b[2] === 0x44 && b[3] === 0x46 && b[4] === 0x2d)) {
    bad.push(`#${r.id} ${r.vendor}: doc_content_type says application/pdf but the bytes do not begin %PDF-`);
  }
}
ok(bad.length === 0, `${rows.length} stored document(s) fetched back; ${bad.length} unreachable or not what the row claims`);
for (const b of bad) console.log('        ' + b);

// ---------------------------------------------------------------------------------------------
// 2. No document is unclassified.
// ---------------------------------------------------------------------------------------------
ok(Number(C.unclassified) === 0,
  `${C.unclassified} record(s) carry a document with no doc_kind — the OS cannot tell the vendor's invoice from a print of the covering email`);

// ---------------------------------------------------------------------------------------------
// 3. The door answers, for a real row and for one with nothing.
// ---------------------------------------------------------------------------------------------
const SEC = (await sql("select value from public.app_secrets where key='cred_fn_accountant'"))[0]?.value;
ok(!!SEC, 'app_secrets.cred_fn_accountant is readable, so the document door can be called');
if (SEC) {
  const call = async (body) => {
    const r = await fetch(`https://${PROJECT_REF}.supabase.co/functions/v1/accountant`, {
      method: 'POST',
      headers: { apikey: ANON, Authorization: 'Bearer ' + ANON, 'Content-Type': 'application/json' },
      body: JSON.stringify({ __secret: SEC, ...body }),
      signal: AbortSignal.timeout(60_000),
    });
    return { status: r.status, json: await r.json().catch(() => ({})) };
  };
  const [f] = await sql(`select
    (select id from public.v_expense_documents where document_state<>'missing' order by id limit 1) any_doc,
    (select id from public.v_expense_documents where document_state='missing'  order by id limit 1) no_doc,
    (select max(id)+1000 from public.expense_entries) absent`);
  ok(!!f.any_doc, 'a record with a document exists to open (fixture)');
  if (f.any_doc) {
    const { status, json } = await call({ action: 'document', entry_id: f.any_doc });
    ok(status === 200 && json.ok === true && typeof json.url === 'string',
      `document #${f.any_doc}: the accountant minted a signed url (http ${status})`);
    if (json.url) {
      const g = await fetch(json.url);
      const b = new Uint8Array(await g.arrayBuffer());
      ok(g.ok && b.length > 4 && b[0] === 0x25 && b[1] === 0x50 && b[2] === 0x44 && b[3] === 0x46,
        `document #${f.any_doc}: that url really serves the document (${b.length} bytes)`);
    }
  }
  if (f.no_doc) {
    const { status, json } = await call({ action: 'document', entry_id: f.no_doc });
    ok(status === 200 && json.ok === false && json.state === 'missing' && !!json.reason,
      `document #${f.no_doc}: a record with no document is REPORTED as missing with a reason, never a broken link`);
  }
  const absent = await call({ action: 'document', entry_id: f.absent });
  ok(absent.json.state === 'no_such_entry',
    'an id that does not exist is distinguished from a record whose document is missing');
}

// ---------------------------------------------------------------------------------------------
// Reported, never failed on. See the header.
// ---------------------------------------------------------------------------------------------
if (Number(C.missing) > 0) {
  console.log(`\nNOTE  ${C.missing} expense record(s) carry NO document: ids ${JSON.stringify(C.missing_ids)}. `
    + 'That is reportable state, not a failure — run `node scripts/expense_documents_backfill.mjs --report` '
    + 'and then the backfill to close it.');
}
console.log(fails === 0 ? '\nEVERY CLAIMED DOCUMENT IS REALLY THERE.' : `\n${fails} CHECK(S) FAILED`);
process.exit(fails === 0 ? 0 : 1);
