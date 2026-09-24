-- marketing, 24 Sep 2026, ledger 993. PURE PROBE (no DDL): raise exception rolls everything back.
-- Ten ZZ DEMO leads (@example.invalid) are "invited" today with the campaign switched on; three bounce.
-- Expect: invite_enabled false, the it_engineer finding open, and the brake's agent_runs row.
-- Then the same with ONE complaint. Nothing survives the raise; no real lead is touched.
do $probe$
declare
  v_ids bigint[]; v_on text; v_find int; v_run int; v_on2 text;
begin
  update app_secrets set value = 'true' where key = 'invite_enabled';
  delete from it_watch_finding where detector_key = 'deliverability:supplier_invite';

  with ins as (
    insert into leads(company_name, email, invited_at, invite_status)
    select 'ZZ DEMO brake probe ' || g, 'zz-brake-' || g || '@example.invalid', now(), 'sent'
      from generate_series(1, 10) g
    returning id)
  select array_agg(id) into v_ids from ins;

  update leads set invite_status = 'bounced' where id = any(v_ids[1:2]);
  select value into v_on from app_secrets where key = 'invite_enabled';
  if v_on <> 'true' then raise exception 'CHK<<FAIL: paused on 2 bounces, below the 3-bounce floor>>'; end if;

  update leads set invite_status = 'bounced' where id = v_ids[3];
  select value into v_on from app_secrets where key = 'invite_enabled';
  select count(*) into v_find from it_watch_finding where detector_key = 'deliverability:supplier_invite' and status = 'open';
  select count(*) into v_run from agent_runs where agent = 'invite_same_day_brake' and finished_at > now() - interval '1 minute';

  -- complaint path
  update app_secrets set value = 'true' where key = 'invite_enabled';
  update leads set invite_status = 'complained' where id = v_ids[4];
  select value into v_on2 from app_secrets where key = 'invite_enabled';

  raise exception 'CHK<<%>>', case when v_on = 'false' and v_find = 1 and v_run >= 1 and v_on2 = 'false'
    then 'PROBE OK: 3 bounces paused, finding opened, run logged; 1 complaint paused'
    else format('PROBE FAILED: bounce-paused=%s finding=%s run=%s complaint-paused=%s', v_on = 'false', v_find, v_run, v_on2 = 'false') end;
end
$probe$;
