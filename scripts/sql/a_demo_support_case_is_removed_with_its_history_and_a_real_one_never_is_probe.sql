-- PROBE (rolled back, never applied) for a_demo_support_case_is_removed_with_its_history_and_a_real_one_never_is.sql
-- (it_engineer, 12 Nov 2026). A pure probe: it always raises, so every row it writes rolls back.
--   node scripts/ci/rehearse_sql.mjs scripts/sql/a_demo_support_case_is_removed_with_its_history_and_a_real_one_never_is.sql \
--        scripts/sql/a_demo_support_case_is_removed_with_its_history_and_a_real_one_never_is_probe.sql
-- Its subject is a ZZ DEMO person at a reserved .invalid address, so nothing can reach anyone. Proves: a demo case with
-- a summary version and a promise is removed with them; a direct delete of a version is still refused, with or without
-- the flag set by hand on a real case; a REAL case (one production holds, chosen by the demo test) is refused by the
-- routine and its rows are counted unchanged; the foreign keys into support_case are the ones the routine knows.
do $probe$
declare
  v_email text := 'zz-demo-purge-probe-' || txid_current() || '@example.invalid';
  v_open jsonb; v_prof bigint; v_case jsonb; v_id bigint; v_w jsonb; v_r jsonb; v_real bigint; v_real_v int; v_real_c int;
  v_fks text;
begin
  select string_agg(conrelid::regclass::text, ',' order by conrelid::regclass::text) into v_fks
    from pg_constraint where contype = 'f' and confrelid = 'public.support_case'::regclass;
  if v_fks is distinct from 'feedback,refund_case,support_case,support_case_promise,support_case_summary_version,support_document_intake,support_notification' then
    raise exception 'PROBE FAILED: the tables pointing at support_case changed (%): teach fn_demo_support_case_purge', v_fks;
  end if;

  v_open := public.fn_support_open_cases('unknown', null, v_email, null);
  v_prof := (v_open ->> 'profile')::bigint;
  v_case := public.fn_support_case_route(v_prof, 'new', null, 'widget', 'ZZ DEMO purge probe', 'en');
  v_id := (select case_id from public.support_case where case_ref = v_case ->> 'case_ref');
  v_w := public.fn_support_case_summary_write(v_case ->> 'case_ref', 0,
    '{"asked":"a quote","said_or_did":"asked for sizes","promised":[],"open":["sizes"]}', 'ASKED: a quote', 'ZZ DEMO purge probe', 'customer_support', 'probe');
  insert into public.support_case_promise (case_id, case_ref, promise_key, what, due_at, due_basis, owner_seat, stated_in_version, is_demo)
  values (v_id, v_case ->> 'case_ref', 'zz-demo-probe', 'ZZ DEMO send the quotes', now() + interval '1 day', 'assumed', 'customer_support', 1, true);
  if v_id is null or not public.fn_support_case_is_demo(v_id)
     or (select count(*) from public.support_case_summary_version where case_id = v_id) <> 1 then
    raise exception 'PROBE FAILED: the demo fixture did not form (case %, write %)', v_id, v_w;
  end if;

  begin
    delete from public.support_case_summary_version where case_id = v_id;
    raise exception 'PROBE FAILED: a direct delete of a demo version went through without the routine';
  exception when raise_exception then
    if sqlerrm not like '%append-only%' then raise; end if;
  end;

  -- the realest case production holds: one with summary versions if any, else any case the demo test calls real
  select c.case_id into v_real from public.support_case c
   where not public.fn_support_case_is_demo(c.case_id)
   order by exists (select 1 from public.support_case_summary_version v where v.case_id = c.case_id) desc, c.case_id limit 1;
  if v_real is not null then
    select count(*) into v_real_v from public.support_case_summary_version where case_id = v_real;
    perform set_config('qd.demo_case_purge', 'on', true);
    if v_real_v > 0 then
      begin
        delete from public.support_case_summary_version where case_id = v_real;
        raise exception 'PROBE FAILED: with the flag set by hand a REAL case''s history was deleted';
      exception when raise_exception then
        if sqlerrm not like '%append-only%' then raise; end if;
      end;
    end if;
    perform set_config('qd.demo_case_purge', 'off', true);
  end if;

  v_r := public.fn_demo_support_case_purge(array[v_id] || coalesce(array[v_real], '{}'::bigint[]));
  if (v_r ->> 'deleted')::int <> 1 or (v_r ->> 'summary_versions')::int <> 1 or (v_r ->> 'promises')::int <> 1
     or exists (select 1 from public.support_case where case_id = v_id) then
    raise exception 'PROBE FAILED: the demo case was not removed with its history: %', v_r;
  end if;
  if v_real is not null then
    select count(*) into v_real_c from public.support_case where case_id = v_real;
    if v_real_c <> 1 or (select count(*) from public.support_case_summary_version where case_id = v_real) <> v_real_v
       or not (v_r -> 'refused') @> jsonb_build_array(jsonb_build_object('case_id', v_real)) then
      raise exception 'PROBE FAILED: real case % was not refused and left as it was: %', v_real, v_r;
    end if;
  end if;
  if coalesce(current_setting('qd.demo_case_purge', true), '') = 'on' then raise exception 'PROBE FAILED: the flag stayed on'; end if;
  raise exception 'PROBE OK: demo case % removed with 1 version and 1 promise; real case % refused (% versions kept)', v_id, v_real, v_real_v;
end
$probe$;
