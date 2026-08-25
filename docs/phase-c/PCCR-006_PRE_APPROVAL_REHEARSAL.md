# PCCR-006 — pre-approval rehearsal

**This is not an approval and it does not record one.** It is the answer to one question, measured
rather than assumed: *if the founder approves PCCR-006, will the committed migration actually
apply, and will FD-01 then pass?*

Rehearsed on production `htdblwldjkcgjvmqkbeh`, 25 Aug 2026, inside a single transaction ending in
`raise exception`. Nothing survived: `phase_c_change_request` unmoved (PCCR-004 `DEFER_OR_REJECT`,
PCCR-005 `DEFERRED`), `phase_c_founder_auth_event` 0 rows, `phase_c_governance_decision` does not
exist.

Reproduce with the file itself, prefixed `begin;` and suffixed with the probe block quoted in §3.

---

## 1. The committed migration did not apply

```
ERROR: 23514: check constraint "phase_c_change_request_approval_is_derived"
              of relation "phase_c_change_request" is violated by some row
```

The row is **PCCR-003** — the founder's real approval of 21 Aug 2026, `approved_by
management@quotesdone.com`, `approved_at 2026-08-21 20:20:33+00`. It has an approver and no
`governance_decision_id`, because **this migration creates that column**.

The constraint's predicate names a column the migration itself introduces, and was then checked
against rows that predate it. A genuine historical approval failed a rule that could not have
existed when it was given. Had this been applied on the strength of an approval, it would have
errored at the first statement of section 5 and left the change half-made.

### The correction, and why it is not a weakening

```sql
ADD CONSTRAINT phase_c_change_request_approval_is_derived CHECK (
  (approved_by IS NULL) = (governance_decision_id IS NULL)) NOT VALID;
