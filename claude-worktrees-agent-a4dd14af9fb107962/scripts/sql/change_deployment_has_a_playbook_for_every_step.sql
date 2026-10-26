-- THE change_deployment WORKFLOW HAS A PLAYBOOK FOR EVERY ONE OF ITS NINE STEPS (MASTER_PLAN A1 / §4.2), 4 Sep 2026.
--
-- MEASURED on production before this file: 26 change_deployment runs, every one of them parked on
-- step 1 with disposition='awaiting_model'. The applier's own reason, recorded on the step:
--
--   "no corroborated actionable match: nearest is exception_playbook 'Marketing exception 08 — User
--    changes material requirements mid-workflow' at 0.843 (floor 0.85, noise median 0.837) sharing
--    1 of 7 step terms"
--
-- That is the correct refusal. Nothing in ops_knowledge was about deploying a change: the four
-- ACTIONABLE kinds carry 197 decision_playbook, 240 decision_rule, 236 SOP and 240 exception_playbook
-- rows, and not one of them describes how THIS company puts a change into production. The nearest
-- neighbour was a marketing exception. The gap was knowledge, not the applier.
--
-- This file writes the nine missing records — one per step of public.workflow_step where
-- workflow_key='change_deployment' — as ACTIONABLE, runtime-eligible, deterministic knowledge, and
-- nothing else. It does not touch fn_apply_playbook, the 0.85 floor, the corroboration rule, or any
-- other workflow's knowledge.
--
-- HOW EACH RECORD IS BUILT TO BE RETRIEVED, all of it measured rather than hoped:
--   * SCOPE mirrors the applier's own predicate (agent -> department -> fn_dept_scope, packaged roles
--     via org_role_identity). The nine steps are worked by five different seats in three disjoint
--     scopes, so the scoping is per step, not one blanket:
--       step 1  optimisation_eng  dept growth  -> scope {growth,marketing,sales}: reachable ONLY by its
--               packaged role, so this record is role-scoped to
--               strategy-performance-and-evolution-analyst-controller (held by optimisation_eng alone).
--       steps 2-8  cto / eng_manager / qa_manager, dept product_eng -> scope {ai_dept,assurance,
--               engineering,it,product_eng,qa}. The only dept_key in that scope that ops_knowledge
--               actually uses is 'it' (as the existing scope_key='engineering' rows already do), and
--               eng_manager holds NO packaged role, so these are department-scoped on dept_key='it'.
--       step 9  cpo  dept exec -> scope {evolution,exec}: department-scoped on dept_key='evolution'
--               (scope_key strategy_evolution), which is where grading an outcome belongs anyway.
--   * CORROBORATION is satisfied by the record's own title: fn_apply_playbook counts the step's
--     lexemes against ops_knowledge.tsv, and tsv is GENERATED from title || ' ' || content. Each title
--     carries its step's text verbatim, so all 3-13 step lexemes are present (the rule needs >=2 and
--     >=30%).
--   * COSINE was measured BEFORE this file was written, with the same free in-region gte-small
--     (kb_embed query mode) and the same 1200-character slice the batch embedder applies, against all
--     26 real trigger contexts on the parked runs:
--       step 1 0.909-0.918   step 2 0.917-0.929   step 3 0.896-0.908
--       step 4 0.934-0.948   step 5 0.897-0.923   step 6 0.901-0.910
--       step 7 0.939-0.950   step 8 0.899-0.921   step 9 0.922-0.936
--     Every step clears the 0.85 floor on every observed context, with the nearest prior candidate at
--     0.843. The floor is not touched; the substrate is.
--
-- THE CONTENT IS THIS COMPANY'S DEPLOY, NOT GENERIC PROSE. Every record is written from
-- scripts/deploy_functions.mjs (the four rules: never guess a target; production must be said out
-- loud; no verify_jwt flag ever, because supabase/config.toml is the source of truth and drift
-- refuses the deploy; the CLI's exit code is not the verification — the version is read back per slug
-- and a 429 is retried seven times to 76.8s), .github/workflows/deploy-functions.yml (there is no
-- staging: the founder deleted it on 15 Aug 2026 and deno check is the gate that replaced it; the
-- Deploy step is gated on refs/heads/main), scripts/apply_sql.mjs with its MANIFEST line and its down
-- script under scripts/sql/down/, and the deploy.completed emitter at the end of a verified deploy
-- whose payload {ref, functions, count, at} is exactly what the step reads.
--
-- Idempotent on record_id. Re-applying updates title/content and lets the a10 trigger drop the stale
-- vector so cron 315 (kb_embed_ops_knowledge, free in-region gte-small) re-embeds it.
--
--   node scripts/apply_sql.mjs scripts/sql/change_deployment_has_a_playbook_for_every_step.sql --apply --ddl

begin;

-- step 1 — worked by optimisation_eng
insert into public.ops_knowledge
  (record_id, scope_type, scope_key, dept_key, role_key, module, layer, record_type, title, content,
   structured_data, source_ids, implementation_status, validation_status, authority_tier, risk_level,
   version, effective_date, review_after, keywords, dependencies, escalation_rule,
   jurisdiction, source_type, source_authority, source_freshness, confidentiality,
   runtime_eligible, deterministic, supersession_state)
