-- PROBE (pure, no DDL, aborted transaction) for a_supplier_is_named_by_his_trade_licence_not_by_typing.sql (founder ruling 1672).
-- Run with the definition in one rolled-back transaction (node scripts/ci/rehearse_sql.mjs <file> <this>) or after it is applied.
-- It always ends in raise exception 'CHK<<json>>', so every row it writes rolls back. Its subjects are ZZ DEMO leads at
-- example.invalid addresses created here; no real row is read for a decision and nobody can be written to (a notification row
-- written here rolls back with the rest).
--   a  registered with no name; licence read as "ZZ DEMO Name Probe Trading LLC"   -> named by the gate, no "name updated" mail,
--                                                                                     the open listing of that name flagged
--   b  an unclaimed listing "ZZ DEMO Name Probe Trading L.L.C."                     -> the listing a's flag names
--   c  registered with no name; licence names d, already claimed                    -> stays unnamed, held as a name mismatch
--   d  a claimed company "ZZ DEMO Taken Probe Steel LLC"
--   e  registered with no name; licence on file, name unread                        -> never told "company name"; reg_name blocks
--   f  registered with no name; no licence yet                                      -> the licence is missing, not the name
do $$
declare a bigint; b bigint; c bigint; d bigint; e bigint; f bigint; fail text := ''; r jsonb; v_six text[]; v_name text;
        v_mail int; v_flag jsonb; v_reason text; v_status text;
  pa constant text := 'zz-demo-probe-1672/a/licence.pdf';
  pc constant text := 'zz-demo-probe-1672/c/licence.pdf';
  pe constant text := 'zz-demo-probe-1672/e/licence.pdf';
