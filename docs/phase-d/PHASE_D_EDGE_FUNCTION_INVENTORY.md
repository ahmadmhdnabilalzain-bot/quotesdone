# THE 202 DEPLOYED EDGE FUNCTIONS — PRECISE RECONCILIATION

**Session:** narrow Phase D / Phase C correction, 2026-08-27
**Production project:** `htdblwldjkcgjvmqkbeh`
**Command:** `node scripts/phase_d/build_edge_function_inventory.mjs`
**Machine-readable result:** [`PHASE_D_EDGE_FUNCTION_INVENTORY.csv`](PHASE_D_EDGE_FUNCTION_INVENTORY.csv)
— 202 rows, 34 columns, one row per deployed function.

---

## 1. The two heuristic numbers, replaced

The session brief carried a broad static scan: *"117 of 202 Edge Functions write at least one
trigger-protected table and 97 have no edge source row."* Both are now reconciled, and both were
measuring something other than what they said.

### 1.1 "117 write a trigger-protected table" → **0 write a kernel-guarded table**

"Trigger-protected" in that scan meant *any table carrying any trigger*, which is most of the
estate. The population that matters is the set of tables carrying `fn_kernel_write_guard`, read live
from `pg_trigger` rather than typed:

```
kernel_signal_inbox, kernel_trigger_inbox, phase_c_event_outbox, phase_c_founder_auth_event,
phase_c_handoff_run, phase_c_refund_decision, phase_c_task, phase_c_workflow_run,
phase_c_workflow_step_run, phase_d_capability_request, phase_d_capability_result,
phase_d_scenario_record, phase_d_test_context_grant                                   — 13 tables
```

**Not eight — thirteen.** The count of eight is in several documents in this repository and is
stale; four Phase D tables and one more Phase C table acquired the guard after it was written.

Across all 202 deployed functions, with comments stripped before matching, the number that perform a
`.from('<one of those 13>').insert|update|upsert|delete(` is **0**.

### 1.2 "97 have no edge source row" → **0 required source rows are missing**

That comparison asked for an `edge:<slug>` row in `public.kernel_trigger_source` for every function.
It measures the wrong subject. **A cron-driven edge function is not itself the source of the work —
the cron job is**, and the register keys those rows `cron:<jobid>`; there are 206 of them. Likewise a
trigger-driven function's source is the trigger, keyed `dbtrigger:<schema>.<table>:<trgname>`; there
are 237.

Asked in the shape the register is actually written in:

| source status | functions |
|---|---|
| `PRESENT_AS_EDGE_SOURCE` | 19 |
| `PRESENT_AS_CRON_SOURCE` | 35 |
| `PRESENT_AS_DB_TRIGGER_SOURCE` | 2 |
| `PRESENT_NOT_REQUIRED` (registered, class does not require it) | 6 |
| `NOT_REQUIRED` | 140 |
| **`MISSING`** | **0** |

**No `kernel_trigger_source` row was created by this session.** The 97 were an artefact of the
question, and the fix was to ask it correctly rather than to write 97 rows.

---

## 2. Classification of all 202

Deterministic; the first matching rule wins and the rule that matched is recorded per function in
`classification_basis`, so a reader can disagree with a specific sentence rather than with a verdict.

| class | n | how it is decided |
|---|---|---|
| `DERIVED_INTERNAL_MUTATION` | 53 | writes only its own derived/projection tables; no frontend, cron, edge, database or kernel caller found |
| `AUTONOMOUS_NEW_WORK_REQUEST` | 50 | calls a kernel new-work door, **or** is registered as an external source that creates work, **or** is driven by cron and reached from no user surface |
| `READ_ONLY` | 39 | no table write, no dynamic write and no rpc survive comment-stripping |
| `KERNEL_INTERNAL` | 20 | invoked by another edge function or by a non-trigger database routine |
| `SYNCHRONOUS_USER_APPLICATION_ENTRY` | 18 | reached from a file under `src/`, or registered as an external entry that answers rather than creating work |
| `MONITORING` | 6 | health/uptime/scan surface |
| `INTENTIONALLY_INACTIVE` | 6 | `phase_c_component.activation_state = 'inactive'` |
| `AUTH_OR_SESSION_SUPPORT` | 4 | authentication/session surface; its writes are its own identity tables |
| `PROVIDER_CALLBACK` | 4 | registered `webhook_provider_event`, or a provider-signature header / hook name is present |
| `EXISTING_WORKFLOW_SIGNAL` | 3 | signals a run that already exists, or is invoked by a registered database trigger |
| `RETIRED` | 0 | deployed with no source directory in the repository |
| `BLOCKED_DEFECT` | 0 | writes a kernel-guarded table with no caller and no kernel door |

