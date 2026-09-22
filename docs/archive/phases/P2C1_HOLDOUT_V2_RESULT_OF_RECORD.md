# QuotesDone P2-C1 — sealed holdout v2, first and only evaluation

**Result of record id:** `1` (`holdout_v2.result_of_record`, immutable)
**Recorded at:** 2026-08-02 22:39:19 UTC
**Commit under test:** `658e67506bc8401bf92c78d143687e8e99e65241` on `feature/phase1-safety-and-decisions`, working tree clean
**Database state:** P2-C1 migrations `20260802165328` … `20260802205600` applied; latest `p2_c1_stage_b7_detection_performance`
**Interpretation-code fingerprint (md5 over 13 function bodies):** `26c2596817db2f01cf3d8af28e37ba78` — identical before and after the run
**Entry point:** `public.fn_inquiry_interpret(group_id, text, null, documents, 'holdout_v2_eval')`

---

## 1. Bundle and seal verification

| check | expected | observed | verdict |
|---|---|---|---|
| `holdout_v2_authoring_input_exact.md` sha-256 | `94cfadfe…202fec` (38,081 B) | identical | PASS |
| `holdout_v2_cases.json` sha-256 | `44973f91…3d4801` (206,693 B) | identical | PASS |
| `holdout_v2_seal.json` sha-256 | `8dd114a7…2eafaf` (857 B) | identical | PASS |
| `holdout_v2_manifest.md` sha-256 | `91c581c7…d0a6d2` (7,968 B) | identical | PASS |
| `validate_holdout_v2.mjs` sha-256 | `047886ce…f030` (35,202 B) | identical | PASS |
| seal `checksum_sha256` == sha-256 of the case file | yes | yes | PASS |
| seal `case_count` | 131 | 131 | PASS |
| seal `brief_sha256` == authoring-input hash | yes | yes | PASS |
| authoring input == brief committed at `c176fc4` | `94cfadfe…202fec` | identical | PASS |
| manifest checksum lines agree with the file | yes | yes | PASS |
| `validate_holdout_v2.mjs --no-write` | exit 0, V1–V24 pass | exit 0, V1–V24 pass | PASS |
| case pairs / interpretations / trade slots | 131 / 262 / 1,310 | 131 / 262 / 1,310 | PASS |
| canonical round-trip | byte-identical | byte-identical (verified twice: by the sealed validator and by an independent re-implementation) | PASS |
| sealed artefacts modified by verification | none | none (hashes unchanged after the run) | PASS |

**Load-time seal.** One transaction created schema `holdout_v2`, inserted all 131 cases, installed
`BEFORE UPDATE OR DELETE` and `BEFORE TRUNCATE` protections on the case, seal and result tables,
inserted the seal, reassembled the canonical document **from the loaded rows** and hashed it:

```
recomputed = 44973f9169510a06468a20eb2ba068f932e25bdd9ad7e0d85d4479b5e03d4801
sealed     = 44973f9169510a06468a20eb2ba068f932e25bdd9ad7e0d85d4479b5e03d4801   MATCH
```

The refuse path was rehearsed before the real load: a single altered byte moved the recomputed
checksum to `deba9263…f506d2ed` and the whole transaction rolled back, leaving no schema behind.
Each immutability trigger was probed and refused UPDATE, DELETE and TRUNCATE.

**Isolation.** `holdout_v2` is not reachable through PostgREST: `anon` and `authenticated` hold no
`USAGE` on the schema, and row-level security is enabled with no policies on all six tables.

---

## 2. Execution

| | |
|---|---|
| Cases executed | **262 / 262 interpretations** (131 cases × 2 languages) |
| Execution errors | 0 |
| Runs of the implementation against v2 | exactly 1 |
| Wall-clock inside `fn_inquiry_interpret` | 28.27 s total |

---

## 3. Metrics, every one with its denominator

| # | metric | numerator | denominator | value |
|---|---|---|---|---|
| 1 | Cases executed | 262 | 262 interpretations | 100.00 % |
| 2 | **Case-level exact accuracy** | 86 | 262 interpretations | **32.82 %** |
| 2b | Cases correct in *both* languages | 32 | 131 cases | 24.43 % |
| 3 | **Active-trade-set accuracy** (exact set equality) | 185 | 262 interpretations | **70.61 %** |
| 5 | **Per-trade disposition accuracy** | 264 | 376 expected trade slots (2 × 188) | **70.21 %** |
| 6 | **Component-disposition accuracy** | 288 | 452 expected component rows (2 × 226) | **63.72 %** |
| 7 | **Clarification accuracy** | 162 | 262 interpretations | **61.83 %** |
| 7b | Clarification-reason accuracy | 154 | 262 interpretations | 58.78 % |
| 8 | **Clarification accuracy, component-triggered subset** | 0 | 28 interpretations (2 × 14 cases) | **0.00 %** |
| 9 | **Blocker-set accuracy** (exact set equality) | 150 | 262 interpretations | **57.25 %** |
| 10 | **English/Arabic parity** | 81 | 131 paired cases | **61.83 %** |

### 4. Detection confusion matrix — all 1,310 trade slots

Denominator = 2 × 131 cases × 5 trades = **1,310**.

| cell | count |
|---|---|
| TP — expected detected and detected | 350 |
| TN — not expected, not detected | 922 |
| FP — not expected, detected | 12 |
| FN — expected detected, not detected | 26 |

| figure | formula | value |
|---|---|---|
| **detection accuracy** | (350 + 922) / 1,310 | **97.1008 %** |
| detection recall (sensitivity) | 350 / 376 | 93.0851 % |
| detection specificity | 922 / 934 | 98.7152 % |
| detection precision | 350 / 362 | 96.6851 % |
| false-positive rate | 12 / 934 | 1.2848 % |