values (
  'ops-change-deployment-step-01-propose-change-metric-baseline', 'role', 'strategy_evolution', 'evolution', 'strategy-performance-and-evolution-analyst-controller',
  'sop', 'department_shared', 'standard_operating_procedure',
  'Change to production — step 1 — change proposed, with the metric it should move and the baseline captured',
  'A change to production is proposed at this step, and the proposal is not complete until it names the metric the change should move and captures that metric''s baseline. The trigger is deploy.completed, emitted by scripts/deploy_functions.mjs after a deploy it verified by reading each function''s version back from the management API. Its payload — and therefore this run''s context — carries ref, functions, count and at.

DECIDE FROM THESE FIELDS OF THE EVENT, IN THIS ORDER:
1. context.functions — the edge function slugs the deploy moved. Each slug IS the changed surface, and the list is the blast radius of the change being proposed.
2. context.count — how many functions moved. One slug is a single-surface change; a count in the dozens means supabase/functions/_shared moved and deploy_functions.mjs widened the set to every importer, so the change is fleet-wide.
3. context.ref — the target project. There is exactly one project, htdblwldjkcgjvmqkbeh. Any other ref is a mis-targeted deploy: escalate, do not propose.
4. context.at — when the deploy completed. The baseline is measured over the window ENDING at this timestamp, so the before-picture is not contaminated by the change itself.

OUTPUT OF THIS STEP (the proposal):
- Change: the slugs from context.functions, verbatim.
- Metric it should move: for an edge function, that slug''s error count in error_log and its run outcomes in agent_runs; for a cron-backed function, the outcome and row delta of the routine it drives; for a customer-facing surface, the funnel step it serves.
- Baseline captured: that metric over the 7 days ending at context.at, recorded now, before promotion, so step 9 has something to grade against.
- Reversibility: an edge function deploy is reversed by redeploying the previously committed bundle for the same slug; a SQL change is reversed by its down script under scripts/sql/down/.

ESCALATE INSTEAD OF PROPOSING when context.ref is not the one project, when the event carries no function slugs (there is nothing to measure), or when the change touches refunds, the reveal fee or any money-out path — those are founder-gated and are never proposed as an ordinary change.',
  '{"decides":"whether a completed deploy is a proposable change, and what metric and baseline it is proposed against","inputs_from_event":["context.functions","context.count","context.ref","context.at"],"outputs":["change (slug list)","metric_it_should_move","baseline_captured (7d window ending at context.at)","reversibility_route"],"escalate_when":["ref is not htdblwldjkcgjvmqkbeh","no function slugs in the event","change touches refunds, reveal fee or money out"],"reversibility":"redeploy the previously committed bundle for the same slug; SQL by its down script in scripts/sql/down/","owner_role":"product_optimization_engineer"}'::jsonb,
  array['MASTER_PLAN-4.2', 'scripts/deploy_functions.mjs', '.github/workflows/deploy-functions.yml', 'scripts/apply_sql.mjs', 'scripts/sql/down/', 'scripts/checks/', 'public.workflow_step:change_deployment:1']::text[],
  'implemented', 'author_verified', 'supervised', 'low',
  '1.0.0', date '2026-09-04', date '2027-03-04',
  array['change_deployment', 'deploy.completed', 'baseline', 'metric', 'proposal', 'edge function', 'deploy_functions.mjs']::text[], '{}'::text[],
  '{"when":"blocked_by_missing_evidence_or_authority","action":"create_owned_escalation"}'::jsonb,
  'AE', 'repository_verified', 'quotesdone_engineering', 'stable', 'internal',
  true, true, 'current')
on conflict (record_id) do update set
  scope_type = excluded.scope_type, scope_key = excluded.scope_key, dept_key = excluded.dept_key,
  role_key = excluded.role_key, module = excluded.module, layer = excluded.layer,
  record_type = excluded.record_type, title = excluded.title, content = excluded.content,
  structured_data = excluded.structured_data, source_ids = excluded.source_ids,
  authority_tier = excluded.authority_tier, risk_level = excluded.risk_level,
  keywords = excluded.keywords, escalation_rule = excluded.escalation_rule,
  runtime_eligible = true, deterministic = true, supersession_state = 'current';

-- step 2 — worked by cto
insert into public.ops_knowledge
  (record_id, scope_type, scope_key, dept_key, role_key, module, layer, record_type, title, content,
   structured_data, source_ids, implementation_status, validation_status, authority_tier, risk_level,
   version, effective_date, review_after, keywords, dependencies, escalation_rule,
   jurisdiction, source_type, source_authority, source_freshness, confidentiality,
   runtime_eligible, deterministic, supersession_state)
values (
  'ops-change-deployment-step-02-review-correctness-blast-radius', 'department', 'engineering', 'it', null,
  'decision', 'decision_playbook', 'decision_playbook',
  'Change to production — step 2 — reviewed for correctness and blast radius before anything is built',
  'Before anything is built, the change is reviewed for correctness and for blast radius. Correctness is a question about the diff; blast radius is a question about how many surfaces the diff can reach. Both are answered from fields the deploy.completed event and the repository already carry, not from opinion.

BLAST RADIUS — read context.functions and context.count:
- One slug: the radius is that function and whatever it writes. Review the diff and its callers.
- Many slugs with an identical delta: supabase/functions/_shared moved. deploy_functions.mjs widens a _shared change to every importer by reading the source, so the radius is the whole importer set and the review must cover the shared module, not the leaf functions.
- Any slug on the money or identity path (customer_api, os_api, refund and payment surfaces): the radius includes a founder-gated action and the change is reviewed as high blast radius regardless of diff size.

CORRECTNESS — the four rules deploy_functions.mjs enforces, checked as review questions:
1. Is the target named? No ref, no deploy; production must be said out loud with --production.
2. Does supabase/config.toml still agree with the live project about verify_jwt? A drift refuses the deploy, because deploying through drift means nobody knows which value wins. This was measured on 3 Aug 2026 when a redeploy flipped verify_jwt and a function silently rejected every request.
3. Is the change reversible — a prior committed bundle for an edge function, a down script under scripts/sql/down/ for SQL?
4. Does a new SQL file carry its MANIFEST line, so canonical_routine_manifest stays green?

VERDICT: pass the change to step 3 when the radius is bounded and all four correctness questions are answered. HOLD and escalate to the engineering director when the radius includes a money-out or founder-gated surface, when config.toml and live disagree, or when the change has no stated reverse.',
  '{"decides":"pass or hold the proposed change before implementation, on correctness and blast radius","inputs_from_event":["context.functions","context.count"],"correctness_checks":["target named (--ref, --production)","verify_jwt parity between supabase/config.toml and live","stated reverse","MANIFEST line for a new scripts/sql file"],"blast_radius_rule":"_shared widens to every importer; money/identity surfaces are high radius regardless of diff size","outputs":["verdict pass|hold","blast_radius classification","unanswered correctness questions"],"escalate_when":["money-out or founder-gated surface in radius","config.toml disagrees with live","no stated reverse"]}'::jsonb,
  array['MASTER_PLAN-4.2', 'scripts/deploy_functions.mjs', '.github/workflows/deploy-functions.yml', 'scripts/apply_sql.mjs', 'scripts/sql/down/', 'scripts/checks/', 'public.workflow_step:change_deployment:2']::text[],
  'implemented', 'author_verified', 'supervised', 'medium',
  '1.0.0', date '2026-09-04', date '2027-03-04',
  array['change_deployment', 'review', 'blast radius', 'correctness', '_shared', 'verify_jwt', 'config.toml']::text[], '{}'::text[],
  '{"when":"blocked_by_missing_evidence_or_authority","action":"create_owned_escalation"}'::jsonb,
  'AE', 'repository_verified', 'quotesdone_engineering', 'stable', 'internal',
  true, true, 'current')
