-- A STATEMENT THE READER CANNOT READ IS THE IT ENGINEER'S DEFECT, NEVER THE FOUNDER'S QUESTION.
-- Assigned: accountant (15 Sep 2026). Companion to supabase/functions/_shared/bank_statement_intake.ts,
-- which the live webhook (resend_inbound) and the accountant's expense_sweep now both call.
--
-- The founder, 15 Sep 2026: "nothing is unclear for the statement. if the agent cant read it then fix it."
-- The reconcile-to-the-fils guard stays: a statement that does not add up is ingested with no lines and
-- recorded 'unreadable' (fn_accountant_bank_statement_ingest), and nothing is booked from a guess. What
-- changes is who is asked. fn_accountant_statement_reader_defects files every unreadable real statement
-- in the IT engineer's finding ledger (fn_it_duty_settle, duty 'bank_statement_reader') as a parser defect,
-- with the reader's own words — the failing row number and date, and the printed opening and closing
-- balances — as evidence. The IT loop hands it to the accountant, whose reader it is (an owner seat with no
-- it.finding row would fall back to the CEO), and no_founder_email keeps the CEO step from emailing him.
-- The same call closes the finding once the same source_ref is ingested with lines.
--
-- MEASURED on the real August 2026 statement (15 Sep 2026, read locally, never copied into the repo): it
-- reads and reconciles to the fils, 6 lines. The monthly charge is AED 199 "Monthly Maintenance Fee" plus
-- AED 9.95 "Value Added Tax - Output", and gl_settings.bank_charge_pattern ('charge|fee|maint|commission|
-- vat on') does not match the VAT line, so fn_accountant_book_bank_charges would leave it unbooked. The
-- company is not VAT registered (no recoverable input VAT), so the bank's VAT is part of the charge: the
-- pattern gains 'value added tax' and the VAT books with the fee to 6300 against 1000.
--
--   node scripts/apply_sql.mjs scripts/sql/a_statement_the_reader_cannot_read_is_the_it_engineers_defect.sql --apply --ddl

insert into public.founder_instruction (said_at, instruction, subject, status, evidence, note)
select '2026-09-15T00:00:00Z', 'nothing is unclear for the statement. if the agent cant read it then fix it.',
       'an unreadable bank statement is a parser defect', 'done',
       'fn_accountant_statement_reader_defects files it with the IT engineer (duty bank_statement_reader), no_founder_email; scripts/sql/a_statement_the_reader_cannot_read_is_the_it_engineers_defect.sql',
       'The reconcile-to-the-fils guard stays; the finding goes to the IT engineer, never to the founder.'
 where not exists (select 1 from public.founder_instruction
                    where instruction = 'nothing is unclear for the statement. if the agent cant read it then fix it.');

-- Anchored to Mashreq's own fee-VAT row text ("Value Added Tax - Output"), not the bare phrase: an outgoing
-- wire whose memo says "incl. value added tax" is a payment, not a bank charge (review of #676).
update public.gl_settings set txt_value = 'charge|fee|maint|commission|vat on|value added tax\s*-\s*output'
 where key = 'bank_charge_pattern'
   and txt_value in ('charge|fee|maint|commission|vat on', 'charge|fee|maint|commission|vat on|value added tax');

-- PROBE (no rows written; a failure rolls this whole file back, a pass is a notice).
do $probe$
declare p text := (select txt_value from public.gl_settings where key = 'bank_charge_pattern');
begin
  if not ('Value Added Tax - Output 000000000000 099REFEAED 00000' ~* p) then
    raise exception 'CHK<<bank_charge_pattern does not match the real fee-VAT row>>'; end if;
  if not ('Value Added Tax-Output' ~* p and 'VALUE ADDED TAX  -  OUTPUT' ~* p) then
    raise exception 'CHK<<bank_charge_pattern is not whitespace-tolerant around the hyphen>>'; end if;
  if 'payment incl. value added tax' ~* p then
    raise exception 'CHK<<bank_charge_pattern matches a debit memo that merely mentions VAT>>'; end if;
  raise notice 'bank_charge_pattern probe passed: the fee-VAT row matches, a VAT-mentioning payment memo does not';
end $probe$;

create or replace function public.fn_accountant_statement_reader_defects()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_items jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'item', i.source_ref, 'owner_seat', 'accountant', 'subject', 'bank_statement',
           'title', 'The statement reader could not read a real ' || i.account || ' statement'
                    || coalesce(' for ' || to_char(i.statement_month, 'Mon YYYY'), '')
                    || ': a parser defect to fix, not a question for the founder',
           'blast', 'agent_facing', 'affected', 1, 'demo', false,
           'evidence', jsonb_build_object('source_ref', i.source_ref, 'doc_path', i.doc_path, 'reader_said', i.note,
             'no_founder_email', true,
             'remedy', 'fix supabase/functions/_shared/bank_statement_parse.ts against this document, then run the accountant expense_sweep with email_id so the same source_ref is ingested with lines'))
           order by i.source_ref), '[]'::jsonb)
    into v_items
    from public.bank_statement_intake i
   where i.state = 'unreadable' and i.account <> 'zz_demo';
  return public.fn_it_duty_settle('bank_statement_reader', v_items);
end $fn$;
revoke execute on function public.fn_accountant_statement_reader_defects() from public, anon, authenticated;
