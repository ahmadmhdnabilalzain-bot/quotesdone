-- EVERY EXPENSE HAS ITS RECEIPT, AND EVERY SUBSCRIPTION ITS RENEWAL DATE AND ITS COST.
--
-- Assigned: accountant (duty 6 of the eight, founder 14 Sep 2026: "yea add them all").
--
-- WHAT WAS MEASURED (14 Sep 2026, production htdblwldjkcgjvmqkbeh):
--   * expense_entries holds 52 booked receipts from the expenses mailbox; expenses (the recurring
--     register) holds 4 rows — Resend, Google, Vercel, GoDaddy — each with next_due NULL: the column
--     and reminder_days exist and nothing ever filled them.
--   * fn_accountant_receipt_cadence_gaps already finds a vendor that skipped a month, went quiet, or
--     billed once without a recorded reason. Its only reader is the weekly report: a gap was printed
--     and nobody was asked to close it.
--   * The company's own subscriptions the founder listed — Dropbox, Supabase, Vercel, Twilio, Resend,
--     Meta and the domains — are not all on the register: a vendor that never had a receipt forwarded
--     is invisible to every check here (the cadence function says so in its own words).
--   * The IT engineer keeps the dates the company must renew in it_expiry (licences, domains, TLS).
--     There is no IT cost watch; the link is a view both seats read.
--
-- WHAT THIS BUILDS: next_due kept current from the latest receipt; a view v_company_subscriptions that
-- puts every recurring cost beside the IT engineer's renewal dates; and four findings, each ONE loop
-- rather than one per line so the founder is never sent a flood — expenses booked with no document,
-- expected vendors never billed through the mailbox, renewals charged with no receipt, and the cadence
-- gaps. Each goes round the IT loop; the founder hears once per finding and the remedy is always the
-- same: forward the receipt to expenses@mail.quotesdone.com.
--
-- WHAT THIS DOES NOT DO. It invents no cost and no renewal date for a vendor with no receipt: that
-- vendor is a finding, not a row with a guessed amount (expenses.amount is NOT NULL for a reason).
--
--   node scripts/apply_sql.mjs scripts/sql/every_expense_has_its_receipt_and_every_subscription_its_renewal.sql --apply --ddl

-- ── 1. CONFIGURATION ─────────────────────────────────────────────────────────────────────────────
insert into public.decision_policy (key, value, description) values
  ('accountant_expected_subscription_vendors', '["Dropbox", "Supabase", "Vercel", "Twilio", "Resend", "Meta", "GoDaddy"]'::jsonb,
   'The company''s own subscriptions the founder listed on 14 Sep 2026 (Dropbox, Supabase, Vercel, Twilio, Resend, Meta, domains = GoDaddy). A vendor here with no receipt in expense_entries is a finding.')
on conflict (key) do nothing;
insert into public.gl_settings (key, num_value, txt_value) values
  ('renewal_receipt_grace_days', 7, 'Days after a recurring cost''s next_due by which its receipt is expected in the expenses mailbox.')
on conflict (key) do nothing;

-- ── 2. THE REGISTER BESIDE THE IT ENGINEER'S RENEWAL DATES ───────────────────────────────────────
create or replace view public.v_company_subscriptions with (security_invoker = true) as
  with last_rcpt as (
    select lower(vendor) v, max(charged_on) last_charged, count(*) receipts
      from public.expense_entries group by lower(vendor))
  select 'cost'::text as kind, e.vendor as item, e.amount, e.currency, e.cadence,
         coalesce(r.last_charged, e.expense_date) as last_charged, e.next_due as renews_on,
         coalesce(r.receipts, 0) as receipts, 'accountant'::text as owner_seat, 'expenses'::text as source
    from public.expenses e left join last_rcpt r on r.v = lower(e.vendor)
   where e.active
  union all
  select x.kind, x.item, null::numeric, null::text, 'on expiry'::text, null::date, x.expires_on, null::bigint,
         x.owner_seat, 'it_expiry'::text
    from public.it_expiry x;
comment on view public.v_company_subscriptions is
  'Every recurring cost the accountant holds (expenses, with the latest receipt from expense_entries) beside every date the IT engineer tracks for renewal (it_expiry: licences, domains, TLS). One place both seats read.';
revoke all on public.v_company_subscriptions from anon, authenticated;

