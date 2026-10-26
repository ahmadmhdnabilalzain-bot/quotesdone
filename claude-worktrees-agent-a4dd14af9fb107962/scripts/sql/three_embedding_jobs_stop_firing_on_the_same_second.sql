-- THREE EMBEDDING JOBS STOP FIRING ON THE SAME SECOND
--
-- kb_embed has errored about once an hour for weeks, and the disclosure in
-- a_failed_scheduled_run_has_a_reader.test.mjs has been bumped repeatedly rather than closed. Bumping
-- a counter buys an hour. This is the attempt at the cause.
--
-- MEASURED 7 September 2026:
--
--   jobid 108  * * * * *   kb_embed_backfill          the real work: 2,531,457 chunks unembedded
--   jobid 271  * * * * *   kb_embed_priority_kinds    a handful of rows left
--   jobid 315  * * * * *   kb_embed_ops_knowledge     ZERO unembedded rows. It posts to do nothing.
--   jobid 242  6 seconds   kb_embed_backfill_boost    ten posts a minute
--
-- All three minute jobs fire on the SAME second of the same minute, on top of a boost that is already
-- posting ten times a minute. That is four concurrent claims against a 2.5-million-row table in one
-- instant, and it is what crosses the 8-second PostgREST wall. The reads themselves are not slow: I
-- planned all three targets today and every one is an index scan, kb_chunks at a limit cost of 1.64.
-- Nothing here is a missing index; it is contention we create ourselves, every sixty seconds.
--
-- WHAT THIS CHANGES, AND WHY IT DOES NOT SLOW THE BACKFILL. The two near-empty jobs move off the
-- every-minute slot. They were spending a post each per minute to find nothing:
--
--   ops_knowledge     every minute -> every 15 minutes.  0 rows to embed; this is pure waste today and
--                                                        still catches anything newly written.
--   priority_kinds    every minute -> every 5 minutes.   A handful of rows; five minutes is ample.
--
-- The backfill and the boost are UNTOUCHED, so the rate at which the 2.5 M backlog actually shrinks is
-- unchanged. This removes two of the four simultaneous claims from 56 of every 60 minutes, without
-- removing any real work. That is the opposite of turning a check green by weakening it: the same
-- work happens, with less self-inflicted contention.
--
-- WHAT IT WILL NOT FIX. 15 of the last 72 hours' errors land at :49 past the hour, which is a separate
-- and still unexplained hourly event; the earlier disclosure admitted the same thing and said so. If
-- errors continue at :49 after this, that is the remaining cause and it is not this one.

do $reschedule$
declare
  v_ops   int;
  v_prio  int;
  v_moved text[] := '{}';
begin
  select jobid into v_ops  from cron.job where jobname = 'kb_embed_ops_knowledge';
  select jobid into v_prio from cron.job where jobname = 'kb_embed_priority_kinds';

  if v_ops is not null then
    perform cron.alter_job(job_id => v_ops, schedule => '*/15 * * * *');
    v_moved := array_append(v_moved, format('kb_embed_ops_knowledge (%s) -> */15 * * * *', v_ops));
  end if;

  if v_prio is not null then
    perform cron.alter_job(job_id => v_prio, schedule => '*/5 * * * *');
    v_moved := array_append(v_moved, format('kb_embed_priority_kinds (%s) -> */5 * * * *', v_prio));
  end if;

  if array_length(v_moved, 1) is null then
    raise notice 'Neither job was found by name; nothing rescheduled.';
  else
    raise notice 'Rescheduled: %', array_to_string(v_moved, '; ');
  end if;
end $reschedule$;

-- A reader for the next person, so this is checkable rather than remembered.
comment on extension pg_cron is
  'kb_embed_backfill and kb_embed_backfill_boost carry the 2.5M-chunk backfill and are deliberately '
  'left at full rate. kb_embed_ops_knowledge (*/15) and kb_embed_priority_kinds (*/5) were moved off '
  'the every-minute slot on 7 Sep 2026: all three fired on the same second and the two of them had '
  'almost nothing to do, so they were contributing contention rather than throughput.';
