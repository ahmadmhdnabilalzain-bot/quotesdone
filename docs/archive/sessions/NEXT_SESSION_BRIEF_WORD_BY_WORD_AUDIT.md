# NEXT SESSION — THE WORD-BY-WORD AUDIT

This brief replaces the Row #3 work list. The founder's mandate, verbatim:

> 1. audit the code word by word against these 8.
> 2. audit the code word by word against any duplicates
> 3. audit the code word by word for any functions with empty tables
> 4. audit the code word by word for anything that goes against the workflow
> 5. the audit should include supabase and repo fully word by word
> 6. don't stop or pause for any reason unless you have the full report

The conduct rules are in the `quotesdone-session` skill and apply automatically. **The one-line
completion rule does not apply to this session** — the deliverable is the full report, and the
session ends when the report exists, not when a score is green.

---

## WHY THIS SESSION EXISTS

On 11 Aug 2026 a session reported **Row #3 at 126/152** and called it progress against the specs.
Then the founder asked three questions the number could not answer, and all three found real defects
in minutes:

- **duplicates** — 36 of 172 functions are defined in more than one `.sql` file; five of the worst
  were created *that same session* while the score went **up**.
- **functions with no tables** — 234 of them.
- **employees vs the specs** — `model_policy_by_identity` holds **96 target-employee keys and not one
  of them resolves** to an `org_agents` row.

None of those is one of the 152 checks. **The score is a proxy for one spec file and it rose while
the codebase got worse.** That is the whole reason for a word-by-word audit: stop measuring the
instrument and read the contract.

---

## WHAT "THE SPECS" ACTUALLY ARE — 8,654 lines plus six packs

| # | file | lines | scorer in repo |
|---|---|---|---|
| 1 | `quotesdone archeticture.txt` | 371 | yes |
| 2 | `OS.txt` — cross-OS contract | 506 | yes |
| 3 | `OS 2.txt` — executive UI | 1,147 | yes — the 152 checks |
| 4 | `customer portal.txt` | 895 | yes |
| 5 | `supplier portal.txt` | 884 | yes |
| 6 | `suppliers categories.txt` | 1,007 | yes |
| 7 | **`quotesdone agents and knowledge.txt`** | **1,497** | **NONE** |
| 8 | `open router.txt` | 2,347 | yes |

