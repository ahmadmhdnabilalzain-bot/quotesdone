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

-- fn_seat_handoff: the live body unchanged except the one ruling-1199 line after the subject check.
create or replace function public.fn_seat_handoff(p_from text, p_to text, p_type text, p_subject_table text, p_subject_id text, p_payload jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare v_id bigint; v_key text := p_type || ':' || p_subject_id; v_known boolean;
begin
  if coalesce(btrim(p_subject_id), '') = '' then raise exception 'a handoff must name its subject'; end if;
  -- ruling 1199: a handoff raised from a demo row is not filed at all
  if public.fn_seat_work_is_demo(p_payload::text, p_payload, p_subject_table, p_subject_id) then return null; end if;
  v_known := exists (select 1 from public.seat_handoff_kind k
                      where k.type = p_type and k.from_seat = p_from and k.to_seat = p_to);

  select id into v_id from public.agent_actions
   where kind = 'handoff' and agent = p_to and target_id = v_key and status <> 'failed'
   order by id limit 1;
  if v_id is not null then return v_id; end if;

  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values (p_to, 'handoff', case when v_known then 'pending' else 'failed' end, 'low',
          left(p_type || ' from ' || p_from || ' about ' || p_subject_table || ' ' || p_subject_id, 200),
          coalesce(p_payload, '{}'::jsonb) || jsonb_build_object(
            'type', p_type, 'from', p_from, 'from_name', p_from, 'to', p_to,
            'subject_table', p_subject_table, 'subject_id', p_subject_id)
          || case when v_known then '{}'::jsonb
                  else jsonb_build_object('error', 'unregistered handoff kind: no row in public.seat_handoff_kind') end,
          p_subject_table, v_key)
  returning id into v_id;

  if not v_known then
    perform public.fn_seat_handoff_event(v_id, 'failed');
    perform public.fn_it_engineer_finding_upsert(
      'monitor:unregistered_handoff_kind:' || p_type || ':' || p_from || ':' || p_to,
      'Unregistered handoff kind: ' || p_from || ' tried to start "' || p_type || '" with ' || p_to,
      'public.fn_seat_handoff (caller: ' || p_from || ')', 'agent_facing', 1,
      jsonb_build_object('type', p_type, 'from', p_from, 'to', p_to, 'handoff_id', v_id, 'owner_seat', 'ceo',
                         'fix', 'insert the conversation into public.seat_handoff_kind with its handler, in the file of the build that starts it'),
      '{}'::text[], array['which build starts this conversation and which handler answers it'], 'fn_seat_handoff');
    return v_id;
  end if;
  perform public.fn_seat_handoff_event(v_id, 'sent');

  -- THE RECEIVING SEAT ACTS NOW. A failure is recorded on the row and in the stream and never
  -- rolls back the money event that raised it: a refund that settled stays settled.
  begin
    perform public.fn_seat_handoff_act(v_id);
  exception when others then
    update public.agent_actions
       set status = 'failed', decided_at = now(),
           detail = detail || jsonb_build_object('error', left(sqlerrm, 500))
     where id = v_id;
    perform public.fn_seat_handoff_event(v_id, 'failed');
  end;
  return v_id;
end $function$;
