# Handover — read this first

Written 15 Aug 2026. If you are a new session on this repository, read this before anything else.
It is the current state of the work and the founder's standing rules, in his words where possible.

---

## How the founder wants this run

1. **Free verification first, always.** Anything that can be checked deterministically — SQL, an
   aborted-transaction probe, a code path with a stubbed input — is checked that way before a single
   model call. His words: *"To do a test is your top priority. You don't make me spend money unless
   it's hundred percent needed and there's no other way around it."*
2. **Never mention context limits.** He monitors them. Do not raise the subject.
3. **Do not jump between steps.** Finish a phase completely before starting the next. Do not report
   a phase closed while part of it is open.
4. **Verify the code is correct before paying to test it.** Gate A-style shape checks are not enough;
   they count things. Mechanism probes are what find defects, and they are free.
5. **Use the real job title when referring to an agent**, never the bare key. Write
   *Interior & Fit-Out Specialist (`spec_fitout`)* if the key is genuinely needed, never `spec_fitout`
   alone. All 90 titles resolve as identifiers — verified 90/90.
6. Escalate only: Stripe refunds, spending money, the three go-live switches, and facts only he
   holds. Everything else is an engineering decision — make it.

### Why he is angry about cost, and the correct framing

He has spent roughly USD 200–300 on OpenRouter over two months with the company not operating. The
explanation, found 14 Aug: **every agent was answering with no context at all** — no identity, no
knowledge, no authority — while returning HTTP 200. The money did not go on testing; it went on a
company of blind employees. That is fixed. Any role-quality score measured before 14 Aug describes
a blindfolded system and must be discarded, not improved upon.

Note also: the large "session cost" figures he sees are **Claude Code usage**, not OpenRouter. Total
OpenRouter spend for all testing on 14 Aug was about **AED 8 (~USD 2)**. Keep the two separate when
discussing money with him.

---

## The phase plan (his structure, agreed)

**Phase A — identity and structure. IN PROGRESS. NOT COMPLETE.**
**Phase B — knowledge per agent. NOT STARTED.**
**Phase C — departmental linkage. NOT STARTED.**

> I reported Phase A closed on 15 Aug. **The founder said it is not** — *"no phase A has alot of
> work still."* He is the judge of when a phase is done, not the checks. Do not re-declare it
> complete. Ask him what remains, or work what he names, and take the checks below as evidence of
> what has been verified so far — not as a verdict that the phase is finished.

Do not begin Phase B until he says Phase A is done. Do not touch Phase C before B is finished.

---

## Phase A — what has been VERIFIED so far (not a completion claim)

| | |
|---|---|
| agents / departments / overlays | 90 / 10 / 86 |
| duplicate names, keys, IDs | 0 |
| two agents with identical decisions or responsibilities | 0 |
| two agents doing the same job (semantic, 4,005 pairs) | 0 |
| Gate A | **20/20 both projects** |
| behavioural suite | **70/70 both projects** |
| `project_parity` | **BOTH PROJECTS IN SYNC** |

Every agent is runtime-ready — context, role knowledge, department knowledge, company core, tools,
authority, model routing, complete contract, autonomy gate, onboarding gate: **90/90 each**.
89/90 have a manager; the CEO reports to the founder, correctly.

Identity resolution: **34 unresolved routines → 7**. The remaining 7 are not employees — a Supabase
auth uuid (`fn_approval_decide`), the founder's email (`fn_control_mode_*`), and supplier catalogue
filters (`match_suppliers`, `match_suppliers_kw`). Each was examined individually, not counted.

---

## Defects fixed 14–15 Aug (all deployed to BOTH projects, all verified by execution)

- **Context assembly returned nothing for every agent.** `fn_agent_context_capped` was declared
  `STABLE`; PostgREST runs a `STABLE` function in a read-only transaction; the nested recording
  `INSERT` threw and took the whole context with it. One word: `VOLATILE`.
- **Reviewer independence defeated by an alias** in all ten departments — plus a `BEFORE INSERT`
  trigger on `review_chain` so a function writing the table directly cannot bypass it.
- **Spend meter blind to 64% of the money** — merged-away department keys and a log that discarded
  the department the router had already resolved. The halt is proven to fire.
- **The autonomy gate failed OPEN** — a blocked employee asked about under an alias read "cleared".
- **`fn_agent_tools` granted no tools at all** to an aliased employee — 44/44 alias probes returned
  zero before, 0/44 after.
- **`fn_prompt_rollback` was a route to activate a never-approved prompt**, bypassing the approval
  gate, and it overwrote `approved_by`.
- **`fn_kb_approve` certified publishes it had not performed** — 8 revisions.
- **Truncated model answers were returned as complete.** Now: detect → one repair call → fail closed.
- **The tool registry had never reached production.** One stale `fn_agent_tools` signature was
  holding four files out; production had no `agent_tool` table at all.
