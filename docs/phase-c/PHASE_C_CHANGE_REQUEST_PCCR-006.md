# PCCR-006 — `governance_approval_authenticity`: founder approval on the governance path is a typed string

**Status on 24 Aug 2026: RAISED. NOT APPROVED. NOT APPLIED.**
`public.fn_phase_c_require_founder` is running its amendment-36 body. `public.fn_phase_c_freeze_drift()`
reads `frozen_subjects_drifted` **0 of 25** and `amendments_awaiting_founder_approval` **0 of 5**.
Nothing in this session changed a frozen subject and nothing in this document records an approval.

**This is a security correction, and it is the one Gate 1 of the final independent acceptance audit
failed on.** The fix PCCR-003 already made on the money path was never made on the governance path.

---

## The defect, measured by execution

Every probe below ran on production `htdblwldjkcgjvmqkbeh` on 24 Aug 2026 inside a `DO` block whose
last statement is `raise exception`, so each one rolled back. Verified afterwards: PCCR-004 still
`DEFER_OR_REJECT`, PCCR-005 still `DEFERRED`, `phase_c_freeze_amendment` still 5 rows,
`phase_c_founder_auth_event` still 0 rows, `fn_phase_c_freeze_drift()` 0 not-ok,
`fn_phase_d_fixture_residue()` 0.

### A. Writing an approver onto a DEFERRED request silently re-dispositions it

```
update public.phase_c_change_request
   set approved_by='management@quotesdone.com', approved_at=now()
 where change_request_ref='PCCR-004';
→ ACCEPTED
→ disposition=APPROVED  approved_by=management@quotesdone.com
   reason="Founder disposition, 24 Aug 2026. The frozen cancellation servic…"
```

PCCR-005 behaves identically. The CHECK `phase_c_change_request_deferral_is_not_approval` is real
and it never fires, because the BEFORE trigger `a15_phase_c_change_request_disposition_follows_approval`
has already rewritten `disposition := 'APPROVED'` by the time the CHECK is evaluated. The row that
comes out **carries the deferral's own reason text as its approval reason**.

### B. A disposition can be set to APPROVED with no approver at all

```
update public.phase_c_change_request
   set disposition='APPROVED', disposition_reason='…', disposition_recorded_at=now()
 where change_request_ref='PCCR-005';
→ ACCEPTED  → disposition=APPROVED  approved_by=(null)
```

The audit did not name this one. Nothing on any board reads `phase_c_change_request` at all — every
governance row on the freeze board is about `phase_c_freeze_amendment`.

### C. A direct row can claim a verified session it never had

```sql
insert into public.phase_c_freeze_amendment (…, approved_by, approval_basis, approval_route,
       approval_auth_subject, approved_amendment_table_digest, …)
values (…, 'management@quotesdone.com', 'AUTHENTICATED_FOUNDER_SESSION', 'auth.uid()',
        '1256c7ec-17bf-4b1e-af8f-aaa32a8fdd14', repeat('a',64), …);
→ ACCEPTED
```

Every constraint checks only the **shape** of the claim: the route is in a list, the subject is not
null, the digest matches `^[0-9a-f]{64}$` — and `repeat('a',64)` passes.

### D. The finding the independent audit did not reach, and the deepest one

**The canonical approval service itself can be walked past from migration SQL.**

```
perform public.fn_phase_c_founder_subject_bind('1256c7ec-…'::uuid);
→ BIND ACCEPTED: {"ok": true, "event_id": 974, "identity": "management@quotesdone.com"}

select public.fn_phase_c_freeze_amendment_approve('{…,"amendment_table_digest":"aaaa…64",…}');
→ ACCEPTED: {"outcome":"APPROVED_IN_VERIFIED_SESSION",
             "approval_route":"fn_phase_c_founder_subject_bind",
             "approval_auth_subject":"1256c7ec-17bf-4b1e-af8f-aaa32a8fdd14"}
```

