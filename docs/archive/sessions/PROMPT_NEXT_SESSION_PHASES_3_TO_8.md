# PROMPT FOR THE NEXT SESSION — PHASES 3 TO 8

Paste everything between the rules. It is self-contained: a new session has none of this context.

---

Read `docs/audits/WORD_BY_WORD_2026_08_11/README.md` first — it is the contract audit, 888 claims,
423 PRESENT / 279 PARTIAL / 171 ABSENT / 15 CONTRADICTED. Then
`docs/sessions/NEXT_SESSION_BRIEF_2026_08_12_REHEARSAL.md`, which carries the containment design and
what is already measured, so you do not re-derive it.

The specs are the contract, all eight:
```
C:\Users\Opera\OneDrive\Desktop\quotesdone archeticture.txt
C:\Users\Opera\OneDrive\Desktop\OS.txt
C:\Users\Opera\OneDrive\Desktop\OS 2.txt
C:\Users\Opera\OneDrive\Desktop\customer portal.txt
C:\Users\Opera\OneDrive\Desktop\supplier portal.txt
C:\Users\Opera\OneDrive\Desktop\suppliers categories.txt
C:\Users\Opera\OneDrive\Desktop\quotesdone agents and knowledge.txt
C:\Users\Opera\OneDrive\Desktop\open router.txt
C:\Users\Opera\Downloads\QuotesDone_*_v2026.07.31.zip   (all six)
```

Start with the clock: `select now() at time zone 'utc';` — Dubai is UTC+4.
Do **not** report the OpenRouter balance. I top it up; it does not gate your work.

The `quotesdone-session` skill applies automatically. **§10 is the one that matters most: never
state anything you are not 100% sure of, and never let a narrow check license a broad claim.** Three
diagnoses died on that rule last session — read them before you plan anything, because two of them
were about to cost a day each.

## FINISH FROM PHASES 1 AND 2 FIRST — three things, all small

1. **Verify Tier 0.4 actually landed.** `agent_brain` now calls `fn_agent_context_capped` instead of
   `fn_agent_context`. The RPC was verified (24,012 chars against a 24,000 budget, was 35,813) but
   the **token reduction was never observed** — two `pg_net` probes returned 401 against both
   `cred_fn_agent_brain` and `inbound_secret`, so the function never ran. Read
   `ai_cost_log.prompt_tokens where fn='agent_brain'` against the **24,619** seven-day baseline. If
   it has not moved, find out why before building anything else — `agent_brain` is 68% of all spend.
2. **Re-run the Row #3 scorer to completion.** It was last run mid-session at **126/152**, before
   the cache fix, `could_be_cheaper`, the context cap and the scenario fix. I am not claiming that
   number still holds.
3. **Finish 1.4.** A "no data yet" rule was applied to Executive Home (`goal_measured`), the
   scenario runner (`STAFFED` not `READY`) and `project_parity` (population line). It was not
   applied anywhere else. Any surface publishing a number derived from an empty table, an unmeasured
   goal or an unexercised mechanism must say so.

## PHASE 3 — identity. CHECK THE READER BEFORE YOU BUILD.

- **Do NOT alias the 96 `model_policy_by_identity` rows.** That was last session's plan and it was
  cancelled after measuring: `fn_ai_route` selects `scope = 'current_agent'` only, and
  `target_employee` is selected **nowhere**. They are not addressed to an unmodelled identity, they
  are addressed to a reader that does not exist. Decide with me: delete them as dead imported
  config, or wire a reader deliberately — per-employee routing changes the model for 94 employees
  and has a cost consequence.
- **The 44 legacy `cat:` keys in `agent_knowledge`.** 132 `cat:` keys exist; 88 carry all 14
  `knowledge_module_standard` modules and 44 carry none. **Apply the same discipline: find out what
  reads them before deciding to retire or migrate them.** `cat:aluminium-glass` and
  `cat:aluminium-and-glass-suppliers` are the same agent twice.
