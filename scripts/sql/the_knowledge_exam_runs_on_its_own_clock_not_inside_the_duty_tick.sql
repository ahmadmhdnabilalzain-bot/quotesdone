-- THE KNOWLEDGE EXAM RUNS ON ITS OWN CLOCK, NOT INSIDE THE DUTY TICK (it_engineer, 24 Sep 2026).
--
-- Measured 24 Sep 2026 after #936 applied every_seats_knowledge_is_examined_daily_by_retrieval_without_a_model.sql:
-- fn_it_engineer_knowledge_recall_exam puts 2,354 questions to the retriever and takes ~36 s. resilience_ping calls
-- fn_seat_duties_tick over PostgREST, whose role carries statement_timeout=8s, so from 10:30Z every tick was cancelled
-- ("canceling statement due to statement timeout", finding duty:heartbeat:seatDuties) and the cancel rolled back EVERY
-- duty in that tick: no seat duty ran from 10:15Z on.
--
-- The fix: the exam leaves the tick. Its seat_duty row is disabled (the tick skips disabled rows) and a daily pg_cron
-- job, which has no 8 s timeout, runs it and writes the same row's last_started_at / last_ok_at / last_error, so the
-- record of the duty stays where every other duty's is. The exam still raises its own findings.
-- Do NOT re-apply every_seats_knowledge_is_examined_daily_by_retrieval_without_a_model.sql after this file: its
-- probe expects the row enabled, and an enabled row puts the 36 s exam back into the 8 s tick.

update public.seat_duty
   set enabled = false,
       what = 'Daily, no model, on its own pg_cron job (knowledge_recall_exam_daily, 00:20 UTC) because it takes ~36 s and the duty tick runs under an 8 s timeout: every verified pack''s eval questions put to each seat''s own retriever; recall@5 per seat recorded, a fall or a score under 0.35 is a finding.'
 where duty = 'it_engineer.knowledge_recall';

select cron.unschedule(jobid) from cron.job where jobname = 'knowledge_recall_exam_daily';
select cron.schedule('knowledge_recall_exam_daily', '20 0 * * *', $cron$
do $do$
declare v jsonb;
begin
  update public.seat_duty set last_started_at = now() where duty = 'it_engineer.knowledge_recall';
  begin
    v := public.fn_it_engineer_knowledge_recall_exam();
    update public.seat_duty set last_ok_at = now(), last_result = v, last_error = null, failures = 0
     where duty = 'it_engineer.knowledge_recall';
  exception when others then
    update public.seat_duty set last_error = left(sqlerrm, 1000), failures = failures + 1
     where duty = 'it_engineer.knowledge_recall';
  end;
end $do$;
$cron$);

select case when not (select enabled from public.seat_duty where duty = 'it_engineer.knowledge_recall')
             and exists (select 1 from cron.job where jobname = 'knowledge_recall_exam_daily' and active)
            then 'PROBE OK' else 'PROBE FAILED' end as verdict;
