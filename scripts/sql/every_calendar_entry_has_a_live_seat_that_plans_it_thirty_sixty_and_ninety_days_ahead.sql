-- EVERY CALENDAR ENTRY HAS A LIVE SEAT THAT PLANS IT THIRTY, SIXTY AND NINETY DAYS AHEAD (16 Nov 2026). Seat: ceo (the
-- calendar and its owners), with marketing and sales_engineer for events. Agent: OPS_LOOPS (it_engineer + ceo builder,
-- wave 2 of the real-company holes; hole H7 of the COO hunt).
--
-- MEASURED (production, read-only SELECT, 16 Nov 2026): company_calendar holds 58 rows; 54 name an owner_dept that is
-- not a seat (Growth 20, Ops 16, Finance 13, Legal 2, All 2, HR 1, Engineering 1) and 4 name 'accountant'. The founder's
-- ruling of 7 Sep 2026 is that there are no departments; the live seats are org_role (6 active: accountant, ceo,
-- customer_support, it_engineer, marketing, sales_engineer). Nothing acts ahead of a date: only it_expiry (licence, NOL)
-- and the send-day freeze read dates, and fn_ceo_register_review re-verifies a compliance row yearly without reading
-- starts_on. Row 41, "Big 5 Global 2026 (DWTC) - key construction event", starts 23 Nov (7 days away), its action says
-- "Treat as the flagship supplier-acquisition moment ... Do NOT run digital invite pushes during the show - run them 2-3
-- weeks before and immediately after", and no seat has an action on it (the marketing functions do not read the calendar).
--
-- WHAT THIS ADDS
--   1. company_calendar.owner_seat (a live seat, FK org_role) and also_seats. Each row's owner is decided by the CEO
--      seat's MODEL reading the row against the live seats and what each owns (held question ceo.calendar_owner, 12 rows
--      a question): owner, the seats that also act, and the next date the row falls on when it recurs. Code only checks the
--      answer: every seat named is an active org_role, a date is a real date. No department name is mapped by a rule.
--      owner_dept stays as the source text; nothing reads it any more.
--      Row 41 is set here (marketing, with sales_engineer) because the founder's hole hunt names it for those two seats
--      with a 7-day lead; the model may not move it (owner_set_by says why).
--   2. public.company_calendar_plan: one row per (entry, seat, horizon, date). The duty ceo.calendar_horizon, daily,
--      gives each seat its entries falling in the next 90, 60 and 30 days (only the nearest horizon crossed, never three at
--      once): an ORDER (ceo_directive, kind register_review, met when the seat's plan is recorded) and ONE held question
--      to the seat's model (<seat>.calendar_plan) with the entry, the days left, the facts the seat needs, and the rules it
--      may not break. The model decides plan or no_action and writes the plan; fn_calendar_plan_apply records it, which
--      meets the order. An entry with no owner yet is the CEO's.
--   3. company_calendar_brief: a standing brief for a seat on an entry, read into that seat's question. Seeded for Big 5
--      Global with what a real supplier recruiter does in the week before such a show (target exhibitors in our open
--      supply gaps, outreach only through the invitation pipeline and its brakes, a landing note for the CEO's approval,
--      the post-show wave before the National Day freeze, how it is measured). NOTHING here sends a message: every
--      outreach step goes through the existing invitation path, which enforces the bounce brake, the same-day brake,
--      opt-outs, the supplier@ sender and the WhatsApp opt-in rule; marketing publishes nothing while marketing_golive is
--      false without the CEO's approval.
-- WHAT IT DOES NOT CHANGE: fn_ceo_register_review (an open branch rewrites it), it_expiry, the send-day freeze, any
-- calendar row's text or dates.
--
-- Probe: scripts/sql/every_calendar_entry_has_a_live_seat_that_plans_it_thirty_sixty_and_ninety_days_ahead_probe.sql
-- Pending: scripts/sql/pending/every_calendar_entry_has_a_live_seat_that_plans_it_thirty_sixty_and_ninety_days_ahead.txt
-- prevented by: scripts/checks/the_ops_loops_close_against_what_they_measure.test.mjs and the probe (local PG16, twice).
--   node scripts/apply_sql.mjs scripts/sql/every_calendar_entry_has_a_live_seat_that_plans_it_thirty_sixty_and_ninety_days_ahead.sql --apply --ddl

set local lock_timeout = '3s';
alter table public.company_calendar
  add column if not exists owner_seat text references public.org_role (role_id),
  add column if not exists also_seats text[] not null default '{}',
  add column if not exists next_on date,
  add column if not exists owner_set_by text,
  add column if not exists owner_set_at timestamptz,
  add column if not exists owner_held_id bigint;
comment on column public.company_calendar.owner_seat is
  'The live seat (org_role) that owns this entry. Decided by the CEO seat''s model (ceo.calendar_owner); owner_dept is the old department text and is not read.';
comment on column public.company_calendar.next_on is
  'The next date a recurring entry falls on, as the CEO seat''s model read it from recurrence (null: starts_on is the date).';

create table if not exists public.company_calendar_plan (
  id bigserial primary key,
  calendar_id bigint not null references public.company_calendar (id),
  seat text not null references public.org_role (role_id),
  horizon_days integer not null check (horizon_days in (30, 60, 90)),
  occurs_on date not null,
  status text not null default 'asked' check (status in ('asked', 'planned', 'no_action')),
  plan text,
  held_id bigint,
  directive_id bigint,
  decided_at timestamptz,
  decided_by text,
  created_at timestamptz not null default now(),
  unique (calendar_id, seat, horizon_days, occurs_on)
);
comment on table public.company_calendar_plan is
  'What each seat decided to do about a company_calendar entry 90, 60 and 30 days ahead: its model''s plan or no_action (ceo.calendar_horizon).';
alter table public.company_calendar_plan enable row level security;
drop policy if exists company_calendar_plan_service_role_only on public.company_calendar_plan;
create policy company_calendar_plan_service_role_only on public.company_calendar_plan
  as permissive for all to public using (false) with check (false);
revoke all on public.company_calendar_plan from anon, authenticated;

create table if not exists public.company_calendar_brief (
  calendar_id bigint not null references public.company_calendar (id),
  seat text not null references public.org_role (role_id),
  brief text not null check (length(btrim(brief)) >= 20),
  set_by text not null,
  set_at timestamptz not null default now(),
  primary key (calendar_id, seat)
);
comment on table public.company_calendar_brief is 'A standing brief for one seat on one calendar entry, read into that seat''s calendar_plan question.';
alter table public.company_calendar_brief enable row level security;
drop policy if exists company_calendar_brief_service_role_only on public.company_calendar_brief;
create policy company_calendar_brief_service_role_only on public.company_calendar_brief
  as permissive for all to public using (false) with check (false);
revoke all on public.company_calendar_brief from anon, authenticated;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('company_calendar_plan', true, 'operations', 'What each seat planned (or decided not to do) about each company calendar entry 90, 60 and 30 days ahead.', 'ceo'),
  ('company_calendar_brief', true, 'operations', 'Standing briefs for a seat on a company calendar entry (Big 5 Global 2026 for marketing and sales_engineer).', 'ceo')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

-- ── Big 5 Global 2026: the two seats the hole hunt names, and what a real recruiter does in the week before ─────────────
update public.company_calendar
   set owner_seat = 'marketing', also_seats = array['sales_engineer'],
       owner_set_by = 'ceo: hole H7 of the 16 Nov 2026 COO hunt (founder ledgers 1711-1713) names Big 5 Global for marketing and sales_engineer',
       owner_set_at = now()
 where id = 41 and event_name like 'Big 5 Global 2026%' and owner_seat is null;

insert into public.company_calendar_brief (calendar_id, seat, brief, set_by)
select 41, 'sales_engineer',
  'Big 5 Global 2026, Dubai World Trade Centre, 23-26 Nov: the construction show where our suppliers exhibit. What a senior supplier recruiter does now: '
  || '(1) TARGET LIST: from the public exhibitor directory on big5global.com, the UAE exhibitors whose trade is one of our open supply gaps '
  || '(the gaps are in your facts: trade, emirate, how many we have, how many we need); match each to our leads table by its company domain; '
  || 'a new company is recorded as a lead with its public business contact and the source big5_global_2026. Building the list sends nothing. '
  || '(2) OUTREACH ONLY THROUGH THE SUPPLIER INVITATION PIPELINE, which applies the bounce brake, the same-day brake, every opt-out and suppression, '
  || 'the supplier@ sender, and WhatsApp only to a number that opted in (a scraped mobile is never an opt-in). The calendar says no digital invite '
  || 'push during the show: a pre-show wave inside the brake now, nothing 23-26 Nov, the post-show wave 27-30 Nov while intent is hot and before '
  || 'the National Day freeze of 1-6 Dec. If invitations are switched off, say what you need the CEO to decide. '
  || '(3) ONSITE: the short list of exhibitors worth meeting if someone attends; attendance is the founder''s decision, so hand the list to the CEO. '
  || '(4) MEASURE: invitations delivered, replies, registrations and approvals from the list within 21 days of the show.',
  'ceo: hole H7 of the 16 Nov 2026 COO hunt'
where exists (select 1 from public.company_calendar where id = 41)
on conflict (calendar_id, seat) do nothing;

insert into public.company_calendar_brief (calendar_id, seat, brief, set_by)
select 41, 'marketing',
  'Big 5 Global 2026, Dubai World Trade Centre, 23-26 Nov. What a real marketing seat does for a recruitment show: '
  || '(1) LANDING NOTE: one short page for suppliers who exhibit or visit (what QuotesDone is, that suppliers pay no commission, how to register in '
  || 'minutes with their trade licence), English, written for the CEO''s approval before anything is published (marketing_golive is false). '
  || '(2) TIMING: nothing pushed during the show; the note is live before the pre-show invitation wave and is the link the post-show wave of '
  || '27-30 Nov carries; no posting on a weekend or a UAE holiday (National Day freeze 1-6 Dec). '
  || '(3) MEASURE: registrations that arrive through the note''s link in the 14 days after the show, reported to the CEO.',
  'ceo: hole H7 of the 16 Nov 2026 COO hunt'
where exists (select 1 from public.company_calendar where id = 41)
on conflict (calendar_id, seat) do nothing;

-- ── 1. the CEO seat's model decides each row's owner, from the live seats ───────────────────────────────────────────────
create or replace function public.fn_ceo_calendar_owner_ask(p_rows integer default 12)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_seats jsonb; v_rows jsonb; v_ids bigint[]; v_hid bigint; v_fields jsonb; v_q text; v_batch int; n_asked int := 0;
        v_held jsonb := '[]'::jsonb;
begin
  -- a batch the model could not answer (failed or expired) is asked again: its rows are released
  update public.company_calendar c set owner_held_id = null
   where c.owner_seat is null and c.owner_held_id is not null
     and exists (select 1 from public.reasoning_held_question q where q.id = c.owner_held_id and q.status in ('failed', 'expired'));
  select coalesce(jsonb_agg(jsonb_build_object('seat', o.role_id, 'responsibilities', left(o.responsibilities, 500),
                                               'owned_decisions', o.owned_decisions) order by o.role_id), '[]'::jsonb)
    into v_seats from public.org_role o where o.status = 'active';
  for v_batch in 1..5 loop
  v_ids := null; v_rows := null; v_hid := null;
  select array_agg(c.id order by c.id), jsonb_agg(jsonb_build_object('id', c.id, 'event', c.event_name, 'kind', c.kind,
           'starts_on', c.starts_on, 'recurrence', c.recurrence, 'affects', c.affects, 'action', c.action,
           'old_department_text', c.owner_dept) order by c.id)
    into v_ids, v_rows
    from (select * from public.company_calendar c
           where c.owner_seat is null and c.owner_held_id is null order by c.id limit greatest(1, least(coalesce(p_rows, 12), 20))) c;
  exit when v_ids is null;
  select jsonb_agg(jsonb_build_object('key', 'row_' || x, 'question',
           'Entry ' || x || ': answer "<owner seat>; also: <seats or none>; next: <YYYY-MM-DD or none>"'))
    into v_fields from unnest(v_ids) x;
  v_q := 'Each company calendar entry needs one live seat that owns acting on it (the company has no departments: the old '
      || 'department text is only a hint). For each entry, name the owner seat from the live seats, the other seats that '
      || 'must also act (or none), and the next date it falls on if it recurs and its starts_on is past (or none).';
  v_hid := public.fn_reason_hold('ceo', 'ceo.calendar_owner', v_q,
    jsonb_build_object('seat', 'ceo', 'surface', 'ceo.calendar_owner', 'research', false, 'stakes', 'normal', 'question', v_q,
      'context', jsonb_build_object('audience', 'internal', 'case', jsonb_build_object('today', current_date, 'live_seats', v_seats, 'entries', v_rows)),
      'decision', jsonb_build_object('name', 'calendar_owners', 'fields', v_fields),
      'subject', jsonb_build_object('calendar_ids', to_jsonb(v_ids)), 'dedupeKey', 'calendar_owner:' || array_to_string(v_ids, ',')),
    jsonb_build_object('filed_by', 'ceo.calendar_horizon'), jsonb_build_object('calendar_ids', to_jsonb(v_ids)),
    'seat_duty', 'calendar_owner:' || array_to_string(v_ids, ','));
  exit when v_hid is null;                         -- nothing filed (the same batch failed in the last 7 days): stop here
  update public.company_calendar set owner_held_id = v_hid where id = any(v_ids);
  n_asked := n_asked + cardinality(v_ids); v_held := v_held || to_jsonb(v_hid);
  end loop;
  return jsonb_build_object('asked', n_asked, 'held_ids', v_held);
end $fn$;
revoke execute on function public.fn_ceo_calendar_owner_ask(integer) from public, anon, authenticated;

create or replace function public.fn_reason_apply_ceo__calendar_owner(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; x bigint; v text; v_owner text; v_also text[]; v_next date; v_part text;
        n_set int := 0; n_bad int := 0; v_bad jsonb := '[]'::jsonb;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  for x in select (e #>> '{}')::bigint from jsonb_array_elements(coalesce(r.subject->'calendar_ids', '[]'::jsonb)) e loop
    v := btrim(coalesce(p_result->'decision'->'fields'->('row_' || x)->>'value', ''));
    v_owner := lower(btrim(split_part(v, ';', 1)));
    v_also := '{}'; v_next := null;
    foreach v_part in array string_to_array(v, ';') loop
      v_part := btrim(v_part);
      if lower(v_part) like 'also:%' then
        select coalesce(array_agg(distinct lower(btrim(s))) filter (where lower(btrim(s)) not in ('', 'none', v_owner)), '{}')
          into v_also from unnest(string_to_array(substr(v_part, 6), ',')) s;
      elsif lower(v_part) like 'next:%' and btrim(substr(v_part, 6)) ~ '^\d{4}-\d{2}-\d{2}$' then
        begin v_next := btrim(substr(v_part, 6))::date; exception when others then v_next := null; end;
      end if;
    end loop;
    -- code only checks the model's answer: every seat it names is a live seat
    if not exists (select 1 from public.org_role o where o.role_id = v_owner and o.status = 'active')
       or exists (select 1 from unnest(v_also) s where not exists (select 1 from public.org_role o where o.role_id = s and o.status = 'active')) then
      update public.company_calendar set owner_held_id = null where id = x and owner_held_id = p_id;   -- asked again next run
      n_bad := n_bad + 1; v_bad := v_bad || jsonb_build_object('id', x, 'answer', left(v, 200));
      continue;
    end if;
    update public.company_calendar
       set owner_seat = v_owner, also_seats = v_also, next_on = case when v_next >= current_date then v_next end,
           owner_set_by = 'ceo.calendar_owner (' || coalesce(p_result->>'model', 'model') || ', held question ' || p_id || ')', owner_set_at = now()
     where id = x and owner_seat is null;
    n_set := n_set + 1;
  end loop;
  return jsonb_build_object('owners_set', n_set, 'refused', n_bad, 'refused_rows', v_bad);
end $fn$;
revoke execute on function public.fn_reason_apply_ceo__calendar_owner(bigint, jsonb) from public, anon, authenticated;

-- ── 2. each seat gets its entries 90, 60 and 30 days ahead ─────────────────────────────────────────────────────────────
create or replace function public.fn_calendar_seat_facts(p_seat text)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select jsonb_build_object(
    'rules', 'No message to any person outside the platform''s consent rules: supplier invitations only through the invitation '
             || 'pipeline (bounce brake, same-day brake, opt-outs and suppressions, supplier@ sender, WhatsApp only to an opted-in number). '
             || 'Marketing publishes nothing without the CEO''s approval while marketing_golive is false; no posting on a weekend or a UAE holiday. '
             || 'No spend, booking or attendance is committed by a seat: those are the CEO''s or the founder''s decisions, asked for in the plan.',
    'switches', (select coalesce(jsonb_object_agg(s.key, s.value), '{}'::jsonb) from public.app_secrets s
                  where s.key in ('invite_enabled', 'invite_lane_enabled', 'invite_m365_enabled', 'marketing_golive')),
    'open_supply_gaps', case when p_seat in ('sales_engineer', 'marketing', 'ceo') then
       (select coalesce(jsonb_agg(jsonb_build_object('trade', g.trade, 'emirate', g.emirate, 'have', g.matchable, 'need', g.target,
                                                     'not_yet_invited', g.uninvited_pool) order by g.target - g.matchable desc, g.trade), '[]'::jsonb)
          from (select * from public.supply_gap where status = 'open' and matchable < target
                 order by target - matchable desc, uninvited_pool desc limit 15) g) end);
$fn$;
revoke execute on function public.fn_calendar_seat_facts(text) from public, anon, authenticated;

create or replace function public.fn_ceo_calendar_horizon()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare c record; v_seat text; v_h int; v_days int; v_plan bigint; v_dir bigint; v_hid bigint; v_q text; v_brief text;
        n_orders int := 0; n_asked int := 0; v_owners jsonb;
begin
  v_owners := public.fn_ceo_calendar_owner_ask(12);
  for c in
    select cc.*, coalesce(case when cc.starts_on >= current_date then cc.starts_on end, cc.next_on) occurs
      from public.company_calendar cc
     where coalesce(case when cc.starts_on >= current_date then cc.starts_on end, cc.next_on) between current_date and current_date + 90
     order by 2
  loop
    v_days := c.occurs - current_date;
    v_h := case when v_days <= 30 then 30 when v_days <= 60 then 60 else 90 end;     -- the nearest horizon crossed, only
    foreach v_seat in array (array[coalesce(c.owner_seat, 'ceo')] || coalesce(c.also_seats, '{}')) loop
      continue when not exists (select 1 from public.org_role o where o.role_id = v_seat and o.status = 'active');
      continue when exists (select 1 from public.company_calendar_plan p
                             where p.calendar_id = c.id and p.seat = v_seat and p.occurs_on = c.occurs and p.horizon_days <= v_h);
      insert into public.company_calendar_plan (calendar_id, seat, horizon_days, occurs_on)
      values (c.id, v_seat, v_h, c.occurs)
      on conflict (calendar_id, seat, horizon_days, occurs_on) do nothing
      returning id into v_plan;
      continue when v_plan is null;
      select b.brief into v_brief from public.company_calendar_brief b where b.calendar_id = c.id and b.seat = v_seat;
      v_dir := public.fn_ceo_directive_issue(v_seat, 'register_review', 'calendar:' || c.id || ':' || c.occurs || ':' || v_h,
        left(format('Company calendar, %s days ahead: "%s" falls on %s. The calendar says: %s Decide what you do about it and record your plan (or that no action is needed).',
                    v_days, c.event_name, to_char(c.occurs, 'DD Mon YYYY'), coalesce(c.action, '(no action text)')), 2000),
        'the seat''s plan or no-action for this entry and horizon is recorded in company_calendar_plan.',
        format($q$exists (select 1 from public.company_calendar_plan where id = %s and status <> 'asked')$q$, v_plan),
        least(c.occurs::timestamptz, now() + interval '7 days'),
        jsonb_build_object('register', 'company_calendar', 'calendar_id', c.id, 'occurs_on', c.occurs, 'horizon_days', v_h, 'plan_id', v_plan));
      v_q := format('Company calendar: "%s" on %s, %s days from today. The calendar says: %s As the %s seat, what do you do about it in the next %s days? '
                    || 'Decide plan or no_action. A plan names the concrete steps with dates, what you will produce, who must decide anything '
                    || 'you cannot, and how you will know it worked. Stay inside the rules in your facts.',
                    c.event_name, to_char(c.occurs, 'DD Mon YYYY'), v_days, coalesce(c.action, '(no action text)'), v_seat, v_days);
      v_hid := public.fn_reason_hold(v_seat, v_seat || '.calendar_plan', v_q,
        jsonb_build_object('seat', v_seat, 'surface', v_seat || '.calendar_plan', 'research', false, 'stakes', 'normal', 'question', v_q,
          'context', jsonb_build_object('audience', 'internal', 'case', jsonb_build_object(
            'entry', jsonb_build_object('id', c.id, 'event', c.event_name, 'kind', c.kind, 'on', c.occurs, 'ends_on', c.ends_on,
                                        'approximate', c.approximate, 'affects', c.affects, 'action', c.action, 'source', c.source_url),
            'your_brief', v_brief, 'owner_seat', coalesce(c.owner_seat, 'ceo'), 'also_seats', c.also_seats,
            'facts', public.fn_calendar_seat_facts(v_seat))),
          'decision', jsonb_build_object('name', 'calendar_plan', 'options', jsonb_build_array(
            jsonb_build_object('id', 'plan', 'meaning', 'this seat acts on the entry: the answer is the plan'),
            jsonb_build_object('id', 'no_action', 'meaning', 'nothing for this seat to do: the answer says why'))),
          'subject', jsonb_build_object('calendar_plan_id', v_plan), 'dedupeKey', 'calendar_plan:' || v_plan),
        jsonb_build_object('filed_by', 'ceo.calendar_horizon'), jsonb_build_object('calendar_plan_id', v_plan),
        'seat_duty', 'calendar_plan:' || v_plan);
      update public.company_calendar_plan set held_id = v_hid, directive_id = v_dir where id = v_plan;
      n_orders := n_orders + (v_dir is not null)::int;
      n_asked := n_asked + (v_hid is not null)::int;
    end loop;
  end loop;
  return jsonb_build_object('owners', v_owners, 'orders', n_orders, 'asked', n_asked,
    'rows_without_owner', (select count(*) from public.company_calendar where owner_seat is null),
    'plans_waiting', (select count(*) from public.company_calendar_plan where status = 'asked'));
end $fn$;
revoke execute on function public.fn_ceo_calendar_horizon() from public, anon, authenticated;

create or replace function public.fn_calendar_plan_apply(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_plan bigint; v_choice text := p_result->'decision'->>'choice';
        v_ans text := btrim(coalesce(p_result->>'answer', ''));
begin
  select * into r from public.reasoning_held_question where id = p_id;
  v_plan := nullif(r.subject->>'calendar_plan_id', '')::bigint;
  if v_plan is null or v_choice is null or v_choice not in ('plan', 'no_action') or v_ans = '' then
    return null;                                   -- stays 'reasoned' for the seat to read; the order stays open
  end if;
  update public.company_calendar_plan
     set status = case v_choice when 'plan' then 'planned' else 'no_action' end, plan = left(v_ans, 6000),
         decided_at = now(), decided_by = r.seat || '.calendar_plan (' || coalesce(p_result->>'model', 'model') || ')'
   where id = v_plan and seat = r.seat and status = 'asked';
  return jsonb_build_object('calendar_plan_id', v_plan, 'status', v_choice, 'recorded', found);
end $fn$;
revoke execute on function public.fn_calendar_plan_apply(bigint, jsonb) from public, anon, authenticated;

-- the surface each seat's answer comes back on (fn_reason_held_resolve calls fn_reason_apply_<seat>__<surface>)
create or replace function public.fn_reason_apply_ceo__calendar_plan(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_calendar_plan_apply(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_ceo__calendar_plan(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_marketing__calendar_plan(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_calendar_plan_apply(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_marketing__calendar_plan(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_sales_engineer__calendar_plan(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_calendar_plan_apply(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_sales_engineer__calendar_plan(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_accountant__calendar_plan(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_calendar_plan_apply(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_accountant__calendar_plan(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_customer_support__calendar_plan(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_calendar_plan_apply(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_customer_support__calendar_plan(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_it_engineer__calendar_plan(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_calendar_plan_apply(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_it_engineer__calendar_plan(bigint, jsonb) from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file)
values ('ceo.calendar_horizon', 'ceo', interval '1 day', 'fn_ceo_calendar_horizon',
        'Every company calendar entry has a live seat (the CEO seat''s model reads each row against the live seats); each seat gets its entries falling in the next 90, 60 and 30 days as an order and a question to its model, which records a plan or no action.',
        'scripts/sql/every_calendar_entry_has_a_live_seat_that_plans_it_thirty_sixty_and_ninety_days_ahead.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

-- VERDICT (this file defines routines, so it never raises to report)
select case
  when to_regclass('public.company_calendar_plan') is null then 'PROBE FAILED: no company_calendar_plan'
  when not exists (select 1 from public.table_export_registry where table_name = 'company_calendar_plan' and exported)
    then 'PROBE FAILED: company_calendar_plan is not exported'
  when has_function_privilege('anon', 'public.fn_ceo_calendar_horizon()', 'execute')
    or has_function_privilege('anon', 'public.fn_calendar_plan_apply(bigint, jsonb)', 'execute')
    or has_function_privilege('anon', 'public.fn_reason_apply_ceo__calendar_owner(bigint, jsonb)', 'execute')
    or has_function_privilege('anon', 'public.fn_reason_apply_marketing__calendar_plan(bigint, jsonb)', 'execute')
    then 'PROBE FAILED: anon can execute a calendar routine'
  when exists (select 1 from public.company_calendar where id = 41 and event_name like 'Big 5 Global 2026%' and owner_seat is distinct from 'marketing')
    then 'PROBE FAILED: Big 5 Global has no seat'
  when not exists (select 1 from public.seat_duty where duty = 'ceo.calendar_horizon' and enabled)
    then 'PROBE FAILED: the calendar duty is not registered'
  else 'PROBE OK' end as verdict;
