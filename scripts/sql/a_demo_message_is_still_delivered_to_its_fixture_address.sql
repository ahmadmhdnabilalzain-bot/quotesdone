-- A DEMO MESSAGE IS STILL DELIVERED TO ITS FIXTURE ADDRESS (it_engineer, 19 Oct 2026).
--
-- demo_activity_files_no_seat_task_or_handoff.sql (ruling 1199) made fn_seat_handoff return null when
-- fn_seat_work_is_demo said the payload was demo. Every message is queued as a 'delivery.request' handoff
-- (fn_customer_support_takes_delivery, fn_sales_engineer_writes, fn_originator_checks_delivery,
-- fn_sales_engineer_answers_delivery_remediate all pass subject table 'notifications'), and a message to a
-- ZZ DEMO customer carries an @example.invalid address, so every demo message was silently dropped: no
-- notification row, handoff_id null, and the deliverer reported ok. Measured: the seat-clock rehearsal
-- (complaints_quotes_reveals_and_support_replies_each_run_on_a_clock_probe.sql) went PROBE FAILED on main:
-- no invited supplier reminded, the customer not told, the 7-day outcome check not asked.
--
-- Ruling 1199 is about seat WORK (tasks and conversations), not the demo's own mail, so the one guard now
-- answers false for the delivery subject. Every other handoff from a demo row is still not filed.
-- Prevented by: scripts/checks/every_duty_has_an_owner_and_a_clock.test.mjs (the rehearsal) and
-- scripts/sql/demo_activity_files_no_seat_task_or_handoff_probe.sql (a demo complaint.due still files nothing).

create or replace function public.fn_seat_work_is_demo(p_text text, p_ref jsonb,
                                                      p_subject_table text default null, p_subject_id text default null)
returns boolean language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $f$
declare
  v_uuid constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_id text := split_part(coalesce(p_subject_id, ''), ':', 1);
  v_ref jsonb := case when jsonb_typeof(p_ref) = 'object' then p_ref else '{}'::jsonb end;
begin
  -- a delivery request (subject table notifications) is the message itself, not seat work: a demo customer is still
  -- written to at its fixture address, where the send gate already keeps it from any real one.
  if p_subject_table = 'notifications' then return false; end if;
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
revoke execute on function public.fn_seat_work_is_demo(text, jsonb, text, text) from public;
revoke execute on function public.fn_seat_work_is_demo(text, jsonb, text, text) from anon;
revoke execute on function public.fn_seat_work_is_demo(text, jsonb, text, text) from authenticated;