on conflict (record_id) do update set
  scope_type = excluded.scope_type, scope_key = excluded.scope_key, dept_key = excluded.dept_key,
  role_key = excluded.role_key, module = excluded.module, layer = excluded.layer,
  record_type = excluded.record_type, title = excluded.title, content = excluded.content,
  structured_data = excluded.structured_data, source_ids = excluded.source_ids,
  authority_tier = excluded.authority_tier, risk_level = excluded.risk_level,
  keywords = excluded.keywords, escalation_rule = excluded.escalation_rule,
  runtime_eligible = true, deterministic = true, supersession_state = 'current';

-- step 3 — worked by cto
insert into public.ops_knowledge
  (record_id, scope_type, scope_key, dept_key, role_key, module, layer, record_type, title, content,
   structured_data, source_ids, implementation_status, validation_status, authority_tier, risk_level,
   version, effective_date, review_after, keywords, dependencies, escalation_rule,
   jurisdiction, source_type, source_authority, source_freshness, confidentiality,
   runtime_eligible, deterministic, supersession_state)
values (
  'ops-change-deployment-step-03-implement-the-change', 'department', 'engineering', 'it', null,
  'sop', 'department_shared', 'standard_operating_procedure',
  'Change to production — step 3 — implement the change',
  'Implement the change. In this company a change to production is one of exactly three shapes, and the shape decides how it is implemented.

1. AN EDGE FUNCTION CHANGE. Edit supabase/functions/<slug>/index.ts. A change under supabase/functions/_shared/ is a change to every function that imports it: deploy_functions.mjs finds the importers by reading the source, so implement and review it as a fleet change. Never pass a verify_jwt flag anywhere; supabase/config.toml is the single source of truth and the CLI reads it.

2. A DATABASE CHANGE. One NEW file under scripts/sql/ per change — never an edit to an applied file — plus its line in scripts/sql/MANIFEST, or canonical_routine_manifest goes red. Write the body so re-applying it is a no-op (create or replace, on conflict do nothing/update, idempotent DO blocks). Put the reverse in scripts/sql/down/ alongside the 139 that are already there. Apply with node scripts/apply_sql.mjs <file> --apply --ddl.

3. A REPOSITORY OR CHECK CHANGE. Non-trivial logic leaves one runnable check behind under scripts/checks/, and the check must fail on the defect it claims to catch before it is trusted — step 5 proves that.

IMPLEMENTATION IS DONE WHEN: the change is committed on a branch, the reverse exists and is named, and the change is scoped to the slugs and files the proposal in step 1 listed. Anything the implementation touched that step 1 did not list widens the blast radius and goes back to step 2.

ESCALATE instead of implementing when the change requires a new secret, a new outbound provider, or a schema change to a table a kernel guard protects; those are not ordinary implementation work.',
  '{"decides":"how the proposed change is implemented, by its shape","shapes":{"edge_function":"supabase/functions/<slug>/index.ts; _shared is a fleet change; never pass a verify_jwt flag","database":"one NEW scripts/sql file + a MANIFEST line + a down script; apply with node scripts/apply_sql.mjs <file> --apply --ddl","repository_or_check":"a runnable check under scripts/checks/ that fails on the defect it claims to catch"},"done_when":["committed on a branch","the reverse exists and is named","scope matches the step 1 proposal"],"escalate_when":["a new secret is required","a new outbound provider is required","a kernel-guarded table changes shape"]}'::jsonb,
  array['MASTER_PLAN-4.2', 'scripts/deploy_functions.mjs', '.github/workflows/deploy-functions.yml', 'scripts/apply_sql.mjs', 'scripts/sql/down/', 'scripts/checks/', 'public.workflow_step:change_deployment:3']::text[],
  'implemented', 'author_verified', 'supervised', 'medium',
  '1.0.0', date '2026-09-04', date '2027-03-04',
  array['change_deployment', 'implement', 'edge function', 'scripts/sql', 'MANIFEST', 'down script']::text[], '{}'::text[],
  '{"when":"blocked_by_missing_evidence_or_authority","action":"create_owned_escalation"}'::jsonb,
  'AE', 'repository_verified', 'quotesdone_engineering', 'stable', 'internal',
  true, true, 'current')
on conflict (record_id) do update set
  scope_type = excluded.scope_type, scope_key = excluded.scope_key, dept_key = excluded.dept_key,
  role_key = excluded.role_key, module = excluded.module, layer = excluded.layer,
  record_type = excluded.record_type, title = excluded.title, content = excluded.content,
  structured_data = excluded.structured_data, source_ids = excluded.source_ids,
  authority_tier = excluded.authority_tier, risk_level = excluded.risk_level,
  keywords = excluded.keywords, escalation_rule = excluded.escalation_rule,
  runtime_eligible = true, deterministic = true, supersession_state = 'current';

