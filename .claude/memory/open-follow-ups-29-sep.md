---
name: open-follow-ups-29-sep
description: "Follow-up PRs promised on 29 Sep that must not be lost across compaction: article approval email carries the full article, held-specs email names portal fields, export-list reconciliation"
metadata:
  node_type: memory
  type: project
  originSessionId: 8c4972a3-8a16-4cb0-a308-31a4f45e00bb
  modified: 2026-10-04T20:38:55.828Z
---

Follow-ups promised on 29 Sep 2026. Raise each one once its prerequisite merges.

1. SUPERSEDED by ruling 1058: founder no longer approves articles (see [[blogs-ceo-reviews-founder-only-notified]]); the FYI must still carry the article or a link.
2. **customer_support:** once #1112 and #1116 are both merged, the held-for-specs email must mention the new portal spec fields.
3. **Export list:** after #1106, #1108 and #1110 are applied, read back `fn_table_export_list` live. It must hold every table: `stalled_inquiry_rescue` from #1105 (#1106 is dropping its duplicate `inquiry_rescue`), plus the #1108 and #1110 tables and `marketing_plan_doc`.
4. **#1105 follow-up:** add `supplier_availability` and `stalled_inquiry_rescue` to the export list, if #1105 did not already.
5. **Guard follow-up after #1111:** multi-alias and copyPages.
6. Blog Arabic question — moot now that blogs are market topics for everyone, not supplier-targeted; bilingual blog stands.
7. **Schema mirror:** DONE. #1123 split it into `supabase/schema/full_schema/` (11 parts, read with `readSchemaMirror()`). Still to do: the prose in `.claude/skills/quotesdone-apply-discipline/SKILL.md` names the old `full_schema.sql` path. Fold that one-line doc fix into the next it_engineer PR.

