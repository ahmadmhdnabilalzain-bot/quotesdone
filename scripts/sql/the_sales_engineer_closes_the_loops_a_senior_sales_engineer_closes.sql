-- THE SALES ENGINEER CLOSES THE LOOPS A SENIOR SALES ENGINEER CLOSES (sales_engineer, founder ledger 1003 stage 2, 19 Oct 2026).
--
-- Assigned: sales_engineer. Stage 1 of ledger 1003 measured the seat against a 20-year senior bar
-- (knowledge/standards/sales_engineer.json in the seat-audit branch): 3 contributions partial, 3 missing. Each becomes
-- a seat_duty here that ACTS -- writes the report, sends the round, hands the brief, opens the improvement -- in code,
-- no model. Same shape as the CEO's (#1526).
--
-- ══ MEASURED, 19 Oct 2026, htdblwldjkcgjvmqkbeh ═══════════════════════════════════════════════════════════════════
--   SE-C03  sales_engineer.comparison_kpi MEASURES qd_compare_cache (written by the quote_compare edge function when a
--           customer opens the comparison); no duty WRITES a levelled comparison on a clock, so 0 reports in the window.
--   SE-C04  supplier_onboarding stages (invited 171 / quoting 1) are kept daily; nothing reports stage conversion or
--           the marketing invite campaign's share of it.
--   SE-C07  supply_gap: every row deferred (rule:nobody_waiting -- there is no demand before launch, customers from
--           Jan 2027). fn_sales_engineer_supply_gap_to_recruitment_brief exists but nothing calls it any more, so no
--           supply_recruitment_brief row reached marketing.
--   SE-C12  no duty runs a clarification or best-and-final round.
--   SE-C13  customer_followup records hired yes/no; nothing reads it as a win/loss review or measures leakage.
--   SE-C14  nothing finds repeat demand or drafts a framework.
--
-- ══ WHAT THIS ADDS (one duty per contribution) ════════════════════════════════════════════════════════════════════
--   SE-C03 sales_engineer.comparison_report  hourly  every open request with a quote and either 3+ complete quotes or a
--          first quote 48h old gets a LEVELLED report in sales_engineer_comparison_report (per quote: ex-VAT price, VAT,
--          total, the five terms, what is missing), a recommendation (lowest complete total) and hours to comparison;
--          rewritten when the quotes change. The first report with 2+ quotes is delivered to the customer once.
--   SE-C04 sales_engineer.onboarding_conversion  weekly  stage conversion invited>clicked>registering>approved>matched>
--          quoting into sales_engineer_onboarding_week, with the week's invitations sent by the campaign; the worst
--          stage with 20+ suppliers in it and under 20% onward opens an improvement to the seat that owns it
--          (marketing before registration, sales_engineer after).
--   SE-C07 sales_engineer.supply_gap_recruitment  daily  before launch nobody can be waiting, so up to 10 gaps a Dubai
--          day with an uninvited pool are reopened as 'rule:pre_launch_build' (largest pool first) and the brief
--          routine turns them into supply_recruitment_brief rows marketing reads; briefs unread 3+ days are counted.
--   SE-C12 sales_engineer.negotiation_round  hourly  once a request is levelled: round 1 CLARIFY -- each incomplete
--          quote's supplier is asked for exactly the missing terms; round 2 BEST AND FINAL -- with 2+ complete quotes,
--          every complete quote gets the same single best-and-final invitation. The emails carry no rank and no comparison.
--   SE-C13 sales_engineer.win_loss_review  daily, acts monthly  last month's revealed / hired / not hired / no decision /
--          unrevealed-with-quotes and LEAKAGE (a request marked hired or completed with no reveal) into
--          sales_engineer_win_loss_month; leakage or a loss share over 50% opens a sales_engineer improvement.
--   SE-C14 sales_engineer.framework_proposal  weekly  a customer with 3+ requests in one trade in 180 days gets a drafted
--          framework in sales_engineer_framework_proposal and a CEO task to approve its rates (pricing is never the
--          seat's). Nothing is sent to the customer by this duty.
--
-- DEMO NEVER REACHES A REAL PERSON: C03, C12 and C14 read fixture requests only in a probe's fixture mode
-- (qd.duty_fixtures = 'on'), real ones otherwise; and a message goes only where the request's demo-ness equals the address's
-- (fn_inquiry_is_demo vs fn_is_demo_email), and @example.invalid never leaves send_outbox. Nothing here notifies the
-- founder. NOT CHANGED: fn_sales_engineer_comparison_kpi, fn_sales_engineer_supplier_onboarding,
-- fn_sales_engineer_supply_gap, fn_sales_engineer_supply_gap_to_recruitment_brief (called, not redefined).
-- Prevented by: scripts/checks/the_sales_engineer_senior_duties_are_registered_and_act.test.mjs and the
-- aborted-transaction probe the_sales_engineer_closes_the_loops_a_senior_sales_engineer_closes_probe.sql.
--
--   node scripts/apply_sql.mjs scripts/sql/the_sales_engineer_closes_the_loops_a_senior_sales_engineer_closes.sql --apply --ddl

-- ── SE-C03 ────────────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.sales_engineer_comparison_report (
  inquiry_id          uuid primary key references public.inquiries(id) on delete cascade,
  quotes_hash         text not null,
  quotes_n            int not null,
  complete_n          int not null,
  lines               jsonb not null,     -- one levelled line per quote (no supplier identity)
  recommended_quote_id uuid,
  recommendation      text not null,
  hours_to_report     numeric,
  delivered_at        timestamptz,
  delivery_handoff_id bigint,
  reported_at         timestamptz not null default now(),
  refreshed_at        timestamptz not null default now()
);
alter table public.sales_engineer_comparison_report enable row level security;
drop policy if exists sales_engineer_comparison_report_service_role_only on public.sales_engineer_comparison_report;
create policy sales_engineer_comparison_report_service_role_only on public.sales_engineer_comparison_report as permissive for all to public using (false) with check (false);
revoke all on public.sales_engineer_comparison_report from anon, authenticated;

create or replace function public.fn_sales_engineer_comparison_report()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; v_lines jsonb; v_hash text; v_best uuid; v_rec text; v_n int; v_c int; v_old public.sales_engineer_comparison_report;
  n_new int := 0; n_refreshed int := 0; n_delivered int := 0; v_cust record; v_h bigint; v_first timestamptz;
begin
  for r in select i.id, i.created_at, i.customer_id, public.fn_inquiry_is_demo(i.id) demo
             from public.inquiries i
            where coalesce(i.status, 'open') not in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost')
              and public.fn_inquiry_is_demo(i.id) = (coalesce(current_setting('qd.duty_fixtures', true), '') = 'on')
              and exists (select 1 from public.quotes q where q.inquiry_id = i.id and q.stale_at is null
                             and coalesce(q.status, 'submitted') not in ('withdrawn', 'rejected', 'expired', 'draft')) loop
    with q as (
      select q.id, coalesce(q.price_ex_vat, q.quote_amount) ex_vat, coalesce(q.vat_amount, 0) vat, q.created_at,
             array_remove(array[case when coalesce(q.price_ex_vat, q.quote_amount) is null then 'price' end,
                   case when nullif(btrim(q.lead_time), '') is null then 'lead_time' end,
                   case when nullif(btrim(q.validity), '') is null then 'validity' end,
                   case when nullif(btrim(q.warranty), '') is null then 'warranty' end,
                   case when nullif(btrim(q.payment_terms), '') is null then 'payment_terms' end], null) missing,
             q.lead_time, q.validity, q.warranty, q.payment_terms, nullif(btrim(q.exclusions), '') exclusions
        from public.quotes q
       where q.inquiry_id = r.id and q.stale_at is null and coalesce(q.status, 'submitted') not in ('withdrawn', 'rejected', 'expired', 'draft'))
    select jsonb_agg(jsonb_build_object('quote_id', id, 'price_ex_vat', ex_vat, 'vat', vat, 'total', ex_vat + vat,
             'lead_time', lead_time, 'validity', validity, 'warranty', warranty, 'payment_terms', payment_terms,
             'exclusions', exclusions, 'missing', to_jsonb(missing), 'complete', cardinality(missing) = 0) order by ex_vat + vat nulls last, id),
           md5(string_agg(id::text || ':' || coalesce(ex_vat, 0) || ':' || cardinality(missing), ',' order by id)),
           count(*), count(*) filter (where cardinality(missing) = 0),
           (array_agg(id order by ex_vat + vat, id) filter (where cardinality(missing) = 0))[1],
           min(created_at)
      into v_lines, v_hash, v_n, v_c, v_best, v_first
      from q;
    -- a report is due with 3+ complete quotes, or once the first quote has waited 48 hours
    continue when v_c < 3 and v_first > now() - interval '48 hours';
    select * into v_old from public.sales_engineer_comparison_report where inquiry_id = r.id;
    continue when found and v_old.quotes_hash = v_hash;
    v_rec := case when v_best is null then format('No quote is complete yet (%s received); the missing terms are being asked for before a recommendation.', v_n)
                  else format('Recommended: the lowest complete total of %s complete quote(s) out of %s, levelled ex-VAT plus VAT on the same five terms.', v_c, v_n) end;
    insert into public.sales_engineer_comparison_report (inquiry_id, quotes_hash, quotes_n, complete_n, lines, recommended_quote_id, recommendation, hours_to_report)
    values (r.id, v_hash, v_n, v_c, v_lines, v_best, v_rec,
            round((extract(epoch from now() - (select created_at from public.inquiries where id = r.id)) / 3600)::numeric, 1))
    on conflict (inquiry_id) do update set quotes_hash = excluded.quotes_hash, quotes_n = excluded.quotes_n, complete_n = excluded.complete_n,
      lines = excluded.lines, recommended_quote_id = excluded.recommended_quote_id, recommendation = excluded.recommendation, refreshed_at = now();
    if v_old.inquiry_id is null then n_new := n_new + 1; else n_refreshed := n_refreshed + 1; end if;

    -- delivered to the customer once, when there are two quotes to compare
    if v_n >= 2 and coalesce(v_old.delivered_at, null) is null then
      select id, email into v_cust from public.customers where id = r.customer_id;
      if v_cust.email like '%@%' and public.fn_is_demo_email(v_cust.email) = r.demo then
        v_h := public.fn_sales_engineer_writes('comparison_ready', 'customer', v_cust.email, null, v_cust.id, r.id, null,
          'Your quotations are compared',
          format('%s quotations for your request are levelled side by side on the same terms (price before VAT, VAT, lead time, validity, warranty, payment terms). %s Open your request in your QuotesDone account to read the comparison.', v_n, v_rec),
          'تمت مقارنة عروض الأسعار',
          format('تمت مقارنة %s من عروض الأسعار لطلبكم على الشروط نفسها (السعر قبل الضريبة، الضريبة، مدة التوريد، الصلاحية، الضمان، شروط الدفع). يمكنكم الاطلاع على المقارنة من طلبكم في حسابكم على QuotesDone.', v_n),
          '{}', 'comparison_ready:' || r.id, null, jsonb_build_object('report', 'sales_engineer_comparison_report'));
        update public.sales_engineer_comparison_report set delivered_at = now(), delivery_handoff_id = v_h where inquiry_id = r.id;
        n_delivered := n_delivered + 1;
      end if;
    end if;
  end loop;
  return jsonb_build_object('reports_new', n_new, 'reports_refreshed', n_refreshed, 'delivered', n_delivered,
    'kpi_7d', public.fn_sales_engineer_comparison_kpi(7));
end $fn$;
revoke execute on function public.fn_sales_engineer_comparison_report() from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_comparison_report() to service_role;

-- ── SE-C04 ────────────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.sales_engineer_onboarding_week (
  week              date primary key,            -- ISO week's Monday, Dubai
  stages            jsonb not null,              -- suppliers now at each stage
  reached           jsonb not null,              -- suppliers who reached at least each stage
  conversion_pct    jsonb not null,              -- each stage -> the next, of those who reached it
  invites_sent_7d   int not null,                -- the marketing invite campaign's sends this week
  invites_clicked_7d int not null,
  bottleneck        text,
  improvement_id    bigint,
  recorded_at       timestamptz not null default now()
);
alter table public.sales_engineer_onboarding_week enable row level security;
drop policy if exists sales_engineer_onboarding_week_service_role_only on public.sales_engineer_onboarding_week;
create policy sales_engineer_onboarding_week_service_role_only on public.sales_engineer_onboarding_week as permissive for all to public using (false) with check (false);
revoke all on public.sales_engineer_onboarding_week from anon, authenticated;

create or replace function public.fn_sales_engineer_onboarding_conversion()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_week date := date_trunc('week', now() at time zone 'Asia/Dubai')::date;
  v_order text[] := array['invited', 'clicked', 'registering', 'approved', 'matched', 'quoting'];
  v_stages jsonb; v_reached jsonb := '{}'::jsonb; v_conv jsonb := '{}'::jsonb; i int; v_n int; v_next int;
  v_worst text; v_worst_pct numeric; v_imp bigint; v_sent int; v_clicked int;
begin
  select coalesce(jsonb_object_agg(stage, n), '{}'::jsonb) into v_stages from (select stage, count(*) n from public.supplier_onboarding group by stage) x;
  -- reached stage k = now at stage k or any later stage (action_required counts as registering; closed is left out)
  for i in 1 .. array_length(v_order, 1) loop
    select count(*) into v_n from public.supplier_onboarding o
     where array_position(v_order, case when o.stage = 'action_required' then 'registering' else o.stage end) >= i;
    v_reached := v_reached || jsonb_build_object(v_order[i], v_n);
  end loop;
  for i in 1 .. array_length(v_order, 1) - 1 loop
    v_n := (v_reached->>v_order[i])::int; v_next := (v_reached->>v_order[i + 1])::int;
    v_conv := v_conv || jsonb_build_object(v_order[i] || '>' || v_order[i + 1], case when v_n > 0 then round(100.0 * v_next / v_n, 1) end);
    if v_n >= 20 and 100.0 * v_next / v_n < 20 and (v_worst_pct is null or 100.0 * v_next / v_n < v_worst_pct) then
      v_worst := v_order[i]; v_worst_pct := round(100.0 * v_next / v_n, 1);
    end if;
  end loop;
  select count(*) filter (where n.type = 'supplier_invite' and n.created_at > now() - interval '7 days' and not public.fn_is_demo_email(n.to_email))
    into v_sent from public.notifications n where n.type = 'supplier_invite' and n.created_at > now() - interval '7 days';
  select count(*) into v_clicked from public.leads where invite_clicked_at > now() - interval '7 days' and not coalesce(is_demo, false);

  if v_worst is not null then
    v_imp := public.fn_ceo_improvement_open('funnel_stage_drop', 'supplier_onboarding:' || v_worst || ':' || v_week,
      case when v_worst in ('invited', 'clicked') then 'marketing' else 'sales_engineer' end,
      format('Supplier onboarding: only %s%% of the %s suppliers who reached "%s" moved on this week. Find why they stop at this stage and change what they receive there.',
             v_worst_pct, v_reached->>v_worst, v_worst),
      jsonb_build_object('week', v_week, 'stage', v_worst, 'conversion_pct', v_conv, 'reached', v_reached, 'invites_sent_7d', v_sent));
  end if;
  insert into public.sales_engineer_onboarding_week (week, stages, reached, conversion_pct, invites_sent_7d, invites_clicked_7d, bottleneck, improvement_id)
  values (v_week, v_stages, v_reached, v_conv, v_sent, v_clicked, v_worst, v_imp)
  on conflict (week) do update set stages = excluded.stages, reached = excluded.reached, conversion_pct = excluded.conversion_pct,
    invites_sent_7d = excluded.invites_sent_7d, invites_clicked_7d = excluded.invites_clicked_7d, bottleneck = excluded.bottleneck,
    improvement_id = coalesce(excluded.improvement_id, sales_engineer_onboarding_week.improvement_id), recorded_at = now();
  return jsonb_build_object('week', v_week, 'reached', v_reached, 'conversion_pct', v_conv, 'bottleneck', v_worst,
    'improvement_id', v_imp, 'invites_sent_7d', v_sent, 'invites_clicked_7d', v_clicked);
end $fn$;
revoke execute on function public.fn_sales_engineer_onboarding_conversion() from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_onboarding_conversion() to service_role;

-- ── SE-C07 ────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_sales_engineer_supply_gap_recruitment()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_day_start timestamptz := date_trunc('day', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai';
  v_budget int; v_reopened int; v_brief jsonb;
begin
  -- BEFORE LAUNCH NOBODY CAN BE WAITING (customers from Jan 2027), so 'nobody_waiting' would defer every gap forever.
  -- A senior sales engineer builds supply ahead of demand: up to 10 a Dubai day, largest uninvited pool first.
  v_budget := greatest(0, 10 - (select count(*) from public.supply_gap where decided_by = 'sales_engineer:recruitment_brief' and decided_at >= v_day_start)::int);
  update public.supply_gap g set status = 'open', decided_by = 'rule:pre_launch_build', decided_at = now(), held_id = null
   where (g.trade, g.emirate) in (select trade, emirate from public.supply_gap
                                   where status = 'deferred' and decided_by = 'rule:nobody_waiting' and uninvited_pool > 0 and matchable < target
                                   order by uninvited_pool desc, target - matchable desc, trade, emirate limit v_budget);
  get diagnostics v_reopened = row_count;
  v_brief := public.fn_sales_engineer_supply_gap_to_recruitment_brief(10);
  return jsonb_build_object('reopened_pre_launch', v_reopened, 'brief', v_brief,
    'briefs_open', (select count(*) from public.supply_recruitment_brief where status = 'open'),
    'briefs_unread_3d', (select count(*) from public.supply_recruitment_brief where status = 'open' and read_by_marketing_at is null and listed_at < now() - interval '3 days'),
    'gaps_by_status', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from public.supply_gap group by status) x));
