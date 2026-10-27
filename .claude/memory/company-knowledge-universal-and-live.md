---
name: company-knowledge-universal-and-live
description: "Step 2 done — every agent knows the whole company, universal and always-current, via company_core + v3 identity. PR #484 on main."
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-01T19:09:13.550Z
---

Step 2 (company knowledge, "equal to everyone, always up to date, nothing static") is built, deployed,
verified, and merged (PR #484, `f33b18e` on main). Mechanism:

- **`fn_company_self_knowledge_sync()`** (in scripts/sql/every_agent_knows_the_company.sql) recomposes
  9 universal `company_core` ops_knowledge records from live sources each run: identity/vision/target,
  operating-model/funnel, commercials (reveal fee read LIVE from pricing_config = 3%), the top-3
  comparison report, quotation format, terms, governance, live org snapshot (fn_company_snapshot), and
  the live state. It calls **`fn_company_org_directory_sync()`** (every_agent_knows_the_org_and_content.sql)
  which adds per-department directory records (every agent's role, LINE MANAGER, KPI + live rating —
  everyone knows everyone), the 484 FAQ answers by section, social posts, blog, website pages. A 15-min
  cron (`company_self_knowledge_sync_15min`) keeps it current; keyword vocabulary is folded into content
  so `fn_task_tsquery` retrieval matches deep questions.
- **Per-agent**: `fn_agent_context_v3` already delivered each agent's manager + authority tiers (what
  needs approval); the `agent_knows_its_own_kpis.sql` splice added the agent's OWN kpis (metric, target,
  live current_rating) to its identity block.

Delivery is the existing universal `company_core` path (fn_context_slice, no scope filter + high-authority
fallback). Verified: 20/20 deep questions retrieve the right record; end-to-end a finance agent asking a
marketplace question receives the Top-3 Comparison Report. **Not covered (by design, per the founder):**
the app CODE — that is Step 3, and ONLY for the IT/cybersecurity agents. And agents VOICING answers still
needs paid inference (held); the knowledge is present + retrievable, which is what can be proven without it.

Gotchas that bit me: ops_knowledge.tsv is a GENERATED column (don't insert it); a new cron whose function
body merely CONTAINS a watched-relation name as a substring must be registered in
phase_d_committed_scenario_cron; a superseding routine needs an ownership-ledger sync ([[supabase-access-has-three-paths]]).
