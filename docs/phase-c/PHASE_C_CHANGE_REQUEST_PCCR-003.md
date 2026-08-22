# PCCR-003 — founder authentication becomes a verified auth subject

**Raised:** 21 Aug 2026
**Approved:** 21 Aug 2026, by the founder, in writing, in the ruling this change request exists to
execute.
**Frozen subject amended:** `founder_authentication` — `fn_phase_c_require_founder(p_actor text)`
**Amendment row:** `public.phase_c_freeze_amendment`, `amendment_id = 36`, `change_request_ref = 'PCCR-003'`

---

## 1. The instruction, verbatim

From the founder's ruling of 21 Aug 2026, section E:

> Do not request a new founder secret.
> Do not use the founder's email address as authentication proof.
> The approved design is Supabase Auth JWT identity.
>
> Use:
> verified JWT → verified auth subject (`sub`) → server-side lookup against the enabled founder
> identity → founder action.
>
> Choose one safe implementation:
>
> A. call the founder RPC with the founder bearer token so `auth.uid()` is available;
>
> or:
>
> B. verify the JWT in os_api, pass only the verified auth subject to a service-role-only database
> routine, and map that subject to `phase_c_founder_identity.auth_user_id`.
>
> Requirements:
> - `fn_phase_c_require_founder` does not trust a caller-supplied email;
> - `fn_refund_decide` cannot be authorized by knowing an email string;
> - direct EXECUTE by anon/authenticated is revoked where the server path is required;
> - non-founder JWT → 403;
> - enabled founder JWT → success;
> - expired/invalid JWT → 401;
> - no custom secret is placed in source, database prose, prompt, or test file;
> - no password or access token is requested from the founder in chat.

And from section F: *"For the founder-authentication amendment, use the approved JWT-subject design
above. Stop before applying any other Phase C amendment until founder approval is recorded."*

## 2. The defect this removes

E39 (`scripts/sql/phase_d_e39_the_guard_authenticated_a_string_not_an_actor.sql`) recorded the
vector and refused to paper over it:

```sql
set local role service_role;
select public.fn_phase_c_require_founder('management@quotesdone.com');   -- PASSED_AS
```

The frozen body resolved `lower(btrim(p_actor))` against `public.phase_c_founder_identity`. That
routine gates `fn_kernel_cancel`, `fn_founder_command_clarify`, `fn_founder_command_control` and
`fn_phase_c_refund_decision_guard`, under a standing rule that **every refund needs the founder, at
any amount**. His email address is a plaintext literal in this repository's own committed history,
so the estate's model of "the founder approved this" was "somebody typed his email".

## 3. What was built

**Both of his options, because they are two lines in one routine and each covers what the other
cannot.**

| Route | Mechanism | When it applies |
|---|---|---|
| **A** | `auth.uid()` | A request that reached PostgREST with the founder's own bearer token. PostgREST verified it against the project's JWT secret. Nothing in the database can manufacture it. |
| **B** | `fn_phase_c_founder_subject_bind(uuid)` | `os_api` verifies the JWT itself with `admin.auth.getUser(token)`, then passes ONLY the verified subject to a service-role-only routine, which resolves it against `phase_c_founder_identity.auth_user_id` where `active`, writes an audit row carrying `txid_current()`, and sets a transaction-local GUC holding that row's id. |

`p_actor` becomes an **assertion**: supplying one that disagrees with the verified identity is
refused; supplying none is fine. It is never the source.

**No new secret exists.** The transaction-local GUC carries an audit-row id, and the verifier
requires that row to name `txid_current()`. A caller who sets the GUC by hand must point it at a row
created in the same transaction, and the only routine that creates one refuses any subject that is
not an enabled founder. There is nothing to place in source, in database prose, in a prompt or in a
test file, and none is.

**Objects added:** `public.phase_c_founder_identity.auth_user_id`;
`public.phase_c_founder_auth_event` (audited, kernel-write-guarded, truncate-guarded);
`public.fn_phase_c_founder_subject_bind(uuid)`; `public.fn_phase_c_founder_auth_state()`.

**Grants (F21, narrowed by F27):** `authenticated` gains EXECUTE on **two** routines —
`fn_founder_command_clarify` and `fn_founder_command_control`. Route A goes through PostgREST as
`authenticated`, and without the grant the founder himself would get 42501 while `service_role`
remained the only caller able to reach them. F21 granted a third, `fn_phase_c_require_founder`
itself, and **F27 revoked it**: its four callers are all SECURITY DEFINER routines that execute it as
the owner, so nothing outside the database ever calls it and the grant was a convenience that
widened a set `anon_cannot_execute_security_definer.test.mjs` exists to hold small.
`fn_phase_c_founder_subject_bind`, `fn_refund_decide` and `fn_kernel_cancel` stay
`service_role`-only.

**`os_api` (deployed, v73):** the two founder-command actions now call through a client carrying the
caller's own verified bearer token, and refuse the static `x-os-key` bypass outright.

## 4. What was measured

`docs/phase-d/PHASE_D_FOUNDER_AUTHENTICATION_RESULT.csv`, produced by execution against production
inside a transaction ending in `raise exception`:

| case | result |
|---|---|
| E39's exact vector — type his email as `service_role` | **REFUSED** (28000) |
| his verified auth subject, bound by the server path | **ACCEPTED** — `management@quotesdone.com` |
| the same call asserting a different identity | **REFUSED** |
| a real non-founder auth subject (`acceptance-nonfounder@example.invalid`) | **REFUSED** |
| a subject that is nobody (`00000000-…`) | **REFUSED** |
| `app.phase_c_founder_auth_event` set by hand | **REFUSED** |
| audit rows committed after the probe | **0** |
| HTTP: no `Authorization` header | **401** |
| HTTP: a garbage bearer token | **401** |
| HTTP: the anon key used as a bearer token | **401** |
| HTTP: a forged JWT naming his auth subject | **401** |