end $fn$;
revoke execute on function public.fn_sales_engineer_supply_gap_recruitment() from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_supply_gap_recruitment() to service_role;

-- ── SE-C12 ────────────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.sales_engineer_negotiation_round (
  id          bigint generated always as identity primary key,
  inquiry_id  uuid not null references public.inquiries(id) on delete cascade,
  quote_id    uuid not null references public.quotes(id) on delete cascade,
  round       text not null check (round in ('clarify', 'best_and_final')),
  asked_for   jsonb not null,
  handoff_id  bigint,
  asked_at    timestamptz not null default now(),
  answered_at timestamptz,
  unique (quote_id, round)
);
alter table public.sales_engineer_negotiation_round enable row level security;
drop policy if exists sales_engineer_negotiation_round_service_role_only on public.sales_engineer_negotiation_round;
create policy sales_engineer_negotiation_round_service_role_only on public.sales_engineer_negotiation_round as permissive for all to public using (false) with check (false);
revoke all on public.sales_engineer_negotiation_round from anon, authenticated;

create or replace function public.fn_sales_engineer_negotiation_round()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; l jsonb; v_sup record; v_h bigint; n_clarify int := 0; n_bafo int := 0; n_answered int;
begin
  -- a round is answered when the supplier's quote has changed since it was asked (the levelled line moved)
  update public.sales_engineer_negotiation_round n set answered_at = now()
    from public.quotes q
   where n.answered_at is null and q.id = n.quote_id
     and (q.stale_at is not null or greatest(q.created_at, coalesce(q.committed_at, q.created_at)) > n.asked_at);
  get diagnostics n_answered = row_count;

  for r in select c.*, i.status, public.fn_inquiry_is_demo(c.inquiry_id) demo
             from public.sales_engineer_comparison_report c join public.inquiries i on i.id = c.inquiry_id
            where coalesce(i.status, 'open') not in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost')
              and public.fn_inquiry_is_demo(c.inquiry_id) = (coalesce(current_setting('qd.duty_fixtures', true), '') = 'on') loop
    for l in select * from jsonb_array_elements(r.lines) loop
      select q.id, q.supplier_id, lw.company_name, lower(nullif(btrim(coalesce(lw.claimed_by, lw.email)), '')) email
        into v_sup from public.quotes q join public.leads lw on lw.id = q.supplier_id where q.id = (l->>'quote_id')::uuid;
      -- demo never reaches a real person, and a real request never writes to a fixture
      continue when v_sup.email is null or public.fn_is_demo_email(v_sup.email) <> r.demo;
      if not (l->>'complete')::boolean then
        continue when exists (select 1 from public.sales_engineer_negotiation_round where quote_id = v_sup.id and round = 'clarify');
        v_h := public.fn_sales_engineer_writes('negotiation_clarify', 'supplier', v_sup.email, v_sup.supplier_id, null, r.inquiry_id, v_sup.id,
          'Please complete your quotation',
          format(E'Dear %s,\n\nYour quotation does not yet state: %s. Please add these in your supplier portal so the customer has your complete terms.',
                 coalesce(nullif(btrim(case when v_sup.company_name ~ '[؀-ۿ]' then '' else v_sup.company_name end), ''), 'supplier'),
                 (select string_agg(replace(x, '_', ' '), ', ') from jsonb_array_elements_text(l->'missing') x)),
          null, null, '{}', 'negotiation_clarify:' || v_sup.id, now() + interval '2 days', jsonb_build_object('round', 'clarify'));
        insert into public.sales_engineer_negotiation_round (inquiry_id, quote_id, round, asked_for, handoff_id)
        values (r.inquiry_id, v_sup.id, 'clarify', l->'missing', v_h);
        n_clarify := n_clarify + 1;
      elsif r.complete_n >= 2 then   -- every complete quote alike: the invitation never depends on a quote's position
        continue when exists (select 1 from public.sales_engineer_negotiation_round where quote_id = v_sup.id and round = 'best_and_final');
        v_h := public.fn_sales_engineer_writes('negotiation_best_and_final', 'supplier', v_sup.email, v_sup.supplier_id, null, r.inquiry_id, v_sup.id,
          'Invitation to submit your best and final offer',
          format(E'Dear %s,\n\nYour quotation for this request is complete. You are invited, once, to submit your best and final offer in your supplier portal within 48 hours: price, lead time or payment terms. If you keep your quotation as it is, nothing more is needed.',
                 coalesce(nullif(btrim(case when v_sup.company_name ~ '[؀-ۿ]' then '' else v_sup.company_name end), ''), 'supplier')),
          null, null, '{}', 'negotiation_bafo:' || v_sup.id, now() + interval '2 days', jsonb_build_object('round', 'best_and_final'));
        insert into public.sales_engineer_negotiation_round (inquiry_id, quote_id, round, asked_for, handoff_id)
        values (r.inquiry_id, v_sup.id, 'best_and_final', jsonb_build_array('price', 'lead_time', 'payment_terms'), v_h);
        n_bafo := n_bafo + 1;
      end if;
    end loop;
  end loop;
  return jsonb_build_object('clarify_sent', n_clarify, 'best_and_final_sent', n_bafo, 'answered', n_answered,
    'open_rounds', (select count(*) from public.sales_engineer_negotiation_round where answered_at is null));
