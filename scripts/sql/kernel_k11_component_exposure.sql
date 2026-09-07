-- ============================================================================================
-- KERNEL K11 — COMPONENT EXPOSURE
--
-- "A deferred component must actually be unreachable, disabled, undeployed or access-controlled.
--  Do not use a registry label as the control."
--
-- 221 rows of phase_c_component carried classification = DEFERRED_RUNTIME_IMPLEMENTATION with
-- activation_state = 'inactive', on the recorded basis that each had "no caller and no entry point
-- anywhere". The label was the only thing holding them there. Re-measuring every reachability
-- vector against the live catalogue, the platform and the repository shows the label was wrong in
-- four different ways at once, and also right far more often than the headline suggested.
--
-- WHAT THE RE-MEASUREMENT FOUND (each number is reproduced by the functions created below)
--
--   1. THE HEADLINE OVERSTATES THE ESTATE BY 41%. 91 of the 206 deferred database functions are
--      extension internals (69 pgvector, 22 pg_trgm) that were never QuotesDone components. They
--      are pg_depend deptype 'e' objects and are now EXCLUDED and counted separately. The real
--      QuotesDone deferred population is 149, not 221.
--
--   2. "106 of 206 grant EXECUTE to anon" is TRUE and MISLEADING. 91 of that 106 are the same
--      extension internals. Of QuotesDone's own 115, exactly 15 are anon-executable — and 13 of
--      those fifteen hold it ONLY through PUBLIC (`=X/postgres` in proacl; only canary_scan and
--      fn_gl_net_income carry an explicit anon=X grant). A `revoke execute ... from anon` on the
--      thirteen is a silent no-op — the revoke has to name PUBLIC. The
--      derivation therefore tests has_function_privilege('anon', oid, 'EXECUTE'), never the grant
--      statement. None of the fifteen mutates state.
--
--   3. FOUR COMPONENTS WERE UNEXPECTEDLY ACTIVE — running, now, while labelled inactive:
--        * fn_enforce_rls_on_new_tables  — ENABLED EVENT TRIGGER trg_enforce_rls_new_tables on
--          ddl_command_end. It fires on every DDL statement and it mutates state. The previous
--          sweep looked at pg_trigger and never at pg_event_trigger.
--        * fn_archetype_tier   — compiled into public.v_role_identity_collision.
--        * fn_jsonb_text_array — compiled into public.inquiries_supplier_safe.
--          Both run on every SELECT of their view.
--        * cron:autonomy_dispose_hourly — cron.job 64 is active = TRUE on '45 * * * *', 372 runs,
--          13 of them in the last seven days, last run 2026-08-16 20:45 UTC. It mutates state and
--          it was filed INACTIVE_HISTORICAL. The audit's own list did not contain this one.
--
--   4. THE EDGE-FUNCTION PICTURE IS THE REVERSE OF WHAT WAS RECORDED. 12 of the 15 deferred edge
--      functions are deployed with verify_jwt = false. That is a platform setting, not an answer.
--      Reading the deployed source of all fifteen:
--        * 5 are 410 stubs retired 22 Jul 2026 with their reason in the file
--          (kb_retrieve, licence_reminder, orchestrate, support_ai, voice_otp; brand_upload is a
--          sixth, behind verify_jwt = true). Deployed, reachable, inert.
--        * 7 authenticate INSIDE the function — Bearer -> auth.getUser -> 401
--          (attach_photos, inquiry_dedup_check, qa_api, quote_quality, rate_dims, refund_flow,
--          sup_dob). The audit's "6 of the 12 mutate state and are reachable unauthenticated" is
--          therefore an overstatement: five of those six ask for a JWT.
--        * 1 requires a 32-char shared token from app_secrets (kb_corpus_import, 403 without it).
--        * 1 has no authentication of any kind: pdpl_request.
--
--   5. THE SWEEP NEVER LOOKED IN scripts/**. edge:kb_corpus_import was filed "no caller in repo,
--      database or cron" while scripts/pull_asset.js, scripts/pull_kb_import_assets.js and
--      scripts/sync_migrations_from_prod.js each POST to its production URL. Sweeping scripts/**
--      for real invocations (rpc('name') or a SQL string containing name() ) finds 25 more
--      database functions with a live checked-in caller. Script callers are now a first-class
--      vector.
--
--   6. external_entry SAYS "no" ON ALL 206 DATABASE FUNCTIONS, including the fifteen an anonymous
--      caller can reach over PostgREST RPC; it says "unauthenticated_only" on six edge functions
--      that return 401 or 403 without a credential; and it says "no" on three that are deployed and
--      addressable. 24 of the 149 recorded answers disagree with the derived one, in both
--      directions. K11 corrects external_entry from the derivation as well, so the check stays a
--      live drift detector rather than a one-off count.
--
-- WHAT THIS MIGRATION DOES NOT DO
--   fn_enforce_rls_on_new_tables is a working security control and is NOT dropped or disabled; it
--   is relabelled to what it is. pdpl_request is a UAE PDPL data-subject endpoint and MUST stay
--   publicly reachable without an account — that is the law, not a defect. Its real defect is abuse
--   capacity (its only rate limit is 3 per EMAIL per rolling day and an anonymous caller varies the
--   email freely; every accepted request fires alert_founder) and that is recorded as a named
--   Phase D item, not fixed here.
--
-- HOW THE DERIVATION IS KEPT HONEST
--   fn_kernel_component_reachability reads pg_proc, pg_trigger, pg_event_trigger, pg_class,
--   pg_depend, cron.job and has_function_privilege — and phase_c_component_probe for the facts a
--   database cannot see (a Deno deployment's verify_jwt, a TypeScript authorisation branch, a file
--   in scripts/**). It reads component_type and source_path_or_db_object because those are the
--   component's IDENTITY — how to find the object. It NEVER reads classification,
--   activation_state, external_entry, entry_method, current_callers or schedule_or_trigger. A
--   registry label can never be the reason the derivation calls something reachable.
-- ============================================================================================

begin;

-- ------------------------------------------------------------------ 1. the un-seeable facts
--
-- Everything else in this file is measured live from the catalogue at call time. These five vectors
-- cannot be: the database cannot read a Supabase Functions deployment setting, a TypeScript
-- authorisation branch, or a file in the repository. They are measured once, out of band, and
-- recorded here WITH the evidence and the timestamp, so a reader can re-run the same measurement
-- and disagree with it. That is the difference between a measured fact and a label.
create table if not exists public.phase_c_component_probe (
  component_id text    not null references public.phase_c_component(component_id) on delete cascade,
  vector       text    not null,
  present      boolean not null,
  evidence     text    not null,
  measured_at  timestamptz not null default now(),
  measured_by  text    not null default 'kernel:k11',
  primary key (component_id, vector),
  constraint phase_c_component_probe_vector_ck check (vector = any (array[
    'http_deployed', 'http_verify_jwt', 'in_function_auth', 'retired_stub',
    'frontend_caller', 'script_caller'])),
  constraint phase_c_component_probe_evidence_ck check (evidence <> '')
);

comment on table public.phase_c_component_probe is
  'K11. Reachability vectors that cannot be read from the Postgres catalogue: edge-function '
  'deployment state and verify_jwt, in-function authorisation, retired 410 stubs, and callers in '
  'src/** and scripts/**. One row per (component, vector) with the evidence that decided it. '
  'fn_kernel_component_reachability merges these with the live catalogue vectors.';

alter table public.phase_c_component_probe enable row level security;
revoke all on public.phase_c_component_probe from public;
grant select, insert, update, delete on public.phase_c_component_probe to service_role;

-- ------------------------------------------------------------------ 2. seed: edge functions
--
-- Measured 2026-08-16 against the live project htdblwldjkcgjvmqkbeh: verify_jwt and status from the
-- Supabase Functions API, authorisation from the DEPLOYED source of each function (fetched back
-- from the platform, not read from the working tree).
insert into public.phase_c_component_probe (component_id, vector, present, evidence) values
  ('edge:attach_photos','http_deployed',true,'Functions API: status ACTIVE, version 7'),
  ('edge:attach_photos','http_verify_jwt',false,'Functions API: verify_jwt=false — no platform JWT gate'),
  ('edge:attach_photos','in_function_auth',true,'index.ts:14-16 Bearer -> admin.auth.getUser -> 401 "Not signed in"'),
  ('edge:brand_upload','http_deployed',true,'Functions API: status ACTIVE, version 4'),
  ('edge:brand_upload','http_verify_jwt',true,'Functions API: verify_jwt=true — platform rejects an anonymous call'),
  ('edge:brand_upload','retired_stub',true,'index.ts is a 2-line 410 responder: "brand_upload was a one-time uploader and is decommissioned"'),
  ('edge:inquiry_dedup_check','http_deployed',true,'Functions API: status ACTIVE, version 3'),
  ('edge:inquiry_dedup_check','http_verify_jwt',false,'Functions API: verify_jwt=false'),
  ('edge:inquiry_dedup_check','in_function_auth',true,'index.ts:8-10 Bearer -> admin.auth.getUser -> 401 "Not signed in"'),
  ('edge:kb_corpus_import','http_deployed',true,'Functions API: status ACTIVE, version 7'),
  ('edge:kb_corpus_import','http_verify_jwt',false,'Functions API: verify_jwt=false'),
  ('edge:kb_corpus_import','in_function_auth',true,'index.ts:66-67 body.__token compared to app_secrets.kb_import_token (>=32 chars) -> 403 "forbidden"'),
  ('edge:kb_corpus_import','script_caller',true,'scripts/pull_asset.js:11, scripts/pull_kb_import_assets.js:14 and scripts/sync_migrations_from_prod.js:15 each POST https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/kb_corpus_import — the vector the previous sweep omitted'),
  ('edge:kb_retrieve','http_deployed',true,'Functions API: status ACTIVE, version 4'),
  ('edge:kb_retrieve','http_verify_jwt',false,'Functions API: verify_jwt=false'),
  ('edge:kb_retrieve','retired_stub',true,'index.ts is a 410 responder, RETIRED 22 Jul 2026 (OS audit F7): orphaned duplicate of kb_search'),
  ('edge:licence_reminder','http_deployed',true,'Functions API: status ACTIVE, version 4'),
  ('edge:licence_reminder','http_verify_jwt',false,'Functions API: verify_jwt=false'),
  ('edge:licence_reminder','retired_stub',true,'index.ts is a 410 responder, RETIRED 22 Jul 2026 (OS audit F7): duplicate of doc_reminder'),
  ('edge:orchestrate','http_deployed',true,'Functions API: status ACTIVE, version 6'),
  ('edge:orchestrate','http_verify_jwt',false,'Functions API: verify_jwt=false'),
  ('edge:orchestrate','retired_stub',true,'index.ts is a 410 responder, RETIRED 22 Jul 2026 (OS audit F4/H12): broken contract against agent_act, was paying per step'),
  ('edge:pdpl_request','http_deployed',true,'Functions API: status ACTIVE, version 4'),
  ('edge:pdpl_request','http_verify_jwt',false,'Functions API: verify_jwt=false'),
  ('edge:pdpl_request','in_function_auth',false,'Deployed source read back from the platform (sha dbc4fd31): 27 lines, no Authorization read, no getUser, no token. Unauthenticated probe 2026-08-16 21:00 UTC — POST with no Authorization header and body {"kind":"__invalid_probe__"} returned HTTP 400 "kind must be export or delete" from the function body, not 401 from a gate'),
  ('edge:qa_api','http_deployed',true,'Functions API: status ACTIVE, version 3'),
  ('edge:qa_api','http_verify_jwt',false,'Functions API: verify_jwt=false'),
  ('edge:qa_api','in_function_auth',true,'index.ts:20-22 Bearer -> admin.auth.getUser -> 401 "unauthorized", then per-row 403 ownership checks'),
  ('edge:quote_quality','http_deployed',true,'Functions API: status ACTIVE, version 3'),
  ('edge:quote_quality','http_verify_jwt',true,'Functions API: verify_jwt=true'),
  ('edge:quote_quality','in_function_auth',true,'index.ts:9-13 Bearer -> admin.auth.getUser -> 401, then customers lookup -> 401'),
  ('edge:rate_dims','http_deployed',true,'Functions API: status ACTIVE, version 4'),
  ('edge:rate_dims','http_verify_jwt',true,'Functions API: verify_jwt=true'),
  ('edge:rate_dims','in_function_auth',true,'index.ts:12-24 Bearer -> admin.auth.getUser -> 401, then "you can only rate a supplier you have dealt with" -> 403'),
  ('edge:refund_flow','http_deployed',true,'Functions API: status ACTIVE, version 5'),
  ('edge:refund_flow','http_verify_jwt',false,'Functions API: verify_jwt=false'),
  ('edge:refund_flow','in_function_auth',true,'index.ts:28-34 Bearer -> admin.auth.getUser -> 401 "Not signed in", then customers row -> 403 "no_customer"'),
  ('edge:sup_dob','http_deployed',true,'Functions API: status ACTIVE, version 3'),
  ('edge:sup_dob','http_verify_jwt',false,'Functions API: verify_jwt=false'),
  ('edge:sup_dob','in_function_auth',true,'index.ts:9-11 Bearer -> admin.auth.getUser -> 401 "unauthorized"'),
  ('edge:support_ai','http_deployed',true,'Functions API: status ACTIVE, version 8'),
  ('edge:support_ai','http_verify_jwt',false,'Functions API: verify_jwt=false'),
  ('edge:support_ai','retired_stub',true,'index.ts is a 410 responder, RETIRED 22 Jul 2026 (OS audit F7): superseded by site_assistant'),
  ('edge:voice_otp','http_deployed',true,'Functions API: status ACTIVE, version 6'),
  ('edge:voice_otp','http_verify_jwt',false,'Functions API: verify_jwt=false'),
  ('edge:voice_otp','retired_stub',true,'index.ts is a 410 responder, DISABLED 18 Jul 2026 (security): it published app_secrets.voice_capture_token in cleartext TwiML to any caller')
on conflict (component_id, vector) do update
  set present = excluded.present, evidence = excluded.evidence, measured_at = now();

-- ------------------------------------------------------------------ 3. seed: script callers
--
-- Sweep of scripts/** on branch rebuild/phase-c-execution-kernel, 2026-08-16, for a real INVOCATION
-- (rpc('name') or a SQL string containing name( ) rather than a mere mention of the name. 25 of the
-- 115 QuotesDone deferred database functions have one. A check harness holding a database
-- credential is an entry point: the component is not unreachable, it is reachable by whoever runs
-- the script.
insert into public.phase_c_component_probe (component_id, vector, present, evidence)
select c.component_id, 'script_caller', true,
       'scripts/** invokes it: ' || s.f
  from (values
    ('fn_agent_autonomy_blocked','scripts/checks/runtime_connection_gate_a.mjs:188 select ... public.fn_agent_autonomy_blocked(k)'),
    ('fn_agent_tool_allowed','scripts/checks/runtime_connection_gate_b.mjs and scripts/checks/v3_remediation_regression.mjs'),
    ('fn_blueprint_regressions','scripts/staging/blueprint_history.mjs'),
    ('fn_category_quote_ready','scripts/checks/v3_runtime_behaviour.test.mjs'),
    ('fn_category_specialist_scorecard','scripts/checks/org_reorg_behaviour.test.mjs'),
    ('fn_decide','scripts/staging/gate_decision_chain.mjs'),
    ('fn_objective_cascade','scripts/agents/export_org_docs.mjs and scripts/checks/org_reorg_behaviour.test.mjs'),
    ('fn_onboarding_gate','scripts/checks/runtime_connection_gate_a.mjs:189 select ... public.fn_onboarding_gate(k)'),
    ('fn_open_remediation','scripts/checks/v3_runtime_behaviour.test.mjs'),
    ('fn_os_portals_gates','scripts/kb/pack_scorecard.mjs:216-219 select count(*) from public.fn_os_portals_gates()'),
    ('fn_overlay_for_category','scripts/agents/export_org_docs.mjs and scripts/checks/org_reorg_behaviour.test.mjs'),
    ('fn_phase_b_closure_blockers','scripts/checks/phase_b_guards_reject_injected_defects.test.mjs'),
    ('fn_phase_b_invariants','scripts/checks/phase_b_invariants.test.mjs and scripts/phase_b/rehearse.mjs'),
    ('fn_phase_b_transition_allowed','scripts/checks/phase_b_guards_reject_injected_defects.test.mjs'),
    ('fn_propose_lesson','scripts/checks/v3_runtime_behaviour.test.mjs'),
    ('fn_rating_due','scripts/staging/prove_rating_schedule.mjs'),
    ('fn_refund_decide','scripts/rehearsal/hvac_dress_rehearsal.mjs:455 select (public.fn_refund_decide(...))::text'),
    ('fn_reliability_report','scripts/checks/v3_remediation_regression.mjs'),
    ('fn_retrieval_leak_check','scripts/checks/v3_remediation_regression.mjs'),
    ('fn_retrieval_probe','scripts/checks/v3_remediation_regression.mjs'),
    ('fn_role_isolation_status','scripts/checks/v3_remediation_regression.mjs'),
    ('fn_specialist_invoke','scripts/checks/org_reorg_behaviour.test.mjs'),
    ('fn_trace_edit_is_blocked','scripts/checks/v3_remediation_regression.mjs'),
    ('fn_unsafe_guard_status','scripts/checks/v3_remediation_regression.mjs'),
    ('fn_validate_lesson','scripts/checks/v3_runtime_behaviour.test.mjs')
  ) as s(nm, f)
  join public.phase_c_component c
    on c.component_type = 'database_function'
   and split_part(c.source_path_or_db_object,'.',2) = s.nm
on conflict (component_id, vector) do update
  set present = excluded.present, evidence = excluded.evidence, measured_at = now();

-- The frontend vector, recorded as a measured ABSENCE rather than left blank. src/** contains no
-- reference of any kind to any of the fifteen deferred edge functions — no fetch of
-- /functions/v1/<slug>, no supabase.functions.invoke('<slug>'), not even the bare string.
insert into public.phase_c_component_probe (component_id, vector, present, evidence)
select c.component_id, 'frontend_caller', false,
       'sweep of src/** 2026-08-16: no functions/v1/ fetch, no functions.invoke, no occurrence of the slug'
  from public.phase_c_component c
 where c.component_type = 'edge_function'
   and c.classification = 'DEFERRED_RUNTIME_IMPLEMENTATION'
on conflict (component_id, vector) do update
  set present = excluded.present, evidence = excluded.evidence, measured_at = now();

-- ------------------------------------------------------------------ 4. the derivation
--
-- Returns one jsonb object per component: every vector as its own boolean with its own evidence
-- string, then the conclusions those vectors force. Reads identity from phase_c_component
-- (component_type, source_path_or_db_object) and status from nowhere.
-- ROUTINE REMOVED 7 September 2026. public.fn_kernel_component_reachability was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


revoke all on function public.fn_kernel_component_reachability(text) from public;
grant execute on function public.fn_kernel_component_reachability(text) to service_role;

comment on function public.fn_kernel_component_reachability(text) is
  'K11. Derives a component''s reachability from measurable facts only: pg_proc, pg_trigger, '
  'pg_event_trigger, pg_class, pg_depend, cron.job, has_function_privilege, and '
  'phase_c_component_probe for the platform and repository vectors a database cannot see. Reads '
  'phase_c_component for identity (type, object) and never for status. Extension-owned objects '
  '(pg_depend deptype ''e'') return EXTENSION_OWNED_EXCLUDED.';

-- ------------------------------------------------------------------ 5a. freeze the denominator
--
-- The first draft of the invariant below defined its population as "activation_state = inactive or
-- classification = DEFERRED_RUNTIME_IMPLEMENTATION", and the rehearsal caught it: reclassifying 48
-- rows moved them OUT of the population, and every check went green over a denominator that had
-- shrunk from 149 to 101. A check whose population is its own subject can always be made to pass by
-- relabelling — which is the exact defect this increment exists to remove.
--
-- So the population is frozen here, once, from the state BEFORE any reclassification: every
-- component that carried an inactive activation_state or a DEFERRED classification at the moment
-- K11 was applied. It never shrinks. Later increments that genuinely wire one of these up leave the
-- row in scope and change what the derivation says about it.
create table if not exists public.phase_c_component_exposure_scope (
  component_id text primary key references public.phase_c_component(component_id) on delete cascade,
  frozen_at    timestamptz not null default now(),
  frozen_as    text not null,          -- classification / activation_state at freeze time
  reason       text not null
);

comment on table public.phase_c_component_exposure_scope is
  'K11. The frozen denominator of the exposure invariant: the components that were labelled '
  'inactive or deferred when K11 was applied. Frozen so that reclassifying a row cannot make a '
  'check pass by removing its own subject from the population.';

alter table public.phase_c_component_exposure_scope enable row level security;
revoke all on public.phase_c_component_exposure_scope from public;
grant select, insert, update, delete on public.phase_c_component_exposure_scope to service_role;

insert into public.phase_c_component_exposure_scope (component_id, frozen_as, reason)
select c.component_id, c.classification || ' / ' || c.activation_state,
       'in the inactive-or-deferred population when K11 was applied'
  from public.phase_c_component c
 where c.activation_state = 'inactive'
    or c.classification   = 'DEFERRED_RUNTIME_IMPLEMENTATION'
on conflict (component_id) do nothing;

-- ------------------------------------------------------------------ 5. the exposure invariant
--
-- Numerator AND denominator on every line, over the FULL frozen population minus the extension
-- internals, so a green number cannot be produced by a shrinking denominator.
-- ROUTINE REMOVED 7 September 2026. public.fn_kernel_component_exposure_state was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


revoke all on function public.fn_kernel_component_exposure_state() from public;
grant execute on function public.fn_kernel_component_exposure_state() to service_role;

comment on function public.fn_kernel_component_exposure_state() is
  'K11 exposure invariant. Four checks with numerator and denominator over the full '
  'inactive-or-deferred population less extension internals, plus the excluded extension count. '
  'Every line is reproducible from fn_kernel_component_reachability.';

-- ------------------------------------------------------------------ 6. widen the CHECK
--
-- Exactly the five names this migration introduces, and no more. ACTIVE_INTERNAL_CALLER,
-- ACTIVE_CRON, ACTIVE_FRONTEND_ENTRY, ACTIVE_WEBHOOK_ENTRY and INTENTIONALLY_RETIRED were already
-- admitted and are reused rather than duplicated.
alter table public.phase_c_component drop constraint if exists phase_c_component_classification_ck;
alter table public.phase_c_component add constraint phase_c_component_classification_ck
  check (classification = any (array[
    'ACTIVE_FRONTEND_ENTRY','ACTIVE_EXTERNAL_API','ACTIVE_WEBHOOK_ENTRY','ACTIVE_CRON',
    'ACTIVE_INTERNAL_CALLER','ACTIVE_DATABASE_TRIGGER','ACTIVE_QUEUE_CONSUMER',
    'DEFERRED_RUNTIME_IMPLEMENTATION','INTENTIONALLY_INACTIVE','HISTORICAL_ONLY',
    'INTENTIONALLY_RETIRED','CANONICAL_KEEP','CANONICAL_BETTER_KEEP','WIRE_TO_CANONICAL',
    'REPAIR_BEFORE_REACTIVATION','INACTIVE_HISTORICAL','NO_CALLER_UNCLASSIFIED',
    -- K11
    'ACTIVE_EVENT_TRIGGER','ACTIVE_AUTH_HOOK','ACTIVE_PUBLIC_ENTRY','ACTIVE_SCRIPT_ENTRY',
    'ACCESS_CONTROLLED_NO_CALLER']));

-- ------------------------------------------------------------------ 7. the guard
--
-- Same shape as a00_phase_c_event_binding_status_guard: a hand-written classification the
-- derivation does not support is refused. Wire the missing leg, or record what is true; do not
-- relabel the row.
--
-- It refuses in three directions and stays silent everywhere else:
--   * a deferred/inactive label on something the derivation can reach;
--   * an ACTIVE_* label on something the derivation cannot reach;
--   * activation_state = 'inactive' on something the derivation finds unexpectedly active.
-- UNDERIVABLE components (state tables, frontend routes, event subscriptions, workflow definitions,
-- and every edge function with no probe row) pass through untouched — a derivation with no
-- measurement must not pretend to an opinion.
create or replace function public.fn_phase_c_component_classification_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'cron', 'pg_temp'
as $k11_guard$
declare
  d           jsonb;
  v_derived   text;
  v_reachable boolean;
  v_unexpect  boolean;
begin
  d := public.fn_kernel_component_reachability(new.component_id);
  v_derived := d->>'derived_classification';

  if v_derived in ('UNDERIVABLE','EXTENSION_OWNED_EXCLUDED') then
    return new;
  end if;

  v_reachable := (d->>'reachable')::boolean;
  v_unexpect  := (d->>'unexpectedly_active')::boolean;

  if new.classification in ('DEFERRED_RUNTIME_IMPLEMENTATION','INACTIVE_HISTORICAL',
                            'INTENTIONALLY_INACTIVE','HISTORICAL_ONLY','NO_CALLER_UNCLASSIFIED')
     and v_reachable then
    -- RAISE has no %L. It is % and a stray literal L, which is how the sibling event-binding guard
    -- ends up printing "CONNECTEDL". Quotes are written into the format string instead.
    raise exception
      'phase_c_component %: classification "%" says this component has no way in, and it has one. '
      'The derivation reaches it via %. Derived classification is "%". '
      'Wire the missing leg, or record what is true; do not relabel the row.',
      new.component_id, new.classification, d->>'decided_by', v_derived
      using errcode = '23514';
  end if;

  if new.classification like 'ACTIVE\_%' and not v_reachable then
    raise exception
      'phase_c_component %: classification "%" claims a live entry point and the derivation finds '
      'none — %. Derived classification is "%". '
      'Wire the missing leg, or record what is true; do not relabel the row.',
      new.component_id, new.classification, d->>'decided_by', v_derived
      using errcode = '23514';
  end if;

  if new.activation_state = 'inactive' and v_unexpect then
    raise exception
      'phase_c_component %: activation_state ''inactive'' cannot stop it — %. Derived state is "%". '
      'Wire the missing leg, or record what is true; do not relabel the row.',
      new.component_id, d->>'decided_by', d->>'derived_activation_state'
      using errcode = '23514';
  end if;

  return new;
end
$k11_guard$;

revoke all on function public.fn_phase_c_component_classification_guard() from public;
grant execute on function public.fn_phase_c_component_classification_guard() to service_role;

drop trigger if exists a00_phase_c_component_classification_guard on public.phase_c_component;
create trigger a00_phase_c_component_classification_guard
  before insert or update of classification, activation_state on public.phase_c_component
  for each row execute function public.fn_phase_c_component_classification_guard();

-- ------------------------------------------------------------------ 8. reclassify from the derivation
--
-- Set from the derivation itself, never by hand, so the guard created above validates every row
-- this migration writes. If any assignment below disagreed with the evidence, this UPDATE would
-- raise and the migration would not apply.
--
-- ONE EXCEPTION, and it matters. When the derivation finds NO vector it returns
-- DEFERRED_RUNTIME_IMPLEMENTATION — which is the absence of a finding, not a finding. Writing that
-- over a row that already says something more specific would destroy real information: the first
-- draft of this UPDATE relabelled eighteen INACTIVE_HISTORICAL cron jobs — one of them with 21,563
-- completed runs before it was switched off — as "deferred runtime implementation", i.e. as though
-- they had never been built. Deactivation is not death. So an empty finding never overwrites an
-- existing inactive-family label; only a positive finding does.
-- The derivation is run ONCE over the frozen scope and materialised, because the guard created
-- above re-runs it on every row this migration writes; recomputing it per statement turned a
-- 240-row migration into a five-minute one.
create temp table k11_derived on commit drop as
select s.component_id, r.j
  from public.phase_c_component_exposure_scope s,
       lateral public.fn_kernel_component_reachability(s.component_id) r(j);

update public.phase_c_component c
   set classification   = d.j->>'derived_classification',
       activation_state = d.j->>'derived_activation_state',
       external_entry   = d.j->>'derived_external_entry',
       evidence         = 'K11 2026-08-16: ' || (d.j->>'decided_by'),
       measured_at      = now()
  from k11_derived d
 where c.component_id = d.component_id
   and d.j->>'derived_classification' not in ('UNDERIVABLE','EXTENSION_OWNED_EXCLUDED')
   and (c.classification, c.activation_state, c.external_entry)
       is distinct from (d.j->>'derived_classification', d.j->>'derived_activation_state',
                         d.j->>'derived_external_entry')
   and not (d.j->>'derived_classification' = 'DEFERRED_RUNTIME_IMPLEMENTATION'
            and c.classification in ('INACTIVE_HISTORICAL','REPAIR_BEFORE_REACTIVATION',
                                     'INTENTIONALLY_RETIRED','INTENTIONALLY_INACTIVE',
                                     'HISTORICAL_ONLY'));

-- external_entry is a separate fact from the classification and is corrected on its own terms, so
-- the rows above that kept their honest inactive label still get an honest external_entry.
update public.phase_c_component c
   set external_entry = d.j->>'derived_external_entry',
       measured_at    = now()
  from k11_derived d
 where c.component_id = d.component_id
   and d.j->>'derived_classification' not in ('UNDERIVABLE','EXTENSION_OWNED_EXCLUDED')
   and c.external_entry is distinct from d.j->>'derived_external_entry';

-- The extension internals keep DEFERRED_RUNTIME_IMPLEMENTATION as a classification — they are not
-- QuotesDone components and inventing a state for them would be its own kind of dishonesty — but
-- their gap now says so, so no future headline counts them again.
update public.phase_c_component c
   set gap = 'not a QuotesDone component: extension internal (pg_depend deptype ''e''). '
          || 'Excluded from the deferred population by fn_kernel_component_exposure_state.',
       measured_at = now()
  from (select d.component_id from k11_derived d
         where d.j->>'derived_classification' = 'EXTENSION_OWNED_EXCLUDED') x
 where c.component_id = x.component_id;

-- ------------------------------------------------------------------ 9. the two kept exceptions
--
-- fn_enforce_rls_on_new_tables is a working security control. It was already relabelled to
-- ACTIVE_EVENT_TRIGGER / active by the derivation above; this records WHY it is not being dropped,
-- so nobody reads "was inactive, now active" as a defect to reverse.
update public.phase_c_component
   set repair_or_keep_action =
         'KEEP AND DO NOT DISABLE. trg_enforce_rls_new_tables is an ENABLED ddl_command_end event '
      || 'trigger that turns row level security on for every table created in this database. It '
      || 'was filed inactive because the sweep read pg_trigger and never pg_event_trigger. It has '
      || 'no caller because it needs none: DDL is its caller. Dropping it would silently open every '
      || 'future table.',
       gap = 'registry said "no trigger"; the object is an enabled EVENT trigger that mutates state '
          || 'on every DDL statement'
 where component_id = 'dbfn:fn_enforce_rls_on_new_tables()';

-- pdpl_request must stay public. That is the law. What it must not stay is trivially abusable.
update public.phase_c_component
   set repair_or_keep_action =
         'KEEP PUBLIC — LEGAL BASIS: UAE Federal Decree-Law 45/2021 (PDPL) Articles 13-17 give a '
      || 'data subject the right to request access, portability and erasure, and the controller '
      || 'must provide a channel that does not require the subject to hold an account. An '
      || 'authentication gate on this endpoint would be the violation, not the fix. '
      || 'PHASE D ITEM — pdpl_request_abuse_capacity: the only limit is 3 requests per EMAIL per '
      || 'rolling 24h (index.ts:16-17) and an anonymous caller varies the email freely, so the '
      || 'endpoint is an unbounded writer to pdpl_requests and an unbounded trigger of '
      || 'alert_founder (index.ts:24, one alert per accepted request, level=action). Needs a '
      || 'per-IP or per-window cap and alert coalescing. NOT changed here: rate limiting is a '
      || 'behaviour change to a legally-required endpoint and belongs in its own increment.',
       gap = 'no authentication of any kind, holds the service-role key, inserts a row and fires a '
          || 'founder alert for any anonymous caller; abuse capacity, not existence, is the defect'
 where component_id = 'edge:pdpl_request';

commit;