8. **it_engineer, after #1038:** refuse to rotate when `twilio_api_key_sid` reads `''`, and never mint a key with old_ref null. The same PR carries the prose fix in the apply-discipline skill (item 7).
9. **sales_engineer:** the `duties_act` supply-gap fixture reads stale live data. It should seed its own ZZ DEMO gap (same class as #1101).
10. **it_engineer:** the new check `every_table_is_exported_or_explicitly_excluded` is being built, because #1105's tables slipped past the export list. `supplier_availability` is added to the list in #1110. After #1110, read the live list back.

11. **Step-1 audit:** #1125 found 179 tables that have a live writer but were never in the daily export, e.g. `sanctions_ban`, `post_reveal_dispute`, `accountant_founder_close_pack`, and `ceo_*` / `seat_*`. Export them, or exclude each one with a reason, and shrink the backlog ceiling.
12. **Step-1 audit:** 70 supply gaps are sitting in `deciding`. Check whether the model hold alone is what keeps them there.

13. **Step-1 audit:** the check `a_seat_is_never_reviewed_by_a_model_of_its_own_family` already fails before #1126, with "a pair with no ceiling row is held". Also: once the hold lifts, read `ai_cost_log` for Gemini/DeepSeek answers truncated by small max_tokens ceilings (e.g. `health_ping` at 32).

14. **Step-1 audit:** `fn_table_export_list` is rewritten whole by every PR that adds a table: five collided in a single day. Turn it into a registry table that each PR inserts rows into.

15. **Step-1 audit:** the Twilio rotate duty has no real pause switch; its only gate is the claim reading `agent_runs`. Give every duty a proper pause, and never fake an `agent_runs` row to hold a duty.

16. **Step-1 audit:** the finding `duty:latency_slo:kyc:error_budget` has been open since 29 Sep 00:44. kyc's 30-day availability is 97.24% against a 99.9% target, with 9 of 391 runs bad in 24 h. Find the root cause.
17. **Twilio rotation on 29 Sep 13:01 UTC:** the new API key is a Standard key, which cannot read `/Accounts/{AC}.json`. #1130 moves the probe to `Balance.json`. Any other code that reads Account resources with the API key breaks the same way, so grep for it.

18. **Step-1 audit, from #1128:**
    - Refund approval via `fn_ceo_refund_review` never calls `fn_refund_decide(true)`, so the second-seat check is skipped; the z05 guard still holds. This is money, so fix it first.
    - `fn_marketing_month_plan_tick` sends the plan to the founder with no CEO round.
    - The marketing-plan stall watch never fires on the argument path.
    - The check that a seat is never reviewed by its own family fails on `no_ceil`.

19. **Step-1 audit:** in #1128, a direct service_role UPDATE on `ceo_experiment`, `ceo_improvement` or `seat_deliberation_turn` skips the reasons check. Move the check into a trigger.

20. **Step-1 audit: incident 508.** An unauthenticated call hits `supplier_portal` every hour from inside our own region, and we don't know where it comes from. Read its user agent in the edge logs (Supabase MCP `get_logs`), find the caller, and fix it or give it credentials.

21. **Follow-ups from 30 Sep reviews:**
    - `duty_pause` (#1139) has no expiry. Raise a finding when a pause is older than about 7 days, especially on money or security duties. Its probe only regex-matches the routine body; it should test a real skipped tick.
    - The #1137 export probe accepts a floor of ">=174". Tighten it to the seeded count, 312.
    - The #1140 matrix probe (section 4) checks primary and fallback models but not tier or max_tokens.
22. **Deferred settings** (ledger 1064–1067): GitHub branch protection, Dependabot alerts, the Vercel OTP rate limit, and Supabase password sign-in off. The founder said "later".

23. **Before the supplier campaign:** a supplier's `accept_terms` still waits 3–12 s for the signed-terms PDF, because the portal's save requires the PDF to exist. Make the save accept a pending PDF so suppliers aren't kept waiting at sign-up. Found in #1139.
24. The empty 913 MB `dr_restore` table is safe to drop (0 rows, no references). Drop it via PR and remove its registry entry.

25. **The release train crashes every tick on a PR it cannot merge,** for example a workflow-file change when its app token lacks the `workflows` permission, and releases nothing else (#1141, 30 Sep). It should skip the PR, label it `release-failed`, raise a finding and move on. Workflow-file PRs are merged by hand with the gh CLI token. Granting the app the `workflows` permission is a founder settings decision.

26. **The release train's */10 schedule stopped firing** after 21:35Z on 30 Sep and had to be dispatched by hand. GitHub delays and drops scheduled workflows. Add a watchdog: resilience_ping, or a cron job, dispatches the train when labelled PRs are waiting and no run has happened for 20 minutes.

27. **Release train gaps found on 30 Sep:**
    - (a) After a hand apply, the drift gate blocks the very bookkeeping PR that records it. Exempt a PR whose diff covers exactly the drift.
    - (b) A PR title with no seat makes the post-merge apply fail. Check the seat before the merge.
    - (c) Close the drift findings the train opened during the window, once #1146 lands.

28. **Next week:** a daily it_engineer duty that syncs `model_registry` from the OpenRouter catalogue.
    - A small drift in price or context is auto-recorded with a note.
    - A price jump over 20%, or any change to a model in the founder's matrix, raises a finding first.
    - The CI check then asserts the sync is fresh, instead of failing on the first provider change. That failure blocked PRs on 28 and 30 Sep, both times on glm-5.3-flash.

29. **The CEO weekly review under-acts:** its probe, now runnable, returns "week 1 missed 5 targets but opened 2 improvements". Every missed target should get an action (owner: ceo). Found 30 Sep in #1154.
30. **Awaiting founder:** the card fee (#919 removed it on 24 Sep, citing Cabinet Res. 66/2023 Art. 5(3), against ruling 88; options: 3% only, 3% + fee, or about 3.1% flat), key rotation (ruling 23 vs the rebuilt rotation), the 24 /services pages, and enterprise accounts.

31. **Accountant:** bank lines with Mashreq structured reference codes (099REFEAED = fee/VAT, 099CIDBAED = interest) should be classified from the code deterministically, not held for the model. The September statement, lines 2265–2269, is held today with a gap of 523.71 between the books and the bank.
32. **Accountant:** the September card purchases of USD 10.80 (26/09) and USD 72.36 (29/09) have no receipts. The founder was asked to forward them to the expenses mailbox.
33. **Spec helper #1186:** Arabic labels on the answer buttons for customers (stored value stays English), and "not sure" opens a handoff to the sales engineer.

Related: [[upgrade-backlog-after-queue-zero]].
