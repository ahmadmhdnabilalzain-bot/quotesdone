-- PROBE (pure, no DDL, aborted transaction) for a_quote_is_checked_for_specs_prices_and_terms_before_the_customer_sees_it.sql.
-- Run AFTER that file, in the same transaction (while it is pending), or on its own once it is applied. It always ends in
-- raise exception 'CHK<<json>>', so every row it writes rolls back. Subjects: ZZ DEMO customers and suppliers at
-- @example.invalid, created here; the only messages go to @example.invalid addresses, which the outbox records 'suppressed'.
-- A price range needs 5 quotes by 3 suppliers on OTHER requests: five ZZ DEMO suppliers price one ZZ DEMO item first.
do $$
declare
  cust uuid; bench uuid; t1 uuid; t2 uuid; t3 uuid; t4 uuid; s bigint[] := '{}'; sid bigint; q uuid; q1 uuid; q2 uuid; q3 uuid; q4 uuid;
  i int; f text := ''; o jsonb := '{}'; h record; r jsonb; v_codes text[]; v_all jsonb; v_st text; n jsonb; v_union int;
begin
  insert into public.customers (full_name, email, locale) values ('ZZ DEMO quality customer', 'zz-demo-quality-cust@example.invalid', 'ar') returning id into cust;
  for i in 1..6 loop
    insert into public.leads (company_name, email) values ('ZZ DEMO — quality supplier ' || i, 'zz-demo-quality-sup' || i || '@example.invalid') returning id into sid;
    s := s || sid;
  end loop;
  insert into public.inquiries (customer_id, category, emirate, lang, status, summary) values
    (cust, 'zz_demo_quality_trade', 'Dubai', 'ar', 'quoted', 'ZZ DEMO quality benchmark') returning id into bench;
  insert into public.inquiries (customer_id, category, emirate, lang, status, summary) values
    (cust, 'zz_demo_quality_trade', 'Dubai', 'ar', 'sent', 'ZZ DEMO quality T1') returning id into t1;
  insert into public.inquiries (customer_id, category, emirate, lang, status, summary) values
    (cust, 'safety_equipment', 'Sharjah', 'en', 'sent', 'ZZ DEMO quality T2') returning id into t2;
  insert into public.inquiries (customer_id, category, emirate, lang, status, summary) values
    (cust, 'safety_equipment', 'Sharjah', 'en', 'sent', 'ZZ DEMO quality T3') returning id into t3;
  insert into public.inquiries (customer_id, category, emirate, lang, status, summary) values
    (cust, 'scaffolding', 'Ajman', 'en', 'sent', 'ZZ DEMO quality T4') returning id into t4;

  -- the UAE range for one item: 5 clean quotes by 5 suppliers at AED 20-24 per m2; each goes out (nothing to flag)
  for i in 1..5 loop
    insert into public.quotes (inquiry_id, supplier_id, quote_amount, status, validity, lead_time, vat_treatment)
      values (bench, s[i], 1000 + i, 'draft', '30 days', '7 days', 'exclusive') returning id into q;
    insert into public.quote_items (quote_id, line_no, description, qty, unit, unit_price, amount)
      values (q::text, 1, 'ZZ DEMO emulsion paint two coats', 50, 'm2', 19 + i, 50 * (19 + i));
    update public.quotes set status = 'submitted' where id = q;
    if (select status from public.quotes where id = q) <> 'submitted' then f := f || 'a clean benchmark quote was held; '; end if;
  end loop;

  -- Q1: priced far above the range and no validity -> held, never shown, the customer not told
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status, lead_time, vat_treatment)
    values (t1, s[6], 3000, 'draft', '10 days', 'exclusive') returning id into q1;
  insert into public.quote_items (quote_id, line_no, description, qty, unit, unit_price, amount)
    values (q1::text, 1, 'ZZ DEMO emulsion paint two coats', 50, 'm2', 60, 3000);
  update public.quotes set status = 'submitted' where id = q1;
  select * into h from public.quote_quality_hold where quote_id = q1;
  o := o || jsonb_build_object('q1_flags', h.flags);
  if (select status from public.quotes where id = q1) <> 'draft' then f := f || 'Q1 reached the customer; '; end if;
  if h.quote_id is null or not (h.flags @> '[{"code":"price_above"}]' and h.flags @> '[{"code":"no_validity"}]')
     or h.flags @> '[{"code":"no_delivery_time"}]' or h.flags @> '[{"code":"no_vat_treatment"}]' then
    f := f || 'Q1 was not flagged for exactly its price and its validity; '; end if;
  if h.release_due < now() + interval '23 hours 59 minutes' or h.release_due > now() + interval '24 hours 1 minute' then
    f := f || 'Q1 is not held for 24 hours; '; end if;

  -- Q2: a trade with one pack checklist, two of its specs not stated, no delivery time, no VAT basis
  select array_agg(x->>'code' order by k) into v_codes
    from public.trade_spec_checklist c, jsonb_array_elements(c.specs) with ordinality e(x, k) where c.trade_code = 'safety_equipment';
  select jsonb_object_agg(c, 'ZZ DEMO value') into v_all from unnest(v_codes[1:cardinality(v_codes) - 2]) c;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status, validity) values (t2, s[6], 500, 'draft', '15 days') returning id into q2;
  insert into public.quote_items (quote_id, line_no, description, qty, unit, unit_price, amount, spec)
    values (q2::text, 1, 'ZZ DEMO safety helmets', 10, 'pcs', 50, 500, v_all);
  update public.quotes set status = 'submitted' where id = q2;
  select * into h from public.quote_quality_hold where quote_id = q2;
  o := o || jsonb_build_object('q2_flag_codes', (select jsonb_agg(x->>'code') from jsonb_array_elements(h.flags) x));
  if (select status from public.quotes where id = q2) <> 'draft' then f := f || 'Q2 reached the customer; '; end if;
  if not (h.flags @> '[{"code":"no_delivery_time"}]' and h.flags @> '[{"code":"no_vat_treatment"}]')
     or coalesce(jsonb_array_length((select x->'specs' from jsonb_array_elements(h.flags) x where x->>'code' = 'missing_spec')), 0) <> 2 then
    f := f || 'Q2 was not flagged for its two missing specs, its delivery time and its VAT basis; '; end if;

  -- Q3: the same trade read by a line reader (a non-checklist attribute on the line), every term stated -> out at once
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status, validity, lead_time, vat_treatment)
    values (t3, s[6], 700, 'draft', '30 days', '5 days', 'inclusive') returning id into q3;
  insert into public.quote_items (quote_id, line_no, description, qty, unit, unit_price, amount, spec)
    values (q3::text, 1, 'ZZ DEMO gloves', 100, 'pcs', 7, 700, '{"brand":"ZZ DEMO"}'::jsonb);
  update public.quotes set status = 'submitted' where id = q3;
  if (select status from public.quotes where id = q3) <> 'submitted' or exists (select 1 from public.quote_quality_hold where quote_id = q3) then
    f := f || 'Q3 (reader regime, complete) was held; '; end if;

  -- Q4: a lump sum in a trade with two checklists and nothing stated -> every spec of both lists, each once
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status, validity, lead_time, vat_treatment)
    values (t4, s[6], 900, 'draft', '30 days', '5 days', 'exclusive') returning id into q4;
  update public.quotes set status = 'submitted' where id = q4;
  select count(distinct x->>'code') into v_union from public.trade_spec_checklist c, jsonb_array_elements(c.specs) x where c.trade_code = 'scaffolding';
  if coalesce(jsonb_array_length((select x->'specs' from jsonb_array_elements((select flags from public.quote_quality_hold where quote_id = q4)) x
                                   where x->>'code' = 'missing_spec' and x->'topic' = 'null'::jsonb)), 0) <> v_union then
    f := f || 'Q4 was not asked every spec of both checklists once; '; end if;

  -- the duty: the fixes go to the supplier in English, once; nothing reaches the customer while held
  r := public.fn_sales_engineer_quote_quality_tick(true);
  o := o || jsonb_build_object('tick1', r);
  select to_jsonb(x) into n from (select lang, to_role, subject, body, status, to_email from public.notifications
                                    where type = 'quote_quality_fixes' and quote_id = q1) x;
  o := o || jsonb_build_object('fixes_q1', n - 'body');
  if n is null or n->>'lang' <> 'en' or n->>'to_role' <> 'supplier' or n->>'body' ~ '[؀-ۿ]'
     or n->>'body' !~ 'above the usual UAE price' or n->>'body' !~ 'State how long the quotation is valid'
     or n->>'to_email' <> 'zz-demo-quality-sup6@example.invalid' then f := f || 'Q1''s supplier was not sent the exact fixes in English; '; end if;
  r := public.fn_sales_engineer_quote_quality_tick(true);
  if (select count(*) from public.notifications where type = 'quote_quality_fixes' and quote_id = q1) <> 1 then f := f || 'the fixes were sent twice; '; end if;
  if exists (select 1 from public.notifications where type = 'new_quote' and inquiry_id in (t1, t2, t4)) then
    f := f || 'a customer was told of a held quote; '; end if;
  if exists (select 1 from public.notifications where to_role = 'supplier' and created_at = now() and coalesce(lang, 'en') <> 'en') then
    f := f || 'a supplier row is not English; '; end if;

  -- corrected: Q2 states everything and is sent again -> it goes out, the hold closed 'corrected'
  update public.quote_items set spec = (select jsonb_object_agg(c, 'ZZ DEMO value') from unnest(v_codes) c) where quote_id = q2::text;
  update public.quotes set lead_time = '3 days', vat_treatment = 'exclusive', status = 'submitted' where id = q2;
  select * into h from public.quote_quality_hold where quote_id = q2;
  if (select status from public.quotes where id = q2) <> 'submitted' or h.release_reason is distinct from 'corrected' then
    f := f || 'the corrected Q2 was not released as corrected; '; end if;

  -- REVIEW OF #1108: a wait never publishes content the door did not accept. Q5 is held; the supplier then sends a new
  -- version the door refuses (supplier_api leaves a draft: here, the lines change and the status does not), and its 24 h pass.
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status, lead_time, vat_treatment)
    values (t1, s[5], 3000, 'draft', '10 days', 'exclusive') returning id into q;
  insert into public.quote_items (quote_id, line_no, description, qty, unit, unit_price, amount)
    values (q::text, 1, 'ZZ DEMO emulsion paint two coats', 50, 'm2', 60, 3000);
  update public.quotes set status = 'submitted' where id = q;
  update public.quote_items set unit_price = 90, amount = 4500 where quote_id = q::text;
  update public.quote_quality_hold set release_due = now() - interval '1 minute' where quote_id = q;
  r := public.fn_sales_engineer_quote_quality_tick(true);
  o := o || jsonb_build_object('tick_changed_content', r - 'fixes_not_sent');
  if (select status from public.quotes where id = q) <> 'draft' or (select released_at from public.quote_quality_hold where quote_id = q) is not null
     or coalesce((r->>'content_not_the_accepted_version')::int, 0) < 1 then
    f := f || 'a wait published content the door had not accepted; '; end if;
  -- ... supplier_api supersedes the hold of a refused submission: it is never released, and it is not counted as open
  update public.quote_quality_hold set superseded_at = now() where quote_id = q and released_at is null and superseded_at is null;
  r := public.fn_sales_engineer_quote_quality_tick(true);
  if (select status from public.quotes where id = q) <> 'draft' or (select released_at from public.quote_quality_hold where quote_id = q) is not null then
    f := f || 'a superseded hold was released; '; end if;
  -- ... and a later ACCEPTED version (still flagged) opens a fresh hold on that version, with a fresh 24 h
  update public.quote_items set unit_price = 61, amount = 3050 where quote_id = q::text;
  update public.quotes set status = 'submitted' where id = q;
  select * into h from public.quote_quality_hold where quote_id = q;
  if (select status from public.quotes where id = q) <> 'draft' or h.superseded_at is not null or h.release_due < now() + interval '23 hours'
     or h.accepted_md5 is distinct from public.fn_quote_quality_content_md5((select x from public.quotes x where x.id = q)) then
    f := f || 'an accepted version after a superseded hold did not open a fresh hold on that version; '; end if;
  delete from public.quote_quality_hold where quote_id = q;   -- out of the way of the waited release below
  update public.quotes set status = 'withdrawn' where id = q;

  -- waited: Q1's 24 h are over -> released with its flags, the request marked quoted, the customer told in Arabic
  update public.quote_quality_hold set release_due = now() - interval '1 minute' where quote_id = q1;
  r := public.fn_sales_engineer_quote_quality_tick(true);
  o := o || jsonb_build_object('tick3', r);
  select * into h from public.quote_quality_hold where quote_id = q1;
  if (select status from public.quotes where id = q1) <> 'submitted' or h.release_reason is distinct from 'waited_24h'
     or not (h.flags @> '[{"code":"price_above"}]') then f := f || 'Q1 was not released with its flags after the wait; '; end if;
  if (select status from public.inquiries where id = t1) <> 'quoted' then f := f || 'T1 was not marked quoted; '; end if;
  select to_jsonb(x) into n from (select lang, subject, body from public.notifications where type = 'new_quote' and quote_id = q1) x;
  o := o || jsonb_build_object('customer_q1', n - 'body');
  if n is null or n->>'lang' <> 'ar' or n->>'body' !~ 'تحية طيبة وبعد' or n->>'body' !~ 'فحص الجودة' then
    f := f || 'T1''s customer was not told in Arabic that a quotation arrived with its points shown; '; end if;

  -- a quote that waited is never held again; a correction after the wait clears the reason shown beside it
  update public.quotes set status = 'submitted' where id = q1;
  if (select status from public.quotes where id = q1) <> 'submitted' then f := f || 'Q1 was pulled back after its wait; '; end if;
  update public.quote_items set unit_price = 22, amount = 1100 where quote_id = q1::text;
  update public.quotes set validity = '30 days', status = 'submitted' where id = q1;
  if (select corrected_at from public.quote_quality_hold where quote_id = q1) is null then f := f || 'a correction after the wait was not recorded; '; end if;

  -- clean up and assert it is gone (the rollback below is the second guarantee)
  delete from public.notifications where inquiry_id in (bench, t1, t2, t3, t4);
  delete from public.quotes where inquiry_id in (bench, t1, t2, t3, t4);
  delete from public.inquiries where id in (bench, t1, t2, t3, t4);
  delete from public.leads where id = any(s);
  delete from public.customers where id = cust;
  if exists (select 1 from public.quote_quality_hold where inquiry_id in (bench, t1, t2, t3, t4)) then f := f || 'cleanup left a hold; '; end if;

  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when f = '' then 'PROBE OK' else 'PROBE FAILED: ' || f end, 'steps', o)::text;
end $$;
