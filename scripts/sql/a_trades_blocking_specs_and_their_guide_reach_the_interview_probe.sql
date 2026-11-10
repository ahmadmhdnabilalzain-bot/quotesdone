-- PROBE (pure, no DDL, aborted transaction) for a_trades_blocking_specs_and_their_guide_reach_the_interview.sql.
-- Seat: sales_engineer. 10 Nov 2026.
-- Run AFTER the definition, or with it, rolled back:
--   node scripts/ci/rehearse_sql.mjs scripts/sql/a_trades_blocking_specs_and_their_guide_reach_the_interview.sql \
--     scripts/sql/a_trades_blocking_specs_and_their_guide_reach_the_interview_probe.sql
-- It always ends in raise exception 'CHK<<json>>', so every row it writes rolls back. Its rows belong to a trade code no
-- taxonomy holds (zz_demo_probe_trade) and name no person; nothing here sends, queues or hands anything off. The real
-- rows are counted (and their content hashed) before and after and must not move.
--   a  a checklist row in the loader's shape (scripts/kb/load_trade_spec_checklists.mjs) is accepted and read back whole
--   b  a blocking code that is not one of the row's specs is refused
--   c  a spec_guide that is not an array is refused, an empty site-visit sentence is refused, a negative pack_order too
--   d  the 305 existing rows take the defaults: an empty guide, nothing blocking, no site visit, pack_order 0
--   e  the table stays closed: RLS on, anon and authenticated cannot read it
do $$
declare fail text := ''; v_before int; v_after int; h_before text; h_after text; r record; v_defaults int;
  t text := 'zz_demo_probe_trade';
  v_specs jsonb := '[{"code":"spec_unit_type","label_en":"unit type (wall split / ducted)"},{"code":"spec_cooling_capacity","label_en":"cooling capacity per unit"},{"code":"spec_refrigerant","label_en":"refrigerant"}]';
  v_guide jsonb := '[{"code":"spec_unit_type","spec":"unit type (wall split / ducted)","why_needed_to_price":"each type has its own price","uae_options":"wall split; ducted","follow_up_if":"ducted: ceiling void depth","blocking":true},{"code":"spec_cooling_capacity","spec":"cooling capacity per unit","why_needed_to_price":"price follows capacity","uae_options":"9,000 to 60,000 BTU/h","follow_up_if":"unknown: room size and use","blocking":true},{"code":"spec_refrigerant","spec":"refrigerant","why_needed_to_price":"changes unit price","uae_options":"R32; R410A","follow_up_if":"","blocking":false}]';
begin
  select count(*), md5(coalesce(string_agg(trade_code || topic_id || specs::text || spec_guide::text || blocking::text || coalesce(site_visit_required_when, '') || pack_order, '|' order by trade_code, topic_id), ''))
    into v_before, h_before from public.trade_spec_checklist where trade_code <> t;
  -- d: the existing rows, before any load, carry the defaults
  select count(*) into v_defaults from public.trade_spec_checklist
   where trade_code <> t and spec_guide = '[]'::jsonb and blocking = '{}'::text[] and site_visit_required_when is null and pack_order = 0;
  -- a: the loader's shape
  insert into public.trade_spec_checklist (trade_code, topic_id, topic, specs, spec_guide, blocking, site_visit_required_when, pack_order, source_pack)
  values (t, t || ':spec-split-ac', 'ZZ DEMO probe checklist', v_specs, v_guide, array['spec_unit_type', 'spec_cooling_capacity'],
          'ZZ DEMO a site visit is needed for replacements', 1, 'zz_demo_probe.json');
  select * into r from public.trade_spec_checklist where trade_code = t;
  if r.blocking <> array['spec_unit_type', 'spec_cooling_capacity'] then fail := fail || 'the blocking codes did not read back; '; end if;
  if jsonb_array_length(r.spec_guide) <> 3 or r.spec_guide->0->>'why_needed_to_price' <> 'each type has its own price'
     or (r.spec_guide->1->>'blocking')::boolean is not true then fail := fail || 'the guide did not read back whole; '; end if;
  if r.site_visit_required_when is distinct from 'ZZ DEMO a site visit is needed for replacements' or r.pack_order <> 1 then fail := fail || 'site visit or pack order did not read back; '; end if;
  -- b: a blocking code the checklist does not ask
  begin
    update public.trade_spec_checklist set blocking = array['spec_unit_type', 'spec_not_in_this_checklist'] where trade_code = t;
    fail := fail || 'a blocking code outside the checklist''s specs was accepted; ';
  exception when check_violation then null; end;
  -- c: the guide's type, the sentence, the order
  begin
    update public.trade_spec_checklist set spec_guide = '{"spec":"x"}'::jsonb where trade_code = t;
    fail := fail || 'a spec_guide that is not an array was accepted; ';
  exception when check_violation then null; end;
  begin
    update public.trade_spec_checklist set site_visit_required_when = '   ' where trade_code = t;
    fail := fail || 'an empty site-visit sentence was accepted; ';
  exception when check_violation then null; end;
  begin
    update public.trade_spec_checklist set pack_order = -1 where trade_code = t;
    fail := fail || 'a negative pack_order was accepted; ';
  exception when check_violation then null; end;
  -- e: closed
  if not (select relrowsecurity from pg_class where oid = 'public.trade_spec_checklist'::regclass) then fail := fail || 'RLS is off; '; end if;
  if has_table_privilege('anon', 'public.trade_spec_checklist', 'select') or has_table_privilege('authenticated', 'public.trade_spec_checklist', 'select')
    then fail := fail || 'the table is readable by anon or authenticated; '; end if;
  delete from public.trade_spec_checklist where trade_code = t;
  select count(*), md5(coalesce(string_agg(trade_code || topic_id || specs::text || spec_guide::text || blocking::text || coalesce(site_visit_required_when, '') || pack_order, '|' order by trade_code, topic_id), ''))
    into v_after, h_after from public.trade_spec_checklist where trade_code <> t;
  if v_after <> v_before or h_after <> h_before then fail := fail || 'real rows moved; '; end if;
  if exists (select 1 from public.trade_spec_checklist where trade_code = t) then fail := fail || 'probe rows left behind; '; end if;
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when fail = '' then 'PROBE OK' else 'PROBE FAILED: ' || fail end,
    'real_rows', v_before, 'real_rows_after', v_after, 'real_rows_with_defaults', v_defaults);
end $$;