- `dept_key='knowledge'` is *Administration & Operations*; Knowledge Engineering is `knowledge_eng`.
  The mis-routed scenario is fixed and the trap is a column comment. Renaming the key is a migration
  — 155 `org_tasks` reference it — so only do it deliberately, not in passing.

## PHASE 4 — the dress rehearsal. This is the headline.

Full design is in `NEXT_SESSION_BRIEF_2026_08_12_REHEARSAL.md`. The essentials:

- **Containment before the first seed row. 19,903 leads carry real email addresses**,
  `enqueue_supplier_invites` / `fn_notify_supplier` / `run_no_quote_nudges` all work, and 10 of 56
  executors notify a human. Prove the block in an aborted transaction *before* seeding.
- **Extend the existing convention, do not invent one.** Demo fixtures have existed since 7 Aug:
  `ZZ DEMO — <name> (QuotesDone fixture, not a real company)` with an `@example.invalid` address.
  Six HVAC suppliers already exist, all `approval_status='pending'`. **Those six are the only reason
  `leads.claimed` is 6 — real claimed suppliers is zero.**
- Seed HVAC: 2 customers, 12 suppliers (6 exist, add 6), a project, 2 inquiries with a BOQ, 7
  quotes, award, reveal, refund, complaint, suspension.
- Drive spec #7's own observability trace (L1467–L1498) and **assert each step on a non-zero
  effect**, never on HTTP 200 — `quote_compare` returned `{ok:false}` at 200 for weeks.
- Then the second inquiry: **customer changes requirements after quotations are received** — spec #7
  L1351, one of the 13 exception scenarios with no coverage at all.
- **Teardown proof is score equality.** Run every scorer before seeding; run them again after
  teardown; they must match exactly. A moved score means teardown was incomplete or a gate counted
  demo data. Do not exclude demo rows by editing 152 checks.
- **The real deliverable is the list of tables the rehearsal could not reach.**

## PHASE 5 — fix what Phase 4 breaks

Not enumerable in advance and do not pretend otherwise. This flow has never run once end to end.
Expect real defects and expect them to be the useful ones.

## PHASE 6 — knowledge retrieval

- **Order matters.** Backfilling embeddings changes nothing while the routines agents call are
  full-text only. Five of six retrieval routines use FTS; `kb_match` is the only vector path and
  `fn_agent_context` does not call it. Make `fn_kb_retrieve` hybrid **first**.
- Then backfill: **only 39% of `kb_chunks` is embedded** — 73,488 have no vector, including 0% of
  `source_kind='trade'` (1,993) and 0% of `'regulation'` (45).
- **Dedupe `kb_chunks`: 28,521 of 120,530 are byte-identical copies (23.7%).** Invisible to
  `fn_kb_corpus_integrity`, which hashes against the ingest manifest.
- **Deliver Layer 4.** The contract's Layer 4 is *external* authority; the code's Layer 4 is internal
  learnings. `regulations` 17, `reg_catalog` 38, `compliance_sources` 17, `mdm_standards` 22,
  `mdm_manufacturers` 22 — **118 rows that reach no employee.**
- **The arity defect is still open:** LAYER 2b/2c only exist in the 3-argument overload, and **9 of
  11 callsites pass no `p_query`**, so 82% of callers get no department knowledge.

## PHASE 7 — hygiene

- **`sec()` — the credential reader — is copy-pasted into 134 of 198 edge functions.** `J()` 153,
  CORS 105. Two auth holes were fixed in `cost_snapshot`'s own copy in July and nothing tests that
  the copies agree. `_shared/internal_auth.ts` proves the pattern: `requireInternal` has zero copies.
  Highest-value item in this phase and the only one with a security dimension.
- Write the `scripts/sql` policy down — it is an append-only log, nothing records what was applied,
  nothing replays it, and the live database is the only source of truth for a function body. Add a
  check that the newest copy matches the live definition.
- Drop `fn_simulate_growth` — the only genuinely dead routine of 698. **Three of the four that
  looked dead were load-bearing**, including `fn_enforce_rls_on_new_tables`, a live EVENT TRIGGER.