**202 of 202 classified. 0 unclassified. 140 are state-changing.**

### Two rules that were wrong on the first pass, and how they were caught

* **`verify_jwt = false` is not a webhook.** Nearly every function on this project runs
  `verify_jwt = false` and does its own auth, so that flag alone classified **113 of 202** as
  provider callbacks. A classifier that calls half the estate a webhook is not measuring anything.
  The shipped rule requires a provider-signature header (`stripe-signature`, `x-hub-signature`,
  `X-Twilio-Signature`, `svix-*`, `x-signature-ed25519`, `hub.challenge`) or a hook name.
* **A function with no frontend and no cron caller is not therefore internal.** `dispatch_inquiry`
  was called `DERIVED_INTERNAL_MUTATION` until the database call graph was added: `public.inquiries`
  carries `autodispatch_inquiry`, whose function `net.http_post`s `/functions/v1/dispatch_inquiry`.
  Adding that channel moved 22 functions to their real class.

---

## 3. The ten named for manual inspection

| function | class | source | workflow / role / authority / trace | basis |
|---|---|---|---|---|
| `os_api` | SYNCHRONOUS_USER_APPLICATION_ENTRY | not required | W02 / corporate_performance_director / routine_operational_decision / TRACE-SYSTEM-EXECUTION | reached from `src/lib/osClient.ts` |
| `dispatch_inquiry` | EXISTING_WORKFLOW_SIGNAL | `dbtrigger:public.inquiries:autodispatch_inquiry` | W05 / rfq_qualification_manager / inquiry_quote_ready / TRACE-SYSTEM-EXECUTION | invoked by a registered database trigger |
| `agents` | KERNEL_INTERNAL | not required | W30 / agent_workforce_capability_director / routine_operational_decision / TRACE-SYSTEM-EXECUTION | invoked from database routine `run_agent` |
| `os_ops` | SYNCHRONOUS_USER_APPLICATION_ENTRY | not required | W02 / corporate_performance_director / routine_operational_decision / TRACE-SYSTEM-EXECUTION | reached from `src/lib/osClient.ts`; dynamic writes hand-reviewed below |
| `cos_execute` | AUTONOMOUS_NEW_WORK_REQUEST | `cron:124` (**inactive**) | W30 / agent_workforce_capability_director / routine_operational_decision / TRACE-SYSTEM-EXECUTION | cron-driven, no user surface |
| `kyc` | AUTH_OR_SESSION_SUPPORT | not required | W10 / supplier_verification / supplier_approval / TRACE-SYSTEM-EXECUTION | identity-verification surface |
| `login_otp` | SYNCHRONOUS_USER_APPLICATION_ENTRY | not required | W04 / customer_onboarding / routine_operational_decision / TRACE-SYSTEM-EXECUTION | reached from `src/components/osx/OsxShell.tsx` |
| `project_api` | SYNCHRONOUS_USER_APPLICATION_ENTRY | not required | W05 / rfq_qualification_manager / inquiry_quote_ready / TRACE-SYSTEM-EXECUTION | reached from `src/components/portal/spatial/api.ts` |
| `inquiry_intake` | AUTONOMOUS_NEW_WORK_REQUEST | `edge:inquiry_intake` | W05 / rfq_qualification_manager / inquiry_quote_ready / TRACE-SYSTEM-EXECUTION | registered `customer_event`, `recorded_creates_work = true`, CONNECTED_ACTIVE |
| `drawing_redact` | KERNEL_INTERNAL | not required | W08 / marketplace_content_privacy_reviewer / supplier_safe_approval / TRACE-SYSTEM-EXECUTION | invoked by `attach_photos` and `customer_api` |

