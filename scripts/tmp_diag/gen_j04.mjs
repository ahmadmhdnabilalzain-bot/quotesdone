import { writeFileSync } from 'node:fs';
import { sql } from '../phase_b/lib/db.mjs';

const src = async (n) => (await sql(
  `select prosrc from pg_proc p join pg_namespace x on x.oid=p.pronamespace
    where x.nspname='public' and p.proname='${n}'`))[0].prosrc;

const one = (s, o) => { const c = s.split(o).length - 1; if (c !== 1) throw new Error(`anchor ${c}: ${o.slice(0, 70)}`); };

// ---- 1. the writer ---------------------------------------------------------------------------
let w = await src('fn_phase_d_object_write');
const WA = `      select count(*), string_agg(distinct q.method || ' ' || q.url, ', ')
        into v_net_new, v_net_urls
        from net.http_request_queue q
       where q.id > v_net_max;`;
one(w, WA);
w = w.replace(WA, `      -- WHOSE REQUEST IS IT. This counted every row above an id watermark, so a request enqueued
      -- by ANY concurrent transaction was attributed to this write. Measured 23 Aug 2026: the
      -- step-coverage drive failed with "writing inquiry to public.inquiries enqueued 2 outbound
      -- HTTP request(s): POST .../dropbox_backup, POST .../uptime_check" -- and neither came from
      -- the write. cron.job 88 (dropbox_backup_scan) and 35 (uptime_check_15min) both run
      -- */15 * * * *, they commit while a Phase D transaction is open, and READ COMMITTED then
      -- shows their rows to the next statement here. A drive that fails four times an hour, on the
      -- quarter hour, because a scheduled job ran is an instrument reporting on the wrong subject.
      -- The requests are attributed to this transaction now; see the helper for how.
      select r.n, r.urls into v_net_new, v_net_urls
        from public.fn_phase_d_outbound_requests_by_this_transaction(v_net_max) r;`);

// ---- 2. the scenario's reported figure --------------------------------------------------------
let f = await src('fn_phase_d_fixture_scenario');
const FA = `      (select count(*) from net.http_request_queue where id > v_net_start),`;
one(f, FA);
f = f.replace(FA, `      (select r.n from public.fn_phase_d_outbound_requests_by_this_transaction(v_net_start) r),`);

// ---- 3. the board that reads the writer's own text --------------------------------------------
let b = await src('fn_phase_d_outbound_state');
const BA = `           and p.prosrc like '%net.http_request_queue%'),`;
const BB = `                            and p.prosrc like '%net.http_request_queue%')`;
one(b, BA); one(b, BB);
b = b.replace(BA, `           and p.prosrc like '%fn_phase_d_outbound_requests_by_this_transaction%'),`)
     .replace(BB, `                            and p.prosrc like '%fn_phase_d_outbound_requests_by_this_transaction%')`);