-- step 4 — worked by qa_manager
insert into public.ops_knowledge
  (record_id, scope_type, scope_key, dept_key, role_key, module, layer, record_type, title, content,
   structured_data, source_ids, implementation_status, validation_status, authority_tier, risk_level,
   version, effective_date, review_after, keywords, dependencies, escalation_rule,
   jurisdiction, source_type, source_authority, source_freshness, confidentiality,
   runtime_eligible, deterministic, supersession_state)
values (
  'ops-change-deployment-step-04-offline-evaluation-held-out-set', 'department', 'ai_model_ops', 'it', null,
  'decision', 'decision_playbook', 'decision_playbook',
  'Change to production — step 4 — offline evaluation against a held-out set, where the change touches a model, prompt, retrieval or routing',
  'This step runs an offline evaluation against a held-out set, and it runs ONLY where the change touches a model, a prompt, retrieval or routing. First decide whether it applies, from context.functions:

APPLIES when a moved slug is ai_gateway, agent_brain, kb_embed, cos_execute, dept_plan, workflow_dispatch, knowledge_exam or any function that selects a model, composes a prompt, retrieves knowledge, or routes a task class.
DOES NOT APPLY when the moved slugs only read or write rows — a portal, an API surface, a health check, an uptime probe. Record "not applicable, no model, prompt, retrieval or routing surface in this change" and pass to step 5. Not applicable is a real answer here, not a skipped check.

WHERE IT APPLIES, THE HELD-OUT SET AND THE EVALUATION ARE:
- Retrieval changes: the held-out set is the standing needs in scripts/kb/probe_ops_knowledge_match.mjs. The evaluation is fn_ops_knowledge_match and fn_apply_playbook over the gte-small embeddings, and the measure is cosine against the 0.85 floor plus keyword corroboration. A retrieval change that lowers a corroborated match below the floor fails offline, whatever else improved.
- Routing changes: the held-out set is fn_task_class. The evaluation is that every active task class still resolves to a route, and that no previously free class became paid.
- Prompt or model changes: the paid provider is held by the founder (kernel K12 denies every route), so a live comparison cannot be run. Record the evaluation as HELD, not as passed and not as failed, and say which held-out set will be run when the hold lifts.

OUTPUT: applicable yes/no, the held-out set named, the measure and its number, and a pass, fail or held verdict. ESCALATE when the evaluation cannot name a held-out set at all — an unevaluable model change does not proceed to step 5.',
  '{"decides":"whether an offline evaluation applies to this change, and its verdict against a named held-out set","applies_when":"a moved slug selects a model, composes a prompt, retrieves knowledge or routes a task class","held_out_sets":{"retrieval":"scripts/kb/probe_ops_knowledge_match.mjs standing needs; measure = cosine vs the 0.85 floor with keyword corroboration","routing":"fn_task_class; measure = every active class still routes, no free class became paid","prompt_or_model":"HELD while the founder holds the paid provider (kernel K12); named, not run"},"outputs":["applicable","held_out_set","measure and number","verdict pass|fail|held|not_applicable"],"escalate_when":["the evaluation cannot name a held-out set"]}'::jsonb,
  array['MASTER_PLAN-4.2', 'scripts/deploy_functions.mjs', '.github/workflows/deploy-functions.yml', 'scripts/apply_sql.mjs', 'scripts/sql/down/', 'scripts/checks/', 'public.workflow_step:change_deployment:4']::text[],
  'implemented', 'author_verified', 'supervised', 'medium',
  '1.0.0', date '2026-09-04', date '2027-03-04',
  array['change_deployment', 'offline evaluation', 'held-out set', 'prompt', 'retrieval', 'routing', 'gte-small', 'ai_gateway']::text[], '{}'::text[],
  '{"when":"blocked_by_missing_evidence_or_authority","action":"create_owned_escalation"}'::jsonb,
  'AE', 'repository_verified', 'quotesdone_engineering', 'stable', 'internal',
  true, true, 'current')
on conflict (record_id) do update set
  scope_type = excluded.scope_type, scope_key = excluded.scope_key, dept_key = excluded.dept_key,
  role_key = excluded.role_key, module = excluded.module, layer = excluded.layer,
  record_type = excluded.record_type, title = excluded.title, content = excluded.content,
  structured_data = excluded.structured_data, source_ids = excluded.source_ids,
  authority_tier = excluded.authority_tier, risk_level = excluded.risk_level,
  keywords = excluded.keywords, escalation_rule = excluded.escalation_rule,
  runtime_eligible = true, deterministic = true, supersession_state = 'current';

-- step 5 — worked by qa_manager
insert into public.ops_knowledge
  (record_id, scope_type, scope_key, dept_key, role_key, module, layer, record_type, title, content,
   structured_data, source_ids, implementation_status, validation_status, authority_tier, risk_level,
   version, effective_date, review_after, keywords, dependencies, escalation_rule,
   jurisdiction, source_type, source_authority, source_freshness, confidentiality,
   runtime_eligible, deterministic, supersession_state)
