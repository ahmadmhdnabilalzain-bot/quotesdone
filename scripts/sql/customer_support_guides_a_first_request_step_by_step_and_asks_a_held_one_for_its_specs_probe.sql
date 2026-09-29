-- PROBE for customer_support_guides_a_first_request_step_by_step_and_asks_a_held_one_for_its_specs.sql (customer_support).
-- A pure probe: it always ends by raising 'PROBE OK ...' or 'PROBE FAILED: ...', so every row it writes rolls back.
-- Before the apply, run it in ONE transaction after the file it proves; after the apply, run it alone.
--
-- Its customers are ZZ DEMO fixtures at @example.invalid (fn_is_demo_email), and fn_email_sendable refuses that
-- domain, so a message is composed and recorded but can never be delivered; the probe asserts no live notification
-- row was written to any of them.
--
-- What it proves:
--   1. an English customer's FIRST request, posted without the gypsum trade's required fields, gets ONE
--      concierge.first_request message: its number, the missing fields in the intake's own plain words, the
--      drawing rule (PDF or CAD - DWG or DXF - only; Revit, IFC, DGN refused) and the gypsum pack's specs;
--      asking again sends nothing;
--   2. the same customer's SECOND request, also held, gets concierge.held_for_specs naming what is missing;
--      a third request that is not held (cancelled) gets nothing;
--   3. an Arabic customer's first request is written in Arabic, with the pack's Arabic checklist;
--   4. the duty (fixture mode) finds a request posted by another door and sends its first-request message;
--   5. the portal's guidance (fn_customer_concierge, no request yet) is four steps and says first_inquiry for a
--      customer with no request, and not for one who has one.
--   6. (re-review of #1112) a request that reached NO supplier is not held for its specs: a later one gets
--      concierge.finding_suppliers, a first one says it in its confirmation, and neither asks for specs; a split
--      parent is judged by its children's inquiry_matches (reached through a matched child, held on that child's
--      missing specs named with its trade; finding suppliers when no child is matched).
do $probe$
declare
  v_tag text := substr(md5(clock_timestamp()::text), 1, 8);
  c_en uuid; c_ar uuid; c_new uuid; c_door uuid; i1 uuid; i2 uuid; i3 uuid; i_ar uuid; i_door uuid; l1 bigint;
  i4 uuid; p1 uuid; k1 uuid; p2 uuid; k2 uuid;
  v jsonb; m jsonb; v_bad text := ''; v_n int; v_emails text[]; v_spec text;
