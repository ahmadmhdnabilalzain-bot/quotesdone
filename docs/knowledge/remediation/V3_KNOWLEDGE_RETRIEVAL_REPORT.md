# V3 REMEDIATION — STAGE 4: KNOWLEDGE RETRIEVAL

**Scope:** `KNOWLEDGE_NOT_RETRIEVED`, 1,706 questions, from result of record `V3-COR-0A782DA90B10`
(overall 56.97%).
**Measured against:** Supabase staging `pglpqrhvozwepymcuunn`, read-only, 14 Aug 2026 between
~14:05 and 14:17 UTC. No writes were made; no aborted-transaction probe was needed.
**Nothing here certifies anything.** Internal measurement is not certification. Zero roles, zero
departments and zero categories are certified, and only an independent evaluator can change that.

---

## 1. The headline, reproduced

The certification recorded a contradiction: retrieval traces non-empty on every row, ~46 records per
execution, 8,256 `ops_knowledge` rows loaded — and the knowledge still not in the answer. Two
defects, each hiding the other.

**Defect A — the task query ANDed every word.** `fn_agent_context_v3` built its query with
`websearch_to_tsquery` over the whole task sentence.

```
websearch_to_tsquery('english','cash reserve budget variance')
  → 'cash' & 'reserv' & 'budget' & 'varianc'
fn_task_tsquery('cash reserve budget variance')
  → 'budget' | 'cash' | 'reserv' | 'varianc'
```

Corpus-wide (`runtime_eligible and supersession_state='current'`, n=8,256, `tsv` populated on
8,256/8,256): the AND form matches **0** rows; the OR form matches **588**. Inside finance's own
department layer (`layer='department_shared' and dept_key = any(fn_dept_scope('finance'))`, 170
scoped rows): AND **0**, OR **49**.

That is not a finance quirk. Six real agents, six departments, one realistic task each, counted over
their own `department_shared` scope:

| agent | scoped | AND matches | OR matches |
|---|---|---|---|
| followup | 92 | 0 | 90 |
| fraud_analyst | 94 | 0 | 67 |
| legal | 94 | 0 | 94 |
| marketing | 179 | 0 | 118 |
| qa_manager | 246 | 0 | 238 |
| supplier_verification | 420 | **1** | 416 |

A task description is a sentence. Requiring every stemmed word to co-occur in one record matches
nothing, every time.

**Defect B — the filter was a tautology.** `scripts/sql/v3_context_assembly.sql:46`:

```sql
and (p_q is null or tsv @@ p_q or true)
```

The trailing `or true` made the predicate unconditionally true. Membership was never filtered — which
is precisely why Defect A never surfaced as an empty context. The two defects were load-bearing for
each other.

## 2. One claim in the repair file is overstated, and it matters

`v3_repair_04_task_query.sql:19` says the runtime settled into "fetching 46 records per call that
were selected by nothing at all." Measured, that is not true, and the correction changes what the fix
is worth.

`ts_rank` awards partial credit against an AND query it does not satisfy:

```
ts_rank(to_tsvector('english','supplier indemnity only nothing else here'),
        websearch_to_tsquery('english','supplier indemnity clause liability cap contract policy'))
  = 0.0991032    -- while @@ returns false
```

So the old `order by rank desc` was still a lexical ordering. Simulating both orderings over the same
scoped rows and comparing the top 4 that survive the budget, **2 to 3 of 4 records are identical**
across all six agents (legal 2/4, followup 2/4, marketing 2/4, fraud_analyst 3/4, qa_manager 3/4,
supplier_verification 3/4).

The honest statement of the defect is therefore narrower and sharper: retrieval was ranking, but it
could not *fail*. There was no state in which the runtime knew that nothing on-topic existed, because
`or true` guaranteed a full slice and no field distinguished a match from a filler. The fix's value
is not that it fetches better rows — it changes 1–2 of 4 — it is that a miss becomes visible.

## 3. A third break the brief never named

The pre-fix department arm was `dept_key = p_dept` (`v3_context_assembly.sql:42`). Counted today:

| dept | rows at `dept_key = dept` | rows at `dept_key = any(fn_dept_scope(dept))` |
|---|---|---|
| legal | 83 | 94 |
| assurance | **0** | 246 |
| customer_experience | **0** | 92 |
| data_intel | **0** | 170 |
| growth | **0** | 179 |
| marketplace | **0** | 420 |