`fn_phase_c_freeze_amendment_approve` is a good service. It resolves the identity through
`fn_phase_c_require_founder`, derives `approved_by` internally, records the route and the subject,
refuses a bundled call, and is idempotent. **With no bind it refuses `28000` — verified.** But
`fn_phase_c_founder_subject_bind` refuses only `current_user in ('anon','authenticated')`, and the
management API connects as `postgres`, which is neither. So a migration can mint a founder auth
event **with no bearer token in existence**, and everything downstream then behaves exactly as it
would for a real session.

### E. What already holds, so the finding is not read as larger than it is

- A **non-founder** approver is refused: `attacker@example.invalid` → `23514
  pccr_approver_not_the_founder`. `fn_phase_c_founder_approver_guard` is real; it is a string
  comparison against `public.phase_c_founder_identity`, and that is all it is.
- The **refund** door holds: `fn_phase_c_require_founder('management@quotesdone.com')` with no
  session → `28000 not the founder: no verified auth subject on this call`.
- `scripts/checks/pccr_approval_matches_committed_tables.test.mjs` recomputes the sha256 of the
  committed amendment tables and would fail a forged `repeat('a',64)`. It is a **repository check,
  not a write guard**, it covers `phase_c_freeze_amendment` only, and Phase D deploys
  production-direct — so a forged row would be live for the whole window between apply and merge.

---

## The load-bearing fact this correction rests on

| `session_user` | `application_name` | what it is |
|---|---|---|
| `postgres` | `mgmt-api` | migration / management SQL (`scripts/apply_sql.mjs`) |
| `authenticator` | `postgrest` | the ONLY connection that can carry a verified user JWT |

Measured on this project, 24 Aug 2026:

- `postgres` has `rolsuper = false`;
- `set session authorization service_role` from `postgres` → **refused, `42501`**;
- `set local role service_role` changes `current_user` and leaves `session_user = postgres`;
- `pg_stat_activity` shows PostgREST connecting as `authenticator`, and the founder's own approval
  path (`scripts/phase_d/approve_pccr_amendments.mjs`) reaches the database through
  `/rest/v1/rpc/…` with a GoTrue-issued bearer token.

So **`session_user` is an identity a migration cannot forge**, and `session_user = 'authenticator'`
is exactly the set of connections through which a founder's bearer token can arrive.

**The boundary, stated so it is not read as larger than it is.** `supabase_admin` IS a superuser on
this project and could `set session authorization`. We do not hold its credentials and no path in
this repository uses it. This correction closes the paths this estate actually has; it does not
claim the platform owner cannot write a row.

---

## The complete amendment table

### Amendment A — the only FROZEN Phase C subject this change touches

