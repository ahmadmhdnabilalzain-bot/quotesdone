-- A JOURNAL MEMO NEVER CARRIES A BANK OR IBAN NUMBER.
--
-- Assigned: accountant.
--
-- WHAT WAS MEASURED (15 Sep 2026, production htdblwldjkcgjvmqkbeh): the bank booking routines copied
-- Mashreq's full line description into gl_journal.memo. 7 of 66 journals carried an IBAN-shaped token
-- or a run of 8+ digits: 4 bank_charge, 1 bank_interest, 1 owner_capital (all posted 14 Sep 2026) and
-- 1 reversal. The founder's standing rule: the statement's account, IBAN and customer numbers are never
-- repeated in chat, code or commits. Journal memos reach the gl_ledger view, the year-end Ledger.csv
-- (fn_accountant_year_end_pack_document), the OS dashboard and the daily exports, so they may not
-- carry them either.
--
-- WHAT THIS DOES:
--   1. public.fn_mask_bank_text(text) is the ONE masking function. It replaces an IBAN (two letters,
--      two check digits, then 10-30 alphanumerics, compact or printed in groups of four) with [IBAN],
--      and any alphanumeric token holding 8 or more digits (account numbers, transfer and bank
--      reference numbers) with [ref]. Words, the counterparty name, the transaction type and dates
--      survive. It is idempotent: masking masked text changes nothing.
--   2. trg_gl_journal_memo_masked routes EVERY gl_journal memo write through it (bank bookings, the
--      draft writer, fn_gl_entry, fn_gl_reverse, which copies the original memo, and expenses), so no
--      writer can reintroduce the leak. The bank routines also mask before truncating, so a cut can
--      never leave half a number behind, and the unrecognised-credit finding's evidence is masked.
--   3. fn_gl_journal_immutable gains exactly one allowance: a posted journal's memo may change ONLY to
--      public.fn_mask_bank_text(old memo). Date, source, status and the lines stay immutable.
--   4. A one-off signed redaction of the rows already written, memo only, proved to leave every other
--      column untouched.
--   5. fn_accountant_bank_reconcile, the same leak in finding evidence: the nearest Stripe credits of a
--      missing payout and an unexplained Stripe credit carried the raw bank description and reference.
--      Both now go through fn_mask_bank_text. Measured 15 Sep 2026: 0 findings carried one yet.
-- bank_statement_line.description stays raw on purpose: it is the private source record, and the PDF
-- is archived anyway. The classifiers keep reading it.
-- These two routines were canonical in the_companys_own_bank_and_stripe_costs_book_themselves.sql;
-- that file is NOT re-applied because two of its other routines are redefined by later files.
-- Check: scripts/checks/a_journal_memo_never_carries_a_bank_number.test.mjs.
--
--   node scripts/apply_sql.mjs scripts/sql/a_journal_memo_never_carries_a_bank_or_iban_number.sql --apply --ddl

-- ── 1. THE ONE MASKING FUNCTION ───────────────────────────────────────────────────────────────────
create or replace function public.fn_mask_bank_text(p text)
returns text language plpgsql immutable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v text := p;
begin
  if v is null then return null; end if;
  -- An IBAN printed in groups of four, then a compact one.
  v := regexp_replace(v, '\m[A-Z]{2}[0-9]{2} [A-Z0-9]{4}( [0-9]{4}){2,6}( [0-9]{1,4})?\M', '[IBAN]', 'g');
  v := regexp_replace(v, '\m[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}\M', '[IBAN]', 'g');
  -- Any alphanumeric token holding 8+ digits, in ONE positional pass. The lookahead holds at a token's
  -- first character exactly when the token has 8+ digits, and the match then runs to the token's end.
  -- (Review of #684: a per-token text replace let one overlapping token rewrite another first and
  -- leaked 9 digits.) A date splits into short tokens and survives; output holds no digit run to re-mask.
  return regexp_replace(v, '(?=(?:[A-Za-z]*[0-9]){8})[A-Za-z0-9]+', '[ref]', 'g');
end $fn$;
revoke execute on function public.fn_mask_bank_text(text) from public, anon, authenticated;

