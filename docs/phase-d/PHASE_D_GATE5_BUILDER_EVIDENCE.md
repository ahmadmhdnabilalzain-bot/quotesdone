# Gate 5 — builder evidence at HEAD

# BUILDER_EVIDENCE_PENDING_FINAL_AUDIT

**This is the builder's own measurement. It is not an independent acceptance and it does not close
Gate 5 / Gate FD-02.** Only an independent audit can do that, against
`docs/phase-d/PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1.md` §B.

The 24 August independent audit failed Gate 5 on two grounds: `schema_output_w17_s06` accepted
`decision = NOT_A_DECISION`, and the hole was structural — 140 of 257 output schemas typed a
consequential verdict-shaped key as a bare string with no domain (`decision` on 35, `verdict` on 47,
`state_change` on 58). Everything below was executed against production
`htdblwldjkcgjvmqkbeh` on 2026-08-24, after PR #466.

---

## Provenance

| | |
|---|---|
| branch | `main` |
| commit | `521ed160af1c995aa4d42d8bb9f048d720ade09e` (= `origin/main`, 0 ahead / 0 behind, working tree clean of tracked changes) |
| PR | **#466** — *"Gate 5: a field named decision that carried a sentence, and 67 down scripts that could not be rehearsed"*, merged into `521ed16` |
| project | `htdblwldjkcgjvmqkbeh` (one project) |
| migration files | `scripts/sql/phase_d_p01_a_field_named_decision_that_carried_a_sentence.sql` · `…p02_a_destructive_runner_and_a_denominator_that_was_typed.sql` · `…p03_two_decision_steps_the_catalogue_never_told_what_was_decided.sql` · `…p04_four_corrections_an_adversarial_pass_found.sql` — all four listed in `scripts/sql/MANIFEST.txt` (lines 1694–1697), i.e. applied |

sha256 of the four, as committed:

```
5d7bd992fb06f7ada1b35650414b932aa9d13359284011679fb8124b41ac287f  phase_d_p01_…
126268d9aabe19f4e82738ac18e7f570d4933e17d5f86755596cac4a8db2cc38  phase_d_p02_…
61cc52dcc5a3bfd9960c09f0607e7f5fdf6d1df851300641d084c98c2847cd77  phase_d_p03_…
5b7f9c68f86c61fdcf77dfa484c643f7bd2118de4b04bb0349a5d9fb6c93a947  phase_d_p04_…
```

---

## The cause, so the fix is not read as a patch on a symptom

Two lines in `public.fn_phase_d_handler_execute`:

```
when 'DECISION_HANDLER'  then … 'decision',     coalesce(s.required_output,'')
when 'EXECUTION_HANDLER' then … 'state_change', coalesce(s.required_output,'')
```

`phase_b_workflow_step.required_output` is a **prose sentence** — *"Case decision with required
actions."*, *"Active customer account."* So the field named `decision` never carried a decision and
the field named `state_change` never carried a state. Both carried a restatement of the artefact
that the `output` key already carries in full. `schema_output_w17_s06` accepted `NOT_A_DECISION`
because the thing it was refusing was a sentence, and there was nothing for a domain to be about.

---

## Denominators, read from production

`public.phase_d_output_domain_registry` — one row for **every** (schema, field) pair across all 514
schemas, including the pairs it classifies as free-form, so "no domain" is a measured classification
rather than an absence.

| measurement | value |
|---|---|
| **domain-registry denominator** | **2,793** (schema, field) pairs across 514 schemas |
| classified `CLOSED_ENUM` — carrying an enforced domain | **478** (was 257, all of them `status`) |
| classified `CLOSED_ENUM_UNDEFINED` | **33** — every one a `decision` field, each naming PBCR-002 in `domain_source` and quoting its own frozen `required_action` |
| classified `FREE_FORM` | 487 |
| classified `STRUCTURED` | 1,732 |
| classified `REFERENTIAL` | 47 |
| classified `NUMERIC` | 16 |
| **fields with no domain** | **0 unclassified of 2,793.** Every pair carries a registered semantic type. 0 registered CLOSED_ENUM fields are undeclared on their schema |

Per consequential field:

| field | denominator | with an enforced domain | authority the values were read from |
|---|---|---|---|
| **`decision`** | **35** | **2** — W17-S06, W08-S06 | CHECK `phase_c_refund_decision_ck`; CHECK `phase_d_file_revision_verdict_ck` |
| | | *33 registered `CLOSED_ENUM_UNDEFINED`* | no vocabulary exists in the frozen estate — raised as PBCR-002 |
| **`verdict`** | **47** | **47** | `fn_kernel_review_decide`, a frozen Phase C subject; corroborated by CHECK `phase_d_file_revision_verdict_ck` |
| **`state_change`** | **58** | **58** | `phase_d_object_state_contract.allowed_states`, enforced by trigger `z40_phase_d_object_record_contract` |
| **other finite-domain fields** | **371** | **371** | `status` 257 → `fn_phase_c_output_validate`, the frozen Phase C output authority · `target_object` 58 → the 56-id business-object registry, identical across three tables · `method` 31 → the only reachable value in the producing routine · `receiving_role_id` 25 → frozen `phase_b_handoff.receiving_role_id`, canonicalised through `fn_phase_c_resolve_actor` |

**No value in any `allowed_values` array was invented.** Each was read from an object that already
refuses an out-of-domain value somewhere else in the estate.

---

## W17-S06, executed

`schema_output_w17_s06` at HEAD: version 2, `additional_properties = false`, 7 required keys, 8
typed fields, 2 enum domains — `status` and `decision: ["approved","rejected"]`.

All ten cases run through `public.fn_phase_d_schema_validate('schema_output_w17_s06', …)` on
production, in one statement, with the conforming payload as the control:

| case | result |
|---|---|
| **conforming control** (`decision = approved`) | **valid** — *"payload satisfies schema_output_w17_s06 v2 (7 keys, 8 typed, 2 domain(s), closed, source digest 0a55289d8e51)"* ✓ |
| second control (`decision = rejected`) | **valid** ✓ |
| `status` as a number | refused — *wrong types [status expected string got number]* ✓ |
| `acceptance_assertions` as a string | refused — *wrong types [… expected array got string]* ✓ |
| `evidence_refs` as a number | refused — *wrong types [… expected array got number]* ✓ |
| `decision` as an array | refused — *wrong types [decision expected string got array]* ✓ |
| `status = purple-elephant` | refused — *outside the declared domain … not one of [ok, success, completed, refused, empty]* ✓ |
| **`decision = NOT_A_DECISION`** | **refused — *outside the declared domain [decision='NOT_A_DECISION' is not one of [approved, rejected]]*** ✓ |
| invented `refund_amount_aed` | refused — *closed contract and the payload carries [refund_amount_aed]* ✓ |
| invented arbitrary property | refused — *closed contract and the payload carries [zz_arbitrary]* ✓ |

**The case the audit failed on now refuses, and the control still validates** — which is the pair
that matters. A refusal with no passing control proves only that the validator says no.

---

## All-schema result

`node --test scripts/checks/phase_d_input_schemas_are_typed_and_closed.test.mjs` at HEAD —
**8 tests, 8 pass, 0 fail**:

```
✔ no schema declares an unconstrained key, and no contract is open
✔ NEGATIVE CONTROL 1: wrongly-typed values are refused
✔ NEGATIVE CONTROL 2: an injected money key and __proto__ are refused
✔ POSITIVE CONTROL: a well-formed payload still validates
✔ the output contract still refuses a bad status and an invented key
✔ every field on every schema carries a classified semantic domain
    478 CLOSED_ENUM field(s) enforced; 33 CLOSED_ENUM_UNDEFINED, each naming its change request
✔ every registered closed domain is actually declared on its schema
    7 closed-domain field name(s): conforming accepted, sentinel refused, on all
✔ an invalid value is refused on EVERY consequential closed-domain field
```

The last two assertions are new in PR #466 and are the answer to *why Gate 5 survived to the final
audit*: the pre-existing assertion was *"the output contract still refuses a bad **status** and an
invented key"* — it tested the one field that had a domain, and a check scoped to the only
constrained key cannot report that the other 140 schemas constrain nothing.

`select * from public.fn_phase_d_contract_state();` — **16 of 16 rows `ok`**, including
`every_schema_carries_a_version` 514, `every_schema_field_carries_a_registered_semantic_domain`
0 unclassified of 2,793, `every_registered_closed_domain_is_declared_on_its_schema` 0 undeclared of
478, and the four `out_of_domain_*_is_refused` rows for `status`, `decision`, `verdict` and
`state_change`.

---