-- ── 3. THE DUTY ──────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_expense_duty(p_as_of date default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  v_grace int := (select num_value::int from public.gl_settings where key = 'renewal_receipt_grace_days');
  v_items jsonb := '[]'::jsonb; v_list jsonb; v_n int; v_gaps jsonb; n_next int; v_vouched jsonb; v_demo boolean;
begin
  if v_grace is null then raise exception 'fn_accountant_expense_duty: gl_settings.renewal_receipt_grace_days is missing'; end if;

  -- (a) next_due from the latest receipt, for every recurring cost on a known cadence.
  update public.expenses e
     set next_due = (coalesce(r.last_charged, e.expense_date)
                     + case e.cadence when 'annual' then interval '1 year' else interval '1 month' end)::date
    from (select lower(vendor) v, max(charged_on) last_charged from public.expense_entries group by 1) r
   where e.active and e.cadence in ('monthly', 'annual') and r.v = lower(e.vendor)
     and e.next_due is distinct from (coalesce(r.last_charged, e.expense_date)
                     + case e.cadence when 'annual' then interval '1 year' else interval '1 month' end)::date;
  get diagnostics n_next = row_count;

  -- (b) Booked with no document behind it. 14 Sep 2026: an expense the founder vouched for (doc_kind
  -- 'founder_statement', allowed only on source founder_reported with his words in doc_note — expense 122,
  -- the DET licence: "its ok no need for it. just note down the number of 1200 AED") is documented by his
  -- word and is listed, not asked for. ZZ DEMO expenses are their own finding, so a rehearsal never judges,
  -- or is judged by, a real row (scripts/sql/an_expense_the_founder_vouches_for_is_documented_by_his_word.sql).
  select coalesce(jsonb_agg(jsonb_build_object('entry', id, 'vendor', vendor, 'amount', amount, 'currency', currency,
                                               'statement', doc_note) order by id), '[]'::jsonb)
    into v_vouched from public.expense_entries where coalesce(btrim(doc_path), '') = '' and doc_kind = 'founder_statement';
  foreach v_demo in array array[false, true] loop
    select count(*), coalesce(jsonb_agg(jsonb_build_object('entry', id, 'vendor', vendor, 'charged_on', charged_on,
                                                           'amount', amount, 'currency', currency) order by id), '[]'::jsonb)
      into v_n, v_list from public.expense_entries
     where coalesce(btrim(doc_path), '') = '' and doc_kind is distinct from 'founder_statement'
       and ((coalesce(vendor, '') || ' ' || coalesce(note, '')) ~* 'zz[ _-]?demo') = v_demo;
    if v_n > 0 then
      v_items := v_items || jsonb_build_object('item', case when v_demo then 'no_document:zz_demo' else 'no_document' end,
        'owner_seat', 'accountant', 'subject', 'expense_entries', 'demo', v_demo,
        'title', v_n || case when v_demo then ' ZZ DEMO' else '' end || ' booked expense(s) have no receipt or invoice behind them',
        'blast', 'internal', 'affected', v_n, 'evidence', jsonb_build_object('entries', v_list,
          'documented_by_founder_statement', v_vouched,
          'remedy', 'forward each receipt to expenses@mail.quotesdone.com; the sweep attaches it by vendor, amount and date'));
    end if;
  end loop;

  -- (c) A vendor the founder named that has never been billed through the mailbox.
  select count(*), coalesce(jsonb_agg(v order by v), '[]'::jsonb) into v_n, v_list
    from public.decision_policy d, jsonb_array_elements_text(d.value) v
   where d.key = 'accountant_expected_subscription_vendors'
     and not exists (select 1 from public.expense_entries x where x.vendor ilike '%' || v || '%')
     and not exists (select 1 from public.vendor_billing_ended b where b.vendor ilike '%' || v || '%');
  if v_n > 0 then
    v_items := v_items || jsonb_build_object('item', 'never_billed', 'owner_seat', 'accountant', 'subject', 'expenses',
      'title', 'No receipt has ever reached the accountant for ' || v_n || ' of the company''s own subscriptions: '
               || (select string_agg(x, ', ') from jsonb_array_elements_text(v_list) x),
      'blast', 'internal', 'affected', v_n, 'evidence', jsonb_build_object('vendors', v_list,
        'remedy', 'forward one receipt per vendor to expenses@mail.quotesdone.com, or record the vendor in vendor_billing_ended if it bills elsewhere'));
  end if;

  -- (d) A renewal that should have been charged and has no receipt.
  select count(*), coalesce(jsonb_agg(jsonb_build_object('vendor', e.vendor, 'renewed_on', e.next_due, 'amount', e.amount,
                                                         'currency', e.currency, 'cadence', e.cadence) order by e.vendor), '[]'::jsonb)
    into v_n, v_list
    from public.expenses e
   where e.active and e.next_due is not null and e.next_due + v_grace < v_as_of
     and not exists (select 1 from public.expense_entries x where lower(x.vendor) = lower(e.vendor) and x.charged_on >= e.next_due - 3)
     and not exists (select 1 from public.vendor_billing_ended b where lower(b.vendor) = lower(e.vendor));
  if v_n > 0 then
    v_items := v_items || jsonb_build_object('item', 'renewal_receipt', 'owner_seat', 'accountant', 'subject', 'expenses',
      'title', v_n || ' subscription renewal(s) fell due more than ' || v_grace || ' days ago with no receipt',
      'blast', 'internal', 'affected', v_n, 'evidence', jsonb_build_object('renewals', v_list,
        'remedy', 'forward the renewal receipt, or mark the subscription inactive in expenses if it was cancelled'));
  end if;

  -- (e) The vendor-side gaps fn_accountant_receipt_cadence_gaps already measures, now owned.
  v_gaps := public.fn_accountant_receipt_cadence_gaps(v_as_of);
  if coalesce((v_gaps->>'suspected_missing')::int, 0) > 0 then
    v_items := v_items || jsonb_build_object('item', 'cadence_gaps', 'owner_seat', 'accountant', 'subject', 'expense_entries',
      'title', (v_gaps->>'suspected_missing') || ' suspected missing receipt(s): a vendor skipped a month, went quiet, or billed once without a recorded reason',
      'blast', 'internal', 'affected', (v_gaps->>'suspected_missing')::int, 'evidence', v_gaps);
  end if;

  return jsonb_build_object('as_of', v_as_of, 'next_due_updated', n_next,
    'documented_by_founder_statement', v_vouched,
    'findings', public.fn_accountant_duty_settle('expenses', v_items));
end $fn$;
revoke execute on function public.fn_accountant_expense_duty(date) from public, anon, authenticated;
