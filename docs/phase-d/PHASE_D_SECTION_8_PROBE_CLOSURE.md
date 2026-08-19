# Phase D — §8 closure: the seven probes, executed

**19 August 2026.** The one thing standing between Phase D and a readiness verdict was that the
seven §8 security probes had never been run. They have now run.

---

## What was outstanding, and what closed it

| | before | after |
|---|---|---|
| §8 security probes executed | **0 of 7** | **7 of 7** — 23 assertions, **23 refused as required, 0 failures to refuse** |
| injected defects refused as required | 26 | **37** |
| injected defects NOT_RUN | 49 | **38** |
| failures to refuse | 0 | **0** |
| deterministic workflow closure | 30 / 30 | 30 / 30 (re-measured this session) |

The runner is `scripts/phase_d/run_section8_security_probes.mjs`. Every verdict is recorded in
`public.phase_d_section8_probe_result` by the run that produced it, and
`fn_phase_d_injected_defect_report()` reads that table so a probe result becomes a defect status
without anyone retyping one.

**The excuse is retracted, not restated.** Three sessions recorded these as NOT_RUN because "no
Phase D path issues an authenticated HTTP request". The recipe had been sitting in
`scripts/phase_d/discharge_d0_auth_debt.mjs` since D0 — management token → `/api-keys?reveal` →
`auth/admin/generate_link` → `/auth/v1/verify` → a real bearer. Nothing had to be invented. The work
had simply not been done.

---

## The defect the probes found

Probe 6 calls RPCs directly as `anon`. `public.fn_supplier_opportunities` — **SECURITY DEFINER**,
ranks open inquiries — answered with **HTTP 200**.

It returned `{"note":"no open opportunities yet","count":0}`. That is the entire danger: **a zero
cannot tell a dead guard from an idle system.** The estate holds zero inquiries today. The first
live RFQ changes the payload, not the permission.

Six siblings were open the same way, and the cause was a **measurement defect**:
`revoke_execute_on_trigger_only_secdef_fns.sql` triaged 63 anon-executable SECURITY DEFINER
functions and set seven aside as *"named in `src/` — a real product surface calls them… LEFT ALONE"*.
Measured on this tree, **`grep -rn "\.rpc(" src/` returns 0 occurrences in total.** The browser calls
no RPC directly at all. The hit that produced the classification is a **comment** at
`src/components/portal/supplier/SupplierQuoteBuilder.tsx:26`.

**A mention was matched instead of a call** — the exact trap this repository already warns about —
and seven SECURITY DEFINER routines stayed reachable by `anon` for a product surface that does not
exist. Every one has a real caller and every real caller is an **edge function** using
`admin.rpc(...)`, which holds its own explicit `service_role` grant.

`scripts/sql/phase_d_d35_a_mention_is_not_a_call.sql` revokes EXECUTE from `public, anon,
authenticated` on all seven — `public` named first, because `revoke … from anon` against a grant
held through PUBLIC is a silent no-op. Verified after the apply by `has_function_privilege`, not by
reading the ACL text: **anon `false`, authenticated `false`, service_role `true` on all seven.**
Probe 6 re-run now observes `401 permission denied for function fn_supplier_opportunities` — found,
fixed and re-verified by the same instrument.

---

## Two defects in this session's own work, caught by its own guards

1. **`build_injected_defect_result.mjs` did not parse.** The committed script fails `node --check`
   with `SyntaxError: Unexpected end of input` — a duplicated block at lines 51-56. **The script
   that claims to produce the deliverable could not run**, which is the same defect the previous
   closure recorded for the workflow builder. Repaired by deletion; the CSV in this commit is the
   first one it actually produced.

2. **The probe runner wrote two notifications, and its own assertion caught them.** The first run
   used `supplier_api save_profile` for the cross-tenant write. That reaches the
   registration-submission branch at `supabase/functions/supplier_api/index.ts:603`, which wrote two
   `public.notifications` rows at 10:54 UTC — **one addressed to management@quotesdone.com**. Both
   were deleted while still `status='pending'`; **neither ever reached `status='sent'`**. The probe
   now uses `save_settings`, which makes the same ownership decision with no registration side
   effect. This is disclosed rather than omitted: the hold said zero, and for four minutes it was
   two.

