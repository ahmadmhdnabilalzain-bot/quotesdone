-- THE ACCOUNTANT LEARNS WHICH MAILBOXES A VENDOR BILLS.
-- Agent: ceo. 9 September 2026.
--
-- THE DEFECT, in the founder's words: "anthropic must be much more than than that. i pay 200 usd
-- monthly". He was right, and the cause was structural rather than arithmetic.
--
-- The accountant only ever sees what somebody REMEMBERS TO FORWARD. Its two sources are the Resend
-- inbound history for expenses@mail.quotesdone.com, and the founder's own Gmail sent folder. Anthropic
-- does not bill either of those. It bills management@doratajewelries.com, an Outlook mailbox nothing
-- in this estate had ever read. Six Anthropic receipts landed there (invoice series YXWTXUVD-0001
-- through -0006, consecutive, so the series itself proves the set is complete). Only the first three
-- were ever forwarded, by hand, on 29 June. The other three were invisible to the book - not held,
-- not refused, not counted as zero, simply never seen. A vendor that bills a mailbox nobody reads is
-- not a missing row, it is a missing SOURCE, and no amount of re-reading the two known mailboxes
-- would ever have surfaced it.
--
-- That is the shape being fixed here. The backfill is the symptom; the register is the fix. Until
-- the accountant can NAME the mailboxes a vendor bills, "the total is complete" is a claim about
-- the mail somebody happened to forward, not about the money the company spent.
--
-- WHAT THIS FILE DOES
--   1. public.expense_billing_mailbox        - every mailbox that receives vendor bills, and whether
--                                              the accountant can actually read it.
--   2. public.expense_vendor_billing_mailbox - which mailbox each vendor was OBSERVED billing, with
--                                              the evidence, and whether that vendor's spend belongs
--                                              in this company's ledger.
--   3. The three unbooked Anthropic receipts, amounts read directly off the receipts.
--   4. fn_accountant_spend_report_coverage() gains SOURCE 3, so the spend report states which
--      mailboxes it covered and which it did not.
--
-- The report routine itself is NOT reopened. The agent who wrote it left the seam deliberately:
-- "fn_accountant_spend_report_coverage owns that paragraph and its shortfalls; the arithmetic below
-- is untouched, and a third source can be added there without reopening this routine."

-- ---------------------------------------------------------------------------------------------
-- 1. THE MAILBOXES
-- ---------------------------------------------------------------------------------------------
create table if not exists public.expense_billing_mailbox (
  mailbox        text primary key,
  description    text not null,
  reachable_by   text,                                   -- null = the accountant CANNOT read it
  is_swept       boolean not null default false,
  last_swept_on  date,
  note           text,
  created_at     timestamptz not null default now()
);

comment on table public.expense_billing_mailbox is
  'Every mailbox a vendor bill can land in, and whether the accountant can read it. A mailbox absent '
  'from this table is a mailbox nobody is watching; a row with is_swept=false is a KNOWN blind spot '
  'and makes the spend report declare itself incomplete. This exists because Anthropic billed an '
  'Outlook mailbox for four months while the book read only two other sources.';

-- ---------------------------------------------------------------------------------------------
-- 2. WHICH MAILBOX EACH VENDOR BILLS
-- ---------------------------------------------------------------------------------------------
-- in_ledger_scope is deliberately THREE-VALUED. true = this vendor's spend belongs in QuotesDone's
-- book. false = it belongs to another entity. NULL = UNDECIDED, and undecided is reported, never
-- silently dropped and never guessed into the total. The mailbox swept below belongs to Dorata
-- Jewelries FZCO and carries bills for BOTH that business and QuotesDone (Dorata Trading Co. L.L.C.);
-- deciding which is which is not something a parser may infer from a receipt.
create table if not exists public.expense_vendor_billing_mailbox (
  id              bigserial primary key,
  vendor          text not null,
  mailbox         text not null references public.expense_billing_mailbox(mailbox),
  in_ledger_scope boolean,
  first_seen      date,
  last_seen       date,
  evidence        text not null,
  note            text,
  created_at      timestamptz not null default now(),
  unique (vendor, mailbox)
);

