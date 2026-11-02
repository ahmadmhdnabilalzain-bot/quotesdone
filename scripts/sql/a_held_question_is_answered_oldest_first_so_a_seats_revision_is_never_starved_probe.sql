-- PROBE for a_held_question_is_answered_oldest_first_so_a_seats_revision_is_never_starved.sql. Pure: no DDL, no write,
-- no lock. It reads the rows fn_reason_held_due would choose from (the same `lead` and 10-minute retry gate) and orders
-- them both ways, so it can run before or after the apply. Verdict first, and every path ends in raise exception.
-- Verdict REPRODUCED when the live order (untried first, newest first) would claim 2 rows (REPLAY_CLAIM) while older due
-- rows wait, which is the defect; NOT NOW when it passes over no row filed before one it takes. Either way it prints both claims.
do $probe$
declare v_new bigint[]; v_old bigint[]; n_due int; n_starved int;
begin
  with lead as (
    select distinct on (surface, coalesce(qhash, id::text)) id, attempts, last_attempt_at, created_at
      from public.reasoning_held_question
     where status = 'held' and attempts < 3
       -- fn_reask_surfaces() spelled out: the read-only role may not execute it (42501)
       and not (surface = any(array['wa_inbound.unwritten_reply', 'supplier_api.quote_review_unwritten',
                                    'sales_engineer.portal_unwritten', 'inquiry_intake.unwritten_reply']))
     order by surface, coalesce(qhash, id::text), attempts desc, id
  ), due as (
    select h.id, h.created_at, h.last_attempt_at from public.reasoning_held_question h
     where h.id in (select id from lead where last_attempt_at is null or last_attempt_at < now() - interval '10 minutes')
  )
  select (select array_agg(id order by created_at, id) from (select id, created_at from due order by created_at, id limit 2) a),
         (select array_agg(id) from (select id from due order by last_attempt_at nulls first, created_at desc limit 2) b),
         (select count(*) from due),
         -- due rows the live claim passes over although they were filed before a row it takes
         (select count(*) from due d where d.created_at < (select max(created_at) from
            (select created_at from due order by last_attempt_at nulls first, created_at desc limit 2) e)
            and d.id not in (select id from due order by last_attempt_at nulls first, created_at desc limit 2))
    into v_new, v_old, n_due, n_starved;
  if n_due = 0 then
    raise exception 'CHK<<NOT NOW: no held row is due; nothing to order>>';
  elsif n_starved > 0 then
    raise exception 'CHK<<REPRODUCED: live order claims % while % older due rows wait | oldest-first claims % | due %>>',
      v_old, n_starved, v_new, n_due;
  else
    raise exception 'CHK<<NOT NOW: the live order passes over no older row (% vs %) | due %>>', v_old, v_new, n_due;
  end if;
end $probe$;
