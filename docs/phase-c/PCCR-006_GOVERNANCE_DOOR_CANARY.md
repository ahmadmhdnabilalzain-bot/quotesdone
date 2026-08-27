# PCCR-006 — THE GOVERNANCE DOOR, DRIVEN THROUGH A REAL FOUNDER SESSION

**Session:** narrow Phase D / Phase C correction, 2026-08-27
**Production project:** `htdblwldjkcgjvmqkbeh` (the only one)
**Command:** `node scripts/phase_d/prove_governance_door.mjs --record`
**Machine-readable result:** [`docs/phase-d/PHASE_D_GOVERNANCE_DOOR_CANARY.csv`](../phase-d/PHASE_D_GOVERNANCE_DOOR_CANARY.csv)

---

## 1. What was wrong, and it was two things

### 1.1 The door had never operated. Not once.

`public.phase_c_governance_decision` held **0 rows** and `public.phase_c_founder_auth_event` held
**0 rows**, measured 2026-08-27 11:44 UTC — from the day PCCR-006 created them until this session.

PCCR-006 built `fn_phase_c_governance_decide` as the one canonical governance-decision door, and
step 4 of that routine INSERTs into `public.phase_c_founder_auth_event` to mint its purpose-bound,
single-use session. That table carries `z10_kernel_write_guard`. `public.kernel_write_authority`
named exactly one routine for it:

| routine | table | added |
|---|---|---|
| `fn_phase_c_founder_subject_bind` | `phase_c_founder_auth_event` | 2026-08-21 20:08:19+00 |

`fn_kernel_write_guard` reads the PL/pgSQL call stack and refuses any writer not on that register
with SQLSTATE **42501**. So every call that got as far as minting its session was refused by the
estate's own write guard — which is why the ledger has never held a row, and why
`fn_phase_c_freeze_drift`'s `approved_change_requests_with_no_verified_governance_decision` could
never clear.

**Fix:** one registry row, not a grant. `scripts/sql/phase_c_the_bind_door_took_the_subject_as_an_argument.sql`
adds `fn_phase_c_governance_decide → phase_c_founder_auth_event` to `public.kernel_write_authority`.
Nothing was granted INSERT, UPDATE or DELETE on that table; the assertion block in the file proves
it (`information_schema.role_table_grants` for anon / authenticated / service_role / PUBLIC → 0).

### 1.2 The bind door took the subject as an argument

`fn_phase_c_founder_subject_bind(p_subject uuid)` asked three questions:

```
session_user = 'authenticator'      -- closes management and migration connections
current_user <> 'anon'              -- see below: this could never be true
p_subject resolves to an active row in public.phase_c_founder_identity
```

and **never compared `p_subject` to the caller's own `auth.uid()`**. `proacl` showed
`service_role=X/postgres`. PostgREST connects as `authenticator` and `SET ROLE`s, so a service_role
call to `/rest/v1/rpc/fn_phase_c_founder_subject_bind` carrying the founder's `auth_user_id` — a
value readable from the very table the routine validates against — bound his subject with no founder
bearer token in existence. From there `fn_kernel_refund_decision_record` and
`fn_phase_c_freeze_amendment_approve` accept it.

Raised as an open finding on 2026-08-26 and deliberately **not used**, because driving a
founder-authority control by handing the door his own uuid is the impersonation the door exists to
stop.

**A second defect found while fixing the first.** `if current_user = 'anon'` could never be true.
The routine is `SECURITY DEFINER`, so `current_user` is the **owner** — `postgres` — on every call,
including anon's. The measured proof is in the canary's own first run: with the check rewritten as
`current_user <> 'authenticated'`, the founder's own valid JWT was refused with
*"this call arrives as current_user postgres"*. The role PostgREST switched to lives in the verified
JWT, and that is what the shipped body reads.

**Fix, five predicates:**

| # | predicate | closes |
|---|---|---|
| 1 | `session_user = 'authenticator'` (unchanged) | management and migration connections |
| 2 | verified JWT role must be `authenticated` | `service_role`, `anon` — with their own refusal code |
| 3 | `auth.uid()` must be non-null | anything arriving without a user JWT |
| 4 | **`p_subject = auth.uid()`** | **the finding: a caller may bind itself and no one else** |
| 5 | EXECUTE revoked from `service_role`, `anon`, PUBLIC; granted to `authenticated` | the grant layer |

