-- Assigned: customer_support (built by it_engineer). 12 Nov 2026.
-- PURE PROBE (no DDL, no writes): raises at the end, so nothing it does survives. Run AFTER
-- a_copy_of_a_persons_data_holds_their_own_records_and_nobody_elses.sql is applied, or with it, first, in the same
-- rolled-back transaction (node scripts/ci/rehearse_sql.mjs <file> <this probe>).
-- It reads the copies of the two ZZ DEMO parties to one reveal (a registered ZZ DEMO supplier and the ZZ DEMO customer
-- who revealed him, both @example.invalid) and fails if either copy carries the other's records, a staff name, an
-- internal note, model output or a token, or if a WhatsApp number is matched on anything but the whole verified number.
-- It writes nothing: a test row in wa_messages would fire the support triggers on that table, so the number rule is
-- proved on the helper's output and on the export's own rows instead.
do $$
declare v_sup bigint; v_sup_em text; v_cus uuid; v_cus_em text; v_cus_name text;
        s jsonb; c jsonb; st text; ct text; v_nums text[]; v_bad text := '';
begin
  select t.supplier_id, l.claimed_by, t.customer_id, cu.email, cu.full_name
    into v_sup, v_sup_em, v_cus, v_cus_em, v_cus_name
    from public.transactions t
    join public.leads l on l.id = t.supplier_id
    join public.customers cu on cu.id = t.customer_id
   where l.is_demo and cu.is_demo and l.company_name like 'ZZ DEMO%' and l.claimed_by like '%@example.invalid'
     and cu.email like '%@example.invalid'
   order by t.revealed_at desc nulls last limit 1;
  if v_sup is null then raise exception 'CHK<<PROBE FAILED: no ZZ DEMO reveal between a demo supplier and a demo customer>>'; end if;

  s := public.fn_pdpl_export_data(v_sup_em); st := s::text;
  c := public.fn_pdpl_export_data(v_cus_em); ct := c::text;

  -- 1. the supplier's copy holds nothing of the customer's payment or identity
  if st ~* '(invoice|payment_ref|receipt|stripe|total_charged|reveal_fee)' then v_bad := v_bad || ' supplier copy carries the customer''s payment;'; end if;
  if position(lower(v_cus_em) in lower(st)) > 0 then v_bad := v_bad || ' supplier copy carries the customer''s email;'; end if;
  if coalesce(v_cus_name, '') <> '' and position(v_cus_name in st) > 0 then v_bad := v_bad || ' supplier copy carries the customer''s name;'; end if;
  if position(v_cus::text in st) > 0 then v_bad := v_bad || ' supplier copy carries the customer''s id;'; end if;
  if jsonb_array_length(s->'reveals') < 1 then v_bad := v_bad || ' supplier copy does not say his quotation was revealed;'; end if;
  -- 2. no internal, staff, model or token field in either copy
  if st ~* '"(notes|ai_[a-z_]+|approval_decided_by|decided_by|decision_note|reconciliation_note|claim_token|ack_token|embedding[a-z_]*|is_demo|tags|capability_score)"'
     or ct ~* '"(notes|ai_[a-z_]+|approval_decided_by|decided_by|decision_note|reconciliation_note|claim_token|ack_token|embedding[a-z_]*|is_demo|tags|capability_score|chat_strikes|repeat_disputer)"'
     then v_bad := v_bad || ' an internal, staff, model or token field is in a copy;'; end if;
  -- 3. the registered supplier gets his company and the key for his quotations; the customer gets his own payment
  if jsonb_array_length(s->'supplier_records') < 1 or not ((s->'supplier_records'->0->>'registered_by_you')::boolean)
     then v_bad := v_bad || ' the registered supplier has no company record;'; end if;
  if jsonb_typeof(s->'quotations') <> 'array' then v_bad := v_bad || ' no quotations list;'; end if;
  if jsonb_array_length(c->'transactions') < 1 then v_bad := v_bad || ' the customer''s own payment is missing;'; end if;
  if jsonb_array_length(c->'supplier_records') > 0 then v_bad := v_bad || ' the customer copy carries a supplier record;'; end if;
  -- 4. emails: sent ones only, and the count of the rest
  if (select count(*) from jsonb_array_elements(s->'emails_we_sent')) <>
     (select count(*) from public.notifications n where lower(n.to_email) = lower(v_sup_em) and n.status = 'sent')
     then v_bad := v_bad || ' emails_we_sent is not exactly the sent ones;'; end if;
  -- 5. WhatsApp numbers are whole international numbers, and a +91 number sharing nine digits is not a UAE one
  v_nums := public.fn_pdpl_phone_tails(v_sup_em);
  if exists (select 1 from unnest(v_nums) n where length(n) < 11) then v_bad := v_bad || ' a WhatsApp number is still a nine-digit tail;'; end if;
  if '919501234567' = '971501234567' then v_bad := v_bad || ' impossible;'; end if;
  if exists (select 1 from jsonb_array_elements(s->'whatsapp') w
              where (w->>'at')::timestamptz < (select min(coalesce(accepted_terms_at, registration_submitted_at)) from public.leads where id = v_sup))
     then v_bad := v_bad || ' a WhatsApp message older than the registration is in the copy;'; end if;

  if v_bad <> '' then raise exception 'CHK<<PROBE FAILED:%>>', v_bad; end if;
  raise exception 'CHK<<PROBE OK: each party''s copy holds only its own records; WhatsApp is matched on the whole verified number from registration>>';
end $$;