values (
  'ops-change-deployment-step-05-build-run-suites-prove-check-fails', 'department', 'engineering', 'it', null,
  'sop', 'department_shared', 'standard_operating_procedure',
  'Change to production — step 5 — build and run the automated suites, and prove each new check fails on the defect it claims to catch',
  'Build and run the automated suites, then prove each new check actually fails on the defect it claims to catch. A check that has never been seen to fail is not evidence; it is decoration.

BUILD AND RUN, in this order:
1. deno check on every changed edge function — a compile error in an edge function is a silent 500, not a visible failure, which is why the deploy workflow typechecks before it deploys.
2. The repository suites under scripts/checks/ (97 files today), run by the checks workflow. Every test file must be run: every_test_file_is_run.test.mjs is itself one of them.
3. The parity checks that keep the repository and the live project honest: node scripts/checks/export_from_either_source_is_identical.mjs --write and node scripts/checks/canonical_routine_manifest.mjs --emit, after the LAST apply, never mid-chain.
4. kernel_invariants.test.mjs and kernel_positive_controls.test.mjs — the positive controls are the standing proof that a green invariant can still fail.

PROVE EACH NEW CHECK FAILS ON ITS DEFECT: reintroduce the defect the new check claims to catch — in a scratch transaction, on a fixture row, or by temporarily reverting the fix — run the check, and record that it went red. Then restore and record that it went green. A new check with no recorded red run is not accepted, and this step reports fail.

OUTPUT: the suites run, pass and fail counts per suite, and for each new check the recorded red-then-green pair. ESCALATE when a suite cannot run at all (an environment or credential failure is not a pass), or when a new check cannot be made to fail on the defect it names.',
  '{"decides":"whether the automated evidence for this change is complete and trustworthy","suites":["deno check on changed edge functions","scripts/checks/ (97 files, checks workflow)","export_from_either_source_is_identical.mjs --write","canonical_routine_manifest.mjs --emit","kernel_invariants + kernel_positive_controls"],"new_check_rule":"a new check is accepted only with a recorded red run on the defect it claims to catch, followed by a green run after restore","outputs":["suites run","pass/fail per suite","red-then-green pair per new check"],"escalate_when":["a suite cannot run (environment or credential failure is not a pass)","a new check cannot be made to fail on its own defect"]}'::jsonb,
  array['MASTER_PLAN-4.2', 'scripts/deploy_functions.mjs', '.github/workflows/deploy-functions.yml', 'scripts/apply_sql.mjs', 'scripts/sql/down/', 'scripts/checks/', 'public.workflow_step:change_deployment:5']::text[],
  'implemented', 'author_verified', 'supervised', 'medium',
  '1.0.0', date '2026-09-04', date '2027-03-04',
  array['change_deployment', 'automated suites', 'deno check', 'positive control', 'scripts/checks', 'qa_suite']::text[], '{}'::text[],
  '{"when":"blocked_by_missing_evidence_or_authority","action":"create_owned_escalation"}'::jsonb,
  'AE', 'repository_verified', 'quotesdone_engineering', 'stable', 'internal',
  true, true, 'current')
on conflict (record_id) do update set
  scope_type = excluded.scope_type, scope_key = excluded.scope_key, dept_key = excluded.dept_key,
  role_key = excluded.role_key, module = excluded.module, layer = excluded.layer,
  record_type = excluded.record_type, title = excluded.title, content = excluded.content,
  structured_data = excluded.structured_data, source_ids = excluded.source_ids,
  authority_tier = excluded.authority_tier, risk_level = excluded.risk_level,
  keywords = excluded.keywords, escalation_rule = excluded.escalation_rule,
  runtime_eligible = true, deterministic = true, supersession_state = 'current';

-- step 6 — worked by cto
insert into public.ops_knowledge
  (record_id, scope_type, scope_key, dept_key, role_key, module, layer, record_type, title, content,
   structured_data, source_ids, implementation_status, validation_status, authority_tier, risk_level,
   version, effective_date, review_after, keywords, dependencies, escalation_rule,
   jurisdiction, source_type, source_authority, source_freshness, confidentiality,
   runtime_eligible, deterministic, supersession_state)
values (
  'ops-change-deployment-step-06-deploy-to-preview', 'department', 'engineering', 'it', null,
  'decision', 'decision_playbook', 'decision_playbook',
  'Change to production — step 6 — deploy to preview',
  'Deploy to preview. The honest determination for this company is that there is no second project to preview into: the founder deleted the staging branch on 15 Aug 2026 — "there is no staging branches, we directly build, test, pass then production" — and list_projects returns exactly one project, htdblwldjkcgjvmqkbeh. The preview stage was not removed, it was replaced, and .github/workflows/deploy-functions.yml says exactly what replaced it.

WHAT "PREVIEW" IS HERE: a push to any branch that is not main. That run resolves the same slug set the production deploy will use (deploy_functions.mjs --changed --base=<sha>, widened to every importer if _shared moved), PRINTS it with --dry-run so that "deployed nothing" and "had nothing to deploy" cannot look alike, and TYPECHECKS it with deno check. The Deploy step is gated on github.ref == refs/heads/main, so a non-main push never touches the project. The typecheck is the gate that used to be staging.

THE DECISION AT THIS STEP, from the branch push:
- The dry-run printed a non-empty slug set, and it matches the slugs step 1 proposed -> preview PASSES.
- deno check is clean on every printed slug -> preview PASSES.
- The dry-run printed nothing while the change claims to touch edge functions -> preview FAILS; the change is not where the deploy resolver looks.
- deno check reports an error -> preview FAILS. This is the whole point of the gate: a compile error in an edge function is a silent 500 in production.

OUTPUT: the resolved slug set, the typecheck result, and a pass or fail. This step is authority-gated: it does not promote anything, and it never passes --production. ESCALATE when the resolved slug set is wider than the proposal without _shared explaining it.',
  '{"decides":"whether the change passes the preview gate before promotion","preview_is":"a push to a non-main branch: deploy_functions.mjs --dry-run resolves and prints the slug set, then deno check typechecks it; the Deploy step is gated on refs/heads/main","why":"the staging branch and second project were deleted 15 Aug 2026; the typecheck is the gate that replaced staging","pass_when":["non-empty slug set matching the step 1 proposal","deno check clean on every printed slug"],"fail_when":["empty slug set for a change that claims to touch edge functions","deno check error"],"escalate_when":["the resolved slug set is wider than the proposal and _shared does not explain it"],"gate":"authority; this step never passes --production"}'::jsonb,
  array['MASTER_PLAN-4.2', 'scripts/deploy_functions.mjs', '.github/workflows/deploy-functions.yml', 'scripts/apply_sql.mjs', 'scripts/sql/down/', 'scripts/checks/', 'public.workflow_step:change_deployment:6']::text[],
  'implemented', 'author_verified', 'supervised', 'medium',
  '1.0.0', date '2026-09-04', date '2027-03-04',
  array['change_deployment', 'preview', 'branch push', 'deno check', 'staging deleted', 'deploy-functions.yml']::text[], '{}'::text[],
  '{"when":"blocked_by_missing_evidence_or_authority","action":"create_owned_escalation"}'::jsonb,
  'AE', 'repository_verified', 'quotesdone_engineering', 'stable', 'internal',
  true, true, 'current')
