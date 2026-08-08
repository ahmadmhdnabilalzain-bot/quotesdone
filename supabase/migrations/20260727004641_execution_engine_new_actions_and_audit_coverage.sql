-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727004641   name: execution_engine_new_actions_and_audit_coverage
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ 14. EXECUTION ENGINE - wire the newly built capabilities ============
insert into public.org_action_executor (action_class, kind, target, params, active, note, advisory_safe, department) values
('brand_scan',        'rpc','fn_brand_scan',     '{}'::jsonb, true, 'Deterministic fraud, impersonation and scam-RFQ scan. Writes brand_signal rows. No model call.', false, 'legal'),
('secops_pattern_test','rpc','fn_secops_test',   '{}'::jsonb, true, 'Tests untrusted content against the prompt-injection and credential-leak rule set before it reaches a prompt.', true, 'it'),
('bi_snapshot',       'rpc','fn_bi_snapshot',    '{}'::jsonb, true, 'Executes every metric definition and records a snapshot. The scorecard is computed, never asserted.', false, 'exec'),
('evolution_scan',    'rpc','fn_evolution_scan', '{}'::jsonb, true, 'Detects repeated failures, off-target metrics and avoidable model spend, and writes a change proposal for each.', false, 'exec'),
('growth_simulate',   'rpc','fn_simulate_growth','{}'::jsonb, true, 'Deterministic marketplace projection: invite rate and conversion in, months-to-target out.', true, 'exec'),
('self_review',       'rpc','fn_self_review',    '{}'::jsonb, true, 'Employee reviews its own recent work against its KPIs and records findings.', true, 'hr'),
('review_submit',     'rpc','fn_review_submit',  '{}'::jsonb, true, 'Submits a draft into the review chain: specialist to manager to Chief of Staff before anything publishes.', false, 'exec'),
('idea_submit',       'rpc','fn_idea_score',     '{}'::jsonb, true, 'Scores a submitted improvement idea deterministically by value, effort and confidence.', true, 'hr')
on conflict do nothing;

-- ============ AUDIT TRAIL COVERAGE ============
create or replace view public.v_audit_coverage as
with sources as (
  select 'decision_log'      as store, 'Every routed agent decision'                as covers, (select count(*) from decision_log)      as rows_held, (select max(created_at)  from decision_log)      as last_write
  union all select 'decision_record',   'Structured decisions with impact analysis', (select count(*) from decision_record),   (select max(created_at) from decision_record)
  union all select 'company_event',     'Business events published by db triggers',  (select count(*) from company_event),     (select max(occurred_at) from company_event)
  union all select 'agent_runs',        'Every scheduled function run and outcome',  (select count(*) from agent_runs),        (select max(started_at) from agent_runs)
  union all select 'agent_action_log',  'Actions taken by employees',                (select count(*) from agent_action_log),  null
  union all select 'os_audit_log',      'Operator and system actions',               (select count(*) from os_audit_log),      null
  union all select 'security_audit_log','Security-relevant events',                  (select count(*) from security_audit_log),null
  union all select 'ai_cost_log',       'Every model call: model, reason, tokens, cost', (select count(*) from ai_cost_log),   (select max(occurred_at) from ai_cost_log)
  union all select 'review_chain',      'Approval hops on anything published',       (select count(*) from review_chain),      null
  union all select 'brand_signal',      'Fraud and brand-misuse detections',         (select count(*) from brand_signal),      (select max(detected_at) from brand_signal)
  union all select 'evolution_proposal','Self-detected process defects',             (select count(*) from evolution_proposal),(select max(created_at) from evolution_proposal)
  union all select 'metric_snapshot',   'Point-in-time metric history',              (select count(*) from metric_snapshot),   (select max(taken_at) from metric_snapshot)
)
select store, covers, rows_held, last_write,
       case
         when rows_held = 0 then 'EMPTY'
         when last_write is null then 'NO_TIMESTAMP'
         when last_write > now() - interval '7 days' then 'ACTIVE'
         else 'STALE'
       end as state
from sources;
