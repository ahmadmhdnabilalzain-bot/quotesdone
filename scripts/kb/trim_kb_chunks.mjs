// THE kb_chunks TRIM DRIVER (5 Oct 2026, it_engineer; ledger 1085 stage 4). Deletes the unverified qd_kb_pack rows
// (clause 6) and the identical-content duplicates (clause 7) planned by public.fn_kb_trim_census(), in pages, under
// the 21 Sep purge's load guard (scripts/kb/purge_guard.mjs), only 23:00-06:00 Asia/Dubai.
// SQL: scripts/sql/the_unverified_bulk_and_the_duplicates_leave_kb_chunks_in_pages.sql.
//
//   node scripts/kb/trim_kb_chunks.mjs           # plan only: preflight + the census counts
//   node scripts/kb/trim_kb_chunks.mjs --run     # census (if none), batches until nothing is left, plain VACUUM, read-back
//
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
// The restorable copy: the 18 Sep full export (docs/KNOWLEDGE_DOCTRINE.md §8); every kb_chunks row is older than it.
const EXPORT_DAY = '2026-09-18';

const token = () => process.env.SUPABASE_ACCESS_TOKEN?.trim()
  || (existsSync(join(homedir(), '.supabase', 'access-token')) && readFileSync(join(homedir(), '.supabase', 'access-token'), 'utf8').trim())
  || (() => { throw new Error('no Supabase access token'); })();
// retry5xx=false for a write: a 524 can commit behind the error (21 Sep), so a batch is never retried on a 5xx.
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

console.log('== preflight');
const run = await one(`select kind, status from public.table_export_run where stamp = '${EXPORT_DAY}'`);
if (run?.kind !== 'full' || run?.status !== 'done') throw new Error(`no finished full export on ${EXPORT_DAY}: ${JSON.stringify(run)}`);
const newest = await one('select max(created_at) newest from public.kb_chunks');
if (new Date(newest.newest) > new Date(`${EXPORT_DAY}T00:00:00Z`)) throw new Error(`a kb_chunks row is newer than the copy (${newest.newest})`);
console.log(`   restorable copy ${EXPORT_DAY}: full, done; newest row ${newest.newest}`);
console.log('   before:', JSON.stringify(await size()));

const census = await one(`select count(*)::int n from public.kb_purge_ledger where verdict = 'TRIM' and batch_no is null`);
const planned = await one(`select count(*) filter (where clause = 6)::int c6, count(*) filter (where clause = 7)::int c7 from public.kb_trim_plan`);
console.log(`   census rows ${census.n}; plan: qd_kb_pack ${planned.c6}, duplicates ${planned.c7}`);
if (!RUN) { console.log('Plan only. Re-run with --run (23:00-06:00 Dubai).'); process.exit(0); }
if (!census.n) console.log('   census:', JSON.stringify((await one('select public.fn_kb_trim_census() c', false)).c));

console.log(`== trim in batches of ${LIMIT}`);
for (;;) {
  const load = await one('select public.fn_kb_purge_load() l').then((x) => x.l, () => null);
  const v = loadVerdict(load, await diskFree());
  if (v.action === 'stop') { console.error(`stopping: ${v.reason}. Re-run to resume.`); process.exit(1); }
  if (v.action === 'wait') { console.log(`   waiting 60 s: ${v.reason}`); await sleep(60000); continue; }
  const r = await one(`set statement_timeout = '30s'; select * from public.fn_kb_trim_batch(${LIMIT})`, false);
  console.log(`   batch ${r.batch_no}: ${r.deleted_count} rows, ids ${r.cursor_from}..${r.cursor_to}, remaining ${r.remaining_count}`);
  if (Number(r.deleted_count) === 0) break;
  await sleep(PAUSE_MS);
}

console.log('== read-back');
// every text that had a copy still has one: no clause-7 id survives, and every planned duplicate's content is present
const orphan = await one(`set statement_timeout = '110s';
  select count(*)::int n from (select distinct p.content_md5 c from public.kb_trim_plan p where p.clause = 7) s
   where not exists (select 1 from public.kb_chunks k where md5(k.content) = s.c)`).catch(() => null);
if (!orphan || orphan.n) throw new Error(`duplicate texts with no surviving copy: ${orphan?.n ?? 'unmeasured'}`);
console.log('   every duplicate text keeps its surviving copy');
const left = await one(`select count(*)::int n from public.kb_trim_plan p join public.kb_chunks k on k.id = p.id`);
if (left.n) throw new Error(`${left.n} planned rows are still present`);
await sql('vacuum (analyze) public.kb_chunks', 0, false).then(() => console.log('   vacuum (analyze): done'),
  (e) => console.log(`   vacuum (analyze) did not finish under the 2-minute cap (${e.message.slice(0, 120)}); autovacuum will`));
const after = await size();
console.log('   after:', JSON.stringify(after));
await sql(`insert into public.kb_purge_ledger (verdict, clause, source_kind, category, rows, note)
           values ('SIZE', 0, 'kb_chunks', 'live rows after the trim', ${after.live}, 'ledger 1085 trim, before the rewrite')`, 0, false);
console.log('Done. The disk is returned only by the rewrite: docs/runbooks/kb_chunks_rewrite.md.');
