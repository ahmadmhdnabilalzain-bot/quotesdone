# 12 Aug 2026 (afternoon) — a human walked the registration, and four instruments were lying

Session ran 11:24–12:30 UTC. One PR, [#251](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/251), squash-merged as `676439c`. Both Supabase projects, every change verified by execution in the same turn.

---

## 1 — The registration path has now been walked end to end

Nobody had ever completed a supplier registration. I did one against **production**, through the real
browser and the real endpoints, using a mailbox I can read.

| step | evidence |
|---|---|
| invitation e-mail | delivered from `supplier@quotesdone.com` to a real inbox, 11:30:04 |
| invite link → portal | `?t=` captured into sessionStorage |
| sign-up + OTP | code `796283` read from the inbox, verified |
| claim | `claimed_by` set **11:31:25**, automatic, no user action |
| trade licence upload | read at confidence `high` — **6 of 6 printed fields correct** |
| company profile | stored, `capability_summary` generated |
| submit | `registration_submitted_at` **11:41:08** |
| approval | `approved`, AI review `clean` |
| scope screen | rendered in an authenticated session for the first time |
| confirm | `confirmed_at` **11:43:16** |

```
select claimed, claimed_by, portal_updated_at, registration_submitted_at, approval_status
  from leads where claimed_by = 'ahmadmhdnabilalzain+qdprobe1@gmail.com';
-- t | ahmadmhdnabilalzain+qdprobe1@gmail.com | 11:41:08 | 11:41:08 | approved

select confirmed_at, trades, roles from supplier_capabilities where supplier_id = 30466;
-- 2026-08-12 11:43:16 | {hvac,electrical,plumbing,mep_general} | {contractor,installer,maintenance}
```

Then I went one step past the brief and asked the matcher:

```
select * from fn_match_capability(array['hvac'], 'executes', p_emirate := 'Dubai', p_value := 250000);
-- 30466 | MERIDIAN MEP CONTRACTING LLC | score 5.0 | "trades hvac · covers Dubai"
```

**This company has a matchable supplier for the first time.**

Lead 30466 carries `source='qd_live_path_probe'`. A real registration by a real mailbox — but mine,
and it should not be counted as a customer-facing supplier. `name_corrected_from` still holds the
probe label the licence extractor replaced with the licensed name.

### The one step I could not walk

Submit is gated client-side on `phoneVerified`, which needs a Twilio SMS to a **real handset**. I
completed that step by calling `save_profile` — the same endpoint the button calls once the gate
passes — so the server path is proved and the client gate is not. That gate is a genuine anti-fraud
control and I did not weaken it. It needs a phone you hold.

`phoneVerified` itself is correct: it rehydrates from `kyc.state`, which reads
`leads.owner_phone_verified`. I had it recorded as a defect until I read line 1022.

---

## 2 — Four instruments were reporting on the wrong subject

Every item below is the same shape: a number that was green, or an alarm that was red, about
something other than what it named.

**`owner_email_verified` could never be set on the invite path.** `login_otp` proves the mailbox and
records it with `update leads set owner_email_verified = true where claimed_by = <email>`. The
portal's order is capture `?t=` → sign in → *then* claim, so at verification time no row carries that
address: `UPDATE 0`, forever. 0 of 7 claimed leads had it. Proved rather than inferred — same
account, same function: verified 28 s **before** the claim → stayed false; verified **after** →
became true. Fixed as a derivation on `leads` (BEFORE trigger on `claimed_by`) because the fact
belongs to the *address* and is already durable in `email_verifications.used_at`.

**17 lessons manufactured from 4 readings.** The brief asked for `expected_kpi_id` /
`expected_direction` / `measure_after` on `decision_log`. Measured: 1,584 of 1,603 `decision_log`
rows are `kind='action_gate'`, `decision='permitted'`, `reasons=[]` — admission control, not
decisions. Adding a KPI claim there would have been the exact fabrication the brief forbids two
paragraphs later. `outcome_record` was already working. What was broken is what the loop *wrote
down*: all 17 graded outcomes were `improved`, every `observed_value` exactly 100.00, all tracing to
four readings — 8 agents sharing one `measure_sql` (our own HTTP health-check pass rate). Legal,
contract_specialist, marketing_content and brand_mgr were each told their work raised HTTP
availability, at confidence 0.9, "Promote to standard practice". A shared reading now yields one
memory naming its co-claimants, `promoted` stays false, confidence 0.4. Retracted the existing ones:
**18 outcome memories → 4, high-confidence claims 17 → 0, promoted 17 → 0**, all 17 measurements kept.

**The cacheable half was a different length every call.** `agent_brain` is ~60% of spend (637 calls,
AED 79.46 in 7 days) at a 0.117% cache-read ratio. Two of the three `# LAYER` markers it splits on
**have never existed**. But fixing the strings alone would have been *worse* than nothing: the head's
budget was `v_want - length(tail)`, computed from the query-matched tail, so the "stable" prefix
moved every call — a cache write at 1.25× and reads on none. Head now has a fixed budget and an
explicit sentinel. Measured after: same agent, two questions, boundary at 17,501 both times,
identical md5, **81.3% of the context now cacheable**.

**The sweep called a working throttle a stalled engine.** `workflow_step_sweep` wrote
`status='error'` every 10 minutes — 144/day — saying 107 steps were stalled. 67 genuinely have no
`action_class`. The other 41 satisfy every claim predicate and are held by *yesterday's deliberate
reflection ceiling* (24 worked today against a cap of 6). `it_health` reads those rows, and its
incident is in `decision_log` verbatim: *"10 agent run(s) failed in last 24h… workflow_step_sweep"*,
routed to the CTO. Three layers believing a misread. Verdict now separates throttled / awaiting
classification / unexplained and raises only on the last: **108 = 67 + 41 + 0, status ok.**

---

## 3 — The invite list is culled, for free

Swept DNS for all 8,564 lead domains — most of what a paid verifier does, at zero cost.

```
mx 6,546 · a_implicit 340 · nxdomain 1,359 · no_records 43 · error 76 (fails open)
```

**1,402 domains do not accept mail → 1,566 leads culled. Eligible 19,835 → sendable 18,037**, 7.9%
of the list removed before a single message is sent. `a_implicit` matters: RFC 5321 §5.1 means a
domain with no MX but an A record still receives mail, and demanding MX alone would have discarded
340 live domains. `error` rows and unchecked domains stay sendable — a resolver outage must never
quietly empty the queue.

`invite_enabled` stays **false**. Your order was prove the path → cull → ramp. First two are done.

---

## 4 — Smaller things

- **`kb_embed`'s `source_kinds` filter was built on 11 Aug for `trade`/`regulation`/`material` and
  neither cron ever passed it.** Sixth "finished capability with no entry point" this week. Added a
  third job; first tick embedded `material` 0→3 and `trade` 0→2. Draining now, ~1 hour, free.
- **`email_domain_mx` reached staging without RLS** — caught by `project_parity`, not by me. Fixed.
- **OpenRouter**: refused 43 calls today between 01:00 and 09:00 UTC (15.2% of the day, against
  0.4–0.7% on prior days), concentrated in `exec_agents` at 07:00. **Nothing has failed since 09:00
  UTC.** `ai_health` confirmed the gateway and key reachable throughout, so it is per-call refusal,
  not an outage or a credential problem. Still undiagnosed beyond that.

---

## What I deliberately did NOT do

**The 67 unclassified workflow steps.** They come from ten workflow *definitions* — `employee_task`,
`rfq_handling`, `payment`, `refund`, `complaint`, `supplier_onboarding`, `customer_registration`,
`invoice_approval`, `campaign_publishing`, `supplier_suspension` — and **none of them carries an
`action_class` on any step**. The company's entire operating model is written down as workflows that
nothing can execute. Classifying them would make **~1,049 queued steps fire at once**, and `refund`
reaches Stripe. That is a per-class review against `notifies_human` / `risk_tier` / `reversible`, one
workflow at a time. `org_task` **#1394** now carries it. Doing it quickly would have been worse than
not doing it.

**`prompt_cache_enabled` stays false.** Your sequence is fix the split → re-measure a full week →
decide. The 0.115 ratio that turned it off was measured while the split cached nothing, so it
measured nothing. The real governing number is how often one agent calls back inside the TTL — over
7 days, 621 calls across just 12 agents, median gap **1 minute**, **58.5% within 5 min** (break-even
22%) and **89.0% within 1 hour** (break-even 53%). Both clear it comfortably. That is the prediction
the week should test.

---

## State at 12:30 UTC

```
Row #3        127/152 · gates 23/23 both · parity IN SYNC · advisors 0 ERROR both
packs         INGESTED 100% · IN USE 37/37 · RETRIEVABLE 54.3% prod / 47.4% staging
leads         20,471 · 18,037 sendable (was 19,835) · 1,475 dead domains recorded
capabilities  1 CONFIRMED and matchable (was 0) · 15,305 confirmable
registration  1 completed end to end, by a human, on production
invites       62 sent · invite_enabled=false · 0 real registrations besides the probe
spend         17.42 AED today · agent_brain ~60% of it · cache split now works, switch still off
learning      outcome memories 18 → 4 · high-confidence causal claims 17 → 0 · promoted 17 → 0
demand        customers 0 · inquiries 0 · quotes 0 · transactions 0 — UNCHANGED
```

## The question that found most of it

Last session's two questions still work. A third earned its place today:

> **Is this number measuring what its name says?** Four separate alarms and scores were about
> something other than their subject — a health-check pass rate sold as a marketing lesson, a
> deliberate throttle sold as a stalled engine, an OTP that proved a mailbox and updated nothing, a
> "stable" cache prefix that moved on every call. None of them failed. All four looked fine.
