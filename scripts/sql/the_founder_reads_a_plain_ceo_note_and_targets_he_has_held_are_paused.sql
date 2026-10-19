-- The founder reads a plain CEO note, and the targets he has held are paused (19 Oct 2026).
-- Assigned: ceo
--
-- MEASURED 19 Oct 2026 on production:
--   - CEO daily note of 18 Oct (notifications 101297) and the weekly review of 19 Oct (105207) read to the founder
--     as code: "Directive #293, due 21 Oct 10:00: RE-ISSUED ... Bring invitations_delivered back to its path: it
--     reads 0 against 644.5", "9 of 14 targets missed this week. Actions: 0 opened, 9 escalated, 0 closed." He said
--     they make no sense to him.
--   - app_secrets.invite_enabled = 'false': the supplier campaign is off by his decision until he says the platform
--     is ready. Yet invitations_delivered, registrations_submitted and registrations_verified_cumulative graded
--     'miss' every day, directives 293/294/295 were re-issued after each deadline, and the weekly "suppliers per
--     category" target opened actions - all for work he deliberately stopped.
--
-- WHAT THIS CHANGES
--   1. public.founder_hold: a register of what the founder has deliberately held, in his words, with the targets
--      that depend on it and the switch that lifts it (supplier_campaign -> app_secrets.invite_enabled = 'true').
--      fn_held_targets() answers the targets held right now; a hold lifts by itself when its switch flips.
--      public.target_label: each target in plain words.
--   2. A held target is 'paused', never 'miss': fn_ceo_target_daily_verdict grades it paused (and closes its
--      open miss task), fn_ceo_year_plan_status reports it paused, fn_ceo_directive_run closes open target
--      directives on it as 'paused' and issues none, fn_ceo_weekly_review opens no action on it and closes open ones.
--   3. The founder's text: the daily note and the weekly email are short notes, one line each for what happened,
--      why, and what is being done, plus one line naming what is paused by his decision. No directive ids, no metric
--      codes, no counts. The weekly PDF (fn_ceo_weekly_review_pdf_blocks) is rewritten the same way.
--
-- WHAT THIS DOES NOT CHANGE: the targets themselves, the year-one contract, how a target is measured, the seat
-- audit directives, or the internal records (ceo_day.priorities, ceo_task, ceo_directive keep their detail).
-- Prevented by: scripts/checks/the_founder_reads_a_plain_ceo_note_and_held_targets_are_paused.test.mjs

-- == 1. THE HOLD REGISTER =============================================================================
create table if not exists public.founder_hold (
  hold_key            text primary key,
  what_is_held        text not null check (btrim(what_is_held) <> ''),   -- plain words, as the founder would say it
  until_when          text not null check (btrim(until_when) <> ''),
  target_keys         text[] not null default '{}',                      -- targets that cannot move while it is held
  flag_key            text,                                              -- app_secrets key that lifts the hold ...
  flag_released_value text,                                              -- ... when it reads this value
  released_at         timestamptz,
  recorded_at         timestamptz not null default now(),
  note                text);
comment on table public.founder_hold is
  'What the founder has deliberately held. A target in target_keys is paused, never a miss, while the hold is active '
  '(released_at is null and the flag, if any, does not read its released value). Read through fn_held_targets().';
alter table public.founder_hold enable row level security;
drop policy if exists founder_hold_service_role_only on public.founder_hold;
create policy founder_hold_service_role_only on public.founder_hold as permissive for all to public using (false) with check (false);
revoke all on public.founder_hold from anon, authenticated;

insert into public.founder_hold (hold_key, what_is_held, until_when, target_keys, flag_key, flag_released_value, note)
values ('supplier_campaign', 'the supplier campaign is off', 'until you say the platform is ready',
        array['invitations_delivered', 'registrations_submitted', 'registrations_verified_cumulative',
              'verified_suppliers_milestone', 'supply'],
        'invite_enabled', 'true',
        '19 Oct 2026: invite_enabled is false; supplier recruitment targets cannot move while no invitation is sent.')
on conflict (hold_key) do nothing;

create table if not exists public.target_label (
  target_key text primary key,
  words      text not null check (btrim(words) <> ''));
comment on table public.target_label is 'Each CEO target in the words the founder reads. Founder-facing text uses these, never the key.';
alter table public.target_label enable row level security;
drop policy if exists target_label_service_role_only on public.target_label;
create policy target_label_service_role_only on public.target_label as permissive for all to public using (false) with check (false);
revoke all on public.target_label from anon, authenticated;

insert into public.target_label (target_key, words) values
  ('invitations_delivered', 'supplier invitations sent'), ('registrations_submitted', 'supplier sign-ups'),
  ('registrations_verified_cumulative', 'verified suppliers'), ('verified_suppliers_milestone', 'the verified-supplier milestone'),
  ('supply', 'suppliers in every category'), ('duties_on_clock_pct', 'routine checks finishing on time'),
  ('it_findings_open', 'open technical issues'), ('costs_aed', 'monthly costs'), ('fee_aed', 'fees earned this month'),
  ('fee_aed_cumulative', 'fees earned to date'), ('bounce_pct_7d', 'emails bouncing'), ('checkout_success_pct', 'payments going through'),
  ('uptime_pct', 'the site staying up'), ('b2b_active_accounts', 'active business accounts'), ('inquiries_posted', 'customer requests'),
  ('quote_coverage_pct', 'requests that get quotes'), ('quotes_received', 'quotes received'), ('reveals_paid', 'paid supplier reveals'),
  ('reveal_conversion_pct', 'quotes turned into paid reveals'), ('findings', 'issues open more than a week'),
  ('risks', 'risks without a plan'), ('budget', 'the expense budget'), ('runway', 'cash and runway')
on conflict (target_key) do nothing;

create or replace function public.fn_held_targets()
 returns table (target_key text, hold_key text, what_is_held text, until_when text)
 language sql stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  select k, h.hold_key, h.what_is_held, h.until_when
    from public.founder_hold h cross join lateral unnest(h.target_keys) k
   where h.released_at is null
     and (h.flag_key is null
          or (select s.value from public.app_secrets s where s.key = h.flag_key) is distinct from h.flag_released_value)
$function$;
revoke execute on function public.fn_held_targets() from public, anon, authenticated;

create or replace function public.fn_target_words(p_key text)
 returns text language sql stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  select coalesce((select words from public.target_label where target_key = p_key), replace(p_key, '_', ' '))
$function$;
revoke execute on function public.fn_target_words(text) from public, anon, authenticated;