## 1,799-case result

`node scripts/phase_d/run_step_cases_live.mjs`, re-run at HEAD after the P-series was applied:

```
steps driven                 257
cases written                1799
cases passed                 1799
cases failed                 0
  positive               257 of 257   (live_step_run)
  missing_input          257 of 257   (live_step_run)
  wrong_actor            257 of 257   (live_step_run)
  invalid_state          257 of 257   (live_step_run)
  duplicate              257 of 257   (live_step_run)
  failed_rule_or_gate    257 of 257   (live_step_run)
  malformed_output       257 of 257   (kernel_boundary)
```

One `ECONNRESET` occurred mid-run and the harness retried it (`retry in 2s (1/5)`). A transport
failure is not a measurement; the retry succeeded and every step is accounted for.

`select * from public.fn_phase_d_case_state();` afterwards — every row `ok`:
`per_step_cases_recorded` 1,799 of 1,799 · `steps_with_the_wrong_number_of_cases` 0 ·
`steps_missing_a_required_case_kind` 0 of 257 · `cases_failing` 0 of 1,799 ·
`negative_cases_with_no_refusal_code` 0 · `cases_not_decided_against_a_live_step_run` 0 of 1,799
(`live_step_run` 1,542, `kernel_boundary` 257).

**Why this was re-run rather than read.** The table held 1,799 passing rows written at
2026-08-24T17:58Z, and `phase_d_output_domain_registry` was written at 17:11Z — so the population
was 47 minutes newer than P01, but whether it predated P03 and P04 could not be settled from
timestamps. A board reading green off a pre-fix population is the failure mode this estate has been
bitten by before, so it was re-driven rather than trusted.

---

## Boundary conditions, all still held

| measurement | value |
|---|---|
| repository → production parity | **0** — `canonical_routine_manifest.mjs --all`: conflicting definitions 0, ambiguous winners 0, manifest gaps 0, repository→production drift 0, production→repository drift 0, uncommitted application DDL 0, exit 0 |
| persistent residue | **0** — `fn_phase_d_fixture_residue()` 0; customers 0, inquiries 0, quotes 0, transactions 0, quote_comparisons 0, refunds 0, `phase_c_refund_decision` 0, `founder_approval_request` 0, `phase_d_effect_ledger` 0, `phase_d_object_record` 0, `phase_d_dispatch` 0, `phase_d_quote_normalisation` 0, `phase_c_founder_auth_event` 0 |
| paid-provider requests | **0** — `llm_attempt` 69 (max 2026-08-15), `ai_usage` 14 (max 2026-07-13), `ai_cost_log` 3,507 (max 2026-08-15): all three unmoved. `net.http_request_queue` 0. `fn_kernel_paid_provider_gate` refuses every named model: *"8 of 8 routes are held open-circuit until 2126-08-15"*. Paid inference **USD 0.00** |
| live external effects | **0** — `phase_d_external_attempt` 0, `stripe_events` 0, `public.refunds` 0. Notifications **sent** since 2026-08-16T05:30:04Z: 0 — that timestamp is still the newest `sent_at` in the table |
| frozen baselines | Phase A drift 0 · Phase B drift 0 · Phase C freeze drift 0 not-ok of 8 rows · Phase B baseline 30 / 257 / 56 / 54 / 32 / 159 / 347 |
| automation hold | `GATE-032` **PASSED** — 23 active cron against the selective ceiling of 25 |

---

## What this evidence does not claim

- It does **not** claim Gate 5 is closed. That is
  **`BUILDER_EVIDENCE_PENDING_FINAL_AUDIT`** — the label at the top of this file, and the reason it
  is there.
- It does **not** claim the 33 `CLOSED_ENUM_UNDEFINED` fields are constrained. They are registered,
  they name an open change request, a CHECK on the registry refuses such a row that names no
  `PBCR-nnn`, and `fn_phase_d_schema_validate` still enforces presence, type, non-emptiness and the
  closed contract on all 33. It does not enforce a vocabulary on them, because none exists.
- It does **not** claim Gate 1 / FD-01 is closed. PCCR-006 is committed, listed in
  `scripts/sql/PENDING.txt`, and **not applied**.
- It says nothing about the eight findings the 24 August audit recorded as not failing a mandatory
  gate; five of them were addressed in the same PR and are the P02/P04 subjects, and that is a
  separate claim needing its own evidence.
