# K11 — component exposure: aborted-transaction rehearsal

Everything below was produced against **production** (`htdblwldjkcgjvmqkbeh`) inside a transaction
that ends in `raise exception`. Nothing was committed and nothing was deployed. The runner refuses a
payload that does not contain a `raise exception`, so there is no path in which this rehearsal
writes.

```sql
begin;
  create temp table k11_before on commit drop as
  select component_id, component_type, classification, activation_state, external_entry, mutates_state
    from public.phase_c_component
   where activation_state = 'inactive' or classification = 'DEFERRED_RUNTIME_IMPLEMENTATION';

  -- scripts/sql/kernel_k11_component_exposure.sql, with its own begin/commit stripped

  create temp table k11_after on commit drop as
  select s.component_id, r.j
    from public.phase_c_component_exposure_scope s,
         lateral public.fn_kernel_component_reachability(s.component_id) r(j);

  -- probe block, ends in raise exception
rollback;
```

Wall time for the whole payload: **21 s**.

## What four failed rehearsals cost, and what they caught

The migration did not apply cleanly first time. Each failure was a real defect in this file rather
than an environment problem, and three of the four are the same class of mistake the increment
itself is about, committed by me while writing the fix for it.

1. **`v_names := v_names || 'cron_active'`** — `text[] || unknown` is parsed as array-to-array.
   `ERROR 22P02: malformed array literal: "cron_active"`. Fixed with an explicit `::text` on all
   fourteen appends.

2. **The invariant's denominator was its own subject.** The population was defined as
   `activation_state = 'inactive' or classification = 'DEFERRED_RUNTIME_IMPLEMENTATION'`, so
   reclassifying 48 rows moved them *out* of it and every check went green over a denominator that
   had silently fallen from 149 to 101. A check that can be satisfied by relabelling is precisely
   the defect K11 exists to remove. Fixed by freezing the population into
   `phase_c_component_exposure_scope` before any write; the denominators below are 149 and 240 and
   cannot shrink.

3. **The reclassification called eighteen retired cron jobs "not built yet".** When the derivation
   finds no vector it returns `DEFERRED_RUNTIME_IMPLEMENTATION`, and the first draft wrote that over
   `INACTIVE_HISTORICAL` — including `cron:site_autodeploy`, which completed 21,563 runs before it
   was switched off. The absence of a finding is not a finding. Fixed: an empty derivation never
   overwrites a more specific inactive label, and the evidence string for a registered-but-disabled
   schedule now says so in its own words instead of "no cron job".

4. **Seven access-controlled edge functions were being filed as unreachable**, because `reachable`
   required an *un*authenticated path. A deployed endpoint that answers a signed-in customer is
   reachable; "access-controlled" describes how it is reached, not whether. Fixed, and the buckets
   moved from 103 / 25 / 21 to 96 / 32 / 21.

A fifth, smaller one: `RAISE` has no `%L`, so the guard printed
`classification DEFERRED_RUNTIME_IMPLEMENTATIONL`. The sibling
`fn_phase_c_event_binding_status_guard` has the identical bug and prints `CONNECTEDL`; it is left
alone here because Phase B is frozen.

**Performance.** The first complete payload timed out at the Cloudflare 524 limit. The derivation
was running `pg_get_viewdef` over 181 views and a `prosrc` regex over 1,219 routines on every call,
roughly 700 times. Replacing the view scan with `pg_depend` on the view's rewrite rule — exact and
index-driven, where the regex was neither — prefiltering the `prosrc` regex with `strpos`, and
materialising the derivation once into a temp table brought it to 21 s.

## Verbatim output

