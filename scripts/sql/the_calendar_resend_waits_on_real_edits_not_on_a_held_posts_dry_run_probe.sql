-- PROBE (no DDL, aborts): the calendar re-send is not held back by a dry-run write, and logs its decisions.
-- ZZ DEMO campaign and post only (month 2099-01); fn_marketing_calendar_resend_decide is the decision
-- fn_marketing_calendar_due takes for each non-demo campaign. Everything is rolled back by the final raise.
-- Result: CHK<<{...}>> in the error text. "bad" must be [].
do $probe$
declare
  v_c bigint; v_p bigint; v_edit0 timestamptz; v_edit1 timestamptz; v_old_rule boolean;
  v_d1 text; v_d2 text; v_d3 text; v_rows1 int; v_rows2 int; v_rows3 int; v_last text; v_in_due int;
  v_real_before text; v_real_after text;
  v_bad text[] := '{}';
begin
  select md5(string_agg(id || ':' || updated_at, ',' order by id)) into v_real_before from public.marketing_post where not is_demo;

  insert into public.marketing_campaign (campaign_key, theme, month, is_demo)
  values ('zz-demo-resend-probe-2099-01', 'ZZ DEMO re-send probe', date '2099-01-01', true) returning id into v_c;
  insert into public.marketing_post (ingest_key, ingested_by, title, text_en, text_ar, channels, scheduled_at, status, is_demo, campaign_id, cta_url)
  values ('zz-demo-resend-probe', 'claude', 'ZZ DEMO probe', 'ZZ DEMO probe', 'مرحبا ZZ DEMO', array['x'],
          timestamptz '2099-01-05 10:00:00+04', 'draft', true, v_c, 'https://quotesdone.ae/?zz=demo') returning id into v_p;
  if (select content_edited_at from public.marketing_post where id = v_p) is distinct from now() then v_bad := v_bad || 'insert_did_not_set_clock'::text; end if;

  -- The last real edit was an hour ago: backdated with triggers off, the only way to move time in one transaction.
  set local session_replication_role = replica;
  update public.marketing_post set content_edited_at = now() - interval '1 hour', updated_at = now() - interval '1 hour' where id = v_p;
  update public.marketing_campaign set updated_at = now() - interval '1 hour' where id = v_c;
  set local session_replication_role = origin;
  select content_edited_at into v_edit0 from public.marketing_post where id = v_p;

  -- The defect: a dry run of the held post, written the way marketing_channels patch() writes it.
  update public.marketing_post set dry_run = jsonb_build_object('at', now(), 'reason', 'approval_void: probe'), updated_at = now() where id = v_p;
  select content_edited_at into v_edit1 from public.marketing_post where id = v_p;
  if v_edit1 is distinct from v_edit0 then v_bad := v_bad || 'dry_run_moved_the_clock'::text; end if;
  -- What the OLD rule would have said: max(updated_at) inside 30 minutes, so not due (the defect reproduced).
  v_old_rule := (select max(updated_at) from public.marketing_post where campaign_id = v_c) < now() - interval '30 minutes';
  if v_old_rule then v_bad := v_bad || 'defect_not_reproduced'::text; end if;

  v_d1 := public.fn_marketing_calendar_resend_decide(v_c);
  select count(*) into v_rows1 from public.marketing_calendar_resend_decision where campaign_id = v_c and decision = 'due';
  if v_d1 is distinct from 'due' then v_bad := v_bad || ('not_due_after_dry_run:' || coalesce(v_d1, 'null')); end if;
  if v_rows1 <> 1 then v_bad := v_bad || 'due_decision_not_logged'::text; end if;

  -- Called again with nothing changed (the next beat): same decision, no second log row.
  v_d2 := public.fn_marketing_calendar_resend_decide(v_c);
  select count(*) into v_rows2 from public.marketing_calendar_resend_decision where campaign_id = v_c;
  if v_d2 is distinct from 'due' or v_rows2 <> 1 then v_bad := v_bad || 'repeat_beat_logged_or_changed'::text; end if;

  -- A demo campaign is never offered for mailing by the loop.
  select count(*) into v_in_due from public.fn_marketing_calendar_due() d where d.campaign_key = 'zz-demo-resend-probe-2099-01';
  if v_in_due <> 0 then v_bad := v_bad || 'demo_campaign_offered'::text; end if;

  -- A real content edit restarts the wait, and that decision is logged.
  update public.marketing_post set cta_url = 'https://quotesdone.ae/?zz=demo2', updated_at = now() where id = v_p;
  if (select content_edited_at from public.marketing_post where id = v_p) is distinct from now() then v_bad := v_bad || 'content_edit_did_not_move_clock'::text; end if;
  v_d3 := public.fn_marketing_calendar_resend_decide(v_c);
  select count(*) into v_rows3 from public.marketing_calendar_resend_decision where campaign_id = v_c;
  select decision into v_last from public.marketing_calendar_resend_decision where campaign_id = v_c order by id desc limit 1;
  if v_d3 is distinct from 'quiet_period' then v_bad := v_bad || 'due_inside_quiet_period'::text; end if;
  if v_rows3 <> 2 or v_last is distinct from 'quiet_period' then v_bad := v_bad || 'quiet_period_not_logged'::text; end if;

  select md5(string_agg(id || ':' || updated_at, ',' order by id)) into v_real_after from public.marketing_post where not is_demo;
  if v_real_after is distinct from v_real_before then v_bad := v_bad || 'real_posts_changed'::text; end if;

  raise exception 'CHK<<%>>', jsonb_build_object('bad', to_jsonb(v_bad), 'old_rule_would_send', v_old_rule,
    'after_dry_run', v_d1, 'next_beat', v_d2, 'after_content_edit', v_d3, 'log_rows', jsonb_build_array(v_rows1, v_rows2, v_rows3),
    'demo_in_due_list', v_in_due);
end $probe$;
