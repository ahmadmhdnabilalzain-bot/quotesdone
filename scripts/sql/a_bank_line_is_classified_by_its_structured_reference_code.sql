-- A BANK LINE IS CLASSIFIED BY ITS STRUCTURED REFERENCE CODE (5 Oct 2026; seat: accountant).
--
-- Measured 5 Oct 2026: the September Mashreq statement lines 2265-2269 were recorded with kind NULL, because
-- bank_statement_line.kind came only from model reasoning (held) or a founder ruling, and ruling 890 forbids
-- reading description words. GL 1000 read 582.96 against a statement balance of 59.25 (gap 523.71 =
-- 199.00 fee + 9.95 VAT + 41.05 + 275.01 card purchases - 1.30 interest).
--
-- Mashreq's REFERENCE field is a structured code, not prose: a transaction-type identifier, then a sequence.
-- public.bank_reference_code holds the codes the bank issues; a line whose reference's first token begins with
-- code_prefix, and whose second token equals code_suffix when one is set, and whose sign matches, takes the
-- row's kind. The description column is never read (scripts/checks/
-- bank_lines_are_classified_by_reference_code_never_by_description.test.mjs fails if it is).
--
-- A row with kind NULL is a known code that is deliberately NOT classified: 030POSB (debit card purchase)
-- stays held until a receipt is matched to it, because the code says how it was paid, not what was bought.
--
-- GL account: fee and its VAT go to 6300 through the existing bank-charge path. The company is not VAT
-- registered (below the AED 375k threshold), so the VAT on the bank fee is not recoverable input VAT (1150);
-- it is part of the cost, exactly as the 1 Sep 2026 VAT line (journal 694) was booked. Interest goes to 7000
-- through the existing bank-credit path. The CHECK pins gl_account to what those two paths post, so the
-- table can never claim an account the journal path does not use.

create table if not exists public.bank_reference_code (
  id          bigint generated always as identity primary key,
  bank        text not null,                 -- = bank_statement_line.account
  code_prefix text not null,                 -- the first token of the reference begins with this
  code_suffix text,                          -- the second token equals this; NULL = any
  sign        smallint not null check (sign in (-1, 1)),
  kind        text check (kind in ('bank_charge', 'bank_interest')),   -- NULL = known, held (needs a receipt)
  gl_account  text references public.gl_accounts(code),
  meaning     text not null,
  added_by    text not null default 'accountant',
  created_at  timestamptz not null default now(),
  unique nulls not distinct (bank, code_prefix, code_suffix),
  check ((kind is null and gl_account is null)
      or (kind = 'bank_charge' and sign = -1 and gl_account = '6300')
      or (kind = 'bank_interest' and sign = 1 and gl_account = '7000'))
);
alter table public.bank_reference_code enable row level security;
drop policy if exists bank_reference_code_service_role_only on public.bank_reference_code;
create policy bank_reference_code_service_role_only on public.bank_reference_code
  as permissive for all to public using (false) with check (false);
revoke all on public.bank_reference_code from anon, authenticated;

insert into public.bank_reference_code (bank, code_prefix, code_suffix, sign, kind, gl_account, meaning) values
  ('mashreq', '099REFEAED', '00001', -1, 'bank_charge',   '6300', 'monthly maintenance fee'),
  ('mashreq', '099REFEAED', '00002', -1, 'bank_charge',   '6300', 'VAT on the monthly maintenance fee (not recoverable: not VAT registered)'),
  ('mashreq', '099CIDBAED', null,     1, 'bank_interest', '7000', 'interest credited'),
  ('mashreq', '030POSB',    null,    -1, null,            null,   'debit card purchase: held until a receipt is matched')
on conflict (bank, code_prefix, code_suffix) do nothing;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('bank_reference_code', true, 'company', 'the bank''s structured reference codes and the kind each one books as', 'accountant')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

create or replace function public.fn_accountant_classify_bank_lines_by_reference()
returns int language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare n int;
begin
  update public.bank_statement_line b
     set kind = c.kind, kind_by = 'bank_reference_code#' || c.id, kind_at = now()
    from public.bank_reference_code c
   where b.kind is null and c.kind is not null
     and b.account = c.bank and b.reference is not null
     and starts_with(split_part(b.reference, ' ', 1), c.code_prefix)
     and (c.code_suffix is null or split_part(b.reference, ' ', 2) = c.code_suffix)
     and sign(b.amount_aed) = c.sign;
  get diagnostics n = row_count;
  return n;
end $fn$;
revoke execute on function public.fn_accountant_classify_bank_lines_by_reference() from public, anon, authenticated;

create or replace function public.fn_accountant_cost_booking_tick()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_sync int; v_class int; v_bank jsonb; v_cap jsonb;
begin
  v_sync := public.fn_gl_sync_business();
  -- Structured reference codes first, so the bank-charge and bank-credit rules below book what they classify.
  -- Its own block: a classifier failure never undoes the business sync or stops the bookings below.
  begin
    v_class := public.fn_accountant_classify_bank_lines_by_reference();
    perform public.fn_accountant_duty_settle('bank_reference_classify', '[]'::jsonb);
  exception when others then
    -- never silent (release review): the failure is an accountant finding, and the bookings below still run
    v_class := null;
    perform public.fn_accountant_duty_settle('bank_reference_classify', jsonb_build_array(jsonb_build_object(
      'item', 'run', 'owner_seat', 'accountant', 'subject', 'bank_statement_line',
      'title', 'Classifying bank lines by their reference code failed, so none was classified this run: ' || sqlerrm,
      'blast', 'agent_facing', 'affected', 1)));
  end;
  v_bank := public.fn_accountant_book_bank_charges();
  -- The bank-credit rule runs in its own block (review of b06d251): whatever fails in it can never undo the
  -- business sync or the bank charges above; the failure is an accountant finding instead.
  begin
    v_cap := public.fn_accountant_book_bank_credits();
    perform public.fn_accountant_duty_settle('bank_credits_run', '[]'::jsonb);
  exception when others then
    v_cap := jsonb_build_object('error', sqlerrm);
    perform public.fn_accountant_duty_settle('bank_credits_run', jsonb_build_array(jsonb_build_object(
      'item', 'run', 'owner_seat', 'accountant', 'subject', 'bank_statement_line',
      'title', 'Booking the bank''s credits failed, so nothing was booked from them this run: ' || sqlerrm,
      'blast', 'agent_facing', 'affected', 1)));
  end;
  return jsonb_build_object('gl_sync_business_entries', v_sync, 'classified_by_reference_code', v_class,
                            'bank_charges', v_bank, 'bank_credits', v_cap);
end $function$;

select case when (select count(*) from public.bank_reference_code where bank = 'mashreq') = 4
             and not exists (select 1 from pg_proc p where p.proname = 'fn_accountant_classify_bank_lines_by_reference'
                               and has_function_privilege('anon', p.oid, 'execute'))
            then 'PROBE OK 4 mashreq reference codes, classifier closed to anon'
            else 'PROBE FAILED: reference codes not seeded or the classifier is open' end as verdict;