-- ── 2. EVERY MEMO WRITE GOES THROUGH IT ───────────────────────────────────────────────────────────
create or replace function public.fn_gl_journal_memo_masked()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  new.memo := public.fn_mask_bank_text(new.memo);
  return new;
end $fn$;
revoke execute on function public.fn_gl_journal_memo_masked() from public, anon, authenticated;

drop trigger if exists trg_gl_journal_memo_masked on public.gl_journal;
create trigger trg_gl_journal_memo_masked before insert or update of memo on public.gl_journal
  for each row execute function public.fn_gl_journal_memo_masked();

-- ── 3. A POSTED JOURNAL IS IMMUTABLE: TWO NAMED EXITS, NOTHING ELSE ───────────────────────────────
-- Measured before (live since the migrations): the guard only fired when the UPDATE kept status
-- 'posted', so an UPDATE moving a posted journal to any other status (draft, or void without the
-- reversal link) made its date, source and memo rewritable (review of #684). A posted journal may now
-- only (a) stay posted with every column unchanged except its memo, replaced by exactly its own masked
-- form, or (b) become 'void' through fn_gl_reverse's own statement: status 'void' and the reversal link
-- set, every other column unchanged. Anything else, and every DELETE, is refused.
create or replace function public.fn_gl_journal_immutable()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_catalog' as $fn$
begin
  if old.status = 'posted' then
    if tg_op = 'UPDATE' and (
         (new.status = 'posted' and (to_jsonb(new) - 'memo') = (to_jsonb(old) - 'memo')
          and (new.memo is not distinct from old.memo or new.memo = public.fn_mask_bank_text(old.memo)))
      or (new.status = 'void' and new.reverses is not null
          and (to_jsonb(new) - 'status' - 'reverses') = (to_jsonb(old) - 'status' - 'reverses'))) then
      return new;
    end if;
    raise exception 'Posted journal % is immutable (reverse it instead)', old.id;
  end if;
  -- A void journal is terminal: fn_gl_reverse already set it void with its reversal link. Measured
  -- 15 Sep 2026: no routine or code path updates or deletes a void journal (the only writers are
  -- fn_gl_reverse's posted-to-void statement and fn_gl_post, which is only ever called on drafts).
  if old.status = 'void' then
    raise exception 'Void journal % is terminal: it was reversed and can never change again', old.id;
  end if;
  return case when tg_op='DELETE' then old else new end;
end $fn$;
revoke execute on function public.fn_gl_journal_immutable() from public, anon, authenticated;

-- ── 4. THE BANK ROUTINES MASK BEFORE THEY TRUNCATE ────────────────────────────────────────────────
-- Bodies as in the_companys_own_bank_and_stripe_costs_book_themselves.sql except the three
-- fn_mask_bank_text calls.
create or replace function public.fn_accountant_book_bank_charges()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_hold boolean := coalesce((select num_value from public.gl_settings where key = 'bank_booking_on_hold'), 1) <> 0;
  v_pat text := coalesce((select txt_value from public.gl_settings where key = 'bank_charge_pattern'), 'charge|fee');
  l record; v_lines jsonb; v_memo text; n_posted int := 0; n_draft int := 0;
begin
  for l in select * from public.bank_statement_line b
            where b.amount_aed < 0 and b.description ~* v_pat
              and not exists (select 1 from public.gl_journal g where g.source = 'bank_charge' and g.source_ref = b.id::text)
            order by b.value_date, b.id loop
    v_lines := jsonb_build_array(jsonb_build_object('account', '6300', 'debit', abs(l.amount_aed)),
                                 jsonb_build_object('account', '1000', 'credit', abs(l.amount_aed)));
    v_memo := case when l.account = 'zz_demo' then 'ZZ DEMO ' else '' end || 'Bank charge (' || l.account || ', ' || l.value_date || '): ' || left(public.fn_mask_bank_text(l.description), 120);
    if v_hold or l.account = 'zz_demo' then
      perform public.fn_accountant_draft_entry(l.value_date, v_memo, 'bank_charge', l.id::text, v_lines);
      n_draft := n_draft + 1;
    else
      perform public.fn_gl_entry(l.value_date, v_memo, 'bank_charge', l.id::text, v_lines, 'accountant');
      n_posted := n_posted + 1;
    end if;
  end loop;
  return jsonb_build_object('posted', n_posted, 'drafted', n_draft, 'hold', v_hold,
    'drafts_waiting', (select count(*) from public.gl_journal where source = 'bank_charge' and status = 'draft'),
    'drafts_waiting_aed', (select coalesce(sum(jl.debit), 0) from public.gl_journal g join public.gl_journal_lines jl on jl.journal_id = g.id
                            where g.source = 'bank_charge' and g.status = 'draft'),
    'basis', case when v_hold then 'gl_settings.bank_booking_on_hold = 1 (the founder''s 9 Sep 2026 instruction): bank charges are prepared as drafts and reported, not posted.'
                  else 'bank_booking_on_hold = 0: bank charges posted to 6300 against 1000.' end);
end $fn$;
revoke execute on function public.fn_accountant_book_bank_charges() from public, anon, authenticated;

create or replace function public.fn_accountant_book_bank_credits()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_hold boolean := coalesce((select num_value from public.gl_settings where key = 'bank_booking_on_hold'), 1) <> 0;
  v_after int := coalesce((select num_value::int from public.gl_settings where key = 'bank_match_days_after'), 5);
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_pat jsonb := '{}'::jsonb; k text; v text;
  l record; v_lines jsonb; v_memo text; v_src text; v_booked boolean;
  n_posted int := 0; n_draft int := 0; n_raced int := 0; v_items jsonb := '[]'::jsonb;
begin
  -- Each pattern validated once, in its own block: a bad one is a finding and its rule books nothing.
  foreach k in array array['owner_transfer_pattern', 'bank_interest_pattern', 'bank_interest_reference_pattern'] loop
    v := (select txt_value from public.gl_settings where key = k);
    begin
      if coalesce(btrim(v), '') = '' then raise exception 'the setting is missing or empty'; end if;
      perform ('' ~ v);
      v_pat := v_pat || jsonb_build_object(k, v);
    exception when others then
      v_items := v_items || jsonb_build_object('item', 'setting:' || k, 'owner_seat', 'accountant', 'subject', 'gl_settings',
        'title', 'gl_settings.' || k || ' is not a usable pattern (' || sqlerrm || '), so the rule it drives books nothing until it is corrected',
        'blast', 'agent_facing', 'affected', 1, 'evidence', jsonb_build_object('key', k, 'value', v));
    end;
  end loop;

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
    if l.ruling = 'capital' or (v_pat ? 'owner_transfer_pattern'
                                and public.fn_bank_line_is_owner_transfer(l.description, v_pat->>'owner_transfer_pattern')) then
      v_src := 'owner_capital';
      v_lines := jsonb_build_array(jsonb_build_object('account', '1000', 'debit', l.amount_aed),
                                   jsonb_build_object('account', '3000', 'credit', l.amount_aed));
      v_memo := 'Owner capital contribution (' || l.account || ', ' || l.value_date
                || '), a transfer from the licence holder''s own account: capital unless he says loan (founder_instruction 357): ' || left(public.fn_mask_bank_text(l.description), 120);
    elsif v_pat ? 'bank_interest_pattern' and v_pat ? 'bank_interest_reference_pattern'
          and l.description ~* (v_pat->>'bank_interest_pattern') and l.description ~ (v_pat->>'bank_interest_reference_pattern') then
      v_src := 'bank_interest';
      v_lines := jsonb_build_array(jsonb_build_object('account', '1000', 'debit', l.amount_aed),
                                   jsonb_build_object('account', '7000', 'credit', l.amount_aed));
      v_memo := 'Bank interest credited (' || l.account || ', ' || l.value_date || '): ' || left(public.fn_mask_bank_text(l.description), 120);
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
    exception when unique_violation then
      n_raced := n_raced + 1;        -- a concurrent run booked this line first: gl_journal_one_live_entry_per_bank_or_fee_line
    end;
  end loop;
  return jsonb_build_object('posted', n_posted, 'drafted', n_draft, 'booked_by_a_concurrent_run', n_raced, 'hold', v_hold,
    'findings', public.fn_accountant_duty_settle('bank_credits', v_items));
end $fn$;
revoke execute on function public.fn_accountant_book_bank_credits() from public, anon, authenticated;

-- ── 4b. THE RECONCILIATION'S FINDING EVIDENCE IS MASKED TOO ───────────────────────────────────────
-- Body as in the_accountant_matches_every_stripe_payout_to_the_bank.sql except the two evidence spots.
create or replace function public.fn_accountant_bank_reconcile(p_as_of date default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  v_before int; v_after int; v_grace int; v_due_day int; v_demo_on boolean;
  p public.stripe_payout; l public.bank_statement_line; x record;
  v_items jsonb := '[]'::jsonb; n_matched int := 0; v_settle jsonb;
begin
  select num_value::int into v_before  from public.gl_settings where key = 'bank_match_days_before';
  select num_value::int into v_after   from public.gl_settings where key = 'bank_match_days_after';
  select num_value::int into v_grace   from public.gl_settings where key = 'payout_transit_grace_days';
  select num_value::int into v_due_day from public.gl_settings where key = 'bank_statement_due_day';
  if v_before is null or v_after is null or v_grace is null or v_due_day is null then
    raise exception 'fn_accountant_bank_reconcile: a bank_* or payout_* window is missing from gl_settings';
  end if;
  -- Test-mode payouts are reconciled only while a ZZ DEMO statement exists (a probe or a rehearsal).
  v_demo_on := exists (select 1 from public.bank_statement_intake where account = 'zz_demo');

  -- MATCH: a paid payout to the nearest unmatched bank credit of exactly its amount inside the window,
  -- a line that names Stripe preferred.
  for p in select * from public.stripe_payout s
            where s.bank_line_id is null and s.status = 'paid' and s.currency = 'aed' and (s.livemode or v_demo_on)
            order by s.arrival_date loop
    select bl.* into l from public.bank_statement_line bl
     where ((p.livemode and bl.account <> 'zz_demo') or (not p.livemode and bl.account = 'zz_demo'))
       and bl.amount_aed = round(p.amount_fils / 100.0, 2)
       and bl.value_date between p.arrival_date - v_before and p.arrival_date + v_after
       and not exists (select 1 from public.stripe_payout q where q.bank_line_id = bl.id)
     order by (bl.description ilike '%stripe%') desc, abs(bl.value_date - p.arrival_date), bl.id
     limit 1;
    if found then
      update public.stripe_payout set bank_line_id = l.id, matched_at = now() where id = p.id;
      n_matched := n_matched + 1;
    end if;
  end loop;

  for p in select * from public.stripe_payout s where (s.livemode or v_demo_on) loop
    -- Stripe says the money did not go.
    if p.status in ('failed', 'canceled') then
      v_items := v_items || jsonb_build_object('item', 'failed:' || p.id, 'owner_seat', 'accountant', 'subject', 'stripe_payout',
        'title', 'Stripe payout ' || p.id || ' of AED ' || round(p.amount_fils / 100.0, 2) || ' ' || p.status
                 || coalesce(' (' || p.failure_code || ')', '') || ': the money did not reach the bank',
        'blast', 'agent_facing', 'affected', 1, 'demo', not p.livemode, 'evidence', to_jsonb(p));
    -- Still travelling well after the date Stripe gave.
    elsif p.status in ('pending', 'in_transit') and p.arrival_date + v_grace < v_as_of then
      v_items := v_items || jsonb_build_object('item', 'transit:' || p.id, 'owner_seat', 'accountant', 'subject', 'stripe_payout',
        'title', 'Stripe payout ' || p.id || ' of AED ' || round(p.amount_fils / 100.0, 2) || ' was due in the bank on '
                 || p.arrival_date || ' and still reads ' || p.status,
        'blast', 'agent_facing', 'affected', 1, 'demo', not p.livemode, 'evidence', to_jsonb(p));
    end if;
    -- The payout does not add up to the balance transactions it carries.
    if p.txn_net_fils is not null and p.txn_net_fils <> p.amount_fils then
      v_items := v_items || jsonb_build_object('item', 'breakdown:' || p.id, 'owner_seat', 'accountant', 'subject', 'stripe_payout',
        'title', 'Stripe payout ' || p.id || ' is AED ' || round(p.amount_fils / 100.0, 2) || ' but its ' || coalesce(p.txn_count, 0)
                 || ' balance transaction(s) net to AED ' || round(p.txn_net_fils / 100.0, 2),
        'blast', 'agent_facing', 'affected', 1, 'demo', not p.livemode, 'evidence', to_jsonb(p));
    end if;
    if p.currency <> 'aed' then
      v_items := v_items || jsonb_build_object('item', 'currency:' || p.id, 'owner_seat', 'accountant', 'subject', 'stripe_payout',
        'title', 'Stripe payout ' || p.id || ' is in ' || upper(p.currency) || ', and the Mashreq account is reconciled in AED',
        'blast', 'agent_facing', 'affected', 1, 'demo', not p.livemode, 'evidence', to_jsonb(p));
    end if;
    -- Paid, unmatched, and a statement already runs past the end of its window: missing from the bank.
    if p.status = 'paid' and p.bank_line_id is null and p.currency = 'aed'
       and exists (select 1 from public.bank_statement_line bl
                    where ((p.livemode and bl.account <> 'zz_demo') or (not p.livemode and bl.account = 'zz_demo'))
                      and bl.value_date >= p.arrival_date + v_after) then
      v_items := v_items || jsonb_build_object('item', 'missing:' || p.id, 'owner_seat', 'accountant', 'subject', 'stripe_payout',
        'title', 'Stripe paid out AED ' || round(p.amount_fils / 100.0, 2) || ' (' || p.id || ') for ' || p.arrival_date
                 || ' and the bank statement shows no credit of that amount between ' || (p.arrival_date - v_before)
                 || ' and ' || (p.arrival_date + v_after),
        'blast', 'agent_facing', 'affected', 1, 'demo', not p.livemode,
        'evidence', to_jsonb(p) || jsonb_build_object('nearest_stripe_credits', (
          select coalesce(jsonb_agg(jsonb_build_object('line', bl.id, 'value_date', bl.value_date, 'amount_aed', bl.amount_aed,
                                                       'description', public.fn_mask_bank_text(bl.description)) order by abs(bl.value_date - p.arrival_date)), '[]'::jsonb)
            from (select * from public.bank_statement_line b2
                   where ((p.livemode and b2.account <> 'zz_demo') or (not p.livemode and b2.account = 'zz_demo'))
                     and b2.amount_aed > 0 and b2.value_date between p.arrival_date - v_before and p.arrival_date + v_after
                   limit 5) bl)));
    end if;
  end loop;

  -- A month with live payouts whose statement has not arrived by the due day of the next month.
  for x in select date_trunc('month', s.arrival_date)::date mo, count(*) n, sum(s.amount_fils) fils
             from public.stripe_payout s where s.livemode and s.status = 'paid'
            group by 1 loop
    if v_as_of > (x.mo + interval '1 month')::date + (v_due_day - 1)
       and not exists (select 1 from public.bank_statement_line bl
                        where bl.account <> 'zz_demo' and bl.value_date >= (x.mo + interval '1 month' - interval '1 day')::date) then
      v_items := v_items || jsonb_build_object('item', 'statement:' || to_char(x.mo, 'YYYY-MM'), 'owner_seat', 'accountant',
        'subject', 'bank_statement',
        'title', 'The Mashreq statement for ' || to_char(x.mo, 'Mon YYYY') || ' has not reached the accountant, so '
                 || x.n || ' Stripe payout(s) totalling AED ' || round(x.fils / 100.0, 2) || ' cannot be confirmed in the bank',
        'blast', 'agent_facing', 'affected', 0,
        'evidence', jsonb_build_object('month', x.mo, 'payouts', x.n, 'amount_aed', round(x.fils / 100.0, 2),
                                       'remedy', 'forward the statement (PDF or CSV export) to expenses@mail.quotesdone.com'));
    end if;
  end loop;

  -- A statement that arrived and could not be read.
  for x in select * from public.bank_statement_intake i where i.state = 'unreadable' and (i.account <> 'zz_demo' or v_demo_on) loop
    v_items := v_items || jsonb_build_object('item', 'unreadable:' || x.source_ref, 'owner_seat', 'accountant', 'subject', 'bank_statement',
      'title', 'A ' || x.account || ' statement' || coalesce(' for ' || to_char(x.statement_month, 'Mon YYYY'), '')
               || ' arrived and no line could be read from it',
      'blast', 'agent_facing', 'affected', 0, 'demo', x.account = 'zz_demo',
      'evidence', jsonb_build_object('source_ref', x.source_ref, 'doc_path', x.doc_path, 'note', x.note,
                                     'remedy', 'forward the CSV export of the same statement, or ingest its lines through the accountant runtime''s bank_statement action'));
  end loop;

  -- Money from Stripe in the bank that no payout explains.
  for x in select bl.* from public.bank_statement_line bl
            where bl.amount_aed > 0 and bl.description ilike '%stripe%' and bl.value_date + v_after < v_as_of
              and (bl.account <> 'zz_demo' or v_demo_on)
              and not exists (select 1 from public.stripe_payout s where s.bank_line_id = bl.id) loop
    v_items := v_items || jsonb_build_object('item', 'unexplained:' || x.id, 'owner_seat', 'accountant', 'subject', 'bank_statement',
      'title', 'The bank shows a Stripe credit of AED ' || x.amount_aed || ' on ' || x.value_date || ' that no recorded payout explains',
      'blast', 'agent_facing', 'affected', 1, 'demo', x.account = 'zz_demo',
      'evidence', to_jsonb(x) || jsonb_build_object('description', public.fn_mask_bank_text(x.description),
                                                    'reference', public.fn_mask_bank_text(x.reference)));
  end loop;

  v_settle := public.fn_accountant_duty_settle('bank', v_items);
  return jsonb_build_object('as_of', v_as_of, 'matched_now', n_matched, 'findings', v_settle,
    'payouts', (select count(*) from public.stripe_payout where livemode),
    'payouts_matched', (select count(*) from public.stripe_payout where livemode and bank_line_id is not null),
    'statements', (select count(*) from public.bank_statement_intake where account <> 'zz_demo'),
    'basis', 'Stripe payouts (read from GET /v1/payouts) against Mashreq statement lines, amount exact, date within the gl_settings window. Nothing was posted to the ledger.');
end $fn$;
revoke execute on function public.fn_accountant_bank_reconcile(date) from public, anon, authenticated;

-- Probe for 4b. Running the reconciliation would settle real findings and can page, so this reads the
-- definition that is now live: both evidence spots call the mask, and no raw description is emitted.
do $probe_reconcile$
declare d text := pg_get_functiondef('public.fn_accountant_bank_reconcile(date)'::regprocedure);
begin
  if d !~ 'fn_mask_bank_text\(bl\.description\)' or d !~ 'fn_mask_bank_text\(x\.description\)'
     or d !~ 'fn_mask_bank_text\(x\.reference\)' then
    raise exception 'CHK<<fn_accountant_bank_reconcile does not mask the bank description and reference in its evidence>>'; end if;
  if d ~ '''description'', bl\.description' or d ~ '''evidence'', to_jsonb\(x\)\)' then
    raise exception 'CHK<<fn_accountant_bank_reconcile still emits a raw bank description>>'; end if;
  raise notice 'reconcile evidence probe passed';
end $probe_reconcile$;

-- ── 5. PROBE: an invented Mashreq-shaped line is masked; a posted memo still cannot be rewritten ───
-- DDL lives in this file, so the probe cleans up after itself: the journal part runs in a
-- sub-transaction that is always rolled back, and the absence of its rows is asserted afterwards.
do $probe$
declare
  v_line text := 'ZZ DEMO IPP TRANSFER - ZZ DEMO SENDER NAME - AE000000000000000000042 FT0000000042ZZ REF 000000000042 CIDZZAED 00042';
  v_spaced text := 'ZZ DEMO Monthly Maintenance Fee AE00 0000 0000 0000 0000 042 value 2026-08-31 GB00ZZZZ00000000000042';
  m text; s text; v_id bigint; v_draft bigint; v_stmt text;
begin
  m := public.fn_mask_bank_text(v_line);
  s := public.fn_mask_bank_text(v_spaced);
  if m ~ '[0-9]{8,}' or s ~ '[0-9]{8,}' or m ~ '[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}' or s ~ '[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}'
     or s ~ 'AE00 0000' then
    raise exception 'CHK<<fn_mask_bank_text left a bank number behind: % | %>>', m, s; end if;
  if m !~ 'IPP TRANSFER' or m !~ 'ZZ DEMO SENDER NAME' or m !~ 'CIDZZAED 00042'
     or s !~ 'Monthly Maintenance Fee' or s !~ '2026-08-31' then
    raise exception 'CHK<<fn_mask_bank_text removed words it must keep: % | %>>', m, s; end if;
  if public.fn_mask_bank_text(m) <> m or public.fn_mask_bank_text(s) <> s then
    raise exception 'CHK<<fn_mask_bank_text is not idempotent>>'; end if;
  -- Overlap shapes (review of #684): the reviewer's exact input, duplicates, a ref inside a longer
  -- token, adjacent tokens, letters between digits. No digit run of 8+ may survive, and masking twice
  -- changes nothing.
  if public.fn_mask_bank_text('90000000 090000000X99999999') <> '[ref] [ref]' then
    raise exception 'CHK<<the reviewer''s overlap input is not fully masked>>'; end if;
  if exists (select 1 from unnest(array[
        '90000000 090000000X99999999', '12345678 12345678 123456789', '00000042 ZZ00000042 00000042ZZ',
        'FT0000000042ZZ/00000000,00000000', '00000000000000000042X00000000', 'A1B2C3D4E5F6G7H8 a1b2c3d4e5f6g7h8',
        'AE000000000000000000042AE000000000000000000042', 'AE00 0000 0000 0000 0000 042 00000000',
        'REF:000000000042-000000000043', 'ZZ DEMO 2026-08-31 CIDZZAED 00042 1234567']) x
        where public.fn_mask_bank_text(x) ~ '[0-9]{8,}'
           or public.fn_mask_bank_text(x) ~ '[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}'
           or public.fn_mask_bank_text(public.fn_mask_bank_text(x)) <> public.fn_mask_bank_text(x)) then
    raise exception 'CHK<<fn_mask_bank_text leaves a digit run or is not idempotent on an overlap shape>>'; end if;
  if public.fn_mask_bank_text('ZZ DEMO 2026-08-31 CIDZZAED 00042 1234567') <> 'ZZ DEMO 2026-08-31 CIDZZAED 00042 1234567' then
    raise exception 'CHK<<fn_mask_bank_text masked a date or a short number>>'; end if;

  begin
    v_id := public.fn_accountant_draft_entry(current_date, v_line, 'bank_charge', 'zz-demo-memo-mask-probe',
              '[{"account":"6300","debit":1},{"account":"1000","credit":1}]'::jsonb);
    if (select memo from public.gl_journal where id = v_id) is distinct from m then
      raise exception 'CHK<<a journal memo was stored unmasked>>'; end if;
    v_draft := v_id;
    insert into public.gl_journal (entry_date, memo, source, source_ref, created_by, status)
    values (current_date, 'ZZ DEMO posted', 'zz_demo', 'zz-demo-memo-mask-probe-posted', 'probe', 'posted') returning id into v_id;
    -- Every way out of 'posted' except the two named exits is refused (review of #684).
    foreach v_stmt in array array[
        'update public.gl_journal set memo = ''ZZ DEMO rewritten'' where id = $1',
        'update public.gl_journal set status = ''draft'' where id = $1',
        'update public.gl_journal set status = ''draft'', memo = ''ZZ DEMO rewritten'' where id = $1',
        'update public.gl_journal set status = ''void'' where id = $1',
        'update public.gl_journal set status = ''void'', reverses = $2, memo = ''ZZ DEMO rewritten'' where id = $1',
        'update public.gl_journal set entry_date = entry_date - 1 where id = $1',
        'update public.gl_journal set source_ref = ''zz-demo-memo-mask-probe-moved'' where id = $1',
        'delete from public.gl_journal where id = $1'] loop
      begin
        execute v_stmt using v_id, v_draft;
        raise exception 'CHK<<a posted journal accepted: %>>', v_stmt;
      exception when raise_exception then
        if sqlerrm like 'CHK<<%' then raise; end if;
      end;
    end loop;
    -- The reversal exit, as fn_gl_reverse writes it (status void and the link, nothing else), still works,
    -- so #682's reversal path is untouched.
    update public.gl_journal set status = 'void', reverses = v_draft where id = v_id;
    if (select status from public.gl_journal where id = v_id) <> 'void' then
      raise exception 'CHK<<the fn_gl_reverse void exit was refused>>'; end if;
    -- A void journal is terminal: nothing about it may change again.
    foreach v_stmt in array array[
        'update public.gl_journal set memo = ''ZZ DEMO rewritten'' where id = $1',
        'update public.gl_journal set status = ''posted'' where id = $1',
        'update public.gl_journal set status = ''draft'' where id = $1',
        'update public.gl_journal set reverses = null where id = $1',
        'update public.gl_journal set reverses = $1 where id = $1',
        'update public.gl_journal set entry_date = entry_date - 1 where id = $1',
        'update public.gl_journal set source = ''zz_demo_moved'' where id = $1',
        'update public.gl_journal set source_ref = ''zz-demo-memo-mask-probe-moved'' where id = $1',
        'delete from public.gl_journal where id = $1'] loop
      begin
        execute v_stmt using v_id;
        raise exception 'CHK<<a void journal accepted: %>>', v_stmt;
      exception when raise_exception then
        if sqlerrm like 'CHK<<%' then raise; end if;
      end;
    end loop;
    raise exception 'zz_probe_rollback';
  exception when others then
    if sqlerrm <> 'zz_probe_rollback' then raise; end if;
  end;
  if exists (select 1 from public.gl_journal where source_ref like 'zz-demo-memo-mask-probe%') then
    raise exception 'CHK<<the probe left a journal behind>>'; end if;
  raise notice 'memo mask probe passed';
end $probe$;

-- ── 6. ONE-OFF REDACTION OF THE ROWS ALREADY WRITTEN: memo only ───────────────────────────────────
do $redact$
declare
  n_before int; n_after int; n_changed int; v_other_before text; v_other_after text; v_lines_before text; v_lines_after text;
begin
  select count(*) into n_before from public.gl_journal where memo ~ '[0-9]{8,}' or memo ~ '[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}';
  select md5(string_agg(concat_ws('|', id, entry_date, status, source, source_ref), ',' order by id)) into v_other_before from public.gl_journal;
  select md5(string_agg(concat_ws('|', id, journal_id, line_no, account_code, debit, credit, memo), ',' order by id)) into v_lines_before from public.gl_journal_lines;

  update public.gl_journal set memo = public.fn_mask_bank_text(memo) where memo is distinct from public.fn_mask_bank_text(memo);
  get diagnostics n_changed = row_count;

  select count(*) into n_after from public.gl_journal where memo ~ '[0-9]{8,}' or memo ~ '[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}';
  select md5(string_agg(concat_ws('|', id, entry_date, status, source, source_ref), ',' order by id)) into v_other_after from public.gl_journal;
  select md5(string_agg(concat_ws('|', id, journal_id, line_no, account_code, debit, credit, memo), ',' order by id)) into v_lines_after from public.gl_journal_lines;
  if n_after <> 0 then raise exception 'CHK<<% journal memos still carry a bank number after the redaction>>', n_after; end if;
  if v_other_before <> v_other_after or v_lines_before <> v_lines_after then
    raise exception 'CHK<<the redaction changed something other than gl_journal.memo>>'; end if;
  raise notice 'memo redaction: % matching before, % rows changed, % matching after', n_before, n_changed, n_after;
end $redact$;