Per trade (denominator 262 slots each):

| trade | TP | FN | FP | TN |
|---|---|---|---|---|
| electrical | 94 | 4 | 4 | 160 |
| elv | 40 | 6 | 0 | 216 |
| fire | 42 | 4 | 0 | 216 |
| hvac | 96 | 8 | 3 | 155 |
| plumbing | 78 | 4 | 5 | 175 |

### 11–14. Safety counts

| count | value |
|---|---|
| **Unsafe activations** (a trade activated whose expected disposition does not contribute) | **52** |
|  of which on trades the case does not expect at all | 5 |
| **Missed component-level clarifications** (component-triggered case returning `clarification_required: false`) | **28** |
| **False-positive detections** | **12** |
| **False-negative detections** | **26** |
| False-positive detections on cases expecting no detection at all | 6 interpretations (P-001 ×3 EN, P-002 EN+AR, P-003 EN+AR, P-004 AR) |
| Clarification asked where the expectation says none | 49 interpretations |
| Clarification expected but not asked | 51 of 68 interpretations that expect one |

Unsafe activations by the disposition the case expected:

| expected disposition of the activated trade | activations |
|---|---|
| `by_others` | 14 |
| `excluded` | 13 |
| `unknown` | 6 |
| `conflicted` | 5 |
| trade not expected at all | 5 |
| `optional` | 5 |
| `future_phase` | 4 |
| **total** | **52** |

Under-detection and over-activation are reported separately and are never netted off.
Parity is reported alongside correctness: 81 / 131 cases agree between languages, and agreement
includes cases where both languages are wrong in the same way.

### 15. Latency

Measured in-database around `fn_inquiry_interpret` only, excluding group creation and teardown.

| statistic | ms |
|---|---|
| mean | **107.92** |
| p50 | **105.75** |
| p95 | **157.25** |
| max | **201.93** |
| min | 73.66 |

Stage B.6 baseline was mean 81.3 / p50 77.6 / p95 106.7; Part 3 measured mean 98.4 / p50 97.0 /
p95 122.1 / max 156.5 on holdout v1. v2 texts are longer and carry more clauses, which is the
expected direction; the residual +21 % structural cost noted in Part 3 is unchanged.

---

## 5. Acceptance thresholds

| criterion | threshold | measured | verdict |
|---|---|---|---|
| case-level exact accuracy | ≥ 99 % | 32.82 % (86/262) | **FAIL** |
| English/Arabic parity | ≥ 99 % | 61.83 % (81/131) | **FAIL** |
| false-positive activation from exclusion language | 0 | 36 (`excluded` 13, `by_others` 14, `future_phase` 4, `optional` 5) | **FAIL** |
| unsafe activations | 0 | 52 | **FAIL** |
| missed component-level clarifications | 0 | 28 | **FAIL** |
| clarification accuracy, component-triggered subset | ≥ 99 % | 0.00 % (0/28) | **FAIL** |
| unexplained failures | 0 | 0 | **PASS** |

**Holdout v2 is not passed.** Every failing case is diagnosed individually in
`P2C1_HOLDOUT_V2_FAILURE_REPORT.md`.

---

## 6. Controls

| control | value |
|---|---|
| Expectation drift (`v_scenario_expectation_drift`) | **0 rows**, before and after |
| Routes activated / live workstreams left behind | **0** |
| Groups, candidates, dispositions, clarifications, audit rows left behind | **0** each |
| Sealed v2 expectations edited | **none** — the case table refuses UPDATE and DELETE |
| Implementation code changed | **none** — fingerprint `26c2596817db2f01cf3d8af28e37ba78` identical before and after |
| Holdout v1 seal | `cfb06e11…1fb089`, unchanged; its result of record still the single row |
| Migrations applied to production | none by this session outside the `holdout_v2` schema |
| Interpretation rules, aliases, weights, expectations, database functions | untouched |

---

## 7. Evaluator interpretation decisions

The implementation does not expose two of the nine sealed `expect` fields in the v2 vocabulary.
Every decision below was fixed *before* the run, applied identically to all 262 interpretations,
and the raw outputs are stored in `holdout_v2.raw_interpretation` so the whole suite can be
rescored under any other reading without touching the implementation.

1. **Trade disposition** = `v_trade_scope_status.disposition`, except that `is_conflict` maps to
   `conflicted`, and a candidate whose confirmation status is `proposed` carrying a contributing
   scope disposition maps to `proposed` (brief 2.2 and 2.8). Scoring the raw value instead would
   be *less* favourable to the implementation.
2. **Component disposition** for an expected `(trade, component)` pair = the implementation's row
   for that pair if it produced one, otherwise the trade disposition by inheritance (brief 2.4),
   otherwise `(absent)`. Only expected rows are scored, which is the 8.2 denominator. Component
   rows the implementation invents beyond the expectation are not charged here; where they carry a
   clarifying disposition they surface in the clarification metrics instead.
3. **`clarification_reason` and `dispatch_blockers` do not exist in the implementation.** Both were
   derived from the implementation's *own* outputs using the 2.7 precedence table and the 2.9
   blocker rules — never from the expectation. Blocker-set accuracy is therefore not an independent
   measurement; it is a restatement of activation, conflict and clarification correctness, and it
   is reported as such. This reporting gap is itself a finding (see RC-11 and the note in §8.2 of
   the brief).
4. **Documents** were passed as approved extractions, matching the holdout v1 language harness.
5. **Latency** covers `fn_inquiry_interpret` only.
