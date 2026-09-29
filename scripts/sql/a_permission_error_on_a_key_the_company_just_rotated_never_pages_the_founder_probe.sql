-- PROBE (always raises, nothing survives): a 70004 on a key the company rotated inside its overlap is not mailed to
-- the founder; the same finding with no rotation in overlap is (stubbed). ZZ provider name, founder mail stubbed.
do $p$
declare r1 jsonb; r2 jsonb; k text := 'duty:integration:zz_probe_rotated_key'; a boolean; b boolean;
begin
  perform set_config('app.qd_stub_founder_notify', 'on', true);
  perform public.fn_it_engineer_finding_upsert(k, 'zz_probe_rotated_key (ZZ DEMO): answered HTTP 401: {"code":70004,"message":"The provided key does not have the permissions"}',
    'probe', 'internal', 0, jsonb_build_object('notify', true, 'what_broke', 'answered HTTP 401: {"code":70004}'), '{}'::text[], '{}'::text[], 'it_engineer');
  update public.it_engineer_finding set seen_count = 3 where issue_key = k;
  insert into public.it_credential_rotation (provider, context, secret_key, status, new_ref, rotated_at, overlap_until, note)
  values ('zz_probe_rotated_key', 'ZZ DEMO probe', 'zz_probe_key', 'overlap', 'SKzzprobe', now(), now() + interval '3 days', 'ZZ DEMO probe row, rolled back');
  r1 := public.fn_it_integration_settle('integration', jsonb_build_array(jsonb_build_object('item', 'zz_probe_rotated_key', 'carried', true, 'title', 'zz_probe_rotated_key (ZZ DEMO): answered HTTP 401: {"code":70004}', 'what_broke', 'answered HTTP 401: {"code":70004}', 'notify', true)));
  a := exists (select 1 from jsonb_array_elements(r1->'mailed') m where m->>'key' = k);
  delete from public.it_credential_rotation where provider = 'zz_probe_rotated_key';
  r2 := public.fn_it_integration_settle('integration', jsonb_build_array(jsonb_build_object('item', 'zz_probe_rotated_key', 'carried', true, 'title', 'zz_probe_rotated_key (ZZ DEMO): answered HTTP 401: {"code":70004}', 'what_broke', 'answered HTTP 401: {"code":70004}', 'notify', true)));
  b := exists (select 1 from jsonb_array_elements(r2->'mailed') m where m->>'key' = k);
  raise exception 'CHK<<%>>', case when not a and b then 'PROBE OK: in overlap not mailed; without the rotation mailed (stubbed)'
    else format('PROBE FAILED: mailed_in_overlap=%s mailed_without=%s', a, b) end;
end $p$;
