-- PROBE (pure, no DDL, aborted transaction) for the_ceo_applies_its_safety_side_growth_powers_without_waiting_for_a_switch.sql.
-- Seat: ceo. Run AFTER the definition in the same transaction; it ends in raise exception, so nothing survives.
-- 1. The classifier on every decision kind (pure). 2. The brake floor (pure). 3. The act itself, for tomorrow 07:00 Dubai
-- with the switch as production has it (off since 2 Nov): every safety-side decision is applied, the ceiling is not, the cap
-- written is never above the founder's schedule, and the run row counts the safety-side ones. Nothing is sent: the act
-- writes settings, ranks and directives, and every one of them rolls back with the raise.
do $p$
declare
  r jsonb := '{"cur_cap":20,"founder_cap":20,"own_pause_days_ago":null}'::jsonb;
  c_cut boolean; c_raise boolean; c_giveback boolean; c_giveback_over boolean; c_reach_on boolean; c_reach_off boolean;
  c_close boolean; c_open_own boolean; c_open_not_own boolean; c_wa_open boolean; c_wa_close boolean; c_ceiling boolean; c_trade boolean; c_dir boolean;
  b jsonb := '{"max_bounce":0.05,"bounce_rate_7d":0.11,"bounced_7d":4,"sent_7d":35,"complained_48h":0,"complained_7d":0,"invite_enabled":true,"cur_cap":8,"founder_cap":20,"reachable_only":true,"trade_live":5,"wa_golive":false,"wa_opt_ins":0,"wa_template_approved":false,"wa_reading_ok":false,"wa_brake":false}'::jsonb;
  d8 jsonb; d5 jsonb; d20 jsonb; cap8 text; cap5 text; cap20 text;
  v_at timestamptz := ((now() at time zone 'Asia/Dubai')::date + 1 + time '07:00') at time zone 'Asia/Dubai';
  v_switch_on boolean; v_res jsonb; v_cap_after int; v_founder int; v_ceiling_applied int; v_safe_rows int; v_run text; v_ok boolean;
begin
  c_cut          := public.fn_ceo_growth_power_is_safe('{"power":"cap","to":10}', r, null);
  c_raise        := public.fn_ceo_growth_power_is_safe('{"power":"cap","to":30}', r, null);
  c_giveback     := public.fn_ceo_growth_power_is_safe('{"power":"cap","to":20}', '{"cur_cap":10}', 20);
  c_giveback_over:= public.fn_ceo_growth_power_is_safe('{"power":"cap","to":30}', '{"cur_cap":20}', 20);
  c_reach_on     := public.fn_ceo_growth_power_is_safe('{"power":"reachable","to":true}', r, null);
  c_reach_off    := public.fn_ceo_growth_power_is_safe('{"power":"reachable","to":false}', r, null);
  c_close        := public.fn_ceo_growth_power_is_safe('{"power":"channel","subject":"email_supplier_mailbox","to":"close"}', r, null);
  c_open_own     := public.fn_ceo_growth_power_is_safe('{"power":"channel","subject":"email_supplier_mailbox","to":"open"}', '{"own_pause_days_ago":8}', null);
  c_open_not_own := public.fn_ceo_growth_power_is_safe('{"power":"channel","subject":"email_supplier_mailbox","to":"open"}', r, null);
  c_wa_open      := public.fn_ceo_growth_power_is_safe('{"power":"channel","subject":"whatsapp_opt_in","to":"open"}', r, null);
  c_wa_close     := public.fn_ceo_growth_power_is_safe('{"power":"channel","subject":"whatsapp_opt_in","to":"close"}', r, null);
  c_ceiling      := public.fn_ceo_growth_power_is_safe('{"power":"ceiling","to":30}', r, null);
  c_trade        := public.fn_ceo_growth_power_is_safe('{"power":"trade","subject":"signage","to":"first"}', r, null);
  c_dir          := public.fn_ceo_growth_power_is_safe('{"power":"directive","subject":"x"}', r, null);

  d8  := public.fn_ceo_growth_decide(b);
  d5  := public.fn_ceo_growth_decide(b || '{"cur_cap":5}');
  d20 := public.fn_ceo_growth_decide(b || '{"cur_cap":20}');
  select e->>'to' into cap8  from jsonb_array_elements(d8)  e where e->>'power' = 'cap';
  select e->>'to' into cap5  from jsonb_array_elements(d5)  e where e->>'power' = 'cap';
  select e->>'to' into cap20 from jsonb_array_elements(d20) e where e->>'power' = 'cap';

  -- 3. the act. The switch is READ, never written: writing its row took the same tuple lock as the older growth probe
  -- (the_ceo_holds_the_supplier_target_and_acts_within_bounded_powers_probe.sql), and two checks run side by side
  -- deadlocked on it (40P01, 10 Nov). With the switch on, the safety-side count is 0 by definition and is asserted so.
  v_switch_on := coalesce((select value from public.app_secrets where key = 'ceo_growth_act_golive'), '') = 'true';
  v_res := public.fn_ceo_growth_act(v_at);
  v_founder := public.fn_invite_founder_cap((v_at at time zone 'Asia/Dubai')::date);
  select value::int into v_cap_after from public.app_secrets where key = 'invite_daily_cap';
  select count(*) into v_ceiling_applied from public.ceo_growth_action
   where decided_on = (v_at at time zone 'Asia/Dubai')::date and power = 'ceiling' and applied;
  select count(*) into v_safe_rows from public.ceo_growth_action
   where decided_on = (v_at at time zone 'Asia/Dubai')::date and power <> 'run' and applied;
  select reason into v_run from public.ceo_growth_action where dedupe_key = 'run:' || (v_at at time zone 'Asia/Dubai')::date;

  v_ok := c_cut and not c_raise and c_giveback and not c_giveback_over and c_reach_on and not c_reach_off and c_close
          and c_open_own and not c_open_not_own and not c_wa_open and c_wa_close and not c_ceiling and c_trade and c_dir
          and cap8 = '5' and cap5 is null and cap20 = '10'
          and coalesce((v_res->>'ran')::boolean, false) and v_ceiling_applied = 0 and v_cap_after <= v_founder
          and coalesce((v_res->>'safety_side')::int, -1) = case when v_switch_on then 0 else v_safe_rows end
          and v_run like '%safety-side with the switch off%';
  raise exception '% CHK<<%>>', case when v_ok then 'PROBE OK' else 'PROBE FAILED' end, jsonb_build_object(
    'classifier', jsonb_build_object('cut', c_cut, 'raise', c_raise, 'giveback', c_giveback, 'giveback_over', c_giveback_over,
      'reach_on', c_reach_on, 'reach_off', c_reach_off, 'close', c_close, 'open_own', c_open_own, 'open_not_own', c_open_not_own,
      'wa_open', c_wa_open, 'wa_close', c_wa_close, 'ceiling', c_ceiling, 'trade', c_trade, 'directive', c_dir),
    'brake_floor', jsonb_build_object('from8', cap8, 'from5', cap5, 'from20', cap20),
    'act', v_res, 'cap_after', v_cap_after, 'founder_cap', v_founder, 'ceiling_applied', v_ceiling_applied,
    'applied_rows', v_safe_rows, 'switch_on', v_switch_on, 'run', v_run);
end $p$;