**Active production callers of the bind door before the change: 0.** Measured, not assumed —
`grep -rn "founder_subject_bind" supabase/ scripts/ src/ docs/` returns the schema mirror, three
CHECK constraints that name the string as a permitted `approval_route` **value**, seven
`scripts/checks/*.test.mjs` and `scripts/phase_d/prove_founder_authentication.mjs` which call it from
a management connection and assert that it REFUSES. There is no caller in `supabase/functions` and
none in `src/`. Nothing in his OS closes when service_role loses this grant — see the call graph.

---

## 2. The founder-subject call graph

```
  browser
    │  fetch(SUPA_URL + '/functions/v1/os_api',
    │        headers: { Authorization: 'Bearer <GoTrue access_token>' })
    │  src/lib/osClient.ts:115
    ▼
  os_api  (supabase/functions/os_api/index.ts, verify_jwt = false — it verifies for itself)
    │
    ├─ line 199  admin.auth.getUser(token)          admin = service_role client
    │            no token          → 401
    │            invalid token     → 401
    │            valid, not admin  → 403
    │            valid + admin     → email, userId
    │
    ├─ for a READ or a service action:  admin.<...>          (service_role; auth.uid() is null)
    │
    └─ for a FOUNDER action:  asCaller(authHeader)           (index.ts:18)
                 │  createClient(SUPA_URL, ANON_KEY,
                 │               { global: { headers: { Authorization: authHeader } } })
                 │  the SAME bearer token the request arrived with — os_api does not mint one
                 ▼
       PostgREST  /rest/v1/rpc/<routine>
                 │  connects as  session_user = authenticator
                 │  verifies the JWT against the project secret
                 │  SET LOCAL ROLE  <jwt.role>              → 'authenticated'
                 │  set_config('request.jwt.claims', <verified claims>)
                 ▼
       database   session_user = 'authenticator'      ← cannot be forged: SET ROLE leaves it alone
                  jwt role      = 'authenticated'      ← the role PostgREST switched to
                  auth.uid()    = <sub>                ← the subject PostgREST verified
                  current_user  = 'postgres'           ← INSIDE a SECURITY DEFINER routine: the OWNER,
                                                          not the caller. Never test identity on it.
                 ▼
       founder identity lookup
                  public.phase_c_founder_identity  where auth_user_id = auth.uid()
                                                     and active and kind = 'email'
                 ▼
       ┌─────────────────────────────┬──────────────────────────────────────────────┐
       │ fn_phase_c_require_founder  │ fn_phase_c_governance_decide                 │
       │ (FROZEN — untouched)        │ (this session)                               │
       │  Route A auth.uid()         │  auth.uid() only; falls back to a bound event │
       │  Route B a bound event      │  minted and consumed in the SAME transaction  │
       │          action_class NULL  │  action_class = 'GOVERNANCE_DECISION'         │
       └────────────┬────────────────┴───────────────────┬──────────────────────────┘
                    │                                    │
        fn_kernel_refund_decision_record      phase_c_founder_auth_event (write authority)
        fn_founder_command_clarify                        │
        fn_founder_command_control              consume in the same transaction
        fn_kernel_cancel(founder_command)                 │
        fn_phase_c_freeze_amendment_approve     phase_c_governance_decision (append-only)
                                                          │
                                        z10 AFTER INSERT → phase_c_change_request
                                                            (disposition + every approval column,
                                                             DERIVED, never written directly)
```

**os_api never calls `fn_phase_c_founder_subject_bind`.** It does not need to: `asCaller` hands
PostgREST the token, PostgREST hands the database the subject it verified, and `auth.uid()` resolves
on Route A. The bind door exists for a server that has verified a token some other way; today
nothing in production uses it, which is why predicate 4 and the service_role revoke close a hole
without closing a path.

---

## 3. The governance authorization matrix

Every row below is one live HTTPS call against the deployed PostgREST endpoint on
`htdblwldjkcgjvmqkbeh`, 2026-08-27 12:03 UTC. **22 of 22 behaved as required.**

### 3.1 `fn_phase_c_governance_decide`

