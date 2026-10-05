// THE kb_chunks COPY-AND-SWAP (5 Oct 2026, it_engineer; ledger 1094, the founder's go). Gives kb_chunks's ~7.3 GB of
// dead space back to the disk WITHOUT VACUUM FULL: that needs ~3 min of ACCESS EXCLUSIVE and both the management API
// and the SQL editor cancel a statement at ~2 min (the founder's attempt, 5 Oct: timed out, no change).
// Instead: build kb_chunks_new from the live rows in pages, index it, catch up the writes, swap the names in one short
// transaction. Every statement is its own management-API call, budgeted well under 2 min. Runbook:
// docs/runbooks/kb_chunks_rewrite.md. Write log: scripts/sql/kb_chunks_records_every_write_while_its_copy_is_built.sql.
//
//   node scripts/kb/kb_chunks_copy_swap.mjs                  # plan: preconditions + inventory + progress, no writes
//   node scripts/kb/kb_chunks_copy_swap.mjs --stage=prepare  # kb_chunks_new (no indexes but pkey), RLS, policies,
//                                                            #   grants, and the write-log trigger on kb_chunks
//   node scripts/kb/kb_chunks_copy_swap.mjs --stage=copy     # live rows in pages of <= 5,000 by id range
//   node scripts/kb/kb_chunks_copy_swap.mjs --stage=index    # every index of kb_chunks, rebuilt on the copy; analyze
//   node scripts/kb/kb_chunks_copy_swap.mjs --stage=catchup  # replay the logged writes, then compare row by row
//   node scripts/kb/kb_chunks_copy_swap.mjs --stage=swap     # baseline, ONE transaction (lock_timeout 5s), read-back
//   node scripts/kb/kb_chunks_copy_swap.mjs --stage=verify   # read-back only (re-runnable after the swap)
//   node scripts/kb/kb_chunks_copy_swap.mjs --stage=all      # prepare..swap in order
//
// Every stage is resumable and safe to stop: prepare is idempotent, copy skips pages already equal, index uses
// "if not exists", catchup consumes the log by sequence, swap refuses unless catchup's comparison is clean. Before the
// swap, stopping leaves kb_chunks untouched (drop kb_chunks_new + the trigger to abandon: runbook "Abandon").
// kb_chunks_old is NOT dropped here: that is runbook step 8, a day after a passing read-back.
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { dubaiMinutes, loadVerdict } from './purge_guard.mjs';
import { inCampaignHours } from '../it/release_train.mjs';

const REF = 'htdblwldjkcgjvmqkbeh';
export const PAGE = 5000;                 // the brief's ceiling per copy statement
export const SUFFIX = '_cs';              // copy-side index names until the swap renames them
// --rehearse=zz_<name>: every stage against a scratch table in schema zz_rehearsal, which carries its own copy of the
// write log + trigger function (no preconditions, no retrieval/export/ledger; public is never touched).
const REH = (process.argv.find((a) => a.startsWith('--rehearse=')) || '').slice(11);
if (REH && !/^zz_[a-z0-9_]{1,30}$/.test(REH)) throw new Error('--rehearse takes a zz_ table name');
export const T = REH || 'kb_chunks';
export const S = REH ? 'zz_rehearsal' : 'public';

// 02:00-05:00 Asia/Dubai, never 02:50-03:10 (the daily export opens at 03:00).
export function inRunWindow(now = new Date()) {
  const m = dubaiMinutes(now);
  return m >= 120 && m < 300 && !(m >= 170 && m < 190);
}
// An index definition of the table, rewritten for the copy: name + SUFFIX, on <table>_new, "if not exists".
export function indexForCopy(def, t = T, s = S) {
  const m = new RegExp(`^CREATE (UNIQUE )?INDEX (\\S+) ON ${s}\\.${t} USING (.+)$`).exec(def);
  if (!m) throw new Error(`unexpected index definition: ${def}`);
  return `CREATE ${m[1] || ''}INDEX IF NOT EXISTS ${m[2]}${SUFFIX} ON ${s}.${t}_new USING ${m[3]}`;
}

const token = () => process.env.SUPABASE_ACCESS_TOKEN?.trim()
  || (existsSync(join(homedir(), '.supabase', 'access-token')) && readFileSync(join(homedir(), '.supabase', 'access-token'), 'utf8').trim())
  || (() => { throw new Error('no Supabase access token'); })();
