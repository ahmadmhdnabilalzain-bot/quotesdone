---
name: the-bind-door-takes-the-subject-as-an-argument
description: "CLOSED 27 Aug 2026. The service_role founder-impersonation path through fn_phase_c_founder_subject_bind is fixed; the governance ledger now has rows and its first FK broke a probe."
metadata:
  type: project
---

**The finding (26 Aug), now closed.** `fn_phase_c_founder_subject_bind` took `p_subject` as an
ARGUMENT and never compared it to the caller's own `auth.uid()`, and `proacl` showed
`service_role=X`. PostgREST connects as `authenticator` and SET ROLEs, so a service_role call
carrying the founder's `auth_user_id` — readable from the very table the routine validates against —
bound his subject with no founder token in existence.

**The fix (27 Aug):** requires `p_subject = auth.uid()`, requires the verified **JWT role** to be
`authenticated`, requires `auth.uid()` non-null, and moves EXECUTE from `service_role` to
`authenticated`. The grant NARROWED. Measured over HTTPS: service_role + his uuid → 403; a
non-founder JWT + his uuid → 403; his JWT + another subject → 403; his JWT binding itself → 200.
Active production callers before the change were **0** — os_api never binds, it uses
`asCaller(authHeader)` so `auth.uid()` resolves on Route A.

**Three things that came out of it and outlive it:**

* **`current_user` inside a SECURITY DEFINER routine is the OWNER.** The old `if current_user = 'anon'`
  could never be true. Read the role from the verified JWT claim instead.
  See [[a-security-definer-guard-reads-its-own-identity]].
* **`fn_phase_c_governance_decide` needed a `kernel_write_authority` row**, not a grant. Without it
  the kernel write guard refused its own mint with 42501 and `phase_c_governance_decision` held 0
  rows from creation until 27 Aug.
* **`phase_c_governance_decision.decided_by` has a FK to `phase_c_founder_identity(identity)`.** The
  first real decision made `delete from public.phase_c_founder_identity` impossible, which broke a
  freeze-board probe that emptied the register to prove resolution. Deactivate (`active = false`)
  instead — it exercises the predicate the board evaluates.

Related: [[founder-approval-is-a-typed-string]], [[a-blocker-is-a-claim-too]],
[[an-audit-can-mint-its-own-session]].
