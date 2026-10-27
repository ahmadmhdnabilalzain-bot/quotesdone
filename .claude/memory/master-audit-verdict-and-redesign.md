---
name: master-audit-verdict-and-redesign
description: "the comprehensive execution-verified whole-system audit (3 Sep 2026) and the redesign to \"capable in sandbox\""
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-02T23:13:17.175Z
---

Comprehensive, execution-verified, live-Supabase-sourced audit done 3 Sep 2026 (19 domain reports +
full inventory of every function/table/trigger). Prompted by the founder rightly calling out that
earlier scoped audits over-claimed. Full write-up: scratchpad/MASTER_REALITY_AND_REDESIGN.md +
scratchpad/reality_*.md + scratchpad/inventory_*.csv (ephemeral). Live scale: 1,193 project-owned
functions (149 extension), 605 tables, 380 triggers, 221 crons, 202 live edge fns, ~3.1M rows.

VERDICT: NOT capable yet — but the reason is favourable. The machine is **built and correct, switched
off, and never fed.** Lifetime real revenue = **AED 0**; every marketplace transactional table (customers,
inquiries, quotes, transactions, refunds, reveal_invoices) has **0 rows**. Root pattern (recurring here):
**a finished mechanism guarded by a condition that never becomes true** ([[guarded-by-a-condition-that-cannot-occur]],
[[finished-capability-with-no-entry-point]]) — a correct engine idling in neutral, not a broken one.

THREE KINDS OF "NOT DONE":
- BUILT-but-idle (a switch/seed away): revenue rails on LIVE Stripe keys, all 3 portals (customer /me,
  supplier /portal, OS dashboard — real+premium), the deterministic `agents` workers, the ARMED
  19,725-lead supplier-invite campaign (Resend), 160/221 crons OFF.
- BUILT-but-empty: the whole marketplace core, 0 customers/inquiries/quotes/transactions.
- NOT-BUILT (only 2 genuine builds needed): (1) deterministic-first DECISION APPLIER — fn_ops_knowledge_match
  retrieves 197 playbooks+240 rules+240 exception-playbooks but they are NEVER APPLIED as a decision (no
  decision-path caller); the workflow loop dies at the `coordinate` step → held model, no deterministic
  fallback. (2) autonomous Meta ad SPEND — meta_ads only creates PAUSED objects, no meta_access_token.

HARDEST FACTS: (a) exactly **1 matchable supplier** estate-wide and it's an uncontactable test probe
(email NULL); 1 of 15,306 capabilities confirmed; 171 invited → 0 claimed. (b) the model is **held by the
founder** (founder_hold, 8/8 routes open until year 2126, last real call 15 Aug) — deliberate+reversible;
the deterministic `agents` half produced thousands of filed actions with ZERO model calls = existence
proof deterministic-first works.

SECURITY: solid, probe-verified — RLS 605/605, anon executes 0 of 890 definer fns, 9 money/founder guards
all FIRED under aborted-tx probes. 66 functions are dead orphans (incl. a whole unwired double-entry ERP
module — fn_gl_*/fn_ap_*/fn_po_*/fn_inv_*/fn_fa_*/fn_budget_*).

REDESIGN (founder's order: backend→portals→email→ads; each step tagged turn-on/seed/wire/build/retire):
mostly switches+seeds+wiring; only the 2 genuine builds above. RETIRE only frozen-phase/reproduction CI
scaffolding (280 governance fns + ~45 trigger fns + the against-production gates). DO NOT TOUCH (probe-
verified, name them): refund→founder chain, app_secrets/org_authority/autonomy guards, gl_journal/
decision_log immutability, kernel write+truncate guards, PII scrub, reviewer-independence, AND the
founder-auth integrity guards (fn_phase_c_founder_auth_event_is_server_minted, _founder_identity_human_only,
founder_command_*). COVERAGE HONESTY: money spine/runtime/guards/security DEEP execution-verified; ~677
other_util + ~280 governance fns and ~570 of 605 tables CLASSIFIED not line-read.

NO REAL DATA — founder confirmed 3 Sep: the company NEVER launched. The ONLY real data is the ~20,465
scraped supplier LEADS (real UAE companies — the fuel for the registration campaign). Everything else is
NOT real business and no assumption may rest on it: 0 real customers/inquiries/quotes/revenue AND the
internal "activity" some audit agents saw live today (agent_runs 31k, company_event, decision_log, etc.)
is SELF-GENERATED test/probe/scaffolding telemetry, not a working loop. Do not cite it as proof the company
works. The build is greenfield except the leads; the sandbox proof is 100% ZZ-DEMO fixtures.

BOTTOM LINE: day-scale to rehearse the loop; a fixture-seed + the 2 builds from a sandbox-perfect loop;
the one genuinely hard REAL-WORLD problem left is supplier acquisition (real suppliers must register).
See [[the-capable-machine-target]] for the bar.
