-- EACH CHANNEL OF A POST SAYS WHAT THE PLATFORM ACTUALLY DID (24 Sep 2026).
-- Assigned: marketing (the post's state) + it_engineer (the finding).
--
-- MEASURED: marketing_channels/index.ts marks marketing_post.status = 'published' when Postiz answers 2xx to
-- POST /public/v1/posts. That is Postiz accepting the job; it publishes to each platform afterwards, and a
-- channel can fail or half-succeed (the founder's example: YouTube reported the thumbnail was not set). In
-- production on 24 Sep 2026 posts 84-87 (linkedin, facebook, youtube, instagram) were 'published' with only the
-- ids Postiz returned on the POST: no per-channel result was stored anywhere and nothing read one back.
--
-- WHAT THIS CHANGES
--   marketing_post_channel_result  one row per post x channel: pending | published | partial | failed, what
--                         Postiz said (its state and the platform's message) and the release URL if any.
--   marketing_post.channel_outcome  the post from its channels: published only if EVERY channel published;
--                         failed if none published or partly published; partial otherwise; pending while any
--                         channel is still pending (at most 48 hours: after that the classifier fails it).
--                         channel_checked_at is when that was last read back.
--   fn_marketing_post_channel_record(post, channels[])  stores one read-back and derives channel_outcome with
--                         the same rule as overallOutcome in supabase/functions/_shared/marketing_channel_results.ts.
--   fn_marketing_channel_results_due(limit)  THE SCHEDULE of the re-check: posts sent in the last 48 hours,
--                         every 30 minutes (decision_policy 'marketing_channel_recheck_minutes' overrides), because
--                         Postiz reports some platform results asynchronously; a post still partial/failed within
--                         30 days every 6 hours, so a channel fixed in Postiz closes its finding. It runs on the
--                         marketing_channels beat that resilience_ping already calls every 15 minutes: no new cron
--                         job (founder, 7 Sep 2026: no job the founder did not ask for).
--   fn_table_export_list  redefined with the new table (every_marketing_table_is_in_the_daily_export.test.mjs);
--                         every other row unchanged from marketing_trend_geo_and_review_tables_are_in_the_daily_export.sql.
--   it_playbook 'postiz_channel_result'  covers duty:postiz_channel_result:, so a cleared finding's handoff closes
--                         instead of parking at awaiting_learning (review of #965).
--   fn_marketing_report_figures  the CEO report counts a post as published only when its channels say so
--                         (channel_outcome), with the old status reading while channel_outcome is NULL.
-- The it_engineer finding: the edge function settles every partial/failed channel of the last 30 days through the
-- existing fn_it_duty_settle('postiz_channel_result', ...) path, ONE finding per CHANNEL + CAUSE
-- (duty:postiz_channel_result:<channel>:<cause>, e.g. youtube:thumbnail_not_set) listing the posts it hit, refiled
-- under that key and closed when no post in the window has that cause any more. owner_seat marketing (it owns
-- the posts and has the handoff kind); the finding is the it_engineer's. Per-post state stays in the table.
--
-- WHAT THIS DELIBERATELY DOES NOT CHANGE
--   * marketing_post.status keeps its meaning (the send lifecycle). A partly failed post is NOT turned back to
--     'failed': 'failed' means "safe to requeue", and requeueing a post that reached some platforms would publish
--     it twice there. The channel outcome is its own column.
--   * marketing_post_platform (the tie that drives metric checkpoints) is not reused: a channel that never
--     published has no id to tie and must not get metric checkpoints.
--   * No write to Postiz, no model, no notification from this file.
--   * fn_marketing_reviews_tick's quarterly published count: it has its own owning file.
-- Prevented by: supabase/functions/_shared/marketing_channel_results.test.ts and
--   scripts/checks/each_channel_of_a_post_says_what_the_platform_actually_did.test.mjs.

-- ── 1. ONE ROW PER POST x CHANNEL ─────────────────────────────────────────────────────────────────────
create table if not exists public.marketing_post_channel_result (
  post_id          bigint not null references public.marketing_post(id) on delete cascade,
  channel          text not null check (channel in ('facebook', 'instagram', 'linkedin', 'x', 'youtube', 'tiktok')),
  state            text not null check (state in ('pending', 'published', 'partial', 'failed')),
  cause            text check (cause is null or cause ~ '^[a-z_]+$'),
  postiz_post_id   text,
  postiz_state     text,
  platform_message text check (platform_message is null or length(platform_message) <= 1000),
  release_url      text check (release_url is null or release_url ~ '^https://'),
  first_checked_at timestamptz not null default now(),
  checked_at       timestamptz not null default now(),
  state_changed_at timestamptz not null default now(),
  primary key (post_id, channel),
  -- a channel that did not fully publish says why, and names its cause class (the second half of its finding key)
  constraint marketing_post_channel_result_says_why check (state not in ('partial', 'failed') or (platform_message is not null and cause is not null))
);
comment on table public.marketing_post_channel_result is
  'What each platform actually did with a post the marketing seat sent through Postiz, read back from Postiz (GET /public/v1/posts state + GET /public/v1/notifications) for 48 hours after sending. Written by fn_marketing_post_channel_record from marketing_channels (channelResults). Partial/failed rows are it_engineer findings duty:postiz_channel_result:post:<id>:<channel>.';
create index if not exists marketing_post_channel_result_open on public.marketing_post_channel_result (state) where state in ('partial', 'failed');
alter table public.marketing_post_channel_result enable row level security;
drop policy if exists marketing_post_channel_result_service_role_only on public.marketing_post_channel_result;
create policy marketing_post_channel_result_service_role_only on public.marketing_post_channel_result
  as permissive for all to public using (false) with check (false);
revoke all on public.marketing_post_channel_result from anon, authenticated;

-- ── 2. THE POST FROM ITS CHANNELS ─────────────────────────────────────────────────────────────────────
alter table public.marketing_post add column if not exists channel_outcome text;
alter table public.marketing_post add column if not exists channel_checked_at timestamptz;
alter table public.marketing_post drop constraint if exists marketing_post_channel_outcome_check;
alter table public.marketing_post add constraint marketing_post_channel_outcome_check
  check (channel_outcome is null or channel_outcome in ('pending', 'published', 'partial', 'failed'));
comment on column public.marketing_post.channel_outcome is
  'The post from its channels (marketing_post_channel_result): published only if every channel published; failed if none published or partly published; partial otherwise; pending while Postiz is still publishing (max 48h). NULL: not read back yet. status stays the send lifecycle.';

create or replace function public.fn_marketing_post_channel_record(p_post_id bigint, p_channels jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare x jsonb; n int := 0; v_states text[]; v_outcome text;
begin
  if jsonb_typeof(p_channels) is distinct from 'array' or jsonb_array_length(p_channels) = 0 then
    raise exception 'fn_marketing_post_channel_record(post, channels[]): at least one channel result is required';
  end if;
  if not exists (select 1 from public.marketing_post where id = p_post_id) then
    raise exception 'fn_marketing_post_channel_record: no marketing_post %', p_post_id;
  end if;
  for x in select e from jsonb_array_elements(p_channels) e loop
    insert into public.marketing_post_channel_result as r
      (post_id, channel, state, cause, postiz_post_id, postiz_state, platform_message, release_url)
    values (p_post_id, x->>'channel', x->>'state', nullif(x->>'cause', ''), nullif(x->>'postiz_post_id', ''), nullif(x->>'postiz_state', ''),
            left(nullif(btrim(coalesce(x->>'platform_message', '')), ''), 1000), nullif(x->>'release_url', ''))
    on conflict (post_id, channel) do update
       set state = excluded.state, cause = excluded.cause, postiz_post_id = coalesce(excluded.postiz_post_id, r.postiz_post_id),
           postiz_state = excluded.postiz_state, platform_message = excluded.platform_message,
           release_url = coalesce(excluded.release_url, r.release_url), checked_at = now(),
           state_changed_at = case when r.state is distinct from excluded.state then now() else r.state_changed_at end;
    n := n + 1;
  end loop;
  select array_agg(c.state) into v_states from public.marketing_post_channel_result c where c.post_id = p_post_id;
  -- THE RULE, the same as overallOutcome in _shared/marketing_channel_results.ts.
  v_outcome := case when 'pending' = any (v_states) then 'pending'
                    when v_states <@ array['published'] then 'published'
                    when not (v_states && array['published', 'partial']) then 'failed'
                    else 'partial' end;
  update public.marketing_post set channel_outcome = v_outcome, channel_checked_at = now() where id = p_post_id;
  return jsonb_build_object('post_id', p_post_id, 'channels', n, 'outcome', v_outcome);
end $fn$;
revoke execute on function public.fn_marketing_post_channel_record(bigint, jsonb) from public, anon, authenticated;

-- ── 3. THE RE-CHECK SCHEDULE ──────────────────────────────────────────────────────────────────────────
-- sent_at is when the send started. Which post a notification is about is decided over EVERY Postiz post on the
-- account (GET /posts, ours and ones made in Postiz's UI) by the edge function, not from our rows here.
create or replace function public.fn_marketing_channel_results_due(p_limit integer default 10)
returns table(post_id bigint, ingest_key text, channels text[], postiz_result jsonb, sent_at timestamptz)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select p.id, p.ingest_key, p.channels, p.postiz_result, coalesce(p.publish_started_at, p.published_at)
    from public.marketing_post p
   where p.status = 'published' and not p.is_demo and p.published_at is not null
     and (   (p.published_at > now() - interval '48 hours'
              and (p.channel_checked_at is null
                   or p.channel_checked_at < now() - make_interval(mins => public.fn_marketing_policy_int('marketing_channel_recheck_minutes', 30))))
          -- still pending at the 48-hour mark: one more read turns it into its final state
          or (p.channel_outcome = 'pending' and p.published_at > now() - interval '30 days'
              and p.channel_checked_at < now() - interval '30 minutes')
          or (p.channel_outcome in ('partial', 'failed') and p.published_at > now() - interval '30 days'
              and p.channel_checked_at < now() - interval '6 hours'))
   order by p.channel_checked_at nulls first, p.published_at
   limit greatest(1, least(coalesce(p_limit, 10), 50))
$fn$;
revoke execute on function public.fn_marketing_channel_results_due(integer) from public, anon, authenticated;

-- ── 4. THE DAILY EXPORT CARRIES THE NEW TABLE ─────────────────────────────────────────────────────────
create or replace function public.fn_table_export_list()
returns table(table_name text, subject text, change_log text)
language sql stable set search_path to 'public', 'pg_temp' as $fn$
  select v.t, v.s,
         (select 'table_export_change' from public.table_export_change_tracked x where x.table_name = v.t)
  from (values
    ('customers','customer'), ('customer_preference','customer'), ('customer_calls','customer'), ('projects','customer'),
    ('leads','supplier'), ('lead_category','supplier'), ('lead_subcategory','supplier'), ('supplier_capabilities','supplier'),
    ('supplier_catalog','supplier'), ('supplier_product','supplier'), ('supplier_product_variant','supplier'),
    ('supplier_capability_confirmation','supplier'), ('supplier_collaboration','supplier'), ('supplier_collaboration_event','supplier'),
    ('supplier_negotiation_policy','supplier'), ('supplier_screening_hit','supplier'), ('supplier_lead_intake','supplier'),
    ('doc_reviews','supplier'), ('licence_renewal_ask','supplier'), ('outreach','supplier'), ('company_registration','company'),
    ('inquiries','inquiry'), ('inquiry_intake','inquiry'), ('inquiry_matches','inquiry'), ('inquiry_requirement','inquiry'),
    ('inquiry_cancellations','inquiry'), ('inquiry_supplier_brief','inquiry'), ('inquiry_state_audit','inquiry'),
    ('inquiry_gate','inquiry'), ('inquiry_answer','inquiry'), ('inquiry_answer_document','inquiry'), ('inquiry_answer_scope','inquiry'),
    ('inquiry_workstream','inquiry'), ('inquiry_workstream_group','inquiry'), ('inquiry_workstream_requirement','inquiry'),
    ('inquiry_trade_candidate','inquiry'), ('inquiry_trade_clarification','inquiry'), ('inquiry_scope_disposition','inquiry'),
    ('rfq_archives','inquiry'), ('rfq_clarification','inquiry'),
    ('quotes','quote'), ('quote_items','quote'), ('quote_reviews','quote'), ('quote_review_messages','quote'),
    ('quote_requirements','quote'), ('quote_committed_items','quote'), ('quote_comparisons','quote'), ('quote_spec_hold','quote'),
    ('spec_alternative_offer','quote'), ('po_orders','quote'), ('po_vendors','quote'), ('questions','quote'), ('reviews','quote'),
    ('category_specs','quote rules'), ('category_quote_specs','quote rules'),
    ('transactions','payment'), ('reveal_invoices','payment'), ('supplier_dues','payment'), ('refunds','payment'),
    ('refund_case','payment'), ('refund_incident','payment'), ('refund_ceo_review','payment'), ('refund_ceo_check','payment'),
    ('refund_ladder_evidence','payment'), ('refund_status_transition','payment'), ('stripe_events','payment'),
    ('stripe_payout','payment'), ('stripe_dispute','payment'), ('charge_audit','payment'), ('pricing_config','payment'),
    ('gl_journal','accounting'), ('gl_journal_lines','accounting'), ('gl_expense_map','accounting'), ('expenses','accounting'),
    ('expense_entries','accounting'), ('bank_statement_intake','accounting'), ('bank_statement_line','accounting'),
    ('accountant_month_close','accounting'), ('accountant_issued_document','accounting'),
    ('messages','conversation'), ('chat_threads','conversation'), ('conversation_archive','conversation'),
    ('inbound_messages','conversation'), ('contact_messages','conversation'), ('complaint_tickets','conversation'),
    ('support_case','conversation'), ('support_notification','conversation'), ('support_document_intake','conversation'),
    ('wa_messages','conversation'), ('wa_conversation','conversation'), ('wa_turn','conversation'),
    ('wa_document_intake','conversation'), ('notifications','conversation'), ('agent_chats','conversation'),
    ('legal_reviews','legal'), ('pdpl_requests','legal'), ('pdpl_erase_files','legal'), ('email_suppressions','legal'),
    ('founder_instruction','decision'), ('company_policy_decision','decision'),
    ('kb_chunks','knowledge'), ('dept_library','knowledge'), ('ops_knowledge','knowledge'), ('agent_knowledge','knowledge'),
    ('sales_knowledge','knowledge'), ('ceo_knowledge','knowledge'), ('support_knowledge','knowledge'),
    ('accountant_knowledge','knowledge'), ('it_engineer_knowledge','knowledge'), ('employee_knowledge','knowledge'),
    ('marketing_post','marketing'), ('marketing_connection_check','marketing'), ('marketing_insight_day','marketing'),
    ('marketing_ad_spend_day','marketing'), ('marketing_duty_run','marketing'), ('marketing_report','marketing'),
    ('marketing_article','marketing'), ('marketing_prospect','marketing'), ('marketing_outreach_message','marketing'),
    ('marketing_platform_spec','marketing'), ('marketing_platform_spec_source','marketing'),
    ('marketing_campaign','marketing'), ('marketing_founder_request','marketing'), ('marketing_video_idea','marketing'), ('supplier_campaign_daily_list','supplier'), ('marketing_post_variant','marketing'),
    ('marketing_post_platform','marketing'), ('marketing_post_channel_result','marketing'), ('marketing_post_metric','marketing'), ('marketing_first_touch','marketing'),
    ('marketing_goal','marketing'), ('marketing_scorecard_report','marketing'),
    ('marketing_asset_feature','marketing'), ('marketing_asset_perception','marketing'), ('marketing_asset_review','marketing'),
    ('marketing_insight_note','marketing'), ('marketing_month_plan','marketing'), ('marketing_plan_review_turn','marketing'),
    ('marketing_model_run','marketing'), ('marketing_trend_source','marketing'), ('marketing_trend','marketing'),
    ('marketing_geo_question','marketing'), ('marketing_geo_check','marketing'), ('marketing_review','marketing'), ('market_intel','marketing'), ('competitor','marketing'), ('marketing_knowledge','knowledge'),
    ('table_export_change','backup')
  ) v(t, s)
  -- The sibling PRs' tables may not exist yet when this applies; backup/index.ts fails the whole day on a
  -- missing table, so ONLY those nine are skipped until their own file creates them. Every other table in the
  -- list still fails loudly if it disappears.
  where v.t not in ('marketing_platform_spec','marketing_platform_spec_source','marketing_campaign','marketing_post_variant',
                    'marketing_post_platform','marketing_post_metric','marketing_first_touch','marketing_goal','marketing_scorecard_report')
     or to_regclass('public.' || v.t) is not null
$fn$;

revoke execute on function public.fn_table_export_list() from public, anon, authenticated;
grant execute on function public.fn_table_export_list() to service_role;

-- ── 5. THE IT PLAYBOOK KNOWS THIS CLASS ───────────────────────────────────────────────────────────────
-- Without a row covering the prefix, fn_it_loop_reverify parks a cleared finding's handoff at awaiting_learning,
-- which later files duty:handoff_sla (the #58198 case fixed in #960). typical_cause / remedy / regression_check
-- let fn_it_learning_from_playbook complete the incident when the finding clears.
insert into public.it_playbook (failure_class, issue_prefix, remedy, not_automatable_reason, regression_check, added_by, typical_cause) values
  ('postiz_channel_result', 'duty:postiz_channel_result:',
   'The marketing seat fixes the cause on that channel (reconnects it in Postiz, verifies the YouTube account for custom thumbnails, or replaces the media below the platform floor) and republishes or corrects the post in Postiz; the 30-minute re-check reads it PUBLISHED and the finding closes by its key.',
   null, 'supabase/functions/_shared/marketing_channel_results.test.ts', 'it_engineer',
   'A channel of a published post failed or only partly published on the platform (Postiz state ERROR, or a platform complaint such as thumbnail not set, a caption cut, or resolution / frame rate / audio lowered), read back from Postiz after sending.')
on conflict (failure_class) do update set issue_prefix = excluded.issue_prefix, remedy = excluded.remedy,
  not_automatable_reason = excluded.not_automatable_reason, regression_check = excluded.regression_check, typical_cause = excluded.typical_cause;

-- ── 6. THE CEO REPORT COUNTS WHAT EACH CHANNEL DID ────────────────────────────────────────────────────
-- fn_marketing_report_figures counted every status='published' post as published, including one whose channels
-- all failed. Redefined here from the_marketing_seat_writes_articles_and_drafts_linkedin_outreach.sql (identical
-- to production's body, compared 24 Sep 2026) with channel_outcome read where it exists; NULL keeps the old
-- reading. fn_marketing_reviews_tick (its quarterly count) is NOT changed here: it has its own owning file.
create or replace function public.fn_marketing_report_figures(p_from timestamptz, p_to timestamptz)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_posts int; v_posts_ever int; v_spend jsonb; v_spend_aed numeric; v_unconv int; v_asked int; v_inq numeric; v_head text;
        v_sched int; v_held int; v_failed int; v_stuck int; v_live boolean; v_ins jsonb; v_conn jsonb; v_ins_days int;
        v_partial int;
begin
  -- A post counts as published only when its channels say so (channel_outcome published, or not read back yet:
  -- null / pending keep the old reading). Partly published is its own figure; failed on every channel is failed.
  select count(*) filter (where published_at >= p_from and published_at < p_to and coalesce(channel_outcome, 'published') in ('published', 'pending')),
         count(*) filter (where coalesce(channel_outcome, 'published') in ('published', 'pending')),
         count(*) filter (where published_at >= p_from and published_at < p_to and channel_outcome = 'partial')
    into v_posts, v_posts_ever, v_partial from public.marketing_post where status = 'published' and not is_demo;
  select count(*) filter (where status = 'scheduled' and scheduled_at >= p_to and scheduled_at < p_to + interval '7 days'),
         count(*) filter (where status = 'scheduled' and scheduled_at <= p_to and dry_run is not null),
         count(*) filter (where (status = 'failed' and updated_at >= p_from and updated_at < p_to)
                             or (status = 'published' and channel_outcome = 'failed' and published_at >= p_from and published_at < p_to)),
         count(*) filter (where status = 'publishing' and updated_at < p_to - interval '30 minutes')
    into v_sched, v_held, v_failed, v_stuck from public.marketing_post where not is_demo;
  v_live := coalesce((select lower(value) = 'true' from public.app_secrets where key = 'marketing_golive'), false);
  select coalesce(jsonb_object_agg(platform, aed), '{}'::jsonb), coalesce(sum(aed), 0), coalesce(sum(unconv), 0)
    into v_spend, v_spend_aed, v_unconv
    from (select platform, sum(amount_aed) aed, count(*) filter (where amount_aed is null) unconv
            from public.ad_spend_reported where spend_date >= (p_from at time zone 'Asia/Dubai')::date
                                           and spend_date < (p_to at time zone 'Asia/Dubai')::date
           group by platform) s;
  select count(*) into v_asked from public.notifications
   where kind = 'social_human_request' and created_at >= p_from and created_at < p_to;
  v_inq := public.fn_ceo_plan_measure('inquiries_posted', p_from, p_to)::numeric;
  select coalesce(jsonb_object_agg(k, v), '{}'::jsonb), count(distinct d) into v_ins, v_ins_days from (
    select i.platform || '.' || i.metric k, sum(i.value) v, max(i.day) d
      from public.marketing_insight_day i
     where i.object_type <> 'post' and i.day >= (p_from at time zone 'Asia/Dubai')::date - 1
       and i.day < (p_to at time zone 'Asia/Dubai')::date
     group by 1) x;
  v_conn := public.fn_marketing_connection_status();
  v_head := format('%s post(s) published%s, %s scheduled for the next 7 days%s, AED %s ad spend reported, %s conversation(s) handed to the founder, %s customer request(s) posted.',
                   v_posts, case when v_partial > 0 then format(' (%s more only partly: a channel failed)', v_partial) else '' end, v_sched, case when not v_live and v_held > 0 then format(' (%s due and held: publishing is off)', v_held) else '' end,
                   v_spend_aed, v_asked, coalesce(v_inq::text, 'unmeasured'));
  return jsonb_build_object(
    'headline', v_head,
    'measured', jsonb_build_object(
      'posts_published', v_posts, 'posts_partly_published', v_partial, 'posts_published_ever', v_posts_ever, 'posts_scheduled_next_7_days', v_sched,
      'posts_due_held_by_switch', v_held, 'posts_failed', v_failed, 'posts_stuck_publishing', v_stuck, 'publishing_live', v_live,
      'ad_spend_reported_aed', v_spend_aed, 'ad_spend_by_platform_aed', v_spend, 'ad_spend_rows_unconverted', v_unconv,
      'conversations_handed_to_founder', v_asked, 'customer_requests_posted', v_inq,
      'insights', v_ins, 'connections_all_ok', v_conn->'all_ok',
      'connections_failing', coalesce((select jsonb_agg(c->'check') from jsonb_array_elements(v_conn->'checks') c where not (c->>'ok')::boolean), '[]'::jsonb),
      'connections_measured_at', v_conn->'oldest_measurement',
      'business_development', (select to_jsonb(f) from public.marketing_bd_figures f),
      'social_inbox', coalesce((select jsonb_agg(to_jsonb(v)) from public.v_marketing_social_volume v), '[]'::jsonb)),
    'not_measured', to_jsonb(array_remove(array[
      case when v_ins_days = 0 then 'followers, reach and engagement per channel: no insight was pulled for the window yet' end,
      case when coalesce((v_conn->>'never_measured')::boolean, true) then 'channel access: the access check has not run yet' end,
      'search rankings and organic traffic: no SEO reader is built yet'], null)),
    'basis', 'Posts: marketing_post (published_at in the window; scheduled and held from its status and dry_run; published / partly / failed from channel_outcome where it has been read back from Postiz, else from status). Spend: ad_spend_reported by spend_date (Asia/Dubai), in AED at gl_settings usd_to_aed. Insights: marketing_insight_day, page and account metrics summed over the window. Connections: marketing_connection_check as last measured. Handed to the founder: notifications of kind social_human_request. Customer requests: fn_ceo_plan_measure(inquiries_posted), demo excluded. Business development: marketing_bd_figures (7-day counts, ZZ DEMO excluded). Social inbox: v_marketing_social_volume per platform. Window: the 24 hours before the report.');
end $fn$;
revoke execute on function public.fn_marketing_report_figures(timestamptz, timestamptz) from public, anon, authenticated;


-- ── THE VERDICT (a row, never a raise: this file defines things) ─────────────────────────────────────
select case
  when to_regclass('public.marketing_post_channel_result') is null then 'PROBE FAILED: marketing_post_channel_result missing'
  when has_function_privilege('anon', 'public.fn_marketing_post_channel_record(bigint, jsonb)', 'execute')
    or has_function_privilege('anon', 'public.fn_marketing_channel_results_due(integer)', 'execute')
    then 'PROBE FAILED: anon can execute a channel-result routine'
  when not exists (select 1 from public.fn_table_export_list() where table_name = 'marketing_post_channel_result')
    then 'PROBE FAILED: marketing_post_channel_result is not in the daily export'
  when not exists (select 1 from public.it_playbook where failure_class = 'postiz_channel_result' and issue_prefix = 'duty:postiz_channel_result:')
    then 'PROBE FAILED: no it_playbook row covers duty:postiz_channel_result:'
  when has_function_privilege('anon', 'public.fn_marketing_report_figures(timestamptz, timestamptz)', 'execute')
    then 'PROBE FAILED: anon can execute fn_marketing_report_figures'
  else 'PROBE OK' end as verdict;
