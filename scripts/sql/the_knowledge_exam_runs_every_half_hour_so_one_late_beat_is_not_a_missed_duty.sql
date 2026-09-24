-- THE KNOWLEDGE EXAM RUNS EVERY HALF HOUR, SO ONE LATE BEAT IS NOT A MISSED DUTY (24 Sep 2026, it_engineer).
-- Measured 17:40Z: it_engineer.knowledge_recall (every 15 min since #948) last ran 16:45. The seat-duty tick shares
-- the resilience plan's budget, so the step is sometimes deferred one beat, and a 15-minute duty then misses its
-- window and reads as "not being done" (seen on the healthy-day replay of #933). At 30 minutes a single deferred beat
-- stays inside the window. A day's 2,354 questions at 150 a slice finish in about 8 hours, before 08:00 Dubai.
update public.seat_duty set every = interval '30 minutes' where duty = 'it_engineer.knowledge_recall';
select case when (select every from public.seat_duty where duty = 'it_engineer.knowledge_recall') = interval '30 minutes'
  then 'PROBE OK' else 'PROBE FAILED' end as verdict;
