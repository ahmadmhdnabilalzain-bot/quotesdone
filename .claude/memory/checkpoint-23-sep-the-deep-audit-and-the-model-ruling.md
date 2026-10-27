---
name: checkpoint-23-sep-the-deep-audit-and-the-model-ruling
description: "READ FIRST on resume — 23 Sep: 16 PRs merged from the deep audit, the per-seat model matrix applied (AED 1,200/mo), what is still open and what the founder decides next"
metadata:
  node_type: memory
  type: project
  originSessionId: 8c4972a3-8a16-4cb0-a308-31a4f45e00bb
  modified: 2026-09-23T06:35:22.387Z
---

State at the end of 23 Sep 2026. Step 2 of [[founder-plan-audit-then-llm-then-full-test]] (the deep
audit) is largely executed; step 3 (the founder opens OpenRouter) has not started.

## Merged and deployed today
#846, #847, #848, #849, #850, #851, #852, #853, #854, #855, #856, #857, #860, #861, #862, #863, #864,
#865, then #866 and #859 — **twenty-one, and the queue is EMPTY** (`gh pr list --state open` = 0 at the end
of 23 Sep). #859 landed last at 06:33 UTC. **A stale queue will keep arriving** — the founder pasted the
early-session list (856/857/861 "in flight") after all of them had merged. Check the live state before
acting on any list of PRs; never redo work because a summary says it is pending. `canonical_routine_manifest.mjs` finished at **0 findings across all six counters**.
Fifteen edge functions were deployed by hand after their applies, all verified `ok=true` — CI's deploy
job runs but has no token, so **a green "deploy changed functions" does not mean production was
updated**; `verify_deploy_parity.mjs --all` is the only thing that says so. The P0s are closed in production and verified: two supplier leaks (#854 — a
supplier cannot see a competitor's price, an unmatched inquiry returns `not_found`, estate-wide counts
gone) and the reveal-fee leak (#850 — document 62933 verified out of the customer's vault).

## The model matrix is LIVE in the database, and still behind the hold
Applied 23 Sep in this order — catalogue → per-seat policy → ceiling:
`the_catalogue_names_every_model_the_seats_run_and_the_hold_covers_all_of_them.sql`,
`every_seat_gets_the_model_its_own_work_needs.sql`, `a_ceiling_exists_before_the_door_is_opened.sql`.
Measured by their own probes: 14 active registry rows, 16 breaker rows, **all held until 2126-08-15**;
36 classes on `qwen/qwen3.8-max-0902`, 18 on `z-ai/glm-5.3-flash`, `speech_transcription` on gemini
because only the Gemini family hears, 17 `tier=none` rows untouched, 0 tier mismatches;
6 department ceilings totalling **AED 1,200/month** over 57 active policies, `quote_compare` resolving
to AED 980 via `dept_key=marketplace`. `identity_redaction_verify` deliberately runs
`anthropic/claude-opus-5.5` — find and verify on one model is one opinion asked twice. Nothing calls a
model yet: the hold is the founder's and he opens it. See [[the-model-ruling-23-sep]].

## End-of-session sweep, measured
`verify_deploy_parity --all`: **DEPLOY PARITY OK, 74 of 74** functions carry main's current code.
`canonical_routine_manifest`: **0 findings across all six counters**. GitHub Actions on main: no
failures (the only non-green runs were two IT post-deploy smokes still in flight from the last two
merges). Production, 90 minutes after the last deploy: 0 site errors, 0 queued, **0 `sending`** (so the
new claim releases correctly and nothing is stuck claimed), 0 failed, and `company_faq` at 638 of 638
embedded.

## Open when the session ended
## I mis-verified a finding, and the builder caught it — twice-checked is why
I told the founder a signed-in customer could call `sales_engineer action:'match'` on anybody's inquiry,
having "verified it in code myself". **It was wrong.** I read the `SERVICE_ACTIONS` gate at index.ts:271
and the match branch at :524 and never read the 200 lines between: **:482 is
`if (caller.kind === 'customer') return 403`**, above `match`. A customer never reaches it. I also
relayed the review's claim that #859 added a lever via `body.services` — that string does not exist in
the file at all (grep: 0). And there is exactly ONE runtime caller, `customer_api/index.ts:272`, sending
`{action:'match', inquiry_id, persist:false}` and nothing else; no caller passes criteria.
What WAS real, proved open on production before the change: every criterion read `body.x || inq.x`, so
anyone holding the `sales_engineer` credential, an internal credential or the founder's admin JWT could
name someone else's inquiry and overwrite its trades/emirate/value — and with `persist` defaulting true,
write the steered result into `inquiry_matches`. Real door, narrower blast radius than I claimed.
**The lesson: reading two lines 250 apart is not reading the path between them.** Source order IS the
access control in these handlers. And the fix is better for my brief being wrong — asked for an
ownership branch, the author found `inq.customer_id !== caller.customerId` **does not compile**
(`Property 'customerId' does not exist on type 'never'`), which is the compiler proving the cutoff
already covers it, and made the invariant a type instead: move `match` above the cutoff and the build
goes red. The reviewer reproduced that with `tsc --strict` rather than trusting the comment.
Merged as **#866**, deployed `sales_engineer` v119. See [[a-fixs-own-check-measures-the-case-the-fix-handles]].
- **THE LIVE DEFECT #859 FIXES, measured by me on production 23 Sep before any apply.** Reachable
  confirmed suppliers, trade level vs an inquiry naming that trade's active services: aluminium 3 → 3,
  **doors 3 → 0**, gypsum 1 → 1, **painting 1 → 0**. Two of the four trades that have any supplier at all
  reach NOBODY the moment an inquiry names a service — the revenue path silently returning an empty
  marketplace, which the customer sees as a request that matched no one rather than as an error. After
  the apply, expect doors 3 and painting 1.
- **THE PROBE TO RUN THE MOMENT #859's STEP 3 IS APPLIED.** Production has churned down to ONE confirmed
  supplier: 126512, trades `{gypsum, painting}`, holding all five active gypsum keys plus the free-text
  «الدهانات». So today no supplier exists that has named services in a trade AND is asked for a key of
  that trade it does not hold — meaning the gate's **exclusion arm cannot be measured** before the apply.
  After step 3, 126512 gains `painting.interior` and `painting.repainting`, leaving
  `painting.decorative`, `painting.exterior` and `painting.protective_coating` unheld. Then
  `fn_match_capability(array['painting'], p_services := those three)` **must return 0**. A non-zero is a
  rollback trigger: it means widening the gate to fix the multi-trade case also loosened the exclusion.
- **#859** (services decide who gets the inquiry) — came back **FIX-FIRST** with a P0: the painting fix
  was real but was a one-row patch of a class defect, and the **doors** trade falls 1 → **0** reachable
  suppliers because two confirmed suppliers store `"Doors"` as free text rather than a service key — and
  that word is the product's own intake vocabulary (`inquiry_intake/interview.test.ts:11`), so it returns
  on the next rehearsal. Its own guard stays red after both applies, so its stated merge gate could not be
  met. Also: the SP-F-06 control says "remove any that are wrong" over a list where nothing is on. Back
  with its author.

## Two product calls left open by #858, neither a lockout
`kyc`'s supplier-only UAE-mobile rule now also covers the WhatsApp "other number" field, so a supplier
whose WhatsApp sits on a foreign line cannot register it (customers keep `toE164` and the Dubai landline
fallback). And the supplier portal prints `1,200 د.إ` on /ar where the customer portal prints
`AED 1,200` — unifying is about seven customer files and was deliberately left out of scope, with the
claim withdrawn from the PR body rather than left standing.

## A merged PR whose guard was never on production — found by adding the missing MANIFEST line
#862 merged with `fn_identity_policy_is_a_live_seat_and_a_known_model` **NOT PRESENT** on production, so
the trigger meant to stop the 119 dead identity rows returning did not exist. It was invisible because
the file had no MANIFEST line, and a file with no line is invisible to the drift gate — which is the
whole reason the line is mandatory. Adding the line exposed it; applying the file cleared it (PROBE OK,
3 rows left, guard in force). The two `every_arabic_message_is_written_not_translated.sql` staleness
findings (`fn_support_knowledge_gap`, `fn_text_did_not_survive_reply`) cleared in the same pass.
`canonical_routine_manifest.mjs` now prints how to attribute a finding (#865): re-run the same check
against `origin/main` at the same moment, because the three production counters read the live database
and not the diff.

## What the founder decides next, in his order
1. Open OpenRouter — `llm_route_health.open_until` and `app_secrets.ceo_model_slot`.
2. Then step 4: a second full audit and feature test with the LLM on.
Also still his: instruction 776 (the supplier fee conflict), and the DNS records that the permission
classifier refuses ("DNS / Domain / Cert Changes") — he must add a permission rule or do those two
records himself.

## The lesson of the day
Every PR that was sent back had a defect **in the fix itself**, not in the diagnosis — a floor
arithmetically invertible at n=3, a leak fix that took both quote doors offline, a trade that would
have reached zero suppliers, a guard whose LIKE prefix dropped 5 of 130 answers, a check that reported
green because it piped to `tail`. The review before the merge is what caught all of them. See
[[code-extremely-well-built]]. And [[applying-an-old-file-resurrects-a-superseded-routine]]: applying
#848 restored a second overload of the IT-digest routine and rolled another back a version — my
mistake, reported as mine, fixed by re-applying the winners in MANIFEST order.
