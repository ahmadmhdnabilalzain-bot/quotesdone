---
name: quotesdone-autonomy-and-staging-rules
description: "On QuotesDone, fix defects without asking and deploy everything to production; only Stripe refunds need founder approval."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 44929eb5-f98f-4608-8a3b-5dc2f37d6fc1
  modified: 2026-08-10T09:33:00.569Z
---

**Everything is for production.** Stated by the founder on 6 Aug 2026: *"nothing is for staging.
all for deploy."* Staging (`pglpqrhvozwepymcuunn`) is a rehearsal and verification surface, not a
destination — work that stops there is not delivered. Every schema object, routine, Edge Function,
reference-data load and config change goes to production (`htdblwldjkcgjvmqkbeh`) in the same turn
it is verified.

This supersedes the older staging-only default, and it also overrides "import into staging only"
notes inside founder-supplied knowledge packs — those predate 5 Aug 2026, when production became a
live deploy target.

**Why:** production has 0 customers, 0 inquiries and 0 quotes, so there is no real data to protect
and nothing to lose by shipping; what there is to lose is time, and anything parked in staging is
invisible to the business. The founder also refuses "zero" as an answer — an empty table in
production is a defect, not a safe default.

**How to apply:**
- Schema parity is mandatory anyway (`verify_phase1` asserts 405 tables / ~745 routines on both), so
  a routine or table created in one project must be created in the other regardless.
- Verify on staging first when a change is risky, then promote by reading staging's verified
  definition back and posting it verbatim, asserting `md5(prosrc)` matches. Do not retype it.
- `qd_guard`'s `mgmtWrite` refuses production by design; that guard is correct and stays. Production
  writes go through the Supabase MCP `execute_sql` or the management API deliberately.
- The ONLY action needing founder approval is a **Stripe refund**. Do not gate anything else.
  Restated far more forcefully on 10 Aug 2026: *"there's not a single thing that requires my
  approval except refunds. Nothing else, literally nothing else."* This retires the habit of
  parking work as an "escalation" — spend decisions, model-routing activation, org-structure
  changes and authority restoration are all the session's to make and then report. Escalate a
  refund; otherwise decide, do it, and say what you did and why.
- Stripe TEST keys remain the one genuinely blocked item — only the founder can issue them,
  because he is the only one who can log into Stripe. That is a capability limit, not an approval.

See [[quotesdone-definition-of-done]] and [[quotesdone-work-without-checkins]].