| id | caller | HTTP | outcome | the refusal |
|---|---|---|---|---|
| GOV-N1 | no bearer token | 401 | REFUSED | `42501 permission denied for function` |
| GOV-N2 | invalid bearer token | 401 | REFUSED | `PGRST301 Expected 3 parts in JWT` |
| GOV-N3 | founder JWT with `exp` rewritten | 401 | REFUSED | `PGRST301 none of the keys was able to decode the JWT` |
| GOV-N4 | **service_role key** | 403 | REFUSED | `42501 permission denied for function` |
| GOV-N5 | anon key as bearer | 401 | REFUSED | `42501 permission denied for function` |
| GOV-N6 | authenticated **non-founder** | 403 | REFUSED | `28000 pccr_governance_not_the_founder` |
| GOV-N7 | founder JWT + typed `approved_by` | 400 | REFUSED | `22023 pccr_governance_caller_supplied_approval` |
| GOV-N8 | founder JWT + typed `approval_auth_subject` | 400 | REFUSED | `22023 pccr_governance_caller_supplied_approval` |
| GOV-N9 | founder JWT + arbitrary 64-hex digest | 400 | REFUSED | `22023 pccr007_governance_digest_never_quoted` |
| GOV-N10 | founder JWT + unknown change request | 409 | REFUSED | `23503 pccr_governance_unknown_change_request` |
| GOV-N11 | founder JWT + **PCCR-003** (he never quoted it) | 400 | REFUSED | `22023 pccr007_governance_digest_never_quoted` |
| **GOV-P1** | **founder JWT over real HTTPS** | **200** | **ACCEPTED** | `DECIDED_IN_VERIFIED_SESSION`, decision 6 |
| GOV-P2 | founder JWT, replayed | 200 | ACCEPTED | `ALREADY_DECIDED`, decision 6, **no second row** |

### 3.2 `fn_phase_c_founder_subject_bind`

| id | caller | HTTP | outcome | the refusal |
|---|---|---|---|---|
| BND-N1 | no bearer token | 401 | REFUSED | `42501 permission denied for function` |
| BND-N2 | invalid bearer token | 401 | REFUSED | `PGRST301` |
| BND-N3 | founder JWT with `exp` rewritten | 401 | REFUSED | `PGRST301` |
| **BND-N4** | **service_role + the founder's own uuid** | **403** | **REFUSED** | `42501 permission denied for function` — **this was ACCEPTED before this session** |
| BND-N5 | anon key + the founder's uuid | 401 | REFUSED | `42501 permission denied for function` |
| BND-N6 | non-founder JWT binding itself | 403 | REFUSED | `28000 not the founder: auth subject … does not resolve` |
| BND-N7 | non-founder JWT + the founder's uuid | 403 | REFUSED | `28000 pd_founder_bind_subject_is_not_the_caller` |
| BND-N8 | founder JWT + another subject | 403 | REFUSED | `28000 pd_founder_bind_subject_is_not_the_caller` |
| **BND-P1** | founder JWT binding itself | **200** | ACCEPTED | one event, `server_verified_subject` |

### 3.3 Direct writes and management SQL — measured in aborted transactions

| id | attempt from the management connection | outcome |
|---|---|---|
| D1 | direct `INSERT` into `phase_c_founder_auth_event` | REFUSED `28000 pccr_auth_event_untrusted_connection` |
| D2 | direct `INSERT` into `phase_c_governance_decision` | REFUSED `28000 pccr_governance_no_auth_event` |
| D3 | `UPDATE` a recorded governance decision | REFUSED `42501 pccr_governance_decision_append_only` |
| D4 | `DELETE` a recorded governance decision | REFUSED `42501 pccr_governance_decision_append_only` |
| D5 | `DELETE` a consumed auth event | REFUSED `42501 pccr_auth_event_append_only` |
| D6 | re-consume an already consumed auth event | REFUSED `23505 pccr_auth_event_replayed` |
| D7 | management SQL calling `fn_phase_c_governance_decide` | REFUSED `28000 pccr_governance_untrusted_connection` |
| D8 | management SQL calling `fn_phase_c_founder_subject_bind` | REFUSED `28000 pccr_founder_bind_untrusted_connection` |
| D9 | migration writing `phase_c_change_request` approval columns | REFUSED `42501 pccr_governance_decision_required` |
| D10 | replay a real governance auth event from another transaction | REFUSED `28000 pccr_governance_wrong_transaction` |
| D11 | use a BIND event (action_class NULL) for a governance decision | REFUSED `28000 pccr_governance_wrong_transaction` |
| D12 | use a GOVERNANCE event to open the general founder door | REFUSED `28000 pccr007_founder_untrusted_connection` |

