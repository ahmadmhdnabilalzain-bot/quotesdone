CREATE OR REPLACE FUNCTION public.fn_security_selfaudit()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_rls_off int; v_no_pol int; v_secviews int; v_secfns int;
        v_anon_tbl int; v_anon_views int; v_anon_defaults int; v_drift text[];
begin
  select count(*) into v_rls_off from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and not c.relrowsecurity;
  select count(*) into v_no_pol from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and c.relrowsecurity
      and not exists (select 1 from pg_policy p where p.polrelid=c.oid);
  select count(*) into v_secviews from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='v'
      and not (coalesce(c.reloptions,'{}') @> array['security_invoker=on'] or coalesce(c.reloptions,'{}') @> array['security_invoker=true']);
  select count(*) into v_secfns from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef and has_function_privilege('anon', p.oid, 'EXECUTE');
  -- allowlist: category_specs (open reference data) + blog_posts (public blog; RLS limits to published=true)
  select count(*) into v_anon_tbl from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and c.relname not in ('category_specs','blog_posts')
      and (has_table_privilege('anon',c.oid,'SELECT') or has_table_privilege('authenticated',c.oid,'SELECT'));
  select count(*) into v_anon_views from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind in ('v','m')
      and (has_table_privilege('anon',c.oid,'SELECT') or has_table_privilege('authenticated',c.oid,'SELECT'));
  select count(*) into v_anon_defaults from pg_default_acl d
    where d.defaclnamespace='public'::regnamespace and d.defaclrole='postgres'::regrole
      and (d.defaclacl::text like '%anon=%' or d.defaclacl::text like '%authenticated=%');

  insert into public.security_selfaudit_snapshots
    (rls_disabled_tables,rls_no_policy,secdef_views,secdef_fns_anon,anon_tables,anon_views,anon_defaults)
    values (v_rls_off, v_no_pol, v_secviews, v_secfns, v_anon_tbl, v_anon_views, v_anon_defaults);

  v_drift := array[]::text[];
  if v_rls_off       > 0 then v_drift := v_drift || ('rls_disabled_tables='||v_rls_off); end if;
  if v_anon_views    > 0 then v_drift := v_drift || ('anon_readable_views='||v_anon_views); end if;
  if v_anon_tbl      > 0 then v_drift := v_drift || ('anon_readable_tables='||v_anon_tbl); end if;
  if v_secfns        > 0 then v_drift := v_drift || ('anon_executable_secdef_fns='||v_secfns); end if;
  if v_anon_defaults > 0 then v_drift := v_drift || ('anon_default_privileges_postgres='||v_anon_defaults); end if;

  if array_length(v_drift,1) is not null then
    insert into public.security_events(kind,severity,source,subject,detail)
      values ('anon_exposure_drift','high','selfaudit','public schema',
              jsonb_build_object('drift',v_drift,'note','Anonymity-by-construction invariant broke: something in public is reachable by anon/authenticated beyond category_specs + blog_posts(published). See docs/upgrade/hotfix-2026-07-19.'));
    insert into public.founder_alerts(level,event,detail,channel)
      values ('high','Security drift: public data reachable by anon',
              'Daily self-audit found: '||array_to_string(v_drift,', ')||'. Anon/authenticated should only reach category_specs and published blog_posts. Review recent migrations/views/grants (see the 2026-07-19 hotfix).','selfaudit');
  end if;

  return jsonb_build_object('rls_disabled_tables',v_rls_off,'rls_no_policy',v_no_pol,'secdef_views',v_secviews,
    'secdef_fns_anon',v_secfns,'anon_tables',v_anon_tbl,'anon_views',v_anon_views,'anon_defaults',v_anon_defaults,'drift',v_drift);
end $function$
