---
name: round-3-upgrades-wait-for-queue-below-20
description: "Ledger 1018: build round-3 agent upgrades ONLY once open PRs < 20; the list, and why builds are paused"
metadata:
  node_type: memory
  type: project
  originSessionId: 8c4972a3-8a16-4cb0-a308-31a4f45e00bb
  modified: 2026-09-28T21:44:24.407Z
---

On 29 Sep 2026, 70 PRs were open because builds outran merges, and a GitHub Actions jam (130 CI jobs fired at once) had frozen the queue. New builds are paused. The founder approved round 3 (ledger 1018) to start only once `gh pr list --state open` is below 20.

**Round 3:**
1. Stalled-inquiry rescue: no quotes after 48 hours triggers targeted recruitment and an honest update to the customer.
2. Quote quality check before the customer sees a quote: missing specs, prices off the price ranges, unclear terms; the supplier is asked to fix it.
3. Fraud and risk screening: duplicate licences, mismatched details, disposable email, refund patterns.
4. A concierge for a customer's first request.
5. Supplier capacity and availability.
6. Fix `trade_words.ts`, which still matches supplier documents by words, against ruling 890.

**How to apply:** check the open-PR count at the start of each session and whenever asked about merging. Start these builds (10 agents max; apply at merge, never before) only once the count is under 20.

Related: [[apply-at-merge-never-before]], [[use-the-installed-skills]].
