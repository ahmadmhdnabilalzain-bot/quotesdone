-- PROBE: never applied. Always raises CHK<<...>>, so nothing survives. Seat: ceo. Before the file is live, the check
-- replays the file and this probe in one rolled-back transaction.
--
-- With the switch ON inside this transaction, it forces a state the decision must act on, runs the real routine, and
-- reads the effect: the cap came down, was never above the founder's schedule, the action and its review row exist, and a
-- raise that met a bad reading was rolled back. The report is built with its switch off, so no mail row is queued; then
-- with it on, inside this transaction, it must queue exactly one founder row.
do $probe$
declare
  v_at timestamptz := (date_trunc('day', now() at time zone 'Asia/Dubai') + interval '7 hours') at time zone 'Asia/Dubai';
  v_today date := (v_at at time zone 'Asia/Dubai')::date; v_founder int := public.fn_invite_founder_cap(v_today);
  v_res jsonb; v_cap int; v_rows int; v_run int; v_rep jsonb; v_mail0 int; v_mail1 int; v_off jsonb; v_rb text; v_supplier_rows0 int; v_supplier_rows1 int; v_sec_before text;
begin
  select count(*) into v_supplier_rows0 from public.notifications where type like 'supplier_invite%';
  delete from public.ceo_growth_action;
  update public.app_secrets set value = (v_founder + 25)::text where key = 'invite_daily_cap';

  -- switch off: the decision is logged and nothing moves
  v_res := public.fn_ceo_growth_act(v_at);
  select value::int into v_cap from public.app_secrets where key = 'invite_daily_cap';
  if v_cap <> v_founder + 25 then raise exception 'CHK<<PROBE FAILED: the switch was off and the cap moved>>'; end if;
  if not exists (select 1 from public.ceo_growth_action where power = 'cap' and not applied and verdict = 'not_applied') then raise exception 'CHK<<PROBE FAILED: off wrote no logged decision: %>>', v_res; end if;
  if not exists (select 1 from public.ceo_growth_action where power = 'run') then raise exception 'CHK<<PROBE FAILED: no run row>>'; end if;
  v_res := public.fn_ceo_growth_act(v_at);
  if (v_res->>'ran')::boolean then raise exception 'CHK<<PROBE FAILED: ran twice in a day>>'; end if;

  -- switch on: it acts, and the schedule wins
  delete from public.ceo_growth_action;
  update public.app_secrets set value = 'true' where key = 'ceo_growth_act_golive';
  v_res := public.fn_ceo_growth_act(v_at);
  select value::int into v_cap from public.app_secrets where key = 'invite_daily_cap';
  if v_cap > v_founder then raise exception 'CHK<<PROBE FAILED: cap % above the ceiling %>>', v_cap, v_founder; end if;
  select count(*) into v_rows from public.ceo_growth_action where power = 'cap' and applied and verdict = 'pending' and review_on is not null;
  if v_rows <> 1 then raise exception 'CHK<<PROBE FAILED: no applied cap action: %>>', v_res; end if;

  -- the review: a raise that meets a bad reading goes back, and its effect is written
  insert into public.ceo_growth_action (decided_on, power, subject, before_value, after_value, reason, applied, baseline, review_on, verdict, dedupe_key)
  values (v_today - 3, 'cap', 'invite_daily_cap', '5', '15', 'probe raise', true, '{"sent_7d":0}', v_today, 'pending', 'probe:raise');
  perform public.fn_ceo_growth_review(v_at, jsonb_build_object('bounce_rate_7d', 0.5, 'max_bounce', 0.03, 'sent_7d', 40, 'complained_48h', 0, 'invite_enabled', true, 'wa_brake', false, 'wa_reading_ok', false), true);
  select verdict into v_rb from public.ceo_growth_action where dedupe_key = 'probe:raise';
  select value::int into v_cap from public.app_secrets where key = 'invite_daily_cap';
  if v_rb <> 'rolled_back' or v_cap <> least(5, v_founder) then raise exception 'CHK<<PROBE FAILED: rollback verdict % cap %>>', v_rb, v_cap; end if;
  if (select effect from public.ceo_growth_action where dedupe_key = 'probe:raise') is null then raise exception 'CHK<<PROBE FAILED: no effect written>>'; end if;

  -- switch off: a failing raise is measured, never marked rolled back
  update public.app_secrets set value = 'false' where key = 'ceo_growth_act_golive';
  insert into public.ceo_growth_action (decided_on, power, subject, before_value, after_value, reason, applied, baseline, review_on, verdict, dedupe_key)
  values (v_today - 3, 'cap', 'invite_daily_cap', '5', '15', 'probe off', true, '{}', v_today, 'pending', 'probe:off');
  perform public.fn_ceo_growth_review(v_at, jsonb_build_object('bounce_rate_7d', 0.5, 'max_bounce', 0.03, 'sent_7d', 40, 'complained_48h', 0), false);
  if (select verdict from public.ceo_growth_action where dedupe_key = 'probe:off') <> 'pending' then raise exception 'CHK<<PROBE FAILED: switch off changed a verdict>>'; end if;

  -- the report: off queues nothing; on queues one email and no WhatsApp
  select count(*) into v_mail0 from public.notifications where kind = 'ceo_daily_number';
  v_off := public.fn_ceo_daily_number_report(v_at + interval '2 hours');
  select count(*) into v_mail1 from public.notifications where kind = 'ceo_daily_number';
  if v_mail1 <> v_mail0 or v_off->>'would_say' is null then raise exception 'CHK<<PROBE FAILED: report off: %>>', v_off; end if;
  if v_off->>'would_say' ~* public.fn_ceo_founder_text_forbidden() then raise exception 'CHK<<PROBE FAILED: reserved word in the report: %>>', v_off->>'would_say'; end if;
  update public.app_secrets set value = 'true' where key = 'ceo_daily_number_golive';
  v_rep := public.fn_ceo_daily_number_report(v_at + interval '2 hours');
  select count(*) into v_mail1 from public.notifications where kind = 'ceo_daily_number';
  if v_mail1 <> v_mail0 + 1 then raise exception 'CHK<<PROBE FAILED: report on queued % rows: %>>', v_mail1 - v_mail0, v_rep; end if;

  -- nothing here wrote to a supplier
  select count(*) into v_supplier_rows1 from public.notifications where type like 'supplier_invite%';
  if v_supplier_rows1 <> v_supplier_rows0 then raise exception 'CHK<<PROBE FAILED: an invitation row was written>>'; end if;

  raise exception 'CHK<<PROBE OK decided=% cap_after_rollback=% text=%>>', v_res->>'decisions', v_cap, v_off->>'would_say';
end $probe$;
