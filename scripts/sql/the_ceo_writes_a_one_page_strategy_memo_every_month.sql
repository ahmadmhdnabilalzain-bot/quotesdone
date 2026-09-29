-- THE CEO WRITES A ONE-PAGE STRATEGY MEMO EVERY MONTH. Seat: ceo. Founder instruction 1013, item 4 (29 Sep 2026).
--
-- One page, four parts, every figure built by code:
--   1. MARKET CHANGES, from marketing's own tables: competitor pages whose content changed in the month
--      (public.competitor_scan, a content_hash that differs from the previous scan of the same page),
--      competitors (re)verified in the month (public.competitor.verified_at), and the trends marketing
--      judged relevant (public.marketing_trend where relevant).
--   2. CATEGORY GROWTH: per primary supplier category (public.lead_category.is_primary), suppliers added
--      and customer requests (public.inquiries.category) in the month against the month before.
--   3. ONE BET FOR NEXT MONTH with a measurable expected result: {metric, category, baseline, target}.
--      RULE: the category with the most requests this month, target = max(baseline + 1, ceil(baseline x 1.2))
--      requests next month; with no request anywhere, the category that added the most suppliers, same
--      target on suppliers added; with neither, the largest category by suppliers on file, target 1.
--      The wording may use the reasoning path; while the founder's model hold is on it is the rule-based
--      sentence below and wording_source says so. Nothing here calls a model.
--   4. GRADING OF LAST MONTH'S BET: the previous memo's bet is measured by the same code over the month it
--      was made for: hit (>= target), partial (> baseline), missed.
--
-- Delivery: public.fn_notify_founder(..., p_level 'info', p_kind 'ceo_strategy_memo', dedupe key per month,
-- owner 'ceo'). The kind is registered below in founder_mail_policy (allowed, owner ceo); level 'info' so
-- it is mail only, never a WhatsApp page. One memo per month (primary key); a re-run returns the memo.
-- Schedule: pg_cron 'ceo-strategy-memo-monthly', 06:00 Dubai on the 2nd, for the month that just ended.
-- Demo: the facts exclude demo suppliers and demo customers unless p_include_demo is true (probe only).

insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role)
values ('ceo_strategy_memo', true,
        'the CEO''s one-page monthly strategy memo: market changes, category growth, one bet and the grading of last month''s bet (founder instruction 1013, 29 Sep 2026)',
        'ceo')
on conflict (kind) do nothing;

create table if not exists public.ceo_strategy_memo (
  month          date primary key check (month = date_trunc('month', month)::date),
  facts          jsonb not null,
  bet            jsonb not null,
  grading        jsonb not null,
  wording_source text  not null,
  body           text  not null,
  notify         jsonb,
  include_demo   boolean not null default false,
  created_at     timestamptz not null default now()
);
alter table public.ceo_strategy_memo enable row level security;
drop policy if exists ceo_strategy_memo_service_role_only on public.ceo_strategy_memo;
create policy ceo_strategy_memo_service_role_only on public.ceo_strategy_memo
  as permissive for all to public using (false) with check (false);
revoke all on public.ceo_strategy_memo from anon, authenticated;

-- One measurement for both the bet and its grading, so a bet is graded by exactly what it promised.
create or replace function public.fn_ceo_strategy_measure(p_metric text, p_category text, p_from date, p_to date, p_include_demo boolean default false)
returns integer
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select case p_metric
    when 'inquiries' then (select count(*)::int from public.inquiries i left join public.customers c on c.id = i.customer_id
                            where i.category = p_category and (i.created_at at time zone 'Asia/Dubai')::date between p_from and p_to
                              and (p_include_demo or not coalesce(c.is_demo, false)))
    when 'suppliers_added' then (select count(*)::int from public.leads l join public.lead_category lc on lc.lead_id = l.id and lc.is_primary
                                  where lc.slug = p_category and (l.created_at at time zone 'Asia/Dubai')::date between p_from and p_to
                                    and (p_include_demo or not coalesce(l.is_demo, false)))
  end;
$fn$;

create or replace function public.fn_ceo_strategy_memo_facts(p_month date, p_include_demo boolean default false)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_m date := date_trunc('month', p_month)::date; v_e date; v_pm date; v_pe date;
  v_changed jsonb; v_verified jsonb; v_trends jsonb; v_cats jsonb;
