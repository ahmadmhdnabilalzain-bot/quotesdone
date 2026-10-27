---
name: openrouter-stays-on-all-tests-with-ai
description: "19 Oct, ledger 1260 — every test runs with real models; OpenRouter is never held/switched off again"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8c4972a3-8a16-4cb0-a308-31a4f45e00bb
  modified: 2026-10-19T00:06:53.069Z
---

Founder, 19 Oct 2026 (ledger 1260): "all tests need to be done with AI. from now on open router stays on".

**Why:** run 5 and the nightlies ran with models off (fixture_no_spend / founder_hold), so ~35 findings were harness noise and real AI behaviour went untested.
**How to apply:** never stub, dry-run or hold models in any test; rehearsal windows open with models_allowed=true; never propose switching OpenRouter off or a model hold. Production spend ceilings still apply. Related: [[never-raise-openrouter-again]], [[idle-llm-spend-max-two-dollars]].
