-- PROBE: A COMPANY BUYER IS BILLED AS HIS COMPANY, WITH ITS TRN AND HIS PO, AND THE REVEALED SUPPLIER IS TOLD WHOM TO ADDRESS.
-- Seat: sales_engineer. Agent: CUSTOMER_W2, 16 Nov 2026. Pure probe: no DDL, never applied. Run after
-- a_company_buyer_is_billed_as_his_company_with_its_trn_and_po.sql on a LOCAL Postgres 16. It always raises, so every row it
-- writes is rolled back. Every party is a ZZ DEMO fixture on @example.invalid.
-- PROBE OK only if
--   1. another customer cannot set the company on his quote; a 14-digit TRN and a 61-character PO are refused; a TRN written with
--      spaces, dashes and Arabic-Indic digits is stored as its 15 digits;
--   2. before the reveal the supplier is told nothing (the company identifies the buyer);
--   3. at the reveal the supplier is told the company, the TRN and the PO, once; saving the same again tells nobody; a new PO tells
--      him again; an empty company removes the row.
do $probe$
declare fails text := ''; c uuid := gen_random_uuid(); c2 uuid := gen_random_uuid(); i uuid := gen_random_uuid(); q uuid := gen_random_uuid();
        s bigint; v jsonb; n int;
begin
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
  values ('delivery.request', 'sales_engineer', 'customer_support', 'probe copy of the production row', 'fn_customer_support_acts_on_handoff', null, false,
          'scripts/sql/the_it_engineer_closes_every_loop_it_opens.sql')
  on conflict (type, from_seat, to_seat) do nothing;
  insert into public.customers (id, full_name, email, locale) values (c, 'ZZ DEMO Facility Buyer', 'zz-demo-billto-c@example.invalid', 'en'),
                                                                   (c2, 'ZZ DEMO Someone Else', 'zz-demo-billto-c2@example.invalid', 'en');
  insert into public.leads (company_name, email) values ('ZZ DEMO Bill Supplier', 'zz-demo-billto-s@example.invalid') returning id into s;
  insert into public.inquiries (id, customer_id, category, emirate, summary, status, lang) values (i, c, 'Painting', 'Dubai', 'ZZ DEMO repaint offices', 'quoted', 'en');
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status) values (q, i, s, 20000, 'draft');

  -- 1. the one writer's checks
  v := public.fn_reveal_bill_to_record(c2, q, 'ZZ DEMO Intruder LLC', null, null);
  if coalesce(v->>'error', '') <> 'not_your_quote' then fails := fails || ' [1: another customer: ' || v::text || ']'; end if;
  v := public.fn_reveal_bill_to_record(c, q, 'ZZ DEMO Facilities LLC', '10012345678900', null);
  if coalesce(v->>'error', '') <> 'trn_invalid' then fails := fails || ' [1: 14 digits: ' || v::text || ']'; end if;
  v := public.fn_reveal_bill_to_record(c, q, 'ZZ DEMO Facilities LLC', null, repeat('P', 61));
  if coalesce(v->>'error', '') <> 'po_invalid' then fails := fails || ' [1: long PO: ' || v::text || ']'; end if;
  v := public.fn_reveal_bill_to_record(c, q, '  ZZ DEMO   Facilities LLC ', '100-1234-٥٦٧٨-٩٠٠٣', 'PO-7781');
  if not coalesce((v->>'ok')::boolean, false) or (select trn from public.reveal_bill_to where quote_id = q) <> '100123456789003'
     or (select company from public.reveal_bill_to where quote_id = q) <> 'ZZ DEMO Facilities LLC' then fails := fails || ' [1: not stored as written: ' || v::text || ']'; end if;

  -- 2. before the reveal: nothing to the supplier
  if exists (select 1 from public.notifications where lead_id = s and type = 'reveal_bill_to') then fails := fails || ' [2: the supplier was told before the reveal]'; end if;

  -- 3. the reveal
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, fee_status, revealed_at, refund_deadline)
  values (q, i, s, c, 20000, 'paid', now(), now() + interval '5 days');
  select count(*) into n from public.notifications where lead_id = s and type = 'reveal_bill_to'
     and body like '%Company: ZZ DEMO Facilities LLC%' and body like '%TRN: 100123456789003%' and body like '%Purchase order reference: PO-7781%';
  if n <> 1 then fails := fails || ' [3: the supplier was told ' || n || ' times at the reveal]'; end if;
  v := public.fn_reveal_bill_to_record(c, q, 'ZZ DEMO Facilities LLC', '100123456789003', 'PO-7781');
  select count(*) into n from public.notifications where lead_id = s and type = 'reveal_bill_to';
  if n <> 1 then fails := fails || ' [3: the same company told again (' || n || ')]'; end if;
  v := public.fn_reveal_bill_to_record(c, q, 'ZZ DEMO Facilities LLC', '100123456789003', 'PO-7790');
  select count(*) into n from public.notifications where lead_id = s and type = 'reveal_bill_to' and body like '%PO-7790%';
  if n <> 1 then fails := fails || ' [3: a new PO was not told]'; end if;
  v := public.fn_reveal_bill_to_record(c, q, '', null, null);
  if exists (select 1 from public.reveal_bill_to where quote_id = q) then fails := fails || ' [3: an empty company did not remove it]'; end if;

  if fails <> '' then raise exception 'CHK<<PROBE FAILED:%>>', fails; end if;
  raise exception 'CHK<<PROBE OK>>';
end $probe$;
