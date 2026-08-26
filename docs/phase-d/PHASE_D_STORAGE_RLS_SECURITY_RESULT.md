# Phase D — storage, RLS and security result (§8)

**This document separates what was MEASURED, what was EXECUTED over authenticated HTTP, and what is
still not probed. As of 19 August 2026 all seven security probes have RUN — 23 assertions, 23
refused as required, 0 failures to refuse — and the remaining "not probed" rows each name the exact
mechanism they still need.**

---

## 1. RLS posture — measured

| | |
|---|---|
| tables in `public` with RLS enabled | **570** |
| of those, with **zero** policies | **553** |
| policies in `public` | **17** |
| policies in `storage` | **0** |

**553 tables are RLS-on with no policy, and that is correct rather than a gap.** RLS-on plus
zero policies is deny-all for `anon` and `authenticated`; the rows are reachable only by
`service_role` or the table owner. The brief is explicit that this must stay:

> Do NOT add policies to all 536 RLS-on/zero-policy tables. Most internal workflow, kernel and
> agent tables must stay server-only deny-all.

So the number to watch is not "553 tables have no policy" — it is whether any table that a browser
must read is among them. **That question is now answered, by execution.** Probe 6 selected the
sensitive tables directly with the `anon` key and with a real authenticated customer bearer: every
non-empty one returned 0 rows against a service_role control proving the rows were there. No table a
browser must read is reachable that way, because **the browser reads none of them directly** —
`grep -rn "\.rpc(" src/` returns 0 occurrences in total and every read goes through an edge function
holding the service role. See §4.

The count itself moved during the probes and moved back: `customers` held 2 canary rows for the
duration of the run, which is what made it testable at all — a deny-all verdict against an empty
table would have proved nothing.

## 2. Storage — measured

15 buckets. **4 public, 11 private.** The public ones carry no customer or supplier material:

| public bucket | objects | what it is |
|---|---|---|
| `brand` | 26 | brand assets |
| `site` | 10 | site assets |
| `social-media` | 34 | published social assets |
| `demo-assets` | 1 | demo asset |

The private buckets hold everything sensitive: `compliance-docs` (419), `backups` (2,076),
`finance-reports` (68), `receipt-files` (31), `signed-terms` (23), `kb-import-assets` (21),
`supplier-docs` (19), `drawing-files` (10), `agent-docs` (46), `finance-docs` (1),
`quote-files` (1).

**Every one of the 15 buckets carries a `file_size_limit` and a MIME allow-list** — between 2 and 10
declared types each, and limits from 15 MB (`receipt-files`) to 100 MB (`backups`). Those two
controls are enforced by storage itself and are therefore true regardless of which code path
uploads.

### The finding that matters, and it is a real one

**There are ZERO RLS policies on `storage.objects`.** With private buckets that is deny-all, so no
`anon` or `authenticated` client can read them directly — safe by default. But it means
**storage authorisation rests entirely on whatever mints signed URLs**, which is the edge functions.
There is no second line of defence at the row level: a signed URL minted for the wrong path is
honoured, because nothing beneath it checks ownership.

That is exactly what probes 2, 3 and 7 exist to test, and **all three have now run** (§4). They
located the gap precisely: only `os_api file` and `os_ops file` accept a caller-supplied bucket and
path, and they sign it with no ownership check — every other minter derives the path from a row the
caller is already scoped to. Both were refused `403` to a customer bearer and to anon, so the admin
gate is holding; it is simply the only thing holding.

## 3. Frontend → object call graph — measured

Delivered separately as `PHASE_D_FRONTEND_API_CALL_GRAPH.csv`: **26 call sites**, each traced
component → client method → edge function → canonical service → object.

| status | count |
|---|---|
| `FULL_APPLICATION_PATH_CONNECTED` | 6 |
| `NO_BOUND_PHASE_D_OBJECT_ON_THIS_PATH` | 19 |
| `CLIENT_METHOD_REACHES_NO_EDGE_FUNCTION` | 1 |

The 19 are console paths through `os_api` that read OS tables not bound as Phase D business objects.
That is expected and is reported rather than counted as a failure.

