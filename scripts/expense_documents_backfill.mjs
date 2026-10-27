#!/usr/bin/env node
// EVERY EXPENSE RECORD GETS A DOCUMENT YOU CAN OPEN.
//
// The founder, 9 September 2026: "but the accountant should actually have the pdfs in the records.
// cause later when we build the OS i wanna be able to click any record and see the actual invoice
// or receipt or email print pdf if none exist".
//
// This is the backfill half of that. The live half is in resend_inbound / accountant.
//
// THE ORDER OF PREFERENCE, and it is never guessed at:
//   1. THE VENDOR'S OWN FILE off the source email. For a `resend:` row that is the PDF attachment,
//      fetched from Resend's inbound history. For a `gmail:` row Resend no longer holds the message
//      (its inbound retention is about a month; measured 9 Sep 2026: the history holds 9 messages,
//      12 Aug - 3 Sep, while the book runs back to 26 May) and the Gmail connector exposes an
//      attachment's NAME but no byte channel. What it does expose is the message text, and a
//      forwarded Stripe-billed receipt carries a link to the vendor's own invoice PDF in that text.
//      That link is followed, and the bytes are only accepted if they really begin `%PDF-`.
//   2. A PDF PRINT OF THE EMAIL ITSELF, rendered by pdf_native, marked doc_kind='email_print'.
//   3. Nothing -- and then doc_path stays null and v_expense_documents reports it as 'missing'.
//
// NOTHING IS EVER FABRICATED. A document is stored only if its bytes were fetched and verified; a
// row is only ever pointed at the object THIS run uploaded for it. The only columns written are
// doc_path, doc_name, doc_content_type, doc_kind and doc_note -- never an amount, a currency, a
// vendor, a date or a source_msg_id. A second agent is writing rows to this table while this runs.
//
// RE-RUNNABLE. It reads whatever rows exist at the moment it runs, skips any row that already has a
// verified vendor document, and can be run again the instant more rows arrive.
//
//   node scripts/expense_documents_backfill.mjs --report
//   node scripts/expense_documents_backfill.mjs --resend [--apply]
//   node scripts/expense_documents_backfill.mjs --messages <dir> [--apply]
//   node scripts/expense_documents_backfill.mjs --verify
//   node scripts/expense_documents_backfill.mjs --prune [--apply]
import { supabaseAccessToken } from './lib/supabase_token.mjs';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { sql, PROJECT_REF } from './lib/db.mjs';
import { pickApiKey } from './lib/supabase_keys.mjs';   // new keys first; legacy only as a temporary fallback (27 Oct 2026)

const ARG = process.argv.slice(2);
const has = (f) => ARG.includes(f);
const val = (f) => { const i = ARG.indexOf(f); return i >= 0 ? ARG[i + 1] : null; };
const APPLY = has('--apply');
const BUCKET = 'receipt-files';
const BASE = `https://${PROJECT_REF}.supabase.co`;

const q = (s) => `'${String(s).replace(/'/g, "''")}'`;
const nul = (s) => (s === null || s === undefined ? 'null' : q(s));

