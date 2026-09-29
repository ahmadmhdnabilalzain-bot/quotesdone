# Postmortem: `duty:heartbeat` — resilience_ping steps failing inside the 15-minute tick

Seat: it_engineer. Blameless. Written 28 Sep 2026 from production reads (read-only) and `git log`.

| | |
|---|---|
| Class (issue-key family) | `duty:heartbeat:*` — 38 distinct step keys |
| Handoffs covered | **333** closed `it.finding` handoffs of severity high, no `it_incident` row (0 critical) |
| First / last | 15 Sep 2026 09:45Z / 28 Sep 2026 13:31Z (still recurring, see action 1) |
| Answering seat | ceo (every handoff) |

## Impact
Internal. A failed heartbeat step means one scheduled job inside `resilience_ping` did not complete that
tick; the job ran again on a later tick. No customer-facing surface is named in any of the 333 handoffs.
The founder received digest emails for part of this class (see `docs/it/IT_FAILURES_18_21_SEP_2026.md`, cause 1).

## Timeline (by step key, handoff count, first → last seen)
- `itdetect` 114 (15 Sep → 21 Sep): `canceling statement due to statement timeout`.
- `orphans` 32 (18 Sep → 28 Sep) and `orphans.wa_templates_watch` 30 (23 Sep → 28 Sep, **still open**): `HTTP 403`.
- `outbox` 22, `backup` 16, `whatsapp` 4: `Signal timed out.`
- `archive` 21, `specoffer` 11, `itlater` 7, `tableExport` 6, `accountantDuties`/`itduties`/`itscheduled`/`ladder` 5 each, and 17 smaller keys: `not run: the tick passed its 95s/110s deadline` or `abandoned after 10s: the tick was out of budget`.
- `backupVerify` 12, `backupPrune` 4, `itlater.usage` 2, `it` 2, `seatDuties` 1: statement timeout.
- `supportCampaignList`, `caseMemory`, `learningGroup` 1 each: `the schedule names a step this function does not have` (a schedule row deployed before its code).
- `marketingChannels` 2, `mlEmbed` 1: `HTTP 546` (edge-function CPU cap).

## Root cause
One signature, three mechanisms, all the same shape — **a step that does not fit the shared tick budget**:
1. **The detector was the slow step.** `fn_it_detect` scanned 7 days of `agent_runs` three times and ran two per-row
   predicates ~100,000 times; timed read-only at 10,999 ms against PostgREST's 8 s statement timeout
   (measured 21 Sep, `IT_FAILURES_18_21_SEP_2026.md` cause 1). Every later step in that tick then ran out of budget.
2. **Steps queue behind each other.** The tick ran steps in list order, so a slow early step starved the tail
   (`not run: the tick passed its deadline`).
3. **`wa_templates_watch` answers 403** to the orphans step. Measured on the open finding; the cause of the 403 was
   **not determined** in this postmortem (the function returns 403 when its internal-auth check fails —
   `supabase/functions/wa_templates_watch/index.ts` line 39 — but which caller key is wrong was not read).

## Detection
`it_engineer.heartbeat` duty (fn_it_duty_settle, `duty:heartbeat:<step>`). Worked as designed; every close and re-open
of the same step opens a new handoff (one per occurrence), which is why 38 keys account for 333 handoffs. A step
that failed earlier and was not due this tick is now held rather than re-raised (fix below).