A third was avoided rather than caught: `mobile_otp` action `status` **inserts a `customers` row for
the caller** before serving what looks like a pure read. It is on the do-not-call list for any
future probe.

---

## What the probes did NOT prove

Stated against the specific probe, because an unbounded verdict from a bounded check is the same
defect as an instrument on the wrong subject.

- **Probe 1's object half is bounded.** `public.inquiries` INSERT fires `trg_inquiry_received`,
  which writes a notification for any parent inquiry whose customer has an e-mail — and the customer
  row must carry its e-mail or `customer_api` cannot resolve it at all. There is no way to create an
  inquiry and honour "notifications written 0". The ownership **branch** was executed and answered
  `403`; discrimination between two *real* inquiries was not tested.
- **Probe 6 counts only non-empty tables.** PostgREST answers an RLS-invisible table and an empty one
  with the identical `200 []`. Each table was counted with the service_role first: 6 non-empty
  tables passed against a control proving the rows existed; 6 that hold 0 rows are reported
  **INCONCLUSIVE and not counted as passes**.
- **`public.quotes` was never populated**, because its INSERT fires `trg_new_quote_sms`.

**The brief predicted twenty defects would become executable. Eleven did.** That was a diagnosis,
and briefs here carry reliable counts and unreliable causes. The eleven are mapped in
`public.phase_d_section8_defect_map`, each with a written justification so the mapping can be argued
with; the nine that did not move keep a NOT_RUN status with a blocker that now says what is still
missing instead of repeating that §8 does not exist. Two of the nine (PD-QUOTE-001, PD-QUOTE-004)
are blocked **by the zero-effect hold, not by a missing capability**, and are executable the day it
lifts.

---

## The storage finding, now precise

There are still **zero RLS policies on `storage.objects`**, and it is still load-bearing — but probe
7 located exactly where it matters. Of the signed-URL minters, only **`os_api file` and `os_ops
file`** accept a caller-supplied bucket and path and sign it with **no ownership check of any kind**;
every customer- and supplier-facing minter derives the path from a row the caller is already scoped
to. Both refused `403` to a customer bearer and to anon, so the admin gate is holding — it is simply
the *only* thing holding, with no row-level second line beneath it.

No policies were added to the 553 RLS-on/zero-policy tables in `public`. The brief forbids it and
the probes confirm the posture is correct: every non-empty one is unreachable by `anon` and by a
real authenticated bearer.

---

## Zero cost and zero external effect

| | |
|---|---|
| OpenRouter / paid inference requests | **0** |
| `llm_attempt` delta | **0** |
| paid inference cost | **USD 0.00** |
| outbound HTTP logged in `net._http_response` during the probe run | **0** |
| live email / SMS / WhatsApp / social / payment / refund | **0** |
| `public.notifications` net delta | **0** (two written and reverted while unsent — see above) |
| Apify runs · production Dropbox writes | **0** · **0** |
| active cron jobs, start → end | **23 → 23** |

`net.http_request_queue` was **not** used as the measure of outbound effect: it drains, so a drained
queue is another zero that proves nothing. The durable record is `net._http_response`, and the only
four requests in the session window are the scheduled read-only monitors the hold keeps active.

**Nothing was left behind.** `fn_phase_d_fixture_residue()` = 0; `customers` 0, `inquiries` 0,
`quotes` 0, `transactions` 0, `phase_d_external_attempt` 0, `company_event` back to its watermark,
`leads` 20,465 unchanged, and 0 surviving canary identities in `auth.users`.

---

## The bigger exposure the fix uncovered — measured, not fixed, and named here

Revoking the seven closed the ones probe 6 proved reachable. It did not close the category. Measured
directly with `has_function_privilege` after the revoke, and corroborated by Supabase's own security
advisor:

