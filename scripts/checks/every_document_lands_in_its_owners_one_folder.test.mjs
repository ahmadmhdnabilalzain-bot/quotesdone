// Founder gate, ledger 1162 (7 Oct 2026): "no issue in the Dropbox backup of supplier/customer documents
// and the folder workflow and organisation". Owners: sales_engineer files, it_engineer verifies.
//
// What this keeps from coming back (each measured on production on 7 Oct 2026, counts only):
//   1. ONE FOLDER PER ENTITY. 2 of 60 inquiries and 2 of 40 customers were split across two Dropbox
//      folders: the inquiry folder carried the status and was recomputed for every new file. The admit
//      trigger must file a later document beside the entity's first (its Details / Summary row).
//   2. A CUSTOMER'S DOCUMENTS UNDER THE CUSTOMER. 386 owned files sat in Storage/<bucket>/<path>. The
//      enqueue must file the supplier's quotation, the quotation PDF, the reveal receipt, the comparison
//      report and the brief under the request; customer_api must write those two reports where it looks.
//   3. A MISSING COPY IS FOUND THE NEXT DAY. The daily check read new rows and a weekly random 20 of
//      24,156. dropbox_backup's reconcile must compare the whole listing.
//   4. DEMO STAYS OUT, EXCEPT A TAGGED SANDBOX. A demo document reaches Dropbox only under _sandbox/<tag>/.
//
// The routine text read is the canonical one: the LAST file in MANIFEST order (pending files included)
// that defines it, so the check is true of what is applied at merge, not of an older body.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { manifestWithPending } from '../lib/pending_sql.mjs';
import { functionSource } from '../lib/function_sources.mjs';

const ROOT = fileURLToPath(new URL('../..', import.meta.url));
const FILES = manifestWithPending(ROOT);

function canonicalBody(name) {
  let body = null;
  for (const f of FILES) {
    let s; try { s = readFileSync(join(ROOT, f), 'utf8'); } catch { continue; }
    const i = s.search(new RegExp(`create\\s+or\\s+replace\\s+function\\s+public\\.${name}\\s*\\(`, 'i'));
    if (i < 0) continue;
    const m = /\bas\s+(\$[A-Za-z_]*\$)/i.exec(s.slice(i));
    const start = i + m.index + m[0].length;
    body = s.slice(start, s.indexOf(m[1], start));
  }
  assert.ok(body, `no file in MANIFEST.txt or scripts/sql/pending defines public.${name}`);
  return body.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');     // code, not comments
}
const src = (p) => readFileSync(join(ROOT, p), 'utf8');

test('the admit trigger files every later document beside the entity\'s first', () => {
  const t = canonicalBody('trg_doc_backups_admit');
  for (const anchor of [`'S:' || v_id || ':details'`, `'C:' || v_cust || ':details'`, `'I:' || v_inq || ':summary'`]) {
    assert.ok(t.includes(anchor), `trg_doc_backups_admit no longer anchors on ${anchor}: a status, name or category change splits the folder again`);
  }
});

test('the customer and supplier folder is the NAMED one, never a placeholder opened before the name was known', () => {
  // 12 Oct 2026 review of #1284: 5 files would have been merged INTO "Customer (<id8>)" because the first file of
  // 2 customers was filed before the name was saved; the trigger must not anchor on such a folder.
  const t = canonicalBody('trg_doc_backups_admit');
  assert.ok(t.includes(String.raw`v_anchor !~ '/Customer \([0-9a-f]{8}\)/$'`), 'a "Customer (<id8>)" first folder must not decide the customer folder');
  assert.ok(t.includes(String.raw`v_anchor !~ ('/Supplier \(' || v_id || '\)/$')`), 'a "Supplier (<id>)" first folder must not decide the supplier folder');
});

test('demo rows are dropped unless a tagged sandbox run admits its own, under _sandbox/<tag>/', () => {
  const t = canonicalBody('trg_doc_backups_admit');
  assert.match(t, /return null;/, 'the trigger must still refuse demo rows');
  assert.match(t, /current_setting\('qd\.backup_sandbox', true\)/, 'the sandbox switch is the transaction-local setting only');
  assert.match(t, /'\/QuotesDone Backup\/_sandbox\/' \|\| v_tag/, 'a sandbox row is re-rooted under _sandbox/<tag>/');
  assert.match(t, /new\.entity := 'zz_demo'/, 'a sandbox row is entity zz_demo, which the scheduled uploader never claims');
  const e = canonicalBody('fn_enqueue_doc_backups');
  assert.match(e, /not v\.is_demo or coalesce\(current_setting\('qd\.backup_sandbox', true\), ''\) <> ''/,
    'correspondence lets demo messages through only inside a tagged sandbox');
  assert.match(canonicalBody('fn_backup_sandbox_enqueue'), /set_config\('qd\.backup_sandbox', p_tag, true\)/, 'the switch is local to the transaction');
});

test('a customer\'s quotations, receipts and reports are filed under the request, not in Storage/', () => {
  const e = canonicalBody('fn_enqueue_doc_backups');
  for (const [what, shape] of [['the supplier\'s quotation', /from public\.quotes q\s+where length\(coalesce\(q\.original_file_path/],
    ['the quotation PDF', /from public\.quote_pdf_cache p/], ['the reveal receipt', /o\.name like 'reveal\\_invoice\/%'/],
    ['the comparison report and brief', /o\.name like 'compare\/%' or o\.name like 'brief\/%'/]]) {
    assert.match(e, shape, `fn_enqueue_doc_backups no longer files ${what} under the request`);
  }
  assert.match(e, /\/Inquiries\/'[\s\S]*x\.folder/, 'the documents go into a folder of the request');
  const api = functionSource('customer_api');
  assert.match(api, /folder: 'compare\/' \+ inq\.id/, 'customer_api writes the comparison report where the enqueue reads it');
  assert.match(api, /folder: 'brief\/' \+ inq\.id/, 'customer_api writes the brief where the enqueue reads it');
});

test('the daily check compares the whole Dropbox listing, inside the caller\'s wait', () => {
  const d = src('supabase/functions/dropbox_backup/index.ts');
  assert.match(d, /await listingCheck\(dbx, await dailyRoots\(dbx\), t0\(\) \+ LISTING_BUDGET_MS, true\)/, 'reconcile must list every root every day');
  const budget = Number(/const LISTING_BUDGET_MS = ([\d_]+)/.exec(d)?.[1].replace(/_/g, ''));
  const wait = Number(/mode: 'reconcile'[^\n]*AbortSignal\.timeout\((\d+)\)/.exec(functionSource('resilience_ping'))?.[1]);
  assert.ok(budget > 0 && wait > 0 && budget + 10_000 <= wait, `the listing budget (${budget} ms) plus confirmation must end inside resilience_ping's wait (${wait} ms)`);
  assert.match(d, /fn_it_backup_listing_record/, 'every listing reading is put on the record');
  // public.dropbox_files was last synced 7 Sep 2026 while seven routines read it: the daily walk refreshes it
  assert.match(d, /rpc\('fn_dropbox_files_refresh', \{ p_root: root, p_rows: sl\.rows, p_stamp: stamp, p_final: sl\.final \}\)/, 'the daily walk refreshes public.dropbox_files');
  assert.match(canonicalBody('fn_dropbox_files_refresh'), /if p_final then\s+delete from public\.dropbox_files/, 'only the final slice of a complete root removes rows');
  assert.match(canonicalBody('fn_it_backup_listing_expected'), /starts_with\(p_root, '\/QuotesDone Backup\/_sandbox\/'\)/, 'demo rows are expected only under _sandbox/');
});
