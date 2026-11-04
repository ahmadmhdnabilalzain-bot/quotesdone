// THE KNOWLEDGE LIBRARY'S BACKFILL (it_engineer, 5 Oct 2026; ledger 1085 stage 2, phase 1).
//
// Drives public.fn_knowledge_library_fill_page(store, n) store by store until every origin row of the nine stores is
// in public.knowledge_library, then prints fn_knowledge_library_reconcile(). SQL:
// scripts/sql/one_knowledge_library_is_built_beside_the_nine_stores_and_read_behind_a_flag.sql.
//
//   node scripts/kb/fill_knowledge_library.mjs            # plan: what is left per store; writes only the verdict row
//   node scripts/kb/fill_knowledge_library.mjs --run      # fill, 23:00-06:00 Asia/Dubai only
//   --limit=N (1..5000, default 2000)   --force-hours (outside the night window; never in a campaign hour)
//
// The same guards as the 21 Sep purge (scripts/kb/purge_guard.mjs): night window, fn_kb_purge_load() before EVERY
// page, never beside a purge or trim batch (the page takes the same advisory lock), never a retry on a 5xx (a 524 can
// commit behind the error; a re-run simply carries on from what is mapped). Measured in a rolled-back transaction on
// 5 Oct 2026: 5,000 ops_knowledge origins = 13.5 s with the HNSW indexes in place, 2,556 agent_knowledge = 1.5 s.
// ORDER does not decide the outcome: the primary of a shared text is chosen by store priority (kb_chunks, ops, agent)
// whatever order the rows arrive in. kb_chunks goes first only because it is the bulk.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
// THE SWITCH (27 Oct 2026, ledger 889; scripts/sql/the_seats_read_the_knowledge_library_once_it_holds_every_row.sql):
// every reconciliation this script runs is RECORDED in knowledge_library_state, and the seats read the library exactly
// while the recorded verdict says reconciled. The run that maps the last page is therefore the run that switches every
// seat to the library; a later NOT reconciled verdict switches them back. Nobody sets a flag.
import { sql, PROJECT_REF } from '../lib/db.mjs';
import { BATCH_DEFAULT, BATCH_MAX, PAUSE_MS, loadVerdict, inNightWindow } from './purge_guard.mjs';

const RUN = process.argv.includes('--run');
const FORCE_HOURS = process.argv.includes('--force-hours');
const LIMIT = Number((process.argv.find(a => a.startsWith('--limit=')) || `--limit=${BATCH_DEFAULT}`).slice(8));
const STORES = ['kb_chunks', 'ops_knowledge', 'agent_knowledge', 'sales_knowledge', 'ceo_knowledge', 'support_knowledge',
  'accountant_knowledge', 'it_engineer_knowledge', 'marketing_knowledge'];
if (!Number.isInteger(LIMIT) || LIMIT < 1 || LIMIT > BATCH_MAX) { console.error(`--limit must be 1..${BATCH_MAX}`); process.exit(1); }
if (RUN && !FORCE_HOURS && !inNightWindow()) { console.error('refusing: the fill runs only 23:00-06:00 Asia/Dubai'); process.exit(1); }

const sleep = (ms) => new Promise(r => setTimeout(r, ms));
async function diskFree() {   // unknown = null, which the guard reads as stop
  try {
    const tok = (process.env.SUPABASE_ACCESS_TOKEN || readFileSync(join(homedir(), '.supabase', 'access-token'), 'utf8')).trim();
    const res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/config/disk/util`, { headers: { Authorization: `Bearer ${tok}` } });
    return res.ok ? Number((await res.json())?.metrics?.fs_avail_bytes) || null : null;
  } catch { return null; }
}
// a 429 is refused before execution, so it is retried; anything else is not (db.mjs retry:false)
async function q(text) {
  for (let a = 0; ; a++) {
    try { return await sql(text, { retry: false }); }
    catch (e) { if (String(e.message).includes('HTTP 429') && a < 8) { await sleep(2000 * 2 ** Math.min(a, 5)); continue; } throw e; }
  }
}

// Before that file is applied the recorder does not exist; the verdict is then printed, not recorded.
async function reconcile(timeout) {
  const has = (await q(`select to_regprocedure('public.fn_knowledge_library_record_reconcile()') is not null ok`))[0].ok;
  const fn = has ? 'fn_knowledge_library_record_reconcile' : 'fn_knowledge_library_reconcile';
  const r = (await q(`set statement_timeout = '${timeout}'; select public.${fn}() r`))[0].r;
  if (!has) console.error('(verdict NOT recorded: fn_knowledge_library_record_reconcile is not applied yet)');
  return r;
}

if (!RUN) {
  const r = [{ r: await reconcile('110s') }];
  console.log(JSON.stringify(r[0].r, null, 2));
  console.log('Plan only. Re-run with --run (23:00-06:00 Dubai).');
  process.exit(0);
}
for (const store of STORES) {
  for (;;) {
    const load = (await q(`select public.fn_kb_purge_load() l`))[0]?.l;
    const v = loadVerdict(load, await diskFree(), { forceHours: FORCE_HOURS });
    if (v.action === 'stop') { console.error(`stopping: ${v.reason}. Re-run to carry on.`); process.exit(1); }
    if (v.action === 'wait') { console.log(`waiting 60 s: ${v.reason}`); await sleep(60000); continue; }
    const t = Date.now();
    const r = (await q(`set statement_timeout = '60s'; select public.fn_knowledge_library_fill_page('${store}', ${LIMIT}) r`))[0].r;
    console.log(`${store}: page ${r.page}, new rows ${r.inserted}, rows that gained a merged origin ${r.rows_merged_into}, left ${r.left} (${((Date.now() - t) / 1000).toFixed(1)} s)`);
    if (!r.page || !r.left) break;
    await sleep(PAUSE_MS);
  }
}
const rec = await reconcile('110s');
console.log(JSON.stringify(rec, null, 2));
if (!rec.reconciled) { console.error('NOT RECONCILED: a store holds rows or citations the library does not map'); process.exit(2); }
console.log('reconciled: every row and citation of the nine stores is in the library; recorded, so the seats now read it');
