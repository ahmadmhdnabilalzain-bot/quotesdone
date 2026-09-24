-- THE ACCOUNTANT RUNS ITS DUTIES EVERY HOUR, AND EACH ONE GOES ROUND THE LOOP.
--
-- Assigned: accountant. Founder, 14 Sep 2026: "yea add them all" (duties 1-8, duty 5 withdrawn: "just
-- ignore the corporate tax matter for companies") and "yea add them" (duties 9-11).
--
-- HOW IT RUNS. resilience_ping calls the accountant runtime (supabase/functions/accountant, action
-- 'duties') under the seat's own credential every tick. The runtime asks fn_accountant_duties_due, and
-- at most once in 55 minutes takes the readings only it can take — Stripe payouts, the balance
-- transactions behind them, Stripe's own fee and tax transactions, disputes, and the charge audit it
-- computes with _shared/reveal_fee.ts — then hands them here. Every duty is its own sub-transaction: one
-- that raises is REPORTED (fn_accountant_duty_stage makes it a finding) and does not stop the others.
--
--   1 bank          fn_accountant_payouts_record + fn_accountant_bank_reconcile     (bank file)
--   2 collections   fn_accountant_collections_tick                                   (collections file)
--   3 subscriptions fn_accountant_subscription_tick                                  (subscriptions file)
--   4 VAT           fn_accountant_vat_threshold_check — already called every tick by resilience_ping
--   6 expenses      fn_accountant_expense_duty                                       (expenses file)
--   7 disputes      fn_accountant_dispute_record + fn_accountant_disputes_tick       (disputes file)
--   8 close         fn_accountant_month_close_tick, the CEO's sweep and the completion (close file)
--   9 reserve       fn_accountant_refund_reserve — read by the close; nothing to run
--  10 charge audit  fn_accountant_charge_audit_record                                (charge audit file)
--  11 costs         fn_accountant_book_stripe_fees + fn_accountant_cost_booking_tick (costs file)
--  12 books         fn_accountant_books_duty: runs AFTER costs has posted, and says when the ledger is stale (this file)
--
-- The five further duties (founder, 14 Sep 2026: "add all for accountant and IT"):
--  F1 cash          fn_accountant_bank_balance_tick; the close carries the cash and runway   (cash file)
--  F2 ad spend      fn_accountant_ad_spend_tick -- HELD since 22 Sep 2026, rule 641 (Meta invoice file)
--  F3 recovery      fn_accountant_recovery_tick                                  (recovery ledger file)
--  F4 year end      fn_accountant_year_end_tick; the runtime writes the pack      (year-end file)
--  F5 renewals      fn_accountant_renewals_tick; renewal.due from the it_engineer (renewals file)
--
--   node scripts/apply_sql.mjs scripts/sql/the_accountant_runs_its_duties_every_hour.sql --apply --ddl

create or replace function public.fn_accountant_duties_due()
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select not exists (select 1 from public.agent_runs where agent = 'accountant' and counts->>'job' = 'duties'
                      and status = 'ok' and started_at > now() - interval '55 minutes')
$fn$;
revoke execute on function public.fn_accountant_duties_due() from public, anon, authenticated;

-- 12 BOOKS (23 Sep 2026, accountant). The readiness audit read "the last journal is 15 Sep" as posting
-- having stopped. Measured the same day, it had not: Resend's inbound history (13 messages back to 27 Aug)
-- held nothing for expenses@ after 15 Sep 22:12 UTC, every message it did hold was booked (the 10 Sep
-- Vercel forward was a second copy of #2293-8940, deduped on its economic identity), and 0 expense
-- entries were unposted. Nothing had been forwarded. What was missing is that a quiet ledger said nothing
-- at all, so "no receipts arrived" and "receipts arrived and were not posted" looked the same from
-- outside. This duty runs after costs (which posts, via fn_gl_sync_business) and raises ONE finding when
-- the newest posted journal is older than gl_settings.books_stale_after_days, naming which of the two it is.
insert into public.gl_settings (key, num_value, txt_value) values ('books_stale_after_days', 2,
  'Days after which a ledger with no new posted journal is a finding (accountant duty 12, fn_accountant_books_duty).')
on conflict (key) do nothing;

create or replace function public.fn_accountant_books_duty(p_as_of date default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  v_after int := (select num_value::int from public.gl_settings where key = 'books_stale_after_days');
  v_last date; v_last_at timestamptz; v_mail timestamptz; n_arrived int; n_unbooked int; n_unposted int;
  v_cause text; v_items jsonb := '[]'::jsonb;
begin
  if v_after is null then raise exception 'fn_accountant_books_duty: gl_settings.books_stale_after_days is missing'; end if;
  select max(entry_date), max(posted_at) into v_last, v_last_at from public.gl_journal
   where status = 'posted' and memo !~* 'zz[ _-]?demo';
  select max(created_at) into v_mail from public.inbound_messages where to_email ilike 'expenses@%';
  -- What reached the mailbox since the last posting, and what of it has no entry and no statement behind it.
  select count(*), count(*) filter (where not exists (select 1 from public.expense_entries e where e.source_msg_id = 'resend:' || m.provider_email_id)
                                      and not exists (select 1 from public.bank_statement_intake b where b.source_ref = 'resend:' || m.provider_email_id))
    into n_arrived, n_unbooked
    from public.inbound_messages m
   where m.to_email ilike 'expenses@%' and m.created_at > coalesce(v_last_at, '-infinity') and m.created_at < now() - interval '2 hours';
  select count(*) into n_unposted from public.expense_entries e
   where not exists (select 1 from public.gl_journal g where g.source = 'expense' and g.source_ref = e.id::text)
     and not ((coalesce(e.vendor, '') || ' ' || coalesce(e.note, '')) ~* 'zz[ _-]?demo');

  if v_last is null or v_as_of - v_last > v_after then
    v_cause := case
      when n_unposted > 0 then n_unposted || ' booked expense(s) have no journal: posting is failing'
      when n_unbooked > 0 then n_unbooked || ' message(s) reached the expenses mailbox and were neither booked nor held as a statement'
      else 'nothing has reached the expenses mailbox since ' || coalesce(to_char(v_mail at time zone 'Asia/Dubai', 'DD Mon YYYY'), 'ever')
           || ', so there was nothing to post; the vendor-side gaps are in the expenses duty' end;
    v_items := jsonb_build_array(jsonb_build_object('item', 'books_stale', 'owner_seat', 'accountant', 'subject', 'gl_journal',
      'title', 'The books are ' || coalesce((v_as_of - v_last)::text, 'never') || ' day(s) stale (last posted journal '
               || coalesce(v_last::text, 'none') || '): ' || v_cause,
      'blast', 'internal', 'affected', 1,
      'evidence', jsonb_build_object('last_posted_journal', v_last, 'last_posted_at', v_last_at, 'stale_after_days', v_after,
        'last_expenses_mail', v_mail, 'mail_since_last_posting', n_arrived, 'mail_not_booked', n_unbooked,
        'entries_not_posted', n_unposted,
        'remedy', case when n_unposted + n_unbooked > 0
                       then 'run the accountant expense_sweep for the named message, then fn_gl_sync_business; read the stage finding if it raises'
                       else 'forward the month''s receipts to expenses@mail.quotesdone.com; nothing is broken on this side' end)));
  end if;
  return jsonb_build_object('as_of', v_as_of, 'last_posted_journal', v_last, 'mail_not_booked', n_unbooked,
    'entries_not_posted', n_unposted, 'findings', public.fn_accountant_duty_settle('books', v_items));
end $fn$;
revoke execute on function public.fn_accountant_books_duty(date) from public, anon, authenticated;

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

  foreach v_step in array array['stripe', 'bank', 'collections', 'subscriptions', 'expenses', 'charge_audit', 'disputes', 'costs', 'books',
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
