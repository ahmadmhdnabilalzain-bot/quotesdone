---
name: the-capable-machine-target
description: "the founder's definitive completion bar (3 Sep 2026) — the autonomous revenue machine, and the redesign to reach it"
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-03T05:32:19.323Z
---

Founder, 3 Sep 2026, the bar that supersedes step-by-step reporting: **"until you can reply 'yes it's
capable' then you are not done."** Capable = a fully-automated company where the ONLY human inputs are
(1) subscriptions kept running and (2) a funded Meta ad balance, and the code turns that ad spend into
AED 1,000,000/yr of reveal-fee revenue autonomously — humans touch nothing else except approving
refunds. Also: **"nothing needs to be proved with real data. everything should be perfect in the
sandbox and by that time only we will launch."** So the deliverable is the WHOLE revenue loop proven
end-to-end on ZZ-DEMO scenarios, deterministic-first, with the model residual wired — perfect in the
sandbox. And: **"90% of calls without LLM or internet"** — the model is the ~10% residual for genuine
open-ended reasoning only. And: **"the current code and structure might not be perfect, you can change
stuff / maybe the whole code needs a rework"** — broad authority to redesign, not just patch.

VERDICT (honest, measured this session): the current code CANNOT do this yet. Infrastructure is largely
built (marketplace schema, 90+ agents, the knowledge base now 100% embedded, payment tables, approval
chain), but the REVENUE ENGINE is not a real autonomous loop. Broken/ missing links:
- **Ads → buyers is not autonomous.** meta_ads/meta_sync/boost_recommend exist but boost_recommend only
  RECOMMENDS and writes a founder-funded proposal per boost ("it never spends"), and it's LLM-driven.
  Founder's model: he funds the Meta balance, the system spends it autonomously within that ceiling.
  This is a deliberate money-boundary change (refunds still always → founder). Top-of-funnel, must build.
- **Supply side empty** — ~1 confirmed supplier, funnel 81 invited / 0 registered ([[supplier-funnel-81-invited-0-registered]], [[one-confirmed-supplier-gates-every-rfq]]).
- **Transactions are all fixtures** ([[the-funnel-was-all-fixtures]]) — real reveal-fee Stripe path unproven (sandbox is fine, but the loop must run).
- **Agents need the model** (OpenRouter held until launch) AND the deterministic-first design so 90% runs without it.
- **Phase-governance friction** wraps everything (see below).

REDESIGN = re-centering, NOT rewrite. Keep the infrastructure + real guards; cut the scaffolding; build
the revenue loop.
- **Governance audit (scratchpad/audit_governance.md):** ~1/3 of ~90 CI checks are retirable frozen-phase
  / "repo-byte-matches-live" reproduction / freeze-PCCR-crosswalk scaffolding. The project-parity.yml
  phase-c/phase-d jobs DRIVE probes into the ONE live DB, serialised, contending with the live loop
  (the slow Phase D). Retire the reproduction/acceptance drives; move the few real runtime assertions to
  read-only/ZZ-DEMO. PROTECT (never touch): refund_single_path, stripe_refund_events,
  anon_cannot_execute_security_definer, authority guards, pricing_*, kernel write guards, migration-lint,
  typecheck, deno-check, deploy/resilience. Caveat: verify no unique real assertion is duplicated before
  deleting a mixed check.
- audit_llm.md (LLM→deterministic map) and audit_core.md (real-vs-stub business core) complete the evidence.

BUILD ORDER (the machine, sandbox-perfect): (1) strip governance friction; (2) deterministic-first agent
runtime (90% no-LLM: retrieve the right playbook via [[reasoning-layer-semantic-retrieval]] and apply it,
model only for the residual); (3) autonomous ad management within the funded Meta balance; (4) real
supply acquisition + onboarding; (5) the reveal-fee transaction loop; (6) the growth loop to AED 1M; (7)
prove the whole loop end-to-end on ZZ-DEMO. Report "yes capable" only when that loop runs perfectly in
the sandbox. This is a marathon across sessions — keep the build coherent against this map.

**PROGRESS 3 Sep 2026:** (1) done (freezes removed, 12 dead governance routines retired by measurement);
(2) done (fn_apply_playbook, 82% of steps deterministic with the model held); (3) DONE — see
[[ad-spend-autopilot-built]]; (5) mechanics proven end-to-end on committed ZZ-DEMO data
([[revenue-loop-mechanics-proven-blocker-is-data]]). Remaining: (4) real supply acquisition (the one
real-world problem), the live Stripe test reveal, and the founder's Meta token (the only switch).
