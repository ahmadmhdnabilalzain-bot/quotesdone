// THE FOREIGN BULK LEAVES THE KNOWLEDGE LIBRARY PERMANENTLY — the driver.
//
// Seat: it_engineer. Founder instruction 520 (18 Sep 2026). Spec: docs/KNOWLEDGE_DOCTRINE.md §6/§8.
// SQL it drives: scripts/sql/the_foreign_bulk_leaves_the_knowledge_library_permanently.sql
// (fn_kb_purge_clause, kb_purge_ledger, fn_kb_purge_batch) — apply that first.
//
//   node scripts/kb/purge_kb_bulk.mjs            # preflight + census only; prints the plan, deletes nothing
//   node scripts/kb/purge_kb_bulk.mjs --run      # the purge: batches until remaining = 0, then vacuum / reindex / stats
//   node scripts/kb/purge_kb_bulk.mjs --run --limit=50000
//
// Every step prints what it measured. It refuses to start unless the 2026-09-18 full export of
// kb_chunks is complete: 4,177 doc_backups pages, all done + verified (§8). It is resumable — a
// re-run after a failure continues from the ledger's cursor because fn_kb_purge_batch does.
//
// Why the writes go straight to the management API and not through qd_guard.mgmtWrite: that helper
// REFUSES production by design (Batch 0), and this script exists only to write production, once,
// on the coordinator's command. There is no staging project to rehearse on (deleted 15 Aug).
//
// The platform's statement_timeout is 2 min on every session. Multi-statement requests run in one
// transaction, so `set statement_timeout` works for the batch call; VACUUM and REINDEX CONCURRENTLY
// cannot run inside a transaction, so they go as single statements under the 2-minute cap. If one
// times out the script says so and prints the statement for a session without the cap.
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const REF = 'htdblwldjkcgjvmqkbeh';
const RUN = process.argv.includes('--run');
const LIMIT = Number((process.argv.find(a => a.startsWith('--limit=')) || '--limit=50000').slice(8));
const EXPORT_DAY = '2026-09-18';
const EXPORT_PAGES = 4177;            // §8: the full copy of 2026-09-18, 11,929,993,565 bytes
const SIZE_BEFORE_MB = 9313;          // §8, measured 21 Sep 2026 09:18 UTC
const STANDARD_SLICE = 200000;        // id slice for the `standard` census: ~140k rows ≈ 12 s each

function token() {
  if (process.env.SUPABASE_ACCESS_TOKEN) return process.env.SUPABASE_ACCESS_TOKEN.trim();
  const p = join(homedir(), '.supabase', 'access-token');
  if (existsSync(p)) return readFileSync(p, 'utf8').trim();
  throw new Error('No Supabase access token (SUPABASE_ACCESS_TOKEN or ~/.supabase/access-token)');
}
async function sql(query, attempt = 0) {
  const res = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
    signal: AbortSignal.timeout(180000),
  });
  const text = await res.text();
  if ((res.status === 429 || res.status >= 500) && attempt < 6) {
    const wait = Math.min(2000 * 2 ** attempt, 60000);
    console.error(`   ${res.status}; retrying in ${wait / 1000}s`);
    await new Promise(r => setTimeout(r, wait));
    return sql(query, attempt + 1);
  }
  if (!res.ok) { const e = new Error(`HTTP ${res.status}: ${text.slice(0, 400)}`); e.body = text; throw e; }
  return text ? JSON.parse(text) : [];
}
const one = async (q) => (await sql(q))[0];
const isTimeout = (e) => /57014|statement timeout/i.test(String(e.body || e.message));
const step = (s) => console.log(`\n== ${s}`);
const t0 = () => Date.now();
const ms = (t) => `${((Date.now() - t) / 1000).toFixed(1)}s`;

