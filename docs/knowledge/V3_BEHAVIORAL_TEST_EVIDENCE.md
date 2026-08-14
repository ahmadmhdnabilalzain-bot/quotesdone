# V3 behavioural test evidence

14 August 2026. `scripts/checks/v3_runtime_behaviour.test.mjs`, run with
`node --test scripts/checks/`. **48 tests, 48 passing, on BOTH projects** (24 each).

No test asserts on a source string. Every one calls the function an agent calls. Writes run
inside a `DO` block that ends in `raise exception`, so the effect is measured and then rolled
back — the test proves the write without leaving one.

## Roster and retrieval

| test | asserts |
|---|---|
| every packaged department resolves to a live runtime department | 24 packaged names, 0 aliases pointing at an inactive or missing department |
| all 96 packaged roles resolve and every active agent has an identity | 96 distinct role ids; 0 active agents without an identity; 0 identities naming a missing agent |
| all 86 category identities are bound to a live route | 86 identities, 0 dangling |
| an agent's context carries identity, company core, department, role and rules | `cfo` gets its packaged department (`finance`), ≥1 role id, >0 deterministic rules, >0 department records, >0 role records, >0 live company objectives, >0 named knowledge ids |
| another department's role knowledge is NOT retrieved | 0 records whose `role_key` is not one of the agent's own |
| the character budget is respected | 6,000-char budget returns strictly less than a 24,000-char one and stays within 20% of the ask |
| the context path records the knowledge ids it retrieved | exactly 1 `agent_context_retrieval` row per assembly, with a non-zero count, for the right agent |
| a decided agent action writes a decision trace naming those records | exactly 1 `decision_trace` row, carrying the 2 knowledge ids the assembly recorded |

## Management and freshness

| test | asserts |
|---|---|
| a director's context carries its own department's goals and the revenue target | >0 objectives, its own department's goals ranked first, and the AED 1,000,000 target present |
| a KPI record is retrieved as a structured rule, not as prose | authority records arrive in `deterministic_rules`, not in the narrative slices |
| knowledge past its review date is labelled stale, not silently served as current | a record whose `review_after` has passed is marked `stale` by the sweep and is still returned — labelled, not hidden |

## Category specialists

| test | asserts |
|---|---|
| every one of the 86 routes returns its own qualification corpus | 86/86 resolved, 86/86 with packaged questions, 86/86 with mandatory fields, 86/86 with a never-infer list |
| two different routes return different question banks | aluminium-and-glass ≠ catering — a corpus identical across trades is not route-specific |
| quote readiness blocks on the missing mandatory fields and names them | a partial brief is `ready:false` with a non-empty `missing`; the same brief with every mandatory field answered is `ready:true` |
| ambiguous routing asks instead of guessing | an unresolvable slug returns a clarifying question, not a silent pick |

## Learning

| test | asserts |
|---|---|
| one observation is not a lesson, and an author cannot validate its own | 1 observation → `insufficient_evidence`; 2 → `proposed`; self-validation → `self_validation_refused`; manager validation → `validated`; retrievable experience goes from N to N+1 only after validation |

## Remediation

| test | asserts |
|---|---|
| remediation retests on unseen cases and gates autonomy until it improves | 5 practice and 5 retest cases with **0 overlap**; autonomy blocked while open; a 0.45 score leaves it `retesting`; a 0.9 score passes and unblocks |

## Visual

| test | asserts |
|---|---|
| an artifact cannot be published without a passing review of those bytes | no digest → blocked; unreviewed digest → blocked; passing review → unblocked; **regenerated image (different bytes) → blocked again** |
| the creator cannot be the only reviewer | the trigger refuses `author_agent = reviewer_agent` on a passing review |

Additionally measured against the live `artifact_review` function (not part of the suite,
because it depends on an external URL):

- `https://quotesdone.com/brand/logo-horizontal.png` measured as **1859×460 PNG, 47,466 bytes**
  — real dimensions of the real file, read from the PNG IHDR chunk with no decoder.
- Against an Instagram feed slot it failed on `height_below_minimum:460<1080` and
  `aspect_ratio_too_wide:4.04>1.92`, **while the vision model passed the design itself**. That
  split is why both checks exist.
- A 512×512 asset failed `width_below_minimum:512<600` against the generic spec.
- `author_agent = reviewer_agent` returned HTTP 409.

## Certification separation

| test | asserts |
|---|---|
| no certification material reached the runtime corpus | 0 `ops_knowledge` rows with layer `certification`; 0 rows from a certification file path; 0 certification cases in `agent_training_case`; **0 rows in `cert.certification_answer_key`** |
| the certification island is unreachable by the runtime roles | `anon` and `authenticated` have no `USAGE` on schema `cert`; RLS on with **zero policies**, which denies every non-owner role |
| certification results are append-only | an `UPDATE` on `cert.certification_result` raises |

## Readiness

| test | asserts |
|---|---|
| no role is claimed as independently certified by a builder session | 0 rows at `certified_for_defined_role_scope` |

## Ingestion integrity

| test | asserts |
|---|---|
| the imported corpus matches the delivery's declared counts | 2,304 / 1,152 / 1,152 / 768 / 672 / 2,924 = **8,972** V3 training cases; 96 roles and 86 categories with their own knowledge |

## Two tests that failed first

Both were real, and both were found by the tests rather than by reading the code.

1. **`company_objective` was always empty.** The assembler filtered `horizon = 'company'`;
   `company_goals` holds `year_1` and `quarter` and has never held `company`. Every agent's
   context said the company had no objective. Fixed to rank the agent's own department's goals
   first, then the financial ones — which is where the AED 1,000,000 target lives.
2. The probe helper mis-parsed the management API's escaped newline, so two assertions compared
   `'cfo\nCONTEXT:'` with `'cfo'`. A test-harness bug, fixed in the helper.