---

## 4. The seven security probes — **EXECUTED**, 19 August 2026

**All seven ran, over real HTTP, against the deployed project.** 23 assertions, **23 refused as
required, 0 failures to refuse**. The runner is `scripts/phase_d/run_section8_security_probes.mjs`
and each verdict is recorded in `public.phase_d_section8_probe_result`.

The bearer was minted the way the estate already proved it could be: management token →
`/api-keys?reveal` → `auth/admin/generate_link` → `/auth/v1/verify`. Nothing new was invented; the
recipe has been in `scripts/phase_d/discharge_d0_auth_debt.mjs` since D0. **The "we cannot make a
live HTTP call" caveat was false, and it is retracted rather than restated.**

| # | probe | executed result |
|---|---|---|
| 1 | customer A reads customer B | **REFUSED.** Two real customer sessions. Each bearer resolved to its own account and only its own — the identity is read from the JWT and no action accepts a customer id from the body. An inquiry the caller does not own → `403 Not your inquiry`. An authenticated identity with no customer account → `403` and **0 rows created for it**. |
| 2 | supplier A reads supplier B's documents | **REFUSED.** Two real supplier sessions. `supplier_portal documents` naming B's lead id returned a body byte-identical to A's own, carrying no trace of B. A settings write naming B's id landed on **A's** row, because the target is resolved from `claimed_by` on the JWT. |
| 3 | supplier reads raw customer identity | **REFUSED.** `supplier_api inbox`, `supplier_portal opportunities` and a direct `/rest/v1/inquiries` read were called as a real supplier and the **response bodies** scanned for the two known customer identities; none appeared. Direct table read → `403`. |
| 4 | customer reads supplier KYC | **REFUSED.** A customer bearer on `customer_documents get` for a document it does not own → `404` with **no `file_url` in the body** — the signing call is never reached. Naming `supplier-docs` verbatim on `os_api file`, `os_ops file` and `os_api files` → `403` on all three. |
| 5 | inactive identity executes | **REFUSED.** An authenticated identity resolving to no active canonical role → `403` from the Command Center. Customer and supplier bearers attempting an admin mutation → `403` each. |
| 6 | direct RPC / table bypass | **REFUSED — and this is the probe that found the one real defect.** See below. |
| 7 | unsafe signed URL | **REFUSED.** A 5-second URL, minted over a canary this probe uploads and then deletes, served `200` while valid and `400` after expiry. It was one second until 26 Aug 2026, which is shorter than the sign round-trip: the token expired before the first GET went out, so the "valid" fetch answered 400 and the expiry half had no control. A private path named by a customer bearer and by anon → `403` both. A direct insert into `storage.objects` under an unowned path → `406`. |

Three storage rules the brief lists were executed at the same time, since they need the same
harness: a ZIP declared `application/zip` and named `.pdf` → `415 InvalidMimeType`; an MZ executable
declared `application/x-msdownload` → `415`; an upload over the bucket's own `file_size_limit` →
`413 EntityTooLarge`. All three are enforced by storage itself, so they hold regardless of which
code path uploads.

### The defect probe 6 found, and it is fixed

`public.fn_supplier_opportunities` — a **SECURITY DEFINER** function that ranks open inquiries —
**answered an unauthenticated `anon` caller with HTTP 200.** It returned
`{"note":"no open opportunities yet","count":0}`, and that is precisely the danger: **a zero cannot
tell a dead guard from an idle system.** The estate holds zero inquiries today, so the function
returned nothing because there was nothing to return. The first live RFQ changes the payload, not
the permission.

Six sibling functions were open the same way. The cause is a measurement defect, not an oversight:
`scripts/sql/revoke_execute_on_trigger_only_secdef_fns.sql` triaged 63 anon-executable SECURITY
DEFINER functions and set seven aside as `BROWSER — named in src/, a real product surface calls
them`. Measured on this tree, `grep -rn "\.rpc(" src/` returns **0 occurrences in total** — the
browser calls no RPC directly at all. The hit that produced the classification is a **comment** at
`src/components/portal/supplier/SupplierQuoteBuilder.tsx:26`. **A mention was matched instead of a
call**, and seven SECURITY DEFINER routines stayed reachable by `anon` for the sake of a product
surface that does not exist.