// A write is never retried on a 5xx: a 524 can commit behind the error (21 Sep).
async function sql(query, { retry5xx = false, attempt = 0 } = {}) {
  const res = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST', headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }), signal: AbortSignal.timeout(150000),
  });
  const text = await res.text();
  if ((res.status === 429 || (retry5xx && res.status >= 500)) && attempt < 5) {
    await new Promise((r) => setTimeout(r, 2000 * 2 ** attempt));
    return sql(query, { retry5xx, attempt: attempt + 1 });
  }
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${text.slice(0, 400)}`);
  return text ? JSON.parse(text) : [];
}
const read = async (q) => (await sql(q, { retry5xx: true }))[0];
const write = (q, timeout = '60s') => sql(`set statement_timeout = '${timeout}'; set lock_timeout = '5s'; ${q}`);
const fail = (why) => { console.error(`STOP: ${why}`); process.exit(1); };
const log = (...a) => console.log(...a);

async function diskFree() {
  try {
    const res = await fetch(`https://api.supabase.com/v1/projects/${REF}/config/disk/util`, { headers: { Authorization: `Bearer ${token()}` } });
    return res.ok ? Number((await res.json())?.metrics?.fs_avail_bytes) || null : null;
  } catch { return null; }
}
const exists = async (rel) => (await read(`select to_regclass('${rel}') is not null x`)).x;
const COLS = `(select string_agg(quote_ident(attname), ',' order by attnum) from pg_attribute
  where attrelid = '${S}.${T}'::regclass and attnum > 0 and not attisdropped and attgenerated = '')`;
let cols;
const columns = async () => (cols ??= (await read(`select ${COLS} c`)).c);

// ---------------------------------------------------------------- preconditions (every mutating stage)
async function preconditions({ mutate }) {
  log('== preconditions');
  if (REH) { log(`   rehearsal on ${S}.${T}: preconditions skipped`); return; }
  const trim = await read(`select
      (select count(*)::int from public.kb_purge_ledger where verdict = 'SIZE' and category = 'live rows after the trim') done,
      (select count(*)::int from public.kb_trim_hash h join public.kb_chunks k on k.id = h.id where h.clause is not null) planned_left`);
  log(`   trim finished: ${trim.done ? 'yes' : 'NO'}; planned rows still present: ${trim.planned_left}`);
  const exp = await read(`select r.stamp::text stamp, r.finished_at,
      (select count(*)::int from public.doc_backups b where b.dropbox_path like '%/' || r.stamp::text || '/kb_chunks/%') pages,
      (select count(*)::int from public.doc_backups b where b.dropbox_path like '%/' || r.stamp::text || '/kb_chunks/%'
          and b.status = 'done' and b.verified_at is not null) verified,
      (select max(created_at) from public.kb_chunks) newest
    from public.table_export_run r where r.kind = 'full' and r.status = 'done' order by r.stamp desc limit 1`);
  const copyOk = exp && exp.pages && exp.verified === exp.pages && new Date(exp.newest) <= new Date(exp.finished_at);
  log(`   restorable copy: ${exp ? `full export ${exp.stamp}, ${exp.verified}/${exp.pages} kb_chunks pages verified, finished ${exp.finished_at}, newest row ${exp.newest}` : 'NONE'}`);
  const disk = await diskFree();
  log(`   disk free: ${disk ? (disk / 1024 ** 3).toFixed(1) + ' GB' : 'unknown'}`);
  if (!mutate) return;
  if (!trim.done || trim.planned_left) fail('the night trim has not finished with 0 planned rows left');
  if (!copyOk) fail(`no verified full export newer than the newest kb_chunks row`);
  if (!inRunWindow()) fail('outside 02:00-05:00 Asia/Dubai (or inside 02:50-03:10)');
  if (inCampaignHours()) fail('campaign hours');
  // The copy is ~live data + indexes; demand 3 GB free (the purge guard's floor) — never below it.
  const v = loadVerdict(await read('select public.fn_kb_purge_load() l').then((x) => x.l), disk, { forceHours: true });
  if (v.action !== 'go') fail(`load guard: ${v.reason}`);
  const busy = await read(`select count(*)::int n from pg_stat_activity where state <> 'idle' and pid <> pg_backend_pid()
     and (query ilike '%vacuum%' or query ilike '%reindex%') and query not ilike '%autovacuum%'`);
  if (busy.n) fail(`${busy.n} vacuum/reindex statements running`);
  let runs = [];
  try {
    runs = JSON.parse(execFileSync('gh', ['run', 'list', '--status', 'in_progress', '--limit', '50', '--json', 'name,workflowName'],
      { encoding: 'utf8' }));
  } catch (e) { fail(`cannot read GitHub runs (${e.message.slice(0, 80)}): refusing blind`); }
  const clash = runs.filter((r) => /smoke|e2e|release|apply|journey/i.test(`${r.name} ${r.workflowName}`));
  if (clash.length) fail(`in progress on GitHub: ${clash.map((r) => r.workflowName || r.name).join(', ')}`);
}