5,229 `ops_knowledge` rows sit on 22 department keys that are no longer active departments. Under
exact-key matching, five of six departments retrieve **zero** department knowledge. (The repair
comment says 5,775 rows; the measured figure is 5,229 over 6,206 rows carrying any `dept_key`.)

**I cannot establish whether this was true during the certification run.** `org_agents` has no
`updated_at`, `org_departments` has no `created_at`, and no migration row records the department
rename. The reorg is untracked working-tree SQL. So this is a real break present now, closed by the
merge arm — not a proven contributor to the 1,706.

## 4. The assembled context, layer by layer

`fn_agent_context_v3('legal', null, '<legal task>', null, 24000)` returns these keys. Measured, not
described:

| key | what it returns | measured for `legal` |
|---|---|---|
| `identity` | agent, dept, charter, north star, manager, packaged role ids, canonical role, owned/forbidden decisions, handoff + escalation targets, committees, per-action-class authority (most restrictive tier wins) | 2 packaged role ids |
| `company_objective` | up to 8 `company_goals`, own department first, Financial first | — |
| `deterministic_rules` | `authority`/`kpi`/`decision_playbook`/`policy` rows, structured, never rank-filtered, `limit 60` | **60** |
| `company_core` | `fn_context_slice`, budget 24000/6 = 4,000 chars | 2 records, 3,600 chars |
| `department_knowledge` | slice over `fn_dept_scope`, budget 24000/3 = 8,000 | 4 records, 7,200 chars |
| `role_knowledge` | slice over packaged role ids, budget 8,000 | 4 records, 7,200 chars |
| `category_knowledge` | slice on `category_key`, budget 4,000; `[]` when no category passed | 0 (none passed); 2–3 with a category |
| `validated_experience` | `agent_knowledge`, `validation_status='validated'` only, unexpired, top 8 | — |
| `live_data_required` | `record_type='live_data_binding'` — the binding, never a cached value, limit 12 | — |
| `tools` | `org_action_executor` rows the agent may run, limit 30 | — |
| `knowledge_ids` / `knowledge_count` | every record id the assembly used | 70 |

Candidate pool versus delivered, same call: role 10 scoped / 10 candidates / **4 delivered**;
department 94 / 94 / **4**; company_core 54 / 48 / **2**. The binding constraint is the character
budget, not the query — 8,000 chars ÷ 1,800 per record = 4. The OR query restores *ranking*, and on a
94-row layer it excludes nothing.

**Retrieval is 100% lexical.** `ops_knowledge` has no embedding or vector column — only
`embedding_status` (text: `pending` 4,511, `not_required` 3,745). No V3 path can substitute an
embedding guess for a deterministic rule, because no embedding exists to substitute. The
`deterministic_rules` block is additionally a structured SQL read that never touches `tsv`.

## 5. Acceptance evidence

Captured **while the fix was live**, ~14:05–14:10 UTC.

**Role knowledge for role tasks / department knowledge for department tasks.** `fn_retrieval_probe`
across legal, qa_manager, marketing, followup, supplier_verification, fraud_analyst: every agent
returned `knowledge_count` 69–70, role 3–4, dept 4, rules 60, `total_matched` 9–10, `has_gap=false`,
`gap_layers=[]`. Every delivered narrative record carried `match:"query"`.

**Category knowledge for category tasks.** `fn_agent_context_v3('spec_commercial', …,
'010_electrical-suppliers', 24000)` returned 2 category records; joining each `record_id` back to
`ops_knowledge`, both carry `category_key='010_electrical-suppliers'`. No other category's rows
appeared. Same for `002_steel-and-reinforcement-suppliers` (3), `009_hvac-suppliers` (2),
`005_waterproofing-suppliers` (2).

**Unrelated-role knowledge excluded.** `fn_retrieval_leak_check` on 8 agents (legal, qa_manager,
marketing, followup, supplier_verification, fraud_analyst, category_curator, spec_commercial):
`foreign_role_records = 0`, `clean = true` on all 8.

