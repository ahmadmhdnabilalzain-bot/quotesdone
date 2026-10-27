---
name: checkpoint-21-sep-night-merge-queue-and-purge
description: "READ FIRST on resume after 21 Sep night — what merged, what is applied, purge run state, agents in flight, founder asks 625-627"
metadata: 
  node_type: memory
  type: project
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-21T19:18:54.834Z
---

21 Sep 2026, ~23:30 Dubai. Merged tonight (all applied/deployed): #782, #791, #793, #794, #792 (7-item brief + registry row file the_founder_brief_pdf_is_registered_for_backup.sql), #796, #787 (invite gates invite_enabled/supplier_outreach_golive still 'false'), #797. #795 (purge safety) APPLIED, PR open — merge after CI.

Purge: `node scripts/kb/purge_kb_bulk.mjs --run` started ~19:20 UTC from worktree .claude/worktrees/m795, log scratchpad/purge_run_21sep.log; 2k batches ~0.9 s; guard stops at 06:00 Dubai; resumable (re-run next night). Needs vacuum/reindex at end.

Registration re-walk on production: 76/76 PASS → registration path GO. Campaign still needs the daily schedule + founder's go.

Agents in flight (PRs to review + apply serially): sales_engineer daily invitation schedule + follow-ups + 24h clock; sales_engineer Arabic quotation PDF + budget bounds; accountant nightly payment test; ceo weekly report + decision rules never firing; customer_support prove bounce/unsubscribe arrive; it_engineer hourly launch-path test.

Founder 21 Sep evening (instructions 625-627): marketing seat later, NOT invitations (SEO, social, digital, BD, LinkedIn outreach, needs LLM); do proper non-marketing staff audit (published https://claude.ai/artifact/4wfNVHE6GLNVQ1XsDrDiND); readiness questions. Still awaiting his OK on Arabic invite signature/brand/terms.

Open: 2 org_tasks 579041/579076 should close on consume tick after #797 — verify. False-alarm fix #767 to be measured over 24 h. Go/no-go due 22 Sep evening. Related: [[a-big-batch-delete-restarted-production]], [[checkpoint-21-sep-sunday-brief-executed]].
