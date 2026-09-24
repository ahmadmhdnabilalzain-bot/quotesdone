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
-- The it_engineer finding: each partial/failed channel is settled by the edge function through the existing
-- fn_it_duty_settle('postiz_channel_result', ...) path, keyed duty:postiz_channel_result:post:<id>:<channel> (one
-- finding per post-channel, refiled under that key, closed when a re-check stores the channel published).
--
-- WHAT THIS DELIBERATELY DOES NOT CHANGE
--   * marketing_post.status keeps its meaning (the send lifecycle). A partly failed post is NOT turned back to
--     'failed': 'failed' means "safe to requeue", and requeueing a post that reached some platforms would publish
--     it twice there. The channel outcome is its own column.
--   * marketing_post_platform (the tie that drives metric checkpoints) is not reused: a channel that never
--     published has no id to tie and must not get metric checkpoints.
--   * No write to Postiz, no model, no notification from this file.
-- Prevented by: supabase/functions/_shared/marketing_channel_results.test.ts and
--   scripts/checks/each_channel_of_a_post_says_what_the_platform_actually_did.test.mjs.

-- ── 1. ONE ROW PER POST x CHANNEL ─────────────────────────────────────────────────────────────────────
create table if not exists public.marketing_post_channel_result (
  post_id          bigint not null references public.marketing_post(id) on delete cascade,
  channel          text not null check (channel in ('facebook', 'instagram', 'linkedin', 'x', 'youtube', 'tiktok')),
  state            text not null check (state in ('pending', 'published', 'partial', 'failed')),
  postiz_post_id   text,
  postiz_state     text,
  platform_message text check (platform_message is null or length(platform_message) <= 1000),
  release_url      text check (release_url is null or release_url ~ '^https://'),
  first_checked_at timestamptz not null default now(),
  checked_at       timestamptz not null default now(),
  state_changed_at timestamptz not null default now(),
  primary key (post_id, channel),
  -- a channel that did not fully publish says why
  constraint marketing_post_channel_result_says_why check (state not in ('partial', 'failed') or platform_message is not null)
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
      (post_id, channel, state, postiz_post_id, postiz_state, platform_message, release_url)
    values (p_post_id, x->>'channel', x->>'state', nullif(x->>'postiz_post_id', ''), nullif(x->>'postiz_state', ''),
            left(nullif(btrim(coalesce(x->>'platform_message', '')), ''), 1000), nullif(x->>'release_url', ''))
    on conflict (post_id, channel) do update
       set state = excluded.state, postiz_post_id = coalesce(excluded.postiz_post_id, r.postiz_post_id),
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
-- sent_at is when the send started (a notification about it cannot be older); next_same_channel is, per
-- channel, when the next post on that channel was sent: a notification after it belongs to that post, not this.
create or replace function public.fn_marketing_channel_results_due(p_limit integer default 10)
returns table(post_id bigint, ingest_key text, channels text[], postiz_result jsonb, sent_at timestamptz, next_same_channel jsonb)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select p.id, p.ingest_key, p.channels, p.postiz_result, coalesce(p.publish_started_at, p.published_at),
         (select jsonb_object_agg(n.ch, n.nx) from (
            select ch, min(coalesce(q.publish_started_at, q.published_at)) as nx
              from unnest(p.channels) ch
              join public.marketing_post q on q.id <> p.id and ch = any (q.channels) and q.status = 'published'
                                          and coalesce(q.publish_started_at, q.published_at) > coalesce(p.publish_started_at, p.published_at)
             group by ch) n)
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

-- ── THE VERDICT (a row, never a raise: this file defines things) ─────────────────────────────────────
select case
  when to_regclass('public.marketing_post_channel_result') is null then 'PROBE FAILED: marketing_post_channel_result missing'
  when has_function_privilege('anon', 'public.fn_marketing_post_channel_record(bigint, jsonb)', 'execute')
    or has_function_privilege('anon', 'public.fn_marketing_channel_results_due(integer)', 'execute')
    then 'PROBE FAILED: anon can execute a channel-result routine'
  when not exists (select 1 from public.fn_table_export_list() where table_name = 'marketing_post_channel_result')
    then 'PROBE FAILED: marketing_post_channel_result is not in the daily export'
  else 'PROBE OK' end as verdict;