---

## 4. Two predicates that cannot fire, said out loud

Both are guards on conditions the canonical path cannot produce. Neither is a defect; neither is a
PASS either, and reporting them as measured would be false.

**Event expiry.** `phase_c_governance_decision`'s trigger checks `e.expires_at <= now()`. The door
mints the event with `expires_at = now() + interval '5 minutes'` and writes the decision in the same
transaction. In PostgreSQL `now()` is transaction-start time and does not advance within a
transaction, so on the canonical path that comparison is `txstart + 5min <= txstart` and can never be
true. The predicate protects an event consumed by some other path; there is no such path today.
**Not measured. Reachable only by a writer that does not exist.**

**Governance event used for the refund door.** `fn_phase_c_require_founder` Route B requires
`e.action_class is null`, and a governance event carries `'GOVERNANCE_DECISION'`. Reaching Route B
needs `app.phase_c_founder_auth_event` to name an event in the current transaction; through HTTPS a
founder token resolves on Route A first, and from a management connection the routine refuses on the
connection before any claim is read (D12 above). **The predicate is present in the live body and is
unreachable from either caller today.**

---

## 5. Threat model, stated honestly

What this closes: `anon`, an authenticated non-founder, `service_role`, a management or migration
connection, a caller-supplied subject, email, route, digest or disposition, a replayed or foreign
transaction's session, and a digest the founder never typed.

What it does **not** close: `postgres` owns these routines and can replace them. A PostgreSQL
superuser is not cryptographically prevented from bypassing the database, and nothing here claims
otherwise. The control is that the superuser path is the Supabase management API, which is audited,
and that **no application role, no edge function and no browser can reach any of it**. Anyone
claiming more than that is claiming something this session did not measure.

---

## 6. Tamper-evident evidence for the one decision recorded

| field | value |
|---|---|
| change request | `PCCR-007` |
| decision | `APPROVED` |
| database decision id | `6` |
| founder auth event id | `1612` (minted, consumed and spent in the same transaction) |
| founder auth subject | `1256c7ec-17bf-4b1e-af8f-aaa32a8fdd14` |
| approval route | `auth.uid()` |
| approval basis | `AUTHENTICATED_FOUNDER_SESSION` |
| decided_by | `management@quotesdone.com` (derived from the verified subject, not supplied) |
| decided_at | `2026-08-27 12:03:41.317322+00` |
| Command Center message id | `46779`, received `2026-08-26 12:35:30.387938+00` |
| raw-text hash | `357c4c0ef59d7ad65672e6b0ffcbf969614562d7cd643831bd8c8ccbe464a0bd`, recomputed on production with `encode(sha256(convert_to(raw_text,'UTF8')),'hex')` and **equal** |
| approved document | `docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-007.md` |
| approved document digest | `f2a89bebcdf115c73d837f4457bddc5375ac4c3ffe7bb25e100bd7b5a0e17ad1` |
| repository revision that digest is of | commit `872d333af9a3f9096bd56168197c8a91328b9ad4` |

**The document moved after he approved it.** At HEAD the same file hashes
`ce638c247143e591c714773d0d7d3609ceee33b0fc2e2e8ba13274bae8d89f2a` — commit `8db01d6` amended it
after the approval to record that the change had been applied. The canary therefore does **not**
hash the working tree. It reads the digest out of his own message, walks the file's git history and
resolves which committed revision that digest is of, and stops if none matches. A ratification names
the document he read.

---

## 7. What this did NOT do

- It did not ratify **PCCR-003** — see [`PCCR-003_DISPOSITION.md`](PCCR-003_DISPOSITION.md).
- It did not change `fn_phase_c_require_founder`, a frozen Phase C subject.
- It did not activate any cron job, call any paid provider, or send any external effect.
