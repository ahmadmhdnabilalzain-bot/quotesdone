-- PROBE: A CHANGE TO A SENT REQUEST IS A REVISION, EVERY QUOTE NAMES THE REVISION IT PRICED, AND EVERY SUPPLIER IS TOLD.
-- Seat: sales_engineer. Agent: CUSTOMER_W2, 16 Nov 2026. Pure probe: no DDL, never applied. Run after
-- a_change_to_a_sent_request_is_a_revision_every_quote_names_and_every_supplier_is_told.sql on a LOCAL Postgres 16. It always
-- raises, so every row it writes is rolled back. Every party is a ZZ DEMO fixture on @example.invalid. No model is called: the
-- sales engineer's reading is passed to fn_reason_held_resolve as the model would return it.
-- PROBE OK only if
--   1. a request posted three days ago is still editable (no one-hour clock); budget + needed-by date make revision 2, both
--      live quotes go back to draft keeping priced_revision 1, each quoting supplier is told "Budget: ... -> ..." and the date,
--      the supplier who had not quoted is told to quote revision 2, inquiry_revision records both fields;
--   2. a re-submitted quote names revision 2 and loses its stale mark; a new quote names revision 2;
--   3. a past date and an unchanged patch are refused / record nothing;
--   4. the model's 'revise' reading of a customer note (required_by, an emirate in lower case, a budget in Arabic-Indic digits,
--      an emirate that is not one of the seven) makes revision 3 with the valid fields, drops the invalid one, scrubs the
--      customer's phone from the change line, and confirms the change to the customer in Arabic (his request's language);
--   5. 'addendum_only' changes nothing; a choice that is not an option raises;
--   6. a customer note on a sent request files nothing for a fixture (fn_reason_hold) and does not fail the insert.
do $probe$
declare
  fails text := ''; c uuid := gen_random_uuid(); i uuid := gen_random_uuid(); q1 uuid := gen_random_uuid(); q2 uuid := gen_random_uuid();
  q3 uuid := gen_random_uuid(); s1 bigint; s2 bigint; s3 bigint; v jsonb; n int; h bigint; t text; r record; nid bigint;
