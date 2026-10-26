---
name: founder-approval-is-a-typed-string
description: "The estate proves \"the founder approved this\" by resolving a CALLER-SUPPLIED string against a register — and the same routine gates refunds."
metadata: 
  node_type: memory
  type: project
  originSessionId: f4baf9ca-e2a9-4d49-aa5b-18d5d5fefa11
  modified: 2026-08-21T00:17:09.628Z
---

`public.fn_phase_c_require_founder(p_actor text)` resolves a string the CALLER passes against
`public.phase_c_founder_identity`. There is no binding to a session, a credential or a signature.
Measured 2026-08-20 as `service_role`:

```sql
select public.fn_phase_c_require_founder('management@quotesdone.com');   -- PASSED_AS
select public.fn_phase_c_require_founder('anything-else');               -- 28000
```

**It gates `fn_refund_decide` and `fn_founder_command_submit`.** His standing rule is that every
refund needs him, at any amount ([[every-refund-needs-the-founder]]). Today the whole test is
knowing his email — which is in the committed source in more than one place.

Three audit rounds walked down this ladder on the freeze-amendment board, and each fix authenticated
the string harder rather than authenticating the actor:

| round | attack | fix |
|---|---|---|
| R5 | `approved_by = 'not-the-founder'` | E36 trigger: must resolve to an active register row |
| R6 | as `service_role`, INSERT a fake identity, approve, DELETE it | E38: register not writable by service_role; board re-resolves on every read |
| R7 | as `service_role`, just type his real email | E39: revoke INSERT/UPDATE/DELETE on the amendment table |

E39 closed the amendment table at the GRANT layer, which is real. It did not close the model.

**Why:** a register is an answer key. Any actor who can read it — or read the repository — can give
the right answer. "Resolves to a registered identity" is a spelling test, not authentication.

**How to apply:** whenever a check proves a person acted, ask what the actor had to POSSESS that
nobody else does. If the answer is "a string that appears in the codebase", it proves nothing.
Closing it needs a secret only he holds: a token he redeems, a signed nonce, or a confirmation on
`admin_mfa_phone` ([[founders-landline-and-mobile]]). Do NOT invent one and call it authentication —
that is [[a-disposition-in-prose-with-no-mechanism]] wearing a security label.