end $fn$;
revoke execute on function public.fn_sales_engineer_negotiation_round() from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_negotiation_round() to service_role;

-- ── SE-C13 ────────────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.sales_engineer_win_loss_month (
  month               date primary key,
  requests_quoted     int not null,      -- non-demo requests created in the month with at least one quote
  revealed            int not null,
  hired               int not null,      -- follow-up answered 'yes'
  not_hired           int not null,      -- follow-up answered 'no'
  no_decision         int not null,      -- quoted, closed or expired, never revealed
  leakage_suspect     int not null,      -- marked hired/completed with no reveal on the platform
  loss_reasons        jsonb not null,
  improvement_id      bigint,
  recorded_at         timestamptz not null default now()
);
alter table public.sales_engineer_win_loss_month enable row level security;
drop policy if exists sales_engineer_win_loss_month_service_role_only on public.sales_engineer_win_loss_month;
create policy sales_engineer_win_loss_month_service_role_only on public.sales_engineer_win_loss_month as permissive for all to public using (false) with check (false);
revoke all on public.sales_engineer_win_loss_month from anon, authenticated;

create or replace function public.fn_sales_engineer_win_loss_review()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_m0 date := date_trunc('month', now() at time zone 'Asia/Dubai')::date; v_pm date := (v_m0 - interval '1 month')::date;
  v_from timestamptz := v_pm::timestamp at time zone 'Asia/Dubai'; v_to timestamptz := v_m0::timestamp at time zone 'Asia/Dubai';
  w public.sales_engineer_win_loss_month; v_imp bigint;