**Missing knowledge produces a signal, not silence.** Nonsense task
`'zzqq xylophone quokka nurburgring'` for legal and marketing: `has_gap=true`,
`gap_layers=["company_core","department_knowledge","role_knowledge"]`, and the instruction present —
"NO retrieved knowledge matched this task. You are working from general departmental material only.
Say so explicitly, and request, research or escalate rather than answering as if you had specific
guidance." Records were still delivered (4–6 per layer) labelled `match:"fallback"` — a labelled
fallback, not an empty prompt.

**Budget and duplicate suppression.** Per-record cap 1,800 chars; running-sum window per layer;
layer budgets 4,000/8,000/8,000/4,000 of a 24,000 default. Delivered totals hit 3,600/7,200/7,200 —
under budget in every layer. Dedup is `distinct on (coalesce(nullif(title,''), record_id))`, keeping
query-matched then higher-ranked then later `effective_date`. Duplicate titles it removes from the
scoped pool: marketplace 47 of 420, growth 20 of 179, assurance 11 of 246, legal 10 of 94,
customer_experience 10 of 92.

## 6. Still broken — the Stage 4 fix is NOT live

**Both halves were reverted on staging during this session.** At 14:17:15 UTC:

- `fn_context_slice` md5 `82d30b25e54973a8cab69624d20a69c8` — body is byte-identical to
  `scripts/sql/org_reorg_04_runtime.sql:27–59`. It carries the merge arm **and**
  `and (p_q is null or tsv @@ p_q or true)` at line 46. No `match`, no `stale`, no dedup, no
  labelled fallback.
- `fn_agent_context_v3` — `pg_get_functiondef` now contains `websearch_to_tsquery` and no longer
  contains `fn_task_tsquery`. Body matches `org_reorg_04_runtime.sql:67`.

Cause is a two-files-one-routine collision: `fn_context_slice` is defined in
`v3_repair_03_retrieval.sql:34`, `v3_context_assembly.sql:19` **and** `org_reorg_04_runtime.sql:27`;
`fn_agent_context_v3` in `v3_repair_05_ctx_v3_query.sql:13`, `v3_context_assembly.sql:63` **and**
`org_reorg_04_runtime.sql:67`. Deploy order decides the winner, and the reorg file won.

Consequences measured after the revert:
- `fn_knowledge_gap` reads `e->>'match'='query'`. With no `match` key emitted, `total_matched` is
  **0 on every task** and `has_gap` is **true on every task** — a signal that can no longer *not*
  fire. Verified: legal, qa_manager, marketing, cfo, onboarding all report `matched=0, has_gap=true`
  on on-topic tasks.
- The regression harness would catch it. `scripts/checks/v3_remediation_regression.mjs:157–171`
  asserts `total_matched > 0` for three on-topic probes. Run now: cfo 0/11, qa_manager 0/11,
  onboarding 0/10 — **three failures**. Its fourth probe (`total_matched === 0` for a nonsense task)
  now passes vacuously and proves nothing.
- Redeploy `v3_repair_03` then `v3_repair_05`, in that order, after any reorg SQL — or fold the merge
  arm into `v3_repair_03` and delete the duplicate definitions. The harness must run *after* the last
  deploy of the session, not after Stage 4.

**A grep is not a verification.** My first check flagged `has_or_true = true` on the fixed function —
a false positive on its own comment, "No \`or true\`". Only reading the full `pg_get_functiondef`
distinguished the two.

## 7. Also not done

- **No jurisdiction filter beyond the column.** All 8,256 rows have `jurisdiction` populated with
  exactly **1 distinct value**. Nothing in `fn_context_slice` or `fn_agent_context_v3` reads it. A
  filter today would be a no-op; it becomes real the first time a second jurisdiction is ingested,
  and nothing warns when that happens.
- **Freshness is carried, not enforced.** `review_after` is set on 3,959 of 8,256 rows and **0** are
  past `current_date`, so the `stale` flag would be false on every row even when the fix is live. The
  flag is untested against a true case and no path down-ranks, excludes or escalates on it.
- **Not measured:** production. Every figure above is staging only. Per the promote rule, a `--promote`
  carries the routine body and not its grants, so the `revoke`/`grant` lines in `v3_repair_03` need
  separate confirmation on production.
- **Not measured:** whether any of this moves the certification score. The runtime was not re-run,
  and re-running it internally would not certify it in any case.
