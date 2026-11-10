-- THE OFF-MAIN REVISION OF 19 OCTOBER IS ACCEPTED ONCE ITS LAST ROUTINE IS VERIFIED.
--
-- Seat: ceo (founder ruling 1560 of 10 Nov 2026: an unsigned routine change is accepted only where every routine it
-- touched is identical to its canonical reviewed file). it_engineer session, 10 Nov 2026.
--
-- MEASURED ON PRODUCTION, 10 Nov 2026 ~10:40 UTC:
--   the_founders_rulings_of_10_november_settle_four_open_problems.sql (applied with #1878, merge bc4a3aee7) accepted four
--   of its five unsigned transactions and correctly refused txid 15743633 (revision 5ec4ba8, 19 Oct 12:47Z): it had pinned
--   fn_it_engineer_knowledge_recall_exam() at md5 b470cf9f..., and the same merge re-applied that routine from the reviewed
--   an_any_mode file, so the pin no longer matched. Finding duty:unsigned_revision:rev:5ec4ba8 and handoff 269841 stay open.
--   Per routine 5ec4ba8 created or dropped (routine_change_log, pg_get_functiondef md5 now):
--     fn_seat_exam_grade(text)                         c0b54ea5d4914c623a9d4aefec09878b  = a_seats_own_pack_fills_half_of_every_retrieval.sql
--                                                      (prosrc md5 b0f95162... equals that file's body byte for byte)
--     fn_it_engineer_knowledge_recall_exam()           20fe6258b2e4c563ca95a489fad80a56  re-applied 10 Nov 09:34Z from main (bc4a3aee7)
--     fn_reason_retrieve(... 7 args)                   76559369723563d94b4bbd947b59faa3  unchanged since the rulings file verified it
--     fn_reason_retrieve_ml(... 9 args)                3b05d39dace67fbb6df9cbbac1afc589  unchanged since the rulings file verified it
--     the two overloads it dropped (6 and 8 args)      absent
--   Nothing live is what 5ec4ba8 alone wrote, so the revision is settled. fn_seat_exam_grade was never re-applied from a
--   reviewed revision, so fn_it_change_watch's SETTLED rule cannot see it without the acceptance.
--
-- WHAT THIS DOES. The rulings file's own rule, for this one transaction: every routine it logged is listed below with the
-- md5 measured above, each is re-checked at apply, and only if all hold is it accepted with fn_it_change_accept(txid,
-- 'ceo', why). If anything changed since this was written, nothing is accepted and the verdict says what.
-- fn_it_change_watch then stops raising the revision and fn_it_duty_settle closes the finding on its next tick. The
-- verdict stays 'not_on_main': that is what GitHub answered.
--
-- Prevented by: the verdict row at the end of this file (PROBE OK / PROBE FAILED).

do $accept$
declare
  v_ok boolean := true; v_why text; o record; r jsonb;
begin
  if exists (select 1 from public.it_change_acceptance where txid = 15743633) then return; end if;
  for o in select * from (values
    ('public.fn_seat_exam_grade(pg_catalog.text)', 'c0b54ea5d4914c623a9d4aefec09878b'),
    ('public.fn_it_engineer_knowledge_recall_exam()', '20fe6258b2e4c563ca95a489fad80a56'),
    ('public.fn_reason_retrieve(pg_catalog.text,public.vector,integer,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text)', '76559369723563d94b4bbd947b59faa3'),
    ('public.fn_reason_retrieve_ml(pg_catalog.text,public.vector,public.vector,integer,integer,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text)', '3b05d39dace67fbb6df9cbbac1afc589'),
    ('public.fn_reason_retrieve(pg_catalog.text,public.vector,integer,pg_catalog.text,pg_catalog.text,pg_catalog.text)', null),
    ('public.fn_reason_retrieve_ml(pg_catalog.text,public.vector,public.vector,integer,integer,pg_catalog.text,pg_catalog.text,pg_catalog.text)', null)
  ) t(obj, want) loop
    if o.want is null and to_regprocedure(o.obj) is not null then
      v_ok := false; v_why := coalesce(v_why || '; ', '') || o.obj || ' was dropped and exists again';
    elsif o.want is not null and md5(coalesce(pg_get_functiondef(to_regprocedure(o.obj)), '')) is distinct from o.want then
      v_ok := false; v_why := coalesce(v_why || '; ', '') || o.obj || ' changed since 10 Nov';
    end if;
  end loop;
  if exists (select 1 from public.routine_change_log c where c.txid = 15743633 and c.object_identity not in (
      'public.fn_seat_exam_grade(pg_catalog.text)', 'public.fn_it_engineer_knowledge_recall_exam()',
      'public.fn_reason_retrieve(pg_catalog.text,public.vector,integer,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text)',
      'public.fn_reason_retrieve_ml(pg_catalog.text,public.vector,public.vector,integer,integer,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text)',
      'public.fn_reason_retrieve(pg_catalog.text,public.vector,integer,pg_catalog.text,pg_catalog.text,pg_catalog.text)',
      'public.fn_reason_retrieve_ml(pg_catalog.text,public.vector,public.vector,integer,integer,pg_catalog.text,pg_catalog.text,pg_catalog.text)')) then
    v_ok := false; v_why := coalesce(v_why || '; ', '') || 'the transaction logged a routine this file did not verify';
  end if;
  if not exists (select 1 from public.routine_change_log c where c.txid = 15743633) then
    v_ok := false; v_why := coalesce(v_why || '; ', '') || 'routine_change_log no longer holds the transaction';
  end if;
  if not v_ok then
    raise notice 'txid 15743633 NOT ACCEPTED: %', v_why; return;
  end if;
  r := public.fn_it_change_accept(15743633, 'ceo',
    'Founder ruling 1560 (10 Nov 2026): applied 19 Oct 12:47Z by an it_engineer session from local revision 5ec4ba8, on no merged or open pull request. '
    || 'Verified 10 Nov 2026: fn_seat_exam_grade is identical to a_seats_own_pack_fills_half_of_every_retrieval.sql (prosrc md5 b0f95162 both sides), '
    || 'fn_it_engineer_knowledge_recall_exam was re-applied from main bc4a3aee7, fn_reason_retrieve and fn_reason_retrieve_ml are unchanged since the rulings '
    || 'file verified them against customers_and_suppliers_are_never_given_internal_knowledge.sql, and the two dropped overloads are absent; each md5 re-checked at apply.');
  raise notice 'txid 15743633 ACCEPTED: %', r;
end
$accept$;

-- VERDICT: read-only, never raises.
select case
  when exists (select 1 from public.it_change_acceptance where txid = 15743633)
    then 'PROBE OK: txid 15743633 (revision 5ec4ba8) accepted by the ceo after every routine it touched was re-verified'
  else 'PROBE FAILED: txid 15743633 not accepted - a routine it touched changed since 10 Nov (see the notice)'
end as verdict;