// ---------------------------------------------------------------- stages
async function prepare() {
  log('== prepare');
  if (!(await read(`select to_regprocedure('${S}.fn_kb_chunks_swap_log()') is not null x`)).x) {
    fail(`${S}.fn_kb_chunks_swap_log() is not applied (scripts/sql/kb_chunks_records_every_write_while_its_copy_is_built.sql)`);
  }
  if (!(await exists(`${S}.${T}_new`))) {
    await write(`create table ${S}.${T}_new (like ${S}.${T} including defaults including generated
        including identity including constraints including storage including compression including comments);
      alter table ${S}.${T}_new add constraint ${T}_new_pkey primary key (id);`);
    log(`   created ${T}_new (+ pkey)`);
  }
  // RLS, policies and grants: copied from kb_chunks, the new table's default grants revoked first.
  await write(`do $p$ declare r record; begin
    execute 'alter table ${S}.${T}_new enable row level security';
    if (select relforcerowsecurity from pg_class where oid = '${S}.${T}'::regclass) then
      execute 'alter table ${S}.${T}_new force row level security'; end if;
    for r in select * from pg_policies where schemaname = '${S}' and tablename = '${T}'
             and policyname not in (select policyname from pg_policies where schemaname = '${S}' and tablename = '${T}_new') loop
      execute format('create policy %I on ${S}.${T}_new as %s for %s to %s %s %s', r.policyname, r.permissive, r.cmd,
        array_to_string(array(select quote_ident(x) from unnest(r.roles) x), ','),
        case when r.qual is not null then 'using (' || r.qual || ')' else '' end,
        case when r.with_check is not null then 'with check (' || r.with_check || ')' else '' end);
    end loop;
    execute 'revoke all on ${S}.${T}_new from public, anon, authenticated, service_role';
    for r in select a.grantee::regrole::text g, a.privilege_type p from pg_class c, aclexplode(c.relacl) a
             where c.oid = '${S}.${T}'::regclass and a.grantee <> c.relowner and a.grantee <> 0 loop
      execute format('grant %s on ${S}.${T}_new to %I', r.p, r.g);
    end loop;
  end $p$;`);
  // The write log: created last, so every write from here on is logged (CREATE TRIGGER waits for in-flight writers).
  await write(`do $t$ begin
    if not exists (select 1 from pg_trigger where tgrelid = '${S}.${T}'::regclass and tgname = 'zz_kb_chunks_swap_log') then
      create trigger zz_kb_chunks_swap_log after insert or update or delete on ${S}.${T}
        for each row execute function ${S}.fn_kb_chunks_swap_log();
    end if; end $t$;`);
  log(`   RLS, policies, grants copied; write-log trigger on ${T}`);
}

async function copy() {
  log(`== copy in pages of <= ${PAGE}`);
  const c = await columns();
  let after = 0; let pages = 0; let copied = 0;
  for (;;) {
    // the page's upper id bound from kb_chunks's pkey (index-only), then compare counts so a resumed run skips it
    const b = await read(`select max(id) hi, count(*)::int n from (select id from ${S}.${T} where id > ${after} order by id limit ${PAGE}) s`);
    if (!b.n) break;
    const have = await read(`select count(*)::int n from ${S}.${T}_new where id > ${after} and id <= ${b.hi}`);
    if (have.n !== b.n) {
      const t = Date.now();
      const r = await write(`with i as (insert into ${S}.${T}_new (${c}) overriding system value
          select ${c} from ${S}.${T} where id > ${after} and id <= ${b.hi} on conflict (id) do nothing returning 1)
        select count(*)::int n from i`, '90s');
      copied += r[0].n; pages++;
      log(`   ids ${after + 1}..${b.hi}: ${r[0].n} rows in ${((Date.now() - t) / 1000).toFixed(1)} s`);
    }
    after = Number(b.hi);
  }
  log(`   copy done: ${pages} pages written, ${copied} rows`);
}

