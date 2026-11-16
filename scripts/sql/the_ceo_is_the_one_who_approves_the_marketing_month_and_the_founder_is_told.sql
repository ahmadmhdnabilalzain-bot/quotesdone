-- THE CEO IS THE ONE WHO APPROVES THE MARKETING MONTH, AND THE FOUNDER IS TOLD.
--
-- Assigned: marketing (the pipes) + ceo (the decision). Agent: simplify_build_D, 16 Nov 2026. Founder ledgers 1714/1715.
-- Audit: scratchpad audit_simplify/STALE.md S5.
--
-- THE LEDGER BOTH WAYS (public.founder_instruction, read 16 Nov 2026):
--   FOR the founder's approval: 866 (23 Sep) "once I have the plan, it's just one click ... I say, OK, approve"; 973 (24 Sep)
--     "Marketing calendar: one shot. The founder replies approve and it is scheduled"; 1058 (29 Sep) "(5) The one-month
--     social calendar approval stays as is".
--   AGAINST, and newer: 1696 (15 Nov) "CEO is having full authority ... He doesnt rely on me in anything. He is fully
--     responsible about his decisions and their outcomes"; 1710 (15 Nov) "I don't want you to wait on me ... don't rely on
--     me"; 1616 (10 Nov) "The CEO seat approves the January launch plan; the founder is only told the result". No ruling
--     after 1696/1710 gives marketing approval back to the founder (rulings 1694-1715 read in full).
-- WHAT IS LIVE (SELECT 16 Nov 2026): the CEO path of 15 Nov (the_ceo_approves_the_marketing_month_publishes_articles_and_holds_
--   the_marketing_switch.sql): fn_ceo_approves_marketing_calendar, seat duty ceo.marketing_decisions hourly, 2 rows in
--   marketing_ceo_decision. THE SECOND PATH STILL OPEN: fn_marketing_calendar_reply (md5 5b8a6f2f003600cae1a9806617ba30de) sets
--   approved_hash with approved_by 'founder' on his "approve" reply, and asks him to reply "approve" in three messages;
--   fn_marketing_month_plan_to_ceo (md5 9dc85f5de4252abaf6f75df0daabe9b0) tells the CEO "review it before it goes to the
--   founder ... the plan goes to the founder for his one approval of the month"; fn_marketing_post_publish_refusal (md5
--   a1439121200ba193731ddc8c68a606e3) refuses with "the founder has not approved"; fn_marketing_reviews_tick (md5
--   7073a5ebe9fca8eb3789c5f705f5d033) plans "goes to the founder for one-shot approval"; seat_duty marketing.month_plan says
--   "mailed to the founder for his one-shot approval"; founder_mail_policy marketing_calendar says "replying "approve" is his
--   single approval action", marketing_calendar_reply "approved and scheduled", marketing_launch_plan "for his one-shot
--   approval" (contra 1616).
-- THE CHANGE: one approval path, the CEO's. His "approve" reply sets nothing and is answered with what the CEO does; a
-- change he asks for still goes to the marketing seat; his emergency stop (marketing_publishing_enabled) is untouched. The
-- calendar e-mail and PDF (supabase/functions/marketing_channels, _shared/marketing_calendar_doc.ts) say the same.
-- prevented by: the_ceo_is_the_one_who_approves_the_marketing_month_and_the_founder_is_told_probe.sql (LOCAL: an "approve"
-- reply on a ZZ DEMO calendar leaves it unapproved) and the verdict row at the end of this file.
-- LOCKS: four routines replaced in place; one seat_duty row and four founder_mail_policy rows updated.
set local lock_timeout = '3s';

