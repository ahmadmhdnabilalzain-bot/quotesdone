-- PROBE (aborted transaction, commits nothing, emails nobody): one_approve_schedules_and_publishes_the_month_on_working_days.sql
-- Every row it writes -- a throwaway campaign, two posts, a holiday, the founder mails in notifications -- is
-- rolled back by the final raise, so no email can leave (send_outbox never sees a rolled-back row). It touches
-- no real campaign: campaign 7 is counted before and after and must be unchanged.
--
--   node scripts/apply_sql.mjs scripts/sql/one_approve_schedules_and_publishes_the_month_on_working_days_probe.sql --apply
do $probe$
declare
  v_cid bigint; v_p1 bigint; v_p2 bigint; v_at timestamptz; v_r jsonb; v_ref text; v_n int; v_bad text := '';
  v_tok text := repeat('ab', 16); v_me text := public.fn_marketing_founder_email(); v_real_before text; v_real_after text;
  v_plan jsonb;
begin
  select string_agg(ingest_key || '@' || scheduled_at || ':' || status, ',' order by id) into v_real_before
    from public.marketing_post where campaign_id is distinct from null;

  -- 1. the emergency stop defaults on
  if not public.fn_marketing_publishing_on() then v_bad := v_bad || ' stop_not_default_on'; end if;
  -- 2. the working-day slot: Saturday -> Monday, National Day (Wed 2 Dec) -> Friday 4 Dec, Friday stays, time kept
  if public.fn_marketing_next_working_slot('2026-10-03 11:30+04') <> '2026-10-05 11:30+04' then v_bad := v_bad || ' sat_not_to_mon'; end if;
  if public.fn_marketing_next_working_slot('2026-12-02 19:30+04') <> '2026-12-04 19:30+04' then v_bad := v_bad || ' holiday_not_skipped'; end if;
  if public.fn_marketing_next_working_slot('2026-09-25 11:30+04') <> '2026-09-25 11:30+04' then v_bad := v_bad || ' friday_moved'; end if;

  -- 3. a post landing on Saturday is moved by the trigger at the same Dubai time
  insert into public.marketing_campaign (campaign_key, theme, month) values ('probe-one-shot', 'probe', '2026-10-01') returning id into v_cid;
  insert into public.marketing_post (ingest_key, ingested_by, text_en, channels, status, scheduled_at, campaign_id)
  values ('probe-one-shot-1', 'marketing', 'probe', array['linkedin'], 'scheduled', '2026-10-03 11:30+04', v_cid) returning id, scheduled_at into v_p1, v_at;
  if v_at <> '2026-10-05 11:30+04' then v_bad := v_bad || ' trigger_did_not_move:' || v_at; end if;
  insert into public.marketing_post (ingest_key, ingested_by, text_en, channels, status, scheduled_at, campaign_id)
  values ('probe-one-shot-2', 'marketing', 'probe', array['linkedin'], 'scheduled', '2026-10-06 19:30+04', v_cid) returning id into v_p2;
  -- 4. a holiday declared later moves the post already on it
  insert into public.public_holidays (holiday_date, name, confirmed) values ('2026-10-06', 'probe holiday', false);
  select scheduled_at into v_at from public.marketing_post where id = v_p2;
  if v_at <> '2026-10-07 19:30+04' then v_bad := v_bad || ' holiday_did_not_move:' || v_at; end if;

  -- 5. the calendar has been "sent"; a reply that is not "approve" becomes the seat's request, with his words
  update public.marketing_campaign set calendar_hash = public.fn_marketing_campaign_hash(v_cid), calendar_token = v_tok where id = v_cid;
  v_r := public.fn_marketing_calendar_reply(jsonb_build_object('token', v_tok, 'from_email', v_me, 'authenticated', true,
           'message_id', 'probe-msg-1', 'intent', 'change', 'text', 'Move video 3 to Monday'));
  if v_r->>'outcome' <> 'change_requested' then v_bad := v_bad || ' change:' || (v_r->>'outcome'); end if;
  select count(*) into v_n from public.marketing_founder_request where campaign_id = v_cid and kind = 'calendar_change' and founder_text = 'Move video 3 to Monday';
  if v_n <> 1 then v_bad := v_bad || ' request_rows:' || v_n; end if;
  -- the same message again is not filed twice
  v_r := public.fn_marketing_calendar_reply(jsonb_build_object('token', v_tok, 'from_email', v_me, 'authenticated', true,
           'message_id', 'probe-msg-1', 'intent', 'change', 'text', 'Move video 3 to Monday'));
  if v_r->>'outcome' <> 'change_already_filed' then v_bad := v_bad || ' refiled:' || (v_r->>'outcome'); end if;
  -- a stranger is never answered, an unauthenticated founder approves nothing
  v_r := public.fn_marketing_calendar_reply(jsonb_build_object('token', v_tok, 'from_email', 'x@example.invalid', 'authenticated', true, 'intent', 'approve'));
  if v_r->>'outcome' <> 'not_the_founder' then v_bad := v_bad || ' stranger:' || (v_r->>'outcome'); end if;
  v_r := public.fn_marketing_calendar_reply(jsonb_build_object('token', v_tok, 'from_email', v_me, 'authenticated', false, 'intent', 'approve'));
  if v_r->>'outcome' <> 'not_authenticated' then v_bad := v_bad || ' unauth:' || (v_r->>'outcome'); end if;

  -- 6. before "approve" the gate says not_approved; after it, NOTHING about approval or a switch refuses
  v_ref := public.fn_marketing_post_refusal(v_p1);
  if v_ref not like 'not_approved%' then v_bad := v_bad || ' pre:' || v_ref; end if;
  v_r := public.fn_marketing_calendar_reply(jsonb_build_object('token', v_tok, 'from_email', v_me, 'authenticated', true,
           'message_id', 'probe-msg-2', 'intent', 'approve', 'text', 'approve'));
  if v_r->>'outcome' <> 'approved' then v_bad := v_bad || ' approve:' || (v_r->>'outcome'); end if;
  v_ref := public.fn_marketing_post_refusal(v_p1);
  if v_ref is distinct from 'no_variants' then v_bad := v_bad || ' post_approve:' || coalesce(v_ref, 'null'); end if;
  -- 7. the emergency stop holds an approved month
  insert into public.app_secrets (key, value) values ('marketing_publishing_enabled', 'false')
    on conflict (key) do update set value = 'false';
  v_ref := public.fn_marketing_post_refusal(v_p1);
  if v_ref not like 'kill_switch%' then v_bad := v_bad || ' stop:' || coalesce(v_ref, 'null'); end if;

  -- 8. the monthly loop: nothing before the November plan; the November plan on 1 Oct, once, 12 working days
  if (public.fn_marketing_month_plan_tick('2026-09-24')->>'sent')::boolean then v_bad := v_bad || ' plan_too_early'; end if;
  -- since 29 Sep 2026 the CEO reviews it first: the first tick files it (no mail), the CEO approves, the next tick mails
  v_plan := public.fn_marketing_month_plan_tick('2026-10-01');
  if coalesce((v_plan->>'sent')::boolean, false) then v_bad := v_bad || ' plan_before_ceo'; end if;
  perform public.fn_reason_apply_ceo__marketing_month_plan((select ceo_held_id from public.marketing_month_plan where month = '2026-11-01'),
    jsonb_build_object('decision', jsonb_build_object('choice', 'approve'), 'answer', 'Approved: the ideas follow what brought registrations and the filing load fits the founder''s month, so it goes to him as drafted.'));
  v_plan := public.fn_marketing_month_plan_tick('2026-10-01');
  if not coalesce((v_plan->>'sent')::boolean, false) or (v_plan->>'ideas')::int <> 12 then v_bad := v_bad || ' plan:' || v_plan; end if;
  select count(*) into v_n from public.marketing_month_plan m, jsonb_array_elements(m.plan->'ideas') e
   where m.month = '2026-11-01' and public.fn_is_working_day((e->>'date')::date) and (e->>'date')::date between '2026-11-01' and '2026-11-30';
  if v_n <> 12 then v_bad := v_bad || ' plan_days:' || v_n; end if;
  if (public.fn_marketing_month_plan_tick('2026-10-02')->>'sent')::boolean then v_bad := v_bad || ' plan_twice'; end if;
  -- 9. his reply with the content is filed for the seat
  v_r := public.fn_marketing_month_plan_reply(jsonb_build_object('token', (select plan_token from public.marketing_month_plan where month = '2026-11-01'),
           'from_email', v_me, 'authenticated', true, 'message_id', 'probe-msg-3', 'text', 'videos attached', 'attachments', jsonb_build_array('a.mp4')));
  if v_r->>'outcome' <> 'content_received' then v_bad := v_bad || ' plan_reply:' || (v_r->>'outcome'); end if;
  -- every founder mail went to his one mailbox, and only there
  select count(*) into v_n from public.notifications where created_at >= now() and kind like 'marketing%' and to_email <> v_me;
  if v_n > 0 then v_bad := v_bad || ' wrong_mailbox:' || v_n; end if;

  select string_agg(ingest_key || '@' || scheduled_at || ':' || status, ',' order by id) into v_real_after
    from public.marketing_post where campaign_id is distinct from null and campaign_id <> v_cid;
  if v_real_after is distinct from v_real_before then v_bad := v_bad || ' real_posts_disturbed'; end if;

  raise exception 'CHK<<%>>', case when v_bad = '' then 'PROBE OK: one approve publishes; weekends and holidays move posts; change requests reach the seat; monthly plan sent once to ' || v_me
                                   else 'PROBE FAILED:' || v_bad end;
end
$probe$;
