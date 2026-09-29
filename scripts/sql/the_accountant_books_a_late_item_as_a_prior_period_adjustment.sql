-- THE ACCOUNTANT BOOKS A LATE ITEM AS A PRIOR-PERIOD ADJUSTMENT — accountant, 29 Sep 2026.
-- Review blocker on #1063 (the founder's close pack by the 5th).
--
-- WHAT WAS WRONG (measured 29 Sep 2026 on htdblwldjkcgjvmqkbeh):
--   * a05_gl_period_lock (#1013) refuses any posted journal dated in a month that has an accountant_month_close row,
--     and no posting routine sets app.period_reopen_reason.
--   * fn_accountant_month_close_tick closes the previous month on day 3 (gl_settings.month_close_day = 3) whether or
--     not its bank statement has arrived. The Mashreq statement arrives at month end or later: August's was received
--     14 Sep (bank_statement_intake, 22:02 UTC) and August was closed on 15 Sep. Its AED 199 maintenance fee is dated
--     in the statement's own month, so on a day-3 close every such fee lands in a month that is already closed.
--   * fn_accountant_book_bank_charges, fn_accountant_book_bank_credits and fn_accountant_owner_card_tick book line by
--     line with no per-line error handling: the first late line raised the lock's exception and failed the whole step,
--     on every tick, so nothing after it was booked either.
--
-- WHAT THIS BUILDS
--   1. THE CLOSE WAITS FOR THE STATEMENT. fn_accountant_statement_booked(month): a parsed Mashreq statement for the
--      month is in bank_statement_intake and every line of it that a booking routine would book - under that
--      routine's own sign and kind rules - has a live journal (a fee refund left as bank_charge, an unrecognised
--      credit or a line the founder ruled a loan is that routine's finding, never the close's). fn_accountant_month_close_status(
--      month, today) is the one place that decides not_due / waiting_for_statement / due / closed, and the date the
--      close is due by: the 5th, or two days after the statement arrived when it arrived later. The close tick closes
--      only a month that is 'due'; the day-5 check and the founder's close pack report a month waiting for its
--      statement as WAITING (routine), never as missed.
--   2. A LATE ITEM IS A PRIOR-PERIOD ADJUSTMENT IN THE OPEN PERIOD. fn_gl_post is the one path every posting takes
--      (fn_gl_entry calls it; so do the charges, credits, owner-card, expense and Stripe-fee routines). When the
--      journal is dated in a closed month and no app.period_reopen_reason is set, it re-dates the journal into the
--      earliest month after it that is still open (today, or that month's last day when it is an earlier month), puts
--      the original date and, for a bank line, the statement line in the memo, and records the item in
--      public.gl_prior_period_adjustment. IFRS for SMEs Section 10 restates prior periods only for a MATERIAL error;
--      an immaterial one (a monthly bank fee) is corrected in the current period, which is what this does. The close
--      pack of the month it lands in lists it (the close-pack file reads gl_prior_period_adjustment).
--      The lock itself is unchanged: a journal INSERTED as posted, or a draft flipped to posted outside fn_gl_post,
--      dated in a closed month, is still refused.
--   3. ONE BAD LINE NEVER BLOCKS THE REST. Each line (each ruled-subscription month in the owner-card tick) books in
--      its own exception block; a line that fails becomes an accountant finding through fn_accountant_duty_settle
--      (acct:bank_charges:line:<id>, acct:bank_credits:line:<id>, acct:owner_card:entry:<id>), which closes itself
--      on the tick that books it.
--
-- Materiality is not gated here: every adjustment is listed in the close pack the founder reads, so a large one is
-- seen the month it lands. A threshold that refuses and asks for a restatement is added when one is ever needed.
--
-- Proved by scripts/sql/the_accountant_books_a_late_item_as_a_prior_period_adjustment_probe.sql (ZZ DEMO July and
-- August 2020, one rolled-back transaction, must print PROBE OK).

-- ── the adjustment register ─────────────────────────────────────────────────────────────────────
create table if not exists public.gl_prior_period_adjustment (
  journal_id        bigint primary key references public.gl_journal (id),
  original_date     date not null,
  closed_month      date not null check (closed_month = date_trunc('month', closed_month)::date),
  posted_on         date not null,
  source            text not null,
  source_ref        text,
  statement_line_id bigint references public.bank_statement_line (id),
  amount_aed        numeric(18,2) not null,
  created_at        timestamptz not null default now(),
  check (posted_on > original_date)
);
create index if not exists gl_prior_period_adjustment_posted_on on public.gl_prior_period_adjustment (posted_on);
alter table public.gl_prior_period_adjustment enable row level security;
drop policy if exists gl_prior_period_adjustment_service_role_only on public.gl_prior_period_adjustment;
create policy gl_prior_period_adjustment_service_role_only on public.gl_prior_period_adjustment
  as permissive for all to public using (false) with check (false);
revoke all on public.gl_prior_period_adjustment from anon, authenticated;
comment on table public.gl_prior_period_adjustment is
  'A journal dated in a closed month that fn_gl_post booked in the earliest open month instead (IFRS for SMEs Section 10: an immaterial prior-period item is corrected in the current period). original_date and statement_line_id name what it was; the close pack of the month it was posted in lists it.';

-- ── where a date lands ──────────────────────────────────────────────────────────────────────────
create or replace function public.fn_gl_open_period_date(p_date date)
returns date language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_m date := date_trunc('month', p_date)::date; v_today date := (now() at time zone 'Asia/Dubai')::date; v_open date;
begin
  if p_date is null or not exists (select 1 from public.accountant_month_close where month = v_m) then
    return p_date;
  end if;
  select min(g)::date into v_open
    from generate_series(v_m + interval '1 month', date_trunc('month', greatest(v_today, p_date)), interval '1 month') g
   where not exists (select 1 from public.accountant_month_close c where c.month = g::date);
  if v_open is null then
    -- fn_accountant_month_close refuses a month that has not ended, so the current month is always open
    raise exception 'no open period after %: every month up to today is closed', to_char(v_m, 'YYYY-MM');
  end if;
  return least(v_today, (v_open + interval '1 month' - interval '1 day')::date);
end $fn$;
revoke execute on function public.fn_gl_open_period_date(date) from public, anon, authenticated;
comment on function public.fn_gl_open_period_date(date) is
  'The date a journal dated p_date is booked on: p_date when its month is open; otherwise today, or the last day of the earliest open month after it when that month is earlier than today''s.';

-- ── the one posting path: a late item is re-dated into the open period ──────────────────────────
create or replace function public.fn_gl_post(p_journal bigint)
returns bigint language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare d numeric(18,2); c numeric(18,2); n int; j public.gl_journal; v_open date; v_line bigint;
begin
  select * into j from public.gl_journal where id = p_journal for update;
  if j.id is null then raise exception 'journal % not found', p_journal; end if;
  if j.status is distinct from 'draft' then
    raise exception 'journal % is %; only a draft can be posted (a posted journal is corrected with fn_gl_reverse, and a void one is terminal)', p_journal, j.status;
  end if;
  select coalesce(sum(debit),0), coalesce(sum(credit),0), count(*) into d,c,n from public.gl_journal_lines where journal_id=p_journal;
  if n < 2 then raise exception 'journal % needs at least 2 lines', p_journal; end if;
  if d <> c then raise exception 'journal % out of balance: debits % <> credits %', p_journal, to_char(d,'FM999999990.00'), to_char(c,'FM999999990.00'); end if;
  if d = 0 then raise exception 'journal % has zero amount', p_journal; end if;

  -- A deliberate reopen (app.period_reopen_reason, the lock's own audit trail) keeps the original date.
  v_open := case when coalesce(current_setting('app.period_reopen_reason', true), '') = ''
                 then public.fn_gl_open_period_date(j.entry_date) else j.entry_date end;
  if v_open is distinct from j.entry_date then
    if j.source in ('bank_charge', 'bank_interest', 'owner_capital') and j.source_ref ~ '^[0-9]+$' then
      select b.id into v_line from public.bank_statement_line b where b.id = j.source_ref::bigint;
    end if;
    update public.gl_journal
       set entry_date = v_open,
           memo = 'Prior-period adjustment: originally dated ' || j.entry_date || ' in the closed period '
                  || to_char(j.entry_date, 'YYYY-MM') || coalesce(', statement line ' || v_line, '') || '. ' || coalesce(j.memo, '')
     where id = p_journal;
  end if;

  update public.gl_journal
     set status='posted', posted_at=now(),
         entry_no = coalesce(entry_no, 'JE-'||lpad(p_journal::text,6,'0'))
   where id=p_journal;

  if v_open is distinct from j.entry_date then
    insert into public.gl_prior_period_adjustment (journal_id, original_date, closed_month, posted_on, source, source_ref, statement_line_id, amount_aed)
    values (p_journal, j.entry_date, date_trunc('month', j.entry_date)::date, v_open, j.source, j.source_ref, v_line, d);
  end if;
  return p_journal;
end $fn$;

-- ── 1. the close waits for the month's Mashreq statement ────────────────────────────────────────
create or replace function public.fn_accountant_statement_booked(p_month date)
returns jsonb language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_m date := date_trunc('month', p_month)::date; i record; v_unbooked jsonb;
begin
  select * into i from public.bank_statement_intake
   where account = 'mashreq' and statement_month = v_m and state = 'parsed'
   order by received_at limit 1;
  if i.source_ref is null then
    return jsonb_build_object('month', to_char(v_m, 'YYYY-MM'), 'booked', false,
      'reason', 'no readable Mashreq statement for ' || to_char(v_m, 'YYYY-MM') || ' has been received (the founder forwards it monthly)');
  end if;
  -- A line counts only when a booking routine WOULD book it, under the same sign and kind rules:
  -- fn_accountant_book_bank_charges takes a debit of kind bank_charge; fn_accountant_book_bank_credits takes a
  -- credit that is no Stripe payout and not ruled a loan, as owner capital (ruled capital, or kind owner_transfer)
  -- or bank interest. Anything else (a fee refund left as bank_charge, an unrecognised credit) is that routine's
  -- finding, and never holds the close at waiting_for_statement (re-review of #1063).
  select coalesce(jsonb_agg(jsonb_build_object('line_id', b.id, 'value_date', b.value_date, 'amount_aed', b.amount_aed, 'kind', b.kind,
                                               'books_as', x.src) order by b.value_date, b.id), '[]'::jsonb)
    into v_unbooked
    from public.bank_statement_line b
    left join public.bank_line_owner_ruling r on r.line_id = b.id
    cross join lateral (select case
             when b.amount_aed < 0 and b.kind = 'bank_charge' then 'bank_charge'
             when b.amount_aed > 0 and coalesce(r.ruling, '') <> 'loan'
                  and not exists (select 1 from public.stripe_payout p where p.bank_line_id = b.id) then
               case when r.ruling = 'capital' or b.kind = 'owner_transfer' then 'owner_capital'
                    when b.kind = 'bank_interest' then 'bank_interest' end
           end as src) x
   where b.account = 'mashreq'
     and b.source_ref in (select i2.source_ref from public.bank_statement_intake i2 where i2.account = 'mashreq' and i2.statement_month = v_m)
     and x.src is not null
     and not exists (select 1 from public.gl_journal g
                      where g.source_ref = b.id::text and g.status in ('draft', 'posted') and g.source = x.src);
  return jsonb_build_object('month', to_char(v_m, 'YYYY-MM'), 'booked', jsonb_array_length(v_unbooked) = 0,
    'statement', i.source_ref, 'received_at', i.received_at, 'unbooked_lines', v_unbooked,
    'reason', case when jsonb_array_length(v_unbooked) > 0
                   then jsonb_array_length(v_unbooked) || ' line(s) of the statement are not booked yet' end);
end $fn$;
revoke execute on function public.fn_accountant_statement_booked(date) from public, anon, authenticated;

create or replace function public.fn_accountant_month_close_status(p_month date, p_today date default null)
returns jsonb language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_m date := date_trunc('month', p_month)::date;
  v_today date := coalesce(p_today, (now() at time zone 'Asia/Dubai')::date);
  v_day int := coalesce((select num_value::int from public.gl_settings where key = 'month_close_day'), 3);
  v_stmt jsonb := public.fn_accountant_statement_booked(v_m);
  v_due_by date; v_closed timestamptz; v_status text;
begin
  -- The close is due by the 5th, or two days after the statement arrived when it arrived later.
  if (v_stmt->>'booked')::boolean then
    v_due_by := greatest((v_m + interval '1 month' + interval '4 days')::date,
                         ((v_stmt->>'received_at')::timestamptz at time zone 'Asia/Dubai')::date + 2);
  end if;
  select closed_at into v_closed from public.accountant_month_close where month = v_m;
  v_status := case when v_closed is not null then 'closed'
                   when v_today < (v_m + interval '1 month')::date + (v_day - 1) then 'not_due'
                   when not (v_stmt->>'booked')::boolean then 'waiting_for_statement'
                   else 'due' end;
  return jsonb_build_object('month', to_char(v_m, 'YYYY-MM'), 'status', v_status, 'due_by', v_due_by,
    'closed_at', v_closed, 'statement', v_stmt,
    'late', case when v_status = 'closed' then v_due_by is not null and (v_closed at time zone 'Asia/Dubai')::date > v_due_by
                 when v_status = 'due' then v_today > v_due_by
                 else false end);
end $fn$;
revoke execute on function public.fn_accountant_month_close_status(date, date) from public, anon, authenticated;
comment on function public.fn_accountant_month_close_status(date, date) is
  'not_due (before gl_settings.month_close_day) / waiting_for_statement (no booked Mashreq statement for the month) / due / closed, and the date the close is due by: the 5th, or two days after the statement arrived when later. late is true only for a due or closed month past that date; a month waiting for its statement is never late.';

create or replace function public.fn_accountant_month_close_tick()
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_prev date := (date_trunc('month', (now() at time zone 'Asia/Dubai')::date) - interval '1 month')::date; v_s jsonb;
begin
  v_s := public.fn_accountant_month_close_status(v_prev);
  if v_s->>'status' <> 'due' then
    return jsonb_build_object('closed', false, 'month', v_s->>'month', 'status', v_s->>'status',
      'waiting_for', case when v_s->>'status' = 'waiting_for_statement' then v_s#>>'{statement,reason}' end,
      'pending_render', (select count(*) from public.accountant_month_close where rendered_at is null));
  end if;
  return public.fn_accountant_month_close(v_prev) || jsonb_build_object('closed', true, 'status', 'closed');
end $fn$;

create or replace function public.fn_accountant_close_by_day_5()
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_local date := (now() at time zone 'Asia/Dubai')::date; v_prev date; v_tick jsonb; v_s jsonb; v_rep jsonb;
begin
  v_prev := (date_trunc('month', v_local) - interval '1 month')::date;
  v_tick := public.fn_accountant_month_close_tick();       -- the close itself runs here too, not only inside the runtime
  v_s := public.fn_accountant_month_close_status(v_prev, v_local);
  if v_s->>'status' = 'waiting_for_statement' and extract(day from v_local) > 5 then
    v_rep := public.fn_support_report_to_ceo(
      p_idempotency_key => 'accountant_close_waiting:' || to_char(v_prev, 'YYYY-MM'), p_severity => 'routine',
      p_subject => 'The ' || to_char(v_prev, 'Mon YYYY') || ' close is waiting for the Mashreq statement',
      p_evidence => jsonb_build_object('month', to_char(v_prev, 'YYYY-MM'), 'statement', v_s->'statement'),
      p_attempted => '[]'::jsonb,
      p_requested => 'None: the founder forwards the statement monthly; the accountant books it and closes the month within two days of its arrival.',
      p_review_in => interval '30 days', p_source_agent => 'accountant');
  elsif (v_s->>'late')::boolean then
    v_rep := public.fn_support_report_to_ceo(
      p_idempotency_key => 'accountant_close_day5:' || to_char(v_prev, 'YYYY-MM'), p_severity => 'elevated',
      p_subject => 'The ' || to_char(v_prev, 'Mon YYYY') || ' close ' || case when v_s->>'status' = 'closed' then 'was late' else 'is not done' end
                   || ' (due by ' || (v_s->>'due_by') || ')',
      p_evidence => jsonb_build_object('month', to_char(v_prev, 'YYYY-MM'), 'status', v_s, 'tick', v_tick),
      p_attempted => '[]'::jsonb, p_requested => 'None: the accountant closes it on this tick; this records the missed target.',
      p_review_in => interval '30 days', p_source_agent => 'accountant');
  end if;
  return jsonb_build_object('month', to_char(v_prev, 'YYYY-MM'), 'status', v_s->>'status', 'due_by', v_s->'due_by',
    'closed_at', v_s->'closed_at', 'closed_by_day_5', v_s->>'status' = 'closed' and not (v_s->>'late')::boolean,
    'late', (v_s->>'late')::boolean, 'tick', v_tick);
end $fn$;

-- ── 3. one bad line never blocks the rest ───────────────────────────────────────────────────────
create or replace function public.fn_accountant_book_bank_charges()
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_hold boolean := coalesce((select num_value from public.gl_settings where key = 'bank_booking_on_hold'), 1) <> 0;
  l record; v_lines jsonb; v_memo text; n_posted int := 0; n_draft int := 0; n_failed int := 0; v_items jsonb := '[]'::jsonb;
begin
  for l in select * from public.bank_statement_line b
            where b.amount_aed < 0 and b.kind = 'bank_charge'
              and not exists (select 1 from public.gl_journal g where g.source = 'bank_charge' and g.source_ref = b.id::text)
            order by b.value_date, b.id loop
    v_lines := jsonb_build_array(jsonb_build_object('account', '6300', 'debit', abs(l.amount_aed)),
                                 jsonb_build_object('account', '1000', 'credit', abs(l.amount_aed)));
    v_memo := case when l.account = 'zz_demo' then 'ZZ DEMO ' else '' end || 'Bank charge (' || l.account || ', ' || l.value_date || '): ' || left(public.fn_mask_bank_text(l.description), 120);
    begin
      if v_hold or l.account = 'zz_demo' then
        perform public.fn_accountant_draft_entry(l.value_date, v_memo, 'bank_charge', l.id::text, v_lines);
        n_draft := n_draft + 1;
      else
        perform public.fn_gl_entry(l.value_date, v_memo, 'bank_charge', l.id::text, v_lines, 'accountant');
        n_posted := n_posted + 1;
      end if;
    exception when others then
      n_failed := n_failed + 1;
      v_items := v_items || jsonb_build_object('item', 'line:' || l.id, 'owner_seat', 'accountant', 'subject', 'bank_statement_line',
        'title', 'The bank charge of AED ' || abs(l.amount_aed) || ' on ' || l.value_date || ' (statement line ' || l.id || ') could not be booked: ' || left(sqlerrm, 200),
        'blast', 'agent_facing', 'affected', 1, 'demo', l.account = 'zz_demo',
        'evidence', jsonb_build_object('line_id', l.id, 'source_ref', l.source_ref, 'error', left(sqlerrm, 600)));
    end;
  end loop;
  return jsonb_build_object('posted', n_posted, 'drafted', n_draft, 'failed', n_failed, 'hold', v_hold,
    'drafts_waiting', (select count(*) from public.gl_journal where source = 'bank_charge' and status = 'draft'),
    'drafts_waiting_aed', (select coalesce(sum(jl.debit), 0) from public.gl_journal g join public.gl_journal_lines jl on jl.journal_id = g.id
                            where g.source = 'bank_charge' and g.status = 'draft'),
    'findings', public.fn_accountant_duty_settle('bank_charges', v_items),
    'basis', case when v_hold then 'gl_settings.bank_booking_on_hold = 1 (the founder''s 9 Sep 2026 instruction): bank charges are prepared as drafts and reported, not posted.'
                  else 'bank_booking_on_hold = 0: bank charges posted to 6300 against 1000.' end);
end $fn$;

create or replace function public.fn_accountant_book_bank_credits()
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_hold boolean := coalesce((select num_value from public.gl_settings where key = 'bank_booking_on_hold'), 1) <> 0;
  v_after int := coalesce((select num_value::int from public.gl_settings where key = 'bank_match_days_after'), 5);
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  l record; v_lines jsonb; v_memo text; v_src text; v_booked boolean;
  n_posted int := 0; n_draft int := 0; n_raced int := 0; n_failed int := 0; v_items jsonb := '[]'::jsonb;
begin
  -- WHAT A CREDIT IS comes from bank_statement_line.kind, REASONED by the accountant runtime (reasoned_books.ts
  -- bankLineKind) or ruled by the founder (bank_line_owner_ruling). No description is read here.
  for l in select b.*, r.ruling, r.founder_instruction_id
             from public.bank_statement_line b left join public.bank_line_owner_ruling r on r.line_id = b.id
            where b.amount_aed > 0
              and not exists (select 1 from public.stripe_payout p where p.bank_line_id = b.id)
            order by b.value_date, b.id loop
    v_booked := exists (select 1 from public.gl_journal g where g.source in ('owner_capital', 'bank_interest')
                          and g.source_ref = l.id::text and g.status in ('draft', 'posted'));
    if l.ruling = 'loan' then
      v_items := v_items || jsonb_build_object('item', 'loan:' || l.id, 'owner_seat', 'accountant', 'subject', 'bank_statement_line',
        'title', 'A credit of AED ' || l.amount_aed || ' on ' || l.value_date || ' was ruled a loan from the founder, and the chart has no owner-loan account'
                 || case when v_booked then '; the entry already made for it must be reversed' else '' end,
        'blast', 'agent_facing', 'affected', 1, 'demo', l.account = 'zz_demo',
        'evidence', jsonb_build_object('line_id', l.id, 'source_ref', l.source_ref, 'founder_instruction_id', l.founder_instruction_id));
      continue;
    end if;
    continue when v_booked;
    v_src := null;
    if l.ruling = 'capital' or l.kind = 'owner_transfer' then
      v_src := 'owner_capital';
      v_lines := jsonb_build_array(jsonb_build_object('account', '1000', 'debit', l.amount_aed),
                                   jsonb_build_object('account', '3000', 'credit', l.amount_aed));
      v_memo := 'Owner capital contribution (' || l.account || ', ' || l.value_date
                || '), a transfer from the licence holder''s own account: capital unless he says loan (founder_instruction 357): ' || left(public.fn_mask_bank_text(l.description), 120);
    elsif l.kind = 'bank_interest' then
      v_src := 'bank_interest';
      v_lines := jsonb_build_array(jsonb_build_object('account', '1000', 'debit', l.amount_aed),
                                   jsonb_build_object('account', '7000', 'credit', l.amount_aed));
      v_memo := 'Bank interest credited (' || l.account || ', ' || l.value_date || '): ' || left(public.fn_mask_bank_text(l.description), 120);
    elsif l.kind is null and l.value_date + v_after < v_today then
      -- Not yet reasoned (the model hold): not booked on a guess, and said out loud rather than left silent.
      v_items := v_items || jsonb_build_object('item', 'unreasoned:' || l.id, 'owner_seat', 'accountant', 'subject', 'bank_statement_line',
        'title', 'A credit of AED ' || l.amount_aed || ' on ' || l.value_date || ' has not been reasoned yet (the model is held), so it is not booked',
        'blast', 'agent_facing', 'affected', 1, 'demo', l.account = 'zz_demo',
        'evidence', jsonb_build_object('line_id', l.id, 'source_ref', l.source_ref,
                                       'remedy', 'it is reasoned the moment the hold lifts (reasoning_held_question, surface accountant.bank_line)'));
    elsif l.value_date + v_after < v_today then
      v_items := v_items || jsonb_build_object('item', 'unrecognised:' || l.id, 'owner_seat', 'accountant', 'subject', 'bank_statement_line',
        'title', 'A credit of AED ' || l.amount_aed || ' on ' || l.value_date || ' is neither a Stripe payout, a transfer from the licence holder''s own account nor the bank''s interest, so it is not booked',
        'blast', 'agent_facing', 'affected', 1, 'demo', l.account = 'zz_demo',
        'evidence', jsonb_build_object('line_id', l.id, 'source_ref', l.source_ref, 'description', left(public.fn_mask_bank_text(l.description), 200),
                                       'remedy', 'the founder names what it is; an owner transfer is recorded in bank_line_owner_ruling'));
    end if;
    continue when v_src is null;
    if l.account = 'zz_demo' then v_memo := 'ZZ DEMO ' || v_memo; end if;
    begin
      if v_hold or l.account = 'zz_demo' then
        perform public.fn_accountant_draft_entry(l.value_date, v_memo, v_src, l.id::text, v_lines);
        n_draft := n_draft + 1;
      else
        perform public.fn_gl_entry(l.value_date, v_memo, v_src, l.id::text, v_lines, 'accountant');
        n_posted := n_posted + 1;
      end if;
    exception
      when unique_violation then
        n_raced := n_raced + 1;        -- a concurrent run booked this line first: gl_journal_one_live_entry_per_bank_or_fee_line
      when others then
        n_failed := n_failed + 1;
        v_items := v_items || jsonb_build_object('item', 'line:' || l.id, 'owner_seat', 'accountant', 'subject', 'bank_statement_line',
          'title', 'The credit of AED ' || l.amount_aed || ' on ' || l.value_date || ' (statement line ' || l.id || ') could not be booked: ' || left(sqlerrm, 200),
          'blast', 'agent_facing', 'affected', 1, 'demo', l.account = 'zz_demo',
          'evidence', jsonb_build_object('line_id', l.id, 'source_ref', l.source_ref, 'error', left(sqlerrm, 600)));
    end;
  end loop;
  return jsonb_build_object('posted', n_posted, 'drafted', n_draft, 'booked_by_a_concurrent_run', n_raced, 'failed', n_failed, 'hold', v_hold,
    'findings', public.fn_accountant_duty_settle('bank_credits', v_items));
end $fn$;

create or replace function public.fn_accountant_owner_card_tick(p_as_of date default null)
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  s record; m date; v_exp date; e record; v_posted numeric(18,2); v_diff numeric(18,2); v_lines jsonb;
  v_booked jsonb := '[]'::jsonb; v_matched jsonb := '[]'::jsonb; v_items jsonb := '[]'::jsonb;
  v_missing jsonb; v_noline jsonb; v_odd jsonb := '[]'::jsonb; v_line bigint; v_failed jsonb := '[]'::jsonb;
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

      -- Each ruled month books in its own block: one that fails is a finding and the others still book.
      begin
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
      exception when others then
        v_failed := v_failed || jsonb_build_object('vendor', s.vendor, 'entry', e.id, 'month', to_char(m, 'YYYY-MM'));
        v_items := v_items || jsonb_build_object('item', 'entry:' || e.id, 'owner_seat', 'accountant', 'subject', 'gl_journal',
          'blast', 'internal', 'affected', 1,
          'title', s.vendor || ' ' || to_char(m, 'Mon YYYY') || ' (expense entry ' || e.id || ') could not be restated at the bank value: ' || left(sqlerrm, 200),
          'evidence', jsonb_build_object('vendor', s.vendor, 'entry', e.id, 'charged_on', e.charged_on, 'error', left(sqlerrm, 600)));
      end;
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

  return jsonb_build_object('as_of', v_as_of, 'restated', v_booked, 'bank_lines_matched', v_matched, 'failed', v_failed,
    'findings', public.fn_accountant_duty_settle('owner_card', v_items));
end $fn$;
