// THE kb_chunks TRIM DRIVER (5 Oct 2026, it_engineer; ledger 1085 stage 4). Deletes the unverified qd_kb_pack rows
// (clause 6) and the exact duplicates (clause 7: same content, title and category; the verified copy stays), in pages,
// under the 21 Sep purge's load guard (scripts/kb/purge_guard.mjs), only 23:00-06:00 Asia/Dubai.
// SQL: scripts/sql/the_unverified_bulk_and_the_duplicates_leave_kb_chunks_in_pages.sql.
//
//   node scripts/kb/trim_kb_chunks.mjs           # plan only: preflight + what exists so far
//   node scripts/kb/trim_kb_chunks.mjs --run     # hash pages, build the plan, delete batches, read-back, plain VACUUM
//
// Every page (hash or delete) re-reads the load guard first, which also re-checks the night window.
// Never VACUUM FULL / pg_repack: that rewrite is docs/runbooks/kb_chunks_rewrite.md and needs the founder's go.
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { BATCH_DEFAULT, BATCH_MAX, PAUSE_MS, loadVerdict, inNightWindow } from './purge_guard.mjs';

const REF = 'htdblwldjkcgjvmqkbeh';
const RUN = process.argv.includes('--run');
const LIMIT = Number((process.argv.find((a) => a.startsWith('--limit=')) || `--limit=${BATCH_DEFAULT}`).slice(8));
if (!Number.isInteger(LIMIT) || LIMIT < 1 || LIMIT > BATCH_MAX) { console.error(`--limit must be 1..${BATCH_MAX}`); process.exit(1); }
if (RUN && !inNightWindow()) { console.error('refusing: the trim runs only between 23:00 and 06:00 Asia/Dubai'); process.exit(1); }

const token = () => process.env.SUPABASE_ACCESS_TOKEN?.trim()
  || (existsSync(join(homedir(), '.supabase', 'access-token')) && readFileSync(join(homedir(), '.supabase', 'access-token'), 'utf8').trim())
  || (() => { throw new Error('no Supabase access token'); })();
// retry5xx=false for a write: a 524 can commit behind the error (21 Sep), so a write is never retried on a 5xx.
async function sql(query, attempt = 0, retry5xx = true) {
  const res = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST', headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }), signal: AbortSignal.timeout(180000),
  });
  const text = await res.text();
  if ((res.status === 429 || (retry5xx && res.status >= 500)) && attempt < 6) {
    await new Promise((r) => setTimeout(r, Math.min(2000 * 2 ** attempt, 60000)));
    return sql(query, attempt + 1, retry5xx);
  }
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${text.slice(0, 400)}`);
  return text ? JSON.parse(text) : [];
}
const one = async (q, r = true) => (await sql(q, 0, r))[0];
async function diskFree() {
  try {
    const res = await fetch(`https://api.supabase.com/v1/projects/${REF}/config/disk/util`, { headers: { Authorization: `Bearer ${token()}` } });
    return res.ok ? Number((await res.json())?.metrics?.fs_avail_bytes) || null : null;
  } catch { return null; }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const size = () => one(`select count(*)::int live, pg_size_pretty(pg_total_relation_size('public.kb_chunks')) total,
  pg_size_pretty(pg_relation_size('public.kb_chunks')) heap, (select n_dead_tup from pg_stat_user_tables where relname = 'kb_chunks') dead
  from public.kb_chunks`);
// Before every page: stop (exit; a re-run resumes), wait, or go.
async function guard() {
  for (;;) {
    const load = await one('select public.fn_kb_purge_load() l').then((x) => x.l, () => null);
    const v = loadVerdict(load, await diskFree());
    if (v.action === 'stop') { console.error(`stopping: ${v.reason}. Re-run to resume.`); process.exit(1); }
    if (v.action === 'go') return;
    console.log(`   waiting 60 s: ${v.reason}`);
    await sleep(60000);
  }
}

console.log('== preflight');
// The restorable copy is the NEWEST finished full export, resolved here (never a pinned day): every kb_chunks page done
// and verified, and finished after the table's newest row. Restore path: docs/runbooks/kb_chunks_rewrite.md.
const exp = await one(`select r.stamp::text stamp, r.finished_at,
    (select count(*)::int from public.doc_backups b where b.dropbox_path like '%/' || r.stamp::text || '/kb_chunks/%') pages,
    (select count(*)::int from public.doc_backups b where b.dropbox_path like '%/' || r.stamp::text || '/kb_chunks/%'
        and b.status = 'done' and b.verified_at is not null) verified,
    (select max(created_at) from public.kb_chunks) newest
  from public.table_export_run r where r.kind = 'full' and r.status = 'done' order by r.stamp desc limit 1`);