create or replace function public.fn_marketing_month_plan_to_ceo(p_month date, p_resubmitted boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare p public.marketing_month_plan; n jsonb; v_key text := 'marketing_month_plan:' || p_month; v_held bigint;
begin
  select * into p from public.marketing_month_plan where month = p_month;
  if p.month is null or p.status <> 'ceo_reviewing' or p.plan is null then
    return jsonb_build_object('filed', false, 'why', 'the plan is not with the CEO', 'status', p.status);
  end if;
  n := public.fn_ceo_decision_next(v_key);
  if not (n->>'open')::boolean then
    return jsonb_build_object('filed', false, 'why', 'the CEO closed the item: ' || (n->>'last_decision'));
  end if;
  if not p_resubmitted and exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.status = 'pending'
                                     and a.detail->>'type' = 'ceo.revise' and a.detail->>'item_key' = v_key
                                     and not coalesce(a.evidence, '{}'::jsonb) ? 'resubmitted_at') then
    return jsonb_build_object('filed', false, 'why', 'marketing owes the CEO a revision');
  end if;
  v_held := public.fn_seat_duty_reason('ceo', 'ceo.marketing_month_plan',
    'Marketing''s video plan for ' || to_char(p_month, 'FMMonth YYYY') || ': ' || jsonb_array_length(p.plan->'ideas')
      || ' short organic videos on UAE working days, chosen by code from what brought supplier registrations. '
      || 'As the chief executive you decide it (founder ruling 1696): approve it, or reject it and say exactly what '
      || 'marketing must change. Either way give your reasons: they go to marketing, and on approval the founder is told the result.',
    '[{"id":"approve","meaning":"you accept the month: it is the plan, the founder is sent it for information and for the videos only he films"},{"id":"reject","meaning":"the plan goes back to marketing with your reasons, to revise and resubmit"}]'::jsonb,
    jsonb_build_object('month', p_month, 'ideas', p.plan->'ideas', 'shifted_to', p.plan->'shifted_to',
                       'learned', p.plan->'learned', 'revisions', coalesce(p.plan->'revisions', '[]'::jsonb),
                       'round', n->'round', 'generation', n->'generation',
                       'earlier_rounds', (select coalesce(jsonb_agg(jsonb_build_object('round', r.round, 'decision', r.decision,
                                                                                         'reasons', left(r.reasons, 800)) order by r.round), '[]'::jsonb)
                                            from public.ceo_decision_round r where r.item_key = v_key and r.generation = (n->>'generation')::int)),
    jsonb_build_object('month', p_month, 'generation', n->'generation', 'round', n->'round'),
    v_key || ':g' || (n->>'generation') || ':r' || (n->>'round'));
  update public.marketing_month_plan set ceo_held_id = v_held, updated_at = now() where month = p_month;
  return jsonb_build_object('filed', true, 'held_id', v_held, 'generation', n->'generation', 'round', n->'round');
end $function$
;

