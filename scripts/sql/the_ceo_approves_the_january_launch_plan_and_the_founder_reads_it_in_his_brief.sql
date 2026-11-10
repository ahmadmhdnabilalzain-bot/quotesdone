-- THE CEO APPROVES THE JANUARY LAUNCH PLAN; THE FOUNDER READS THE RESULT IN HIS DAILY BRIEF AND NOWHERE ELSE.
--
-- Assigned: ceo (the approval and the brief lines), with marketing (the plan it draws). 10 Nov 2026. Founder ledger 1616
-- (standing): "the CEO seat approves the January launch plan; the founder is only told in his daily brief". With 1609
-- ("no decision goes to the founder") and 1614 (trade by trade). Proposal P7 of
-- docs/reports/2026-11-10-seat-qualification-audit.md.
--
-- == MEASURED, 10 Nov 2026, production read-only ====================================================================
--   * fn_marketing_launch_plan_run (canonical: the_marketing_seat_puts_its_plan_geo_articles_launch_and_competitor_work_on_a_clock.sql,
--     diffed equal to live) mails the founder "Launch plan for January 2027 [approve <token>]" from 1 Dec and waits for
--     his "approve" reply (marketing_plan_doc.status sent_to_founder). The plan's rule reads "Organic only until every
--     category has its verified suppliers", the all-categories rule 1614 retired; its counts come from v_category_open.
--   * The launch plan doc for 2027-01-01 is 'draft'. The seat_duty text says "sent for approval from 1 December".
--   * fn_founder_brief (live) composes the brief from fn_founder_brief_figures/_text and has no place for a decision
--     the CEO took.
--
-- == WHAT THIS CHANGES ===============================================================================================
--   fn_marketing_launch_plan_run   draws the plan on the trades OPEN to customers (trade_customer_opening, ledger 1614)
--                                  and the nearest to opening, and from 1 Dec hands it to fn_ceo_decide_launch_plan
--                                  instead of mailing the founder.
--   fn_ceo_decide_launch_plan      the CEO's rules, in code, with reasons on the document (body.ceo_review): no paid
--                                  channel while paid is not allowed (ledgers 1456, 1606); at least 15 UAE posting days;
--                                  the plan names the trades it launches in (open ones, else the nearest with the waiting
--                                  list, never "every trade"). Approved, or change_requested with the reasons; the seat
--                                  redraws daily and a changed plan is decided again (1059: a rejection never ends it).
--   ceo_brief_line + fn_founder_brief_ceo_lines + fn_founder_brief
--                                  every CEO decision of the day (this approval, a trade opening, the break-even verdict)
--                                  is one line in the brief, under "Decided by the CEO (nothing needs your reply)".
-- NOT CHANGED: the monthly social calendar stays his one approval (ledger 1059; marketing.month_plan). No mail is added.
-- prevented by: scripts/checks/the_ceo_approves_the_january_launch_plan_and_the_founder_reads_it_in_his_brief.test.mjs
-- Pending: scripts/sql/pending/the_ceo_approves_the_january_launch_plan_and_the_founder_reads_it_in_his_brief.txt

create table if not exists public.ceo_brief_line (
  id          bigint generated always as identity primary key,
  subject_key text not null unique,
  line        text not null check (length(btrim(line)) > 0),
  source      text not null,
  created_at  timestamptz not null default now()
);
alter table public.ceo_brief_line enable row level security;
drop policy if exists ceo_brief_line_service_role_only on public.ceo_brief_line;
create policy ceo_brief_line_service_role_only on public.ceo_brief_line as permissive for all to public using (false) with check (false);
revoke all on public.ceo_brief_line from anon, authenticated;

-- One line per decision, once (the subject key): a decision re-taken the same way is not told twice.
create or replace function public.fn_ceo_brief_line(p_key text, p_line text, p_source text)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint;
begin
  insert into public.ceo_brief_line (subject_key, line, source) values (p_key, p_line, p_source)
  on conflict (subject_key) do nothing returning id into v_id;
  return v_id;
end $fn$;
revoke execute on function public.fn_ceo_brief_line(text, text, text) from public, anon, authenticated;
grant execute on function public.fn_ceo_brief_line(text, text, text) to service_role;

