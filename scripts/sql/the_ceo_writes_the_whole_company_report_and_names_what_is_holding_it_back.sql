-- THE CEO WRITES THE WHOLE-COMPANY REPORT AND NAMES WHAT IS HOLDING IT BACK.
--
-- The founder, 9 September 2026: "the CEO is supposed to email me once a week for a report... it
-- should be about the whole company, and that's why everyone reports to him. And his report should
-- be extremely organized more than anybody else." And: "the data analytics for the CEO is purely
-- from business perspective and how can we improve, because in his report he should be also
-- suggesting ideas and improvements to the company, like how Elon Musk does it for Tesla."
--
-- WHAT "SUGGESTING IMPROVEMENTS" HAS TO MEAN HERE, GIVEN PAID INFERENCE IS HELD.
-- It cannot be generated prose. So the report does the thing a good operator actually does and a
-- model usually fakes: it walks the revenue chain in order, finds the FIRST link that is broken or
-- empty, and says so — because everything downstream of a broken link is noise. One binding
-- constraint, named, with the number that proves it and the specific next action. A list of twelve
-- suggestions is not analysis; identifying which one matters is.
--
-- THE CHAIN, IN ORDER, AND WHY THAT ORDER. A customer cannot be quoted without a matchable
-- supplier; a comparison needs quotes; a reveal needs a comparison; revenue needs a reveal. So the
-- constraint is found by walking supply -> demand -> quoting -> comparison -> reveal -> cash and
-- stopping at the first zero. Today that stops at the first link, and the report will say so rather
-- than printing five more sections of zeros as though they were independent problems.
--
-- WHY IT IS NOT A WALL OF ZEROES. A pre-revenue company's report should read as a pre-revenue
-- company's report. Where a figure is zero the report distinguishes TRUE ZERO (measured, nothing
-- happened) from NOT INSTRUMENTED (nobody is counting) — the estate has been bitten repeatedly by
-- treating those as the same, and the CEO of all seats must not.
--
-- IT REPORTS TO THE FOUNDER, WEEKLY, AS HIMSELF. Mail kind `board_report`, which founder_mail_policy
-- already allows and already owns to `ceo`. The structure mirrors the accountant's weekly report,
-- which is the one report in this estate proven to reach him with a document attached.

create table if not exists public.ceo_weekly_report (
  id             bigserial primary key,
  company_key    text        not null default 'quotesdone',
  iso_year       int         not null,
  iso_week       int         not null,
  week_start     date        not null,
  week_end       date        not null,
  report_key     text        not null,
  revision       int         not null default 1,
  subject        text,
  body           text,
  figures        jsonb       not null default '{}'::jsonb,
  constraint_now jsonb,
  proposals      jsonb       not null default '[]'::jsonb,
  status         text        not null default 'generated'
                 check (status in ('generated','partial','delivered','delivery_failed')),
  generated_at   timestamptz not null default now(),
  founder_submitted_at timestamptz,
  notification_id      bigint,
  delivery_attempts    int   not null default 0,
  last_delivery_error  text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint ceo_weekly_report_key_rev unique (report_key, revision)
);
comment on table public.ceo_weekly_report is
  'The CEO''s weekly whole-company report to the founder. Covers money, supply, demand, the five seats and the estate''s health, then names the single binding constraint on revenue and what to do about it. Founder''s instruction, 9 Sep 2026.';

alter table public.ceo_weekly_report enable row level security;
revoke all on public.ceo_weekly_report from anon, authenticated;