comment on table public.expense_vendor_billing_mailbox is
  'Which mailbox each vendor was OBSERVED billing, with the evidence that proved it. in_ledger_scope '
  'NULL means undecided: the charge is real and was seen, but whether it belongs to QuotesDone rather '
  'than a sibling entity has not been established, so it is named in the spend report instead of '
  'being guessed into or out of the total.';

-- These tables are read by SECURITY DEFINER reporting routines and written by the accountant seat.
-- Nothing anonymous needs them. Revoking from PUBLIC as well as from the two roles, because
-- `revoke ... from anon` is a silent no-op when the grant is actually held through PUBLIC.
revoke all on public.expense_billing_mailbox from public, anon, authenticated;
revoke all on public.expense_vendor_billing_mailbox from public, anon, authenticated;
revoke all on sequence public.expense_vendor_billing_mailbox_id_seq from public, anon, authenticated;
alter table public.expense_billing_mailbox        enable row level security;
alter table public.expense_vendor_billing_mailbox enable row level security;

-- ---------------------------------------------------------------------------------------------
-- 3. SEED: the three sources, as MEASURED on 9 Sep 2026
-- ---------------------------------------------------------------------------------------------
insert into public.expense_billing_mailbox (mailbox, description, reachable_by, is_swept, last_swept_on, note)
values
  ('expenses@mail.quotesdone.com',
   'The accountant''s own intake address. Receipts forwarded here are parsed and booked automatically.',
   'Resend inbound webhook + Resend inbound history API', true, date '2026-09-09',
   'Resend keeps inbound history for roughly one month, so the sweep is a WINDOW on recent mail, never the whole of it.'),
  ('founder Gmail sent folder',
   'The founder''s own record of what he forwarded to the accountant before Resend''s retention window aged it out.',
   'Gmail connector, search of sent mail', true, date '2026-09-09',
   'Covers the history the Resend window cannot reach. Only shows what he REMEMBERED to forward.'),
  ('management@doratajewelries.com',
   'Outlook mailbox. The card on file for several subscriptions bills this address DIRECTLY - it is never forwarded unless the founder does it by hand.',
   'Microsoft 365 connector, outlook_email_search', true, date '2026-09-09',
   'Added 9 Sep 2026 after Anthropic was found billing here for four months with only 3 of 6 receipts ever forwarded. '
   'This mailbox belongs to Dorata Jewelries FZCO and carries bills for that business as well as for QuotesDone.')
on conflict (mailbox) do update
  set description   = excluded.description,
      reachable_by  = excluded.reachable_by,
      is_swept      = excluded.is_swept,
      last_swept_on = excluded.last_swept_on,
      note          = excluded.note;

-- Every vendor found billing the Outlook mailbox between 1 May and 9 Sep 2026. Amounts are quoted
-- only where they were read directly off the receipt; where a receipt could not be opened that is
-- said plainly rather than estimated.
insert into public.expense_vendor_billing_mailbox
  (vendor, mailbox, in_ledger_scope, first_seen, last_seen, evidence, note)