begin
  v_e := (v_m + interval '1 month')::date - 1; v_pm := (v_m - interval '1 month')::date; v_pe := v_m - 1;

  select coalesce(jsonb_agg(jsonb_build_object('competitor', c.name, 'page', z.page_kind, 'url', z.url, 'on', z.on_day) order by z.on_day), '[]'::jsonb)
    into v_changed
    from (select competitor_id, page_kind, url, (requested_at at time zone 'Asia/Dubai')::date on_day, content_hash,
                 lag(content_hash) over (partition by competitor_id, page_kind order by requested_at) prev_hash
            from public.competitor_scan where content_hash is not null) z
    join public.competitor c on c.id = z.competitor_id
   where z.on_day between v_m and v_e and z.prev_hash is not null and z.prev_hash <> z.content_hash;

  select coalesce(jsonb_agg(jsonb_build_object('competitor', name, 'kind', kind, 'threat', threat_level) order by name), '[]'::jsonb)
    into v_verified from public.competitor where verified_at between v_m and v_e;

  select coalesce(jsonb_agg(jsonb_build_object('title', title, 'why', why_it_matters, 'url', url) order by seen_at desc), '[]'::jsonb)
    into v_trends
    from (select * from public.marketing_trend where relevant and (seen_at at time zone 'Asia/Dubai')::date between v_m and v_e
           order by seen_at desc limit 5) t;

  select coalesce(jsonb_agg(x order by (x->>'requests')::int desc, (x->>'suppliers_added')::int desc, x->>'category'), '[]'::jsonb)
    into v_cats
    from (select jsonb_build_object('category', slug,
                   'suppliers_added', public.fn_ceo_strategy_measure('suppliers_added', slug, v_m, v_e, p_include_demo),
                   'suppliers_added_prior', public.fn_ceo_strategy_measure('suppliers_added', slug, v_pm, v_pe, p_include_demo),
                   'requests', public.fn_ceo_strategy_measure('inquiries', slug, v_m, v_e, p_include_demo),
                   'requests_prior', public.fn_ceo_strategy_measure('inquiries', slug, v_pm, v_pe, p_include_demo),
                   'suppliers_on_file', n) x
            from (select lc.slug, count(*) n from public.lead_category lc join public.leads l on l.id = lc.lead_id
                   where lc.is_primary and (p_include_demo or not coalesce(l.is_demo, false))
                   group by lc.slug) s) y;

  return jsonb_build_object('month', to_char(v_m, 'YYYY-MM'), 'from', v_m, 'to', v_e,
    'market', jsonb_build_object('competitors_watched', (select count(*) from public.competitor where watched),
                                 'competitor_pages_changed', v_changed, 'competitors_verified', v_verified,
                                 'relevant_trends', v_trends),
    'categories', v_cats,
    'measured_at', now());
end $fn$;