```
Failed to run sql query: ERROR:  P0001: K11 REHEARSAL (aborted)
=== BEFORE (as the registry recorded it) ===
  DEFERRED_RUNTIME_IMPLEMENTATION  inactive  221
  INACTIVE_HISTORICAL              inactive  18
  REPAIR_BEFORE_REACTIVATION       inactive  1
  extension-owned inside that population: 91 (excluded)
  QuotesDone population: 149
  ...of which the derivation can REACH: 48
  ...of which are UNEXPECTEDLY ACTIVE: 4
  ...whose recorded external_entry was WRONG: 24
  ...state-changing AND unauthenticated-reachable: 1

=== AFTER (derived) ===
  DEFERRED_RUNTIME_IMPLEMENTATION  inactive  168
  ACTIVE_SCRIPT_ENTRY              active    21
  INACTIVE_HISTORICAL              inactive  17
  ACTIVE_PUBLIC_ENTRY              active    16
  ACCESS_CONTROLLED_NO_CALLER      deployed  7
  INTENTIONALLY_RETIRED            inactive  6
  ACTIVE_INTERNAL_CALLER           active    1
  ACTIVE_CRON                      active    1
  REPAIR_BEFORE_REACTIVATION       inactive  1
  ACTIVE_EVENT_TRIGGER             active    1
  ACTIVE_AUTH_HOOK                 active    1

=== fn_kernel_component_exposure_state() ===
  [PASS] deferred_or_inactive_but_reachable
    expected: 0 of 149
    actual:   0 of 149
  [PASS] deferred_or_inactive_but_unexpectedly_active
    expected: 0 of 149
    actual:   0 of 149
  [PASS] state_changing_and_reachable_unauthenticated
    expected: 0 of 79 (except the recorded legal exception)
    actual:   0 of 79 state-changing; edge:pdpl_request excluded — UAE PDPL Art. 13-17 require the data-subject request channel to be usable without an account
  [PASS] external_entry_disagrees_with_derivation
    expected: 0 of 149
    actual:   0 of 149 (recorded vocabulary no / unauthenticated_only / yes)
  [PASS] extension_owned_excluded_from_the_headline
    expected: reported separately, never counted as deferred QuotesDone components
    actual:   91 of 240 extension internals excluded (pg_depend deptype 'e')

=== BUCKETS (QuotesDone components only) ===
  1 unreachable / safely deferred    96
  2 callable but access-controlled   32
  3 publicly reachable               21
```

The four "before" numbers are the honest measurement of the audit's claims:

