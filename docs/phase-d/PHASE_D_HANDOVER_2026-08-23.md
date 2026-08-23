# Phase D — hand-over, 23 Aug 2026

Every figure below was measured by execution on `htdblwldjkcgjvmqkbeh` in the session that wrote
this file, and every one is reproducible by the command named beside it. **Phase D is not ready for
independent audit.** What is closed and what is open are both listed exactly.

---

## Closed this session

| section | result | command |
|---|---|---|
| §1 step coverage | **257 of 257** frozen steps reached through the canonical path | `node scripts/phase_d/build_step_branch_coverage.mjs` |
| §1 branch coverage | **257 of 257** pass edges and **257 of 257** fail edges exercised; **257 of 257** fail edges reach the step's own declared `failure_workflow_state`; fail edges produced 0 effects and 0 objects | same |
| §1 direct completion | **0** steps reached only by a direct `fn_kernel_step_complete` call | same |
| §2 failure path | **30 of 30** (was 11) | `node scripts/phase_d/build_four_mode_result.mjs` |
| §2 cancellation | **30 of 30** reached `cancelled` (was 21) | same |
| §3 handler effects | **254 of 257** steps produce their declared effect (was 144 in the brief, 249 when this session started) | `build_step_branch_coverage.mjs` |
| §4 notification | decided; both kernel boards unchanged; 56/56 objects have a proved creation path | `docs/phase-d/PHASE_D_NOTIFICATION_OBJECT_DECISION.md` |
| §7 classification | **200 of 200** Phase D migrations classified, **0** missing down scripts | `node scripts/phase_d/build_migration_rollback_classification.mjs` |
| §9C replay | duplicate effects 0/30, result reference moved 0/30, duplicate objects 0/30 | `build_four_mode_result.mjs` |
| residue | customers, inquiries, quotes, transactions, object records, dispatches, effects, scenario records, fixture contexts, capability requests/results, outbound HTTP, fixture residue — **all 0** | same |
| cost | `ai_cost_log` rows in the last 8 hours **0**, AED **0**; `llm_attempt` unchanged at 69 | see below |

**On the 254 held fail edges.** 254 of the 257 fail edges were reached with the deterministic
handler held open by `app.phase_d_hold_step` (J03), and 3 because the handler declined of its own
accord. The row says which. A held row proves the **kernel's** fail edge for that step; it does not
claim the handler could have failed. Those are different claims and they are in different columns.

---

## Open, with the exact measurement

### 1. Three steps do not produce their declared effect

| step | refusal | measured cause |
|---|---|---|
| `W05-S07` | `pd_evidence_absent` | GATE-005 (Founder boundary) requires `founder_authority_ref` and the step context resolves none. `fn_phase_d_step_context` answers that key from `founder_command_workflow_link` or `phase_c_workflow_run.command_id`; for this run neither holds one. Decide whether the gate is right to refuse (in which case this is a recorded exemption, not a gap) or whether the run should carry a founder authority. |
| `W12-S06` | `pd_object_write_produced_nothing` | `public.inquiry_matches` carries `BEFORE INSERT` trigger `gate_incomplete_match`, whose body is `select rfq_ready into ready from public.inquiries where id = NEW.inquiry_id; if ready is not true then return null;` — a **silent skip**. The fixture inquiry is not `rfq_ready`, deliberately: the fixture board `inquiry_writer_maps_a_derived_column` requires the inquiry write map NOT to map `rfq_ready`, because the product derives it in `trg_rfq_complete`. The fixture inquiry has to satisfy `trg_rfq_complete` on its own content. This is fixture content, which is what the committed catalogue is for. |
| `W16-S05` | `pd_effect_identity_collision` | `duplicate key value violates unique constraint "reveal_invoices_pkey"`. `public.reveal_invoices` has PRIMARY KEY **(transaction_id)** while `phase_d_object_write_map` for `invoice_receipt` names `key_column = invoice_no`. The scenario already creates an `invoice_receipt` for that transaction, so the step inserts a second `invoice_no` against the same `transaction_id`. The natural-key probe in `fn_phase_d_object_write` enumerates unique indexes and should find the PK — measure whether `v_supplied` carries `transaction_id` at that point before changing anything. |

