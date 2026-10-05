-- PROBE for an_arabic_spec_answer_reaches_suppliers_only_in_english.sql (sales_engineer). A pure probe: it always
-- ends by raising 'PROBE OK ...' or 'PROBE FAILED: ...', so every row it writes rolls back. Before the apply, run it in
-- ONE transaction after #1195's file and the file it proves; after, alone.
--
-- Its customer and supplier are ZZ DEMO fixtures at .invalid addresses, which fn_email_sendable refuses.
--
-- On a gypsum request held on two specs, the customer answers one in Arabic, one in English, and a budget in Arabic:
--   1. both specs count as answered: the request is released (rfq_ready);
--   2. the Arabic answer is kept as written on the request and on a held note (answer null, english_held_at set);
--   3. its English is filed for the replay under the surface and dedupe key finishEnglish delivers;
--   4. nothing a supplier can read carries Arabic: the supplier note, the hand-over to the matched supplier, and the
--      portal's copy of the spec (spec_masked);
--   5. the Arabic budget is not written and is reported kept_missing;
--   6. a budget in Arabic-Indic digits is written as Western digits.
do $probe$
declare
  v_tag text := substr(md5(clock_timestamp()::text), 1, 8);
  ar constant text := '[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻾]';
  c1 uuid; i1 uuid; l1 bigint; v jsonb; v_bad text := ''; n int; h public.rfq_clarification;
begin
  insert into public.customers (email, full_name, locale) values
    ('zz-arspec-' || v_tag || '@example.invalid', 'ZZ DEMO Arabic spec customer', 'ar') returning id into c1;
  insert into public.leads (company_name, email, claimed, claimed_by, approval_status) values
    ('ZZ DEMO Gypsum ' || v_tag, 'office@zz-arspec-' || v_tag || '.invalid', true, 'office@zz-arspec-' || v_tag || '.invalid', 'pending')
    returning id into l1;
  insert into public.inquiries (customer_id, category, emirate, summary, status, lang, spec, scope_type, budget) values
    (c1, 'gypsum', 'Dubai', 'ZZ DEMO ceiling', 'sent', 'ar', '{}'::jsonb, 'single', null) returning id into i1;
  insert into public.inquiry_matches (inquiry_id, supplier_id) values (i1, l1);

  v := public.fn_inquiry_add_missing_specs(i1, c1,
         jsonb_build_object('work', 'سقف معلق من الجبس في الصالة', 'area_sqm', '40', 'budget', 'خمسة آلاف درهم'), 'customer_portal');

  -- 1. released on the Arabic answer
  if not coalesce((v->>'ok')::boolean, false) then v_bad := v_bad || 'the door refused: ' || v::text || '; '; end if;
  if (select spec->>'work' from public.inquiries where id = i1) is distinct from 'سقف معلق من الجبس في الصالة' then
    v_bad := v_bad || 'the Arabic answer is not on the request as written; ';
  end if;
  if exists (select 1 from jsonb_array_elements(coalesce(v->'still_missing', '[]')) m where m->>'key' in ('work', 'area_sqm')) then
    v_bad := v_bad || 'the hold check does not see the Arabic spec as answered: ' || v::text || '; ';
  end if;

  -- 2. the held note
  select * into h from public.rfq_clarification where id = (v->>'held_note_id')::bigint;
  if h.id is null or h.answer is not null or h.english_held_at is null or h.answer_as_written !~ ar or h.inquiry_id <> i1 then
    v_bad := v_bad || 'no held note keeping the Arabic as written: ' || v::text || '; ';
  end if;

  -- 3. filed for the replay
  if not exists (select 1 from public.reasoning_held_question where dedupe_key = 'supplier_english:' || h.id
                   and seat = 'sales_engineer' and surface = 'sales_engineer.supplier_english'
                   and (subject->>'clarification_id')::bigint = h.id and question like 'Translate this message%') then
    v_bad := v_bad || 'the English is not filed for the replay; ';
  end if;

  -- 4. nothing a supplier reads carries Arabic
  select count(*) into n from public.rfq_clarification where inquiry_id = i1 and answer ~ ar;
  if n > 0 then v_bad := v_bad || n || ' supplier-visible note(s) carry Arabic; '; end if;
  if not exists (select 1 from public.rfq_clarification where inquiry_id = i1 and answer like '%40%' and english_held_at is null) then
    v_bad := v_bad || 'the English answer did not reach the supplier note; ';
  end if;
  select count(*) into n from public.agent_actions a where a.target_id like 'delivery.request:missing_specs:%:' || l1;
  if n <> 1 then v_bad := v_bad || n || ' hand-overs to the matched supplier (want 1, for the English line); '; end if;
  select count(*) into n from public.agent_actions a where a.target_id like 'delivery.request:missing_specs:%:' || l1 and to_jsonb(a)::text ~ ar;
  if n > 0 then v_bad := v_bad || 'the supplier hand-over carries Arabic; '; end if;
  select count(*) into n from public.notifications where (lead_id = l1 or inquiry_id = i1) and coalesce(subject, '') || coalesce(body, '') ~ ar;
  if n > 0 then v_bad := v_bad || n || ' notification(s) carry Arabic; '; end if;
  if (select spec_masked::text from public.inquiries where id = i1) ~ ar
     or not (select spec_masked ? 'area_sqm' from public.inquiries where id = i1) then
    v_bad := v_bad || 'the portal copy of the spec carries Arabic or lost the English answer; ';
  end if;

  -- 5. the Arabic budget stays missing
  if (select budget from public.inquiries where id = i1) is not null or not coalesce(v->'kept_missing' ? 'budget', false) then
    v_bad := v_bad || 'an Arabic budget was written to the column suppliers read: ' || v::text || '; ';
  end if;

  -- 6. a budget in Arabic-Indic digits is a number, not Arabic: written as Western digits
  v := public.fn_inquiry_add_missing_specs(i1, c1, jsonb_build_object('budget', '٥٠٠٠'), 'customer_portal');
  if (select budget from public.inquiries where id = i1) is distinct from '5000' then
    v_bad := v_bad || 'an Arabic-Indic budget was not written as 5000: ' || v::text || '; ';
  end if;

  if v_bad <> '' then raise exception 'PROBE FAILED: %', v_bad; end if;
  raise exception 'PROBE OK: Arabic spec answer kept as written, request not held on it, supplier copy held and filed (supplier_english:%), supplier note, hand-over and spec_masked English only, Arabic budget kept missing', h.id;
end $probe$;