| Field | Value |
|---|---|
| **Amendment ID** | to be allocated by `public.phase_c_freeze_amendment` on approval; change request **PCCR-006** |
| **Subject** | `founder_authentication` — the ONLY one of the seven subjects named in the session brief that is registered in `public.phase_c_frozen_subject`. The other six (`phase_c_change_request`, `phase_c_freeze_amendment`, the a15 trigger, `fn_phase_c_founder_approver_guard`, the approval RPC, `fn_phase_c_freeze_drift`, `phase_c_founder_auth_event`) are **not frozen subjects** — verified against all 25 rows — and are amended under this same change request without a freeze-amendment row. |
| **Frozen object** | `public.fn_phase_c_require_founder(p_actor text)` |
| **Current approved value** | Digest `e0f8f63e14238a83…` (sha256 of `pg_get_functiondef`), which is amendment 36's `new_digest` — the body PCCR-003 introduced and the founder approved in a verified session on 21 Aug 2026. The prior frozen digest was `b2fff88d695729dd…`. |
| **Proposed value** | The same body plus **one predicate** on Route B: `and e.action_class is null`. Route A, the signature, the return, the message text and every caller are unchanged. Digest computed on application and recorded as `new_digest`. |
| **Current source digest** | `e0f8f63e14238a8319ea79b401c57ba4c81380a8aac6baa176e4c165eb20cabc` |
| **Proposed source digest** | recorded on application; the proposed body is committed verbatim in `scripts/sql/phase_c_pccr006_governance_approval_authenticity.sql` §3 |
| **Exact reason** | PCCR-006 introduces purpose-bound founder auth events (`action_class = 'GOVERNANCE_DECISION'`, carrying the change request, the decision and the amendment-table digest). Without this predicate, a session minted to approve a change request would **also satisfy the refund door in the same transaction**. A session issued for one act must not pay for another. |
| **Exact audit evidence** | Gate 1 of `PHASE_D_FINAL_INDEPENDENT_ACCEPTANCE_20260824.md`, plus probes A–D above, each re-measured independently in this session in aborted transactions. |
| **Affected tables** | none directly. It reads `public.phase_c_founder_auth_event` and `public.phase_c_founder_identity`. |
| **Affected routines** | `fn_phase_c_require_founder` itself. Its callers — `fn_kernel_refund_decision_record`, `fn_phase_c_freeze_amendment_approve` and the refund guards — are unchanged and keep working: their events carry `action_class IS NULL`. |
| **Affected Edge Functions / APIs** | none. No signature, parameter or return changes. |
| **Caller and grant impact** | none. `proacl` is `{postgres=X/postgres,service_role=X/postgres}` and stays so; `CREATE OR REPLACE` preserves the ACL. |
| **Security impact** | Strictly tightening. It removes a cross-purpose spend of a verified session and adds no new acceptance. |
| **Privacy impact** | none. No new column, no new data, no PII. |
| **Founder-boundary impact** | It **strengthens** one: the refund boundary (`refund_only_founder_approval`) can no longer be satisfied by a session minted for a governance decision. |
| **Phase A impact** | none. `fn_phase_a_baseline_drift()` 0 rows. |
| **Phase B impact** | none. `fn_phase_b_baseline_drift()` 0 rows; the baseline 30 / 257 / 56 / 54 / 32 / 159 / 347 is untouched. |
| **Backward compatibility** | Full. Every event that exists today has `action_class IS NULL` (the column does not exist yet, and the migration adds it nullable). Both live routes keep working. |
| **Migration** | `scripts/sql/phase_c_pccr006_governance_approval_authenticity.sql` §3 |
| **Exact rollback** | `scripts/sql/phase_c_pccr006_governance_approval_authenticity_down.sql` §5 re-applies the body whose sha256 is `e0f8f63e14238a83…`, read out of production with `pg_get_functiondef` before the change was written. One statement, no data change. |
| **Positive tests** | valid founder JWT → `fn_phase_c_governance_decide` records exactly one decision; the refund door still admits a refund session (`action_class IS NULL`). |
| **Negative tests** | a governance-class event presented to `fn_phase_c_require_founder` → `28000`. |
| **Already present on any branch** | **No.** Committed, not applied. |
| **Already present on production** | **No.** |
| **Consequence of approval** | A verified governance session becomes single-purpose. |
| **Consequence of rejection** | A session minted to approve a change request can also authorise a refund in the same transaction. |

### Amendments B–H — the governance path itself (no frozen subject; same change request)