// The clause-2 join, spelled once here and once in the SQL file — the same text.
const CITED = `(select split_part(x, ':', 2)::bigint from public.sales_decision_log s, unnest(s.cited) x where x ~ '^kb_chunks:[0-9]+$')`;
const CLAUSE = `public.fn_kb_purge_clause(k.source_kind, k.category, k.citation)`;
const VERDICT = `case when c = 1 then 'KEEP' when c = 2 then 'KEEP' when c = 3 then 'KEEP' when c = 4 then 'UNSURE' else 'DELETE' end`;

// ── 1. Preflight ─────────────────────────────────────────────────────────────────────────────
step('preflight');
{
  const run = await one(`select kind, status, finished_at from public.table_export_run where stamp = '${EXPORT_DAY}'`);
  if (!run || run.kind !== 'full' || run.status !== 'done') throw new Error(`table_export_run ${EXPORT_DAY} is not a finished full export: ${JSON.stringify(run)}`);
  const pages = await one(`select count(*)::int as pages, count(*) filter (where status = 'done' and verified_at is not null)::int as verified,
                                  coalesce(sum(bytes), 0)::bigint as bytes
                             from public.doc_backups where dropbox_path like '%/${EXPORT_DAY}/kb_chunks/%'`);
  if (pages.pages !== EXPORT_PAGES || pages.verified !== EXPORT_PAGES) {
    throw new Error(`restorable copy incomplete: ${pages.pages} pages, ${pages.verified} done+verified; §8 requires ${EXPORT_PAGES}/${EXPORT_PAGES}`);
  }
  console.log(`   restorable copy: ${EXPORT_DAY} full export done ${run.finished_at}; ${pages.pages} pages, ${pages.verified} verified, ${pages.bytes} bytes`);
  const newest = await one(`select max(created_at) as newest from public.kb_chunks`);
  if (new Date(newest.newest) > new Date(`${EXPORT_DAY}T00:00:00Z`)) throw new Error(`kb_chunks has a row newer than the copy (${newest.newest}); take a full export first`);
  console.log(`   newest kb_chunks row: ${newest.newest} (older than the copy)`);
  const objs = await one(`select (select count(*) from pg_proc where proname = 'fn_kb_purge_batch')::int as batch_fn,
                                 (select count(*) from pg_proc where proname = 'fn_kb_purge_clause')::int as clause_fn,
                                 to_regclass('public.kb_purge_ledger') is not null as ledger`);
  if (!objs.batch_fn || !objs.clause_fn || !objs.ledger) throw new Error(`apply scripts/sql/the_foreign_bulk_leaves_the_knowledge_library_permanently.sql first: ${JSON.stringify(objs)}`);
  const size = await one(`select pg_total_relation_size('public.kb_chunks')::bigint as b, pg_size_pretty(pg_total_relation_size('public.kb_chunks')) as p`);
  console.log(`   kb_chunks total size now: ${size.p} (§8: ${SIZE_BEFORE_MB} MB)`);
}

