-- fn_resilience_watch — the unmatched-inquiry alert was wrong in both directions.
--
-- NOT A FULL FUNCTION BODY ON PURPOSE. The deployed fn_resilience_watch embeds its own project's
-- edge-function URLs, and the two projects' definitions therefore differ. qd_guard refuses to apply
-- a body carrying the production ref to a branch — correctly; that is the 3–4 Aug incident where
-- staging code called production for eighteen hours. So each project's OWN deployed definition was
-- read back and this ONE statement replaced inside it, leaving the other 7,784 characters
-- byte-identical. This file is the statement and the reasoning, not the whole routine.
--
-- WHAT WAS THERE:
--
--   select count(*) into v_match_stuck from inquiries i
--     where i.created_at between now()-interval '24 hours' and now()-interval '6 hours'
--       and i.status not in ('completed','accepted','closed','cancelled','draft')
--       and not exists(select 1 from inquiry_matches m where m.inquiry_id=i.id);
--
-- (a) IT WAS A BAND, SO THE WATCHDOG FORGOT. `between 24h and 6h` means an inquiry older than one
--     day leaves the alert whether or not it was ever matched. Measured on production: six rows
--     created 2026-08-08 10:40 alarmed every ten minutes — 65 error rows in agent_runs — and went
--     silent at exactly 2026-08-09 10:40. Nothing had been matched. They had crossed the 24-hour
--     edge. A monitor that stops reporting an unresolved condition is worse than one that never
--     looked, because the silence reads as health.
--
-- (b) IT COUNTED FIXTURES. All 7 rows in inquiries carry brief_source='qd_demo_fixture' and are
--     seeded "ZZ DEMO" briefs. Every one of those 65 alerts was about demo data. An alert that
--     cries wolf every ten minutes for a day is an alert nobody will read on the day it is right.
--
-- The two corrections pull in opposite directions and that is the point: dropping the ceiling makes
-- it STRICTER on real traffic, excluding fixtures makes it QUIETER on data that was never real.
--
-- IT READS 0 ON PRODUCTION TODAY, AND THAT IS NOT A PASS. There are zero real inquiries — all 7 are
-- fixtures — so there is nothing for the matcher to have got wrong yet. Live matching has never
-- been exercised. Do not read this 0 as evidence that matching works; match_eval's 100%/100% is a
-- synthetic benchmark against its own seeded suppliers, not live traffic.

  select count(*) into v_match_stuck from inquiries i
    where i.created_at < now()-interval '6 hours'
      and coalesce(i.brief_source,'') <> 'qd_demo_fixture'
      and i.status not in ('completed','accepted','closed','cancelled','draft')
      and not exists(select 1 from inquiry_matches m where m.inquiry_id=i.id);

-- VERIFIED ON STAGING before promotion, both directions, with three backdated rows:
--   fixture at 7h   -> not counted
--   real at 7h      -> counted
--   real at 40h     -> counted   (the old band missed this one entirely)
-- New logic went 1 -> 3 (+2 real). The old band, restricted to the probes, counted 2: the FIXTURE
-- and the 7h real one, and missed the 40h real one. Fixtures removed afterwards.
