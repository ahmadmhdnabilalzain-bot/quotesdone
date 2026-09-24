-- CLAUDE AND CHATGPT ARE COMPANY EXPENSES, PAID ON THE OWNER'S CARD, AT THE BANK'S AED 799 EACH.
--
-- Assigned: accountant. Founder, in chat, 24 Sep 2026 (instruction 974 context):
--   * his Claude (Anthropic) and ChatGPT (OpenAI) subscriptions are company expenses;
--   * each costs AED 799 a month AS CHARGED BY THE BANK (FX and card fees included), which replaces the USD
--     figures; both recur monthly at that amount: Claude around the 23rd, ChatGPT around the 19th;
--   * correction the same day: these, like most subscriptions today, are paid on his PERSONAL card, moving to
--     the company card from early October 2026. So they are expenses the owner paid on the company's behalf:
--     a debt to him, NOT capital (owner money IN is capital; an owner paying a company bill is owed back),
--     and they are NOT on the Mashreq statement until he says the card has moved.
--
-- WHAT WAS MEASURED (24 Sep 2026, production):
--   * Every expense journal credits 1000 Cash & Bank (fn_expense_post_to_gl), and the chart had no account for
--     money owed to the owner. Anthropic's last booked month is 23 Aug (USD 210); OpenAI's only row is 29 Jul
--     (AED 385), and vendor_billing_ended records OpenAI as portal_only (it never emails a monthly receipt).
--   * The September Claude receipt #2830-8951-2948 reached expenses@ as inbound_messages 161 (23 Sep 23:37 UTC)
--     and was not yet booked; the hourly expense sweep books it at USD 210 x 3.6725 = AED 771.23.
--
-- WHAT THIS BUILDS:
--   1. 2500 Due to Owner (founder current account), a liability.
--   2. accountant_owner_ruled_subscription, the register of his ruling: vendor, AED bank value, usual day, and
--      paid_from 'owner_card' | 'company_card' (default owner_card). Bank matching starts only for a vendor
--      flipped to company_card; flipping is an UPDATE of one row.
--   3. OpenAI 19 Sep 2026, AED 799, booked on his word: source founder_reported, doc_kind founder_statement,
--      "receipt not provided; owner ruling 24 Sep".
--   4. fn_accountant_owner_card_tick (duty 'owner_card', run every hour by fn_accountant_duties after costs):
--      (a) for each month's charge of a ruled vendor, once its expense has posted, ONE journal restates it at
--          the bank value. owner_card: Dr 1000 what the expense took from cash, Dr 6300 the FX-and-card
--          difference, Cr 2500 the bank value. company_card: Dr 6300 / Cr 1000 the difference only.
--          Claude September: Dr 1000 771.23, Dr 6300 27.77, Cr 2500 799.00. ChatGPT: Dr 1000 799, Cr 2500 799.
--          6300 is where the Mashreq bank charges already book (every_mashreq_line_of_august_is_ruled_and_reconciled.sql).
--      (b) the expectation: a month whose usual date is more than 5 days past with no receipt and no owner
--          confirmation (a founder_reported entry) is a finding in the accountant's loop, under its own duty
--          name, NOT the "waiting" expenses items of instruction 585, because he asked to see this one.
--          company_card vendors also need a Mashreq line of the bank value (+/-2%) within 5 days of the usual
--          date, once a statement covering that date has arrived.
--
-- WHAT IT DOES NOT DO. It invents no August ChatGPT charge (he ruled from September), re-dates nothing already
-- booked, and does not reclassify owner-card expenses before September (their credit is still 1000: a
-- separate reclassification the founder has not ruled on).
--
-- DATA + DDL, committed PENDING (scripts/sql/pending/) and applied by the release operator:
--   node scripts/apply_sql.mjs scripts/sql/claude_and_chatgpt_are_company_expenses_paid_on_the_owners_card.sql --apply --ddl

