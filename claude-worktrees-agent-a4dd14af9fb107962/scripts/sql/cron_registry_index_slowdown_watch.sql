-- Registry row for index_slowdown_watch_daily. STAGING ONLY — apply_sql --ddl forbids carrying row
-- data to production; this reaches production through promote_rows_to_production.mjs.
-- s38-manual-always-current reads 0 undocumented and 0 ghosts; an unregistered job puts it back to 1.
insert into public.cron_registry (jobname, human_name, category, purpose)
values ('index_slowdown_watch_daily', 'Company index slowdown watch (daily)', 'governance',
        'Raises an evolution proposal for any company index that lost more than a point since its previous measurement and that nothing has referenced since. Names the dimensions that moved down, from the index own stored dimensions. Before this, company_maturity fell 44.1 to 42.4 on 6 Aug on an 18.5-point drop in strategic_execution and nothing in the company referenced it.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