- Dedupe `ops_knowledge` (1,197 of 3,959), `os_runbooks` (21 duplicate titles), `leads` phones (675).

## PHASE 8 — the 171 ABSENT, in value order

1. **OCR + Drawing Intelligence** — absent in specs #6 and #7, blocks Document Intelligence entirely
2. **Inbound WhatsApp** — my command channel; today it is outbound alerting only
3. **Vision routing** — a tier is registered in `model_catalog` and no vision call has ever been made
4. **The 13 uncovered exception scenarios** — OCR failure, corrupt PDF, ZIP-instead-of-PDF, vector DB
   down, email stopped, WhatsApp down, gateway down, supplier site offline, locked record,
   post-quote requirement change
5. **The 5 missing workflows** as `workflow` rows — Customer Registration, Payment, Complaint,
   Refund, Supplier Suspension
6. **Model cascading** — only after the output contract carries a confidence. It is configured on 47
   of 61 policies and cannot run: confidence appears on **5 of 1,642 calls and 0 of 622 sonnet-5
   calls**, so building it now pays for two models every time
7. Cost per OS, Company Maturity Index, a delete-proposer
8. Remaining spec #3 UI gaps — AI side panel, interactive documents, drag & drop, workspace
   snapshots, live collaboration, visual workflow builder

## THINGS THAT WILL WASTE YOUR TIME IF YOU DO NOT KNOW THEM

- **Vercel builds fail non-deterministically** on `module-not-found` for a `next/font/google`
  internal CSS module — a different font each time, on an unchanged `src/` tree. A **Redeploy with
  "Use existing Build Cache" unchecked** cleared it. Mechanism unknown; do not assert one. The
  durable fix is removing `next/font/google` by self-hosting the four families, which has not been
  attempted.
- **The PR edge-function typecheck resolves the root `package.json`**, and Deno enforces a 24-hour
  minimum dependency age. A freshly published npm version will fail that check even if nothing
  imports it. Pin, do not disable the policy.
- `least(100.0, NULL)` returns **100.0**. It has now caused this twice.
- BEFORE triggers fire in **name** order — `a00_` first, `zzz_` last.
- `revoke … from anon` is a silent no-op when the grant is held through PUBLIC.
- Every SECURITY DEFINER function you **CREATE** is granted EXECUTE to PUBLIC — revoke in the same
  migration. `CREATE OR REPLACE` preserves the ACL; do not revoke there.
- `idempotency_key` is UNIQUE — a not-exists guard excluding only live statuses collides on a
  previously FAILED row.
- Signature parity is not behaviour parity. `project_parity` now prints population for that reason:
  **96 empty tables on production, 255 on staging.**
- The Vercel agent skills are installed in `.agents/skills/`. **`vercel-optimize` has never been
  run** and the deployment page shows 3 unread recommendations.

## STATE AS OF 2026-08-11 ~15:00 UTC — do not re-derive

| | |
|---|---|
| main | `663c643`, production READY, serving quotesdone.com |
| audit | 888 claims — 423 PRESENT, 279 PARTIAL, 171 ABSENT, 15 CONTRADICTED |
| Row #3 | 126/152 measured mid-session, **stale** |
| gates / parity | 23/23 both · IN SYNC (shape only) |
| org | 25 departments, 94 agents, `manager_key` 100% resolving |
| suppliers | 20,470 leads · **0 real claimed** (the 6 are ZZ DEMO) · 0 approved · 19,903 real emails |
| demand | customers 0 · inquiries 0 · quotes 0 · transactions 0 |
| empty tables | 96 of 418 production · 255 of 418 staging |
| knowledge | `kb_chunks` 120,530 · **39% embedded** · 28,521 byte-identical duplicates |
| spend | `agent_brain` 68% of AI cost, 24,619 avg input tokens (pre-cap baseline) |
| cache | `llm_cache` live — 2 rows, 3 hits, `cache_exact` verified |
| dead code | exactly **1** of 698 routines (`fn_simulate_growth`) |

Do not stop and do not check in. Take the next item. If you hit a hard limit, hand over honestly and
name exactly what is unfinished.
