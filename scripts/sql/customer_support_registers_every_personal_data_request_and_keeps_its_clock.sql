-- CUSTOMER SUPPORT REGISTERS EVERY PERSONAL-DATA REQUEST AND KEEPS ITS CLOCK (19 Oct 2026). Assigned: customer_support
-- (register, identity, clock); fulfilment stays with the doors that own it (fn_pdpl_* for access and erasure,
-- it_engineer for a correction). Founder ledger 1003 stage 2, contribution CS-C11: "Handle PDPL data subject requests
-- (access, correction, erasure, objection) with identity check and a tracked clock". UAE Federal Decree-Law 45/2021
-- (PDPL) Arts. 13-17 give the rights; its Executive Regulations, which would set a response period, are not issued, so
-- the period here is the company's own decision_policy data_request_days (30), changeable by the CEO, not a statute.
--
-- MEASURED 19 Oct 2026 (repo + production, read-only): the access/erasure path exists and is careful
-- (a_person_can_get_a_copy_of_their_data_and_have_it_erased_where_no_law_requires_it_kept.sql: fn_pdpl_open emails a
-- 6-digit code, fn_pdpl_verify proves the address, erasure cools off 7 days, fn_pdpl_tick completes it). pdpl_requests
-- has 0 rows and kind admits only export|delete. Nothing registers a request that arrives as a support conversation,
-- nothing handles correction or objection, and no request carries a due date or is chased.
--
-- WHAT THIS ADDS:
--   * public.customer_support_data_request, the register: kind access | correction | erasure | objection, the address,
--     where it came from, identity status, due_at (received + data_request_days), the linked pdpl request or handoff.
--   * public.fn_customer_support_data_request_open(email, kind, source, case_ref): the one door to register (a portal,
--     the email triage or a person calls it), idempotent per open (email, kind).
--   * support category 'data_request' (owner customer_support) and the signal email_category/data_request, so an email
--     the triage classifies as a data request lands in that category.
--   * customer_support.data_requests, hourly, fn_customer_support_data_request_tick(). Code, no model:
--       register  every pdpl_requests row (self-service or operator) and every support case in category data_request
--                 not yet in the register (kind from the case's topic tags: erase/delete -> erasure, correct ->
--                 correction, object/stop -> objection, else access);
--       identity  access and erasure: fn_pdpl_open sends the code to the address (the address is the identity);
--                 correction and objection: the case's identity_verified, else the request waits as identity pending;
--       fulfil    access/erasure follow their pdpl request (verified -> identity verified; completed or exported ->
--                 fulfilled); objection to marketing is fulfilled at once once verified (email_suppressions
--                 'unsubscribe', source pdpl_objection, which stops marketing only); correction is handed to
--                 it_engineer (data.correction) with the due date and fulfilled when that handoff completes;
--       clock     5 days before due_at and still open -> the CEO is asked now (once); past due_at -> reported as
--                 serious (once). A fixture run never writes to the CEO.
--
-- Prevented by: scripts/checks/customer_support_senior_contributions_are_working_duties.test.mjs.
-- Apply at merge:  node scripts/apply_sql.mjs scripts/sql/customer_support_registers_every_personal_data_request_and_keeps_its_clock.sql --apply --ddl

insert into public.decision_policy (key, value, description) values
  ('data_request_days', '30'::jsonb,
   'fn_customer_support_data_request_tick: days from receipt within which a personal-data request (access, correction, erasure, objection) is answered. Company policy; the PDPL Executive Regulations that would set a period are not issued.')
on conflict (key) do nothing;

insert into public.support_category (category, owner_seat, support_fixes, meaning) values
  ('data_request', 'customer_support', true, 'A person asking for a copy, a correction or the erasure of their personal data, or objecting to its use (PDPL). Registered in customer_support_data_request.')
on conflict do nothing;
insert into public.support_signal_category (source, value, category) values ('email_category', 'data_request', 'data_request')
on conflict do nothing;

