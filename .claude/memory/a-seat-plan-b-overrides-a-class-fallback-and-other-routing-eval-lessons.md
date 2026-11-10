---
name: a-seat-plan-b-overrides-a-class-fallback-and-other-routing-eval-lessons
description: "10 Nov 2026 model-routing work (ruling 1571): a class fallback is replaced by the seat's plan B unless cheaper; a judge must see the brief; a direct OpenRouter call needs the gateway's thinking headroom; '#5202' tripped the supplier-count guard."
metadata:
  node_type: memory
  type: feedback
---

10 Nov 2026, it_engineer (cost), branch it_engineer-model-tiers. Design: docs/reports/2026-11-10-design-model-routing.md;
results: docs/reports/2026-11-10-model-routing-evals.md.

- **A class's fallback is not what a seat's call falls back to.** fn_ai_route replaces it with the seat catch-all's plan B
  (model_policy_by_identity, Sonnet 5.5 for all six seats) whenever the class runs on the seat's primary. Setting
  `model_fallback = qwen` on a T1 class changed nothing for any call that names its seat (every think() and aiReply call):
  the rehearsal read Luna Pro > Sonnet. Fixed in simple_tasks_leave_sonnet_and_every_reply_runs_on_the_model_its_task_needs.sql:
  a CHEAPER class fallback is kept. Read `fn_ai_route(class, ..., seat)`, never the policy row, to know a route.
- **A judge shown only a summary fails true facts it cannot see** (as the-seat-exam-sweep-runs-offline.md says). Eval A run 1
  marked "no cap" and "not VAT-registered" as invented on BOTH arms; give the judge the company brief (sysStable, cached).
- **A direct OpenRouter call must be shaped like the gateway's** (`_shared/request_shape.ts` shapeRequest): Qwen 3.8 Flash
  reasons inside max_tokens, and at a flat 600 tokens 10 of 60 answers came back empty. The gateway adds thinking headroom.
- **support_reply_guard's internal_number read a request reference as our supplier count** ("طلبكم #5202 ... 4 موردين"); a
  status answer was refused, and the rewrite then dropped the reference it must carry. References are NOT_A_COUNT now.
- **A matrix-style check that replays pending files must replay the branch's own new MANIFEST files first**
  (applies_at_merge.mjs branchAddedFiles): a pending file can name a model only this PR's MANIFEST file registers.
- Sonnet was NOT better than Luna Pro on the 20 paired T2 cases once judged fairly (7.85 vs 8.05). Both invent details the
  brief does not hold (Sonnet: "20 options", "BOQ held back"); the figure guard checks money only, not counts or days.