-- The brief's CEO section for a window: the decision lines, the trades that opened, and the break-even verdict.
create or replace function public.fn_founder_brief_ceo_lines(p_from timestamptz, p_to timestamptz)
returns text language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_lines text[] := '{}'; v_be record;
begin
  select coalesce(array_agg(l.line order by l.created_at), '{}') into v_lines from public.ceo_brief_line l where l.created_at >= p_from and l.created_at < p_to;
  if to_regclass('public.trade_customer_opening') is not null then
    v_lines := v_lines || coalesce((select array_agg('Opened to customers: ' || t.label || ' (' || o.verified_suppliers || ' verified suppliers).' order by t.label)
                                      from public.trade_customer_opening o join public.taxonomy_trade t on t.code = o.trade
                                     where o.opened_at >= p_from and o.opened_at < p_to), '{}');
  end if;
  if to_regclass('public.ceo_break_even_month') is not null then
    select * into v_be from public.ceo_break_even_month order by month desc limit 1;
    if found then
      v_lines := array_append(v_lines, format('Break-even to 30 Jun 2027: AED %s to cover, AED %s earned, gap AED %s; this month needs %s reveals and %s verified suppliers (%s).',
        to_char(v_be.cost_to_cover_aed, 'FM999,999,990'), to_char(v_be.revenue_net_aed, 'FM999,999,990'), to_char(v_be.gap_aed, 'FM999,999,990'),
        v_be.targets->>'reveals_per_month', v_be.targets->>'verified_suppliers', replace(v_be.verdict, '_', ' ')));
    end if;
  end if;
  if cardinality(v_lines) = 0 then return ''; end if;
  return E'\n\nDecided by the CEO (nothing needs your reply):\n' || (select string_agg('- ' || x, E'\n') from unnest(v_lines) x);
