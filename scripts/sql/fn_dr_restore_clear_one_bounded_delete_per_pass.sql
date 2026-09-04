-- THE DRILL'S STAGING CLEAR MOVES SERVER-SIDE: ONE BOUNDED DELETE PER PASS (4 Sep 2026).
--
-- dr_drill cleared public.dr_restore through PostgREST — select up to 1,000 ids, delete them, repeat —
-- because a single conditional DELETE over a quarter of a million rows hit the authenticator role's
-- 8-second statement_timeout on 12 Aug 2026. PostgREST caps every select at 1,000 rows, so a
-- 40-pass pre-clear reaches 40,000 rows while one drill leaves ~234,000 (201 pages of kb_chunks).
-- The fire-and-forget self-cleanup added on 3 Sep never ran at all: on 4 Sep the table held every
-- one of run 43409's 234,047 rows. Measured on 3 Sep: run 43341 reported "cleared 200000 row(s) in
-- 200 passes and 34047 still remain" and called its own verdict untrustworthy.
--
-- One pass is now one statement here: delete up to p_limit rows chosen by ctid, either older than
-- p_before (the pre-clear, which keeps the 180-second predicate so a concurrently running chain's
-- rows survive) or belonging to p_run_id (the drill's own rows at the end). 20,000 rows took 1.4s
-- on 4 Sep against the 8s budget. dr_drill loops over this until it returns 0.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_dr_restore_clear_one_bounded_delete_per_pass.sql --apply --ddl
create or replace function public.fn_dr_restore_clear(p_before timestamptz default null, p_run_id uuid default null, p_limit integer default 20000)
returns integer
language plpgsql
set search_path = public
as $fn$
declare
  v_n integer;
begin
  if p_before is null and p_run_id is null then
    raise exception 'fn_dr_restore_clear needs p_before or p_run_id: an unbounded clear would race a running drill chain';
  end if;
  delete from public.dr_restore d
   where d.ctid = any(array(
           select r.ctid from public.dr_restore r
            where (p_before is not null and r.drill_at < p_before)
               or (p_run_id is not null and r.run_id = p_run_id)
            limit greatest(1, least(coalesce(p_limit, 20000), 50000))));
  get diagnostics v_n = row_count;
  return v_n;
end
$fn$;
comment on function public.fn_dr_restore_clear(timestamptz, uuid, integer) is
  'One bounded DELETE pass over dr_restore for dr_drill: rows older than p_before (pre-clear, keeps the running-chain predicate) or rows of p_run_id (the drill''s own cleanup). Returns rows deleted; the caller loops until 0.';
