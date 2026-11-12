-- Assigned: customer_support (built by it_engineer). 12 Nov 2026; extended the same night on the review of #1986.
-- PURE PROBE (no DDL): raises at the end, so every row it touches is rolled back. Run AFTER
-- a_copy_of_a_persons_data_holds_their_own_records_and_nobody_elses.sql is applied, or with it, first, in the same
-- rolled-back transaction (node scripts/ci/rehearse_sql.mjs <file> <this probe>).
--
-- WHO IT TOUCHES: only the two ZZ DEMO parties to one reveal (a registered ZZ DEMO supplier and the ZZ DEMO customer
-- who revealed him, both @example.invalid and is_demo), and WhatsApp rows already on file from a RESERVED fixture number
-- (fn_is_demo_phone: +971 50 000 00xx, written by the harness). It never writes wa_messages (that table's support
-- triggers would run); it moves the demo accounts' own phone fields and one demo chat row instead, inside this
-- transaction, and nothing it reads is printed: the only output is the verdict.
--
-- WHAT EACH STEP WOULD CATCH (each was a mutant of the routine that the first probe passed, review of #1986):
--   W0  positive control: a verified fixture number brings its messages (else every WhatsApp check below is vacuous)
--   W1  (m3) a number's messages from BEFORE that number was verified on the account are left out
--   W2  (item 2) a number verified by two accounts is left out of both copies, and each copy says so (whatsapp_withheld)
--   W3  (item 1) the scraped listing number leads.phone_e164 is never treated as verified
--   L1  (m4) the company is matched by its owner: a listed address equal to another person's verified e-mail gives that
--       person nothing, and the owner keeps his record when the listed address differs from his login
--   B1  (m5) a chat message the other side never received is not in the reader's copy; the sender's copy keeps it,
--       marked undelivered
--   N1  (m6) the customer's payments, refunds and requests carry neither the supplier's name nor his id
--   Q1  (x4, second review) a supplier's copy lists only HIS quotations: a competitor's quote on a request he also quoted
--       is not in it. Production has no second ZZ DEMO supplier (measured 12 Nov 2026), so the rival listing
--       (zz-probe-rival@example.invalid, is_demo) and its quote are created here, inside the rolled-back transaction.
--   P1  (x7, second review) the customer's mobile and WhatsApp number are nowhere in the supplier's copy
--
-- IT NEEDS THESE ZZ DEMO ROWS, and fails closed without them (a harness clean-up that removes them blocks the apply until
-- they are made again): a reveal (transactions) between a registered ZZ DEMO supplier and a ZZ DEMO customer, both
-- @example.invalid; a portal chat message the supplier sent that customer; a quotation of that supplier on a request;
-- and a WhatsApp row from a
-- reserved fixture number (+971 50 000 00xx) that no account has verified.
--   plus the first probe's checks: no payment, id, staff, note, model or token field crosses over; e-mails are the sent ones.
do $$
declare v_sup bigint; v_sup_em text; v_sup_name text; v_cus uuid; v_cus_em text; v_cus_name text;
        v_num text; v_t1 timestamptz; v_t2 timestamptz; v_n int; v_times timestamptz[];
        o_cus_wa text; o_cus_wav timestamptz; o_sup_wa text; o_sup_wav timestamptz; o_sup_e164 text;
        v_msg bigint; s jsonb; c jsonb; st text; ct text; v_bad text := '';
        v_cus_phone text; v_cus_wa text; v_iq uuid; v_rival bigint; v_mine int;
begin
  select t.supplier_id, l.claimed_by, l.company_name, t.customer_id, cu.email, cu.full_name
    into v_sup, v_sup_em, v_sup_name, v_cus, v_cus_em, v_cus_name
    from public.transactions t
    join public.leads l on l.id = t.supplier_id
    join public.customers cu on cu.id = t.customer_id
   where l.is_demo and cu.is_demo and l.company_name like 'ZZ DEMO%' and l.claimed_by like '%@example.invalid'
     and cu.email like '%@example.invalid'
   order by t.revealed_at desc nulls last limit 1;
  if v_sup is null then raise exception 'CHK<<PROBE FAILED: no ZZ DEMO reveal between a demo supplier and a demo customer>>'; end if;
  select whatsapp_phone, whatsapp_verified_at, phone into o_cus_wa, o_cus_wav, v_cus_phone from public.customers where id = v_cus;
  v_cus_wa := o_cus_wa;
  select whatsapp_phone, whatsapp_verified_at, phone_e164 into o_sup_wa, o_sup_wav, o_sup_e164 from public.leads where id = v_sup;

  -- ── the first probe's checks, on the fixtures as they are ──
  s := public.fn_pdpl_export_data(v_sup_em); st := s::text;
  c := public.fn_pdpl_export_data(v_cus_em); ct := c::text;
  if st ~* '(invoice|payment_ref|receipt|stripe|total_charged|reveal_fee)' then v_bad := v_bad || ' supplier copy carries the customer''s payment;'; end if;
  if position(lower(v_cus_em) in lower(st)) > 0 then v_bad := v_bad || ' supplier copy carries the customer''s email;'; end if;
  if coalesce(v_cus_name, '') <> '' and position(v_cus_name in st) > 0 then v_bad := v_bad || ' supplier copy carries the customer''s name;'; end if;
  if position(v_cus::text in st) > 0 then v_bad := v_bad || ' supplier copy carries the customer''s id;'; end if;
  if jsonb_array_length(s->'reveals') < 1 then v_bad := v_bad || ' supplier copy does not say his quotation was revealed;'; end if;
  if st ~* '"(notes|ai_[a-z_]+|approval_decided_by|decided_by|decision_note|reconciliation_note|claim_token|ack_token|embedding[a-z_]*|is_demo|tags|capability_score)"'
     or ct ~* '"(notes|ai_[a-z_]+|approval_decided_by|decided_by|decision_note|reconciliation_note|claim_token|ack_token|embedding[a-z_]*|is_demo|tags|capability_score|chat_strikes|repeat_disputer)"'
     then v_bad := v_bad || ' an internal, staff, model or token field is in a copy;'; end if;
  if jsonb_array_length(s->'supplier_records') < 1 or not ((s->'supplier_records'->0->>'registered_by_you')::boolean)
     then v_bad := v_bad || ' the registered supplier has no company record;'; end if;
  if jsonb_array_length(c->'transactions') < 1 then v_bad := v_bad || ' the customer''s own payment is missing;'; end if;
  if jsonb_array_length(c->'supplier_records') > 0 then v_bad := v_bad || ' the customer copy carries a supplier record;'; end if;
  if coalesce((s->>'emails_total')::int, -1) <> (select count(*) from public.notifications n where lower(n.to_email) = lower(v_sup_em) and n.status = 'sent')
     then v_bad := v_bad || ' emails_total is not exactly the sent ones;'; end if;

  -- ── P1 (x7): the customer's numbers, as stored and as whole international digits, are not in the supplier's copy ──
  if exists (select 1 from unnest(array[v_cus_phone, v_cus_wa]) x(p)
              where p is not null and (position(p in st) > 0
                 or st ~ ('(^|[^0-9])\+?' || public.fn_pdpl_norm_phone(p) || '([^0-9]|$)')
                 or st ~ ('(^|[^0-9])0' || right(public.fn_pdpl_norm_phone(p), 9) || '([^0-9]|$)')))
     then v_bad := v_bad || ' P1: supplier copy carries the customer''s phone or WhatsApp number;'; end if;

  -- ── Q1 (x4): a competitor quotes a request he quoted; his copy lists only his own ──
  select q.inquiry_id into v_iq from public.quotes q where q.supplier_id = v_sup order by q.created_at desc limit 1;
  if v_iq is null then v_bad := v_bad || ' Q1: the ZZ DEMO supplier has no quotation to probe;';
  else
    if not exists (select 1 from public.quotes where inquiry_id = v_iq and supplier_id <> v_sup) then
      -- is_demo is a generated column: the ZZ DEMO name and the @example.invalid address make it true (checked below)
      insert into public.leads (company_name, email, source)
      values ('ZZ DEMO Probe Rival Trading', 'zz-probe-rival@example.invalid', 'probe') returning id into v_rival;
      if not (select is_demo from public.leads where id = v_rival) then raise exception 'CHK<<PROBE FAILED: the rival listing is not marked demo>>'; end if;
      insert into public.quotes (inquiry_id, supplier_id, quote_amount, status, notes) values (v_iq, v_rival, 1, 'submitted', 'ZZ DEMO probe rival');
    end if;
    select count(*) into v_mine from public.quotes where supplier_id = v_sup;
    s := public.fn_pdpl_export_data(v_sup_em);
    if jsonb_array_length(s->'quotations') <> v_mine then v_bad := v_bad || ' Q1: the supplier''s copy lists quotations that are not his;'; end if;
  end if;

  -- ── N1 (m6): the customer's money and requests never name the supplier ──
  if position(lower(v_sup_name) in lower(coalesce(c->>'transactions', '') || coalesce(c->>'refunds', '') || coalesce(c->>'requests', '') || coalesce(c->>'request_files', ''))) > 0
     or (c->'transactions')::text ~ ('\m' || v_sup || '\M')
     then v_bad := v_bad || ' N1: the customer''s payments or requests name the supplier;'; end if;

  -- ── WhatsApp: a reserved fixture number with messages on file that no account has verified ──
  select n, ts, t1, t2 into v_num, v_times, v_t1, v_t2 from (
    select public.fn_pdpl_norm_phone(w.wa_from) n, array_agg(w.created_at) ts, min(w.created_at) t1, max(w.created_at) t2
      from public.wa_messages w where public.fn_is_demo_phone(w.wa_from) group by 1) f
   where n is not null
     and not exists (select 1 from public.customers x where public.fn_pdpl_norm_phone(x.phone) = f.n or public.fn_pdpl_norm_phone(x.whatsapp_phone) = f.n)
     and not exists (select 1 from public.leads x where x.claimed_by is not null
                       and (public.fn_pdpl_norm_phone(x.phone) = f.n or public.fn_pdpl_norm_phone(x.whatsapp_phone) = f.n))
   order by cardinality(ts) desc limit 1;
  if v_num is null then raise exception 'CHK<<PROBE FAILED: no reserved fixture number with WhatsApp rows to probe>>'; end if;
  v_n := cardinality(v_times);

  -- W0: verified on the customer before its messages: all of them are his
  update public.customers set whatsapp_phone = '+' || v_num, whatsapp_verified_at = v_t1 - interval '1 second' where id = v_cus;
  c := public.fn_pdpl_export_data(v_cus_em);
  if (select count(*) from jsonb_array_elements(c->'whatsapp') w where (w->>'at')::timestamptz = any (v_times)) <> least(v_n, 500)
     then v_bad := v_bad || ' W0: a verified number does not bring its messages;'; end if;
  -- W1 (m3): verified after its last message: none of them are his
  update public.customers set whatsapp_verified_at = v_t2 + interval '1 second' where id = v_cus;
  c := public.fn_pdpl_export_data(v_cus_em);
  if exists (select 1 from jsonb_array_elements(c->'whatsapp') w where (w->>'at')::timestamptz = any (v_times))
     then v_bad := v_bad || ' W1: messages from before the number was verified are in the copy;'; end if;
  -- W2 (item 2): the same number verified by the supplier too: in neither copy, and each copy says one was withheld
  update public.customers set whatsapp_verified_at = v_t1 - interval '1 second' where id = v_cus;
  update public.leads set whatsapp_phone = '+' || v_num, whatsapp_verified_at = v_t1 - interval '1 second' where id = v_sup;
  c := public.fn_pdpl_export_data(v_cus_em); s := public.fn_pdpl_export_data(v_sup_em);
  if exists (select 1 from jsonb_array_elements(c->'whatsapp') w where (w->>'at')::timestamptz = any (v_times))
     or exists (select 1 from jsonb_array_elements(s->'whatsapp') w where (w->>'at')::timestamptz = any (v_times))
     then v_bad := v_bad || ' W2: a number two accounts verified brings its chats into a copy;'; end if;
  if coalesce((c->>'whatsapp_withheld')::int, 0) < 1 or coalesce((s->>'whatsapp_withheld')::int, 0) < 1
     then v_bad := v_bad || ' W2: the copy does not say a shared number was left out;'; end if;
  -- W3 (item 1): only the scraped listing number is the fixture number: not his
  update public.customers set whatsapp_phone = o_cus_wa, whatsapp_verified_at = o_cus_wav where id = v_cus;
  update public.leads set whatsapp_phone = o_sup_wa, whatsapp_verified_at = o_sup_wav, phone_e164 = '+' || v_num where id = v_sup;
  s := public.fn_pdpl_export_data(v_sup_em);
  if exists (select 1 from jsonb_array_elements(s->'whatsapp') w where (w->>'at')::timestamptz = any (v_times))
     then v_bad := v_bad || ' W3: the scraped listing number counts as verified;'; end if;
  -- the copy above sees it only if its messages fall after the account's dates; the list of his numbers sees it always
  if exists (select 1 from public.fn_pdpl_whatsapp_numbers(v_sup_em) x where x.num = v_num)
     then v_bad := v_bad || ' W3: the scraped listing number is among his verified numbers;'; end if;
  update public.leads set phone_e164 = o_sup_e164 where id = v_sup;

  -- ── L1 (m4): the listed address is the customer's verified e-mail; the owner signs in with another ──
  update public.leads set email = v_cus_em where id = v_sup;
  c := public.fn_pdpl_export_data(v_cus_em); s := public.fn_pdpl_export_data(v_sup_em);
  if jsonb_array_length(c->'supplier_records') > 0 then v_bad := v_bad || ' L1: a listed address hands another person the owner''s company record;'; end if;
  if jsonb_array_length(s->'supplier_records') < 1 then v_bad := v_bad || ' L1: the owner loses his record when the listed address differs;'; end if;

  -- ── B1 (m5): the supplier's message in this conversation was never delivered ──
  select id into v_msg from public.messages where supplier_id = v_sup and customer_id = v_cus and sender = 'supplier' order by id limit 1;
  if v_msg is null then v_bad := v_bad || ' B1: no demo chat message to probe;';
  else
    update public.messages set blocked = true where id = v_msg;
    c := public.fn_pdpl_export_data(v_cus_em); s := public.fn_pdpl_export_data(v_sup_em);
    if (select count(*) from jsonb_array_elements(c->'portal_chat') m
         where (m->>'at')::timestamptz = (select created_at from public.messages where id = v_msg) and m->>'from' = 'supplier') > 0
       then v_bad := v_bad || ' B1: the reader''s copy carries a message he never received;'; end if;
    if (select count(*) from jsonb_array_elements(s->'portal_chat') m
         where (m->>'at')::timestamptz = (select created_at from public.messages where id = v_msg) and (m->>'delivered')::boolean = false) <> 1
       then v_bad := v_bad || ' B1: the sender''s copy lost his own undelivered message;'; end if;
  end if;

  if v_bad <> '' then raise exception 'CHK<<PROBE FAILED:%>>', v_bad; end if;
  raise exception 'CHK<<PROBE OK: each copy holds only its owner''s records; WhatsApp by whole verified number, from its own verification, never shared or scraped; company by owner; undelivered chat only to its sender>>';
end $$;
