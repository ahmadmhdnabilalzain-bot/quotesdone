# Phase D — external effects result (§9)

**Every number below was produced by executing the adapter on production inside an aborted
transaction. Nothing was sent.**

| | |
|---|---|
| contract fields PRESENT | **14 / 14** |
| mock cases executed | **84 / 84 passed** (12 external steps × 7 cases) |
| outbound HTTP requests during the run | **0** |
| provider modes available | **mock only** — CHECKed on the ledger and refused in the routine |
| live email / SMS / WhatsApp / payment / refund | **0** |

---

## 1. The 14 contract fields

Before this work, 8 were ABSENT or PARTIAL and the 12 steps were classified
`EXTERNAL_ADAPTER_CONTRACT_NOT_BUILT` — a classification D12 introduced because
`READY_DISABLED` was claiming a contract that did not exist.

| # | field | state | backed by |
|---|---|---|---|
| 1 | durable effect-intent record | PRESENT | `phase_d_effect_ledger`, one row per (step_run_id, effect_type) |
| 2 | approved payload / version reference | **PRESENT** | the adapter **refuses** an intent with no approved payload (`pd_external_payload_not_approved`); ref + sha256 recorded |
| 3 | recipient / target | PRESENT | `fn_phase_d_effect_produce` raises `pd_effect_intent_incomplete` |
| 4 | consent or suppression result | PRESENT | a suppression records `reconciliation_state = SUPPRESSED` and delivers nothing |
| 5 | provider mode | PRESENT | CHECK `provider_mode = 'mock'`; the routine refuses any other value |
| 6 | idempotency key | PRESENT | UNIQUE `(idempotency_key, attempt_no)`; the first delivered attempt owns the result id |
| 7 | attempt ledger | **PRESENT** | `public.phase_d_external_attempt`, one row per attempt with `attempt_no` |
| 8 | mock provider result | **PRESENT** | `provider_outcome` CHECKed to the seven declared cases |
| 9 | request / result ID contract | **PRESENT** | every attempt carries a request id; a **delivered** attempt must carry a result id, by CHECK |
| 10 | retry classification | **PRESENT** | `retry_class` CHECKed to RETRYABLE / TERMINAL / NOT_APPLICABLE |
| 11 | dead-letter behaviour | **PRESENT** | terminal → dead-letters immediately; retryable → dead-letters at the attempt cap |
| 12 | cancellation behaviour | **PRESENT** (was PARTIAL) | a cancelled intent is recorded and a later delivery on it is **refused** |
| 13 | trace | PRESENT | `trace_id` on the attempt and on the effect ledger |
| 14 | reconciliation | **PRESENT** | every attempt reconciles to MATCHED / SUPPRESSED / NOT_DELIVERED / DEAD_LETTERED / CANCELLED, by CHECK |

**Each state is derived, not typed.** `fn_phase_d_external_field_state()` reads `pg_constraint` and
`prosrc` and computes all 14; `phase_d_external_adapter_field` is a projection of that function, and
a board check fails if the stored table and the mechanism disagree. Editing the table by hand can no
longer change what the phase claims.

---

## 2. The seven cases, and what the adapter does with each

The caller names the case because in mock mode there is no provider to ask. That is stated rather
than dressed up. What the adapter **owns** is what it does with each answer:

| case | delivered | retry class | reconciles as |
|---|---|---|---|
| `success` | yes, with a result id | NOT_APPLICABLE | MATCHED |
| `suppression` | no | NOT_APPLICABLE | SUPPRESSED |
| `null_result` | **no** | RETRYABLE | NOT_DELIVERED |
| `retryable_failure` | no | RETRYABLE, until the cap | NOT_DELIVERED → DEAD_LETTERED |
| `terminal_failure` | no | TERMINAL | DEAD_LETTERED immediately |
| `duplicate_replay` | **no second delivery** — returns the first attempt's result id | NOT_APPLICABLE | MATCHED |
| `cancellation` | no; a later delivery is **refused** | NOT_APPLICABLE | CANCELLED |

