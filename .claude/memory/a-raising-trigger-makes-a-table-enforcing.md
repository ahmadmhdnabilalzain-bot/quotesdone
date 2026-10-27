---
name: a-raising-trigger-makes-a-table-enforcing
description: "Adding any row trigger that raises turns its table into an ENFORCING table, and fn_kernel_truncate_protection_state is a GATE — attach z00_kernel_truncate_guard and REVOKE TRUNCATE in the same migration."
metadata: 
  node_type: memory
  type: project
  originSessionId: 051dbf76-3315-4c3b-9c5c-69c40409fdcc
  modified: 2026-08-24T14:01:04.421Z
---

24 Aug 2026. `public.fn_kernel_truncate_protection_state` counts as **ENFORCING** any table in
`public` carrying a non-statement row trigger whose function body contains `raise exception`. It is
a **GATE**, not a ratchet — it is not named in `scripts/checks/kernel-boards.json`, so both of its
counts must read `0 of N` or `kernel_boards_are_green.test.mjs` fails the suite.

Four tables reached that definition in one session and took it to `4 of 91` on both counts:

    phase_d_file_revision        a10_phase_d_file_revision_reviewer
    phase_d_quote_normalisation  a10_phase_d_normalisation_shape
    phase_d_legal_assertion      a10_phase_d_legal_assertion_source
    public.quotes                a30_quote_supplier_is_immutable    <- an EXISTING table, newly enforcing

Each refused a WRITE and none refused a TRUNCATE, so every refusal was one statement from
irrelevant: `truncate public.phase_d_file_revision` would have removed every redaction verdict
without the reviewer-independence trigger having anything to say about it. And all four still
granted TRUNCATE to `service_role`, because **TRUNCATE arrives with ALL and nothing takes it away**.

**In the same migration that adds a raising row trigger:**

```sql
DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.<table>;
CREATE TRIGGER z00_kernel_truncate_guard
  BEFORE TRUNCATE ON public.<table>
  FOR EACH STATEMENT EXECUTE FUNCTION public.fn_kernel_truncate_guard();
REVOKE TRUNCATE ON public.<table> FROM service_role, authenticated, anon;
```

Both halves, because the board counts them separately: a guard with the grant still in place is a
control the owner walks around, and a revoke with no guard reopens the moment someone regains the
privilege.

**And the second lesson, which cost more.** The first reading of this board was taken *after ten of
the session's files had already been applied*, and `4 of 91` was written into the closure document
as "pre-existing". It was not — it was mine. **A baseline read after the change is not a baseline.**
Take board readings BEFORE the first apply, or say plainly that the reading is post-change.
See [[instruments-report-on-the-wrong-subject]] and
[[a-new-guard-reddens-the-fixture-not-the-code]].
