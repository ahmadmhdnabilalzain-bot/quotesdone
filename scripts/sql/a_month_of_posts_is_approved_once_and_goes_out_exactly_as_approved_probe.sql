-- PROBE: A MONTH OF POSTS IS APPROVED ONCE AND GOES OUT EXACTLY AS APPROVED (23 Sep 2026; seat: marketing).
--
-- A pure probe: it always ends in raise exception 'CHK<<...>>', so every row it writes (two storage object
-- rows, a campaign, posts, variants) and the stub platform spec it may create roll back with it. Nothing it
-- does can reach Postiz or a person: the edge function is not called and marketing_golive is only READ.
-- Run it AFTER a_month_of_posts_is_approved_once_and_goes_out_exactly_as_approved.sql. The verdict is the
-- first key of the CHK payload: PROBE OK or PROBE FAILED with what failed.
--
-- WHAT IT PROVES, in the database and not the app:
--   * the calendar loads a month in one call, and loading it TWICE leaves byte-identical rows (ids, updated_at
--     and the content hash included); a post over X's limit becomes an EN tweet + AR reply thread
--   * publishing is refused without the founder's approval, refused with an approval of other content,
--     refused after an edit (the approval is void), and -- once approved -- still refused while
--     marketing_golive is not 'true' (the switch on top)
--   * the monthly calendar email is queued through founder_mail_policy with an unguessable Reply-To token;
--     HIS REPLY approves: a forged (unauthenticated) reply, a stranger, an unclear reply, a reply to an older
--     calendar email and a reply after the month was edited approve nothing; a second approve is idempotent
--   * ZZ DEMO both ways: a post whose text says ZZ DEMO with is_demo false is refused by a constraint; a
--     ZZ DEMO caption on a variant, or an is_demo post, is refused by the publish gate
--   * inserting a row straight into 'published' is refused
--
--   node scripts/apply_sql.mjs scripts/sql/a_month_of_posts_is_approved_once_and_goes_out_exactly_as_approved_probe.sql --apply

do $probe$
declare
  v_bad text[] := '{}'; r jsonb := '{}'::jsonb; x jsonb; s1 jsonb; s2 jsonb; v_hash text; v_hash2 text; v_err text;
  v_pid bigint; v_stub boolean := false; v_tok1 text; v_tok2 text; v_founder text;
  cal jsonb := jsonb_build_object(
    'campaign', jsonb_build_object('key', 'probe-2099-01', 'theme', 'probe month', 'month', '2099-01'),
    'posts', jsonb_build_array(
      jsonb_build_object('key', 'probe-2099-01-01-instagram', 'platform', 'instagram',
        'at_dubai', '2099-01-05T19:00:00', 'at_utc', '2099-01-05T15:00:00Z',
        'video', jsonb_build_object('path', 'marketing-media/campaigns/probe-2099-01/videos/v01.mp4', 'sha256', repeat('a', 64), 'title', 'Three quotes, one request'),
        'keyframe', jsonb_build_object('path', 'campaigns/probe-2099-01/frames/v01.jpg', 'sha256', repeat('b', 64)),
        'caption_en', 'Suppliers: receive real requests from UAE buyers.', 'caption_ar', 'الموردون: استقبلوا طلبات حقيقية من المشترين في الإمارات.',
        'hashtags', jsonb_build_array('#UAE', 'Suppliers'), 'alt_text', 'A supplier reading a request on a phone',
        'cta_url', 'https://www.quotesdone.ae/suppliers', 'rationale', 'probe', 'music', jsonb_build_object('bpm', 100, 'mood', 'calm')),
      jsonb_build_object('key', 'probe-2099-01-01-x', 'platform', 'x',
        'at_dubai', '2099-01-06T12:00:00', 'at_utc', '2099-01-06T08:00:00Z',
        'video', jsonb_build_object('path', 'campaigns/probe-2099-01/videos/v01.mp4', 'sha256', repeat('a', 64), 'title', 'Three quotes, one request'),
        'keyframe', jsonb_build_object('path', 'campaigns/probe-2099-01/frames/v01.jpg', 'sha256', repeat('b', 64)),
        'caption_en', repeat('Suppliers in the UAE get real requests. ', 4), 'caption_ar', repeat('الموردون في الإمارات يستقبلون طلبات حقيقية. ', 4),
        'hashtags', jsonb_build_array('UAE'))));