All eight live in `C:\Users\Opera\OneDrive\Desktop\`. The six packs are
`C:\Users\Opera\Downloads\QuotesDone_*_v2026.07.31.zip`.

**Spec file #7 has no instrument at all**, and it is the file that governs departments, employees,
knowledge and workflows — exactly where the 96-key mismatch lives. It was not audited carelessly;
nothing was ever pointed at it.

**`pack_scorecard.mjs` measures `ingested` and `in use`. It does not measure structural
conformance.** That is why 96 unresolvable employee keys scored as a healthy 37-of-37.

---

## METHOD — what makes it word by word rather than another proxy

A scorer asks a question someone thought of. This audit must go the other way: **every line of the
contract gets a verdict**, and the verdict names the code or names the absence.

Produce a **line ledger**, not a score:

```
spec_file | line | claim (verbatim) | verdict | evidence
#7        | 193  | Payment Department: Payment Gateway | ABSENT | no org_departments row, no routine
#7        | 1336 | What happens if OpenAI is unavailable? | PARTIAL | scenario_library openrouter_outage, never rehearsed end to end
```

Four verdicts only: **PRESENT** (name the routine/table/component), **PARTIAL** (name what is there
and what is missing), **ABSENT**, **CONTRADICTED** (the code does the opposite — this is task 4).

Rules:
- A claim is PRESENT only with a named artefact. "The system does this somewhere" is ABSENT.
- Prose, vision statements and "if I were designing it" passages still get a verdict — usually
  PARTIAL or ABSENT — because the founder wrote them as requirements.
- **Never mark PRESENT from a scorer's verdict.** The scorers are what failed here.
- Batch by section, commit the ledger incrementally so nothing is lost if the session ends.

---

## TASK 1 — the eight spec files

Start with **#7**, because it has never been audited and it is the largest known gap.

### What #7 states, already extracted

**22 departments.** 17 numbered (CEO Office, Supplier Success, Customer Success, RFQ/Inquiry
Intelligence, Marketplace Operations, Sales, Marketing, Finance, Legal & Compliance, HR,
Administration & Operations, Engineering, AI, IT & Cybersecurity, Data & Analytics, QA & Testing,
Business Development) plus 5 unnumbered (**Supplier Knowledge**, **Document Intelligence**,
**Notification & Communication**, **Payment**, **Trust & Safety**).

Production has **25 active** departments. Reconcile name by name — do not assume the counts differing
by 3 means three are missing.

**20 knowledge profiles**, each with an explicit "Knowledge Required" list. Note the spec's own gap:
**Notification & Communication and Payment have departments but no knowledge profile.** Report that
as a defect in the contract rather than silently inventing one.

**20 OS knowledge requirements** (Company, Platform, User, Department, AI Agent, Workflow,
Permission, Document, Communication, Supplier, Customer, Marketplace, Financial, Analytics, Security,
Integration, AI, Automation, Reporting, Learning).

**22 interactive capabilities** (AI Command Center, Multi-Agent Workspace, Smart Windows, AI Side
Panel, Universal Search, Interactive Knowledge Graph, Interactive Timeline, Interactive Documents,
Drawing Intelligence, Live Collaboration, Interactive Dashboard, Drag & Drop, Context Memory, AI
Suggestions, Visual Workflow Builder, Floating AI Tools, Natural Language Navigation, Workspace
Snapshots, Real-Time Notifications, Voice Mode, Adaptive Workspace, AI Mission Control).

**A 4-layer knowledge architecture** (Company Core / Department / Live Business Data / External) with
an explicit instruction: *"Don't create 20 isolated knowledge bases."* Check whether the knowledge
actually layers or duplicates.

**16 named exception scenarios** — OpenAI unavailable, Anthropic unavailable, vector DB fails, email
stops, WhatsApp down, payment gateway down, supplier site offline, OCR fails, corrupted PDF, ZIP
instead of PDF, Arabic reply, two agents disagree, locked record, no supplier reply in 24h, wrong
quotation uploaded, customer changes requirements after quotes. `scenario_library` holds 19 scenarios
and `fn_scenario_run` exercises them — map the 16 onto it and report which are genuinely covered.

**Self-healing (8), continuous monitoring (11), learning (6), and six platform components** — AI
Governor, AI Scheduler, AI Auditor, AI Memory Manager, Disaster Recovery, Observability.

Then do #1, #2, #4, #5, #6, #8. **None of their scorers was run on 11 Aug** — six-eighths of the
contract is currently unmeasured. Run each scorer for orientation only; the ledger is the deliverable.

---

## TASK 2 — duplicates

**Measured 11 Aug: 36 of 172 distinct functions are defined in more than one `.sql` file.** Worst:

```
trg_action_gate ×5   fn_agent_context ×5   fn_ws_exec_home ×4   fn_what_if ×4
fn_ws_operations ×3  fn_ws_governance ×3   fn_os_command ×3     fn_ea_agenda ×3
fn_ws_company_os ×3  fn_task_lesson ×3     fn_should_escalate ×3
fn_reputation_recompute ×3  fn_llm_log ×3  fn_exec_meeting ×3
fn_evolution_scan ×3 fn_decide ×3
```

No two `.sql` files are byte-identical, so this is **redundant definitions, not duplicate files**.
Each generated file carries a full copy of a body; the newest wins on apply, and the older copies
are silent decoys for the next reader.

Reproduce with:

```bash
grep -ohiE "create or replace function[[:space:]]+(public\.)?[a-z0-9_]+" scripts/sql/*.sql \
  | sed -E 's/^.*[[:space:]]//;s/^public\.//' | tr 'A-Z' 'a-z' | sort | uniq -c | sort -rn
```

Also cover, and none of these has been measured yet:
- duplicate **edge functions** and duplicated helpers across `supabase/functions/*` (191 functions,
  each with its own copy of `sec()`, `J()`, CORS blocks)
- duplicate **React components** and repeated JSX in `src/components/osx/OsxShell.tsx`
- duplicate **rows** in reference tables (categories were de-duplicated on 10 Aug — check the rest)
- duplicate **cron jobs** doing the same work under different names

**Decide the policy, do not just count.** Either the `.sql` files are an append-only migration log
(in which case duplicates are expected and the rule is "newest wins, older are historical") or they
are the source of truth (in which case 36 need collapsing). The repo currently behaves like the
first and reads like the second. Say which it is in the report.

---

## TASK 3 — functions with no tables

**Measured 11 Aug on production, and the bar as stated cannot be met:**

| | count |
|---|---|
| extension-owned (pgvector: `l2_distance`, `cosine_distance`, `array_to_vector`, …) with no table | **145** |
| **ours**, with no table reference | **89** |
| ours, touching at least one table | 609 |

The 145 belong to pgvector and **deleting them breaks the embedding search the entire knowledge base
runs on**. "Not a single function with no tables" is achievable only for the 89.

Query that separates them:

```sql
exists (select 1 from pg_depend d join pg_extension e on e.oid=d.refobjid
         where d.objid=p.oid and d.deptype='e')   -- true = extension-owned, leave alone
```

For each of the 89, classify: **pure helper with callers** (correct — `fn_norm_text` has 7 callers),
**orphan** (`scripts/checks/no_orphan_routines.mjs` baselines 58 as a ratchet), or **dead**. The
prior audit's verdict — that the rule as written does not isolate dead code — is an *analysis*, not
a reason to skip it. Re-derive it per function and name the ones that are genuinely dead.

**Verify before dropping any.** Several are PostgREST RPCs the console names at runtime, so "named
nowhere in the repository" is evidence, not proof.

---

## TASK 4 — anything that goes against the workflow

Spec #7 §6 names **11 workflows**: Customer Registration, Supplier Registration, RFQ Creation,
Supplier Matching, Quote Collection, Quote Comparison, Award Process, Payment, Complaint, Refund,
Supplier Suspension. Spec #7 also gives the canonical multi-agent chain (BOQ → RFQ Agent → Document
Agent → Supplier Agent → Legal Agent → Finance Agent → Marketplace Agent → RFQ) and the observability
trace (RFQ created → BOQ analysed → qualified → 12 suppliers → invitations → 7 quotes → ranked →
award recommendation).

A **CONTRADICTED** verdict is code that does the opposite of a stated workflow, not code that is
merely missing. Known live example to start from:

- **`model_policy_by_identity`: 96 target-employee keys, 0 resolve.** This is the **fifth** instance
  of the recurring root cause in memory — *a complete thing addressed to an identity the system does
  not model*. The keys are `<department>-<role>` for 24 departments × 4 roles (director,
  analyst-controller, operations-specialist, reviewer-auditor); production uses short keys
  (`ceo`, `cfo`, `procurement`) across 25 departments.
  **The fix shape already exists in this codebase and must be reused, not reinvented:**
  `org_agent_alias` + `fn_org_agent_resolve`, applied at the **write boundary** via a BEFORE INSERT
  trigger — never by widening the reader's join.

Hunt the same shape elsewhere: any table whose `agent`/`actor`/`owner` column holds names that are
not `org_agents` keys. Instance 4 is still open — `ai_quality_snapshots.agent` (754 of 1,066) and
`agent_expectations.agent` (29 of 36).

---

## TASK 5 — Supabase and repo, both, fully

**Repo:** `scripts/sql/` (276 files), `scripts/` (29 `gen_*.mjs` and the checks), `supabase/functions/`
(191 edge functions), `src/` (the OS console and both portals), `.github/workflows/`.

**Supabase, both projects** — production `htdblwldjkcgjvmqkbeh`, staging `pglpqrhvozwepymcuunn`:
698 routines in `public` (609 touching tables, 89 not), 418 tables, 154 triggers, 166 cron jobs on
production and 53 on staging (113 excluded by decision, see `scripts/checks/staging_cron_exclusions.json`),
56 anon-executable SECURITY DEFINER.

**Do not trust signature parity for behaviour parity** — 837 = 837 functions once hid six missing
triggers. `scripts/checks/project_parity.mjs` prints BOTH PROJECTS IN SYNC and that is a shape check,
not a behaviour check.

---

## STATE AS OF 11 Aug 2026, 12:00 UTC — do not re-derive

| | |
|---|---|
| Row #3 | 126/152, 26 NOT MET (a complete run) |
| pack scorecard | 100% ingested, 37 of 37 in use, both projects |
| OS_PORTALS gates | 23 met, 0 open, both projects |
| project parity | BOTH PROJECTS IN SYNC |
| org | 25 active departments, 93 active employees (94 rows) |
| **OpenRouter** | **~$9.27, ~$0.27/h — the only item with a clock on it** |

Six Row #3 checks clear themselves on dates without any work: 13 Aug, ~17 Aug, 23 Aug, 5 Sept,
5 Oct, plus queue turnover. Twelve are blocked on data that does not exist (`customers 0`,
`inquiries 0`, `quotes 0`, `transactions 0`, `approved suppliers 0`). Details in
`NEXT_SESSION_BRIEF_ROW3_2026_08_11_PM.md` — **read it before touching any Row #3 item**, so the
audit does not spend itself rebuilding things that are already fixed and waiting on a date.

---

## TRAPS

- **A scorer's MET is not evidence for the ledger.** That is what this session exists to correct.
- **The specs' own gaps are findings.** Two departments have no knowledge profile. Report it; do not
  paper over it.
- Read the dates. `select now() at time zone 'utc';` first — Dubai is UTC+4. A 24-hour failure window
  keeps showing failures that self-healed hours earlier.
- `least(100.0, NULL)` returns 100.0. `least()`/`greatest()` ignore nulls.
- Postgres fires BEFORE triggers in **name** order. `a00_` forces first, `zzz_` forces last. This cost
  a wrong fix on 11 Aug: `trg_action_gate` read `NEW.confidence` before `trg_governance_stamp` set it.
- `revoke … from anon` is a silent no-op when the grant is held through PUBLIC.
- Every SECURITY DEFINER function you **CREATE** is granted EXECUTE to PUBLIC — revoke in the same
  migration. `CREATE OR REPLACE` preserves the ACL, so do not revoke there.
- Never fabricate, back-date or mass-close data to make a verdict PRESENT. An honest ABSENT is the
  product.

---

## THE DELIVERABLE

One report, committed to `docs/audits/`, containing:

1. The **line ledger** for all eight spec files — every claim with a verdict and evidence.
2. The **duplicate register** — repo and Supabase, with the policy decision stated.
3. The **89 no-table functions** classified, with the 145 extension-owned ones excluded and why.
4. The **contradictions** — code that does the opposite of a stated workflow, starting with the 96
   unresolvable employee keys.
5. A count at the top: claims audited, PRESENT / PARTIAL / ABSENT / CONTRADICTED.

**Do not stop or pause until that report exists.** If the session runs out of context, commit the
ledger as far as it goes, write down exactly which spec file and line number it reached, and hand
over there — a half ledger with a known stopping point is resumable; a summary is not.
