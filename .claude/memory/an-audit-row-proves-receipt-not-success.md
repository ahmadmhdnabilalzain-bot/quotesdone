---
name: an-audit-row-proves-receipt-not-success
description: "os_api writes its os_audit_log row BEFORE the RPC, so an audit entry means the request arrived and was authenticated, never that it worked."
metadata: 
  node_type: memory
  type: project
  originSessionId: 12007385-5c1a-4596-9522-d83edb00dcb7
  modified: 2026-08-25T00:58:22.320Z
---

`supabase/functions/os_api/index.ts` inserts into `public.os_audit_log` *before* dispatching the
action — deliberately, so an attempted mutation on the static preview key is on record even though
it is refused two lines later. The comment says so: *"it is logged first and refused second."*

On 25 Aug 2026 this made an authenticated founder decision look like it had landed. `os_audit_log`
18826 carried his exact PCCR-006 approval sentence and his verified email; the RPC behind it
returned 403 and nothing was written. Reading the audit row alone would have been reading a receipt
as an outcome.

**Why:** the audit log is the only record of a refused request, which is what makes it valuable and
what makes it not evidence of success.

**How to apply:** never conclude a Command Center action succeeded from `os_audit_log`. Confirm the
EFFECT — the `founder_command` / `founder_command_clarification` / `phase_c_trace` row it should
have produced. When they disagree, the `edge_logs` and `postgres_logs` analytics endpoints hold the
answer: `https://api.supabase.com/v1/projects/<ref>/analytics/endpoints/logs.all?sql=…&iso_timestamp_start=…&iso_timestamp_end=…`
against `edge_logs` gives the HTTP status per RPC and `postgres_logs` gives the SQLSTATE, both
timestamped in microseconds. Related: [[a-refusal-that-is-not-an-error]],
[[connected-is-a-claim-not-a-measurement]], [[a-deferred-trigger-runs-as-the-transaction-role]].