values
  ('Anthropic', 'management@doratajewelries.com', true, date '2026-05-26', date '2026-08-23',
   'Six receipts, invoice series YXWTXUVD-0001..0006 (consecutive, so the series proves the set complete). '
   '0001 $105.00 26 May; 0002 $47.25 9 Jun; 0003 $105.00 26 Jun; 0004 $21.00 22 Jul; 0005 $200.32 23 Jul; 0006 $210.00 23 Aug.',
   'QuotesDone build tooling; the ledger already carried 0001-0003 via the founder''s 29 Jun forwards. '
   '0004-0006 booked 9 Sep 2026 from this mailbox. The plan changed on 23 Jul from Max 5x to Max 20x.'),

  ('SKYWORK AI PTE. LTD.', 'management@doratajewelries.com', null, date '2026-05-01', date '2026-06-06',
   'Three paid receipts read: #1046-9434 $34.99 paid 1 May 2026; #2321-5295 $49.99 6 May 2026; #2793-6296 $49.99 6 Jun 2026. '
   'Subscription cancelled 6 Jun 2026.',
   'UNDECIDED. A design/video/poster generation tool. Not attributable to QuotesDone from the receipt alone.'),

  ('Artguru', 'management@doratajewelries.com', null, date '2026-05-06', date '2026-05-06',
   'One paid receipt read: #2837-4514 $49.99 paid 6 May 2026.',
   'UNDECIDED. An image generation tool. Not attributable to QuotesDone from the receipt alone.'),

  ('Grok xAI', 'management@doratajewelries.com', null, date '2026-05-26', date '2026-05-26',
   'One paid receipt read: #2622-4616 $30.00 paid 26 May 2026, period 25 May - 24 Jun.',
   'UNDECIDED. An AI subscription. Could belong to either entity; the receipt does not say.'),

  ('DEWA', 'management@doratajewelries.com', null, date '2026-05-06', date '2026-06-06',
   'Two bill payment confirmations read: AED 58.07 on 6 May 2026 and AED 40.40 on 6 Jun 2026.',
   'UNDECIDED, and probably not QuotesDone - a premises utility, and QuotesDone has no premises of its own.'),

  ('Dubai Customs', 'management@doratajewelries.com', null, date '2026-08-25', date '2026-08-25',
   'Revenue Receipt -2837810, 25 Aug 2026, e-revenue receipt delivered as a PDF attachment. AMOUNT NOT READ.',
   'UNDECIDED and HELD. Customs clearance relates to physical goods movement, which QuotesDone does not do. '
   'No amount is recorded here because none was read.'),

  ('Network International', 'management@doratajewelries.com', null, date '2026-05-21', date '2026-06-02',
   'Three "Tax Invoice for the period" messages for NI services, periods 11-20 May and 21-31 May 2026. AMOUNTS NOT READ.',
   'UNDECIDED and HELD. Card acquiring services. No amount is recorded here because none was read.'),

  ('ADIB', 'management@doratajewelries.com', null, date '2026-05-13', date '2026-08-12',
   'Four "ADIB Monthly VAT Invoice" messages (13 May, 11 Jun, 9 Jul, 12 Aug 2026). The attachment is '
   'PASSWORD PROTECTED and could not be opened. AMOUNTS NOT READ.',
   'UNDECIDED and HELD. Bank charges. The password is the account RIM number, which this seat does not hold.')
on conflict (vendor, mailbox) do update
  set in_ledger_scope = excluded.in_ledger_scope,
      first_seen      = excluded.first_seen,
      last_seen       = excluded.last_seen,
      evidence        = excluded.evidence,
      note            = excluded.note;

-- The vendors the book already sees through the forwarding path, so the register describes the whole
-- picture rather than only the newly-found corner of it.
insert into public.expense_vendor_billing_mailbox
  (vendor, mailbox, in_ledger_scope, first_seen, last_seen, evidence, note)
select distinct e.vendor, 'expenses@mail.quotesdone.com', true,
       min(e.charged_on) over (partition by e.vendor),
       max(e.charged_on) over (partition by e.vendor),
       'Booked from a receipt that reached the accountant''s intake address.',
       'Registered 9 Sep 2026 from the entries already in public.expense_entries.'
  from public.expense_entries e
 where e.vendor is not null
