-- A DEMO SUPPORT CASE IS REMOVED WITH ITS HISTORY, AND A REAL ONE NEVER IS (it_engineer, 12 Nov 2026).
-- Assigned: it_engineer (the e2e harness's teardown and its database door). Founder ledger 1642 ("Proceed with fixes"):
-- DECIDED, demo data is exempt from ruling 1634's keep-everything rule; a real person's case history stays append-only.
-- Final audit 12 Nov 2026: customer_journey H6 / health H7 (fix O4).
--
-- MEASURED (production, read-only, 12 Nov 2026):
--   * support_case_summary_version (#1943) references support_case(case_id) and its trigger
--     a00_support_case_summary_version_append_only refuses every UPDATE and DELETE. scripts/lib/demo_factory.mjs teardown
--     deleted the run's support_case rows and met 23503 support_case_summary_version_case_id_fkey; the teardown stops at
--     its first such error, so audit run d9a04dbc left 3 customers, 15 suppliers, 2 requests, 140 notices, 18 auth users.
--   * Left behind now: cases 2221 (run 71366940), 2235 and 2236 (run d9a04dbc), their 4 summary versions (ids 10-13),
--     0 promises, and profiles 1034, 1036, 1037.
--   * Foreign keys into support_case: feedback, refund_case, support_case (recovery_of_case_id), support_case_promise,
--     support_case_summary_version, support_document_intake, support_notification. The probe fails when that list changes.
--
-- THE DEMO TEST is the one the promise ledger already uses for "the demo marker of whoever the case is with"
-- (every_promise_a_case_records_is_kept_or_its_seat_is_told_before_it_is_due.sql): fn_party_is_demo(party_kind, party_id),
-- or the case's profile has a reserved address (fn_is_demo_email), a demo customer or a demo lead. It is named once here,
-- as fn_support_case_is_demo, and not redefined.
--
-- CHANGE
--   1. fn_support_case_is_demo(case_id): that test, for one case.
--   2. fn_demo_support_case_purge(case_ids[]): for each named case that passes the test, with no refund_case and no
--      non-demo case pointing at it, removes its summary versions, promises, feedback, document intakes and support
--      notifications, clears demo cases' recovery links to it, then the case. Every other id is returned as refused,
--      untouched. It sets the transaction-local flag qd.demo_case_purge only around its own deletes.
--   3. The append-only trigger lets a DELETE through only when that flag is on AND the row's case passes the demo test
--      itself, so a caller who sets the flag by hand still cannot remove a real person's history. UPDATE is refused always.
-- Revoked from public, anon, authenticated; no grant: the harness calls it through the management API (postgres).
-- CREATE OR REPLACE keeps the trigger function's ACL; search_path pinned on all three.
-- Order: apply this file, then merge/run the harness change (scripts/lib/demo_factory.mjs calls the routine).
-- Prevented by: scripts/checks/a_demo_support_case_is_removed_with_its_history_and_a_real_one_never_is.test.mjs (the
-- teardown removes a run's cases through the routine) and the rolled-back probe
-- a_demo_support_case_is_removed_with_its_history_and_a_real_one_never_is_probe.sql (a real case is refused).
--   node scripts/apply_sql.mjs scripts/sql/a_demo_support_case_is_removed_with_its_history_and_a_real_one_never_is.sql --apply --ddl

create or replace function public.fn_support_case_is_demo(p_case_id bigint)
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce((
    select public.fn_party_is_demo(c.party_kind, c.party_id)
        or coalesce(public.fn_is_demo_email(p.email), false)
        or (p.customer_id is not null and coalesce(public.fn_customer_is_demo(p.customer_id), false))
        or (p.lead_id is not null and coalesce(public.fn_supplier_is_demo(p.lead_id), false))
      from public.support_case c left join public.support_customer_profile p on p.id = c.customer_profile_id
     where c.case_id = p_case_id), false)
$fn$;

revoke execute on function public.fn_support_case_is_demo(bigint) from public, anon, authenticated;

create or replace function public.fn_support_case_summary_version_is_append_only()
returns trigger language plpgsql set search_path to 'public', 'pg_temp' as $fn$
begin
  -- Ledger 1642: a demo case's history goes with the demo case, only through fn_demo_support_case_purge.
  if tg_op = 'DELETE' and coalesce(current_setting('qd.demo_case_purge', true), '') = 'on'
     and public.fn_support_case_is_demo(old.case_id) then
    return old;
  end if;
  raise exception 'support_case_summary_version is append-only (ruling 1634): write a new version instead';
end $fn$;

revoke execute on function public.fn_support_case_summary_version_is_append_only() from public, anon, authenticated;

create or replace function public.fn_demo_support_case_purge(p_case_ids bigint[])
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_ok bigint[]; v_refused jsonb; n_v int; n_p int; n_f int; n_d int; n_n int; n_c int;
begin
  select coalesce(array_agg(x.id) filter (where x.why is null), '{}'),
         coalesce(jsonb_agg(jsonb_build_object('case_id', x.id, 'why', x.why)) filter (where x.why is not null), '[]')
    into v_ok, v_refused
    from (select u.id,
                 case when not exists (select 1 from public.support_case c where c.case_id = u.id) then 'no such case'
                      when not public.fn_support_case_is_demo(u.id) then 'not a demo case: a real person''s history is kept'
                      when exists (select 1 from public.refund_case r where r.case_id = u.id) then 'a refund case names it'
                      when exists (select 1 from public.support_case o where o.recovery_of_case_id = u.id
                                     and not public.fn_support_case_is_demo(o.case_id)) then 'a real case recovers it'
                 end why
            from (select distinct unnest(coalesce(p_case_ids, '{}'::bigint[])) id) u) x;
  if cardinality(v_ok) = 0 then
    return jsonb_build_object('deleted', 0, 'refused', v_refused);
  end if;
  perform set_config('qd.demo_case_purge', 'on', true);
  delete from public.support_case_summary_version where case_id = any (v_ok); get diagnostics n_v = row_count;
  delete from public.support_case_promise where case_id = any (v_ok);          get diagnostics n_p = row_count;
  delete from public.feedback where case_id = any (v_ok);                      get diagnostics n_f = row_count;
  delete from public.support_document_intake where case_id = any (v_ok);       get diagnostics n_d = row_count;
  delete from public.support_notification where case_id = any (v_ok);          get diagnostics n_n = row_count;
  update public.support_case set recovery_of_case_id = null where recovery_of_case_id = any (v_ok);
  delete from public.support_case where case_id = any (v_ok);                  get diagnostics n_c = row_count;
  perform set_config('qd.demo_case_purge', 'off', true);
  return jsonb_build_object('deleted', n_c, 'case_ids', to_jsonb(v_ok), 'summary_versions', n_v, 'promises', n_p,
                            'feedback', n_f, 'document_intakes', n_d, 'support_notifications', n_n, 'refused', v_refused);
end $fn$;

revoke execute on function public.fn_demo_support_case_purge(bigint[]) from public, anon, authenticated;

comment on function public.fn_demo_support_case_purge(bigint[]) is
  'Removes ZZ DEMO support cases (fn_support_case_is_demo) with their summary versions, promises and other case rows; refuses and returns every other id. The only door through the append-only summary history (ledger 1642). it_engineer, 12 Nov 2026.';

-- PROBE: read-only; returns its verdict as a row (the file holds DDL, so it must not raise).
with f as (select count(*) n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
            where s.nspname = 'public'
              and p.proname in ('fn_support_case_is_demo', 'fn_demo_support_case_purge', 'fn_support_case_summary_version_is_append_only')
              and exists (select 1 from unnest(p.proconfig) cfg where cfg like 'search_path=%')
              and not has_function_privilege('anon', p.oid, 'execute')
              and not has_function_privilege('authenticated', p.oid, 'execute')),
     t as (select count(*) n from pg_trigger where tgname = 'a00_support_case_summary_version_append_only' and tgenabled = 'O')
select case when (select n from f) = 3 and (select n from t) = 1 then 'PROBE OK'
            else 'PROBE FAILED: routines ' || (select n from f) || ' of 3 closed and pinned, trigger ' || (select n from t) end as verdict;