end $fn$;
revoke execute on function public.fn_founder_brief_ceo_lines(timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function public.fn_founder_brief_ceo_lines(timestamptz, timestamptz) to service_role;

-- The live fn_founder_brief, read back 10 Nov 2026 and unchanged but for the one line that appends the CEO section.
create or replace function public.fn_founder_brief(p_local_date date default null)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
declare
  v_tz text := 'Asia/Dubai';
  v_day date := coalesce(p_local_date, (now() at time zone 'Asia/Dubai')::date);
  v_midnight timestamptz := (v_day::timestamp) at time zone 'Asia/Dubai';
  v_from timestamptz; v_to timestamptz; v_prev timestamptz;
  v_fig jsonb; v_body text; v_subj text; v_run bigint; v_alert uuid;
begin
  insert into public.agent_runs(agent, started_at) values ('brief', now()) returning id into v_run;

  -- The window starts where the previous brief ended, so 20:00-24:00 is never lost between days.
  select (figures->>'window_to')::timestamptz into v_prev
    from public.ceo_daily_digest
   where local_date < v_day and figures ? 'window_to'
   order by local_date desc limit 1;
  v_from := case when v_prev is null or v_prev < v_midnight - interval '1 day' then v_midnight else v_prev end;
  v_to   := least(now(), v_midnight + interval '1 day');

  v_fig  := public.fn_founder_brief_figures(v_from, v_to);
  v_body := public.fn_founder_brief_text(v_fig);
  -- ledger 1616: what the CEO decided in the window, told here and nowhere else (fn_founder_brief_ceo_lines)
  v_body := v_body || public.fn_founder_brief_ceo_lines(v_from, v_to);
  v_subj := 'QuotesDone daily brief - '||to_char(v_day,'Dy DD Mon');

  -- The Command Center row is written whether or not a recipient exists.
  insert into public.founder_alerts(level, event, detail, channel)
    values ('info', 'CEO end-of-day company digest', v_body, 'os') returning id into v_alert;

  -- Unchanged from the previous brief: fold the week's 'digest' notifications.
  update public.notifications set status = 'digested'
   where status = 'digest' and created_at >= now() - interval '7 days' and created_at <= now();

  update public.agent_runs set finished_at = now(), status = 'ok',
         counts = jsonb_build_object(
           'invitations', v_fig->'invitations'->'count', 'suppliers_registered', v_fig->'suppliers_registered'->'count',
           'inquiries', v_fig->'inquiries'->'count', 'customers', v_fig->'customers'->'count',
           'comparisons', v_fig->'comparisons'->'count', 'reveal_fees', v_fig->'reveal_fees'->'count')
   where id = v_run;

  return jsonb_build_object('subject', v_subj, 'body', v_body, 'figures', v_fig, 'command_center_id', v_alert);
end;
$fn$;

-- THE CEO'S DECISION ON THE LAUNCH PLAN (ledger 1616). Rules in code; reasons on the document; one brief line.
create or replace function public.fn_ceo_decide_launch_plan(p_doc bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare d public.marketing_plan_doc; v_why text[] := '{}'; v_ok text[] := '{}'; v_status text; v_days int; v_trades int; v_paid boolean := public.fn_marketing_paid_allowed();
begin
  select * into d from public.marketing_plan_doc where id = p_doc and kind = 'launch_plan';
  if not found then return jsonb_build_object('decided', false, 'why', 'no launch plan'); end if;
  v_days := jsonb_array_length(coalesce(d.body->'posting_days', '[]'::jsonb));
  v_trades := jsonb_array_length(coalesce(d.body->'launch_trades', '[]'::jsonb));
  if not v_paid and exists (select 1 from jsonb_array_elements_text(coalesce(d.body->'channels', '[]'::jsonb)) c where c ilike '%paid%') then
    v_why := array_append(v_why, 'a paid channel is in the plan while paid spend is not allowed (ledgers 1456, 1606): remove it');
  else v_ok := array_append(v_ok, 'organic channels only'); end if;
  if v_days < 15 then v_why := array_append(v_why, format('%s posting days is under the 15 a launch month needs', v_days));
  else v_ok := array_append(v_ok, format('%s UAE posting days', v_days)); end if;
  if v_trades = 0 then v_why := v_why || 'the plan names no trade to launch in (ledger 1614: trade by trade; the open ones, else the nearest with the waiting list)';
  else v_ok := array_append(v_ok, format('launches in %s named trade(s): %s', v_trades, d.body->>'launch_basis')); end if;
  v_status := case when cardinality(v_why) = 0 then 'approved' else 'change_requested' end;
  update public.marketing_plan_doc set status = v_status, decided_at = now(), updated_at = now(),
         body = body || jsonb_build_object('ceo_review', jsonb_build_object('decided_by', 'ceo', 'decided_at', now(), 'status', v_status,
                'reasons', to_jsonb(case when v_status = 'approved' then v_ok else v_why end), 'ruling', 'ledger 1616'))
   where id = d.id;
  perform public.fn_ceo_brief_line('launch_plan:' || d.period || ':' || v_status || ':' || coalesce(d.sent_hash, ''),
    case when v_status = 'approved' then 'January launch plan approved: ' || array_to_string(v_ok, '; ') || '.'
         else 'January launch plan sent back to marketing: ' || array_to_string(v_why, '; ') || '. It is decided again when redrawn.' end,
    'fn_ceo_decide_launch_plan');
  return jsonb_build_object('decided', true, 'status', v_status, 'reasons', to_jsonb(case when v_status = 'approved' then v_ok else v_why end));
end $fn$;
revoke execute on function public.fn_ceo_decide_launch_plan(bigint) from public, anon, authenticated;
grant execute on function public.fn_ceo_decide_launch_plan(bigint) to service_role;

-- THE PLAN, DRAWN TRADE BY TRADE, DECIDED BY THE CEO. Unchanged from the canonical file except: the counts are trades
-- open to customers (1614), the plan names the trades it launches in, and from 1 Dec the CEO decides it (no founder mail).
create or replace function public.fn_marketing_launch_plan_run(p_today date)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_today date := p_today;
  v_launch date := date '2027-01-01';
  v_body jsonb; d public.marketing_plan_doc; v_paid boolean := public.fn_marketing_paid_allowed();
  v_open int; v_total int; v_short jsonb; v_hash text; v_changes jsonb; v_trades jsonb; v_basis text; v_dec jsonb;
begin
  select count(*) filter (where o.is_open), count(*) into v_open, v_total
    from public.taxonomy_trade t left join public.trade_customer_opening o on o.trade = t.code where t.active;
  select coalesce(jsonb_agg(jsonb_build_object('trade', x.label, 'verified', x.v, 'needed', x.open_at) order by x.short, x.label), '[]'::jsonb)
    into v_short
    from (select t.label, coalesce(o.verified_suppliers, 0) v, coalesce(o.open_at, 0) open_at, coalesce(o.open_at, 0) - coalesce(o.verified_suppliers, 0) short
            from public.taxonomy_trade t left join public.trade_customer_opening o on o.trade = t.code
           where t.active and not coalesce(o.is_open, false) order by short, t.label limit 10) x;
  -- the trades it launches in: the open ones; with none open yet, the five nearest to opening, whose customers join the waiting list
  if v_open > 0 then
    select jsonb_agg(t.label order by t.label) into v_trades from public.trade_customer_opening o join public.taxonomy_trade t on t.code = o.trade where o.is_open;
    v_basis := 'the trades open to customers';
  else
    select jsonb_agg(e->>'trade') into v_trades from (select e from jsonb_array_elements(v_short) e limit 5) s;
    v_basis := 'none is open yet: the five nearest to opening, customers join their waiting list until each opens';
  end if;
  v_changes := coalesce((select founder_changes from public.marketing_plan_doc where kind = 'launch_plan' and period = v_launch), '[]'::jsonb);
  v_body := jsonb_build_object(
    'founder_changes', v_changes,
    'launch_month', v_launch, 'drawn_on', v_today,
    'categories', jsonb_build_object('open', v_open, 'total', v_total, 'short', v_short),
    'launch_trades', coalesce(v_trades, '[]'::jsonb), 'launch_basis', v_basis,
    'paid_allowed', v_paid,
    'channels', case when v_paid then jsonb_build_array('organic social', 'blog and GEO', 'LinkedIn outreach', 'paid Meta within the ad cap')
                     else jsonb_build_array('organic social', 'blog and GEO', 'LinkedIn outreach') end,
    'rule', 'Trade by trade (ledger 1614): each trade is promoted to customers once it is open; organic only while paid spend is not allowed; no post on a UAE weekend or public holiday.',
    'posting_days', (select coalesce(jsonb_agg(g::date order by g), '[]'::jsonb)
                       from generate_series(v_launch, date '2027-01-31', interval '1 day') g where public.fn_is_working_day(g::date)),
    'articles_ready', (select count(*) from public.marketing_article where status in ('approved', 'released', 'live') and not is_demo),
    'supplier_recruitment', (select last_result from public.seat_duty where duty = 'marketing.recruitment_funnel'));
  insert into public.marketing_plan_doc (kind, period, body) values ('launch_plan', v_launch, v_body)
  on conflict (kind, period) do update set body = excluded.body, updated_at = now()
    where marketing_plan_doc.status in ('draft', 'change_requested')
  returning * into d;
  if d.id is null then select * into d from public.marketing_plan_doc where kind = 'launch_plan' and period = v_launch; end if;
  v_hash := md5((v_body - 'drawn_on' - 'supplier_recruitment' - 'articles_ready'
                 || jsonb_build_object('categories', jsonb_build_object('open', v_open, 'total', v_total)))::text);

  -- from 1 Dec the CEO decides the plan (ledger 1616); a plan sent back is decided again once it has changed
  if v_today >= date '2026-12-01' and v_today < v_launch
     and (d.status = 'draft' or (d.status = 'change_requested' and v_hash is distinct from d.sent_hash)) then
    update public.marketing_plan_doc set sent_hash = v_hash, sent_at = now(), updated_at = now() where id = d.id;
    v_dec := public.fn_ceo_decide_launch_plan(d.id);
    d.status := v_dec->>'status';
  end if;
  return jsonb_build_object('status', d.status, 'open', v_open, 'total', v_total, 'paid_allowed', v_paid, 'mailed', false,
    'decided_by', case when v_dec is not null then 'ceo' end, 'ceo_decision', v_dec,
    'founder_changes', jsonb_array_length(v_changes), 'posting_days', jsonb_array_length(v_body->'posting_days'));
end $fn$;

update public.seat_duty
   set what = 'The January 2027 launch plan redrawn daily trade by trade from the trades open to customers (ledger 1614); from 1 December the CEO seat decides it under its rules, and the founder reads the decision in his daily brief (ledger 1616).'
 where duty = 'marketing.launch_plan';   -- owner_file stays: fn_marketing_launch_plan_duty is defined there