insert into public.founder_instruction (said_at, instruction, subject, status, evidence, note)
select '2026-09-24T10:00:00Z',
       'Claude (Anthropic) and ChatGPT (OpenAI) subscriptions are company expenses: AED 799 a month each as charged by the bank (includes FX and card fees, replaces the USD amounts), monthly, Claude ~23rd, ChatGPT ~19th; no receipt for the 19 Sep ChatGPT charge. Paid on his personal card until early October 2026, then the company card.',
       'Claude and ChatGPT are company expenses at AED 799 bank value, paid on the owner''s card', 'done',
       'accountant_owner_ruled_subscription holds both vendors; OpenAI 19 Sep booked as founder_statement; fn_accountant_owner_card_tick restates each month at AED 799 to 2500 Due to Owner and raises a finding 5 days after a missed month (scripts/sql/claude_and_chatgpt_are_company_expenses_paid_on_the_owners_card.sql).',
       'Owner paid a company bill: a debt to him (2500), not capital.'
 where not exists (select 1 from public.founder_instruction f
                    where f.said_at::date = '2026-09-24' and f.instruction ilike '%799%' and f.instruction ~* 'claude|anthropic');

insert into public.gl_accounts (code, name, type, subtype, normal_balance, is_active, description)
values ('2500', 'Due to Owner (founder current account)', 'liability', 'owner', 'C', true,
        'Company expenses the founder paid on his own card; owed back to him. Not capital (founder, 24 Sep 2026).')
on conflict (code) do nothing;

create table if not exists public.accountant_owner_ruled_subscription (
  vendor          text primary key,
  vendor_pattern  text not null,
  bank_value_aed  numeric(18,2) not null check (bank_value_aed > 0),
  cadence         text not null default 'monthly' check (cadence = 'monthly'),
  usual_day       int  not null check (usual_day between 1 and 31),
  expected_from   date not null,
  paid_from       text not null default 'owner_card' check (paid_from in ('owner_card', 'company_card')),
  bank_pattern    text,
  receipt_emailed boolean not null,
  basis           text not null,
  recorded_at     timestamptz not null default now()
);
comment on table public.accountant_owner_ruled_subscription is
  'Subscriptions the founder ruled are company expenses at a fixed AED bank value (24 Sep 2026: Claude and ChatGPT, AED 799/month). paid_from says whose card pays: owner_card books the bank value to 2500 Due to Owner and never expects a Mashreq line; company_card books against 1000 and expects the line. Read by fn_accountant_owner_card_tick.';
alter table public.accountant_owner_ruled_subscription enable row level security;
drop policy if exists accountant_owner_ruled_subscription_service_role_only on public.accountant_owner_ruled_subscription;
create policy accountant_owner_ruled_subscription_service_role_only on public.accountant_owner_ruled_subscription
  as permissive for all to public using (false) with check (false);
revoke all on public.accountant_owner_ruled_subscription from anon, authenticated;

insert into public.accountant_owner_ruled_subscription
  (vendor, vendor_pattern, bank_value_aed, usual_day, expected_from, paid_from, bank_pattern, receipt_emailed, basis) values
  ('Anthropic', '^anthropic', 799, 23, date '2026-09-01', 'owner_card', 'anthropic|claude', true,
   'Founder, 24 Sep 2026: Claude is a company expense, AED 799/month at bank value, billed ~23rd; receipt forwarded to expenses@. Owner''s personal card until early Oct 2026.'),
  ('OpenAI', '^openai', 799, 19, date '2026-09-01', 'owner_card', 'openai|chatgpt', false,
   'Founder, 24 Sep 2026: ChatGPT is a company expense, AED 799/month at bank value, billed ~19th; OpenAI emails no monthly receipt, so his confirmation is the evidence. Owner''s personal card until early Oct 2026.')
on conflict (vendor) do nothing;

-- OpenAI, 19 Sep 2026, on the founder's word (the CHECK admits founder_statement only on founder_reported).
insert into public.expense_entries (vendor, category, amount, currency, charged_on, note, source, doc_kind, doc_note)
select 'OpenAI', 'Subscription', 799, 'AED', date '2026-09-19',
       'OpenAI ChatGPT subscription, September 2026, AED 799 as charged by the bank (FX and card fees included). Paid on the founder''s personal card; owed back to him (2500).',
       'founder_reported', 'founder_statement',
       'receipt not provided; owner ruling 24 Sep 2026: ChatGPT is a company expense at AED 799 a month as charged by the bank, billed around the 19th. OpenAI emails no monthly receipt.'
 where not exists (select 1 from public.expense_entries e where e.vendor ~* '^openai' and e.charged_on between date '2026-09-14' and date '2026-09-24');

