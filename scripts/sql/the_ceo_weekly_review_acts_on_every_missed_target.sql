-- THE CEO WEEKLY REVIEW ACTS ON EVERY MISSED TARGET.
-- Seat: ceo. 29 Sep 2026. Founder instruction 1009, item (5): "A CEO weekly review that ACTS. It is one page,
-- covering suppliers per category against the target of 10 per category; cash and runway from the accountant's
-- books; spend against budget; open risks; each seat's open findings. For every target missed, it names the
-- corrective action and assigns it to the owning seat as a tracked improvement with an owner, a due date and a check
-- that closes it. Missed actions escalate the next week. It is sent to the founder once a week as a short PDF through
-- fn_notify_founder, with the correct p_kind. Plain code, no LLM."
--
-- ══ MEASURED BEFORE WRITING (production, 29 Sep 2026, read-only) ══════════════════════════════════════════
--   * Suppliers per category: public.supply_gap holds one row per active trade for emirate 'UAE' (213 rows) with
--     matchable suppliers against target = pricing_config.category_open_min_suppliers (10), refreshed daily by the
--     sales engineer's duty fn_sales_engineer_supply_gap. It is READ here, never re-run.
--   * Cash and runway: fn_accountant_runway_figures(month) (STABLE) answers available cash, monthly spend and runway
--     months at actual spend from the accountant's books (AED 582.96 available, 0.3 months on 29 Sep).
--   * Spend against budget: budgets / budget_lines / budget_vs_actual. 0 budgets exist: "no budget" is itself the miss.
--   * Open risks: risk_register, 1 open (id 18, owner ceo, no review date).
--   * Findings: it_engineer_finding, open rows attributed to a seat by evidence->>'owner_seat' else raised_by (the
--     same attribution fn_ceo_management_review uses).
--   * Tracked improvements already exist: public.ceo_improvement + fn_ceo_improvement_open (a ceo_task and a handoff
--     to the seat) + fn_ceo_improvement_close. They had an owner (seat) but NO due date and NO closing check, and
--     nothing escalated an improvement that sat open. This file adds those three columns and uses the machinery.
--   * The existing weekly company report (fn_ceo_weekly_report_tick, kind board_report) is narrative and mails
--     through a direct notifications insert. It is NOT changed. This review is the second, acting, one-page document.
--
-- ══ WHAT THIS ADDS ═══════════════════════════════════════════════════════════════════════════════════════
--   fn_ceo_weekly_review_measure(p_at)  STABLE, code only: one row per target and owning seat —
--       supply    sales_engineer   every category at 10 matchable suppliers
--       runway    (information only) months at current spend. NOT a target: founder ruling 29 Sep 2026, he funds the
--                                  company until profitable with no deadline. Revisited only if investor funding arrives.
--       budget    accountant       an active budget for the year, and expense actuals YTD within it
--       risks     each seat        no open risk it owns without a mitigation or past its review date
--       findings  each seat        no finding attributed to it open more than 7 days
--   fn_ceo_weekly_review(p_week)  once per ISO week (Dubai), in this order:
--       1. CLOSE every open weekly_review improvement whose check now passes (the same measure, re-read);
--       2. ESCALATE every one still open past its due date: escalations + 1, due one week later, a new CEO task
--          "ESCALATED (n)" and a line at the top of the page;
--       3. OPEN one improvement per missed target that has none open: owner = the seat, due_on = next review,
--          close_check = the rule in words, evidence = the measured numbers;
--       4. build the one-page PDF block list.
--   fn_ceo_weekly_review_tick()  on the resilience_ping heartbeat (step ceoWeeklyReview): from Monday 09:00 Dubai it
--       runs the week, the heartbeat renders the PDF (pdf_native) and fn_ceo_weekly_review_attach_pdf delivers it:
--       fn_notify_founder(p_level 'info', p_kind 'ceo_weekly_review', dedupe per week, owner ceo), and the PDF is
--       attached to the email that call queued (a20_notifications_attachment_policy validates the UPDATE).
--       level info: email only, no WhatsApp copy. A failed render or delivery is retained and retried next beat.
--
-- NOT CHANGED: the supply duty, the accountant's figures, the risk register, IT's findings, the weekly company report.
-- No model is called and no text is read to decide anything.
--
-- Pending: scripts/sql/pending/the_ceo_weekly_review_acts_on_every_missed_target.txt (applies after merge).
--   node scripts/apply_sql.mjs scripts/sql/the_ceo_weekly_review_acts_on_every_missed_target.sql --apply --ddl --seat ceo

-- ── 1. an improvement has an owner, a due date and a check that closes it; it can be escalated ─────────────
alter table public.ceo_improvement
  add column if not exists due_on            date,
  add column if not exists close_check       text,
  add column if not exists escalations       int not null default 0,
  add column if not exists last_escalated_at timestamptz;

alter table public.ceo_improvement drop constraint if exists ceo_improvement_source_kind_check;
alter table public.ceo_improvement add constraint ceo_improvement_source_kind_check check (source_kind = any (array[
  'recurring_miss', 'month_miss', 'lesson', 'recurring_finding', 'binding_constraint', 'marketing_plan_late',
  'seat_audit', 'weekly_review', 'self_review']));

-- ── 2. the founder-mail kind ─────────────────────────────────────────────────────────────────────────────
insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role) values
  ('ceo_weekly_review', true,
   'Founder instruction 1009 (29 Sep 2026): once a week the CEO sends a one-page PDF review (suppliers per category, '
   || 'cash and runway, spend against budget, open risks, each seat''s findings) naming the corrective action assigned '
   || 'for every missed target. Email only (level info). Informational: it asks for no approval.', 'ceo')