create or replace function public.fn_ceo_strategy_memo(p_month date default null, p_include_demo boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_m date := date_trunc('month', coalesce(p_month, (v_today - interval '1 month')::date))::date; v_e date;
  f jsonb; c jsonb; v_bet jsonb; v_grade jsonb; prev public.ceo_strategy_memo; v_meas int; v_body text; v_n jsonb; v_base int;
begin
  if v_m >= date_trunc('month', v_today)::date then
    raise exception 'month % has not ended; the memo is written for a month that is over', to_char(v_m, 'YYYY-MM');
  end if;
  if exists (select 1 from public.ceo_strategy_memo where month = v_m) then
    return jsonb_build_object('ok', true, 'month', to_char(v_m, 'YYYY-MM'), 'already', true);
  end if;
  v_e := (v_m + interval '1 month')::date - 1;
  f := public.fn_ceo_strategy_memo_facts(v_m, p_include_demo);

  -- the bet (rule-based; see the header)
  select x into c from jsonb_array_elements(f->'categories') x where (x->>'requests')::int > 0
   order by (x->>'requests')::int desc, x->>'category' limit 1;
  if c is not null then
    v_base := (c->>'requests')::int;
    v_bet := jsonb_build_object('metric', 'inquiries', 'category', c->>'category', 'baseline', v_base);
  else
    select x into c from jsonb_array_elements(f->'categories') x where (x->>'suppliers_added')::int > 0
     order by (x->>'suppliers_added')::int - (x->>'suppliers_added_prior')::int desc, (x->>'suppliers_added')::int desc, x->>'category' limit 1;
    if c is null then
      select x into c from jsonb_array_elements(f->'categories') x order by (x->>'suppliers_on_file')::int desc, x->>'category' limit 1;
    end if;
    v_base := coalesce((c->>'suppliers_added')::int, 0);
    v_bet := jsonb_build_object('metric', 'suppliers_added', 'category', c->>'category', 'baseline', v_base);
  end if;
  v_bet := v_bet || jsonb_build_object('target', greatest(v_base + 1, ceil(v_base * 1.2)::int),
    'month', to_char((v_m + interval '1 month')::date, 'YYYY-MM'));
  v_bet := v_bet || jsonb_build_object('wording', format('In %s we focus on %s: %s from %s to at least %s.',
    to_char((v_m + interval '1 month')::date, 'Mon YYYY'), coalesce(v_bet->>'category', 'no category on file'),
    case v_bet->>'metric' when 'inquiries' then 'customer requests' else 'suppliers added' end, v_bet->>'baseline', v_bet->>'target'));

  -- the grading of last month's bet, measured by the same code over the month it was made for
  select * into prev from public.ceo_strategy_memo where month = (v_m - interval '1 month')::date;
  if prev.month is null then
    v_grade := jsonb_build_object('grade', 'none', 'note', 'no memo, so no bet, for ' || to_char((v_m - interval '1 month')::date, 'Mon YYYY'));
  else
    v_meas := public.fn_ceo_strategy_measure(prev.bet->>'metric', prev.bet->>'category', v_m, v_e, prev.include_demo);
    v_grade := prev.bet || jsonb_build_object('measured', v_meas,
      'grade', case when v_meas >= (prev.bet->>'target')::int then 'hit'
                    when v_meas > (prev.bet->>'baseline')::int then 'partial' else 'missed' end);
  end if;

  v_body := 'CEO STRATEGY MEMO - ' || to_char(v_m, 'FMMonth YYYY') || E'\n\n'
    || '1. MARKET CHANGES' || E'\n'
    || format('  Competitors watched %s. Pages that changed this month: %s. Competitors re-verified: %s. Relevant trends: %s.',
              f#>>'{market,competitors_watched}', jsonb_array_length(f#>'{market,competitor_pages_changed}'),
              jsonb_array_length(f#>'{market,competitors_verified}'), jsonb_array_length(f#>'{market,relevant_trends}')) || E'\n'
    || coalesce((select string_agg('  - ' || (x->>'competitor') || ' changed its ' || (x->>'page') || ' page (' || (x->>'on') || ')', E'\n')
                   from (select x from jsonb_array_elements(f#>'{market,competitor_pages_changed}') x limit 5) z) || E'\n', '')
    || coalesce((select string_agg('  - Trend: ' || (x->>'title') || coalesce(' - ' || (x->>'why'), ''), E'\n')
                   from jsonb_array_elements(f#>'{market,relevant_trends}') x) || E'\n', '')
    || E'\n' || '2. CATEGORY GROWTH (this month / month before)' || E'\n'
    || coalesce((select string_agg(format('  %-40s requests %s / %s, suppliers added %s / %s', x->>'category', x->>'requests', x->>'requests_prior',
                                          x->>'suppliers_added', x->>'suppliers_added_prior'), E'\n')
                   from (select x from jsonb_array_elements(f->'categories') x limit 5) z), '  no category on file') || E'\n\n'
    || '3. THE BET FOR ' || upper(to_char((v_m + interval '1 month')::date, 'FMMonth YYYY')) || E'\n'
    || '  ' || (v_bet->>'wording') || E'\n'
    || '  Measured by: ' || (v_bet->>'metric') || ' in ' || coalesce(v_bet->>'category', '-') || ', expected result ' || (v_bet->>'target') || '.' || E'\n\n'
    || '4. LAST MONTH''S BET' || E'\n'
    || case when v_grade->>'grade' = 'none' then '  ' || (v_grade->>'note')
            else format('  %s  Result %s against a target of %s (baseline %s): %s.', v_grade->>'wording', v_grade->>'measured',
                        v_grade->>'target', v_grade->>'baseline', upper(v_grade->>'grade')) end || E'\n\n'
    || 'Every figure is measured from the live tables at the moment of writing. The bet''s wording is rule-based while the model hold is on.';

  insert into public.ceo_strategy_memo (month, facts, bet, grading, wording_source, body, include_demo)
  values (v_m, f, v_bet, v_grade, 'rule_based (model hold on)', v_body, p_include_demo);

  v_n := public.fn_notify_founder(p_event => 'CEO strategy memo - ' || to_char(v_m, 'FMMonth YYYY'), p_detail => v_body,
                                  p_level => 'info', p_kind => 'ceo_strategy_memo',
                                  p_dedupe_key => 'ceo_strategy_memo:' || to_char(v_m, 'YYYY-MM') || case when p_include_demo then ':zz-demo' else '' end,
                                  p_owner_agent => 'ceo');
  update public.ceo_strategy_memo set notify = v_n where month = v_m;
  return jsonb_build_object('ok', true, 'month', to_char(v_m, 'YYYY-MM'), 'bet', v_bet, 'grading', v_grade, 'notify', v_n);
end $fn$;

revoke execute on function public.fn_ceo_strategy_measure(text, text, date, date, boolean) from public, anon, authenticated;
revoke execute on function public.fn_ceo_strategy_memo_facts(date, boolean) from public, anon, authenticated;
revoke execute on function public.fn_ceo_strategy_memo(date, boolean) from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'ceo-strategy-memo-monthly';
select cron.schedule('ceo-strategy-memo-monthly', '0 2 2 * *', 'select public.fn_ceo_strategy_memo()');
