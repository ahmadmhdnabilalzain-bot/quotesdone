# Phase D — storage, RLS and security result (§8)

**This document separates what was MEASURED from what was NOT PROBED, and the second list is not
short. Every "not probed" row names the exact mechanism it needs.**

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
must read is among them. **That question is not answered here**, because answering it requires
issuing an authenticated read, which is the probe work below.

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

That is exactly what probes 2, 3 and 7 below exist to test, and none of them was run.

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

## 4. The seven security probes — NOT RUN

**None of the seven was executed. None is claimed.** Each needs an authenticated HTTP request, and
no Phase D path issues one — the phase drives the database directly, inside transactions it aborts.

| # | probe | exact mechanism it needs |
|---|---|---|
| 1 | customer A reads customer B | two customer sessions and a portal read; the memory records the three-key sign-in (`qd-cust-token`, `qd-cust-refresh`, **`qd-cust-auth`**) and that getting it wrong looks like an account-mixup bug that is not one |
| 2 | supplier A reads supplier B's documents | two supplier sessions and a signed URL minted for A used against B's path |
| 3 | supplier reads raw customer identity | a supplier bearer token against the raw inquiry endpoint, and the response **body** inspected |
| 4 | customer reads supplier KYC | a customer bearer token against `compliance-docs` / `supplier-docs` |
| 5 | inactive identity executes | a deactivated canonical role presented to an authenticated route |
| 6 | direct RPC / table bypass | `anon` and `authenticated` keys calling RPCs and selecting tables directly, to confirm the 553 deny-all tables are actually unreachable |
| 7 | unsafe signed URL | an expired URL replayed, and a URL whose path belongs to another owner |

**It is possible to run these.** The estate has already proved a live session can be minted —
management token → `api-keys?reveal` → `generate_link` → verify → a real bearer — so the "we cannot
make a live HTTP call" caveat is false and is not offered here. What is true is that this session
did not do it.

## 5. The storage rules the brief lists — status

| rule | status |
|---|---|
| MIME / extension / magic-byte agreement | **enforced in code, tested by its own suite, not probed here.** `supabase/functions/_shared/attachment.ts` refuses a ZIP declared as a PDF, HTML however dressed, SVG, executables by name, and a PDF carrying JavaScript — 16 deno tests pass in the suite. Not exercised through an upload in this phase. |
| size limit | **measured** — every bucket carries a `file_size_limit` |
| MIME allow-list | **measured** — every bucket carries one, 2–10 types |
| owner-scoped path | **NOT PROBED** — and with 0 storage policies there is no row-level enforcement to inspect; it rests on the URL minter |
| safe filename | enforced in `attachment.ts` (traversal, hidden, disagreeing names); not probed |
| quarantine | `documents.status` carries `quarantined` and GATE-012 refuses it — proved by the W07 drive |
| short-lived URL | **NOT PROBED** |
| immutable approved revision | **proved in the database** — `IMMUTABLE_REVISION` supersedes and retains; not probed over HTTP |

---

## 6. Honest summary

**Section 8 is PARTIALLY delivered.** The call graph is real and complete for the surfaces it found.
The RLS and storage posture is measured from the database and includes one finding worth acting on
(no storage-level policies; authorisation rests on the URL minter).

**The seven security probes were not run, and the twenty §11 defects that depend on them remain
NOT_RUN.** Marking any of them satisfied on the strength of the posture measurements above would be
the instrument-on-the-wrong-subject defect this estate keeps finding: a bucket being private is not
evidence that supplier A cannot read supplier B's file.

## Boundary of this evidence

Measured on the one project on 2026-08-19 (database clock), from `pg_class`, `pg_policy`,
`storage.buckets` and `storage.objects`, plus static analysis of `src/` and `supabase/functions/`.
No authenticated HTTP request was issued, no signed URL was minted or replayed, and no upload was
performed. This document is a statement about **posture and structure**, not about behaviour under
an authenticated request.