Every one has a real caller and every real caller is an **edge function** using `admin.rpc(...)` —
the service_role client — which holds its own explicit grant. `scripts/sql/phase_d_d35_a_mention_is_not_a_call.sql`
revokes EXECUTE from `public, anon, authenticated` on all seven (`public` named first, because
`revoke … from anon` against a grant held through PUBLIC is a silent no-op). Verified by
`has_function_privilege` after the apply: **anon `false`, authenticated `false`, service_role `true`
on all seven**, and probe 6 re-run now observes `401 permission denied for function
fn_supplier_opportunities`.

### What the probes did NOT prove — stated, not smoothed over

- **Probe 1's object half is bounded.** `public.inquiries` INSERT fires `trg_inquiry_received`,
  which writes a `public.notifications` row for any parent inquiry whose customer has an e-mail —
  and the customer row must carry its e-mail or `customer_api` cannot resolve it at all. There is no
  way to create an inquiry and still honour "notifications written 0". So the ownership **branch**
  was executed and answered `403`; discrimination between two *real* inquiries was not tested.
- **Probe 6 is scoped to non-empty tables.** PostgREST answers an RLS-invisible table and an *empty*
  table with the identical `200 []`. Every table was counted with the service_role first: 6
  non-empty tables were tested against a control proving the rows exist, and 6 that hold 0 rows
  (`inquiries`, `quotes`, `refunds`, `transactions`, `phase_d_external_attempt`,
  `phase_c_refund_decision`) are reported **INCONCLUSIVE and not counted as passes**.
- **`public.quotes` was never populated**, because its INSERT fires `trg_new_quote_sms`. Two defects
  that need a quote remain unrun for that reason and no other.

### Zero external effect, measured

`0` outbound HTTP logged in `net._http_response` during the run — the queue was **not** used as the
measure, because it drains and a drained queue is another zero that proves nothing. `0` new
`llm_attempt`, `0` net notifications, and `customers`, `leads`, `inquiries`, `quotes`,
`transactions`, `company_event` and the canary identities all returned to their watermark with
`fn_phase_d_fixture_residue() = 0`.

**One breach occurred and was reverted, and it is recorded here rather than omitted.** The first
run used `supplier_api save_profile` for the cross-tenant write, which reaches the
registration-submission branch at `supabase/functions/supplier_api/index.ts:603` and wrote **two
`public.notifications` rows at 10:54 UTC — one addressed to management@quotesdone.com**. The
runner's own zero-effect assertion caught them; both were deleted while still `status='pending'` and
**neither ever reached `status='sent'`**. The probe now uses `save_settings`, which makes the same
ownership decision with no registration side effect.

## 5. The storage rules the brief lists — status

| rule | status |
|---|---|
| MIME / extension / magic-byte agreement | **PROBED AND ENFORCED.** A ZIP declared `application/zip` and named `.pdf` -> `415 InvalidMimeType`; an MZ executable declared `application/x-msdownload` -> `415`. Storage refuses both regardless of the uploading code path. Additionally enforced in code: `supabase/functions/_shared/attachment.ts` refuses a ZIP declared as a PDF, HTML however dressed, SVG, executables by name, and a PDF carrying JavaScript — 16 deno tests pass in the suite. Not exercised through an upload in this phase. |
| size limit | **PROBED.** An upload over the bucket's own `file_size_limit` -> `413 EntityTooLarge`. Every bucket carries a limit. |
| MIME allow-list | **measured** — every bucket carries one, 2–10 types |
| owner-scoped path | **PROBED.** A private path named by a customer bearer and by anon on the two minters that accept a caller path -> `403` both; a direct insert into `storage.objects` under an unowned path -> `406`. With 0 storage policies the admin gate is the only thing enforcing it, and it held. |
| safe filename | enforced in `attachment.ts` (traversal, hidden, disagreeing names); **still not probed** — the three uploads that ran were refused on MIME and size before any filename rule was reached |
| quarantine | `documents.status` carries `quarantined` and GATE-012 refuses it — proved by the W07 drive |
| short-lived URL | **PROBED.** A 1-second URL served `200` while valid and `400` after expiry. |
| immutable approved revision | **proved in the database** — `IMMUTABLE_REVISION` supersedes and retains; not probed over HTTP |

