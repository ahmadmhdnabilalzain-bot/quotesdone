-- A COMPANY BUYER IS BILLED AS HIS COMPANY, WITH ITS TRN AND HIS PO, AND THE REVEALED SUPPLIER IS TOLD WHOM TO ADDRESS.
-- Seat: sales_engineer (the reveal and the supplier's notice), with the accountant (the invoice prints it). Agent: CUSTOMER_W2
-- (wave 2 of the real-company hole hunt, 16 Nov 2026; scratchpad holes/CUSTOMER.md item 9).
--
-- MEASURED on origin/main 27969740b: the reveal invoice and receipt print "Billed to: name · email · phone"
-- (_shared/reveal_fee_documents.ts parties); public.customers has no company, TRN, billing address or PO field; nothing tells the
-- revealed supplier that the buyer needs a formal quotation addressed to his company for a purchase order. An FM company's buyer
-- cannot file an invoice made out to himself. The approvals tab stays removed (companies buy like individuals, ruling kept):
-- this asks nothing at sign-up, only an optional "bill to a company" at the reveal.
--
-- WHAT THIS CHANGES
--   1. public.reveal_bill_to: one row per quote the customer reveals with a company to bill (company, TRN, PO reference).
--      Service role only (RLS on, a deny-all policy).
--   2. fn_reveal_bill_to_record: the one writer. The quote must be his; the company is 2-120 characters; a TRN is the UAE's 15
--      digits (spaces and dashes ignored), or none; a PO reference is up to 60 characters. Empty company: the row is removed. A
--      change after the reveal re-tells the supplier (the invoice document is named by its contents, so it is made again).
--   3. fn_reveal_bill_to_tell_supplier: ONLY once the quote is revealed and paid (the company identifies the buyer: never
--      before the reveal, ruling 1683), the supplier is written in English through customer_support's door: address the formal
--      quotation and invoices to this company, TRN and PO. A trigger on public.transactions tells him at the reveal; it never
--      fails the sale (an error is only a warning, and the customer saving the company again tells the supplier).
-- Every new routine: SECURITY DEFINER, search_path pinned, EXECUTE revoked from public, anon and authenticated.
-- Probe: a_company_buyer_is_billed_as_his_company_with_its_trn_and_po_probe.sql (local Postgres 16).
-- Deploy order: apply this file, then deploy customer_api, reveal_invoice and supplier_api.

create table if not exists public.reveal_bill_to (
  quote_id uuid primary key references public.quotes(id) on delete cascade,
  customer_id uuid not null,
  company text not null check (length(btrim(company)) between 2 and 120),
  trn text check (trn is null or trn ~ '^[0-9]{15}$'),
  po_ref text check (po_ref is null or length(po_ref) <= 60),
  supplier_told_at timestamptz,
  supplier_told_md5 text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.reveal_bill_to is
  'The company a customer asked to be billed as when he revealed a quote (company, UAE TRN, his PO reference): printed on the reveal invoice and receipt, and passed to the supplier only after the reveal. Sales engineer and accountant, 16 Nov 2026.';
alter table public.reveal_bill_to enable row level security;
drop policy if exists reveal_bill_to_service_role_only on public.reveal_bill_to;
create policy reveal_bill_to_service_role_only on public.reveal_bill_to as permissive for all to public using (false) with check (false);
revoke all on public.reveal_bill_to from anon, authenticated;

create or replace function public.fn_reveal_bill_to_tell_supplier(p_quote uuid)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare b public.reveal_bill_to; t record; l public.leads; v_md5 text; v_d jsonb;
begin
  select * into b from public.reveal_bill_to where quote_id = p_quote for update;
  if not found then return jsonb_build_object('told', false, 'why', 'no company to bill'); end if;
  select tx.id, tx.inquiry_id, tx.supplier_id, i.rfq_no into t
    from public.transactions tx join public.inquiries i on i.id = tx.inquiry_id
   where tx.quote_id = p_quote and tx.revealed_at is not null limit 1;
  -- the company identifies the buyer: never before the reveal
  if t.id is null then return jsonb_build_object('told', false, 'why', 'not revealed'); end if;
  v_md5 := md5(concat_ws('|', b.company, b.trn, b.po_ref));
  if b.supplier_told_md5 = v_md5 then return jsonb_build_object('told', true, 'already', true); end if;
  select * into l from public.leads where id = t.supplier_id;
  if coalesce(nullif(btrim(l.claimed_by), ''), l.email, '') not like '%@%' then return jsonb_build_object('told', false, 'why', 'the supplier has no e-mail'); end if;
  v_d := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
    'type', 'reveal_bill_to', 'requested_by', 'sales_engineer', 'channel', 'email',
    'to_email', coalesce(nullif(btrim(l.claimed_by), ''), l.email), 'to_role', 'supplier', 'lead_id', l.id,
    'inquiry_id', t.inquiry_id, 'quote_id', p_quote, 'lang', 'en',
    'subject', 'Request ' || coalesce(t.rfq_no::text, '') || ': address your formal quotation to the buyer''s company',
    'body', 'Hello ' || coalesce(l.company_name, '') || ',' || chr(10) || chr(10)
      || 'The buyer who revealed your quotation on request ' || coalesce(t.rfq_no::text, '') || ' buys for a company. Please address your formal '
      || 'quotation, and any invoice for this job, to:' || chr(10) || chr(10)
      || '  Company: ' || b.company || chr(10)
      || coalesce('  TRN: ' || b.trn || chr(10), '')
      || coalesce('  Purchase order reference: ' || b.po_ref || chr(10), '')
      || chr(10) || 'Their contact details are on the job in your supplier portal.' || chr(10) || chr(10) || 'QuotesDone',
    'dedupe_key', 'reveal_bill_to:' || p_quote || ':' || v_md5)));
  update public.reveal_bill_to set supplier_told_at = now(), supplier_told_md5 = v_md5 where quote_id = p_quote;
  return jsonb_build_object('told', true, 'delivery', v_d);
