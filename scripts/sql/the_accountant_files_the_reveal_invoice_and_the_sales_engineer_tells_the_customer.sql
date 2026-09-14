-- THE ACCOUNTANT FILES THE REVEAL INVOICE, AND THE SALES ENGINEER TELLS THE CUSTOMER
-- 14 Sep 2026. Agent: accountant (filing) -> sales_engineer (the customer's voice).
--
-- Founder, 14 Sep 2026: "when a customer pays the reveal fee, a copy of stripe invoice should be
-- already showing in the portal in the right tab. so he can click it anytime and it would open the
-- pdf from stripe". Same day: "anything related to payment is under the accountant agent. and the
-- accountant need to be in communication back and forth with the sales agent. its one company
-- eventually." And: "make sure its 3% plus stripe fees included"; refunds return everything the
-- customer paid; "our company is not vat registered so for our reveal fee there is no vat".
--
-- MEASURED BEFORE (production, 14 Sep 2026): stripe_checkout already set invoice_creation, and
-- stripe_webhook already attached invoice id / invoice_pdf / hosted_invoice_url and a stored copy in
-- finance-docs through fn_transaction_attach_invoice. 0 transactions exist. What was missing: the
-- customer could not reach any of it (nothing in documents, nothing on the card), the charge had no
-- processing line, and nothing told the sales engineer the document existed.
--
-- WHAT THIS FILE ADDS
--   1. transactions.processing_fee / total_charged / stripe_fee_fils / stripe_fee_details: the full
--      amount a refund returns, its breakdown, and what Stripe actually kept.
--   2. fn_accountant_files_reveal_invoice (accountant): when the stored Stripe PDF lands on a sale,
--      file it into the customer's Documents vault (kind 'invoice', against the request) and hand
--      off to the sales engineer through the estate's existing inbox (agent_actions kind 'handoff',
--      read by fn_agent_handoff_inbox), with the fact recorded on company_event (invoice.issued).
--   3. fn_sales_engineer_tells_customer_invoice_ready (sales_engineer): the deterministic half of that
--      seat's job - queue the customer's "your invoice is ready" message and close the handoff. The
--      customer hears the sales engineer, never the accountant.
-- The handoff is the estate's existing mechanism; no parallel queue is built.

-- ── 1. THE AMOUNTS A REFUND RETURNS ──────────────────────────────────────────────────────────────
alter table public.transactions
  add column if not exists processing_fee     numeric(12,2),
  add column if not exists total_charged      numeric(12,2),
  add column if not exists stripe_fee_fils    bigint,
  add column if not exists stripe_fee_details jsonb;

comment on column public.transactions.processing_fee is
  'Card-processing line charged to the customer on top of the 3% reveal fee (_shared/reveal_fee.ts). '
  'reveal_fee stays the 3% base. No VAT on either line: the company is not VAT-registered.';
comment on column public.transactions.total_charged is
  'Everything the customer paid (reveal_fee + processing_fee), in AED. A refund returns this whole '
  'amount (founder, 14 Sep 2026); QuotesDone absorbs the Stripe fee.';
comment on column public.transactions.stripe_fee_fils is
  'What Stripe actually kept, read from the balance transaction by stripe_webhook. Written once.';

-- ── 2. THE ACCOUNTANT FILES IT ───────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_files_reveal_invoice()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_doc bigint;
begin
  if new.doc_path is null or new.doc_path !~ '^invoices/' then return new; end if;
  if tg_op = 'UPDATE' and old.doc_path is not distinct from new.doc_path then return new; end if;

  -- (bucket, path) is UNIQUE, so a replayed attach files nothing twice and hands off nothing twice.
  insert into public.documents (bucket, path, file_name, kind, ref_table, ref_id, mime, status)
  values ('finance-docs', new.doc_path,
          coalesce(nullif(new.doc_name, ''), 'Invoice ' || coalesce(new.stripe_invoice_number, '') || '.pdf'),
          'invoice', 'inquiries', new.inquiry_id::text, 'application/pdf', 'done')
  on conflict (bucket, path) do nothing
  returning id into v_doc;
  if v_doc is null then return new; end if;

  perform public.fn_emit('invoice.issued', 'transaction', new.id::text, 'accountant',
    jsonb_build_object('document_id', v_doc, 'quote_id', new.quote_id, 'inquiry_id', new.inquiry_id,
                       'customer_id', new.customer_id, 'invoice_id', new.stripe_invoice_id,
                       'invoice_number', new.stripe_invoice_number, 'total_charged', new.total_charged));

  insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
  values ('sales_engineer', 'handoff', 'pending', 'low',
          'Reveal invoice filed - tell the customer it is ready',
          'The Stripe invoice is in the customer''s Documents and on the revealed quote card.',
          jsonb_build_object('from', 'accountant', 'from_name', 'Accountant', 'subject', 'reveal_invoice',
                             'transaction_id', new.id, 'quote_id', new.quote_id, 'inquiry_id', new.inquiry_id,
                             'customer_id', new.customer_id, 'document_id', v_doc,
                             'invoice_number', new.stripe_invoice_number),
          'transactions', new.id::text);
  return new;
