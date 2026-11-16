# docs/ — what lives where

`docs/` is narrative: context, history, audits and plans. **It is never the source of truth for
behaviour.** What the system does lives in code and in the database; the founder's decisions live in
`public.founder_instruction` and `public.company_policy_decision`; working rules live in
`.claude/skills/*/SKILL.md`. Where a document and the code disagree, the code is right and the
document is stale.

Index written 22 Sep 2026 (founder instruction 642). Many documents describe the company
**before 7 Sep 2026**, when the organisation was cut from ten departments and 90+ agents to a few
seats. **Six today**, measured 23 Sep 2026 against `public.function_owner` and the live deployment
list: sales_engineer 29 functions, customer_support 19, accountant 10, it_engineer 10, marketing 4,
ceo 1 — 73 in total. The marketing seat went live on 22 Sep and this line said five until the 23rd.
Documents describing the pre-cut organisation now live under
`archive/`: kept because they record what was measured and why it changed, not because they
describe today. **Everything outside `archive/` is meant to be current.** If you find something in
the list below that is not, move it into `archive/` and say so in the same commit.

## Current reference

| where | what |
|---|---|
| `architecture/` | the maps: the database by business area (generated, checked for drift), and where the code is organised |
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
| `audits/` | narrower audits: AI spend (14 Aug), chat answers (21 Sep) |
| `EMAIL_AUDIT_info_at_quotesdone_2026-09-06.md` | 30 days of mail sent from info@ |

## Knowledge

| where | what |
|---|---|
| `KNOWLEDGE_DOCTRINE.md` | how knowledge is held and trusted |
| `KNOWLEDGE_PLAN_2026-09-06.md`, `SEAT_KNOWLEDGE_DEPTH_2026-09-09.md` | the staff knowledge plan and the depth gap per seat |
| `knowledge/` | the V3 knowledge build: ingestion, runtime connection, role crosswalk, trades still UNVERIFIED |
| `knowledge-import/` | the knowledge package import report |
| `expertise/` | how knowledge reaches an agent; certification sources and targets; corpus ingestion |
| `step3/` | the IT / cybersecurity knowledge build and how to regenerate it |

## Plans, decisions and registers

| where | what |
|---|---|
| `LAUNCH_READINESS_PLAN.md`, `LAUNCH_STEP1_ORG_CONNECTIVITY.md` | the road to launch |
| `release/qualification_matrix.md` | the release go/no-go standard (3 Nov 2026): severities, scenarios per flow, AI eval specs, drills, load, gaps, the dated checklist |
| `UPGRADE_PLAN.md` | hardening and upgrade plan |
| `SUPPORT_AGENT_DELIVERY_v1_2.md` | delivery report of the customer support agent v1.2 |
| `specs_row1…row8_*.txt` | the founder's original specification rows (architecture, OS, executive UI, both portals, categories, agents, OpenRouter cost) |

## History — `archive/`

Everything here records a state the company has left. It is kept because it says what was measured
and why something changed; none of it describes the build today. Nothing in `archive/` is read by
any script or workflow — that was the test for moving it (measured 22 Sep 2026).

| where | what |
|---|---|
| `archive/sessions/` | 82 session briefs and hand-overs, one file per session (Aug–Sep 2026) |
| `archive/phases/` | Phase 1–2 design and results, including the holdout v2 evaluation |
| `archive/knowledge_audit/` | per-department knowledge audit, for the ten-department organisation |
| `archive/brain/` | per-department "company brain" notes |
| `archive/os_audit/`, `archive/OS_AUDIT.md`, `archive/OS.md` | the OS dashboard: production-readiness audit, a walk of it, and the backend reference (out of scope since 7 Sep 2026) |
| `archive/COMPANY_BRAIN_PLAN_2026-09-07.md`, `archive/DECISION_STANDARDS_2026-09-07.md` | plans written for the pre-cut organisation |
| `archive/DEFECT_REGISTER_2026-09-07.md`, `archive/STAGE0_CHAIN_OF_COMMAND_FINDINGS.md` | structural defect register and chain-of-command scan |
| `archive/CHECKPOINT_2026-09-08.md` | state of the build on 8 Sep 2026 |
| `archive/phase-d-package/` | the Phase D deterministic-business-handler package, delivered Aug 2026; its check is in `scripts/checks/retired/` |
| `archive/SKILLS_MANUAL.md` | the skills manual; working rules themselves live in `.claude/skills/*/SKILL.md` |
| `archive/repomix.config.json` | the repomix export config (`npx repomix`); the exports themselves are ignored |
| `archive/tools/` | the public-API reference and Python toolbox notes |
| `archive/knowledge-libraries/` | the five UAE knowledge-library source archives the corpus was built from |
| `archive/knowledge/certification/`, `archive/knowledge/remediation/` | the V3 blind certification run of 14 Aug 2026 and its remediation reports; the agent_brain / agent_train / os_api functions they ran on are gone. The 49 MB raw-output export is not in the tree: its SHA-256 is in `V3_CERTIFICATION_RAW_OUTPUTS.sha256` and the file is `git show c8d91b1:docs/knowledge/certification/V3_CERTIFICATION_RAW_OUTPUTS.jsonl` (moved 16 Nov 2026) |
| `archive/audits/WORD_BY_WORD_2026_08_11/` | the word-by-word review of 11 Aug 2026, of the organisation before the 7-8 Sep deletions (moved 16 Nov 2026) |
| `archive/agents/` | four reports of the department-agent organisation (org-runtime closure, reorganisation migration, orchestration evidence, cross-department handoffs), whose routines are gone (moved 16 Nov 2026) |
| `archive/DETERMINATIONS_CENSUS.md` | which decisions were code and which went to a model, before the 7-8 Sep deletions; 201 of its 320 routines are gone (moved 16 Nov 2026) |
| `archive/security/WI-001-runbook.md` | the operator runbook for scoped internal credentials, whose routines are gone (moved 16 Nov 2026) |
| `agents/` | the 90-agent roster, role registry and retired two-project checks — *historical, but read by `project-parity.yml` and four checks, so it stays here* |
| `rehearsal/` | the 11 Aug 2026 dress rehearsal — *historical, but written to by `scripts/rehearsal/hvac_dress_rehearsal.mjs`* |
| `prs/` | screenshots attached to a PR (WhatsApp sign-up) |
| `visuals/` | photo shortlist for the site |

## Not in docs/, and where it is

| what | where |
|---|---|
| database changes, in apply order | `scripts/sql/` + `scripts/sql/MANIFEST.txt` |
| live gates and tests | `scripts/checks/` (run by `scripts/checks/run.mjs`); retired ones in `scripts/checks/retired/` with an index |
| edge functions | `supabase/functions/<name>/index.ts` |
| the stack, how to run it, how to change the database | `README.md` at the repository root |
| where each kind of thing lives, and how the money flows | `ARCHITECTURE.md` at the repository root |
| the code graph | `graphify-out/graph.json` — generated locally by `graphify update .`, not tracked; query it with `graphify query "<question>"` |
| one-shot scripts that already ran | `scripts/archive/` with an index of what each did |
| holdout v2 evaluation scratch, repomix exports | removed 22 Sep 2026; in git history before that date, and regenerated by `npx repomix` with `docs/archive/repomix.config.json` |