create or replace function public.fn_marketing_calendar_reply(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c public.marketing_campaign; v_from text := lower(btrim(coalesce(p->>'from_email', '')));
  v_now text; v_out text; v_msg text; v_subj text; v_nid bigint; v_last timestamptz; v_rid bigint;
  v_text text := btrim(coalesce(p->>'text', ''));
begin
  select * into c from public.marketing_campaign where calendar_token = lower(coalesce(p->>'token', '')) for update;
  -- A reply from anyone but him is recorded by the caller and never answered: we do not email strangers.
  if v_from is distinct from public.fn_marketing_founder_email() then
    return jsonb_build_object('outcome', 'not_the_founder', 'approved', false, 'campaign_key', c.campaign_key);
  end if;
  select max(scheduled_at) into v_last from public.marketing_post where campaign_id = c.id and status <> 'cancelled';
  if c.id is null then
    v_out := 'unknown_calendar';
    v_msg := 'Your reply did not match the current social calendar email, so nothing was approved. Please reply to the latest calendar email you received from us (a newer one replaces any earlier one).';
  elsif not coalesce((p->>'authenticated')::boolean, false) then
    v_out := 'not_authenticated';
    v_msg := 'A reply to the social calendar arrived with your address but our mail server could not verify it came from your mailbox (no SPF/DKIM/DMARC pass), so nothing was approved or changed. If it was you, reply again from your usual mail app.';
  else
    v_now := public.fn_marketing_campaign_hash(c.id);
    if coalesce(p->>'intent', '') = 'approve' and c.approved_hash is not null and c.approved_hash = v_now then
      return jsonb_build_object('outcome', 'already_approved', 'approved', true, 'campaign_key', c.campaign_key);  -- idempotent: nothing sent
    elsif v_last is null or now() >= v_last then
      v_out := 'expired';
      v_msg := 'This social calendar has no posts left to go out, so nothing was approved or changed.';
    elsif coalesce(p->>'intent', '') = 'change' and v_text <> '' then
      -- HIS WORDS GO TO THE SEAT. Filed once per message; the corrected calendar is re-sent by code when it changes.
      insert into public.marketing_founder_request (kind, campaign_id, month, founder_text, message_id)
      values ('calendar_change', c.id, c.month, left(v_text, 4000), nullif(p->>'message_id', ''))
      on conflict (message_id) where message_id is not null and message_id <> '' do nothing
      returning id into v_rid;
      if v_rid is null then
        return jsonb_build_object('outcome', 'change_already_filed', 'approved', false, 'campaign_key', c.campaign_key);
      end if;
      v_out := 'change_requested';
      v_msg := 'Your change request was passed to the marketing seat (request ' || v_rid || '):' || E'\n\n'
               || left(v_text, 1500) || E'\n\n'
               || 'The corrected calendar goes to the CEO seat, which approves it (founder ruling 1696); it is emailed to you for information.';
    elsif c.calendar_hash is distinct from v_now then
      v_out := 'edited_after_sending';
      v_msg := 'The social calendar was changed after we emailed it to you; the updated calendar is being emailed to you now. The CEO seat approves it (founder ruling 1696), so nothing waits on you.';
    elsif coalesce(p->>'intent', '') <> 'approve' then
      v_out := 'unclear';
      v_msg := 'Your reply had no text of its own, so nothing changed. The CEO seat approves the calendar (founder ruling 1696); to change something, reply saying what.';
    else
      -- 16 NOV 2026 (ceo, wave D): THE CEO APPROVES THE CALENDAR (founder ruling 1696, 15 Nov 2026: "He doesnt rely on me
      -- in anything"; fn_ceo_approves_marketing_calendar, seat duty ceo.marketing_decisions). His "approve" reply is a second
      -- approval path and no longer sets approved_hash; it is answered with what the CEO does. His emergency stop is unchanged.
      v_out := 'ceo_approves';
      v_msg := 'Thank you. The CEO seat approves the social calendar (founder ruling 1696), so your reply changed nothing'
               || case when c.approved_hash = v_now then ': this calendar is already approved.'
                       else ': it approves this calendar on its next hourly round when it meets its boundaries (organic only, not edited after it was built).' end
               || ' To change anything, reply saying what. Your emergency stop (marketing_publishing_enabled) is unchanged.';
    end if;
  end if;
  v_subj := case v_out when 'ceo_approves' then 'For your information: ' when 'change_requested' then 'Change request received: ' else 'Not changed: ' end
            || 'social calendar' || coalesce(' — ' || c.title, '');
  v_nid := public.fn_marketing_mail_founder('marketing_calendar_reply', left(v_subj, 200), v_msg);
  return jsonb_build_object('outcome', v_out, 'approved', false, 'campaign_key', c.campaign_key,
                            'request_id', v_rid, 'reply_notification_id', v_nid);
end $function$
;

create or replace function public.fn_marketing_post_publish_refusal(p marketing_post)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c public.marketing_campaign; v record; v_probs text[];
begin
  -- ZZ DEMO both ways: the flag OR the words anywhere that is published
  if p.is_demo or (p.text_en || ' ' || coalesce(p.text_ar, '') || ' ' || coalesce(p.title, '') || ' ' || coalesce(p.cta_url, '')) ~* 'zz[ _-]?demo'
     or exists (select 1 from public.marketing_post_variant x where x.post_id = p.id
                 and (x.body || ' ' || coalesce(x.title, '') || ' ' || coalesce(x.alt_text, '') || ' ' || coalesce(x.first_comment, '')) ~* 'zz[ _-]?demo') then
    return 'demo: a ZZ DEMO post is never published';
  end if;
  if p.campaign_id is null then return 'no_campaign: only a post of an approved campaign is published'; end if;
  select * into c from public.marketing_campaign where id = p.campaign_id;
  if c.is_demo then return 'demo: a ZZ DEMO campaign is never published'; end if;
  if c.spend_policy <> 'organic_only' then return 'spend: only organic campaigns are published'; end if;
  if c.approved_hash is null then return 'not_approved: the CEO has not approved campaign ' || c.campaign_key; end if;
  if c.approved_hash <> public.fn_marketing_campaign_hash(c.id) then
    return 'approval_void: campaign ' || c.campaign_key || ' was edited after it was approved';
  end if;
  -- A CAMPAIGN LAUNCH IS HIGH STAKES (29 Sep 2026, instruction 1009): the CEO agreed on another family, or the review is owed.
  if not public.fn_high_stakes_may_proceed('campaign_launch', 'marketing_campaign', c.id::text) then
    return 'awaiting_second_seat: the CEO has not agreed to launch campaign ' || c.campaign_key || ' (fn_high_stakes_clearance)';
  end if;
  -- A slot missed by more than 30 minutes is not posted late (review of #874).
  if p.scheduled_at < now() - interval '30 minutes' then
    return 'missed_slot: due ' || to_char(p.scheduled_at at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI') || ' Dubai; reschedule and re-approve';
  end if;
  -- Founder, 24 Sep 2026: never on the UAE weekend or a UAE public holiday (the trigger moves such posts; this
  -- is the backstop for a row that reached the day some other way).
  if not public.fn_is_working_day((p.scheduled_at at time zone 'Asia/Dubai')::date) then
    return 'blocked_day: ' || to_char(p.scheduled_at at time zone 'Asia/Dubai', 'YYYY-MM-DD') || ' is a UAE weekend day or public holiday';
  end if;
  if not public.fn_marketing_publishing_on() then
    return 'kill_switch: app_secrets.marketing_publishing_enabled is false (emergency stop)';
  end if;
  if not exists (select 1 from public.marketing_post_variant x where x.post_id = p.id) then return 'no_variants'; end if;
  for v in select x from public.marketing_post_variant x where x.post_id = p.id loop
    v_probs := public.fn_marketing_variant_problems(v.x);
    if v_probs is null then return 'platform_specs_not_loaded: fn_marketing_platform_spec_problems does not exist'; end if;
    if cardinality(v_probs) > 0 then return 'platform_spec: ' || (v.x).platform || ' ' || array_to_string(v_probs, '; '); end if;
  end loop;
  return null;
end $function$
;

create or replace function public.fn_marketing_reviews_tick(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_local date := (p_at at time zone 'Asia/Dubai')::date;
  v_last_month date := (date_trunc('month', v_local) - interval '1 month')::date;
  v_quarter date := date_trunc('quarter', v_local)::date;
  v_body jsonb; v_id bigint; v_handoff bigint; v_out jsonb := '{}'::jsonb;
begin
  if extract(day from v_local) >= 2 and not exists (select 1 from public.marketing_review where kind = 'geo_monthly' and period = v_last_month)
     and exists (select 1 from public.marketing_geo_check where month = v_last_month) then
    v_body := public.fn_marketing_geo_summary(v_last_month);
    insert into public.marketing_review (kind, period, body) values ('geo_monthly', v_last_month, v_body)
      on conflict (kind, period) do nothing returning id into v_id;
    if v_id is not null then
      v_handoff := public.fn_seat_handoff('marketing', 'ceo', 'marketing.review', 'marketing_review', v_id::text,
        jsonb_build_object('kind', 'geo_monthly', 'period', v_last_month));
      update public.marketing_review set handoff_id = v_handoff where id = v_id;
      v_out := v_out || jsonb_build_object('geo_monthly', v_id);
    end if;
  end if;

  -- Only in the first 14 days of a quarter, so the file applied mid-quarter does not compose a review of an empty one.
  if v_local < v_quarter + 14 and not exists (select 1 from public.marketing_review where kind = 'brand_quarterly' and period = v_quarter) then
    v_body := jsonb_build_object(
      'quarter', v_quarter,
      'positioning', jsonb_build_object(
        'rule_source', 'profile_text.json (one description everywhere; "smart", never "AI"; no licence number)',
        'social_profiles_checked', (select count(*) from public.marketing_connection_check),
        'social_profiles_failing', (select count(*) from public.marketing_connection_check where not ok)),
      'reach_last_quarter', (select coalesce(jsonb_object_agg(platform, total), '{}'::jsonb) from (
          select platform, sum(value) total from public.marketing_insight_day
           where day >= (v_quarter - interval '3 months') and day < v_quarter group by platform) r),
      'posts_published_last_quarter', (select count(*) from public.marketing_post where status = 'published'
           and published_at >= (v_quarter - interval '3 months') and published_at < v_quarter),
      'geo_last_three_months', (select coalesce(jsonb_agg(public.fn_marketing_geo_summary(m::date) - 'rows' order by m), '[]'::jsonb)
           from generate_series((v_quarter - interval '3 months')::date, (v_quarter - interval '1 month')::date, interval '1 month') g(m)),
      'competitor_posts_seen', (select count(*) from public.market_intel where platform is not null and created_at >= v_quarter - interval '3 months'),
      'relevant_trends', (select count(*) from public.marketing_trend where relevant and seen_at >= v_quarter - interval '3 months'),
      'reputation', (select to_jsonb(s) from public.company_reputation_snapshot s order by day desc limit 1),
      -- THE JANUARY 2027 CUSTOMER LAUNCH (seat map, 24 Sep 2026): no customer campaign before January 2027, and
      -- customers launch only once suppliers can quote every inquiry. This is the proposal the CEO decides on.
      'customer_launch_2027', jsonb_build_object(
        'decision_owner', 'ceo',
        'rule', 'Oct-Dec 2026 supplier registration only; customers from January 2027 once the supplier base can quote every inquiry',
        'supply_gaps_open', (select count(*) from public.supply_gap where status in ('open', 'recruit')),
        'supply_gaps_recruiting', (select count(*) from public.supply_gap where status = 'recruit'),
        'suppliers_registered', (select coalesce(sum(registered), 0) from public.supplier_recruitment_funnel
                                  where day = (select max(day) from public.supplier_recruitment_funnel)),
        'suppliers_approved', (select coalesce(sum(approved), 0) from public.supplier_recruitment_funnel
                                  where day = (select max(day) from public.supplier_recruitment_funnel)),
        'plan', jsonb_build_array(
          'December 2026: the CEO decides the launch against supply_gaps_open = 0 for the launch trades',
          'December 2026: customer landing pages and the blog answer the buyer questions in marketing_geo_question',
          'January 2027: the first customer calendar (organic only) is approved by the CEO (ruling 1696); the founder is told',
          'January 2027 onward: the monthly GEO audit tracks whether answer engines name QuotesDone to buyers')));
    insert into public.marketing_review (kind, period, body) values ('brand_quarterly', v_quarter, v_body)
      on conflict (kind, period) do nothing returning id into v_id;
    if v_id is not null then
      v_handoff := public.fn_seat_handoff('marketing', 'ceo', 'marketing.review', 'marketing_review', v_id::text,
        jsonb_build_object('kind', 'brand_quarterly', 'period', v_quarter));
      update public.marketing_review set handoff_id = v_handoff where id = v_id;
      v_out := v_out || jsonb_build_object('brand_quarterly', v_id);
    end if;
  end if;
  return v_out;
end $function$
;

update public.seat_duty set what =
  'Next month''s plan drafted on the first day of the month and filed with the CEO, who accepts it (ruling 1696); the founder is '
  || 'sent the accepted plan for information and for the videos only he films. From the 20th a missing plan is a failure.'
 where duty = 'marketing.month_plan' and what like '%for his one-shot approval%';

update public.founder_mail_policy set updated_at = now(), reason =
  'Founder instructions 866, 871, 872 (23 Sep 2026): the month''s social calendar (PDF + spreadsheet, clickable video links) is '
  || 'emailed to him once per month and whenever it changes, for information: the CEO seat approves it (ruling 1696, 15 Nov 2026). '
  || 'His reply can ask for a change; his emergency stop (marketing_publishing_enabled) stays his.'
 where kind = 'marketing_calendar';
update public.founder_mail_policy set updated_at = now(), reason =
  'The answer to his reply to the calendar: his change request passed to the marketing seat. An "approve" reply changes nothing: '
  || 'the CEO seat approves the calendar (ruling 1696, 15 Nov 2026).'
 where kind = 'marketing_calendar_reply';
update public.founder_mail_policy set updated_at = now(), reason =
  'The January 2027 launch plan, for information: the CEO seat decides it from 1 December 2026 and he is told the result (ruling 1616).'
 where kind = 'marketing_launch_plan';
update public.founder_mail_policy set updated_at = now(), reason =
  'The answer to his reply to a launch-plan or an old article approval email: both are the CEO seat''s decisions (rulings 1058, 1616, 1696).'
 where kind = 'marketing_approval_reply';

select case
  when exists (select 1 from pg_proc where proname = 'fn_marketing_calendar_reply' and prosrc like '%approved_by = ''founder''%')
    then 'PROBE FAILED: the founder''s reply still approves a calendar'
  when exists (select 1 from pg_proc where proname in ('fn_marketing_month_plan_to_ceo', 'fn_marketing_reviews_tick', 'fn_marketing_post_publish_refusal', 'fn_marketing_calendar_reply')
                and prosrc ~ '(one approval of the month|one-shot approval|the founder has not approved|reply with the single word)')
    then 'PROBE FAILED: a routine still frames marketing approval as the founder''s'
  when exists (select 1 from public.seat_duty where duty like 'marketing.%' and what ~ 'one-shot approval')
    or exists (select 1 from public.founder_mail_policy where kind like 'marketing%' and allowed_to_email and reason ~ '(single approval action|one-shot approval|approved and scheduled)')
    then 'PROBE FAILED: a duty or a mail policy still says the founder approves marketing'
  else 'PROBE OK: one approval path for marketing, the CEO''s; the founder is told' end as verdict;