// ---- keys ------------------------------------------------------------------------------------
let _k = null;
async function keys() {
  if (_k) return _k;
  const mgmt = supabaseAccessToken();
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/api-keys?reveal=true`,
    { headers: { Authorization: 'Bearer ' + mgmt } });
  const j = await r.json();
  const ANON = pickApiKey(j, 'publishable');
  const SERVICE = pickApiKey(j, 'secret');
  if (!ANON || !SERVICE) throw new Error('could not read the project api keys');
  _k = { ANON, SERVICE };
  return _k;
}
let _sec = null;
async function secrets() {
  if (_sec) return _sec;
  const rows = await sql("select key, value from public.app_secrets where key in ('resend_api_key','cred_fn_to_pdf_native')");
  _sec = Object.fromEntries(rows.map((r) => [r.key, r.value]));
  return _sec;
}

// ---- storage ---------------------------------------------------------------------------------
async function upload(path, bytes, contentType) {
  const { SERVICE } = await keys();
  const r = await fetch(`${BASE}/storage/v1/object/${BUCKET}/${path}`, {
    method: 'POST',
    headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': contentType, 'x-upsert': 'true' },
    body: bytes,
  });
  if (!r.ok) throw new Error(`upload ${path} -> HTTP ${r.status} ${(await r.text()).slice(0, 200)}`);
  return path;
}
async function download(path) {
  const { SERVICE } = await keys();
  const r = await fetch(`${BASE}/storage/v1/object/${BUCKET}/${encodeURI(path)}`,
    { headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE } });
  if (!r.ok) return { ok: false, status: r.status, bytes: null };
  return { ok: true, status: 200, bytes: new Uint8Array(await r.arrayBuffer()) };
}
const isPdf = (b) => !!b && b.length > 4 && b[0] === 0x25 && b[1] === 0x50 && b[2] === 0x44 && b[3] === 0x46 && b[4] === 0x2d;

// ---- the vendor's own file, followed out of the message text ---------------------------------
// A forwarded Stripe-billed receipt (Vercel, OpenRouter, Resend, Supabase, Anthropic, Figma ...)
// carries "Download invoice" / "Download receipt" as a click-tracking wrapper around the vendor's
// real PDF url. The wrapper is UNWRAPPED rather than followed, so nothing registers a click on the
// founder's behalf and the request goes to the vendor's own host.
function unwrapTracking(u) {
  const m = String(u).match(/\/CL\d+\/(https?(?::|%3A|%3a)[^\s]*?)\/\d+\/[0-9a-f]{8}/);
  if (!m) return String(u);
  try { return decodeURIComponent(m[1]); } catch { return m[1]; }
}
const PRIVATE_HOST = /^(localhost$|127\.|10\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.|\[|0\.0\.0\.0$)/i;
function pdfUrlsIn(text) {
  const out = [];
  const seen = new Set();
  for (const raw of String(text || '').match(/https?:\/\/[^\s<>"')\]]+/g) || []) {
    const u = unwrapTracking(raw.replace(/[.,;]+$/, ''));
    let parsed; try { parsed = new URL(u); } catch { continue; }
    if (parsed.protocol !== 'https:') continue;              // http:// is never a vendor invoice host
    if (PRIVATE_HOST.test(parsed.hostname)) continue;        // never reach for a private address
    const p = parsed.pathname.toLowerCase();
    if (!(p.endsWith('.pdf') || p.endsWith('/pdf') || p.includes('/pdf/'))) continue;
    if (seen.has(parsed.href)) continue;
    seen.add(parsed.href); out.push(parsed.href);
  }
  return out;
}
async function fetchVendorPdf(urls) {
  for (const u of urls) {
    try {
      const r = await fetch(u, { redirect: 'follow', signal: AbortSignal.timeout(30000) });
      if (!r.ok) continue;
      const b = new Uint8Array(await r.arrayBuffer());
      if (isPdf(b) && b.length > 400) return { bytes: b, url: u };
    } catch { /* a link that does not answer is not evidence; try the next */ }
  }
  return null;
}

// ---- the email print -------------------------------------------------------------------------
// pdf_native NAMES ITS OWN PATH. The path it RETURNS is the one written to the row - never one
// composed here - because it is the only value that is certain to name the object it just wrote.
const softWrap = (s) => String(s || '').split(/(\s+)/)
  .map((t) => (t.length > 95 ? (t.match(/.{1,95}/g) || [t]).join(' ') : t)).join('');

// THE INVISIBLE PADDING IS REMOVED BEFORE RENDERING, so that `glyphs_dropped` means something.
// Measured on the live receipts (9 Sep 2026): an OpenRouter receipt carries 138x U+2007 and 138x
// U+034F, a GoDaddy one 122x U+200C -- the zero-width filler marketing mail uses to pad the inbox
// preview snippet. pdf_native reported 276 characters dropped rendering that email, every one of
// them invisible. Left in, a real loss of content would be indistinguishable from that noise;
// stripped, any non-zero glyphs_dropped on an email print is a finding.
const stripInvisible = (s) => String(s || '')
  .replace(/[͏​‌‍⁠﻿­]/g, '')
  .replace(/[   ]/g, ' ');

async function emailPrint(entry, msg) {
  const { ANON } = await keys();
  const S = await secrets();
  if (!S.cred_fn_to_pdf_native) throw new Error('app_secrets.cred_fn_to_pdf_native is unreadable');
  const paras = stripInvisible(msg.body).replace(/\r/g, '').split(/\n{2,}/)
    .map((p) => softWrap(p.replace(/\n/g, ' ').replace(/[ \t]+/g, ' ').trim()))
    .filter((p) => p.length > 0).slice(0, 260);
  const blocks = [
    { t: 'h2', text: 'Print of the covering email' },
    { t: 'kv', pairs: [
      ['Vendor', String(entry.vendor)],
      ['Amount', `${entry.amount} ${entry.currency}`],
      ['Charged on', String(entry.charged_on)],
      ['Expense record', `expense_entries #${entry.id}`],
      ['Source message', String(entry.source_msg_id || '-')],
      ['From', String(msg.from || '-')],
      ['Sent', String(msg.date || '-')],
      ['Subject', softWrap(String(msg.subject || '-'))],
      ['Vendor file on the email', msg.attachments && msg.attachments.length
        ? msg.attachments.map((a) => a.filename || a.name).join(', ')
        : 'none'],
    ] },
    { t: 'note', text: 'This is a PDF PRINT OF THE EMAIL, not the vendor\'s own invoice document. '
      + (msg.attachments && msg.attachments.length
        ? 'The source message carries the vendor file named above; it could not be retrieved through '
          + 'any byte channel available to the archive, so this print stands in for it.'
        : 'The source message carried no vendor file at all.')
      + ' Long links in the original are wrapped across lines to fit the page; their text is unchanged.' },
    { t: 'h3', text: 'Message as received' },
    ...paras.map((text) => ({ t: 'p', text, size: 9.5 })),
  ];
  const r = await fetch(`${BASE}/functions/v1/pdf_native`, {
    method: 'POST',
    headers: { apikey: ANON, Authorization: 'Bearer ' + ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      __secret: S.cred_fn_to_pdf_native,
      title: `Email print — ${entry.vendor} ${entry.amount} ${entry.currency}`,
      date: String(entry.charged_on),
      bucket: BUCKET,
      folder: `receipts/email-prints/${String(entry.charged_on)}`,
      name: `email-print-${entry.id}-${String(entry.vendor).replace(/[^\w.-]+/g, '_')}`,
      blocks,
      options: { letterhead: true },
    }),
    signal: AbortSignal.timeout(120000),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || !j.ok || !j.path) throw new Error(`pdf_native HTTP ${r.status} ${JSON.stringify(j).slice(0, 300)}`);
  if (j.glyphs_dropped) console.warn(`   ! pdf_native dropped ${j.glyphs_dropped} glyph(s) rendering #${entry.id}: ${j.sample || ''}`);
  return { path: j.path, name: `email-print-${entry.id}.pdf`, bytes: j.bytes };
}

