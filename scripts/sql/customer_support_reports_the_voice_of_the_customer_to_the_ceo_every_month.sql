-- CUSTOMER SUPPORT REPORTS THE VOICE OF THE CUSTOMER TO THE CEO EVERY MONTH (19 Oct 2026). Assigned: customer_support
-- (writes it), ceo (receives it). Founder ledger 1003 stage 2, contribution CS-C14: "Report voice-of-the-customer
-- findings (CSAT, top contact reasons, effort) to the CEO monthly with actions".
--
-- MEASURED 19 Oct 2026 (repo + production, read-only): the weekly case review reports volumes only; no CSAT or CES
-- result was aggregated anywhere (feedback kind 'csat' 1-5 and 'ces' 1-7 are recorded per closed case by
-- fn_support_touch / fn_support_feedback_record, none collected pre-launch), and no monthly report with actions went to
-- the CEO. support_case carries category, fcr, first_reply_seconds, contact_count and reopen_count.
--
-- WHAT THIS ADDS: customer_support.voice_of_customer, checked daily, fn_customer_support_voice_of_customer_month():
-- once per last complete Dubai calendar month (customer_support_voc_month, one row per month). Code, no model:
--   satisfaction  CSAT average and count, share rating 4-5; CES average and count (lower is easier); NPS is not
--                 collected and the report says so rather than printing a number;
--   contact       cases opened, top 5 contact reasons (support_case.category), first-contact resolution share,
--                 median first reply (minutes), repeat contacts (contact_count > 1), reopened, complaints opened and
--                 past their due date, knowledge requests still open;
--   actions       derived by fixed rules, each naming the owner seat: CSAT under 4.0 -> service recovery review
--                 (customer_support); a contact reason over 25% of cases -> root cause to its owning seat
--                 (support_category.owner_seat); median first reply over the SLA -> reply speed (customer_support);
--                 FCR under 70% -> answer completeness (customer_support); any complaint past due -> complaint handling
--                 (ceo); more than 20 knowledge requests open -> knowledge backlog (their owner seats). None fired ->
--                 "no action: every measure on target", said explicitly;
--   delivery      fn_support_report_to_ceo('voc:<month>', 'routine', ...) with the whole report, once per month.
-- qd.duty_fixtures = 'on' measures only fixture rows and never writes to the CEO.
--
-- Prevented by: scripts/checks/customer_support_senior_contributions_are_working_duties.test.mjs.
-- Apply at merge:  node scripts/apply_sql.mjs scripts/sql/customer_support_reports_the_voice_of_the_customer_to_the_ceo_every_month.sql --apply --ddl

create table if not exists public.customer_support_voc_month (
  month       date primary key check (month = date_trunc('month', month)::date),
  report      jsonb not null,
  actions     jsonb not null default '[]'::jsonb,
  ceo_report  jsonb,
  fixture     boolean not null default false,
  reported_at timestamptz not null default now()
);
comment on table public.customer_support_voc_month is
  'customer_support''s monthly voice-of-the-customer report to the CEO: CSAT, CES, top contact reasons, effort measures and rule-derived actions.';
alter table public.customer_support_voc_month enable row level security;
drop policy if exists customer_support_voc_month_service_role_only on public.customer_support_voc_month;
create policy customer_support_voc_month_service_role_only on public.customer_support_voc_month
  as permissive for all to public using (false) with check (false);
revoke all on public.customer_support_voc_month from anon, authenticated;

create or replace function public.fn_customer_support_voice_of_customer_month()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_month date := (date_trunc('month', now() at time zone 'Asia/Dubai') - interval '1 month')::date;
  v_from timestamptz := v_month::timestamp at time zone 'Asia/Dubai';
  v_to timestamptz := (v_month + interval '1 month')::timestamp at time zone 'Asia/Dubai';
  v_sla numeric := public.fn_seat_clock_policy('support_first_reply_sla_hours', 24);
  v_sat jsonb; v_cases jsonb; v_reasons jsonb; v_other jsonb; v_rep jsonb; v_act jsonb := '[]'::jsonb; v_ceo jsonb; r record; v_n int;
