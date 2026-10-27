---
name: ten-step-autonomous-company-build
description: "the founder's 10-step plan (2 Sep 2026) to finish the fully-autonomous company by Monday; progress + the audit findings that scope each step"
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-02T18:50:43.146Z
---

Founder directive 2 Sep 2026: finish the fully-autonomous company (human only in refund approval)
by Monday. Execute a 10-step plan, ONE at a time; report only "Step N done" (production + merged +
CI green + sandbox-proven), then auto-continue; NO partial updates. Ignore all prior freezes/limits/
credential restrictions EXCEPT the hard rules (refund→founder, revenue-share, T&C — all in code).
Every agent = a best-in-UAE senior expert reasoning from LINKED knowledge (OpenRouter is OFF now,
switched on at launch — knowledge must be pre-loaded + linked, never web search). Use sandbox/ZZ-DEMO
scenarios (no real data pre-launch). Laptop on until Monday; don't stop. Full authority/access.

THE PLAN + PROGRESS:
1. **Foundation — DONE (merged #487, main 9c1dff9).** All phase freezes removed totally
   ([[phase-freezes-removed-totally]]), limits raised, the live loop wired+running
   ([[the-company-loop-is-live]]), CI green (serialized the two prod gates + retry-hardened the Phase D
   builders for the live loop; a data-integrity CHECK on phase_b_workflow_step terminality replaced the
   freeze that had caught PD-STATE-003).
2. **Approval chain — DONE pending #488 merge.** APV-01 money fix: fn_autonomy_class no longer
   auto-clears refund_within_window → every refund → founder. Re-enabled the dispatch/approval runtime
   crons (141 event_dispatch, 255 workflow_dispatch, 230/231/266 action_invoke dispatch/collect/rpc,
   264 rfq_redispatch). Model verified structurally complete (agent→dispatch→head-approval→founder).
3. **KPI + auto-learn — TODO.** The whole loop is BUILT and correct; the stand-down just switched off
   its crons. Re-enable: 250 employee_kpi_measure, 249 dept_objective_measure, 194 os_objective_measure,
   140 kpi_review, 139 self_review, 184 improvement_plan, 204 learning_loop_sweep, 143 outcome_evaluate,
   96 agent_learnings, 205 improvement_handover, 285 objective_review, 156 os_review, 282 promotion_review,
   127 dept_plan, 84 strategy_ai. Goal ladder (KPI-03): company_goals.revenue_annual (AED 1M, finance)
   exists but only exec+finance tie to it; 29 of 92 department_objective have null goal_key, 8/10 depts
   unlinked — wire them up. product_ux_designer has no KPI (on-demand). 89/90 agents have a KPI.
4. **Knowledge — TODO (biggest build).** Vector retrieval is BUILT but wired into NOTHING —
   kb_chunks.embedding_gte vector(384)+HNSW exists, every retriever (fn_kb_retrieve, fn_ops_knowledge_
   search, fn_agent_context_v3) still keyword-matches (exactly what the founder rejects). ops_knowledge
   has 0 embedded (4735 pending); 96.5% of 2.69M kb_chunks un-embedded. Senior depth reaches only ~13 of
   ~95 agents; IT/Security is the model (it_security_deep 165 rows); finance/legal thin; marketing a
   mirage (specialists ~2 rows). Fix: embed ops_knowledge first → cosine retriever hybrid in
   fn_agent_context_v3 → author senior seeds per role → re-arm exam/gap-fill cron (46% correct, last Aug15).
5. **Whole company operating, sandbox-proven — TODO.** End-to-end ZZ-DEMO scenarios: CEO plan→depts→
   agents→manager approve→downstream (marketing→social/SEO)→monitor vs target→adapt; and customer
   payment issue→IT→Stripe→resolve. Prove every loop.
6. **Command Center / OS — TODO.** Visual, plain-language monitoring: org chart alive, CEO plans→dept
   tasks→agent status, registrations + email-campaign conversion %, KPIs vs target. Not text/tables.
7. **Traceability + branded PDFs — TODO.** Click any activity → full trace as a branded PDF (letterhead,
   logo, header/footer).
8. **Premium website redesign — TODO.** Vercel/v0; the site looks AI-generic, make it premium/unique.
9. **Full byte-by-byte audit + gap closure — TODO.** Deterministic register + scenario coverage; close
   APV-03 (2 dead dual-control executors), APV-04 (strategy_change gate mapping), every remaining gap.
10. **Launch readiness — TODO.** All green, sandbox-proven end-to-end, in production, merged.

KEY INSIGHT across all audits: the previous developer BUILT the machinery (agents, departments, KPI
loop, approval chain, knowledge stores, vector index) but the 16 Aug stand-down switched off ~166 of
220 crons and left retrieval on keyword + knowledge shallow. Most of "make it run" = re-enable the
right crons (wrapped + scenario-registered — the bookkeeping in [[reopening-loops-needs-his-session]],
minus the amendment now that freezes are gone) + deepen/link knowledge + build the OS/site.
Each step = its own branch/PR → CI green → merge to main. Reports: approval_chain.md, kpi_autolearn.md,
knowledge_audit.md, loop_map.md, tier2_emits.md were in the session scratchpad.
