-- PROBE: A SUPPLIER CANNOT RE-PRICE A QUOTE ON A REQUEST THAT HAS ENDED.
-- Seat: sales_engineer. 10 Nov 2026. Pure probe: no DDL, never applied. Run after
-- a_supplier_cannot_reprice_a_quote_on_a_request_that_has_ended.sql (or concatenated after it). It always raises, so
-- every row is rolled back. The supplier is a ZZ DEMO fixture on a reserved +97150000014x number, confirmed as its
-- WhatsApp ('same' + owner_phone_verified), checked unused by any real row first.
-- PROBE OK only if a quote on a completed, an expired and a lost request is refused and left at its price, and one on an
-- open request is re-priced.
do $probe$
declare
  fails text := ''; v jsonb; c uuid := gen_random_uuid(); s1 bigint; st text; u uuid; q uuid; ph text := '+971500000146';
begin
  if exists (select 1 from public.leads l where right(regexp_replace(coalesce(l.phone, '') || coalesce(l.whatsapp_phone, ''), '[^0-9]', '', 'g'), 9) = '500000146')
     or exists (select 1 from public.customers x where right(regexp_replace(coalesce(x.phone, '') || coalesce(x.whatsapp_phone, ''), '[^0-9]', '', 'g'), 9) = '500000146') then
    raise exception 'CHK<<PROBE FAILED: a real row already holds the fixture number>>';
  end if;
  insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, signed_terms_url, locale, created_at)
  values (c, 'ZZ DEMO Reprice Customer', 'zz-demo-reprice@example.invalid', '+971500000147', true, true, 'demo://terms', 'en', now() - interval '30 days');
  insert into public.leads (company_name, email, phone, whatsapp_opt, owner_phone_verified)
  values ('ZZ DEMO Reprice Supplier', 'zz-demo-reprice-s1@example.invalid', ph, 'same', true) returning id into s1;
  foreach st in array array['completed', 'expired', 'lost', 'quoted'] loop
    u := gen_random_uuid(); q := gen_random_uuid();
    insert into public.inquiries (id, customer_id, category, emirate, summary, status, lang, created_at, scope_type)
    values (u, c, 'plumbing', 'Dubai', 'ZZ DEMO reprice probe ' || st, 'sent', 'en', now() - interval '20 days', 'single');
    insert into public.quote_items (quote_id, line_no, description, brand, model, specification, qty, unit, unit_price, labour)
    values (q::text, 1, 'ZZ DEMO heater and labour', 'ZZ DEMO Brand', 'ZZ-1', '80 litre electric', 1, 'lot', 4000, 500);
    insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status, created_at, warranty, lead_time, payment_terms, exclusions, validity)
    values (q, u, s1, 4500, 'submitted', now() - interval '15 days', '1 year', '1 week', '50% advance', 'civil works', '30 days');
    update public.quote_quality_hold set released_at = now(), release_reason = 'waited_24h' where quote_id = q;
    update public.quotes set status = 'submitted' where id = q;
    update public.inquiries set status = st where id = u;
    v := public.fn_supplier_apply_change('whatsapp:' || ph, 'quote_price', '4700', 'ZZ DEMO change my price to 4700', q, 'whatsapp');
    if st = 'quoted' then
      if not coalesce((v->>'ok')::boolean, false) or (select quote_amount from public.quotes where id = q) <> 4700 then fails := fails || ' open:not_repriced(' || v::text || ')'; end if;
    elsif coalesce((v->>'ok')::boolean, true) or (select quote_amount from public.quotes where id = q) <> 4500 then
      fails := fails || ' ' || st || ':repriced(' || v::text || ')';
    end if;
  end loop;
  if fails <> '' then raise exception 'CHK<<PROBE FAILED:%>>', fails; end if;
  raise exception 'CHK<<PROBE OK>>';
end $probe$;
