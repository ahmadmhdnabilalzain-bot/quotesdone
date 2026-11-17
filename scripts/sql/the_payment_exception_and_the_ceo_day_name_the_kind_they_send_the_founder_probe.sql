-- PROBE for the_payment_exception_and_the_ceo_day_name_the_kind_they_send_the_founder.sql. Seat: it_engineer. Never applied: it writes nothing and always raises CHK<<...>>. Run after the file.
-- Asserts from the catalogue: each routine now names p_kind on its fn_notify_founder call with the kind it always sent, the
-- kind is registered in founder_mail_policy, and neither routine is executable by public, anon or authenticated.
do $probe$
declare v_bad text := ''; r record;
begin
  for r in select * from (values ('public.fn_accountant_escalates_payment_exception(uuid,text,text,text,boolean)'::regprocedure, 'finance_alert'),
                                 ('public.fn_ceo_daily_summary_to_the_founder(timestamptz)'::regprocedure, 'ceo_daily_summary')) v(f, kind) loop
    if (select prosrc from pg_proc where oid = r.f) !~ ('p_kind => ''' || r.kind || '''') then v_bad := v_bad || ' unnamed:' || r.f::text; end if;
    if not exists (select 1 from public.founder_mail_policy where kind = r.kind) then v_bad := v_bad || ' unregistered:' || r.kind; end if;
    if has_function_privilege('anon', r.f, 'execute') or has_function_privilege('authenticated', r.f, 'execute') then
      v_bad := v_bad || ' open:' || r.f::text; end if;
  end loop;
  if v_bad <> '' then raise exception 'CHK<<PROBE FAILED:%>>', v_bad; end if;
  raise exception 'CHK<<PROBE OK both name their kind, both kinds registered, both closed>>';
end $probe$;