if (!exp) throw new Error('no finished full export: refusing to delete without a restorable copy');
if (!exp.pages || exp.verified !== exp.pages) throw new Error(`full export ${exp.stamp}: ${exp.verified}/${exp.pages} kb_chunks pages done+verified`);
if (!exp.finished_at || new Date(exp.newest) > new Date(exp.finished_at)) {
  throw new Error(`the newest full export (${exp.stamp}, finished ${exp.finished_at}) is older than the newest kb_chunks row (${exp.newest}); take a full export first`);
}
console.log(`   restorable copy: full export ${exp.stamp} (finished ${exp.finished_at}), ${exp.pages} kb_chunks pages verified; newest row ${exp.newest}`);
console.log('   before:', JSON.stringify(await size()));

const st = await one(`select (select count(*)::int from public.kb_purge_ledger where verdict = 'TRIM' and batch_no is null) census,
  (select count(*)::int from public.kb_trim_hash) hashed, (select coalesce(max(id), 0) from public.kb_trim_hash) hash_to,
  (select count(*)::int from public.kb_trim_plan where clause = 6) c6, (select count(*)::int from public.kb_trim_plan where clause = 7) c7`);
console.log(`   census rows ${st.census}; hashed ${st.hashed} (to id ${st.hash_to}); plan left: qd_kb_pack ${st.c6}, duplicates ${st.c7}`);
if (!RUN) { console.log('Plan only. Re-run with --run (23:00-06:00 Dubai).'); process.exit(0); }

if (!st.census) {
  console.log(`== census: hash in pages of ${LIMIT}, resuming after id ${st.hash_to}`);
  for (let after = Number(st.hash_to); ;) {
    await guard();
    const p = await one(`select * from public.fn_kb_trim_hash_page(${after}, ${LIMIT})`, false);
    if (!Number(p.hashed)) break;
    after = Number(p.last_id);
    await sleep(1000);
  }
  await guard();
  console.log('   census:', JSON.stringify((await one('select public.fn_kb_trim_plan_build() c', false)).c));
}

console.log(`== trim in batches of ${LIMIT}`);
for (;;) {
  await guard();
  const r = await one(`set statement_timeout = '30s'; select * from public.fn_kb_trim_batch(${LIMIT})`, false);
  console.log(`   batch ${r.batch_no}: ${r.deleted_count} rows, ids ${r.cursor_from}..${r.cursor_to}, remaining ${r.remaining_count}`);
  if (Number(r.deleted_count) === 0) break;
  await sleep(PAUSE_MS);
}

console.log('== read-back');
// every text that had a copy still has one: each clause-7 row's keeper is present (pkey lookups, no re-hash)
const orphan = await one(`select count(*)::int n from public.kb_trim_hash h where h.clause = 7
   and not exists (select 1 from public.kb_chunks k where k.id = h.keeper_id)`).catch(() => null);
if (!orphan || orphan.n) throw new Error(`duplicate texts with no surviving copy: ${orphan?.n ?? 'unmeasured'}`);
console.log('   every duplicate text keeps its surviving copy');
const left = await one(`select count(*)::int n from public.kb_trim_hash h join public.kb_chunks k on k.id = h.id where h.clause is not null`);
if (left.n) throw new Error(`${left.n} planned rows are still present`);
await sql('vacuum (analyze) public.kb_chunks', 0, false).then(() => console.log('   vacuum (analyze): done'),
  (e) => console.log(`   vacuum (analyze) did not finish under the 2-minute cap (${e.message.slice(0, 120)}); autovacuum will`));
const after = await size();
console.log('   after:', JSON.stringify(after));
await sql(`insert into public.kb_purge_ledger (verdict, clause, source_kind, category, rows, note)
           values ('SIZE', 0, 'kb_chunks', 'live rows after the trim', ${after.live}, 'ledger 1085 trim, before the rewrite; copy ${exp.stamp}')`, 0, false);
console.log('Done. The disk is returned only by the rewrite: docs/runbooks/kb_chunks_rewrite.md.');