- Plus: the retrieval filter was disabled on production (`or true`), the routing tier never reached
  the employee path, and 12 plpgsql + 3 sql routines compared identities they never resolved.

---

## Open, and each is genuinely his call

1. **Gate C / Gate D runs.** OpenRouter large-tier credit is available again. The blueprint requires
   budget approval before Gate D. Measured basis: Gate B cost **AED 0.12/case on the medium tier**;
   the large-tier per-case cost has NOT been measured — do not estimate it as though it had been.
2. **A dedicated OpenRouter key** for test runs, separate from the company's operating key. An
   account action only he can take.
3. **Four managers have no cadence.** Giving them one is activation.

## 15 Aug — the role/workflow alignment pass (PR #387)

The founder asked for the 10-department / 90-role organisation to be **corrected against the actual
workflow**, not rebuilt. Done and merged-ready; six documents in `docs/agents/FINAL_*`.

What it found, all measured before being fixed:

- The step that decides **which suppliers see a customer's RFQ had no owner**. `workflow_step`
  `rfq_handling` #5 read `domain specialist`, which resolves to nobody.
- `rfq_handling` had **no supplier-safe payload / privacy review step at all**, and no
  document-processing, readiness-scoring or message-delivery step.
- **20 of 90 roles were named by nothing** across seven surfaces. Now 0.
- **The designer was the default reviewer of its own artifact** — `artifact_review` defaulted
  `reviewer_agent` to `marketing_design`, the Visual Design Director's own runtime key, and both
  guards compared identities raw.
- **A refused supplier was counted as a notified one.** The eligibility guard returns null, which is
  not an error, so `if (!error) inserted++` counted a refusal as a contact and `routing.fanout`
  over-reported the RFQ's reach.
- **Whoever took the reveal payment reconciled their own charge.**
- `employee_workflow` held **157 rows on production and 0 on staging**.
- A step run had sat **queued since 10 Aug addressed to `Director`**, which resolves to nobody.
- **A retry's cost was money nothing recorded** — `llm_attempt` had 666 rows and 0 with a cost.
  (`ai_cost_log` *does* price every request; the gap was per-attempt, on the fallback ladder.)

Evidence: 60/60 + 16/16 deterministic tests on both projects, `fn_os_portals_gates()` 22/22 met on
both, `project_parity` IN SYNC, and a capped staging smoke of 16 scenarios at **AED 3.23** with 0
truncated outputs.

**Still not exercised end to end: production holds 0 inquiries.** The chain is proved by registry
and by forced guards, not by a live inquiry travelling it. The eligibility probe reports SKIP on
production for that reason rather than passing over absent data.

## Open engineering, free to do, not yet done

- **Cross-department handoffs do not work.** `handoff_contract` has 0 rows on both projects and
  `fn_handoff_open` refuses every contract constructible from its own documented field list — it
  names 8 required fields, all 8 supplied, still `ok=false`. Diagnose this first in Phase C.
- **KPI misses do not reliably reach a department head.** Product & Engineering missed 19 KPIs in
  seven days and its head was never told; People Ops missed 16. Customer Experience missed 24 and its
  head ran 59 times. Managers have no cron of their own — every manager run is a
  *"DEPARTMENT WORK ORDER from the Chief of Staff"*, and that routing is partial. Phase C.
- **Deterministic mechanism probes do not exist as a suite.** Tool result envelope, decision-trace
  completeness, handoff lifecycle. These should have been written before any paid gate.
- ~10 approval routines have no self-approval check at all. Some need schema first — `review_queue`
  has no author column, so `fn_review_decide` cannot be guarded until one exists.

---

## The lesson that keeps repeating

**Four instruments produced real numbers about the wrong subject on 14 Aug alone:**
a check that bound to the wrong column and failed 270/270; overlay joins missing a number prefix,
failing 86/86; a KPI query comparing lowercase `'missed'` against uppercase `MISSED`, returning zero
from 207 real misses; and a manager check counting deleted demo runs.

**If a check fails for 100% of its population, the check is wrong.** Verify the instrument before
reporting the finding.

---

## Phase B, when he starts it

His definition: every agent must hold the knowledge from **all** sessions, not just recent ones;
build what is missing; test → build → test until each reads like twenty years in its field.

**First deliverable, free, before any model call:** a per-agent knowledge inventory — all 90 agents,
what each holds, which layers, how many records, and where it came from. He has asked to see this.

The only part of Phase B that genuinely needs money is judging whether an answer reads like an
expert. Everything before it is free.

---

**Branch:** `repair/v3-certification-remediation-1` · **latest commit at handover:** `9b0aa44`
**Projects:** production `htdblwldjkcgjvmqkbeh`, staging `pglpqrhvozwepymcuunn` — deploy to both,
always. PR #385 merged 14 Aug.
