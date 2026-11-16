---
name: the-it-engineer-repairs-and-the-engineer-session-fixes-code
description: "15 Nov 2026 (rulings 1574, 1705, 1706): the IT engineer seat repairs operational faults itself with approved safe-fix families (7 registration families of ruling 1705 beside the 8 of 1574), tells the person through customer_support, and writes what it cannot repair to public.it_code_defect for an hourly Claude Code engineer session (docs/runbooks/the-code-defect-session.md). The old route, it_session_fix_day, was never read. Four SQL files in a fixed apply order; supportReply() has no live caller, so 'it is broken' is read by needs_a_person's site_fault option."
metadata:
  type: project
  modified: 2026-11-15
---

**Why.** Founder, 15 Nov 2026 (ledger 1705): "Someone is registering and there is an issue. Who would solve this issue? The IT
engineer should solve it, not report it ... His auto-learning loop should help him. And the knowledge loop in the company,
where everyone knows what everyone else is doing, is extremely important." Measured that day (SP audit SUPPORT_IT.md): the
it_engineer charter row said "It never repairs production itself"; 8 safe-fix families made 632 fixes in 30 days and none on
the registration path; 368 licence reads failed on an open circuit (11-13 Nov), 19 acceptances produced no certificate,
>= 54 SMS sign-ins were refused for a shared mobile; 0 support.root_cause hand-overs reached it_engineer; it_session_fix_day
was read on none of the last 5 days.

**What exists (branch it_engineer-the-it-engineer-repairs-a-registration-and-learns; apply in this order, each with its
pending note until applied):**
1. `scripts/sql/support_and_the_it_engineer_hand_a_fault_both_ways.sql` — support_fault_report; fn_support_hands_it_a_fault
   (support.root_cause with path live_fault, the existing conversation); fn_it_tells_the_person (customer_support's voice,
   model-written, suppression checked at the send); fn_support_fault_fixed (told once when verified).
2. `scripts/sql/a_code_defect_goes_to_the_engineer_session.sql` — it_code_defect, one row per class; open (counts, reopens a
   verified class with its old PR), claim (2-hour lease, skip locked), progress, verified (only after deployed, against a
   SELECT; tells the affected), queue.
3. `scripts/sql/the_it_engineer_repairs_a_registration_and_learns.sql` — the 7 families (licence_read_rerun,
   terms_certificate_retry, code_resend_assist, held_registration_explain, duplicate_mobile_guide, stuck_job_rerun,
   route_failover), the registers it_rerunnable_job / it_route_plan_b / it_route_failover, fn_it_registration_watch every 5
   minutes (stall, burst, returns; the classifier), fn_it_safe_fix_tick with the qd.safe_fix_only_ruling filter (one copy of
   the dispatcher), the it.safe_fix trigger.
4. `scripts/sql/the_it_engineer_repairs_within_its_guardrails.sql` — the charters (tags kept: the it_engineer runtime looks a
   refusal up by its exact [tag]); job_rerun grant active, bounded by it_rerunnable_job.

**How to apply it right.** The dispatcher skips demo findings, so a fixture run raises and closes but never repairs; test the
families on a LOCAL database with non-demo planted rows (scripts/checks/the_it_engineer_repairs_a_registration_and_learns.test.mjs
does), and drive them THROUGH fn_it_registration_watch: calling a family directly skips the dispatcher's budget, which is how
the first probe missed review FIX 1. The licence reader's plan B is qwen/qwen3.8-flash, recorded by the CEO (rulings 1696, 1571)
and INACTIVE until `scripts/eval/model_routing/eval_licence_plan_b.ts --record` passes on ZZ DEMO licences (no plan B for
json_extraction*: the old sonnet seed was dead and would have reversed 1571). The engineer session's scheduled task needs a
yes before it is created.

**Rules the review of f79833d44 set (each is a probe row):** only fixed/failed runs spend max_runs_per_occurrence (a refusal is
"not now", and an unchanged refusal is not rewritten); licence_read_tries 8 is the reader's deliberate stop (held for a person,
wrong document; supplier_api documents.ts) and is never reset; one person hears one "fixed" an hour and one "being fixed" a day
(fn_it_told_recently); a burst gets a 30-minute repair window before a P1 defect; affected_cases is a 200-ref sample beside
affected_count; a verified defect reopens only on a condition seen after verified_at; only the live leaseholder advances a
defect, one step at a time; the hourly tick and the watch share one advisory lock; it.escalation goes to the CEO (ruling
1696), the founder informed, destructive deploys excluded.

**Gotcha.** `_shared/support_reply.ts` supportReply() is imported by no live surface (READ, 15 Nov); the widget, WhatsApp and
e-mail decide "it is broken" in the reasoned needs_a_person reading (site_fault), so a hand-over wired only into supportReply
would never fire.
