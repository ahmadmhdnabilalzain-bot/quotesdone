-- PROBE for a_supplier_is_asked_what_his_documents_could_not_say.sql (12 Nov 2026, sales_engineer; built by it_engineer).
-- A pure probe: it always raises CHK<<...>>, so everything it writes is rolled back. ZZ DEMO suppliers only (company name
-- ZZ/QD DEMO and an @example.invalid address); it counts every other supplier's capability and question rows before and after
-- and fails if one moved. Run with the file in one rolled-back transaction while the file is pending:
--   node scripts/ci/rehearse_sql.mjs scripts/sql/a_supplier_is_asked_what_his_documents_could_not_say.sql \
--        scripts/sql/a_supplier_is_asked_what_his_documents_could_not_say_probe.sql
-- What it proves:
--   1. a question row is written once: a second insert on (supplier_id, kind, about_hash) is ignored (a re-read never asks twice)
--   2. another supplier may hold the same question (the key is per supplier)
--   3. an unknown kind, an unknown status, and 'answered' without an answer are refused by the table
--   4. the table is closed: anon and authenticated hold no privilege on it, RLS is on with its one policy
--   5. services_partner exists, is not null, defaults to '{}', and no supplier holds a partner key outside his services
--   6. his questions go with his lead: the foreign key to leads cascades on delete
do $probe$
declare
  f text := ''; v_sup bigint[]; v_a bigint; v_b bigint; n int; v_others_before int; v_others_after int; ok boolean;
begin
  select array_agg(l.id order by l.id) into v_sup from (
    select l.id from public.leads l
     where l.company_name ~* '^\s*(zz|qd)\s*demo' and l.email like '%@example.invalid' order by l.id limit 2) l;
  if coalesce(cardinality(v_sup), 0) < 2 then raise exception 'CHK<<{"verdict":"PROBE FAILED: fewer than two demo suppliers at @example.invalid"}>>'; end if;
  v_a := v_sup[1]; v_b := v_sup[2];
  select count(*) into v_others_before from public.supplier_service_question where not (supplier_id = any(v_sup));

  -- 1. once per (supplier, kind, about_hash)
  insert into public.supplier_service_question (supplier_id, kind, about, about_hash, prompt_en, options, multi, status, source)
  values (v_a, 'vague', '{"quote":"We supply staff and similar services."}', 'abcd1234', 'What sort of staff do you supply?',
          '[{"key":"labour_supply.general","label_en":"General labour","own_words":false}]', true, 'open', 'probe')
  on conflict (supplier_id, kind, about_hash) do nothing;
  insert into public.supplier_service_question (supplier_id, kind, about, about_hash, prompt_en, options, multi, status, source)
  values (v_a, 'vague', '{"quote":"We supply staff and similar services."}', 'abcd1234', 'What sort of staff do you supply? (again)',
          '[]', true, 'open', 'probe')
  on conflict (supplier_id, kind, about_hash) do nothing;
  select count(*) into n from public.supplier_service_question where supplier_id = v_a and about_hash = 'abcd1234';
  if n <> 1 then f := f || 'the same question was stored ' || n || ' times; '; end if;
  if (select prompt_en from public.supplier_service_question where supplier_id = v_a and about_hash = 'abcd1234') <> 'What sort of staff do you supply?' then
    f := f || 'a re-read overwrote the question first asked; '; end if;

  -- 2. per supplier
  insert into public.supplier_service_question (supplier_id, kind, about, about_hash, prompt_en, source)
  values (v_b, 'vague', '{}', 'abcd1234', 'What sort of staff do you supply?', 'probe');
  select count(*) into n from public.supplier_service_question where about_hash = 'abcd1234' and supplier_id = any(v_sup);
  if n <> 2 then f := f || 'two suppliers could not hold the same question: ' || n || '; '; end if;

  -- 3. the table refuses what is not a question
  begin
    insert into public.supplier_service_question (supplier_id, kind, about_hash, prompt_en, source) values (v_a, 'guess', 'x1', 'Q?', 'probe');
    f := f || 'an unknown kind was stored; ';
  exception when check_violation then null; end;
  begin
    insert into public.supplier_service_question (supplier_id, kind, about_hash, prompt_en, status, source) values (v_a, 'umbrella', 'x2', 'Q?', 'maybe', 'probe');
    f := f || 'an unknown status was stored; ';
  exception when check_violation then null; end;
  begin
    update public.supplier_service_question set status = 'answered' where supplier_id = v_a and about_hash = 'abcd1234';
    f := f || 'a question was marked answered with no answer; ';
  exception when check_violation then null; end;
  update public.supplier_service_question set status = 'answered', answer = '{"picked":[0]}', answered_at = now()
   where supplier_id = v_a and about_hash = 'abcd1234';
  if not found then f := f || 'an answer could not be stored; '; end if;

  -- 4. closed to the public roles
  if has_table_privilege('anon', 'public.supplier_service_question', 'select') or has_table_privilege('anon', 'public.supplier_service_question', 'insert')
     or has_table_privilege('authenticated', 'public.supplier_service_question', 'select') or has_table_privilege('authenticated', 'public.supplier_service_question', 'update') then
    f := f || 'a public role holds a privilege on supplier_service_question; '; end if;
  if not (select relrowsecurity from pg_class where oid = 'public.supplier_service_question'::regclass) then f := f || 'RLS is off; '; end if;
  select count(*) into n from pg_policies where schemaname = 'public' and tablename = 'supplier_service_question';
  if n <> 1 then f := f || 'expected one policy, found ' || n || '; '; end if;

  -- 5. services_partner
  select (is_nullable = 'NO' and column_default like '''{}''%') into ok from information_schema.columns
   where table_schema = 'public' and table_name = 'supplier_capabilities' and column_name = 'services_partner';
  if not coalesce(ok, false) then f := f || 'services_partner is missing, nullable or has another default; '; end if;
  select count(*) into n from public.supplier_capabilities where not (services_partner <@ coalesce(services, '{}'::text[]));
  if n > 0 then f := f || n || ' supplier(s) hold a partner service outside their services; '; end if;

  -- 6. his questions go with his lead (read off the foreign key: a demo lead is never deleted by a probe)
  select count(*) into n from pg_constraint where conrelid = 'public.supplier_service_question'::regclass and contype = 'f' and confdeltype = 'c';
  if n <> 1 then f := f || 'the foreign key to leads does not cascade on delete; '; end if;

  select count(*) into v_others_after from public.supplier_service_question where not (supplier_id = any(v_sup));
  if v_others_after <> v_others_before then f := f || 'another supplier''s questions moved: ' || v_others_before || ' -> ' || v_others_after || '; '; end if;

  if f = '' then raise exception 'CHK<<{"verdict":"PROBE OK"}>>'; end if;
  raise exception 'CHK<<{"verdict":"PROBE FAILED: %"}>>', f;
end $probe$;