## Fix (found in git)
- `1de84e3` (#767): `the_it_detector_reads_agent_runs_once_and_no_subject_can_flood_it.sql` — one bounded slice; rolled-back run 4,141 ms.
- `b0357f0` (#754): the tick runs what is stalest, not what is first in the list.
- `5afd873` (#810): `a_failed_heartbeat_step_stays_failing_until_it_runs_again.sql` — a carried step no longer closes and re-opens.
- `7ec6773` (#714), `e8e0990` (#742), `f85de16` (#912): heartbeat coverage and paging fixes.
- `1c0abad` (#948): the knowledge exam scored in slices so the duty tick fits its 8 s.
- `wa_templates_watch` 403: **no fix found in git**. `4b544bb` (#849) changed the watcher's gating, not its auth.

## Action items
1. **it_engineer** — diagnose `duty:heartbeat:orphans.wa_templates_watch` (HTTP 403, open since 28 Sep 13:31Z, 30 handoffs since 23 Sep): read which key `resilience_ping` sends and which the function checks.
2. **it_engineer** — a schedule row must not name a step before its code is deployed (`supportCampaignList`, `caseMemory`, `learningGroup`): deploy the function, then insert the schedule row, in that order.
3. **marketing / it_engineer** — `marketingChannels` and `mlEmbed` hit HTTP 546 (CPU cap); see memory "an edge function has a CPU cap a deadline does not bound".

## Handoff ids covered (agent_actions.id)
`duty:heartbeat` (333): 28707, 28743, 28919, 28920, 28942, 28957, 28958, 28959, 28960, 28961, 28962, 28970, 28971, 28976, 28977, 28978, 28979, 28980, 28981, 28982, 28983, 28984, 28985, 28986, 28987, 28988, 28989, 28990, 28991, 28992, 28994, 28995, 28996, 28997, 29004, 29005, 29008, 29095, 29096, 29105, 29106, 29107, 29113, 29114, 29115, 29116, 29120, 29123, 29124, 29125, 29126, 29127, 29128, 29129, 29130, 29131, 29132, 29133, 29135, 29136, 29137, 29138, 29233, 29234, 31052, 33308, 33309, 33310, 33311, 33315, 33316, 33317, 33318, 33319, 33320, 33321, 33322, 33323, 35257, 35258, 35259, 35260, 35261, 35262, 35263, 35264, 35282, 35283, 35284, 35363, 35764, 35765, 35766, 35767, 35768, 38241, 38246, 38247, 38248, 38249, 38250, 38251, 38252, 38320, 38449, 38665, 38842, 38848, 38850, 38853, 38854, 38859, 38866, 38868, 39022, 39025, 39027, 39029, 39031, 39034, 39043, 39052, 39053, 39054, 39057, 39058, 39059, 39060, 39061, 39062, 39063, 39065, 39067, 39068, 39069, 39070, 39071, 39072, 39073, 39074, 39075, 39076, 39078, 39079, 39080, 39081, 39082, 39106, 39165, 39178, 39180, 39182, 39183, 39184, 39185, 39186, 39190, 39193, 39195, 39196, 39197, 39198, 39203, 39204, 39205, 39206, 39208, 39210, 39211, 39212, 39213, 39214, 39219, 39224, 39225, 39226, 39227, 39228, 39229, 39230, 39231, 39232, 39233, 39235, 39237, 39238, 39239, 39240, 39241, 39242, 39243, 39244, 39245, 39246, 39247, 39248, 39249, 39250, 39274, 39320, 39324, 39325, 39326, 39327, 39328, 39329, 39330, 39332, 39333, 39334, 39335, 39345, 39346, 39351, 39353, 39354, 39355, 39358, 39361, 39362, 39363, 39619, 39781, 39881, 39938, 39941, 39943, 40018, 40019, 40020, 40021, 40223, 40609, 40715, 42598, 56007, 66646, 80956, 80990, 81022, 81043, 83585, 83586, 83587, 84462, 84525, 84526, 84592, 84699, 84790, 84830, 84840, 84853, 84930, 84969, 84990, 85059, 85357, 85422, 85635, 86185, 87230, 87231, 87232, 87233, 87234, 87235, 87248, 87357, 87383, 87394, 87427, 87428, 87573, 87687, 87724, 88018, 89188, 89731, 90715, 93014, 93179, 93446, 93447, 93512, 93513, 93520, 93531, 93626, 96030, 96718, 96781, 96963, 96964, 97320, 97458, 97459, 97487, 97521, 97581, 97582, 97583, 97591, 97592, 97683, 97752, 97753, 97783, 97784, 97802, 97872, 97915, 97923, 97979, 98027, 98028, 98029, 98030, 98031, 98032, 98067, 98068, 98069, 98070, 98071, 98072, 98073, 98074, 98184, 98250, 101559, 101560, 101627.
