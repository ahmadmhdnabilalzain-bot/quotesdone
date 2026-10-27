-- A ROLLED-BACK PROBE MAY FILE DEMO SEAT WORK UNDER ITS OWN SWITCH (it_engineer, 27 Oct 2026).
-- Seat: it_engineer. Extends demo_activity_files_no_seat_task_or_handoff.sql (ruling 1199, #1479, applied 19 Oct).
--
-- MEASURED 27 Oct 2026 (npm test on main 5446f606 against production): ruling 1199's guard made fn_seat_handoff
-- return NULL and the org_tasks trigger drop the row for every ZZ DEMO subject. That is right for the running
-- company, and it left every rolled-back probe that proves a seat loop on ZZ DEMO fixtures with nothing to measure:
-- "no held question <NULL>" (a_ceo_rejection_loops_back_to_the_seat), "no handoff <NULL>"
-- (a_lesson_never_carries_a_case_or_inquiry_id_or_an_amount), "0 handoffs for the supplier"
-- (a_verified_supplier_is_told_what_his_portfolio_is_missing), "no it.finding handoff opened"
-- (the_accountant_closes_every_loop_it_opens) and more. A probe that cannot see the loop cannot catch it breaking.
--
-- THE SWITCH. qd.probe_files_demo_handoff = 'on' makes fn_seat_work_is_demo answer false, so a ZZ DEMO subject files its
-- handoff and its task like a real one. It is the same shape as qd.duty_fixtures (a_fenced_seat_duty_keeps_its_
-- fixture_switch.sql): a custom setting no role, cron job or edge function sets. A probe sets it with
-- set_config('qd.probe_files_demo_handoff', 'on', true) - transaction-local - inside a request that safe_replay always
-- rolls back, so nothing it files survives and pg_net (the only outbound path; the http extension is not
-- installed) sends nothing from a rolled-back transaction. It is a separate name from qd.duty_fixtures ON PURPOSE:
-- the_sales_engineer_closes_the_loops_a_senior_sales_engineer_closes_probe.sql sets qd.duty_fixtures and asserts
-- that its demo rounds file NO handoff; reusing that switch would have turned that guard off under it.
--
-- ONE SWITCH, NOT TWO. #1587 (applied 27 Oct 00:0x UTC) already gave fn_seat_handoff this exact name for the IT duty
-- probes, but only there: the org_tasks trigger (a000_org_task_demo_files_nothing) still dropped a ZZ DEMO task under
-- it, which is why the rescreen, week-review and founder-mail probes stayed blind. Reading the same name in the one
-- guard both doors call extends #1587 to the task door; fn_seat_handoff's own check becomes redundant, not different.
--
-- Unset, or anything but 'on', the guard is byte-for-byte the 19 Oct body.
-- Prevented by: scripts/checks/a_rolled_back_probe_may_file_demo_seat_work_under_its_own_switch.test.mjs.

create or replace function public.fn_seat_work_is_demo(p_text text, p_ref jsonb,
                                                      p_subject_table text default null, p_subject_id text default null)
returns boolean language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $f$
declare
  v_uuid constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_id text := split_part(coalesce(p_subject_id, ''), ':', 1);
  v_ref jsonb := case when jsonb_typeof(p_ref) = 'object' then p_ref else '{}'::jsonb end;
begin
  -- a rolled-back probe proving a seat loop on ZZ DEMO fixtures (never set outside one)
  if coalesce(current_setting('qd.probe_files_demo_handoff', true), '') = 'on' then return false; end if;

  if coalesce(p_text, '') ~* '(^|[^a-z])zz\s*demo' then return true; end if;

  -- the subject a handoff names, folded into the reference set
  if p_subject_table in ('leads', 'suppliers') then v_ref := v_ref || jsonb_build_object('zz_subject', jsonb_build_object('supplier_id', v_id));
  elsif p_subject_table = 'customers' then v_ref := v_ref || jsonb_build_object('zz_subject', jsonb_build_object('customer_id', v_id));
  elsif p_subject_table = 'inquiries' then v_ref := v_ref || jsonb_build_object('zz_subject', jsonb_build_object('inquiry_id', v_id));
  elsif p_subject_table = 'transactions' then v_ref := v_ref || jsonb_build_object('zz_subject', jsonb_build_object('transaction_id', v_id));
  elsif p_subject_table = 'reviews' and v_id ~ '^[0-9]{1,18}$' then
    v_ref := v_ref || coalesce((select jsonb_build_object('zz_subject', jsonb_build_object('customer_id', r.customer_id,
                       'supplier_id', r.supplier_id, 'transaction_id', r.transaction_id)) from public.reviews r where r.id = v_id::bigint), '{}');
  elsif p_subject_table is not null and public.fn_deliberation_subject_is_fixture(p_subject_table, p_subject_id) then
    return true;
  end if;

  if v_ref = '{}'::jsonb then return false; end if;
  if coalesce((public.fn_ai_subject_is_fixture(v_ref) ->> 'fixture')::boolean, false) then return true; end if;

  -- any customer / supplier / lead / inquiry / transaction / email named at any depth (a rating nests them)
  return exists (
    select 1
      from (values ('customer_id'), ('supplier_id'), ('lead_id'), ('inquiry_id'), ('transaction_id'), ('email')) k(key)
      cross join lateral jsonb_path_query(v_ref, ('lax $.**.' || k.key)::jsonpath) x(val)
      cross join lateral (select x.val #>> '{}' as s) s
     where case k.key
             when 'customer_id'    then public.fn_party_is_demo('customer', s.s)
             when 'supplier_id'    then public.fn_party_is_demo('supplier', s.s)
             when 'lead_id'        then public.fn_party_is_demo('lead', s.s)
             when 'email'          then public.fn_is_demo_email(s.s)
             when 'inquiry_id'     then case when s.s ~ v_uuid then public.fn_inquiry_is_demo(s.s::uuid) else false end
             when 'transaction_id' then case when s.s ~ v_uuid then public.fn_transaction_is_demo(s.s::uuid) else false end
           end);
end $f$;
-- CREATE OR REPLACE keeps the ACL the 19 Oct file set (revoked from public, anon, authenticated).