**`null_result` is not a success, and that is deliberate.** A provider that answers with nothing has
not delivered. This estate has already paid for the opposite reading once — `quote_compare` returned
`{ok:false}` at HTTP 200 for weeks and was counted as working. Here a null result is a failure, is
retryable, and reconciles as NOT_DELIVERED.

**84 / 84 cases pass.** The denominator is derived — 7 × the number of steps whose
`expected_effect_type` is `EXTERNAL_EFFECT_INTENT` — so it moves if the frozen registry moves and
cannot be satisfied by a shrinking population.

---

## 3. It cannot send

This is asserted by a board check, not by a promise:

- `provider_mode` is CHECKed to `'mock'` on the attempt ledger; there is no live value to set.
- `fn_phase_d_external_deliver` refuses any other mode with `pd_external_live_mode_refused`.
- Neither `fn_phase_d_external_deliver` nor `fn_phase_d_run_external_cases` contains
  `net.http_`, `pg_net` or `functions/v1/` — checked against `prosrc`, and RED if either ever does.
- Underneath it, the D17 guard in `fn_phase_d_object_write` refuses **any** Phase D write that
  leaves a request in `net.http_request_queue`. The 84-case run enqueued **0**.

The 12 steps have returned to `EXTERNAL_ADAPTER_READY_DISABLED`, and the control on that
reclassification refuses to run unless all 14 fields read PRESENT — so the label cannot run ahead of
the contract a second time.

---

## 4. The founder's reveal contract — encoded, not enabled

He stated that a reveal notifies **both** parties: an email to each and a WhatsApp to each, on their
registered numbers. **Four messages.**

`phase_d_external_message_contract` carries all four as required, and the adapter **refuses** a
reveal payload that does not carry every one of them (`pd_external_reveal_contract_incomplete`).

**The gap is measured and disclosed rather than quietly closed.** `trg_reveal_receipt` contains
exactly **one** insert into `public.notifications`, `to_role='customer'`, naming no channel and no
phone. The board reports that count as a DISCLOSED row.

Closing the gap means changing live product behaviour while the outbound senders are held, which is
a product change and not a Phase D increment. **Nothing was enabled and the trigger was not
touched.** Section 9 is built to the contract he described, which is what the brief required.

---

## 5. Board

| check | expected | actual | state |
|---|---|---|---|
| `all_fourteen_contract_fields_present` | 14 | 14 | **GREEN** |
| `the_stored_field_table_matches_the_mechanism` | 0 | 0 | **GREEN** |
| `the_adapter_cannot_send` | 0 | 0 | **GREEN** |
| `the_founder_reveal_contract_is_four_messages` | 4 | 4 | **GREEN** |
| `reveal_messages_the_live_trigger_actually_sends` | disclosed | 1 | **DISCLOSED** |

## Boundary of this evidence

This covers the mock adapter on the one project, executed in aborted transactions on
2026-08-19 (database clock). It is a statement about what the adapter records, classifies, refuses
and reconciles. It is **not** a claim that any live provider integration works, because there is no
live provider mode to test — building one is Phase E work and is explicitly held here.

---

## 2026-08-24 — legal-source currency, and what still did not leave the estate

Project `htdblwldjkcgjvmqkbeh`.

### Nothing left, and here is the measurement rather than the assurance

| | |
|---|---|
| OpenRouter HTTP requests | **0** |
| other paid-inference requests | **0** |
| `public.llm_attempt` rows this session | **0** (last row in the table: `2026-08-15 02:51:33+00`) |
| `public.ai_usage` rows this session | **0** (last row in the table: `2026-07-13 23:37:25+00`) |
| paid inference cost | **USD 0.00** |
| live email / SMS / WhatsApp | **0** |
| social publication | **0** |
| payment execution | **0** |
| refund execution | **0** — `public.refunds` still holds 0 rows |
| customer / supplier notification | **0** |
| Apify runs | **0** |
| production Dropbox writes | **0** |
| fallback provider keys | **0** |

