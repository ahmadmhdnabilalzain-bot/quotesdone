-- PROBE for a_held_request_takes_its_missing_specs_from_the_customer_and_is_released_when_complete.sql
-- (customer_support). A pure probe: it always ends by raising 'PROBE OK ...' or 'PROBE FAILED: ...', so every row
-- it writes rolls back. Before the apply, run it in ONE transaction after the file it proves; after, alone.
--
-- Its customers and its supplier are ZZ DEMO fixtures at @example.invalid, which fn_email_sendable refuses, and it
-- asserts no live notification row reached any of them.
--
-- What it proves, on a gypsum request posted with only its emirate (required: type of work, area):
--   1. the request is held, and the two missing specs are asked in the intake's plain words, in English and in
--      Arabic;
--   2. the portal door takes only a spec that is missing (an unknown key and a blank answer are dropped), writes it
--      under the key the check reads, and the request stays held on the one still missing;
--   3. the matched supplier is told what was added, and the note is on the request;
--   4. the last spec releases it: rfq_ready is true, nothing is missing, and it says the request has suppliers;
--   5. another customer cannot add to it; a closed request takes nothing; the e-mail path (customer_support,
--      source email_reply, no customer id) completes a second held request the same way, including the budget a
--      request below the general bar is asked for.
do $probe$
declare
  v_tag text := substr(md5(clock_timestamp()::text), 1, 8);
  c1 uuid; c2 uuid; i1 uuid; i2 uuid; l1 bigint; v jsonb; v_bad text := ''; v_n int; v_emails text[];
