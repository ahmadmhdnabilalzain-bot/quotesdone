-- PROBE for the_invitation_batch_runs_on_its_own_clock_and_the_guard_takes_the_link_less_copy.sql. Pure probe: no
-- DDL, it always raises CHK<<...>>, so every row enqueue_supplier_invites writes (notifications, leads, invite_schedule,
-- agent_runs) rolls back. It runs the REAL batch under the duty's own 60 s limit, after the fix is applied, and proves:
--   * no SUPPLIER_INVITE_REFUSED: the link-less approved copy passes a07_notifications_supplier_invite_is_whole;
--   * app_secrets is byte-identical before and after (the probe never writes a switch, cap or brake);
--   * every queued recipient is in a provider class fn_invite_placement_open_providers opened today.
-- It calls enqueue_supplier_invites, not the tick: the tick's fn_invite_ramp writes invite_daily_cap in app_secrets.
-- Measured 28 Oct 2026 ~06:20Z with the fix in the same rolled-back transaction: queued=20, 13.4 s, secrets unchanged.
do $probe$
declare a timestamptz; v int; s0 text; s1 text; n int; n_closed int; t numeric; o text[];
begin
  perform set_config('statement_timeout', '60s', true);
  select md5(string_agg(key || value, ',' order by key)) into s0 from public.app_secrets;
  o := public.fn_invite_placement_open_providers((now() at time zone 'Asia/Dubai')::date);
  a := clock_timestamp();
  begin
    v := public.enqueue_supplier_invites(null);
  exception when check_violation then
    raise exception 'CHK<<PROBE FAILED: %>>', sqlerrm;
  end;
  t := round(extract(epoch from clock_timestamp() - a), 2);
  select md5(string_agg(key || value, ',' order by key)) into s1 from public.app_secrets;
  select count(*) into n from public.notifications where type = 'supplier_invite' and created_at = now();
  select count(*) into n_closed from public.notifications x
   where x.type = 'supplier_invite' and x.created_at = now()
     and not (public.fn_mail_provider_of_email(x.to_email) = any (o));
  raise exception 'CHK<<%>>', case
    when s0 is distinct from s1 then 'PROBE FAILED: app_secrets changed'
    when n <> coalesce(v, 0) then 'PROBE FAILED: returned ' || v || ' but wrote ' || n || ' row(s)'
    when n_closed > 0 then 'PROBE FAILED: ' || n_closed || ' recipient(s) outside the open classes ' || array_to_string(o, ',')
    else 'PROBE OK: queued=' || coalesce(v, 0) || ' secs=' || t || ' open=' || array_to_string(o, ',')
         || ' run=' || coalesce((select note from public.agent_runs where agent = 'supplier_invites' order by id desc limit 1), '-') end;
end $probe$;
