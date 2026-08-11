# THE WORD-BY-WORD AUDIT — 2026-08-11

Production `htdblwldjkcgjvmqkbeh` · staging `pglpqrhvozwepymcuunn` · clock **2026-08-11 12:22 UTC**
(Dubai 16:22) · measured 12:22–16:10 UTC.

**No verdict in this report is taken from a scorer.** The 152-check instrument was deliberately not
run: it reported 126/152 *rising* in a session that added five redundant function definitions and
left 96 unresolvable identity rows in place, and that is the reason this audit was commissioned.

---

## THE COUNT

| verdict | count | share |
|---|---|---|
| **PRESENT** | **423** | 47.6% |
| **PARTIAL** | **279** | 31.4% |
| **ABSENT** | **171** | 19.3% |
| **CONTRADICTED** | **15** | 1.7% |
| **total claims audited** | **888** | |

The 15 file-level CONTRADICTED verdicts dedupe to **14 distinct defects** (two span more than one
spec file).

### By spec file

| # | file | lines | PRESENT | PARTIAL | ABSENT | CONTRA | claims | had a scorer? |
|---|---|---|---|---|---|---|---|---|
| 1 | `quotesdone archeticture.txt` | 372 | 41 | 17 | 6 | 1 | 65 | yes, not run |
| 2 | `OS.txt` | 507 | **52** | 8 | 2 | 0 | 62 | yes, not run |
| 3 | `OS 2.txt` | 1,147 | 63 | 71 | 39 | 3 | 176 | the 152 checks — **not run** |
| 4 | `customer portal.txt` | 895 | 24 | 27 | 11 | 0 | 62 | yes, not run |
| 5 | `supplier portal.txt` | 884 | 31 | 24 | 9 | 1 | 65 | yes, not run |
| 6 | `suppliers categories.txt` | 1,007 | **82** | 14 | 8 | 0 | 104 | yes, not run |
| 7 | **`quotesdone agents and knowledge.txt`** | 1,498 | 92 | 71 | 63 | 6 | **232** | **never had one** |
| 8 | `open router.txt` | 2,347 | 38 | 47 | 33 | 4 | 122 | yes, not run |
| | **total** | **8,657** | **423** | **279** | **171** | **15** | **888** | |

**Best implemented: #2 (84% PRESENT) and #6 (79%).** **Worst: #8 (31%) and #3 (36%).**

### The six packs

All six `QuotesDone_*_v2026.07.31.zip` are present and ingested. `model_policy_by_identity` (120
rows) and `model_catalog` (14) both carry `package_version = v2026.07.31`; `kb_chunks` holds
**115,148 rows of `source_kind = 'qd_kb_pack'`**. Ingestion is real. **Retrievability is not** — see
contradiction #1.

---

## THE FILES

| file | contents |
|---|---|
| [`01_02_architecture_and_os.md`](01_02_architecture_and_os.md) | specs #1 and #2 |
| [`03_executive_ui.md`](03_executive_ui.md) | spec #3, audited without its scorer |
| [`04_05_portals.md`](04_05_portals.md) | specs #4 and #5 |
| [`06_supplier_categories.md`](06_supplier_categories.md) | spec #6 |
| [`07_agents_and_knowledge.md`](07_agents_and_knowledge.md) | **spec #7 — the file that never had a scorer** |
| [`08_openrouter.md`](08_openrouter.md) | spec #8 |
| [`02_duplicates.md`](02_duplicates.md) | task 2 — the duplicate register |
| [`03_functions_and_empty_tables.md`](03_functions_and_empty_tables.md) | task 3 — both readings |
| [`04_contradictions.md`](04_contradictions.md) | task 4 — the 14 contradictions |

---

## THE TEN THINGS THAT MATTER MOST

Ordered by consequence.

1. **The knowledge base is searched by keyword, not by meaning.** Five of six retrieval routines use
   full-text; the one semantic routine (`kb_match`) is not the one agents call. And only **39% of
   `kb_chunks` is embedded** — 73,488 chunks have no vector, including **0%** of `trade` and **0%**
   of `regulation`. The pack scorecard's "100% ingested, 37 of 37 in use" is true and measures
   neither of those words.

