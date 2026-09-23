-- THE BOOKS AND THE KNOWLEDGE ARE READ BY MEANING, NOT BY WORDS — decision points 63-71, batch 8.
-- Seats: accountant (the books: points 63-66), marketing (67, the SQL side of the LinkedIn reply), it_engineer
-- (70, the incident owner; 71, the knowledge vectors). 23 Sep 2026, founder_instruction 886-903: "NO word matching
-- anywhere: decisions by reasoning, never keyword/regex/ilike on meaning."
--
-- WHY. What a bank line IS, what a booked expense IS, which expense pays a licence renewal, which bank credit is
-- Stripe's, and which knowledge record answers a question were all decided in SQL by reading words:
--   * fn_accountant_book_bank_charges: description ~* gl_settings.bank_charge_pattern ('charge|fee|maint|...');
--   * fn_accountant_book_bank_credits: owner_transfer_pattern ('transfer|p_?2_?p') + fn_bank_line_is_owner_transfer
--     (a name split out of the description), bank_interest_pattern + bank_interest_reference_pattern;
--   * fn_accountant_bank_reconcile: description ilike '%stripe%' (the payout preference and a finding);
--   * fn_accountant_ad_spend_figures: vendor ~* decision_policy accountant_meta_invoice_vendor_pattern;
--   * fn_accountant_renewal_budget_line: vendor ~* accountant_renewal_vendor_patterns per it_expiry item;
--   * fn_accountant_expense_duty: expected vendors found by vendor ilike '%' || name || '%';
--   * fn_os_incident_set_owner_and_due: order by (reason ilike '%incident response%') over event_subscription;
--   * fn_support_knowledge_search / fn_ceo_knowledge_search: websearch_to_tsquery, then "best terms" OR'd.
--
-- WHAT. Meaning arrives as structured data REASONED upstream (think(), _shared/reasoned_books.ts):
--   * bank_statement_line.kind (bank_charge | owner_transfer | bank_interest | stripe_payout | other), written by
--     fn_accountant_bank_line_reasoned from the accountant runtime's duties tick, or on replay by
--     fn_reason_apply_accountant__bank_line. NULL = not reasoned yet: every booking routine skips it, and a credit
--     still NULL past the matching window is an accountant finding ("not reasoned yet"), never booked on a guess.
--   * expense_entries.read_as (receipt_monthly | receipt_annual | receipt_one_off | meta_ads_invoice | renewal) and
--     expense_entries.renews_item (the it_expiry item a renewal receipt pays), written when the receipt is booked.
--   * the incident owner is the it_engineer seat (the founder's org: seats, no departments) — no text is read.
--   * support_knowledge and ceo_knowledge gain embedding_gte vector(384) (gte-small, free, in-region); their search
--     routines and fn_reason_retrieve rank by vector distance only; a BEFORE UPDATE trigger clears a row's vector
--     when its title or body changes; scripts/kb/embed_sales_knowledge.mjs --table=support_knowledge|ceo_knowledge
--     backfills (NOT run by this change), and the two pack loaders call it after every load (embed-on-write).
--   * the LinkedIn reply reasoned after the hold is recorded by fn_marketing_outreach_reply_reasoned.
-- The patterns that decided meaning are deleted (gl_settings, decision_policy) and fn_bank_line_is_owner_transfer
-- is dropped.
--
-- MEASURED 23 Sep 2026, production (read-only):
--   * bank_statement_line: 6 lines, all 6 already booked, posted (bank_charge 4, owner_capital 1, bank_interest 1);
--     their kind is back-filled below FROM THE JOURNAL THAT BOOKED THEM (gl_journal.source), not from the text.
--   * expense_entries: 54 rows, none from Meta (so read_as needs no Meta back-fill). The renewal budget matched
--     #122 (DET licence, AED 1,200, founder-reported) for trade_licence_det_1633275, and for BOTH domains the last
--     GoDaddy row, #103 — AED 93.80 of monthly Microsoft 365 email, which is not a domain renewal. #122 is
--     back-filled renews_item by id; the domains are left unbudgeted until a receipt reasoned to renew them is
--     booked (the old figure was the wrong expense, and a missing budget is an honest finding inside 90 days).
--   * event_subscription holds NO security.event row, so every incident since 7 Sep fell to the literal 'security',
--     a seat that does not exist (os_incidents owners: security 32, ops_director 7, it 4, null 19).
--   * support_knowledge 408 rows, ceo_knowledge 508 rows, no vector column: an exact scan (no HNSW) is enough.
--
-- Pending: scripts/sql/pending/the_books_and_the_knowledge_are_read_by_meaning_not_by_words.txt. Proved by replaying
-- the chain and a probe inside ONE aborted transaction: node --test scripts/checks/decision_points_are_reasoned.test.mjs

-- Load pgvector's shared library into THIS backend before the routines below are validated: fn_reason_retrieve's SET
-- clauses name hnsw.* GUCs, which a backend that has not yet touched a vector treats as unknown placeholders and, for a
-- non-superuser, refuses (measured on scripts/sql/fn_ops_knowledge_match_returns_k_rows_for_a_scoped_agent.sql).
select '[0]'::vector;

-- ── 1. WHAT A BANK LINE IS, AS DATA ─────────────────────────────────────────────────────────────
alter table public.bank_statement_line add column if not exists kind          text;
alter table public.bank_statement_line add column if not exists kind_by       text;
alter table public.bank_statement_line add column if not exists kind_at       timestamptz;
alter table public.bank_statement_line add column if not exists kind_tried_at timestamptz;
alter table public.bank_statement_line drop constraint if exists bank_statement_line_kind_check;
alter table public.bank_statement_line add constraint bank_statement_line_kind_check
  check (kind is null or kind in ('bank_charge', 'owner_transfer', 'bank_interest', 'stripe_payout', 'other'));
comment on column public.bank_statement_line.kind is
  'What the line IS, reasoned by the accountant (reasoned_books.ts bankLineKind, through think()) or taken from the journal or payout that already accounts for it. NULL = not reasoned yet: nothing books it.';

-- The lines already accounted for take their kind from WHAT ACCOUNTS FOR THEM (structured), never from their text.
update public.bank_statement_line b
   set kind = case g.source when 'bank_charge' then 'bank_charge' when 'owner_capital' then 'owner_transfer' else 'bank_interest' end,
       kind_by = 'gl_journal#' || g.id, kind_at = now()
  from public.gl_journal g
 where g.source in ('bank_charge', 'owner_capital', 'bank_interest') and g.source_ref = b.id::text
   and g.status in ('draft', 'posted') and b.kind is null;
update public.bank_statement_line b set kind = 'stripe_payout', kind_by = 'stripe_payout#' || p.id, kind_at = now()
  from public.stripe_payout p where p.bank_line_id = b.id and b.kind is null;

-- The lines the accountant runtime reasons next (a few per duties tick). Oldest attempt first, so a line whose
-- reasoning keeps failing never starves the ones behind it; the owner's name is context, the text is masked.
create or replace function public.fn_accountant_bank_lines_to_reason(p_limit integer default 10)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_ids bigint[];
begin
  select array_agg(id) into v_ids from (
    select id from public.bank_statement_line where kind is null
     order by kind_tried_at nulls first, id limit greatest(1, least(coalesce(p_limit, 10), 50))) x;
  update public.bank_statement_line set kind_tried_at = now() where id = any(coalesce(v_ids, '{}'));
  return jsonb_build_object(
    'owner', (select owner_name from public.company_registration order by recorded_at desc limit 1),
    'lines', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'value_date', b.value_date, 'amount_aed', b.amount_aed,
                                                           'account', b.account, 'description', public.fn_mask_bank_text(b.description)) order by b.id)
                         from public.bank_statement_line b where b.id = any(coalesce(v_ids, '{}'))), '[]'::jsonb));
