# Row #3, part 8 — opening brief: THE SIX KNOWLEDGE PACKS

Row #3 spec: `docs/specs_row3_executive_ui.txt`. Scorer: `scripts/staging/verify_os2_blueprint.mjs`.
State: `docs/sessions/ROW3_STATE.md` (session 6 section is at the top).

**Row #3 measured 2026-08-10 06:50 UTC: 120/152 (79%), 0 errored, 0 regressions.**
Re-measured after the post-close work: same 120, byte-identical MET set.

---

## 0. READ THE CLOCK BEFORE ANYTHING ELSE

```sql
select now() at time zone 'utc';
```

Four sessions in a row were opened minutes after the previous one closed and told that crons "had
fired". Dubai is UTC+4; the local date rolls over four hours before the database's does.
**Query `cron.job_run_details`. Never take a cron table in a brief on faith.**

A **partial scorer run is not a score.** One run this session reported 103 because it was killed by
its own timeout at check 130 of 152, and the sixteen "regressions" were checks that never executed.
Check for the `SPEC FILE #3 … : N/152` summary line before believing a number.

---

## 1. THE PACKS, AND WHAT IS ACTUALLY DEPLOYED

All six are in `C:\Users\Opera\Downloads\`, dated `v2026.07.31`. Nothing was extracted into the repo:
27 MB of zipped corpus does not belong in git. Extract to a scratch directory and stream from there.

| pack | what is in it | what production has | verdict |
|---|---|---|---|
| `QuotesDone_ALL_KNOWLEDGE_86_CATEGORIES` — **routing half** | 86 operational routes, crosswalk, EN/AR alias lexicon, route tests | `kb_operational_route` **86**, `kb_operational_alias` **4,212**, `kb_operational_route_map` **426**, `kb_operational_route_test` **344**, `v_kb_operational_86_coverage` **86 of 86 MAPPED** | **DEPLOYED** |
| `QuotesDone_ALL_KNOWLEDGE_86_CATEGORIES` — **knowledge half** | 67 package zips (66 broad + 1 lifts supplement), 1,066 JSONL files, **213,198 records** | **ZERO.** `select count(*) from kb_chunks where citation ilike '%QD-KB%'` → **0** | **NOT DEPLOYED** |
| `QuotesDone_COMPANY_OPERATIONS_KNOWLEDGE` | 24 departments, 96 roles, 236 SOPs, 240 decision rules, 18 cross-department workflows, 132 handoffs, 100 event subscriptions — **7,918 JSONL records over 228 files** | `org_departments` **15**, `org_agents` **67**, `workflow` **14**, `event_subscription` **53**, and **0** rows carrying an `ops-…` record id | **NOT DEPLOYED** |
| `QuotesDone_AI_AUTONOMY_MODEL_ROUTING_AND_TOOLS_PACK` | 32 task classes, 96 target-employee policies, 24 current-agent policies, 14-model catalogue, 22-row tool/connector matrix, reference routing SQL | `model_policy` **38 rows**, of which only **10 of the pack's 32 task classes** exist | **PARTIAL — 10 of 32** |
| `QuotesDone_COMPLETE_OS_PORTALS_AUTONOMY_UPDATE_PACKAGE` | 48 files: executive audit, frontend repo audit, reconciled target architecture, priority roadmap, acceptance gates, current API action inventory, deployment/rollback | not a data pack — read `01_MASTER/07_ACCEPTANCE_GATES.md` and check each gate against production | **UNASSESSED** |
| `QuotesDone_CLAUDE_INGESTION_INSTRUCTIONS` + `QuotesDone_CLAUDE_COMPANY_OPERATIONS_INGESTION` | staging schema SQL, importer templates (`.ts`), validators (`.py`), schema-mapping guide, acceptance checklists, OpenRouter reduction plan | these are the **HOW** for the four above | **METHOD** |

### THE ONE SENTENCE THAT MATTERS

**The map is deployed and the territory is not.** `kb_operational_route_map` holds 426 rows that
name package zips — `package_zip: "QD-KB-001-construction-civil-building-materials-v2026.07.31.zip"`
— and **not one record from any of those 67 packages is in the database**. All 86 live supplier
routes resolve to knowledge that was never ingested.

`kb_chunks` does hold 5,139 rows across 289 categories, but they are a **different corpus**: their
citations read "UAE Knowledge Library", "Researched by QuotesDone (Claude)", "DEWA", "SIRA", "RTA",
"ADCD". Useful, and not these packs. Do not let the 5,139 be mistaken for coverage.

---

## 2. HOW THE PACKS SAY TO INGEST THEM — FOLLOW IT

From `02_TOKEN_EFFICIENT_METHOD.md`, and it is the right instruction:

> Claude should understand the importer and the schema. Claude should **not** consume the corpus text
> as conversation tokens.

1. Read the compact manifest, schema, QA and crosswalk — **never the corpus**.
2. Write ONE local importer; stream each JSONL from disk; validate in code; upload in batches.
3. Store file hashes and resume checkpoints so a killed run resumes instead of restarting.
4. Return only counts, errors and test results.
5. Embeddings **only** for changed narrative records.

**Explicitly forbidden by the pack**: pasting master markdown into chat, summarising every department
before import, embedding SOPs/decision rules/KPIs unless retrieval genuinely needs them, regenerating
records that already have stable IDs.

213,198 records at even 200 tokens each is ~43M tokens. Reading the corpus into the conversation is
not slow — it is impossible. The importer is the deliverable.

### Import order (`03_IMPORT_ORDER.md`), abbreviated

checksums → source registry → package version + ingestion run → company-core → department registry +
production crosswalk → roles + current agent mappings → department knowledge → SOPs → decision rules
→ exception playbooks → workflows + handoffs → event subscriptions → live-data bindings → KPIs →
scenario tests → resolve the supplier-corpus dependency → embeddings for narrative only → **run tests
and STOP before production activation**.

That last step is the pack's own instruction, not a suggestion.

---

## 3. WHAT TO WATCH FOR, FROM THIS SESSION'S EVIDENCE

- **`org_departments` is 15 and the pack has 24.** Nine departments would be new. `fn_evolution_scan`
  already reports four departments holding ≥5 open tasks with nobody running them. Adding nine more
  department rows without staffing them makes that number worse, not better. Import the registry,
  but do not silently create employees to fill it.
- **`org_agents` is 67 and the pack targets 96 roles.** **56 of the current 67 have not run in 30
  days.** Adding 29 more dormant employees would make every per-employee universal in Row #3 harder,
  which is correct if the roles are real and dishonest if they are not. Decide before importing.
- **`model_policy` has 38 rows over 38 classes but only 10 of the pack's 32 task classes.** The other
  22 are the interesting ones: `document_extraction_multimodal`, `drawing_and_boq_analysis`,
  `redaction_detection`, `speech_transcription`, `marketing_image`. Check what each of those paths
  routes to **today** before overwriting a live policy.
- **OpenRouter has ~3 days of balance.** The pack ships an OpenRouter reduction plan
  (`05_OPENROUTER_REDUCTION_PLAN.md`) — read it before generating a single embedding. Embedding
  213,198 records is a spend decision and it is the founder's, not the session's.
- **Every SECURITY DEFINER function you create gets `EXECUTE` granted to `PUBLIC` automatically** and
  raises `anon_security_definer_function_executable`. Revoke in the same migration. Production is at
  58 and the frontend makes **zero** direct `.rpc()` calls, so nothing browser-side needs any of them.

---

## 4. ROW #3 — WHERE IT STANDS

**120/152.** The 32 still red, by what blocks each:

- **7 are dates.** `s33-replay-six-tracks` 23:55 nightly · `explain-knowledge-used` ~14 Aug ·
  `s21-no-polling` ~13–16 Aug · `time-machine-restores-six-dimensions` ~24 Aug ·
  `s36-recommendation-seven-fields` ~9 Sept · `exec-meeting-priorities-agreed` late Sept ·
  `time-machine-scrub` ~Feb 2027.
- **5 need a real customer.** `customers` = 0 and `inquiries` = 0.
- **4 need the workforce to work.** 56 of 66 employees have not run in 30 days.
- **5 are founder decisions.** Apify, media budget, invites, a keyword-volume feed, founder usage.
- **11 cannot be closed honestly today** — a missing column or invented data. `s24` is scoped to a
  single guarded `perform fn_board_review(p_kind, v_dr_id::text)` in `fn_decide` and was left because
  it cannot flip before ~9 Sept and `fn_decide` gates money approvals.

**The single biggest lever is not a check.** It is the `audit_gap` proposal the company raised itself
at 06:00 on 10 Aug: 44 of 66 employees dormant, four departments with open work and nobody running,
13 departments with two or more wholly dormant employees. That one decision unblocks four Row #3
checks and drains 43 of the 85 stranded handoffs.

---

## 5. OPEN ESCALATIONS — CARRY THESE FORWARD

1. **OpenRouter $11.87** at 07:15 on 10 Aug, ~$3.96/day, ~3 days. `agent_brain` is 93%.
   `cost_snapshot` fired its own low-balance alert at 07:00.
2. **`anon_security_definer_function_executable` = 58.** The repository-side pass is done: the
   frontend makes **zero** `.rpc()` and zero `rest/v1/rpc` calls, and all four API edge functions use
   the service role only. Whether an external integration calls PostgREST with the anon key is a fact
   only the founder holds. The one-command close is in `ROW3_STATE`.
3. **34 gated authorities over 14 employees, none on probation** — residue from a scoring bug that
   has been fixed, on ordinary classes (`health_report` gated for 2, autonomous for 7). Two are
   `money_verify` and `invoice_review`, so restoring is a money-path widening.
4. **`agent_brain` runs seconds from its timeout**: 425 calls in 7 days, 28 over 45 s, 7 failures,
   and until 10 Aug every one wrote `status:'ok'`. Now recorded truthfully. **No context cap was
   imposed** — that is a quality decision. The `repeated_failure` trigger will now raise it.
5. **The 226 split-address leads** and re-enabling invites (13.3% bounce, hard cut-off 8%).

---

## 6. HOW THIS SESSION IS WORKED

One row at a time. Everything deploys to **BOTH** Supabase projects — production
`htdblwldjkcgjvmqkbeh` and staging `pglpqrhvozwepymcuunn`. Verified by **EXECUTION** in the same
turn, never by typecheck or by reading. Committed and merged via PR.

A MISSING verdict is a BUILD ORDER, never an argument that something existing already covers it.
Never fabricate, back-date or mass-close data to turn a gate green, and never weaken a check. If a
change makes a check HARDER because the old pass was false, that is correct — say so.

**VERIFY THE VERIFICATION.** Assert on a 200 **and** on a non-zero effect. This session's aborted-
transaction probe pattern works well: do the write, count the effect, `raise exception` with the
counts so the whole thing rolls back and the numbers still come out. It caught a real failure —
`knowledge_exam` returned HTTP 200 with `examined: 0`, and the probe correctly failed.

**DO NOT REBUILD WHAT EXISTS.** Three things this session turned out to be already built: the four
structural questions in `fn_evolution_scan` (they had simply never run), `outcome.graded` inside
`fn_outcome_evaluate`, and the whole 86-route crosswalk. Read section 1 and `ROW3_STATE` section 3
before building anything.