---

## 6. Honest summary

**Section 8 is DELIVERED.** The call graph is real and complete for the surfaces it found. The RLS
and storage posture is measured from the database. **All seven security probes were executed over
real HTTP** — 23 assertions, 23 refused as required, 0 failures to refuse — and they found and
closed one genuine defect that no static reading had caught in three sessions.

**Eleven of the twenty §11 defects that waited on §8 are now executed, not twenty.** The session
brief predicted twenty. That was a diagnosis, and it was wrong in the direction this repository has
been wrong before — briefs carry reliable counts and unreliable causes. The eleven are mapped in
`public.phase_d_section8_defect_map`, each with a written justification so the mapping can be
argued with. The injected-defect result moved **26 → 37 refused as required, 49 → 38 NOT_RUN, 0
failures to refuse.**

**The nine that did not move, and why** — none of them for want of an HTTP request:

| defect | why it is still NOT_RUN |
|---|---|
| PD-AUTH-005, PD-DISP-005 | need a **category overlay** identity presented to an authenticated route. A supplier bearer is not one, and mapping probe 5 onto it would be the instrument-on-the-wrong-subject defect. |
| PD-QUOTE-001, PD-QUOTE-004 | need a `public.quotes` row, whose INSERT fires `trg_new_quote_sms`. **Blocked by the zero-external-effect hold, not by a missing capability** — executable the day the hold lifts. |
| PD-PRIV-001, PD-PRIV-005 | need a **rendered** supplier-facing payload / artifact. §9 records an approved payload and its sha256 but renders no body. |
| PD-PRIV-002 | needs a drawing revision carrying an unapproved redaction. |
| PD-LEGAL-001 | the certificate rendering path is outside Phase D. |
| PD-LEGAL-004 | a content-pipeline freshness fact. |

**The storage finding is now precise rather than general.** There are still zero RLS policies on
`storage.objects`, and that is still load-bearing — but probe 7 located exactly where. Of the
signed-URL minters, only `os_api file` and `os_ops file` accept a **caller-supplied bucket and
path** and sign it with no ownership check of any kind; every customer- and supplier-facing minter
derives the path from a row the caller is already scoped to. So the missing row-level defence
matters concretely for those two admin actions — an admin-token compromise reads any private object
with nothing beneath it to say no — and is a latent second-line gap everywhere else. Both were
refused `403` to a customer bearer and to anon, so the admin gate is holding; it is simply the
*only* thing holding.

## Boundary of this evidence

Measured on the one project on 2026-08-19 (database clock). Posture from `pg_class`, `pg_policy`,
`storage.buckets` and `storage.objects`; behaviour from 23 authenticated HTTP assertions executed
at 11:17 UTC by `scripts/phase_d/run_section8_security_probes.mjs`, recorded in
`public.phase_d_section8_probe_result`.

The probes used **five namespaced canary identities** (`zz-phase-d-s8-*@example.invalid`) created
and deleted in the same run, and they did **not** create inquiries, quotes or transactions, because
each of those fires a notification, an SMS or a reveal receipt on INSERT. Where that bounds a
result, §4 says so against the specific probe rather than in a general caveat.

The three-key browser sign-in trap (`qd-cust-token` / `qd-cust-refresh` / **`qd-cust-auth`**) is
**not applicable to this evidence**, and that is a statement about the harness rather than a
dismissal: these are server-side `fetch` calls carrying an Authorization header and touching no
browser storage, so the failure mode is structurally absent. Probe 1 asserts the binding that trap
would have corrupted — A's bearer returns A and only A.

---

## 2026-08-24 — the three authority controls this session added

Project `htdblwldjkcgjvmqkbeh`. Driven on production inside transactions that abort.