// ---- the one write ---------------------------------------------------------------------------
// ONLY the five document columns. Never an amount, a currency, a vendor, a date, a VAT figure or a
// source_msg_id: another agent owns the figures on this table and nothing here may move one.
async function writeDoc(id, { path, name, type, kind, note }) {
  await sql(`update public.expense_entries set doc_path=${q(path)}, doc_name=${q(String(name).slice(0, 180))}, `
    + `doc_content_type=${q(type)}, doc_kind=${q(kind)}, doc_note=${nul(note && String(note).slice(0, 600))} `
    + `where id=${Number(id)}`);
}

async function entries() {
  return await sql('select id, vendor, amount, currency, charged_on, source_msg_id, doc_path, doc_name, '
    + 'doc_content_type, doc_kind, doc_note from public.expense_entries order by id');
}
// A RE-RUN MAY ONLY UPGRADE EVIDENCE, NEVER CHURN IT.
//   * a row already holding the vendor's own document is finished — skip it entirely;
//   * a row holding an email print is still worth ANOTHER LOOK for the vendor's file (a link that
//     had not been reachable, an attachment that has since arrived), but if that look finds nothing
//     the existing print STAYS. Re-rendering it would move doc_path to a byte-identical new object
//     and orphan the old one, so a second run would quietly litter the bucket and rewrite rows that
//     were already correct — which is what the first re-run of this script actually did.
//   * a row with no document at all gets the full treatment.
// --force-print overrides, for when a print must genuinely be re-rendered.
const FORCE = has('--force-print');
const needsWork = (e) => FORCE || !(e.doc_path && e.doc_kind === 'vendor_document');
const printOnlyIfNothingBetter = (e) => !FORCE && !!e.doc_path && e.doc_kind === 'email_print';