begin
  insert into public.customers (email, full_name, locale) values
    ('zz-specs-' || v_tag || '-1@example.invalid', 'ZZ DEMO specs customer', 'en') returning id into c1;
  insert into public.customers (email, full_name, locale) values
    ('zz-specs-' || v_tag || '-2@example.invalid', 'ZZ DEMO other customer', 'ar') returning id into c2;
  insert into public.leads (company_name, email, claimed, claimed_by, approval_status) values
    ('ZZ DEMO Gypsum ' || v_tag, 'office@zz-gypsum-' || v_tag || '.invalid', true, 'office@zz-gypsum-' || v_tag || '.invalid', 'pending')
    returning id into l1;
  -- As the portal posts it: one trade, a budget, the emirate; the category's own fields not yet stated.
  insert into public.inquiries (customer_id, category, emirate, summary, status, lang, spec, scope_type, budget) values
    (c1, 'gypsum', 'Dubai', 'ZZ DEMO ceiling', 'sent', 'en', '{}'::jsonb, 'single', 'AED 5,000') returning id into i1;
  insert into public.inquiry_matches (inquiry_id, supplier_id) values (i1, l1);
  v_emails := array[(select email from public.customers where id = c1), (select email from public.customers where id = c2),
                    'office@zz-gypsum-' || v_tag || '.invalid'];

  -- 1. held, asked plainly, both languages
  v := public.fn_inquiry_missing_specs(i1, 'en');
  if not coalesce((v->>'held')::boolean, false)
     or (select array_agg(m->>'key' order by m->>'key') from jsonb_array_elements(v->'missing') m) is distinct from array['area_sqm', 'work'] then
    v_bad := v_bad || 'the request is not held on area_sqm and work: ' || v::text || '; ';
  end if;
  if not exists (select 1 from jsonb_array_elements(v->'missing') m where m->>'key' = 'work' and m->>'ask' like '%false ceiling%'
                    and jsonb_array_length(m->'options') > 0) then
    v_bad := v_bad || 'the missing type of work is not asked in plain words with its options; ';
  end if;
  if not exists (select 1 from jsonb_array_elements(public.fn_inquiry_missing_specs(i1, 'ar')->'missing') m
                  where m->>'key' = 'area_sqm' and m->>'ask' ~ '[؀-ۿ]') then
    v_bad := v_bad || 'the Arabic ask is not Arabic; ';
  end if;

  -- 2. only what is missing, and the request stays held on the rest
  v := public.fn_inquiry_add_missing_specs(i1, c1, jsonb_build_object('work', 'False ceiling', 'finish', 'Matte', 'area_sqm', '  '), 'customer_portal');
  if not coalesce((v->>'ok')::boolean, false) or v->'added' is distinct from '["work"]'::jsonb then
    v_bad := v_bad || 'the door did not take exactly the missing, answered spec: ' || v::text || '; ';
  end if;
  if (select spec->>'work' from public.inquiries where id = i1) is distinct from 'False ceiling'
     or (select spec ? 'finish' from public.inquiries where id = i1) then
    v_bad := v_bad || 'the spec was not written under the checked key, or an unasked key was written; ';
  end if;
  if coalesce((v->>'ready')::boolean, true) or (select rfq_ready from public.inquiries where id = i1) then
    v_bad := v_bad || 'the request was released with area still missing; ';
  end if;

  -- 3. the supplier is told, the note is on the request
  if (v->>'suppliers_told')::int is distinct from 1
     or not exists (select 1 from public.agent_actions where kind = 'handoff' and agent = 'customer_support'
                      and target_id like 'delivery.request:missing_specs:' || (v->>'note_id') || ':' || l1) then
    v_bad := v_bad || 'the matched supplier was not handed the addendum: ' || v::text || '; ';
  end if;
  if not exists (select 1 from public.rfq_clarification where inquiry_id = i1 and source = 'missing_specs' and answer like '%False ceiling%') then
    v_bad := v_bad || 'no note on the request; ';
  end if;

  -- 4. the last spec releases it
  v := public.fn_inquiry_add_missing_specs(i1, c1, jsonb_build_object('area_sqm', '40'), 'customer_portal');
  if not coalesce((v->>'ready')::boolean, false) or jsonb_array_length(v->'still_missing') <> 0
     or not (select rfq_ready from public.inquiries where id = i1) or not coalesce((v->>'reached_suppliers')::boolean, false) then
    v_bad := v_bad || 'completing the specs did not release the request: ' || v::text || '; ';
  end if;
  if coalesce((public.fn_inquiry_missing_specs(i1, 'en')->>'held')::boolean, true) then v_bad := v_bad || 'a complete request still reads held; '; end if;

  -- 5. another customer, a closed request, the e-mail path
  -- Below the general bar as well (no scope type, no budget): the budget is asked with the specs.
  insert into public.inquiries (customer_id, category, emirate, summary, status, lang, spec) values
    (c1, 'gypsum', 'Dubai', 'ZZ DEMO partition', 'sent', 'en', '{}'::jsonb) returning id into i2;
  if (select array_agg(m->>'key' order by m->>'key') from jsonb_array_elements(public.fn_inquiry_missing_specs(i2, 'en')->'missing') m)
     is distinct from array['area_sqm', 'budget', 'work'] then
    v_bad := v_bad || 'a request below the general bar is not asked its budget; ';
  end if;
  if public.fn_inquiry_add_missing_specs(i2, c2, '{"work":"Gypsum partition"}', 'customer_portal')->>'error' is distinct from 'not_your_inquiry' then
    v_bad := v_bad || 'another customer could add specs; ';
  end if;
  begin
    perform public.fn_inquiry_add_missing_specs(i2, null, '{"work":"Gypsum partition"}', 'customer_portal');
    v_bad := v_bad || 'a portal answer without a customer was taken; ';
  exception when others then null;
  end;
  v := public.fn_inquiry_add_missing_specs(i2, null, '{"work":"Gypsum partition","area_sqm":"25","budget":"AED 8,000"}', 'email_reply');
  if not coalesce((v->>'ready')::boolean, false)
     or not exists (select 1 from public.rfq_clarification where inquiry_id = i2 and answer like 'The customer replied%') then
    v_bad := v_bad || 'the e-mail path did not complete the request: ' || v::text || '; ';
  end if;
  update public.inquiries set status = 'cancelled' where id = i2;
  if public.fn_inquiry_add_missing_specs(i2, c1, '{"work":"x"}', 'customer_portal')->>'error' is distinct from 'inquiry_closed' then
    v_bad := v_bad || 'a closed request took specs; ';
  end if;

  -- 6. a combined request is completed on its per-trade parts: the parent asks nothing and takes nothing
  insert into public.inquiries (customer_id, category, emirate, summary, status, lang, spec, scope_type) values
    (c1, 'fitout', 'Dubai', 'ZZ DEMO combined', 'split', 'en', '{}'::jsonb, 'multi') returning id into i2;
  insert into public.inquiries (customer_id, category, emirate, summary, status, lang, spec, parent_inquiry_id) values
    (c1, 'gypsum', 'Dubai', 'ZZ DEMO combined gypsum', 'sent', 'en', '{}'::jsonb, i2);
  if coalesce((public.fn_inquiry_missing_specs(i2, 'en')->>'held')::boolean, true)
     or public.fn_inquiry_add_missing_specs(i2, c1, '{"work":"False ceiling"}', 'customer_portal')->>'error' is distinct from 'nothing_to_add' then
    v_bad := v_bad || 'a combined parent is asked for, or takes, its parts'' specs; ';
  end if;

  select count(*) into v_n from public.notifications where lower(to_email) = any(v_emails)
     and status not in ('failed', 'skipped', 'suppressed', 'cancelled', 'held');
  if v_n > 0 then v_bad := v_bad || v_n || ' live notification rows to a fixture address; '; end if;

  if v_bad <> '' then raise exception 'PROBE FAILED: %', v_bad; end if;
  raise exception 'PROBE OK: held on its two specs, asked plainly in both languages, only missing specs taken, supplier told, released when complete, other customer and closed request refused, e-mail path completes';
end $probe$;