| | |
|---|---|
| SECURITY DEFINER functions in `public` | **786** |
| still executable by `anon` | **56** (was 63 before this session) |
| still executable by `authenticated` | **60** |
| advisor `security_definer_view` at ERROR | **30** |
| advisor `function_search_path_mutable` at WARN | **74** |

**The reframing matters more than the count.** The 2026 triage kept grants on the strength of a
`BROWSER` category — "a real product surface calls them". That category is **empty by measurement**:
`grep -rn "\.rpc(" src/` returns **0 occurrences in the entire frontend**. The browser calls no
database routine directly, through any helper, anywhere. So **no `anon` grant on any of the 56 is
justified by a browser surface**, and the reason the seven were left open cannot be the reason any of
the rest are.

This is **not** revoked here, and the restraint is deliberate rather than lazy: the original triage
said each remaining function "needs one look before its grant goes", and it was right. A blind sweep
over 56 routines under a zero-effect hold, with cron and edge callers unverified per function, is how
a security tidy-up becomes an outage. What has changed is that the justification for leaving them is
now known to be false, so the look is owed. It is the single largest open security item this session
found and it is stated with its number rather than folded into a green tick.

The 605 `rls_enabled_no_policy` INFO advisories are the deliberate deny-all posture and are **not** a
gap — probe 6 confirmed by execution that every non-empty one is unreachable by `anon` and by a real
authenticated bearer.

---

## The Row #3 score is 105/152, and the two lost points are a clock, not a regression

The blueprint scorer completed with its own total line — `SPEC FILE #3 (executive UI) on
htdblwldjkcgjvmqkbeh: 105/152 (69%)`, 152 checks, exit 0. A complete run, not a partial. The brief
expected 107, and the scorer names the two it lost as REGRESSED:

| check | why |
|---|---|
| `company-brain-one-page-graph` | `public.graph_nodes` last rebuilt **2026-08-16 08:34:21**; the check requires `max(updated_at) > now() - interval '3 days'`. At 11:38 UTC it was **75.1 hours** stale — it crossed the 72-hour line about three hours before the run. |
| `exec-home-monthly-goal-pct` | the same 3-day recency bound on `public.goal_period`, whose refresher last ran **2026-08-16 02:45**. |

**Neither was caused by this session's changes, and that was checked rather than assumed.** The
obvious suspicion was the D35 revoke — `fn_supplier_knowledge_graph` is one of the seven and the
failing check has "graph" in its name. It is not the cause: the scorer's `UI_READS` counts routines
whose `pg_get_functiondef` **text** matches the table name, so it is blind to grants, and the readers
it names for `graph_nodes` are `fn_company_map` / `fn_ws_com…`, none of them revoked.

The actual cause is measured: both refreshing cron jobs are switched **off**.

| job | schedule | active | last run |
|---|---|---|---|
| `graph_rebuild_daily` | `5 4 * * *` | **false** | 2026-08-16 04:05 |
| `goal_period_refresh_daily` | `45 2 * * *` | **false** | 2026-08-16 02:45 |

They were stood down by the Phase D automation hold — which is also why the active cron count is the
required 23. **They were deliberately not reactivated**: doing so to move a score by two points would
be running automation the hold forbids, to make a number look better. The two points return on their
own when the hold lifts and the daily jobs run again. This is recorded so the next session reads
105 as "two clocks expired under the hold", not as damage.

1. **GATE-020** guards a step named *"Execute approved financial action"* but checks only that
   **some** decision exists, not that it was an **approval** — a rejected case satisfies it. Phase B
   is frozen. Measured and reported; not changed.
2. **The reveal contract.** §9 refuses a payload missing any of the four messages he specified
   (email + WhatsApp to **both** parties). `trg_reveal_receipt` still sends **one** email to the
   customer, naming no channel and no phone. On the board as DISCLOSED. Nothing was enabled.
3. **Terms of Service v6 §5(b)** (`src/content/legal.json`) still contradicts how he says refunds
   work. The frozen W17 model already matches his version. **Not one word of the published text was
   edited.**