2. **OpenRouter's distribution is inverted, with ~32 hours of credit left.** Premium is **38.1% of
   calls and 84.8% of cost** against a stated 5% target — 7.6×. Balance **$8.68** at $0.27/h.
   *Money is the founder's call; the engineering point is that all three mechanisms that would cut
   the burn are already built and none is returning anything.*

3. **The LLM cache is complete, configured on all 61 policies, and holds 1 row / 2 hits / $0.00.**
   2 of 1,642 calls were hits. The cheapest available saving; nothing needs designing.

4. **Model cascading cannot run and building it now would cost more.** Confidence is reported on
   **5 of 1,642 calls** and on **0 of 622 sonnet-5 calls**. The output contract must carry a
   confidence first.

5. **`model_policy_by_identity`: 96 rows resolving to nothing, on both projects.** Instance 5 of the
   recurring root cause. **48 of the 96 already match a slugified department name** and fail only on
   `&` vs `and` — the fix shape (`org_agent_alias` + `fn_org_agent_resolve` at the write boundary)
   is already in this codebase.

6. **Nine of fourteen contradictions are one defect:** an instrument reporting on something other
   than what it appears to measure, with no surface separating *measured zero* from *never measured*.
   19/19 scenarios is a staffing check. Observability healthy is no events. Company Health high is
   55 of 63 goals with no measure. BOTH PROJECTS IN SYNC is 418 = 418 tables while **staging holds
   255 empty tables against production's 96**, `board_advisor` **0 vs 7**, `workflow_run` **7 vs
   198**.

7. **96 of 418 tables are empty — the whole demand side.** `customers` 0, `inquiries` 0, `quotes` 0,
   `transactions` 0, and **20,470 leads of which 6 are claimed and 0 approved**. Both portals are
   fully built and neither has served its user. **No code change fixes this.**

8. **28,521 of 120,530 `kb_chunks` are byte-identical duplicates (23.7%)**, plus 1,197 in
   `ops_knowledge` (30%) and 675 duplicate supplier phone numbers. Directly contradicts spec #7
   L543. Invisible to `fn_kb_corpus_integrity`, which hashes against the ingest manifest — identical
   content from two source files passes.

9. **`sec()`, the credential reader, is copy-pasted into 134 of 198 edge functions** (`J()` 153,
   CORS 105). Two authentication holes were fixed in `cost_snapshot`'s own copy in July. There is no
   test that the 134 copies agree. `_shared/internal_auth.ts` proves the fix works —
   `requireInternal` has zero copies.

10. **Exactly one function in 698 is dead** (`fn_simulate_growth`). Of the four that looked dead,
    three are load-bearing — `fn_enforce_rls_on_new_tables` is a **live event trigger**, and dropping
    it would silently stop RLS on every table created afterwards.

---

## WHAT THE AUDIT FOUND THAT WAS ALREADY RIGHT

Reported because an audit that lists only failures misrepresents the system.

- **Spec #2 is 84% PRESENT.** 10 operating systems exactly as named, all 17 blueprint components
  populated, `os_objective` **50 of 50 measurable** across five horizons, **zero** responsibilities
  owned by two OSes, **zero** departments unmapped, a live event bus at 987 events in seven days, and
  the prohibition "no OS calls another directly" backed by an actual guard.
- **`org_agents.manager_key`: 93 of 94 set, every one resolving, hierarchy complete and acyclic.**
  100% referential integrity — in the same database that carries 96 rows resolving to nothing. It is
  the proof the identity problem is fixable.
- **Company Consciousness runs.** `company_reflect_nightly` at 21:30 UTC every night, unprompted, 14
  reflections stored. **Company Genome** is stored (`company_constitution` 20, `culture_principle` 8,
  `company_vision`, `company_economics` 10) and `fn_agent_context` really does emit it to every
  employee as Layer 1 — the inheritance clause, not just the storage.