create table if not exists public.customer_support_data_request (
  id              bigint generated always as identity primary key,
  received_at     timestamptz not null default now(),
  email           text not null,
  kind            text not null check (kind in ('access', 'correction', 'erasure', 'objection')),
  source          text not null,
  case_ref        text,
  pdpl_request_id uuid,
  handoff_id      bigint,
  identity_status text not null default 'pending' check (identity_status in ('pending', 'verified', 'failed')),
  due_at          timestamptz not null,
  status          text not null default 'open' check (status in ('open', 'fulfilled', 'refused')),
  fulfilled_at    timestamptz,
  outcome         jsonb not null default '{}'::jsonb,
  warned_at       timestamptz,
  overdue_at      timestamptz,
  fixture         boolean not null default false
);
create unique index if not exists customer_support_data_request_one_open on public.customer_support_data_request (lower(email), kind) where status = 'open';
create unique index if not exists customer_support_data_request_pdpl on public.customer_support_data_request (pdpl_request_id) where pdpl_request_id is not null;
comment on table public.customer_support_data_request is
  'customer_support''s register of personal-data requests (UAE PDPL): kind, identity, due date and fulfilment. Kept by fn_customer_support_data_request_tick.';
alter table public.customer_support_data_request enable row level security;
drop policy if exists customer_support_data_request_service_role_only on public.customer_support_data_request;
create policy customer_support_data_request_service_role_only on public.customer_support_data_request
  as permissive for all to public using (false) with check (false);
revoke all on public.customer_support_data_request from anon, authenticated;

