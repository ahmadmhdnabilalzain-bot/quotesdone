---
name: audit-defect-verdicts-3-sep
description: "which of the byte-by-byte audit's flagged defects were REAL (fixed 3 Sep 2026) and which were false positives — so nobody re-chases the false ones"
metadata:
  type: project
---

Verified one by one, by reading + executing, 3 Sep 2026. Two carried "defects" turned out false on the
first look, so every item was checked before touching it ([[never-state-what-you-have-not-measured]]).

REAL — fixed, deployed, proven by execution:
- **reg_fetch SSRF**: fetched a caller-supplied url with redirect:'follow', no host check, then ingested
  it into the KB. Now validates scheme/host (loopback, RFC1918, 169.254 metadata, CGNAT, IPv6 ULA/LL,
  *.local/*.internal) and re-checks the FINAL url after redirects. Guard passes 13/13. Residual stated:
  DNS rebinding. Also: NO credential is scoped to reg_fetch and nothing calls it — a dead door.
- **fn_undo first-column-as-PK**: employee_authority's key is composite (agent_key, action_class);
  the old body matched agent_key alone (9 rows for supplier_verification). Now reads pg_constraint,
  matches every key column from the before-image, refuses tables with no PK. Proven: 1 restored, 8 untouched.
- **fn_supersede_lesson**: `found` from the wrong statement, nulled the old row's own supersedes_id
  (broke the chain), allowed self-supersede. Fixed + proven.
- **kpi_miss remediations froze autonomy** (agent_remediation.blocks_autonomy defaults true; found via
  CI): a KPI miss now coaches (task + practice), never blocks. See [[the-company-loop-is-live]].

FALSE POSITIVE / already mitigated — do not re-chase:
- doc_render "bypasses paidProviderGate": its call goes through makeLlm → ai_gateway (gated); the raw
  openrouter_api_key read is only a boolean precondition, never used for a fetch.
- stripe_webhook↔stripe_setup REQUIRED_EVENTS drift: already fixed in-file; 5 events = 5 branches.
- dropbox_oauth "secret in query string": client_secret is in a form-encoded POST body (correct OAuth).
- os_* build-mode door: the x-os-key preview bypass is hard-limited to the read_only action class;
  phase_c_command_center_entry_point asserts it.
- "portal unauth HTML": home/about/faq/legal/portal/supplier_ack/unsubscribe serve PUBLIC shells; data
  sits behind authenticated APIs; secrets are server-side only (unsubscribe verifies signed tokens).
- "5-fn table-sourced dynamic-SQL-under-DEFINER": no definer fn uses execute format with %s; the 5
  `||` hits are prose/string-building, not executed SQL. fn_undo was the one real dynamic-SQL definer.
- "swallowed-error pattern": diffuse, not one defect; the instances that mattered (held-model paths in
  agent_brain / route_inquiry / kb_deepen) were made idle-clean rather than silent.