begin
  if exists (select 1 from public.sales_engineer_win_loss_month where month = v_pm) then
    return jsonb_build_object('month', v_pm, 'already_reviewed', true);
  end if;
  with i as (select i.* from public.inquiries i where i.created_at >= v_from and i.created_at < v_to and not public.fn_inquiry_is_demo(i.id)
                and exists (select 1 from public.quotes q where q.inquiry_id = i.id)),
       t as (select distinct t.inquiry_id from public.transactions t join i on i.id = t.inquiry_id where t.revealed_at is not null),
       f as (select distinct on (tx.inquiry_id) tx.inquiry_id, cf.hired from public.customer_followup cf join public.transactions tx on tx.id = cf.transaction_id
              join i on i.id = tx.inquiry_id where cf.answered_at is not null order by tx.inquiry_id, cf.answered_at desc)
  select v_pm, (select count(*) from i), (select count(*) from t),
         (select count(*) from f where hired = 'yes'), (select count(*) from f where hired = 'no'),
         (select count(*) from i where i.status in ('closed', 'expired', 'lost', 'cancelled') and i.id not in (select inquiry_id from t)),
         (select count(*) from i where (i.hired_supplier_id is not null or i.status = 'completed' or i.outcome ilike 'hired%') and i.id not in (select inquiry_id from t)),
         (select coalesce(jsonb_object_agg(reason, n), '{}'::jsonb) from (select coalesce(nullif(btrim(i.lost_reason), ''), 'not stated') reason, count(*) n
            from i where i.id not in (select inquiry_id from t) and i.status in ('closed', 'expired', 'lost', 'cancelled') group by 1) x),
         null, now()
    into w;
  if w.leakage_suspect > 0 or (w.requests_quoted >= 5 and w.no_decision > w.requests_quoted / 2) then
    v_imp := public.fn_ceo_improvement_open('self_review', 'win_loss:' || v_pm, 'sales_engineer',
      format('Win/loss %s: %s quoted requests, %s revealed, %s with no decision, %s suspected leakage (hired with no reveal). Call the no-decision and leaked customers, record why, and change the stage that loses them.',
             to_char(v_pm, 'Mon YYYY'), w.requests_quoted, w.revealed, w.no_decision, w.leakage_suspect),
      to_jsonb(w));
    w.improvement_id := v_imp;
  end if;
  insert into public.sales_engineer_win_loss_month select w.*;
  return to_jsonb(w) - 'recorded_at';