### 2. PCCR-004 awaits the founder

`fn_kernel_cancel` refuses a workflow-run cancellation on the state model of a command nobody
named, and sweeps sibling runs' derived work. Measured, reproduced, written up in
`docs/phase-d/PCCR_004_CANCELLATION_SERVICE.md`, and **reverted**, because
`canonical_cancellation_service` is a frozen Phase C subject. The harness coupling that made the
four-mode need it is fixed separately. One sentence of written approval unblocks it.

### 3. Injected defects: 38 NOT_RUN, 2 NOT_DISCRIMINATED

Unchanged from the brief. The two NOT_DISCRIMINATED cases were read this session and both have a
specific, measured cause:

* **PD-AUTH-002** (`P2-document-scope`) — `supplier_portal`'s documents handler accepts **no owner
  id at all**; it reads only `sup.id`, resolved from `claimed_by` on the JWT. An identical body is
  the only answer the endpoint can give whoever is named, so IDENTICAL cannot separate a refusal
  from a discarded parameter. Both §8 fixtures also held **zero documents**. To discriminate,
  supplier A needs a document and supplier B a different one, then a cross-tenant call returning
  A's body proves the id is discarded.
* **PD-PRIV-004** (`P3-supplier-surface-body`) — the scan had nothing to find: `public.inquiries`
  0 rows, `public.customers` 0 rows, `public.inquiry_matches` 0 rows, so the 200 is an empty list
  and not a masked payload. Discriminating it requires **creating an inquiry**, and the automation
  hold forbids that. This one cannot be closed while the hold stands; it is a recorded exemption,
  not an engineering gap.

The 38 NOT_RUN each already name a specific blocker in
`docs/phase-d/PHASE_D_INJECTED_DEFECT_RESULT.csv`, and
`scripts/checks/phase_d_documents_do_not_contradict_each_other.test.mjs` asserts none is a
placeholder. They cluster into: nine that need §8 HTTP paths the harness does not reach, a family
that needs a **committed** run (sealing happens at commit and every Phase D transaction aborts), one
that needs two concurrent sessions, and three whose subject is a frozen Phase B property.

### 4. D6–D12

`PHASE_D_EXTERNAL_EFFECTS_RESULT.md`, `PHASE_D_FINANCIAL_PRIVACY_RESULT.md`,
`PHASE_D_IDEMPOTENCY_CONCURRENCY_RESULT.md`, `PHASE_D_STORAGE_RLS_SECURITY_RESULT.md`,
`PHASE_D_CAPABILITY_BOUNDARY_RESULT.csv` and `PHASE_D_SECTION_8_PROBE_CLOSURE.md` are committed and
current, and the deliverable check reproduces every regenerable one from production. **D11 is not
complete** — see §3 above — and D12's 347-event reconciliation is re-proved by the committed
`PHASE_D_HANDOFF_EVENT_RESULT.csv`, which the deliverable check regenerated from production this
session, not by observation of a live emission.

---

## Standing facts a next session should not re-derive

* The frozen model is a **linear chain**: `next_step_if_pass` names the next step for 227 steps and
  `WORKFLOW_COMPLETE` for the 30 closure steps; `next_step_if_fail` names
  `WORKFLOW_BLOCKED_OR_ESCALATED` (146), `CORRECTION_OR_REJECTION_PATH` (82) or `WORKFLOW_BLOCKED`
  (29) and **never a step**. No step is reachable only through a fail edge.
* The kernel dispatches at step **OPENING**, so a handler that can execute closes its step before
  any caller is consulted. `max_steps` cannot leave a step open. Use
  `hold_at_first_open_step` / `hold_at_step_id`.
* A run with no open step run is often **waiting for a handoff to be accepted**, not stopped.
* `cron.job` 35 (`uptime_check_15min`) and 88 (`dropbox_backup_scan`) run `*/15 * * * *` and enqueue
  into `net.http_request_queue` while a Phase D transaction is open. Requests are attributed by
  `xmin` now; do not read a bare queue delta as the write's own.
* The management endpoint cuts an exception message at **2000 characters**. Any probe that emits a
  row per subject must chunk and must guard, or it reports a truncated payload as a short answer.