// ---- report ----------------------------------------------------------------------------------
async function report() {
  const [c] = await sql('select public.fn_expense_document_coverage() j');
  console.log(JSON.stringify(c.j, null, 2));
  const rows = await sql("select id, vendor, charged_on, source_channel, document_state, doc_kind, "
    + "coalesce(doc_name,'-') doc_name from public.v_expense_documents order by id");
  for (const r of rows) {
    console.log(`#${String(r.id).padStart(3)} ${String(r.document_state).padEnd(15)} ${String(r.source_channel).padEnd(8)} `
      + `${String(r.vendor).padEnd(12)} ${r.charged_on} ${r.doc_name}`);
  }
}

// ---- verify: fetch every stored object BACK and assert it is really there and really a PDF ----
async function verify() {
  const rows = await sql("select id, vendor, doc_path, doc_name, doc_content_type, doc_kind "
    + 'from public.expense_entries where doc_path is not null order by id');
  let realPdf = 0, notPdf = 0, missingObject = 0;
  for (const r of rows) {
    const d = await download(r.doc_path);
    if (!d.ok) { missingObject++; console.log(`#${r.id} ${r.vendor}: OBJECT MISSING (HTTP ${d.status}) ${r.doc_path}`); continue; }
    const ok = isPdf(d.bytes);
    if (ok) realPdf++; else notPdf++;
    console.log(`#${String(r.id).padStart(3)} ${String(r.doc_kind || 'unclassified').padEnd(15)} `
      + `${ok ? '%PDF- ok' : 'NOT A PDF'} ${String(d.bytes.length).padStart(8)} bytes  ${r.doc_path}`);
  }
  const nodoc = await sql('select count(*) n from public.expense_entries where doc_path is null');
  console.log(`\nVERIFY: ${rows.length} row(s) with a document — ${realPdf} verified %PDF-, ${notPdf} not a PDF, `
    + `${missingObject} pointing at nothing. ${nodoc[0].n} row(s) carry no document.`);
  return { realPdf, notPdf, missingObject, noDoc: Number(nodoc[0].n) };
}

// ---- resend rows -----------------------------------------------------------------------------
async function doResend() {
  const S = await secrets();
  if (!S.resend_api_key) throw new Error('app_secrets.resend_api_key is unreadable');
  const R = (u) => fetch(u, { headers: { Authorization: 'Bearer ' + S.resend_api_key } });
  const list = (await entries()).filter((e) => String(e.source_msg_id || '').startsWith('resend:')).filter(needsWork);
  console.log(`resend rows needing a document: ${list.length}`);
  for (const e of list) {
    const eid = e.source_msg_id.slice(7);
    const mr = await R('https://api.resend.com/emails/inbound/' + eid);
    if (!mr.ok) { console.log(`#${e.id} ${e.vendor}: message unreadable (HTTP ${mr.status}) — left as is`); continue; }
    const mj = await mr.json().catch(() => ({}));
    const d = mj.data || mj;   // Resend answers this endpoint unwrapped; `|| {}` here read as "no attachments"
    const atts = Array.isArray(d.attachments) ? d.attachments : [];

    // 1. the vendor's own attachment
    let got = null, note = null;
    for (const a of atts) {
      const fn = String(a.filename || a.name || '');
      const mm = String(a.content_type || a.contentType || '');
      if (!(/pdf/i.test(mm) || /\.pdf$/i.test(fn))) continue;
      const ar = await R(`https://api.resend.com/emails/inbound/${eid}/attachments/${a.id}`);
      if (!ar.ok) continue;
      const aj = await ar.json().catch(() => ({}));
      const ao = aj.data || aj;   // unwrapped, same as the message endpoint
      const url = String(ao.download_url || ao.url || '');
      if (!url) continue;
      const br = await fetch(url, { signal: AbortSignal.timeout(30000) });
      if (!br.ok) continue;
      const bytes = new Uint8Array(await br.arrayBuffer());
      if (!isPdf(bytes)) continue;
      got = { bytes, name: fn || 'invoice.pdf' };
      note = `The vendor's own file, taken off the source email (Resend inbound ${eid}, attachment ${fn}).`;
      break;
    }
    // 2. the vendor's own file behind a link in the message
    if (!got) {
      const found = await fetchVendorPdf(pdfUrlsIn(String(d.text || '') + '\n' + String(d.html || '')));
      if (found) {
        got = { bytes: found.bytes, name: (new URL(found.url).pathname.split('/').filter(Boolean).pop() || 'invoice') + '.pdf' };
        note = `The vendor's own invoice PDF, fetched from the link the receipt email carries (${new URL(found.url).host}).`;
      }
    }
    if (!got && printOnlyIfNothingBetter(e)) { console.log(`#${e.id} ${e.vendor}: still no vendor file; the existing email print stands`); continue; }
    if (!APPLY) { console.log(`#${e.id} ${e.vendor}: would store ${got ? 'VENDOR PDF' : 'EMAIL PRINT'} (${atts.length} attachment(s))`); continue; }

    if (got) {
      const path = `receipts/${e.charged_on}/${Date.now()}_${String(e.vendor).replace(/[^A-Za-z0-9._-]/g, '_')}.pdf`;
      await upload(path, got.bytes, 'application/pdf');
      await writeDoc(e.id, { path, name: got.name, type: 'application/pdf', kind: 'vendor_document', note });
      console.log(`#${e.id} ${e.vendor}: vendor document stored (${got.bytes.length} bytes) ${path}`);
    } else {
      const p = await emailPrint(e, {
        subject: d.subject, from: d.from, date: d.created_at,
        body: String(d.text || '').trim() || String(d.html || '').replace(/<[^>]+>/g, ' '),
        attachments: atts.map((a) => ({ filename: a.filename || a.name })),
      });
      await writeDoc(e.id, { path: p.path, name: p.name, type: 'application/pdf', kind: 'email_print',
        note: 'The source email carried no vendor file, so this is a print of the email itself '
          + `(Resend inbound ${eid}).` });
      console.log(`#${e.id} ${e.vendor}: email print stored (${p.bytes} bytes) ${p.path}`);
    }
  }
}