begin
  insert into storage.objects (bucket_id, name) values ('supplier-docs', pa), ('supplier-docs', pc), ('supplier-docs', pe);
  insert into public.leads (company_name, email, claimed, claimed_by, source)
       values ('', 'zz-demo-name-a@probe1672.example.invalid', true, 'zz-demo-name-a@probe1672.example.invalid', 'self_registered') returning id into a;
  insert into public.leads (company_name, email, emirate)
       values ('ZZ DEMO Name Probe Trading L.L.C.', 'zz-demo-name-b@listing1672.example.invalid', 'Dubai') returning id into b;
  insert into public.leads (company_name, email, claimed, claimed_by)
       values ('ZZ DEMO Taken Probe Steel LLC', 'zz-demo-name-d@probe1672.example.invalid', true, 'zz-demo-name-d@probe1672.example.invalid') returning id into d;
  insert into public.leads (company_name, email, claimed, claimed_by, source)
       values ('', 'zz-demo-name-c@probe1672.example.invalid', true, 'zz-demo-name-c@probe1672.example.invalid', 'self_registered') returning id into c;
  insert into public.leads (company_name, email, claimed, claimed_by, source)
       values ('', 'zz-demo-name-e@probe1672.example.invalid', true, 'zz-demo-name-e@probe1672.example.invalid', 'self_registered') returning id into e;
  insert into public.leads (company_name, email, claimed, claimed_by, source)
       values ('', 'zz-demo-name-f@probe1672.example.invalid', true, 'zz-demo-name-f@probe1672.example.invalid', 'self_registered') returning id into f;

  -- f: no licence yet -> the licence is missing, the name is not asked for
  select public.fn_supplier_mandatory_six(l) into v_six from public.leads l where l.id = f;
  if 'reg_name' = any(v_six) then fail := fail || 'f: a blank name with no licence is listed as missing; '; end if;
  if not ('reg_licence' = any(v_six)) then fail := fail || 'f: the licence is not listed as missing; '; end if;
  r := public.fn_sales_engineer_verifies_supplier(f, 'save_profile');
  if r->>'reason' = 'reg_name' then fail := fail || 'f: told reg_name; '; end if;

  -- a: the licence is read; the gate names the company from it
  update public.leads set license_doc_path = pa, licence_legal_name = 'ZZ DEMO Name Probe Trading LLC', trade_license_no = 'ZZ-PROBE-1672-A',
         license_authority = 'Dubai Economy and Tourism', license_expiry = current_date + 300, emirate = 'Dubai' where id = a;
  select public.fn_supplier_mandatory_six(l) into v_six from public.leads l where l.id = a;
  if not ('reg_name' = any(v_six)) then fail := fail || 'a: a blank name with a licence on file is not missing before the gate; '; end if;
  r := public.fn_sales_engineer_verifies_supplier(a, 'save_profile');
  select company_name into v_name from public.leads where id = a;
  if v_name is distinct from 'ZZ DEMO Name Probe Trading LLC' then fail := fail || 'a: not named from the licence (' || coalesce(v_name, 'null') || '); '; end if;
  if 'reg_name' = any(array(select jsonb_array_elements_text(r->'missing'))) then fail := fail || 'a: the stale reg_name survived the rename; '; end if;
  if r->>'reason' = 'reg_name' then fail := fail || 'a: told reg_name; '; end if;
  select count(*) into v_mail from public.notifications where lead_id = a and type = 'company_name_from_licence';
  if v_mail <> 0 then fail := fail || 'a: told "your company name was updated" from a name he never typed; '; end if;
  if not exists (select 1 from public.agent_actions where kind = 'supplier_name_from_licence' and target_id = a::text and detail->>'previous_name' = '') then
    fail := fail || 'a: the rename is not recorded; '; end if;
  select detail into v_flag from public.agent_actions where agent = 'it_engineer' and kind = 'possible_duplicate_listing' and status = 'pending' and target_id = a::text;
  if v_flag is null then fail := fail || 'a: the listing with the licensed name is not flagged; ';
  elsif not exists (select 1 from jsonb_array_elements(v_flag->'listings') x where (x->>'id')::bigint = b) then fail := fail || 'a: the flag does not name the listing; '; end if;
  if exists (select 1 from public.leads where id = b and (claimed or claimed_by is not null)) then fail := fail || 'b: the listing was taken; '; end if;

  -- c: the licence names a company another account has claimed -> unnamed, held for a person
  update public.leads set license_doc_path = pc, licence_legal_name = 'ZZ DEMO Taken Probe Steel L.L.C', trade_license_no = 'ZZ-PROBE-1672-C',
         license_authority = 'Dubai Economy and Tourism', license_expiry = current_date + 300 where id = c;
  r := public.fn_sales_engineer_verifies_supplier(c, 'save_profile');
  select company_name, licence_gate_reason into v_name, v_reason from public.leads where id = c;
  if coalesce(v_name, '') <> '' then fail := fail || 'c: took another claimed company''s name; '; end if;
  -- c's mobile and the rest are missing too, so the reason told is the first of those; the name stays the gate's to hold
  if coalesce((r->>'licence_name_mismatch')::boolean, false) is not true then fail := fail || 'c: the other company''s name is not held as a mismatch; '; end if;
  if v_reason = 'reg_name' then fail := fail || 'c: told reg_name; '; end if;

  -- e: licence on file, its name unread -> held on the licence, never "company name"; not approvable
  update public.leads set license_doc_path = pe, licence_read_state = 'ours_failed' where id = e;
  r := public.fn_sales_engineer_verifies_supplier(e, 'save_profile');
  select licence_gate_reason, approval_status into v_reason, v_status from public.leads where id = e;
  if v_reason is null or v_reason = 'reg_name' then fail := fail || 'e: reason ' || coalesce(v_reason, 'null') || '; '; end if;
  if v_status = 'approved' then fail := fail || 'e: approved with no name; '; end if;
  select public.fn_supplier_mandatory_six(l) into v_six from public.leads l where l.id = e;
  if not ('reg_name' = any(v_six)) then fail := fail || 'e: the six do not hold a blank name with a licence on file; '; end if;

  -- the Dropbox sweep files no supplier until he is named (its text: every supplier block carries the guard)
  if (select count(*) from regexp_matches(pg_get_functiondef('public.fn_enqueue_doc_backups()'::regprocedure), 'coalesce\(btrim\((l|b)\.company_name\), ''''\) (<>|=) ''''', 'g')) < 4 then
    fail := fail || 'fn_enqueue_doc_backups does not hold back an unnamed supplier in every block; '; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'leads' and column_name = 'trading_name') then
    fail := fail || 'leads.trading_name is missing; '; end if;

  delete from public.agent_actions where target_table = 'leads' and target_id in (a::text, b::text, c::text, d::text, e::text, f::text);
  delete from public.notifications where lead_id in (a, b, c, d, e, f);
  delete from public.leads where id in (a, b, c, d, e, f);
  -- the three storage.objects rows go with the raise below (storage.protect_delete refuses a direct delete)
  if exists (select 1 from public.leads where id in (a, b, c, d, e, f)) then fail := fail || 'teardown left a lead; '; end if;
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when fail = '' then 'PROBE OK' else 'PROBE FAILED: ' || fail end);
end $$;
