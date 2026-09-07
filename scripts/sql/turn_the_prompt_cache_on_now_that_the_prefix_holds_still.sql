-- TURN THE PROMPT CACHE ON, NOW THAT THE PREFIX HOLDS STILL.
--
-- Order matters and this file is deliberately second. a_prefix_that_moved_four_times_in_forty_five
-- _minutes.sql made the cacheable block byte-stable by storing it; until that landed, flipping this
-- switch would have bought a cache WRITE at 1.25x on every call and read none of them back, which
-- is worse than leaving it off. The switch is the cheap half; the prefix was the work.
--
-- THE REFRESH CADENCE IS PART OF THE ARITHMETIC, NOT HOUSEKEEPING.
-- Measured on production, 7 days, agent_brain/agent_reasoning grouped by employee: 267 calls with a
-- prior call, 14 distinct employees, median gap 59.6 minutes, 34.5% inside 5 minutes and 72.7%
-- inside an hour. A prefix rebuilt hourly would change between an employee's consecutive turns
-- roughly as often as those turns happen, so the refresh runs every SIX hours: the block is then
-- constant across the whole window in which any cache could hit, and the drift that was the binding
-- constraint stops being one. What it costs is that identity, company genome, authority, KPIs,
-- goals and doctrine can be up to six hours old — none of which change hourly, and every live
-- figure an employee is told to quote from is in the volatile half of the same prompt, rebuilt on
-- every single turn.
--
-- WHICH TTL, AND WHY NOT THE OTHER ONE. ai_gateway sends no ttl field, taking the provider default
-- (5 minutes, 1.25x to write, 0.1x to read, break-even at 21.7% hits). The 1-hour tier costs 2x to
-- write and breaks even at 52.6%. Both clear their break-even on the numbers above — 34.5% against
-- 21.7%, and 72.7% against 52.6% — and on paper the 1-hour tier saves more. It is NOT taken in this
-- change: the default tier is the strictly safer of two profitable options (a 1.25x downside if the
-- hit rate falls, against 2x), and the 1-hour rate rests on a 59.6-minute median sitting right on
-- its own boundary, where a small shift in the hourly loop's timing flips the sign. Move it as its
-- own change, with its own before/after, once this one has a week of measured hit rate behind it.
--
-- THE EXPECTED SAVING, STATED BEFORE IT IS MEASURED SO THE MEASUREMENT CAN CONTRADICT IT.
-- The stable block is 19,500 of the ~48,000 prompt characters agent_brain sends, and agent_brain's
-- agent_reasoning path is 8.85M input tokens and AED 91.55 over 30 days. At the measured 34.5%
-- hit rate the block costs 1.25 - 1.15 x 0.345 = 0.853 of what it costs today, i.e. about 15% off
-- roughly AED 26 of cacheable input: of the order of AED 4 a month, plus the same proportion on the
-- other agent_reasoning callers as they adopt sys_stable.
--
-- THAT IS NOT THE BIGGEST SAVING AVAILABLE AND THIS FILE SHOULD NOT BE READ AS CLAIMING IT IS.
-- agent_reasoning routed to anthropic/claude-sonnet-5 is AED 148 of the AED 210 spent in 30 days.
-- Prompt caching trims the input side of one call site; the tier decides the price of all of them.
-- See docs/audits/AI_SPEND_2026_08_14.md for the call-site-by-call-site verdicts.

-- Every six hours, at :40 — before the hourly employee burst that lands around :50, so a turn never
-- races a half-written prefix. Registered on both projects in this same change: a refresh that is
-- deployed but never scheduled would let agent_context_head age past its 3-hour staleness bound and
-- silently fall back to live assembly, which is exactly the drift this pair of migrations removes.
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.

update decision_policy
   set value = 'true'::jsonb,
       description = 'Anthropic prompt caching on the stable half of the system prompt. Turned on '
                     '14 Aug 2026 once agent_context_head made that half byte-stable; before that '
                     'it drifted four times in forty-five minutes and every call paid a 1.25x '
                     'cache write for a read that never came. Set to false to switch it off '
                     'without a deploy.',
       updated_at = now()
 where key = 'prompt_cache_enabled';
