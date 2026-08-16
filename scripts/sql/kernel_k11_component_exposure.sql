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
create or replace function public.fn_kernel_component_reachability(p_component_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'cron', 'pg_temp'
as $k11_reach$
declare
  c              public.phase_c_component%rowtype;
  v_oid          oid;
  v_slug         text;
  v_jobid        bigint;
  v_ext          boolean := false;
  v_vec          jsonb   := '{}'::jsonb;
  v_names        text[]  := '{}';
  v_txt          text;
  v_bool         boolean;
  v_class        text;
  v_state        text;
  v_decided      text;
  v_reachable    boolean := false;
  v_unauth       boolean := false;
  v_unexpected   boolean := false;
  v_external     text;
  -- a deployed 410 responder: it answers HTTP and executes nothing
  v_retired_stub boolean := false;
begin
  select * into c from public.phase_c_component where component_id = p_component_id;
  if not found then
    return jsonb_build_object('component_id', p_component_id, 'derived_classification','UNDERIVABLE',
      'why','no row in phase_c_component with this id');
  end if;

  -- ---- resolve the physical object -------------------------------------------------------
  if c.component_type = 'database_function' then
    select p.oid into v_oid
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = split_part(c.source_path_or_db_object,'.',1)
       and p.proname = split_part(c.source_path_or_db_object,'.',2)
       -- the registry writes the signature without DEFAULT clauses; strip them to compare
       and c.component_id = 'dbfn:' || p.proname || '(' ||
             regexp_replace(pg_get_function_arguments(p.oid),
                            ' DEFAULT .*?(?=(, [a-zA-Z_"]+ )|$)', '', 'g') || ')'
     limit 1;
  elsif c.component_type = 'edge_function' then
    v_slug := regexp_replace(c.component_id, '^edge:', '');
  elsif c.component_type = 'cron_job' then
    begin
      v_jobid := (regexp_replace(c.source_path_or_db_object, '^cron\.job/', ''))::bigint;
    exception when others then v_jobid := null; end;
  end if;

  if c.component_type not in ('database_function','edge_function','cron_job')
     or (c.component_type = 'database_function' and v_oid is null)
     or (c.component_type = 'cron_job' and v_jobid is null) then
    return jsonb_build_object(
      'component_id', c.component_id, 'component_type', c.component_type,
      'extension_owned', false, 'vectors', '{}'::jsonb,
      'reachable', null, 'reachable_unauthenticated', null, 'unexpectedly_active', null,
      'derived_classification','UNDERIVABLE', 'derived_activation_state', null,
      'decided_by','no measurable object: this component type carries no catalogue, platform or '
                 ||'repository vector that this derivation can read');
  end if;

  -- ---- extension-owned objects are not QuotesDone components ------------------------------
  if v_oid is not null then
    select true into v_ext from pg_depend d
     where d.classid = 'pg_proc'::regclass and d.objid = v_oid and d.deptype = 'e' limit 1;
    v_ext := coalesce(v_ext, false);
  end if;
  if v_ext then
    select e.extname into v_txt
      from pg_depend d join pg_extension e on e.oid = d.refobjid
     where d.classid = 'pg_proc'::regclass and d.objid = v_oid and d.deptype = 'e' limit 1;
    return jsonb_build_object(
      'component_id', c.component_id, 'component_type', c.component_type,
      'extension_owned', true, 'vectors', '{}'::jsonb,
      'reachable', null, 'reachable_unauthenticated', null, 'unexpectedly_active', false,
      'derived_classification','EXTENSION_OWNED_EXCLUDED', 'derived_activation_state', null,
      'decided_by', format('pg_depend deptype ''e'' on extension %L — an extension internal, never '
                        || 'a QuotesDone component; excluded from the deferred population', v_txt));
  end if;

  -- ---- vector: HTTP deployment + verify_jwt (probe) ---------------------------------------
  select p.present, p.evidence into v_bool, v_txt
    from public.phase_c_component_probe p
   where p.component_id = c.component_id and p.vector = 'http_deployed';
  if v_bool is not null then
    v_vec := v_vec || jsonb_build_object('http_deployed', jsonb_build_object('present', v_bool, 'evidence', v_txt));
    if v_bool then v_names := v_names || 'http_deployed'::text; end if;
  end if;
  select p.present, p.evidence into v_bool, v_txt
    from public.phase_c_component_probe p
   where p.component_id = c.component_id and p.vector = 'http_verify_jwt';
  if v_bool is not null then
    v_vec := v_vec || jsonb_build_object('http_verify_jwt', jsonb_build_object('present', v_bool, 'evidence', v_txt));
  end if;

  -- ---- vector: in-function authorisation, and the retired 410 stub (probe) ----------------
  select p.present, p.evidence into v_bool, v_txt
    from public.phase_c_component_probe p
   where p.component_id = c.component_id and p.vector = 'in_function_auth';
  if v_bool is not null then
    v_vec := v_vec || jsonb_build_object('in_function_auth', jsonb_build_object('present', v_bool, 'evidence', v_txt));
  end if;
  select p.present, p.evidence into v_bool, v_txt
    from public.phase_c_component_probe p
   where p.component_id = c.component_id and p.vector = 'retired_stub';
  v_retired_stub := coalesce(v_bool, false);
  if v_bool is not null then
    v_vec := v_vec || jsonb_build_object('retired_stub', jsonb_build_object('present', v_bool, 'evidence', v_txt));
  end if;

  -- ---- vector: RPC grants. has_function_privilege, NOT the grant statement -----------------
  -- A `revoke execute from anon` is a silent no-op while the grant is held through PUBLIC, so the
  -- privilege check is the only answer that means anything. The PUBLIC leg is reported separately
  -- because it changes what the repair has to be.
  if v_oid is not null then
    v_bool := has_function_privilege('anon', v_oid, 'EXECUTE');
    v_vec := v_vec || jsonb_build_object('rpc_anon', jsonb_build_object('present', v_bool,
      'evidence', format('has_function_privilege(''anon'', %s, ''EXECUTE'') = %s; proacl = %s',
        v_oid::regprocedure, v_bool, coalesce((select proacl::text from pg_proc where oid = v_oid),'null (owner default: PUBLIC holds EXECUTE)'))));
    if v_bool then v_names := v_names || 'rpc_anon'::text; end if;

    v_bool := has_function_privilege('authenticated', v_oid, 'EXECUTE');
    v_vec := v_vec || jsonb_build_object('rpc_authenticated', jsonb_build_object('present', v_bool,
      'evidence', format('has_function_privilege(''authenticated'', %s, ''EXECUTE'') = %s', v_oid::regprocedure, v_bool)));
    if v_bool then v_names := v_names || 'rpc_authenticated'::text; end if;

    select coalesce(bool_or(a.grantee = 0 and a.privilege_type = 'EXECUTE'), false)
      into v_bool
      from pg_proc p,
           lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     where p.oid = v_oid;
    v_bool := coalesce(v_bool, false);
    v_vec := v_vec || jsonb_build_object('rpc_public', jsonb_build_object('present', v_bool,
      'evidence', case when v_bool
        then 'PUBLIC holds EXECUTE (aclitem grantee 0): a REVOKE FROM anon on this function is a silent no-op'
        else 'PUBLIC does not hold EXECUTE' end));
    if v_bool then v_names := v_names || 'rpc_public'::text; end if;

    -- ---- vector: auth hook. An EXPLICIT grant to supabase_auth_admin, not one inherited -----
    -- through PUBLIC, which every PUBLIC-executable function would otherwise register as a hook.
    select coalesce(bool_or(a.grantee = (select r.oid from pg_roles r where r.rolname = 'supabase_auth_admin')
                            and a.privilege_type = 'EXECUTE'), false)
      into v_bool
      from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     where p.oid = v_oid;
    v_bool := coalesce(v_bool, false);
    v_vec := v_vec || jsonb_build_object('auth_hook', jsonb_build_object('present', v_bool,
      'evidence', case when v_bool
        then 'explicit GRANT EXECUTE to supabase_auth_admin in proacl (not inherited through PUBLIC) '
             || '— the GoTrue auth service can call this'
        else 'no explicit grant to supabase_auth_admin' end));
    if v_bool then v_names := v_names || 'auth_hook'::text; end if;

    -- ---- vector: internal callers in pg_proc.prosrc -----------------------------------------
    select string_agg(cn.nspname||'.'||cp.proname, ', ' order by cp.proname)
      into v_txt
      from pg_proc cp join pg_namespace cn on cn.oid = cp.pronamespace
     where cp.oid <> v_oid
       and cn.nspname not in ('pg_catalog','information_schema')
       and not exists (select 1 from pg_depend d where d.classid='pg_proc'::regclass and d.objid=cp.oid and d.deptype='e')
       -- cheap substring test first; the anchored regex only runs on the handful that survive it
       and strpos(cp.prosrc, (select proname from pg_proc where oid = v_oid)) > 0
       and cp.prosrc ~ ('\y' || (select proname from pg_proc where oid = v_oid) || '\s*\(');
    v_bool := v_txt is not null;
    v_vec := v_vec || jsonb_build_object('internal_caller', jsonb_build_object('present', v_bool,
      'evidence', coalesce('pg_proc.prosrc references it in: '||left(v_txt, 400),
                           'no other non-extension routine names it in pg_proc.prosrc')));
    if v_bool then v_names := v_names || 'internal_caller'::text; end if;

    -- ---- vector: row triggers ---------------------------------------------------------------
    select string_agg(t.tgname, ', ' order by t.tgname) into v_txt
      from pg_trigger t where t.tgfoid = v_oid and not t.tgisinternal;
    v_bool := v_txt is not null;
    v_vec := v_vec || jsonb_build_object('row_trigger', jsonb_build_object('present', v_bool,
      'evidence', coalesce('pg_trigger: '||v_txt, 'no row trigger executes this function')));
    if v_bool then v_names := v_names || 'row_trigger'::text; end if;

    -- ---- vector: EVENT triggers. The vector that missed fn_enforce_rls_on_new_tables --------
    select string_agg(format('%s on %s (evtenabled=%s)', t.evtname, t.evtevent, t.evtenabled), ', ' order by t.evtname)
      into v_txt
      from pg_event_trigger t where t.evtfoid = v_oid and t.evtenabled <> 'D';
    v_bool := v_txt is not null;
    v_vec := v_vec || jsonb_build_object('event_trigger', jsonb_build_object('present', v_bool,
      'evidence', coalesce('pg_event_trigger, ENABLED: '||v_txt,
                           'no enabled event trigger executes this function')));
    if v_bool then v_names := v_names || 'event_trigger'::text; end if;

    -- ---- vector: views and matviews that compile the function in ----------------------------
    -- Through pg_depend on the view's rewrite rule, not a regex over pg_get_viewdef: the dependency
    -- is what the planner itself recorded, so it cannot miss a call and cannot invent one from a
    -- name that merely appears in a comment or a column alias. It is also ~100x cheaper, which
    -- matters when the invariant calls this function once per component.
    select string_agg(distinct cn.nspname||'.'||cl.relname||
                      ' ('||case cl.relkind when 'm' then 'matview' else 'view' end||')', ', ')
      into v_txt
      from pg_depend d
      join pg_rewrite rw on rw.oid = d.objid
      join pg_class cl   on cl.oid = rw.ev_class
      join pg_namespace cn on cn.oid = cl.relnamespace
     where d.refclassid = 'pg_proc'::regclass and d.refobjid = v_oid
       and d.classid = 'pg_rewrite'::regclass
       and cl.relkind in ('v','m');
    v_bool := v_txt is not null;
    v_vec := v_vec || jsonb_build_object('compiled_into_view', jsonb_build_object('present', v_bool,
      'evidence', coalesce('runs on every SELECT of: '||v_txt, 'no view or matview compiles it in')));
    if v_bool then v_names := v_names || 'compiled_into_view'::text; end if;

    -- ---- vector: queue consumers -------------------------------------------------------------
    select string_agg(qn.nspname||'.'||q.proname, ', ' order by q.proname) into v_txt
      from pg_proc q join pg_namespace qn on qn.oid = q.pronamespace
     where qn.nspname in ('pgmq','net')
       and q.prosrc ~ ('\y' || (select proname from pg_proc where oid = v_oid) || '\s*\(');
    v_bool := v_txt is not null;
    v_vec := v_vec || jsonb_build_object('queue_consumer', jsonb_build_object('present', v_bool,
      'evidence', coalesce('named by queue machinery: '||v_txt, 'no pgmq/net routine names it')));
    if v_bool then v_names := v_names || 'queue_consumer'::text; end if;
  end if;

  -- ---- vector: cron, ACTIVE and INACTIVE reported separately -------------------------------
  -- An inactive job is a disabled component; an active one is a running component that a label
  -- calling it inactive cannot stop.
  if v_jobid is not null then
    select format('cron.job %s %L schedule %L active=%s; %s runs, last %s',
                  j.jobid, j.jobname, j.schedule, j.active,
                  (select count(*) from cron.job_run_details r where r.jobid = j.jobid),
                  coalesce((select max(r.start_time)::text from cron.job_run_details r where r.jobid = j.jobid),'never')),
           j.active
      into v_txt, v_bool
      from cron.job j where j.jobid = v_jobid;
    v_vec := v_vec || jsonb_build_object('cron_active', jsonb_build_object('present', coalesce(v_bool,false), 'evidence', coalesce(v_txt,'no cron.job row with this jobid')));
    v_vec := v_vec || jsonb_build_object('cron_registered', jsonb_build_object('present', v_txt is not null, 'evidence', coalesce(v_txt,'no cron.job row with this jobid')));
    if coalesce(v_bool,false) then v_names := v_names || 'cron_active'::text; end if;
  end if;

  -- ---- vector: webhook / net.http_post targeting this component ----------------------------
  if v_slug is not null then
    select string_agg(x.src, ', ') into v_txt from (
      select 'db routine '||n.nspname||'.'||p.proname src
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname not in ('pg_catalog','information_schema')
         and strpos(p.prosrc, 'functions/v1/'||v_slug) > 0
         and p.prosrc ~ ('functions/v1/'||v_slug||'\y')
      union all
      select 'cron.job '||j.jobid||' ('||coalesce(j.jobname,'')||', active='||j.active||')'
        from cron.job j where j.command ~ ('functions/v1/'||v_slug||'\y')
    ) x;
  elsif v_oid is not null then
    select string_agg('trigger '||t.tgname||' -> '||tp.proname, ', ') into v_txt
      from pg_trigger t join pg_proc tp on tp.oid = t.tgfoid
     where not t.tgisinternal and tp.prosrc ~ 'net\.http_post'
       and tp.prosrc ~ ('\y' || (select proname from pg_proc where oid = v_oid) || '\y');
  else
    v_txt := null;
  end if;
  v_bool := v_txt is not null;
  v_vec := v_vec || jsonb_build_object('webhook_caller', jsonb_build_object('present', v_bool,
    'evidence', coalesce('net.http_post / cron HTTP caller: '||v_txt,
                         'no database routine, trigger or cron command posts to this component')));
  if v_bool then v_names := v_names || 'webhook_caller'::text; end if;

  -- ---- vector: frontend callers in src/** (probe) ------------------------------------------
  select p.present, p.evidence into v_bool, v_txt
    from public.phase_c_component_probe p
   where p.component_id = c.component_id and p.vector = 'frontend_caller';
  v_vec := v_vec || jsonb_build_object('frontend_caller', jsonb_build_object('present', coalesce(v_bool,false),
    'evidence', coalesce(v_txt, 'not swept: no src/** measurement recorded for this component')));
  if coalesce(v_bool,false) then v_names := v_names || 'frontend_caller'::text; end if;

  -- ---- vector: SCRIPT callers in scripts/** (probe) — the omitted one -----------------------
  select p.present, p.evidence into v_bool, v_txt
    from public.phase_c_component_probe p
   where p.component_id = c.component_id and p.vector = 'script_caller';
  v_vec := v_vec || jsonb_build_object('script_caller', jsonb_build_object('present', coalesce(v_bool,false),
    'evidence', coalesce(v_txt, 'no invocation of this component found in scripts/**')));
  if coalesce(v_bool,false) then v_names := v_names || 'script_caller'::text; end if;

  -- ---- conclusions -------------------------------------------------------------------------
  -- REACHABLE: some caller, some grant or some schedule can put control into this component.
  -- A retired 410 stub answers HTTP but executes nothing, so it is deployed-and-disabled, not
  -- reachable.
  -- A deployed HTTP endpoint that answers is reachable even when it demands a credential first:
  -- "access-controlled" is a description of HOW it is reached, not a claim that it is not. Only the
  -- 410 stubs are genuinely not reachable, because there is nothing behind the door.
  v_reachable := (not v_retired_stub) and (
       'http_deployed'      = any(v_names)
    or 'rpc_anon'           = any(v_names)
    or 'rpc_authenticated'  = any(v_names)
    or 'auth_hook'          = any(v_names)
    or 'internal_caller'    = any(v_names)
    or 'row_trigger'        = any(v_names)
    or 'event_trigger'      = any(v_names)
    or 'compiled_into_view' = any(v_names)
    or 'queue_consumer'     = any(v_names)
    or 'cron_active'        = any(v_names)
    or 'webhook_caller'     = any(v_names)
    or 'frontend_caller'    = any(v_names)
    or 'script_caller'      = any(v_names));

  -- REACHABLE UNAUTHENTICATED: a caller holding no credential at all gets in.
  v_unauth := (
       'rpc_anon' = any(v_names)
    or ('http_deployed' = any(v_names)
        and not coalesce((v_vec->'http_verify_jwt'->>'present')::boolean, true)
        and not coalesce((v_vec->'in_function_auth'->>'present')::boolean, false)));

  -- UNEXPECTEDLY ACTIVE: something is executing it now, without anyone deciding to call it.
  v_unexpected := 'event_trigger' = any(v_names)
               or 'row_trigger'   = any(v_names)
               or 'cron_active'   = any(v_names)
               or 'compiled_into_view' = any(v_names);

  -- The recorded vocabulary is 'no' / 'unauthenticated_only' / 'yes'. A deployed HTTP surface is an
  -- external entry even when every caller must present a credential — 'yes' means "an outside
  -- caller can address this", not "an outside caller can do as they like".
  v_external := case
    when v_unauth then 'unauthenticated_only'
    when 'http_deployed' = any(v_names) or 'rpc_authenticated' = any(v_names) then 'yes'
    else 'no' end;

  -- ---- the classification the evidence supports, most consequential vector first ------------
  -- The 410 stub is tested first. Five of the six answer an anonymous caller and would otherwise be
  -- filed ACTIVE_PUBLIC_ENTRY on the strength of a verify_jwt setting, which would be the same
  -- mistake in the opposite direction: the deployment is reachable, the component is not.
  if v_retired_stub then
    v_class := 'INTENTIONALLY_RETIRED'; v_state := 'inactive';
    v_decided := 'retired_stub: ' || (v_vec->'retired_stub'->>'evidence')
              || ' — deployed and addressable, executes nothing';
  elsif 'event_trigger' = any(v_names) then
    v_class := 'ACTIVE_EVENT_TRIGGER'; v_state := 'active';
    v_decided := 'event_trigger: ' || (v_vec->'event_trigger'->>'evidence');
  elsif 'cron_active' = any(v_names) then
    v_class := 'ACTIVE_CRON'; v_state := 'active';
    v_decided := 'cron_active: ' || (v_vec->'cron_active'->>'evidence');
  elsif v_unauth then
    v_class := 'ACTIVE_PUBLIC_ENTRY'; v_state := 'active';
    v_decided := case when 'rpc_anon' = any(v_names)
                      then 'rpc_anon: ' || (v_vec->'rpc_anon'->>'evidence')
                      else 'http_deployed with verify_jwt=false and no in-function authorisation: '
                           || (v_vec->'in_function_auth'->>'evidence') end;
  elsif 'auth_hook' = any(v_names) then
    v_class := 'ACTIVE_AUTH_HOOK'; v_state := 'active';
    v_decided := 'auth_hook: ' || (v_vec->'auth_hook'->>'evidence');
  elsif 'webhook_caller' = any(v_names) then
    v_class := 'ACTIVE_WEBHOOK_ENTRY'; v_state := 'active';
    v_decided := 'webhook_caller: ' || (v_vec->'webhook_caller'->>'evidence');
  elsif 'frontend_caller' = any(v_names) then
    v_class := 'ACTIVE_FRONTEND_ENTRY'; v_state := 'active';
    v_decided := 'frontend_caller: ' || (v_vec->'frontend_caller'->>'evidence');
  elsif 'compiled_into_view' = any(v_names) or 'internal_caller' = any(v_names)
     or 'row_trigger' = any(v_names) or 'queue_consumer' = any(v_names) then
    v_class := 'ACTIVE_INTERNAL_CALLER'; v_state := 'active';
    v_decided := coalesce('compiled_into_view: '||(v_vec->'compiled_into_view'->>'evidence'),'')
              || case when 'internal_caller' = any(v_names) then ' | internal_caller: '||(v_vec->'internal_caller'->>'evidence') else '' end
              || case when 'row_trigger' = any(v_names) then ' | row_trigger: '||(v_vec->'row_trigger'->>'evidence') else '' end
              || case when 'queue_consumer' = any(v_names) then ' | queue_consumer: '||(v_vec->'queue_consumer'->>'evidence') else '' end;
  elsif 'script_caller' = any(v_names) then
    v_class := 'ACTIVE_SCRIPT_ENTRY'; v_state := 'active';
    v_decided := 'script_caller: ' || (v_vec->'script_caller'->>'evidence');
  elsif 'http_deployed' = any(v_names)
        and (coalesce((v_vec->'http_verify_jwt'->>'present')::boolean,false)
             or coalesce((v_vec->'in_function_auth'->>'present')::boolean,false)) then
    v_class := 'ACCESS_CONTROLLED_NO_CALLER'; v_state := 'deployed';
    v_decided := 'deployed and callable, but every caller must present a credential: '
              || coalesce((v_vec->'in_function_auth'->>'evidence'), (v_vec->'http_verify_jwt'->>'evidence'))
              || ' | no frontend, script, cron or webhook caller found';
  elsif 'rpc_authenticated' = any(v_names) then
    v_class := 'ACCESS_CONTROLLED_NO_CALLER'; v_state := 'deployed';
    v_decided := 'rpc_authenticated: ' || (v_vec->'rpc_authenticated'->>'evidence') || ' | anon cannot execute it';
  else
    -- No vector at all. This is the absence of a finding, not a finding: it says the derivation
    -- could not get in, never that the component was never built. A registered-but-switched-off
    -- cron job says so in its own words rather than being described as "no cron job".
    v_class := 'DEFERRED_RUNTIME_IMPLEMENTATION'; v_state := 'inactive';
    v_decided := 'no reachability vector: no grant to anon or authenticated, no internal caller, no '
              || 'row or event trigger, no active schedule, no view, no queue consumer, no webhook, '
              || 'no caller in src/** or scripts/**'
              || case when coalesce((v_vec->'cron_registered'->>'present')::boolean,false)
                      then ' | schedule is registered and SWITCHED OFF: '
                           || (v_vec->'cron_active'->>'evidence')
                      else '' end;
  end if;

  return jsonb_build_object(
    'component_id',              c.component_id,
    'component_type',            c.component_type,
    'object',                    c.source_path_or_db_object,
    'mutates_state',             c.mutates_state,
    'extension_owned',           false,
    'vectors',                   v_vec,
    'vectors_present',           to_jsonb(v_names),
    'reachable',                 v_reachable,
    'reachable_unauthenticated', v_unauth,
    'unexpectedly_active',       v_unexpected,
    'derived_classification',    v_class,
    'derived_activation_state',  v_state,
    'derived_external_entry',    v_external,
    'decided_by',                v_decided);
end
$k11_reach$;

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
create or replace function public.fn_kernel_component_exposure_state()
returns table (check_name text, expected text, actual text, ok boolean)
language sql
stable
security definer
set search_path to 'public', 'cron', 'pg_temp'
as $k11_state$
with pop as (
  select c.component_id, c.component_type, c.classification, c.activation_state,
         c.external_entry, c.mutates_state, r.d
    from public.phase_c_component_exposure_scope s
    join public.phase_c_component c using (component_id),
         lateral public.fn_kernel_component_reachability(c.component_id) r(d)
), qd as (   -- QuotesDone components only; extension internals are counted on their own line
  select * from pop where d->>'derived_classification' <> 'EXTENSION_OWNED_EXCLUDED'
)
select 'deferred_or_inactive_but_reachable'::text,
       '0 of ' || (select count(*) from qd)::text,
       (select count(*) from qd
         where classification in ('DEFERRED_RUNTIME_IMPLEMENTATION','INACTIVE_HISTORICAL',
                                  'INTENTIONALLY_INACTIVE','REPAIR_BEFORE_REACTIVATION')
           and (d->>'reachable')::boolean)::text
         || ' of ' || (select count(*) from qd)::text,
       (select count(*) from qd
         where classification in ('DEFERRED_RUNTIME_IMPLEMENTATION','INACTIVE_HISTORICAL',
                                  'INTENTIONALLY_INACTIVE','REPAIR_BEFORE_REACTIVATION')
           and (d->>'reachable')::boolean) = 0
union all
select 'deferred_or_inactive_but_unexpectedly_active'::text,
       '0 of ' || (select count(*) from qd)::text,
       (select count(*) from qd
         where activation_state = 'inactive' and (d->>'unexpectedly_active')::boolean)::text
         || ' of ' || (select count(*) from qd)::text,
       (select count(*) from qd
         where activation_state = 'inactive' and (d->>'unexpectedly_active')::boolean) = 0
union all
select 'state_changing_and_reachable_unauthenticated'::text,
       '0 of ' || (select count(*) from qd where mutates_state)::text
         || ' (except the recorded legal exception)',
       (select count(*) from qd
         where mutates_state and (d->>'reachable_unauthenticated')::boolean
           and component_id <> 'edge:pdpl_request')::text
         || ' of ' || (select count(*) from qd where mutates_state)::text
         || ' state-changing; edge:pdpl_request excluded — UAE PDPL Art. 13-17 require the '
         || 'data-subject request channel to be usable without an account',
       (select count(*) from qd
         where mutates_state and (d->>'reachable_unauthenticated')::boolean
           and component_id <> 'edge:pdpl_request') = 0
union all
select 'external_entry_disagrees_with_derivation'::text,
       '0 of ' || (select count(*) from qd)::text,
       (select count(*) from qd where external_entry is distinct from d->>'derived_external_entry')::text
         || ' of ' || (select count(*) from qd)::text
         || ' (recorded vocabulary no / unauthenticated_only / yes)',
       (select count(*) from qd where external_entry is distinct from d->>'derived_external_entry') = 0
union all
select 'extension_owned_excluded_from_the_headline'::text,
       'reported separately, never counted as deferred QuotesDone components',
       (select count(*) from pop where d->>'derived_classification' = 'EXTENSION_OWNED_EXCLUDED')::text
         || ' of ' || (select count(*) from pop)::text
         || ' extension internals excluded (pg_depend deptype ''e'')',
       true;
$k11_state$;

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