on conflict (vendor, mailbox) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 4. THE BACKFILL: the three Anthropic receipts that never reached the accountant
-- ---------------------------------------------------------------------------------------------
-- Every amount below was read directly off the receipt body in the Outlook mailbox on 9 Sep 2026.
-- Nothing is derived, estimated, or reconstructed from a monthly rate.
--
-- The guard is deliberately on the ECONOMIC IDENTITY (vendor + charge date + amount + currency) and
-- not only on source_msg_id. The same charge forwarded to two mailboxes arrives with two different
-- message ids, so a key-only guard would happily book it twice. The existing 37 rows contain zero
-- such duplicates and this keeps it that way.
with candidate(vendor, category, amount, currency, charged_on, vat_amount, source_msg_id, note) as (
  values
    ('Anthropic', 'Subscription', 21.00::numeric, 'USD', date '2026-07-22', 1.00::numeric,
     'outlook:<0101019f8ab09d36-0a5c48e2-8b6f-432d-812c-33e98400d830-000000@us-west-2.amazonses.com>',
     'Anthropic, PBC receipt 2628-4225-9586 (invoice YXWTXUVD-0004), "Prepaid extra usage, Individual plan" qty 1. '
     'Subtotal $20.00, VAT - United Arab Emirates (5%) $1.00, total and amount paid $21.00. Read directly off the '
     'receipt in management@doratajewelries.com on 9 Sep 2026; this receipt was never forwarded to the accountant.'),
    ('Anthropic', 'Subscription', 200.32::numeric, 'USD', date '2026-07-23', 9.54::numeric,
     'outlook:<0101019f90b20036-62982630-d416-4ac7-965f-2a8a75da9551-000000@us-west-2.amazonses.com>',
     'Anthropic, PBC receipt 2461-7806-5600 (invoice YXWTXUVD-0005), period Jul 23 - Aug 23 2026. "Max plan - 20x" '
     '$200.00 less "Unused time on Max plan - 5x after 23 Jul 2026" -$9.22, subtotal $190.78, VAT - United Arab '
     'Emirates (5%) $9.54, total and amount paid $200.32. This is the upgrade from Max 5x to Max 20x. Read directly '
     'off the receipt in management@doratajewelries.com on 9 Sep 2026; never forwarded to the accountant.'),
    ('Anthropic', 'Subscription', 210.00::numeric, 'USD', date '2026-08-23', 10.00::numeric,
     'outlook:<010101a03090e489-4bc1648d-e974-4c36-8bf0-9788d55aecd6-000000@us-west-2.amazonses.com>',
     'Anthropic, PBC receipt 2763-0316-1687 (invoice YXWTXUVD-0006), period Aug 23 - Sep 23 2026. "Max plan - 20x" '
     'qty 1 $200.00, subtotal $200.00, VAT - United Arab Emirates (5%) $10.00, total and amount paid $210.00. Read '
     'directly off the receipt in management@doratajewelries.com on 9 Sep 2026; never forwarded to the accountant.')
)
insert into public.expense_entries
  (vendor, category, amount, currency, charged_on, vat_amount, source, source_msg_id, note)
select c.vendor, c.category, c.amount, c.currency, c.charged_on, c.vat_amount, 'receipt', c.source_msg_id, c.note
  from candidate c
 where not exists (select 1 from public.expense_entries e where e.source_msg_id = c.source_msg_id)
   and not exists (select 1 from public.expense_entries e
                    where lower(e.vendor) = lower(c.vendor)
                      and e.charged_on = c.charged_on
                      and e.amount = c.amount
                      and upper(e.currency) = upper(c.currency));

-- Post anything in the book that has not reached the ledger. fn_expense_post_to_gl is itself
-- idempotent - it returns the existing journal id rather than posting twice - so this is safe to
-- re-run and safe if another seat posted first.
select public.fn_expense_post_to_gl(e.id)
  from public.expense_entries e
 where not exists (select 1 from public.gl_journal g
                    where g.source = 'expense' and g.source_ref = e.id::text);

-- ---------------------------------------------------------------------------------------------
-- 5. THE SPEND REPORT LEARNS ABOUT MAILBOXES
-- ---------------------------------------------------------------------------------------------
-- CREATE OR REPLACE, so the ACL is preserved and must NOT be re-revoked here.
-- Sources 1 and 2 are unchanged, character for character. Source 3 is new.
create or replace function public.fn_accountant_spend_report_coverage()
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tz    text := 'Asia/Dubai';
  v_sweep record;
  v_back  record;
  v_cov   text := '';
  v_short text[] := '{}';
  v_mb        record;
  v_mb_seen   int := 0;
  v_mb_blind  int := 0;
  v_undecided int := 0;
  v_names     text;
