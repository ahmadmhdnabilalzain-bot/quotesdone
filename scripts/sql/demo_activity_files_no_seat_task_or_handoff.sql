-- Ruling 1199 (founder): demo activity must NEVER create seat work. Sandbox run 5: a demo rating raised a real
-- sales_engineer task through fn_sales_rating_landed; on 18 Oct the last 8 org_tasks held 6 ZZ DEMO ones (portal
-- questions, a ZZ DEMO supplier registration) and 1,129 of 12,882 handoffs in 30 days named ZZ DEMO.
--
-- ONE guard, fn_seat_work_is_demo, built only from the existing fixture predicates (fn_party_is_demo,
-- fn_inquiry_is_demo, fn_transaction_is_demo, fn_is_demo_email, fn_ai_subject_is_fixture for the qd_run harness,
-- the "ZZ DEMO" name convention). It is applied where every source converges, so no caller can be missed:
--   * org_tasks: a BEFORE INSERT trigger skips the row (covers fn_sales_rating_landed, fn_event_dispatch for
--     customer.complaint, fn_founder_mail_route for supplier_registered, the portal/whatsapp question filers,
--     fn_workflow_step_sweep, fn_kpi_review, fn_receipt_hand_to_bookkeeper, and every edge function insert).
--   * handoffs: fn_seat_handoff returns null before it writes the agent_actions row (an insert-time skip there
--     would leave fn_seat_handoff_event called with a null id). Callers of fn_seat_handoff already treat its
--     result as optional.
-- Not guarded on purpose: agent_actions of kind held_question / supplier_verification. The sandbox walks
-- those on demo rows by design (a_held_question_is_paid_for_once...).

create or replace function public.fn_seat_work_is_demo(p_text text, p_ref jsonb,
                                                      p_subject_table text default null, p_subject_id text default null)
returns boolean language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $f$
declare
  v_uuid constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_id text := split_part(coalesce(p_subject_id, ''), ':', 1);
  v_ref jsonb := case when jsonb_typeof(p_ref) = 'object' then p_ref else '{}'::jsonb end;
begin
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

create or replace function public.fn_org_task_demo_files_nothing()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $f$
begin
  if public.fn_seat_work_is_demo(coalesce(new.title, '') || ' ' || coalesce(new.detail, ''), new.result) then
    return null;   -- ruling 1199: a demo row files no seat task
  end if;
  return new;
end $f$;
revoke execute on function public.fn_org_task_demo_files_nothing() from public;
revoke execute on function public.fn_org_task_demo_files_nothing() from anon;
revoke execute on function public.fn_org_task_demo_files_nothing() from authenticated;

-- "a000" fires before every other BEFORE INSERT trigger on org_tasks (alphabetical), so nothing else sees the row.
drop trigger if exists a000_org_task_demo_files_nothing on public.org_tasks;
create trigger a000_org_task_demo_files_nothing before insert on public.org_tasks
  for each row execute function public.fn_org_task_demo_files_nothing();

-- fn_seat_handoff: its ruling-1199 line (return null when fn_seat_work_is_demo) lives in the routine's one owner,
-- scripts/sql/the_it_engineer_closes_every_loop_it_opens.sql (handoff_kinds_are_data.test.mjs). This file applied
-- that same body to production on 19 Oct; the owner file now carries it, so production needs no re-apply.