begin
  insert into public.customers (email, full_name, locale) values
    ('zz-concierge-' || v_tag || '-en@example.invalid', 'ZZ DEMO Concierge EN', 'en') returning id into c_en;
  insert into public.customers (email, full_name, locale) values
    ('zz-concierge-' || v_tag || '-ar@example.invalid', 'ZZ DEMO Concierge AR', 'ar') returning id into c_ar;
  insert into public.customers (email, full_name, locale) values
    ('zz-concierge-' || v_tag || '-new@example.invalid', 'ZZ DEMO Concierge new', 'en') returning id into c_new;
  insert into public.customers (email, full_name, locale) values
    ('zz-concierge-' || v_tag || '-door@example.invalid', 'ZZ DEMO Concierge other door', 'en') returning id into c_door;
  -- One ZZ DEMO supplier the held requests are matched to (a held request is one suppliers already have).
  insert into public.leads (company_name, email, claimed, claimed_by, approval_status) values
    ('ZZ DEMO Concierge Gypsum ' || v_tag, 'office@zz-cg-' || v_tag || '.invalid', true, 'office@zz-cg-' || v_tag || '.invalid', 'pending')
    returning id into l1;
  v_emails := array(select email from public.customers where id in (c_en, c_ar, c_new, c_door));
  -- The first required spec the gypsum pack names, whatever its wording is on the day.
  select e->'specs'->>0 into v_spec from jsonb_array_elements(public.fn_customer_concierge_checklists('gypsum', 'en')) e limit 1;
  if v_spec is null then v_bad := v_bad || 'the gypsum pack has no English checklist to guide with; '; end if;

  -- 1. first request, held
  insert into public.inquiries (customer_id, category, summary, status, lang) values
    (c_en, 'gypsum', 'ZZ DEMO ceiling', 'sent', 'en') returning id into i1;
  insert into public.inquiry_matches (inquiry_id, supplier_id) values (i1, l1);
  v := public.fn_customer_support_concierge_confirm(i1);
  if v->>'stage' is distinct from 'concierge.first_request' then v_bad := v_bad || 'the first request got ' || coalesce(v->>'stage', 'nothing') || ': ' || v::text || '; '; end if;
  if not exists (select 1 from public.customer_support_duty_message where stage = 'concierge.first_request' and subject_key = i1::text) then
    v_bad := v_bad || 'no duty message recorded for the first request; ';
  end if;
  m := public.fn_customer_concierge_message(i1, 'first_request');
  if position('QD-' || public.fn_job_no(i1) in m->>'body') = 0 then v_bad := v_bad || 'the confirmation does not carry the request number; '; end if;
  if position('PDF or CAD (DWG or DXF) only' in m->>'body') = 0 or position('Revit, IFC, DGN' in m->>'body') = 0 then
    v_bad := v_bad || 'the confirmation does not state ruling 1000 (PDF or CAD only); ';
  end if;
  if position(v_spec in m->>'body') = 0 then v_bad := v_bad || 'the confirmation does not name the gypsum pack''s spec "' || coalesce(v_spec, '') || '"; '; end if;
  if not coalesce((m#>>'{held,held}')::boolean, false)
     or position('a false ceiling' in m->>'body') = 0 then
    v_bad := v_bad || 'the held first request does not ask for its missing type of work in plain words: ' || coalesce(m->>'held', 'null') || '; ';
  end if;
  v := public.fn_customer_support_concierge_confirm(i1);
  if coalesce((v->>'sent')::boolean, false) then v_bad := v_bad || 'the first request was confirmed twice; '; end if;

  -- 2. a later held request; a request that is not held
  insert into public.inquiries (customer_id, category, summary, status, lang) values
    (c_en, 'gypsum', 'ZZ DEMO partition', 'sent', 'en') returning id into i2;
  insert into public.inquiry_matches (inquiry_id, supplier_id) values (i2, l1);
  v := public.fn_customer_support_concierge_confirm(i2);
  if v->>'stage' is distinct from 'concierge.held_for_specs' then v_bad := v_bad || 'the held second request got ' || coalesce(v->>'stage', 'nothing') || '; '; end if;
  m := public.fn_customer_concierge_message(i2, 'held_for_specs');
  if position('The suppliers who have your request' in m->>'body') = 0 or position('a false ceiling' in m->>'body') = 0 then
    v_bad := v_bad || 'the held prompt is not specific: ' || left(m->>'body', 300) || '; ';
  end if;
  insert into public.inquiries (customer_id, category, summary, status, lang) values
    (c_en, 'gypsum', 'ZZ DEMO cancelled', 'cancelled', 'en') returning id into i3;
  v := public.fn_customer_support_concierge_confirm(i3);
  if coalesce((v->>'sent')::boolean, false) or v ? 'stage' then v_bad := v_bad || 'a request that is not held was written to: ' || v::text || '; '; end if;

  -- 3. Arabic
  insert into public.inquiries (customer_id, category, summary, status, lang) values
    (c_ar, 'gypsum', 'ZZ DEMO سقف', 'sent', 'ar') returning id into i_ar;
  m := public.fn_customer_concierge_message(i_ar, 'first_request');
  if m->>'lang' <> 'ar' or position('السيد/' in m->>'body') = 0 or position('PDF أو CAD' in m->>'body') = 0
     or position((select e->>'body' from jsonb_array_elements(public.fn_customer_concierge_checklists('gypsum', 'ar')) e limit 1) in m->>'body') = 0 then
    v_bad := v_bad || 'the Arabic customer''s confirmation is not Arabic with the Arabic checklist; ';
  end if;
  if m->>'body' ~ 'Dear |Describe the job|What happens next' then v_bad := v_bad || 'English left in the Arabic confirmation; '; end if;

  -- 4. the duty finds a request from another door
  insert into public.inquiries (customer_id, category, summary, status, lang) values
    (c_door, 'painting', 'ZZ DEMO villa repaint', 'sent', 'en') returning id into i_door;
  perform set_config('qd.duty_fixtures', 'on', true);
  v := public.fn_customer_support_concierge_tick();
  if not exists (select 1 from public.customer_support_duty_message where stage = 'concierge.first_request' and subject_key = i_door::text) then
    v_bad := v_bad || 'the duty did not confirm a request posted by another door: ' || v::text || '; ';
  end if;

  -- 6a. no supplier reached: a first request says so honestly (c_door's, matched to nobody), a later one gets its
  --     own message, and neither asks for specs
  m := public.fn_customer_concierge_message(i_door, 'first_request');
  if position('We are finding suppliers for your trade' in m->>'body') = 0 or position('we need a few details' in m->>'body') > 0 then
    v_bad := v_bad || 'a first request that reached no supplier is not told honestly, or is asked for specs: ' || left(m->>'body', 300) || '; ';
  end if;
  insert into public.inquiries (customer_id, category, summary, status, lang) values
    (c_en, 'gypsum', 'ZZ DEMO bulkhead', 'sent', 'en') returning id into i4;
  v := public.fn_customer_support_concierge_confirm(i4);
  m := public.fn_customer_concierge_message(i4, 'finding_suppliers');
  if v->>'stage' is distinct from 'concierge.finding_suppliers' or coalesce((m#>>'{held,held}')::boolean, true)
     or position('We are finding suppliers for your trade' in m->>'body') = 0
     or m->>'body' ~* 'need the following|details from you|a false ceiling' then
    v_bad := v_bad || 'a request with no supplier was blamed on its specs or not told: ' || coalesce(v->>'stage', 'nothing') || ' ' || left(m->>'body', 300) || '; ';
  end if;

  -- 6b. a split parent is judged by its children
  insert into public.inquiries (customer_id, category, summary, status, lang, scope_type) values
    (c_en, 'fitout', 'ZZ DEMO combined', 'split', 'en', 'multi') returning id into p1;
  insert into public.inquiries (customer_id, category, summary, status, lang, parent_inquiry_id) values
    (c_en, 'gypsum', 'ZZ DEMO combined gypsum', 'sent', 'en', p1) returning id into k1;
  insert into public.inquiry_matches (inquiry_id, supplier_id) values (k1, l1);
  v := public.fn_customer_concierge_held(p1);
  if coalesce((v->>'finding_suppliers')::boolean, true) or not coalesce((v->>'held')::boolean, false)
     or not exists (select 1 from jsonb_array_elements(v->'missing') e where e->>'inquiry_id' = k1::text and e->>'ask' like '%: %false ceiling%') then
    v_bad := v_bad || 'a split parent with a matched child is not judged by that child: ' || v::text || '; ';
  end if;
  insert into public.inquiries (customer_id, category, summary, status, lang, scope_type) values
    (c_en, 'fitout', 'ZZ DEMO combined 2', 'split', 'en', 'multi') returning id into p2;
  insert into public.inquiries (customer_id, category, summary, status, lang, parent_inquiry_id) values
    (c_en, 'gypsum', 'ZZ DEMO combined 2 gypsum', 'sent', 'en', p2) returning id into k2;
  v := public.fn_customer_concierge_held(p2);
  if not coalesce((v->>'finding_suppliers')::boolean, false) or coalesce((v->>'held')::boolean, true) then
    v_bad := v_bad || 'a split parent with no matched child is not finding suppliers: ' || v::text || '; ';
  end if;

  -- 5. the portal's guidance
  v := public.fn_customer_concierge(c_new, 'gypsum', 'en', null);
  if not coalesce((v->>'first_inquiry')::boolean, false) or jsonb_array_length(v->'steps') <> 4
     or jsonb_array_length(v->'checklists') = 0 then
    v_bad := v_bad || 'a new customer''s portal guidance is wrong: ' || left(v::text, 300) || '; ';
  end if;
  if coalesce((public.fn_customer_concierge(c_en, 'gypsum', 'en', null)->>'first_inquiry')::boolean, true) then
    v_bad := v_bad || 'a customer with requests is still told it is his first; ';
  end if;

  select count(*) into v_n from public.notifications where lower(to_email) = any(v_emails)
     and status not in ('failed', 'skipped', 'suppressed', 'cancelled', 'held');
  if v_n > 0 then v_bad := v_bad || v_n || ' live notification rows to a fixture address; '; end if;

  if v_bad <> '' then raise exception 'PROBE FAILED: %', v_bad; end if;
  raise exception 'PROBE OK: first request confirmed once with the number, the held fields, PDF/CAD only and the pack specs; a later held request prompted; a not-held one left alone; Arabic in Arabic; the duty covers other doors; the portal guidance is four steps; no supplier reached = finding suppliers, never specs; a split parent judged by its children';
end $probe$;