The metadata scanner added this session (`scripts/phase_d/metadata_scan.mjs`) reads **committed
bytes from the repository** and the Supabase management endpoint, and nothing else. It uses no
model and no third-party service: PDF `/Info`, XMP, PNG text chunks and JPEG `APP1`/`COM` are read
from the raw bytes with the standard library, which is also why it adds no dependency.

### PD-LEGAL-004 — the freshness control, and where it is a boundary rather than a report

Measured across the whole estate before anything was built: `public.compliance_sources` holds 17
UAE building/fire/electrical/telecom/health codes and **zero** tax or legal-interpretation
authorities; `public.legal_documents` holds 12 of our own published policies; `public.reg_catalog`
and `public.regulations` are technical codes; all 8,256 rows of `public.ops_knowledge` carry
`source_authority` `quotesdone_delivery` or null — us citing ourselves. **No predicate anywhere
judged any of them stale**: the four routines that compare a date to `now()` each SET a column or
RAISE a flag, and none refuses anything.

`phase_d_o03` adds `public.phase_d_legal_source` (jurisdiction, subject, source type, authority
tier, source reference, content digest, published/effective dates, retrieved-at, review-by,
freshness policy, supersession, evidence owner, reviewer, trace) and
`public.fn_phase_d_legal_source_current`, which names **which** failure it found:

| committed fixture | verdict |
|---|---|
| `zz-demo-fta-corporate-tax-expired` (review_by 2021-03-31) | `pd_legal_source_stale` |
| `zz-demo-undated-circular` (authoritative, no dates at all) | `pd_legal_source_missing` |
| `zz-demo-blog-vat-opinion` (in date, secondary commentary) | `pd_legal_source_not_authoritative` |
| `zz-demo-fta-corporate-tax-2024` (in date, authoritative, replaced) | `pd_legal_source_superseded` |
| `zz-demo-fta-corporate-tax-current` | **usable** |
| the blog again, with `p_require_authoritative := false` | **usable** — the tier arm is not refuse-everything |

The five fixtures are **committed by the migration, not created by the probe**: a probe that writes
its own stale source and then asks whether a stale source is refused has answered its own question.
The stale one is stale by five years so it cannot become current by the passage of time and quietly
turn a red arm green.

**Where it BLOCKS.** `public.phase_d_legal_assertion` records a legal or tax position and the source
it rests on, and `a10_phase_d_legal_assertion_source` refuses the row outright when the source is
stale, superseded, undated or not authoritative. That is the hard boundary. Measured: an assertion
citing `zz-demo-fta-corporate-tax-expired` is refused `23514` carrying `pd_legal_source_stale`.

**Where it only JUDGES, and why it does not block there.** GATE-027 binds 10 W27 steps and GATE-028
binds 9 W28 steps. Making a source reference a **required** evidence key would block all nineteen on
every drive, because `fn_phase_d_step_context` resolves no such key — nineteen steps stopped for a
control that belongs to the two whose frozen acceptance criteria demand it. That is the "tightening
a guard reddens its own probes" trade and it is not worth making here. Instead both gates now judge
a source **when one is cited**, and say so in the reason either way:

| call | result |
|---|---|
| GATE-027 citing the stale tax source | BLOCKED `pd_legal_source_stale` |
| GATE-027 citing the current one | PASSED |
| GATE-027 citing none | PASSED, and the reason says no currency test was performed |
| GATE-028 citing the non-authoritative source | BLOCKED `pd_legal_source_not_authoritative` |
| GATE-028 citing the superseded one | BLOCKED `pd_legal_source_superseded` |
| GATE-028 citing the undated one | BLOCKED `pd_legal_source_missing` |
| GATE-028 citing none | PASSED, with the same disclosure |

GATE-022 · 023 · 024 · 025 · 026 · 029 · 030 were re-read after the change and are unchanged at
PASSED with all declared evidence present.

**Phase D does not supply the interpretation, and the capability boundary still refuses it.**
`fn_phase_d_handler_execute` raises `pd_capability_unavailable` (`23514`) for W28-S03, W28-S04,
W28-S06 and W17-S05 because those steps declare `capability_dependency REASONING` and
`public.phase_d_capability_result` holds no answer. That is Phase E's work and it is untouched.