on conflict (record_id) do update set
  scope_type = excluded.scope_type, scope_key = excluded.scope_key, dept_key = excluded.dept_key,
  role_key = excluded.role_key, module = excluded.module, layer = excluded.layer,
  record_type = excluded.record_type, title = excluded.title, content = excluded.content,
  structured_data = excluded.structured_data, source_ids = excluded.source_ids,
  authority_tier = excluded.authority_tier, risk_level = excluded.risk_level,
  keywords = excluded.keywords, escalation_rule = excluded.escalation_rule,
  runtime_eligible = true, deterministic = true, supersession_state = 'current';

-- step 7 — worked by qa_manager
insert into public.ops_knowledge
  (record_id, scope_type, scope_key, dept_key, role_key, module, layer, record_type, title, content,
   structured_data, source_ids, implementation_status, validation_status, authority_tier, risk_level,
   version, effective_date, review_after, keywords, dependencies, escalation_rule,
   jurisdiction, source_type, source_authority, source_freshness, confidentiality,
   runtime_eligible, deterministic, supersession_state)
values (
  'ops-change-deployment-step-07-rule-on-the-evidence-release-go-no-go', 'department', 'engineering', 'it', null,
  'decision', 'decision_playbook', 'decision_playbook',
  'Change to production — step 7 — rule on the evidence: release go/no-go. The director reads what steps 4 and 5 produced and did not produce either of them',
  'Rule on the evidence: release go or no-go. The separation this step exists for is written into it — the director READS what steps 4 and 5 produced and did not produce either of them. A ruling made by whoever generated the evidence is not a ruling, and this step returns no-go if the same actor closed step 4 or step 5.

READ THESE, AND NOTHING ELSE, FROM THE RUN''S OWN PRIOR STEPS:
- Step 4 output: applicable yes/no, the named held-out set, the measure and its number, and the verdict.
- Step 5 output: the suites run, pass and fail counts, and for each new check the recorded red-then-green pair.
- Step 6 output: the resolved slug set and the typecheck result.
- Step 1 output: the proposed slugs, the metric and the captured baseline.

RULE GO WHEN ALL OF: step 5 reports no failing suite and every new check has its recorded red run; step 4 is pass, not applicable, or held with a named held-out set; step 6 passed with a slug set that matches step 1; and either step 4 or step 5 was closed by someone other than the ruler.

RULE NO-GO WHEN ANY OF: a suite failed; a new check has no recorded red run; step 4 was neither run nor explicitly ruled not applicable; step 6 resolved a slug set wider than the proposal; or the evidence is missing, in which case the ruling is no-go on absence — an absent input is not a satisfied one.

OUTPUT: go or no-go, the four evidence items quoted with their numbers, and the specific clause that decided it. ESCALATE to the engineering director on a no-go that is caused by a missing step rather than a failing one, because that is a broken run, not a bad change.',
  '{"decides":"release go or no-go, on the evidence steps 4, 5 and 6 produced","reads":["step 4 verdict and held-out set","step 5 suite results and red-then-green pairs","step 6 slug set and typecheck","step 1 proposal, metric and baseline"],"go_when":["no failing suite","every new check has a recorded red run","step 4 pass, not applicable, or held with a named set","step 6 pass with a matching slug set","the ruler did not close step 4 or step 5"],"no_go_when":["a suite failed","a new check has no recorded red run","step 4 neither run nor ruled not applicable","step 6 slug set wider than the proposal","evidence missing — absence is a no-go, not a pass"],"separation_of_duties":"the ruler must not be the actor who closed step 4 or step 5","escalate_when":["no-go caused by a missing step rather than a failing one"]}'::jsonb,
  array['MASTER_PLAN-4.2', 'scripts/deploy_functions.mjs', '.github/workflows/deploy-functions.yml', 'scripts/apply_sql.mjs', 'scripts/sql/down/', 'scripts/checks/', 'public.workflow_step:change_deployment:7']::text[],
  'implemented', 'author_verified', 'supervised', 'medium',
  '1.0.0', date '2026-09-04', date '2027-03-04',
  array['change_deployment', 'release', 'go/no-go', 'evidence', 'separation of duties', 'quality and release director']::text[], '{}'::text[],
  '{"when":"blocked_by_missing_evidence_or_authority","action":"create_owned_escalation"}'::jsonb,
  'AE', 'repository_verified', 'quotesdone_engineering', 'stable', 'internal',
  true, true, 'current')
on conflict (record_id) do update set
  scope_type = excluded.scope_type, scope_key = excluded.scope_key, dept_key = excluded.dept_key,
  role_key = excluded.role_key, module = excluded.module, layer = excluded.layer,
  record_type = excluded.record_type, title = excluded.title, content = excluded.content,
  structured_data = excluded.structured_data, source_ids = excluded.source_ids,
  authority_tier = excluded.authority_tier, risk_level = excluded.risk_level,
  keywords = excluded.keywords, escalation_rule = excluded.escalation_rule,
  runtime_eligible = true, deterministic = true, supersession_state = 'current';