end $fn$;
revoke execute on function public.fn_accountant_bank_lines_to_reason(integer) from public, anon, authenticated;
grant execute on function public.fn_accountant_bank_lines_to_reason(integer) to service_role;

-- The reasoned kind, recorded once. A kind already recorded is never overwritten by a later reading.
create or replace function public.fn_accountant_bank_line_reasoned(p_line_id bigint, p_kind text, p_by text default 'reasoning')
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if p_kind is null or p_kind not in ('bank_charge', 'owner_transfer', 'bank_interest', 'stripe_payout', 'other') then
    raise exception 'fn_accountant_bank_line_reasoned: % is not a bank line kind', p_kind using errcode = '22023';
  end if;
  update public.bank_statement_line set kind = p_kind, kind_by = coalesce(nullif(btrim(p_by), ''), 'reasoning'), kind_at = now()
   where id = p_line_id and kind is null;
  return jsonb_build_object('line_id', p_line_id, 'kind', p_kind, 'recorded', found);
end $fn$;
revoke execute on function public.fn_accountant_bank_line_reasoned(bigint, text, text) from public, anon, authenticated;
grant execute on function public.fn_accountant_bank_line_reasoned(bigint, text, text) to service_role;

-- The replay: a line held under the model hold gets its kind when fn_reason_held_resolve applies the answer.
create or replace function public.fn_reason_apply_accountant__bank_line(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_line bigint; v_kind text := p_result->'decision'->>'choice';
begin
  select (subject->>'line_id')::bigint into v_line from public.reasoning_held_question where id = p_id;
  if v_line is null or v_kind is null or v_kind not in ('bank_charge', 'owner_transfer', 'bank_interest', 'stripe_payout', 'other') then
    return null;          -- nothing to apply: the row stays 'reasoned', not 'applied'
  end if;
  return public.fn_accountant_bank_line_reasoned(v_line, v_kind, 'reasoning:held#' || p_id);
end $fn$;
revoke execute on function public.fn_reason_apply_accountant__bank_line(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_accountant__bank_line(bigint, jsonb) to service_role;

-- ── 2. THE BOOKING ROUTINES READ THE KIND, NOT THE DESCRIPTION ───────────────────────────────────
-- Canonical bodies (a_journal_memo_never_carries_a_bank_or_iban_number.sql) with only the meaning test replaced.
create or replace function public.fn_accountant_book_bank_charges()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_hold boolean := coalesce((select num_value from public.gl_settings where key = 'bank_booking_on_hold'), 1) <> 0;
  l record; v_lines jsonb; v_memo text; n_posted int := 0; n_draft int := 0;
begin
  for l in select * from public.bank_statement_line b
            where b.amount_aed < 0 and b.kind = 'bank_charge'
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

drop function if exists public.fn_bank_line_is_owner_transfer(text, text);
create or replace function public.fn_accountant_book_bank_credits()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_hold boolean := coalesce((select num_value from public.gl_settings where key = 'bank_booking_on_hold'), 1) <> 0;
  v_after int := coalesce((select num_value::int from public.gl_settings where key = 'bank_match_days_after'), 5);
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  l record; v_lines jsonb; v_memo text; v_src text; v_booked boolean;
  n_posted int := 0; n_draft int := 0; n_raced int := 0; v_items jsonb := '[]'::jsonb;
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
    exception when unique_violation then
      n_raced := n_raced + 1;        -- a concurrent run booked this line first: gl_journal_one_live_entry_per_bank_or_fee_line
    end;
  end loop;
  return jsonb_build_object('posted', n_posted, 'drafted', n_draft, 'booked_by_a_concurrent_run', n_raced, 'hold', v_hold,
    'findings', public.fn_accountant_duty_settle('bank_credits', v_items));
end $fn$;
revoke execute on function public.fn_accountant_book_bank_credits() from public, anon, authenticated;

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
  -- a line REASONED to be a Stripe payout preferred (bank_statement_line.kind; never a word in its description).
  for p in select * from public.stripe_payout s
            where s.bank_line_id is null and s.status = 'paid' and s.currency = 'aed' and (s.livemode or v_demo_on)
            order by s.arrival_date loop
    select bl.* into l from public.bank_statement_line bl
     where ((p.livemode and bl.account <> 'zz_demo') or (not p.livemode and bl.account = 'zz_demo'))
       and bl.amount_aed = round(p.amount_fils / 100.0, 2)
       and bl.value_date between p.arrival_date - v_before and p.arrival_date + v_after
       and not exists (select 1 from public.stripe_payout q where q.bank_line_id = bl.id)
     order by (bl.kind is not distinct from 'stripe_payout') desc, abs(bl.value_date - p.arrival_date), bl.id
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
            where bl.amount_aed > 0 and bl.kind = 'stripe_payout' and bl.value_date + v_after < v_as_of
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

-- ── 3. WHAT A BOOKED EXPENSE IS, AS DATA ─────────────────────────────────────────────────────────
alter table public.expense_entries add column if not exists read_as     text;
alter table public.expense_entries add column if not exists renews_item text;
alter table public.expense_entries drop constraint if exists expense_entries_read_as_check;
alter table public.expense_entries add constraint expense_entries_read_as_check
  check (read_as is null or read_as in ('receipt_monthly', 'receipt_annual', 'receipt_one_off', 'meta_ads_invoice', 'renewal'));
comment on column public.expense_entries.read_as is
  'What the document was REASONED to be when it was booked (reasoned_books.ts documentKind). NULL on rows booked before 23 Sep 2026.';
comment on column public.expense_entries.renews_item is
  'The public.it_expiry item this receipt pays the renewal of, when it was reasoned to be one.';
-- #122: the DET trade licence, founder-reported 14 Sep 2026 ("just note down the number of 1200 AED"); its own note
-- says "Renewal due before the licence expires on 2027-06-24". The one row the old vendor pattern matched correctly.
update public.expense_entries set renews_item = 'trade_licence_det_1633275', read_as = 'renewal'
 where id = 122 and renews_item is null;

-- What the reasoning is given as context: the vendors the books carry (the options it picks among), the
-- subscription register, and the licences and domains that renew. ZZ DEMO fixtures are not offered.
create or replace function public.fn_accountant_reading_context()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object(
    'vendors', coalesce((select jsonb_agg(v order by v) from (
        select btrim(vendor) v from public.expense_entries where coalesce(btrim(vendor), '') <> ''
        union select btrim(vendor) from public.expenses where coalesce(btrim(vendor), '') <> ''
        union select btrim(x) from public.decision_policy d, jsonb_array_elements_text(d.value) x
               where d.key = 'accountant_expected_subscription_vendors') s
       where v !~* 'zz[ _-]?demo'), '[]'::jsonb),
    'register', coalesce((select jsonb_agg(jsonb_build_object('vendor', vendor, 'cadence', cadence) order by vendor)
                            from public.expenses where active), '[]'::jsonb),
    'renewals', coalesce((select jsonb_agg(jsonb_build_object('item', item, 'kind', kind, 'expires_on', expires_on) order by item)
                            from public.it_expiry where kind in ('licence', 'domain')), '[]'::jsonb));
$fn$;
revoke execute on function public.fn_accountant_reading_context() from public, anon, authenticated;
grant execute on function public.fn_accountant_reading_context() to service_role;

create or replace function public.fn_accountant_ad_spend_figures(p_month date)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_m date := date_trunc('month', p_month)::date; v_e date; v_from timestamptz; v_to timestamptz;
  v_fx numeric; v_inv numeric; v_n int; v_unconv int; v_rep numeric; v_inq int; v_rev int;
begin
  v_e := (v_m + interval '1 month')::date - 1;
  v_from := v_m::timestamp at time zone 'Asia/Dubai'; v_to := (v_e + 1)::timestamp at time zone 'Asia/Dubai';
  -- The same conversion the monthly close uses (gl_settings usd_to_aed; AED is pegged at 3.6725).
  v_fx := coalesce((select num_value from public.gl_settings where key = 'usd_to_aed'), 3.6725);

  select count(*) filter (where upper(currency) in ('AED', 'USD')),
         round(sum(amount * case upper(currency) when 'USD' then v_fx else 1 end) filter (where upper(currency) in ('AED', 'USD')), 2),
         count(*) filter (where upper(currency) not in ('AED', 'USD'))
    into v_n, v_inv, v_unconv
    from public.expense_entries where read_as = 'meta_ads_invoice' and charged_on between v_m and v_e;
  select reported_spend_aed into v_rep from public.accountant_ad_spend_month where month = v_m;
  select count(*) into v_inq from public.inquiries i left join public.customers c on c.id = i.customer_id
   where i.created_at >= v_from and i.created_at < v_to and not coalesce(c.is_demo, false);
  select count(*) into v_rev from public.transactions t left join public.customers c on c.id = t.customer_id
   where t.fee_status = 'paid' and t.revealed_at >= v_from and t.revealed_at < v_to and not coalesce(c.is_demo, false);

  return jsonb_build_object(
    'month', to_char(v_m, 'YYYY-MM'),
    'invoiced_aed', case when v_n > 0 then v_inv end,
    'meta_invoices', v_n, 'meta_invoices_unconverted', v_unconv,
    'reported_spend_aed', v_rep,
    'difference_aed', case when v_n > 0 and v_rep is not null then v_inv - v_rep end,
    'inquiries', v_inq, 'reveals', v_rev,
    'cost_per_inquiry_aed', case when v_n > 0 and v_inq > 0 then round(v_inv / v_inq, 2) end,
    'cost_per_reveal_aed', case when v_n > 0 and v_rev > 0 then round(v_inv / v_rev, 2) end,
    'missing', to_jsonb(array_remove(array[
      case when v_n = 0 then 'no Meta invoice is booked in expense_entries for the month' end,
      case when v_unconv > 0 then v_unconv || ' Meta invoice(s) in a currency other than AED or USD are not converted' end,
      case when v_rep is null then 'Meta reported no spend for the month (meta_sync wrote none, or nothing was spent)' end,
      case when v_inq = 0 then 'no inquiry in the month, so there is no cost per inquiry' end,
      case when v_rev = 0 then 'no paid reveal in the month, so there is no cost per reveal' end], null)),
    'basis', 'Invoiced = Meta ads invoices booked in expense_entries (read_as meta_ads_invoice: each document REASONED to be a Meta advertising invoice when it was booked), USD at gl_settings usd_to_aed. Reported = ad_spend_policy.month_spent_aed as meta_sync last wrote it for the month. Cost per inquiry and per reveal divide the INVOICED figure by the inquiries created and the reveals paid in the month (Asia/Dubai). ZZ DEMO customers are not counted.');
end $fn$;
revoke execute on function public.fn_accountant_ad_spend_figures(date) from public, anon, authenticated;

-- The renewal budget: the last payment booked that was REASONED to renew this item.
create or replace function public.fn_accountant_renewal_budget_line(p_item text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  x public.it_expiry; v_before int; v_fx numeric; v_basis text; v_amt numeric;
  v_eid bigint; v_vendor text; v_amount numeric; v_cur text; v_on date;
begin
  select * into x from public.it_expiry where item = p_item;
  if not found then raise exception 'public.it_expiry has no item %', p_item; end if;
  v_before := (select (value #>> '{}')::int from public.decision_policy where key = 'accountant_renewal_pay_days_before');
  if v_before is null then raise exception 'decision_policy accountant_renewal_pay_days_before is missing'; end if;
  v_fx := coalesce((select num_value from public.gl_settings where key = 'usd_to_aed'), 3.6725);
  select id, vendor, amount, upper(currency), charged_on into v_eid, v_vendor, v_amount, v_cur, v_on
    from public.expense_entries
   where renews_item = p_item and upper(currency) in ('AED', 'USD') and amount > 0
   order by charged_on desc, id desc limit 1;
  if v_eid is null then
    v_basis := 'MISSING: no payment booked in expense_entries was reasoned to renew ' || p_item || '; the fee is unknown until its receipt is booked';
  else
    v_amt := round(v_amount * case v_cur when 'USD' then v_fx else 1 end, 2);
    v_basis := 'the last booked payment reasoned to renew it: expense_entries #' || v_eid || ', ' || v_vendor || ', ' || v_cur || ' ' || v_amount || ' on ' || v_on;
  end if;
  insert into public.accountant_renewal_budget (item, kind, expires_on, pay_by, budget_aed, basis, last_expense_id, updated_at)
  values (x.item, x.kind, x.expires_on, x.expires_on - v_before, v_amt, v_basis, v_eid, now())
  on conflict (item) do update set kind = excluded.kind, expires_on = excluded.expires_on, pay_by = excluded.pay_by,
                                   budget_aed = excluded.budget_aed, basis = excluded.basis,
                                   last_expense_id = excluded.last_expense_id, updated_at = now();
  return jsonb_build_object('item', x.item, 'kind', x.kind, 'expires_on', x.expires_on, 'pay_by', x.expires_on - v_before,
                            'budget_aed', v_amt, 'basis', v_basis);
end $fn$;
revoke execute on function public.fn_accountant_renewal_budget_line(text) from public, anon, authenticated;

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
     and not exists (select 1 from public.expense_entries x where lower(x.vendor) = lower(v))
     and not exists (select 1 from public.vendor_billing_ended b where lower(b.vendor) = lower(v));
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

-- The word patterns that decided meaning are gone with the routines that read them.
delete from public.gl_settings where key in ('bank_charge_pattern', 'owner_transfer_pattern', 'bank_interest_pattern', 'bank_interest_reference_pattern');
delete from public.decision_policy where key in ('accountant_meta_invoice_vendor_pattern', 'accountant_renewal_vendor_patterns');

-- ── 4. A LINKEDIN REPLY REASONED AFTER THE HOLD (marketing) ──────────────────────────────────────
-- The reply was recorded 'replied' with no class while the hold was on. The reasoned class is recorded now, a
-- decline closes the person exactly as fn_marketing_outreach_mark does, and the follow-up the runtime composed and
-- linted (marketing_outreach.ts) is added for the founder. A class a live reasoning already wrote is not replaced.
create or replace function public.fn_marketing_outreach_reply_reasoned(p_token uuid, p_class text, p_follow_up text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_m public.marketing_outreach_message; v_follow uuid;
begin
  if p_class is null or p_class not in ('decline', 'later', 'positive', 'question') then
    raise exception 'fn_marketing_outreach_reply_reasoned: % is not a reply class', p_class using errcode = '22023';
  end if;
  select * into v_m from public.marketing_outreach_message where mark_token = p_token for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'unknown_link'); end if;
  if v_m.status is distinct from 'replied' then return jsonb_build_object('ok', false, 'error', 'not_a_reply'); end if;
  if v_m.reply_class is not null then return jsonb_build_object('ok', true, 'already', v_m.reply_class); end if;
  update public.marketing_outreach_message set reply_class = p_class, updated_at = now() where id = v_m.id;
  if p_class = 'decline' then
    update public.marketing_prospect set status = 'declined', updated_at = now() where id = v_m.prospect_id and status <> 'declined';
  end if;
  if btrim(coalesce(p_follow_up, '')) <> ''
     and not exists (select 1 from public.marketing_outreach_message f where f.prospect_id = v_m.prospect_id and f.kind = 'follow_up' and f.id > v_m.id) then
    insert into public.marketing_outreach_message (prospect_id, kind, language, body, lint, listed_on, status, is_demo)
    values (v_m.prospect_id, 'follow_up', v_m.language, p_follow_up, '[]'::jsonb, (now() at time zone 'Asia/Dubai')::date, 'listed', v_m.is_demo)
    returning mark_token into v_follow;
  end if;
  return jsonb_build_object('ok', true, 'class', p_class, 'follow_up_token', v_follow);
end $fn$;
revoke execute on function public.fn_marketing_outreach_reply_reasoned(uuid, text, text) from public, anon, authenticated;
grant execute on function public.fn_marketing_outreach_reply_reasoned(uuid, text, text) to service_role;

-- ── 5. AN INCIDENT BELONGS TO THE IT ENGINEER SEAT (it_engineer) ─────────────────────────────────
-- Body as in incidents_get_an_owner_a_task_and_a_watchdog.sql, except the owner: it was the event subscriber whose
-- free-text reason read like "incident response" (ilike), and with no subscriber left it fell to a seat that does not
-- exist. Incidents are the it_engineer's by the founder's org ruling; a writer that names an owner keeps it.
create or replace function public.fn_os_incident_set_owner_and_due()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_sla interval;
begin
  if new.owner is null then
    new.owner := 'it_engineer';
  end if;
  if new.due_at is null then
    v_sla := case coalesce(new.severity,'medium')
               when 'critical' then interval '4 hours'
               when 'high'     then interval '24 hours'
               when 'medium'   then interval '72 hours'
               else interval '7 days' end;
    new.due_at := coalesce(new.opened_at, now()) + v_sla;
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_os_incident_set_owner_and_due() from public, anon, authenticated;

-- ── 6. THE SUPPORT AND CEO KNOWLEDGE ARE READ BY MEANING (it_engineer) ───────────────────────────
alter table public.support_knowledge add column if not exists embedding_gte vector(384);
alter table public.ceo_knowledge     add column if not exists embedding_gte vector(384);
comment on column public.support_knowledge.embedding_gte is
  'gte-small (384-d, free, in-region). Written by scripts/kb/embed_sales_knowledge.mjs --table=support_knowledge (the loader calls it after every load); cleared by trg_support_knowledge_text_change_clears_embedding when the title or body changes. 408 rows (23 Sep 2026): exact scan, no index.';
comment on column public.ceo_knowledge.embedding_gte is
  'gte-small (384-d, free, in-region). Written by scripts/kb/embed_sales_knowledge.mjs --table=ceo_knowledge (the loader calls it after every load); cleared by trg_ceo_knowledge_text_change_clears_embedding when the title or body changes. 508 rows (23 Sep 2026): exact scan, no index.';

-- A changed record is never read by its OLD meaning: its vector is cleared so the next embed rebuilds it (the
-- company_faq pattern, scripts/sql/an_edited_faq_answer_is_re_embedded_and_a_quote_is_not_a_fee.sql).
create or replace function public.fn_knowledge_text_change_clears_embedding()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if (new.title is distinct from old.title or new.body is distinct from old.body)
     and new.embedding_gte is not distinct from old.embedding_gte then
    new.embedding_gte := null;
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_knowledge_text_change_clears_embedding() from public, anon, authenticated;
drop trigger if exists trg_support_knowledge_text_change_clears_embedding on public.support_knowledge;
create trigger trg_support_knowledge_text_change_clears_embedding
  before update of title, body on public.support_knowledge
  for each row execute function public.fn_knowledge_text_change_clears_embedding();
drop trigger if exists trg_ceo_knowledge_text_change_clears_embedding on public.ceo_knowledge;
create trigger trg_ceo_knowledge_text_change_clears_embedding
  before update of title, body on public.ceo_knowledge
  for each row execute function public.fn_knowledge_text_change_clears_embedding();

-- The seats' reasoning reads both packs (fn_reason_retrieve, every_seat_reasons_before_it_answers.sql, + two arms).
create or replace function public.fn_reason_retrieve(p_seat text, p_embedding vector(384), p_k integer default 6)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
set "hnsw.iterative_scan" to 'relaxed_order'
set "hnsw.ef_search" to '100'
as $fn$
declare
  k   integer := greatest(1, least(coalesce(p_k, 6), 12));
  out jsonb := '[]'::jsonb;
begin
  if p_embedding is null then return out; end if;

  -- Each source is ordered by distance on its own, so each uses its own index; the union is then
  -- ranked by the same distance. Excerpts are cut, never the ranking.
  with hits as (
    (select 'kb_chunks' src, c.id::text id, c.title, left(c.content, 1200) excerpt, c.citation,
            1 - (c.embedding_gte <=> p_embedding) sim, 'reviewed' trust
       from public.kb_chunks c where c.embedding_gte is not null
      order by c.embedding_gte <=> p_embedding limit k)
    union all
    (select 'ops_knowledge', o.record_id, o.title, left(o.content, 1200), o.source_path,
            1 - (o.embedding_gte <=> p_embedding), 'reviewed'
       from public.ops_knowledge o
      where o.embedding_gte is not null and o.runtime_eligible and o.supersession_state = 'current'
        and o.scope_type in ('company', 'external_source', 'category')
      order by o.embedding_gte <=> p_embedding limit k)
    union all
    (select 'agent_knowledge', a.id::text, a.topic, left(a.content, 1200), a.source_ref,
            1 - (a.embedding_gte <=> p_embedding), 'reviewed'
       from public.agent_knowledge a
      where a.embedding_gte is not null and a.agent_key in (p_seat, '_global')
      order by a.embedding_gte <=> p_embedding limit k)
    union all
    (select 'company_faq', f.id::text, f.question, left(f.answer, 1200), 'FAQ ' || f.id,
            1 - (f.embedding_gte <=> p_embedding), 'reviewed'
       from public.company_faq f where f.embedding_gte is not null and f.status = 'approved'
      order by f.embedding_gte <=> p_embedding limit k)
    union all
    (select 'sales_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id,
            1 - (s.embedding_gte <=> p_embedding), 'reviewed'
       from public.sales_knowledge s
      where p_seat = 'sales_engineer' and s.embedding_gte is not null and s.runtime_index_eligible
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'accountant_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id,
            1 - (s.embedding_gte <=> p_embedding), 'reviewed'
       from public.accountant_knowledge s
      where p_seat = 'accountant' and s.embedding_gte is not null and s.runtime_index_eligible
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'it_engineer_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id,
            1 - (s.embedding_gte <=> p_embedding), 'reviewed'
       from public.it_engineer_knowledge s
      where p_seat = 'it_engineer' and s.embedding_gte is not null and s.runtime_index_eligible
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    -- customer_support and the ceo read their own packs by meaning (23 Sep 2026; 408 and 508 rows, exact scan).
    (select 'support_knowledge', s.record_id, s.title, left(s.body, 1200), s.source_path,
            1 - (s.embedding_gte <=> p_embedding), 'reviewed'
       from public.support_knowledge s
      where p_seat = 'customer_support' and s.embedding_gte is not null and s.runtime_index_eligible
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'ceo_knowledge', c.record_id, c.title, left(c.body, 1200), c.source_path,
            1 - (c.embedding_gte <=> p_embedding), 'reviewed'
       from public.ceo_knowledge c
      where p_seat = 'ceo' and c.embedding_gte is not null and c.runtime_index_eligible
      order by c.embedding_gte <=> p_embedding limit k)
    union all
    (select 'research', r.id::text, left(r.question, 200), r.finding, r.sources->0->>'url',
            1 - (r.embedding_gte <=> p_embedding), case when r.status = 'approved' then 'reviewed' else 'pending_review' end
       from public.reasoning_knowledge_candidate r
      where r.embedding_gte is not null and r.status <> 'rejected'
      order by r.embedding_gte <=> p_embedding limit k)
  )
  select coalesce(jsonb_agg(jsonb_build_object('source', src, 'id', id, 'title', title, 'excerpt', excerpt,
           'citation', citation, 'similarity', round(sim::numeric, 4), 'trust', trust) order by sim desc), '[]'::jsonb)
    into out
    from (select * from hits order by sim desc limit k * 2) t;
  return out;
end $fn$;
revoke execute on function public.fn_reason_retrieve(text, vector, integer) from public, anon, authenticated;
grant execute on function public.fn_reason_retrieve(text, vector, integer) to service_role;

-- The support and CEO lookups: nearest records by vector distance, over a floor. 0.84 is the corroboration floor
-- measured for gte-small (paraphrases 0.847-0.924, unrelated 0.760-0.816; _shared/think.ts CORROBORATION_FLOOR):
-- below it a nearest neighbour is only the least-far record, not an answer. No embedding: nothing, never words.
-- p_query stays as the first parameter only so the callers' shape does not change; it is not read.
drop function if exists public.fn_support_knowledge_search(text, integer, text);
create or replace function public.fn_support_knowledge_search(p_query text, p_limit integer default 6, p_kind text default null,
                                                              p_embedding vector(384) default null)
returns table(record_id text, record_kind text, title text, body text, body_sha256 text, source_ids text[], source_path text,
              review_status text, authority_effect text, contains_synthetic_example boolean, structured_data jsonb,
              relevance real, matched_how text, warning text)
language plpgsql stable
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if p_embedding is null then return; end if;
  return query
  select k.record_id, k.record_kind, k.title, k.body, k.body_sha256, k.source_ids, k.source_path, k.review_status,
         k.authority_effect, k.contains_synthetic_example, k.structured_data,
         (1 - (k.embedding_gte <=> p_embedding))::real as relevance, 'meaning'::text as matched_how,
         'Advisory only. authority_effect=none: this may not approve a refund, grant an entitlement, '
         || 'change a price or become policy. review_status=' || k.review_status || '. '
         || case when k.record_kind = 'message_template'
                 then 'DRAFT TEMPLATE -- not an approved provider template. Check wa_template_registry before sending. ' else '' end
         || case when k.contains_synthetic_example
                 then 'CONTAINS A SYNTHETIC EXAMPLE -- authored, not a real QuotesDone conversation. ' else '' end
         || 'Account facts come from the database, never from this record.' as warning
    from public.support_knowledge k
   where k.runtime_index_eligible and k.embedding_gte is not null
     and (p_kind is null or k.record_kind = p_kind)
     and 1 - (k.embedding_gte <=> p_embedding) >= 0.84
   order by k.embedding_gte <=> p_embedding, k.record_id
   limit greatest(1, least(coalesce(p_limit, 6), 30));
end $fn$;
revoke execute on function public.fn_support_knowledge_search(text, integer, text, vector) from public, anon, authenticated;
grant execute on function public.fn_support_knowledge_search(text, integer, text, vector) to service_role;

drop function if exists public.fn_ceo_knowledge_search(text, integer, text, text);
create or replace function public.fn_ceo_knowledge_search(p_query text, p_limit integer default 8, p_kind text default null,
  p_domain text default null, p_embedding vector(384) default null)
returns table(record_id text, record_version text, record_kind text, title text, domain text, body text, body_sha256 text,
  source_ids text[], source_path text, review_status text, authority_effect text, contains_synthetic_example boolean,
  requires_current_verification boolean, relevance real, matched_how text, warning text)
language plpgsql stable set search_path to 'public', 'pg_temp'
as $fn$
begin
  if p_embedding is null then return; end if;
  return query
  select k.record_id, k.record_version, k.record_kind, k.title, k.domain, k.body, k.body_sha256, k.source_ids, k.source_path,
         k.review_status, k.authority_effect, k.contains_synthetic_example, k.requires_current_verification,
         (1 - (k.embedding_gte <=> p_embedding))::real as relevance, 'meaning'::text as matched_how,
         'Advisory only. authority_effect=none: this may not approve an action, change a target or '
         || 'become policy. review_status=' || k.review_status || '. '
         || case when k.contains_synthetic_example
                 then 'CONTAINS A SYNTHETIC EXAMPLE -- it is authored, not QuotesDone experience. ' else '' end
         || case when k.requires_current_verification
                 then 'REQUIRES CURRENT VERIFICATION against an authoritative company source. ' else '' end
         || 'Current company facts come from the application, never from this record.' as warning
    from public.ceo_knowledge k
   where k.runtime_index_eligible and k.embedding_gte is not null
     and (p_kind is null or k.record_kind = p_kind)
     and (p_domain is null or k.domain = p_domain)
     and 1 - (k.embedding_gte <=> p_embedding) >= 0.84
   order by k.embedding_gte <=> p_embedding, k.record_id
   limit greatest(1, least(coalesce(p_limit, 8), 50));
end $fn$;
revoke execute on function public.fn_ceo_knowledge_search(text, integer, text, text, vector) from public, anon, authenticated;
grant execute on function public.fn_ceo_knowledge_search(text, integer, text, text, vector) to service_role;

-- The seats' context calls pass the embedding through (fn_ceo_context: ceo_agent's `context` action embeds the query).
drop function if exists public.fn_support_context(text, integer, integer);
create or replace function public.fn_support_context(p_query text, p_max_chars integer DEFAULT 12000, p_limit integer DEFAULT 5, p_embedding vector(384) DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path to 'public', 'pg_temp'
AS $function$
declare
  r record; v_out jsonb := '[]'::jsonb; v_used int := 0; v_n int := 0; v_how text;
begin
  for r in select * from public.fn_support_knowledge_search(p_query, p_limit, p_embedding => p_embedding) loop
    exit when v_used + length(r.body) > greatest(1500, p_max_chars);
    v_how := coalesce(v_how, r.matched_how);
    v_out := v_out || jsonb_build_object(
      'record_id', r.record_id, 'record_kind', r.record_kind, 'title', r.title,
      'body', r.body, 'source_ids', to_jsonb(r.source_ids), 'review_status', r.review_status,
      'relevance', r.relevance, 'matched_how', r.matched_how, 'warning', r.warning);
    v_used := v_used + length(r.body); v_n := v_n + 1;
  end loop;

  return jsonb_build_object(
    -- THE COMPANY BLOCK. Pinned, never retrieved and never rankable: it is here on every answer,
    -- including the refusals, because a seat with no retrieval hit is exactly the seat most likely
    -- to improvise a fee or a policy. Founder ruling, 9 Sep 2026.
    'company', public.fn_company_context(),
    
    'query', p_query,
    -- PINNED EVERY TIME, never retrieved and never rankable. These are the rules that must hold
    -- when the retrieval finds nothing, which is exactly when an agent is most tempted to improvise.
    'invariants', jsonb_build_array(
      'Never say you checked, sent, escalated, fixed, refunded or approved anything without tool evidence for it.',
      'A tool error means "cannot verify right now". It never means "no inquiry", "unpaid" or "no discount".',
      'Never reveal a supplier name, contact, logo, amount or quotation content in a notification. The quotation stays in the portal, including after a reveal payment.',
      'Never invent a fee, discount, promotion, policy, deadline or guaranteed outcome.',
      'A supplied email, number or reference is a search clue, never proof of account ownership.',
      'Never request a password, full card number or a banking OTP.',
      'Identify as QuotesDone Support. Never impersonate a person and never claim to be human.',
      'Escalation goes to the CEO. Never to the founder, and never to an invented department.'),
    'advisory_records', v_out,
    'record_count', v_n,
    'matched_how', v_how,
    'sufficient', v_n > 0,
    -- The caller fills this from the database. It is named rather than left implicit so that a
    -- caller who forgets it produces an obviously empty slot instead of a confident general answer.
    'account_facts', null,
    'account_facts_note', 'The CALLER must fill account_facts from authorised live data. Advisory records never contain this customer''s facts.',
    'signal', case when v_n = 0
                   then case when p_embedding is null then 'NO EMBEDDING was passed, so nothing was retrieved: this pack is read by meaning only. Answer from company policy and live account facts; do not improvise.'
                             else 'NO ADVISORY COVERAGE for this query. Answer from company policy and live account facts; do not improvise from these records.' end
                   else 'Advisory guidance only. Account facts come from the database.' end);
end $function$;
revoke execute on function public.fn_support_context(text, integer, integer, vector) from public, anon, authenticated;
grant execute on function public.fn_support_context(text, integer, integer, vector) to service_role;

drop function if exists public.fn_ceo_context(text, integer, integer);
create or replace function public.fn_ceo_context(p_query text, p_max_chars integer DEFAULT 18000, p_limit integer DEFAULT 8, p_embedding vector(384) DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path to 'public', 'pg_temp'
AS $function$
declare
  r record;
  v_out jsonb := '[]'::jsonb;
  v_used int := 0;
  v_n int := 0;
  v_how text := null;
begin
  for r in select * from public.fn_ceo_knowledge_search(p_query, p_limit, p_embedding => p_embedding) loop
    exit when v_used + length(r.body) > greatest(2000, p_max_chars);
    v_how := coalesce(v_how, r.matched_how);
    v_out := v_out || jsonb_build_object(
      'record_id', r.record_id, 'record_kind', r.record_kind, 'title', r.title,
      'domain', r.domain, 'body', r.body, 'body_sha256', r.body_sha256,
      'source_ids', to_jsonb(r.source_ids), 'source_path', r.source_path,
      'review_status', r.review_status, 'authority_effect', r.authority_effect,
      'relevance', r.relevance, 'matched_how', r.matched_how, 'warning', r.warning);
    v_used := v_used + length(r.body);
    v_n := v_n + 1;
  end loop;

  return jsonb_build_object(
    -- THE COMPANY BLOCK. Pinned, never retrieved and never rankable: it is here on every answer,
    -- including the refusals, because a seat with no retrieval hit is exactly the seat most likely
    -- to improvise a fee or a policy. Founder ruling, 9 Sep 2026.
    'company', public.fn_company_context(),
    
    'query', p_query,
    'records', v_out,
    'record_count', v_n,
    'chars_used', v_used,
    'matched_how', v_how,
    'sufficient', v_n > 0,
    'signal', case when v_n = 0
                   then case when p_embedding is null then 'INSUFFICIENT CONTEXT -- no embedding was passed, and this pack is read by meaning only. Say so rather than answering from memory.'
                             else 'INSUFFICIENT CONTEXT -- nothing in the CEO knowledge pack is near this query in meaning. Say so rather than answering from memory.' end
                   else 'Advisory context only. Company facts, targets, budgets and permissions must be read from the application, not from these records.' end,
    'pack_fingerprint', (select max(pack_fingerprint) from public.ceo_knowledge));
end $function$;
revoke execute on function public.fn_ceo_context(text, integer, integer, vector) from public, anon, authenticated;
grant execute on function public.fn_ceo_context(text, integer, integer, vector) to service_role;