create or replace function public.fn_seat_words(p_seat text)
 returns text language sql immutable
 set search_path to 'public', 'pg_temp'
as $function$
  select case p_seat when 'accountant' then 'finance' when 'customer_support' then 'customer support'
                     when 'it_engineer' then 'IT' when 'sales_engineer' then 'sales' when 'marketing' then 'marketing'
                     when 'ceo' then 'the CEO office' else replace(p_seat, '_', ' ') end
$function$;
revoke execute on function public.fn_seat_words(text) from public, anon, authenticated;

-- One line on what is paused by his decision, or null when nothing is held.
create or replace function public.fn_founder_hold_line()
 returns text language sql stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  select string_agg(x.what_is_held || ' ' || x.until_when || ', so ' || x.words
                    || ' are paused. They are not counted as misses and nobody is chased for them.', E'\n')
    from (select h.hold_key, h.what_is_held, h.until_when,
                 regexp_replace(string_agg(distinct public.fn_target_words(h.target_key), ', '), ', ([^,]*)$', ' and \1') words
            from public.fn_held_targets() h group by h.hold_key, h.what_is_held, h.until_when) x
$function$;
revoke execute on function public.fn_founder_hold_line() from public, anon, authenticated;

alter table public.target_daily_verdict drop constraint if exists target_daily_verdict_status_check;
alter table public.target_daily_verdict add constraint target_daily_verdict_status_check check (status = any (array[
  'on_track', 'within_tolerance', 'miss', 'not_measurable', 'no_target', 'too_early', 'not_yet_due', 'paused']));
alter table public.ceo_directive drop constraint if exists ceo_directive_status_check;
alter table public.ceo_directive add constraint ceo_directive_status_check check (status = any (array[
  'open', 'met', 'escalated', 'missed', 'paused']));

