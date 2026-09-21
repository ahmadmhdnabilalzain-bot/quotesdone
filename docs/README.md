# docs/ — what lives where

`docs/` is narrative: context, history, audits and plans. **It is never the source of truth for
behaviour.** What the system does lives in code and in the database; the founder's decisions live in
`public.founder_instruction` and `public.company_policy_decision`; working rules live in
`.claude/skills/*/SKILL.md`. Where a document and the code disagree, the code is right and the
document is stale.

Index written 22 Sep 2026 (founder instruction 642). Many documents below describe the company
**before 7 Sep 2026**, when the organisation was cut from ten departments and 90+ agents to a few
seats (today: ceo, customer_support, sales_engineer, accountant, it_engineer). They are marked
*historical*: kept because they record what was measured and why it changed, not because they
describe today.

## Current reference

| where | what |
|---|---|
| `CUSTOMER_PORTAL.md` | customer portal — complete reference |
| `SUPPLIER_PORTAL.md` | supplier portal — complete reference |
| `WEBSITE.md` | the public website |
| `api/` | supplier portal API contracts, one file per tab (services, quotations, messages, inbox drawings) |
| `contracts/` | data contracts: the customer's intake answers, the technical comparison |
| `SECTORS_WE_COVER.md` | which sectors the marketplace covers |
| `CONVENTIONS_LOADING.md` | the standing convention for loading states in the UI |
| `e2e.md` | the end-to-end harness that browses both portals without anyone's credentials |
| `brand/` | the brand guide |
| `legal/` | supplier charge recovery under UAE law; company identity sources |
| `security/` | Stripe webhook setup, third-party key rotation, the inbound-secret separation runbook |
| `it/` | IT failures of 18–21 Sep 2026 and the recurrence guards added for each |
| `sales-engineer/` | the sales engineer seat: acceptance, capability audit, Dropbox archive spec, taxonomy mapping |
| `positions/` | position descriptions (the CEO seat) |
| `FOUNDER_INPUTS.md` | what only the founder can give the machine |
| `VENDOR_EVALUATION.md` | CAD / OCR / ERP reference projects evaluated (clones are in the ignored `vendor/reference/`) |

## Audits

| where | what |
|---|---|
| `audit/` | 14 Sep 2026 backend audit and one-year plan; website audit and upgrade plan; package conformance |
| `audits/` | narrower audits: AI spend (14 Aug), chat answers (21 Sep), word-by-word review (11 Aug) |
| `EMAIL_AUDIT_info_at_quotesdone_2026-09-06.md` | 30 days of mail sent from info@ |
| `OS_AUDIT.md`, `os_audit/` | the OS dashboard production-readiness audit and a walk of it (the OS dashboard is out of scope since 7 Sep) |
| `knowledge_audit/` | per-department knowledge audit — *historical* |

## Knowledge

| where | what |
|---|---|
| `KNOWLEDGE_DOCTRINE.md` | how knowledge is held and trusted |
| `KNOWLEDGE_PLAN_2026-09-06.md`, `SEAT_KNOWLEDGE_DEPTH_2026-09-09.md` | the staff knowledge plan and the depth gap per seat |
| `knowledge/` | the V3 knowledge build: ingestion, runtime connection, role crosswalk, trades still UNVERIFIED — *historical* |
| `knowledge/certification/` | the V3 blind certification run of 14 Aug 2026. The 49 MB raw-output export is no longer in the tree: its SHA-256 is in `V3_CERTIFICATION_RAW_OUTPUTS.sha256` and the file is `git show c8d91b1:docs/knowledge/certification/V3_CERTIFICATION_RAW_OUTPUTS.jsonl` |
| `knowledge-import/` | the knowledge package import report |
| `expertise/` | how knowledge reaches an agent; certification sources and targets; corpus ingestion |
| `step3/` | the IT / cybersecurity knowledge build and how to regenerate it |
| `brain/` | per-department "company brain" notes — *historical* |

## Plans, decisions and registers

| where | what |
|---|---|
| `LAUNCH_READINESS_PLAN.md`, `LAUNCH_STEP1_ORG_CONNECTIVITY.md` | the road to launch |
| `UPGRADE_PLAN.md` | hardening and upgrade plan |
| `COMPANY_BRAIN_PLAN_2026-09-07.md`, `DECISION_STANDARDS_2026-09-07.md` | plans written for the pre-cut organisation — *historical* |
| `DEFECT_REGISTER_2026-09-07.md`, `STAGE0_CHAIN_OF_COMMAND_FINDINGS.md` | structural defect register and chain-of-command scan — *historical* |
| `DETERMINATIONS_CENSUS.md` | which decisions are deterministic code and which still route to a model |
| `SUPPORT_AGENT_DELIVERY_v1_2.md` | delivery report of the customer support agent v1.2 |
| `CHECKPOINT_2026-09-08.md` | state of the build on 8 Sep 2026 |
| `specs_row1…row8_*.txt` | the founder's original specification rows (architecture, OS, executive UI, both portals, categories, agents, OpenRouter cost) |

## History

| where | what |
|---|---|
| `sessions/` | session briefs and hand-overs, one file per session (Aug–Sep 2026) |
| `phases/` | Phase 1–2 design and results, including the holdout v2 evaluation — *historical* |
| `agents/` | the 90-agent roster, role registry, reorganisation and retired two-project checks — *historical* |
| `rehearsal/` | the 11 Aug 2026 dress rehearsal and its traces — *historical* |
| `prs/` | screenshots attached to a PR (WhatsApp sign-up) |
| `visuals/` | photo shortlist for the site |
| `OS.md` | backend reference of the OS edge functions — *historical* |

## Not in docs/, and where it is

| what | where |
|---|---|
| database changes, in apply order | `scripts/sql/` + `scripts/sql/MANIFEST.txt` |
| live gates and tests | `scripts/checks/` (run by `scripts/checks/run.mjs`); retired ones in `scripts/checks/retired/` with an index |
| edge functions | `supabase/functions/<name>/index.ts` |
| the code graph | `graphify-out/graph.json` (`graphify query "<question>"`) |
| holdout v2 evaluation scratch, repomix exports | removed 22 Sep 2026; in git history before that date, and regenerated by `npx repomix` with `repomix.config.json` |