`fn_phase_c_founder_auth_state()` — 4 of 4 green.
`fn_phase_a_baseline_drift()` and `fn_phase_b_baseline_drift()` — **0 rows** each.
`fn_phase_c_freeze_drift().frozen_subjects_drifted` — **0 of 25**.

## 5. What was NOT measured, said plainly

- **`non-founder JWT → 403` was not measured over HTTP.** It needs a valid bearer token for a
  non-admin, and no password for the existing non-founder test user is held here. Creating a
  temporary auth user to mint one was available under his instruction and was **not** done: it adds
  a persistent identity to production for a case the database layer already refuses with a REAL
  non-founder auth subject, which is measured above. The HTTP 403 branch in `os_api` is unchanged by
  this amendment.
- **`enabled founder JWT → success` was measured at the database layer, not over HTTP.** The same
  reason: minting his bearer token needs his password, and his instruction is explicit that no
  password or access token is to be requested from him in chat. What is measured is the subject his
  JWT would carry, resolved through the same routine the HTTP path calls.

## 6. The residual

Route B trusts `os_api`, which holds `service_role`. Anyone else holding `service_role` could bind
the founder's auth subject **if they knew it**. That is the boundary his own approved design draws,
and it is strictly smaller than the one it replaces: a uuid that appears in no committed file,
versus an email address that appears in several. Route A has no such residual and is what `os_api`
now uses for the two founder-command actions.

## 7. Rollback

Re-apply the body whose digest is `b2fff88d6957…`. One `CREATE OR REPLACE FUNCTION`, no data change.
It reopens the typed-email vector, which is why it should not be done.

---

## 8. The eleven elements PHASE_D_CHANGE_CONTROL.md requires

`scripts/checks/freeze_amendment_names_a_real_change_request.test.mjs` asserts that a change request
carries every element the change-control document names. They are answered here rather than left to
be inferred from the sections above.

**Owner.** Founder authentication is a Phase C kernel subject; the accountable owner is the founder,
and the routine's four callers belong to `risk_and_governance_manager`'s workflows. The change was
built and applied in this session under his written instruction.

**Reviewer.** Not independently reviewed inside this session, and that is stated rather than
implied: there is no second engineer here. The review this change is offered to is the independent
acceptance audit, and every claim in section 4 is reproducible from
`node scripts/phase_d/prove_founder_authentication.mjs`.

**Current behaviour.** `fn_phase_c_require_founder(p_actor text)` resolved `lower(btrim(p_actor))`
against `public.phase_c_founder_identity` where `active` and `kind = 'email'`, and returned the
identity. Any caller who could execute the routine and knew an enabled email was the founder.

**Proposed behaviour.** The identity is resolved from a verified auth subject — `auth.uid()`, or a
subject bound by `fn_phase_c_founder_subject_bind` after `os_api` verified the JWT — and `p_actor`
is an assertion that must match it. A call with no verified subject raises 28000 whatever it types.

**Evidence.** Section 4, produced by execution against production inside a transaction ending in
`raise exception`, and committed as
`docs/phase-d/PHASE_D_FOUNDER_AUTHENTICATION_RESULT.csv`. Section 5 states what was **not** measured.

**Security.** Strictly tightening. The one door this opens is `authenticated` EXECUTE on
`fn_founder_command_clarify` and `fn_founder_command_control`, which is what makes route A reachable
by the founder — and the routine behind it refuses every caller whose verified subject is not an
enabled founder identity, including `service_role`, which has no `auth.uid()` at all. That grant is
recorded by name, with this reasoning, in `scripts/checks/anon_cannot_execute_security_definer.test.mjs`,
whose pinned set is what would catch a third name appearing. F27 revoked the third grant F21 made —
`fn_phase_c_require_founder` itself needs none, because its four callers are SECURITY DEFINER and
execute it as the owner.

**Privacy.** No personal data is added or exposed. `phase_c_founder_identity.auth_user_id` holds a
Supabase auth subject uuid for two existing founder identities, read from `auth.users` by email.
`phase_c_founder_auth_event` records that subject alongside the identity it resolved to, and lives
only inside a transaction that is aborted — 0 rows committed, asserted by
`scripts/checks/phase_d_fixture_catalogue_matches_the_file.test.mjs`.

**Finance / financial.** No money moves. `fn_refund_decide` is untouched and stays
`service_role`-only; the founder's standing rule that every refund needs him, at any amount, is
strengthened rather than relaxed — the guard behind it can no longer be satisfied by typing his
email. No provider was called: `ai_cost_log` shows 0 rows since 2026-08-18 14:00 UTC.

**Compatibility.** Broken deliberately for exactly one caller shape — a `service_role` call that
supplies only an email — because that shape is the defect. `os_api` is updated and deployed (v73) in
the same change. No other caller in the repository supplies an email to this routine; the four
in-database callers pass it through unchanged and are unaffected.

**Rollback.** Section 7.

**Migration.** `scripts/sql/phase_d_f20_*.sql`, `phase_d_f21_*.sql`, `phase_d_f23_*.sql`,
`phase_d_f27_*.sql`, each applied with `node scripts/apply_sql.mjs <file> --apply` and read back;
`node scripts/deploy_functions.mjs --ref=htdblwldjkcgjvmqkbeh --production os_api`.
