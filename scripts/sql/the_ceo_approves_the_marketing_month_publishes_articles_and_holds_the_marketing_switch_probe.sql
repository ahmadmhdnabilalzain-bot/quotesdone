-- PROBE of the_ceo_approves_the_marketing_month_publishes_articles_and_holds_the_marketing_switch.sql. LOCAL only (a Postgres
-- 16 built from the schema mirror). Always raises CHK<<...>>, so every plan, campaign, post, decision and switch rolls back.
do $probe$
declare
  v_p text[] := '{}'; r jsonb; v_cid bigint; v_key text := 'probe-' || md5(random()::text); v_month date := date '2031-02-01';
begin
  insert into public.app_secrets (key, value) values ('marketing_golive', 'false'), ('marketing_publishing_enabled', 'true')
  on conflict (key) do update set value = excluded.value;

  -- 1. marketing_golive is data the CEO moves, with a reason, no deploy
  r := public.fn_ceo_switches_marketing_golive(true, 'short');
  if coalesce((r->>'ok')::boolean, false) or public.fn_marketing_publishing_live() then v_p := v_p || 'the switch moved without a reason'::text; end if;
  r := public.fn_ceo_switches_marketing_golive(true, 'Probe: an approved calendar waits and the emergency stop is off.');
  if not public.fn_marketing_publishing_live() or not exists (select 1 from public.marketing_ceo_decision where subject_kind = 'marketing_golive' and decision = 'switch_on') then
    v_p := v_p || ('the CEO could not switch publishing on: ' || r::text); end if;
  r := public.fn_ceo_switches_marketing_golive(true, 'Probe: switching on again changes nothing at all.');
  if coalesce((r->>'changed')::boolean, true) then v_p := v_p || 'a second switch-on was recorded as a change'::text; end if;
  r := public.fn_ceo_switches_marketing_golive(false, 'Probe: the CEO switches publishing off with a reason.');
  if public.fn_marketing_publishing_live() then v_p := v_p || 'the CEO could not switch publishing off'::text; end if;

  -- 2. a month waiting on the founder is accepted by the CEO with its own review as the reason
  insert into public.marketing_month_plan (month, status, verdict, plan_sent_at)
  values (v_month, 'sent_to_founder', jsonb_build_object('ceo', jsonb_build_object('round', 2, 'reasons', 'Probe: leans on what brought registrations.')), now() - interval '5 days');
  r := public.fn_ceo_decides_marketing();
  if (select status from public.marketing_month_plan where month = v_month) <> 'accepted' then v_p := v_p || ('the waiting month was not accepted: ' || r::text); end if;
  if not exists (select 1 from public.marketing_ceo_decision where subject_kind = 'month_plan' and subject_ref = v_month::text and decision = 'accept' and reason like '%round 2%') then
    v_p := v_p || 'the acceptance has no reason from the CEO''s review'::text; end if;

  -- 3. a calendar built, unedited, organic, with a post to come: the CEO approves it exactly as built
  insert into public.marketing_campaign (campaign_key, theme, month, spend_policy) values (v_key, 'probe', v_month, 'organic_only') returning id into v_cid;
  insert into public.marketing_post (campaign_id, ingest_key, ingested_by, text_en, channels, scheduled_at, status, is_demo)
  values (v_cid, v_key || '-1', 'marketing', 'Probe post', array['linkedin'], now() + interval '3 days', 'scheduled', false);
  update public.marketing_campaign set calendar_hash = public.fn_marketing_campaign_hash(v_cid) where id = v_cid;
  r := public.fn_ceo_decides_marketing();
  if (select approved_by from public.marketing_campaign where id = v_cid) is distinct from 'ceo'
     or (select approved_hash from public.marketing_campaign where id = v_cid) is distinct from public.fn_marketing_campaign_hash(v_cid) then
    v_p := v_p || ('the calendar was not approved as built: ' || r::text); end if;
  if public.fn_marketing_publishing_live() then v_p := v_p || 'the CEO round switched marketing_golive on by itself (it also starts the founder''s LinkedIn list)'::text; end if;

  -- an article the CEO approved is published by the CEO's decision (released on its weekly slot), once
  insert into public.marketing_article (slug, kind, title_en, excerpt_en, meta_desc_en, category_en, body_html_en, title_ar, excerpt_ar, meta_desc_ar,
                                        category_ar, body_html_ar, sources, checks, ingested_by, linkedin_post_key, status, approved_by, approved_at, is_demo)
  values (v_key || '-article', 'market_topic', 'Probe title', 'Probe excerpt', 'Probe meta', 'Probe', '<p>Probe</p>', U&'\0645\0642\0627\0644', U&'\0645\0642\0627\0644',
          U&'\0645\0642\0627\0644', U&'\0645\0642\0627\0644', U&'<p>\0645\0642\0627\0644</p>', '[{"ref":"probe","text":"probe"}]'::jsonb,
          '{"lint":[],"ungrounded":[]}'::jsonb, 'claude', v_key || '-post', 'approved', 'ceo', now() - interval '3 days', false);
  r := public.fn_ceo_decides_marketing();
  if not exists (select 1 from public.marketing_ceo_decision where subject_kind = 'article' and subject_ref = v_key || '-article' and decision = 'publish') then
    v_p := v_p || ('the CEO did not publish the article it approved: ' || r::text); end if;
  r := public.fn_ceo_decides_marketing();
  if (select count(*) from public.marketing_ceo_decision where subject_kind = 'article' and subject_ref = v_key || '-article') <> 1 then v_p := v_p || 'an article was published twice'::text; end if;
  r := public.fn_ceo_publishes_article('qd-probe-no-such-article', 'Probe: publishing an article that does not exist.');
  if coalesce((r->>'ok')::boolean, false) then v_p := v_p || 'an unknown article was published'::text; end if;

  -- an edited calendar (the channels are in the content hash) is refused; a paid one cannot exist (marketing_campaign_spend_policy_check)
  update public.marketing_campaign set approved_by = null, approved_at = null, approved_hash = null, approved_message_id = null where id = v_cid;
  update public.marketing_post set channels = array['linkedin', 'x'] where campaign_id = v_cid;
  r := public.fn_ceo_approves_marketing_calendar(v_key, 'Probe: the CEO approves the calendar as built here.');
  if coalesce((r->>'ok')::boolean, false) or r->>'reason' not like '%changed after it was built%' then v_p := v_p || ('an edited calendar was approved: ' || r::text); end if;

  -- 4. the founder's emergency stop outranks the CEO: with it on, the CEO's round switches nothing on
  update public.app_secrets set value = 'false' where key = 'marketing_golive';
  update public.app_secrets set value = 'false' where key = 'marketing_publishing_enabled';
  update public.marketing_article set status = 'approved' where slug = v_key || '-article';
  insert into public.marketing_article (slug, kind, title_en, excerpt_en, meta_desc_en, category_en, body_html_en, title_ar, excerpt_ar, meta_desc_ar,
                                        category_ar, body_html_ar, sources, checks, ingested_by, linkedin_post_key, status, approved_by, approved_at, is_demo)
  values (v_key || '-second', 'market_topic', 'Probe title', 'Probe excerpt', 'Probe meta', 'Probe', '<p>Probe</p>', U&'\0645\0642\0627\0644', U&'\0645\0642\0627\0644',
          U&'\0645\0642\0627\0644', U&'\0645\0642\0627\0644', U&'<p>\0645\0642\0627\0644</p>', '[{"ref":"probe","text":"probe"}]'::jsonb,
          '{"lint":[],"ungrounded":[]}'::jsonb, 'claude', v_key || '-post2', 'approved', 'ceo', now() - interval '1 day', false);
  r := public.fn_ceo_decides_marketing();
  if public.fn_marketing_publishing_live() then v_p := v_p || 'the CEO switched publishing on over the founder''s emergency stop'::text; end if;
  if exists (select 1 from public.marketing_ceo_decision where subject_ref = v_key || '-second') then v_p := v_p || 'the CEO published over the founder''s emergency stop'::text; end if;
  if (select value from public.app_secrets where key = 'marketing_publishing_enabled') <> 'false' then v_p := v_p || 'the CEO touched the emergency stop'::text; end if;

  -- 5. decisions are history
  begin
    update public.marketing_ceo_decision set reason = 'rewritten history, never allowed' where subject_kind = 'month_plan';
    v_p := v_p || 'a CEO decision was rewritten'::text;
  exception when raise_exception then null; end;

  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when cardinality(v_p) = 0 then 'PROBE OK' else 'PROBE FAILED' end, 'problems', to_jsonb(v_p));
end $probe$;