end $fn$;
revoke execute on function public.fn_sales_engineer_win_loss_review() from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_win_loss_review() to service_role;

-- ── SE-C14 ────────────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.sales_engineer_framework_proposal (
  id            bigint generated always as identity primary key,
  customer_id   uuid not null,
  trade         text not null,
  requests_180d int not null,
  quoted_total_aed numeric,
  draft         text not null,
  status        text not null default 'drafted' check (status in ('drafted', 'approved', 'declined', 'sent', 'signed')),
  ceo_task_id   bigint,
  created_at    timestamptz not null default now(),
  unique (customer_id, trade)
);
alter table public.sales_engineer_framework_proposal enable row level security;
drop policy if exists sales_engineer_framework_proposal_service_role_only on public.sales_engineer_framework_proposal;
create policy sales_engineer_framework_proposal_service_role_only on public.sales_engineer_framework_proposal as permissive for all to public using (false) with check (false);
revoke all on public.sales_engineer_framework_proposal from anon, authenticated;

create or replace function public.fn_sales_engineer_framework_proposal()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; v_id bigint; v_task bigint; n_drafted int := 0;
begin
  for r in select i.customer_id, t trade, count(*) n,
                  (select round(avg(q.quote_amount), 2) from public.quotes q join public.inquiries j on j.id = q.inquiry_id
                    where j.customer_id = i.customer_id and t = any(j.trades) and j.created_at > now() - interval '180 days') avg_quote
             from public.inquiries i, unnest(i.trades) t
            where i.created_at > now() - interval '180 days' and i.customer_id is not null
              and public.fn_inquiry_is_demo(i.id) = (coalesce(current_setting('qd.duty_fixtures', true), '') = 'on')
            group by i.customer_id, t having count(*) >= 3 loop
    continue when exists (select 1 from public.sales_engineer_framework_proposal where customer_id = r.customer_id and trade = r.trade);
    insert into public.sales_engineer_framework_proposal (customer_id, trade, requests_180d, quoted_total_aed, draft)
    values (r.customer_id, r.trade, r.n, r.avg_quote,
            format('Framework proposal (draft): %s requests for %s in 180 days, average quotation AED %s. Proposed: a 12-month framework for %s with pre-agreed rates from the best-performing suppliers, a fixed response time, and one levelled quotation per call-off. Rates and any fee change need the CEO''s approval before this is offered.',
                   r.n, r.trade, coalesce(r.avg_quote::text, 'not measured'), r.trade))
    returning id into v_id;
    v_task := public.fn_ceo_task_open(format('Approve framework proposal #%s (%s, %s requests)', v_id, r.trade, r.n),
      format('The sales engineer drafted framework proposal #%s for a repeat customer: %s requests for %s in 180 days. Approve or decline its rates; nothing is offered until you do.', v_id, r.n, r.trade));
    update public.sales_engineer_framework_proposal set ceo_task_id = v_task where id = v_id;
    n_drafted := n_drafted + 1;
  end loop;
  return jsonb_build_object('drafted', n_drafted,
    'by_status', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from public.sales_engineer_framework_proposal group by status) x));