begin
  if exists (select 1 from public.customer_support_voc_month where month = v_month and fixture = v_fx) then
    return jsonb_build_object('ok', true, 'month', v_month, 'already', true);
  end if;

  select jsonb_build_object(
           'csat_avg', round(avg(f.rating) filter (where f.kind = 'csat'), 2), 'csat_count', count(*) filter (where f.kind = 'csat'),
           'csat_4_or_5_share', round(avg(case when f.rating >= 4 then 1 else 0 end) filter (where f.kind = 'csat'), 3),
           'ces_avg', round(avg(f.rating) filter (where f.kind = 'ces'), 2), 'ces_count', count(*) filter (where f.kind = 'ces'),
           'nps', null, 'nps_note', 'not collected: no NPS question is asked')
    into v_sat
    from public.feedback f
    left join public.support_case s on s.case_id = f.case_id
    left join public.support_customer_profile p on p.id = s.customer_profile_id
   where f.created_at >= v_from and f.created_at < v_to and f.kind in ('csat', 'ces')
     and public.fn_is_demo_email(p.email) = v_fx;

  select jsonb_build_object('opened', count(*),
           'fcr_share', round(avg(case when s.fcr then 1 else 0 end) filter (where s.fcr is not null), 3),
           'median_first_reply_minutes', round((percentile_cont(0.5) within group (order by s.first_reply_seconds) / 60)::numeric),
           'repeat_contact_share', round(avg(case when s.contact_count > 1 then 1 else 0 end), 3),
           'reopened', count(*) filter (where s.reopen_count > 0))
    into v_cases
    from public.support_case s left join public.support_customer_profile p on p.id = s.customer_profile_id
   where s.opened_at >= v_from and s.opened_at < v_to and public.fn_is_demo_email(p.email) = v_fx;

  select coalesce(jsonb_agg(jsonb_build_object('reason', x.category, 'cases', x.n, 'share', x.share, 'owner_seat', x.owner_seat) order by x.n desc), '[]'::jsonb)
    into v_reasons
    from (select coalesce(s.category, 'uncategorised') category, count(*) n,
                 round(count(*)::numeric / nullif(sum(count(*)) over (), 0), 3) share, max(c.owner_seat) owner_seat
            from public.support_case s left join public.support_customer_profile p on p.id = s.customer_profile_id
            left join public.support_category c on c.category = s.category
           where s.opened_at >= v_from and s.opened_at < v_to and public.fn_is_demo_email(p.email) = v_fx
           group by 1 order by 2 desc limit 5) x;

  select jsonb_build_object(
           'complaints_opened', (select count(*) from public.complaint_tickets t where t.created_at >= v_from and t.created_at < v_to and public.fn_is_demo_email(t.email) = v_fx),
           'complaints_past_due', (select count(*) from public.complaint_tickets t where public.fn_is_demo_email(t.email) = v_fx
                                     and t.respond_due < v_to and (t.final_response_at is null or t.final_response_at > t.respond_due) and t.created_at < v_to),
           'knowledge_requests_open', (select count(*) from public.sales_knowledge_gap k where k.status = 'open' and (k.question like 'ZZ DEMO%') = v_fx))
    into v_other;

  -- actions, by fixed rules
  if (v_sat->>'csat_count')::int > 0 and (v_sat->>'csat_avg')::numeric < 4.0 then
    v_act := v_act || jsonb_build_array(jsonb_build_object('owner_seat', 'customer_support', 'action', 'service recovery review: CSAT ' || (v_sat->>'csat_avg') || ' is under 4.0'));
  end if;
  for r in select * from jsonb_to_recordset(v_reasons) as x(reason text, cases int, share numeric, owner_seat text) loop
    if r.share > 0.25 and r.reason <> 'uncategorised' then
      v_act := v_act || jsonb_build_array(jsonb_build_object('owner_seat', coalesce(r.owner_seat, 'customer_support'),
        'action', 'root cause for "' || r.reason || '": ' || round(r.share * 100) || '% of cases'));
    end if;
  end loop;
  if (v_cases->>'median_first_reply_minutes')::numeric > v_sla * 60 then
    v_act := v_act || jsonb_build_array(jsonb_build_object('owner_seat', 'customer_support', 'action', 'reply speed: median first reply ' || (v_cases->>'median_first_reply_minutes') || ' min is over the ' || v_sla || ' h SLA'));
  end if;
  if (v_cases->>'fcr_share')::numeric < 0.7 then
    v_act := v_act || jsonb_build_array(jsonb_build_object('owner_seat', 'customer_support', 'action', 'answer completeness: first-contact resolution ' || round((v_cases->>'fcr_share')::numeric * 100) || '% is under 70%'));
  end if;
  if (v_other->>'complaints_past_due')::int > 0 then
    v_act := v_act || jsonb_build_array(jsonb_build_object('owner_seat', 'ceo', 'action', 'complaint handling: ' || (v_other->>'complaints_past_due') || ' complaint(s) answered late or not at all'));
  end if;
  if (v_other->>'knowledge_requests_open')::int > 20 then
    v_act := v_act || jsonb_build_array(jsonb_build_object('owner_seat', 'sales_engineer and ceo', 'action', 'knowledge backlog: ' || (v_other->>'knowledge_requests_open') || ' requests open'));
  end if;
  if jsonb_array_length(v_act) = 0 then
    v_act := jsonb_build_array(jsonb_build_object('owner_seat', 'customer_support', 'action', 'no action: every measure on target'));
  end if;

  v_rep := jsonb_build_object('month', v_month, 'satisfaction', v_sat, 'cases', v_cases, 'top_contact_reasons', v_reasons) || v_other;

  if not v_fx then
    v_ceo := public.fn_support_report_to_ceo('voc:' || v_month, 'routine',
      'Voice of the customer, ' || to_char(v_month, 'FMMonth YYYY') || ': CSAT ' || coalesce(v_sat->>'csat_avg', 'none collected')
        || ', ' || coalesce(v_cases->>'opened', '0') || ' cases, ' || jsonb_array_length(v_act) || ' action(s)',
      v_rep || jsonb_build_object('actions', v_act),
      jsonb_build_array('measured by customer_support from feedback, support_case, complaint_tickets and sales_knowledge_gap'),
      'Read the month and confirm or change the actions; each names its owner seat.', p_review_in => interval '7 days');
  end if;

  -- a fixture run never takes the real month's row
  if not v_fx then
    insert into public.customer_support_voc_month (month, report, actions, ceo_report, fixture)
    values (v_month, v_rep, v_act, v_ceo, false)
    on conflict (month) do nothing;
  end if;
  return jsonb_build_object('ok', true, 'fixture', v_fx, 'month', v_month, 'actions', v_act, 'ceo_report', v_ceo) || v_rep;
end $fn$;
revoke execute on function public.fn_customer_support_voice_of_customer_month() from public, anon, authenticated;
grant execute on function public.fn_customer_support_voice_of_customer_month() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('customer_support.voice_of_customer', 'customer_support', interval '1 day', 'fn_customer_support_voice_of_customer_month',
   'CS-C14: once a month, the voice-of-the-customer report to the CEO: CSAT and CES aggregated, top contact reasons, effort measures, and rule-derived actions naming their owner seats',
   'scripts/sql/customer_support_reports_the_voice_of_the_customer_to_the_ceo_every_month.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;
