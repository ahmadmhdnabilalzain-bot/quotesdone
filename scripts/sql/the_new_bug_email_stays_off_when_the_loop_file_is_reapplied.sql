-- THE NEW-BUG EMAIL STAYS OFF WHEN THE LOOP FILE IS REAPPLIED (it_engineer, 27 Oct 2026).
-- Seat: it_engineer. Founder instruction 642 (22 Sep 2026): no per-issue IT email; a new bug nobody could fix reaches
-- him only in the daily IT digest. the_founder_hears_from_it_once_a_day.sql set founder_mail_policy.it_new_bug false.
--
-- MEASURED 27 Oct 2026 (production, founder_mail_policy_history id 313): at 00:00:35 UTC it_new_bug went back to
-- allowed_to_email = true, changed_by postgres, with the 14 Sep reason. That is the moment #1587 was applied: its
-- apply re-ran the whole of the_it_engineer_closes_every_loop_it_opens.sql (MANIFEST 1403), whose section 12 upserts
-- ('it_new_bug', true) ... on conflict do update - the policy instruction 642 superseded. Caught by
-- the_founder_hears_from_it_once_a_day.test.mjs ("the IT kinds that reach the founder at once ... + it_new_bug").
-- 0 it_new_bug notifications were written between 00:00:35 and the measurement (to_jsonb(notifications) scan).
--
-- This file restores instruction 642's row, word for word as that file wrote it. The loop file's section 12 is changed
-- in the same PR to `on conflict (kind) do nothing`, so a future re-apply registers the kind but never re-opens it.
-- Prevented by: scripts/checks/the_founder_hears_from_it_once_a_day.test.mjs (production list + the new static case).
update public.founder_mail_policy
   set allowed_to_email = false, updated_at = now(),
       reason = 'Superseded by founder instruction 642 (22 Sep 2026): no per-issue IT email. A new bug nobody could fix reaches him in the daily IT digest (kind it_daily_digest) once it has been open 24 hours; until then it stays with the seats and the CEO.'
 where kind = 'it_new_bug' and allowed_to_email;
