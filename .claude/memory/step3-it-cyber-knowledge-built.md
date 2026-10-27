---
name: step3-it-cyber-knowledge-built
description: "Step 3 done — IT/cyber agents carry a deep, scoped code+security knowledge layer, delivered via v3, excluded from universal recall."
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-01T20:57:00.610Z
---

**Step 3 (IT/cybersecurity deep knowledge) built 2 Sep 2026** — the one extra layer on top of the universal company knowledge, only for `product_eng` + `assurance` agents.

**What:** 164 `ops_knowledge` records at `layer='it_security_deep'` (163 authored by an 11-agent workflow + 1 live posture), mapped to our exact stack across four dimensions: internal mastery (edge attack surface, RLS/grants/definer, kernel controls, auth+baseline), OWASP+secure-coding, MITRE threat model+detection + a dated CVE snapshot, and the AI-security frontier (LLM Top 10, indirect prompt injection). Plus PCI/PDPL/SOC2 posture and SRE.

**Delivery (scoped, not universal):**
- `fn_it_security_slice(dept, q, budget)` returns records only for product_eng/assurance — `[]` otherwise. Folded into `fn_agent_context_v3` as `it_security_knowledge`.
- `fn_company_knowledge_search` (universal veteran recall, see [[always-max-parallel-agents]] context) EXCLUDES `layer='it_security_deep'` so code/security depth stays IT/cyber-only.
- `fn_it_security_live_posture()` recomputes RLS coverage / definer surface / cron baseline / anon grants every run (hourly cron `it_security_live_posture_hourly`).

**Files:** `scripts/sql/it_cyber_deep_knowledge.sql` (helpers+cron), `it_cyber_v3_and_search_scoping.sql` (+ownership_ledger), `scripts/sql/seed/it_cyber_knowledge_seed.json` + `scripts/seed_it_cyber_knowledge.mjs` (reproducible), `docs/step3/` (README + regeneration workflow). PR #485 (branch company-knowledge-gaps-2026-09-01).

**Accuracy caveat learned:** the workflow faithfully copied a STALE config.toml header comment claiming "20 verify_jwt=true" — actual is **13**; the 7 os_* admin functions are verify_jwt=false but code-guarded by app_secrets.admin_emails (a defense-in-depth drift, spawned as task_4a0a9500). Corrected the record. Lesson: security-critical QUANTITATIVE claims must be re-measured against the artifact, not a comment — the records themselves mostly say "verify X", which is the right instinct. See [[never-state-what-you-have-not-measured]].

Step 3 depth scoping was the founder's own boundary (see [[specs-are-upgrades-not-repairs]] context): company knowledge universal, code depth IT/cyber-only.