-- ── THE DUTY ─────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_owner_card_tick(p_as_of date default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  s record; m date; v_exp date; e record; v_posted numeric(18,2); v_diff numeric(18,2); v_lines jsonb;
  v_booked jsonb := '[]'::jsonb; v_matched jsonb := '[]'::jsonb; v_items jsonb := '[]'::jsonb;
  v_missing jsonb; v_noline jsonb; v_odd jsonb := '[]'::jsonb; v_line bigint;
begin
  for s in select * from public.accountant_owner_ruled_subscription order by vendor loop
    v_missing := '[]'::jsonb; v_noline := '[]'::jsonb;
    for m in select generate_series(date_trunc('month', s.expected_from), date_trunc('month', v_as_of), interval '1 month')::date loop
      v_exp := m + (least(s.usual_day, extract(day from (m + interval '1 month - 1 day'))::int) - 1);
      if v_exp < s.expected_from then continue; end if;
      -- The month's charge: the vendor's entry nearest the usual date, within 5 days (a receipt, or his word).
      select x.* into e from public.expense_entries x
       where x.vendor ~* s.vendor_pattern and x.charged_on between v_exp - 5 and v_exp + 5
         and not ((coalesce(x.vendor, '') || ' ' || coalesce(x.note, '')) ~* 'zz[ _-]?demo')
       order by abs(x.charged_on - v_exp), x.id limit 1;
      if not found then
        if v_as_of > v_exp + 5 then
          v_missing := v_missing || jsonb_build_object('month', to_char(m, 'YYYY-MM'), 'expected_on', v_exp);
        end if;
        continue;
      end if;

      -- (a) Restate it at the bank value, once, after its expense journal has posted.
      if not exists (select 1 from public.gl_journal g where g.source = 'owner_card_bank_value' and g.source_ref = e.id::text) then
        select sum(jl.credit) into v_posted from public.gl_journal g join public.gl_journal_lines jl on jl.journal_id = g.id
         where g.source = 'expense' and g.source_ref = e.id::text and g.status = 'posted' and jl.account_code = '1000';
        if v_posted is not null then
          v_diff := s.bank_value_aed - v_posted;
          if v_diff < 0 or v_diff > 0.15 * s.bank_value_aed then
            -- ponytail: a gap over 15% is not FX and card fees; it is reported, never forced to the bank value.
            v_odd := v_odd || jsonb_build_object('vendor', s.vendor, 'entry', e.id, 'posted_aed', v_posted, 'bank_value_aed', s.bank_value_aed);
          elsif v_diff > 0 or s.paid_from = 'owner_card' then
            v_lines := '[]'::jsonb;
            if s.paid_from = 'owner_card' then
              v_lines := v_lines || jsonb_build_object('account', '1000', 'debit', v_posted,
                                      'memo', 'Not paid from the company bank: the owner''s card paid it');
            end if;
            if v_diff > 0 then
              v_lines := v_lines || jsonb_build_object('account', '6300', 'debit', v_diff, 'memo', 'FX and card fees above the receipt');
            end if;
            v_lines := v_lines || jsonb_build_object('account', case when s.paid_from = 'owner_card' then '2500' else '1000' end,
                         'credit', case when s.paid_from = 'owner_card' then s.bank_value_aed else v_diff end);
            perform public.fn_gl_entry(e.charged_on,
              s.vendor || ' ' || to_char(m, 'Mon YYYY') || ' at the bank value AED ' || s.bank_value_aed
                || ' (booked ' || v_posted || ', FX and card ' || v_diff || ')'
                || case when s.paid_from = 'owner_card' then ', paid on the owner''s card: due to owner' else '' end,
              'owner_card_bank_value', e.id::text, v_lines, 'accountant');
            v_booked := v_booked || jsonb_build_object('vendor', s.vendor, 'entry', e.id, 'posted_aed', v_posted, 'fx_card_aed', v_diff,
                                                       'bank_value_aed', s.bank_value_aed, 'paid_from', s.paid_from);
          end if;
        end if;
      end if;

      -- (b) A company_card charge is also on the Mashreq statement, once a statement covering it has arrived.
      if s.paid_from = 'company_card'
         and exists (select 1 from public.bank_statement_line b where b.account = 'mashreq' and b.value_date >= v_exp + 5) then
        v_line := null;
        select b.id into v_line from public.bank_statement_line b
         where b.account = 'mashreq' and b.value_date between v_exp - 5 and v_exp + 5
           and b.amount_aed between -1.02 * s.bank_value_aed and -0.98 * s.bank_value_aed
           and (s.bank_pattern is null or b.description ~* s.bank_pattern)
         order by abs(b.value_date - v_exp) limit 1;
        if v_line is null then
          v_noline := v_noline || jsonb_build_object('month', to_char(m, 'YYYY-MM'), 'entry', e.id);
        else
          v_matched := v_matched || jsonb_build_object('vendor', s.vendor, 'entry', e.id, 'bank_line', v_line);
        end if;
      end if;
    end loop;

    if jsonb_array_length(v_missing) > 0 then
      v_items := v_items || jsonb_build_object('item', 'missing_charge:' || lower(s.vendor), 'owner_seat', 'accountant',
        'subject', 'expense_entries', 'blast', 'internal', 'affected', jsonb_array_length(v_missing),
        'title', s.vendor || ': ' || jsonb_array_length(v_missing) || ' month(s) with no '
                 || case when s.receipt_emailed then 'receipt' else 'owner confirmation' end
                 || ' 5 days after the usual date (AED ' || s.bank_value_aed || ' a month, ' || replace(s.paid_from, '_', ' ') || ')',
        'evidence', jsonb_build_object('vendor', s.vendor, 'months', v_missing, 'paid_from', s.paid_from,
          'remedy', case when s.receipt_emailed then 'forward the month''s receipt to expenses@mail.quotesdone.com'
                         else 'the founder confirms the month''s charge; it is booked as a founder_statement at the bank value' end));
    end if;
    if jsonb_array_length(v_noline) > 0 then
      v_items := v_items || jsonb_build_object('item', 'bank_line_missing:' || lower(s.vendor), 'owner_seat', 'accountant',
        'subject', 'bank_statement_line', 'blast', 'internal', 'affected', jsonb_array_length(v_noline),
        'title', s.vendor || ' is paid by the company card but ' || jsonb_array_length(v_noline)
                 || ' month(s) have no Mashreq line of AED ' || s.bank_value_aed,
        'evidence', jsonb_build_object('vendor', s.vendor, 'months', v_noline,
          'remedy', 'read the statement for the charge; if the card did not move, set paid_from back to owner_card'));
    end if;
  end loop;

  if jsonb_array_length(v_odd) > 0 then
    v_items := v_items || jsonb_build_object('item', 'bank_value_mismatch', 'owner_seat', 'accountant', 'subject', 'gl_journal',
      'blast', 'internal', 'affected', jsonb_array_length(v_odd),
      'title', jsonb_array_length(v_odd) || ' ruled subscription charge(s) differ from the bank value by more than FX and card fees explain',
      'evidence', jsonb_build_object('entries', v_odd, 'remedy', 'read the receipt; a plan change needs a new bank value from the founder'));
  end if;

  return jsonb_build_object('as_of', v_as_of, 'restated', v_booked, 'bank_lines_matched', v_matched,
    'findings', public.fn_accountant_duty_settle('owner_card', v_items));
end $fn$;
revoke execute on function public.fn_accountant_owner_card_tick(date) from public, anon, authenticated;

-- ── THE HOURLY DUTIES, WITH owner_card AFTER costs ───────────────────────────────────────────────
-- p_r: {stripe: {live|test: {basis, reason?, payouts[], fee_bts[], disputes[]}}, charge_audit: [..] | null}
create or replace function public.fn_accountant_duties(p_r jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare o jsonb := '{}'::jsonb; v_err jsonb := '[]'::jsonb; v_mode text; s jsonb; x jsonb; v_step text; v_rec jsonb;
begin
  if jsonb_typeof(p_r) is distinct from 'object' then
    raise exception 'fn_accountant_duties takes the readings object the accountant runtime assembles';
  end if;

  -- What only Stripe can say, recorded first so the duties below read it.
  begin
    for v_mode in select unnest(array['live', 'test']) loop
      s := p_r->'stripe'->v_mode;
      if coalesce(s->>'basis', '') <> 'measured' then
        o := o || jsonb_build_object('stripe_' || v_mode, jsonb_build_object('basis', coalesce(s->>'basis', 'not_read'), 'reason', s->>'reason'));
        continue;
      end if;
      v_rec := jsonb_build_object(
        'payouts', public.fn_accountant_payouts_record(v_mode = 'live', coalesce(s->'payouts', '[]'::jsonb)),
        'stripe_fees', public.fn_accountant_book_stripe_fees(v_mode = 'live', coalesce(s->'fee_bts', '[]'::jsonb)),
        'disputes', (select coalesce(jsonb_agg(public.fn_accountant_dispute_record(e, v_mode = 'live')), '[]'::jsonb)
                       from jsonb_array_elements(coalesce(s->'disputes', '[]'::jsonb)) e));
      o := o || jsonb_build_object('stripe_' || v_mode, v_rec);
    end loop;
  exception when others then v_err := v_err || jsonb_build_object('step', 'stripe', 'error', sqlerrm); end;

  begin o := o || jsonb_build_object('bank', public.fn_accountant_bank_reconcile());
  exception when others then v_err := v_err || jsonb_build_object('step', 'bank', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('collections', public.fn_accountant_collections_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'collections', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('subscriptions', public.fn_accountant_subscription_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'subscriptions', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('expenses', public.fn_accountant_expense_duty());
  exception when others then v_err := v_err || jsonb_build_object('step', 'expenses', 'error', sqlerrm); end;
  begin
    if jsonb_typeof(p_r->'charge_audit') = 'array' then
      o := o || jsonb_build_object('charge_audit', public.fn_accountant_charge_audit_record(p_r->'charge_audit'));
    else
      o := o || jsonb_build_object('charge_audit', jsonb_build_object('basis', 'not_read'));
    end if;
  exception when others then v_err := v_err || jsonb_build_object('step', 'charge_audit', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('disputes', public.fn_accountant_disputes_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'disputes', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('costs', public.fn_accountant_cost_booking_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'costs', 'error', sqlerrm); end;
  -- owner_card (24 Sep 2026): after costs has posted the month's expenses, restate the ruled subscriptions
  -- at their bank value and raise a missed month (claude_and_chatgpt_are_company_expenses_paid_on_the_owners_card.sql).
  begin o := o || jsonb_build_object('owner_card', public.fn_accountant_owner_card_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'owner_card', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('books', public.fn_accountant_books_duty());
  exception when others then v_err := v_err || jsonb_build_object('step', 'books', 'error', sqlerrm); end;
  -- The five further duties (14 Sep 2026). Ad spend, recovery and renewals run BEFORE the close, which
  -- reads their figures; the bank balance and the year-end pack read the close, so they run after it.
  -- F2 AD SPEND IS HELD FOR THE MARKETING SEAT (founder rule 641, 22 Sep 2026: Meta and social are
  -- wired to no agent until that seat exists). The tick booked Meta spend from meta_insights (2 rows)
  -- into accountant_ad_spend_month (0 rows, measured 22 Sep 2026), so unwiring it changes no figure.
  -- fn_accountant_ad_spend_tick and _figures stay defined, and the close still reads the (empty)
  -- figures. The hold is recorded once, in public.company_policy_decision 'meta_and_social_held_for_marketing'.
  o := o || jsonb_build_object('ad_spend', jsonb_build_object('held', 'for the marketing seat (founder rule 641)'));
  begin o := o || jsonb_build_object('recovery', public.fn_accountant_recovery_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'recovery', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('renewals', public.fn_accountant_renewals_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'renewals', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('close', public.fn_accountant_month_close_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'close', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('bank_balance', public.fn_accountant_bank_balance_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'bank_balance', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('year_end', public.fn_accountant_year_end_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'year_end', 'error', sqlerrm); end;
  begin
    o := o || jsonb_build_object('ceo_acknowledged', public.fn_ceo_accountant_reports_sweep(),
                                 'completed', public.fn_accountant_reports_complete());
  exception when others then v_err := v_err || jsonb_build_object('step', 'ceo', 'error', sqlerrm); end;

  foreach v_step in array array['stripe', 'bank', 'collections', 'subscriptions', 'expenses', 'charge_audit', 'disputes', 'costs', 'owner_card', 'books',
                                'recovery', 'renewals', 'close', 'bank_balance', 'year_end', 'ceo'] loop
    perform public.fn_accountant_duty_stage(v_step,
      (select string_agg(e->>'error', '; ') from jsonb_array_elements(v_err) e where e->>'step' = v_step));
  end loop;

  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('accountant', case when jsonb_array_length(v_err) = 0 then 'ok' else 'error' end, now(), now(),
          jsonb_build_object('job', 'duties', 'result', o, 'errors', v_err), null);
  return o || jsonb_build_object('ok', jsonb_array_length(v_err) = 0, 'errors', v_err);
end $fn$;
revoke execute on function public.fn_accountant_duties(jsonb) from public, anon, authenticated;

-- Book what is already here: post the OpenAI entry (and the Claude September receipt if the sweep has booked
-- it), then run the duty once, so the release operator sees the result at apply.
select public.fn_expense_post_to_gl(e.id) from public.expense_entries e
 where e.vendor ~* '^(openai|anthropic)' and e.charged_on >= date '2026-09-01'
   and not exists (select 1 from public.gl_journal g where g.source = 'expense' and g.source_ref = e.id::text);
select public.fn_accountant_owner_card_tick();

-- The verdict. Writes nothing of its own; reads what the file booked.
with o as (select e.id, (select sum(jl.credit) from public.gl_journal g join public.gl_journal_lines jl on jl.journal_id = g.id
                          where g.source = 'owner_card_bank_value' and g.source_ref = e.id::text and jl.account_code = '2500') due
             from public.expense_entries e where e.vendor = 'OpenAI' and e.charged_on = '2026-09-19' and e.doc_kind = 'founder_statement'),
     c as (select e.id, (select sum(jl.debit) from public.gl_journal g join public.gl_journal_lines jl on jl.journal_id = g.id
                          where g.source in ('expense', 'owner_card_bank_value') and g.source_ref = e.id::text
                            and jl.account_code <> '1000') cost
             from public.expense_entries e where e.vendor ~* '^anthropic' and e.charged_on between '2026-09-18' and '2026-09-28'
            order by e.id limit 1)
select case
  when not exists (select 1 from public.gl_accounts where code = '2500' and type = 'liability') then 'PROBE FAILED: 2500 Due to Owner is missing'
  when (select count(*) from public.accountant_owner_ruled_subscription where paid_from = 'owner_card' and bank_value_aed = 799) <> 2
       then 'PROBE FAILED: the register does not hold both vendors at 799 on the owner''s card'
  when (select count(*) from o) <> 1 then 'PROBE FAILED: OpenAI 19 Sep is not booked exactly once as a founder_statement'
  when (select due from o) is distinct from 799 then 'PROBE FAILED: OpenAI 19 Sep does not owe the owner AED 799, got ' || coalesce((select due from o)::text, 'nothing')
  when exists (select 1 from c where cost is not null) and (select cost from c) is distinct from 799
       then 'PROBE FAILED: Claude September costs ' || (select cost from c) || ', not 799'
  when not exists (select 1 from pg_proc where proname = 'fn_accountant_duties' and prosrc like '%fn_accountant_owner_card_tick%')
       then 'PROBE FAILED: the hourly duties do not run owner_card'
  else 'PROBE OK: OpenAI 19 Sep AED 799 due to owner; Claude September '
       || coalesce('at ' || (select cost from c where cost is not null) || ' (receipt + FX and card to 6300), due to owner',
                   'waits for the sweep to book receipt #2830-8951-2948; the hourly duty then restates it to 799')
end as verdict;