begin
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  -- the delivery door's rows production holds (SELECT, 16 Nov 2026); a bare local schema has none
  insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
  select 'delivery.request', s, 'customer_support', 'probe copy of the production row', 'fn_customer_support_acts_on_handoff', null, false,
         'scripts/sql/the_it_engineer_closes_every_loop_it_opens.sql'
    from unnest(array['sales_engineer', 'customer_support']) s
  on conflict (type, from_seat, to_seat) do nothing;
  insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, locale, created_at)
  values (c, 'ZZ DEMO Revision Customer', 'zz-demo-rev-c@example.invalid', '+971500000141', true, true, 'ar', now() - interval '5 days');
  insert into public.leads (company_name, email) values ('ZZ DEMO Rev Supplier One', 'zz-demo-rev-s1@example.invalid') returning id into s1;
  insert into public.leads (company_name, email) values ('ZZ DEMO Rev Supplier Two', 'zz-demo-rev-s2@example.invalid') returning id into s2;
  insert into public.leads (company_name, email) values ('ZZ DEMO Rev Supplier Three', 'zz-demo-rev-s3@example.invalid') returning id into s3;
  insert into public.inquiries (id, customer_id, category, emirate, summary, budget, required_by, status, lang, created_at)
  values (i, c, 'Painting', 'Dubai', 'ZZ DEMO paint two bedrooms', 'AED 20,000', ((now() at time zone 'Asia/Dubai')::date + 20), 'sent', 'ar', now() - interval '3 days');
  insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, sent_at, match_reason)
  select i, s, 0.9, now() - interval '70 hours', 'ZZ DEMO probe' from unnest(array[s1, s2, s3]) s;
  insert into public.quote_items (quote_id, line_no, description, brand, model, specification, qty, unit, unit_price, labour)
  select q::text, 1, 'ZZ DEMO paint and labour', 'ZZ DEMO Brand', 'ZZ-1', 'two coats emulsion', 1, 'lot', a, 500
    from (values (q1, 18000), (q2, 21000)) x(q, a);
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status, created_at, warranty, lead_time, payment_terms, exclusions, validity)
  values (q1, i, s1, 18000, 'submitted', now() - interval '60 hours', '1 year', '5 days', '50% advance', 'furniture moving', '30 days'),
         (q2, i, s2, 21000, 'submitted', now() - interval '50 hours', '1 year', '6 days', '50% advance', 'furniture moving', '30 days');
  if (select count(*) from public.quotes where inquiry_id = i and coalesce(priced_revision, 0) = 1) <> 2 then
    fails := fails || ' [0: a new quote does not name revision 1]'; end if;

  -- 1. three days after posting, budget and date
  v := public.fn_edit_inquiry(i, c, jsonb_build_object('budget', 'AED 30,000', 'required_by', to_char((now() at time zone 'Asia/Dubai')::date + 10, 'YYYY-MM-DD')));
  if coalesce(v->>'error', '') <> '' then fails := fails || ' [1: refused three days after posting: ' || (v->>'error') || ']'; end if;
  if (v->>'revision')::int is distinct from 2 or (v->>'quotes_staled')::int is distinct from 2 then fails := fails || ' [1: not revision 2 with 2 quotes staled: ' || v::text || ']'; end if;
  if (select revision from public.inquiries where id = i) <> 2 or (select budget from public.inquiries where id = i) <> 'AED 30,000'
     or (select required_by from public.inquiries where id = i) <> (now() at time zone 'Asia/Dubai')::date + 10 then
    fails := fails || ' [1: the record was not revised]'; end if;
  if (select count(*) from public.quotes where inquiry_id = i and status = 'draft' and stale_at is not null and coalesce(priced_revision, 1) = 1) <> 2 then
    fails := fails || ' [1: the staled quotes do not keep the revision they priced]'; end if;
  select count(*) into n from public.notifications where inquiry_id = i and type = 'quote_requirements_changed'
     and body like '%Budget: AED 20,000 -> AED 30,000%' and body like '%Needed by:%' and body like '%revision 2%';
  if n <> 2 then fails := fails || ' [1: ' || n || ' of 2 quoting suppliers told what changed]'; end if;
  select count(*) into n from public.notifications where inquiry_id = i and lead_id = s3 and body like '%Please quote the revised request%';
  if n <> 1 then fails := fails || ' [1: the supplier who had not quoted was not told (' || n || ')]'; end if;
  if not exists (select 1 from public.inquiry_revision where inquiry_id = i and revision = 2 and changes ? 'budget' and changes ? 'required_by' and source = 'portal_edit') then
    fails := fails || ' [1: no inquiry_revision row]'; end if;
  if exists (select 1 from public.notifications where inquiry_id = i and to_role = 'supplier' and (body ilike '%Revision Customer%' or body like '%500000141%')) then
    fails := fails || ' [1: a supplier notice names the customer]'; end if;

  -- 2. a re-submission answers revision 2; a new quote too
  update public.quotes set status = 'submitted', quote_amount = 25000 where id = q1;
  select * into r from public.quotes where id = q1;
  if r.priced_revision is distinct from 2 or r.stale_at is not null then fails := fails || ' [2: re-submitted quote: rev ' || coalesce(r.priced_revision::text, 'null') || ', stale ' || coalesce(r.stale_at::text, 'null') || ']'; end if;
  insert into public.quote_items (quote_id, line_no, description, brand, model, specification, qty, unit, unit_price, labour)
  values (q3::text, 1, 'ZZ DEMO paint and labour', 'ZZ DEMO Brand', 'ZZ-1', 'two coats emulsion', 1, 'lot', 26000, 500);
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status, created_at, warranty, lead_time, payment_terms, exclusions, validity)
  values (q3, i, s3, 26000, 'submitted', now(), '1 year', '5 days', '50% advance', 'furniture moving', '30 days');
  if (select priced_revision from public.quotes where id = q3) is distinct from 2 then fails := fails || ' [2: a new quote does not name revision 2]'; end if;

  -- 3. a past date is refused; an unchanged patch records nothing
  v := public.fn_edit_inquiry(i, c, jsonb_build_object('required_by', '2020-01-01'));
  if coalesce(v->>'error', '') <> 'date_in_past' then fails := fails || ' [3: a past date: ' || v::text || ']'; end if;
  v := public.fn_edit_inquiry(i, c, jsonb_build_object('budget', 'AED 30,000'));
  if coalesce((v->>'edited')::boolean, true) or (select revision from public.inquiries where id = i) <> 2 then fails := fails || ' [3: an unchanged patch made a revision]'; end if;

  -- 6. a note on the request files nothing for a fixture and the insert stands
  insert into public.rfq_clarification (inquiry_id, supplier_id, kind, answer, answered_at, source)
  values (i, null, 'note', 'ZZ DEMO we now need it by the 5th and in Sharjah', now(), 'rfq_note') returning id into nid;
  if exists (select 1 from public.reasoning_held_question where dedupe_key = 'request_revision:' || nid) then
    fails := fails || ' [6: a fixture note filed a reasoning question]'; end if;

  -- 4. the sales engineer's reading of that note, as the model returns it
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key)
  values ('sales_engineer', 'sales_engineer.request_revision', 'ZZ DEMO probe', '{}'::jsonb, '{}'::jsonb,
          jsonb_build_object('inquiry_id', i, 'clarification_id', nid, 'customer_id', c), 'probe', 'probe_rev:' || nid) returning id into h;
  v := public.fn_reason_held_resolve(h, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO',
        'decision', jsonb_build_object('choice', 'revise', 'fields', jsonb_build_object(
          'required_by', jsonb_build_object('value', to_char((now() at time zone 'Asia/Dubai')::date + 5, 'YYYY-MM-DD'), 'evidence', ''),
          'emirate', jsonb_build_object('value', 'sharjah', 'evidence', ''),
          'budget', jsonb_build_object('value', 'AED ٣٥٠٠٠', 'evidence', ''),
          'change_en', jsonb_build_object('value', 'The job moves to Sharjah and is needed 5 days from now; call 0500000141 for access.', 'evidence', '')))));
  if coalesce(v->>'status', '') <> 'applied' then fails := fails || ' [4: not applied: ' || v::text || ']'; end if;
  select * into r from public.inquiries where id = i;
  if r.revision <> 3 or r.emirate <> 'Sharjah' or r.required_by <> (now() at time zone 'Asia/Dubai')::date + 5 or r.budget <> 'AED 35000' then
    fails := fails || ' [4: record not revised from the reading: rev ' || r.revision || ', ' || coalesce(r.emirate, '') || ', ' || coalesce(r.budget, '') || ']'; end if;
  select change_en into t from public.inquiry_revision where inquiry_id = i and revision = 3 and source = 'sales_engineer' and note_id = nid;
  if t is null or t like '%0500000141%' then fails := fails || ' [4: change line missing or names the phone: ' || coalesce(t, 'null') || ']'; end if;
  if not exists (select 1 from public.notifications where inquiry_id = i and to_role = 'customer' and lang = 'ar' and body like '%النسخة 3%') then
    fails := fails || ' [4: the customer was not told in Arabic what was recorded]'; end if;
  update public.reasoning_held_question set status = 'held' where id = h;
  v := public.fn_reason_apply_sales_engineer__request_revision(h, jsonb_build_object('decision', jsonb_build_object('choice', 'revise',
        'fields', jsonb_build_object('emirate', jsonb_build_object('value', 'Muscat')))));
  if coalesce((v->>'revised')::boolean, true) or not (v->'dropped' ? 'emirate') then fails := fails || ' [4: a non-emirate was recorded: ' || v::text || ']'; end if;

  -- 5. addendum only, and a choice that is not an option
  v := public.fn_reason_apply_sales_engineer__request_revision(h, jsonb_build_object('decision', jsonb_build_object('choice', 'addendum_only')));
  if coalesce((v->>'revised')::boolean, true) or (select revision from public.inquiries where id = i) <> 3 then fails := fails || ' [5: addendum_only changed the record]'; end if;
  begin
    perform public.fn_reason_apply_sales_engineer__request_revision(h, jsonb_build_object('decision', jsonb_build_object('choice', 'rewrite_everything')));
    fails := fails || ' [5: an unknown choice was accepted]';
  exception when others then if sqlerrm not like 'CHOICE_NOT_AN_OPTION%' then fails := fails || ' [5: ' || sqlerrm || ']'; end if;
  end;

  if fails <> '' then raise exception 'CHK<<PROBE FAILED:%>>', fails; end if;
  raise exception 'CHK<<PROBE OK>>';
end $probe$;