// ── 2. Census — the audit rows §6 demands before any delete ──────────────────────────────────
step('census (verdict per source_kind × category, written to kb_purge_ledger before the first delete)');
{
  const have = await one(`select count(*)::int as n from public.kb_purge_ledger where batch_no is null and verdict <> 'SIZE'`);
  if (have.n > 0) {
    console.log(`   census already in the ledger (${have.n} rows) — not rewritten; delete batches resume from it`);
  } else {
    const before = await one(`select pg_total_relation_size('public.kb_chunks')::bigint as b`);
    await sql(`insert into public.kb_purge_ledger (verdict, clause, source_kind, category, bytes, note)
               values ('SIZE', 0, 'kb_chunks', 'pg_total_relation_size', ${before.b}, 'before the purge')`);
    // Non-`standard` kinds fit one request (≈21 s measured); `standard` (2.06 M rows) goes by id slice.
    const censusSql = (where) => `
      set statement_timeout = '10min';
      insert into public.kb_purge_ledger (verdict, clause, source_kind, category, rows, note)
      select ${VERDICT}, c, source_kind, category, count(*), 'census'
        from (select k.source_kind, k.category,
                     case when ${CLAUSE} = 1 then 1
                          when k.id in ${CITED} then 2
                          else ${CLAUSE} end as c
                from public.kb_chunks k where ${where}) x
       group by 1, 2, 3, 4`;
    try {
      let t = t0();
      await sql(censusSql(`k.source_kind <> 'standard'`));
      console.log(`   non-standard kinds classified in ${ms(t)}`);
      const range = await one(`select min(id)::bigint as lo, max(id)::bigint as hi from public.kb_chunks`);
      for (let lo = Number(range.lo); lo <= Number(range.hi); lo += STANDARD_SLICE) {
        t = t0();
        await sql(censusSql(`k.source_kind = 'standard' and k.id >= ${lo} and k.id < ${lo + STANDARD_SLICE}`));
        console.log(`   standard ids ${lo}..${lo + STANDARD_SLICE - 1} classified in ${ms(t)}`);
      }
    } catch (e) {
      // A half-written census would make fn_kb_purge_batch plan against a short count, so it goes.
      await sql(`delete from public.kb_purge_ledger where batch_no is null and verdict <> 'SIZE'`);
      await sql(`delete from public.kb_purge_ledger where verdict = 'SIZE' and note = 'before the purge'`);
      console.error(`   census failed and was removed from the ledger; re-run to start it again: ${e.message}`);
      process.exit(1);
    }
  }
  const plan = await sql(`select verdict, clause, sum(rows)::bigint as rows,
                                 string_agg(source_kind || ' ' || kind_rows, ', ' order by kind_rows desc) as by_kind
                            from (select verdict, clause, source_kind, sum(rows) as kind_rows
                                    from public.kb_purge_ledger where batch_no is null and verdict <> 'SIZE'
                                   group by 1, 2, 3) k
                           group by 1, 2 order by 2`);
  for (const r of plan) console.log(`   ${r.verdict.padEnd(6)} clause ${r.clause}: ${r.rows} rows — ${r.by_kind}`);
  const del = plan.find(r => r.verdict === 'DELETE');
  console.log(`   §8 preview said DELETE 2,437,975; this census says ${del ? del.rows : 0} (this rule holds every foreign-code citation as UNSURE regardless of category, so fewer is expected, never more)`);
  // Founder instruction 535 (21 Sep) moved US codes/laws from UNSURE to DELETE, so the ceiling is
  // §8's DELETE (2,437,975) plus §8's whole UNSURE set (45,169) = 2,483,144. Above that, the rule is wrong.
  if (del && Number(del.rows) > 2483144) throw new Error('the census would delete MORE than §8 DELETE + UNSURE — stop and compare the rule');
}

if (!RUN) { console.log('\nPlan only. Re-run with --run to delete.'); process.exit(0); }

// ── 3. The batches ────────────────────────────────────────────────────────────────────────────
step(`purge in batches of ${LIMIT}`);
{
  const done = await one(`select coalesce(max(batch_no), 0)::int as n, coalesce(sum(rows), 0)::bigint as rows from public.kb_purge_ledger where batch_no is not null`);
  if (done.n > 0) console.log(`   resuming after batch ${done.n} (${done.rows} rows already deleted)`);
  for (;;) {
    const t = t0();
    let r;
    try {
      r = await one(`set statement_timeout = '10min'; select * from public.fn_kb_purge_batch(${LIMIT})`);
    } catch (e) {
      console.error(`   batch failed (${ms(t)}): ${e.message}\n   nothing from this batch was kept; re-run to resume from the ledger`);
      process.exit(1);
    }
    console.log(`   batch ${r.batch_no}: deleted ${r.deleted_count} rows (${(Number(r.deleted_bytes) / 1048576).toFixed(0)} MB content), ids ${r.cursor_from}..${r.cursor_to}, remaining ${r.remaining_count}, ${ms(t)}`);
    if (Number(r.deleted_count) === 0) break;
  }
  const left = await one(`set statement_timeout = '10min';
    select count(*)::bigint as n from public.kb_chunks k
     where ${CLAUSE} = 5 and k.id not in ${CITED}`);
  console.log(`   clause-5 rows left after the last batch: ${left.n}`);
  if (Number(left.n) !== 0) throw new Error(`purge ended with ${left.n} clause-5 rows still present`);
}

