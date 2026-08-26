# PCCR-007 — auth.uid() is a setting, and the money door reads it

**Status: RAISED. NOT APPROVED. NOT APPLIED.**
`public.fn_phase_a_baseline_drift()` and `public.fn_phase_b_baseline_drift()` both return 0 rows.
Nothing in this document has been applied and no frozen Phase C body has been changed by it.

Raised by the session of 26 Aug 2026, immediately after the independent Phase D acceptance audit,
from a probe that audit did not run.

---

## 1. Observed problem — the defect

`public.fn_phase_c_require_founder(p_actor text)` — the frozen `founder_authentication` subject —
resolves the founder from `auth.uid()`. `auth.uid()` reads `current_setting('request.jwt.claims')`.
A `postgres` connection can set that setting for itself.

PCCR-003 replaced a caller-supplied *string* with a verified *subject* and was right to. But the
subject it now trusts is read from a session variable, and on the management and migration path
there is no bearer token behind that variable — only a `set_config` the caller made.

PCCR-006 closed exactly this shape for governance by refusing any connection whose `session_user` is
not `authenticator`. Every other door `fn_phase_c_require_founder` guards was left as it was.

## 2. Evidence — measured on production, in aborted transactions, 26 Aug 2026

```sql
select set_config('request.jwt.claims',
       '{"sub":"1256c7ec-17bf-4b1e-af8f-aaa32a8fdd14","role":"authenticated"}', true);

select auth.uid();
-- 1256c7ec-17bf-4b1e-af8f-aaa32a8fdd14

select public.fn_phase_c_require_founder('management@quotesdone.com');
-- management@quotesdone.com        <- ACCEPTED
```

Without that one `set_config` line the identical call is **REFUSED 28000**, *"no verified auth
subject on this call"*. So the door does not test whether a session exists; it tests whether a
string has been set.

**The money path, reached the same way.** `fn_kernel_refund_decision_record` calls
`fn_phase_c_require_founder` as the **first executable statement of its body**, before any argument
validation:

```
fn_kernel_refund_decision_record(… 'transaction_id':'zz-audit-no-such-transaction' …)
-- REFUSED 22023: "request_id is required and names the…"
```

`22023` is the argument check, which sits *after* the founder gate. A `28000` would mean the gate
refused. It did not. The founder gate was passed by a migration connection with no bearer token in
existence.

**What still held, measured in the same transaction:**

| door | result |
|---|---|
| `fn_phase_c_governance_decide` | **REFUSED 28000** — PCCR-006's `session_user <> 'authenticator'` check runs first and is not forgeable |
| `SET SESSION AUTHORIZATION authenticator` | **REFUSED 42501** — `postgres` is not superuser on this deployment (`is_superuser = off`) |
| `SET ROLE authenticator` | accepted, and `session_user` stays `postgres` — so the PCCR-006 predicate holds under it |

That last row is why the fix below is the same predicate: `session_user` is the connected role, and
nothing short of superuser can change it.

**Already closed without this change request**, because neither object is frozen — applied 26 Aug
2026, `scripts/sql/phase_c_the_amendment_guard_only_watched_one_basis.sql`:
`public.phase_c_freeze_amendment` now refuses an approval write from any connection that is not
`authenticator`, on **every** basis, and its approval columns are immutable once set. Before that
file, a forged `request.jwt.claims` let a migration write an `AUTHENTICATED_FOUNDER_SESSION`
amendment; after it, the same insert is refused `28000`.

## 3. Current behaviour

`fn_phase_c_require_founder` accepts any caller who can set `request.jwt.claims`. It gates:

- `fn_kernel_refund_decision_record` — the refund decision ledger, under the founder's standing rule
  that **every refund at any amount** requires him;
- `fn_kernel_cancel` — the frozen cancellation service;
- `fn_founder_command_clarify` and `fn_founder_command_control` — the Chief of Staff command path.

All four are reachable today from a `postgres` connection carrying no token.

## 4. Proposed behaviour

One predicate, added to `fn_phase_c_require_founder` ahead of Route A, identical in shape and
message to the one PCCR-006 put on `fn_phase_c_governance_decide`:

```sql
if session_user <> 'authenticator' then
  raise exception 'fn_phase_c_require_founder: the founder is resolved from a bearer token verified
    by PostgREST (session_user authenticator); this call arrives as session_user %. auth.uid() reads
    request.jwt.claims, which a management or migration connection can set for itself.
    (pccr007_founder_untrusted_connection)', session_user using errcode = '28000';
end if;
```

Route B — a subject `os_api` verified and bound with `fn_phase_c_founder_subject_bind` — already
requires `authenticator` at the bind door and is unaffected. `service_role` calls through PostgREST
also arrive as `session_user = 'authenticator'`, so `os_api` continues to work; this was measured,
not assumed.