| # | Object | Now | Proposed | Why |
|---|---|---|---|---|
| **B** | `public.fn_phase_c_founder_subject_bind(uuid)` — digest `e119c18c53788c0e…` | refuses only `current_user in ('anon','authenticated')` | refuses unless `session_user = 'authenticator'` | **This is the root cause of finding D.** The deny-list named two roles and not `postgres`, so migration SQL minted founder sessions. The positive condition names the one connection that can carry a JWT. |
| **C** | `public.phase_c_founder_auth_event` | `event_id, auth_subject, identity, route, txid, bound_by, bound_at` | adds `action_class, object_ref, decision, amendment_table_digest, nonce, issued_at, expires_at, consumed_at, consumed_by`; CHECK binding all of them when `action_class='GOVERNANCE_DECISION'`; `expires_at ≤ issued_at + 10 min`; UNIQUE nonce; trigger `a00_…_is_server_minted` refusing an INSERT unless `session_user='authenticator'`, refusing every UPDATE but the single-use consumption stamp, refusing DELETE, and a truncate guard | §2.7–2.8: short-lived, single-use, consumed atomically, transaction-bound, unusable for another request, digest or decision. All columns nullable so the refund path's existing events stay legal. |
| **D** | *(new)* `public.phase_c_governance_decision` | — | append-only ledger: change request, decision, approval reason, amendment-table path **and** digest, decided_by, decided_at, approval basis/route/auth subject, `auth_event_id` UNIQUE, nonce UNIQUE, txid; UNIQUE `(change_request_ref, decision, digest)` so replay makes no second row; BEFORE trigger re-reading the auth event and refusing a mismatch on txid, action class, object, decision, digest, nonce, identity, expiry or non-consumption; UPDATE and DELETE refused | §2.11: approval derived from an immutable governance-decision ledger. |
| **E** | *(new)* `public.fn_phase_c_governance_decide(p_input jsonb)` | there was **no** approval service for a change request at all | the one canonical service. Refuses unless `session_user='authenticator'`; derives the identity from `auth.uid()` or the bound verified subject; **refuses a call that supplies `approved_by`, `approved_at`, `approval_basis`, `approval_route`, `approval_auth_subject`, `disposition` or `decided_by`**; requires the change request, the decision, the amendment-table path and its exact digest and a reason; mints and consumes a purpose-bound event in the same transaction; idempotent on replay | §2.5–2.6. `fn_phase_c_freeze_amendment_approve` keeps its name and its job — it approves one freeze **amendment**; this is its sibling for the change **request**. |
| **F** | `public.phase_c_change_request` | `approved_by`, `approved_at`, `disposition` directly writable; a15 flips the disposition | adds `approval_reason` (separate from `disposition_reason` — §2.4), `approval_basis`, `approval_route`, `approval_auth_subject`, `approved_amendment_table_digest`, `governance_decision_id` FK; CHECK `(approved_by IS NULL) = (governance_decision_id IS NULL)`; CHECK approval_reason only on APPROVED; BEFORE trigger `a05_…_approval_is_derived` refusing ANY write to the disposition or any approval column that is not this transaction's ledger row | §2.1, §2.11, §2.12. Fires before a10 and a15, so "not a verified session" is answered first. |
| **G** | `fn_phase_c_change_request_disposition_follows_approval()` — digest `d58329f04c9d3556…` | writing an approver rewrites `disposition := 'APPROVED'` and, if no reason is given, keeps the deferral's | the forward half is **removed**. Only the reverse remains: clearing an approver returns the row to RAISED and blanks every approval column | §2.2, §2.3. O15 added the forward half for a real reason — the CHECK refused a legitimate approval because approver and disposition were two statements. The service now sets both in one derivation, so the trigger no longer has to guess, and the guess was the defect. |
| **H** | `public.phase_c_freeze_amendment` + `fn_phase_c_freeze_drift()` — digest `44d3253af459f7e9…` | a direct row may claim `AUTHENTICATED_FOUNDER_SESSION`; the board carries no row about `phase_c_change_request` | adds `approved_amendment_table_path` (so a SECOND amendment document can be verified without invalidating the first five — which is what would otherwise happen the moment PCCR-006's own table was committed) and a BEFORE trigger refusing an unbacked session claim; the board gains two rows, spliced after its complete final emit with the existing eight carried byte-identically | §2.10, §2.13. |

### The exact negative cases §2 requires, and where each is refused

| case | refused by |
|---|---|
| typed founder email, no verified session | `fn_phase_c_governance_decide` §1 → `28000 pccr_governance_no_verified_session` |
| arbitrary `approved_by` on deferred PCCR-004 | `a05_phase_c_change_request_approval_is_derived` → `42501` |
| arbitrary `approved_by` on deferred PCCR-005 | same |
| direct `disposition='APPROVED'` | same |
| arbitrary auth subject | the ledger trigger compares `approval_auth_subject` to the event's `auth_subject` |
| arbitrary 64-character digest | the ledger trigger compares to the event's `amendment_table_digest`, which only a verified session could mint |
| valid event bound to another request | ledger trigger → `pccr_governance_wrong_object` |
| valid event bound to another digest | ledger trigger → `pccr_governance_wrong_digest` |
| expired event | ledger trigger → `pccr_governance_auth_event_expired` |
| reused event | UNIQUE `auth_event_id`, UNIQUE nonce, and the auth-event trigger's `pccr_auth_event_replayed` |
| written instruction presented as a founder session | there is no column to write it into; `approval_basis` is derived |
| migration / management SQL with no verified event | `session_user <> 'authenticator'` on the service, on the bind door AND on the auth-event insert |
| direct freeze-amendment session claim | `a05_freeze_amendment_session_claim_is_verified` → `28000` |

### The positive case

Valid enabled founder JWT through `/rest/v1/rpc/fn_phase_c_governance_decide` → the exact current
amendment-table digest → a same-transaction verified auth event minted and consumed → the exact
change request and decision → the approval succeeds exactly once, the freeze board reflects it,
replay returns `ALREADY_DECIDED` and writes no second row.

---

## Where CI sits in this

`scripts/checks/pccr_approval_matches_committed_tables.test.mjs` continues to hash the committed
amendment table and compare it to each stored digest — extended to hash the file each row NAMES, so
this document can be verified without invalidating the five approvals recorded against
`PHASE_D_PCCR_AMENDMENT_TABLES.md`. **CI is a secondary integrity check and not a substitute for the
production write guard**, which is the whole reason it was insufficient: it is a repository check,
it covers one table, and it cannot see the window between a production-direct apply and its merge.

---

## The bootstrap founder-approval procedure

PCCR-006 closes the door it must be approved through. That is not circular, but it does need one
stated bootstrap, and the bootstrap must not be any of the things it forbids.

**Not used, and why:** chat text alone (no record in the estate); SQL typed by Claude (a `postgres`
connection is exactly the identity finding D names); a migration-written `approved_by` (finding C);
a caller-supplied founder email (finding A); written-instruction-only approval
(`fn_phase_c_freeze_drift` already counts these separately and it must stay at 0).

### The path, and what was measured about each step

**The founder logs into the QuotesDone Command Center and submits the approval sentence and its
sha256.** Everything below was measured on production at HEAD `521ed16` on 24 Aug 2026.

| step | what happens | measured |
|---|---|---|
| 1 | The browser POSTs `{action:'founder_command', message:'<the sentence>'}` to `os_api` | `os_api` is deployed **ACTIVE v74**, `verify_jwt=false` with its own in-function gate |
| 2 | `os_api` verifies the bearer token | *"No token is 401, not a fallback. An invalid token is 401. A valid token belonging to somebody who is not an admin is 403. There is no fourth branch."* — `admin.auth.getUser(token)` at `supabase/functions/os_api/index.ts:199`. The build-mode open-door identity was removed by kernel K0 on 17 Aug 2026 |
| 3 | The `x-os-key` header bypass is not a way in | it is read-only by classification, and `public.app_secrets` holds **0** rows for `os_bypass_key` — measured, so nothing can present it |
| 4 | `os_api` passes the **verified** email to `fn_founder_command_submit` | `p_founder_identity: email`, where `email` came from `getUser`, not from the request body |
| 5 | The routine refuses a non-founder | `not_the_founder` unless the identity is active in `public.phase_c_founder_identity`. Active today: `management@quotesdone.com`, `ahmadalzain1993@admin.quotesdone.com` |
| 6 | A browser cannot call the routine directly | `fn_founder_command_submit` EXECUTE grants are **`postgres`, `service_role`** only — no `anon`, no `authenticated` |
| 7 | The routine is a **frozen Phase C subject** | `chief_of_staff_command_path`; live `pg_get_functiondef` digest **`b4dbfd58037838d3`** = the frozen digest. Undrifted |
| 8 | The record it writes is immutable | `public.founder_command_message` carries `raw_text` and `raw_text_hash = sha256(raw_text)`; `z10_founder_command_message_immutable` refuses **UPDATE and DELETE**; `z00_kernel_truncate_guard` refuses TRUNCATE |
| 9 | A second, independent record is written | `fn_phase_c_trace_write('TRACE-FOUNDER-COMMAND', …)` with `input_hash = sha256(text)`. The trace ledger is append-only and is itself a frozen subject (`fn_phase_c_trace_append_only`) |
| 10 | **Nothing is executed** | the sentence classifies as `AMBIGUOUS` / `CLARIFICATION_REQUIRED`, confidence 0.0, *"no registered command intent matches this instruction"* — executed against `fn_founder_command_classify` here. That branch returns `tasks_created: 0`, `workflow_ids: []`, `task_ids: []`. No task, no workflow run, no plan |
| 11 | The builder verifies the record | reads `founder_command_message` for a row whose `founder_identity` is an active founder, whose `raw_text_hash` equals the sha256 of the exact sentence, and whose `received_at` is after this document's commit; and the matching `TRACE-FOUNDER-COMMAND` row |
| 12 | The exact PCCR-006 migration is applied | `node scripts/apply_sql.mjs scripts/sql/phase_c_pccr006_governance_approval_authenticity.sql --apply --ddl`, then the entry moves from `scripts/sql/PENDING.txt` to `scripts/sql/MANIFEST.txt` |
| 13 | Every future governance approval uses the new service | `fn_phase_c_governance_decide`, transaction-bound, single-use, server-derived. **This bootstrap is used exactly once** |

**Boundary on step 10.** `fn_founder_command_classify` was executed here against the approval
sentence with a placeholder digest, because the real digest is the sha256 of this file and this
paragraph is inside it. The classifier matches against `public.phase_c_command_rule`, which is data
and reads no hex string — it returned `AMBIGUOUS`, confidence 0.0, *"no registered command intent
matches this instruction"*. The digest's value cannot change that, but the sentence with the real
digest was not itself put through the classifier and is not claimed to have been.

### The residual weakness in the bootstrap, stated rather than hidden

`founder_command_message` records the founder identity as a **string** and does not record
`auth.uid()`. The JWT verification happens in `os_api`, not in the database. So the row is strong
evidence and is **not self-proving**: a `postgres` connection could call the same frozen routine
with the same identity string and produce an indistinguishable row.

What narrows it, each measured rather than asserted:

- no such call exists anywhere in this repository — `os_api` is the only caller of
  `fn_founder_command_submit` in `supabase/functions/` and `src/`;
- `canonical_routine_manifest.mjs --all` reads **0** repository→production drift, **0**
  production→repository drift and **0** uncommitted application DDL, so no unlisted routine could
  make the call either;
- the builder states, in the same hand-over, that no SQL was applied between this document's commit
  and the verification read — and the manifest is the check on that statement;
- the window is minutes, used once, for one sentence whose digest is fixed in advance.

**This weakness is the reason PCCR-006 exists**, and PCCR-006's Amendment C closes it permanently
for governance decisions by minting the auth event server-side and refusing any INSERT whose
`session_user` is not `authenticator`. If the founder prefers, the alternative bootstrap is
`scripts/phase_d/approve_pccr_amendments.mjs`, which mints a real founder bearer token and reaches
the database through `/rest/v1/rpc/…` as `authenticator` — a stronger record, at the cost of the
founder handing over a live credential to a script rather than typing a sentence into his own
screen. Both are offered; the Command Center path is the one this document recommends because he
drives it himself and nothing else holds his token.

## What the founder is being asked for

The exact one-sentence approval required, and nothing else:

> **I approve PCCR-006 — governance_approval_authenticity — as set out in
> `docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-006.md`, sha256 `<P6>`.**

`<P6>` is the sha256 of **this file as committed**, deliberately not written inside the file — a
digest that quotes itself cannot be recomputed. It is read with:

```bash
sha256sum docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-006.md
```

and it is stated in the commit that introduces this section and in the decision packet that
accompanies it. He types that sentence, with the digest filled in, into the Command Center.

- **Amendment table:** `docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-006.md`
- **Proposed migration:** `scripts/sql/phase_c_pccr006_governance_approval_authenticity.sql`
- **Exact rollback:** `scripts/sql/phase_c_pccr006_governance_approval_authenticity_down.sql`

**This builder session did not and cannot approve its own Phase C change.** Nothing in
`phase_c_change_request` or `phase_c_freeze_amendment` moved.

---

## Execution record — appended after approval, 25 Aug 2026

**Everything above this line is what the founder approved and it is unchanged.** This section is a
record of what happened when it was applied. It is appended because
`scripts/checks/freeze_amendment_names_a_real_change_request.test.mjs` requires the change request to
name the amendment id its approval produced — *"an amendment may not shelter under another
amendment's paperwork"* — and the amendment id cannot exist until the change is applied. The
amendment table above says so: *"Amendment ID: to be allocated by `public.phase_c_freeze_amendment`
on approval"*.

### The approved digest is preserved, not overwritten

Appending changes this file's sha256. The digest the founder quoted is the digest of the file **as
he approved it**, and it is immutable in git:

```bash
git show ac7ab8e:docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-006.md | sha256sum
# c787bfcfe38578010f29e4ed2dcaddc602be42f16eb3a320aab6f75519561ceb
```

`ac7ab8e` is the commit that was HEAD when he submitted his approval. Recomputing the digest of the
**working file** after this section will not equal `c787bfcf…`, and should not: the two are
different bytes and only one of them is what he read.

### The approval

| | |
|---|---|
| Command Center command | **39505** |
| message | **40674**, channel `command_center` |
| received | `2026-08-25 16:54:20.940141+00` |
| founder identity | `management@quotesdone.com` — active, kind `email` |
| `raw_text_hash` | `53edf1251bcee9123d587f4f3dc13c11aca184547cac12edd9fc7491511924ad`, recomputed on production and equal |
| root trace | **4329096**, `TRACE-FOUNDER-COMMAND` |
| audit | `os_audit_log` 19027 |
| business work created | `tasks_created` 0, `workflow_ids` [], `task_ids` [], no external effect |

### Amendment A, as allocated

| | |
|---|---|
| **amendment_id** | **51** |
| subject | `founder_authentication` |
| frozen object | `fn_phase_c_require_founder(p_actor text)` |
| prior digest | `b2fff88d695729ddc8134532908ca0dd9fb3697f80bd7457d8ec35ab5a601e24` |
| new digest | `3fc51958472a20c785214f7142f635c83f0c349e51d8246e4a6ba7c0b42574d6` |
| approval basis | `AUTHENTICATED_FOUNDER_COMMAND_BOOTSTRAP` |
| `deployed_before_approval` | `false` — the approval came first |

**The prior digest is the FROZEN BASELINE, not the body this change replaced.**
`fn_phase_c_freeze_drift` judges a subject undrifted when an amendment carries the baseline as its
prior digest and the live body as its new one, because *"an edit on top of an amendment is drift"*.
The body actually replaced was `e0f8f63e14238a83…`, amendment 36's new digest — the one PCCR-003
introduced. Amendment 36 correctly stops matching the live body from here.

### One correction was made to the migration before it was applied

The committed migration **did not apply as written**. Its new CHECK
`phase_c_change_request_approval_is_derived` was violated by **PCCR-003** — the founder's real
approval of 21 Aug 2026, which has an approver and no `governance_decision_id` because this
migration creates that column. It was corrected to `NOT VALID` (still enforced on every INSERT and
UPDATE; only the retroactive scan is skipped) with an assertion that the grandfathered set is
exactly PCCR-003. Back-filling PCCR-003 was refused: minting a ledger row for a decision that
predates the ledger is the defect this change request exists to close. Full rehearsal:
`docs/phase-c/PCCR-006_PRE_APPROVAL_REHEARSAL.md`.

### This register row says RAISED and cannot say APPROVED

`phase_c_change_request.disposition` for PCCR-006 is `RAISED`. That is this change request working
on itself: `phase_c_change_request_approval_is_derived` now requires a `governance_decision_id`
beside any `approved_by`, only `fn_phase_c_governance_decide` can create one, and only on a
connection whose `session_user` is `authenticator`. The change request that created that rule cannot
satisfy it retroactively without the unbacked write it forbids. Its approval is recorded on
`public.phase_c_freeze_amendment` as amendment 51, and the register row's `disposition_reason` says
so in full. **Every change request after this one reaches APPROVED through the canonical service.**

### The four required elements this document was missing

`scripts/checks/freeze_amendment_names_a_real_change_request.test.mjs` checks every change request
named by an amendment against the element list in `PHASE_D_CHANGE_CONTROL.md`. It could not check
PCCR-006 until an amendment named it, which happened only when the change was applied — so these
four absences were invisible until 25 Aug 2026, and the check found them the moment it could see the
document. They are completed here rather than quietly left.

**Current behaviour.** Founder approval on the governance path is a typed string. Measured on
production and reproduced immediately before application: writing `approved_by` onto a DEFERRED
change request silently re-dispositions it to APPROVED and carries the deferral's own text as the
approval reason (findings A and A2); a disposition can be set to APPROVED with no approver at all
(finding B); a direct row can claim `AUTHENTICATED_FOUNDER_SESSION` with a 64-character digest of
`repeat('a',64)` (finding C); and `fn_phase_c_founder_subject_bind` refused only
`current_user in ('anon','authenticated')`, so a `postgres` connection could mint a verified founder
session with no bearer token in existence (finding D). Finding D reaches further than the change
request first stated: running the bind door and then the refund door in one transaction, **the
refund door accepted** — a session minted for one act paid for another.

**Proposed behaviour.** Approval is DERIVED, never asserted. `fn_phase_c_governance_decide` is the
one canonical service; it refuses any connection whose `session_user` is not `authenticator`,
derives the identity from `auth.uid()` or a bound verified subject, refuses a caller that supplies
`approved_by`, `approved_at`, `approval_basis`, `approval_route`, `approval_auth_subject`,
`disposition` or `decided_by`, and mints and consumes a purpose-bound, single-use, ten-minute
auth event in the same transaction. The decision lands in an append-only ledger
(`public.phase_c_governance_decision`) whose UPDATE and DELETE raise unconditionally and whose
TRUNCATE is refused, and `phase_c_change_request.disposition` can then only move as a derivation
from that ledger row. Replay returns `ALREADY_DECIDED` and writes no second row.

**Reviewer.** Raised by the builder session of 24 Aug 2026 and rewritten by an adversarial pass on
25 Aug that rehearsed the migration on production before approval and found that **it did not
apply** — see `docs/phase-c/PCCR-006_PRE_APPROVAL_REHEARSAL.md`. Approved by the founder,
`management@quotesdone.com`, Command Center command 39505. **No independent reviewer has audited it
yet**; `docs/phase-d/PHASE_D_Q_SERIES_BUILDER_EVIDENCE.md` is labelled
`BUILDER_EVIDENCE_PENDING_FINAL_AUDIT` and this change is inside that scope. Stating that plainly is
part of the element, not a substitute for it.

**Financial impact: none, and the money boundary is strengthened.** No price, fee, refund, payout or
provider charge is touched. `public.refunds` is 0 throughout and `public.phase_c_refund_decision`
holds 0 rows. The one financial effect is a tightening: Amendment A's single predicate
(`and e.action_class is null`) stops a session minted for a governance decision from also satisfying
the refund door, which finding D showed it could. The founder's standing rule that every refund at
any amount needs his approval in a verified session is unchanged and now harder to circumvent, not
easier. Cost of the change itself: AED 0 — no paid provider was called at any point, and every
external route remains held.