end
$fn$;

revoke execute on function public.fn_accountant_files_reveal_invoice() from public, anon, authenticated;

drop trigger if exists trg_accountant_files_reveal_invoice on public.transactions;
create trigger trg_accountant_files_reveal_invoice
  after insert or update of doc_path on public.transactions
  for each row execute function public.fn_accountant_files_reveal_invoice();

-- ── 3. THE SALES ENGINEER TELLS THE CUSTOMER ─────────────────────────────────────────────────────
create or replace function public.fn_sales_engineer_tells_customer_invoice_ready()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  c record;
  v_ar boolean;
begin
  if new.kind <> 'handoff' or coalesce(new.detail->>'subject', '') <> 'reveal_invoice' then return new; end if;
  select id, email, locale into c from public.customers where id = (new.detail->>'customer_id')::uuid;
  if c.email is not null and c.email ~ '@' then
    v_ar := coalesce(c.locale, 'en') like 'ar%';
    insert into public.notifications (type, to_email, to_role, inquiry_id, quote_id, subject, body)
    values ('invoice_ready', c.email, 'customer',
            (new.detail->>'inquiry_id')::uuid, (new.detail->>'quote_id')::uuid,
            case when v_ar then 'فاتورتك جاهزة' else 'Your invoice is ready' end,
            case when v_ar
              then 'فاتورة رسوم الكشف التي دفعتها أصبحت في حسابك على QuotesDone. افتحها في أي وقت من زر «الفاتورة (PDF)» على العرض الذي كشفته، أو من «المستندات» ضمن «الفواتير».'
              else 'The invoice for the reveal fee you paid is now in your QuotesDone account. Open it any time from the "Invoice (PDF)" button on the quote you revealed, or under Invoices in Documents.'
            end);
  end if;
  update public.agent_actions
     set status = 'done', decided_at = now(), decided_by = 'sales_engineer'
   where id = new.id;
  return new;
end
$fn$;

revoke execute on function public.fn_sales_engineer_tells_customer_invoice_ready() from public, anon, authenticated;

drop trigger if exists trg_sales_engineer_tells_customer_invoice_ready on public.agent_actions;
create trigger trg_sales_engineer_tells_customer_invoice_ready
  after insert on public.agent_actions
  for each row execute function public.fn_sales_engineer_tells_customer_invoice_ready();

-- ── 4. WHO OWNS WHAT ─────────────────────────────────────────────────────────────────────────────
-- public.function_owner is the ledger of DEPLOYED EDGE FUNCTIONS (every_deployed_function_has_an_owner
-- fails on a row with no deployed function), so these two routines carry their owner in their own
-- comment, and the edge functions on the path (stripe_checkout, stripe_webhook, stripe_confirm,
-- reveal_invoice) are already owner = accountant there.
comment on function public.fn_accountant_files_reveal_invoice() is
  'Owner: accountant. Files the stored Stripe reveal invoice into the customer''s Documents (kind '
  'invoice) and hands off to sales_engineer via agent_actions kind handoff; records invoice.issued.';
comment on function public.fn_sales_engineer_tells_customer_invoice_ready() is
  'Owner: sales_engineer. Takes the accountant''s reveal_invoice handoff, queues the customer''s '
  '"your invoice is ready" message and closes the handoff. The customer never hears the accountant.';