// ---- gmail / outlook rows, from message JSON an agent wrote --------------------------------
// Two files per message, and the split is deliberate: <entry_id>.json carries the small exact
// fields ({ entry_id, message_id, subject, from, date, attachments:[{filename}] }) and
// <entry_id>.body.txt carries the message text RAW. A 4 KB email body re-typed as a JSON string
// literal is 4 KB of escaping to get exactly right; as a plain text file it is the bytes.
// The script does the deciding: it looks for the vendor's own invoice link in that text FIRST, and
// only prints the email when there is none.
async function doMessages(dir) {
  if (!existsSync(dir)) throw new Error('no such directory: ' + dir);
  const byId = new Map((await entries()).map((e) => [Number(e.id), e]));
  const files = readdirSync(dir).filter((f) => f.endsWith('.json')).sort((a, b) => Number(a.split('.')[0]) - Number(b.split('.')[0]));
  console.log(`message files: ${files.length}`);
  for (const f of files) {
    let m; try { m = JSON.parse(readFileSync(join(dir, f), 'utf8')); } catch (err) { console.log(`${f}: unreadable JSON — ${err.message}`); continue; }
    const side = join(dir, `${m.entry_id}.body.txt`);
    if (existsSync(side)) m.body = readFileSync(side, 'utf8');
    if (!String(m.body || '').trim()) { console.log(`${f}: no message body (looked for ${m.entry_id}.body.txt) — skipped`); continue; }
    const e = byId.get(Number(m.entry_id));
    if (!e) { console.log(`${f}: no expense_entries row #${m.entry_id} — skipped`); continue; }
    if (!needsWork(e)) { console.log(`#${e.id} ${e.vendor}: already carries a vendor document — skipped`); continue; }

    const found = await fetchVendorPdf(pdfUrlsIn(m.body));
    if (!found && printOnlyIfNothingBetter(e)) { console.log(`#${e.id} ${e.vendor}: still no vendor file; the existing email print stands`); continue; }
    if (!APPLY) { console.log(`#${e.id} ${e.vendor}: would store ${found ? 'VENDOR PDF from ' + new URL(found.url).host : 'EMAIL PRINT'}`); continue; }

    if (found) {
      const path = `receipts/${e.charged_on}/${Date.now()}_${String(e.vendor).replace(/[^A-Za-z0-9._-]/g, '_')}.pdf`;
      await upload(path, found.bytes, 'application/pdf');
      const named = (m.attachments || []).map((a) => a.filename).filter(Boolean).join(', ');
      // NAME IT WHAT THE VENDOR NAMED IT. A Stripe hosted-invoice url ends in the literal segment
      // "pdf", so deriving the name from the path produced "pdf.pdf" — a filename that tells an
      // auditor nothing. The same email attaches the vendor's own file under its real name, and
      // this IS that document, so that name is the honest one; the derived one is the fallback.
      const vendorName = (m.attachments || []).map((a) => a.filename)
        .find((n) => /\.pdf$/i.test(String(n || ''))) || null;
      await writeDoc(e.id, { path,
        name: vendorName || `${String(e.vendor).replace(/[^\w.-]+/g, '_')}-invoice-${e.charged_on}.pdf`,
        type: 'application/pdf', kind: 'vendor_document',
        note: `The vendor's own invoice PDF, fetched from the link the receipt email carries (${new URL(found.url).host}). `
          + `Source message ${m.message_id}${named ? `; the same email also attaches ${named}` : ''}.` });
      console.log(`#${e.id} ${e.vendor}: vendor document stored (${found.bytes.length} bytes) ${path}`);
    } else {
      const p = await emailPrint(e, m);
      const named = (m.attachments || []).map((a) => a.filename).filter(Boolean).join(', ');
      await writeDoc(e.id, { path: p.path, name: p.name, type: 'application/pdf', kind: 'email_print',
        note: named
          ? `A print of the covering email. The source message ${m.message_id} attaches the vendor file ${named}, `
            + 'but Resend no longer holds this message and the Gmail connector exposes no byte channel for an '
            + 'attachment, so the vendor document itself is NOT in the archive.'
          : `A print of the covering email; the source message ${m.message_id} carried no vendor file.` });
      console.log(`#${e.id} ${e.vendor}: email print stored (${p.bytes} bytes) ${p.path}`);
    }
  }
}