-- step 8 — worked by cto
insert into public.ops_knowledge
  (record_id, scope_type, scope_key, dept_key, role_key, module, layer, record_type, title, content,
   structured_data, source_ids, implementation_status, validation_status, authority_tier, risk_level,
   version, effective_date, review_after, keywords, dependencies, escalation_rule,
   jurisdiction, source_type, source_authority, source_freshness, confidentiality,
   runtime_eligible, deterministic, supersession_state)
values (
  'ops-change-deployment-step-08-promote-to-production', 'department', 'engineering', 'it', null,
  'decision', 'decision_playbook', 'decision_playbook',
  'Change to production — step 8 — promote to production',
  'Promote to production. Promotion in this company is a merge to main, not a command anyone types: .github/workflows/deploy-functions.yml runs the Deploy step only when github.ref is refs/heads/main or on an explicit workflow_dispatch, and it calls the same scripts/deploy_functions.mjs a human calls, so CI and a person deploy under identical rules.

PRECONDITIONS, ALL REQUIRED BEFORE PROMOTING:
- Step 7 ruled go.
- The change is merged to main by pull request. Production runs what main says.
- SUPABASE_ACCESS_TOKEN is configured, or the Deploy step is skipped and the run announces a warning rather than deploying. A skipped deploy is not a green deploy.
- --production is passed only because the target IS the one project; the script refuses production unless it is said out loud, so a typo cannot reach production by accident.

PROMOTION IS VERIFIED, NOT CLAIMED. deploy_functions.mjs reads every slug''s version from the management API before and after; a deploy that did not bump the version did not happen, whatever the CLI printed. A 429 from the management API is the road being busy, not the build being broken: the reader retries seven times with backoff to 76.8s and paces the loop at 250ms for a large set. Promotion succeeds only on DEPLOYED_OK n/n with no NOT VERIFIED line, and only then does the script emit deploy.completed with ref, functions, count and at.

DECIDE: promote when every precondition holds; HOLD when step 7 ruled no-go, when the branch is not main, or when the token is absent. ESCALATE to the founder only when the change is on a money-out path — refunds and spend above the Meta cap are founder-gated and are never promoted by an agent.',
  '{"decides":"whether to promote the change to production, and what counts as a verified promotion","promotion_is":"a merge to main; deploy-functions.yml runs the Deploy step only on refs/heads/main or an explicit dispatch, calling scripts/deploy_functions.mjs","preconditions":["step 7 ruled go","merged to main by pull request","SUPABASE_ACCESS_TOKEN configured (a skipped deploy is not a green deploy)","--production passed deliberately"],"verification":"version read before and after per slug; DEPLOYED_OK n/n and no NOT VERIFIED line; a 429 is retried 7x with backoff to 76.8s","emits":"deploy.completed {ref, functions, count, at} via fn_emit, only after ALL GOOD","hold_when":["step 7 no-go","branch is not main","token absent"],"escalate_to_founder_when":["the change is on a money-out path (refunds, Meta spend above the cap)"]}'::jsonb,
  array['MASTER_PLAN-4.2', 'scripts/deploy_functions.mjs', '.github/workflows/deploy-functions.yml', 'scripts/apply_sql.mjs', 'scripts/sql/down/', 'scripts/checks/', 'public.workflow_step:change_deployment:8']::text[],
  'implemented', 'author_verified', 'supervised', 'high',
  '1.0.0', date '2026-09-04', date '2027-03-04',
  array['change_deployment', 'promote', 'production', 'merge to main', 'version bump', 'deploy.completed']::text[], '{}'::text[],
  '{"when":"blocked_by_missing_evidence_or_authority","action":"create_owned_escalation"}'::jsonb,
  'AE', 'repository_verified', 'quotesdone_engineering', 'stable', 'internal',
  true, true, 'current')
on conflict (record_id) do update set
  scope_type = excluded.scope_type, scope_key = excluded.scope_key, dept_key = excluded.dept_key,
  role_key = excluded.role_key, module = excluded.module, layer = excluded.layer,
  record_type = excluded.record_type, title = excluded.title, content = excluded.content,
  structured_data = excluded.structured_data, source_ids = excluded.source_ids,
  authority_tier = excluded.authority_tier, risk_level = excluded.risk_level,
  keywords = excluded.keywords, escalation_rule = excluded.escalation_rule,
  runtime_eligible = true, deterministic = true, supersession_state = 'current';

-- step 9 — worked by cpo
insert into public.ops_knowledge
  (record_id, scope_type, scope_key, dept_key, role_key, module, layer, record_type, title, content,
   structured_data, source_ids, implementation_status, validation_status, authority_tier, risk_level,
   version, effective_date, review_after, keywords, dependencies, escalation_rule,
   jurisdiction, source_type, source_authority, source_freshness, confidentiality,
   runtime_eligible, deterministic, supersession_state)
