-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709110023   name: fn_strategy_ai_agent
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- De-duped founder recommendation helper for Strategy AI
create or replace function public.fn_strategy_rec(p_title text, p_risk text, p_rec text)
returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  if not exists (
    select 1 from public.agent_actions
    where agent='strategy_ai' and kind='strategy_rec' and title=p_title and status in ('pending','needs_review')
  ) then
    insert into public.agent_actions(agent,kind,status,risk,title,recommendation,created_at)
    values ('strategy_ai','strategy_rec','needs_review',p_risk,p_title,p_rec, now());
  end if;
end $$;
revoke all on function public.fn_strategy_rec(text,text,text) from anon, authenticated, public;

-- The Strategy AI: long-term thinking — refreshes the risk register, surfaces strategic
-- recommendations, and keeps the scenario/forecast tools ready.
-- OVERSIGHT-FIRST: it recommends, simulates and forecasts only. It NEVER changes pricing,
-- commits an expansion, or takes any irreversible action — every move is a founder decision.
create or replace function public.fn_strategy_ai()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $$
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
      '['||upper(r.category)||' · risk score '||r.score||'/25] '||coalesce(r.mitigation,'Review and decide a mitigation.'));
    v_recs := v_recs + 1;
  end loop;

  -- Expansion signal: under-supplied high-demand categories
  if coalesce(k.under_supplied_categories,0) > 0 then
    perform public.fn_strategy_rec('Expansion: recruit suppliers in under-supplied categories','medium',
      k.under_supplied_categories||' categories have demand outstripping supplier coverage. Targeted supplier acquisition here is the highest-ROI growth lever — see the Marketplace supply-gap list.');
  end if;

  -- Pricing: standing review of the reveal fee vs average job value (recommend, never change)
  perform public.fn_strategy_rec('Pricing review: reveal fee vs average job value','low',
    'Periodically re-test the reveal fee and supplier registration pricing against average job value and willingness-to-pay. Use fn_simulate to model options before any change — pricing changes stay a founder decision.');

  -- Market intelligence gap
  if coalesce(k.competitor_intel,0) = 0 then
    perform public.fn_strategy_rec('Add a competitor / market-intelligence source','medium',
      'No competitor records on file (market_intel is empty). Connect a web-research or market-data source, or add competitors manually, so positioning, pricing and expansion calls are evidence-based rather than assumed.');
  end if;

  return jsonb_build_object('open_risks',k.open_risks,'top_risk',k.top_risk,'top_risk_score',k.top_risk_score,
    'new_or_open_recs', v_recs, 'competitor_intel', k.competitor_intel, 'under_supplied', k.under_supplied_categories);
end $$;
revoke all on function public.fn_strategy_ai() from anon, authenticated, public;

insert into public.category_agents(slug,name,emoji,active,persona)
values ('strategy_ai','Strategy AI','🧭',true,
  'I think long-term for QuotesDone. I track the strategic risk register, competitor and market intelligence, expansion opportunities, pricing, forecasting and scenario simulation — and I surface recommendations for you to decide on. I never change pricing, commit an expansion, or take irreversible action; I model options and advise, the call is always yours.')
on conflict (slug) do update set name=excluded.name, emoji=excluded.emoji, active=true, persona=excluded.persona;

select cron.schedule('strategy_ai_daily','25 5 * * *', 'select public.fn_strategy_ai();');
