-- s36 for the strategy desk: every strategic recommendation now states its assumptions, its
-- expected impact and its cost.
--
-- RE-MEASURED FIRST, because the brief's diagnosis was wrong again. It said "~600 of 1,311
-- recommendations/30d still carry NULL". Production on 13 Aug 2026: 1,433 agent_actions in 30 days
-- and exactly TWO carry all three columns - both written today by fn_operations_ai. The helper
-- routines that fill them (ai_rec, doc_rec, kn_task, mkt_rec, ops_rec) shipped hours ago and only
-- ops_rec has run since, so the columns fill as those routines come round. What is genuinely
-- unfinished is the writers that have no helper at all.
--
-- strategy_rec is the largest of those: 93 rows in 30 days, none of them carrying anything.
-- fn_strategy_rec is replaced rather than overloaded so there is exactly one of it; the DROP means
-- the new function is granted to PUBLIC on creation, so the REVOKE below is in the same file - and
-- this file is applied with --ddl, which carries the whole text to both projects rather than only
-- the routine body.
--
-- The four assumption sets are statements about what each recommendation TAKES ON TRUST, checkable
-- against the tables named in them. None of them is a restatement of the recommendation.
drop function if exists public.fn_strategy_rec(text, text, text);

create or replace function public.fn_strategy_rec(
  p_title text, p_risk text, p_rec text,
  p_assumptions jsonb default null, p_impact text default null, p_cost text default null)
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  if not exists (
    select 1 from public.agent_actions
    where agent='strategy_ai' and kind='strategy_rec' and title=p_title and status in ('pending','needs_review')
  ) then
    insert into public.agent_actions(agent,kind,status,risk,title,recommendation,created_at,
                                     assumptions,expected_impact,cost)
    values ('strategy_ai','strategy_rec','needs_review',p_risk,p_title,p_rec, now(),
            p_assumptions, p_impact, p_cost);
  end if;
end $function$;

revoke all on function public.fn_strategy_rec(text, text, text, jsonb, text, text) from public;
revoke all on function public.fn_strategy_rec(text, text, text, jsonb, text, text) from anon;

create or replace function public.fn_strategy_ai()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare k record; r record; v_recs int := 0;
begin
  perform public.fn_strategy_scan();               -- refresh internal risk signals
  select * into k from public.strategy_kpis;
  insert into public.strategy_kpi_snapshots(kpis) values (to_jsonb(k));

  -- Recommend on material open risks (score >= 12)
  for r in select category,title,score,mitigation from public.strategy_risks
           where status='open' and score >= 12 order by score desc loop
    perform public.fn_strategy_rec('Strategic risk: '||r.title,
      case when r.score>=16 then 'high' else 'medium' end,
      '['||upper(r.category)||' · risk score '||r.score||'/25] '||coalesce(r.mitigation,'Review and decide a mitigation.'),
      jsonb_build_array(
        'The score of '||r.score||'/25 is a self-assessment stored on strategy_risks by whatever raised the risk. It has not been independently reviewed, and 12/25 is a threshold on that self-assessment rather than on measured exposure.',
        'status=''open'' means nobody has closed the row. A risk that has already passed looks identical to one that is still live until someone closes it.',
        case when r.mitigation is null then 'No mitigation is stored with this risk, so the recommendation asks for one rather than proposing one.'
             else 'The mitigation quoted here is the text stored with the risk when it was raised; it may predate the current situation.' end),
      'Deciding it removes the risk this company has scored highest. Left open, the only thing that changes is the score.',
      'No spend to decide. The mitigation itself may cost - that is stated on the strategy_risks row, not here.');
    v_recs := v_recs + 1;
  end loop;

  -- Expansion signal: under-supplied high-demand categories
  if coalesce(k.under_supplied_categories,0) > 0 then
    perform public.fn_strategy_rec('Expansion: recruit suppliers in under-supplied categories','medium',
      k.under_supplied_categories||' categories have demand outstripping supplier coverage. Targeted supplier acquisition here is the highest-ROI growth lever — see the Marketplace supply-gap list.',
      jsonb_build_array(
        'Under-supplied compares demand signals against CONFIRMED supplier coverage per category. With '||(select count(*) from public.leads where coalesce(claimed,false))||' confirmed supplier(s) on file, nearly every category qualifies, so this count currently says more about supply than about demand.',
        'Coverage is counted through the catalogue''s own taxonomy: a supplier who serves a category but has not declared it counts as absent.',
        'It assumes the demand signal is real demand. With 0 inquiries to date the signal is derived from catalogue structure and lead distribution, not from customers asking.'),
      'Supply is the binding constraint on revenue: an RFQ in a category with no supplier cannot be quoted at all, so the request is lost before pricing ever matters.',
      'No spend to decide. Recruiting costs invitation volume and sending reputation, which the invite ramp governs and caps.');
  end if;

  -- Pricing: standing review of the reveal fee vs average job value (recommend, never change)
  perform public.fn_strategy_rec('Pricing review: reveal fee vs average job value','low',
    'Periodically re-test the reveal fee and supplier registration pricing against average job value and willingness-to-pay. Use fn_simulate to model options before any change — pricing changes stay a founder decision.',
    jsonb_build_array(
      'That the live prices are the ones in pricing_config and have not been overridden for an individual customer or supplier.',
      'That average job value can be estimated at all. With no completed jobs on file there is nothing to estimate from, so this is a standing reminder rather than a finding about the current price.',
      'That willingness-to-pay is unknown rather than zero: nobody has been asked to pay the reveal fee yet.'),
    'Pricing is the only lever that changes revenue without changing volume. Untested, today''s fee hardens into a default that nobody ever chose.',
    'No spend. A founder decision; fn_simulate models the options first and costs one model call.');

  -- Market intelligence gap
  if coalesce(k.competitor_intel,0) = 0 then
    perform public.fn_strategy_rec('Add a competitor / market-intelligence source','medium',
      'No competitor records on file (market_intel is empty). Connect a web-research or market-data source, or add competitors manually, so positioning, pricing and expansion calls are evidence-based rather than assumed.',
      jsonb_build_array(
        'An empty market_intel means no competitor has been RECORDED. It is not evidence that no competitor exists, and it is the weaker of the two readings.',
        'That positioning and pricing calls are currently being made without competitor evidence. That follows from the table being empty, but it does not prove the founder holds no such knowledge outside the system.',
        'That a usable source exists for this market. UAE marketplace competitors may not publish the pricing that would make the comparison decisive.'),
      'Every positioning, pricing and expansion decision is currently taken with no recorded evidence about anyone else in this market.',
      'A market-data source or web-research subscription costs money and needs founder approval. Adding competitors by hand costs founder time and nothing else.');
  end if;

  return jsonb_build_object('open_risks',k.open_risks,'top_risk',k.top_risk,'top_risk_score',k.top_risk_score,
    'new_or_open_recs', v_recs, 'competitor_intel', k.competitor_intel, 'under_supplied', k.under_supplied_categories);
end $function$;
