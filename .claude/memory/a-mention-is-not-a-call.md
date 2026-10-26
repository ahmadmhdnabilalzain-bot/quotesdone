---
name: a-mention-is-not-a-call
description: "The browser calls ZERO RPCs directly — grep -rn \"\\.rpc(\" src/ returns 0 in the whole frontend — so any grant justified by \"named in src/\" rests on a comment, not a caller."
metadata: 
  node_type: memory
  type: reference
  originSessionId: b938bfcf-ddcb-45bf-8cf7-2f8b74c71fd5
  modified: 2026-08-19T12:03:53.108Z
---

19 Aug 2026. `scripts/sql/revoke_execute_on_trigger_only_secdef_fns.sql` kept seven SECURITY DEFINER
grants under a `BROWSER` category — *"named in src/ — a real product surface calls them… LEFT
ALONE"*. The §8 probe found `fn_supplier_opportunities` answering **anon** with HTTP 200.

**Measured: `grep -rn "\.rpc(" src/` returns 0 occurrences in the entire frontend.** The browser
calls no database routine directly, through any helper. The hit that produced the classification is
a **comment** at `src/components/portal/supplier/SupplierQuoteBuilder.tsx:26`. Every real caller is
an edge function using `admin.rpc(...)` — the service role — which holds its own explicit grant.

It returned `count: 0` because the estate holds zero inquiries. A zero cannot tell a dead guard from
an idle system; the first live RFQ changes the payload, not the permission.

Fixed in `phase_d_d35_a_mention_is_not_a_call.sql` (7 revoked, verified with
`has_function_privilege`, guarded by `scripts/checks/anon_cannot_execute_security_definer.test.mjs`
with a ratchet). **Still open: 56 anon-executable and 60 authenticated-executable of 786 SECURITY
DEFINER routines in `public`.** Not swept — each needs a per-function caller check — but the reason
they were left is now known false, so the look is owed.

Two corollaries: `revoke … from anon` is a silent no-op when the grant is held through PUBLIC, so
name `public` first; and a plain `CREATE` re-grants EXECUTE to PUBLIC while `CREATE OR REPLACE`
preserves the ACL, so the regression is one DROP-and-recreate away.