```

Postgres enforces a `NOT VALID` CHECK on **every INSERT and every UPDATE**. What it skips is the
retroactive scan. So from application onward an approver without a ledger row is refused — which is
the entire point — and one real approval taken before the ledger existed is grandfathered rather
than deleted or back-filled.

**Back-filling was the alternative and it is refused.** Giving PCCR-003 a `governance_decision_id`
means minting a ledger row for a decision that predates the ledger — inventing the verified session
it never had, which is precisely the defect this change request exists to close.

**The grandfathered set is asserted, not assumed.** The migration now fails if that set is anything
other than exactly `PCCR-003 (management@quotesdone.com, 2026-08-21)`, so a second unbacked approval
cannot arrive under this allowance between now and the day it is applied.

### What this changes, and what it deliberately does not

| | |
|---|---|
| `scripts/sql/phase_c_pccr006_governance_approval_authenticity.sql` | `ec37b870c4ffb80717623c29cd6aa566341eced98673c617f00efb2ad7b73044` → **`ff5929e646cb027962984dfbb0dee3459426e6ff8eddc183e8c9dcc54bdfdf6d`** |
| `…_down.sql` | `a9d5475018115281a7d6b9604ef13496bbc3922b15b3def10fb0241fa1f3e299` — **unchanged**; it already drops the constraint by name |
| `docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-006.md` | `c787bfcfe38578010f29e4ed2dcaddc602be42f16eb3a320aab6f75519561ceb` — **unchanged** |

**The document is deliberately untouched**, so the approval sentence PCCR-006 asks for still carries
the digest it always did and the founder's wording does not have to change. The document names the
migration by path and never by digest, so nothing in it has become false.

**The founder's instruction said "use the exact committed migration".** It could not be satisfied:
the exact committed migration does not apply. This is stated here rather than worked around, and the
correction is one clause with its reasoning beside it.

---

## 2. With that one correction, the whole migration applies

Every object FD-01 requires is built:

```
fn_phase_c_governance_decide                     true
phase_c_governance_decision                      true
phase_c_founder_auth_event.action_class          true
phase_c_founder_auth_event.nonce                 true
phase_c_change_request.governance_decision_id    true
a05_phase_c_change_request_approval_is_derived   true
a05_freeze_amendment_session_claim_is_verified   true
```

---

## 3. FD-01, as far as a `postgres` connection can reach

| FD-01 # | case | result |
|---|---|---|
| 1, 3 | typed founder email onto **DEFERRED PCCR-004** | **REFUSED** `42501` — *the disposition and every approval column are derived* |
| 3 | the same onto **DEFERRED PCCR-005** | **REFUSED** `42501` |
| 2 | direct `disposition = 'APPROVED'` with no approver | **REFUSED** `42501` |
| 6 | a `phase_c_freeze_amendment` row claiming `AUTHENTICATED_FOUNDER_SESSION` from a migration | **REFUSED** `28000` — *a row may not claim AUTHENTICATED_FOUNDER_SESSION without…* |
| 12 | `fn_phase_c_founder_subject_bind` from a `postgres` connection — **finding D, the deepest one** | **REFUSED** `28000` — *this is the server path* |
| 12 | a direct INSERT into `phase_c_founder_auth_event` from `postgres` | **REFUSED** `28000` — *a founder session may only be minted on the PostgREST connection* |
| 1, 11 | `fn_phase_c_governance_decide` with a typed approver and no verified session | **REFUSED** `28000` — *may only be recorded on the PostgREST connection that verified…* |

### What could NOT be rehearsed from here, and why — stated, not glossed

| FD-01 # | case | why not |
|---|---|---|
| 4, 5, 7–11, 13 | arbitrary auth subject · arbitrary digest · event bound to another request · to another digest · expired event · reused event · valid founder JWT · replay → `ALREADY_DECIDED` | every one needs a **minted, verified auth event**, and PCCR-006's whole design refuses to mint one unless `session_user = 'authenticator'`. The management API connects as `postgres`. **This is the migration working**, and it is also why these cases cannot be proved without a real founder session |
| 12 | UPDATE / DELETE on the decision ledger | the ledger is EMPTY, so both statements touch **0 rows** and a `FOR EACH ROW` trigger never fires. The probe read "accepted" and that is a **dead-guard reading, not a pass and not a defect**. What IS measured: `a00_phase_c_governance_decision_is_session_backed` is attached `BEFORE INSERT OR UPDATE OR DELETE … FOR EACH ROW`, and its first statement is `if TG_OP <> 'INSERT' then raise … append-only`. Populating the ledger to force the branch needs a verified session |

**So FD-01 is not claimed to pass.** Seven of its cases are proved against the deployed objects; the
rest are unreachable from any connection the builder has, by the migration's own design.

---

## 4. What the founder does, exactly

Sign in to the Command Center and submit this as a **NEW COMMAND** — not as a reply in the existing
thread:

> I approve PCCR-006 — governance_approval_authenticity — as set out in
> `docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-006.md`, sha256
> `c787bfcfe38578010f29e4ed2dcaddc602be42f16eb3a320aab6f75519561ceb`.

**A new command, and not a reply, for a measured reason.** A new command writes
`founder_command_message` with `raw_text`, `raw_text_hash = sha256(raw_text)`, an immutability
trigger, a truncate guard and a `TRACE-FOUNDER-COMMAND` row — which is exactly what his
acceptance-standard approval produced and what an audit can verify. A clarification answer is an
append to an existing thread and carries no command id, no message id and no trace of its own.
(`phase_d_q07` now hashes and seals a clarification answer too, so one can no longer be lost or
edited — but the stronger record is still a command, so that is what is asked for.)

He will see it classify as `AMBIGUOUS` / `clarification_required` with `tasks_created 0`. **That is
correct and expected** — it is what the acceptance-standard approval did, and it is what keeps a
governance sentence from creating business work.

Then the builder verifies the record and applies the migration.

---

## 5. What is NOT blocking this

- **FD-02** passes: 8 of 8, 479 enforced closed domains, 15 registered `CLOSED_ENUM_UNDEFINED`
  naming PBCR-002.
- The frozen 13-gate regression set reproduces.
- PBCR-002 is a **Phase B** change request and is not an FD gate. Phase D does not wait on it.
- The 52 uninventoried edge functions are a disclosed ratchet, not a gate.

`PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1` §A: *"These two, and only these two, are what stands between
the estate and Phase D acceptance."* One of the two is green. The other needs one sentence.
