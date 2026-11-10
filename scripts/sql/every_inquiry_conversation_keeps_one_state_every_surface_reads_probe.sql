-- PROBE (pure, no DDL, aborted transaction) for every_inquiry_conversation_keeps_one_state_every_surface_reads.sql.
-- Seat: sales_engineer.
-- Run AFTER the definition, or with it, rolled back (scripts/ci/rehearse_sql.mjs <file> <this probe>). It always ends in
-- raise exception 'CHK<<json>>', so every row it writes rolls back. Its subjects are conversation keys that name no person
-- (zz-demo-probe:*): inquiry_state carries no address or phone, and nothing here sends, queues or hands anything off.
-- The real rows are counted before and after and must not move.
--   a  a portal episode: specs with their turn, a change of mind, a "does not know", asks counted, the count only grows,
--      the status only moves forward, a model's dialect reading is not replaced by the code's markers
--   b  the request it is carried into: specs, unknown, count and dialect carried; a: carried
do $$
declare a jsonb; b jsonb; fail text := ''; v_before int; v_after int;
  ka text := 'zz-demo-probe:portal#0'; kb text := 'zz-demo-probe:intake';
begin
  select count(*) into v_before from public.inquiry_state where conv_key not like 'zz-demo-probe:%';
  -- turn 2: size and budget given, the material asked
  a := public.fn_inquiry_state_merge(ka, 'portal_assistant', jsonb_build_object('turn', 2, 'party_key', 'zz-demo-probe:party', 'episode_from', 0,
         'specs', jsonb_build_object('size', jsonb_build_object('value', '2.4 x 1.2 m, one face'), 'budget', jsonb_build_object('value', 'about 3,000 AED')),
         'asked', jsonb_build_array('material'), 'message_count', 4, 'language', 'ar', 'dialect', 'egyptian', 'dialect_by', 'model', 'trade', 'wallpaper'));
  -- turn 3: they do not know the material; the count arrives lower (a retry): it must not shrink
  a := public.fn_inquiry_state_merge(ka, 'portal_assistant', jsonb_build_object('turn', 3,
         'unknown', jsonb_build_object('material', jsonb_build_object('said', 'mesh 3aref')), 'asked', jsonb_build_array('material'),
         'message_count', 3, 'dialect', 'gulf', 'dialect_by', 'markers', 'status', 'converging'));
  -- turn 9: a change of mind on the size, a status that would go backwards
  a := public.fn_inquiry_state_merge(ka, 'portal_assistant', jsonb_build_object('turn', 9,
         'specs', jsonb_build_object('size', jsonb_build_object('value', '2.4 x 1.2 m, both faces')), 'message_count', 18, 'status', 'open'));
  if a->'specs'->'size'->>'value' <> '2.4 x 1.2 m, both faces' then fail := fail || 'the changed size is not the latest; '; end if;
  if a->'specs'->'size'->>'changed_from' <> '2.4 x 1.2 m, one face' then fail := fail || 'the earlier size is not kept in changed_from; '; end if;
  if (a->'specs'->'size'->>'first_turn')::int <> 2 or (a->'specs'->'budget'->>'turn')::int <> 2 then fail := fail || 'a spec lost the message it came from; '; end if;
  if not (a->'unknown' ? 'material') then fail := fail || 'the does-not-know answer is not kept; '; end if;
  if (a->'asked'->'material'->>'count')::int <> 2 then fail := fail || 'the asks of material are not counted twice; '; end if;
  if (a->>'message_count')::int <> 18 then fail := fail || 'the message count is not the highest seen; '; end if;
  if a->>'status' <> 'converging' then fail := fail || 'the status went backwards (' || (a->>'status') || '); '; end if;
  if a->>'dialect' <> 'egyptian' or a->>'dialect_by' <> 'model' then fail := fail || 'the model''s dialect was replaced by markers; '; end if;
  -- a spec given later clears its does-not-know
  a := public.fn_inquiry_state_merge(ka, 'portal_assistant', jsonb_build_object('turn', 10, 'specs', jsonb_build_object('material', 'PVC panels')));
  if a->'unknown' ? 'material' then fail := fail || 'a spec given later did not clear its does-not-know; '; end if;
  a := public.fn_inquiry_state_merge(ka, 'portal_assistant', jsonb_build_object('turn', 11, 'unknown', jsonb_build_object('finish', 'ma ba3ref')));
  -- the carry into the request
  b := public.fn_inquiry_state_carry(ka, kb, 'request_chat', null);
  if b is null then fail := fail || 'the carry returned nothing; ';
  else
    if b->>'source_key' <> ka then fail := fail || 'the request does not name its source; '; end if;
    if b->'specs'->'size'->>'value' <> '2.4 x 1.2 m, both faces' or not (b->'unknown' ? 'finish') then fail := fail || 'specs or unknown were not carried; '; end if;
    if (b->>'message_count')::int <> 18 then fail := fail || 'the count was not carried (the limit is per inquiry); '; end if;
    if b->>'surface' <> 'request_chat' or b->>'dialect' <> 'egyptian' then fail := fail || 'surface or dialect wrong after the carry; '; end if;
  end if;
  if (select status from public.inquiry_state where conv_key = ka) <> 'carried' then fail := fail || 'the portal episode is not marked carried; '; end if;
  -- an empty key is refused
  begin perform public.fn_inquiry_state_merge('  ', 'request_chat', '{}'::jsonb); fail := fail || 'an empty key was accepted; ';
  exception when others then null; end;
  -- the routines are closed to the public roles
  if has_function_privilege('anon', 'public.fn_inquiry_state_merge(text,text,jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_inquiry_state_carry(text,text,text,uuid)', 'execute') then fail := fail || 'a routine is executable by anon or authenticated; '; end if;
  if has_table_privilege('anon', 'public.inquiry_state', 'select') or has_table_privilege('authenticated', 'public.inquiry_state', 'select') then fail := fail || 'the table is readable by anon or authenticated; '; end if;
  delete from public.inquiry_state where conv_key like 'zz-demo-probe:%';
  select count(*) into v_after from public.inquiry_state where conv_key not like 'zz-demo-probe:%';
  if v_after <> v_before then fail := fail || 'real rows moved; '; end if;
  if exists (select 1 from public.inquiry_state where conv_key like 'zz-demo-probe:%') then fail := fail || 'probe rows left behind; '; end if;
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when fail = '' then 'PROBE OK' else 'PROBE FAILED: ' || fail end,
    'portal', a - 'created_at' - 'updated_at', 'request', b - 'created_at' - 'updated_at', 'real_before', v_before, 'real_after', v_after);
end $$;
