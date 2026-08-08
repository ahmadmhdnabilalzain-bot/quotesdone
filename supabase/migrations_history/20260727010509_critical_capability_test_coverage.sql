-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727010509   name: critical_capability_test_coverage
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ AUTOMATED TEST FOR EVERY CRITICAL CAPABILITY ============
-- A register of what is actually critical, and what proves it works. Honest by construction:
-- a capability with no named test reads UNTESTED, and one whose suite is failing reads FAILING.
create table if not exists public.critical_capability (
  capability_key text primary key,
  capability     text not null,
  why_critical   text not null,
  owner_dept     text,
  test_kind      text check (test_kind in ('suite','rpc_selftest','scenario','none')),
  test_ref       text,
  last_verdict   text,
  last_checked   timestamptz
);

insert into public.critical_capability (capability_key, capability, why_critical, owner_dept, test_kind, test_ref) values
('anonymity','Supplier identity is never disclosed before a paid reveal','This is the product. A leak destroys the reason buyers pay.','it','suite','qa_suite'),
('money_invariants','Reveal fees, invoices and refunds obey their invariants','Direct financial exposure and the only revenue line.','finance','suite','money_tests'),
('supplier_verification','No supplier receives an RFQ without a verified, unexpired trade licence','An unverified supplier reaching a buyer costs trust, which cannot be bought back.','procurement','rpc_selftest','fn_brand_scan'),
('fraud_detection','Duplicate licences, expired licences, impersonation and scam RFQs are detected','Fraud at the supplier gate is the highest-consequence failure in a trust marketplace.','legal','rpc_selftest','fn_brand_scan'),
('prompt_injection','Supplier and buyer content cannot issue instructions to an employee','A regression was already observed. Untrusted content reaches prompts on every document path.','it','rpc_selftest','fn_secops_test'),
('review_chain','Nothing publishes without passing the approval chain','Brand and legal exposure; an earlier version of this rule engine failed open.','exec','scenario','five_posts_one_violation'),
('decision_impact_gate','No decision reaches approved without business, financial, legal and customer impact plus evidence','Decisions without stated impact are how avoidable losses get approved.','exec','rpc_selftest','trg_decision_gate'),
('cost_metering','Every model call is priced, attributed and budgeted','Unmetered AI spend is the fastest way this company loses money quietly.','it','rpc_selftest','fn_llm_log'),
('model_routing','Task classes route to the correct tier and refuse an LLM where code is correct','A single routing error multiplied 5x across the highest-volume paths.','it','rpc_selftest','fn_select_model'),
('knowledge_standard','Every catalogue category employee holds all 14 expert modules','Thin knowledge produces confident wrong answers, which is worse than no answer.','knowledge','rpc_selftest','v_category_coverage'),
('metric_truth','Every reported metric is computed from live rows, not asserted','A dashboard that can be wrong is worse than no dashboard.','exec','rpc_selftest','fn_bi_snapshot'),
('scheduled_run_health','Failed scheduled runs raise an alert','43 failures in 24 hours went unnoticed before alerting was wired.','it','suite','smoke'),
('doc_extraction','Supplier documents are read, including scanned PDFs','A document that cannot be read makes a supplier invisible to matching.','knowledge','suite','knowledge_exam'),
('matching','RFQs reach suppliers who can actually do the work','Bad matches waste the supplier response budget and produce refunds.','procurement','suite','match_eval'),
('continuity','Every external dependency has a documented fallback','13 external services; an outage with no fallback stops the business.','it','rpc_selftest','continuity_plan')
on conflict (capability_key) do update set capability=excluded.capability, why_critical=excluded.why_critical,
  owner_dept=excluded.owner_dept, test_kind=excluded.test_kind, test_ref=excluded.test_ref;

create or replace view public.v_critical_capability_tests as
select c.capability_key, c.capability, c.owner_dept, c.test_kind, c.test_ref, c.why_critical,
       case
         when c.test_kind = 'none' or c.test_ref is null then 'UNTESTED'
         when c.test_kind = 'suite' then coalesce(
              (select case when t.verdict ilike '%pass%' then 'PASSING'
                           when t.verdict is null then 'NEVER_RUN'
                           else 'FAILING' end
                 from v_test_matrix t where t.suite = c.test_ref), 'NEVER_RUN')
         when c.test_kind = 'scenario' then coalesce(
              (select case when s.last_result = 'pass' then 'PASSING'
                           when s.last_result = 'not_run' then 'NEVER_RUN'
                           else 'FAILING' end
                 from scenario_library s where s.scenario_key = c.test_ref), 'NEVER_RUN')
         when c.test_kind = 'rpc_selftest' then 'SELFTEST_ON_BUILD'
         else 'UNKNOWN'
       end as state,
       (select t.pass_pct from v_test_matrix t where t.suite = c.test_ref) as pass_pct,
       (select t.last_run  from v_test_matrix t where t.suite = c.test_ref) as last_run
from critical_capability c;

alter table public.critical_capability enable row level security;
