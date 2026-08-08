-- ============================================================================
-- ANALYTICS department: data-grounded advisory execution.
-- Analytics is advisory (recommend) — it never acts on the business directly. But instead of
-- reasoning in the abstract, its executor pulls LIVE metrics and produces a recommendation that
-- CITES the numbers, recorded as a shared org insight.
-- ============================================================================

-- Advisory-safe executors: an executor that only READS data and RECORDS a recommendation (no business
-- side effect) may run even for advisory-tier tasks. cos_execute (v4) runs an executor when
--   ex && (task.tier <> 'advisory' OR ex.advisory_safe)
-- so "advisory = no side effects" stays true while Analytics executes a data-grounded recommendation.
alter table public.org_action_executor add column if not exists advisory_safe boolean not null default false;

-- The analytics_recommend edge function (deployed separately) pulls fn_query_platform('analytics'),
-- ('funnel',{days:30}) and ('company'), then has the analytics head synthesize a prioritized
-- recommendation citing those figures, recorded to org_memory (kind='insight'). Register it.
insert into public.org_action_executor(action_class, kind, target, params, advisory_safe, note) values
('recommend','edge','analytics_recommend','{}', true, 'Data-grounded advisory: cite live funnel/marketplace metrics, record as a shared org insight. Read-only (advisory-safe).')
on conflict (action_class) do update set kind=excluded.kind, target=excluded.target, params=excluded.params, advisory_safe=excluded.advisory_safe, note=excluded.note, active=true;

insert into public.org_memory(scope,kind,content,source) values
('analytics','policy','Analytics is advisory (recommend). Its executor analytics_recommend pulls live funnel/marketplace metrics and produces a recommendation that CITES the numbers, recorded as a shared org insight. Read + recommend only — never acts on the business directly.','founder_directive')
on conflict do nothing;