| audit said | measured |
|---|---|
| 221 deferred components | 240 in the inactive/deferred population, of which **91 are pgvector and pg_trgm internals**; the QuotesDone population is **149** |
| 106 of 206 db functions grant EXECUTE to anon | true, and **91 of those 106 are the extension internals**; QuotesDone's own count is **15**, none of which mutates state |
| fn_enforce_rls_on_new_tables is a live event trigger | confirmed, and it is one of **4** unexpectedly-active components, not one |
| 12 edge functions "deployed and unreachable" while reachable without a JWT | 12 have `verify_jwt = false`; **5 are 410 stubs, 5 authenticate in-function, 1 requires a shared token, and exactly 1 — pdpl_request — has no authentication at all** |
| 6 of the 12 mutate state and are reachable unauthenticated | **1**: `state_changing AND unauthenticated-reachable = 1`, and that one is pdpl_request |
| external_entry says "no" on all 206 | **24** of the 149 recorded answers were wrong, in both directions |
| the sweep did not cover scripts/** | confirmed: 3 checked-in scripts POST to `kb_corpus_import`, and **25** more database functions have a real script invoker |

### What moved, and why

```
=== WHAT MOVED, and why ===
  dbfn:hook_password_verification_attempt(event jsonb)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_AUTH_HOOK/active
      K11 2026-08-16: auth_hook: explicit GRANT EXECUTE to supabase_auth_admin in proacl (not inherited through PUBLIC) — the GoTrue auth service can call t
  cron:autonomy_dispose_hourly  INACTIVE_HISTORICAL -> ACTIVE_CRON/active
      K11 2026-08-16: cron_active: cron.job 64 'autonomy_dispose_hourly' schedule '45 * * * *' active=t; 372 runs, last 2026-08-16 20:45:00.319576+00
  dbfn:fn_enforce_rls_on_new_tables()  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_EVENT_TRIGGER/active
      K11 2026-08-16: event_trigger: pg_event_trigger, ENABLED: trg_enforce_rls_new_tables on ddl_command_end (evtenabled=O)
  dbfn:fn_archetype_tier(p_archetype text)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_INTERNAL_CALLER/active
      K11 2026-08-16: compiled_into_view: runs on every SELECT of: public.v_role_identity_collision (view)
  dbfn:canary_scan(haystack text)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_PUBLIC_ENTRY/active
      K11 2026-08-16: rpc_anon: has_function_privilege('anon', canary_scan(text), 'EXECUTE') = t; proacl = {=X/postgres,postgres=X/postgres,anon=X/postgres,
  dbfn:fn_gl_net_income()  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_PUBLIC_ENTRY/active
      K11 2026-08-16: rpc_anon: has_function_privilege('anon', fn_gl_net_income(), 'EXECUTE') = t; proacl = {=X/postgres,postgres=X/postgres,anon=X/postgres
  dbfn:fn_jsonb_text_array(j jsonb)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_PUBLIC_ENTRY/active
      K11 2026-08-16: rpc_anon: has_function_privilege('anon', fn_jsonb_text_array(jsonb), 'EXECUTE') = t; proacl = {=X/postgres,postgres=X/postgres,service
  dbfn:fn_kb_next_question(p_catalog_num integer, p_answered jsonb)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_PUBLIC_ENTRY/active
      K11 2026-08-16: rpc_anon: has_function_privilege('anon', fn_kb_next_question(integer,jsonb), 'EXECUTE') = t; proacl = {=X/postgres,postgres=X/postgres
  dbfn:fn_norm_roles(p_text text)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_PUBLIC_ENTRY/active
      K11 2026-08-16: rpc_anon: has_function_privilege('anon', fn_norm_roles(text), 'EXECUTE') = t; proacl = {=X/postgres,postgres=X/postgres,service_role=X
  dbfn:fn_os_portals_gates()  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_PUBLIC_ENTRY/active
      K11 2026-08-16: rpc_anon: has_function_privilege('anon', fn_os_portals_gates(), 'EXECUTE') = t; proacl = {=X/postgres,postgres=X/postgres,service_role
  dbfn:fn_os_selftest()  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_PUBLIC_ENTRY/active
      K11 2026-08-16: rpc_anon: has_function_privilege('anon', fn_os_selftest(), 'EXECUTE') = t; proacl = {=X/postgres,postgres=X/postgres,service_role=X/po
  dbfn:fn_phase_b_closure_blockers(p_workflow_id text, p_completed_steps text[], p_open_blockers bigint, p_open_handoffs bigint)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_PUBLIC_ENTRY/active
      K11 2026-08-16: rpc_anon: has_function_privilege('anon', fn_phase_b_closure_blockers(text,text[],bigint,bigint), 'EXECUTE') = t; proacl = {=X/postgres
  dbfn:fn_phase_b_invariants()  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_PUBLIC_ENTRY/active
      K11 2026-08-16: rpc_anon: has_function_privilege('anon', fn_phase_b_invariants(), 'EXECUTE') = t; proacl = {=X/postgres,postgres=X/postgres,service_ro
  dbfn:fn_phase_b_step_transition_allowed(p_from text, p_to text)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_PUBLIC_ENTRY/active
      K11 2026-08-16: rpc_anon: has_function_privilege('anon', fn_phase_b_step_transition_allowed(text,text), 'EXECUTE') = t; proacl = {=X/postgres,postgres
  dbfn:fn_phase_b_transition_allowed(p_from text, p_to text)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_PUBLIC_ENTRY/active
      K11 2026-08-16: rpc_anon: has_function_privilege('anon', fn_phase_b_transition_allowed(text,text), 'EXECUTE') = t; proacl = {=X/postgres,postgres=X/po
  dbfn:fn_rating_due(p_now timestamp with time zone)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_PUBLIC_ENTRY/active
      K11 2026-08-16: rpc_anon: has_function_privilege('anon', fn_rating_due(timestamp with time zone), 'EXECUTE') = t; proacl = {=X/postgres,postgres=X/pos
  dbfn:fn_secops_test(sample text)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_PUBLIC_ENTRY/active
      K11 2026-08-16: rpc_anon: has_function_privilege('anon', fn_secops_test(text), 'EXECUTE') = t; proacl = {=X/postgres,postgres=X/postgres,service_role=
  dbfn:fn_supplier_quality(p_lead_id bigint)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_PUBLIC_ENTRY/active
      K11 2026-08-16: rpc_anon: has_function_privilege('anon', fn_supplier_quality(bigint), 'EXECUTE') = t; proacl = {=X/postgres,postgres=X/postgres,servic
  dbfn:playbook_for(p_category text)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_PUBLIC_ENTRY/active
      K11 2026-08-16: rpc_anon: has_function_privilege('anon', playbook_for(text), 'EXECUTE') = t; proacl = {=X/postgres,postgres=X/postgres,service_role=X/
  edge:pdpl_request  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_PUBLIC_ENTRY/active
      K11 2026-08-16: http_deployed with verify_jwt=false and no in-function authorisation: Deployed source read back from the platform (sha dbc4fd31): 27 l
  dbfn:fn_agent_autonomy_blocked(p_agent_key text)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_SCRIPT_ENTRY/active
      K11 2026-08-16: script_caller: scripts/** invokes it: scripts/checks/runtime_connection_gate_a.mjs:188 select ... public.fn_agent_autonomy_blocked(k)
  dbfn:fn_agent_tool_allowed(p_agent_key text, p_tool_id text)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_SCRIPT_ENTRY/active
      K11 2026-08-16: script_caller: scripts/** invokes it: scripts/checks/runtime_connection_gate_b.mjs and scripts/checks/v3_remediation_regression.mjs
  dbfn:fn_blueprint_regressions(p_spec text, p_ref text)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_SCRIPT_ENTRY/active
      K11 2026-08-16: script_caller: scripts/** invokes it: scripts/staging/blueprint_history.mjs
  dbfn:fn_category_quote_ready(p_category text, p_spec jsonb, p_label text)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_SCRIPT_ENTRY/active
      K11 2026-08-16: script_caller: scripts/** invokes it: scripts/checks/v3_runtime_behaviour.test.mjs
  dbfn:fn_category_specialist_scorecard(p_days integer)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_SCRIPT_ENTRY/active
      K11 2026-08-16: script_caller: scripts/** invokes it: scripts/checks/org_reorg_behaviour.test.mjs
  dbfn:fn_decide(p_kind text, p_ctx jsonb, p_actor text)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_SCRIPT_ENTRY/active
      K11 2026-08-16: script_caller: scripts/** invokes it: scripts/staging/gate_decision_chain.mjs
  dbfn:fn_objective_cascade()  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_SCRIPT_ENTRY/active
      K11 2026-08-16: script_caller: scripts/** invokes it: scripts/agents/export_org_docs.mjs and scripts/checks/org_reorg_behaviour.test.mjs
  dbfn:fn_onboarding_gate(p_agent text)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_SCRIPT_ENTRY/active
      K11 2026-08-16: script_caller: scripts/** invokes it: scripts/checks/runtime_connection_gate_a.mjs:189 select ... public.fn_onboarding_gate(k)
  dbfn:fn_open_remediation(p_agent_key text, p_failure_class text, p_competency text, p_detail jsonb)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_SCRIPT_ENTRY/active
      K11 2026-08-16: script_caller: scripts/** invokes it: scripts/checks/v3_runtime_behaviour.test.mjs
  dbfn:fn_overlay_for_category(p_category_key text)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_SCRIPT_ENTRY/active
      K11 2026-08-16: script_caller: scripts/** invokes it: scripts/agents/export_org_docs.mjs and scripts/checks/org_reorg_behaviour.test.mjs
  dbfn:fn_propose_lesson(p_agent_key text, p_topic text, p_statement text, p_evidence jsonb, p_confidence numeric, p_valid_until date)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_SCRIPT_ENTRY/active
      K11 2026-08-16: script_caller: scripts/** invokes it: scripts/checks/v3_runtime_behaviour.test.mjs
  dbfn:fn_refund_decide(p_refund_id bigint, p_approve boolean, p_decided_by text, p_note text)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_SCRIPT_ENTRY/active
      K11 2026-08-16: script_caller: scripts/** invokes it: scripts/rehearsal/hvac_dress_rehearsal.mjs:455 select (public.fn_refund_decide(...))::text
  dbfn:fn_reliability_report(p_days integer)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_SCRIPT_ENTRY/active
      K11 2026-08-16: script_caller: scripts/** invokes it: scripts/checks/v3_remediation_regression.mjs
  dbfn:fn_retrieval_leak_check(p_agent_key text, p_task_text text)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_SCRIPT_ENTRY/active
      K11 2026-08-16: script_caller: scripts/** invokes it: scripts/checks/v3_remediation_regression.mjs
  dbfn:fn_retrieval_probe(p_agent_key text, p_task_text text, p_category_key text)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_SCRIPT_ENTRY/active
      K11 2026-08-16: script_caller: scripts/** invokes it: scripts/checks/v3_remediation_regression.mjs
  dbfn:fn_role_isolation_status()  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_SCRIPT_ENTRY/active
      K11 2026-08-16: script_caller: scripts/** invokes it: scripts/checks/v3_remediation_regression.mjs
  dbfn:fn_specialist_invoke(p_manager text, p_specialist text, p_subject_type text, p_subject_id text, p_reason text)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_SCRIPT_ENTRY/active
      K11 2026-08-16: script_caller: scripts/** invokes it: scripts/checks/org_reorg_behaviour.test.mjs
  dbfn:fn_trace_edit_is_blocked(p_id uuid)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_SCRIPT_ENTRY/active
      K11 2026-08-16: script_caller: scripts/** invokes it: scripts/checks/v3_remediation_regression.mjs
  dbfn:fn_unsafe_guard_status()  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_SCRIPT_ENTRY/active
      K11 2026-08-16: script_caller: scripts/** invokes it: scripts/checks/v3_remediation_regression.mjs
  dbfn:fn_validate_lesson(p_lesson_id bigint, p_validator text, p_verdict text, p_reason text)  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_SCRIPT_ENTRY/active
      K11 2026-08-16: script_caller: scripts/** invokes it: scripts/checks/v3_runtime_behaviour.test.mjs
  edge:kb_corpus_import  DEFERRED_RUNTIME_IMPLEMENTATION -> ACTIVE_SCRIPT_ENTRY/active
      K11 2026-08-16: script_caller: scripts/pull_asset.js:11, scripts/pull_kb_import_assets.js:14 and scripts/sync_migrations_from_prod.js:15 each POST htt
```

Not in that list, because they did not become `ACTIVE_*`: the six 410 stubs
(`brand_upload`, `kb_retrieve`, `licence_reminder`, `orchestrate`, `support_ai`, `voice_otp`) moved
to `INTENTIONALLY_RETIRED`, and the seven JWT-gated edge functions (`attach_photos`,
`inquiry_dedup_check`, `qa_api`, `quote_quality`, `rate_dims`, `refund_flow`, `sup_dob`) moved to
`ACCESS_CONTROLLED_NO_CALLER / deployed`.

### The guard

```
=== GUARD ===
  refused relabel of fn_enforce_rls_on_new_tables -> DEFERRED (23514)
    phase_c_component dbfn:fn_enforce_rls_on_new_tables(): classification "DEFERRED_RUNTIME_IMPLEMENTATION" says this component has no way in, and it has one. The derivation reaches it via event_trigger: pg_event_trigger, ENABLED: trg_enforce_rls_new_tables on ddl
  refused relabel of cron:autonomy_dispose_hourly -> INACTIVE_HISTORICAL (23514)
    phase_c_component cron:autonomy_dispose_hourly: classification "INACTIVE_HISTORICAL" says this component has no way in, and it has one. The derivation reaches it via cron_active: cron.job 64 'autonomy_dispose_hourly' schedule '45 * * * *' active=t; 372 runs, l
  refused invented ACTIVE_PUBLIC_ENTRY on fn_ai_gate (23514)
    phase_c_component dbfn:fn_ai_gate(p_answer text, p_sources jsonb, p_confidence numeric, p_action text, p_actor text, p_attrs jsonb): classification "ACTIVE_PUBLIC_ENTRY" claims a live entry point and the derivation finds none — no reachability vector: no grant
  accepted the TRUE label on fn_ai_gate (guard does not block honest writes)
```

The fourth line matters as much as the first three. The guard refuses a label the evidence does not
support, in both directions, and accepts one it does. A guard that refused everything would be a
freeze, not a check.

The 48 rows the migration itself rewrites are written **through** this guard — the trigger is created
before the `UPDATE`, and the `UPDATE` takes its values from `fn_kernel_component_reachability`. If
any assignment in this file disagreed with the evidence, the migration would not apply.

## Rollback rehearsal

Same runner, payload `k11_pre.sql + kernel_k11_component_exposure.sql + rollback + probe`:

```
Failed to run sql query: ERROR:  P0001: K11 ROLLBACK REHEARSAL (aborted)
  functions remaining after rollback: 0 (expected 0)
  guard triggers remaining: 0 (expected 0)
  probe rows kept (evidence): 86
  frozen scope rows kept: 240
  fn_enforce_rls_on_new_tables still recorded ACTIVE_EVENT_TRIGGER: 1
```

The last line is deliberate. The rollback removes the machinery and keeps the measurements: putting
`DEFERRED_RUNTIME_IMPLEMENTATION / inactive` back onto a trigger that fires on every DDL statement
would restore the false statement, and the trigger would go on firing either way. The reasoning is
in the header of `scripts/sql/rollback/kernel_k11_component_exposure.rollback.sql`, and
`phase_c_component_exposure_scope.frozen_as` holds every original value if a later migration wants
to argue with a specific one.

## What a reader can re-run without any of this

```sql
select * from public.fn_kernel_component_exposure_state();
select jsonb_pretty(public.fn_kernel_component_reachability('dbfn:fn_enforce_rls_on_new_tables()'));
select jsonb_pretty(public.fn_kernel_component_reachability('edge:pdpl_request'));
select jsonb_pretty(public.fn_kernel_component_reachability('cron:autonomy_dispose_hourly'));
```

`docs/phase-c-kernel/K11_COMPONENT_EXPOSURE.csv` is 240 rows — one per component in the frozen
scope — with every vector as its own column, the before and after labels, the derived status, the
bucket, and the evidence. It was generated from the same derivation inside the same aborted
transaction, not written by hand.

## The unauthenticated probe

One HTTP call was made, to establish that `pdpl_request` has no authentication rather than inferring
it from `verify_jwt`. It uses a deliberately invalid body, so it cannot write:

```
$ curl -i -X POST -H 'Content-Type: application/json' \
    -d '{"kind":"__invalid_probe__"}' \
    https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/pdpl_request
HTTP/1.1 400 Bad Request
{"error":"kind must be export or delete"}
```

400 from the function body, with no `Authorization` header — not 401 from a gate. The 400 is raised
before the `pdpl_requests` insert and before `alert_founder`, so nothing was created and no alert
fired. No other endpoint was called, and no inference endpoint was touched by anything in this
increment.

## What is still open

* **`pdpl_request` abuse capacity.** Recorded as a named Phase D item in `repair_or_keep_action`,
  deliberately not fixed here. The endpoint must stay public (UAE PDPL Art. 13-17); its only limit
  is 3 requests per **email** per rolling day (`index.ts:16-17`) and an anonymous caller varies the
  email freely, so it is an unbounded writer to `pdpl_requests` and an unbounded trigger of
  `alert_founder` (one `level=action` alert per accepted request). Rate-limiting a legally-required
  endpoint is a behaviour change and belongs in its own increment.
* **`hook_password_verification_attempt` is classified `ACTIVE_AUTH_HOOK`** on the strength of an
  explicit `GRANT EXECUTE` to `supabase_auth_admin` — the measurable vector, and the only grantee
  besides `postgres` and `service_role`. Whether GoTrue is configured to call it is platform auth
  config and is **not readable from SQL**. `security_events` holds 0 rows with
  `kind='login_failed', source='password'`, which cannot distinguish "hook not enabled" from "no
  password login has ever failed" on a project whose founder auth is OTP. Confirm the hook in the
  auth config or revoke the grant — Phase D.
* **13 of the fifteen anon-executable functions hold EXECUTE through PUBLIC**, not through a grant
  to `anon`: `fn_jsonb_text_array`, `fn_kb_next_question`, `fn_norm_roles`, `fn_os_portals_gates`,
  `fn_os_selftest`, `fn_phase_b_closure_blockers`, `fn_phase_b_invariants`,
  `fn_phase_b_step_transition_allowed`, `fn_phase_b_transition_allowed`, `fn_rating_due`,
  `fn_secops_test`, `fn_supplier_quality`, `playbook_for`. Only `canary_scan` and
  `fn_gl_net_income` carry an explicit `anon=X` grant. K11 records this and revokes nothing; a
  future `revoke execute ... from anon` on the thirteen would be a silent no-op, because the
  revoke has to name PUBLIC.
* **The 91 extension internals keep `DEFERRED_RUNTIME_IMPLEMENTATION`** as a classification, with
  their `gap` column now stating that they are not QuotesDone components. The invariant excludes
  them by `pg_depend`, so no future headline counts them again; inventing an activation state for
  objects the project does not own would be its own dishonesty.
* **`fn_archetype_tier` and `fn_jsonb_text_array` are now `ACTIVE_INTERNAL_CALLER` / anon**, but
  neither view (`v_role_identity_collision`, `inquiries_supplier_safe`) grants SELECT to `anon` or
  `authenticated` — only `postgres` and `service_role`. The functions run on every SELECT of those
  views; the views are not themselves an external surface. Both facts are in the CSV.