end $fn$;
revoke execute on function public.fn_reveal_bill_to_tell_supplier(uuid) from public, anon, authenticated;
grant execute on function public.fn_reveal_bill_to_tell_supplier(uuid) to service_role;

create or replace function public.fn_reveal_bill_to_record(p_customer uuid, p_quote uuid, p_company text, p_trn text, p_po text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_owner uuid; v_company text := nullif(btrim(regexp_replace(coalesce(p_company, ''), '\s+', ' ', 'g')), '');
        v_trn text := nullif(regexp_replace(translate(coalesce(p_trn, ''), '٠١٢٣٤٥٦٧٨٩', '0123456789'), '[\s-]', '', 'g'), '');
        v_po text := nullif(btrim(coalesce(p_po, '')), ''); v_told jsonb;
begin
  select i.customer_id into v_owner from public.quotes q join public.inquiries i on i.id = q.inquiry_id where q.id = p_quote;
  if v_owner is null or v_owner is distinct from p_customer then return jsonb_build_object('ok', false, 'error', 'not_your_quote'); end if;
  if v_company is null then
    delete from public.reveal_bill_to where quote_id = p_quote;
    return jsonb_build_object('ok', true, 'bill_to', null);
  end if;
  if length(v_company) not between 2 and 120 then return jsonb_build_object('ok', false, 'error', 'company_invalid'); end if;
  if v_trn is not null and v_trn !~ '^[0-9]{15}$' then return jsonb_build_object('ok', false, 'error', 'trn_invalid'); end if;
  if v_po is not null and length(v_po) > 60 then return jsonb_build_object('ok', false, 'error', 'po_invalid'); end if;
  insert into public.reveal_bill_to (quote_id, customer_id, company, trn, po_ref)
  values (p_quote, p_customer, v_company, v_trn, v_po)
  on conflict (quote_id) do update set company = excluded.company, trn = excluded.trn, po_ref = excluded.po_ref, updated_at = now();
  v_told := public.fn_reveal_bill_to_tell_supplier(p_quote);
  return jsonb_build_object('ok', true, 'bill_to', jsonb_build_object('company', v_company, 'trn', v_trn, 'po_ref', v_po), 'supplier', v_told);
end $fn$;
revoke execute on function public.fn_reveal_bill_to_record(uuid, uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_reveal_bill_to_record(uuid, uuid, text, text, text) to service_role;

create or replace function public.fn_reveal_passes_the_bill_to_on()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if new.revealed_at is not null and new.quote_id is not null and exists (select 1 from public.reveal_bill_to b where b.quote_id = new.quote_id) then
    begin
      perform public.fn_reveal_bill_to_tell_supplier(new.quote_id);
    exception when others then
      -- the sale is recorded whatever happens here; the next save of the company by the customer tells the supplier again
      raise warning 'fn_reveal_passes_the_bill_to_on: % (quote %)', sqlerrm, new.quote_id;
    end;
  end if;
  return null;
end $fn$;
revoke execute on function public.fn_reveal_passes_the_bill_to_on() from public, anon, authenticated;
drop trigger if exists z26_reveal_passes_the_bill_to_on on public.transactions;
create trigger z26_reveal_passes_the_bill_to_on after insert or update of revealed_at on public.transactions
  for each row execute function public.fn_reveal_passes_the_bill_to_on();

select case
  when to_regclass('public.reveal_bill_to') is null then 'PROBE FAILED: the table is missing'
  when not exists (select 1 from pg_policies where tablename = 'reveal_bill_to') then 'PROBE FAILED: no policy'
  when has_function_privilege('anon', 'public.fn_reveal_bill_to_record(uuid, uuid, text, text, text)', 'execute')
    or has_function_privilege('authenticated', 'public.fn_reveal_bill_to_tell_supplier(uuid)', 'execute') then 'PROBE FAILED: a client can run them'
  else 'PROBE OK' end as verdict;