create or replace function public.fn_customer_support_data_request_open(p_email text, p_kind text, p_source text, p_case_ref text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_em text := lower(btrim(coalesce(p_email, ''))); v_id bigint;
begin
  if v_em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or p_kind not in ('access', 'correction', 'erasure', 'objection') or coalesce(btrim(p_source), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'an address, a kind (access|correction|erasure|objection) and a source are required');
  end if;
  select id into v_id from public.customer_support_data_request where lower(email) = v_em and kind = p_kind and status = 'open';
  if v_id is not null then return jsonb_build_object('ok', true, 'id', v_id, 'duplicate', true); end if;
  insert into public.customer_support_data_request (email, kind, source, case_ref, due_at, fixture)
  values (v_em, p_kind, p_source, p_case_ref,
          now() + make_interval(days => greatest(1, public.fn_seat_clock_policy('data_request_days', 30)::int)),
          public.fn_is_demo_email(v_em))
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $fn$;
revoke execute on function public.fn_customer_support_data_request_open(text, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_customer_support_data_request_open(text, text, text, text) to service_role;

create or replace function public.fn_seat_takes_data_request(p_id bigint)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object('accepted', true, 'seat', a.agent, 'request_id', a.detail->'request_id',
    'waiting', coalesce(a.detail->>'waiting_for', 'the correction of the person''s data, by the due date'))
    from public.agent_actions a where a.id = p_id
$fn$;
revoke execute on function public.fn_seat_takes_data_request(bigint) from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
values ('data.correction', 'customer_support', 'it_engineer',
        'A verified person asked for their personal data to be corrected (PDPL). it_engineer corrects the record by the due date in the payload; customer_support closes the request when this completes.',
        'fn_seat_takes_data_request', interval '7 days', false,
        'scripts/sql/customer_support_registers_every_personal_data_request_and_keeps_its_clock.sql')
on conflict (type, from_seat, to_seat) do update
   set meaning = excluded.meaning, handler = excluded.handler, reply_within = excluded.reply_within, owner_file = excluded.owner_file;

create or replace function public.fn_customer_support_data_request_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_days int := greatest(1, public.fn_seat_clock_policy('data_request_days', 30)::int);
  p record; c record; q public.customer_support_data_request; v_kind text; v_open jsonb; v_pr record; v_h bigint; v_r jsonb;
  n_reg int := 0; n_code int := 0; n_done int := 0; n_hand int := 0; n_warn int := 0; n_over int := 0;
begin
  -- register: requests made through the pdpl door
  for p in select r.* from public.pdpl_requests r
            where public.fn_is_demo_email(r.email) = v_fx
              and not exists (select 1 from public.customer_support_data_request d where d.pdpl_request_id = r.id) loop
    insert into public.customer_support_data_request (received_at, email, kind, source, pdpl_request_id, due_at, fixture)
    values (p.created_at, lower(p.email), case when p.kind = 'delete' then 'erasure' else 'access' end, 'pdpl:' || coalesce(p.role, '?'),
            p.id, p.created_at + make_interval(days => v_days), v_fx)
    on conflict do nothing;
    n_reg := n_reg + 1;
  end loop;

  -- register: support conversations categorised as a data request
  for c in select s.case_ref, s.topic_tags, s.identity_verified, coalesce(pr.email, '') email
             from public.support_case s left join public.support_customer_profile pr on pr.id = s.customer_profile_id
            where s.category = 'data_request' and public.fn_is_demo_email(pr.email) = v_fx
              and not exists (select 1 from public.customer_support_data_request d where d.case_ref = s.case_ref) loop
    v_kind := case when exists (select 1 from unnest(c.topic_tags) t where t ~* '(eras|delet|remov)') then 'erasure'
                   when exists (select 1 from unnest(c.topic_tags) t where t ~* 'correct') then 'correction'
                   when exists (select 1 from unnest(c.topic_tags) t where t ~* '(object|stop|opt)') then 'objection'
                   else 'access' end;
    v_open := public.fn_customer_support_data_request_open(c.email, v_kind, 'support_case', c.case_ref);
    if coalesce((v_open->>'ok')::boolean, false) then
      n_reg := n_reg + 1;
      if c.identity_verified then
        update public.customer_support_data_request set identity_status = 'verified' where id = (v_open->>'id')::bigint;
      end if;
    end if;
  end loop;

  for q in select * from public.customer_support_data_request where status = 'open' and fixture = v_fx order by id for update loop
    if q.kind in ('access', 'erasure') then
      if q.pdpl_request_id is null then
        -- the identity check: a code to the address, through the pdpl door
        v_open := public.fn_pdpl_open(q.email, case when q.kind = 'erasure' then 'delete' else 'export' end, 'customer_support');
        if coalesce((v_open->>'ok')::boolean, false) then
          update public.customer_support_data_request set pdpl_request_id = (v_open->>'request_id')::uuid where id = q.id;
          n_code := n_code + 1;
        end if;
      else
        select r.* into v_pr from public.pdpl_requests r where r.id = q.pdpl_request_id;
        if v_pr.verified_at is not null and q.identity_status <> 'verified' then
          update public.customer_support_data_request set identity_status = 'verified' where id = q.id;
        end if;
        if v_pr.completed_at is not null or (q.kind = 'access' and v_pr.verified_at is not null) or v_pr.status in ('completed', 'deferred') then
          update public.customer_support_data_request set status = 'fulfilled', fulfilled_at = now(),
                 outcome = outcome || jsonb_build_object('pdpl_status', v_pr.status, 'pdpl_outcome', v_pr.outcome) where id = q.id;
          n_done := n_done + 1; continue;
        elsif v_pr.cancelled_at is not null then
          update public.customer_support_data_request set status = 'refused', outcome = outcome || jsonb_build_object('cancelled', v_pr.cancelled_at) where id = q.id;
          continue;
        end if;
      end if;
    elsif q.identity_status = 'verified' and q.kind = 'objection' then
      insert into public.email_suppressions (email, reason, source) values (q.email, 'unsubscribe', 'pdpl_objection') on conflict (email) do nothing;
      update public.customer_support_data_request set status = 'fulfilled', fulfilled_at = now(),
             outcome = outcome || jsonb_build_object('marketing_stopped', true) where id = q.id;
      n_done := n_done + 1; continue;
    elsif q.identity_status = 'verified' and q.kind = 'correction' then
      if q.handoff_id is null then
        v_h := public.fn_seat_handoff('customer_support', 'it_engineer', 'data.correction', 'customer_support_data_request', q.id::text,
          jsonb_build_object('request_id', q.id, 'email', q.email, 'case_ref', q.case_ref, 'due_at', q.due_at,
                             'waiting_for', 'the correction asked for in case ' || coalesce(q.case_ref, '?') || ', by ' || to_char(q.due_at at time zone 'Asia/Dubai', 'YYYY-MM-DD')));
        update public.customer_support_data_request set handoff_id = v_h where id = q.id;
        n_hand := n_hand + 1;
      elsif exists (select 1 from public.agent_actions a where a.id = q.handoff_id and a.status = 'done') then
        update public.customer_support_data_request set status = 'fulfilled', fulfilled_at = now(),
               outcome = outcome || jsonb_build_object('corrected_by', 'it_engineer', 'handoff_id', q.handoff_id) where id = q.id;
        n_done := n_done + 1; continue;
      end if;
    end if;

    -- the clock
    if not v_fx and q.warned_at is null and now() >= q.due_at - interval '5 days' and now() < q.due_at then
      v_r := public.fn_support_report_to_ceo('data_request_due_soon:' || q.id, 'elevated',
        'A personal-data request (' || q.kind || ') is due ' || to_char(q.due_at at time zone 'Asia/Dubai', 'YYYY-MM-DD'),
        jsonb_build_object('request_id', q.id, 'kind', q.kind, 'received_at', q.received_at, 'due_at', q.due_at,
                           'identity_status', q.identity_status, 'case_ref', q.case_ref),
        jsonb_build_array('registered by customer_support', 'identity: ' || q.identity_status),
        'Make sure the ' || q.kind || ' is completed before the due date, or decide a lawful refusal.', p_case_ref => q.case_ref);
      update public.customer_support_data_request set warned_at = now() where id = q.id;
      n_warn := n_warn + 1;
    elsif not v_fx and q.overdue_at is null and now() >= q.due_at then
      v_r := public.fn_support_report_to_ceo('data_request_overdue:' || q.id, 'serious',
        'A personal-data request (' || q.kind || ') is past its due date',
        jsonb_build_object('request_id', q.id, 'kind', q.kind, 'received_at', q.received_at, 'due_at', q.due_at,
                           'identity_status', q.identity_status, 'case_ref', q.case_ref),
        jsonb_build_array('warned 5 days before'), 'Complete the ' || q.kind || ' now and tell the person.', p_case_ref => q.case_ref);
      update public.customer_support_data_request set overdue_at = now() where id = q.id;
      n_over := n_over + 1;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'fixture', v_fx, 'registered', n_reg, 'identity_codes_sent', n_code, 'fulfilled', n_done,
    'handed_to_it_engineer', n_hand, 'warned', n_warn, 'overdue', n_over,
    'open', (select count(*) from public.customer_support_data_request where status = 'open' and fixture = v_fx));
end $fn$;
revoke execute on function public.fn_customer_support_data_request_tick() from public, anon, authenticated;
grant execute on function public.fn_customer_support_data_request_tick() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('customer_support.data_requests', 'customer_support', interval '1 hour', 'fn_customer_support_data_request_tick',
   'CS-C11: every personal-data request (PDPL: access, correction, erasure, objection) registered, identity checked, fulfilled through its owning door, and its due date kept (the CEO asked before it lapses)',
   'scripts/sql/customer_support_registers_every_personal_data_request_and_keeps_its_clock.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

-- the new table is in the daily table export (backups), like every other seat record
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('customer_support_data_request', true, 'customer_support', 'The register of personal-data requests under the UAE PDPL and their due dates (CS-C11).', 'customer_support')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category, reason = excluded.reason;