- **The review chain is real.** `review_chain` 1,557 rows across 7 stages including `dept_review` and
  `cos_review` — the exact chain spec #1 describes — with 4 rejections, 8 revision requests and 43
  holds, and reasons on 1,290 rows. The Chief of Staff genuinely rejects work.
- **Knowledge governance is faithfully implemented.** `kb_revisions` 9,355, `fn_kb_submit_revision` →
  `fn_kb_gov_approve`, `fn_require_grounding`, `fn_knowledge_provenance_stamp`. Spec #7 L1405 —
  *"learning should propose updates rather than silently changing approved knowledge"* — is one of
  the most faithfully implemented sentences in the contract.
- **88 category agents each carry all 14 standardised knowledge modules**, against 86 catalogue
  categories. Spec #6 L820's "different for every supplier category" is actually delivered.
- **Autonomous Governance can actually pause itself** — all six monitored conditions have a routine,
  plus `fn_org_task_autonomy_brake`, `fn_phase1_disarm`, `fn_autonomy_dispose`.
- **The customer layout code treats the server's module order as a floor, not a whitelist**, so
  shipping a new module cannot make it invisible to existing customers. That is the failure mode of
  every server-driven layout, and this one was designed around it.

---

## WHAT WAS RE-MEASURED AND DID NOT REPRODUCE

Per the standing rule that brief **counts** are reliable and brief **diagnoses** are not:

| brief said | measured today |
|---|---|
| `model_policy_by_identity` "96 target-**employee** keys" | correct count; the `scope` value is `target_employee` and **48 of 96 already match a slugified department name** — the failure is `&` vs `and`, not 96 unknown identities |
| `ai_quality_snapshots.agent` 754 of 1,066 unresolved | **171 of 1,115 rows; 7 of 35 distinct keys** |
| `agent_expectations.agent` 29 of 36 unresolved | **108 of 121 — and not a defect**: the column holds cron job names, the same vocabulary as `agent_runs` |
| prompt caching "roughly break-even" at R/W 0.216 | **0.115 over the full 7 days** against a 0.278 break-even — losing money, not marginal |
| 191 edge functions | **198** |
| OpenRouter ~$9.27 | **$8.68** at 12:24 UTC (150 credits − 141.32 used); the $0.27/h rate is confirmed |

Reproduced exactly: 36 duplicated SQL functions / 172 distinct / 230 definitions; 89 no-table
routines and 145 extension-owned; 55 of 63 goals without `measure_sql`; 25 departments / 94 agents.

---

## END-OF-SESSION SWEEP

| check | result |
|---|---|
| GitHub Actions, last 12 runs | **all success**, no zero-step (quota) jobs |
| `scripts/checks/project_parity.mjs` | **BOTH PROJECTS IN SYNC** — 197 edge fns, 418 tables, 843 functions, 154 triggers, 0 tables without RLS, 56 anon-executable SECURITY DEFINER — **and see contradiction #6: this is a shape check** |
| Supabase advisors (production, security) | 614 advisories, **0 at ERROR**: 448 INFO `rls_enabled_no_policy`, 59+56 WARN security-definer-executable, 48 WARN `function_search_path_mutable`, 3 WARN `extension_in_public` |
| OpenRouter | **$8.68**, ~$0.27/h, ~32h. Low-balance alert firing (threshold $20). **Founder's call.** |

---

## THE HONEST BOTTOM LINE

**47.6% of the contract is PRESENT with a named artefact.** Almost a third is PARTIAL — and the
dominant reason is not missing code. It is that **the marketplace has no demand side**: 96 empty
tables, 0 customers, 0 inquiries, 0 quotes, 6 claimed suppliers of 20,470 and none approved. The
customer portal, the supplier portal, the RFQ workflow, quote comparison, the observability trace and
nine of fourteen workflows are all **built and unexercised**.

The 171 ABSENT verdicts are genuine build orders. The 14 CONTRADICTED are the ones to fix first,
because each one is currently reporting success.

**The score rose while the codebase got worse because the instruments measure the wrong subject.**
That is not a scorer bug to patch — it is a rule to adopt: *a surface may not report a number derived
from an empty table, an unmeasured goal or an unexercised mechanism without saying so.*