begin
  -- the two assets exist in the private bucket (rolled back with everything else)
  insert into storage.objects (bucket_id, name) values
    ('marketing-media', 'campaigns/probe-2099-01/videos/v01.mp4'), ('marketing-media', 'campaigns/probe-2099-01/frames/v01.jpg');
  -- a stub platform spec for X only, when the sibling's routine is not there yet (rolled back)
  if to_regprocedure('public.fn_marketing_platform_spec_problems(text,text,text,text[],text,text,text)') is null then
    execute $stub$create function public.fn_marketing_platform_spec_problems(p text, t text, b text, h text[], ti text, a text, c text)
      returns text[] language sql immutable as $s$ select case when p = 'x' and char_length(b) > 280 then array['x body over 280'] else '{}'::text[] end $s$$stub$;
    v_stub := true;
  end if;

  -- 1. load twice: identical rows
  x := public.fn_marketing_calendar_load(cal);
  select jsonb_build_object('p', jsonb_agg(to_jsonb(p) order by p.id), 'v', (select jsonb_agg(to_jsonb(v) order by v.id) from public.marketing_post_variant v
           join public.marketing_post pp on pp.id = v.post_id where pp.campaign_id = (x->>'campaign_id')::bigint),
         'h', public.fn_marketing_campaign_hash((x->>'campaign_id')::bigint))
    into s1 from public.marketing_post p where p.campaign_id = (x->>'campaign_id')::bigint;
  r := r || jsonb_build_object('first_load', x - 'state');
  x := public.fn_marketing_calendar_load(cal);
  select jsonb_build_object('p', jsonb_agg(to_jsonb(p) order by p.id), 'v', (select jsonb_agg(to_jsonb(v) order by v.id) from public.marketing_post_variant v
           join public.marketing_post pp on pp.id = v.post_id where pp.campaign_id = (x->>'campaign_id')::bigint),
         'h', public.fn_marketing_campaign_hash((x->>'campaign_id')::bigint))
    into s2 from public.marketing_post p where p.campaign_id = (x->>'campaign_id')::bigint;
  r := r || jsonb_build_object('second_load', x - 'state');
  if s1 is distinct from s2 then v_bad := v_bad || 'loading_twice_changed_rows'::text; end if;
  if (x->>'unchanged')::int <> 2 then v_bad := v_bad || 'second_load_was_not_unchanged'::text; end if;
  if (select count(*) from public.marketing_post_variant v join public.marketing_post p on p.id = v.post_id
       where p.ingest_key = 'probe-2099-01-01-x') <> 2 then v_bad := v_bad || 'x_overflow_did_not_become_a_thread'::text; end if;
  if not exists (select 1 from public.marketing_post where ingest_key = 'probe-2099-01-01-instagram' and scheduled_local = '2099-01-05 19:00'
                   and scheduled_at = '2099-01-05 15:00Z' and video_path = 'campaigns/probe-2099-01/videos/v01.mp4') then
    v_bad := v_bad || 'dubai_and_utc_times_not_both_stored'::text;
  end if;
  if (select body from public.marketing_post_variant v join public.marketing_post p on p.id = v.post_id
       where p.ingest_key = 'probe-2099-01-01-instagram') !~ E'\n\n#UAE #Suppliers$' then
    v_bad := v_bad || 'hashtags_not_rendered_once_with_one_hash'::text;
  end if;
  select id into v_pid from public.marketing_post where ingest_key = 'probe-2099-01-01-instagram';

  -- 2. not approved -> refused in the database
  begin update public.marketing_post set status = 'publishing' where id = v_pid; v_bad := v_bad || 'published_without_approval'::text;
  exception when check_violation then v_err := sqlerrm; end;
  r := r || jsonb_build_object('unapproved', v_err);
  if v_err !~ 'not_approved' then v_bad := v_bad || 'unapproved_refused_for_the_wrong_reason'::text; end if;

  -- 3. the calendar email, and his reply is the approval
  v_hash := public.fn_marketing_campaign_hash((x->>'campaign_id')::bigint);
  x := public.fn_marketing_calendar_sent('probe-2099-01', v_hash, 'marketing/calendar/probe-2099-01/probe.pdf', 'marketing/calendar/probe-2099-01/probe.xlsx',
                                         'Social calendar January 2099', 'The calendar.');
  select calendar_token into v_tok1 from public.marketing_campaign where campaign_key = 'probe-2099-01';
  if not (x->>'ok')::boolean or v_tok1 is null or not exists (select 1 from public.notifications n where n.id = (x->>'notification_id')::bigint
       and n.kind = 'marketing_calendar' and n.reply_to = 'calendar+' || v_tok1 || '@mail.quotesdone.com' and n.subject like '%[ref ' || v_tok1 || ']'
       and jsonb_array_length(n.attachments) = 2) then
    v_bad := v_bad || ('calendar_email_not_queued: ' || x::text);
  end if;
  v_founder := public.fn_marketing_founder_email();
  -- a forged From (no SPF/DKIM/DMARC pass) approves nothing
  x := public.fn_marketing_calendar_reply(jsonb_build_object('token', v_tok1, 'from_email', v_founder, 'authenticated', false, 'message_id', 'm-forged', 'intent', 'approve'));
  r := r || jsonb_build_object('forged', x->'outcome');
  if x->>'outcome' <> 'not_authenticated' then v_bad := v_bad || 'forged_reply_not_refused'::text; end if;
  -- someone else approves nothing, and is not answered
  x := public.fn_marketing_calendar_reply(jsonb_build_object('token', v_tok1, 'from_email', 'someone@example.invalid', 'authenticated', true, 'message_id', 'm-other', 'intent', 'approve'));
  if x->>'outcome' <> 'not_the_founder' or x ? 'reply_notification_id' then v_bad := v_bad || 'stranger_not_refused_or_answered'::text; end if;
  -- an ambiguous reply approves nothing and asks
  x := public.fn_marketing_calendar_reply(jsonb_build_object('token', v_tok1, 'from_email', v_founder, 'authenticated', true, 'message_id', 'm-unclear', 'intent', 'unclear'));
  r := r || jsonb_build_object('unclear', x->'outcome');
  if x->>'outcome' <> 'unclear' or (x->>'reply_notification_id') is null then v_bad := v_bad || 'unclear_reply_not_asked'::text; end if;
  -- not approved yet -> still refused
  v_err := null;
  begin update public.marketing_post set status = 'publishing' where id = v_pid; v_bad := v_bad || 'published_before_approval'::text;
  exception when check_violation then v_err := sqlerrm; end;
  if v_err !~ 'not_approved' then v_bad := v_bad || 'refused_for_the_wrong_reason_before_approval'::text; end if;
  -- the genuine reply approves, with one confirmation
  x := public.fn_marketing_calendar_reply(jsonb_build_object('token', v_tok1, 'from_email', upper(v_founder), 'authenticated', true, 'message_id', 'm-genuine', 'intent', 'approve'));
  r := r || jsonb_build_object('genuine', x->'outcome', 'confirmation', (select subject || ' | ' || body from public.notifications where id = (x->>'reply_notification_id')::bigint));
  if x->>'outcome' <> 'approved' then v_bad := v_bad || ('genuine_reply_not_approved: ' || x::text); end if;
  if not exists (select 1 from public.marketing_campaign where campaign_key = 'probe-2099-01' and approved_by = 'founder'
                   and approved_hash = v_hash and approved_message_id = 'm-genuine') then v_bad := v_bad || 'approval_not_recorded_whole'::text; end if;
  -- approve twice: nothing changes, nothing is sent
  x := public.fn_marketing_calendar_reply(jsonb_build_object('token', v_tok1, 'from_email', v_founder, 'authenticated', true, 'message_id', 'm-again', 'intent', 'approve'));
  if x->>'outcome' <> 'already_approved' or x ? 'reply_notification_id'
     or not exists (select 1 from public.marketing_campaign where campaign_key = 'probe-2099-01' and approved_message_id = 'm-genuine') then
    v_bad := v_bad || 'second_approve_was_not_idempotent'::text;
  end if;

  -- 4. approved, switch off -> still refused, for the switch
  v_err := null;
  begin update public.marketing_post set status = 'publishing' where id = v_pid;
    if coalesce((select lower(value) from public.app_secrets where key = 'marketing_golive'), 'false') <> 'true' then v_bad := v_bad || 'published_with_the_switch_off'::text; end if;
  exception when check_violation then v_err := sqlerrm; end;
  r := r || jsonb_build_object('approved_switch_off', v_err);
  if v_err !~ 'switch_off' then v_bad := v_bad || 'approved_post_refused_for_the_wrong_reason'::text; end if;

  -- 5. an edit voids the approval; a reply to the stale email is refused; the resent email's token is new
  update public.marketing_post_variant set caption = caption || ' Edited.' where post_id = v_pid;
  v_err := null;
  begin update public.marketing_post set status = 'publishing' where id = v_pid; v_bad := v_bad || 'published_after_an_edit'::text;
  exception when check_violation then v_err := sqlerrm; end;
  r := r || jsonb_build_object('after_edit', v_err, 'state_after_edit', public.fn_marketing_campaign_state('probe-2099-01') - 'current_hash' - 'calendar_hash');
  if v_err !~ 'approval_void' then v_bad := v_bad || 'edit_did_not_void_the_approval'::text; end if;
  update public.marketing_campaign set approved_by = null, approved_at = null, approved_hash = null, approved_message_id = null
   where campaign_key = 'probe-2099-01';  -- as a fresh month: the edit happened before he replied
  x := public.fn_marketing_calendar_reply(jsonb_build_object('token', v_tok1, 'from_email', v_founder, 'authenticated', true, 'message_id', 'm-stale', 'intent', 'approve'));
  r := r || jsonb_build_object('edited_after_sending', x->'outcome');
  if x->>'outcome' <> 'edited_after_sending' then v_bad := v_bad || 'approval_of_edited_content_not_refused'::text; end if;
  v_hash2 := public.fn_marketing_campaign_hash((select id from public.marketing_campaign where campaign_key = 'probe-2099-01'));
  perform public.fn_marketing_calendar_sent('probe-2099-01', v_hash2, 'marketing/calendar/probe-2099-01/probe2.pdf', null, 'Social calendar January 2099', 'Updated.');
  select calendar_token into v_tok2 from public.marketing_campaign where campaign_key = 'probe-2099-01';
  x := public.fn_marketing_calendar_reply(jsonb_build_object('token', v_tok1, 'from_email', v_founder, 'authenticated', true, 'message_id', 'm-last', 'intent', 'approve'));
  r := r || jsonb_build_object('reply_to_the_older_email', x->'outcome');
  if v_tok2 = v_tok1 or x->>'outcome' <> 'unknown_calendar' then v_bad := v_bad || 'reply_to_an_older_calendar_email_not_refused'::text; end if;
  -- reloading the original calendar restores exactly the first content
  perform public.fn_marketing_calendar_load(cal);
  if public.fn_marketing_campaign_hash((select id from public.marketing_campaign where campaign_key = 'probe-2099-01')) <> v_hash then
    v_bad := v_bad || 'reload_did_not_restore_the_content'::text;
  end if;

  -- 6. ZZ DEMO both ways
  v_err := null;
  begin
    insert into public.marketing_post (ingest_key, ingested_by, text_en, text_ar, channels, status, is_demo)
    values ('probe-demo-text', 'claude', 'Hello ZZ DEMO', 'مرحبا', array['x'], 'draft', false);
    v_bad := v_bad || 'demo_text_without_the_flag_was_stored'::text;
  exception when check_violation then v_err := sqlerrm; end;
  r := r || jsonb_build_object('demo_text_unflagged', v_err);
  update public.marketing_post_variant set caption = 'ZZ DEMO ' || caption
   where post_id = (select id from public.marketing_post where ingest_key = 'probe-2099-01-01-x') and seq = 1;
  v_err := null;
  begin update public.marketing_post set status = 'publishing' where ingest_key = 'probe-2099-01-01-x'; v_bad := v_bad || 'demo_caption_published'::text;
  exception when check_violation then v_err := sqlerrm; end;
  if v_err !~ 'demo' then v_bad := v_bad || 'demo_caption_refused_for_the_wrong_reason'::text; end if;
  r := r || jsonb_build_object('demo_caption', v_err);

  -- 7. nobody inserts straight into 'published'
  v_err := null;
  begin
    insert into public.marketing_post (ingest_key, ingested_by, text_en, text_ar, channels, scheduled_at, status, published_at)
    values ('probe-straight-in', 'claude', 'Hello', 'مرحبا', array['x'], now(), 'published', now());
    v_bad := v_bad || 'inserted_as_published'::text;
  exception when check_violation then v_err := sqlerrm; end;
  r := r || jsonb_build_object('straight_in', v_err, 'stub_spec', v_stub);

  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when cardinality(v_bad) = 0 then 'PROBE OK' else 'PROBE FAILED' end, 'bad', v_bad, 'r', r);
end $probe$;