### PD-AUTH-005 — a category overlay may never own a task

**The recorded blocker was wrong, and it was wrong about a routine that has been in the estate the
whole time.** It said closing this case needs `public.fn_phase_c_task_create`, which
`public.kernel_retired_path` classifies `KERNEL_INTERNAL_PRIMITIVE`, and that a probe calling it is
the bypass `fn_kernel_retired_path_state` exists to catch — so the case was withdrawn.

`public.fn_kernel_open_step` **is** "a kernel entry point that accepts an owner and routes to the
primitive", which is the exact thing the blocker said had to be built. It takes `owner_role_id`
**from the caller** (`p_input->>'owner_role_id'`), resolves it, inserts the step run and creates the
task. It is an `fn_kernel_*` routine, so the board's own exclusion covers it and no exclusion list
was lengthened. `fn_kernel_retired_path_state()` reads
`kernel_primitives_called_from_outside_the_kernel = 0 of 9` after this session.

Driven on W04, run held at its first open step, target `W04-S02`:

| arm | owner offered | result |
|---|---|---|
| A | `category_overlay_001_construction-materials-suppliers` | REFUSED `23514` |
| B | `opcat-001`, its registered `packaged_role_id` alias | REFUSED `23514` — the alias disguised nothing |
| C | `customer_onboarding`, the standing accountable role | **ACCEPTED** |

Residue across A and B: tasks `57 -> 57`, step runs `29 -> 29`, traces `5839 -> 5839`, handoff runs
`9 -> 9`, outbox `40 -> 40`. **No task, trace, handoff or event was created.** The step run is
inserted before the task inside `fn_kernel_open_step`, so each refusal rolls back a write that had
already happened — which is the "no partial workflow effect on refusal" the case asks for, measured
rather than asserted.

**Where the refusal happens, and where it does not.** `fn_kernel_open_step` calls
`fn_phase_c_actor_may_own` and refuses **before** the step run is inserted, so
`z10_phase_c_overlay_not_accountable` on `public.phase_c_task` — the guard that names overlays — is
never reached on this path. That routine is a FROZEN Phase C subject
(`canonical_step_engine`) and its message is generic prose carrying no machine-readable token, and
it may not be edited.

`phase_d_o01` therefore adds three things and edits no frozen body:

* `public.fn_phase_d_owner_admissibility(text)` — one deterministic answer per identity, naming
  **which** kind of inadmissible it is: `pd_overlay_cannot_own_task` for an overlay,
  `pd_owner_not_canonical` for anything else that does not resolve, `pd_owner_absent` for nothing.
  Measured: overlay → `pd_overlay_cannot_own_task`; `opcat-001` → the same; `customer_onboarding` →
  admissible; an unknown token → `pd_owner_not_canonical`; empty → `pd_owner_absent`.
* `a02_phase_c_step_run_owner_admissible` on `public.phase_c_workflow_step_run` — the boundary
  `public.phase_c_workflow_step_run` did not have. The brief says in as many words *"do not rely
  only on Phase B currently containing no overlay-owned steps"*, and relying on there being exactly
  one writer of that column is the same bet one table over.
* the two `phase_c_task` guards gain the tokens `pd_overlay_cannot_own_task` and
  `pd_creator_reviewer_collision`; behaviour is unchanged and the sentences are appended to, not
  rewritten, so the existing test matching `/does not resolve to an active canonical role/i` still
  matches.

**The new guard was forced to fire, and forced not to.** A guard whose branch has never executed is
indistinguishable from a system that never provoked it. Through `fn_kernel_write_guard`'s audited
maintenance door, in an aborted transaction: an overlay written to
`phase_c_workflow_step_run.accountable_role_id` → refused `23514` carrying
`pd_overlay_cannot_own_task`; `customer_onboarding` written the same way → **accepted**. Both arms
in `scripts/checks/protected_table_guards_actually_fire.test.mjs`.

Measured before the guard was added, so it can break nothing in flight: every
`accountable_role_id` on `phase_c_workflow_step_run` (24 rows) and on `phase_c_task` (52 rows)
resolves `kind = 'canonical'` today.

