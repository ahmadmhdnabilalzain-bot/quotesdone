-- A RECEIPT FORWARDED TO THE EXPENSES MAILBOX REACHES THE LEDGER.
--
-- The founder, 9 Sep 2026: the accountant "collects expenses from the email
-- expenses@mail.quotesdone.com", and 1 Sep: "all expenses are shared on the email... that's the
-- source of truth as i forward all receipts there" and "the revenue is basically from stripe.
-- those are the only two sources for in and out flows."
--
-- The seat exists (the_company_gets_an_accountant_and_the_money_finally_has_an_owner.sql). Its
-- grant says: "Read receipts forwarded to expenses@mail.quotesdone.com, extract vendor, date,
-- amount, currency and tax, and file them against the chart of accounts... A receipt that cannot
-- be read is held for review, never guessed at." This file is the ledger half of that sentence.
-- resend_inbound is the mail half.
--
-- WHAT WAS MEASURED FIRST, 9 Sep 2026 (every number read from production, not assumed):
--   * expenses 0 · expense_entries 0 · ap_bills 0 · gl_journal 0 rows. gl_accounts 30,
--     gl_expense_map 6. The chart of accounts is built and completely unused.
--   * fn_gl_sync_business() section 3 ALREADY posts every expense_entries row to gl_journal,
--     mapping category through gl_expense_map with a 6300 fallback and converting USD at
--     gl_settings.usd_to_aed. Nothing here re-implements that.
--   * cron.job holds exactly ONE job in the entire project, and it is not this one. So nothing
--     ever CALLS fn_gl_sync_business: the posting capability has no entry point, which is why a
--     booked expense would sit in expense_entries and never reach the ledger. resend_inbound now
--     posts the entry it just booked, through fn_expense_post_to_gl below, at the moment it books
--     it. That is a real entry point rather than a schedule this session cannot prove runs.
--   * expense_entries had NO unique index of any kind. Idempotency was vendor+charged_on inside
--     the edge function, which cannot tell a redelivery from a genuine second same-day charge.
--
-- 1. THE IDEMPOTENCY KEY. source_msg_id carries the Resend inbound email id ('resend:<email_id>'),
--    which is stable across Resend's own retries of the same email. The unique index is PARTIAL so
--    the 0 existing rows and every manually-entered expense stay legal with a NULL key.
--    The edge function looks the key up UNFILTERED BY STATUS and inserts with
--    on-conflict-do-nothing. The index is NOT partial, deliberately: Postgres cannot infer a
--    partial index as the arbiter of a plain `on conflict (source_msg_id)`, which is the form
--    PostgREST emits, so a partial index would have made the conflict clause fail at runtime.
--    Under the default NULLS DISTINCT a plain unique index already allows unlimited NULL keys,
--    so every manually-entered expense stays legal. That is the fn_agent_action_work_sweep trap
--    avoided: a status-filtered guard over a unique key does not find a FAILED row that already
--    occupies the key, then fails to insert, and the work is lost with no record.
--    It cannot deadlock: there is one row, one index, no second table locked in the same
--    statement, and no network call inside the transaction — the storage upload finishes before
--    the insert begins.
--
-- 2. VAT AND THE TRN. gl_accounts has carried 1150 "VAT Recoverable (Input)" since 8 Jul and
--    nothing has ever debited it. A UAE tax invoice states 5% VAT and the supplier's 15-digit TRN;
--    receipt_parse now READS both and never derives them. When VAT is stated the journal splits
--    net to the expense account and VAT to 1150; when it is not, the whole amount is the expense.
--    Not reclaiming input VAT we have no evidence for is the correct answer, not a shortfall.
--
-- 3. THE HELD PATH GETS ITS OWNER. fn_receipt_hand_to_bookkeeper was written on 6 Sep for a
--    'bookkeeper' seat that has never existed in org_agents (ceo, customer_support,
--    sales_engineer, accountant). Its fallback set assigned_agent to NULL, so every held receipt
--    became an UNOWNED task. The accountant seat now exists and this is precisely its work, so the
--    routine prefers 'accountant'. create-or-replace, so the ACL is preserved.

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. The evidence a receipt carries, and the key that makes a redelivery harmless.
-- ---------------------------------------------------------------------------------------------
alter table public.expense_entries add column if not exists source_msg_id text;
alter table public.expense_entries add column if not exists vat_amount numeric(18,2);
alter table public.expense_entries add column if not exists vendor_trn text;