// ── 4. Reclaim ────────────────────────────────────────────────────────────────────────────────
step('vacuum / reindex / stats');
{
  const single = async (label, stmt) => {
    const t = t0();
    try { await sql(stmt); console.log(`   ${label}: done in ${ms(t)}`); return true; }
    catch (e) {
      if (isTimeout(e)) console.log(`   ${label}: hit the platform 2-minute statement_timeout after ${ms(t)} — run it from a session without the cap:\n      set statement_timeout = 0; ${stmt};`);
      else console.log(`   ${label}: failed — ${e.message}`);
      return false;
    }
  };
  // VACUUM VERBOSE's report is a notice, which the API discards; ANALYZE is what the planner needs.
  await single('vacuum (verbose, analyze) kb_chunks', `vacuum (verbose, analyze) public.kb_chunks`);
  for (const ix of ['kb_chunks_fts', 'kb_chunks_emb_hnsw', 'kb_chunks_category_norm_idx']) {
    const ok = await single(`reindex index concurrently ${ix}`, `reindex index concurrently public.${ix}`);
    if (!ok) {
      const bad = await sql(`select indexrelid::regclass::text as name from pg_index where not indisvalid and indrelid = 'public.kb_chunks'::regclass`);
      if (bad.length) console.log(`   invalid index left behind: ${bad.map(b => b.name).join(', ')} — drop it before retrying (drop index concurrently <name>)`);
    }
  }
  // kb_category_stats: its refresh routine was dropped 7 Sep 2026; refresh it here the way it was defined.
  await sql(`delete from public.kb_category_stats;
             insert into public.kb_category_stats (category, source_kind, chunks, refreshed_at)
             select coalesce(category, ''), source_kind, count(*), now() from public.kb_chunks group by 1, 2`);
  const stats = await one(`select count(*)::int as rows, sum(chunks)::bigint as chunks from public.kb_category_stats`);
  console.log(`   kb_category_stats refreshed: ${stats.rows} rows, ${stats.chunks} chunks`);
  const after = await one(`select pg_total_relation_size('public.kb_chunks')::bigint as b, pg_size_pretty(pg_total_relation_size('public.kb_chunks')) as p,
                                  pg_size_pretty(pg_relation_size('public.kb_chunks')) as heap, pg_size_pretty(pg_indexes_size('public.kb_chunks')) as idx,
                                  (select n_dead_tup from pg_stat_user_tables where relname = 'kb_chunks') as dead,
                                  (select count(*) from public.kb_chunks) as live`);
  await sql(`insert into public.kb_purge_ledger (verdict, clause, source_kind, category, bytes, note)
             values ('SIZE', 0, 'kb_chunks', 'pg_total_relation_size', ${after.b}, 'after the purge, vacuum and reindex')`);
  const reclaimed = SIZE_BEFORE_MB - Math.round(Number(after.b) / 1048576);
  console.log(`   kb_chunks now: ${after.p} total (heap ${after.heap}, indexes ${after.idx}), ${after.live} live rows, ${after.dead} dead tuples`);
  console.log(`   reclaimed vs §8's ${SIZE_BEFORE_MB} MB: ${reclaimed} MB. A plain VACUUM returns space to the table, not to the disk — the heap and TOAST files only shrink with VACUUM FULL, which needs a session without the 2-minute cap and an exclusive lock.`);
}
console.log('\nDone. Run node scripts/checks/the_knowledge_library_holds_no_foreign_bulk.mjs to prove it.');