async function indexes() {
  log('== index');
  const defs = await sql(`select indexrelid::regclass::text n, pg_get_indexdef(indexrelid) d from pg_index
    where indrelid = '${S}.${T}'::regclass and not indisprimary order by (pg_get_indexdef(indexrelid) ilike '% USING hnsw %')`);
  for (const { n, d } of defs) {
    const t = Date.now();
    // maintenance_work_mem 512 MB holds the ~54 k x 384-dim HNSW graph in memory; 21 Sep's restart was >4 GB.
    await write(`set maintenance_work_mem = '512MB'; set max_parallel_maintenance_workers = 2; ${indexForCopy(d)}`, '115s');
    log(`   ${n}${SUFFIX}: ${((Date.now() - t) / 1000).toFixed(1)} s`);
  }
  await write(`analyze ${S}.${T}_new`, '115s');
  const bad = await read(`select count(*)::int n from pg_index where indrelid = '${S}.${T}_new'::regclass and not indisvalid`);
  const cnt = await read(`select (select count(*)::int from pg_index where indrelid = '${S}.${T}'::regclass) a,
    (select count(*)::int from pg_index where indrelid = '${S}.${T}_new'::regclass) b`);
  if (bad.n || cnt.a !== cnt.b) fail(`copy indexes: ${cnt.b}/${cnt.a}, ${bad.n} invalid`);
  log(`   ${cnt.b} indexes, all valid; analyzed`);
}

const REPLAY = (c) => `do $r$ declare s bigint[]; i bigint[]; begin
    select array_agg(seq), array_agg(distinct id) into s, i from ${S}.kb_chunks_swap_log;
    if i is null then return; end if;
    delete from ${S}.${T}_new where id = any(i);
    insert into ${S}.${T}_new (${c}) overriding system value select ${c} from ${S}.${T} where id = any(i);
    delete from ${S}.kb_chunks_swap_log where seq = any(s);
  end $r$;`;

async function catchup() {
  log('== catch-up');
  const c = await columns();
  const n = await read(`select count(*)::int n from ${S}.kb_chunks_swap_log`);
  await write(REPLAY(c), '90s');
  log(`   replayed ${n.n} logged writes`);
  // Row-by-row comparison in pages, ids written since (still in the log) excluded: they are the swap's to replay.
  let after = 0; let diff = 0;
  for (;;) {
    const b = await read(`select max(id) hi, count(*)::int n from (select id from ${S}.${T} where id > ${after} order by id limit ${PAGE}) s`);
    const hi = b.n ? b.hi : '9223372036854775807';
    const d = await read(`select count(*)::int n from
        (select id, md5(row(${c})::text) h from ${S}.${T} where id > ${after} and id <= ${hi}) o
        full join (select id, md5(row(${c})::text) h from ${S}.${T}_new where id > ${after} and id <= ${hi}) w using (id)
      where o.h is distinct from w.h and id not in (select id from ${S}.kb_chunks_swap_log)`);
    diff += d.n;
    if (!b.n) break;
    after = Number(b.hi);
  }
  if (diff) fail(`${diff} rows differ between ${T} and ${T}_new after the replay`);
  log('   every row equal (outside the writes logged since)');
  const p = await read(`select
    (select relacl::text from pg_class where oid = '${S}.${T}'::regclass) = (select relacl::text from pg_class where oid = '${S}.${T}_new'::regclass) acl,
    (select relrowsecurity from pg_class where oid = '${S}.${T}_new'::regclass) rls,
    (select count(*)::int from pg_policies where tablename = '${T}') = (select count(*)::int from pg_policies where tablename = '${T}_new') pol,
    (select count(*)::int from pg_index where indrelid = '${S}.${T}'::regclass) = (select count(*)::int from pg_index where indrelid = '${S}.${T}_new'::regclass and indisvalid) idx`);
  if (!p.acl || !p.rls || !p.pol || !p.idx) fail(`${T}_new not ready to swap: ${JSON.stringify(p)}`);
}