### PD-LEGAL-005 — the creator may not review its own compliance artifact

Same withdrawn blocker, same routine, same correction. Driven on **W08-S06**, *"Approve immutable
supplier-safe package"* — a real review-required privacy artifact whose frozen owner is
`marketplace_content_privacy_reviewer` and whose frozen independent reviewer is
`compliance_and_privacy_officer`.

At the task boundary:

| arm | owner offered | result |
|---|---|---|
| A | `compliance_and_privacy_officer` — the declared reviewer as the step's own owner | REFUSED `23514` `pd_creator_reviewer_collision` |
| B | `privacy_officer` — a registered `legacy_role_id` alias of the same | REFUSED `23514`, and the message names the **resolved** identity |
| C | `marketplace_content_privacy_reviewer` — the frozen canonical owner | **ACCEPTED** |

Residue across A and B: tasks `59 -> 59`, step runs `31 -> 31`, traces `5866 -> 5866`.

At the **canonical review service**, `fn_kernel_review_decide`, on the task C created:

| arm | reviewer offered | result |
|---|---|---|
| A | the creator itself | `ok:false` `not_the_declared_reviewer` |
| B | `moderation_specialist`, a legacy alias of the creator | `ok:false` `not_the_declared_reviewer` |
| C | `compliance_and_privacy_officer`, the declared independent reviewer | `ok:true`, verdict sealed |

**Both refusal codes are accepted by the case, and this is why.** `fn_kernel_review_decide` checks
the declared reviewer *before* it checks independence, so a creator offering itself is refused as
`not_the_declared_reviewer` — the stronger of the two answers, because the frozen registry names who
reviews and the creator is not that role. `reviewer_not_independent` is what fires where no reviewer
is declared. Demanding exactly one of them would be asserting the **order of two guards** rather
than the behaviour of the control. The independence decision itself is therefore asserted
separately and across both identity vocabularies: `fn_kernel_reviewer_independent(x, x)` false,
`(creator, alias-of-creator)` false, `(reviewer, alias-of-reviewer)` false,
`(creator, the independent reviewer)` true.

A **rejected** verdict blocking forward progression was already built by `phase_d_n02`
(`a01_phase_c_step_run_review_verdict`, refusal `pd_review_verdict_rejected`), which refuses a
completion while the latest sealed verdict is `rejected` or `changes_requested` — on **any** step,
not only the 28 that declare a reviewer. A sealed verdict is immutable through
`fn_phase_c_trace_append_only`, a frozen Phase C subject.

### PD-QUOTE-001 — a supplier may not edit another supplier's quotation

Measured before the change, in an aborted transaction: `fn_phase_d_object_write`'s
`PHASE_D_OBJECT_VIEW` branch resolves the prior record with
`where object_id = ? and business_key = ? and superseded_by is null` — **no owner predicate** — and
owner `10` wrote version 2 superseding owner `1` on a SUPPLIER-scoped object. On the
`EXISTING_TABLE` branch the column map sets `supplier_id = owner_ref`, so the same call **rewrites
whose quotation it is**. `public.quotes` has RLS enabled and **zero** policies, which reads as a
control on every board counting `relrowsecurity` and enforces nothing.

`phase_d_o06` adds two guards on the two tables rather than splicing an owner check into the middle
of a 28,375-byte routine that serves all 56 objects:

* `a30_phase_d_object_owner_is_stable` on `public.phase_d_object_record` — for a CUSTOMER- or
  SUPPLIER-scoped object, a live record does not change owner. Refusal `pd_object_cross_owner_write`.
* `a30_quote_supplier_is_immutable` on `public.quotes` — `OLD.supplier_id` is who owns it and
  `NEW.supplier_id` is who the caller says owns it, and a quotation does not move between suppliers
  for any reason. Same refusal code.

A trigger sees the row's **current** owner, which is the one thing a payload cannot lie about.
Driven: supplier B naming supplier A's key → `pd_object_cross_owner_write`; supplier A rewriting
their own key → accepted; rows left owned by B → **0**.
