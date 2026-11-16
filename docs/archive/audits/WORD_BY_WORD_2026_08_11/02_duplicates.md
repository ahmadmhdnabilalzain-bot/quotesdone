> **Archived 16 Nov 2026** (simplification wave B, it_engineer): it describes the word-by-word audit of 11 Aug 2026, of the organisation before the 7-8 Sep 2026 deletions. 22 of the 43 routines it names are gone from production (SELECT pg_proc, 16 Nov 2026). History, not the build today.

# TASK 2 — THE DUPLICATE REGISTER

Repo and Supabase. Measured 2026-08-11 12:40–13:20 UTC.

---

## 2.1 The policy decision the brief asked for — stated

> "Either the `.sql` files are an append-only migration log (in which case duplicates are expected)
> or they are the source of truth (in which case 36 need collapsing)."

**They are an append-only log, and the finding is that nothing records what was applied.**

Evidence:
- `scripts/apply_sql.mjs` takes **one named file** and applies it. It writes no ledger row, no hash,
  no timestamp. Its output is `applied to staging …` / `applied DDL to production …` and nothing
  else.
- **Nothing replays `scripts/sql/*`.** No script, no workflow, no `supabase db push` over that
  directory. `supabase/migrations/` holds **3 files**; `scripts/sql/` holds **276**.
- There is therefore no way, from the repo alone, to know which of the five `trg_action_gate`
  bodies is the one running.

**So the rule is "newest wins on apply, older copies are historical" — and it must be written down,
because the repo currently reads like a source of truth.** Collapsing the 36 would destroy the only
record of why each change was made; the honest fix is not deletion but a header line in each file
naming what it supersedes, plus a check that the newest copy matches the live body.

**The live database is the only source of truth for function bodies.** That is a real operational
risk and it is stated here as the finding, not as an aside.

---

## 2.2 SQL function definitions — reproduced exactly

```
distinct functions:                        172
total definitions:                         230
defined more than once:                     36
definitions belonging to duplicated fns:    94
redundant copies (94 − 36):                 58
.sql files:                                276
```

Worst offenders, with the commit date of each copy:

| function | copies | files (newest first) |
|---|---|---|
| `trg_action_gate` | 5 | `gate_records_the_alternative_it_rejected.sql` (11 Aug 14:41), `action_gate_records_confidence.sql` (11 Aug 13:44), `escalation_names_a_party.sql` (6 Aug 17:35), `decide_routes_to_a_party.sql` (6 Aug 16:30), `action_gate_records_sources.sql` (6 Aug 15:51) |
| `fn_agent_context` | 5 | `fn_agent_context_reads_ops_projections.sql` (10 Aug 16:43), `fn_agent_context_genome.sql` (10 Aug 05:21), `escalation_names_a_party.sql` (6 Aug 17:35), `fn_agent_context_os_layer.sql` (6 Aug 15:51), `fn_agent_context_employee.sql` (6 Aug 10:13) |
| `fn_what_if` | 4 | `simulation_action_carries_its_evidence.sql` (11 Aug 15:06), `what_if_result_carries_confidence.sql` (11 Aug 14:59), `simulation_offers_the_action.sql` (11 Aug 14:52), `what_if_measures_the_cache.sql` (11 Aug 14:52) |
| `fn_ws_exec_home` | 4 | `fn_ws_exec_home_company_at_work.sql` (10 Aug 14:32), `console_six_boards.sql` (10 Aug 01:06), `fn_ws_exec_home_employees_working.sql` (10 Aug 06:02), `fn_ws_exec_home.sql` (9 Aug 14:31) |
| `fn_decide` | 3 | `escalation_names_a_party.sql`, `decide_routes_to_a_party.sql`, `fn_execution_run.sql` |
| plus 31 more at ×2–×3 | | `fn_ws_operations`, `fn_ws_governance`, `fn_ws_company_os`, `fn_task_lesson`, `fn_should_escalate`, `fn_reputation_recompute`, `fn_os_command`, `fn_llm_log`, `fn_exec_meeting`, `fn_evolution_scan`, `fn_ea_agenda`, `trg_company_event_dispatch`, `fn_workflow_step_sweep`, `fn_task_review`, `fn_owning_os`, `fn_org_task_execute_sweep`, `fn_ops_department_context`, `fn_opportunity_scan`, `fn_kb_route_decide`, `fn_improvement_plan_refresh`, `fn_handoff_answer`, `fn_graph_rebuild`, `fn_event_consolidate`, `fn_emit_metric_alerts`, `fn_decision_gate`, `fn_budget_rollup`, `fn_ai_route`, `fn_ai_gate`, `fn_agent_inbox_closable_kinds`, `fn_agent_handoff_inbox`, `fn_action_queue_sweep` |

**Four of the five `fn_what_if` copies and two of the five `trg_action_gate` copies were written on
11 August — the same session that reported the score going up.** That is the brief's point,
confirmed: the redundancy is being produced now, not inherited.

---

## 2.3 Duplicates in the live database — one, and it is benign

Only **one** function name in `public` has more than one live definition:

| signature | bytes | verdict |
|---|---|---|
| `fn_agent_context(p_agent_key text, p_max_chars integer)` | 34,892 | base |
| `fn_agent_context(p_agent_key text, p_max_chars integer, p_query text)` | 2,394 | **correct decorator** |

The 3-argument body's first statement is
`out := public.fn_agent_context(p_agent_key, p_max_chars);` and it then appends LAYER 2b and 2c.
This is an intentional overload, not a duplicate. **No verdict against it.**