const header = `-- J04 — the outbound-request guard counted a scheduled job's requests as the write's own
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh. The 257-step coverage drive came back:
--
--   fn_phase_d_object_write: writing inquiry to public.inquiries enqueued 2 outbound HTTP
--   request(s): POST https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/dropbox_backup,
--   POST https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/uptime_check
--   (pd_object_outbound_request_produced)
--
-- Neither request came from the write. cron.job 88 dropbox_backup_scan and cron.job 35
-- uptime_check_15min are both \`*/15 * * * *\` and both active; they enqueue into
-- net.http_request_queue, they commit while a Phase D transaction is open, and READ COMMITTED shows
-- their rows to this function's next statement. The guard counted \`where q.id > v_net_max\` -- every
-- row above a watermark, by whoever -- so four times an hour a Phase D drive was refused for
-- something a scheduled job did.
--
-- The guard itself is right and stays: a Phase D test write may not leave an outbound request
-- behind it. What was wrong is the population. Requests are now attributed to THIS transaction:
-- a visible queue row whose xmin is still in progress can only have been written by us, because a
-- row from any other in-flight transaction is not visible at all and a row from a committed one
-- reports 'committed'. pg_xact_status settles it exactly, including for the subtransaction xids a
-- plpgsql exception block allocates -- verified on this database, where a row inserted inside
-- \`begin ... exception ... end\` carried xmin 3453125 against a top-level 3453124 and still reported
-- 'in progress'.
--
-- fn_phase_d_fixture_scenario reported the same population under the name
-- outbound_http_requests_written_by_this_scenario, and had the same defect for the same reason.
--
-- THE BOARD IS UPDATED, NOT WEAKENED. fn_phase_d_outbound_state's check
-- the_canonical_writer_still_counts_the_outbound_queue asserted the writer's own text contains
-- 'net.http_request_queue'. The writer now reaches the queue through the attribution helper, so the
-- check reads the helper's name instead. The other half of the check --
-- pd_object_outbound_request_produced -- is untouched, and the assertion is the same one: the
-- canonical writer still counts.
--
-- ROLLBACK: re-apply the previous bodies of fn_phase_d_object_write, fn_phase_d_fixture_scenario
-- and fn_phase_d_outbound_state, then
--   drop function if exists public.fn_phase_d_outbound_requests_by_this_transaction(bigint);
-- A down script is committed at
-- scripts/sql/down/phase_d_j04_the_outbound_guard_counted_a_cron_jobs_requests_down.sql.
--
-- GENERATED from the live bodies by scripts/tmp_diag/gen_j04.mjs.

-- ---- the attribution, in one place, because two callers ask the same question -----------------
CREATE OR REPLACE FUNCTION public.fn_phase_d_outbound_requests_by_this_transaction(p_after bigint)
 RETURNS TABLE(n integer, urls text)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  -- The 64-bit id carries the epoch; the 32-bit form is what a row's xmin holds.
  v_top8  bigint := pg_current_xact_id()::text::bigint;
  v_top32 bigint := mod(pg_current_xact_id()::text::bigint, 4294967296);
begin
  return query
  select count(*)::int,
         string_agg(distinct q.method || ' ' || q.url, ', ')
    from net.http_request_queue q
   where q.id > p_after
     -- Anything below our own xid was written before this transaction started and cannot be ours.
     -- Filtering it first also fixes the epoch for the conversion on the next line.
     and q.xmin::text::bigint >= v_top32
     -- A visible row whose writer is still in progress is ours: another in-flight transaction's
     -- rows are not visible here at all, and a committed one reports 'committed'.
     and pg_xact_status(((v_top8 - v_top32) + q.xmin::text::bigint)::text::xid8) = 'in progress';
end
$function$;

-- A newly CREATED function is granted EXECUTE to PUBLIC. Nothing outside the two Phase D writers
-- calls this, and it reads a queue that names production endpoints.
REVOKE ALL ON FUNCTION public.fn_phase_d_outbound_requests_by_this_transaction(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_phase_d_outbound_requests_by_this_transaction(bigint) FROM anon;
REVOKE ALL ON FUNCTION public.fn_phase_d_outbound_requests_by_this_transaction(bigint) FROM authenticated;

`;

const fn = (name, args, extra, body) =>
  `CREATE OR REPLACE FUNCTION public.${name}(${args})\n${extra}AS $function$${body}$function$;\n\n`;

const meta = await sql(`select p.proname,
    pg_get_function_identity_arguments(p.oid) args,
    pg_get_function_result(p.oid) ret,
    p.prosecdef, p.provolatile, l.lanname,
    array_to_string(p.proconfig, ',') cfg
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  join pg_language l on l.oid = p.prolang
  where n.nspname='public' and p.proname in
    ('fn_phase_d_object_write','fn_phase_d_fixture_scenario','fn_phase_d_outbound_state')`);
const m = Object.fromEntries(meta.map(r => [r.proname, r]));
const sig = (r) => ` RETURNS ${r.ret}\n LANGUAGE ${r.lanname}\n`
  + (r.provolatile === 's' ? ' STABLE\n' : '')
  + (r.prosecdef ? ' SECURITY DEFINER\n' : '')
  + (r.cfg ? ` SET search_path TO ${r.cfg.replace(/^search_path=/, '').split(',').map(x => `'${x.trim()}'`).join(', ')}\n` : '');

writeFileSync('scripts/sql/phase_d_j04_the_outbound_guard_counted_a_cron_jobs_requests.sql',
  header
  + fn('fn_phase_d_object_write', m.fn_phase_d_object_write.args, sig(m.fn_phase_d_object_write), w)
  + fn('fn_phase_d_fixture_scenario', m.fn_phase_d_fixture_scenario.args, sig(m.fn_phase_d_fixture_scenario), f)
  + fn('fn_phase_d_outbound_state', m.fn_phase_d_outbound_state.args, sig(m.fn_phase_d_outbound_state), b));
console.log('written');
