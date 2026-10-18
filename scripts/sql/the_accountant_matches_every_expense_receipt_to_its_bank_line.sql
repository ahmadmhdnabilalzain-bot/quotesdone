-- THE ACCOUNTANT MATCHES EVERY EXPENSE RECEIPT TO ITS BANK LINE (T6, accountant seat, 4 Oct 2026).
--
-- WHY: receipts the founder forwards to the expenses mailbox land in public.expense_entries (55 rows,
-- 4 Oct 2026); Mashreq statement lines land in public.bank_statement_line (6 rows). Only Stripe payouts
-- were matched to the bank (fn_accountant_bank_reconcile); no receipt was ever paired with the debit
-- that paid it, so a receipt with no payment and a payment with no receipt were both invisible.
--
-- WHAT THIS CHANGES:
--   * public.expense_bank_match: one row per receipt paired with one statement debit (each side once).
--   * public.fn_accountant_receipt_bank_match(): deterministic, no model. A receipt matches the
--     unmatched debit whose |amount| is within tolerance of the receipt in AED (USD at gl_settings
--     usd_to_aed) and whose value_date is within receipt_match_days after (1 day before) charged_on.
--     Among candidates, a debit whose description carries the vendor's first word wins, then the
--     nearest date, then the nearest amount. ZZ DEMO receipts match only the zz_demo account and back.
--   * It returns the unmatched on both sides inside the statement's coverage as the duty result
--     (seat_duty.last_result), which is where the accountant reads it. It raises no finding: until
--     29 Sep 2026 subscriptions were paid on the founder's personal card, so most receipts have no
--     Mashreq line by design and a finding per receipt would be noise.
--   * seat_duty accountant.receipt_bank_match, daily, on the existing seat clock.
--
-- Tolerance: receipt_match_tolerance_pct (3%, card FX spread) with a floor of
-- receipt_match_tolerance_aed (AED 1). Both in gl_settings so a ruling moves them without code.

insert into public.gl_settings (key, num_value, txt_value, updated_at) values
  ('receipt_match_days', 5, 'A Mashreq debit may be dated up to this many days AFTER a receipt''s charged_on (1 day before) and still be the payment of that receipt.', now()),
  ('receipt_match_tolerance_pct', 3, 'A Mashreq debit matches a receipt when its amount is within this percent of the receipt in AED (card FX spread on USD charges).', now()),
  ('receipt_match_tolerance_aed', 1, 'Floor of the receipt-to-debit amount tolerance, in AED.', now())
on conflict (key) do nothing;

create table if not exists public.expense_bank_match (
  expense_entry_id bigint primary key references public.expense_entries(id) on delete cascade,
  bank_line_id     bigint not null unique references public.bank_statement_line(id) on delete cascade,
  receipt_aed      numeric not null,
  bank_aed         numeric not null,
  day_gap          integer not null,
  vendor_in_text   boolean not null,
  matched_at       timestamptz not null default now()
);
alter table public.expense_bank_match enable row level security;
drop policy if exists expense_bank_match_service_role on public.expense_bank_match;
create policy expense_bank_match_service_role on public.expense_bank_match
  for all to service_role using (true) with check (true);
revoke all on public.expense_bank_match from public, anon, authenticated;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('expense_bank_match', true, 'company', 'which Mashreq statement debit paid each expense receipt, and how close the amount and date were', 'accountant')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

create or replace function public.fn_accountant_receipt_bank_match()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_days int; v_pct numeric; v_floor numeric; v_usd numeric;
  e record; l record; n_matched int := 0; v_aed numeric; v_token text;
