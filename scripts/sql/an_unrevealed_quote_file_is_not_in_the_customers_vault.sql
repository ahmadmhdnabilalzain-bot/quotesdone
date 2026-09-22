-- AN UNREVEALED QUOTE'S FILE IS NOT IN THE CUSTOMER'S VAULT.
--
-- Customer-portal audit CP-02 and the supplier-portal audit, 22 Sep 2026 — the same leak found from
-- both sides, and it is a second door around the 3% reveal fee.
--
-- WHAT WAS MEASURED. trg_reg_quote_doc registers quotes.original_file_path in public.documents.
-- fn_customer_document_refs() returned EVERY non-draft quote of the customer's own RFQ, with the
-- `revealed` flag reported but never used as a filter. policy documents_customer_select grants any
-- row whose (ref_table, ref_id) that function returns, and customer_documents `get` then signs a
-- storage URL for it and returns documents.extracted with it. So a customer who had paid nothing
-- could download the supplier's own quotation PDF — letterhead, company name, contact block — and
-- read the text extracted from it. Live example when this was written: document 62933, a quote with
-- no transaction, whose file name contains the supplier's company name.
--
-- customer_api has always been right about this: it signs original_file_path only after the reveal
-- (customer_api reveal / supplier_history). The documents path was the way around it.
--
-- THE FIX IS ONE FILTER, IN THE FUNCTION BOTH PATHS GO THROUGH. The leads branch below already
-- demands a paid, revealed transaction; the quotes branch now does the same. Because the policy and
-- fn_customer_documents both read this function, the row disappears from the vault list, from the
-- search, from `get`, from the signed URL and from the extracted text in one change, instead of
-- four places that can drift. customer_documents also refuses a quotes document with no paid reveal
-- in its own code, so the refusal is stated where a reader of that action can see it.
--
-- WHAT THE CUSTOMER STILL HAS before the reveal: every figure, term and line of the quotation, as
-- customer_api my_inquiries and the comparison report serve them. What they do not have is the
-- supplier's own file, which carries the identity the fee exists to sell.
create or replace function public.fn_customer_document_refs()
returns table(ref_table text, ref_id text, source text, supplier_id bigint, supplier_name text, revealed boolean)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with me as (
    select c.id
      from public.customers c
     where lower(c.email) = lower(nullif(auth.email(), ''))
        or c.id = auth.uid()
     order by (lower(c.email) = lower(nullif(auth.email(), ''))) desc nulls last
     limit 1
  )
  -- the customer's own uploads
  select 'inquiries'::text, i.id::text, 'inquiry'::text, null::bigint, null::text, true
    from public.inquiries i join me on i.customer_id = me.id
  union all
  -- quotation files sent against their RFQs, and ONLY once the customer has paid to reveal that
  -- quote. A draft quote is not shown to the customer by customer_api, so its attachment is not
  -- shown here either; nor, since 22 Sep 2026, is an unrevealed one's (CP-02).
  select 'quotes'::text, q.id::text, 'quote'::text, q.supplier_id, l.company_name, true
    from public.quotes q
    join public.inquiries i on i.id = q.inquiry_id
    join me on i.customer_id = me.id
    join public.transactions t
      on t.quote_id = q.id and t.customer_id = me.id and t.revealed_at is not null
    left join public.leads l on l.id = q.supplier_id
   where coalesce(q.status, '') <> 'draft'
  union all
  -- supplier documents, and ONLY for a supplier this customer has paid to reveal
  select 'leads'::text, l.id::text, 'supplier'::text, l.id, l.company_name, true
    from public.leads l
   where exists (select 1 from public.transactions t join me on t.customer_id = me.id
                  where t.supplier_id = l.id and t.revealed_at is not null);
$fn$;

-- CREATE OR REPLACE keeps the existing ACL, and the routine was already closed to the roles that
-- must not call it directly; the revoke is repeated so the file states the whole grant.
revoke execute on function public.fn_customer_document_refs() from public, anon;
grant execute on function public.fn_customer_document_refs() to authenticated, service_role;

comment on function public.fn_customer_document_refs() is
  'The (ref_table, ref_id) pairs the signed-in customer owns: their own inquiries, the quotation files of quotes they have PAID to reveal, and the documents of suppliers they have revealed. documents_customer_select and fn_customer_documents both read it, so it is the one place the vault''s scope is decided (CP-02, 22 Sep 2026).';
