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
--     Only a debit whose text carries the vendor's first word can be booked, and only when the pairing
--     is unique (review of #1178): two such debits for one receipt, no vendor word at all, or a debit
--     that is the only option of two receipts are listed under 'ambiguous' and never booked. Order
--     decides nothing: forced pairs are booked and the rest re-read, so an earlier receipt cannot take
--     the debit a later receipt needs. ZZ DEMO receipts match only the zz_demo account and back.
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
set search_path to 'public', 'pg_temp'
as $$
declare
  v_days int; v_pct numeric; v_floor numeric; v_usd numeric;
  e int; n_matched int := 0;
begin
  select num_value::int into v_days  from public.gl_settings where key = 'receipt_match_days';
  select num_value      into v_pct   from public.gl_settings where key = 'receipt_match_tolerance_pct';
  select num_value      into v_floor from public.gl_settings where key = 'receipt_match_tolerance_aed';
  select num_value      into v_usd   from public.gl_settings where key = 'usd_to_aed';
  if v_days is null or v_pct is null or v_floor is null or v_usd is null then
    raise exception 'fn_accountant_receipt_bank_match: a receipt_match_* window or usd_to_aed is missing from gl_settings';
  end if;

  -- Every (unmatched receipt, unmatched debit) pair that fits on account, amount and date, with whether
  -- the debit's text carries the receipt vendor's first 3+ character word (after any ZZ DEMO prefix).
  drop table if exists pg_temp.rbm_cand;
  create temp table rbm_cand on commit drop as
  select x.id as eid, bl.id as lid, r.aed as receipt_aed, -bl.amount_aed as bank_aed,
         bl.value_date - x.charged_on as gap,
         (r.tok is not null and position(r.tok in lower(coalesce(bl.description, '') || ' ' || coalesce(bl.reference, ''))) > 0) as hit
    from public.expense_entries x
    cross join lateral (select round(x.amount * case when upper(x.currency) = 'USD' then v_usd else 1 end, 2) as aed,
                               lower(substring(regexp_replace(coalesce(x.vendor, ''), '^\s*ZZ DEMO\s*', '', 'i')
                                               from '[A-Za-z0-9]{3,}')) as tok) r
    join public.bank_statement_line bl
      on bl.amount_aed < 0
     and (bl.account = 'zz_demo') = (x.vendor ilike 'ZZ DEMO%')
     and abs(-bl.amount_aed - r.aed) <= greatest(v_floor, r.aed * v_pct / 100)
     and bl.value_date between x.charged_on - 1 and x.charged_on + v_days
   where x.amount > 0 and upper(x.currency) in ('AED', 'USD')
     and not exists (select 1 from public.expense_bank_match m where m.expense_entry_id = x.id)
     and not exists (select 1 from public.expense_bank_match m where m.bank_line_id = bl.id);

  -- A receipt whose fitting debits carry no vendor word is never booked: it is listed ambiguous.
  -- Only vendor-word pairs can be booked, and only when the pairing is forced, never by order:
  -- a receipt with exactly one such debit takes it unless another receipt has that same debit as
  -- ITS only one too (contested). Each booking removes both sides and the rest is re-read, so a
  -- later receipt whose only debit an earlier receipt could also use gets it, and the earlier one
  -- is left with its own. Whatever is still open is ambiguous for the accountant.
  drop table if exists pg_temp.rbm_open;
  create temp table rbm_open on commit drop as select * from rbm_cand where hit;
  loop
    with only_one as (
      select eid, min(lid) as lid from rbm_open group by eid having count(*) = 1
    ), forced as (
      select o.eid, o.lid from only_one o
       where (select count(*) from only_one o2 where o2.lid = o.lid) = 1
    ), booked as (
      insert into public.expense_bank_match (expense_entry_id, bank_line_id, receipt_aed, bank_aed, day_gap, vendor_in_text)
      select c.eid, c.lid, c.receipt_aed, c.bank_aed, c.gap, true
        from forced f join rbm_open c on c.eid = f.eid and c.lid = f.lid
      returning expense_entry_id, bank_line_id
    ), gone as (
      delete from rbm_open c using booked b where c.eid = b.expense_entry_id or c.lid = b.bank_line_id
      returning 1
    )
    select count(*) into e from booked;
    exit when e = 0;
    n_matched := n_matched + e;
  end loop;

  return jsonb_build_object(
    'matched_now', n_matched,
    'matched', (select count(*) from public.expense_bank_match),
    -- Receipts with a fitting debit that were NOT booked, for the accountant to decide: never posted.
    'ambiguous', (select coalesce(jsonb_agg(jsonb_build_object('expense_entry', a.eid,
                     'reason', case when not bool_or_hit then 'no_vendor_word'
                                    when open_n > 1 then 'several_debits' else 'contested' end,
                     'lines', a.lines) order by a.eid), '[]'::jsonb)
                    from (select c.eid, bool_or(c.hit) as bool_or_hit,
                                 (select count(*) from rbm_open o where o.eid = c.eid) as open_n,
                                 jsonb_agg(c.lid order by c.lid) as lines
                            from rbm_cand c
                           where not exists (select 1 from public.expense_bank_match m where m.expense_entry_id = c.eid)
                             and not exists (select 1 from public.expense_bank_match m where m.bank_line_id = c.lid)
                           group by c.eid) a),
    'receipts_not_matchable', (select count(*) from public.expense_entries x
                                where not (x.amount > 0 and upper(coalesce(x.currency, '')) in ('AED', 'USD'))),
    -- Receipts inside a statement's coverage (and past the window) with no debit: paid elsewhere, or missing.
    'receipts_unmatched', (select coalesce(jsonb_agg(jsonb_build_object('expense_entry', x.id, 'vendor', x.vendor,
                              'amount', x.amount, 'currency', x.currency, 'charged_on', x.charged_on) order by x.charged_on), '[]'::jsonb)
                             from public.expense_entries x
                            where x.amount > 0 and upper(x.currency) in ('AED', 'USD')
                              and not exists (select 1 from public.expense_bank_match m where m.expense_entry_id = x.id)
                              and not exists (select 1 from rbm_cand c where c.eid = x.id
                                                and not exists (select 1 from public.expense_bank_match m where m.bank_line_id = c.lid))
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
revoke execute on function public.fn_accountant_receipt_bank_match() from public, anon, authenticated;
grant execute on function public.fn_accountant_receipt_bank_match() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('accountant.receipt_bank_match', 'accountant', '1 day', 'fn_accountant_receipt_bank_match',
   'every expense receipt from the expenses mailbox paired with the Mashreq debit that paid it; unmatched receipts and unmatched debits listed in the result',
   'scripts/sql/the_accountant_matches_every_expense_receipt_to_its_bank_line.sql')
on conflict (duty) do update set routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file, every = excluded.every;
