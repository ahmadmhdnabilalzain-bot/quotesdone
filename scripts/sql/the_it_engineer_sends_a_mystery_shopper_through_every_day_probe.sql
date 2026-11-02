-- PROBE: the mystery shopper's report reaches the IT engineer. Pure probe, no DDL: run AFTER
-- the_it_engineer_sends_a_mystery_shopper_through_every_day.sql; it always ends in raise exception CHK<<...>>, so the
-- findings and heartbeats it writes do not survive. It contacts no one (findings and agent_runs rows only).
-- PROBE OK only if:
--   1. a FAIL at matching files duty:mystery_shopper:matching, its title naming the step and the error, owned by the
--      sales engineer; a SKIP after it files nothing; the PASS steps file nothing;
--   2. the next run, all PASS, closes it;
--   3. with the last report more than 26 hours old the heartbeat duty raises duty:mystery_shopper_heartbeat:no_run, and
--      a fresh report clears it.
do $probe$
declare v jsonb; f public.it_engineer_finding; v_skip int; v_pass int; v_closed timestamptz; v_hb int; v_hb2 int; v_fail text := '';
begin
  update public.it_engineer_finding set closed_at = now(), close_note = 'probe reset'
   where issue_key like 'duty:mystery_shopper%' and closed_at is null;

  v := public.fn_it_engineer_mystery_shopper_ingest('{"tag":"probems01","steps":[
      {"step":"preflight","status":"PASS"},{"step":"signup","status":"PASS"},
      {"step":"matching","status":"FAIL","error":"the matcher found 1 of the run''s 2 exact-trade suppliers"},
      {"step":"quote","status":"SKIP","error":"not run: matching broke first"},{"step":"cleanup","status":"PASS"}]}');
  select * into f from public.it_engineer_finding where issue_key = 'duty:mystery_shopper:matching' and closed_at is null;
  if f.issue_key is null then v_fail := v_fail || ' no finding for the broken step;';
  elsif f.title !~ 'matching' or f.title !~ '1 of the run' then v_fail := v_fail || ' the title does not name the step and the error: ' || f.title || ';';
  elsif f.evidence->>'owner_seat' is distinct from 'sales_engineer' then v_fail := v_fail || ' owner ' || coalesce(f.evidence->>'owner_seat', 'none') || ';';
  end if;
  select count(*) into v_skip from public.it_engineer_finding where issue_key = 'duty:mystery_shopper:quote' and closed_at is null;
  select count(*) into v_pass from public.it_engineer_finding where issue_key in ('duty:mystery_shopper:signup', 'duty:mystery_shopper:cleanup') and closed_at is null;
  if v_skip > 0 then v_fail := v_fail || ' a skipped step was filed as broken;'; end if;
  if v_pass > 0 then v_fail := v_fail || ' a passing step was filed;'; end if;

  v := public.fn_it_engineer_mystery_shopper_ingest('{"tag":"probems02","steps":[{"step":"preflight","status":"PASS"},{"step":"signup","status":"PASS"},
      {"step":"matching","status":"PASS"},{"step":"quote","status":"PASS"},{"step":"comparison","status":"PASS"},{"step":"cleanup","status":"PASS"}]}');
  select closed_at into v_closed from public.it_engineer_finding where issue_key = 'duty:mystery_shopper:matching';
  if v_closed is null then v_fail := v_fail || ' an all-PASS run did not close the finding;'; end if;

  update public.agent_runs set finished_at = now() - interval '30 hours'
   where agent = 'it_engineer' and counts->>'job' = 'mystery_shopper';
  perform public.fn_it_engineer_mystery_shopper_heartbeat();
  select count(*) into v_hb from public.it_engineer_finding where issue_key = 'duty:mystery_shopper_heartbeat:no_run' and closed_at is null;
  v := public.fn_it_engineer_mystery_shopper_ingest('{"tag":"probems03","steps":[{"step":"cleanup","status":"PASS"}]}');
  perform public.fn_it_engineer_mystery_shopper_heartbeat();
  select count(*) into v_hb2 from public.it_engineer_finding where issue_key = 'duty:mystery_shopper_heartbeat:no_run' and closed_at is null;
  if v_hb <> 1 then v_fail := v_fail || ' a 30-hour silence raised ' || v_hb || ' heartbeat finding(s);'; end if;
  if v_hb2 <> 0 then v_fail := v_fail || ' a fresh report did not clear the heartbeat;'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK matching FAIL filed to sales_engineer naming the error; SKIP and PASS filed nothing; '
      || 'all-PASS closed it; 30 h silence raised the heartbeat, a fresh report cleared it'
    else 'PROBE FAILED:' || v_fail end;
end $probe$;