async function snapshot() {
  // One call of each retriever per seat (the seat's first exam question). The COUNTS must be equal before and after
  // (all items, and the items drawn from kb_chunks). The md5 is reported, not gated: HNSW is approximate and a rebuilt
  // graph may order near-ties differently. Measured 5 Oct: 12 items per seat from each, kb_chunks among the sources.
  const rows = await sql(`select seat, md5(r::text) r_md5, md5(ml::text) ml_md5,
      jsonb_array_length(r) r, jsonb_array_length(ml) ml,
      (select count(*)::int from jsonb_array_elements(r) x where x->>'source' = '${T}') r_kb,
      (select count(*)::int from jsonb_array_elements(ml) x where x->>'source' = '${T}') ml_kb
    from (select q.seat, public.fn_reason_retrieve(q.seat, q.embedding) r,
                 public.fn_reason_retrieve_ml(q.seat, q.embedding, q.embedding_ml) ml
            from (select distinct on (seat) seat, embedding, embedding_ml from public.seat_knowledge_eval_question
                  where embedding is not null order by seat, id) q) s`);
  return Object.fromEntries(rows.map((x) => [x.seat, x]));
}
const sizes = () => read(`select count(*)::int live, pg_total_relation_size('${S}.${T}') total_b,
  pg_database_size(current_database()) db_b,
  (select string_agg(c.oid::regclass::text || ':' || coalesce(array_to_string(c.reloptions, ','), ''), ' ' order by 1)
     from pg_depend d join pg_rewrite rw on rw.oid = d.objid join pg_class c on c.oid = rw.ev_class
    where d.refobjid = '${S}.${T}'::regclass and c.oid <> '${S}.${T}'::regclass) views
  from ${S}.${T}`);

const SWAP = (c) => `do $s$
declare r record; v jsonb := '[]'; s bigint[]; i bigint[]; oseq text; nseq text;
begin
  perform set_config('lock_timeout', '5s', true);
  lock table ${S}.${T}, ${S}.${T}_new in access exclusive mode;
  -- final delta: no writer can run now
  select array_agg(seq), array_agg(distinct id) into s, i from ${S}.kb_chunks_swap_log;
  if i is not null then
    delete from ${S}.${T}_new where id = any(i);
    insert into ${S}.${T}_new (${c}) overriding system value select ${c} from ${S}.${T} where id = any(i);
    delete from ${S}.kb_chunks_swap_log where seq = any(s);
  end if;
  drop trigger zz_kb_chunks_swap_log on ${S}.${T};
  -- views over ${T}: definitions captured while they still read "${T}"
  -- (with their options: CREATE OR REPLACE without WITH would reset security_invoker on v_knowledge_ml_source)
  for r in select distinct c.oid::regclass::text n, pg_get_viewdef(c.oid) d, array_to_string(c.reloptions, ', ') o
           from pg_depend d join pg_rewrite rw on rw.oid = d.objid join pg_class c on c.oid = rw.ev_class
           where d.refobjid = '${S}.${T}'::regclass and c.oid <> '${S}.${T}'::regclass loop
    v := v || jsonb_build_object('n', r.n, 'd', r.d, 'o', r.o);
  end loop;
  -- triggers re-created on the copy, under the same names
  for r in select pg_get_triggerdef(oid) d from pg_trigger where tgrelid = '${S}.${T}'::regclass and not tgisinternal loop
    execute regexp_replace(r.d, ' ON ${S}\\.${T} (REFERENCING|FOR) ', ' ON ${S}.${T}_new \\1 ');
  end loop;
  -- publications (supabase_realtime)
  for r in select pubname from pg_publication_tables where schemaname = '${S}' and tablename = '${T}' loop
    execute format('alter publication %I drop table ${S}.${T}', r.pubname);
    execute format('alter publication %I add table ${S}.${T}_new', r.pubname);
  end loop;
  -- identity sequence: the copy continues where ${T} stopped
  oseq := pg_get_serial_sequence('${S}.${T}', 'id');
  nseq := pg_get_serial_sequence('${S}.${T}_new', 'id');
  execute format('select setval(%L, greatest((select last_value from %s), (select coalesce(max(id), 1) from ${S}.${T}_new)))', nseq, oseq);
  -- names: old aside, copy in
  for r in select c.relname from pg_index x join pg_class c on c.oid = x.indexrelid
           where x.indrelid = '${S}.${T}'::regclass and not x.indisprimary loop
    execute format('alter index ${S}.%I rename to %I', r.relname, left(r.relname, 59) || '_old');
  end loop;
  alter table ${S}.${T} rename constraint ${T}_pkey to ${T}_old_pkey;
  execute format('alter sequence %s rename to ${T}_old_id_seq', oseq);
  alter table ${S}.${T} rename to ${T}_old;
  alter table ${S}.${T}_new rename to ${T};
  alter table ${S}.${T} rename constraint ${T}_new_pkey to ${T}_pkey;
  execute format('alter sequence %s rename to ${T}_id_seq', nseq);
  for r in select c.relname from pg_index x join pg_class c on c.oid = x.indexrelid
           where x.indrelid = '${S}.${T}'::regclass and right(c.relname, ${SUFFIX.length}) = '${SUFFIX}' loop
    execute format('alter index ${S}.%I rename to %I', r.relname, left(r.relname, length(r.relname) - ${SUFFIX.length}));
  end loop;
  -- views re-bound to the new ${T} (CREATE OR REPLACE keeps their grants; options re-applied above)
  for r in select x->>'n' n, x->>'d' d, x->>'o' o from jsonb_array_elements(v) x loop
    execute format('create or replace view %s %s as %s', r.n, case when r.o is null then '' else 'with (' || r.o || ')' end, r.d);
  end loop;
end $s$;`;