-- == 2. A HELD TARGET IS PAUSED, NEVER A MISS =========================================================
CREATE OR REPLACE FUNCTION public.fn_ceo_year_plan_status(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with c as (select id from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30' and status = 'active'),
       m as (select date_trunc('month', p_at at time zone 'Asia/Dubai')::date as m0),
       h as (select distinct on (target_key) target_key, what_is_held from public.fn_held_targets())
  select jsonb_build_object('month', (select m0 from m),
    'plan', (select to_jsonb(y) from public.ceo_year_plan y, m where y.month = m.m0),
    'metrics', coalesce((select jsonb_agg(jsonb_build_object('metric', p.metric_key, 'owner_seat', p.owner_seat, 'kind', p.kind,
                 'direction', p.direction, 'month_target', p.value, 'day', v.day, 'expected', v.expected, 'actual', v.actual,
                 'gap_pct', v.gap_pct, 'status', case when h.target_key is not null then 'paused' else v.status end,
                 'paused_because', h.what_is_held) order by p.owner_seat, p.metric_key)
        from public.target_path p join c on c.id = p.contract_id cross join m
        left join h on h.target_key = p.metric_key
        left join lateral (select * from public.target_daily_verdict d where d.contract_id = p.contract_id and d.metric_key = p.metric_key
                            and d.day <= (p_at at time zone 'Asia/Dubai')::date order by d.day desc limit 1) v on true
       where p.month = m.m0), '[]'::jsonb))
$function$;

CREATE OR REPLACE FUNCTION public.fn_ceo_target_daily_verdict(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_local timestamp := p_at at time zone 'Asia/Dubai'; v_day date := v_local::date;
  v_m0 date := date_trunc('month', v_local)::date; v_from timestamptz := v_m0::timestamp at time zone 'Asia/Dubai';
  v_frac numeric := extract(day from v_local) / extract(day from (date_trunc('month', v_local) + interval '1 month - 1 day'));
  p record; v_exp numeric; v_act numeric; v_gap numeric; v_status text; v_task bigint; v_hid bigint; v_prev_cum numeric;
  n_miss int := 0; n_new int := 0; n_closed int := 0; v_out jsonb := '[]'::jsonb; c_id bigint;
  v_pm date; v_launch date; m_next record; m_prev record;
  v_held text[] := array(select target_key from public.fn_held_targets());   -- 19 Oct 2026: held by the founder = paused
  c_customer constant text[] := array['inquiries_posted', 'quotes_received', 'quote_coverage_pct', 'reveals_paid',
    'b2b_active_accounts', 'fee_aed', 'fee_aed_cumulative', 'checkout_success_pct', 'reveal_conversion_pct'];
begin
  select id into c_id from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30' and status = 'active';
  if c_id is null then raise exception 'ceo.target_verdict: the year-one plan contract is not active'; end if;

  v_pm := coalesce((select max(month) from public.target_path where contract_id = c_id and month = v_m0),
                   (select min(month) from public.target_path where contract_id = c_id and month > v_m0));
  v_launch := (select min(month) from public.ceo_year_plan where requests > 0);
  select * into m_next from public.ceo_year_plan_milestone where due > v_day order by due limit 1;
  if m_next is null then select * into m_next from public.ceo_year_plan_milestone order by due desc limit 1; end if;
  select * into m_prev from public.ceo_year_plan_milestone where due < m_next.due order by due desc limit 1;

  for p in
    select t.metric_key, t.owner_seat, t.kind, t.direction, t.value, t.tolerance_pct from public.target_path t
     where t.contract_id = c_id and t.month = v_pm
    union all
    select 'verified_suppliers_milestone', 'sales_engineer', 'milestone', 'min', m_next.verified, 20 where m_next.due is not null
    order by 1
  loop
    if p.kind = 'milestone' then
      v_act := public.fn_ambition_measure('registrations_verified_cumulative', v_from, p_at);
      v_exp := case when m_prev.due is null or v_day >= m_next.due then m_next.verified
                    else round(m_prev.verified + (m_next.verified - m_prev.verified)
                               * (v_day - m_prev.due)::numeric / (m_next.due - m_prev.due), 1) end;
    else
      v_act := public.fn_ambition_measure(p.metric_key, v_from, p_at);
      if p.kind = 'cumulative' then
        select coalesce(max(value), 0) into v_prev_cum from public.target_path where contract_id = c_id and metric_key = p.metric_key and month < v_pm;
        v_exp := round(v_prev_cum + (p.value - v_prev_cum) * v_frac, 1);
      elsif p.kind = 'month' and p.direction = 'min' then v_exp := round(p.value * v_frac, 1);
      else v_exp := p.value; end if;
    end if;

    v_gap := case when v_exp > 0 and v_act is not null then round(100.0 * (v_act - v_exp) / v_exp, 1) end;
    v_status := case when p.kind <> 'milestone' and v_pm <> v_m0 then 'not_yet_due'
                     when p.metric_key = any (c_customer) and (v_launch is null or v_m0 < v_launch) then 'not_yet_due'
                     when p.metric_key = any (v_held) then 'paused'
                     when p.direction = 'max' then
                       case when v_act is null then 'not_measurable'
                            when v_act <= v_exp then 'on_track'
                            when v_gap <= p.tolerance_pct then 'within_tolerance'
                            else 'miss' end
                     when p.kind in ('month', 'cumulative') and extract(day from v_local) < 7 then 'too_early'
                     when v_exp is null or v_exp <= 0 then 'no_target'
                     when v_act is null then 'not_measurable'
                     when v_act >= v_exp then 'on_track'
                     when -v_gap <= p.tolerance_pct then 'within_tolerance'
                     else 'miss' end;

    select t.task_id into v_task from public.target_daily_verdict d join public.ceo_task t on t.task_id = d.task_id
     where d.contract_id = c_id and d.metric_key = p.metric_key and d.day >= v_m0 and d.day <= v_day
       and t.state in ('open', 'working', 'blocked') order by d.day desc limit 1;
    v_hid := null;
    if v_status = 'miss' then
      n_miss := n_miss + 1;
      if v_task is null then
        v_task := public.fn_ceo_task_open(format('Target miss: %s (%s) %s', p.metric_key, p.owner_seat, to_char(v_m0, 'Mon YYYY')),
          format(E'On %s %s read %s against %s (%s) on the founder''s year-one path (%s%% gap, tolerance %s%%).\nOwner: %s. The root-cause question went to the owner; this task closes when the measure is back within tolerance.',
                 v_day, p.metric_key, v_act, v_exp, case when p.direction = 'max' then 'the month''s ceiling' else 'expected by today' end,
                 v_gap, p.tolerance_pct, p.owner_seat));
        n_new := n_new + 1;
        if p.owner_seat = 'ceo' then
          perform public.fn_ceo_root_cause_ask('ceo', v_task, jsonb_build_object('metric', p.metric_key, 'day', v_day, 'expected', v_exp,
                                               'actual', v_act, 'gap_pct', v_gap, 'tolerance_pct', p.tolerance_pct, 'month_target', p.value));
        else
          v_hid := public.fn_seat_handoff('ceo', p.owner_seat, 'ceo.root_cause', 'ceo_task', v_task::text,
            jsonb_build_object('task_id', v_task, 'metric', p.metric_key, 'day', v_day, 'expected', v_exp, 'actual', v_act,
                               'gap_pct', v_gap, 'tolerance_pct', p.tolerance_pct, 'month_target', p.value));
        end if;
      end if;
    elsif v_task is not null and v_status = 'paused' then
      update public.ceo_task set state = 'done', closed_at = now(),
             evidence = format('Paused on %s: the founder has held the work %s depends on (founder_hold); not a miss.', v_day, p.metric_key)
       where task_id = v_task;
      n_closed := n_closed + 1; v_task := null;
    elsif v_task is not null and v_status in ('on_track', 'within_tolerance') then
      update public.ceo_task set state = 'done', closed_at = now(),
             evidence = format('Recovered on %s: %s read %s against %s expected (%s).', v_day, p.metric_key, v_act, v_exp, v_status)
       where task_id = v_task;
      n_closed := n_closed + 1; v_task := null;
    elsif v_task is not null and v_status = 'not_measurable' then
      update public.ceo_task set state = 'blocked',
             blocked_reason = format('On %s %s became not measurable (under 20 in its denominator); the miss is neither confirmed nor cleared.', v_day, p.metric_key)
       where task_id = v_task and state <> 'blocked';
    end if;

    insert into public.target_daily_verdict (day, contract_id, metric_key, owner_seat, expected, actual, gap_pct, status, task_id, handoff_id)
    values (v_day, c_id, p.metric_key, p.owner_seat, v_exp, v_act, v_gap, v_status, case when v_status = 'miss' then v_task end, v_hid)
    on conflict (day, contract_id, metric_key) do update set expected = excluded.expected, actual = excluded.actual, gap_pct = excluded.gap_pct,
      status = excluded.status, task_id = coalesce(target_daily_verdict.task_id, excluded.task_id),
      handoff_id = coalesce(target_daily_verdict.handoff_id, excluded.handoff_id);
    v_out := v_out || jsonb_build_object('metric', p.metric_key, 'status', v_status, 'expected', v_exp, 'actual', v_act);
  end loop;

  if jsonb_array_length(v_out) = 0 then raise exception 'ceo.target_verdict: no plan metric graded on %', v_day; end if;
  return jsonb_build_object('day', v_day, 'contract_id', c_id, 'plan_month', v_pm, 'customers_launch', v_launch,
                            'milestone', jsonb_build_object('due', m_next.due, 'verified', m_next.verified),
                            'metrics', v_out, 'misses', n_miss, 'tasks_opened', n_new, 'tasks_closed', n_closed);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_ceo_directive_run(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; d public.ceo_directive; v bigint; v_ok boolean; v_err text; v_new bigint; v_dec bigint; v_task bigint;
  n_issued int := 0; n_met int := 0; n_esc int := 0; n_missed int := 0; n_paused int := 0; v_q date; v_hold text;
  v_late text := $q$exists (select 1 from public.agent_actions a
      join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
     where a.kind = 'handoff' and a.agent = %1$L and a.status = 'pending' and public.fn_handoff_is_late(a.detail, a.created_at, k.reply_within))$q$;
begin
  -- 1. target misses on the year-one plan (a target the founder has held reads 'paused', never 'miss')
  for r in select e->>'metric' as metric, e->>'owner_seat' as seat, e->>'actual' as actual, e->>'expected' as expected
             from jsonb_array_elements(coalesce(public.fn_ceo_year_plan_status(p_at)->'metrics', '[]'::jsonb)) e
            where e->>'status' = 'miss' and e->>'owner_seat' is not null loop
    v := public.fn_ceo_directive_issue(r.seat, 'target_miss', r.metric || ':' || to_char(p_at at time zone 'Asia/Dubai', 'YYYY-MM'),
      format('Bring %s back to its path: it reads %s against %s. Name the step that is not converting and change that step.', r.metric, coalesce(r.actual, '?'), r.expected),
      format('%s is no longer a miss on the year-one plan.', r.metric),
      format($q$not exists (select 1 from jsonb_array_elements(coalesce(public.fn_ceo_year_plan_status(now())->'metrics', '[]'::jsonb)) e where e->>'metric' = %L and e->>'status' = 'miss')$q$, r.metric),
      p_at + interval '7 days', jsonb_build_object('metric', r.metric, 'actual', r.actual, 'expected', r.expected));
    n_issued := n_issued + (v is not null)::int;
  end loop;

  -- 2. late deliverables: the month marketing plan
  for r in select i.id, (i.evidence->>'plan_month')::date as m, (i.evidence->>'deadline')::date as due_was, (i.evidence->>'due_on')::date as due_on
             from public.ceo_improvement i where i.source_kind = 'marketing_plan_late' and i.status in ('open', 'assigned') loop
    v := public.fn_ceo_directive_issue('marketing', 'late_deliverable', 'marketing_month_plan:' || r.m,
      format('Send the CEO the marketing plan for %s. It was due on %s; the month does not start unplanned.', to_char(r.m, 'FMMonth YYYY'), to_char(r.due_was, 'DD Mon')),
      format('marketing_month_plan for %s exists and has left draft, or improvement #%s is closed.', r.m, r.id),
      format($q$exists (select 1 from public.marketing_month_plan p where p.month = %L::date and p.status <> 'draft') or exists (select 1 from public.ceo_improvement i where i.id = %s and i.status = 'done')$q$, r.m, r.id),
      greatest(coalesce(r.due_on::timestamp at time zone 'Asia/Dubai', p_at), p_at) + interval '1 day',
      jsonb_build_object('improvement_id', r.id, 'plan_month', r.m, 'due_was', r.due_was));
    n_issued := n_issued + (v is not null)::int;
  end loop;

  -- 3. stuck handoffs
  for r in select a.id, a.agent as seat, a.detail->>'type' as type, a.detail->>'from' as from_seat, a.created_at
             from public.agent_actions a
             left join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'replied_at' is null
              and a.created_at < p_at - coalesce(k.reply_within * 2, interval '1 day') loop
    v := public.fn_ceo_directive_issue(r.seat, 'stuck_handoff', 'agent_actions:' || r.id,
      format('Answer handoff #%s (%s from %s), waiting since %s.', r.id, r.type, r.from_seat, to_char(r.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI')),
      format('handoff #%s is answered (replied_at set) or no longer pending.', r.id),
      format($q$exists (select 1 from public.agent_actions a where a.id = %s and (a.status <> 'pending' or a.detail ? 'replied_at'))$q$, r.id),
      p_at + interval '1 day', jsonb_build_object('handoff_id', r.id, 'type', r.type, 'from', r.from_seat, 'since', r.created_at));
    n_issued := n_issued + (v is not null)::int;
  end loop;

  -- 4. the latest seat audit's below-bar seats
  select max(quarter) into v_q from public.ceo_seat_audit;
  for r in select a.seat, a.shortfalls, a.improvement_id from public.ceo_seat_audit a where a.quarter = v_q and a.below_bar loop
    v := public.fn_ceo_directive_issue(r.seat, 'seat_audit', v_q || ':' || r.seat,
      format('Get back to the senior bar found short in the audit of the quarter starting %s: %s.', to_char(v_q, 'DD Mon YYYY'), array_to_string(r.shortfalls, '; ')),
      'no handoff to the seat is open past its reply window, and none of its duties is failing or overdue.',
      format('not ' || v_late || $q$ and not exists (select 1 from jsonb_array_elements(public.fn_seat_duty_health()) h where h->>'owner_seat' = %1$L)$q$, r.seat),
      p_at + interval '14 days', jsonb_build_object('quarter', v_q, 'improvement_id', r.improvement_id, 'shortfalls', r.shortfalls));
    n_issued := n_issued + (v is not null)::int;
  end loop;

  -- the close loop: each open directive is re-checked on its own predicate
  for d in select * from public.ceo_directive where status = 'open' order by id loop
    -- 19 Oct 2026: a target directive on work the founder has held is paused - not met, not re-issued.
    v_hold := null;
    if d.source_kind = 'target_miss' then
      select h.hold_key into v_hold from public.fn_held_targets() h where h.target_key = d.evidence->>'metric' limit 1;
    end if;
    if v_hold is not null then
      update public.ceo_directive set status = 'paused', closed_at = p_at,
             evidence = evidence || jsonb_build_object('paused', jsonb_build_object('checked_at', p_at, 'founder_hold', v_hold))
       where id = d.id;
      n_paused := n_paused + 1; continue;
    end if;
    v_err := null;
    begin
      execute 'select coalesce((' || d.done_sql || ')::boolean, false)' into v_ok;
    exception when others then v_ok := false; v_err := left(sqlerrm, 300);
    end;
    if v_ok then
      update public.ceo_directive set status = 'met', closed_at = p_at,
             evidence = evidence || jsonb_build_object('closed', jsonb_build_object('checked_at', p_at, 'predicate', d.done_sql, 'result', true))
       where id = d.id;
      n_met := n_met + 1;
    elsif p_at > d.deadline and d.escalated_from is null then
      update public.ceo_directive set status = 'escalated', closed_at = p_at,
             evidence = evidence || jsonb_build_object('escalated', jsonb_build_object('checked_at', p_at, 'result', false, 'error', v_err))
       where id = d.id;
      insert into public.ceo_directive (seat, source_kind, source_ref, instruction, done_when, done_sql, deadline, escalated_from, evidence)
      values (d.seat, d.source_kind, d.source_ref, 'RE-ISSUED after the deadline of ' || to_char(d.deadline at time zone 'Asia/Dubai', 'DD Mon') || ' passed: ' || d.instruction,
              d.done_when, d.done_sql, p_at + (d.deadline - d.issued_at), d.id, d.evidence)
      returning id into v_new;
      insert into public.ceo_decision_log (decision_key, the_decision, evidence, reading_before, outcome, dedupe_key)
      values ('directive_escalation',
              format('Directive #%s to %s passed its deadline unmet; re-issued once as #%s, due %s.', d.id, d.seat, v_new,
                     to_char((p_at + (d.deadline - d.issued_at)) at time zone 'Asia/Dubai', 'DD Mon')),
              jsonb_build_object('directive_id', d.id, 'reissue_id', v_new, 'seat', d.seat, 'done_when', d.done_when, 'deadline', d.deadline, 'predicate_error', v_err),
              'done-condition false at ' || p_at, 'decided', 'ceo_directive_escalation:' || d.id)
      on conflict do nothing returning id into v_dec;
      update public.ceo_directive set evidence = evidence || jsonb_build_object('decision_log_id', v_dec) where id = d.id;
      n_esc := n_esc + 1;
    elsif p_at > d.deadline then
      v_task := public.fn_ceo_task_open(format('Directive #%s to %s missed after re-issue', d.id, d.seat),
        format(E'%s\nDone when: %s\nFirst issued as #%s. The CEO decides the next step itself; it is not re-issued again.', d.instruction, d.done_when, d.escalated_from));
      update public.ceo_directive set status = 'missed', closed_at = p_at,
             evidence = evidence || jsonb_build_object('missed', jsonb_build_object('checked_at', p_at, 'result', false, 'error', v_err, 'task_id', v_task))
       where id = d.id;
      n_missed := n_missed + 1;
    end if;
  end loop;

  return jsonb_build_object('issued', n_issued, 'met', n_met, 'escalated', n_esc, 'missed', n_missed, 'paused', n_paused,
    'open', (select count(*) from public.ceo_directive where status = 'open'));
end $function$;

-- == 3. THE DAILY NOTE, IN WORDS ======================================================================
CREATE OR REPLACE FUNCTION public.fn_ceo_daily_run(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_day date := (p_at at time zone 'Asia/Dubai')::date; v_m0 date := date_trunc('month', p_at at time zone 'Asia/Dubai')::date;
  v_from timestamptz := v_m0::timestamp at time zone 'Asia/Dubai';
  v_verdict jsonb; v_status jsonb; h record; n_stuck_new int := 0; v_stuck jsonb := '[]'::jsonb; v_prio jsonb := '{}'::jsonb;
  v_signals jsonb; v_matters text[] := '{}'; v_lines text[] := '{}'; v_note bigint; s text; v_m jsonb; v_first text; v_task bigint;
  v_body text; v_dir jsonb; v_d public.ceo_directive; v_behind text; v_hold text;
begin
  v_verdict := public.fn_ceo_target_daily_verdict(p_at);
  v_status := public.fn_ceo_year_plan_status(p_at);

  for h in select a.id, a.agent, a.detail->>'type' as type, a.detail->>'from' as from_seat, a.created_at
             from public.agent_actions a
             left join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'replied_at' is null
              and a.created_at < p_at - coalesce(k.reply_within * 2, interval '1 day') loop
    v_stuck := v_stuck || jsonb_build_object('handoff_id', h.id, 'seat', h.agent, 'type', h.type, 'from', h.from_seat, 'since', h.created_at);
    if not exists (select 1 from public.ceo_task where title = format('Stuck handoff #%s', h.id)) then
      v_task := public.fn_ceo_task_open(format('Stuck handoff #%s', h.id),
        format(E'%s from %s to %s has waited since %s with no answer. The CEO re-runs it (fn_seat_handoff_act) and, if it fails again, the failure is on this task.',
               h.type, h.from_seat, h.agent, h.created_at));
      begin
        perform public.fn_seat_handoff_act(h.id);
        update public.ceo_task set state = 'done', closed_at = now(), evidence = 'Re-run on ' || v_day || ': the seat answered.'
         where task_id = v_task and exists (select 1 from public.agent_actions where id = h.id and (status = 'done' or detail ? 'replied_at'));
      exception when others then
        update public.ceo_task set state = 'blocked', blocked_reason = left('Re-run failed: ' || sqlerrm, 1000) where task_id = v_task;
      end;
      n_stuck_new := n_stuck_new + 1;
    end if;
  end loop;

  v_signals := jsonb_build_object(
    'stranded_registrations', public.fn_ceo_plan_measure('stranded_submissions', p_at - interval '1 day', p_at),
    'bounce_pct_7d', public.fn_ceo_plan_measure('bounce_pct_7d', p_at - interval '7 days', p_at),
    'requests_unquoted_3d', (select count(*) from public.inquiries i join public.customers c on c.id = i.customer_id
                               where i.parent_inquiry_id is null and i.created_at < p_at - interval '3 days' and i.created_at > p_at - interval '30 days'
                                 and not exists (select 1 from public.quotes q where q.inquiry_id = i.id)
                                 and coalesce(i.provenance->>'source', '') not in ('demo_factory', 'e2e')
                                 and not (coalesce(c.is_demo, false) or coalesce(c.full_name, '') ilike 'ZZ DEMO%' or coalesce(c.email, '') ilike '%@example.invalid')),
    'findings_open', (select count(*) from public.it_engineer_finding where closed_at is null),
    'findings_new_today', (select count(*) from public.it_engineer_finding where closed_at is null and started_at > p_at - interval '1 day'),
    'fee_month_aed', public.fn_ambition_measure('fee_aed', v_from, p_at),
    'costs_month_aed', public.fn_ambition_measure('costs_aed', v_from, p_at),
    'cost_ceiling_month_aed', (select cost_ceiling_aed from public.ceo_year_plan where month = v_m0),
    'stale_tasks', (select count(*) from public.ceo_task where state in ('open', 'working', 'blocked') and created_at < p_at - interval '14 days'));

  v_dir := public.fn_ceo_directive_run(p_at);

  -- the day's priorities per seat (internal record: ceo_day.priorities keeps the directive detail)
  foreach s in array array['sales_engineer', 'customer_support', 'marketing', 'accountant', 'it_engineer'] loop
    select e into v_m from jsonb_array_elements(v_status->'metrics') e
     where e->>'owner_seat' = s and e->>'status' in ('miss', 'within_tolerance')
     order by (e->>'status' = 'miss') desc, abs(coalesce((e->>'gap_pct')::numeric, 0)) desc limit 1;
    v_d := null;
    select * into v_d from public.ceo_directive d where d.seat = s and d.status = 'open' order by d.deadline, d.id limit 1;
    v_first := case
      when v_d.id is not null then format('Directive #%s, due %s: %s Done when %s', v_d.id,
        to_char(v_d.deadline at time zone 'Asia/Dubai', 'DD Mon HH24:MI'), v_d.instruction, v_d.done_when)
      when v_m is not null then format('Recover %s: %s against %s today (%s).', v_m->>'metric', coalesce(v_m->>'actual', '?'), v_m->>'expected', v_m->>'status')
      when exists (select 1 from jsonb_array_elements(v_stuck) e where e->>'seat' = s) then 'Answer the handoffs waiting past their reply time.'
      when exists (select 1 from public.ceo_improvement i where i.seat = s and i.status = 'assigned') then
        (select format('Improvement #%s: %s', i.id, left(i.proposal, 300)) from public.ceo_improvement i
          where i.seat = s and i.status = 'assigned' order by i.id limit 1)
      else 'Hold the path: every target of the month is on track.' end;
    v_prio := v_prio || jsonb_build_object(s, jsonb_build_object('first', v_first,
      'misses', (select coalesce(jsonb_agg(e->>'metric'), '[]'::jsonb) from jsonb_array_elements(v_status->'metrics') e where e->>'owner_seat' = s and e->>'status' = 'miss'),
      'directive_id', v_d.id,
      'stuck_handoffs', (select count(*) from jsonb_array_elements(v_stuck) e where e->>'seat' = s),
      'improvements_open', (select count(*) from public.ceo_improvement i where i.seat = s and i.status in ('open', 'assigned'))));
  end loop;

  -- What matters enough for the founder: kept as before in ceo_day.matters (internal), and written to him as a
  -- short note - one line each for what happened, why, and what is being done. 19 Oct 2026: no ids, no codes, no counts.
  select regexp_replace(string_agg(distinct public.fn_target_words(e->>'metric'), ', '), ', ([^,]*)$', ' and \1')
    into v_behind from jsonb_array_elements(v_status->'metrics') e where e->>'status' = 'miss';
  if coalesce((v_verdict->>'tasks_opened')::int, 0) > 0 then
    v_matters := v_matters || format('%s target(s) fell behind the path today', v_verdict->>'tasks_opened');
    v_lines := v_lines || ('- What happened: we slipped behind plan on ' || coalesce(v_behind, 'one of our targets') || '.'
      || E'\n  Why: the step that feeds it is not working well enough yet.'
      || E'\n  What we are doing: the team that owns it has a deadline this week to find and fix that step, and I check it every morning.');
  end if;
  if n_stuck_new > 0 then
    v_matters := v_matters || format('%s handoff(s) were stuck and re-run', n_stuck_new);
    v_lines := v_lines || ('- What happened: some work passed between teams waited too long for an answer.'
      || E'\n  Why: the team receiving it did not reply in time.'
      || E'\n  What we are doing: I restarted each one today; anything still stuck stays on my list until it moves.');
  end if;
  if coalesce((v_signals->>'stranded_registrations')::numeric, 0) > 0 then
    v_matters := v_matters || format('%s supplier registration(s) waited over 24 hours', v_signals->>'stranded_registrations');
    v_lines := v_lines || ('- What happened: supplier sign-ups waited more than a day for review.'
      || E'\n  Why: reviews did not keep up.'
      || E'\n  What we are doing: the sales team reviews them first thing tomorrow and I follow up.');
  end if;
  if coalesce((v_signals->>'bounce_pct_7d')::numeric, 0) >= 5 then
    v_matters := v_matters || format('email bounces at %s %% over 7 days', v_signals->>'bounce_pct_7d');
    v_lines := v_lines || ('- What happened: too many of our emails bounced this week.'
      || E'\n  Why: some addresses on our lists are no longer valid.'
      || E'\n  What we are doing: sending slows down and bad addresses are removed before anything else goes out.');
  end if;
  if coalesce((v_signals->>'requests_unquoted_3d')::int, 0) > 0 then
    v_matters := v_matters || format('%s request(s) have no quote after 3 days', v_signals->>'requests_unquoted_3d');
    v_lines := v_lines || ('- What happened: some customer requests have no quote after three days.'
      || E'\n  Why: not enough matching suppliers answered.'
      || E'\n  What we are doing: the sales team is reaching more suppliers for each one.');
  end if;
  if coalesce((v_signals->>'costs_month_aed')::numeric, 0) > coalesce((v_signals->>'cost_ceiling_month_aed')::numeric, 1e12) then
    v_matters := v_matters || format('costs this month AED %s are over the ceiling of AED %s', round((v_signals->>'costs_month_aed')::numeric), v_signals->>'cost_ceiling_month_aed');
    v_lines := v_lines || ('- What happened: this month''s costs are above the budget we set (AED '
      || to_char(round((v_signals->>'costs_month_aed')::numeric), 'FM999,999,990') || ' against AED '
      || to_char((v_signals->>'cost_ceiling_month_aed')::numeric, 'FM999,999,990') || ').'
      || E'\n  Why: spending ran ahead of plan.'
      || E'\n  What we are doing: finance is cutting what is not needed, and I review it daily.');
  end if;

  insert into public.ceo_day (day, facts, priorities, matters)
  values (v_day, jsonb_build_object('verdict', v_verdict, 'plan', v_status, 'signals', v_signals, 'stuck', v_stuck), v_prio, v_matters)
  on conflict (day) do update set facts = excluded.facts, priorities = excluded.priorities,
    matters = coalesce((select array_agg(distinct m) from unnest(ceo_day.matters || excluded.matters) m), '{}'), updated_at = now();

  select note_handoff_id into v_note from public.ceo_day where day = v_day;
  if cardinality(v_lines) > 0 and v_note is null then
    v_hold := public.fn_founder_hold_line();
    v_body := to_char(v_day, 'FMDay DD Mon') || E'\n\n' || array_to_string(v_lines, E'\n\n')
      || coalesce(E'\n\nOn hold by your decision: ' || v_hold, '') || E'\n\nCEO';
    v_note := public.fn_seat_handoff('ceo', 'customer_support', 'delivery.request', 'ceo_day', v_day::text,
      jsonb_build_object('recipient_role', 'founder', 'event', 'CEO note: ' || to_char(v_day, 'Dy DD Mon'), 'detail', v_body,
                         'level', 'info', 'kind', 'founder_brief', 'dedupe_key', 'ceo_day:' || v_day));
    update public.ceo_day set note_handoff_id = v_note where day = v_day;
  end if;
  return jsonb_build_object('day', v_day, 'misses', v_verdict->'misses', 'stuck_new', n_stuck_new, 'matters', to_jsonb(v_matters),
                            'note_handoff_id', v_note, 'note', v_body, 'priorities', v_prio, 'directives', v_dir);
end $function$;

-- == 4. THE WEEKLY REVIEW: PAUSED TARGETS, AND THE FOUNDER'S TEXT ======================================
CREATE OR REPLACE FUNCTION public.fn_ceo_weekly_review(p_week date, p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_targets jsonb; t jsonb; i record; v_id bigint; v_task bigint;
  v_open bigint[] := '{}'; v_esc bigint[] := '{}'; v_closed bigint[] := '{}'; v_carried bigint[] := '{}'; v_row public.ceo_weekly_review;
  v_today date := (p_at at time zone 'Asia/Dubai')::date;
begin
  select * into v_row from public.ceo_weekly_review where week = p_week;
  if found then return jsonb_build_object('week', p_week, 'already', true, 'id', v_row.id); end if;

  -- 19 Oct 2026: a target the founder has held is marked paused; it opens no action and its open actions close.
  select coalesce(jsonb_agg(case when h.target_key is not null then x || jsonb_build_object('paused', true, 'paused_because', h.what_is_held) else x end), '[]'::jsonb)
    into v_targets
    from jsonb_array_elements(public.fn_ceo_weekly_review_measure(p_at)) x
    left join lateral (select f.target_key, f.what_is_held from public.fn_held_targets() f where f.target_key = x->>'key' limit 1) h on true;

  -- 1. CLOSE: the check of each open action, re-read on the same measure; an action on a held target closes as paused
  for i in select * from public.ceo_improvement where source_kind = 'weekly_review' and status in ('open', 'assigned') loop
    select x into t from jsonb_array_elements(v_targets) x
     where x->>'key' = i.evidence->>'target' and x->>'seat' = i.seat limit 1;
    if t is not null and coalesce((t->>'paused')::boolean, false) then
      perform public.fn_ceo_improvement_close(i.id, format('Weekly review of %s: paused - %s.', p_week, t->>'paused_because'));
      v_closed := v_closed || i.id;
    elsif t is not null and ((t->>'met')::boolean
        or (t->>'key' = 'supply' and (t->>'value')::numeric < (i.evidence->>'value')::numeric)) then
      perform public.fn_ceo_improvement_close(i.id, format('Weekly review of %s: %s. %s', p_week, t->>'actual', i.close_check));
      v_closed := v_closed || i.id;
    end if;
  end loop;

  -- 2. ESCALATE: still open past its due date
  for i in select * from public.ceo_improvement where source_kind = 'weekly_review' and status in ('open', 'assigned')
                                                     and due_on is not null and due_on <= v_today loop
    v_task := public.fn_ceo_task_open(
      format('ESCALATED x%s: %s missed the due date of improvement #%s', i.escalations + 1, i.seat, i.id),
      format(E'%s\nWas due %s. Now due %s. %s\nMeasured this week: %s',
             coalesce(i.evidence->>'action', i.proposal), i.due_on, v_today + 7, i.close_check,
             coalesce((select x->>'actual' from jsonb_array_elements(v_targets) x where x->>'key' = i.evidence->>'target' and x->>'seat' = i.seat limit 1), 'not measured')));
    update public.ceo_improvement set escalations = escalations + 1, last_escalated_at = p_at, due_on = v_today + 7,
           evidence = evidence || jsonb_build_object('escalation_tasks', coalesce(evidence->'escalation_tasks', '[]'::jsonb) || to_jsonb(v_task))
     where id = i.id;
    v_esc := v_esc || i.id;
  end loop;

  -- 3. OPEN: one action per missed (and not paused) target that has none open; one already open is CARRIED
  for t in select x from jsonb_array_elements(v_targets) x
            where not (x->>'met')::boolean and not coalesce((x->>'paused')::boolean, false) loop
    select id into v_id from public.ceo_improvement where source_kind = 'weekly_review' and status in ('open', 'assigned')
       and seat = t->>'seat' and evidence->>'target' = t->>'key' limit 1;
    if v_id is not null then v_carried := v_carried || v_id; continue; end if;
    v_id := public.fn_ceo_improvement_open('weekly_review', (t->>'key') || ':' || (t->>'seat') || ':' || p_week, t->>'seat',
      format('Weekly review %s, %s missed (%s; target %s). Action: %s Due %s. %s',
             to_char(p_week, 'DD Mon YYYY'), t->>'label', t->>'actual', t->>'target', t->>'action', to_char(p_week + 7, 'DD Mon YYYY'), t->>'close_check'),
      jsonb_build_object('target', t->>'key', 'value', t->'value', 'week', p_week, 'actual', t->>'actual', 'action', t->>'action', 'detail', t->'detail'));
    if v_id is not null then
      update public.ceo_improvement set due_on = p_week + 7, close_check = t->>'close_check' where id = v_id;
      v_open := v_open || v_id;
    end if;
  end loop;

  insert into public.ceo_weekly_review (week, targets, opened, escalated, closed)
  values (p_week, v_targets, v_open, v_esc, v_closed) returning * into v_row;
  update public.ceo_weekly_review set pdf_blocks = public.fn_ceo_weekly_review_pdf_blocks(v_row.id) where id = v_row.id;
  return jsonb_build_object('ok', true, 'week', p_week, 'id', v_row.id, 'opened', cardinality(v_open),
    'escalated', cardinality(v_esc), 'closed', cardinality(v_closed), 'carried', cardinality(v_carried),
    'carried_ids', to_jsonb(v_carried),
    'missed', (select count(*) from jsonb_array_elements(v_targets) x where not (x->>'met')::boolean and not coalesce((x->>'paused')::boolean, false)));
end $function$;

-- The week in the founder's words: one line per area still behind (what happened, why, what is being done),
-- the paused line, and the cash line. Shared by the email and the PDF so they never disagree.
create or replace function public.fn_ceo_weekly_review_lines(p_id bigint)
 returns jsonb
 language plpgsql stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare w public.ceo_weekly_review; v_items text[] := '{}'; r record; v_runway text;
begin
  select * into w from public.ceo_weekly_review where id = p_id;
  if not found then return null; end if;
  for r in
    select x->>'key' as k,
           regexp_replace(string_agg(distinct public.fn_seat_words(x->>'seat'), ', '), ', ([^,]*)$', ' and \1') as seats
      from jsonb_array_elements(w.targets) x
     where not (x->>'met')::boolean and not coalesce((x->>'info_only')::boolean, false)
       and not coalesce((x->>'paused')::boolean, x->>'key' in (select target_key from public.fn_held_targets()))
     group by x->>'key' order by min(x->>'label')
  loop
    v_items := v_items || case r.k
      when 'findings' then 'Some issues have stayed open for more than a week (' || r.seats || '), because they were not closed on time. Each team is closing its oldest first, and I escalate anything past its date.'
      when 'budget' then 'There is no expense budget for this year yet, because it was never set up. Finance is setting it this week so spending can be checked against it.'
      when 'risks' then 'A known risk has no plan or review date (' || r.seats || '), because its owner has not written one. The owner writes it this week.'
      when 'supply' then 'Most categories do not yet have enough suppliers, because recruitment is still early. The sales team is recruiting, starting with the biggest gaps.'
      else initcap(public.fn_target_words(r.k)) || ' is behind, because it missed its weekly target. Its owner has a fix due next week.' end;
  end loop;
  select 'Cash and runway (for your information): ' || (x->>'actual') || '.' into v_runway
    from jsonb_array_elements(w.targets) x where x->>'key' = 'runway' limit 1;
  return jsonb_build_object('items', to_jsonb(v_items), 'hold', public.fn_founder_hold_line(), 'runway', v_runway);
end $function$;
revoke execute on function public.fn_ceo_weekly_review_lines(bigint) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_ceo_weekly_review_deliver(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare w public.ceo_weekly_review; v_res jsonb; v_notif bigint; v_err text; v_file text; v_event text; v_l jsonb; v_text text;
begin
  select * into w from public.ceo_weekly_review where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'no such ceo_weekly_review ' || p_id); end if;
  if w.delivered_at is not null then return jsonb_build_object('ok', true, 'week', w.week, 'already', true); end if;

  if w.pdf_path is null then
    v_err := 'not delivered: the PDF has not been rendered yet; retained, the next beat retries';
  else
    v_event := 'CEO weekly review, week of ' || to_char(w.week, 'DD Mon YYYY');
    v_file := 'QuotesDone_CEO_Weekly_Review_' || to_char(w.week, 'IYYY-"W"IW') || '.pdf';
    v_text := public.fn_ceo_weekly_review_text(p_id);
    begin
      v_res := public.fn_notify_founder(p_event => v_event, p_detail => v_text || E'\n\nThe one-page review is attached.\n\nCEO',
        p_level => 'info', p_kind => 'ceo_weekly_review', p_dedupe_key => 'ceo_weekly_review:' || w.week, p_owner_agent => 'ceo');
      if coalesce((v_res->>'emailed')::boolean, false) then
        update public.notifications n
           set attachments = jsonb_build_array(jsonb_build_object('bucket', coalesce(w.pdf_bucket, 'agent-docs'), 'path', w.pdf_path, 'filename', v_file))
         where n.id = (select max(x.id) from public.notifications x
                        where x.kind = 'ceo_weekly_review' and x.channel = 'email' and x.to_role = 'founder' and x.created_at = now())
        returning n.id into v_notif;
        if v_notif is null then v_err := 'fn_notify_founder said emailed, but no queued email of kind ceo_weekly_review was found to attach the PDF to'; end if;
      else
        v_err := 'fn_notify_founder did not email: ' || coalesce(v_res::text, 'null');
      end if;
    exception when others then
      v_err := 'delivery raised: ' || sqlerrm;
      v_notif := null;
    end;
  end if;

  update public.ceo_weekly_review
     set notification_id = coalesce(v_notif, notification_id), notify = coalesce(v_res, notify),
         delivered_at = case when v_notif is not null then now() end,
         attempts = attempts + 1, last_error = v_err, updated_at = now()
   where id = p_id;
  return jsonb_build_object('ok', v_notif is not null, 'week', w.week, 'notification_id', v_notif, 'pdf_filename', v_file)
    || case when v_err is null then '{}'::jsonb else jsonb_build_object('error', v_err) end;
end $function$;

-- The weekly email body: the week's lines as a short note.
create or replace function public.fn_ceo_weekly_review_text(p_id bigint)
 returns text language sql stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  select 'This week:' || E'\n'
      || coalesce((select string_agg('- ' || e, E'\n') from jsonb_array_elements_text(l->'items') e),
                  '- Every target we track this week was met.')
      || coalesce(E'\n\nOn hold by your decision: ' || (l->>'hold'), '')
      || coalesce(E'\n\n' || (l->>'runway'), '')
    from public.fn_ceo_weekly_review_lines(p_id) l
$function$;
revoke execute on function public.fn_ceo_weekly_review_text(bigint) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_ceo_weekly_review_pdf_blocks(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare w public.ceo_weekly_review; l jsonb; v jsonb;
begin
  select * into w from public.ceo_weekly_review where id = p_id;
  if not found then return null; end if;
  l := public.fn_ceo_weekly_review_lines(p_id);
  v := jsonb_build_array(
    jsonb_build_object('t', 'h2', 'text', 'CEO weekly review'),
    jsonb_build_object('t', 'p', 'text', 'Week of ' || to_char(w.week, 'FMDay DD Mon YYYY') || '.'),
    jsonb_build_object('t', 'h3', 'text', 'What is behind, why, and what we are doing'));
  v := v || coalesce((select jsonb_agg(jsonb_build_object('t', 'li', 'text', e)) from jsonb_array_elements_text(l->'items') e),
                     jsonb_build_array(jsonb_build_object('t', 'li', 'text', 'Every target we track this week was met.')));
  if l->>'hold' is not null then
    v := v || jsonb_build_array(jsonb_build_object('t', 'h3', 'text', 'Paused by your decision'),
                                jsonb_build_object('t', 'li', 'text', l->>'hold'));
  end if;
  if l->>'runway' is not null then
    v := v || jsonb_build_array(jsonb_build_object('t', 'h3', 'text', 'Cash'), jsonb_build_object('t', 'li', 'text', l->>'runway'));
  end if;
  v := v || jsonb_build_array(jsonb_build_object('t', 'note', 'text',
    'Each item has an owner and a date. Next week''s review checks it again and escalates anything that slipped.'));
  return v;
end $function$;

-- == PROBE (verdict row; this file defines routines, so it never raises) ==============================
select case
  when (select count(*) from public.fn_held_targets()) = 0 and (select value from public.app_secrets where key = 'invite_enabled') is distinct from 'true'
    then 'PROBE FAILED: the campaign is off but no target is held'
  when exists (select 1 from jsonb_array_elements(public.fn_ceo_year_plan_status(now())->'metrics') e
                where e->>'metric' in (select target_key from public.fn_held_targets()) and e->>'status' <> 'paused')
    then 'PROBE FAILED: a held target is not reported paused'
  when public.fn_ceo_weekly_review_text((select max(id) from public.ceo_weekly_review)) ~ '[a-z]+_[a-z_]+|#[0-9]'
    then 'PROBE FAILED: the weekly text carries a code or an id'
  else 'PROBE OK' end as verdict;