comment on column public.expense_entries.source_msg_id is
  'Stable id of the message this expense was read from (resend:<email_id>). Unique when present: the same forwarded receipt can never become two expenses. NULL for manually entered expenses.';
comment on column public.expense_entries.vat_amount is
  'VAT the receipt STATES, in the entry currency. NULL means the receipt stated none - never a computed 5%.';
comment on column public.expense_entries.vendor_trn is
  'The vendor 15-digit UAE Tax Registration Number, only when the document printed one.';

create unique index if not exists uq_expense_entries_source_msg
  on public.expense_entries (source_msg_id);

-- ---------------------------------------------------------------------------------------------
-- 2. One expense entry, posted to the chart of accounts.
--    fn_gl_sync_business() posts the whole book on demand and skips anything already posted
--    (its guard is: no gl_journal row with source='expense' and source_ref=<entry id>). This
--    routine posts exactly ONE entry under that same source/source_ref, so the two can never
--    double-post each other, and it adds the VAT split the bulk routine has no column for.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_expense_post_to_gl(p_entry_id bigint)
returns bigint
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare e record; fx numeric; acct text; amt_aed numeric(18,2); vat_aed numeric(18,2);
        net_aed numeric(18,2); jid bigint; lines jsonb;
begin
  select id, vendor, category, amount, upper(coalesce(currency,'AED')) as cur, vat_amount,
         coalesce(charged_on, created_at::date) as d
    into e
    from public.expense_entries where id = p_entry_id;
  if not found or coalesce(e.amount,0) <= 0 then return null; end if;

  -- already posted (by this routine or by fn_gl_sync_business): return it, never post twice
  select g.id into jid from public.gl_journal g
   where g.source='expense' and g.source_ref = e.id::text limit 1;
  if jid is not null then return jid; end if;

  select num_value into fx from public.gl_settings where key='usd_to_aed';
  fx := coalesce(fx, 3.6725);

  -- Same refusal as fn_gl_sync_business: a currency with no rate is NOT booked at 1:1. An
  -- understated ledger that says so beats a wrong one that does not.
  if e.cur not in ('AED','USD') then
    begin
      insert into public.founder_alerts(level, event, detail, channel)
      values ('warn','gl_unconvertible_currency',
              'Expense #'||e.id||' from '||coalesce(e.vendor,'?')||' is in '||e.cur||
              ', which has no rate in gl_settings, so it was NOT posted to the ledger.','system');
    exception when others then null; end;
    return null;
  end if;

  amt_aed := round(e.amount * case when e.cur='USD' then fx else 1 end, 2);
  vat_aed := round(coalesce(e.vat_amount,0) * case when e.cur='USD' then fx else 1 end, 2);
  if vat_aed <= 0 or vat_aed >= amt_aed then vat_aed := 0; end if;
  net_aed := amt_aed - vat_aed;

  acct := coalesce((select m.account_code from public.gl_expense_map m where m.category = e.category), '6300');

  lines := jsonb_build_array(jsonb_build_object('account', acct, 'debit', net_aed,
             'memo', coalesce(e.vendor,'')||' '||coalesce(e.category,'G&A')));
  if vat_aed > 0 then
    lines := lines || jsonb_build_array(jsonb_build_object('account','1150','debit',vat_aed,
               'memo','Input VAT stated on the receipt'));
  end if;
  lines := lines || jsonb_build_array(jsonb_build_object('account','1000','credit',amt_aed));

  return public.fn_gl_entry(e.d,
    'Expense: '||coalesce(e.vendor,'?')||' - '||coalesce(e.category,'G&A')
      ||case when e.cur='USD' then ' ('||e.amount||' USD @ '||fx||')' else '' end
      ||case when vat_aed > 0 then ' incl VAT '||vat_aed||' AED' else '' end,
    'expense', e.id::text, lines, 'expenses_inbox');