---

## 4. Dynamic writes — declared manual review

A dynamic table name (`.from(tbl)`) defeats a static scan, so each is read by hand and the resolved
set is recorded with the date. **An entry is not an exemption**: the resolved tables are still
checked against the 13 kernel-guarded tables, and a function that acquires a dynamic write with no
entry is reported as `UNREVIEWED`.

The first pass reported six. Four — `agent_act`, `compliance_archive`, `dropbox_backup`, `vt_scan` —
were only ever calling `.storage.from(bucket)`, which is the Storage API and not a table. The
negative lookbehind is what makes the column mean *"a table this scan could not name"*.

| function | resolved tables | why the set is closed | any guarded? |
|---|---|---|---|
| `kb_embed` | `kb_chunks`, `company_faq` | `index.ts:78` `TARGETS` is a literal map of two entries; `:84` falls back to `kb_chunks` for any other value. Only `embedding_gte` is written. | no |
| `os_ops` | `inquiries`, `leads`, `crm_tasks`, `expenses`, `board_reports`, `exec_reports`, `finance_reports`, `agent_actions`, `security_events` | `index.ts:17` `EDITABLE` and `:24` `CONTENT` are literal maps; `field_set` (`:181`) refuses any entity or field absent from `EDITABLE`, and the content path refuses any key absent from `CONTENT`. | no |

**Dynamic writes unreviewed: 0. Reviewed dynamic writes reaching a kernel-guarded table: 0.**

---

## 5. Ownership and traceability of every state-changing path

For all **140** state-changing functions, `public.phase_c_component` carries a non-empty
`accountable_role_id`, `authority_class` and `trace_policy_id`, and a `workflow_id`.

**Functions with a business write and no workflow/step or justified scope: 0.**
**Functions with a business write and no accountable role, authority class or trace policy: 0.**

---

## 6. What was NOT measured, so no zero here is read as a fact

* **Runtime invocation history.** The per-function `runtime_evidence` column reads
  `public.os_audit_log` and the deployment's own `updated_at`. Supabase Log Explorer retains **24
  hours**, and a 24-hour window cannot answer *"has this ever run"*. Where a function has no audit
  row the record says `NEVER_OBSERVED in os_audit_log`, which is a statement about that table and not
  about the function's whole life.
* **Reachability of a branch.** Static text cannot distinguish a write in a branch no caller can
  enter from one on the happy path. Nothing here claims a branch is dead.
* **Dead code that compiles.** Comments are stripped before every pattern, so commented-out code is
  not counted as a live source. Unreachable-but-compiled code is not detected.
* **The deployed bundle.** Classification reads the **repository** source for each deployed slug.
  Repository↔production parity is a separate gate (`node scripts/verify_deploy_parity.mjs --all`).

---

## 7. Required outcomes

| required | result |
|---|---|
| deployed Edge Functions inventoried | **202 / 202** |
| active state-changing functions unclassified | **0** |
| active autonomous source bypassing the kernel | **0** — all 56 in the three work-creating/signalling classes carry a registered source (19 edge, 35 cron, 2 db-trigger) |
| active business write with no workflow/step or justified scope | **0** of 140 |
| direct write to a kernel-guarded table | **0** (13 guarded tables, read live) |
| active business DML outside a canonical domain service or source adapter | **0** |
| dead-code text counted as a live source | **0** — comments stripped before matching |
| dynamic write missed without a declared manual review | **0** — 2 of 2 reviewed, both bounded, neither guarded |
| held source reactivated | **0** — this session activated nothing; `cos_execute`'s `cron:124` is still inactive and is recorded as such |