async function swap() {
  log('== swap');
  if (!(await exists(`${S}.${T}_new`))) fail(`${T}_new does not exist (already swapped? run --stage=verify)`);
  const c = await columns();
  await catchup();                       // refuses unless every row is equal
  const before = await sizes();
  const base = REH ? null : await snapshot();
  log('   before:', JSON.stringify(before));
  const t = Date.now();
  await write(SWAP(c), '60s');
  const lockS = ((Date.now() - t) / 1000).toFixed(1);
  log(`   swapped: one transaction, ${lockS} s wall (lock + delta + renames, round trip included)`);
  await verify({ before, base, lockS });
}

async function verify({ before, base, lockS } = {}) {
  log('== read-back');
  if (!(await exists(`${S}.${T}_old`))) fail(`${T}_old does not exist: nothing was swapped`);
  const problems = [];
  const n = await read(`select (select count(*)::int from ${S}.${T}) a, (select count(*)::int from ${S}.${T}_old) b`);
  // Gated right after the swap only: kb_chunks_old takes no writes after it, so a later re-run may differ legitimately.
  if (before && n.a !== n.b) problems.push(`row count ${n.a} vs ${T}_old ${n.b}`);
  if (!before) log(`   rows: ${n.a} (kb_chunks_old ${n.b}; writes since the swap land only in ${T})`);
  const ix = await read(`select (select count(*)::int from pg_index where indrelid = '${S}.${T}'::regclass) a,
    (select count(*)::int from pg_index where indrelid = '${S}.${T}_old'::regclass) b,
    (select count(*)::int from pg_index where indrelid = '${S}.${T}'::regclass and not (indisvalid and indisready)) bad`);
  if (ix.a !== ix.b || ix.bad) problems.push(`indexes ${ix.a}/${ix.b}, ${ix.bad} invalid`);
  const par = await read(`select
    (select relacl::text from pg_class where oid = '${S}.${T}'::regclass) = (select relacl::text from pg_class where oid = '${S}.${T}_old'::regclass) acl,
    (select relrowsecurity from pg_class where oid = '${S}.${T}'::regclass) rls,
    (select count(*)::int from pg_policies where tablename = '${T}') pol, (select count(*)::int from pg_policies where tablename = '${T}_old') pol_old,
    (select count(*)::int from pg_trigger where tgrelid = '${S}.${T}'::regclass and not tgisinternal) trg,
    (select count(*)::int from pg_trigger where tgrelid = '${S}.${T}_old'::regclass and not tgisinternal) trg_old,
    (select count(*)::int from pg_publication_tables where tablename = '${T}') pub,
    (select count(*)::int from pg_publication_tables where tablename = '${T}_old') pub_old,
    (select count(*)::int from pg_depend d join pg_rewrite rw on rw.oid = d.objid where d.refobjid = '${S}.${T}_old'::regclass and rw.ev_class <> '${S}.${T}_old'::regclass) views_on_old,
    pg_get_serial_sequence('${S}.${T}', 'id') seq,
    (select last_value from ${S}.${T}_id_seq) >= (select max(id) from ${S}.${T}) seq_ok`);
  if (!par.acl) problems.push(`grants differ from ${T}_old`);
  if (!par.rls || par.pol !== par.pol_old) problems.push(`RLS ${par.rls}, policies ${par.pol}/${par.pol_old}`);
  if (par.trg !== par.trg_old) problems.push(`triggers ${par.trg}/${par.trg_old}`);
  if ((!REH && par.pub < 1) || par.pub_old) problems.push(`publication: ${T} ${par.pub}, ${T}_old ${par.pub_old}`);
  if (par.views_on_old) problems.push(`${par.views_on_old} view rules still read ${T}_old`);
  if (par.seq !== `${S}.${T}_id_seq` || !par.seq_ok) problems.push(`identity sequence ${par.seq}, ahead of max(id): ${par.seq_ok}`);
  const exp = REH ? { t: 'object' } : await read(`select jsonb_typeof(public.fn_table_export_page('kb_chunks', null, 5)) t`).catch((e) => ({ t: `error ${e.message.slice(0, 120)}` }));
  if (exp.t !== 'object' && exp.t !== 'array') problems.push(`export page: ${exp.t}`);
  if (base) {
    const now = await snapshot();
    for (const [seat, b] of Object.entries(base)) {
      const a = now[seat];
      const k = ['r', 'ml', 'r_kb', 'ml_kb'];
      if (!a || k.some((x) => a[x] !== b[x])) problems.push(`retrieval counts for ${seat}: ${k.map((x) => `${x} ${b[x]}->${a?.[x]}`).join(', ')}`);
      log(`   ${seat}: ${k.map((x) => `${x} ${b[x]}->${a?.[x]}`).join(', ')}; identical results: ${a?.r_md5 === b.r_md5 && a?.ml_md5 === b.ml_md5}`);
    }
  }
  const after = await sizes();
  if (before && after.views !== before.views) problems.push(`dependent views/options changed: ${before.views} -> ${after.views}`);
  log('   after:', JSON.stringify(after), before ? `(was ${(before.total_b / 1024 ** 2).toFixed(0)} MB)` : '');
  if (problems.length) fail(`read-back: ${problems.join('; ')}. ${T}_old is intact; runbook "Rollback after the swap".`);
  if (before && !REH) {
    await write(`insert into public.kb_purge_ledger (verdict, clause, source_kind, category, bytes, note)
      values ('SIZE', 0, 'kb_chunks', 'pg_total_relation_size', ${after.total_b},
        'after the copy-and-swap: was ${before.total_b} B, swap ${lockS} s; ${T}_old kept a day (runbook step 8)')`);
  }
  log(`   read-back passed. ${T}_old stays until a day has passed: runbook step 8.`);
}

async function plan() {
  await preconditions({ mutate: false });
  log('== progress');
  log(`   ${T}_new: ${(await exists(`${S}.${T}_new`)) ? 'exists' : 'not yet'}; ${T}_old: ${(await exists(`${S}.${T}_old`)) ? 'EXISTS (swapped)' : 'no'}`);
  log(`   ${T}:`, JSON.stringify(await sizes()));
  log('Plan only. Stages: prepare, copy, index, catchup, swap (or all), verify.');
}

async function main() {
  const stage = (process.argv.find((a) => a.startsWith('--stage=')) || '').slice(8);
  const steps = { prepare, copy, index: indexes, catchup, swap, verify: () => verify() };
  if (!stage) return plan();
  if (stage === 'verify') return verify();
  if (stage !== 'all' && !steps[stage]) fail(`unknown stage ${stage}`);
  for (const s of stage === 'all' ? ['prepare', 'copy', 'index', 'catchup', 'swap'] : [stage]) {
    await preconditions({ mutate: true });   // before EVERY stage: a long run must not drift into 02:50 or past 05:00
    if (s !== 'prepare' && !(await exists(`${S}.${T}_new`))) fail('run --stage=prepare first');
    await steps[s]();
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] || '').href) await main();