The separate defect it exposes — that 9 of 11 callsites use the 2-argument form and so silently
lose the department knowledge layer — is recorded in spec #7 §4, not here.

**So the 58 redundant copies in `scripts/sql/` produced exactly zero redundant definitions in
production.** The duplication is a readability and provenance problem, not a runtime one.

---

## 2.4 Edge function duplication — the largest copy-paste surface

**198 edge functions** (the brief said 191; it has grown). `supabase/functions/_shared/` contains
exactly **four** modules: `attachment.ts`, `attachment.test.ts`, `internal_auth.ts`, `llm.ts`.

| helper | files carrying their own copy | shared module exists? |
|---|---|---|
| `createClient(Deno.env.get(...))` | **178** | no |
| `const J = (o, s = 200) => new Response(...)` | **153** | no |
| `async function sec(k: string)` — reads `app_secrets` | **134** | no |
| `Access-Control-Allow-Origin` literal | **105** | no |
| `requireInternal` | 0 copies — **imported** from `_shared/internal_auth.ts` | **yes** |

`requireInternal` is the proof that the pattern works: one module, zero copies. `sec()` is the one
that matters most — it is a **credential reader**, duplicated 134 times. The `cost_snapshot` history
in that file records two separate authentication holes fixed in its own copy of the gate (19 Jul and
27 Jul 2026). **Every fix to a copied `sec()` has to be found and repeated 133 times, and there is
no test that they agree.**

This is the highest-value consolidation in the repo and the only duplicate class with a security
dimension.

---

## 2.5 React / UI duplication

The entire OS console is **two files**: `src/components/osx/OsxShell.tsx` (**3,347 lines**) and
`ControlMode.tsx`. Within `OsxShell.tsx` the repetition is real but bounded — the file already
factors its repeated patterns into `ReadableObject`, `RichList`, `KanbanBoard`, `BoardHeader`,
`SmartCell`, `StatTile`, `Chip`, `RecordDrawer` and a shared `FK_ENTITY` map, and the 31 modules are
a data array rather than 31 copies.

**Verdict: not a duplication defect.** A 3,347-line single file is a size problem, not a duplicate
problem, and splitting it is cosmetic. The one genuine repetition is that `<Escalations>` and
`<GovernanceApp>` name their payload fields by hand while `<OperationsApp>` and `<AssistantApp>`
delegate to `<ReadableObject>` — which is exactly why the 11 Aug `alternatives` work had to touch
two components instead of none. That asymmetry is worth removing; nothing else here is.

---

## 2.6 Duplicate cron jobs

**None.** 185 jobs (166 active, 19 inactive); **zero pairs share a command string**. Checked for
same-work-different-name by grouping on the command text — no group has more than one member.

---

## 2.7 Duplicate rows in the data — the findings the brief did not have

| table | rows | distinct | **redundant copies** | note |
|---|---|---|---|---|
| `kb_chunks` | 120,530 | 92,009 | **28,521 (23.7%)** | byte-identical `content` |
| `ops_knowledge` | 3,959 | 2,762 | **1,197 (30.2%)** | byte-identical `content` |
| `leads` (phone) | 20,355 with a phone | 19,680 | **675 (3.3%)** | on digits-only normalisation; 584 numbers appear more than once |
| `os_runbooks` | 106 | — | **21 duplicate titles** | |
| `agent_knowledge` | 2,040 | — | **5 duplicate (agent_key, topic)** | |
| `leads` (email) | — | — | **0** | clean |
| `org_agents` (agent_key) | 94 | 94 | **0** | clean |
| `org_departments` (name) | 25 | 25 | **0** | clean |

**`kb_chunks` is the headline.** Nearly a quarter of the knowledge base is a byte-identical copy of
another chunk. Three consequences, all measurable:

1. **It contradicts spec #7 L543 directly** — *"This approach avoids duplicated information."*
2. **It was paid for.** Every one of the 28,521 duplicates was embedded. Embedding runs on the free
   in-region `gte-small` model, so the cost is storage and index size rather than cash — but the
   retrieval cost is not free: `fn_kb_retrieve` and `kb_match` return duplicate chunks, so a
   top-k of 8 can spend several slots on the same text and crowd out genuinely different knowledge.
3. **It is invisible to every existing check.** `fn_kb_corpus_integrity` verifies hashes against the
   ingest manifest; identical content ingested from two different source files is *correct* by that
   test.

`leads` phone duplication matters for a different reason: `invite_daily_cap` is 10 against a
sendable pool of 16,238, and 675 of those rows are the same company reachable on one number. Inviting
both is the kind of thing a supplier notices.

---

## Register summary

| class | measured | verdict |
|---|---|---|
| `scripts/sql` redundant definitions | 58 across 36 functions | **expected under append-only, but the policy was never written down and nothing records what was applied** |
| live duplicate routines | 1 name, 2 signatures | **benign** — a correct decorator |
| edge function copied helpers | `sec()` ×134, `J()` ×153, CORS ×105, client ×178 | **real, security-relevant, fixable — `_shared/` already proves the pattern** |
| React duplication | 2 components name fields by hand vs 2 that delegate | **minor** |
| duplicate cron jobs | 0 | **clean** |
| duplicate data rows | `kb_chunks` 28,521; `ops_knowledge` 1,197; `leads` 675 | **the largest real duplication in the system, and unmeasured until now** |