// ---- prune: email prints no expense record points at ------------------------------------------
// ONLY under receipts/email-prints/, and ONLY objects no row references. A vendor's own file is
// never touched: it is irreplaceable evidence and a bug here would destroy it. An orphan is
// created when a print is re-rendered, and an auditor finding five versions of one print in the
// bucket has to work out which one the record means — the answer should be "the only one".
async function prune() {
  const { SERVICE } = await keys();
  const referenced = new Set((await sql('select doc_path from public.expense_entries where doc_path is not null'))
    .map((r) => r.doc_path));
  const prefixes = (await sql("select distinct substring(doc_path from '^receipts/email-prints/[0-9-]+') p "
    + "from public.expense_entries where doc_path like 'receipts/email-prints/%'"))
    .map((r) => r.p).filter(Boolean);
  let orphans = 0, removed = 0;
  for (const prefix of prefixes) {
    const r = await fetch(`${BASE}/storage/v1/object/list/${BUCKET}`, {
      method: 'POST',
      headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/json' },
      body: JSON.stringify({ prefix: prefix + '/', limit: 1000 }),
    });
    if (!r.ok) { console.log(`list ${prefix}: HTTP ${r.status}`); continue; }
    for (const o of await r.json()) {
      const path = `${prefix}/${o.name}`;
      if (referenced.has(path)) continue;
      orphans++;
      if (!APPLY) { console.log(`orphan (would delete): ${path}`); continue; }
      const del = await fetch(`${BASE}/storage/v1/object/${BUCKET}/${encodeURI(path)}`,
        { method: 'DELETE', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE } });
      if (del.ok) { removed++; console.log(`deleted orphan: ${path}`); }
      else console.log(`could not delete ${path}: HTTP ${del.status}`);
    }
  }
  console.log(`\nPRUNE: ${orphans} orphaned email print(s) under receipts/email-prints/, ${removed} deleted. `
    + 'No vendor document was examined or touched.');
}

// ---- main ------------------------------------------------------------------------------------
const t0 = Date.now();
if (has('--report')) await report();
else if (has('--verify')) await verify();
else if (has('--resend')) await doResend();
else if (has('--messages')) await doMessages(val('--messages'));
else if (has('--prune')) await prune();
else { console.error(readFileSync(new URL(import.meta.url)).toString().split('\n').filter((l) => l.startsWith('//   node')).join('\n')); process.exit(2); }
if (!APPLY && (has('--resend') || has('--messages'))) console.log('\nDRY RUN — nothing was written. Add --apply.');
console.log(`\n(${((Date.now() - t0) / 1000).toFixed(1)}s)`);
