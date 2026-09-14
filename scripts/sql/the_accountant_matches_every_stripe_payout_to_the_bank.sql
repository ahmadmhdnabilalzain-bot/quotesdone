-- THE ACCOUNTANT MATCHES EVERY STRIPE PAYOUT TO THE BANK.
--
-- Assigned: accountant (duty 1 of the eight, founder 14 Sep 2026: "yea add them all").
--
-- WHAT WAS MEASURED (14 Sep 2026, production htdblwldjkcgjvmqkbeh):
--   * Nothing in the database records a Stripe payout. stripe_events logs webhook deliveries, and no
--     payout.* event is subscribed; the IT engineer's payment duty compares checkout sessions and refunds
--     with our books, never money leaving Stripe for the bank.
--   * The bank is Mashreq, the same account Stripe pays out to; statements arrive monthly by email to
--     the expenses mailbox (memory: the_bank_is_mashreq_and_statements_come_monthly). No routine reads a
--     bank statement, and the founder said nothing is to be booked from the bank yet.
--
-- WHAT THIS BUILDS. Two records and one reconciliation, and NO journal entry:
--   stripe_payout          every payout Stripe reports, read daily by the accountant runtime (GET
--                          /v1/payouts) with the sum of the balance transactions each one carries.
--   bank_statement_intake  every statement that reached the accountant, parsed or not, so "no statement
--                          arrived" and "a statement arrived that could not be read" are different rows.
--   bank_statement_line    the statement's lines, idempotent on a hash of the line.
--   fn_accountant_bank_reconcile matches a paid payout to a bank credit of the same amount within a
--   configurable window and raises, through fn_accountant_duty_settle (the IT loop), every payout that
--   failed, is stuck in transit, does not add up to its own balance transactions, is missing from a
--   statement that covers its arrival date, and every month whose statement has not arrived, every
--   statement that could not be read, and every Stripe credit in the bank that no payout explains.
--
-- WHAT THIS DOES NOT DO. It posts nothing to gl_journal (the founder's instruction). It does not read the
-- bank directly: Mashreq has no API here, so the statement is the bank's only word. TEST-mode payouts are
-- reconciled only against ZZ DEMO statements (account 'zz_demo'), and only while one exists.
--
--   node scripts/apply_sql.mjs scripts/sql/the_accountant_matches_every_stripe_payout_to_the_bank.sql --apply --ddl

-- ── 1. THE RECORDS ───────────────────────────────────────────────────────────────────────────────
create table if not exists public.stripe_payout (
  id                text primary key,
  livemode          boolean     not null,
  amount_fils       bigint      not null,
  currency          text        not null,
  status            text        not null,
  arrival_date      date        not null,
  created_at_stripe timestamptz,
  method            text,
  destination       text,
  automatic         boolean,
  failure_code      text,
  failure_message   text,
  txn_count         integer,
  txn_net_fils      bigint,
  first_seen_at     timestamptz not null default now(),
  last_seen_at      timestamptz not null default now(),
  bank_line_id      bigint,
  matched_at        timestamptz
);
comment on table public.stripe_payout is
  'Every Stripe payout the accountant runtime read (GET /v1/payouts), with the count and net of the balance transactions it carries. bank_line_id is the Mashreq statement line it was matched to by fn_accountant_bank_reconcile. Nothing here is posted to the ledger (founder: nothing is booked from the bank yet).';

create table if not exists public.bank_statement_intake (
  source_ref      text primary key,
  account         text        not null default 'mashreq',
  statement_month date,
  state           text        not null check (state in ('parsed', 'unreadable')),
  lines           integer     not null default 0,
  doc_path        text,
  note            text,
  received_at     timestamptz not null default now()
);
comment on table public.bank_statement_intake is
  'Every bank statement that reached the accountant (the expenses mailbox sweep, or the accountant runtime''s bank_statement action). state unreadable is an open finding until the same source_ref is ingested with lines.';

create table if not exists public.bank_statement_line (
  id          bigserial primary key,
  account     text          not null default 'mashreq',
  source_ref  text          not null references public.bank_statement_intake(source_ref),
  value_date  date          not null,
  description text          not null,
  amount_aed  numeric(14,2) not null,
  reference   text,
  line_hash   text          not null unique,
  created_at  timestamptz   not null default now()
);
comment on table public.bank_statement_line is
  'One line of a bank statement, as the statement printed it: amount_aed is positive for a credit and negative for a debit. line_hash makes a re-forwarded statement a no-op.';
create index if not exists bank_statement_line_match_idx on public.bank_statement_line (account, amount_aed, value_date);

do $fk$ begin
  if not exists (select 1 from pg_constraint where conname = 'stripe_payout_bank_line_fk') then
    alter table public.stripe_payout add constraint stripe_payout_bank_line_fk
      foreign key (bank_line_id) references public.bank_statement_line(id);
  end if;
end $fk$;

alter table public.stripe_payout enable row level security;
alter table public.bank_statement_intake enable row level security;
alter table public.bank_statement_line enable row level security;
drop policy if exists stripe_payout_service_role_only on public.stripe_payout;
create policy stripe_payout_service_role_only on public.stripe_payout as permissive for all to public using (false) with check (false);
drop policy if exists bank_statement_intake_service_role_only on public.bank_statement_intake;
create policy bank_statement_intake_service_role_only on public.bank_statement_intake as permissive for all to public using (false) with check (false);
drop policy if exists bank_statement_line_service_role_only on public.bank_statement_line;
create policy bank_statement_line_service_role_only on public.bank_statement_line as permissive for all to public using (false) with check (false);
revoke all on public.stripe_payout, public.bank_statement_intake, public.bank_statement_line from anon, authenticated;
revoke all on sequence public.bank_statement_line_id_seq from anon, authenticated;

-- ── 2. THE WINDOWS ARE CONFIGURATION ─────────────────────────────────────────────────────────────
insert into public.gl_settings (key, num_value, txt_value) values
  ('bank_match_days_before', 1, 'A bank credit may be dated this many days BEFORE the payout''s Stripe arrival date and still match it.'),
  ('bank_match_days_after', 5, 'A bank credit may be dated this many days AFTER the payout''s Stripe arrival date and still match it. A statement that runs past arrival + this many days and has no matching line is a missing payout.'),
  ('payout_transit_grace_days', 3, 'A payout still pending or in transit this many days after its arrival date is a finding.'),
  ('bank_statement_due_day', 10, 'The statement for a month is expected by this day of the following month (Mashreq sends monthly).')
on conflict (key) do nothing;

-- ── 3. RECORDING WHAT STRIPE REPORTED ────────────────────────────────────────────────────────────
-- p_payouts: Stripe payout objects, each optionally carrying txn_count and txn_net (fils) from
-- GET /v1/balance_transactions?payout=<id>. Absent txn_* leave the stored values as they were.
create or replace function public.fn_accountant_payouts_record(p_livemode boolean, p_payouts jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare x jsonb; n int := 0;
begin
  if jsonb_typeof(p_payouts) is distinct from 'array' then
    raise exception 'fn_accountant_payouts_record(livemode, payouts[]): an array of Stripe payout objects is required';
  end if;
  for x in select e from jsonb_array_elements(p_payouts) e loop
    if coalesce(x->>'id', '') !~ '^po_' or (x->>'amount') is null or (x->>'arrival_date') is null then
      raise exception 'fn_accountant_payouts_record: % is not a Stripe payout object', left(x::text, 200);
    end if;
    insert into public.stripe_payout (id, livemode, amount_fils, currency, status, arrival_date, created_at_stripe,
                                      method, destination, automatic, failure_code, failure_message, txn_count, txn_net_fils)
    values (x->>'id', p_livemode, (x->>'amount')::bigint, lower(x->>'currency'), x->>'status',
            (to_timestamp((x->>'arrival_date')::bigint) at time zone 'Asia/Dubai')::date,
            to_timestamp((x->>'created')::bigint), x->>'method', x->>'destination', (x->>'automatic')::boolean,
            x->>'failure_code', x->>'failure_message', (x->>'txn_count')::int, (x->>'txn_net')::bigint)
    on conflict (id) do update
       set status = excluded.status, arrival_date = excluded.arrival_date,
           failure_code = excluded.failure_code, failure_message = excluded.failure_message,
           txn_count = coalesce(excluded.txn_count, stripe_payout.txn_count),
           txn_net_fils = coalesce(excluded.txn_net_fils, stripe_payout.txn_net_fils),
           last_seen_at = now();
    n := n + 1;
  end loop;
  return jsonb_build_object('recorded', n, 'livemode', p_livemode);
end $fn$;
revoke execute on function public.fn_accountant_payouts_record(boolean, jsonb) from public, anon, authenticated;

-- ── 4. RECORDING A STATEMENT ─────────────────────────────────────────────────────────────────────
-- p_lines: [{value_date, description, amount_aed, reference}] as supabase/functions/_shared/
-- bank_statement_parse.ts reads them. An empty array records the statement as unreadable.
create or replace function public.fn_accountant_bank_statement_ingest(
  p_account text, p_source_ref text, p_statement_month date, p_lines jsonb, p_doc_path text default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare x jsonb; n_new int := 0; n int; v_month date;
begin
  if coalesce(btrim(p_source_ref), '') = '' or coalesce(btrim(p_account), '') = '' then
    raise exception 'fn_accountant_bank_statement_ingest: an account and a source reference are required';
  end if;
  if jsonb_typeof(p_lines) is distinct from 'array' then
    raise exception 'fn_accountant_bank_statement_ingest: lines must be an array (empty for an unreadable statement)';
  end if;
  n := jsonb_array_length(p_lines);
  v_month := coalesce(p_statement_month,
                      (select date_trunc('month', max((e->>'value_date')::date))::date from jsonb_array_elements(p_lines) e));
  insert into public.bank_statement_intake (source_ref, account, statement_month, state, lines, doc_path, note)
  values (p_source_ref, p_account, v_month, case when n > 0 then 'parsed' else 'unreadable' end, n, p_doc_path, p_note)
  on conflict (source_ref) do update
     set state = case when excluded.lines > 0 then 'parsed' else bank_statement_intake.state end,
         lines = greatest(bank_statement_intake.lines, excluded.lines),
         statement_month = coalesce(excluded.statement_month, bank_statement_intake.statement_month),
         doc_path = coalesce(excluded.doc_path, bank_statement_intake.doc_path),
         note = coalesce(excluded.note, bank_statement_intake.note);
  for x in select e from jsonb_array_elements(p_lines) e loop
    if (x->>'value_date') is null or (x->>'amount_aed') is null or coalesce(btrim(x->>'description'), '') = '' then
      raise exception 'fn_accountant_bank_statement_ingest: a line needs value_date, description and amount_aed (%)', left(x::text, 200);
    end if;
    insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, reference, line_hash)
    values (p_account, p_source_ref, (x->>'value_date')::date, x->>'description', (x->>'amount_aed')::numeric, x->>'reference',
            md5(p_account || '|' || (x->>'value_date') || '|' || ((x->>'amount_aed')::numeric)::text || '|'
                || lower(btrim(x->>'description')) || '|' || coalesce(x->>'reference', '')))
    on conflict (line_hash) do nothing;
    if found then n_new := n_new + 1; end if;
  end loop;
  return jsonb_build_object('source_ref', p_source_ref, 'statement_month', v_month, 'lines', n, 'new_lines', n_new,
                            'state', case when n > 0 then 'parsed' else 'unreadable' end);
end $fn$;
revoke execute on function public.fn_accountant_bank_statement_ingest(text, text, date, jsonb, text, text) from public, anon, authenticated;

-- ── 5. THE RECONCILIATION ────────────────────────────────────────────────────────────────────────
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
                                                       'description', bl.description) order by abs(bl.value_date - p.arrival_date)), '[]'::jsonb)
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
      'blast', 'agent_facing', 'affected', 1, 'demo', x.account = 'zz_demo', 'evidence', to_jsonb(x));
  end loop;

  v_settle := public.fn_accountant_duty_settle('bank', v_items);
  return jsonb_build_object('as_of', v_as_of, 'matched_now', n_matched, 'findings', v_settle,
    'payouts', (select count(*) from public.stripe_payout where livemode),
    'payouts_matched', (select count(*) from public.stripe_payout where livemode and bank_line_id is not null),
    'statements', (select count(*) from public.bank_statement_intake where account <> 'zz_demo'),
    'basis', 'Stripe payouts (read from GET /v1/payouts) against Mashreq statement lines, amount exact, date within the gl_settings window. Nothing was posted to the ledger.');
end $fn$;
revoke execute on function public.fn_accountant_bank_reconcile(date) from public, anon, authenticated;
