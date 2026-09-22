-- PROBE: EVERY SOCIAL MESSAGE IS KEPT ONCE, A PERSON IS ASKED FOR ONCE, AND THE FOUNDER HANDS IT BACK.
--
-- Assigned: marketing. 22 Sep 2026. Pure probe: no DDL, nothing survives it. Run AFTER
-- every_social_message_is_answered.sql, as ONE query through the Management API; it is never applied.
--
-- WHAT IT RUNS, inside a block that always raises so every write is rolled back:
--   a ZZDEMO Instagram conversation (user ZZDEMO_PROBE_1, handle "ZZ DEMO probe") with one inbound
--   message; the same Meta message id inserted a second time; fn_marketing_social_hand_to_human twice;
--   fn_marketing_social_set_status(…, 'auto', 'founder').
-- VERDICT: PROBE OK only if
--   1. the second insert of the same meta_message_id is refused (the webhook's idempotency key);
--   2. the first hand-off marks the conversation handed_to_human, notifies (one founder_alerts row, kind
--      social_human_request — emailed once the kind is registered, routed to an org_task until then) and
--      the notice carries the platform, the handle, the message text and the Meta inbox link;
--   3. the second hand-off does not notify again;
--   4. the founder's word hands it back: status auto, resumed_by founder;
--   5. v_marketing_social_volume does not count the fixture;
--   6. the library holds its nine rows, each with English and Arabic;
--   7. the fixture message appears in v_conversation_message (the sales engineer's record), marked demo.
-- Nothing reaches a person: the conversation is a fixture, and the notice rows it causes roll back with
-- the block before send_outbox could read them.
create temp table zz_probe_verdict (verdict text, detail text) on commit drop;
do $probe$
declare
  v_conv bigint; v_dup boolean := false; r1 jsonb; r2 jsonb; v_status1 text; v_status2 text; v_by text;
  v_alerts_before int; v_alerts_1 int; v_alerts_2 int; v_detail text; v_view0 int; v_view int; v_conv_rows int; v_lib int; v_err text;
begin
  begin
    -- @UNAPPLIED_FILE (a rehearsal before the apply executes the file here; see the report)
    select coalesce(sum(conversations), 0) into v_view0 from public.v_marketing_social_volume;
    select count(*) into v_alerts_before from public.founder_alerts where event ilike 'Someone on % asked to speak with you%';

    insert into public.social_conversation (platform, user_id, handle, last_inbound_at)
    values ('instagram', 'ZZDEMO_PROBE_1', 'ZZ DEMO probe', now()) returning id into v_conv;
    insert into public.social_message (conversation_id, platform, channel, direction, author, meta_message_id, body)
    values (v_conv, 'instagram', 'dm', 'in', 'person', 'ZZDEMO_MID_PROBE_1', 'I want to speak with an agent');
    begin
      insert into public.social_message (conversation_id, platform, channel, direction, author, meta_message_id, body)
      values (v_conv, 'instagram', 'dm', 'in', 'person', 'ZZDEMO_MID_PROBE_1', 'I want to speak with an agent');
    exception when unique_violation then v_dup := true;
    end;

    r1 := public.fn_marketing_social_hand_to_human(v_conv, 'I want to speak with an agent');
    select status into v_status1 from public.social_conversation where id = v_conv;
    select count(*) into v_alerts_1 from public.founder_alerts where event ilike 'Someone on % asked to speak with you%';
    select detail into v_detail from public.founder_alerts where event ilike 'Someone on % asked to speak with you%' order by id desc limit 1;
    r2 := public.fn_marketing_social_hand_to_human(v_conv, 'agent');
    select count(*) into v_alerts_2 from public.founder_alerts where event ilike 'Someone on % asked to speak with you%';

    perform public.fn_marketing_social_set_status(v_conv, 'auto', 'founder');
    select status, resumed_by into v_status2, v_by from public.social_conversation where id = v_conv;

    select coalesce(sum(conversations), 0) into v_view from public.v_marketing_social_volume;
    select count(*) into v_conv_rows from public.v_conversation_message
     where source_table = 'social_message' and is_demo and from_addr = 'ZZ DEMO probe' and channel = 'instagram';
    select count(*) into v_lib from public.social_reply_library where reply_ar ~ '[؀-ۿ]' and length(reply_en) > 20;
    raise exception 'ZZPROBE rollback';
  exception when others then
    v_err := sqlerrm;
  end;
  insert into zz_probe_verdict
  select case when v_err = 'ZZPROBE rollback' and v_dup and (r1->>'notified')::boolean and v_status1 = 'handed_to_human'
                   and v_alerts_1 = v_alerts_before + 1 and v_detail like '%Instagram%' and v_detail like '%ZZ DEMO probe%'
                   and v_detail like '%I want to speak with an agent%' and v_detail like '%business.facebook.com/latest/inbox%'
                   and not (r2->>'notified')::boolean and v_alerts_2 = v_alerts_1
                   and v_status2 = 'auto' and v_by = 'founder' and v_view = v_view0 and v_conv_rows = 1 and v_lib = 9
              then 'PROBE OK' else 'PROBE FAILED' end,
         format('duplicate refused=%s; first handoff notified=%s status=%s alerts %s->%s (notify: %s); second handoff notified=%s alerts=%s; '
                || 'after hand-back status=%s by=%s; CEO view conversations before/after the fixture=%s/%s; sales-engineer view rows for the fixture=%s (want 1); library rows=%s; block ended with: %s',
                v_dup, r1->>'notified', v_status1, v_alerts_before, v_alerts_1, r1->'notify', r2->>'notified', v_alerts_2,
                v_status2, v_by, v_view0, v_view, v_conv_rows, v_lib, v_err);
end $probe$;
select * from zz_probe_verdict;
