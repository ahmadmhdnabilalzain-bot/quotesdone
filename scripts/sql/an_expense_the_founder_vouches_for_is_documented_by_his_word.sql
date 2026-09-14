-- AN EXPENSE THE FOUNDER VOUCHES FOR IS DOCUMENTED BY HIS WORD, NOT A MISSING RECEIPT.
--
-- Assigned: accountant. Founder, 14 Sep 2026, on the DET e-Trader licence paid through a PRO agent:
-- "its ok no need for it. just note down the number of 1200 AED".
--
-- WHAT WAS MEASURED (14 Sep 2026, production, after #659 was applied):
--   * public.expense_entries id 122 — DET e-Trader licence 1633275, AED 1,200, source 'founder_reported' —
--     has no doc_path and never will: the PRO agent was paid in cash and there is no receipt.
--   * The expense duty (every_expense_has_its_receipt_and_every_subscription_its_renewal.sql) counted every
--     expense with no doc_path under ONE key, acct:expenses:no_document. Row 122 kept that finding open for
--     ever, asking for a receipt that cannot exist, and it also kept the ZZ DEMO loop test red after the
--     fixture's own fix: a rehearsal was being judged by a real row.
--
-- WHAT CHANGES:
--   * expense_entries.doc_kind gains 'founder_statement'. A CHECK allows it ONLY on source 'founder_reported'
--     with doc_note carrying why no receipt exists, so no other source can claim it.
--   * Row 122 carries it, with his words in doc_note (idempotent; the founder approved this one update).
--   * The duty itself changes in its own file: a founder_statement expense is documented by his word, listed
--     in the finding's evidence as documented_by_founder_statement so an auditor sees why, and ZZ DEMO
--     expenses are their own finding (no_document:zz_demo), so a fixture judges only its own rows.
--
-- WHAT IT DOES NOT DO. It widens nothing beyond 'founder_reported', and does not change v_expense_documents:
-- the record still has no file, and the view still reports that.
--
--   node scripts/apply_sql.mjs scripts/sql/an_expense_the_founder_vouches_for_is_documented_by_his_word.sql --apply --ddl

insert into public.founder_instruction (said_at, instruction, subject, status, evidence, note)
select '2026-09-14T00:00:00Z', 'its ok no need for it. just note down the number of 1200 AED',
       'the DET e-Trader licence needs no receipt', 'done',
       'expense_entries id 122 carries doc_kind founder_statement with his words in doc_note; fn_accountant_expense_duty lists it as documented_by_founder_statement instead of a missing receipt (scripts/sql/an_expense_the_founder_vouches_for_is_documented_by_his_word.sql).',
       'Paid to DET through a PRO agent in cash; there is no receipt and there never will be.'
 where not exists (select 1 from public.founder_instruction f where f.instruction = 'its ok no need for it. just note down the number of 1200 AED');

alter table public.expense_entries drop constraint if exists expense_entries_doc_kind_ck;
alter table public.expense_entries add constraint expense_entries_doc_kind_ck
  check (doc_kind is null or doc_kind in ('vendor_document', 'email_print', 'founder_statement'));
alter table public.expense_entries drop constraint if exists expense_entries_founder_statement_ck;
alter table public.expense_entries add constraint expense_entries_founder_statement_ck
  check (doc_kind is distinct from 'founder_statement' or (source = 'founder_reported' and coalesce(btrim(doc_note), '') <> ''));

comment on column public.expense_entries.doc_kind is
  'What KIND of evidence backs the record: ''vendor_document'' = the vendor''s own invoice/receipt file taken off the source email; '
  '''email_print'' = a PDF print of the email itself, because the email carried no vendor file; ''founder_statement'' = no file exists '
  'and the founder vouched for the amount (source founder_reported only, his words in doc_note). null = no document. Never inferred from the filename.';

update public.expense_entries
   set doc_kind = 'founder_statement',
       doc_note = 'Founder, 14 Sep 2026, verbatim: "its ok no need for it. just note down the number of 1200 AED". Paid to DET through a PRO agent in cash; no receipt exists or will exist.'
 where id = 122 and source = 'founder_reported' and doc_kind is distinct from 'founder_statement';

-- Proof, cleaning up nothing because it writes nothing: row 122 carries the statement.
do $probe$
begin
  if not exists (select 1 from public.expense_entries where id = 122 and doc_kind = 'founder_statement' and doc_note like 'Founder, 14 Sep 2026%') then
    raise exception 'expense_entries 122 does not carry the founder''s statement';
  end if;
  raise notice 'expense 122 is documented by the founder''s statement';
end
$probe$;