begin
  select r.id, r.finished_at, r.counts, r.status into v_sweep
    from public.agent_runs r
   where r.agent = 'accountant' and r.counts->>'action' = 'expense_sweep'
   order by r.id desc limit 1;

  select r.id, r.finished_at, r.counts, r.status into v_back
    from public.agent_runs r
   where r.agent = 'accountant' and r.counts->>'action' = 'expense_backfill'
   order by r.id desc limit 1;

  -- ---- SOURCE 1: Resend's inbound history, which is what the live webhook and the sweep see. ----
  if v_sweep.id is null then
    v_cov := 'RESEND INBOUND: never swept. The expenses mailbox has never been read by this seat '
          || 'through Resend, so nothing here bounds how many messages arrived that way.';
    v_short := v_short || array['the Resend inbound mailbox has never been swept'];
  else
    v_cov := 'RESEND INBOUND: the last sweep (agent_runs #' || v_sweep.id || ', '
          || to_char(v_sweep.finished_at at time zone v_tz, 'DD Mon YYYY HH24:MI') || ' Asia/Dubai) read '
          || coalesce(v_sweep.counts->>'history_messages','?') || ' message(s) from Resend''s inbound history, of which '
          || coalesce(v_sweep.counts->>'to_expense_mailbox','?') || ' were addressed to expenses@mail.quotesdone.com. It booked '
          || coalesce(v_sweep.counts->>'booked','?') || ', found ' || coalesce(v_sweep.counts->>'already_booked','?')
          || ' already booked, held ' || coalesce(v_sweep.counts->>'held','?') || ', refused '
          || coalesce(v_sweep.counts->>'refused','?') || ' and failed on ' || coalesce(v_sweep.counts->>'failed','?') || '.'
          || ' Resend''s inbound retention is roughly one month, so that history is a WINDOW on recent '
          || 'mail, never the whole of it. Nothing older than the window was misaddressed or lost by us '
          || '- the provider simply stops keeping it.';
    if coalesce((v_sweep.counts->>'pages_capped')::boolean, false) then
      v_cov := v_cov || ' PAGING WAS CAPPED, so the history itself may be incomplete.';
      v_short := v_short || array['the sweep stopped at its page cap, so older messages may never have been read'];
    end if;
    if coalesce(v_sweep.counts->>'list_error','') <> '' then
      v_cov := v_cov || ' The listing reported an error: ' || (v_sweep.counts->>'list_error') || '.';
      v_short := v_short || array['the mailbox listing errored during the last sweep'];
    end if;
  end if;

  -- ---- SOURCE 2: the founder's own SENT folder, which is what survived the retention window. ----
  if v_back.id is null then
    v_cov := v_cov || E'\n\n' || 'FORWARDED HISTORY: never read. Everything the founder forwarded '
          || 'before Resend''s retention window has NOT been examined, so the total below covers only '
          || 'recent mail and is expected to be short.';
    v_short := v_short || array['the forwarded history older than Resend''s retention window has never been read'];
  else
    v_cov := v_cov || E'\n\n' || 'FORWARDED HISTORY: on '
          || to_char(v_back.finished_at at time zone v_tz, 'DD Mon YYYY HH24:MI') || ' Asia/Dubai (agent_runs #'
          || v_back.id || ') the accountant read the founder''s own record of what he forwarded - a '
          || 'search of his sent mail for ' || coalesce(v_back.counts->>'query','the expenses address')
          || ' returning ' || coalesce(v_back.counts->>'threads_found','?') || ' thread(s) covering '
          || coalesce(v_back.counts->>'period','the whole period') || '. All '
          || coalesce(v_back.counts->>'threads_read','?') || ' were opened and read. '
          || coalesce(v_back.counts->>'amounts_read','?') || ' printed an amount that could be read directly off the receipt; '
          || coalesce(v_back.counts->>'booked','?') || ' were booked here, '
          || coalesce(v_back.counts->>'already_booked','?') || ' were already in the book under their Resend keys, and '
          || coalesce(v_back.counts->>'held','?') || ' were held.';
    if coalesce(v_back.counts->>'date_by_corroboration','0') <> '0' then
      v_cov := v_cov || ' ' || (v_back.counts->>'date_by_corroboration')
            || ' receipt(s) printed an amount but no date, and were dated by matching to the unique '
            || 'source message in the same mailbox rather than by estimate; each says so in its own note.';
    end if;
    if coalesce((v_back.counts->>'more_pages')::boolean, false) then
      v_cov := v_cov || ' THE SEARCH REPORTED MORE RESULTS THAN IT RETURNED, so the forwarded history may be incomplete.';
      v_short := v_short || array['the forwarded-history search did not reach the end of its results'];
    end if;
  end if;

  -- ---- SOURCE 3: the mailboxes vendors bill DIRECTLY, which nobody has to remember to forward. ----
  --
  -- Added 9 Sep 2026. Sources 1 and 2 both describe the same pipe from a different end: mail that
  -- SOMEBODY FORWARDED. Neither can see a vendor that bills an address the accountant does not read,
  -- and neither would ever report that vendor as missing, because a source nobody looks at produces
  -- no evidence of its own absence. Anthropic billed management@doratajewelries.com for four months
  -- and three of its six receipts simply never existed as far as this book was concerned.
  --
  -- So coverage is now stated per MAILBOX, from a register, and a mailbox that is known but unread
  -- makes the report say so out loud instead of quietly totalling what it happens to hold.
  select count(*) filter (where is_swept),
         count(*) filter (where not is_swept)
    into v_mb_seen, v_mb_blind
    from public.expense_billing_mailbox;

  if v_mb_seen + v_mb_blind = 0 then
    v_cov := v_cov || E'\n\n' || 'BILLING MAILBOXES: no mailbox register exists, so nothing states '
          || 'which addresses a vendor bill can even arrive at. The total below is bounded by what '
          || 'was forwarded, which is not the same thing as what was spent.';
    v_short := v_short || array['there is no register of which mailboxes a vendor bills'];
  else
    select string_agg(mailbox || case when is_swept
                       then ' (read' || coalesce(' ' || to_char(last_swept_on, 'DD Mon YYYY'), '') || ')'
                       else ' (NOT READ)' end, '; ' order by is_swept desc, mailbox)
      into v_names from public.expense_billing_mailbox;

    v_cov := v_cov || E'\n\n' || 'BILLING MAILBOXES: a vendor bill only reaches this book if it lands '
          || 'somewhere the accountant reads. ' || v_mb_seen || ' of ' || (v_mb_seen + v_mb_blind)
          || ' known mailbox(es) were read: ' || v_names || '.';

    if v_mb_blind > 0 then
      v_cov := v_cov || ' A mailbox marked NOT READ receives vendor bills that this total CANNOT include.';
      v_short := v_short || array[(v_mb_blind || ' known billing mailbox(es) that the accountant cannot read')];
    end if;

    -- A charge that was SEEN but whose entity is undecided is the honest middle case. It is neither
    -- booked (which would claim it is ours) nor forgotten (which would claim it does not exist).
    select count(*) into v_undecided
      from public.expense_vendor_billing_mailbox where in_ledger_scope is null;

    if v_undecided > 0 then
      select string_agg(vendor, ', ' order by vendor) into v_names
        from public.expense_vendor_billing_mailbox where in_ledger_scope is null;
      v_cov := v_cov || ' ' || v_undecided || ' vendor(s) bill a mailbox that is read but have NOT been '
            || 'attributed to this company rather than to a sibling entity, so their spend is deliberately '
            || 'absent from the total above: ' || v_names || '. Each is recorded in '
            || 'public.expense_vendor_billing_mailbox with the evidence that was actually read.';
      v_short := v_short || array[(v_undecided || ' vendor(s) seen billing a read mailbox whose attribution to this company is undecided, so their spend is NOT in the total')];
    end if;
  end if;

  return jsonb_build_object('note', v_cov, 'shortfalls', to_jsonb(v_short),
    'sweep_run_id', v_sweep.id, 'sweep_at', v_sweep.finished_at, 'sweep_counts', v_sweep.counts,
    'backfill_run_id', v_back.id, 'backfill_at', v_back.finished_at, 'backfill_counts', v_back.counts,
    'mailboxes_read', v_mb_seen, 'mailboxes_unread', v_mb_blind, 'vendors_undecided', v_undecided);
end
$function$;