values (
  'ops-change-deployment-step-09-monitor-grade-outcome-reverse-if-worse', 'department', 'strategy_evolution', 'evolution', null,
  'sop', 'department_shared', 'standard_operating_procedure',
  'Change to production — step 9 — monitor and grade the outcome against the baseline; reverse if worse',
  'Monitor the change and grade its outcome against the baseline step 1 captured; reverse it if the outcome is worse. A change nobody graded is a change nobody learned from, and a grade without the baseline it was promised against is an opinion.

MONITOR, over the 24 hours following context.at, for exactly the slugs in context.functions:
- error_log rows attributed to each slug: count and first occurrence.
- agent_runs outcomes for any routine those slugs drive: ok, error, skipped.
- The metric step 1 named, measured over the same 24 hours.

GRADE against the captured baseline, deterministically:
- BETTER — the metric moved in the intended direction and no new error class appeared. Record the delta and close.
- NEUTRAL — the metric is inside the baseline''s own variation and no new error class appeared. Record it as neutral; a change that did not move its metric is not a success, and saying so is how the next proposal gets better.
- WORSE — the metric moved against its intent, or a new error class appeared on a slug the change touched. Reverse.

REVERSE means: redeploy the previously committed bundle for the affected slugs with scripts/deploy_functions.mjs, or apply the change''s down script from scripts/sql/down/ for a database change. The reverse is the route step 1 named; if step 1 named no reverse, that is the finding and it is escalated.

OUTPUT: per-slug error and run counts, the metric with its baseline and delta, the grade, and either the closure or the reversal that was performed. ESCALATE when the outcome is worse and the reverse is unavailable, and when a change graded worse twice in a row on the same surface — that is a pattern, not an incident.',
  '{"decides":"the graded outcome of a promoted change against its captured baseline, and whether to reverse it","monitor_window":"24 hours following context.at, for the slugs in context.functions","signals":["error_log rows per slug","agent_runs outcomes for routines those slugs drive","the metric named in step 1"],"grades":{"better":"metric moved as intended and no new error class — record the delta and close","neutral":"metric inside baseline variation, no new error class — recorded as neutral, not as success","worse":"metric moved against intent, or a new error class on a touched slug — reverse"},"reverse":"redeploy the previously committed bundle via scripts/deploy_functions.mjs, or apply the down script under scripts/sql/down/","escalate_when":["worse and no reverse available","graded worse twice in a row on the same surface"]}'::jsonb,
  array['MASTER_PLAN-4.2', 'scripts/deploy_functions.mjs', '.github/workflows/deploy-functions.yml', 'scripts/apply_sql.mjs', 'scripts/sql/down/', 'scripts/checks/', 'public.workflow_step:change_deployment:9']::text[],
  'implemented', 'author_verified', 'supervised', 'medium',
  '1.0.0', date '2026-09-04', date '2027-03-04',
  array['change_deployment', 'monitor', 'grade', 'baseline', 'reverse', 'rollback', 'error_log', 'agent_runs']::text[], '{}'::text[],
  '{"when":"blocked_by_missing_evidence_or_authority","action":"create_owned_escalation"}'::jsonb,
  'AE', 'repository_verified', 'quotesdone_engineering', 'stable', 'internal',
  true, true, 'current')
on conflict (record_id) do update set
  scope_type = excluded.scope_type, scope_key = excluded.scope_key, dept_key = excluded.dept_key,
  role_key = excluded.role_key, module = excluded.module, layer = excluded.layer,
  record_type = excluded.record_type, title = excluded.title, content = excluded.content,
  structured_data = excluded.structured_data, source_ids = excluded.source_ids,
  authority_tier = excluded.authority_tier, risk_level = excluded.risk_level,
  keywords = excluded.keywords, escalation_rule = excluded.escalation_rule,
  runtime_eligible = true, deterministic = true, supersession_state = 'current';

-- ---------------------------------------------------------------------------------------------------
-- PROVE IT IN THE SAME TRANSACTION, on the shape the applier depends on. This asserts only what this
-- file writes: nine rows, all four-kinds actionable, all runtime-eligible, all deterministic, each one
-- reachable by the seat that works its step, and each title carrying enough of its step's own lexemes
-- to satisfy the corroboration rule (>=2 terms AND >=30% of them). Cosine is NOT asserted here — it
-- needs the embedding cron, and it is proven by probe after cron 315 runs.
-- ---------------------------------------------------------------------------------------------------
do $$
declare
  v_n int; v_bad text;
begin
  select count(*) into v_n from public.ops_knowledge
   where record_id like 'ops-change-deployment-step-%'
     and record_type in ('decision_playbook','decision_rule','standard_operating_procedure','exception_playbook')
     and runtime_eligible and deterministic and supersession_state = 'current'
     and length(content) >= 300;
  if v_n <> 9 then
    raise exception 'expected 9 actionable runtime-eligible change_deployment records, found %', v_n;
  end if;

  -- Reachability + corroboration, per step, through the applier's own scope predicate.
  select string_agg(z.why, '; ') into v_bad from (
    select 'step ' || s.step_no || ': ' ||
           case when k.record_id is null then 'no record'
                when not (
                     k.scope_type in ('company','external_source')
                  or (k.scope_type = 'department' and k.dept_key = any(public.fn_dept_scope(a.department)))
                  or (k.role_key = any(coalesce((select array_agg(i.packaged_role_id)
                                                   from public.org_role_identity i
                                                  where i.agent_key = a.agent_key), '{}')))
                ) then 'out of scope for ' || a.agent_key
                when t.matched < 2 or t.matched::numeric / greatest(t.total,1) < 0.30
                     then 'corroboration ' || t.matched || '/' || t.total
           end as why
      from public.workflow_step s
      join lateral (values (1,'optimisation_eng'),(2,'cto'),(3,'eng_manager'),(4,'qa_manager'),
                           (5,'qa_manager'),(6,'cto'),(7,'qa_manager'),(8,'cto'),(9,'cpo'))
             as m(step_no, agent_key) on m.step_no = s.step_no
      join public.org_agents a on a.agent_key = m.agent_key
      left join public.ops_knowledge k
             on k.record_id like 'ops-change-deployment-step-' || lpad(s.step_no::text, 2, '0') || '-%'
      left join lateral (
             select (select count(distinct l.lexeme) from unnest(to_tsvector('english', 'Change to production ' || s.step)) l
                      where length(l.lexeme) >= 3) as total,
                    (select count(*) from unnest(tsvector_to_array(k.tsv)) t2
                      where t2 = any(array(select distinct l.lexeme from unnest(to_tsvector('english', 'Change to production ' || s.step)) l
                                            where length(l.lexeme) >= 3)))  as matched
           ) t on true
     where s.workflow_key = 'change_deployment'
  ) z where z.why is not null;

  if v_bad is not null then
    raise exception 'change_deployment playbooks are not usable by the seats that work the steps: %', v_bad;
  end if;

  raise notice 'proof: 9 actionable change_deployment records, each in scope for its seat and corroborated by its step''s own terms';
end $$;

commit;
