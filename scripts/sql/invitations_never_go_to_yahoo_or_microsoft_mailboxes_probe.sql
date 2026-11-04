-- PROBE for invitations_never_go_to_yahoo_or_microsoft_mailboxes.sql. Never applied: it writes nothing and always
-- raises CHK<<...>>. Run after the file (or with it, in one rolled-back transaction): the deployed
-- fn_invite_placement_open_providers must carry the exclusion, and today's live list must hold neither class.
-- Before the apply it says PROBE FAILED (deployed_routine_has_no_exclusion). Seat: sales_engineer.
do $probe$
declare v text[]; src text; fails text := '';
begin
  select p.prosrc into src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_invite_placement_open_providers';
  if src is null or position('''microsoft'', ''yahoo_aol''' in src) = 0 then fails := fails || ' deployed_routine_has_no_exclusion'; end if;
  v := public.fn_invite_placement_open_providers((now() at time zone 'Asia/Dubai')::date, now());
  if 'microsoft' = any(v) or 'yahoo_aol' = any(v) then fails := fails || ' live_list_open'; end if;
  raise exception 'CHK<<%>>', case when fails = '' then 'PROBE OK live_open=' || coalesce(array_to_string(v, ','), '')
                                    else 'PROBE FAILED:' || fails end;
end $probe$;
