# QuotesDone Phase D — builder closure, session 5 (D17–D24)

**PHASE_D_NOT_READY**

| | |
|---|---|
| session | 2026-08-18 21:41 → 2026-08-19 UTC (database clock) |
| project | `htdblwldjkcgjvmqkbeh` — the one project |
| branch | `feat/phase-d-d9-the-handoff-is-159-contracts`, PR [#450](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/450) |
| baseline at start | `669d3cb`, closure **20 / 30**, re-measured by execution before any work |
| paid inference | **USD 0.00** — 0 `llm_attempt` rows in the session window |
| live external effects | **0** — and this session found the guard that was not measuring them |
| active cron, start → end | **23 → 23** |

Phase E was not begun. No frozen Phase A, Phase B or Phase C object was edited. No Phase D audit
was run. Business automation was not reactivated.

---

## The one number that moved

| | before | after |
|---|---|---|
| workflows reaching deterministic closure | **20 / 30** | **28 / 30** |
| handoffs accepted in one 30-workflow batch | — | **153** |
| business effects in one batch | — | **244** |
| outbound HTTP requests per scenario build | **2** | **0** |

Closing now and not before: **W01, W05, W06, W07, W09, W14, W15, W16**.

Two remain and one of them is not an engineer's.

---

## 0. What was re-measured before anything was built

The brief states its counts are reliable and its diagnoses have been wrong before. Both held.

**The counts were exact.** Driving the ten named workflows reproduced all ten stops at the named
steps with the named codes.

**The central diagnosis was wrong.** The brief attributes four stops to "the harness seeds the row
the step creates" and asks that `for_workflow` be re-tested. It was, and it does not close them:
with the exclusion on, W09 skipped 3 stages, the cascade blocked 13 more, and **W09-S03 still died
on `supplier_capabilities_pkey`**. Removing the fixture row did not remove the collision, which is
the tell that the fixture was never the mechanism. The real cause is in §2 below. The brief is right
about exactly one of the four — W12 — and that one is now narrowed correctly.

---

## 1. The fixture had a second door, and it was HTTP (D17)

Measured on production before anything was written:

```
net.http_request_queue   before=0  after=2  delta=2
  POST https://…/functions/v1/dispatch_inquiry
  POST https://…/functions/v1/enrich_capability
```

**Every `fn_phase_d_fixture_scenario` build enqueued two outbound POSTs to production edge
functions, and the factory returned `'external_effects', 0` while it happened.**

The factory's assertion counts `public.notifications` before and after every stage and aborts on any
delta. It is real and it works. It is also named for external effects and measures one table.
`net.http_post` is a second door. One of the two requests is `dispatch_inquiry` — the RFQ offer to
matched suppliers — which is precisely the business-producing automation this phase holds.

**Nothing was ever sent, and that is a measurement rather than a hope.** pg_net's worker reads
committed rows; every Phase D transaction ends in `raise exception`. The probe read `before=0` on a
database that has had dozens of scenario builds run through it across D9 and this session. What was
wrong was the guard, not the outcome — but the abort is the only thing standing between this factory
and a live dispatch, and `mgmtFixture` is a committing door that exists.

The fix is in `fn_phase_d_object_write`, which every Phase D write goes through, so it covers the
driver and the handlers and not just the factory. It takes the queue's high-water mark before the
write and counts rows above it after, because pg_net's worker DELETES as it drains and a plain count
delta can be masked to zero by a concurrent drain.

**The scan found four doors, not the two that fired.** Starting from the observed POSTs would have
registered half the surface:

| trigger | relation | endpoint | disposition |
|---|---|---|---|
| `enrich_capability_on_approve` | leads | enrich_capability | FIRED — suppressed |
| `autodispatch_inquiry` | inquiries | dispatch_inquiry | FIRED — suppressed |
| `trg_sign_customer` | customers | compliance_archive | silent — unreachable |
| `trg_sign_supplier` | leads | compliance_archive | silent — unreachable |

No trigger is disabled, altered or dropped. The two that fire are closed through their **own**
already-done guard — `capability_enriched_at` and `routing->>'dispatched_at'` — declared in the write
map so the suppression is a mechanism rather than a comment. Neither column is read by any Phase D
rule, gate contract, `fn_rfq_score` or `fn_rfq_required_check`: measured, 0 each.

The two silent doors are recorded with a **checkable** reason. The board proves the named column
appears in the trigger's own definition and does **not** appear in the relation's write map, so the
day someone maps `owner_email_verified` it goes red — which matters, because
`fn_leads_derive_owner_email_verified` can move that column from an ordinary email write.

Proved by execution: registry emptied → the write refuses; registry in place → a 23-stage build
enqueues **0**. `fn_phase_d_outbound_state()` 9/9 GREEN.

---

## 2. An upsert that could not find the row it wrote (D18)

Proved in isolation on production, no workflow involved:

```
write 1  business_key=KEYPROBE-A  owner_ref=30723 -> supplier_capabilities:supplier_id=30723
write 2  business_key=KEYPROBE-B  owner_ref=30723 -> REFUSED duplicate key … _pkey
```

`UPSERT_STATE` probed `where key_column::text = business_key` unconditionally, which is only correct
when the map points key_column at business_key. Two shapes in the estate do not:

- **`supplier_capability`** — `key_column = supplier_id`, `column_map.supplier_id = 'owner_ref'`. It
  probed one value and inserted another, so it could never match its own row.
- **`quotation` / `payment_transaction`** — `key_column = id`, generated, probed against a uuid
  business key. Never matched, so `UPSERT_STATE` could only ever INSERT, and the second insert died
  on the relation's natural key.

Identity is now resolved in two derived passes: key_column using the value that will be **written**
into it, then any other unique index whose columns are all mapped and all supplied. The index's own
predicate travels with it from `pg_get_expr`, so the partial `transactions(quote_id) WHERE quote_id
IS NOT NULL` matches exactly the rows it constrains.

**Not fixed and not hidden:** `supplier_account` has no resolvable identity, so W09 still writes four
lead rows for one supplier. `fn_phase_d_object_identity_state()` lists every such map and is **RED
with an owner**. Inventing an identity for `leads` would be the harness deciding what a supplier
account is.

---

## 3. Five more, each found by running the thing rather than reading it

**D19 — a generated payload re-armed the door D17 had just closed.** Driving after D18, W05 went
2/9 → 1/9, refused by D17's own guard on `dispatch_inquiry`. D17 declared `routing` in the write map
so the writer could set it; the driver generates a value for every declared column, so from D17 on it
supplied its own `routing` with no `dispatched_at`, and the injection's *if not supplied* check stood
aside for it. **Declaring a column so the writer can control it is also what makes the harness invent
it.** The suppression is no longer defeasible by the caller.

**D20 — the driver created every object open and asked the gate whether open was good enough.** Five
stops were one defect wearing five refusal codes. Every one of those gates is MEASURED — it reads the
real row — and every one was right. The driver's existing derivation reads the target's state CHECK,
and **four of the five relations carry no CHECK at all**, so it resolved null every time and the
`coalesce(…, 'open')` beside it did all the work unannounced.

**D21 — the run renamed its own inquiry, and a gate was blamed for not finding it.** Four workflows
stopped at the gate immediately after a review step, each complaining about an object id from one
sequence while `inquiries.id` is a uuid. Review steps name a business object in `effect_object_id`
and produce a **review_record**; the fold filed that record's id as `inquiry_id`. GATE-011 said
"inquiry 3123 … does not exist" and that was the true half of its own message.

**D22 / D23 — three more, and one regression of my own.** A COMPANY-scoped owner is still a foreign
key (`org_tasks.dept_key` → `org_departments`, resolved never created — Phase A is frozen at 10
departments). An APPEND_ONLY object may not share one business key across two steps. `for_workflow`
narrowed by a rule rather than a list: **a stage no other stage requires cannot cascade**, so only
leaves are skippable — 3 skipped/13 blocked became 2 skipped/1 blocked.

**D25 — the key was computed correctly and thrown away one statement later.** D22 gave APPEND_ONLY
objects a per-step business key so W16-S03 and W16-S04 would each append their own provider event,
and W16 still died on . A cache a few lines below — one business key per object
for the life of the run — overwrote it. The cache is correct and without it W04 wrote two customer
rows, but its entire purpose is to make a second write MOVE the first row's state, and APPEND_ONLY is
defined by not doing that. The family the cache exists to serve is exactly the family it must skip.
D22 claimed no fix for W16 and its control asserted NO REGRESSION rather than a number, which is the
only reason a change that did nothing was not recorded as a fix.

And the one this session broke and caught: **D20 gave the driver the real state and W09 went 9/9 →
1/9** on `leads_approved_implies_verified`, because writing `approved` also owes `verified`. Caught
only by re-driving **all thirty** rather than the nine being iterated on. It was introduced two files
earlier and shipped for the length of one commit.

---

## 4. Two things the sweep found that the increments did not

**`build_workflow_implementation_result.mjs` could not produce its own deliverable.** It routed
through `mgmtWriteData`, which refuses production and is INSERT-only, so the committed CSV was not
made by the script that claims to make it. Three further defects in it, each of which would have
shipped a deliverable that looked populated and carried nothing: one exception carrying 30 rows
against a transport that truncates at 2000 characters; a raw JSON body whose `` separators
arrive escaped; and a residue check naming `source_ref`, a column `phase_c_workflow_run` does not
have — **the check that proves the probe left nothing behind had never once run.**

**A new table joined a guarded population.** `fn_kernel_truncate_protection_state` went red: D20 put
a raising trigger on `phase_d_fixture_stage`, which is what makes a table "enforcing" here, and it
arrived without a TRUNCATE guard or a revoke. A row trigger cannot see TRUNCATE, and that table is
now the registry the driver reads its states from. D20 could not have known it was joining a guarded
population; the board derives that population from `pg_trigger` and knew.

---

## 5. Zero cost and zero external effect

| | |
|---|---|
| OpenRouter / paid inference requests | **0** |
| `llm_attempt` rows in the session window | **0** |
| paid inference cost | **USD 0.00** |
| live email / SMS / WhatsApp / social / payment / refund | **0** |
| `public.notifications` rows written by this session | **0** |
| outbound HTTP enqueued by a 30-workflow batch | **0** (was 2 per scenario build) |
| Apify runs · production Dropbox writes | **0** · **0** |
| active cron jobs, start → end | **23 → 23** |

**The boundary, stated:** `public.notifications` holds 2 rows in the last 14 hours, both
`type='health_alert'`, `status='digest'`, timestamped 14:30 and 21:00 UTC — the scheduled read-only
monitoring the hold keeps active, both written **before** this session's first drive at 21:41. Every
scenario build additionally asserts its own per-stage delta of 0.

**Nothing was left behind.** Read back after the full 30-workflow batch: `customers` 0, `inquiries`
0, `quotes` 0, `transactions` 0, `phase_d_effect_ledger` 0, `net.http_request_queue` 0,
`fn_phase_d_fixture_residue()` **0**, `leads` 20,465 unchanged.

---

## 6. Estate state at close

| check | result |
|---|---|
| `fn_phase_a_baseline_drift()` | **0 rows** |
| `fn_phase_b_baseline_drift()` | **0 rows** |
| `canonical_routines.test.mjs` | **11 passed** — 0 drift both directions, 0 manifest gaps |
| `kernel_boards_are_green.test.mjs` | **7/7** — 33 boards, 388 checks, 9 red, every one disclosed and owned |
| `fn_kernel_truncate_protection_state` | green after D24 (was 1 of 79 red) |
| `fn_phase_d_outbound_state()` | **9/9 GREEN** |
| `fn_phase_d_object_identity_state()` | 3 GREEN, **1 RED — disclosed**, `supplier_account` has no resolvable identity |
| `fn_phase_d_reference_fold_state()` | 1 GREEN, 2 DISCLOSED |
| schema mirror vs live export | regenerated — production gained `phase_d_outbound_door` |
| `sql_files_match_live.test.mjs` | **retired** — the file is `sql_files_match_live.RETIRED.mjs`; `canonical_routines.test.mjs` replaced it |

---

## 7. What is NOT done — the itemised remainder

| brief section | state |
|---|---|
| **§A–D workflows** | **28 / 30.** Two open, listed below. |
| **§8** frontend → API → RLS → storage, 7 security probes, storage rules | **NOT STARTED.** |
| **§9** durable external-effect adapters | **NOT STARTED.** Still **6 of 14** fields PRESENT; the 8 the brief names are unchanged. |
| **§11** 75 injected defects | **NOT STARTED.** |
| deliverables | **10 of 15.** |

**Still owed:** `PHASE_D_FRONTEND_API_CALL_GRAPH.csv`, `PHASE_D_STORAGE_RLS_SECURITY_RESULT.md`,
`PHASE_D_FINANCIAL_PRIVACY_RESULT.md`, `PHASE_D_IDEMPOTENCY_CONCURRENCY_RESULT.md`,
`PHASE_D_EXTERNAL_EFFECTS_RESULT.md`, `PHASE_D_INJECTED_DEFECT_RESULT.csv`.

This session spent itself on the workflow block and on four defects the workflow block uncovered. It
did not reach §8, §9 or §11, and it does not claim to have.

### The two workflows that still stop

| workflow | stops at | what it needs |
|---|---|---|
| **W12** | W12-S02, `pd_object_duplicate_identity` | `dispatch_batch` is TRANSACTION_RECORD and two steps write it under one business key. The same family question D22 answered for APPEND_ONLY, asked again for TRANSACTION_RECORD — and the answer is not the same, because one record per identity is the whole point of that family. It needs the driver to MOVE the batch's state rather than write a second, which is a step-level state ladder this session did not build. |
| **W17** | W17-S07, `GATE-020` | **The gate working correctly. Not a defect.** |

---

## 8. The blocker that is the founder's, not an engineer's

**W17 cannot reach closure without a recorded founder decision on a refund.** GATE-020 refuses
W17-S07 because `phase_c_refund_decision` holds no decision for the case. His standing rule is that
every refund needs him at any amount, and it is enforced by a trigger rather than a convention.

A fixture must never forge that artefact. **30/30 is therefore not reachable by an engineer alone**,
and the brief says so itself. D22's deploy control now *requires* W17 to drive 7 of 11 and refuse at
W17-S07, so a later change that quietly makes it pass will fail the deploy.

Raised once, not re-asked. It needs either a founder decision recorded in a test context, or his
ruling that a test-context refund may carry a synthetic one.

## 9. Two items carried forward for him, unchanged and not acted on

1. **The reveal notification is one email to the customer.** He stated it should be an email to both
   parties plus a WhatsApp to both. `trg_reveal_receipt` still contains exactly one insert into
   `public.notifications`, `to_role='customer'`, naming no channel and no phone. §9 must be built to
   the four-message contract he described. Nothing was enabled.
2. **Terms of Service v6 §5(b)** still makes a refund conditional on the customer having emailed the
   supplier and CC'd `supplier@quotesdone.com` beforehand. He said that is not how it works. The
   frozen W17 model already matches his version. **Not one word of the published text was edited.**

---

**PHASE_D_NOT_READY**