begin
  select num_value::int into v_days  from public.gl_settings where key = 'receipt_match_days';
  select num_value      into v_pct   from public.gl_settings where key = 'receipt_match_tolerance_pct';
  select num_value      into v_floor from public.gl_settings where key = 'receipt_match_tolerance_aed';
  select num_value      into v_usd   from public.gl_settings where key = 'usd_to_aed';
  if v_days is null or v_pct is null or v_floor is null or v_usd is null then
    raise exception 'fn_accountant_receipt_bank_match: a receipt_match_* window or usd_to_aed is missing from gl_settings';
  end if;

  for e in select x.* from public.expense_entries x
            where x.amount > 0 and upper(x.currency) in ('AED', 'USD')
              and not exists (select 1 from public.expense_bank_match m where m.expense_entry_id = x.id)
            order by x.charged_on, x.id loop
    v_aed := round(e.amount * case when upper(e.currency) = 'USD' then v_usd else 1 end, 2);
    -- The vendor's first word of 3+ characters, after any ZZ DEMO prefix (else every demo word is "demo").
    v_token := lower(substring(regexp_replace(coalesce(e.vendor, ''), '^\s*ZZ DEMO\s*', '', 'i') from '[A-Za-z0-9]{3,}'));
    select bl.id, -bl.amount_aed as aed, bl.value_date - e.charged_on as gap,
           (v_token is not null and position(v_token in lower(coalesce(bl.description, '') || ' ' || coalesce(bl.reference, ''))) > 0) as hit
      into l
      from public.bank_statement_line bl
     where bl.amount_aed < 0
       and ((bl.account = 'zz_demo') = (e.vendor ilike 'ZZ DEMO%'))
       and abs(-bl.amount_aed - v_aed) <= greatest(v_floor, v_aed * v_pct / 100)
       and bl.value_date between e.charged_on - 1 and e.charged_on + v_days
       and not exists (select 1 from public.expense_bank_match m where m.bank_line_id = bl.id)
     order by 4 desc, abs(bl.value_date - e.charged_on), abs(-bl.amount_aed - v_aed), bl.id
     limit 1;
    if found then
      insert into public.expense_bank_match (expense_entry_id, bank_line_id, receipt_aed, bank_aed, day_gap, vendor_in_text)
      values (e.id, l.id, v_aed, l.aed, l.gap, l.hit);
      n_matched := n_matched + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'matched_now', n_matched,
    'matched', (select count(*) from public.expense_bank_match),
    'receipts_not_matchable', (select count(*) from public.expense_entries x
                                where not (x.amount > 0 and upper(coalesce(x.currency, '')) in ('AED', 'USD'))),
    -- Receipts inside a statement's coverage (and past the window) with no debit: paid elsewhere, or missing.
    'receipts_unmatched', (select coalesce(jsonb_agg(jsonb_build_object('expense_entry', x.id, 'vendor', x.vendor,
                              'amount', x.amount, 'currency', x.currency, 'charged_on', x.charged_on) order by x.charged_on), '[]'::jsonb)
                             from public.expense_entries x
                            where x.amount > 0 and upper(x.currency) in ('AED', 'USD')
                              and not exists (select 1 from public.expense_bank_match m where m.expense_entry_id = x.id)
                              and exists (select 1 from public.bank_statement_line bl
                                           where (bl.account = 'zz_demo') = (x.vendor ilike 'ZZ DEMO%')
                                             and bl.value_date <= x.charged_on - 1)
                              and exists (select 1 from public.bank_statement_line bl
                                           where (bl.account = 'zz_demo') = (x.vendor ilike 'ZZ DEMO%')
                                             and bl.value_date >= x.charged_on + v_days)),
    -- Debits the bank did not book itself, with no receipt: a payment the mailbox never received a document for.
    'bank_debits_unmatched', (select coalesce(jsonb_agg(jsonb_build_object('line', bl.id, 'account', bl.account,
                              'value_date', bl.value_date, 'amount_aed', bl.amount_aed,
                              'description', public.fn_mask_bank_text(bl.description)) order by bl.value_date), '[]'::jsonb)
                             from public.bank_statement_line bl
                            where bl.amount_aed < 0
                              and bl.kind is distinct from 'bank_charge'
                              and not exists (select 1 from public.expense_bank_match m where m.bank_line_id = bl.id)),
    'basis', 'Receipts (expense_entries, from the expenses mailbox) against Mashreq debits: amount within '
             || v_pct || '% (floor AED ' || v_floor || '), USD at ' || v_usd || ', value date ' || '-1..+' || v_days
             || ' days, vendor word in the line preferred. Bank charges book themselves and are not expected to carry a receipt. Nothing was posted to the ledger.');
end $$;
revoke all on function public.fn_accountant_receipt_bank_match() from public, anon, authenticated;
grant execute on function public.fn_accountant_receipt_bank_match() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('accountant.receipt_bank_match', 'accountant', '1 day', 'fn_accountant_receipt_bank_match',
   'every expense receipt from the expenses mailbox paired with the Mashreq debit that paid it; unmatched receipts and unmatched debits listed in the result',
   'scripts/sql/the_accountant_matches_every_expense_receipt_to_its_bank_line.sql')
on conflict (duty) do update set routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file, every = excluded.every;