**A second, separable item, raised here rather than applied.** `fn_phase_c_freeze_drift`'s check
`approved_change_requests_with_no_verified_governance_decision` reads *1 of 1* because **PCCR-003**
carries an approver and no `governance_decision_id` — the column did not exist when he approved it.
The `NOT VALID` CHECK `phase_c_change_request_approval_is_derived` already grandfathers exactly that
row; the board does not, so the two instruments disagree and V1 §A's *"every row ok"* cannot hold.
The proposal is to split the check so the grandfathered set is **pinned by name at exactly
PCCR-003**, the way `amendments_approved_on_the_one_time_command_bootstrap` is pinned at one — a
second unbacked approval still turns it red. **This is deliberately not applied**, because turning a
red row on a mandatory V1 §A precondition green is a change to what a pass condition reports, and
`PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1` §E reserves that to the founder.

**The alternative to the split, and it is his to choose.** He can instead re-approve PCCR-003
through the now-working governance door, which writes a real ledger row and clears the check with no
change to any board. That would also populate `public.phase_c_governance_decision`, which holds **0
rows** today — and four FD-01 requirements (immutable decision, exact decision, single-use
consumption, replay returns `ALREADY_DECIDED`) cannot be executed by any audit until it holds one.

## 5. Owner

`risk_and_governance_manager`, as the accountable role for founder-authority controls. Built by the
session of 26 Aug 2026.

## 6. Reviewer

Raised by the same session that found it, immediately after that session completed the independent
Phase D acceptance audit — so it has **no independent reviewer**, and that is stated rather than
implied. The audit report it corrects,
`PHASE_D_V1_FINAL_INDEPENDENT_AUDIT.md`, recorded FD-01 line 6 as PASSING; that was wrong, because
the forged-claims probe was not run. The correction is recorded in the same artifacts.

## 7. Gate impact

No gate is added, removed, weakened or re-scoped. The 32 gates are untouched. One gate becomes
strictly harder to pass: GATE-020 and every founder-boundary predicate that resolves through
`fn_phase_c_require_founder` gains a connection requirement it did not have. Nothing that passes
today on a real bearer token stops passing.

## 8. Security and privacy impact

This is a security change and it only tightens. No identity is revealed, no retention window moves,
no data becomes readable to anyone it was not readable to. The forgeable path is removed; the
verified path is unchanged.

## 9. Financial impact

**None to any price, fee, payout or provider charge, and the money boundary is strengthened.**
`public.refunds` holds 0 rows and `public.phase_c_refund_decision` holds 0 rows, before and after
every probe in this document. The single financial effect is that the refund decision service stops
accepting a founder identity that a migration connection asserted about itself. The founder's
standing rule — every refund, at any amount, needs him in a verified session — becomes enforceable
rather than assumed. Cost of the change: **AED 0**; no paid provider is called and every external
route remains held.

## 10. Backward compatibility

No historical record is deleted, edited or back-dated. The five amendments recorded
`AUTHENTICATED_FOUNDER_SESSION` were written by `scripts/phase_d/approve_pccr_amendments.mjs`
through `/rest/v1/rpc/…` with a GoTrue bearer — `session_user = 'authenticator'` — and are
undisturbed. `phase_c_refund_decision` and `refunds` are empty, so no recorded decision is affected.
The only callers that stop working are management and migration connections, which is the change.

## 11. Rollback and migration

| | |
|---|---|
| migration | `scripts/sql/phase_c_the_founder_door_read_a_setting.sql` — **to be written on approval** |
| rollback | `scripts/sql/down/phase_c_the_founder_door_read_a_setting_down.sql`, restoring the PCCR-003 body verbatim |
| amendment | subject `founder_authentication`, object `fn_phase_c_require_founder(p_actor text)`; prior digest `3fc51958472a20c785214f7142f635c83f0c349e51d8246e4a6ba7c0b42574d6` (the body PCCR-006 Amendment A left live); new digest allocated on apply |
| amendment id | to be allocated by `public.phase_c_freeze_amendment` on approval |
| verification | the probe in §2 re-run and required to return `28000`; `fn_phase_c_founder_subject_bind` through `service_role` still reaching its identity check; `fn_phase_a_baseline_drift()` and `fn_phase_b_baseline_drift()` both 0 rows |

## 12. Founder approval

Required, because `fn_phase_c_require_founder(p_actor text)` is a frozen Phase C subject
(`public.phase_c_frozen_subject`, subject `founder_authentication`). **Not given. Not assumed.**

Approve it the way PCCR-006 was approved — as a **new command** in the Command Center, so the words
land in `public.founder_command_message` with their own `raw_text_hash`:

> I approve PCCR-007 — the founder door read a setting — as set out in
> `docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-007.md`, sha256 `<D>`.

`<D>` is `sha256sum docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-007.md` at the commit that introduces
this file, stated in that commit's message. Since 26 Aug 2026,
`fn_phase_c_governance_decide` **requires** that a founder command message names both the change
request and the digest before it will record a decision, so the sentence above is not ceremony — an
approval that does not quote the digest is refused.

Please also say, in the same message or a second one, which of the two §4 options you want for the
PCCR-003 row: the pinned board split, or re-approving PCCR-003 through the governance door.