end $fn$;
revoke execute on function public.fn_sales_engineer_framework_proposal() from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_framework_proposal() to service_role;

-- ── the duties ────────────────────────────────────────────────────────────────────────────────────────────────────
insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('sales_engineer.comparison_report', 'sales_engineer', interval '1 hour', 'fn_sales_engineer_comparison_report',
   'SE-C03: every open request with 3+ complete quotes, or a first quote 48h old, gets a levelled comparison and recommendation; delivered to the customer once at 2+ quotes.',
   'scripts/sql/the_sales_engineer_closes_the_loops_a_senior_sales_engineer_closes.sql'),
  ('sales_engineer.onboarding_conversion', 'sales_engineer', interval '7 days', 'fn_sales_engineer_onboarding_conversion',
   'SE-C04: weekly supplier stage conversion with the invite campaign''s sends; the worst stage under 20% opens an improvement to the seat that owns it.',
   'scripts/sql/the_sales_engineer_closes_the_loops_a_senior_sales_engineer_closes.sql'),
  ('sales_engineer.supply_gap_recruitment', 'sales_engineer', interval '1 day', 'fn_sales_engineer_supply_gap_recruitment',
   'SE-C07: up to 10 supply gaps a day are built ahead of launch into recruitment briefs marketing reads; briefs close at target.',
   'scripts/sql/the_sales_engineer_closes_the_loops_a_senior_sales_engineer_closes.sql'),
  ('sales_engineer.negotiation_round', 'sales_engineer', interval '1 hour', 'fn_sales_engineer_negotiation_round',
   'SE-C12: once levelled, incomplete quotes are asked for exactly their missing terms, then every complete quote gets the same single best-and-final invitation (no rank or comparison in either email).',
   'scripts/sql/the_sales_engineer_closes_the_loops_a_senior_sales_engineer_closes.sql'),
  ('sales_engineer.win_loss_review', 'sales_engineer', interval '1 day', 'fn_sales_engineer_win_loss_review',
   'SE-C13: last month''s win/loss and suspected off-platform leakage, once a month; leakage or a majority with no decision opens an improvement.',
   'scripts/sql/the_sales_engineer_closes_the_loops_a_senior_sales_engineer_closes.sql'),
  ('sales_engineer.framework_proposal', 'sales_engineer', interval '7 days', 'fn_sales_engineer_framework_proposal',
   'SE-C14: a repeat customer (3+ requests in one trade in 180 days) gets a drafted framework and a CEO task to approve its rates.',
   'scripts/sql/the_sales_engineer_closes_the_loops_a_senior_sales_engineer_closes.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;