on conflict (kind) do update set allowed_to_email = excluded.allowed_to_email, reason = excluded.reason,
  owner_role = excluded.owner_role, updated_at = now();

-- ── 3. the review, one row per week ──────────────────────────────────────────────────────────────────────
create table if not exists public.ceo_weekly_review (
  id               bigint generated always as identity primary key,
  week             date not null unique,               -- the ISO week's Monday, Asia/Dubai
  targets          jsonb not null,                     -- fn_ceo_weekly_review_measure at review time
  opened           bigint[] not null default '{}',
  escalated        bigint[] not null default '{}',
  closed           bigint[] not null default '{}',
  pdf_blocks       jsonb,
  pdf_bucket       text,
  pdf_path         text,
  pdf_url          text,
  pdf_bytes        int,
  pdf_error        text,
  notification_id  bigint,
  notify           jsonb,
  delivered_at     timestamptz,
  attempts         int not null default 0,
  last_error       text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
alter table public.ceo_weekly_review enable row level security;
drop policy if exists ceo_weekly_review_service_role_only on public.ceo_weekly_review;
create policy ceo_weekly_review_service_role_only on public.ceo_weekly_review as permissive for all to public using (false) with check (false);
revoke all on public.ceo_weekly_review from anon, authenticated;

-- ── 4. the measure: one row per target and owning seat ───────────────────────────────────────────────────
-- Each row: {key, seat, label, met, value, target, actual, action, close_check, detail}. "value" is the number the
-- closing check compares (for supply: categories short; it closes when fewer are short than when it was opened).
create or replace function public.fn_ceo_weekly_review_measure(p_at timestamptz default now())
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_today date := (p_at at time zone 'Asia/Dubai')::date;
  v_min int := coalesce((select category_open_min_suppliers from public.pricing_config order by id limit 1), 10);
  v_out jsonb := '[]'::jsonb;
  v_trades int; v_short int; v_top jsonb;
  v_rf jsonb; v_months numeric; v_cash numeric; v_spend numeric;
  v_bud numeric; v_act numeric; v_nbud int; v_over jsonb;
  s record; v_n int; v_ids jsonb;
begin
  -- SUPPLY (sales_engineer)
  select count(*), count(*) filter (where matchable < v_min) into v_trades, v_short
    from public.supply_gap where emirate = 'UAE';
  select coalesce(jsonb_agg(jsonb_build_object('trade', x.trade, 'label', x.label, 'matchable', x.matchable,
           'requests_90d', x.demand_90d, 'uninvited_pool', x.uninvited_pool) order by x.demand_90d desc, x.uninvited_pool desc, x.matchable desc), '[]'::jsonb)
    into v_top
    from (select g.*, coalesce(t.label, g.trade) as label from public.supply_gap g left join public.taxonomy_trade t on t.code = g.trade
           where g.emirate = 'UAE' and g.matchable < v_min
           order by g.demand_90d desc, g.uninvited_pool desc, g.matchable desc limit 5) x;
  v_out := v_out || jsonb_build_object('key', 'supply', 'seat', 'sales_engineer', 'label', 'Suppliers per category',
    'met', v_trades > 0 and v_short = 0, 'value', v_short,
    'target', format('%s matchable suppliers in every category', v_min),
    'actual', case when v_trades = 0 then 'not measured: supply_gap holds no UAE rows (the supply duty has not run)'
                   else format('%s of %s categories at target; %s short', v_trades - v_short, v_trades, v_short) end,
    'action', case when v_trades = 0 then 'Run the supply-gap duty so every category is measured against the target.'
                   else format('Recruit to %s matchable suppliers per category, starting with %s.', v_min,
                     coalesce((select string_agg(e->>'label' || ' (' || (e->>'matchable') || ')', ', ') from (select e from jsonb_array_elements(v_top) e limit 3) z), 'the short categories')) end,
    'close_check', 'Closes when fewer categories are short than when it was opened (or none are).',
    'detail', v_top);

  -- RUNWAY (accountant)
  v_rf := public.fn_accountant_runway_figures(date_trunc('month', v_today)::date);
  v_months := (v_rf->>'runway_months_at_actual_spend')::numeric;
  v_cash := (v_rf->>'available_aed')::numeric; v_spend := (v_rf->>'monthly_spend_aed')::numeric;
  -- INFORMATION ONLY. Founder ruling, 29 Sep 2026 (ledger): there is NO runway target -- he funds the company himself,
  -- with no deadline, until it is profitable. Runway is shown (months at current spend) and is never a missed target,
  -- never opens an improvement and never escalates. Revisit ONLY if investor funding arrives.
  v_out := v_out || jsonb_build_object('key', 'runway', 'seat', 'accountant', 'label', 'Cash and runway',
    'info_only', true, 'met', true, 'value', v_months,
    'target', 'none: information only (founder funds the company until profitable; revisited only if investor funding arrives)',
    'actual', case when v_months is null then 'not measured: ' || coalesce(v_rf->>'missing', 'the books give no runway')
                   else format('AED %s available, AED %s a month, %s months at current spend', to_char(v_cash, 'FM999,999,990.00'), to_char(v_spend, 'FM999,999,990.00'), v_months) end,
    'detail', v_rf);

  -- SPEND AGAINST BUDGET (accountant): expense lines of active budgets for the year, to this month
  select count(distinct b.budget_id), sum(b.budget_amount), sum(b.actual_amount)
    into v_nbud, v_bud, v_act
    from public.budget_vs_actual b join public.budgets bu on bu.id = b.budget_id and bu.status = 'active'
   where b.fiscal_year = extract(year from v_today)::int and b.type = 'expense' and b.period_month <= v_today;
  select coalesce(jsonb_agg(jsonb_build_object('account', x.account_name, 'budget', x.bud, 'actual', x.act) order by x.act - x.bud desc), '[]'::jsonb)
    into v_over
    from (select b.account_name, sum(b.budget_amount) bud, sum(b.actual_amount) act
            from public.budget_vs_actual b join public.budgets bu on bu.id = b.budget_id and bu.status = 'active'
           where b.fiscal_year = extract(year from v_today)::int and b.type = 'expense' and b.period_month <= v_today
           group by b.account_name having sum(b.actual_amount) > sum(b.budget_amount) order by sum(b.actual_amount) - sum(b.budget_amount) desc limit 3) x;
  v_out := v_out || jsonb_build_object('key', 'budget', 'seat', 'accountant', 'label', 'Spend against budget',
    'met', v_nbud > 0 and v_act <= v_bud, 'value', case when v_nbud > 0 then v_act - v_bud end,
    'target', 'expense actuals year to date within an active budget',
    'actual', case when coalesce(v_nbud, 0) = 0 then format('no active budget for %s', extract(year from v_today))
                   else format('AED %s spent against AED %s budgeted year to date', to_char(v_act, 'FM999,999,990'), to_char(v_bud, 'FM999,999,990')) end,
    'action', case when coalesce(v_nbud, 0) = 0 then format('Set the %s expense budget by month and account, activate it, and report spend against it.', extract(year from v_today))
                   else format('Bring spend back inside budget: AED %s over, largest overrun %s.', to_char(v_act - v_bud, 'FM999,999,990'),
                          coalesce(v_over->0->>'account', '(none)')) end,
    'close_check', 'Closes when an active budget exists for the year and expense actuals year to date are within it.',
    'detail', v_over);

  -- RISKS and FINDINGS, per active seat (a row for every seat, met or not, so a closing check always finds its row)
  for s in select role_id from public.org_role where status = 'active' order by role_id loop
    select count(*), coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'risk', left(r.risk, 90), 'review_due', r.review_due) order by r.id), '[]'::jsonb)
      into v_n, v_ids
      from public.risk_register r
     where r.status = 'open'
       and (case when exists (select 1 from public.org_role o where o.role_id = r.owner_agent and o.status = 'active') then r.owner_agent else 'ceo' end) = s.role_id
       and (r.review_due is null or r.review_due < v_today or nullif(btrim(coalesce(r.mitigation, '')), '') is null);
    v_out := v_out || jsonb_build_object('key', 'risks', 'seat', s.role_id, 'label', 'Open risks', 'met', v_n = 0, 'value', v_n,
      'target', 'every open risk owned has a mitigation and a review date not passed',
      'actual', format('%s open risk(s) without a mitigation or past review', v_n),
      'action', format('Review risk(s) %s: write the mitigation and set the next review date.',
                       coalesce((select string_agg('#' || (e->>'id'), ', ') from jsonb_array_elements(v_ids) e), '-')),
      'close_check', 'Closes when every open risk this seat owns has a mitigation and a review date not passed.',
      'detail', v_ids);

    select count(*) filter (where f.started_at < p_at - interval '7 days'), count(*),
           coalesce(jsonb_agg(jsonb_build_object('key', f.issue_key, 'title', left(f.title, 90), 'since', f.started_at::date)
                              order by f.started_at) filter (where f.started_at < p_at - interval '7 days'), '[]'::jsonb)
      into v_n, v_short, v_ids
      from public.it_engineer_finding f
     where f.closed_at is null
       and (case when exists (select 1 from public.org_role o where o.role_id = coalesce(f.evidence->>'owner_seat', f.raised_by) and o.status = 'active')
                 then coalesce(f.evidence->>'owner_seat', f.raised_by) else 'it_engineer' end) = s.role_id;
    v_out := v_out || jsonb_build_object('key', 'findings', 'seat', s.role_id, 'label', 'Open findings', 'met', v_n = 0, 'value', v_n,
      'open_total', v_short,
      'target', 'no finding open more than 7 days',
      'actual', format('%s open, %s of them more than 7 days', v_short, v_n),
      'action', format('Close the %s finding(s) open more than 7 days, oldest first: %s.', v_n,
                       coalesce((select string_agg(e->>'title', '; ') from (select e from jsonb_array_elements(v_ids) e limit 3) z), '-')),
      'close_check', 'Closes when no finding attributed to this seat is open more than 7 days.',
      'detail', (select coalesce(jsonb_agg(e), '[]'::jsonb) from (select e from jsonb_array_elements(v_ids) e limit 5) z));
  end loop;
  return v_out;
