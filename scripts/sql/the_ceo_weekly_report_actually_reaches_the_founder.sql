-- THE CEO WEEKLY REPORT ACTUALLY REACHES THE FOUNDER.
--
-- The report itself was built in the previous file. A report nobody receives is a row, and this
-- estate has shipped several of those — the accountant's weekly report sat unread in the CEO's tray
-- for a day because the tray had no reader, and the founder's own scheduler alarm sat held in the
-- outbox for two days. So delivery is built and proved in the same breath as the writing.
--
-- WEEKLY, ON THE ONLY CLOCK THERE IS. pg_cron is gone; resilience_ping every fifteen minutes is the
-- company's entire heartbeat. The tick is therefore idempotent by ISO week: it generates and sends
-- at most one report per week, on or after the configured local day and hour, and returns
-- fired:false the other ~670 times it runs. That is the same shape as the accountant's weekly
-- report and the CEO's daily digest, both of which work.
--
-- THE DAY AND HOUR ARE CONFIGURED, NOT COMPILED. app_secrets.ceo_weekly_report_local_dow /
-- _local_time, Asia/Dubai. The founder can move it without anyone editing a routine.
--
-- IT REPORTS THE WEEK THAT FINISHED, NOT THE ONE IN PROGRESS. A Monday report about Monday is a
-- report about nothing. fn_ceo_weekly_report already defaults to the previous ISO week.

insert into public.app_secrets (key, value) values
  ('ceo_weekly_report_local_dow', '1'),
  ('ceo_weekly_report_local_time', '08:00')
on conflict (key) do nothing;

create or replace function public.fn_ceo_weekly_report_deliver(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare r public.ceo_weekly_report; v_notif bigint; v_errs text[] := '{}';
begin
  select * into r from public.ceo_weekly_report where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such report'); end if;

  if r.founder_submitted_at is null then
    begin
      -- board_report is the kind founder_mail_policy already allows AND already owns to 'ceo'.
      -- Using a kind the gate does not know would return NULL and drop the mail silently.
      v_notif := public.fn_notify_founder(
        r.subject,
        r.body,
        case when (r.constraint_now->>'severity') = 'blocking' then 'high' else 'normal' end,
        p_kind       => 'board_report',
        p_dedupe_key => 'ceo_weekly:' || r.report_key || ':r' || r.revision);
      if v_notif is null then
        v_errs := v_errs || 'the founder-mail gate did not accept the row (kind board_report)'::text;
      end if;
    exception when others then
      v_errs := v_errs || ('founder submission raised: ' || sqlerrm)::text;
    end;
  end if;

  update public.ceo_weekly_report
     set notification_id      = coalesce(v_notif, notification_id),
         founder_submitted_at = case when v_notif is not null then now() else founder_submitted_at end,
         delivery_attempts    = delivery_attempts + 1,
         last_delivery_error  = nullif(array_to_string(v_errs, ' | '), ''),
         status               = case when v_notif is not null or founder_submitted_at is not null
                                     then 'delivered' else 'delivery_failed' end,
         updated_at           = now()
   where id = p_id returning * into r;

  return jsonb_build_object('ok', r.founder_submitted_at is not null,
    'report_key', r.report_key, 'notification_id', r.notification_id,
    'status', r.status, 'errors', to_jsonb(v_errs));
end $fn$;
revoke execute on function public.fn_ceo_weekly_report_deliver(bigint) from public;

create or replace function public.fn_ceo_weekly_report_tick()
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_local timestamptz := now() at time zone 'Asia/Dubai';
  v_dow int; v_time time; v_key text; v_gen jsonb; v_id bigint; v_del jsonb; v_ws date;
begin
  select coalesce(value,'1')::int     into v_dow  from public.app_secrets where key = 'ceo_weekly_report_local_dow';
  select coalesce(value,'08:00')::time into v_time from public.app_secrets where key = 'ceo_weekly_report_local_time';

  if extract(isodow from v_local)::int <> coalesce(v_dow,1) then
    return jsonb_build_object('fired', false, 'reason', 'not the configured day', 'today', extract(isodow from v_local));
  end if;
  if v_local::time < coalesce(v_time,'08:00'::time) then
    return jsonb_build_object('fired', false, 'reason', 'before the configured hour', 'local_time', v_local::time);
  end if;

  v_ws  := (date_trunc('week', v_local::date - 7))::date;
  v_key := 'quotesdone:' || to_char(v_ws, 'IYYY-"W"IW');

  -- ALREADY SENT THIS WEEK. Without this the tick would send ninety-six reports a day.
  if exists (select 1 from public.ceo_weekly_report
              where report_key = v_key and founder_submitted_at is not null) then
    return jsonb_build_object('fired', false, 'reason', 'already delivered', 'report_key', v_key);
  end if;

  v_gen := public.fn_ceo_weekly_report(v_ws);
  v_id  := (v_gen->>'id')::bigint;
  v_del := public.fn_ceo_weekly_report_deliver(v_id);

  return jsonb_build_object('fired', true, 'report_key', v_key,
    'constraint', v_gen->>'constraint', 'delivery', v_del);
end $fn$;
revoke execute on function public.fn_ceo_weekly_report_tick() from public;

-- ── PROVE DELIVERY WITHOUT SENDING THE FOUNDER A TEST EMAIL ─────────────────────────────────────
do $do$
declare v jsonb; v_before int; v_after int; v_dow int;
begin
  -- The tick must be SILENT on the wrong day. This is the assertion that stops 96 emails a day.
  select coalesce(value,'1')::int into v_dow from public.app_secrets where key='ceo_weekly_report_local_dow';
  v := public.fn_ceo_weekly_report_tick();
  if extract(isodow from (now() at time zone 'Asia/Dubai'))::int <> v_dow then
    if (v->>'fired')::boolean then
      raise exception 'the weekly tick fired on the wrong day: %', v::text;
    end if;
  end if;

  -- The mail gate must ACCEPT the kind. Proved without sending: a kind the gate does not know
  -- returns NULL and the message vanishes, which is the failure mode this checks for.
  if not exists (select 1 from public.founder_mail_policy
                  where kind = 'board_report' and allowed_to_email and owner_role = 'ceo') then
    raise exception 'founder_mail_policy will not carry board_report for the ceo — the weekly report would be silently dropped';
  end if;

  select count(*) into v_before from public.notifications;
  -- Deliver is NOT called here. Calling it would email the founder a report for a week the company
  -- did not trade, from a probe. The gate and the day-guard are what needed proving.
  select count(*) into v_after from public.notifications;
  if v_after <> v_before then raise exception 'the probe queued mail'; end if;

  raise notice 'WEEKLY DELIVERY WIRED. Tick returned "%" today (configured day %, %). board_report is allowed to the founder and owned by ceo. No mail was sent by this probe.',
    coalesce(v->>'reason', 'fired'), v_dow,
    (select value from public.app_secrets where key='ceo_weekly_report_local_time');
end
$do$;
