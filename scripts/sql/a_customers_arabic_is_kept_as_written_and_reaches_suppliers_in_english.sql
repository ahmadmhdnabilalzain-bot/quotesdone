-- A CUSTOMER'S ARABIC IS KEPT AS WRITTEN AND REACHES SUPPLIERS IN ENGLISH (5 Oct 2026, sales_engineer; PR #1195,
-- founder_instruction 1026, ledger 993 "suppliers always English").
--
-- public.rfq_clarification.answer is what every matched supplier reads. An Arabic answer to a supplier's question,
-- or an Arabic note on a live request, is now kept in answer_as_written and the supplier copy is HELD
-- (english_held_at set, answer null) until the model route writes its English (surface
-- sales_engineer.supplier_english, replayed by resilience_ping when the founder's model hold allows;
-- supabase/functions/_shared/supplier_english.ts finishEnglish stores it and clears english_held_at).
--
-- The shape check allowed a note only with an answer; a held note has its text in answer_as_written instead.
-- No routine, no new table: no revoke or policy is owed.

alter table public.rfq_clarification
  add column if not exists answer_as_written text,
  add column if not exists english_held_at timestamptz;

comment on column public.rfq_clarification.answer_as_written is
  'The customer''s text exactly as written when it was not English; answer holds the English every supplier reads.';
comment on column public.rfq_clarification.english_held_at is
  'Set while the supplier copy waits for its English (surface sales_engineer.supplier_english); suppliers see nothing until it clears.';

alter table public.rfq_clarification drop constraint if exists rfq_clarification_shape_ck;
alter table public.rfq_clarification add constraint rfq_clarification_shape_ck check (
  (kind = 'question' and supplier_id is not null and question is not null)
  or (kind = 'note' and supplier_id is null and answered_at is not null
      and (answer is not null or (english_held_at is not null and answer_as_written is not null))));

alter table public.rfq_clarification drop constraint if exists rfq_clarification_held_keeps_its_text_ck;
alter table public.rfq_clarification add constraint rfq_clarification_held_keeps_its_text_ck check (
  english_held_at is null or answer_as_written is not null);

select case when (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'rfq_clarification'
                    and column_name in ('answer_as_written', 'english_held_at')) = 2
            then 'PROBE OK' else 'PROBE FAILED: the held-for-English columns are missing' end as verdict;