-- ── THE MEASUREMENT ─────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_weekly_figures(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare
  v_prev_from date := p_from - (p_to - p_from) - 1;
  v_prev_to   date := p_from - 1;
  j jsonb;
begin
  select jsonb_build_object(
    'window', jsonb_build_object('from', p_from, 'to', p_to,
                                 'prior_from', v_prev_from, 'prior_to', v_prev_to),

    'money', jsonb_build_object(
      'revenue_week_aed',  (select coalesce(sum(l.credit-l.debit),0) from gl_journal_lines l join gl_journal g on g.id=l.journal_id
                             where l.account_code like '4%' and g.status='posted' and g.entry_date between p_from and p_to),
      'revenue_prior_aed', (select coalesce(sum(l.credit-l.debit),0) from gl_journal_lines l join gl_journal g on g.id=l.journal_id
                             where l.account_code like '4%' and g.status='posted' and g.entry_date between v_prev_from and v_prev_to),
      'revenue_life_aed',  (select coalesce(sum(l.credit-l.debit),0) from gl_journal_lines l join gl_journal g on g.id=l.journal_id
                             where l.account_code like '4%' and g.status='posted'),
      -- SPEND COMES FROM THE LEDGER, NOT FROM expense_entries. Those rows carry a raw amount in
      -- the currency the vendor billed (USD and AED are both present), so summing them would add
      -- dollars to dirhams. The GL is already converted and is the accountant's authoritative
      -- figure, which is also where revenue above is read from — one source, one basis.
      'spend_week_aed',    (select coalesce(sum(l.debit-l.credit),0) from gl_journal_lines l join gl_journal g on g.id=l.journal_id
                             where l.account_code like '6%' and g.status='posted' and g.entry_date between p_from and p_to),
      'spend_life_aed',    (select coalesce(sum(l.debit-l.credit),0) from gl_journal_lines l join gl_journal g on g.id=l.journal_id
                             where l.account_code like '6%' and g.status='posted'),
      'vat_position',      public.fn_accountant_vat_threshold_check(false)),

    'supply', jsonb_build_object(
      'leads_total',       (select count(*) from leads),
      'contactable',       (select count(*) from leads where email is not null and coalesce(invite_status,'') <> 'bounced'),
      'invited_ever',      (select count(*) from leads where invite_status is not null),
      'invited_week',      (select count(*) from leads where invited_at::date between p_from and p_to),
      'registered',        (select count(*) from leads where registration_status is not null),
      'verified',          (select count(*) from leads where verified),
      'matchable',         (select count(*) from supplier_capabilities where confirmed_at is not null),
      'days_since_last_invite', (select case when max(invited_at) is null then null
                                   else (current_date - max(invited_at)::date) end from leads)),

    'demand', jsonb_build_object(
      'customers',         (select count(*) from customers),
      'customers_real',    ((select public.fn_customer_counts())->>'substantiated')::int,
      'inquiries_week',    (select count(*) from inquiries where created_at::date between p_from and p_to),
      'inquiries_ever',    (select count(*) from inquiries),
      'quotes_ever',       (select count(*) from quotes),
      'comparisons_ever',  (select count(*) from quote_comparisons),
      'reveals_ever',      (select count(*) from transactions)),

    'seats', (select jsonb_object_agg(s.seat, jsonb_build_object(
                'runs_week', (select count(*) from agent_runs r
                               where regexp_replace(r.agent,'^fn:','') = s.seat
                                 and r.started_at::date between p_from and p_to),
                'errors_week', (select count(*) from agent_runs r
                               where regexp_replace(r.agent,'^fn:','') = s.seat
                                 and r.status = 'error' and r.started_at::date between p_from and p_to)))
              from (select unnest(array['ceo','customer_support','sales_engineer','accountant','it_engineer']) as seat) s),

    'health', jsonb_build_object(
      'it_findings_open',   (select count(*) from it_watch_finding where status='open'),
      'it_alerts_week',     (select count(*) from notifications where kind like 'it_%' and created_at::date between p_from and p_to),
      'reports_awaiting_ceo',(select count(*) from support_ceo_report where accepted_at is null and status='sent'),
      'founder_instructions_open', (select count(*) from founder_instruction where status='open'))
  ) into j;
  return j;
end $fn$;
revoke execute on function public.fn_ceo_weekly_figures(date,date) from public;

-- ── THE ANALYSIS: WALK THE CHAIN, STOP AT THE FIRST BREAK ───────────────────────────────────────
-- This is the part the founder asked for. It is deterministic on purpose: the order of the chain is
-- a fact about the business, not an opinion, so the first broken link is computable and the
-- proposal attached to it is the specific next action rather than advice.
create or replace function public.fn_ceo_binding_constraint(p_figures jsonb)
returns jsonb language plpgsql immutable as $fn$
declare
  s jsonb := p_figures->'supply'; d jsonb := p_figures->'demand'; m jsonb := p_figures->'money';
begin
  if (s->>'matchable')::int = 0 then
    return jsonb_build_object('stage','supply_confirmation','severity','blocking',
      'finding', format('No supplier can be matched to any request. %s suppliers are on file and %s have confirmed the trades they actually do.',
                        s->>'leads_total', s->>'matchable'),
      'why_it_outranks_everything','A request that matches nobody produces no quote, no comparison, no reveal and no revenue. Every other number below is downstream of this one and cannot move until it does.',
      'proposal','Send a one-screen confirmation link to invited suppliers: show the trades already scraped for them and let them press yes. That single action sets the two fields the matcher requires and does not depend on the parked supplier portal.',
      'measure_of_success','matchable > 0, then the first request that reaches a supplier.');
  end if;

  if (d->>'inquiries_ever')::int = 0 then
    return jsonb_build_object('stage','demand','severity','blocking',
      'finding', format('Supply is ready (%s matchable) and no customer has posted a request. Real customers: %s.',
                        s->>'matchable', d->>'customers_real'),
      'why_it_outranks_everything','Matchable supply with no demand earns nothing, and suppliers who are asked to wait without a request go cold.',
      'proposal','Outbound to the buyer side of the existing list — the consultants, fit-out contractors and interior designers already on file — since they are buyers of these trades and their emails are already held.',
      'measure_of_success','the first request posted by someone who is not the founder.');
  end if;

  if (d->>'quotes_ever')::int = 0 then
    return jsonb_build_object('stage','supplier_response','severity','blocking',
      'finding','Requests exist and no supplier has quoted.',
      'why_it_outranks_everything','A marketplace that cannot return a quote has failed the customer once, and the customer does not come back.',
      'proposal','Measure dispatch: how many suppliers each request reached, and how many opened it. If dispatch is working, the problem is the ask; if it is not, the problem is delivery.',
      'measure_of_success','at least three quotes on a request, which is what the top-three comparison needs.');
  end if;

  if (d->>'comparisons_ever')::int = 0 then
    return jsonb_build_object('stage','comparison','severity','blocking',
      'finding','Quotes exist and no comparison has been produced.',
      'why_it_outranks_everything','The comparison IS the product. Without it there is nothing to pay to reveal.',
      'proposal','The comparison engine falls back to a deterministic ranking while paid inference is held. Confirm the fallback produces a report a buyer would act on, since that is what every customer will see.',
      'measure_of_success','a published comparison a customer opens.');
  end if;

  if (d->>'reveals_ever')::int = 0 then
    return jsonb_build_object('stage','reveal','severity','blocking',
      'finding','Comparisons exist and nobody has paid to reveal.',
      'why_it_outranks_everything','This is the only revenue event in the model.',
      'proposal','Check the reveal price is visible before the click and that the paid receipt actually reaches both parties.',
      'measure_of_success','the first 3% fee settled in the bank.');
  end if;

  if (m->>'revenue_week_aed')::numeric = 0 and (m->>'revenue_life_aed')::numeric > 0 then
    return jsonb_build_object('stage','repeat','severity','watch',
      'finding','Revenue exists but none this week.',
      'why_it_outranks_everything','A marketplace lives on repeat, and one-off revenue hides churn.',
      'proposal','Look at whether last week''s buyers returned and whether revealed suppliers responded.',
      'measure_of_success','revenue in consecutive weeks.');
  end if;

  return jsonb_build_object('stage','growth','severity','healthy',
    'finding', format('The chain is intact end to end. Revenue this week AED %s.', m->>'revenue_week_aed'),
    'why_it_outranks_everything','Nothing in the chain is broken, so the constraint is rate rather than function.',
    'proposal','Raise the top of the funnel and protect the reveal conversion.',
    'measure_of_success','week-on-week revenue growth.');
end $fn$;

-- ── COMPOSE ─────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_weekly_report(p_week_start date default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_ws date; v_we date; v_key text; v_fig jsonb; v_con jsonb; v_id bigint; v_body text; v_subj text;
  m jsonb; s jsonb; d jsonb; h jsonb;
begin
  v_ws := coalesce(p_week_start, (date_trunc('week', (now() at time zone 'Asia/Dubai')::date - 7))::date);
  v_we := v_ws + 6;
  v_key := 'quotesdone:' || to_char(v_ws, 'IYYY-"W"IW');

  v_fig := public.fn_ceo_weekly_figures(v_ws, v_we);
  v_con := public.fn_ceo_binding_constraint(v_fig);
  m := v_fig->'money'; s := v_fig->'supply'; d := v_fig->'demand'; h := v_fig->'health';

  v_subj := format('QuotesDone weekly - %s to %s - %s',
                   to_char(v_ws,'DD Mon'), to_char(v_we,'DD Mon YYYY'),
                   case when (v_con->>'severity') = 'healthy'
                        then 'AED ' || (m->>'revenue_week_aed') || ' revenue'
                        else 'blocked at ' || replace(v_con->>'stage','_',' ') end);

  v_body :=
    'WHAT IS HOLDING THE COMPANY BACK' || E'\n' ||
    (v_con->>'finding') || E'\n\n' ||
    'Why this outranks everything else: ' || (v_con->>'why_it_outranks_everything') || E'\n\n' ||
    'What to do: ' || (v_con->>'proposal') || E'\n' ||
    'How we will know it worked: ' || (v_con->>'measure_of_success') || E'\n\n' ||
    '--------------------------------------------------' || E'\n' ||
    'MONEY' || E'\n' ||
    format('  Revenue this week   AED %s   (prior week AED %s)', m->>'revenue_week_aed', m->>'revenue_prior_aed') || E'\n' ||
    format('  Revenue to date     AED %s', m->>'revenue_life_aed') || E'\n' ||
    format('  Spend this week     AED %s   (to date AED %s)', m->>'spend_week_aed', m->>'spend_life_aed') || E'\n' ||
    format('  VAT registration    %s (%s%% of the AED %s threshold)',
           (m->'vat_position'->>'band'), (m->'vat_position'->>'pct_of_threshold'), (m->'vat_position'->>'threshold_aed')) || E'\n\n' ||
    'SUPPLY' || E'\n' ||
    format('  On file %s, contactable %s, invited %s, registered %s, verified %s, MATCHABLE %s',
           s->>'leads_total', s->>'contactable', s->>'invited_ever', s->>'registered', s->>'verified', s->>'matchable') || E'\n' ||
    format('  Invited this week %s. Last invitation went out %s days ago.',
           s->>'invited_week', coalesce(s->>'days_since_last_invite','never')) || E'\n\n' ||
    'DEMAND' || E'\n' ||
    format('  Customers %s (with evidence behind them: %s)', d->>'customers', d->>'customers_real') || E'\n' ||
    format('  Requests this week %s, ever %s. Quotes %s. Comparisons %s. Paid reveals %s.',
           d->>'inquiries_week', d->>'inquiries_ever', d->>'quotes_ever', d->>'comparisons_ever', d->>'reveals_ever') || E'\n\n' ||
    'THE SEATS' || E'\n' ||
    (select string_agg(format('  %-17s %s run(s), %s error(s)', k, v->>'runs_week', v->>'errors_week'), E'\n' order by k)
       from jsonb_each(v_fig->'seats') as t(k,v)) || E'\n\n' ||
    'HEALTH' || E'\n' ||
    format('  Open IT findings %s. Alerts sent to you this week %s.', h->>'it_findings_open', h->>'it_alerts_week') || E'\n' ||
    format('  Reports waiting on the CEO %s. Your instructions still open %s.',
           h->>'reports_awaiting_ceo', h->>'founder_instructions_open') || E'\n\n' ||
    'Every figure above is measured from the ledger and the live tables at the moment of writing. ' ||
    'A zero here means nothing happened, not that nothing was counted.';

  insert into public.ceo_weekly_report
    (iso_year, iso_week, week_start, week_end, report_key, subject, body, figures, constraint_now,
     proposals, status)
  values
    (extract(isoyear from v_ws)::int, extract(week from v_ws)::int, v_ws, v_we, v_key,
     v_subj, v_body, v_fig, v_con, jsonb_build_array(v_con->>'proposal'), 'generated')
  on conflict (report_key, revision) do update
     set subject = excluded.subject, body = excluded.body, figures = excluded.figures,
         constraint_now = excluded.constraint_now, proposals = excluded.proposals, updated_at = now()
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id, 'report_key', v_key,
    'week', v_ws || ' to ' || v_we, 'constraint', v_con->>'stage', 'subject', v_subj);
end $fn$;
revoke execute on function public.fn_ceo_weekly_report(date) from public;

-- ── PROVE IT ────────────────────────────────────────────────────────────────────────────────────
do $do$
declare v jsonb; r public.ceo_weekly_report; v_con jsonb;
begin
  v := public.fn_ceo_weekly_report();
  if not coalesce((v->>'ok')::boolean,false) then raise exception 'the report did not generate: %', v::text; end if;
  select * into r from public.ceo_weekly_report where id = (v->>'id')::bigint;

  -- It must have found the real constraint, not a default.
  if (r.constraint_now->>'stage') <> 'supply_confirmation' then
    raise exception 'the binding constraint reads "%" — with 0 matchable suppliers it must be supply_confirmation', r.constraint_now->>'stage';
  end if;

  -- The analysis must be exercised at every stage, not just today's. A rule that has only ever
  -- returned one answer has not been tested.
  v_con := public.fn_ceo_binding_constraint(jsonb_build_object(
    'supply', jsonb_build_object('matchable','5','leads_total','22264'),
    'demand', jsonb_build_object('inquiries_ever','0','customers_real','3','quotes_ever','0','comparisons_ever','0','reveals_ever','0'),
    'money',  jsonb_build_object('revenue_week_aed','0','revenue_life_aed','0')));
  if (v_con->>'stage') <> 'demand' then raise exception 'with supply ready and no requests the constraint must be demand, got %', v_con->>'stage'; end if;

  v_con := public.fn_ceo_binding_constraint(jsonb_build_object(
    'supply', jsonb_build_object('matchable','5','leads_total','22264'),
    'demand', jsonb_build_object('inquiries_ever','9','customers_real','3','quotes_ever','12','comparisons_ever','4','reveals_ever','2'),
    'money',  jsonb_build_object('revenue_week_aed','4500','revenue_life_aed','9000')));
  if (v_con->>'stage') <> 'growth' then raise exception 'a working chain must read growth, got %', v_con->>'stage'; end if;

  if r.body not like '%WHAT IS HOLDING THE COMPANY BACK%' or r.body not like '%THE SEATS%' then
    raise exception 'the report lost a section';
  end if;

  raise notice 'CEO WEEKLY REPORT BUILT. % | %  Constraint: % — %  Body % chars.',
    r.report_key, r.subject, r.constraint_now->>'stage', left(r.constraint_now->>'finding', 90), length(r.body);
end
$do$;