end $fn$;
revoke execute on function public.fn_ceo_weekly_review_measure(timestamptz) from public, anon, authenticated;
grant execute on function public.fn_ceo_weekly_review_measure(timestamptz) to service_role;

-- ── 5. the one page ──────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_weekly_review_pdf_blocks(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare w public.ceo_weekly_review; v jsonb; t jsonb; li jsonb := '[]'::jsonb;
  f jsonb := '{}'::jsonb; v_find text;
begin
  select * into w from public.ceo_weekly_review where id = p_id;
  if not found then return null; end if;
  v := jsonb_build_array(
    jsonb_build_object('t', 'h2', 'text', 'CEO weekly review'),
    jsonb_build_object('t', 'p', 'text', 'Week of ' || to_char(w.week, 'Dy DD Mon YYYY') || ' (Asia/Dubai). '
      || (select count(*) from jsonb_array_elements(w.targets) x where (x->>'met')::boolean and not coalesce((x->>'info_only')::boolean, false)) || ' of '
      || (select count(*) from jsonb_array_elements(w.targets) x where not coalesce((x->>'info_only')::boolean, false)) || ' targets met. Actions: ' || cardinality(w.opened) || ' opened, '
      || cardinality(w.escalated) || ' escalated, ' || cardinality(w.closed) || ' closed.'),
    jsonb_build_object('t', 'h3', 'text', 'Actions assigned'));

  -- escalated first, then the rest still open; each with owner, due date and the check that closes it
  for t in select jsonb_build_object('line',
             case when i.escalations > 0 then 'ESCALATED x' || i.escalations || ' ' else '' end
             || i.seat || ': ' || (select case when length(a) > 200 then left(a, 197) || '...' else a end
                                     from (select coalesce(i.evidence->>'action', i.proposal) as a) z)
             || ' Due ' || to_char(i.due_on, 'DD Mon') || '. ' || coalesce(i.close_check, ''))
             from public.ceo_improvement i
            where i.source_kind = 'weekly_review' and i.status in ('open', 'assigned')
            order by i.escalations desc, i.seat, i.id limit 12 loop
    li := li || jsonb_build_object('t', 'li', 'text', t->>'line');
  end loop;
  if jsonb_array_length(li) = 0 then li := jsonb_build_array(jsonb_build_object('t', 'li', 'text', 'Every target is met; no action is open.')); end if;
  v := v || li;

  for t in select x from jsonb_array_elements(w.targets) x where x->>'key' in ('supply', 'runway', 'budget') loop
    v := v || jsonb_build_array(
      jsonb_build_object('t', 'h3', 'text', t->>'label'),
      jsonb_build_object('t', 'li', 'text', case when coalesce((t->>'info_only')::boolean, false) then 'INFORMATION ONLY. '
                                                        when (t->>'met')::boolean then 'MET. ' else 'MISSED. ' end
        || (t->>'actual') || '. Target: ' || (t->>'target') || '.'));
    if t->>'key' = 'supply' and jsonb_array_length(coalesce(t->'detail', '[]'::jsonb)) > 0 then
      v := v || jsonb_build_array(jsonb_build_object('t', 'li', 'text', 'Shortest where demand is: ' ||
        (select string_agg((e->>'label') || ' ' || (e->>'matchable') || '/' || (select coalesce(category_open_min_suppliers, 10) from public.pricing_config order by id limit 1), ', ')
           from jsonb_array_elements(t->'detail') e)));
    end if;
  end loop;

  v := v || jsonb_build_array(jsonb_build_object('t', 'h3', 'text', 'Open risks'));
  li := coalesce((select jsonb_agg(jsonb_build_object('t', 'li', 'text', '#' || r.id || ' ' || left(r.risk, 110)
          || ' (owner ' || coalesce(r.owner_agent, 'none') || ', ' || r.probability || '/' || r.impact
          || coalesce(', review ' || to_char(r.review_due, 'DD Mon'), ', no review date') || ')') order by r.id)
          from (select * from public.risk_register where status = 'open' order by id limit 5) r), '[]'::jsonb);
  v := v || case when jsonb_array_length(li) = 0 then jsonb_build_array(jsonb_build_object('t', 'li', 'text', 'None open.')) else li end;

  select string_agg((x->>'seat') || ' ' || coalesce(x->>'open_total', '0') || ' (' || (x->>'value') || ' over 7 days)', ', ' order by x->>'seat')
    into v_find from jsonb_array_elements(w.targets) x where x->>'key' = 'findings';
  v := v || jsonb_build_array(jsonb_build_object('t', 'h3', 'text', 'Open findings by seat'),
                              jsonb_build_object('t', 'li', 'text', coalesce(v_find, 'none')),
                              jsonb_build_object('t', 'note', 'text', 'Measured by code, no model. Each action is a tracked improvement; the next review closes it when its check passes, or escalates it.'));
  return v;
end $fn$;
revoke execute on function public.fn_ceo_weekly_review_pdf_blocks(bigint) from public, anon, authenticated;
grant execute on function public.fn_ceo_weekly_review_pdf_blocks(bigint) to service_role;

-- ── 6. the review: close, escalate, open, then the page ──────────────────────────────────────────────────
create or replace function public.fn_ceo_weekly_review(p_week date, p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_targets jsonb; t jsonb; i record; v_id bigint; v_task bigint;
  v_open bigint[] := '{}'; v_esc bigint[] := '{}'; v_closed bigint[] := '{}'; v_row public.ceo_weekly_review;
  v_today date := (p_at at time zone 'Asia/Dubai')::date;
begin
  select * into v_row from public.ceo_weekly_review where week = p_week;
  if found then return jsonb_build_object('week', p_week, 'already', true, 'id', v_row.id); end if;

  v_targets := public.fn_ceo_weekly_review_measure(p_at);

  -- 1. CLOSE: the check of each open action, re-read on the same measure
  for i in select * from public.ceo_improvement where source_kind = 'weekly_review' and status in ('open', 'assigned') loop
    select x into t from jsonb_array_elements(v_targets) x
     where x->>'key' = i.evidence->>'target' and x->>'seat' = i.seat limit 1;
    if t is not null and ((t->>'met')::boolean
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

  -- 3. OPEN: one action per missed target that has none open
  for t in select x from jsonb_array_elements(v_targets) x where not (x->>'met')::boolean loop
    if exists (select 1 from public.ceo_improvement where source_kind = 'weekly_review' and status in ('open', 'assigned')
                  and seat = t->>'seat' and evidence->>'target' = t->>'key') then continue; end if;
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
    'escalated', cardinality(v_esc), 'closed', cardinality(v_closed),
    'missed', (select count(*) from jsonb_array_elements(v_targets) x where not (x->>'met')::boolean));
end $fn$;
revoke execute on function public.fn_ceo_weekly_review(date, timestamptz) from public, anon, authenticated;
grant execute on function public.fn_ceo_weekly_review(date, timestamptz) to service_role;

-- ── 7. delivery through fn_notify_founder, with the PDF on the email it queued ───────────────────────────
create or replace function public.fn_ceo_weekly_review_deliver(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare w public.ceo_weekly_review; v_res jsonb; v_notif bigint; v_err text; v_file text; v_event text; v_missed int;
begin
  select * into w from public.ceo_weekly_review where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'no such ceo_weekly_review ' || p_id); end if;
  if w.delivered_at is not null then return jsonb_build_object('ok', true, 'week', w.week, 'already', true); end if;

  if w.pdf_path is null then
    v_err := 'not delivered: the PDF has not been rendered yet; retained, the next beat retries';
  else
    v_missed := (select count(*) from jsonb_array_elements(w.targets) x where not (x->>'met')::boolean);
    v_event := 'CEO weekly review, week of ' || to_char(w.week, 'DD Mon YYYY');
    v_file := 'QuotesDone_CEO_Weekly_Review_' || to_char(w.week, 'IYYY-"W"IW') || '.pdf';
    begin
      v_res := public.fn_notify_founder(p_event => v_event,
        p_detail => format(E'%s of %s targets missed this week. Actions: %s opened, %s escalated, %s closed.\nThe one-page review is attached as %s.',
               v_missed, (select count(*) from jsonb_array_elements(w.targets) x where not coalesce((x->>'info_only')::boolean, false)), cardinality(w.opened), cardinality(w.escalated), cardinality(w.closed), v_file),
        p_level => 'info', p_kind => 'ceo_weekly_review', p_dedupe_key => 'ceo_weekly_review:' || w.week, p_owner_agent => 'ceo');
      if coalesce((v_res->>'emailed')::boolean, false) then
        -- fn_notify_founder answers jsonb, not the row id: the email it queued is the one of this kind in THIS transaction.
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
end $fn$;
revoke execute on function public.fn_ceo_weekly_review_deliver(bigint) from public, anon, authenticated;
grant execute on function public.fn_ceo_weekly_review_deliver(bigint) to service_role;

-- The heartbeat renders (Postgres cannot) and hands the result back here, with renderPdfAndAttach's parameter names.
create or replace function public.fn_ceo_weekly_review_attach_pdf(
  p_id bigint, p_bucket text default null, p_path text default null, p_url text default null,
  p_bytes int default null, p_error text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if not exists (select 1 from public.ceo_weekly_review where id = p_id) then
    return jsonb_build_object('ok', false, 'error', 'no such ceo_weekly_review ' || p_id);
  end if;
  if p_path is null or coalesce(p_error, '') <> '' then
    update public.ceo_weekly_review set pdf_error = coalesce(nullif(p_error, ''), 'pdf_native returned no path'),
           attempts = attempts + 1, last_error = 'the PDF could not be rendered: ' || coalesce(nullif(p_error, ''), 'no path returned'), updated_at = now()
     where id = p_id;
    return jsonb_build_object('ok', false, 'retained', true, 'error', 'the PDF could not be rendered: ' || coalesce(nullif(p_error, ''), 'no path returned'));
  end if;
  update public.ceo_weekly_review set pdf_bucket = coalesce(p_bucket, 'agent-docs'), pdf_path = p_path, pdf_url = p_url,
         pdf_bytes = p_bytes, pdf_error = null, updated_at = now()
   where id = p_id;
  return public.fn_ceo_weekly_review_deliver(p_id);
end $fn$;
revoke execute on function public.fn_ceo_weekly_review_attach_pdf(bigint, text, text, text, int, text) from public, anon, authenticated;
grant execute on function public.fn_ceo_weekly_review_attach_pdf(bigint, text, text, text, int, text) to service_role;

-- ── 8. the tick: from Monday 09:00 Dubai (after the 08:00 company report), finish whatever is in flight ────
create or replace function public.fn_ceo_weekly_review_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_local timestamp := now() at time zone 'Asia/Dubai'; v_week date := date_trunc('week', v_local)::date;
  w public.ceo_weekly_review; v_run jsonb;
begin
  select * into w from public.ceo_weekly_review where week = v_week;
  if not found then
    if extract(isodow from v_local) = 1 and v_local::time < time '09:00' then
      return jsonb_build_object('fired', false, 'reason', 'before Monday 09:00 Asia/Dubai', 'week', v_week);
    end if;
    v_run := public.fn_ceo_weekly_review(v_week);
    select * into w from public.ceo_weekly_review where week = v_week;
  end if;
  if w.delivered_at is not null then
    return jsonb_build_object('fired', false, 'reason', 'already delivered', 'week', v_week, 'id', w.id);
  end if;
  if w.pdf_path is null then
    return jsonb_build_object('fired', true, 'pdf_pending', true, 'id', w.id, 'report_key', 'ceo_weekly_review_' || to_char(v_week, 'IYYY-"W"IW'),
      'subject', 'CEO weekly review, week of ' || to_char(v_week, 'DD Mon YYYY'), 'pdf_blocks', w.pdf_blocks, 'run', v_run);
  end if;
  return public.fn_ceo_weekly_review_deliver(w.id) || jsonb_build_object('fired', true);
end $fn$;
revoke execute on function public.fn_ceo_weekly_review_tick() from public, anon, authenticated;
grant execute on function public.fn_ceo_weekly_review_tick() to service_role;

insert into public.resilience_step (step, every, budget_ms, place, rank, note, owner_seat) values
  ('ceoWeeklyReview', interval '15 min', 5000, 'plan', 0,
   'ceo: from Monday 09:00 Dubai, the one-page weekly review that closes, escalates and opens tracked improvements for every missed target (fn_ceo_weekly_review_tick -> pdf_native -> fn_ceo_weekly_review_attach_pdf -> fn_notify_founder kind ceo_weekly_review)',
   'ceo')
on conflict (step) do update set every = excluded.every, budget_ms = excluded.budget_ms, place = excluded.place,
       note = excluded.note, owner_seat = excluded.owner_seat;

-- ── 9. the PDF column is registered for backup ──────────────────────────────────────────────────────────
-- every_storage_path_is_in_the_backup_registry requires every *_path column to be named. The file sits in agent-docs,
-- which the STORAGE SWEEP files. Rebuilt 29 Sep 2026 from the canonical definition on main
-- (the_founder_close_pack_pdf_is_backed_up_with_the_finance_reports.sql, #1090, last in MANIFEST) with the one row
-- ceo_weekly_review.pdf_path added. An older copy here dropped #1090's accountant_founder_close_pack.pdf_path row.
CREATE OR REPLACE FUNCTION public.fn_backup_source_registry()
 RETURNS TABLE(source text, kind text, bucket text, backed_up boolean, enqueue_rule text, reason text)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  values
    -- ── (a) backed up by an owner rule: each names the fn_enqueue_doc_backups section that files it ──
    ('leads.license_doc_path',               'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.egr_doc_path',                   'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.insurance_doc_path',             'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.vat_doc_path',                   'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.iso_doc_path',                   'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.manufacturer_auth_doc_path',     'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.company_profile_doc_path',       'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.catalog_doc_paths',              'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS (catalogue)', null),
    ('leads.signed_terms_path',              'column', 'signed-terms',  true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('customers.signed_terms_path',          'column', 'signed-terms',  true,  'fn_enqueue_doc_backups: CUSTOMERS', null),
    ('inquiries.drawing_file_path',          'column', 'drawing-files', true,  'fn_enqueue_doc_backups: INQUIRIES', null),
    ('transactions.doc_path',                'column', 'finance-docs',  true,  'fn_enqueue_doc_backups: REVENUE INVOICES', null),
    ('conversation_archive.pdf_path',        'column', 'backups',       true,  'fn_enqueue_doc_backups: CORRESPONDENCE', null),
    ('backups/<YYYY-MM-DD>/<table>/page_NNNN.json', 'export', 'backups', true, 'fn_enqueue_doc_backups: TABLE EXPORTS (written daily by supabase/functions/backup; the tables are fn_table_export_list()); kept 90 days, Friday full copies 12 months (fn_backup_prune_tick)', null),
    -- The accountant's four (open gaps until 14 Sep 2026, closed by
    -- the_accountant_files_the_year_end_pack_in_dropbox_and_the_backups_bucket.sql). A path stored as
    -- '<bucket>/<path>' names its bucket itself, so the bucket column is null for those two.
    ('accountant_month_close.pdf_path',      'column', 'finance-reports', true, 'fn_enqueue_doc_backups: ACCOUNTING', null),
    ('accountant_month_close.csv_path',      'column', 'finance-reports', true, 'fn_enqueue_doc_backups: ACCOUNTING', null),
    ('accountant_issued_document.file_path', 'column', null,              true, 'fn_enqueue_doc_backups: ACCOUNTING', null),
    ('bank_statement_intake.doc_path',       'column', null,              true, 'fn_enqueue_doc_backups: ACCOUNTING', null),

    -- ── (a) the buckets: every file an owner rule did not file is filed by the STORAGE SWEEP ──
    ('supplier-docs',    'bucket', 'supplier-docs',    true, 'fn_enqueue_doc_backups: SUPPLIERS; STORAGE SWEEP for every other file (inbound/, legal/, catalog/ ...)', null),
    ('signed-terms',     'bucket', 'signed-terms',     true, 'fn_enqueue_doc_backups: SUPPLIERS, CUSTOMERS; STORAGE SWEEP for every other signed record', null),
    ('drawing-files',    'bucket', 'drawing-files',    true, 'fn_enqueue_doc_backups: INQUIRIES; STORAGE SWEEP for every other file, the anonymised redacted/ copies included', null),
    ('finance-docs',     'bucket', 'finance-docs',     true, 'fn_enqueue_doc_backups: REVENUE INVOICES; STORAGE SWEEP for every other file', null),
    ('backups',          'bucket', 'backups',          true, 'fn_enqueue_doc_backups: CORRESPONDENCE, ACCOUNTING (the year-end pack in backups/accountant/year-end/), TABLE EXPORTS; dropbox_backup renders generated documents into backups/generated/; STORAGE SWEEP for everything outside the dated export folders, conversations/ and generated/ (archives/, engineering/, imports/ ...)', null),
    ('quote-files',      'bucket', 'quote-files',      true, 'fn_enqueue_doc_backups: STORAGE SWEEP (suppliers'' quotation files and the regenerated quotations)', null),
    ('compliance-docs',  'bucket', 'compliance-docs',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP (compliance sources as downloaded, the UAE library)', null),
    ('receipt-files',    'bucket', 'receipt-files',    true, 'fn_enqueue_doc_backups: ACCOUNTING (bank statements); STORAGE SWEEP for the expense receipts (the inbound mailbox keeps about a month)', null),
    ('agent-docs',       'bucket', 'agent-docs',       true, 'fn_enqueue_doc_backups: STORAGE SWEEP (quotations and invoices as sent, weekly reports, incident PDFs)', null),
    ('finance-reports',  'bucket', 'finance-reports',  true, 'fn_enqueue_doc_backups: ACCOUNTING (month close); STORAGE SWEEP for every other report and legal notice', null),
    ('reports',          'bucket', 'reports',          true, 'fn_enqueue_doc_backups: STORAGE SWEEP (board and executive report PDFs; their rows are not in the daily table export)', null),
    ('social-media',     'bucket', 'social-media',     true, 'fn_enqueue_doc_backups: STORAGE SWEEP (generated post cards and avatars; not in the repository)', null),
    ('brand',            'bucket', 'brand',            true, 'fn_enqueue_doc_backups: STORAGE SWEEP (brand kit, signature and stamp images; not in the repository)', null),
    ('kb-import-assets', 'bucket', 'kb-import-assets', true, 'fn_enqueue_doc_backups: STORAGE SWEEP (knowledge import runs; only part of it is in the repository)', null),
    ('site',             'bucket', 'site',             true, 'fn_enqueue_doc_backups: STORAGE SWEEP (the static website pages as first published)', null),
    ('marketing-media',  'bucket', 'marketing-media',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP (the media of the posts the founder and Claude ingest to the marketing seat; private, not in the repository)', null),

    -- ── (a) columns whose files are filed by the STORAGE SWEEP of the bucket they sit in ──
    -- measured 15 Sep 2026 where rows exist; "no writer today" where no code writes the column yet
    ('quotes.original_file_path',            'column', 'quote-files',      true, 'fn_enqueue_doc_backups: STORAGE SWEEP (written by supplier_api)', null),
    ('accountant_founder_close_pack.pdf_path', 'column', 'finance-reports', true, 'fn_enqueue_doc_backups: STORAGE SWEEP (the accountant function renders the founder close pack into finance-reports)', null),
    ('quote_spec_hold.pdf_path',             'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (bucket in quote_spec_hold.pdf_bucket; the regenerated quotations sit in quote-files)', null),
    ('quote_reviews.original_file_path',     'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('quote_committed_items.sub_quote_path', 'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('quote_items.datasheet_path',           'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('rfq_archives.archive_path',            'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (bucket in rfq_archives.bucket; backups/archives/ is swept)', null),
    ('compliance_sources.doc_path',          'column', 'compliance-docs',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP (16 of 16 paths in compliance-docs)', null),
    ('support_artifact.storage_path',        'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('support_document_intake.storage_path', 'column', 'supplier-docs',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (the path is the one written into leads.*_doc_path)', null),
    ('wa_document_intake.storage_path',      'column', 'supplier-docs',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (the path is the one written into leads.*_doc_path)', null),
    ('messages.attachment_path',             'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (bucket chosen by the portal, recorded in public.documents)', null),
    ('customer_calls.recording_path',        'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('refunds.doc_path',                     'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('supplier_dues.demand_letter_path',     'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today; the legal notices on file sit in supplier-docs/legal/ and finance-reports/legal/)', null),
    ('supplier_dues.case_file_path',         'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('supplier_dues.evidence_terms_path',    'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('expense_entries.doc_path',             'column', 'receipt-files',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (52 of 52 paths in receipt-files; the inbound mailbox keeps about a month)', null),
    ('doc_reviews.file_path',                'column', 'supplier-docs',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (7 of 7 paths in supplier-docs/inbound/, none filed by an owner rule)', null),
    ('supplier_catalog.source_document_path','column', 'supplier-docs',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (written by supplier_catalog_ingest into supplier-docs/catalog/)', null),
    ('drawing_redaction_runs.source_path',   'column', 'drawing-files',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (the customer''s original drawing; also INQUIRIES)', null),
    ('accountant_weekly_report.pdf_path',    'column', 'agent-docs',       true, 'fn_enqueue_doc_backups: STORAGE SWEEP (agent-docs/accountant/weekly/)', null),
    ('accountant_spend_report.pdf_path',     'column', 'finance-reports',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP (finance-reports/accountant/spend/)', null),
    ('finance_reports.html_path',            'column', 'finance-reports',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP', null),
    ('finance_reports.xlsx_path',            'column', 'finance-reports',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP', null),
    ('finance_reports.pdf_path',             'column', 'finance-reports',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP', null),
    ('board_reports.pdf_path',               'column', 'reports',          true, 'fn_enqueue_doc_backups: STORAGE SWEEP (20 of 20 paths in reports)', null),
    ('exec_reports.pdf_path',                'column', 'reports',          true, 'fn_enqueue_doc_backups: STORAGE SWEEP (2 of 2 paths in reports)', null),
    ('it_incident.pdf_path',                 'column', 'agent-docs',       true, 'fn_enqueue_doc_backups: STORAGE SWEEP (rendered into agent-docs/it_engineer/incidents/)', null),
    ('ceo_daily_digest.pdf_path',            'column', 'agent-docs',       true, 'fn_enqueue_doc_backups: STORAGE SWEEP (rendered into agent-docs/ceo/daily_brief/)', null),
    ('ceo_weekly_report.pdf_path',           'column', 'agent-docs',       true, 'fn_enqueue_doc_backups: STORAGE SWEEP (rendered into agent-docs by resilience_ping renderPdfAndAttach)', null),
    ('marketing_post.media_paths',           'column', 'marketing-media',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP (marketing-media/posts/<ingest_key>/, written by marketing_channels ingest)', null),
    ('marketing_post.video_path',            'column', 'marketing-media', true, 'fn_enqueue_doc_backups: STORAGE SWEEP (marketing-media/posts/<ingest_key>/, the calendar''s video, written by marketing_channels ingest)', null),
    ('marketing_post.cover_path',            'column', 'marketing-media', true, 'fn_enqueue_doc_backups: STORAGE SWEEP (marketing-media/posts/<ingest_key>/, the cover image, written by marketing_channels ingest)', null),
    ('marketing_post_variant.cover_path',    'column', 'marketing-media', true, 'fn_enqueue_doc_backups: STORAGE SWEEP (marketing-media, a platform''s own cover image)', null),
    ('marketing_campaign.calendar_pdf_path', 'column', 'agent-docs',     true, 'fn_enqueue_doc_backups: STORAGE SWEEP (agent-docs/marketing/calendar/<campaign_key>/, the monthly calendar PDF the founder approves)', null),
    ('marketing_campaign.calendar_xlsx_path', 'column', 'agent-docs',     true, 'fn_enqueue_doc_backups: STORAGE SWEEP (agent-docs/marketing/calendar/<campaign_key>/, the same calendar as a spreadsheet)', null),
    ('ceo_weekly_review.pdf_path',           'column', 'agent-docs',     true, 'fn_enqueue_doc_backups: STORAGE SWEEP (agent-docs/ceo/weekly_review/, the CEO''s one-page weekly review PDF)', null),

    -- ── (b) EXEMPT (not a file or not ours) ──
    ('doc_backups.dropbox_path',             'column', null, false, null, 'EXEMPT (not a file or not ours): the Dropbox destination of a backup, not a source'),
    ('pdpl_erase_files.storage_path',        'column', null, false, null, 'EXEMPT (not a file or not ours): the PDPL erasure ledger names files being REMOVED under a data subject''s request; fn_backup_sweep_objects never offers a file it names, so an erased file is never copied again'),
    ('pdpl_erase_files.dropbox_path',        'column', null, false, null, 'EXEMPT (not a file or not ours): the PDPL erasure ledger names Dropbox copies being REMOVED; never a source'),
    -- The knowledge source paths are LABELS: none of the sampled paths exists as a storage object or in
    -- the repository (review, 15 Sep 2026). The knowledge is the table rows, which the daily table export
    -- (fn_table_export_list) carries to Dropbox.
    ('support_knowledge.source_path',        'column', null, false, null, 'EXEMPT (not a file or not ours): a label naming where a knowledge entry came from, not a stored file; the entries themselves are table rows in the daily table export'),
    ('ops_knowledge.source_path',            'column', null, false, null, 'EXEMPT (not a file or not ours): a label naming where a knowledge entry came from, not a stored file; the entries themselves are table rows in the daily table export'),
    ('ceo_knowledge.source_path',            'column', null, false, null, 'EXEMPT (not a file or not ours): a label naming where a knowledge entry came from, not a stored file; the entries themselves are table rows in the daily table export'),
    ('cad_read_jobs.source_path',            'column', null, false, null, 'EXEMPT (not a file or not ours): a work-queue pointer to the customer''s original drawing in drawing-files, which is backed up through inquiries.drawing_file_path; the job holds no second copy'),
    ('marketing_first_touch.landing_path',  'column', null, false, null, 'EXEMPT (not a file or not ours): the site page (a URL path such as /en/suppliers) a supplier first landed on from a post, not a stored file; the row is in the daily table export'),
    ('marketing_asset_feature.asset_path',  'column', null, false, null, 'EXEMPT (not a file or not ours): a pointer to a post video already in marketing-media (backed up through marketing_post.video_path and media_paths); the feature row measures it and holds no second copy'),
    ('action_class_demand.on_revenue_path', 'column', null, false, null, 'EXEMPT (not a file or not ours): a boolean saying whether an action_class is on the revenue path; it names no file, and the row is in the daily table export'),
    ('ml-models',                            'bucket', null, false, null, 'EXEMPT (not a file or not ours): a copy of a public embedding model downloaded from Hugging Face for the multilingual embedder; it can be fetched again and holds no record'),
    ('supplier_campaign_daily_list.pdf_path', 'column', null, false, null, 'EXEMPT (not a file or not ours): the 18:00 supplier-list PDF is drawn from its own row (rows, pdf_blocks), which is in the daily table export; it can be rendered again'),
    ('demo-assets',                          'bucket', null, false, null, 'EXEMPT (not a file or not ours): a rehearsal fixture (one sample recording), never a record'),

    -- ── (c) EXEMPT (derived): no registry source. The one derived thing left out is a folder, not a
    -- source: signed-terms/registers/ (the customer register compliance_archive uploads to Dropbox
    -- itself), excluded in fn_backup_sweep_objects. The anonymised drawings are derived, but 2 of the 3
    -- redacted files have no original left (review, 15 Sep 2026), so they are kept like any other file. ──
    ('inquiries.drawing_redacted_paths',     'column', 'drawing-files', true, 'fn_enqueue_doc_backups: STORAGE SWEEP (drawing-files/redacted/; derived, but not every original survives)', null),
    ('drawing_redaction_runs.output_paths',  'column', 'drawing-files', true, 'fn_enqueue_doc_backups: STORAGE SWEEP (drawing-files/redacted/; derived, but not every original survives)', null)
$function$
;
revoke execute on function public.fn_backup_source_registry() from public, anon, authenticated;
