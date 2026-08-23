# Phase D — closing session, 24 Aug 2026

Every figure below was measured by execution on `htdblwldjkcgjvmqkbeh` in the session that wrote
this file, and every one names the command that reproduces it. Where a figure is bounded, the bound
is stated next to it rather than left to be discovered.

---

## 0. Source and baseline

| | |
|---|---|
| branch | `phase-d-closing-committed-scenario` |
| pull request | [#463](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/463) |
| base | `main @ a9ed8f3` (PRs #461 and #462 merged) |
| applied production-direct | L01–L04, M01–M09, each `node scripts/apply_sql.mjs <file> --apply --ddl`, each read back and identical to the file |
| Supabase project | `htdblwldjkcgjvmqkbeh`, the only one |

---

## 1. What the previous hand-over said, and what was actually true

The 23 Aug hand-over recorded **248 of 257** for the stricter harness — the fixture withholding the
object the workflow under test produces on all 30 workflows rather than on W12 alone — with all nine
of the fallen steps in W09, and gave the cause as:

> The rule's subject is not derivable from any register the estate holds today.

Re-measured. That is **one of four causes, and it is the least of them**. The other three were
defects in the product that the harness's own fixture had been answering for. Driving W09 with the
withhold on and reading the refusal:

```
BR-025: acceptance names version phase-d-fixture-terms-v1 at digest 5d31c13d1f0f,
        which matches 0 row(s) in public.legal_documents
```

Nine steps, one refusal, four separate reasons behind it.

### L01 — a register that could not tell naming an object from describing one

`public.phase_d_context_key_object` answers "which business object does this context key name", and
five call sites read it — three identity doors in `fn_phase_d_step_context`, one in
`fn_phase_d_fixture_input`, one in `fn_phase_d_fixture_effect_payload` — every one of them to turn a
key into a **reference**. BR-025 needs two keys that are not references: `terms_version` and
`terms_hash` are facts **about** an acceptance, and the acceptance they are about is the customer's
in W04 and the supplier's in W09. The register had no row for either, and its primary key
(`context_key`) could not have held both answers.

Adding the rows without saying what kind of key they are turns those five doors into fabricators.
Measured: the K07 door then answered `terms_hash` with the business key of the record the run had
just created — `terms_hash 2dbc3271-4f4e-84f5-8d56- is not a SHA-256 digest`. The register now
records `key_role`; every pre-existing row is `IDENTIFIES` and nothing about their behaviour changes;
a partial unique index keeps one key identifying at most one object, so no door can take whichever
row came first.

### L02 — a rule that judges the creation of its subject must still be asked at the step that creates it

K06 gave a rule a **whole-workflow** exemption wherever the workflow produces its subject. K07,
written the same day for gates, had already recorded why that shape is wrong and had already written
the right one: silent before the producing step, and at the producing step only where the test is
the *presence* of the subject.

BR-025 is the rule that makes the difference visible. Scope `W04;W09`; `W09-S06` is the only step in
the estate that produces a supplier terms acceptance; and its own frozen completion condition is
"Displayed version, recorded version and document hash match". A whole-workflow exemption of W09
therefore leaves **nothing anywhere** asking whether a supplier acceptance names its exact terms.
That is a repeal, not an exemption.

Which of the two a rule is, is derived rather than listed: a rule requiring a key that IDENTIFIES its
subject is asking the step to name a record, and at the step that creates that record there is
nothing to name (BR-018 needs `quote_revision_ref`, BR-032 needs `provider_event_id`); a rule whose
keys only DESCRIBE it is judging what is being written and must be asked exactly there.

**Measured delta over all 54 rules × 257 steps — 13,878 pairs: 0 lost, 14 gained.** Nothing stops
being governed.

### L03 — the acceptance record stated neither the version nor the digest it accepted

`phase_b_workflow_step` says W09-S06's required output is an "Immutable supplier acceptance record"
and that the displayed version, the recorded version and the document hash must match. The record
the handler wrote carried a `workflow_record` blob and nothing else: no version, no digest, nothing
to match. Nothing reported it, because the fixture scenario builds a `supplier_terms_acceptance` of
its own with the published pair on it, and every downstream read found **that** record. A harness
that seeds the row the step is supposed to create is answering its own question — one layer further
in than where that sentence was first written.

`public.phase_d_acceptance_document` registers which published document each acceptance object
accepts; the resolver reads it at the producing step, and the handler writes the pair onto the
record, in the same place it already closes a payload with a review verdict or a decider.

### L04 — an object stored in the record table had its owner chosen by position

J06 fixed "which scenario record is the owner" by reading the owner column's own foreign key out of
the write map. Twenty-two of the 56 business objects are views over `public.phase_d_object_record`
and have **no write map**, no owner column and no foreign key, so all of them fell past J06 to the
fallback it was written to replace. W09-S06's acceptance came out owned by `ca99c3de-…`, the
`supplier_safe_package`'s uuid and the first SUPPLIER-scoped scenario record. The owner is now the
primary object of the object's governing workflow where that is a different object of the same
ownership scope — supplier_terms_acceptance is governed by W09 whose primary object is
supplier_account, both SUPPLIER.

### The result

`node scripts/phase_d/build_step_branch_coverage.mjs`, with `for_workflow` set on **every** workflow:

```
frozen steps in the matrix         257 of 257
reached through the canonical path 257 of 257
producing their declared effect    257 of 257
reached only by a direct complete    0
pass edge exercised                257 of 257
fail edge exercised                257 of 257
fail edge matches the frozen model 257 of 257
fail edge produced an effect         0
fail edge produced an object         0
```

The nine builders that asked for the withhold on W12 by name now ask for it on all 30. There is no
longer a stricter harness to report separately: this **is** the harness.

---

## 2. The committed scenario capability

Built, guarded, run for real on production and reversed.

**It refuses to start** unless every guard in `public.fn_phase_d_committed_scenario_guards()` is
green — and the guards are measurements, not assumptions:

| guard | what it measures |
|---|---|
| `no_other_scenario_open` | a partial unique index; a second concurrent open is refused by the database |
| `every_outbound_door_on_a_written_relation_is_disposed` | read from `phase_d_outbound_door`, not asserted |
| `every_active_cron_that_reaches_a_watched_relation_is_registered` | derived from `cron.job` and the routine bodies. **It refused first: six ACTIVE jobs reached a watched relation and were not registered.** They are 92, 172, 179, 213, 214 and 215, all now registered with what each writes and why it cannot touch a fixture row. |
| `outcome_evaluate_daily_inactive` | |
| `fixture_residue_zero_before_open` | |

**The window is designed for, not timed around.** Two ACTIVE cron jobs reach a committed fixture:
278 `phase_c_outbox_deliver_1min` (every minute) and 88 `dropbox_backup_scan` (every 15 minutes,
and a Dropbox write is what the hold forbids). `open()` is ONE statement and therefore ONE
transaction: before it commits it has already inserted cron 88's own dedupe key
(`'C:'||customers.id||':details'`) with status `done`, so the enqueue conflicts and the processor —
which selects `status in ('pending','error')` — never sees it; removed every queue row the
transaction produced; and asserted, with J04's xmin attribution rather than a watermark delta, that
nothing outbound was enqueued.

**Attribution by the xid TREE, not the top-level xid.** The first rehearsal removed queue rows whose
`xmin` equalled `pg_current_xact_id()` and still left six relations above their watermark —
org_tasks +2, phase_c_trace +5, phase_c_task +1, phase_d_dispatch +1, phase_c_workflow_run +1,
phase_c_workflow_step_run +1. Every one was written inside a plpgsql `begin/exception` block, and a
subtransaction has its own xid. `public.fn_phase_d_row_is_ours(xid)` uses the same test J04's
outbound helper already used: a row visible to us whose xmin is still `in progress` can only be ours.

**Run for real** (`scripts/tmp_diag/cs_real.mjs`, scenario 4):

```
OPEN   customer 0dceb236-…, lead 41442, doc_backups quarantine written,
       removed before commit: company_event 1, event_delivery 1, event_assessment 1
CLOSE  removed: leads 1, customers 1, doc_backups 1
REGISTER  every_watched_relation_back_at_its_watermark true
          relations_compared 30
          outbound_requests_naming_the_fixture 0
          fn_phase_d_fixture_residue 0
          kernel_maintenance_write_receipts_added 0
```

### A committed inquiry is refused by name, and this is why

The founder's list permits one. The estate does not, while zero residue also holds. Rehearsed in an
aborted transaction, `close()` failed on:

```
phase_c_system_execution is append-only: DELETE on trace 1931857 refused.
An execution record that can be edited after the fact records the editor, not the execution.
```

`public.inquiries` AFTER INSERT fires `trg_inquiry_received_a`, a registered ACTIVE class A
NEW_WORK_REQUEST source; `fn_kernel_trigger_submit` starts a real W05 run; and
`phase_c_workflow_step_run` AFTER INSERT writes `public.phase_c_trace`, which cascades ON DELETE to
`public.phase_c_system_execution`, whose `z10` trigger refuses DELETE **unconditionally, with no
`kernel.maintenance_reason` door**. Both relations are the frozen Phase C subject `trace_ledger`.
Setting a maintenance reason in the same transaction returns the identical refusal; measured.

Deleting from them needs a Phase C change request and the founder's approval, and weakening the
trigger so this operation could clean up after itself would be the same thing by another route. So
`open()` refuses a committed inquiry, and **PD-PRIV-004 — the one defect that needs one — is a
permanent exemption carrying exactly that reason** rather than closed by leaving ledger rows behind.

---

## 3. Injected defects

`node scripts/phase_d/build_injected_defect_result.mjs`

*(final tally recorded in §9)*

### The blockers were wrong more often than they were right

Of the 39 cases that were not executing, **the recorded blocker was wrong for 23 of them**. Four
shapes:

* **"needs a COMMITTED row."** `public.inquiries`, `public.quotes` and `public.phase_d_object_record`
  hold zero rows *outside* a fixture. Inside one they do not: `fn_phase_d_fixture_scenario` builds
  the customer, the inquiry, the supplier account and the terms acceptance in the caller's own
  transaction, and every refusal those cases needed is an immediate BEFORE-trigger, CHECK or writer
  refusal. None is deferred to commit. What they needed was a **scenario** — and the deliverable
  driver opens the fixture context and builds none, which is why the branches now build their own.
* **"SECTION 8 NOT BUILT."** Section 8 is built and ran 23 probes on 23 Aug. Four cases still carried
  that text, and all four are refused in SQL anyway, one layer before the HTTP path.
* **"the founder-approval path is `phase_c_refund_decision`."** It is
  `public.founder_approval_request`, and that table carries the exact refusal the defect asks for.
* **"no Phase D path writes that table."** True, and irrelevant: BR-031 is registered at
  `fn_kernel_reviewer_independent`, not at the table.

### And one of them was an open door

PD-NOTIFY-005 said it needed a rendered body and a PII detector in the edge functions. Measured:

```
fn_phase_d_external_deliver('W13-S02', … body 'contact Ahmad at zz.cust@example.invalid / 0501234567')
  -> ok=true, delivered=true, attempt 25981
```

BR-011 — "no customer identity in a supplier-facing payload" — refuses that exact string, on shape
as well as on a row match, so it does not need `public.customers` to hold rows. **The send path had
never asked it.** The guard existed, was correct, was registered, and nothing on the path that
needed it called it. M05 makes the send path ask `fn_phase_d_rule_applies` and then
`fn_phase_d_rule_check`, so BR-011's scope stays in the register (42 of 257 steps, unchanged), and
PD-NOTIFY-005 is now closed against it in both directions.

### Two findings carried rather than smoothed over

Both live in the `observed` text of the row that found them, so they cannot be lost:

1. **BR-015 and GATE-014 refuse pending, rejected and expired ALIKE and distinguish none of the
   three.** The only BEFORE-INSERT eligibility guard on `public.inquiry_matches`,
   `fn_unsafe_match_eligibility_guard`, reads `banned`, `matching_blocked`, `permanently_closed` and
   `license_expiry` and **never `approval_status`** — so the canonical writer accepted all three
   ineligible suppliers when the gate was not consulted. `leads.registration_expires_at` is read by
   no rule, no gate and no trigger, so "expired" has no representation any of them would see.
2. **GATE-011 and BR-013 read `inquiries.status`; the trigger reads `inquiries.rfq_ready`;** and
   `rfq_ready` is DERIVED — recomputed by `trg_rfq_complete` on every write — so setting it false is
   not an injection at all.

---

## 4. The register

`public.phase_d_injected_defect_disposition`, and `public.fn_phase_d_disposition_state()` is what
makes it owed: a case whose status is not `REFUSED_AS_REQUIRED` and which has no row is a case nobody
decided. `scripts/phase_d/build_injected_defect_result.mjs` now **fails the build** both ways — a
case that did not run and is not in the register, and a register row for a case that has since been
closed.

*(the register's contents are listed in §9)*

---

## 5. Other defects this session found and fixed

### A door one call deep was invisible to the board that counted doors

`fn_phase_d_outbound_state()` reported "every outbound trigger on a Phase D relation is registered,
4 of 4" and nine green checks. Its denominator matched `net.http_post` in the **trigger function's
own body**. `public.leads` carries `trg_self_reg_category`, whose body posts nothing and calls
`fn_provision_category_call`, which posts to `/functions/v1/category_provision`. The fifth door is
now registered, with the reason it cannot fire: the `supplier_account` write map declares neither
`categories` nor `source`.

**The bound is stated in the code.** The unbounded transitive closure was measured first: it takes
the denominator from 4 to **15**, because `trg_inquiry_received_a`, `notify_matched_supplier`,
`trg_new_quote_sms` and seven more all reach `net.http_post` eventually *through the kernel's own
chain*, and whether they ever do is a runtime condition rather than a property of the trigger.
Registering those ten would assert something this board has not measured. The scan is **one call
deep**; a door two calls deep, or one reached through the kernel chain, is outside this denominator,
and what catches it is `fn_phase_d_object_write`'s own `net.http_request_queue` count on every
fixture write — which aborts the transaction rather than reporting a number.

Also measured on the way: **`'\m'` does not survive this transport.** `standard_conforming_strings`
is off, so `'\m'` arrives as `m`, and the widened pattern silently matched nothing — the widened scan
reported the same four doors as the narrow one until the word boundary was written as a character
class.

### A check arm that had never once reached its report

The 23 Aug hand-over recorded, of
`scripts/checks/phase_d_the_three_steps_that_had_no_effect.test.mjs`:

> Proved both directions, including forced negatives for each of the three on the founder-command
> branch.

That arm failed at its first statement and reported `the probe did not reach its report (HTTP 400)`.
Six reasons, each hidden behind the one before it: `founder_command.message_id` is NOT NULL with a
foreign key to `founder_command_message`; `founder_command_owner_ck` restricts
`command_owner_role_id` to `chief_of_staff`; `intent_id` is NOT NULL and is text;
`phase_c_workflow_run` has no `source_kind` or `source_ref` column and its `start_event` and
`dedupe_key` are NOT NULL; `fn_kernel_write_guard` refuses a direct insert without the owner's
audited maintenance reason; and `fn_founder_command_trace_guard` refuses to leave `received` without
a root trace whose `state_after` matches. All six are fixed, every column read out of
`information_schema` rather than remembered, and all seven tests pass.

### A finding that was counted and never named

The canonical routine engine printed `uncommitted application DDL 2` and named neither. Every other
finding class it reports shows its rows; this one was summed into the exit code and nothing said
which two. They were auto-named CHECK constraints of M04's own — one written on the line after its
column, which the matcher's per-line scan cannot see, and one truncated by Postgres at 63 characters
into a name that appears in no file by construction. The findings are now named, the constraints are
named, and the engine reports 0.

---

## 6. PCCR-004

**Not approved, not applied, and still open.** The approval sentence the founder specified does not
appear in any message from him. `sha256(pg_get_functiondef('public.fn_kernel_cancel(jsonb)'))` is
`fc59489aff…`, which is the frozen baseline digest — measured this session. Cancellation remains
**30 of 30** with the currently approved frozen service. Said once, here, and nowhere else.

---

## 7. Injected defects — the final tally and the register

`node scripts/phase_d/build_injected_defect_result.mjs`

```
catalogue                          75
executed and refused as required   58      (was 36)
NOT_RUN with a named blocker       15      (was 38)
executed but NOT_DISCRIMINATED      2      (was 1)
FAILED TO REFUSE                    0
attempt rows left behind            0
named in the disposition register  17 of 17
```

The seventeen that stay open. Every reason names the object that refuses or the object that does not
exist; the full text is in `public.phase_d_injected_defect_disposition` and in
`PHASE_D_INJECTED_DEFECT_RESULT.csv`.

| defect | why it is not executable |
|---|---|
| PD-FIN-004 | needs a committed founder decision to rewrite. A fixture may never forge one — his standing rule — and `kernel_write_authority` holds 0 rows for `phase_c_refund_decision`, so `a00_kernel_write_guard` refuses every write to it regardless. The append-only refusal itself is real and named: `a00_phase_c_refund_decision_immutable`. |
| PD-CONC-001 | needs two concurrent sessions AND a committed subject with a real claim. Five claimers exist in `public`; the two over `phase_c_event_outbox` are unusable because a committed row there is delivered for real by cron 278 within 60 seconds, `fn_workflow_step_claim` is the business-automation dispatcher and also executes the step, and `fn_kernel_handoff_accept` needs a committed run — which needs a committed trace. |
| PD-PRIV-004 | needs a committed inquiry, which cannot be reversed. Proved by execution: `DELETE FROM public.phase_c_system_execution` → *"is append-only … refused"*, and the identical refusal with `kernel.maintenance_reason` set. |
| PD-STATE-003 | empty population: 0 of 257 frozen steps state their terminality inconsistently, and creating one means editing `phase_b_workflow_step`. |
| PD-STATE-004 | the subject is a frozen Phase B property; `z90_phase_b_freeze` refuses. |
| PD-OUTBOX-004 | a re-emission needs a consumer that both consumes and emits, observed twice on one event; no consumer runs under the automation hold. |
| PD-TRACE-001, -002, -005 | the subject is a kernel-owned table and Phase D has no door to it. `fn_phase_d_object_write` refuses it by name (`pd_object_kernel_owned`) — **that refusal IS the control**, and the rows say so. |
| PD-PRIV-002, PD-PRIV-005, PD-LEGAL-004, PD-QUOTE-005 | the subject does not exist in this estate: a drawing-revision redaction state, a rendered artifact's metadata, a stale legal source, a normalisation path. |
| PD-PROV-002 | the distinction the defect asks for — a gate READ failing rather than evaluating false — is not representable in what `fn_phase_d_gate_evaluate` returns. |
| PD-PROV-004 | the subject is outside the database: it is a CI repository scan over `supabase/functions`. |
| PD-QUOTE-001, PD-QUOTE-004 | not discriminated at the layer this harness reaches: `public.quotes` has row security enabled and the fact the defect names is not stored. |

**Ten of the seventeen are the founder's own holds, or his own frozen registries refusing. None is a
gap in Phase D.**

---

## 8. What was measured, and what was not

Stated because a narrow check does not license a broad claim.

* **257 of 257** is the coverage matrix built by `build_step_branch_coverage.mjs` from a real drive
  of every workflow through the canonical doors, in transactions that end in `raise exception`, with
  the fixture withholding the object the workflow under test produces on all 30. It is not a claim
  that the runtime works in production, where no workflow has been driven under the hold.
* **The outbound-door board's denominator is one call deep.** A door two calls deep, or one reached
  through the kernel's own chain, is outside it. What catches those is
  `fn_phase_d_object_write`'s own `net.http_request_queue` count, which aborts the transaction
  rather than reporting a number.
* **The committed scenario created a customer and a supplier lead, and no inquiry.** Everything §2
  asserts about reversal is asserted about that scenario. A committed inquiry was not run, and the
  reason is measured rather than assumed.
* **The knowledge-pack scorecard was not run.** `scripts/kb/pack_scorecard.mjs` requires
  `--packs=<extracted packs dir>`, which is not in this repository and was not supplied. Nothing is
  claimed about the packs either way.
* **PD-REV-004's row carries a gap this session did not repair**: the kernel's reviewer check runs
  only when `outcome='pass'` AND the step declares an independent reviewer. 28 of 257 do, so on the
  other 229 a recorded `rejected` verdict stops nothing.
* **BR-015 and GATE-014 do not distinguish pending from rejected from expired**, and the only
  BEFORE-INSERT eligibility guard on `inquiry_matches` never reads `approval_status`. Measured,
  carried in PD-DISP-002's row, not repaired here.

---

## 9. Final measurements

Taken after the last run of the session, 21:22 UTC on 23 Aug 2026 (Dubai is UTC+4).

### Phase D

| | |
|---|---|
| frozen steps producing their declared effect | **257 of 257**, with the workflow's own output withheld on all 30 |
| step-contract cases | **1,799 of 1,799**; 1,542 at `live_step_run`, 257 at `kernel_boundary`, **0 at contract level** |
| frozen events observed transaction-locally | **347 of 347**; emitted ids not in the register 0 |
| workflow terminal / failure / cancellation / replay | 30 of 30 each; replay duplicate effects 0 |
| effective handoffs | 159 |
| injected defects | 58 of 75 refused · 0 accepted · 0 incorrectly labelled · 17 of 17 open cases in the register |
| business effects produced | 257 · notification rows written 0 · workflow runs left behind 0 |

### Frozen boards

| | |
|---|---|
| Phase A drift | **0 rows** |
| Phase B drift | **0 rows** |
| Phase C freeze board | **0 red**, `frozen_subjects_drifted` **0 of 25** |
| `fn_kernel_cancel` digest | `fc59489aff…` — the frozen baseline, unchanged |
| repository → production drift | **0** |
| production → repository drift | **0** |
| manifest gaps | **0** · uncommitted application DDL **0** |
| schema export | regenerated, 80,272 lines, byte-identical to the live export |
| deploy parity | **202 functions** carry the repository's current code |
| outbound-door board | 9 checks, **0 red**, denominator 5 |
| disposition board | 4 checks, **0 red**, 17 rows |

### Residue and holds

```
inquiries 0 · customers 0 · quotes 0 · transactions 0 · phase_d_object_record 0
phase_d_dispatch 0 · phase_d_effect_ledger 0 · phase_d_external_attempt 0
fn_phase_d_fixture_residue() 0 · net.http_request_queue 0
leads 20,465 (baseline) · doc_backups 190 (baseline) · company_event 1,526 (baseline)
committed scenarios 1, state CLOSED, 30 relations back at their watermark

llm_attempt 69, unchanged · ai_cost_log today 0 rows, AED 0.00 · paid inference USD 0.00
OpenRouter requests 0 · live email 0 · SMS/WhatsApp 0 · social 0
payment 0 · refund 0 · Apify 0 · production Dropbox writes 0
23 of 206 cron jobs active, unchanged · outcome_evaluate_daily INACTIVE
```

**One persistent count moved and it was not this session's.** `public.notifications` 666 → 667. The
row is id 2351, a `health_alert` written by cron job 7 (`health_check`, `*/30`) at 21:00 UTC to
management@quotesdone.com with status `digest`. **0 notification rows carry any Phase D fixture
marker** — `@example.invalid`, `ZZ DEMO` or `zz-phase-d-`.

### End-of-session sweep

| check | result |
|---|---|
| GitHub Actions on `main` | 3 of 3 workflows success |
| Row #3 scorer, run to completion | **105 / 152 (69%)** — unchanged, and the scorer says so itself: "No verdict changed since the previous recorded run." This session touched no executive-UI surface. |
| `fn_os_portals_gates()` | **21 of 23 met.** The two unmet are consequences of the founder's own holds: "model calls include task class…" is *0 of 0* `ai_cost_log` rows because paid inference is held at zero, and "monitoring and alerts configured" reports 23 of 206 cron jobs active with `watch_failed_runs_hourly` INACTIVE, which is the stand-down. |
| canonical routine engine | **0 findings**, both drift directions, exit 0 |
| schema export byte-identical | yes |
| `node scripts/verify_deploy_parity.mjs --all` | **202 functions** |
| `node --test scripts/checks/phase_d_the_three_steps_that_had_no_effect.test.mjs` | 7 of 7 pass — it was 6 of 7, silently, until this session |
| knowledge-pack scorecard | **not run** — see §8 |

### Exact remaining blockers

1. **Seventeen injected defects are not executable**, each named in
   `public.phase_d_injected_defect_disposition` with the object that refuses or the object that does
   not exist. Ten of the seventeen are the founder's own holds or his own frozen registries
   refusing. None is accepted; none is a zero-population pass.
2. **PCCR-004 awaits one sentence from him.** Nothing else in this session needs him.
3. **Two measured gaps are carried, not repaired**: the kernel's reviewer check does not read a
   rejected verdict on the 229 steps that declare no reviewer, and the `inquiry_matches` eligibility
   guard never reads `approval_status`. Both are recorded where the next reader will see them.