end
$function$;

revoke execute on function public.fn_expense_post_to_gl(bigint) from public;
grant execute on function public.fn_expense_post_to_gl(bigint) to service_role;

comment on function public.fn_expense_post_to_gl(bigint) is
  'Posts ONE expense_entries row to gl_journal under source=expense/source_ref=<id> - the same key fn_gl_sync_business uses, so neither can double-post the other. Splits stated VAT to 1150. Called by resend_inbound the moment a forwarded receipt is booked, because no cron job calls fn_gl_sync_business.';

-- ---------------------------------------------------------------------------------------------
-- 3. A held receipt now has an owner that exists.
--    Identical to the 6 Sep routine except for the two lines marked 9 SEP.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_receipt_hand_to_bookkeeper(p_inbound_id bigint, p_review_ids bigint[], p_reason text)
returns bigint
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare m record; v_owner text; v_task bigint;
begin
  select * into m from public.inbound_messages where id = p_inbound_id;
  if not found then return null; end if;

  -- one task per inbound email, however many times the email is redelivered
  select t.id into v_task from public.org_tasks t
   where t.detail like '[inbound_message:' || p_inbound_id || ']%'
     and t.status not in ('done', 'cancelled')
   order by t.id limit 1;

  if v_task is null then
    -- 9 SEP 2026: 'bookkeeper' has never been a row in org_agents, so every held receipt became an
    -- UNOWNED task. The accountant seat now exists and this is its named work; the old key is kept
    -- first so nothing changes if that seat is ever created.
    select o.agent_key into v_owner from public.org_agents o
     where o.agent_key in ('bookkeeper','accountant') and o.active and coalesce(o.available, true)
     order by case o.agent_key when 'bookkeeper' then 0 else 1 end limit 1;

    insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, decided_by,
                                  action_class, assigned_agent, priority, result)
    values ('finance',
            left('Book a forwarded receipt the parser could not read: ' || coalesce(m.subject, '(no subject)'), 200),
            '[inbound_message:' || p_inbound_id || '] ' || coalesce(p_reason, 'no amount could be read from the text')
              || E'\n\nFrom ' || coalesce(m.from_email, '?') || ' to ' || coalesce(m.to_email, '?') || ' at ' || m.created_at
              || '. Stored documents: doc_reviews ' || coalesce(array_to_string(p_review_ids, ', '), '(none)')
              || '. Read the document, book the expense in expense_entries (source ''receipt''), close the doc_reviews rows '
              || 'as auto_applied and the inbound row as replied. Only a Stripe refund reaches the founder.',
            'assigned', 'advisory', false, 'fn_receipt_hand_to_bookkeeper',
            'analysis', v_owner, 1,
            jsonb_build_object('source', jsonb_build_object('inbound_message_id', p_inbound_id,
                               'doc_review_ids', to_jsonb(coalesce(p_review_ids, '{}'::bigint[])),
                               'reason', p_reason, 'handed_at', now())))
    returning id into v_task;
  end if;

  update public.inbound_messages set owner_role = coalesce(v_owner, 'accountant') where id = p_inbound_id and owner_role is null;
  update public.doc_reviews set owner_role = coalesce(v_owner, 'accountant')
   where id = any(coalesce(p_review_ids, '{}'::bigint[])) and owner_role is null;
  return v_task;
end
$function$;

commit;
