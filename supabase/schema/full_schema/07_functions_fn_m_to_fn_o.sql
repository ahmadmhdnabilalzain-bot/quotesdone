CREATE OR REPLACE FUNCTION public.fn_mail_provider_class(p_domain text, p_mx_hosts text[])
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d text := lower(btrim(coalesce(p_domain, ''))); h text := lower(rtrim(btrim(coalesce(p_mx_hosts[1], '')), '.'));
begin
  if h <> '' then
    if h ~ '(^|\.)(protection\.)?outlook\.com$' or h ~ '(^|\.)hotmail\.com$' then return 'microsoft'; end if;
    if h ~ '(^|\.)(google|googlemail)\.com$' then return 'google'; end if;
    if h ~ '(^|\.)yahoodns\.net$' or h ~ '(^|\.)(yahoo|aol)\.com$' then return 'yahoo_aol'; end if;
    return 'other';
  end if;
  if d ~ '^(outlook|hotmail|live|msn)\.[a-z.]+$' then return 'microsoft'; end if;
  if d in ('gmail.com', 'googlemail.com') then return 'google'; end if;
  if d ~ '^(yahoo|ymail|rocketmail|aol)\.[a-z.]+$' then return 'yahoo_aol'; end if;
  return 'other';
end $function$


CREATE OR REPLACE FUNCTION public.fn_mail_provider_of_email(p_email text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select public.fn_mail_provider_class(x.dom, (select m.hosts from public.email_domain_mx m where m.domain = x.dom and m.kind = 'mx'))
    from (select split_part(lower(btrim(coalesce(p_email, ''))), '@', 2) as dom) x;
$function$


CREATE OR REPLACE FUNCTION public.fn_mail_sender_known(p_email text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare e text := lower(btrim(coalesce(p_email, '')));
begin
  if e = '' then return null; end if;
  if exists (select 1 from public.app_secrets s, unnest(string_to_array(lower(s.value), ',')) a
              where s.key in ('admin_emails', 'expense_forwarders', 'founder_email') and btrim(a) = e) then return 'staff'; end if;
  if exists (select 1 from public.customers where lower(email) = e) then return 'customer'; end if;
  if exists (select 1 from public.leads where lower(email) = e) then return 'supplier'; end if;
  if exists (select 1 from public.leads where lower(btrim(claimed_by)) = e) then return 'supplier'; end if;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_mailbox_fold(p_addr text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare e text := lower(btrim(coalesce(p_addr, ''))); l text; d text;
begin
  -- "Name <a@b>" is reduced to the address inside the brackets.
  if e ~ '<[^<>]+>' then e := btrim(substring(e from '<([^<>]+)>')); end if;
  if position('@' in e) = 0 then return e; end if;
  l := split_part(e, '@', 1); d := split_part(e, '@', 2);
  l := regexp_replace(l, '\+.*$', '');
  if d in ('gmail.com', 'googlemail.com') then l := replace(l, '.', ''); d := 'gmail.com'; end if;
  return l || '@' || d;
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_ad_spend_record(p_account text, p_business_id text, p_rows jsonb, p_is_demo boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_expected_acct text := 'act_' || regexp_replace(coalesce((select value from public.app_secrets where key = 'meta_ad_account_id'), ''), '^act_', '');
  v_business text := (select value #>> '{}' from public.decision_policy where key = 'marketing_meta_business_id');
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_n int := 0; v_handoffs int := 0; d record;
begin
  if not p_is_demo and (p_account is distinct from v_expected_acct or p_business_id is distinct from v_business) then
    return jsonb_build_object('ok', false, 'error', 'account_not_the_company',
      'message', 'The ad account read is not app_secrets.meta_ad_account_id inside the Quotes Done business (decision_policy marketing_meta_business_id); nothing was recorded.',
      'account', p_account, 'business', p_business_id);
  end if;

  insert into public.marketing_ad_spend_day as t (account_id, campaign_id, day, campaign_name, spend, currency, impressions, clicks, is_demo, pulled_at)
  select p_account, r->>'campaign_id', (r->>'day')::date, r->>'campaign_name', round((r->>'spend')::numeric, 2),
         upper(r->>'currency'), nullif(r->>'impressions', '')::bigint, nullif(r->>'clicks', '')::bigint, p_is_demo, now()
    from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r
  on conflict (account_id, campaign_id, day) do update
     set campaign_name = excluded.campaign_name, currency = excluded.currency, impressions = excluded.impressions,
         clicks = excluded.clicks, pulled_at = now(),
         -- a revised figure goes to the accountant again
         handed_off_at = case when excluded.spend is distinct from t.spend then null else t.handed_off_at end,
         booked_ack_at = case when excluded.spend is distinct from t.spend then null else t.booked_ack_at end,
         spend = excluded.spend;
  get diagnostics v_n = row_count;

  -- Never today (still moving), never a demo row, never a zero.
  for d in
    select s.* from public.marketing_ad_spend_day s
     where s.account_id = p_account and not s.is_demo and s.day < v_today and s.handed_off_at is null and s.spend > 0
     order by s.day, s.campaign_id
  loop
    update public.marketing_ad_spend_day set handed_off_at = now()
     where account_id = d.account_id and campaign_id = d.campaign_id and day = d.day;
    perform public.fn_marketing_records_ad_spend('meta', d.day, d.currency, d.spend,
      d.account_id || ':' || d.campaign_id || ':' || d.day, d.campaign_name, false);
    v_handoffs := v_handoffs + 1;
  end loop;
  return jsonb_build_object('ok', true, 'rows', v_n, 'handoffs', v_handoffs);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_approval_reply(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_token text := lower(coalesce(p->>'token', '')); v_from text := lower(btrim(coalesce(p->>'from_email', '')));
  d public.marketing_plan_doc; v_out text; v_what text; v_msg text;
begin
  if v_from is distinct from public.fn_marketing_founder_email() then return jsonb_build_object('outcome', 'not_the_founder'); end if;
  -- ARTICLE APPROVAL IS RETIRED (founder 1058): a reply to any article approval email ever sent changes nothing.
  if v_token <> '' and (exists (select 1 from public.marketing_article where approval_token = v_token)
       or exists (select 1 from public.notifications where kind = 'marketing_article_approval'
                   and reply_to = 'approve+' || v_token || '@mail.quotesdone.com')) then
    perform public.fn_marketing_mail_founder('marketing_approval_reply', 'Not changed: article approval is retired',
      'Blog articles are no longer approved by you: the CEO seat reviews each one, and you are told only when one goes live. '
      || 'Your reply changed nothing and published nothing.');
    return jsonb_build_object('outcome', 'article_approval_retired');
  end if;
  select * into d from public.marketing_plan_doc where approval_token = v_token and v_token <> '' for update;
  v_what := case when d.id is not null then 'launch plan for ' || to_char(d.period, 'FMMonth YYYY') end;
  if v_what is null then
    v_out := 'unknown'; v_msg := 'Your reply did not match an approval email, so nothing was changed. Please reply to the latest one.';
  elsif not coalesce((p->>'authenticated')::boolean, false) then
    v_out := 'not_authenticated';
    v_msg := 'A reply about the ' || v_what || ' arrived with your address but could not be verified as coming from your mailbox, so nothing was changed.';
  elsif d.status <> 'sent_to_founder' then
    v_out := 'already_decided'; v_msg := 'The ' || v_what || ' was already decided; nothing was changed.';
  elsif p->>'intent' = 'approve' then
    update public.marketing_plan_doc set status = 'approved', decided_at = now(), updated_at = now() where id = d.id;
    v_out := 'approved'; v_msg := 'Approved: the ' || v_what || '. The marketing seat runs it from 1 January 2027.';
  elsif btrim(coalesce(p->>'text', '')) = '' then
    -- an empty reply is not a change: nothing is filed, the token stays valid, and the item is still his to approve
    v_out := 'empty_reply';
    v_msg := 'Your reply about the ' || v_what || ' was empty, so nothing was changed and it is still waiting for you. '
          || 'Reply "approve" to the same email, or write the change you want.';
  else
    -- his change joins the plan (founder_changes) and the next daily redraw is re-sent to him with it
    update public.marketing_plan_doc set status = 'change_requested', founder_note = left(btrim(p->>'text'), 4000),
           founder_changes = founder_changes || to_jsonb(left(btrim(p->>'text'), 4000)),
           approval_token = null, decided_at = now(), updated_at = now() where id = d.id;
    v_out := 'change_requested';
    v_msg := 'Your change to the ' || v_what || ' is written into the plan, which is sent back to you with it. '
          || 'Nothing is run until you approve the new version.';
  end if;
  perform public.fn_marketing_mail_founder('marketing_approval_reply',
    case when v_out = 'approved' then 'Approved: ' when v_out = 'change_requested' then 'Change noted: ' else 'Not changed: ' end || coalesce(v_what, 'approval'), v_msg);
  return jsonb_build_object('outcome', v_out, 'plan_doc', d.id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_article_approve(p_slug text, p_by text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint;
begin
  if p_by is distinct from 'ceo' then return jsonb_build_object('ok', false, 'error', 'only_the_ceo_seat_approves_an_article'); end if;
  update public.marketing_article a set status = 'approved', approved_by = 'ceo', approved_at = now(), updated_at = now()
   where a.slug = p_slug and a.status = 'draft' and a.kind = 'market_topic'
     and (select r.decision from public.marketing_article_round r where r.article_id = a.id order by r.round desc limit 1) = 'approve'
  returning a.id into v_id;
  return jsonb_build_object('ok', v_id is not null, 'slug', p_slug, 'error', case when v_id is null then 'no_approved_review_round' end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_article_fingerprint(p_id bigint)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select md5(concat_ws(E'\x1f', title_en, excerpt_en, meta_desc_en, category_en, body_html_en,
                                 title_ar, excerpt_ar, meta_desc_ar, category_ar, body_html_ar))
    from public.marketing_article where id = p_id
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_article_ingest(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_slug text := lower(btrim(coalesce(p->>'slug', '')));
  v_key text; v_cur public.marketing_article; v_id bigint; v_post jsonb; v_f text;
begin
  foreach v_f in array array['title', 'excerpt', 'meta_desc', 'category', 'body_html'] loop
    if public.fn_text_lost_its_script(p->'ar'->>v_f) then
      return jsonb_build_object('ok', false, 'error', 'text_lost_its_script', 'field', 'ar.' || v_f);
    end if;
  end loop;
  if coalesce(p->'checks'->'lint', '[]'::jsonb) <> '[]'::jsonb or coalesce(p->'checks'->'ungrounded', '[]'::jsonb) <> '[]'::jsonb then
    return jsonb_build_object('ok', false, 'error', 'checks_not_clean', 'checks', p->'checks');
  end if;
  v_key := 'article-' || v_slug;
  select * into v_cur from public.marketing_article where slug = v_slug for update;
  if found and v_cur.status <> 'draft' then
    return jsonb_build_object('ok', true, 'unchanged', true, 'status', v_cur.status,
      'message', 'Already ' || v_cur.status || '; an approved article is not edited in place. Withdraw it or ingest a new slug.');
  end if;
  insert into public.marketing_article (slug, kind, title_en, excerpt_en, meta_desc_en, category_en, body_html_en,
      title_ar, excerpt_ar, meta_desc_ar, category_ar, body_html_ar, sources, checks, ingested_by, linkedin_post_key, is_demo)
  values (v_slug, p->>'kind', p->'en'->>'title', p->'en'->>'excerpt', p->'en'->>'meta_desc', p->'en'->>'category', p->'en'->>'body_html',
          p->'ar'->>'title', p->'ar'->>'excerpt', p->'ar'->>'meta_desc', p->'ar'->>'category', p->'ar'->>'body_html',
          p->'sources', p->'checks', coalesce(p->>'ingested_by', 'claude'), v_key, coalesce((p->>'is_demo')::boolean, false))
  on conflict (slug) do update
     set kind = excluded.kind, title_en = excluded.title_en, excerpt_en = excluded.excerpt_en, meta_desc_en = excluded.meta_desc_en,
         category_en = excluded.category_en, body_html_en = excluded.body_html_en, title_ar = excluded.title_ar,
         excerpt_ar = excluded.excerpt_ar, meta_desc_ar = excluded.meta_desc_ar, category_ar = excluded.category_ar,
         body_html_ar = excluded.body_html_ar, sources = excluded.sources, checks = excluded.checks,
         ingested_by = excluded.ingested_by, is_demo = excluded.is_demo, updated_at = now()
  returning id into v_id;
  -- Its LinkedIn post, a DRAFT in #834's store: scheduled only by fn_marketing_article_mark_live.
  v_post := public.fn_marketing_post_ingest(jsonb_build_object('ingest_key', v_key, 'ingested_by', 'marketing',
              'title', p->'en'->>'title', 'text_en', p->'post'->>'text_en', 'text_ar', p->'post'->>'text_ar',
              'channels', jsonb_build_array('linkedin'), 'is_demo', coalesce((p->>'is_demo')::boolean, false)));
  if not coalesce((v_post->>'ok')::boolean, false) then
    raise exception 'the article''s LinkedIn post was refused: %', v_post;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'slug', v_slug, 'status', 'draft', 'linkedin_post', v_post);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_article_mark_live(p_slug text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_a public.marketing_article; v_posts int; v_fyi bigint; v_rounds int;
begin
  update public.marketing_article set status = 'live', live_at = now(), updated_at = now()
   where slug = p_slug and status = 'released' returning * into v_a;
  if v_a.id is null then return jsonb_build_object('ok', false, 'error', 'not_released'); end if;
  update public.marketing_post set status = 'scheduled', scheduled_at = now() + interval '5 minutes', updated_at = now()
   where ingest_key = v_a.linkedin_post_key and status = 'draft';
  get diagnostics v_posts = row_count;
  if v_a.topic_id is not null then
    update public.marketing_blog_topic set status = 'published', closed_at = now() where id = v_a.topic_id and status = 'picked';
  end if;
  if not v_a.is_demo then
    select count(*) into v_rounds from public.marketing_article_round where article_id = v_a.id;
    v_fyi := public.fn_marketing_mail_founder('marketing_article_live',
      'FYI - published on the blog: ' || left(v_a.title_en, 140),
      'For your information: this week''s blog article is live, in English and Arabic.' || E'\n\n'
      || v_a.title_en || E'\n' || 'https://quotesdone.ae/blog/' || v_a.slug || E'\n\n'
      || v_a.title_ar || E'\n' || 'https://quotesdone.ae/ar/blog/' || v_a.slug || E'\n\n'
      || 'The CEO seat approved it after ' || v_rounds || ' review round(s). Nothing is needed from you.');
  end if;
  return jsonb_build_object('ok', true, 'slug', p_slug, 'linkedin_post_scheduled', v_posts = 1, 'founder_fyi', v_fyi,
                            'next_topic', public.fn_marketing_blog_topic_pick());
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_article_release_due()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_now timestamp := now() at time zone 'Asia/Dubai';
  v_week int; v_today int; v_next public.marketing_article;
begin
  -- ONE CALLER AT A TIME (release review, 29 Sep 2026): two overlapping ticks each counted 0 releases this week and
  -- each skip-locked a DIFFERENT approved row, so the week got two blogs. The lock serialises the count and the release.
  perform pg_advisory_xact_lock(hashtext('fn_marketing_article_release_due'));
  if not public.fn_is_working_day(v_now::date) then
    return jsonb_build_object('released', null, 'reason', 'not a UAE working day');
  end if;
  select count(*) filter (where released_at at time zone 'Asia/Dubai' >= date_trunc('week', v_now)),
         count(*) filter (where (released_at at time zone 'Asia/Dubai')::date = v_now::date)
    into v_week, v_today from public.marketing_article where released_at is not null and not is_demo;
  if v_week >= 1 or v_today > 0 then
    return jsonb_build_object('released', null, 'this_week', v_week, 'reason', 'one blog a week');
  end if;
  select * into v_next from public.marketing_article
   where status = 'approved' and approved_by = 'ceo' and kind = 'market_topic' and not is_demo
   order by approved_at, id limit 1 for update skip locked;
  if not found then return jsonb_build_object('released', null, 'this_week', v_week, 'reason', 'nothing_approved_by_the_ceo'); end if;
  if not public.fn_marketing_publishing_live() then
    return jsonb_build_object('released', null, 'held', true, 'would_release', v_next.slug, 'reason', 'marketing_golive is not true');
  end if;
  update public.marketing_article set status = 'released', released_at = now(), updated_at = now() where id = v_next.id;
  return jsonb_build_object('released', v_next.slug, 'this_week', v_week + 1);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_article_release_duty()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_stuck text; v_pick jsonb;
begin
  select slug into v_stuck from public.marketing_article
   where status = 'approved' and approved_by = 'ceo' and not is_demo and approved_at < now() - interval '8 days' limit 1;
  if v_stuck is not null and public.fn_marketing_publishing_live() then
    raise exception 'article % was approved by the CEO seat more than 8 days ago and is not released', v_stuck;
  end if;
  v_pick := public.fn_marketing_blog_topic_pick();
  return jsonb_build_object('topic', v_pick,
    'open_topic', (select jsonb_build_object('id', id, 'title', title, 'kind', kind) from public.marketing_blog_topic where status = 'picked'),
    'in_review', (select count(*) from public.marketing_article_round r join public.marketing_article a on a.id = r.article_id
                   where r.decision is null and a.status = 'draft'),
    'approved', (select count(*) from public.marketing_article where status = 'approved' and not is_demo),
    'live', (select count(*) from public.marketing_article where status = 'live' and not is_demo));
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_article_round_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_prev public.marketing_article_round; v_missing text;
begin
  if tg_op = 'DELETE' then
    raise exception 'round % of article % is history: a review round is never deleted', old.round, old.article_id;
  end if;
  if tg_op = 'UPDATE' then
    if old.decision is not null then
      raise exception 'round % of article % is decided (%): its history is never overwritten', old.round, old.article_id, old.decision;
    end if;
    if (new.article_id, new.topic_id, new.round, new.version, new.fingerprint, new.drafted_by_model, new.changes, new.created_at)
       is distinct from (old.article_id, old.topic_id, old.round, old.version, old.fingerprint, old.drafted_by_model, old.changes, old.created_at) then
      raise exception 'only the CEO''s decision is written to a submitted round';
    end if;
    if new.decision = 'revise' and (select count(*) from public.marketing_article_round r
                                     where r.topic_id = new.topic_id and r.decision = 'revise') >= 4 then
      raise exception 'after 4 revise rounds on topic % the CEO approves or replaces the topic', new.topic_id;
    end if;
    return new;
  end if;
  if new.decision is not null then raise exception 'a round is submitted undecided'; end if;
  if new.round > 1 then
    select * into v_prev from public.marketing_article_round where article_id = new.article_id and round = new.round - 1;
    if v_prev.decision is distinct from 'revise' then
      raise exception 'round % of article % follows only a revise decision', new.round, new.article_id;
    end if;
    select string_agg(k.key, ', ' order by k.key) into v_missing
      from jsonb_each(v_prev.reasons) k
     where k.value->>'verdict' = 'fail'
       and not exists (select 1 from jsonb_array_elements(coalesce(new.changes, '[]'::jsonb)) c
                        where c->>'criterion' = k.key and length(btrim(coalesce(c->>'change', ''))) >= 10);
    if v_missing is not null then
      raise exception 'the revision does not say what changed for the CEO''s reason(s): %', v_missing;
    end if;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_asks_the_founder_to_take_over(p_platform text, p_thread_ref text, p_handle text, p_last_message text, p_summary text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_subject text; v_id bigint; a public.agent_actions;
begin
  if coalesce(p_platform, '') !~ '^[a-z][a-z0-9_]*$' or coalesce(btrim(p_thread_ref), '') = '' then
    raise exception 'a handover names its platform (lowercase key) and the platform''s thread reference';
  end if;
  if concat_ws(' ', p_thread_ref, p_handle, p_last_message) ~* 'zz[ _-]?demo' then
    return jsonb_build_object('asked', false, 'reason', 'a ZZ DEMO conversation never reaches the founder');
  end if;
  v_subject := p_platform || ':' || p_thread_ref || ':' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD');
  v_id := public.fn_seat_handoff('marketing', 'customer_support', 'delivery.request', 'social_conversation', v_subject,
    jsonb_build_object('recipient_role', 'founder', 'kind', 'social_human_request', 'level', 'medium',
      'dedupe_key', 'social_human_request:' || v_subject,
      'event', 'Someone on ' || initcap(p_platform) || ' asked to speak with a person',
      'detail', coalesce(nullif(btrim(p_handle), ''), 'A person') || ' asked to speak with a person on ' || initcap(p_platform)
                || ' (conversation ' || p_thread_ref || ').' || E'\n\nTheir last message: ' || left(coalesce(p_last_message, ''), 1000)
                || coalesce(E'\n\nThe conversation so far: ' || left(nullif(btrim(p_summary), ''), 1500), '')
                || E'\n\nThe automatic replies on this conversation have stopped. Please reply to them directly on '
                || initcap(p_platform) || '.',
      'platform', p_platform, 'thread_ref', p_thread_ref));
  select * into a from public.agent_actions where id = v_id;
  return jsonb_build_object('asked', a.status <> 'failed', 'handoff_id', v_id, 'status', a.status,
                            'notification_id', a.evidence->'notification_id', 'error', a.detail->>'error');
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_asset_dossier(p_sha text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare f public.marketing_asset_feature; q public.marketing_asset_perception; v_metrics jsonb := '[]'::jsonb;
begin
  select * into f from public.marketing_asset_feature where file_sha256 = p_sha order by measured_at desc limit 1;
  select * into q from public.marketing_asset_perception where file_sha256 = p_sha order by id desc limit 1;
  if to_regclass('public.marketing_post_metric') is not null and f.file_sha256 is not null then
    execute 'select coalesce(jsonb_agg(to_jsonb(m)), ''[]''::jsonb) from (select m.* from public.marketing_post_metric m '
         || 'join public.marketing_post p on p.id = m.post_id where $1 = any(p.media_paths) or $2 = any(p.media_paths) '
         || 'order by m.id limit 50) m'
      into v_metrics using f.asset_path, f.asset_bucket || '/' || f.asset_path;
  end if;
  return jsonb_build_object('asset', p_sha, 'path', f.asset_path,
    'features', case when f.file_sha256 is null then null else to_jsonb(f) - 'toolchain' end,
    'perception', case when q.id is null then null else jsonb_build_object('id', q.id, 'model', q.model, 'perception', q.perception, 'disagreements', q.disagreements) end,
    'keyframes', coalesce(f.keyframes, '[]'::jsonb), 'post_metrics', v_metrics,
    'posts_measured', jsonb_array_length(v_metrics));
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_asset_feature_record(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  insert into public.marketing_asset_feature (file_sha256, extractor_version, asset_bucket, asset_path, bytes, duration_s,
    width, height, aspect, fps, scene_cuts, cuts_per_10s, hook_cuts_first_3s, hook_motion_first_3s, audio_present,
    loudness_lufs, true_peak_db, speech_band_ratio, voiceover_suspected, frames_with_text, frames_sampled,
    text_chars_per_frame, keyframes, music, toolchain, measured_at)
  values (p->>'file_sha256', p->>'extractor_version', p->>'asset_bucket', p->>'asset_path', (p->>'bytes')::bigint,
    (p->>'duration_s')::numeric, (p->>'width')::int, (p->>'height')::int, p->>'aspect', (p->>'fps')::numeric,
    (p->>'scene_cuts')::int, (p->>'cuts_per_10s')::numeric, (p->>'hook_cuts_first_3s')::int,
    (p->>'hook_motion_first_3s')::numeric, (p->>'audio_present')::boolean, (p->>'loudness_lufs')::numeric,
    (p->>'true_peak_db')::numeric, (p->>'speech_band_ratio')::numeric, (p->>'voiceover_suspected')::boolean,
    (p->>'frames_with_text')::int, (p->>'frames_sampled')::int, (p->>'text_chars_per_frame')::numeric,
    coalesce(p->'keyframes', '[]'::jsonb), coalesce(p->'music', '{}'::jsonb), coalesce(p->'toolchain', '{}'::jsonb), now())
  on conflict (file_sha256, extractor_version) do update set
    asset_bucket = excluded.asset_bucket, asset_path = excluded.asset_path, bytes = excluded.bytes,
    duration_s = excluded.duration_s, width = excluded.width, height = excluded.height, aspect = excluded.aspect,
    fps = excluded.fps, scene_cuts = excluded.scene_cuts, cuts_per_10s = excluded.cuts_per_10s,
    hook_cuts_first_3s = excluded.hook_cuts_first_3s, hook_motion_first_3s = excluded.hook_motion_first_3s,
    audio_present = excluded.audio_present, loudness_lufs = excluded.loudness_lufs, true_peak_db = excluded.true_peak_db,
    speech_band_ratio = excluded.speech_band_ratio, voiceover_suspected = excluded.voiceover_suspected,
    frames_with_text = excluded.frames_with_text, frames_sampled = excluded.frames_sampled,
    text_chars_per_frame = excluded.text_chars_per_frame, keyframes = excluded.keyframes, music = excluded.music,
    toolchain = excluded.toolchain, measured_at = now();
  return jsonb_build_object('ok', true, 'file_sha256', p->>'file_sha256');
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_assets_cited(p_evidence jsonb)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(array_agg(distinct sha) filter (where sha is not null), '{}')
    from (select case e->>'kind'
                   when 'asset_feature' then e->>'ref'
                   when 'asset_review' then (select file_sha256 from public.marketing_asset_review where id::text = e->>'ref')
                   when 'asset_perception' then (select file_sha256 from public.marketing_asset_perception where id::text = e->>'ref')
                   when 'post_metric' then 'post:' || (e->>'ref') end sha
            from jsonb_array_elements(coalesce(p_evidence, '[]'::jsonb)) e) x
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_assist(p_text text, p_embedding vector DEFAULT NULL::vector, p_min_similarity numeric DEFAULT 0.83, p_min_rank numeric DEFAULT 0.05, p_k integer DEFAULT 5, p_min_overlap numeric DEFAULT 0.60)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_k int := greatest(1, least(coalesce(p_k, 5), 20)); v_wide int := greatest(v_k * 4, 20);
  c_lex_only numeric := greatest(0.20, coalesce(p_min_rank, 0));
  v_tq tsquery; v_lex text[]; v_nlex int; v_need int; v_records jsonb; v_cited text[];
begin
  if coalesce(btrim(p_text), '') = '' then
    return jsonb_build_object('company', public.fn_company_context(), 'ok', false, 'answered', false, 'refusal', 'empty_query');
  end if;
  v_tq := websearch_to_tsquery('english', p_text);
  select array_agg(distinct u.lexeme) into v_lex from unnest(to_tsvector('english', p_text)) u;
  v_nlex := coalesce(cardinality(v_lex), 0);
  v_need := case when v_nlex = 0 then 2147483647
                 else greatest(least(2, v_nlex), ceil(coalesce(p_min_overlap, 0.60) * v_nlex)::int) end;

  with cand as (
    select o.record_id, o.title, left(o.content, 4000) content, o.module, o.layer,
           (1 - (o.embedding_gte <=> p_embedding))::numeric sim,
           coalesce(ts_rank(o.tsv, v_tq), 0)::numeric * (case when o.tsv @@ v_tq then 1 else 0 end) rnk,
           (select count(*) from unnest(o.tsv) u where u.lexeme = any (v_lex))::int hits, true has_vec
      from public.ops_knowledge o
     where p_embedding is not null and o.embedding_gte is not null
       and coalesce(o.supersession_state, 'current') = 'current'
     order by o.embedding_gte <=> p_embedding limit v_wide
  ), lex as (
    select o.record_id, o.title, left(o.content, 4000) content, o.module, o.layer,
           null::numeric sim, ts_rank(o.tsv, v_tq)::numeric rnk, 0 hits, false has_vec
      from public.ops_knowledge o
     where o.tsv @@ v_tq and coalesce(o.supersession_state, 'current') = 'current'
       and not exists (select 1 from cand c where c.record_id = o.record_id)
     order by ts_rank(o.tsv, v_tq) desc limit v_wide
  ), judged as (
    select x.*, case when x.has_vec then x.sim >= p_min_similarity and (x.rnk >= p_min_rank or x.hits >= v_need)
                     else x.rnk >= c_lex_only end ok
      from (select * from cand union all select * from lex) x
  ), top as (
    select j.* from judged j where j.ok order by j.has_vec desc, j.sim desc nulls last, j.rnk desc limit v_k
  )
  select coalesce(jsonb_agg(jsonb_build_object('corpus', 'ops_knowledge', 'record_id', t.record_id, 'title', t.title,
                                               'provenance', coalesce(t.module, '') || coalesce(' · ' || t.layer, ''),
                                               'similarity', round(t.sim, 4), 'lexical_rank', round(t.rnk, 4),
                                               'route', case when t.has_vec then 'vector+lexical' else 'lexical_only' end,
                                               'content', t.content)), '[]'::jsonb),
         coalesce(array_agg('ops_knowledge:' || t.record_id), '{}')
    into v_records, v_cited from top t;

  return jsonb_build_object('company', public.fn_company_context(), 'ok', true, 'answered', cardinality(v_cited) > 0,
    'records', v_records, 'cited', v_cited, 'corpora', jsonb_build_array('ops_knowledge'),
    'floor', jsonb_build_object('min_similarity', p_min_similarity, 'min_rank', p_min_rank, 'lexical_only', c_lex_only,
                                'lexeme_overlap_needed', v_need, 'vector_route', p_embedding is not null),
    'refusal', case when cardinality(v_cited) = 0 then 'no_sourced_answer' end,
    'handoff', case when cardinality(v_cited) = 0 then
      'No sourced answer in company knowledge. Reply with the standard holding line and do not state a fee, date or policy; '
      || 'if the person asks for someone, hand the conversation to the founder (fn_marketing_asks_the_founder_to_take_over).' end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_blog_draft_due()
 RETURNS TABLE(topic_id bigint, kind text, title text, trade text, evidence jsonb, sources jsonb, lessons jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select t.id, t.kind, t.title, t.trade, t.evidence, t.sources, t.lessons
    from public.marketing_blog_topic t
   where t.status = 'picked' and not exists (select 1 from public.marketing_article a where a.topic_id = t.id)
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_blog_publish(p_id uuid, p_published boolean, p_by text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare r public.blog_posts%rowtype;
begin
  update public.blog_posts set published = p_published,
    published_at = case when p_published and published_at is null then now() else published_at end,
    updated_at = now()
  where id = p_id returning * into r;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  begin insert into public.os_audit_log(actor, action, entity, entity_id, detail)
    values (coalesce(nullif(btrim(p_by),''),'operator'), case when p_published then 'blog_publish' else 'blog_unpublish' end, 'blog_posts', p_id::text, jsonb_build_object('title', r.title));
  exception when others then null; end;
  return jsonb_build_object('ok', true, 'published', r.published);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_blog_review(p_round_id bigint, p_decision text, p_reasons jsonb, p_model text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.marketing_article_round; v_slug text; v_out jsonb;
begin
  select * into r from public.marketing_article_round where id = p_round_id for update;
  if r.id is null or r.decision is not null then return jsonb_build_object('ok', false, 'error', 'not_awaiting_review'); end if;
  update public.marketing_article_round
     set decision = p_decision, reasons = p_reasons, reviewed_by_model = nullif(p_model, ''), reviewed_at = now()
   where id = r.id;
  if p_decision = 'approve' then
    select slug into v_slug from public.marketing_article where id = r.article_id;
    v_out := public.fn_marketing_article_approve(v_slug, 'ceo');
    if not coalesce((v_out->>'ok')::boolean, false) then raise exception 'the CEO''s approval was refused: %', v_out; end if;
  elsif p_decision = 'replace_topic' then
    v_out := public.fn_marketing_blog_topic_replace(r.topic_id, 'the CEO replaced the topic at round ' || r.round || ': '
      || (select string_agg(k.key || ' - ' || (k.value->>'reason'), '; ' order by k.key) from jsonb_each(p_reasons) k where k.value->>'verdict' = 'fail'));
  end if;
  return jsonb_build_object('ok', true, 'round', r.round, 'article_id', r.article_id, 'decision', p_decision, 'then', v_out);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_blog_review_due()
 RETURNS TABLE(round_id bigint, article_id bigint, slug text, round integer, version jsonb, drafted_by_model text, changes jsonb, topic jsonb, history jsonb, revise_rounds integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select r.id, r.article_id, a.slug, r.round, r.version, r.drafted_by_model, r.changes,
         jsonb_build_object('title', t.title, 'kind', t.kind, 'evidence', t.evidence, 'sources', t.sources),
         (select coalesce(jsonb_agg(jsonb_build_object('round', p.round, 'decision', p.decision, 'reasons', p.reasons,
                                                       'changes', p.changes) order by p.round), '[]'::jsonb)
            from public.marketing_article_round p where p.article_id = r.article_id and p.round < r.round),
         (select count(*) from public.marketing_article_round p where p.topic_id = r.topic_id and p.decision = 'revise')::int
    from public.marketing_article_round r
    join public.marketing_article a on a.id = r.article_id
    join public.marketing_blog_topic t on t.id = r.topic_id
   where r.decision is null and a.status = 'draft' and t.status = 'picked'
   order by r.created_at, r.id
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_blog_revise_due()
 RETURNS TABLE(article_id bigint, topic_id bigint, slug text, round integer, version jsonb, reasons jsonb, sources jsonb, history jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select r.article_id, r.topic_id, a.slug, r.round, r.version, r.reasons, t.sources,
         (select coalesce(jsonb_agg(jsonb_build_object('round', p.round, 'reasons', p.reasons, 'changes', p.changes) order by p.round), '[]'::jsonb)
            from public.marketing_article_round p where p.article_id = r.article_id and p.round < r.round)
    from public.marketing_article_round r
    join public.marketing_article a on a.id = r.article_id
    join public.marketing_blog_topic t on t.id = r.topic_id
   where r.decision = 'revise' and a.status = 'draft' and t.status = 'picked'
     and r.round = (select max(q.round) from public.marketing_article_round q where q.article_id = r.article_id)
   order by r.reviewed_at, r.id
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_blog_submit(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t public.marketing_blog_topic; a public.marketing_article; v_prev public.marketing_article_round;
  v_all text; v_head text; v_name text; v_slug text; v_round int; v_ing jsonb;
begin
  select * into t from public.marketing_blog_topic where id = (p->>'topic_id')::bigint for update;
  if t.id is null or t.status <> 'picked' then return jsonb_build_object('ok', false, 'error', 'topic_not_open'); end if;
  v_head := lower(concat_ws(' ', p#>>'{en,title}', p#>>'{en,excerpt}', p#>>'{en,meta_desc}',
                                 p#>>'{ar,title}', p#>>'{ar,excerpt}', p#>>'{ar,meta_desc}'));
  -- the brand is written QuotesDone in Latin letters in both languages (docs/marketing/writing_style.md)
  if v_head ~ 'quotes ?done' then
    return jsonb_build_object('ok', false, 'error', 'about_quotesdone', 'detail', 'a blog is a market topic: its title, excerpt and description do not name QuotesDone');
  end if;
  v_all := lower(concat_ws(' ', p#>>'{en,title}', p#>>'{en,excerpt}', p#>>'{en,meta_desc}', p#>>'{en,body_html}',
                                p#>>'{ar,title}', p#>>'{ar,excerpt}', p#>>'{ar,meta_desc}', p#>>'{ar,body_html}'));
  -- a supplier is any company in the invited pool: a full name of two or more words (a single word is too common to be a name)
  select btrim(l.company_name) into v_name from public.leads l
   where length(btrim(l.company_name)) >= 8 and btrim(l.company_name) ~ '\s'
     and strpos(v_all, lower(btrim(l.company_name))) > 0
   limit 1;
  if v_name is not null then
    return jsonb_build_object('ok', false, 'error', 'names_a_supplier', 'detail', 'the article names "' || v_name || '"; a blog never names a supplier');
  end if;
  select * into a from public.marketing_article where topic_id = t.id and status = 'draft' for update;
  if a.id is null then
    if exists (select 1 from public.marketing_article where topic_id = t.id) then
      return jsonb_build_object('ok', false, 'error', 'topic_article_closed');
    end if;
    v_round := 1; v_slug := lower(btrim(coalesce(p->>'slug', '')));
    -- fn_marketing_article_ingest overwrites a DRAFT with the same slug: a new topic never takes another article over
    if exists (select 1 from public.marketing_article where slug = v_slug) then
      return jsonb_build_object('ok', false, 'error', 'slug_taken', 'detail', 'the slug ' || v_slug || ' belongs to another article; choose another title');
    end if;
  else
    select * into v_prev from public.marketing_article_round where article_id = a.id order by round desc limit 1;
    if v_prev.decision is distinct from 'revise' then
      return jsonb_build_object('ok', false, 'error', 'not_awaiting_a_revision', 'round', v_prev.round, 'decision', v_prev.decision);
    end if;
    v_round := v_prev.round + 1; v_slug := a.slug;
  end if;
  v_ing := public.fn_marketing_article_ingest(jsonb_build_object('slug', v_slug, 'kind', 'market_topic', 'ingested_by', 'claude',
             'is_demo', coalesce((p->>'is_demo')::boolean, false), 'en', p->'en', 'ar', p->'ar', 'sources', t.sources,
             'checks', jsonb_build_object('lint', '[]'::jsonb, 'ungrounded', '[]'::jsonb), 'post', p->'post'));
  if not coalesce((v_ing->>'ok')::boolean, false) or coalesce((v_ing->>'unchanged')::boolean, false) then
    return v_ing || jsonb_build_object('ok', false);
  end if;
  update public.marketing_article set topic_id = t.id where id = (v_ing->>'id')::bigint returning * into a;
  insert into public.marketing_article_round (article_id, topic_id, round, version, fingerprint, drafted_by_model, changes)
  values (a.id, t.id, v_round, jsonb_build_object('en', p->'en', 'ar', p->'ar'), public.fn_marketing_article_fingerprint(a.id),
          nullif(p->>'model', ''), case when v_round > 1 then coalesce(p->'changes', '[]'::jsonb) end);
  return jsonb_build_object('ok', true, 'article_id', a.id, 'slug', a.slug, 'round', v_round);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_blog_topic_candidates()
 RETURNS TABLE(topic_key text, kind text, title text, trade text, score numeric, evidence jsonb, sources jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with used as (
    select t.topic_key from public.marketing_blog_topic t where t.status = 'published' or t.picked_at > now() - interval '90 days'
  ), c as (
    -- what the seat judged relevant among the searches and news of the last 21 days (a search interest first)
    select 'trend:' || m.id as topic_key, s.kind, m.title, null::text as trade,
           (case s.kind when 'search' then 10 when 'regulation' then 8 else 6 end)
             + round((greatest(0, 21 - extract(epoch from now() - coalesce(m.published_at, m.seen_at)) / 86400) / 7)::numeric, 2) as score,
           jsonb_build_array(jsonb_build_object('kind', s.kind, 'source', s.name, 'title', m.title, 'url', m.url,
             'published_at', m.published_at, 'why_it_matters', m.why_it_matters)) as evidence,
           jsonb_build_array(jsonb_build_object('ref', 'trend:' || m.id, 'url', m.url, 'title', m.title,
             'text', m.title || '. ' || coalesce(m.why_it_matters, ''))) as sources
      from public.marketing_trend m join public.marketing_trend_source s on s.id = m.source_id
     where m.relevant and coalesce(m.published_at, m.seen_at) > now() - interval '21 days'
    union all
    -- the trades buyers asked for in 90 days (never a demo customer), grounded in the trade's verified knowledge
    select 'demand:' || d.trade, 'demand', coalesce(tt.label, d.trade), d.trade, (4 + 2 * d.asked)::numeric,
           jsonb_build_array(jsonb_build_object('kind', 'demand', 'trade', d.trade, 'inquiries_90d', d.asked)),
           k.sources
      from (select x.trade, count(*) as asked
              from public.inquiries i
              left join public.customers cu on cu.id = i.customer_id
              cross join lateral unnest(i.trades) x(trade)
             where i.created_at > now() - interval '90 days'
               and not coalesce(cu.is_demo, false) and coalesce(cu.email, '') !~* '@example\.invalid$'
             group by x.trade) d
      left join public.taxonomy_trade tt on tt.code = d.trade
      cross join lateral (
        select jsonb_agg(jsonb_build_object('ref', sk.record_id, 'url', sk.source_ids[1], 'title', sk.title,
                                            'text', left(sk.content, 3000))) as sources, count(*) as n
          from (select * from public.sales_knowledge k2
                 where ('trade:' || d.trade) = any(k2.tags) and 'verified_pack' = any(k2.tags) and 'lang:en' = any(k2.tags)
                   and coalesce(array_length(k2.source_ids, 1), 0) > 0
                 order by k2.record_id limit 6) sk) k
     where k.n >= 3
  )
  select c.* from c where c.topic_key not in (select u.topic_key from used u)
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_blog_topic_pick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c record; v_considered jsonb; v_lessons jsonb; v_id bigint;
begin
  if exists (select 1 from public.marketing_blog_topic where status = 'picked') then
    return jsonb_build_object('picked', null, 'reason', 'a topic is open');
  end if;
  if exists (select 1 from public.marketing_article where kind = 'market_topic' and status in ('approved', 'released') and not is_demo) then
    return jsonb_build_object('picked', null, 'reason', 'an approved article waits for its release');
  end if;
  select * into c from public.fn_marketing_blog_topic_candidates() order by score desc, topic_key limit 1;
  if c.topic_key is null then
    return jsonb_build_object('picked', null, 'reason', 'no candidate: no relevant search or news in 21 days and no trade asked for in 90 days');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('topic_key', x.topic_key, 'title', x.title, 'score', x.score) order by x.score desc), '[]'::jsonb)
    into v_considered
    from (select * from public.fn_marketing_blog_topic_candidates() where topic_key <> c.topic_key order by score desc, topic_key limit 5) x;
  select coalesce(jsonb_agg(l.v order by l.at desc), '[]'::jsonb) into v_lessons
    from (select e.v, t.closed_at as at from public.marketing_blog_topic t, jsonb_array_elements(t.learned) e(v)
           where t.status = 'replaced' order by t.closed_at desc limit 20) l;
  insert into public.marketing_blog_topic (topic_key, kind, title, trade, score, evidence, sources, considered, lessons)
  values (c.topic_key, c.kind, c.title, c.trade, c.score, c.evidence, c.sources, v_considered, v_lessons)
  returning id into v_id;
  return jsonb_build_object('picked', v_id, 'topic_key', c.topic_key, 'title', c.title, 'score', c.score);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_blog_topic_replace(p_topic_id bigint, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_learned jsonb;
begin
  if btrim(coalesce(p_reason, '')) = '' then raise exception 'a topic is replaced with its reason'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('round', r.round, 'criterion', k.key, 'reason', k.value->>'reason')
                            order by r.round, k.key), '[]'::jsonb)
    into v_learned
    from public.marketing_article_round r cross join lateral jsonb_each(r.reasons) k
   where r.topic_id = p_topic_id and k.value->>'verdict' = 'fail';
  update public.marketing_blog_topic
     set status = 'replaced', replaced_reason = left(p_reason, 2000), closed_at = now(),
         learned = v_learned || jsonb_build_array(jsonb_build_object('criterion', 'topic', 'reason', left(p_reason, 1000)))
   where id = p_topic_id and status = 'picked';
  if not found then return jsonb_build_object('replaced', false, 'reason', 'not an open topic'); end if;
  update public.marketing_article set status = 'withdrawn', withdrawn_reason = left('topic replaced: ' || p_reason, 2000),
         withdrawn_at = now(), updated_at = now()
   where topic_id = p_topic_id and status = 'draft';
  return jsonb_build_object('replaced', true, 'next', public.fn_marketing_blog_topic_pick());
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_calendar_due()
 RETURNS TABLE(campaign_key text, current_hash text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record;
begin
  for r in select c.id, c.campaign_key ck from public.marketing_campaign c where not c.is_demo order by c.id loop
    if public.fn_marketing_calendar_resend_decide(r.id) = 'due' then
      campaign_key := r.ck; current_hash := public.fn_marketing_campaign_hash(r.id); return next;
    end if;
  end loop;
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_calendar_load(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  cj jsonb := p->'campaign'; r jsonb; v_cid bigint; v_key text; v_pid bigint; v_status text;
  v_platform text; v_utc timestamptz; v_local timestamp; v_video text; v_frame text; v_type text; v_lang text;
  v_tags text[]; v_bi text; v_seqs int[]; v_keys text[] := '{}'; v_ins int := 0; v_upd int := 0; v_same int := 0;
  v_skip int := 0; v_n int; v_probe public.marketing_post_variant; v_probs text[];
  v_title text; v_en text; v_ar text; v_demo boolean; v_cap text; v_vlang text;
begin
  if coalesce(cj->>'key', '') !~ '^[a-z0-9][a-z0-9-]{2,80}$' then raise exception 'calendar: campaign.key is missing or malformed'; end if;
  if coalesce(cj->>'month', '') !~ '^\d{4}-\d{2}$' then raise exception 'calendar: campaign.month must be YYYY-MM'; end if;
  if jsonb_typeof(p->'posts') is distinct from 'array' or jsonb_array_length(p->'posts') = 0 then raise exception 'calendar: no posts'; end if;
  v_demo := coalesce((cj->>'is_demo')::boolean, false);

  insert into public.marketing_campaign as t (campaign_key, theme, title, month, is_demo)
  values (cj->>'key', cj->>'theme', nullif(btrim(cj->>'title'), ''), (cj->>'month' || '-01')::date, v_demo)
  on conflict (campaign_key) do update set theme = excluded.theme, title = excluded.title, month = excluded.month,
         is_demo = excluded.is_demo, updated_at = now()
   where (t.theme, t.title, t.month, t.is_demo) is distinct from (excluded.theme, excluded.title, excluded.month, excluded.is_demo);
  select id into v_cid from public.marketing_campaign where campaign_key = cj->>'key';

  for r in select * from jsonb_array_elements(p->'posts') loop
    v_key := lower(btrim(coalesce(r->>'key', '')));
    if v_key !~ '^[a-z0-9][a-z0-9_-]{2,80}$' then raise exception 'calendar: post key % is malformed', r->>'key'; end if;
    if v_key = any (v_keys) then raise exception 'calendar: post key % appears twice', v_key; end if;
    v_keys := v_keys || v_key;
    v_platform := r->>'platform';
    if v_platform is null or v_platform not in ('facebook', 'instagram', 'linkedin', 'x', 'youtube', 'tiktok') then
      raise exception 'calendar %: platform % is not one of facebook, instagram, linkedin, x, youtube, tiktok', v_key, v_platform;
    end if;
    -- The two clocks must agree: Dubai is UTC+4 all year.
    v_utc := (r->>'at_utc')::timestamptz; v_local := (r->>'at_dubai')::timestamp;
    if v_utc is null or v_local is null or v_local <> (v_utc at time zone 'Asia/Dubai') then
      raise exception 'calendar %: at_dubai % is not at_utc % in Asia/Dubai', v_key, r->>'at_dubai', r->>'at_utc';
    end if;
    v_video := regexp_replace(coalesce(r#>>'{video,path}', ''), '^marketing-media/', '');
    v_frame := regexp_replace(coalesce(r#>>'{keyframe,path}', ''), '^marketing-media/', '');
    if v_video !~ ('^campaigns/' || (cj->>'key') || '/videos/[A-Za-z0-9._-]+\.mp4$') then
      raise exception 'calendar %: video.path % is not campaigns/%/videos/<name>.mp4', v_key, v_video, cj->>'key';
    end if;
    if v_frame !~ ('^campaigns/' || (cj->>'key') || '/(frames|videos)/[A-Za-z0-9._-]+\.(jpg|jpeg|png)$') then
      raise exception 'calendar %: keyframe.path % is not a jpg/png under campaigns/%/frames/', v_key, v_frame, cj->>'key';
    end if;
    if coalesce(r#>>'{video,sha256}', '') !~ '^[0-9a-f]{64}$' or coalesce(r#>>'{keyframe,sha256}', '') !~ '^[0-9a-f]{64}$' then
      raise exception 'calendar %: video.sha256 and keyframe.sha256 are required (64 lowercase hex)', v_key;
    end if;
    if not exists (select 1 from storage.objects o where o.bucket_id = 'marketing-media' and o.name = v_video)
       or not exists (select 1 from storage.objects o where o.bucket_id = 'marketing-media' and o.name = v_frame) then
      raise exception 'calendar %: % or % is not in the private marketing-media bucket', v_key, v_video, v_frame;
    end if;
    v_en := btrim(coalesce(r->>'caption_en', '')); v_ar := btrim(coalesce(r->>'caption_ar', ''));
    -- ENGLISH ONLY ON SOCIAL (founder, 23 Sep 2026): caption_en is required; caption_ar is optional and, when
    -- given, must be Arabic (question marks refused). An absent Arabic caption stores NULL, never ''.
    if v_en = '' then raise exception 'calendar %: caption_en is required', v_key; end if;
    if v_ar <> '' and v_ar !~ '[؀-ۿ]' then raise exception 'calendar %: caption_ar is given but is not Arabic', v_key; end if;
    v_title := coalesce(nullif(btrim(r->>'title'), ''), nullif(btrim(r#>>'{video,title}'), ''));
    if v_title is null then raise exception 'calendar %: video.title is required', v_key; end if;
    v_tags := coalesce((select array_agg(regexp_replace(btrim(x), '^#', '') order by n) from jsonb_array_elements_text(coalesce(r->'hashtags', '[]')) with ordinality h(x, n)), '{}');
    -- a video is a reel on Instagram and Facebook, a Short on YouTube, a video on LinkedIn and X
    v_type := coalesce(r->>'post_type', case v_platform when 'youtube' then 'short' when 'instagram' then 'reel'
                                                        when 'facebook' then 'reel' else 'video' end);

    -- the post
    select id, status into v_pid, v_status from public.marketing_post where ingest_key = v_key for update;
    if found and v_status not in ('draft', 'scheduled', 'failed') then v_skip := v_skip + 1; continue; end if;
    if found and exists (select 1 from public.marketing_post where id = v_pid and campaign_id is distinct from v_cid) then
      raise exception 'calendar %: this key belongs to another campaign', v_key;
    end if;
    insert into public.marketing_post as t (ingest_key, ingested_by, title, text_en, text_ar, media_paths, channels, scheduled_at,
                                            scheduled_local, status, is_demo, campaign_id, video_path, video_sha256, cover_path,
                                            cover_sha256, cta_url, rationale, music)
    values (v_key, 'claude', v_title, v_en, nullif(v_ar, ''), array[v_video], array[v_platform], v_utc, v_local, 'scheduled', v_demo, v_cid,
            v_video, r#>>'{video,sha256}', v_frame, r#>>'{keyframe,sha256}', nullif(btrim(r->>'cta_url'), ''),
            nullif(btrim(r->>'rationale'), ''), r->'music')
    on conflict (ingest_key) do update set title = excluded.title, text_en = excluded.text_en, text_ar = excluded.text_ar,
           media_paths = excluded.media_paths, channels = excluded.channels, scheduled_at = excluded.scheduled_at,
           scheduled_local = excluded.scheduled_local, status = 'scheduled', is_demo = excluded.is_demo,
           video_path = excluded.video_path, video_sha256 = excluded.video_sha256, cover_path = excluded.cover_path,
           cover_sha256 = excluded.cover_sha256, cta_url = excluded.cta_url, rationale = excluded.rationale,
           music = excluded.music, dry_run = null, error = null, updated_at = now()
     where (t.title, t.text_en, t.text_ar, t.media_paths, t.channels, t.scheduled_at, t.scheduled_local, t.status, t.is_demo,
            t.video_path, t.video_sha256, t.cover_path, t.cover_sha256, t.cta_url, t.rationale, t.music)
       is distinct from
           (excluded.title, excluded.text_en, excluded.text_ar, excluded.media_paths, excluded.channels, excluded.scheduled_at,
            excluded.scheduled_local, 'scheduled'::text, excluded.is_demo, excluded.video_path, excluded.video_sha256,
            excluded.cover_path, excluded.cover_sha256, excluded.cta_url, excluded.rationale, excluded.music);
    get diagnostics v_n = row_count;
    if v_pid is null then v_ins := v_ins + 1; elsif v_n > 0 then v_upd := v_upd + 1; else v_same := v_same + 1; end if;
    select id into v_pid from public.marketing_post where ingest_key = v_key;

    -- the variants: EN+AR in one post where the platform spec says it fits; on X a thread (EN, then AR) when not
    v_bi := case when v_ar = '' then v_en else v_en || E'\n\n' || v_ar end;
    v_lang := coalesce(r->>'language', case when v_ar = '' then 'en' end);
    if v_lang in ('ar', 'bi', 'thread') and v_ar = '' then raise exception 'calendar %: language % needs caption_ar', v_key, v_lang; end if;
    if v_lang is null then
      v_probe := row(null, v_pid, v_platform, 1, 'bi', v_type, v_bi, v_tags, public.fn_marketing_variant_text(v_bi, v_tags),
                     nullif(btrim(r->>'alt_text'), ''), case when v_platform = 'youtube' then v_title end,
                     nullif(btrim(r->>'first_comment'), ''), v_frame, now(), now())::public.marketing_post_variant;
      v_probs := public.fn_marketing_variant_problems(v_probe);
      v_lang := case when coalesce(cardinality(v_probs), 0) = 0 then 'bi' when v_platform = 'x' then 'thread' else 'bi' end;
    end if;
    v_seqs := '{}';
    for v_n, v_cap, v_vlang in
      select * from (values (1, case when v_lang = 'ar' then v_ar when v_lang in ('en', 'thread') then v_en else v_bi end,
                                case when v_lang = 'thread' then 'en' else v_lang end),
                            (2, v_ar, 'ar')) s(seq, cap, lang)
       where s.seq = 1 or v_lang = 'thread'
    loop
      insert into public.marketing_post_variant as t (post_id, platform, seq, language, post_type, caption, hashtags, alt_text,
                                                      title, first_comment, cover_path)
      values (v_pid, v_platform, v_n, v_vlang, v_type, v_cap, case when v_n = 1 then v_tags else '{}' end,
              nullif(btrim(r->>'alt_text'), ''), case when v_platform = 'youtube' then v_title end,
              case when v_n = 1 then nullif(btrim(r->>'first_comment'), '') end, v_frame)
      on conflict (post_id, platform, seq) do update set language = excluded.language, post_type = excluded.post_type,
             caption = excluded.caption, hashtags = excluded.hashtags, alt_text = excluded.alt_text, title = excluded.title,
             first_comment = excluded.first_comment, cover_path = excluded.cover_path, updated_at = now()
       where (t.language, t.post_type, t.caption, t.hashtags, t.alt_text, t.title, t.first_comment, t.cover_path)
             is distinct from (excluded.language, excluded.post_type, excluded.caption, excluded.hashtags, excluded.alt_text,
                               excluded.title, excluded.first_comment, excluded.cover_path);
      v_seqs := v_seqs || v_n;
    end loop;
    delete from public.marketing_post_variant where post_id = v_pid and not (seq = any (v_seqs) and platform = v_platform);
    -- a variant the platform spec refuses stops the whole month here, not at publish time
    for v_probe in select * from public.marketing_post_variant where post_id = v_pid loop
      v_probs := public.fn_marketing_variant_problems(v_probe);
      if cardinality(v_probs) > 0 then
        raise exception 'calendar %: % seq % breaks the platform spec: %', v_key, v_probe.platform, v_probe.seq, array_to_string(v_probs, '; ');
      end if;
    end loop;
  end loop;

  -- a post that left the calendar leaves the month (kept as history, never published)
  update public.marketing_post set status = 'cancelled', updated_at = now()
   where campaign_id = v_cid and status in ('draft', 'scheduled', 'failed') and not (ingest_key = any (v_keys));
  get diagnostics v_n = row_count;

  return jsonb_build_object('ok', true, 'campaign_key', cj->>'key', 'campaign_id', v_cid, 'inserted', v_ins, 'updated', v_upd,
    'unchanged', v_same, 'already_sent_not_touched', v_skip, 'cancelled_as_removed', v_n,
    'state', public.fn_marketing_campaign_state(cj->>'key'));
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_calendar_reply(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c public.marketing_campaign; v_from text := lower(btrim(coalesce(p->>'from_email', '')));
  v_now text; v_st jsonb; v_out text; v_msg text; v_subj text; v_nid bigint; v_last timestamptz; v_rid bigint;
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
      v_msg := 'Nothing was approved yet. Your change request was passed to the marketing seat (request ' || v_rid || '):' || E'\n\n'
               || left(v_text, 1500) || E'\n\n'
               || 'The corrected calendar will be emailed to you for approval; reply "approve" to that one and it is scheduled and published.';
    elsif c.calendar_hash is distinct from v_now then
      v_out := 'edited_after_sending';
      v_msg := 'The social calendar was changed after we emailed it to you, so this approval would not match what will be posted. Nothing was approved; the updated calendar is being emailed to you now. Please reply "approve" to that one.';
    elsif coalesce(p->>'intent', '') <> 'approve' then
      v_out := 'unclear';
      v_msg := 'Your reply had no text of its own, so nothing was approved. To approve the calendar exactly as sent, reply with the single word "approve" (or "موافق"). To change something, reply saying what.';
    else
      update public.marketing_campaign set approved_by = 'founder', approved_at = now(), approved_hash = v_now,
             approved_message_id = coalesce(nullif(p->>'message_id', ''), 'unknown'), updated_at = now()
       where id = c.id;
      v_st := public.fn_marketing_campaign_state(c.campaign_key);
      v_out := 'approved';
      v_msg := 'Approved — ' || (v_st->>'posts') || ' posts scheduled and publishing from '
               || to_char(((v_st->>'first_post_at')::timestamptz at time zone 'Asia/Dubai'), 'FMDay DD FMMonth YYYY, HH24:MI') || ' (Dubai), '
               || 'on UAE working days only. They go out exactly as in the calendar you approved (content reference ' || left(v_now, 12) || ').'
               || case when not public.fn_marketing_publishing_on()
                       then ' NOTE: the emergency stop is on (marketing_publishing_enabled = false); nothing posts until it is lifted.' else '' end;
    end if;
  end if;
  v_subj := case v_out when 'approved' then 'Approved: ' when 'change_requested' then 'Change request received: ' else 'Not approved: ' end
            || 'social calendar' || coalesce(' — ' || c.title, '');
  v_nid := public.fn_marketing_mail_founder('marketing_calendar_reply', left(v_subj, 200), v_msg);
  return jsonb_build_object('outcome', v_out, 'approved', v_out = 'approved', 'campaign_key', c.campaign_key,
                            'request_id', v_rid, 'reply_notification_id', v_nid);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_calendar_resend_decide(p_campaign_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c public.marketing_campaign; v_hash text; v_last_post timestamptz; v_edit timestamptz; v_dec text;
        v_prev public.marketing_calendar_resend_decision;
begin
  select * into c from public.marketing_campaign where id = p_campaign_id;
  if not found then return null; end if;
  v_hash := public.fn_marketing_campaign_hash(c.id);
  select max(p.scheduled_at) into v_last_post from public.marketing_post p where p.campaign_id = c.id and p.status <> 'cancelled';
  v_edit := greatest(c.updated_at,
                     (select max(p.content_edited_at) from public.marketing_post p where p.campaign_id = c.id),
                     (select max(v.updated_at) from public.marketing_post_variant v join public.marketing_post p on p.id = v.post_id
                       where p.campaign_id = c.id));
  v_dec := case when v_last_post is null or now() >= v_last_post then 'finished'
                when v_hash is not distinct from c.approved_hash then 'already_approved'
                when v_hash is not distinct from c.calendar_hash then 'already_sent'
                when v_edit >= now() - interval '30 minutes' then 'quiet_period'
                else 'due' end;
  select * into v_prev from public.marketing_calendar_resend_decision d where d.campaign_id = c.id order by d.id desc limit 1;
  -- a campaign that was over before this log existed is not written; every other change is
  if (v_prev.id is null and v_dec <> 'finished')
     or (v_prev.id is not null and (v_prev.decision, v_prev.current_hash) is distinct from (v_dec, v_hash)) then
    insert into public.marketing_calendar_resend_decision (campaign_id, decision, current_hash, last_edit_at, due_at)
    values (c.id, v_dec, v_hash, v_edit, v_edit + interval '30 minutes');
  end if;
  return v_dec;
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_calendar_sent(p_campaign_key text, p_hash text, p_pdf_path text, p_xlsx_path text, p_subject text, p_body text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c public.marketing_campaign; v_token text := encode(extensions.gen_random_bytes(16), 'hex'); v_nid bigint; v_att jsonb;
begin
  select * into c from public.marketing_campaign where campaign_key = p_campaign_key for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'no_such_campaign'); end if;
  if c.is_demo then return jsonb_build_object('ok', false, 'error', 'demo_campaign_never_mailed'); end if;
  if p_hash is distinct from public.fn_marketing_campaign_hash(c.id) then
    return jsonb_build_object('ok', false, 'error', 'content_changed_while_rendering', 'message', 'Render the calendar again.');
  end if;
  v_att := jsonb_build_array(
    jsonb_build_object('bucket', 'agent-docs', 'path', p_pdf_path, 'filename', 'QuotesDone social calendar ' || to_char(c.month, 'YYYY-MM') || '.pdf'))
    || case when p_xlsx_path is null then '[]'::jsonb else jsonb_build_array(
    jsonb_build_object('bucket', 'agent-docs', 'path', p_xlsx_path, 'filename', 'QuotesDone social calendar ' || to_char(c.month, 'YYYY-MM') || '.xlsx')) end;
  v_nid := public.fn_marketing_mail_founder('marketing_calendar',
    left(p_subject, 200) || ' [ref ' || v_token || ']', p_body, v_att, 'calendar+' || v_token || '@mail.quotesdone.com');
  update public.marketing_campaign
     set calendar_pdf_path = p_pdf_path, calendar_xlsx_path = p_xlsx_path, calendar_hash = p_hash, calendar_token = v_token,
         calendar_sent_at = now(), calendar_notification_id = v_nid,
         -- an approval of OLDER content is already void (the gate compares hashes); clear it so the record says so
         approved_by = case when approved_hash = p_hash then approved_by end,
         approved_at = case when approved_hash = p_hash then approved_at end,
         approved_message_id = case when approved_hash = p_hash then approved_message_id end,
         approved_hash = case when approved_hash = p_hash then approved_hash end,
         updated_at = now()
   where id = c.id;
  return jsonb_build_object('ok', true, 'notification_id', v_nid, 'hash', p_hash);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_campaign_hash(p_campaign_id bigint)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select encode(sha256(convert_to(
    (select c.campaign_key || chr(31) || c.spend_policy from public.marketing_campaign c where c.id = p_campaign_id)
    || chr(30) || coalesce((
      select string_agg(concat_ws(chr(31), p.ingest_key, to_char(p.scheduled_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
               array_to_string(p.channels, ','), p.video_path, p.video_sha256, p.cover_path, p.cover_sha256,
               array_to_string(p.media_paths, ','), p.cta_url, p.is_demo::text,
               (select string_agg(concat_ws(chr(31), v.platform, v.seq::text, v.language, v.post_type, v.body, v.title,
                                            v.alt_text, v.first_comment, v.cover_path), chr(29) order by v.platform, v.seq)
                  from public.marketing_post_variant v where v.post_id = p.id)), chr(30) order by p.scheduled_at, p.ingest_key)
        from public.marketing_post p where p.campaign_id = p_campaign_id and p.status <> 'cancelled'), ''),
    'UTF8')), 'hex')
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_campaign_state(p_campaign_key text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object('campaign_key', c.campaign_key, 'theme', c.theme, 'month', c.month, 'spend_policy', c.spend_policy,
           'current_hash', h.v, 'calendar_hash', c.calendar_hash, 'calendar_sent_at', c.calendar_sent_at,
           'calendar_is_current', c.calendar_hash = h.v,
           'approved', c.approved_hash = h.v, 'approved_by', c.approved_by, 'approved_at', c.approved_at,
           'approved_message_id', c.approved_message_id,
           'voided_by_an_edit', c.approved_hash is not null and c.approved_hash <> h.v,
           'posts', (select count(*) from public.marketing_post p where p.campaign_id = c.id and p.status <> 'cancelled'),
           'first_post_at', (select min(p.scheduled_at) from public.marketing_post p where p.campaign_id = c.id and p.status <> 'cancelled'),
           'variants', (select count(*) from public.marketing_post_variant v join public.marketing_post p on p.id = v.post_id
                         where p.campaign_id = c.id and p.status <> 'cancelled'))
    from public.marketing_campaign c, lateral (select public.fn_marketing_campaign_hash(c.id) v) h
   where c.campaign_key = p_campaign_key
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_caption_length(p_text text, p_counted_as text)
 RETURNS integer
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v text := coalesce(p_text, ''); n int := 0; cp int; ch text; v_urls int;
begin
  if p_counted_as = 'utf8_bytes' then return octet_length(v); end if;
  if p_counted_as = 'codepoints' then return char_length(v); end if;
  if p_counted_as = 'utf16_units' then
    return char_length(v) + (select count(*) from regexp_split_to_table(v, '') c where ascii(c) > 65535)::int;
  end if;
  if p_counted_as is distinct from 'x_weighted' then
    raise exception 'fn_marketing_caption_length: unknown counting rule %', p_counted_as;
  end if;
  v := normalize(v, NFC);
  -- A URL is ASCII only ([!-~]) and never ends in trailing punctuation, so "(https://quotesdone.ae)" keeps its
  -- brackets outside, an Arabic comma after a link is not swallowed, and Arabic glued to a domain stays text.
  select count(*) into v_urls from regexp_matches(v,
    '(https?://[!-~]*[A-Za-z0-9/#=_&%+~-]|www\.[!-~]*[A-Za-z0-9/#=_&%+~-]|[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.(com|ae|net|org|io|co|app|me|ly|gl)(/[!-~]*[A-Za-z0-9/#=_&%+~-])?)', 'gi');
  v := regexp_replace(v,
    '(https?://[!-~]*[A-Za-z0-9/#=_&%+~-]|www\.[!-~]*[A-Za-z0-9/#=_&%+~-]|[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.(com|ae|net|org|io|co|app|me|ly|gl)(/[!-~]*[A-Za-z0-9/#=_&%+~-])?)', '', 'gi');
  -- A keycap (digit, optional VS16, U+20E3) and any character shown as emoji (followed by VS16, e.g. ©️) are
  -- emoji and weigh 2: replace each with one astral stand-in before the folding below.
  v := regexp_replace(v, '.' || chr(65039) || '?' || chr(8419), chr(128512), 'g');
  v := regexp_replace(v, '.' || chr(65039), chr(128512), 'g');
  -- fold each emoji sequence to its first code point: drop text selectors, skin tones, and every ZWJ with the
  -- code point it joins; a flag (two regional indicators) keeps one.
  v := regexp_replace(v, '[' || chr(65038) || chr(127995) || '-' || chr(127999) || ']', '', 'g');
  v := regexp_replace(v, chr(8205) || '.', '', 'g');
  v := regexp_replace(v, '([' || chr(127462) || '-' || chr(127487) || '])[' || chr(127462) || '-' || chr(127487) || ']', '\1', 'g');
  -- regexp_split_to_table('', '') yields one empty row, which the loop would weigh as 1.
  if v = '' then return 23 * v_urls; end if;
  for ch in select c from regexp_split_to_table(v, '') c loop
    cp := ascii(ch);
    n := n + case when cp <= 4351 or cp between 8192 and 8205 or cp between 8208 and 8223 or cp between 8242 and 8247
                  then 1 else 2 end;
  end loop;
  return n + 23 * v_urls;
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_channel_results_due(p_limit integer DEFAULT 10)
 RETURNS TABLE(post_id bigint, ingest_key text, channels text[], postiz_result jsonb, sent_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_closes_ad_spend_loops()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare h public.agent_actions; b public.agent_actions; n_closed int := 0; n_mismatch int := 0; n_wait int := 0;
begin
  for h in select * from public.agent_actions
            where kind = 'handoff' and agent = 'accountant' and detail->>'type' = 'adspend.recorded'
              and detail->>'from' = 'marketing' and status = 'pending' and detail ? 'replied_at'
            order by id limit 200 loop
    select * into b from public.agent_actions
     where kind = 'handoff' and agent = 'marketing' and detail->>'type' = 'adspend.booked'
       and (detail->>'recorded_handoff')::bigint = h.id and status = 'done'
     order by id desc limit 1;
    if b.id is null then
      n_wait := n_wait + 1;
    elsif coalesce((b.evidence->>'verified')::boolean, false) then
      perform set_config('qd.handoff_closer', 'marketing', true);
      perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
        'verified_by', 'marketing', 'verified_at', now(), 'verdict', 'recorded as reported (adspend.booked ' || b.id || ')'));
      perform set_config('qd.handoff_closer', '', true);
      n_closed := n_closed + 1;
    else
      n_mismatch := n_mismatch + 1;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'closed', n_closed, 'mismatch', n_mismatch, 'waiting', n_wait);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_competitor_refresh_duty()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_week date := date_trunc('week', now() at time zone 'Asia/Dubai')::date;
  v_body jsonb; v_stale int;
begin
  select count(*) into v_stale from public.competitor
   where watched and kind <> 'incumbent_behaviour' and (verified_at is null or verified_at < current_date - 90);
  v_body := jsonb_build_object(
    'week', v_week,
    'watched', (select count(*) from public.competitor where watched),
    'stale_profiles', v_stale,
    'changes', (select coalesce(jsonb_agg(jsonb_build_object('competitor', c.name, 'page', s.page_kind, 'decision', s.decision,
                  'what_changed', s.fields->>'what_changed', 'ceo_task', s.task_id) order by s.decided_at), '[]'::jsonb)
                  from public.competitor_scan s join public.competitor c on c.id = s.competitor_id
                 where s.decided_at >= now() - interval '7 days'),
    'fetch_failures', (select count(*) from public.competitor_scan where status = 'failed' and requested_at >= now() - interval '7 days'),
    'social_posts_seen', (select count(*) from public.market_intel where platform = 'instagram' and fetched_at >= now() - interval '7 days'),
    'scan', public.fn_marketing_competitor_scan());
  insert into public.marketing_plan_doc (kind, period, body) values ('competitor_intel', v_week, v_body)
  on conflict (kind, period) do update set body = excluded.body, updated_at = now();
  return v_body - 'changes';
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_competitor_scan()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s record; r record; c record; n_in int := 0; n_out int := 0; v_req bigint;
begin
  for s in select * from public.competitor_scan where status = 'fetching' and request_id is not null order by id loop
    select status_code, content, error_msg, timed_out into r from net._http_response where id = s.request_id;
    if found then
      perform public.fn_competitor_scan_ingest(s.id, case when coalesce(r.timed_out, false) then null else r.status_code end, r.content,
                                               coalesce(r.error_msg, case when r.timed_out then 'timed out' end));
      n_in := n_in + 1;
    elsif s.requested_at < now() - interval '6 hours' then
      perform public.fn_competitor_scan_ingest(s.id, null, null, 'no response within six hours');
      n_in := n_in + 1;
    end if;
  end loop;

  for c in
    select x.id, x.kind, p.page_kind, p.url
      from public.competitor x
      cross join lateral (values ('home', x.url), ('pricing', x.pricing_url)) p(page_kind, url)
     where x.watched and x.kind <> 'incumbent_behaviour' and p.url ~ '^https://'
       and not exists (select 1 from public.competitor_scan z where z.competitor_id = x.id and z.page_kind = p.page_kind
                         and (z.status = 'fetching' or z.requested_at > now() - interval '30 days'))
     order by x.id, p.page_kind limit 10
  loop
    v_req := net.http_get(c.url, '{}'::jsonb,
               jsonb_build_object('User-Agent', 'QuotesDone market watch (+https://www.quotesdone.ae)', 'Accept', 'text/html'), 20000);
    insert into public.competitor_scan (competitor_id, page_kind, url, request_id) values (c.id, c.page_kind, c.url, v_req);
    n_out := n_out + 1;
  end loop;
  return jsonb_build_object('collected', n_in, 'requested', n_out);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_connection_status()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'all_ok', coalesce(bool_and(c.ok), false),
    'oldest_measurement', min(c.measured_at),
    'checks', coalesce(jsonb_agg(jsonb_build_object('check', c.check_key, 'platform', c.platform, 'ok', c.ok,
                'http_status', c.http_status, 'measured_at', c.measured_at, 'credential_keys', c.credential_keys,
                'needs', c.needs, 'detail', c.detail) order by c.check_key), '[]'::jsonb),
    'never_measured', not exists (select 1 from public.marketing_connection_check))
  from public.marketing_connection_check c
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_content_brief(p_month date, p_plan jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object('month', p_month, 'organic_only', true,
    'videos', p_plan->'video', 'topics', p_plan->'topics', 'formats', p_plan->'formats',
    'music', p_plan->'music', 'voiceover', p_plan->'voiceover', 'cadence', p_plan->'cadence',
    'who_makes_it', 'The founder and Claude produce the videos; the marketing seat decided what is in them.')
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_duties_due()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- Due when no success yet today; but a start with no success after it is a run in flight or one that
  -- failed, so that waits two hours instead of hammering Graph every beat.
  select jsonb_object_agg(d.duty,
           (r.last_ok_at is null or (r.last_ok_at at time zone 'Asia/Dubai')::date < (now() at time zone 'Asia/Dubai')::date)
           and (r.last_started_at is null or r.last_started_at <= coalesce(r.last_ok_at, '-infinity')
                or r.last_started_at < now() - interval '2 hours'))
    from (values ('access'), ('insights'), ('ad_spend')) d(duty)
    left join public.marketing_duty_run r on r.duty = d.duty
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_duty_mark(p_duty text, p_phase text, p_result jsonb DEFAULT NULL::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_phase not in ('start', 'ok', 'error') then raise exception 'phase must be start, ok or error'; end if;
  insert into public.marketing_duty_run (duty, last_started_at, last_ok_at, last_result)
  values (p_duty, case when p_phase = 'start' then now() end, case when p_phase = 'ok' then now() end, p_result)
  on conflict (duty) do update
     set last_started_at = case when p_phase = 'start' then now() else marketing_duty_run.last_started_at end,
         last_ok_at = case when p_phase = 'ok' then now() else marketing_duty_run.last_ok_at end,
         last_result = coalesce(p_result, marketing_duty_run.last_result);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_evidence_problems(p_evidence jsonb)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare e jsonb; bad text[] := '{}'; k text; r text; v_ok boolean;
begin
  if p_evidence is null or jsonb_typeof(p_evidence) <> 'array' or jsonb_array_length(p_evidence) = 0 then
    return array['evidence must be a non-empty array'];
  end if;
  for e in select * from jsonb_array_elements(p_evidence) loop
    k := e->>'kind'; r := e->>'ref';
    if coalesce(btrim(e->>'point'), '') = '' then bad := bad || ('evidence ' || coalesce(k,'?') || ':' || coalesce(r,'?') || ' says nothing'); end if;
    v_ok := case k
      when 'market_intel'     then exists (select 1 from public.market_intel where id::text = r)
      when 'asset_review'     then exists (select 1 from public.marketing_asset_review where id::text = r)
      when 'asset_perception' then exists (select 1 from public.marketing_asset_perception where id::text = r)
      when 'asset_feature'    then exists (select 1 from public.marketing_asset_feature where file_sha256 = r)
      when 'insight_note'     then exists (select 1 from public.marketing_insight_note where week_start::text = r)
      when 'ceo_plan_month'   then exists (select 1 from public.ceo_plan_month where month::text = r)
      when 'turn'             then exists (select 1 from public.marketing_plan_review_turn where id::text = r)
      when 'scorecard'        then r ~ '^\d{4}-\d{2}-01$' and to_regclass('public.marketing_post_metric') is not null
      when 'post_metric'      then to_regclass('public.marketing_post_metric') is not null and coalesce(r, '') <> ''
      else false end;
    -- a post metric must be a row of marketing_post_metric; a scorecard must name a month that has metric rows
    -- (read by name at run time: the table is the sibling metrics build's)
    if v_ok and k = 'post_metric' then
      execute 'select exists (select 1 from public.marketing_post_metric m where to_jsonb(m)->>''id'' = $1)' into v_ok using r;
    elsif v_ok and k = 'scorecard' then
      execute 'select exists (select 1 from public.marketing_post_metric m where m.captured_at >= $1::date '
           || 'and m.captured_at < ($1::date + interval ''1 month''))' into v_ok using r;
    end if;
    if not coalesce(v_ok, false) then
      bad := bad || ('evidence ' || coalesce(k,'?') || ':' || coalesce(r,'?') || ' does not exist');
    end if;
  end loop;
  return bad;
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_files_invite_reply(p_inbound_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare m public.inbound_messages; l public.leads;
  v_from text; v_boxes text[]; v_first text; v_reply text; v_id bigint;
begin
  select * into m from public.inbound_messages where id = p_inbound_id;
  if not found then return jsonb_build_object('due', false, 'reason', 'no such inbound message'); end if;
  v_from := lower(substring(coalesce(m.from_email, '') from '([^<>[:space:]"]+@[^<>[:space:]"]+)'));
  select array_agg(lower(btrim(value))) into v_boxes from public.app_secrets
   where key in ('invite_m365_mailbox', 'email_reply_supplier') and btrim(coalesce(value, '')) <> '';
  if v_boxes is null or not exists (select 1 from unnest(v_boxes) b where position(b in lower(coalesce(m.to_email, ''))) > 0) then
    return jsonb_build_object('due', false, 'reason', 'not addressed to the invitation mailbox');
  end if;
  select * into l from public.leads x
   where (m.lead_id is not null and x.id = m.lead_id) or (m.lead_id is null and lower(btrim(x.email)) = v_from)
   order by x.id limit 1;
  if l.id is null then return jsonb_build_object('due', false, 'reason', 'the sender is no lead'); end if;
  if l.invited_at is null and l.invite_status is null then return jsonb_build_object('due', false, 'reason', 'the lead was never invited'); end if;
  if coalesce(l.claimed, false) then return jsonb_build_object('due', false, 'reason', 'the lead already has its company page'); end if;
  -- 27 Oct 2026: an out-of-office or help-desk acknowledgement never takes the lead's one handoff
  if public.fn_inbound_is_auto_reply(m.subject, m.body, m.raw) then return jsonb_build_object('due', false, 'reason', 'an automatic reply'); end if;
  -- the supplier's own words: everything above the quoted original
  -- (CRLF folded first: a Graph text body ends its lines with \r, measured 27 Oct 2026 end to end)
  v_reply := btrim(regexp_replace(replace(coalesce(m.body, ''), E'\r', ''), E'(\\n|^)\\s*(>|On [^\\n]{0,200}wrote:|-{2,}\\s*Original Message|From:\\s).*$', ''));
  v_first := lower(btrim(regexp_replace(split_part(v_reply, E'\n', 1), '[[:punct:][:space:]]+', ' ', 'g')));
  -- "stop" is an unsubscribe (resend_inbound), never a request for a page
  if v_first in ('stop', 'unsubscribe', 'stopall', 'end', 'cancel', 'opt out', 'optout', 'remove', 'remove me', 'please remove', 'not interested') then
    return jsonb_build_object('due', false, 'reason', 'a stop reply (handled as an unsubscribe)');
  end if;
  if v_reply = '' then return jsonb_build_object('due', false, 'reason', 'an empty reply'); end if;

  v_id := public.fn_seat_handoff('marketing', 'sales_engineer', 'invite.reply', 'leads', l.id::text,
    jsonb_build_object('lead_id', l.id, 'company_name', l.company_name, 'from_email', v_from,
                       'inbound_message_id', m.id, 'reply_text', left(v_reply, 4000),
                       'ask', 'Set up the company page for this supplier from the trades it listed in its reply.'));
  -- null = a demo lead (ruling 1199: a demo row files no handoff)
  return jsonb_build_object('due', true, 'reason', 'an invited supplier replied', 'lead_id', l.id, 'reply_text', left(v_reply, 4000), 'handoff_id', v_id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_files_wa_invite_reply(p_from text, p_body text, p_button_payload text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_phone text := '+' || regexp_replace(coalesce(p_from, ''), '\D', '', 'g');
  v_optins int := 0; l public.leads; v_reply text := btrim(coalesce(p_body, '')); v_id bigint;
  v_ask public.supplier_whatsapp_consent_ask; v_source text; v_rule jsonb;
begin
  if v_phone !~ '^\+[0-9]{8,15}$' then return jsonb_build_object('due', false, 'reason', 'no number'); end if;
  -- (a) the button
  if btrim(coalesce(p_button_payload, '')) <> '' then
    v_source := 'wa_button'; v_rule := public.fn_wa_optin_rule('wa_button', p_button_payload, null, null);
  else
    -- (b) the first reply after an open consent ask on this number (7 days) answers it, yes or not; the ask closes
    select * into v_ask from public.supplier_whatsapp_consent_ask
     where phone = v_phone and answered_at is null and asked_at > now() - interval '7 days'
     order by asked_at desc, id desc limit 1 for update;
    if v_ask.id is not null then
      update public.supplier_whatsapp_consent_ask set answered_at = now(), answer = left(v_reply, 500)
       where phone = v_phone and answered_at is null;
      v_source := 'wa_consent_reply'; v_rule := public.fn_wa_optin_rule('wa_consent_reply', null, v_ask.question, v_reply);
    else
      v_rule := jsonb_build_object('counts', false, 'why', 'a message that is neither the button nor a reply to the consent question');
    end if;
  end if;
  if (v_rule->>'counts')::boolean then
    insert into public.supplier_whatsapp_optin (lead_id, phone, source, button_payload, consent_question, consent_answer, evidence)
    select x.id, v_phone, v_source, nullif(btrim(coalesce(p_button_payload, '')), ''), v_ask.question,
           case when v_source = 'wa_consent_reply' then left(v_reply, 500) end,
           (v_rule->>'why') || ' on WhatsApp at ' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI') || ' Dubai'
      from public.leads x
     where (x.phone_e164 = v_phone or x.whatsapp_phone = v_phone) and coalesce(x.whatsapp_opt, '') <> 'none'
    on conflict (lead_id, phone) do nothing;
    get diagnostics v_optins = row_count;
  end if;

  select * into l from public.leads x
   where (x.phone_e164 = v_phone or x.whatsapp_phone = v_phone)
     and not coalesce(x.claimed, false)
     and (x.invited_at is not null or x.invite_status is not null
          or exists (select 1 from public.notifications n where n.type = 'supplier_invite_wa' and n.lead_id = x.id and n.status = 'sent'))
   order by x.id limit 1;
  if l.id is null then return jsonb_build_object('due', false, 'reason', 'no invited lead without a company page on this number',
                                                 'optins', v_optins, 'optin_why', v_rule->>'why'); end if;
  if v_reply = '' then return jsonb_build_object('due', false, 'reason', 'an empty message', 'optins', v_optins, 'optin_why', v_rule->>'why'); end if;
  v_id := public.fn_seat_handoff('marketing', 'sales_engineer', 'invite.reply', 'leads', l.id::text,
    jsonb_build_object('lead_id', l.id, 'company_name', l.company_name, 'channel', 'whatsapp', 'from_phone', v_phone,
                       'reply_text', left(v_reply, 4000), 'opted_in', (v_rule->>'counts')::boolean,
                       'ask', case when (v_rule->>'counts')::boolean
                                   then 'Set up the company page for this supplier from the trades it listed in its WhatsApp reply.'
                                   else 'Answer this supplier. This message is not a WhatsApp opt-in (ledger 1341); to message it later, ask the consent question and record the ask with fn_supplier_whatsapp_consent_ask_record.' end));
  -- null = a demo lead (ruling 1199: a demo row files no handoff)
  return jsonb_build_object('due', true, 'reason', 'an invited supplier wrote on WhatsApp', 'lead_id', l.id,
                            'handoff_id', v_id, 'optins', v_optins, 'optin_why', v_rule->>'why');
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_first_touch_record(p_lead_id bigint, p_touch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_ok constant text := '^[A-Za-z0-9._-]{1,100}$';
  v_src text; v_med text; v_cmp text; v_cnt text; v_path text; v_at timestamptz; v_post bigint; v_id bigint;
begin
  if p_lead_id is null then
    return jsonb_build_object('ok', true, 'recorded', false, 'reason', 'no lead');
  end if;
  if p_touch is null or jsonb_typeof(p_touch) <> 'object' then p_touch := '{}'::jsonb; end if;
  v_src := nullif(btrim(p_touch->>'utm_source'), '');     if v_src !~ v_ok then v_src := null; end if;
  v_med := nullif(btrim(p_touch->>'utm_medium'), '');     if v_med !~ v_ok then v_med := null; end if;
  v_cmp := nullif(btrim(p_touch->>'utm_campaign'), '');   if v_cmp !~ v_ok then v_cmp := null; end if;
  v_cnt := nullif(btrim(p_touch->>'utm_content'), '');    if v_cnt !~ v_ok then v_cnt := null; end if;
  v_path := nullif(btrim(p_touch->>'landing_path'), '');  if v_path !~ '^/\S{0,200}$' then v_path := null; end if;
  -- THE INVITATION IS A TOUCH EVEN WHEN THE BROWSER KEPT NONE (28 Sep 2026): private mode or a link
  -- opened before the ref existed leaves no tagged visit, but claim_lookup stamps invite_clicked_at when the
  -- lead's own claim link is opened. That is evidence of the invitation, not a status column.
  if v_src is null then
    select 'invite', 'email', 'supplier_invite', 'lead-' || l.id, '/portal', l.invite_clicked_at
      into v_src, v_med, v_cmp, v_cnt, v_path, v_at
      from public.leads l where l.id = p_lead_id and l.invite_clicked_at is not null;
    if v_src is null then
      -- refused, not accepted: nothing is recorded, and the caller can tell (outcome audit 30 Sep 2026)
      return jsonb_build_object('ok', false, 'recorded', false, 'reason', 'no_utm',
        'detail', 'no valid utm_source and no opened invitation');
    end if;
    p_touch := jsonb_build_object('first_seen_at', v_at);
  end if;
  begin
    v_at := (p_touch->>'first_seen_at')::timestamptz;
    if v_at < now() - interval '400 days' or v_at > now() + interval '1 hour' then v_at := null; end if;
  exception when others then v_at := null;
  end;
  if v_med = 'social' and v_cnt is not null then
    select id into v_post from public.marketing_post where ingest_key = lower(v_cnt);
  end if;
  insert into public.marketing_first_touch (lead_id, utm_source, utm_medium, utm_campaign, utm_content, landing_path, first_seen_at, post_id)
  values (p_lead_id, lower(v_src), v_med, v_cmp, v_cnt, v_path, v_at, v_post)
  on conflict (lead_id) do nothing
  returning id into v_id;
  return jsonb_build_object('ok', true, 'recorded', v_id is not null, 'post_id', v_post);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_founder_email()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select lower(btrim(coalesce(nullif(split_part((select value from public.app_secrets where key = 'admin_emails'), ',', 1), ''),
                              'management@quotesdone.com')))
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_funnel_diagnosis(p_include_demo boolean DEFAULT false, p_file boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_min int := coalesce((select nullif(btrim(value), '')::int from public.app_secrets where key = 'recruitment_diagnosis_min_invites'), 20);
  v_month text := to_char((now() at time zone 'Asia/Dubai')::date, 'YYYY-MM');
  v_channels jsonb; v_trades jsonb; c record; v_filed jsonb := '[]'::jsonb; v_imp bigint;
begin
  with f as (
    select l.id, coalesce(n.channel, 'email') as channel,
           coalesce(nullif(l.invite_trades, '{}'::text[]), array['unknown']) as trades,
           coalesce(n.sent, false)::int as sent, coalesce(n.delivered, false)::int as delivered,
           (l.invite_clicked_at is not null)::int as clicked, coalesce(l.claimed, false)::int as started,
           (l.registration_submitted_at is not null)::int as registered
      from public.leads l
      left join lateral (
        select max(x.channel) as channel, bool_or(x.status = 'sent') as sent,
               bool_or(x.status = 'sent' and x.provider_status = 'delivered') as delivered
          from public.notifications x where x.lead_id = l.id and x.type = 'supplier_invite') n on true
     where l.invited_at is not null and (p_include_demo or not coalesce(l.is_demo, false))
  ), per_channel as (
    select channel, jsonb_build_object('invited', count(*), 'sent', sum(sent), 'delivered', sum(delivered),
           'clicked', sum(clicked), 'started', sum(started), 'registered', sum(registered)) st
      from f group by channel
  ), per_trade as (
    select f.channel, t.trade, jsonb_build_object('invited', count(*), 'sent', sum(f.sent), 'delivered', sum(f.delivered),
           'clicked', sum(f.clicked), 'started', sum(f.started), 'registered', sum(f.registered)) st
      from f cross join lateral unnest(f.trades) t(trade) group by f.channel, t.trade
  )
  select (select coalesce(jsonb_agg(jsonb_build_object('channel', channel, 'stages', st,
                   'drop', public.fn_marketing_funnel_largest_drop(st)) order by channel), '[]'::jsonb) from per_channel),
         (select coalesce(jsonb_agg(jsonb_build_object('channel', channel, 'trade', trade, 'stages', st,
                   'drop', public.fn_marketing_funnel_largest_drop(st)) order by channel, trade), '[]'::jsonb) from per_trade)
    into v_channels, v_trades;

  if p_file then
    for c in select e from jsonb_array_elements(v_channels) e
              where (e->'stages'->>'invited')::int >= v_min and (e->'stages'->>'registered')::int = 0 loop
      v_imp := public.fn_ceo_improvement_open('funnel_stage_drop',
        (c.e->>'channel') || ':' || (c.e->'drop'->>'cause') || ':' || v_month, 'marketing',
        format('Recruitment by %s: %s invited, 0 registered. The largest drop is %s -> %s (%s lost): %s. %s',
               c.e->>'channel', c.e->'stages'->>'invited', c.e->'drop'->>'from', c.e->'drop'->>'to', c.e->'drop'->>'lost',
               c.e->'drop'->>'cause', c.e->'drop'->>'proposed_fix'),
        jsonb_build_object('stages', c.e->'stages', 'drop', c.e->'drop', 'min_invites', v_min,
                           'source', 'fn_marketing_funnel_diagnosis'));
      v_filed := v_filed || jsonb_build_object('channel', c.e->>'channel', 'improvement_id', v_imp);
    end loop;
  end if;

  return jsonb_build_object('min_invites', v_min, 'channels', v_channels, 'by_trade', v_trades, 'filed', v_filed);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_funnel_largest_drop(p_stages jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce((
    select jsonb_build_object('from', s.a, 'to', s.b, 'lost', s.lost, 'cause', s.cause, 'proposed_fix', s.fix)
      from (select a, b, coalesce((p_stages->>a)::int, 0) - coalesce((p_stages->>b)::int, 0) as lost, cause, fix, ord
              from (values
                (1, 'invited', 'sent', 'not_actually_sent',
                 'Leads are marked invited but the outbox holds no sent invitation for them. Count only outbox sends; the batch is released by enqueue_supplier_invites once supplier_outreach_golive and invite_enabled are true.'),
                (2, 'sent', 'delivered', 'bounced_or_undelivered',
                 'Invitations left the outbox but were not delivered. Clean the list (role and dead domains) and check the sending domain before the next batch.'),
                (3, 'delivered', 'clicked', 'no_clicks',
                 'Invitations were delivered but nobody opened the link. Test the subject line, the first sentence and the sender name per trade.'),
                (4, 'clicked', 'started', 'clicks_but_no_start',
                 'Suppliers opened the link but did not claim their company. Walk the portal claim step from the invitation link and shorten it.'),
                (5, 'started', 'registered', 'started_not_finished',
                 'Suppliers claimed but did not submit the registration. Find the form step they stop at and follow up through customer_support.')
              ) v(ord, a, b, cause, fix)) s
     where s.lost > 0
     order by s.lost desc, s.ord
     limit 1),
    jsonb_build_object('from', null, 'to', null, 'lost', 0, 'cause', 'no_drop', 'proposed_fix', null))
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_gap_recruitment_plans()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_body text := (select value from public.app_secrets where key = 'invite_body');
  v_rows int; v_dropped int;
begin
  -- 27 Oct 2026: the founder approved ONE invitation with no link; each plan row stores it (the trade is filled at
  -- send time by the Microsoft 365 lane). Only an empty template is refused.
  if btrim(coalesce(v_body, '')) = '' then
    raise exception 'app_secrets.invite_body is empty: no plan is built from nothing';
  end if;

  delete from public.marketing_gap_recruitment_plan p
   where not exists (select 1 from public.supply_gap g where g.trade = p.trade and g.emirate = p.emirate
                       and g.closed_at is null and g.status <> 'closed' and g.matchable < g.target);
  get diagnostics v_dropped = row_count;

  with gaps as (
    select g.*, coalesce(t.label, g.trade) as label, t.group_code,
           row_number() over (order by (g.target - g.matchable) desc, g.demand_90d desc, g.uninvited_pool desc, g.trade, g.emirate) as rk
      from public.supply_gap g left join public.taxonomy_trade t on t.code = g.trade
     where g.closed_at is null and g.status <> 'closed' and g.matchable < g.target
  )
  insert into public.marketing_gap_recruitment_plan as p
    (trade, emirate, rank, matchable, target, gap, demand_90d, uninvited_pool, gap_status, sources, invite_subject, invite_body, built_at)
  select x.trade, x.emirate, x.rk, x.matchable, x.target, x.target - x.matchable, x.demand_90d, x.uninvited_pool, x.status,
         coalesce((select jsonb_agg(jsonb_build_object('kind', s.kind, 'name', s.name, 'url', s.url, 'scope', s.scope,
                                                       'http_status', s.http_status, 'verified', s.verified, 'checked_at', s.checked_at)
                                    order by (s.scope = x.trade) desc, (s.scope = x.group_code) desc, s.verified desc, s.kind, s.name)
                     from public.marketing_recruitment_source s
                    where s.scope in ('all', x.trade, coalesce(x.group_code, '-'))), '[]'::jsonb),
         initcap(x.label) || ' quote requests',
         v_body,
         now()
    from gaps x
  on conflict (trade, emirate) do update set rank = excluded.rank, matchable = excluded.matchable, target = excluded.target,
    gap = excluded.gap, demand_90d = excluded.demand_90d, uninvited_pool = excluded.uninvited_pool, gap_status = excluded.gap_status,
    sources = excluded.sources, invite_subject = excluded.invite_subject, invite_body = excluded.invite_body, built_at = excluded.built_at;
  get diagnostics v_rows = row_count;

  -- a planned trade with no checked source is marketing's own finding (where to look is the gap, not the invitation)
  perform public.fn_it_engineer_finding_upsert('recruitment:no_source:' || p.trade,
      'No checked recruitment source is recorded for ' || p.trade, 'public.marketing_recruitment_source', 'monitor', 1,
      jsonb_build_object('trade', p.trade, 'owner_seat', 'marketing'), '{}'::text[],
      array['a directory, association, chamber, LinkedIn group or trade fair where this trade gathers'], 'marketing')
    from (select distinct trade from public.marketing_gap_recruitment_plan
           where not exists (select 1 from jsonb_array_elements(sources) e where (e->>'verified')::boolean)) p;
  update public.it_engineer_finding f set closed_at = now(), close_note = 'a checked source is recorded'
   where f.issue_key like 'recruitment:no_source:%' and f.closed_at is null
     and not exists (select 1 from public.marketing_gap_recruitment_plan p where 'recruitment:no_source:' || p.trade = f.issue_key
                       and not exists (select 1 from jsonb_array_elements(p.sources) e where (e->>'verified')::boolean));

  return public.fn_marketing_gap_recruitment_report() || jsonb_build_object('plans_written', v_rows, 'plans_dropped', v_dropped);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_gap_recruitment_report()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'plans', (select count(*) from public.marketing_gap_recruitment_plan),
    'plans_with_checked_source', (select count(*) from public.marketing_gap_recruitment_plan p
                                   where exists (select 1 from jsonb_array_elements(p.sources) e where (e->>'verified')::boolean)),
    'sources', (select count(*) from public.marketing_recruitment_source),
    'sources_verified', (select count(*) from public.marketing_recruitment_source where verified),
    'uninvited_pool_in_plans', (select coalesce(sum(uninvited_pool), 0) from public.marketing_gap_recruitment_plan),
    'top', (select coalesce(jsonb_agg(jsonb_build_object('rank', rank, 'trade', trade, 'emirate', emirate, 'gap', gap,
                                                         'demand_90d', demand_90d, 'uninvited_pool', uninvited_pool, 'gap_status', gap_status,
                                                         'sources', jsonb_array_length(sources)) order by rank), '[]'::jsonb)
              from public.marketing_gap_recruitment_plan where rank <= 20))
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_geo_check_duty()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_month date := date_trunc('month', v_today)::date;
  v_owed int; v_last timestamptz; v_held boolean;
begin
  v_held := not coalesce((public.fn_kernel_paid_provider_gate('perplexity/sonar')->>'allowed')::boolean, false);
  select count(*) into v_owed from public.fn_marketing_geo_due(1000, true);
  select max(checked_at) into v_last from public.marketing_geo_check where engine like 'answer_%';
  if not v_held and v_owed > 0 and extract(day from v_today) >= 10 and (v_last is null or v_last < now() - interval '2 days') then
    raise exception 'GEO: % answer-engine check(s) owed for % and none recorded since %', v_owed, to_char(v_month, 'YYYY-MM'),
      coalesce(to_char(v_last, 'YYYY-MM-DD HH24:MI'), 'ever');
  end if;
  return jsonb_build_object('month', v_month, 'owed', v_owed, 'held_by_founder', v_held, 'last_check', v_last,
    'summary', public.fn_marketing_geo_summary(v_month) - 'rows');
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_geo_due(p_limit integer DEFAULT 2, p_include_model boolean DEFAULT true)
 RETURNS TABLE(question_id bigint, question text, engine text, month date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with m as (select date_trunc('month', now() at time zone 'Asia/Dubai')::date as month)
  select q.id, q.question, e.engine, m.month
    from public.marketing_geo_question q cross join (values ('answer_search'), ('answer_online')) e(engine) cross join m
   where q.active and p_include_model and not exists (select 1 from public.marketing_geo_check c
                                   where c.month = m.month and c.question_id = q.id and c.engine = e.engine)
   order by q.id, e.engine limit greatest(p_limit, 0)
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_geo_record(p_month date, p_question_id bigint, p_engine text, p_cited boolean, p_rank integer, p_evidence text, p_model text, p_competitors text[] DEFAULT '{}'::text[])
 RETURNS bigint
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  insert into public.marketing_geo_check (month, question_id, engine, cited, rank, evidence, model, competitors_cited)
  values (p_month, p_question_id, p_engine, p_cited, p_rank, left(p_evidence, 2000), p_model, coalesce(p_competitors, '{}'))
  on conflict (month, question_id, engine) do update set cited = excluded.cited, rank = excluded.rank, evidence = excluded.evidence,
    model = excluded.model, competitors_cited = excluded.competitors_cited, checked_at = now()
  returning id
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_geo_summary(p_month date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object('month', p_month,
    'questions', (select count(distinct question_id) from public.marketing_geo_check where month = p_month),
    'answer_checked', (select count(*) from public.marketing_geo_check where month = p_month and engine like 'answer_%'),
    'answer_cited', (select count(*) from public.marketing_geo_check where month = p_month and engine like 'answer_%' and cited),
    'by_engine', (select coalesce(jsonb_object_agg(engine, jsonb_build_object('checked', n, 'cited', k)), '{}'::jsonb)
                    from (select engine, count(*) n, count(*) filter (where cited) k from public.marketing_geo_check where month = p_month group by engine) e),
    'competitors_cited', (select coalesce(jsonb_object_agg(name, n), '{}'::jsonb)
                            from (select x name, count(*) n from public.marketing_geo_check, unnest(competitors_cited) x
                                   where month = p_month group by x) z),
    'blog_posts_published', (select count(*) from public.blog_posts where published),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('question', q.question, 'trade', q.trade, 'city', q.city, 'engine', c.engine,
               'cited', c.cited, 'competitors', c.competitors_cited, 'evidence', left(c.evidence, 300)) order by q.id, c.engine), '[]'::jsonb)
               from public.marketing_geo_check c join public.marketing_geo_question q on q.id = c.question_id where c.month = p_month))
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_hashtags_ok(p text[])
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(bool_and(h ~ '^[^[:space:]#]{1,100}$'), true) from unnest(coalesce(p, '{}')) h
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_intel_upsert(p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r jsonb; n_new int := 0; n_upd int := 0; n_bad int := 0; v_new boolean;
begin
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    if coalesce(r->>'source_url', '') !~ '^https://' or coalesce(r->>'external_id', '') = ''
       or coalesce(r->>'platform', '') !~ '^[a-z][a-z0-9_]*$' then
      n_bad := n_bad + 1; continue;
    end if;
    insert into public.market_intel (kind, title, detail, source, impact, status, source_url, platform, external_id,
                                     competitor_id, posted_at, metrics, fetched_at)
    values ('competitor', left(coalesce(nullif(btrim(r->>'caption'), ''), '(no caption) ' || coalesce(r->>'media_type', 'post')), 160),
            r->>'caption', r->>'platform' || ':' || coalesce(r->>'source', 'official_api'), 'low', 'open', r->>'source_url',
            r->>'platform', r->>'external_id', (r->>'competitor_id')::bigint, (r->>'posted_at')::timestamptz,
            coalesce(r->'metrics', '{}'::jsonb) || jsonb_build_object('media_type', r->>'media_type'), now())
    on conflict (platform, external_id) where external_id is not null do update
      set metrics = excluded.metrics, fetched_at = now(), detail = excluded.detail
    returning (xmax = 0) into v_new;
    if v_new then n_new := n_new + 1; else n_upd := n_upd + 1; end if;
  end loop;
  return jsonb_build_object('ok', true, 'inserted', n_new, 'updated', n_upd, 'refused', n_bad);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_jbool(v jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case when jsonb_typeof(v) = 'boolean' then (v #>> '{}')::boolean end
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_jnum(v jsonb)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case when jsonb_typeof(v) = 'number' then (v #>> '{}')::numeric end
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_launch_plan_duty()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select public.fn_marketing_launch_plan_run((now() at time zone 'Asia/Dubai')::date)
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_launch_plan_run(p_today date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_today date := p_today;
  v_launch date := date '2027-01-01';
  v_body jsonb; d public.marketing_plan_doc; v_token text; v_nid bigint; v_paid boolean := public.fn_marketing_paid_allowed();
  v_open int; v_total int; v_short jsonb; v_hash text; v_changes jsonb;
begin
  select count(*) filter (where is_open), count(*) into v_open, v_total from public.v_category_open;
  select coalesce(jsonb_agg(jsonb_build_object('category', name, 'verified', verified_registered_suppliers, 'needed', min_required)
           order by min_required - verified_registered_suppliers desc, num), '[]'::jsonb)
    into v_short from public.v_category_open where not is_open;
  v_changes := coalesce((select founder_changes from public.marketing_plan_doc where kind = 'launch_plan' and period = v_launch), '[]'::jsonb);
  v_body := jsonb_build_object(
    'founder_changes', v_changes,
    'launch_month', v_launch, 'drawn_on', v_today,
    'categories', jsonb_build_object('open', v_open, 'total', v_total, 'short', v_short),
    'paid_allowed', v_paid,
    'channels', case when v_paid then jsonb_build_array('organic social', 'blog and GEO', 'LinkedIn outreach', 'paid Meta within the ad cap')
                     else jsonb_build_array('organic social', 'blog and GEO', 'LinkedIn outreach') end,
    'rule', 'Organic only until every category has its verified suppliers; no post on a UAE weekend or public holiday.',
    'posting_days', (select coalesce(jsonb_agg(g::date order by g), '[]'::jsonb)
                       from generate_series(v_launch, date '2027-01-31', interval '1 day') g where public.fn_is_working_day(g::date)),
    'articles_ready', (select count(*) from public.marketing_article where status in ('approved', 'released', 'live') and not is_demo),
    'supplier_recruitment', (select last_result from public.seat_duty where duty = 'marketing.recruitment_funnel'));
  insert into public.marketing_plan_doc (kind, period, body) values ('launch_plan', v_launch, v_body)
  on conflict (kind, period) do update set body = excluded.body, updated_at = now()
    where marketing_plan_doc.status in ('draft', 'change_requested')
  returning * into d;
  if d.id is null then select * into d from public.marketing_plan_doc where kind = 'launch_plan' and period = v_launch; end if;
  -- the plan he approves: channels, the rule, the posting days, the open count and his changes (not the draw date,
  -- the per-category supplier counts or the recruitment counters, which move daily without changing the plan)
  v_hash := md5((v_body - 'drawn_on' - 'supplier_recruitment' - 'articles_ready'
                 || jsonb_build_object('categories', jsonb_build_object('open', v_open, 'total', v_total)))::text);

  if v_today >= date '2026-12-01' and v_today < v_launch
     and (d.status = 'draft' or (d.status = 'change_requested' and v_hash is distinct from d.sent_hash)) then
    v_token := encode(extensions.gen_random_bytes(16), 'hex');
    v_nid := public.fn_marketing_mail_founder('marketing_launch_plan', 'Launch plan for January 2027 [approve ' || v_token || ']',
      'The launch plan for January 2027.' || E'\n\n'
      || case when jsonb_array_length(v_changes) > 0 then 'Your changes, in this version:' || E'\n'
           || (select string_agg('- ' || x, E'\n' order by n) from jsonb_array_elements_text(v_changes) with ordinality t(x, n)) || E'\n\n'
         else '' end
      || 'Categories open: ' || v_open || ' of ' || v_total || ' (a category opens at its verified supplier minimum).' || E'\n'
      || 'Channels: ' || (select string_agg(x, ', ') from jsonb_array_elements_text(v_body->'channels') x)
      || case when v_paid then '' else ' - organic only, because not every category is open yet.' end || E'\n'
      || 'Posting days: ' || jsonb_array_length(v_body->'posting_days') || ' UAE working days (no weekends or public holidays).' || E'\n'
      || 'Articles approved and ready: ' || (v_body->>'articles_ready') || E'\n\n'
      || 'Reply "approve" and the marketing seat runs it. Any other reply is passed to the seat as a change.',
      null, 'approve+' || v_token || '@mail.quotesdone.com');
    update public.marketing_plan_doc set status = 'sent_to_founder', approval_token = v_token, sent_at = now(), notification_id = v_nid,
           sent_hash = v_hash, updated_at = now()
     where id = d.id;
    d.status := 'sent_to_founder';
  end if;
  return jsonb_build_object('status', d.status, 'open', v_open, 'total', v_total, 'paid_allowed', v_paid, 'mailed', v_nid is not null,
    'founder_changes', jsonb_array_length(v_changes), 'posting_days', jsonb_array_length(v_body->'posting_days'));
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_learning(p_month date, p_include_demo boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with pp as (          -- every (post, platform) published in the month
    select p.id as post_id, c.platform,
           coalesce(i.idea_key, nullif(lower(btrim(p.title)), ''), 'untitled') as topic,
           coalesce(v.post_type, case when p.video_path is not null then 'video' else 'image' end) as format,
           public.fn_marketing_time_slot(coalesce(p.published_at, p.scheduled_at)) as slot
      from public.marketing_post p
      cross join unnest(p.channels) c(platform)
      left join public.marketing_video_idea i on lower(i.title) = lower(btrim(p.title))
      left join lateral (select v.post_type from public.marketing_post_variant v
                          where v.post_id = p.id and v.platform = c.platform order by v.seq limit 1) v on true
     -- a ZZ DEMO post is never published (fn_marketing_post_guard_publish), so a demo run counts it once scheduled
     where (p_include_demo or not p.is_demo)
       and (p.status = 'published' or (p_include_demo and p.is_demo and p.status = 'scheduled'))
       and date_trunc('month', coalesce(p.published_at, p.scheduled_at) at time zone 'Asia/Dubai')::date = date_trunc('month', p_month)::date
  ), regs as (          -- every supplier registration of the month with a first touch
    select t.lead_id, t.utm_source as platform, t.post_id,
           coalesce((select lc.slug from public.lead_category lc where lc.lead_id = t.lead_id
                      order by lc.is_primary desc, lc.score desc limit 1), 'unclassified') as category
      from public.marketing_first_touch t join public.leads l on l.id = t.lead_id
     where date_trunc('month', t.recorded_at at time zone 'Asia/Dubai')::date = date_trunc('month', p_month)::date
       and (p_include_demo or not coalesce(l.is_demo, false))
  ), rp as (select r.*, pp.topic, pp.format, pp.slot from regs r
              left join pp on pp.post_id = r.post_id and pp.platform = r.platform
  ), hits as (
    select 'channel' as dim, platform as val, category, lead_id from rp
    union all select 'topic', topic, category, lead_id from rp where topic is not null
    union all select 'format', format, category, lead_id from rp where format is not null
    union all select 'time', slot, category, lead_id from rp where slot is not null
  ), posts as (
    select 'channel' as dim, platform as val, count(*) as n from pp group by platform
    union all select 'topic', topic, count(distinct post_id) from pp group by topic
    union all select 'format', format, count(*) from pp group by format
    union all select 'time', slot, count(distinct post_id) from pp group by slot
  ), hc as (select dim, val, category, count(distinct lead_id) as n from hits group by 1, 2, 3
  ), hv as (select dim, val, sum(n)::int as regs, jsonb_object_agg(category, n) as by_category from hc group by 1, 2
  ), rows as (
    select coalesce(hv.dim, po.dim) as dim, coalesce(hv.val, po.val) as val, coalesce(po.n, 0)::int as posts,
           coalesce(hv.regs, 0) as regs, coalesce(hv.by_category, '{}'::jsonb) as by_category,
           case when coalesce(po.n, 0) > 0 then round(coalesce(hv.regs, 0)::numeric / po.n, 3) end as per_post
      from hv full join posts po on po.dim = hv.dim and po.val = hv.val
  ), under as (
    select coalesce(jsonb_agg(jsonb_build_object('category', g.trade, 'suppliers', g.matchable, 'target', g.target)
                              order by g.matchable, g.trade), '[]'::jsonb) as list, count(*)::int as n
      from public.supply_gap g where g.emirate = 'UAE' and g.matchable < g.target
  )
  select jsonb_build_object(
    'month', date_trunc('month', p_month)::date,
    'posts', (select count(distinct post_id) from pp),
    'registrations', (select count(*) from regs),
    'traced_to_a_post', (select count(*) from regs where post_id is not null),
    'has_data', (select count(*) from regs) > 0,
    'by_category', (select coalesce(jsonb_object_agg(category, n), '{}'::jsonb) from (select category, count(*) n from regs group by 1) z),
    'dimensions', (select coalesce(jsonb_object_agg(dim, v), '{}'::jsonb) from (
                     select dim, jsonb_agg(jsonb_build_object('value', val, 'posts', posts, 'registrations', regs,
                                                              'per_post', per_post, 'by_category', by_category)
                                           order by regs desc, per_post desc nulls last, val) as v
                       from rows group by dim) d),
    -- founder: organic only until every category has 10 suppliers. No supply_gap row yet = not measured = organic.
    'organic_only', (select n > 0 from under) or not exists (select 1 from public.supply_gap where emirate = 'UAE'),
    'categories_under_target', (select list from under),
    'method', 'code: first-touch attribution (marketing_first_touch), counted per month in Asia/Dubai; no model')
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_learning_text(p_learned jsonb, p_shifted jsonb DEFAULT '[]'::jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select 'WHAT WORKED IN ' || upper(to_char((p_learned->>'month')::date, 'FMMonth YYYY')) || E' (supplier registrations by first touch, counted by code)\n'
    || case when not coalesce((p_learned->>'has_data')::boolean, false) then
         '- No supplier registration has been traced to a post or channel yet (' || coalesce(p_learned->>'posts', '0')
         || ' post(s) published). The mix is kept as it is: the ideas below follow the normal rotation.'
       else
         '- ' || (p_learned->>'registrations') || ' registration(s) with a first touch, ' || (p_learned->>'traced_to_a_post')
         || ' traced to a specific post, across ' || (p_learned->>'posts') || E' post(s).\n'
         || coalesce((select string_agg(format('- %s: %s', initcap(d.key),
               (select string_agg(format('%s %s reg / %s post(s)%s', r->>'value', r->>'registrations', r->>'posts',
                                         case when (r->'by_category') <> '{}'::jsonb then ' [' ||
                                           (select string_agg(c.key || ' ' || c.value, ', ') from jsonb_each_text(r->'by_category') c) || ']' else '' end), '; ')
                  from (select r from jsonb_array_elements(d.value) r where (r->>'registrations')::int > 0 limit 3) z)), E'\n'
               order by array_position(array['topic','channel','format','time'], d.key))
             from jsonb_each(p_learned->'dimensions') d
            where exists (select 1 from jsonb_array_elements(d.value) r where (r->>'registrations')::int > 0)), '')
         || E'\n' || case when jsonb_array_length(coalesce(p_shifted, '[]'::jsonb)) > 0
              then '- The shift: ' || (select string_agg(x #>> '{}', ', ') from jsonb_array_elements(p_shifted) x)
                   || ' brought registrations, so they come first below; the rest keep the rotation so new ideas are still tested.'
              else '- None of the topics that brought registrations is an enabled idea, so the ideas keep the rotation; use the channel and time lines above when setting the calendar.' end
       end
    || E'\n' || case when coalesce((p_learned->>'organic_only')::boolean, true)
         then '- Organic only: ' || jsonb_array_length(coalesce(p_learned->'categories_under_target', '[]'::jsonb))
              || ' categor(ies) still have fewer than 10 suppliers, so no paid promotion is planned.'
         else '- Every category has at least 10 suppliers. This plan is still organic; paid promotion would need its own proposal.' end
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_mail_founder(p_kind text, p_subject text, p_body text, p_attachments jsonb DEFAULT NULL::jsonb, p_reply_to text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint;
begin
  if not coalesce((select allowed_to_email from public.founder_mail_policy where kind = p_kind), false) then
    raise exception 'founder_mail_policy does not allow % to email the founder', p_kind;
  end if;
  insert into public.notifications (type, kind, to_email, to_role, subject, body, status, channel, attachments, reply_to, requested_by)
  values (p_kind, p_kind, public.fn_marketing_founder_email(), 'founder', p_subject, p_body, 'queued', 'email',
          p_attachments, p_reply_to, 'marketing')
  returning id into v_id;
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_manual_outreach_targets()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select public.fn_marketing_supplier_outreach_targets(3)
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_month_covered_by_approved_calendar(p_month date)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists (
    select 1 from public.marketing_campaign c join public.marketing_post p on p.campaign_id = c.id
     where not c.is_demo and c.approved_hash is not null and p.status <> 'cancelled'
       and (p.scheduled_at at time zone 'Asia/Dubai')::date >= date_trunc('month', p_month)::date
       and (p.scheduled_at at time zone 'Asia/Dubai')::date <  (date_trunc('month', p_month) + interval '1 month')::date)
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_month_plan_duty()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_month date := (date_trunc('month', v_today) + interval '1 month')::date;
  v_tick jsonb; m public.marketing_month_plan;
begin
  v_tick := public.fn_marketing_month_plan_tick(v_today);
  select * into m from public.marketing_month_plan where month = v_month;
  if v_month >= date '2026-11-01' and extract(day from v_today) >= 20 and m.plan_sent_at is null
     and not public.fn_marketing_month_covered_by_approved_calendar(v_month) then
    raise exception 'the plan for % is not with the founder on %: %', to_char(v_month, 'YYYY-MM'), v_today, v_tick::text;
  end if;
  return jsonb_build_object('month', v_month, 'tick', v_tick, 'status', m.status, 'sent_at', m.plan_sent_at,
    'founder_decided_at', m.founder_decided_at, 'paid_allowed', public.fn_marketing_paid_allowed());
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_month_plan_founder_decides(p_month date, p_accepted boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare p public.marketing_month_plan;
begin
  update public.marketing_month_plan
     set status = case when p_accepted then 'accepted' else 'rejected' end, founder_decided_at = now(),
         founder_note = p_note, updated_at = now()
   where month = p_month and status = 'sent_to_founder' returning * into p;
  if p.month is null then raise exception 'no brief for % is waiting for the founder', p_month; end if;
  return jsonb_build_object('ok', true, 'month', p.month, 'status', p.status);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_month_plan_ideas(p_today date, p_month date, p_include_demo boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_ideas jsonb; v_learned jsonb; v_shifted jsonb;
begin
  v_learned := public.fn_marketing_learning(date_trunc('month', p_today)::date, p_include_demo);
  -- topics that brought registrations, best per post first; only enabled ideas can be planned; at most 6 of 12
  with won as (select r->>'value' as topic, (r->>'per_post')::numeric as pp, (r->>'registrations')::int as n
                 from jsonb_array_elements(coalesce(v_learned->'dimensions'->'topic', '[]'::jsonb)) r
                where (r->>'registrations')::int > 0),
       ranked as (select i.id, i.idea_key, row_number() over (order by w.pp desc nulls last, w.n desc, i.id) as won_rank
                    from public.marketing_video_idea i join won w on w.topic in (i.idea_key, lower(i.title)) where i.enabled)
  select coalesce(jsonb_agg(idea_key order by won_rank), '[]'::jsonb) into v_shifted from ranked where won_rank <= 6;

  with days as (select d, row_number() over (order by d) n from public.fn_marketing_video_days(p_month, 12) d),
       picks as (select i.*, row_number() over (order by coalesce(array_position(array(select jsonb_array_elements_text(v_shifted)), i.idea_key), 1000),
                                                         i.last_planned_month nulls first, i.id) n
                   from public.marketing_video_idea i where i.enabled)
  select jsonb_agg(jsonb_build_object('n', d.n, 'date', d.d, 'idea_key', p.idea_key, 'title', p.title, 'hook', p.hook,
                                      'film_plan', p.film_plan, 'cta', p.cta, 'audience', p.audience,
                                      'why', case when v_shifted ? p.idea_key then 'brought registrations' else 'rotation' end) order by d.n)
    into v_ideas
    from days d join picks p on p.n = d.n;
  if v_ideas is null then raise exception 'marketing_month_plan: no enabled ideas or no working days in %', p_month; end if;
  return jsonb_build_object('by', 'code', 'ideas', v_ideas, 'learned', v_learned, 'shifted_to', v_shifted);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_month_plan_reply(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  m public.marketing_month_plan; v_from text := lower(btrim(coalesce(p->>'from_email', ''))); v_rid bigint; v_msg text; v_out text;
  v_atts text[] := coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p->'attachments', '[]'::jsonb)) x), '{}');
begin
  select * into m from public.marketing_month_plan where plan_token = lower(coalesce(p->>'token', '')) for update;
  if v_from is distinct from public.fn_marketing_founder_email() then
    return jsonb_build_object('outcome', 'not_the_founder', 'month', m.month);
  end if;
  if m.month is null then
    v_out := 'unknown_plan';
    v_msg := 'Your reply did not match a video plan email, so nothing was filed. Please reply to the latest plan email.';
  elsif not coalesce((p->>'authenticated')::boolean, false) then
    v_out := 'not_authenticated';
    v_msg := 'A reply to the video plan arrived with your address but our mail server could not verify it came from your mailbox, so nothing was filed. If it was you, reply again from your usual mail app.';
  else
    insert into public.marketing_founder_request (kind, month, founder_text, attachments, message_id)
    values ('month_content', m.month, left(btrim(coalesce(p->>'text', '')), 4000), v_atts, nullif(p->>'message_id', ''))
    on conflict (message_id) where message_id is not null and message_id <> '' do nothing
    returning id into v_rid;
    if v_rid is null then return jsonb_build_object('outcome', 'already_filed', 'month', m.month); end if;
    -- his reply with the content IS his acceptance of the plan (the columns fn_marketing_month_plan_founder_decides writes)
    update public.marketing_month_plan set status = 'accepted', founder_decided_at = now(),
           founder_note = left(btrim(coalesce(p->>'text', '')), 2000), updated_at = now() where month = m.month;
    v_out := 'content_received';
    v_msg := 'Received for ' || to_char(m.month, 'FMMonth YYYY') || ' (' || cardinality(v_atts) || ' attachment(s)). The marketing seat builds the calendar from it '
             || '(request ' || v_rid || ') and emails it to you; reply "approve" to that calendar and it is scheduled and published.';
  end if;
  perform public.fn_marketing_mail_founder('marketing_month_plan_reply',
    case when v_out = 'content_received' then 'Received: ' else 'Not filed: ' end || 'video plan ' || coalesce(to_char(m.month, 'FMMonth YYYY'), ''), v_msg);
  return jsonb_build_object('outcome', v_out, 'month', m.month, 'request_id', v_rid);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_month_plan_tick(p_today date DEFAULT NULL::date, p_include_demo boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_today date := coalesce(p_today, (now() at time zone 'Asia/Dubai')::date);
  v_month date := (date_trunc('month', v_today) + interval '1 month')::date;
  v_key text; p public.marketing_month_plan; n jsonb; v_built jsonb; v_ideas jsonb; v_token text; v_body text; v_nid bigint; v_mname text;
begin
  if v_month < date '2026-11-01' then return jsonb_build_object('sent', false, 'reason', 'the monthly loop starts with November 2026'); end if;
  v_key := 'marketing_month_plan:' || v_month;
  select * into p from public.marketing_month_plan where month = v_month;
  -- the argued plan owns a month once marketing has put it to the CEO; a sent or decided month is done
  if p.plan_sent_at is not null or p.status in ('with_ceo', 'agreed', 'brief_requested', 'sent_to_founder', 'accepted', 'rejected') then
    return jsonb_build_object('sent', false, 'reason', 'already planned', 'month', v_month, 'status', p.status);
  end if;
  v_mname := to_char(v_month, 'FMMonth YYYY');
  n := public.fn_ceo_decision_next(v_key);

  if p.status = 'ceo_reviewing' then
    if n->>'last_decision' = 'withdrawn' then
      update public.marketing_month_plan set status = 'rejected', updated_at = now(),
             verdict = coalesce(verdict, '{}'::jsonb) || jsonb_build_object('ceo', jsonb_build_object('decision', 'withdrawn'))
       where month = v_month;
      return jsonb_build_object('sent', false, 'month', v_month, 'reason', 'the CEO withdrew the plan after four rejections');
    end if;
    if n->>'last_decision' = 'replaced' and (n->>'round')::int = 1 and p.ceo_held_id is not null
       and exists (select 1 from public.reasoning_held_question h where h.id = p.ceo_held_id
                    and (h.subject->>'generation')::int < (n->>'generation')::int) then
      -- replaced: a fresh draft, a fresh count
      v_built := public.fn_marketing_month_plan_ideas(v_today, v_month, p_include_demo);
      update public.marketing_month_plan set plan = v_built, content_brief = jsonb_build_object('videos', jsonb_build_object('count', jsonb_array_length(v_built->'ideas')), 'ideas', v_built->'ideas'),
             updated_at = now() where month = v_month;
      update public.marketing_video_idea set last_planned_month = v_month
       where idea_key in (select e->>'idea_key' from jsonb_array_elements(v_built->'ideas') e);
    end if;
    return jsonb_build_object('sent', false, 'month', v_month, 'with_ceo', true, 'filed', public.fn_marketing_month_plan_to_ceo(v_month));
  end if;

  if p.status is distinct from 'ceo_approved' then
    -- first draft (no row, or the argued path's evaluation draft with no plan put to the CEO yet): to the CEO, not the founder
    v_built := public.fn_marketing_month_plan_ideas(v_today, v_month, p_include_demo);
    insert into public.marketing_month_plan as t (month, status, verdict, plan, content_brief)
    values (v_month, 'ceo_reviewing',
            jsonb_build_object('by', 'code', 'rule', 'founder 24 Sep 2026: the monthly idea plan is routine work, coded; 28 Sep (1009): it leans on what brought registrations; 29 Sep: the CEO reviews it first (1059)'),
            v_built, jsonb_build_object('videos', jsonb_build_object('count', jsonb_array_length(v_built->'ideas')), 'ideas', v_built->'ideas'))
    on conflict (month) do update set status = excluded.status, verdict = coalesce(t.verdict, excluded.verdict), plan = excluded.plan,
           content_brief = excluded.content_brief, updated_at = now();
    update public.marketing_video_idea set last_planned_month = v_month
     where idea_key in (select e->>'idea_key' from jsonb_array_elements(v_built->'ideas') e);
    return jsonb_build_object('sent', false, 'month', v_month, 'with_ceo', true, 'ideas', jsonb_array_length(v_built->'ideas'),
                              'filed', public.fn_marketing_month_plan_to_ceo(v_month));
  end if;

  -- ceo_approved: the founder gets the plan the CEO approved, once
  v_ideas := p.plan->'ideas';
  v_token := encode(extensions.gen_random_bytes(16), 'hex');
  v_body := 'Here is the video plan for ' || v_mname || ': ' || jsonb_array_length(v_ideas)
         || ' short videos on UAE working days (Monday, Wednesday, Thursday first; no weekends or public holidays).' || E'\n\n'
         || 'The CEO reviewed it and approved it' || coalesce(' in round ' || (p.verdict->'ceo'->>'round'), '') || ': '
         || coalesce(p.verdict->'ceo'->>'reasons', '') || E'\n\n'
         || coalesce((select string_agg(format('Round %s, the CEO asked: %s' || E'\n' || 'Marketing changed: %s', x->>'round', x->>'ceo_reasons', coalesce(x->>'revision', x->>'answers')), E'\n\n')
                        from jsonb_array_elements(coalesce(p.plan->'revisions', '[]'::jsonb)) x) || E'\n\n', '')
         || public.fn_marketing_learning_text(p.plan->'learned', coalesce(p.plan->'shifted_to', '[]'::jsonb)) || E'\n\n'
         || (select string_agg(format(E'%s. %s — %s%s\n   Hook: %s\n   Film: %s\n   Call to action: %s',
                                      e->>'n', to_char((e->>'date')::date, 'Dy DD Mon'), e->>'title',
                                      case when e->>'why' = 'brought registrations' then ' (brought registrations)' else '' end,
                                      e->>'hook', e->>'film_plan', e->>'cta'),
                               E'\n\n' order by (e->>'n')::int)
               from jsonb_array_elements(v_ideas) e)
         || E'\n\nWhen the videos are ready, reply to this email with them (attachments or links). Change any idea by saying so in the same reply. '
         || 'The marketing seat then builds the calendar (dates, times per platform, captions, hashtags, links) and sends it to you; '
         || 'replying "approve" to that calendar schedules and publishes it.';
  v_nid := public.fn_marketing_mail_founder('marketing_month_plan', 'Video plan for ' || v_mname || ' [plan ' || v_token || ']',
                                            v_body, null, 'plan+' || v_token || '@mail.quotesdone.com');
  update public.marketing_month_plan set status = 'sent_to_founder', plan_token = v_token, plan_notification_id = v_nid,
         plan_sent_at = now(), updated_at = now()
   where month = v_month;
  return jsonb_build_object('sent', true, 'month', v_month, 'ideas', jsonb_array_length(v_ideas), 'notification_id', v_nid,
                            'ceo_round', p.verdict->'ceo'->'round', 'has_data', p.plan->'learned'->'has_data', 'shifted_to', p.plan->'shifted_to');
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_month_plan_to_ceo(p_month date, p_resubmitted boolean DEFAULT false)
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
      || 'As the chief executive, review it before it goes to the founder. Approve it, or reject it and say exactly what '
      || 'marketing must change. Either way give your reasons: they go to marketing and, on approval, to the founder.',
    '[{"id":"approve","meaning":"the plan goes to the founder for his one approval of the month"},{"id":"reject","meaning":"the plan goes back to marketing with your reasons, to revise and resubmit"}]'::jsonb,
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


CREATE OR REPLACE FUNCTION public.fn_marketing_next_working_slot(p_at timestamp with time zone)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v timestamptz := p_at; i int := 0;
begin
  if v is null then return null; end if;
  while not public.fn_is_working_day((v at time zone 'Asia/Dubai')::date) loop
    v := v + interval '1 day'; i := i + 1;
    if i > 30 then raise exception 'no UAE working day within 30 days of %', p_at; end if;
  end loop;
  return v;
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_notes_ad_spend_booked(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions; d jsonb; r public.ad_spend_reported; v_ok boolean; v_why text;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found or a.detail->>'type' is distinct from 'adspend.booked' then
    raise exception 'fn_marketing_notes_ad_spend_booked: % is not an adspend.booked handoff', p_id;
  end if;
  d := a.detail;
  select * into r from public.ad_spend_reported where source_ref = d->>'source_ref';
  if coalesce((d->>'recorded')::boolean, false) then
    v_ok := r.source_ref is not null and r.amount = (d->>'amount')::numeric;
    v_why := case when r.source_ref is null then 'the accountant said recorded and no row exists'
                  when not v_ok then 'the accountant''s row says ' || r.amount || ', marketing reported ' || (d->>'amount') end;
  else
    v_ok := coalesce((d->>'test')::boolean, false);
    v_why := case when not v_ok then 'the accountant did not record real spend' end;
  end if;
  if v_ok then
    update public.marketing_ad_spend_day set booked_ack_at = now()
     where account_id || ':' || campaign_id || ':' || day = d->>'source_ref' and spend = (d->>'amount')::numeric;
  end if;
  return jsonb_build_object('verified', v_ok, 'reason', v_why, 'recorded_handoff', d->'recorded_handoff');
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_outreach_deliver(p_day date, p_ids bigint[], p_subject text, p_body text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_listed int; v_res jsonb; v_delivery jsonb;
begin
  select count(*) into v_listed from public.marketing_outreach_message where id = any (p_ids) and status = 'listed' and not is_demo;
  if public.fn_marketing_publishing_live() and v_listed > 0 then
    v_res := public.fn_notify_founder(p_event => p_subject, p_detail => p_body, p_level => 'normal',
                                      p_kind => 'marketing_outreach_list', p_dedupe_key => 'marketing_outreach_list:' || p_day);
    v_delivery := jsonb_build_object('mode', 'emailed', 'at', now(), 'notify', v_res);
  else
    v_delivery := jsonb_build_object('mode', 'dry_run', 'at', now(),
      'why', case when v_listed = 0 then 'nothing listed (held or demo)' else 'marketing_golive is not true' end,
      'subject', p_subject, 'body', left(p_body, 6000));
  end if;
  update public.marketing_outreach_message set delivery = v_delivery, updated_at = now() where id = any (p_ids);
  return v_delivery - 'body';
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_outreach_due(p_include_demo boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with d as (select (now() at time zone 'Asia/Dubai')::date as day, extract(hour from now() at time zone 'Asia/Dubai')::int as hr),
       n as (select least(3, greatest(0, public.fn_marketing_policy_int('marketing_outreach_per_day', 3))) as want)
  select jsonb_build_object(
    'day', d.day, 'want', n.want, 'live', public.fn_marketing_publishing_live(),
    'due', d.hr >= public.fn_marketing_policy_int('marketing_outreach_list_hour', 7)
           and not exists (select 1 from public.marketing_outreach_message m
                            where m.kind = 'first' and m.listed_on = d.day and (p_include_demo or not m.is_demo)),
    'prospects', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at, x.id) from (
        select p.id, p.full_name, p.role_title, p.company, p.segment, p.language, p.linkedin_url, p.opening_line, p.created_at
          from public.marketing_prospect p
         where p.status = 'new' and (p_include_demo or not p.is_demo)
         order by p.created_at, p.id limit n.want) x), '[]'::jsonb))
  from d, n
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_outreach_mark(p_token uuid, p_status text, p_reply text DEFAULT NULL::text, p_reply_class text DEFAULT NULL::text, p_follow_up text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_m public.marketing_outreach_message; v_follow uuid; v_person text;
begin
  select * into v_m from public.marketing_outreach_message where mark_token = p_token for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'unknown_link'); end if;
  if p_status not in ('sent', 'replied', 'converted', 'declined') then return jsonb_build_object('ok', false, 'error', 'unknown_status'); end if;
  if p_status = 'replied' and btrim(coalesce(p_reply, '')) = '' then return jsonb_build_object('ok', false, 'error', 'paste_the_reply'); end if;

  update public.marketing_outreach_message
     set status = p_status,
         sent_at = coalesce(sent_at, case when p_status in ('sent', 'replied', 'converted') then now() end),
         replied_at = case when p_status = 'replied' then now() else replied_at end,
         converted_at = case when p_status = 'converted' then now() else converted_at end,
         reply_text = case when p_status = 'replied' then left(p_reply, 4000) else reply_text end,
         reply_class = case when p_status = 'replied' then p_reply_class else reply_class end,
         updated_at = now()
   where id = v_m.id;

  v_person := case when p_status = 'declined' or p_reply_class = 'decline' then 'declined' else p_status end;
  -- a person only moves forward: a late "sent" tap never undoes a reply or a conversion
  update public.marketing_prospect set status = v_person, updated_at = now()
   where id = v_m.prospect_id
     and array_position(array['new', 'listed', 'sent', 'replied', 'converted'], status) <= coalesce(array_position(array['new', 'listed', 'sent', 'replied', 'converted'], v_person), 99)
     and status <> 'declined';

  if p_status = 'replied' and btrim(coalesce(p_follow_up, '')) <> '' then
    insert into public.marketing_outreach_message (prospect_id, kind, language, body, lint, listed_on, status, is_demo)
    values (v_m.prospect_id, 'follow_up', v_m.language, p_follow_up, '[]'::jsonb, (now() at time zone 'Asia/Dubai')::date, 'listed', v_m.is_demo)
    returning mark_token into v_follow;
  end if;
  return jsonb_build_object('ok', true, 'status', p_status, 'person', v_person, 'follow_up_token', v_follow);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_outreach_page(p_token uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object('id', m.id, 'kind', m.kind, 'status', m.status, 'language', m.language, 'body', m.body, 'note', m.note,
           'reply_text', m.reply_text,
           'prospect', jsonb_build_object('full_name', p.full_name, 'role_title', p.role_title, 'company', p.company,
                                          'linkedin_url', p.linkedin_url, 'status', p.status),
           'follow_ups', coalesce((select jsonb_agg(jsonb_build_object('body', f.body, 'token', f.mark_token, 'status', f.status) order by f.id)
                                     from public.marketing_outreach_message f where f.prospect_id = m.prospect_id and f.kind = 'follow_up' and f.id > m.id), '[]'::jsonb))
    from public.marketing_outreach_message m join public.marketing_prospect p on p.id = m.prospect_id
   where m.mark_token = p_token
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_outreach_record(p_day date, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_live boolean := public.fn_marketing_publishing_live(); v_out jsonb;
begin
  with ins as (
    insert into public.marketing_outreach_message (prospect_id, kind, language, body, note, lint, listed_on, status, is_demo)
    select (i->>'prospect_id')::bigint, 'first', i->>'language', i->>'body', i->>'note', coalesce(i->'lint', '[]'::jsonb), p_day,
           case when v_live and not p.is_demo then 'listed' else 'draft' end, p.is_demo
      from jsonb_array_elements(p_items) i
      join public.marketing_prospect p on p.id = (i->>'prospect_id')::bigint and p.status = 'new'
    on conflict (prospect_id) where kind = 'first' do update
       set language = excluded.language, body = excluded.body, note = excluded.note, lint = excluded.lint,
           listed_on = excluded.listed_on, status = excluded.status, updated_at = now()
     where marketing_outreach_message.status = 'draft'
    returning id, prospect_id, mark_token, status
  ), used as (
    update public.marketing_prospect p set status = 'listed', updated_at = now()
      from ins where ins.prospect_id = p.id and ins.status = 'listed'
    returning p.id
  )
  select jsonb_build_object('live', v_live, 'items',
           coalesce(jsonb_agg(jsonb_build_object('id', ins.id, 'prospect_id', ins.prospect_id, 'token', ins.mark_token, 'status', ins.status)), '[]'::jsonb),
           'used', (select count(*) from used))
    into v_out from ins;
  return v_out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_outreach_reply_reasoned(p_token uuid, p_class text, p_follow_up text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_m public.marketing_outreach_message; v_follow uuid;
begin
  if p_class is null or p_class not in ('decline', 'later', 'positive', 'question') then
    raise exception 'fn_marketing_outreach_reply_reasoned: % is not a reply class', p_class using errcode = '22023';
  end if;
  select * into v_m from public.marketing_outreach_message where mark_token = p_token for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'unknown_link'); end if;
  if v_m.status is distinct from 'replied' then return jsonb_build_object('ok', false, 'error', 'not_a_reply'); end if;
  if v_m.reply_class is not null then return jsonb_build_object('ok', true, 'already', v_m.reply_class); end if;
  update public.marketing_outreach_message set reply_class = p_class, updated_at = now() where id = v_m.id;
  if p_class = 'decline' then
    update public.marketing_prospect set status = 'declined', updated_at = now() where id = v_m.prospect_id and status <> 'declined';
  end if;
  if btrim(coalesce(p_follow_up, '')) <> ''
     and not exists (select 1 from public.marketing_outreach_message f where f.prospect_id = v_m.prospect_id and f.kind = 'follow_up' and f.id > v_m.id) then
    insert into public.marketing_outreach_message (prospect_id, kind, language, body, lint, listed_on, status, is_demo)
    values (v_m.prospect_id, 'follow_up', v_m.language, p_follow_up, '[]'::jsonb, (now() at time zone 'Asia/Dubai')::date, 'listed', v_m.is_demo)
    returning mark_token into v_follow;
  end if;
  return jsonb_build_object('ok', true, 'class', p_class, 'follow_up_token', v_follow);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_paid_allowed()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists (select 1 from public.v_category_open) and not exists (select 1 from public.v_category_open where not is_open)
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_plan_calendar(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_today date := (p_at at time zone 'Asia/Dubai')::date;
        v_next date := (date_trunc('month', v_today) + interval '1 month')::date;
        v_deadline date := v_next - 1 - 7; v_start date; n int := 0;
begin
  while extract(isodow from v_deadline) in (6, 7) loop v_deadline := v_deadline - 1; end loop;   -- UAE weekend Sat/Sun
  v_start := v_deadline;
  while n < 2 loop v_start := v_start - 1; if extract(isodow from v_start) not in (6, 7) then n := n + 1; end if; end loop;
  return jsonb_build_object('today', v_today, 'plan_month', v_next, 'evaluated_month', date_trunc('month', v_today)::date,
                            'start', v_start, 'deadline', v_deadline, 'in_window', v_today >= v_start);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_plan_loop_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare p public.marketing_month_plan; n_closed int := 0; n_sent int := 0; n_taken int := 0; v_id bigint; b jsonb; v_status text; r jsonb;
        v_refused jsonb := '[]'::jsonb; n_delivered int := 0; n_quarantined int := 0; q record;
begin
  for p in select * from public.marketing_month_plan where status = 'with_ceo' order by month loop
    begin
      perform public.fn_marketing_plan_to_ceo(p.month);
    exception when others then
      v_refused := v_refused || jsonb_build_object('month', p.month, 'why', left(sqlerrm, 300));
    end;
    r := public.fn_marketing_takes_the_ceo_review(p.month);
    if coalesce((r->>'taken')::boolean, false) then n_taken := n_taken + 1; end if;
  end loop;
  for p in select * from public.marketing_month_plan where status = 'agreed' order by month loop
    if p.deliberation_id is not null and to_regclass('public.seat_deliberation') is not null then
      select status into v_status from public.seat_deliberation where id = p.deliberation_id;
      if v_status in ('reviewed', 'no_independent_reviewer') then
        perform public.fn_seat_deliberation_close(p.deliberation_id, 'marketing', 'agreed after ' || p.rounds || ' round(s)');
        n_closed := n_closed + 1;
      end if;
    end if;
    if p.brief_handoff_id is null then
      b := p.content_brief;
      v_id := public.fn_seat_handoff('marketing', 'customer_support', 'delivery.request', 'marketing_month_plan', 'brief:' || p.month::text,
        jsonb_build_object('recipient_role', 'founder', 'kind', 'marketing_content_brief', 'level', 'medium',
          'dedupe_key', 'marketing_content_brief:' || p.month::text,
          'event', 'The content brief for ' || to_char(p.month, 'FMMonth YYYY') || ' (agreed with the CEO)',
          'detail', 'Marketing and the CEO agreed next month''s organic plan in ' || p.rounds || ' round(s). What to produce:'
            || E'\n\nVideos: ' || coalesce(b->'videos'->>'count', '?') || ' x ' || coalesce(b->'videos'->>'length_s', '?') || ' s'
            || E'\nTopics: ' || coalesce((select string_agg(coalesce(t->>'title', t #>> '{}'), '; ') from jsonb_array_elements(b->'topics') t), '-')
            || E'\nFormats: ' || coalesce((select string_agg(x #>> '{}', ', ') from jsonb_array_elements(b->'formats') x), '-')
            || E'\nMusic: ' || coalesce(b->'music'->>'direction', b->>'music', '-')
            || E'\nVoice-over: ' || coalesce(b->'voiceover'->>'use', '-') || coalesce(' (' || (b->'voiceover'->>'language') || ')', '')
            || E'\nCadence: ' || coalesce(b->'cadence'->>'posts_per_week', '?') || ' posts a week'
            || E'\n\nOrganic only: no ads and no paid promotion. Every turn of the discussion is in marketing_plan_review_turn.'));
      update public.marketing_month_plan set brief_handoff_id = v_id, status = 'brief_requested', updated_at = now() where month = p.month;
      n_sent := n_sent + 1;
    end if;
  end loop;
  -- SENT MEANS THE OUTBOX SAYS SENT (review of #876): the brief is 'brief_requested' until the notification that
  -- customer_support queued for it reads status 'sent'.
  for p in select * from public.marketing_month_plan where status = 'brief_requested' order by month loop
    if exists (select 1 from public.agent_actions a join public.notifications nt on nt.id::text = coalesce(a.detail->>'retry_notification_id', a.evidence->>'notification_id')
                where a.id = p.brief_handoff_id and nt.status = 'sent') then
      update public.marketing_month_plan set status = 'sent_to_founder', updated_at = now() where month = p.month;
      n_delivered := n_delivered + 1;
    end if;
  end loop;
  -- A QUARANTINED SUBJECT IS A FINDING OWNED BY MARKETING, not a silent gap in the queue.
  for q in select distinct r.step, r.subject from public.marketing_model_run r
            where r.outcome in ('rejected','failed')
              and public.fn_marketing_subject_blocked(r.step, r.subject) like 'quarantined%' loop
    perform public.fn_it_engineer_finding_upsert('marketing:step_quarantined:' || q.step || ':' || q.subject,
      'Marketing step ' || q.step || ' failed 3 days running on ' || left(q.subject, 40) || ' and left the queue',
      'public.fn_marketing_steps_due (marketing)', 'agent_facing', 1,
      jsonb_build_object('owner_seat', 'marketing', 'step', q.step, 'subject', q.subject,
        'last_reasons', (select jsonb_agg(reason order by id desc) from (select id, reason from public.marketing_model_run
                          where step = q.step and subject = q.subject and outcome in ('rejected','failed') order by id desc limit 3) z)),
      '{}'::text[], array['why the step keeps failing on this subject (see last_reasons)'], 'fn_marketing_plan_loop_tick');
    n_quarantined := n_quarantined + 1;
  end loop;
  return jsonb_build_object('ok', true, 'ceo_reviews_taken', n_taken, 'deliberations_closed', n_closed, 'briefs_sent', n_sent,
                            'briefs_delivered', n_delivered, 'quarantined', n_quarantined,
                            'not_yet_before_the_ceo', v_refused);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_plan_problems(p_plan jsonb)
 RETURNS text[]
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare bad text[] := '{}'; k text;
begin
  if p_plan is null or jsonb_typeof(p_plan) <> 'object' then return array['plan must be an object']; end if;
  foreach k in array array['topics','formats','music','voiceover','video','cadence','budget'] loop
    if not p_plan ? k then bad := bad || ('plan is missing ' || k); end if;
  end loop;
  if jsonb_typeof(p_plan->'topics') is distinct from 'array' or jsonb_array_length(coalesce(p_plan->'topics','[]')) = 0 then
    bad := bad || 'plan names no topics'::text; end if;
  if coalesce(public.fn_marketing_jnum(p_plan->'video'->'count'), 0) <= 0 then bad := bad || 'plan.video.count must be a number above 0'::text; end if;
  if coalesce(public.fn_marketing_jnum(p_plan->'video'->'length_s'), 0) <= 0 then bad := bad || 'plan.video.length_s must be a number above 0'::text; end if;
  if p_plan->'budget' ? 'ad_spend_aed' and public.fn_marketing_jnum(p_plan->'budget'->'ad_spend_aed') is distinct from 0 then
    bad := bad || 'ORGANIC ONLY (founder 866): plan.budget.ad_spend_aed must be the number 0'::text; end if;
  -- ORGANIC ONLY BY STRUCTURE, NOT WORDING: a paid-promotion FIELD anywhere in the plan (a key such as paid_*, ad(s)_*,
  -- boost*, sponsor*, promot*), or money in the budget on any line but the model's, is refused. Prose is free to say
  -- "we will not boost"; a regex over prose refused exactly that.
  if exists (with recursive k(key, val) as (
               select e.key, e.value from jsonb_each(p_plan) e
               union all
               select e.key, e.value from k, jsonb_each(k.val) e where jsonb_typeof(k.val) = 'object')
             select 1 from k where k.key ~* '^(paid|ads?(_|$)|boost|sponsor|promot)' and k.key <> 'ad_spend_aed') then
    bad := bad || 'ORGANIC ONLY (founder 866): the plan carries a paid-promotion field'::text; end if;
  if jsonb_typeof(p_plan->'budget') = 'object' and exists (select 1 from jsonb_each(p_plan->'budget') b
       where b.key not in ('model_aed', 'ad_spend_aed') and coalesce(public.fn_marketing_jnum(b.value), 0) <> 0) then
    bad := bad || 'ORGANIC ONLY (founder 866): the only money in the plan is model_aed'::text; end if;
  return bad;
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_plan_review_packet(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare p public.marketing_month_plan; v_last public.marketing_plan_review_turn; v_assets text[]; v_cited int;
        v_flags jsonb := '[]'::jsonb; v_round int;
begin
  select * into p from public.marketing_month_plan where month = p_month;
  if p.plan is null then raise exception 'no plan for % to review', p_month; end if;
  select * into v_last from public.marketing_plan_review_turn where month = p_month and seat = 'marketing' order by id desc limit 1;
  v_round := coalesce(v_last.round, 1);
  select coalesce(array_agg(distinct s), '{}') into v_assets
    from public.marketing_plan_review_turn t, unnest(public.fn_marketing_assets_cited(t.evidence)) s
   where t.month = p_month and t.seat = 'marketing' and s not like 'post:%';
  if cardinality(v_assets) = 0 then
    select coalesce(array_agg(distinct file_sha256), '{}') into v_assets from public.marketing_asset_perception;
  end if;
  v_cited := cardinality(public.fn_marketing_assets_cited(v_last.evidence));
  if coalesce(v_cited, 0) <= 2 then
    v_flags := jsonb_build_array(jsonb_build_object('criterion', 'evidence_strength', 'flag', 'thin_evidence', 'cited_videos_or_posts', coalesce(v_cited, 0),
      'rule', 'the proposal rests on ' || coalesce(v_cited, 0) || ' video(s)/post(s); month 1 is 12 videos. Treat it as a hypothesis, not a finding, and say so (criteria.evidence_strength.flagged = true).'));
  end if;
  return jsonb_build_object(
    'question', 'Should the company run this organic content plan for ' || to_char(p_month, 'FMMonth YYYY') || '? '
      || 'You can see the videos it rests on: each dossier in the evidence says what the video shows and sounds like, its measured features and its results. '
      || 'Judge it yourself on FIVE criteria and add them to your JSON as criteria{name: {assessment, reasoning, evidence:[{kind, ref, point}]}}: '
      || '(1) business_goal: does it move supplier registrations toward 1,000 and this month''s target in company_plan, not vanity metrics; '
      || '(2) evidence_strength: sample size and noise; a claim resting on 1-2 posts is a hypothesis, not a finding (see deterministic_flags; add flagged: true|false); '
      || '(3) production_cost: the founder and Claude make the content, so every ask must justify its effort; '
      || '(4) truth_and_brand_fit: no false claim, fits the supplier-first stage; (5) risk_if_wrong. '
      || 'On revise or reject also add changes:[{what, why}] - specific, answerable asks. Organic only: no ads, boosting or paid promotion. '
      || 'This is round ' || v_round || ' of at most 3' || case when v_round >= 3 then '; your verdict now DECIDES.' else '.' end,
    'evidence', jsonb_build_object('month', p_month,
      'videos', (select coalesce(jsonb_agg(public.fn_marketing_asset_dossier(a) order by a), '[]'::jsonb) from unnest(v_assets[1:12]) a),
      'key_frames', (select coalesce(jsonb_agg(k), '[]'::jsonb) from (
          select k from unnest(v_assets[1:12]) a,
                 lateral (select k from jsonb_array_elements((select keyframes from public.marketing_asset_feature
                                                               where file_sha256 = a order by measured_at desc limit 1)) k limit 3) f
          limit 24) z),
      'deterministic_flags', v_flags,
      'company_plan', (select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) from public.ceo_plan_month c where month = p_month),
      'market_posts', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'url', source_url, 'caption', left(detail, 300), 'metrics', metrics)), '[]'::jsonb)
                         from (select * from public.market_intel where platform is not null order by id desc limit 40) m)),
    'proposal', jsonb_build_object('month', p_month, 'plan', p.plan, 'round', v_round,
      'reasoning', v_last.reasoning, 'answers_to_the_ceo', v_last.answers, 'cited', v_last.evidence,
      'verdict_on_last_month', p.verdict));
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_plan_to_ceo(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare p public.marketing_month_plan; pk jsonb; v_id bigint; v_ceo public.marketing_plan_review_turn;
        v_mkt public.marketing_plan_review_turn; v_status text; v_round int; v_author text;
begin
  select * into p from public.marketing_month_plan where month = p_month;
  if p.plan is null or p.status <> 'with_ceo' then return jsonb_build_object('ok', true, 'action', 'none', 'status', p.status); end if;
  if to_regprocedure('public.fn_seat_deliberation_open(text,text,text,text,jsonb,jsonb,text,text,text,text,boolean)') is null then
    return jsonb_build_object('ok', false, 'action', 'waiting', 'why', 'seat_deliberation (founder_instruction 873) is not applied; the plan waits for it');
  end if;
  select * into v_ceo from public.marketing_plan_review_turn where month = p_month and seat = 'ceo' order by id desc limit 1;
  select * into v_mkt from public.marketing_plan_review_turn where month = p_month and seat = 'marketing' order by id desc limit 1;
  v_author := coalesce((select model_id from public.model_registry where model_id = v_mkt.model), (select model_primary from public.model_policy where task_class = 'marketing_plan' and active));  -- 18 Oct 2026 (ledger 1240): the plan's own class, never a retired model
  pk := public.fn_marketing_plan_review_packet(p_month);

  if p.deliberation_id is not null then
    select status, round into v_status, v_round from public.seat_deliberation where id = p.deliberation_id;
    if v_mkt.id is not distinct from p.sent_turn_id then
      return jsonb_build_object('ok', true, 'action', 'none', 'deliberation_id', p.deliberation_id, 'status', v_status);
    end if;
    -- revise only what the machine itself asked to revise; a CEO request that criterion 2 produced from an
    -- approval (see fn_marketing_takes_the_ceo_review) closes this deliberation and opens the next round fresh.
    if v_ceo.move = 'request_changes' and v_status = 'reviewed' and v_round < 3
       and (select t.verdict from public.seat_deliberation_turn t where t.id = v_ceo.deliberation_turn_id) = 'revise' then
      perform public.fn_seat_deliberation_revise(p.deliberation_id, pk->'proposal', v_author);
      update public.marketing_month_plan set sent_turn_id = v_mkt.id, updated_at = now() where month = p_month;
      return jsonb_build_object('ok', true, 'action', 'revised', 'deliberation_id', p.deliberation_id);
    end if;
    if v_status in ('reviewed', 'no_independent_reviewer') then
      perform public.fn_seat_deliberation_close(p.deliberation_id, 'marketing',
        'the CEO''s round ' || coalesce(v_ceo.round, 0) || ' ended in ' || coalesce(v_ceo.move, '?')
        || case when v_ceo.reasoning like '%Criterion 2 applied by code%' then ' (criterion 2, measured by code)' else '' end
        || '; marketing''s answer goes to a new review');
    end if;
  end if;

  v_id := public.fn_seat_deliberation_open('marketing.monthly_plan', 'marketing', 'ceo', pk->>'question', pk->'evidence', pk->'proposal',
            v_author, 'marketing_plan', 'marketing_month_plan', p_month::text, false);
  update public.seat_deliberation set max_rounds = 3 where id = v_id;
  update public.marketing_month_plan set deliberation_id = v_id, sent_turn_id = v_mkt.id, updated_at = now() where month = p_month;
  return jsonb_build_object('ok', true, 'action', 'opened', 'deliberation_id', v_id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_platform_spec_freshness()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_items jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'item', md5(source_url),
           'title', case when seen_hash is distinct from verified_hash
                         then 'platform spec source changed since it was verified: ' || source_url
                         else 'platform spec source could not be read (' || coalesce(last_status::text, 'no status') || '): ' || source_url end,
           'owner_seat', 'marketing', 'subject', 'marketing', 'blast', 'agent_facing',
           'affected', (select count(*) from public.marketing_platform_spec p where p.source_url = s.source_url),
           'evidence', jsonb_build_object('url', source_url, 'checked_at', checked_at, 'verified_at', verified_at,
                                          'status', last_status, 'error', last_error,
                                          'remedy', 'Re-read the page, correct marketing_platform_spec, then call fn_marketing_platform_spec_source_verified(url, who).'))), '[]'::jsonb)
    into v_items
    from public.marketing_platform_spec_source s
   where (seen_hash is distinct from verified_hash)
      -- a timeout or network error leaves status 0; an HTTP error leaves its code. Both are reported.
      or (checked_at is not null and (coalesce(last_status, 0) = 0 or last_status >= 400));
  return public.fn_it_duty_settle('marketing_platform_spec_freshness', v_items);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_platform_spec_knowledge_sync()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare p text; v_body text; v_n int := 0;
begin
  for p in select distinct platform from public.marketing_platform_spec order by 1 loop
    select format(E'Posting limits for %s (organic), read from the official pages on the dates shown. '
                  'A limit marked "silent" is one the platform does not publish: do not state a number for it.\n\n', initcap(p))
        || string_agg(format('- %s / %s: %s%s%s. Source: %s (read %s, confidence %s)%s',
                        surface, replace(attribute, '_', ' '),
                        coalesce(value_text, value_num::text, 'silent'),
                        case when value_num is not null and value_text is not null then ' = ' || value_num::text else '' end,
                        case when counted_as is not null then ' ' || coalesce(unit, '') || ', counted as ' || counted_as
                             when unit is not null and value_num is not null then ' ' || unit else '' end,
                        source_url, read_on, confidence, coalesce('. ' || note, '')),
                      E'\n' order by surface, attribute)
      into v_body
      from public.marketing_platform_spec where platform = p;
    insert into public.ops_knowledge(
      record_id, scope_type, scope_key, role_key, layer, module, record_type, title, content, structured_data,
      source_ids, implementation_status, validation_status, authority_tier, risk_level, version, keywords,
      jurisdiction, source_freshness, confidentiality, runtime_eligible, deterministic, supersession_state,
      embedding_status, effective_date)
    values (
      'qd-marketing:platform-spec:' || p, 'role', 'marketing', 'marketing', 'source_reference', 'marketing_platform_spec',
      'md', initcap(p) || ' posting limits: caption length, hashtags, aspect ratio, duration, file size', v_body,
      jsonb_build_object('table', 'marketing_platform_spec', 'platform', p),
      array['marketing_platform_spec'], 'active', 'validated', 'autonomous', 'low', '1',
      array[p, 'caption limit', 'character limit', 'hashtags', 'aspect ratio', 'video length', 'duration', 'file size',
            'resolution', 'thumbnail', 'safe zone', 'reels', 'shorts'],
      'international', 'monthly', 'internal', true, true, 'current', 'pending', current_date)
    on conflict (record_id) do update set
      title = excluded.title, content = excluded.content, structured_data = excluded.structured_data,
      keywords = excluded.keywords, effective_date = excluded.effective_date,
      supersession_state = 'current', embedding_status = 'pending';
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'records', v_n);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_platform_spec_problems(p_platform text, p_post_type text, p_body text, p_hashtags text[], p_title text, p_alt_text text, p_first_comment text)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_pf text := lower(btrim(coalesce(p_platform, '')));
  v_pt text := lower(btrim(coalesce(p_post_type, '')));
  v_sf text; v_tags text;
begin
  v_sf := case
    when v_pf = 'instagram' then case v_pt when 'reel' then 'reel' else 'feed_image' end
    when v_pf = 'facebook'  then case v_pt when 'reel' then 'reel' else 'feed_post' end
    when v_pf = 'youtube'   then case v_pt when 'short' then 'short' else 'video' end
    when v_pf = 'x'         then 'post'
    when v_pf = 'linkedin'  then 'page_post'
    when v_pf = 'tiktok'    then 'video'
    else v_pt end;
  select string_agg('#' || ltrim(btrim(t), '#'), ' ') into v_tags
    from unnest(coalesce(p_hashtags, '{}'::text[])) t where btrim(t) <> '';
  return coalesce((
    select array_agg(e->>'message')
      from jsonb_array_elements(public.fn_marketing_variant_violations(
             jsonb_build_object('platform', v_pf, 'surface', v_sf,
                                'caption', concat_ws(' ', nullif(btrim(coalesce(p_body, '')), ''), v_tags))
             || case when p_title is not null then jsonb_build_object('title', p_title) else '{}'::jsonb end)) e), '{}'::text[]);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_platform_spec_source_seen(p_url text, p_hash text, p_status integer, p_error text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.marketing_platform_spec_source;
begin
  update public.marketing_platform_spec_source
     set checked_at = now(), last_status = p_status, last_error = left(p_error, 300),
         seen_hash = coalesce(p_hash, seen_hash),
         verified_hash = coalesce(verified_hash, p_hash),
         verified_at = case when verified_hash is null and p_hash is not null then now() else verified_at end
   where source_url = p_url
  returning * into r;
  if not found then raise exception 'fn_marketing_platform_spec_source_seen: % is not a cited source', p_url; end if;
  return jsonb_build_object('url', r.source_url, 'changed', r.seen_hash is distinct from r.verified_hash, 'status', r.last_status);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_platform_spec_source_verified(p_url text, p_by text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if coalesce(btrim(p_by), '') = '' then raise exception 'fn_marketing_platform_spec_source_verified: say who re-read the page'; end if;
  update public.marketing_platform_spec_source set verified_hash = seen_hash, verified_at = now() where source_url = p_url;
  if not found then raise exception 'fn_marketing_platform_spec_source_verified: % is not a cited source', p_url; end if;
  update public.marketing_platform_spec set read_on = current_date where source_url = p_url;
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('marketing', 'ok', now(), now(), jsonb_build_object('action', 'platform_spec_verified', 'url', p_url), 'verified by ' || p_by);
  perform public.fn_marketing_platform_spec_knowledge_sync();
  return jsonb_build_object('ok', true, 'url', p_url);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_platform_spec_sources_due(p_limit integer DEFAULT 3)
 RETURNS SETOF text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select source_url from public.marketing_platform_spec_source
   where checked_at is null or checked_at < now() - interval '30 days'
   order by checked_at nulls first, source_url
   limit greatest(1, least(coalesce(p_limit, 3), 20))
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_policy_int(p_key text, p_default integer)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce((select (value #>> '{}')::int from public.decision_policy where key = p_key), p_default)
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_post_channel_record(p_post_id bigint, p_channels jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_post_checkpoints_due(p_limit integer DEFAULT 25)
 RETURNS TABLE(post_id bigint, platform text, platform_post_id text, postiz_post_id text, checkpoint text, published_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select pp.post_id, pp.platform, pp.platform_post_id, pp.postiz_post_id, c.checkpoint, p.published_at
    from public.marketing_post_platform pp
    join public.marketing_post p on p.id = pp.post_id
   cross join (values ('1d', 1), ('3d', 3), ('7d', 7), ('28d', 28)) c(checkpoint, days)
   where p.status = 'published' and not p.is_demo
     and now() >= p.published_at + make_interval(days => c.days)
     and now() <  p.published_at + make_interval(days => c.days * 2 + 1)
     and not exists (select 1 from public.marketing_post_metric m
                      where m.post_id = pp.post_id and m.platform = pp.platform and m.checkpoint = c.checkpoint)
   order by p.published_at, c.days
   limit greatest(1, least(coalesce(p_limit, 25), 100))
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_post_content_edited_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if tg_op = 'INSERT'
     or (old.ingest_key, old.scheduled_at, old.channels, old.video_path, old.video_sha256, old.cover_path, old.cover_sha256,
         old.media_paths, old.cta_url, old.is_demo, old.campaign_id, old.status = 'cancelled')
        is distinct from
        (new.ingest_key, new.scheduled_at, new.channels, new.video_path, new.video_sha256, new.cover_path, new.cover_sha256,
         new.media_paths, new.cta_url, new.is_demo, new.campaign_id, new.status = 'cancelled') then
    new.content_edited_at := now();
  else
    new.content_edited_at := old.content_edited_at;   -- a bookkeeping write never moves the clock, nor may it set it
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_post_guard_publish()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_why text;
begin
  -- Gated: the claim itself, an INSERT straight into flight, and a never-attempted post jumping to
  -- unconfirmed/published. A post with attempts > 0 passed this gate when it was claimed; recording that
  -- Postiz has it (reconcile, requeue) records what happened and is not gated again.
  if new.status in ('publishing', 'unconfirmed', 'published')
     and (tg_op = 'INSERT'
          or (old.status not in ('publishing', 'unconfirmed', 'published')
              and (new.status = 'publishing' or coalesce(old.attempts, 0) = 0))) then
    v_why := public.fn_marketing_post_publish_refusal(new);
    if v_why is not null then
      raise exception 'marketing_post % may not be published: %', coalesce(new.ingest_key, '?'), v_why
        using errcode = 'check_violation';
    end if;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_post_ingest(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_key text := lower(btrim(coalesce(p->>'ingest_key', '')));
  v_at timestamptz := nullif(p->>'scheduled_at', '')::timestamptz;
  v_media text[] := coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p->'media_paths', '[]'::jsonb)) x), '{}');
  v_ch text[] := coalesce((select array_agg(distinct lower(x)) from jsonb_array_elements_text(coalesce(p->'channels', '[]'::jsonb)) x), '{}');
  v_cur public.marketing_post; v_id bigint;
begin
  if public.fn_text_lost_its_script(p->>'text_ar') or public.fn_text_lost_its_script(p->>'text_en') then
    return jsonb_build_object('ok', false, 'error', 'text_lost_its_script',
      'message', 'The text arrived as question marks; send it as UTF-8 (scripts/marketing/ingest_post.mjs does).');
  end if;
  if v_at is not null and v_at < now() - interval '1 hour' then
    return jsonb_build_object('ok', false, 'error', 'scheduled_in_the_past',
      'message', 'scheduled_at is more than an hour ago; a past time would publish at once. Send a future time or none (draft).');
  end if;
  if exists (select 1 from unnest(v_media) m where m !~ '^posts/[a-z0-9_-]+/[A-Za-z0-9._-]+$') then
    return jsonb_build_object('ok', false, 'error', 'media_path_outside_the_bucket_layout',
      'message', 'media_paths are marketing-media objects under posts/<ingest_key>/.');
  end if;

  select * into v_cur from public.marketing_post where ingest_key = v_key for update;
  if found and v_cur.status not in ('draft', 'scheduled') then
    return jsonb_build_object('ok', true, 'id', v_cur.id, 'unchanged', true, 'status', v_cur.status,
      'message', 'Already ' || v_cur.status || '; a post that reached Postiz is not edited. Ingest it under a new key.');
  end if;

  insert into public.marketing_post (ingest_key, ingested_by, title, text_en, text_ar, media_paths, channels,
                                     scheduled_at, status, is_demo)
  values (v_key, coalesce(p->>'ingested_by', 'claude'), nullif(btrim(p->>'title'), ''), p->>'text_en', p->>'text_ar',
          v_media, v_ch, v_at, case when v_at is null then 'draft' else 'scheduled' end,
          coalesce((p->>'is_demo')::boolean, false))
  on conflict (ingest_key) do update
     set ingested_by = excluded.ingested_by, title = excluded.title, text_en = excluded.text_en,
         text_ar = excluded.text_ar, media_paths = excluded.media_paths, channels = excluded.channels,
         scheduled_at = excluded.scheduled_at, status = excluded.status, is_demo = excluded.is_demo,
         dry_run = null, updated_at = now()
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'status', case when v_at is null then 'draft' else 'scheduled' end,
                            'updated', v_cur.id is not null);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_post_on_a_working_day()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.status in ('draft', 'scheduled') and new.scheduled_at is not null then
    new.scheduled_at := public.fn_marketing_next_working_slot(new.scheduled_at);
    new.scheduled_local := new.scheduled_at at time zone 'Asia/Dubai';
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_post_publish_refusal(p marketing_post)
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
  if c.approved_hash is null then return 'not_approved: the founder has not approved campaign ' || c.campaign_key; end if;
  if c.approved_hash <> public.fn_marketing_campaign_hash(c.id) then
    return 'approval_void: campaign ' || c.campaign_key || ' was edited after the founder approved it';
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


CREATE OR REPLACE FUNCTION public.fn_marketing_post_refusal(p_post_id bigint)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(
    (select 'paused: ' || string_agg(regexp_replace(f.issue_key, '^duty:integration_social:postiz:', ''), ', ' order by f.issue_key)
            || ' is down in Postiz (it_engineer finding open); the post goes out on the first beat after it is reconnected'
       from public.it_engineer_finding f
      where f.closed_at is null
        and (f.issue_key = 'duty:integration_social:postiz:api'
             or f.issue_key = any (select 'duty:integration_social:postiz:' || c from unnest(p.channels) c))),
    public.fn_marketing_post_publish_refusal(p))
  from public.marketing_post p where p.id = p_post_id
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_prospect_upsert(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_urls text[] := coalesce((select array_agg(btrim(x)) from jsonb_array_elements_text(coalesce(p->'source_urls', '[]'::jsonb)) x), '{}');
  v_id bigint; v_status text;
begin
  if cardinality(v_urls) = 0 or exists (select 1 from unnest(v_urls) u where u !~ '^https?://[^\s/]+\.[^\s]+$') then
    return jsonb_build_object('ok', false, 'error', 'source_urls_required', 'message', 'Every person needs the public page(s) they were found on.');
  end if;
  if exists (select 1 from unnest(v_urls) u where u ~* '^https?://([a-z]{2,3}\.)?linkedin\.com/') and cardinality(v_urls) = 1 then
    return jsonb_build_object('ok', false, 'error', 'linkedin_is_not_a_source',
      'message', 'A person must be found on a public page other than LinkedIn (company site, directory, press); the profile URL goes in linkedin_url.');
  end if;
  select id, status into v_id, v_status from public.marketing_prospect
   where lower(full_name) = lower(btrim(p->>'full_name')) and lower(company) = lower(btrim(p->>'company')) for update;
  if v_id is not null and v_status <> 'new' then
    return jsonb_build_object('ok', true, 'id', v_id, 'unchanged', true, 'status', v_status);
  end if;
  if v_id is null then
    insert into public.marketing_prospect (full_name, role_title, company, segment, emirate, language, linkedin_url,
        opening_line, opening_line_url, source_urls, researched_by, is_demo)
    values (btrim(p->>'full_name'), btrim(p->>'role_title'), btrim(p->>'company'), p->>'segment', nullif(p->>'emirate', ''),
            coalesce(nullif(p->>'language', ''), 'en'), nullif(btrim(p->>'linkedin_url'), ''), nullif(btrim(p->>'opening_line'), ''),
            nullif(btrim(p->>'opening_line_url'), ''), v_urls, coalesce(p->>'researched_by', 'claude'), coalesce((p->>'is_demo')::boolean, false))
    returning id into v_id;
  else
    update public.marketing_prospect
       set role_title = btrim(p->>'role_title'), segment = p->>'segment', emirate = nullif(p->>'emirate', ''),
           language = coalesce(nullif(p->>'language', ''), 'en'), linkedin_url = nullif(btrim(p->>'linkedin_url'), ''),
           opening_line = nullif(btrim(p->>'opening_line'), ''), opening_line_url = nullif(btrim(p->>'opening_line_url'), ''),
           source_urls = v_urls, updated_at = now()
     where id = v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_publishing_live()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'marketing_golive'), false)
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_publishing_on()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce((select lower(btrim(value)) from public.app_secrets where key = 'marketing_publishing_enabled'), 'true') <> 'false'
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_records_ad_spend(p_platform text, p_spend_date date, p_currency text, p_amount numeric, p_source_ref text, p_campaign_ref text DEFAULT NULL::text, p_test boolean DEFAULT false)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_test boolean;
begin
  if coalesce(p_platform, '') !~ '^[a-z][a-z0-9_]*$' then raise exception 'platform must be a lowercase key such as meta or linkedin, got %', p_platform; end if;
  if p_spend_date is null then raise exception 'spend_date is required'; end if;
  if coalesce(upper(p_currency), '') !~ '^[A-Z]{3}$' then raise exception 'currency must be an ISO code, got %', p_currency; end if;
  if p_amount is null or p_amount < 0 then raise exception 'amount must be >= 0, got %', p_amount; end if;
  if coalesce(btrim(p_source_ref), '') = '' then raise exception 'source_ref (the platform''s own reference for this spend) is required'; end if;
  v_test := coalesce(p_test, false) or p_source_ref ~* 'zz[ _-]?demo' or coalesce(p_campaign_ref, '') ~* 'zz[ _-]?demo';
  return public.fn_seat_handoff('marketing', 'accountant', 'adspend.recorded', 'ad_spend_reported',
    p_source_ref || '@' || round(p_amount, 2)::text,
    jsonb_build_object('platform', p_platform, 'spend_date', p_spend_date, 'currency', upper(p_currency),
                       'amount', round(p_amount, 2), 'source_ref', p_source_ref, 'campaign_ref', p_campaign_ref,
                       'test', v_test, 'demo', v_test));
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_recruitment_funnel()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_day date := (now() at time zone 'Asia/Dubai')::date; v_rows int; gp record; v_empty int := 0; v_keys text[] := '{}';
begin
  insert into public.supplier_recruitment_funnel as f (trade, emirate, day, pool, invited, clicked, registered, approved, quoting)
  select g.trade, g.emirate, v_day,
         -- l.id is not null: a gap with NO matching lead is a null-extended row whose invite_status is
         -- null, which counted as a pool of 1 and so never fired pool_empty (found by this PR's probe).
         count(*) filter (where l.id is not null and l.invite_status is null and not coalesce(l.banned, false) and not coalesce(l.permanently_closed, false)),
         count(*) filter (where l.invited_at is not null),
         count(*) filter (where l.invite_clicked_at is not null),
         count(*) filter (where l.registration_submitted_at is not null or coalesce(l.claimed, false)),
         count(*) filter (where l.approval_status = 'approved'),
         count(*) filter (where exists (select 1 from public.quotes q where q.supplier_id = l.id))
    from public.supply_gap g
    left join public.leads l on g.trade = any(coalesce(l.invite_trades, '{}'::text[]))
                            and (g.emirate = 'UAE' or l.emirate = g.emirate) and coalesce(l.is_demo, false) = false
   where g.status = 'recruit'
   group by g.trade, g.emirate
  on conflict (trade, emirate, day) do update set pool = excluded.pool, invited = excluded.invited, clicked = excluded.clicked,
    registered = excluded.registered, approved = excluded.approved, quoting = excluded.quoting;
  get diagnostics v_rows = row_count;

  -- An empty pool is the lead source, not the invitation: marketing's finding, one per trade group.
  for gp in select coalesce(tt.group_code, 'ungrouped') as grp, count(*)::int as n,
                   jsonb_agg(jsonb_build_object('trade', f.trade, 'emirate', f.emirate) order by f.trade, f.emirate) as gaps
              from public.supplier_recruitment_funnel f
              join public.supply_gap s on s.trade = f.trade and s.emirate = f.emirate and s.status = 'recruit'
              left join public.taxonomy_trade tt on tt.code = f.trade
             where f.day = v_day and f.pool = 0
             group by 1 loop
    v_empty := v_empty + gp.n;
    v_keys := v_keys || ('recruitment:pool_empty:' || gp.grp);
    perform public.fn_it_engineer_finding_upsert('recruitment:pool_empty:' || gp.grp,
      'No uninvited lead is left for ' || gp.n || ' recruiting gap(s) in trade group ' || gp.grp,
      'public.supplier_recruitment_funnel', 'agent_facing', gp.n,
      jsonb_build_object('trade_group', gp.grp, 'gap_count', gp.n, 'gaps', gp.gaps, 'owner_seat', 'marketing'), '{}'::text[],
      array['which source can supply leads for these trades while lead scraping is paused'], 'marketing');
  end loop;
  update public.it_engineer_finding fi
     set closed_at = now(),
         close_note = case when fi.issue_key ~ '^recruitment:pool_empty:[^:]+:'
                           then 'superseded: empty pools are now one finding per trade group'
                           else 'no recruiting gap in this trade group has an empty pool' end
   where fi.issue_key like 'recruitment:pool_empty:%' and fi.closed_at is null and not (fi.issue_key = any(v_keys));

  return jsonb_build_object('gaps_recruiting', v_rows, 'empty_pools', v_empty, 'empty_pool_findings', cardinality(v_keys),
    'totals', (select jsonb_build_object('pool', sum(pool), 'invited', sum(invited), 'registered', sum(registered), 'approved', sum(approved), 'quoting', sum(quoting))
                 from public.supplier_recruitment_funnel where day = v_day),
    -- which stage lost them, filed to the CEO when a channel has N invited and 0 registered (#1012)
    'diagnosis', public.fn_marketing_funnel_diagnosis(false, true));
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_report_figures(p_from timestamp with time zone, p_to timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_report_tick(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_local timestamp := p_at at time zone 'Asia/Dubai'; f jsonb; v_none boolean; v_hid bigint;
begin
  if exists (select 1 from public.marketing_report where report_date = v_local::date) then
    return jsonb_build_object('ok', true, 'reported', false, 'reason', 'today''s report exists');
  end if;
  if v_local::time < time '07:00' then
    return jsonb_build_object('ok', true, 'reported', false, 'reason', 'before 07:00 Dubai');
  end if;
  f := public.fn_marketing_report_figures(p_at - interval '1 day', p_at);
  v_none := coalesce((f->'measured'->>'posts_published')::numeric, 0) = 0
        and coalesce((f->'measured'->>'ad_spend_reported_aed')::numeric, 0) = 0
        and coalesce((f->'measured'->>'conversations_handed_to_founder')::numeric, 0) = 0
        and coalesce((f->'measured'->>'customer_requests_posted')::numeric, 0) = 0;
  if v_none then
    f := f || jsonb_build_object('headline', 'No data yet: nothing was published, spent or handed over in the last 24 hours, and no customer request was posted. ' || (f->>'headline'));
  end if;
  insert into public.marketing_report (report_date, window_from, window_to, figures, no_data_yet)
  values (v_local::date, p_at - interval '1 day', p_at, f, v_none);
  v_hid := public.fn_seat_handoff('marketing', 'ceo', 'marketing.report', 'marketing_report', v_local::date::text,
                                  jsonb_build_object('report_date', v_local::date, 'headline', f->>'headline', 'no_data_yet', v_none));
  update public.marketing_report set handoff_id = v_hid where report_date = v_local::date;
  return jsonb_build_object('ok', true, 'reported', true, 'report_date', v_local::date, 'handoff_id', v_hid, 'no_data_yet', v_none);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_reputation()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_link text := nullif(btrim((select value from public.app_secrets where key = 'public_review_url')), '');
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';   -- fixture run: ONLY demo rows
  r record; v_asked int := 0; v_waiting int := 0; v_ar boolean;
begin
  insert into public.company_review_ask (customer_id, transaction_id, status)
  select k.customer_id, k.transaction_id, 'waiting_link' from public.fn_marketing_review_ask_candidates() k
  on conflict (transaction_id) do nothing;

  if v_link is null then
    select count(*) into v_waiting from public.company_review_ask where status = 'waiting_link';
    if v_waiting > 0 then
      perform public.fn_it_engineer_finding_upsert('reputation:no_public_review_link',
        v_waiting || ' customer job(s) are waiting to be asked for a public review, and no review link is configured',
        'app_secrets public_review_url', 'monitor', v_waiting, jsonb_build_object('owner_seat', 'marketing'),
        '{}'::text[], array['the Google Business Profile or directory review link to use'], 'marketing');
    end if;
  else
    update public.it_engineer_finding set closed_at = now(), close_note = 'a public review link is configured'
     where issue_key = 'reputation:no_public_review_link' and closed_at is null;
    for r in select a.id, a.customer_id, coalesce(a.transaction_id::text, a.customer_id::text) as job,
                    c.full_name, lower(btrim(c.email)) as email, c.locale
               from public.company_review_ask a join public.customers c on c.id = a.customer_id and c.is_demo = v_fx
              where a.status = 'waiting_link' and a.created_at > now() - interval '60 days'
                and not exists (select 1 from public.email_suppressions s where lower(btrim(s.email)) = lower(btrim(c.email)))
              order by a.id limit 50 loop
      v_ar := r.locale = 'ar';
      -- customer_support is the only seat that addresses a customer; the ask is marketing's, the send is support's.
      perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
        'type', 'public_review_ask', 'requested_by', 'customer_support', 'channel', 'email', 'to_email', r.email,
        'to_role', 'customer', 'lang', case when v_ar then 'ar' else 'en' end, 'dedupe_key', 'public_review_ask:' || r.job,
        'subject', case when v_ar then 'هل تشاركون تجربتكم مع QuotesDone؟' else 'Would you share your experience of QuotesDone?' end,
        'body', case when v_ar then
            'عزيزنا ' || coalesce(nullif(btrim(r.full_name), ''), 'العميل') || '،' || chr(10) || chr(10)
            || 'شكرًا لاستخدامكم QuotesDone. نرحب برأيكم الصريح علنًا، أيًّا كان، فذلك يساعد غيركم على اختيار موردين موثوقين: '
            || v_link || chr(10) || chr(10) || 'مع خالص الشكر والتقدير،'
          else
            'Dear ' || coalesce(nullif(btrim(r.full_name), ''), 'customer') || ',' || chr(10) || chr(10)
            || 'Thank you for using QuotesDone. If you have a minute, we would welcome your honest public review, '
            || 'whatever your experience; it helps other companies find reliable suppliers: ' || v_link
            || chr(10) || chr(10) || 'QuotesDone' end)));
      update public.company_review_ask set status = 'asked', asked_at = now() where id = r.id;
      v_asked := v_asked + 1;
    end loop;
  end if;

  -- The snapshot measures reputation; it is written after the asks and decides none of them.
  insert into public.company_reputation_snapshot as s (day, reviews, avg_rating, low_ratings_30d, asks_sent, asks_waiting)
  select (now() at time zone 'Asia/Dubai')::date, count(*), round(avg(rating)::numeric, 2),
         count(*) filter (where rating <= 2 and created_at > now() - interval '30 days'),
         (select count(*) from public.company_review_ask where status = 'asked'),
         (select count(*) from public.company_review_ask where status = 'waiting_link')
    from public.reviews
  on conflict (day) do update set reviews = excluded.reviews, avg_rating = excluded.avg_rating, low_ratings_30d = excluded.low_ratings_30d,
    asks_sent = excluded.asks_sent, asks_waiting = excluded.asks_waiting;
  return jsonb_build_object('asked', v_asked, 'waiting_for_link', v_link is null,
    'snapshot', (select to_jsonb(s) from public.company_reputation_snapshot s where day = (now() at time zone 'Asia/Dubai')::date));
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_review_ask_candidates(p_include_fixtures boolean DEFAULT false)
 RETURNS TABLE(transaction_id uuid, customer_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select t.id, t.customer_id
    from public.transactions t
    join public.customers c on c.id = t.customer_id
   where t.revealed_at is not null
     and t.revealed_at <= now() - make_interval(days => coalesce((select nullif(regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g'), '')::int
                                                                   from public.app_secrets where key = 'rating_request_days_after_reveal'), 21))
     and coalesce(t.refund_status, 'none') in ('none', 'window_open', 'declined')
     and coalesce(c.banned, false) = false
     and (p_include_fixtures or coalesce(c.is_demo, false) = false)
     and coalesce(btrim(c.email), '') like '%@%'
     and not exists (select 1 from public.email_suppressions s where lower(btrim(s.email)) = lower(btrim(c.email)))
     and not exists (select 1 from public.company_review_ask a where a.transaction_id = t.id)
   order by t.revealed_at, t.id
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_review_reasons_ok(p_decision text, p_reasons jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_typeof(p_reasons) = 'object'
     and (select count(*) from jsonb_object_keys(p_reasons)) = 6
     and coalesce((select bool_and(coalesce(r.value->>'verdict', '') in ('pass', 'fail')
                                   and length(btrim(coalesce(r.value->>'reason', ''))) >= 15)
                     from jsonb_each(p_reasons) r
                    where r.key in ('useful', 'market_topic_not_quotesdone', 'accurate_grounded', 'no_supplier_named',
                                    'language_quality', 'seo_geo')
                   having count(*) = 6), false)
     and case p_decision
           when 'approve' then not exists (select 1 from jsonb_each(p_reasons) r where r.value->>'verdict' <> 'pass')
           when 'revise' then exists (select 1 from jsonb_each(p_reasons) r where r.value->>'verdict' = 'fail')
           when 'replace_topic' then exists (select 1 from jsonb_each(p_reasons) r where r.value->>'verdict' = 'fail')
           else false end
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_reviews_tick(p_at timestamp with time zone DEFAULT now())
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
          'January 2027: the first customer calendar (organic only) goes to the founder for one-shot approval',
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


CREATE OR REPLACE FUNCTION public.fn_marketing_scorecard(p_month text, p_include_demo boolean DEFAULT false)
 RETURNS TABLE(platform text, rank integer, post_id bigint, ingest_key text, title text, checkpoint text, metric text, value numeric, target numeric, account_median numeric, verdict text, benchmark_source text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with posts as (
    select p.id, p.ingest_key, p.title
      from public.marketing_post p
     where to_char(coalesce(p.published_at, p.scheduled_at) at time zone 'Asia/Dubai', 'YYYY-MM') = p_month
       and (p_include_demo or not p.is_demo)
  ), latest as (
    select distinct on (m.post_id, m.platform, m.metric) m.post_id, m.platform, m.checkpoint, m.metric, m.value, m.captured_at
      from public.marketing_post_metric m join posts on posts.id = m.post_id
     where m.value is not null
     order by m.post_id, m.platform, m.metric,
              case m.checkpoint when '28d' then 4 when '7d' then 3 when '3d' then 2 else 1 end desc
  ), derived as (
    select l.post_id, l.platform, l.checkpoint, l.metric, l.value from latest l
    union all
    select l.post_id, l.platform, l.checkpoint, 'engagement_rate_by_followers', round(l.value / f.value, 6)
      from latest l
      cross join lateral (select d.value from public.marketing_insight_day d
                           where d.platform = 'instagram' and d.metric = 'followers'
                             and d.day <= (l.captured_at at time zone 'Asia/Dubai')::date
                           order by d.day desc limit 1) f
     where l.platform = 'instagram' and l.metric = 'total_interactions' and f.value > 0
    union all
    select pp.post_id, pp.platform, null, 'registrations', count(t.id)::numeric
      from public.marketing_post_platform pp join posts on posts.id = pp.post_id
      left join public.marketing_first_touch t on t.post_id = pp.post_id and t.utm_source = pp.platform
     group by pp.post_id, pp.platform
  ), med as (
    select d.platform, d.metric, percentile_cont(0.5) within group (order by d.value)::numeric as median
      from derived d group by d.platform, d.metric
  ), scored as (
    select d.*, round(md.median, 6) as median, g.target, g.benchmark_source,
           case when g.target is not null then (d.value >= g.target) else (d.value >= md.median) end as good
      from derived d
      join med md on md.platform = d.platform and md.metric = d.metric
      left join public.marketing_goal g on g.month = p_month and g.platform = d.platform and g.metric = d.metric
  ), post_score as (
    select s.post_id, s.platform,
           max(s.value) filter (where s.metric = 'registrations') as regs,
           count(*) filter (where s.metric <> 'registrations' and s.value >= s.median) as at_or_above
      from scored s group by s.post_id, s.platform
  )
  select s.platform,
         (dense_rank() over (partition by s.platform order by coalesce(ps.regs, 0) desc, ps.at_or_above desc, s.post_id))::int,
         s.post_id, p.ingest_key, p.title, s.checkpoint, s.metric, s.value, s.target, s.median,
         case when s.target is not null then case when s.good then 'met target' else 'below target' end
              else case when s.good then 'at or above own median' else 'below own median' end || ' (no sourced target)' end,
         s.benchmark_source
    from scored s join posts p on p.id = s.post_id join post_score ps on ps.post_id = s.post_id and ps.platform = s.platform
   order by s.platform, 2, s.metric
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_scorecard_publish(p_kind text, p_period_key text, p_month text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_rows int; v_new boolean;
begin
  if p_kind not in ('weekly', 'month_end') then raise exception 'kind must be weekly or month_end'; end if;
  insert into public.marketing_scorecard_report (period_key, month, kind, rows, result)
  select p_period_key, p_month, p_kind, count(*), coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb)
    from public.fn_marketing_scorecard(p_month) s
  on conflict (period_key) do nothing
  returning rows into v_rows;
  v_new := v_rows is not null;
  return jsonb_build_object('ok', true, 'stored', v_new, 'period_key', p_period_key, 'rows', v_rows);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_self_review()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_seat_self_review((now() at time zone 'Asia/Dubai')::date, 'marketing') $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_social_connect_link(p_platform text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_token text;
begin
  if p_platform not in ('youtube', 'linkedin') then
    raise exception 'fn_marketing_social_connect_link: platform must be youtube or linkedin, not %', p_platform;
  end if;
  -- 32 random bytes, base64url: the edge function accepts 40-64 characters of [A-Za-z0-9_-].
  v_token := rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
  insert into public.social_connect_link (platform, token_hash, expires_at)
  values (p_platform, encode(extensions.digest(v_token, 'sha256'), 'hex'), now() + interval '24 hours');
  return v_token;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_social_hand_to_human(p_conversation_id bigint, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c public.social_conversation%rowtype;
  v_last text;
  v_detail text;
begin
  select * into c from public.social_conversation where id = p_conversation_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no_such_conversation'); end if;
  -- Already with him: a second "agent" in the same conversation does not email him twice.
  if c.status = 'handed_to_human' then return jsonb_build_object('ok', true, 'notified', false, 'reason', 'already_handed'); end if;

  update public.social_conversation
     set status = 'handed_to_human', handed_at = now(), handed_reason = left(coalesce(p_reason, ''), 500),
         handoff_count = handoff_count + 1
   where id = c.id;

  select string_agg(to_char(m.occurred_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || '  '
                    || case m.author when 'person' then coalesce(c.handle, 'them') when 'seat' then 'QuotesDone (auto)' else 'QuotesDone (team)' end
                    || ': ' || left(m.body, 400), E'\n' order by m.occurred_at)
    into v_last
    from (select * from public.social_message where conversation_id = c.id order by occurred_at desc limit 8) m;

  v_detail := 'Someone on ' || initcap(c.platform) || ' asked to speak with a person. The marketing seat has stopped '
    || 'auto-replying in this conversation and it is waiting for you.' || E'\n\n'
    || 'Platform: ' || initcap(c.platform) || E'\n'
    || 'Handle: ' || coalesce(nullif(c.handle, ''), '(not shared by Meta)') || '  (id ' || c.user_id || ')' || E'\n'
    || 'Conversation: #' || c.id || E'\n\n'
    || 'Last messages (Dubai time):' || E'\n' || coalesce(v_last, '(none)') || E'\n\n'
    || 'Continue in the Meta inbox: https://business.facebook.com/latest/inbox/all' || E'\n'
    || 'When you are done, hand it back to the seat: select public.fn_marketing_social_set_status('
    || c.id || ', ''auto'', ''founder'');';

  return jsonb_build_object('ok', true, 'notified', true, 'notify',
    public.fn_notify_founder(
      p_event       => 'Someone on ' || initcap(c.platform) || ' asked to speak with you' || coalesce(' (' || nullif(c.handle, '') || ')', ''),
      p_detail      => v_detail,
      p_level       => 'high',
      p_kind        => 'social_human_request',
      p_dedupe_key  => 'social_human:' || c.id || ':' || (c.handoff_count + 1),
      p_owner_agent => 'marketing'));
end
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_social_handoff_answered(p_id bigint, p_seat text, p_note text, p_unhide boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions
   where id = p_id and kind = 'handoff' and status = 'pending' and detail->>'type' in ('social.escalation', 'social.lead') for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no pending social handoff ' || p_id); end if;
  if a.agent is distinct from p_seat then
    return jsonb_build_object('ok', false, 'reason', 'handoff ' || p_id || ' is addressed to ' || a.agent || ', not ' || coalesce(p_seat, 'nobody'));
  end if;
  if coalesce(btrim(p_note), '') = '' then return jsonb_build_object('ok', false, 'reason', 'an answer needs a note of what was done'); end if;
  update public.agent_actions
     set detail = detail || jsonb_build_object('answered_at', now(), 'answered_by', p_seat, 'answer', left(p_note, 1000))
                         || case when p_unhide then jsonb_build_object('unhide', true) else '{}'::jsonb end
   where id = p_id;
  return jsonb_build_object('ok', true, 'handoff_id', p_id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_social_handoff_waits(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object('waiting', coalesce(a.detail ->> 'waiting_for', a.agent || ' to answer the commenter privately'))
    from public.agent_actions a where a.id = p_id
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_social_handoffs_close()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare h record; n_closed int := 0; n_waiting int := 0;
begin
  for h in select a.id, a.detail from public.agent_actions a
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'from' = 'marketing'
              and a.detail->>'type' in ('social.escalation', 'social.lead')
  loop
    if h.detail ? 'answered_at' and (coalesce((h.detail->>'unhide')::boolean, false) = false or h.detail ? 'unhidden_at') then
      perform set_config('qd.handoff_closer', 'marketing', true);
      perform public.fn_seat_handoff_complete(h.id, jsonb_build_object('verified_by', 'marketing', 'verified_at', now(),
        'answer', h.detail->>'answer', 'answered_by', h.detail->>'answered_by', 'unhidden_at', h.detail->>'unhidden_at'));
      perform set_config('qd.handoff_closer', '', true);
      n_closed := n_closed + 1;
    else
      n_waiting := n_waiting + 1;
    end if;
  end loop;
  return jsonb_build_object('closed', n_closed, 'waiting', n_waiting);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_social_set_status(p_conversation_id bigint, p_status text, p_by text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_status not in ('auto', 'handed_to_human') then
    return jsonb_build_object('ok', false, 'reason', 'status must be auto or handed_to_human');
  end if;
  update public.social_conversation
     set status = p_status,
         resumed_at = case when p_status = 'auto' then now() else resumed_at end,
         resumed_by = case when p_status = 'auto' then left(coalesce(p_by, ''), 120) else resumed_by end,
         handed_at = case when p_status = 'handed_to_human' and status = 'auto' then now() else handed_at end,
         handed_reason = case when p_status = 'handed_to_human' and status = 'auto' then left(coalesce(p_by, ''), 500) else handed_reason end
   where id = p_conversation_id;
  return jsonb_build_object('ok', found, 'status', p_status);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_step_accept(p_step text, p_subject text, p_seat text, p_output jsonb, p_outcome text DEFAULT 'answered'::text, p_reason text DEFAULT NULL::text, p_model text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_class text; v_table text; v_ref text; v_bad text[] := '{}'; f public.marketing_asset_feature;
        v_dis jsonb := '[]'::jsonb; v_month date; v_round int; v_move text; v_plan jsonb; v_turn bigint;
        p public.marketing_month_plan; v_last public.marketing_plan_review_turn; v_hid bigint; v_run bigint; v_perc bigint;
        v_crit text; v_cited int;
begin
  v_class := case p_step when 'watch' then 'marketing_watch' when 'quality_review' then 'marketing_quality_review'
               when 'research' then 'marketing_research' when 'evaluate' then 'marketing_evaluate' when 'plan' then 'marketing_plan'
               when 'plan_defend' then 'marketing_plan_defend' end;
  if v_class is null then raise exception 'unknown marketing step %', p_step; end if;
  -- THE CREDENTIAL DECIDES THE SEAT: every step here is marketing's. The CEO's review is seat_deliberation's (873).
  if p_seat is distinct from 'marketing' then
    raise exception 'step % belongs to marketing, not %', p_step, p_seat;
  end if;

  if p_outcome = 'held' then
    insert into public.marketing_model_run (step, subject, seat, task_class, outcome, reason, model)
    values (p_step, p_subject, p_seat, v_class, 'held_not_run', coalesce(p_reason, 'the founder''s model hold is on'), p_model)
    on conflict (step, subject, run_day) where outcome = 'held_not_run' do nothing;
    return jsonb_build_object('ok', true, 'outcome', 'held_not_run', 'written', false);
  end if;
  if p_outcome = 'failed' or p_output is null or jsonb_typeof(p_output) <> 'object' then
    insert into public.marketing_model_run (step, subject, seat, task_class, outcome, reason, model)
    values (p_step, p_subject, p_seat, v_class, case when p_outcome = 'failed' then 'failed' else 'rejected' end,
            coalesce(p_reason, 'the answer was not a JSON object'), p_model);
    return jsonb_build_object('ok', false, 'outcome', case when p_outcome = 'failed' then 'failed' else 'rejected' end, 'written', false, 'reason', coalesce(p_reason, 'not a JSON object'));
  end if;

  -- validate per step
  if p_step = 'watch' then
    select * into f from public.marketing_asset_feature where file_sha256 = p_subject order by measured_at desc limit 1;
    if f.file_sha256 is null then v_bad := v_bad || 'no measured features for this asset'::text; end if;
    if jsonb_typeof(p_output->'scenes') is distinct from 'array' or jsonb_array_length(coalesce(p_output->'scenes','[]')) = 0 then v_bad := v_bad || 'scenes missing'::text; end if;
    if jsonb_typeof(p_output->'on_screen_text') is distinct from 'array' then v_bad := v_bad || 'on_screen_text missing'::text; end if;
    if not (p_output ?& array['hook','pacing','legibility','music','voiceover','cta']) then v_bad := v_bad || 'hook/pacing/legibility/music/voiceover/cta required'::text; end if;
    if p_output ? 'duration_s_claimed' and public.fn_marketing_jnum(p_output->'duration_s_claimed') is null then v_bad := v_bad || 'duration_s_claimed must be a number'::text; end if;
    if p_output ? 'has_audio_claimed' and public.fn_marketing_jbool(p_output->'has_audio_claimed') is null then v_bad := v_bad || 'has_audio_claimed must be true or false'::text; end if;
    if p_output->'voiceover' ? 'present' and public.fn_marketing_jbool(p_output->'voiceover'->'present') is null then v_bad := v_bad || 'voiceover.present must be true or false'::text; end if;
  elsif p_step = 'quality_review' then
    if not (p_output ?& array['hook','pacing','legibility','music_fit','voiceover_recommendation','overall_recommendation']) then
      v_bad := v_bad || 'hook, pacing, legibility, music_fit, voiceover_recommendation and overall_recommendation are required'::text; end if;
    v_bad := v_bad || public.fn_marketing_evidence_problems(p_output->'evidence');
  elsif p_step = 'research' then
    if not (p_output ?& array['themes','what_to_borrow','what_to_avoid']) then v_bad := v_bad || 'themes, what_to_borrow, what_to_avoid required'::text; end if;
    v_bad := v_bad || public.fn_marketing_evidence_problems(p_output->'evidence');
    if exists (select 1 from jsonb_array_elements(coalesce(p_output->'evidence','[]')) e where e->>'kind' <> 'market_intel') then
      v_bad := v_bad || 'research cites market_intel posts only'::text; end if;
  elsif p_step = 'evaluate' then
    if coalesce(btrim(p_output->>'verdict'), '') = '' or not (p_output ? 'what_worked') then v_bad := v_bad || 'verdict and what_worked required'::text; end if;
    v_bad := v_bad || public.fn_marketing_evidence_problems(p_output->'evidence');
  else
    v_month := p_subject::date;
    select * into p from public.marketing_month_plan where month = v_month;
    select * into v_last from public.marketing_plan_review_turn where month = v_month order by round desc, (seat = 'ceo') desc limit 1;
    v_move := case p_step when 'plan' then 'propose' else p_output->>'move' end;
    v_round := coalesce(v_last.round, 0) + 1;
    v_plan := case when v_move = 'propose' then p_output->'plan' when v_move = 'adjust' then p_output->'plan' else null end;
    if p.month is null or p.verdict is null then v_bad := v_bad || 'the month has no verdict yet'::text; end if;
    if p_step = 'plan' and p.plan is not null then v_bad := v_bad || 'the plan was already proposed'::text; end if;
    if p_step = 'plan_defend' and not (v_last.seat = 'ceo' and v_last.move in ('request_changes','reject')) then v_bad := v_bad || 'no CEO request is waiting for an answer'::text; end if;
    if p_step = 'plan_defend' and v_move not in ('adjust','defend') then v_bad := v_bad || 'move must be adjust or defend'::text; end if;
    -- marketing answers EVERY ask: one answer per CEO change, concede or defend, each with evidence
    if p_step = 'plan_defend' and v_last.seat = 'ceo' then
      if jsonb_typeof(p_output->'answers') is distinct from 'array'
         or (select count(distinct (a->>'ask')) from jsonb_array_elements(coalesce(p_output->'answers','[]')) a
              where (case when jsonb_typeof(a->'ask') = 'number' and (a->>'ask') ~ '^\d{1,6}$' then (a->>'ask')::int end)
                    < jsonb_array_length(coalesce(v_last.changes,'[]'))
                and a->>'response' in ('concede','defend') and length(btrim(coalesce(a->>'reasoning',''))) >= 20
                and cardinality(public.fn_marketing_evidence_problems(a->'evidence')) = 0)
            <> jsonb_array_length(coalesce(v_last.changes,'[]')) then
        v_bad := v_bad || ('every one of the CEO''s ' || jsonb_array_length(coalesce(v_last.changes,'[]')) || ' ask(s) needs an answer (concede|defend) with reasoning and valid evidence');
      end if;
      if v_move = 'defend' and exists (select 1 from jsonb_array_elements(coalesce(p_output->'answers','[]')) a where a->>'response' = 'concede') then
        v_bad := v_bad || 'an ask was conceded, so the move is adjust and the revised plan must be returned'::text; end if;
      if v_move = 'adjust' and not (p_output ? 'plan') then v_bad := v_bad || 'adjust must return the revised plan'::text; end if;
    end if;
    if length(btrim(coalesce(p_output->>'reasoning', ''))) < 40 then v_bad := v_bad || 'reasoning is missing or too thin to inspect'::text; end if;
    if v_plan is not null then v_bad := v_bad || public.fn_marketing_plan_problems(v_plan); end if;
    if v_round > 3 then v_bad := v_bad || 'the debate is capped at 3 rounds'::text; end if;
    v_bad := v_bad || public.fn_marketing_evidence_problems(p_output->'evidence');
  end if;

  if cardinality(v_bad) > 0 then
    insert into public.marketing_model_run (step, subject, seat, task_class, outcome, reason, model)
    values (p_step, p_subject, p_seat, v_class, 'rejected', array_to_string(v_bad, '; '), p_model);
    return jsonb_build_object('ok', false, 'outcome', 'rejected', 'written', false, 'problems', to_jsonb(v_bad));
  end if;

  -- write
  if p_step = 'watch' then
    if abs(coalesce(public.fn_marketing_jnum(p_output->'duration_s_claimed'), f.duration_s) - f.duration_s) > 1.5 then
      v_dis := v_dis || jsonb_build_object('field', 'duration_s', 'model', p_output->'duration_s_claimed', 'measured', f.duration_s); end if;
    if p_output ? 'has_audio_claimed' and public.fn_marketing_jbool(p_output->'has_audio_claimed') is distinct from f.audio_present then
      v_dis := v_dis || jsonb_build_object('field', 'audio_present', 'model', p_output->'has_audio_claimed', 'measured', f.audio_present); end if;
    if f.voiceover_suspected is not null and p_output->'voiceover' ? 'present' and public.fn_marketing_jbool(p_output->'voiceover'->'present') is distinct from f.voiceover_suspected then
      v_dis := v_dis || jsonb_build_object('field', 'voiceover', 'model', p_output->'voiceover'->'present', 'measured_proxy', f.voiceover_suspected,
                                           'note', 'the measured side is a speech-band proxy; a disagreement is a flag for review, not a verdict'); end if;
    insert into public.marketing_asset_perception (file_sha256, model, prompt_version, perception, disagreements)
    values (p_subject, coalesce(p_model, 'unknown'), 'watch-v1', p_output, v_dis)
    on conflict (file_sha256, model, prompt_version) do update set perception = excluded.perception, disagreements = excluded.disagreements, created_at = now()
    returning id into v_perc;
    v_table := 'marketing_asset_perception'; v_ref := v_perc::text;
  elsif p_step = 'quality_review' then
    insert into public.marketing_asset_review (file_sha256, review, evidence, inputs, model)
    values (p_subject, p_output - 'evidence', p_output->'evidence',
            jsonb_build_object('perception_id', (select max(id) from public.marketing_asset_perception where file_sha256 = p_subject)), p_model)
    returning id::text into v_ref;
    v_table := 'marketing_asset_review';
  elsif p_step = 'research' then
    insert into public.marketing_insight_note (week_start, synthesis, intel_ids, model)
    values (p_subject::date, p_output, array(select (e->>'ref')::bigint from jsonb_array_elements(p_output->'evidence') e), p_model)
    on conflict (week_start) do update set synthesis = excluded.synthesis, intel_ids = excluded.intel_ids, model = excluded.model, created_at = now();
    v_table := 'marketing_insight_note'; v_ref := p_subject;
  elsif p_step = 'evaluate' then
    insert into public.marketing_month_plan (month, status, verdict) values (p_subject::date, 'draft', p_output)
    on conflict (month) do update set verdict = excluded.verdict, updated_at = now();
    v_table := 'marketing_month_plan'; v_ref := p_subject;
  else
    insert into public.marketing_plan_review_turn (month, round, seat, move, reasoning, evidence, changes, answers, criteria, plan, model)
    values (v_month, v_round, p_seat, v_move, p_output->>'reasoning', p_output->'evidence', p_output->'changes',
            p_output->'answers', case when p_seat = 'ceo' then p_output->'criteria' end, v_plan, p_model)
    returning id into v_turn;
    v_table := 'marketing_plan_review_turn'; v_ref := v_turn::text;
    update public.marketing_month_plan
       set plan = coalesce(v_plan, plan), rounds = greatest(rounds, v_round), updated_at = now(),
           status = 'with_ceo'
     where month = v_month;
    -- the CEO reviews it on seat_deliberation (873): opened on the proposal, revised on each answer. A refusal
    -- by the review machine (an unproven author model, a leak) must not undo marketing's own turn: it is kept,
    -- the refusal is logged, and fn_marketing_plan_loop_tick sends it again on the next beat.
    begin
      perform public.fn_marketing_plan_to_ceo(v_month);
    exception when others then
      insert into public.marketing_model_run (step, subject, seat, task_class, outcome, reason, model)
      values ('ceo_review', p_subject, 'marketing', 'seat_deliberation_blind', 'failed',
              'not yet before the CEO: ' || left(sqlerrm, 400), p_model);
    end;
  end if;

  insert into public.marketing_model_run (step, subject, seat, task_class, outcome, model, output_table, output_ref)
  values (p_step, p_subject, p_seat, v_class, 'written', p_model, v_table, v_ref) returning id into v_run;
  return jsonb_build_object('ok', true, 'outcome', 'written', 'written', true, 'table', v_table, 'ref', v_ref, 'run_id', v_run);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_step_request(p_step text, p_subject text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare f public.marketing_asset_feature; q public.marketing_asset_perception; p public.marketing_month_plan;
        v_metrics jsonb := '[]'::jsonb; v_score jsonb; v_month date; v_round int; v_last public.marketing_plan_review_turn;
        v_assets text[]; v_cited int; v_dossiers jsonb; v_images jsonb := '[]'::jsonb; v_flags jsonb := '[]'::jsonb;
        v_org text := 'You work for QuotesDone, a UAE procurement marketplace. Organic content only: never propose ads, boosting or paid promotion. '
                   || 'Answer with ONE JSON object matching output_schema, nothing else. Every claim you rely on cites evidence '
                   || '{kind, ref, point} using only the ids present in input; a citation to anything not in input is rejected.';
begin
  if p_step in ('watch','quality_review') then
    select * into f from public.marketing_asset_feature where file_sha256 = p_subject order by measured_at desc limit 1;
    if f.file_sha256 is null then raise exception 'no measured features for asset %', p_subject; end if;
  end if;

  if p_step = 'watch' then
    return jsonb_build_object('step', 'watch', 'seat', 'marketing', 'task_class', 'marketing_watch', 'max_tokens', 2500,
      'prompt_version', 'watch-v1', 'video', jsonb_build_object('bucket', f.asset_bucket, 'path', f.asset_path, 'bytes', f.bytes),
      'require_caps', jsonb_build_array('vision', 'audio'),
      'system', 'You watch and listen to one short vertical social video the way an experienced social media creative would. '
             || 'Describe only what is in the video; do not guess. Answer with ONE JSON object matching output_schema.',
      'input', jsonb_build_object('asset', f.asset_path, 'music_on_file', f.music,
                                  'measured', jsonb_build_object('duration_s', f.duration_s, 'fps', f.fps, 'aspect', f.aspect)),
      'output_schema', jsonb_build_object(
        'scenes', '[{start_s, end_s, what_is_shown}]', 'on_screen_text', '[{start_s, end_s, text, legible_on_phone: boolean}]',
        'hook', '{first_3s_description, strength: weak|ok|strong, why}', 'pacing', '{cut_rhythm, feels: slow|even|fast, why}',
        'legibility', '{overall: poor|ok|good, issues: []}', 'music', '{mood, tempo, energy, suits_message: boolean, fights_voice: boolean, why}',
        'voiceover', '{present: boolean, transcript, tone}', 'cta', '{text, clear: boolean, why}',
        'off_brand_or_false', '[string]', 'duration_s_claimed', 'number', 'has_audio_claimed', 'boolean'));
  end if;

  if p_step = 'quality_review' then
    select * into q from public.marketing_asset_perception where file_sha256 = p_subject order by id desc limit 1;
    if q.id is null then raise exception 'no perception for asset %', p_subject; end if;
    if to_regclass('public.marketing_post_metric') is not null then
      execute 'select coalesce(jsonb_agg(to_jsonb(m)), ''[]''::jsonb) from (select m.* from public.marketing_post_metric m '
           || 'join public.marketing_post mp on mp.id = m.post_id where $1 = any(mp.media_paths) or $2 = any(mp.media_paths) '
           || 'order by m.id limit 50) m'
        into v_metrics using f.asset_path, f.asset_bucket || '/' || f.asset_path;
    end if;
    return jsonb_build_object('step', 'quality_review', 'seat', 'marketing', 'task_class', 'marketing_quality_review', 'max_tokens', 2000,
      'images', (select coalesce(jsonb_agg(k), '[]'::jsonb) from (select k from jsonb_array_elements(f.keyframes) k limit 4) s),
      'system', v_org || ' You are a senior creative director reviewing one published video.',
      'input', jsonb_build_object('asset_feature', to_jsonb(f), 'asset_perception', jsonb_build_object('id', q.id, 'perception', q.perception, 'disagreements', q.disagreements),
                                  'post_metrics', v_metrics,
                                  'note', case when jsonb_array_length(v_metrics) = 0 then 'No per-post results exist for this asset yet; say so rather than infer performance.' end),
      'output_schema', jsonb_build_object('hook', '{verdict, why}', 'pacing', '{verdict, why}', 'legibility', '{verdict, why}',
        'music_fit', '{verdict, why, change_next_month: boolean}', 'voiceover_recommendation', '{add: boolean, why}',
        'overall_recommendation', '{keep|change|drop, what_to_change: []}',
        'evidence', '[{kind: asset_feature|asset_perception|post_metric, ref, point}]'));
  end if;

  if p_step = 'research' then
    return jsonb_build_object('step', 'research', 'seat', 'marketing', 'task_class', 'marketing_research', 'max_tokens', 2500,
      'system', v_org || ' You study competitor posts to decide what our next month should borrow or avoid.',
      'input', jsonb_build_object('week_start', p_subject, 'posts', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'platform', platform,
                 'url', source_url, 'posted_at', posted_at, 'caption', left(detail, 600), 'metrics', metrics)), '[]'::jsonb)
                 from (select * from public.market_intel where platform is not null and coalesce(posted_at, created_at) >= p_subject::date
                        and coalesce(posted_at, created_at) < p_subject::date + 7 order by id limit 200) m)),
      'output_schema', jsonb_build_object('themes', '[string]', 'formats_seen', '[string]', 'what_to_borrow', '[string]',
        'what_to_avoid', '[string]', 'evidence', '[{kind: market_intel, ref: id, point}]'));
  end if;

  v_month := p_subject::date;   -- the month being planned
  if p_step = 'evaluate' then
    -- #875's signature: fn_marketing_scorecard(p_month text 'YYYY-MM', p_include_demo boolean) returns a table of rows
    if to_regprocedure('public.fn_marketing_scorecard(text,boolean)') is not null then
      begin execute 'select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from public.fn_marketing_scorecard($1, false) x'
              into v_score using to_char(v_month - interval '1 month', 'YYYY-MM');
      exception when others then v_score := jsonb_build_object('error', left(sqlerrm, 200)); end;
    end if;
    return jsonb_build_object('step', 'evaluate', 'seat', 'marketing', 'task_class', 'marketing_evaluate', 'max_tokens', 3000,
      'system', v_org || ' You judge the month that is ending: what worked, what did not, and why.',
      'input', jsonb_build_object('evaluated_month', (v_month - interval '1 month')::date,
        'scorecard', coalesce(v_score, jsonb_build_object('note', 'fn_marketing_scorecard is not built yet: no measured results; say so.')),
        'asset_reviews', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'asset', file_sha256, 'review', review)), '[]'::jsonb)
                            from public.marketing_asset_review where created_at >= v_month - interval '45 days'),
        'insight_notes', (select coalesce(jsonb_agg(jsonb_build_object('week_start', week_start, 'synthesis', synthesis)), '[]'::jsonb)
                            from public.marketing_insight_note where week_start >= v_month - interval '45 days'),
        'company_plan', (select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) from public.ceo_plan_month c where month in ((v_month - interval '1 month')::date, v_month)),
        'this_month_plan', (select plan from public.marketing_month_plan where month = (v_month - interval '1 month')::date)),
      'output_schema', jsonb_build_object('verdict', 'string', 'what_worked', '[{what, why, evidence_refs}]',
        'what_did_not', '[{what, why, evidence_refs}]', 'evidence', '[{kind, ref, point}]'));
  end if;

  select * into p from public.marketing_month_plan where month = v_month;
  select * into v_last from public.marketing_plan_review_turn where month = v_month order by round desc, (seat = 'ceo') desc limit 1;
  v_round := coalesce(v_last.round, 0);

  if p_step in ('plan','plan_defend') then
    -- Marketing's plan and defence see every perceived video's dossier (perception, features, results).
    select coalesce(jsonb_agg(public.fn_marketing_asset_dossier(a) order by a), '[]'::jsonb) into v_dossiers
      from (select distinct file_sha256 a from public.marketing_asset_perception order by 1 limit 12) x;
    return jsonb_build_object('step', p_step, 'seat', 'marketing',
      'task_class', case p_step when 'plan' then 'marketing_plan' else 'marketing_plan_defend' end,
      'max_tokens', case when p_step = 'plan' then 4000 else 3000 end, 'round', v_round + 1,
      'system', v_org || case p_step
        when 'plan' then ' You are the marketing seat. Propose next month''s organic content plan to the CEO. The founder and Claude produce the videos; YOU decide what is in them: topics, formats, music, voice-over, length, count and cadence. Give your reasoning and cite the videos and posts it rests on.'
        else ' You are the marketing seat. The CEO asked for specific changes. Answer EVERY ask, in order, in answers[]: concede (and change the plan) or defend (with evidence the CEO has not weighed). move = adjust when any ask is conceded (return the full revised plan), else defend.' end,
      'input', jsonb_build_object('month', v_month, 'verdict_on_last_month', p.verdict, 'current_plan', p.plan, 'videos', v_dossiers,
        'turns', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'round', round, 'seat', seat, 'move', move, 'reasoning', reasoning,
                   'changes', changes, 'answers', answers, 'criteria', criteria, 'evidence', evidence) order by id), '[]'::jsonb)
                   from public.marketing_plan_review_turn where month = v_month),
        'company_plan', (select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) from public.ceo_plan_month c where month = v_month),
        'company', public.fn_company_context(),
        'asset_reviews', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'asset', file_sha256, 'review', review)), '[]'::jsonb)
                            from (select * from public.marketing_asset_review order by id desc limit 24) r),
        'insight_notes', (select coalesce(jsonb_agg(jsonb_build_object('week_start', week_start, 'synthesis', synthesis)), '[]'::jsonb)
                            from (select * from public.marketing_insight_note order by week_start desc limit 5) n)),
      'output_schema', case p_step
        when 'plan_defend' then jsonb_build_object('move', 'adjust|defend', 'reasoning', 'string',
            'answers', '[{ask: <index into the CEO''s changes, from 0>, response: concede|defend, reasoning, evidence: [...]}] - one per ask',
            'plan', 'full plan when adjust', 'evidence', '[{kind, ref, point}]')
        else jsonb_build_object('plan', jsonb_build_object('topics', '[{title, angle, why}]', 'formats', '[string]',
               'music', '{direction, bpm_range, why}', 'voiceover', '{use: boolean, language, why}', 'video', '{count, length_s}',
               'cadence', '{posts_per_week, platforms: []}', 'budget', '{model_aed, ad_spend_aed: 0}'),
             'reasoning', 'string', 'evidence', '[{kind, ref, point}]') end);
  end if;
  raise exception 'unknown marketing step %', p_step;
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_steps_due(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare out jsonb := '[]'::jsonb; cal jsonb := public.fn_marketing_plan_calendar(p_at);
        v_day date := (p_at at time zone 'Asia/Dubai')::date; v_week date; p public.marketing_month_plan;
        t public.marketing_plan_review_turn; x record;
begin
  -- watch: every measured asset without a perception by the current prompt version
  if (select count(*) from public.marketing_model_run where step = 'watch' and outcome = 'written' and run_day = v_day) < 6 then
    for x in select distinct on (f.file_sha256) f.file_sha256 from public.marketing_asset_feature f
              where not exists (select 1 from public.marketing_asset_perception q
                                 where q.file_sha256 = f.file_sha256 and q.prompt_version = 'watch-v1')
                and public.fn_marketing_subject_blocked('watch', f.file_sha256, p_at) is null
              order by f.file_sha256 limit 3 loop
      out := out || jsonb_build_object('step', 'watch', 'subject', x.file_sha256, 'seat', 'marketing');
    end loop;
  end if;
  -- quality_review: a perception with no review, or a review older than 30 days when results exist
  if (select count(*) from public.marketing_model_run where step = 'quality_review' and outcome = 'written' and run_day = v_day) < 6 then
    for x in select q.file_sha256 from public.marketing_asset_perception q
              where q.prompt_version = 'watch-v1'
                and not exists (select 1 from public.marketing_asset_review r where r.file_sha256 = q.file_sha256
                                   and r.created_at > p_at - interval '30 days')
                and public.fn_marketing_subject_blocked('quality_review', q.file_sha256, p_at) is null
              order by q.id limit 3 loop
      out := out || jsonb_build_object('step', 'quality_review', 'subject', x.file_sha256, 'seat', 'marketing');
    end loop;
  end if;
  -- research: the last complete week, once, when there is anything to read
  v_week := (date_trunc('week', v_day) - interval '7 days')::date;
  if not exists (select 1 from public.marketing_insight_note where week_start = v_week)
     and public.fn_marketing_subject_blocked('research', v_week::text, p_at) is null
     and exists (select 1 from public.market_intel where platform is not null
                   and coalesce(posted_at, created_at) >= v_week and coalesce(posted_at, created_at) < v_week + 7) then
    out := out || jsonb_build_object('step', 'research', 'subject', v_week::text, 'seat', 'marketing');
  end if;
  -- the month: evaluate -> plan -> (the CEO's review on seat_deliberation <-> plan_defend).
  -- A month an approved calendar already covers is planned: no second plan is drafted for it.
  if (cal->>'in_window')::boolean
     and not public.fn_marketing_month_covered_by_approved_calendar((cal->>'plan_month')::date) then
    select * into p from public.marketing_month_plan where month = (cal->>'plan_month')::date;
    if public.fn_marketing_subject_blocked(case when p.month is null or p.verdict is null then 'evaluate'
                                              when p.plan is null then 'plan' else 'plan_defend' end,
                                         cal->>'plan_month', p_at) is not null then
      null;   -- capped or quarantined today: the other steps above still run
    elsif p.month is null or p.verdict is null then
      out := out || jsonb_build_object('step', 'evaluate', 'subject', cal->>'plan_month', 'seat', 'marketing');
    elsif p.plan is null then
      out := out || jsonb_build_object('step', 'plan', 'subject', cal->>'plan_month', 'seat', 'marketing');
    elsif p.status = 'with_ceo' then
      select * into t from public.marketing_plan_review_turn where month = p.month order by round desc, (seat = 'ceo') desc limit 1;
      if t.seat = 'ceo' and t.move in ('request_changes','reject') and t.round < 3 then
        out := out || jsonb_build_object('step', 'plan_defend', 'subject', p.month::text, 'seat', 'marketing');
      end if;
    end if;
  end if;
  return out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_studio()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', (select to_jsonb(k) from marketing_kpis k limit 1),
    'trend', coalesce((select jsonb_agg(jsonb_build_object(
        'd', to_char(s.snapshot_date,'Mon DD'),
        'leads', nullif(s.kpis->>'leads_total','')::numeric,
        'blog', nullif(s.kpis->>'blog_published','')::numeric,
        'social', nullif(s.kpis->>'social_published','')::numeric,
        'seo', nullif(s.kpis->>'seo_pages','')::numeric
      ) order by s.snapshot_date) from marketing_snapshots s),'[]'::jsonb),
    -- the pipeline's own smoke rows (source = 'selftest') are not posts anyone prepared or designed
    'social', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'image_url', p.image_url,
        'text', coalesce(p.content->>'all', p.content->>'text', left(p.content::text,400)),
        'channels', to_jsonb(p.channels), 'status', p.status, 'mode', p.mode, 'error', p.error, 'created_at', p.created_at,
        'live', (p.mode = 'now' and p.status in ('sent','published')),
        'permalinks', p.permalinks, 'permalink_missing', p.permalink_missing,
        'media_missing', p.media_missing, 'preview_url', p.preview_url
      ) order by p.created_at desc) from social_posts p where coalesce(p.source, '') <> 'selftest'),'[]'::jsonb),
    -- the blog is the seat's article table: the same rows the count above reads
    'blog', coalesce((select jsonb_agg(jsonb_build_object(
        'id', a.id, 'title', a.title_en, 'slug', a.slug, 'category', a.category_en, 'excerpt', a.excerpt_en,
        'status', a.status, 'published', a.status = 'live', 'published_at', a.live_at, 'body_html', left(a.body_html_en, 24000),
        'url', case when a.status = 'live' then 'https://quotesdone.ae/blog/' || a.slug end
      ) order by a.updated_at desc) from marketing_article a where not a.is_demo),'[]'::jsonb),
    'site_blog', coalesce((select jsonb_agg(jsonb_build_object(
        'id', b.id, 'title', b.title, 'slug', b.slug, 'published', b.published,
        'url', case when b.published and b.slug is not null then 'https://quotesdone.ae/blog/' || b.slug end
      ) order by b.updated_at desc) from blog_posts b),'[]'::jsonb),
    'review', (select coalesce(fn_review_pending(),'[]'::jsonb))
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_subject_blocked(p_step text, p_subject text, p_at timestamp with time zone DEFAULT now())
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with d as (select (p_at at time zone 'Asia/Dubai')::date today)
  select case
    -- counted SINCE the last written run, not in a window tied to today: a quarantine does not lapse at midnight
    when (select count(distinct r.run_day) from public.marketing_model_run r
           where r.step = p_step and r.subject = p_subject and r.outcome in ('rejected','failed')
             and r.id > coalesce((select max(w.id) from public.marketing_model_run w
                                   where w.step = p_step and w.subject = p_subject and w.outcome = 'written'), 0)) >= 3
      then 'quarantined: failed on 3 or more days since its last written run'
    when (select count(*) from public.marketing_model_run r, d where r.step = p_step and r.subject = p_subject
           and r.outcome in ('written','rejected','failed') and r.run_day = d.today) >= 2
      then 'attempt cap: 2 attempts today'
  end
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_supplier_outreach_targets(p_per_trade integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb;
begin
  with trades as (
    select g.trade, min(g.rank) rank from public.marketing_gap_recruitment_plan g group by g.trade order by 2 limit 15
  ), pool as (
    select t.trade, t.rank, l.id, l.company_name, l.emirate, l.website, l.linkedin, l.instagram, l.facebook,
           row_number() over (partition by t.trade order by (coalesce(l.linkedin, '') = ''), l.id) rn
      from trades t join public.leads l on coalesce(l.invite_trades[1], l.sector) = t.trade
     where not coalesce(l.is_demo, false) and not coalesce(l.banned, false) and not coalesce(l.permanently_closed, false)
       and not coalesce(l.claimed, false) and l.invited_at is null and l.invite_status is null
       and coalesce(l.whatsapp_opt, '') <> 'none'
       and (l.email is null or not exists (select 1 from public.email_suppressions s where lower(s.email) = lower(l.email)))
       and coalesce(l.linkedin, l.instagram, l.facebook, '') <> ''
  )
  select jsonb_build_object('built_at', now(), 'per_trade', p_per_trade,
           'rule', 'manual outreach from the company''s own LinkedIn / Instagram / Facebook accounts; no automation, no scraping, English only, no link in a first message',
           'trades', coalesce(jsonb_agg(jsonb_build_object('trade', x.trade, 'rank', x.rank, 'targets', x.targets) order by x.rank), '[]'::jsonb))
    into v
    from (select trade, rank, jsonb_agg(jsonb_build_object('lead_id', id, 'company', company_name, 'emirate', emirate,
                   'website', website, 'linkedin', linkedin, 'instagram', instagram, 'facebook', facebook) order by rn) targets
            from pool where rn <= greatest(1, least(coalesce(p_per_trade, 3), 10)) group by trade, rank) x;
  return v;
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_takes_the_ceo_review(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare p public.marketing_month_plan; c record; m public.marketing_plan_review_turn;  -- c: a seat_deliberation_turn (873), a record so this compiles before that table exists
        o jsonb; v_move text; v_changes jsonb; v_cited int; v_ev jsonb; v_turn bigint; v_measured boolean := false;
begin
  select * into p from public.marketing_month_plan where month = p_month;
  if p.deliberation_id is null or to_regclass('public.seat_deliberation_turn') is null then
    return jsonb_build_object('ok', true, 'taken', false, 'why', 'no deliberation yet');
  end if;
  select * into c from public.seat_deliberation_turn t
   where t.deliberation_id = p.deliberation_id and t.phase = 'compare' and t.status = 'recorded' order by t.id desc limit 1;
  if c.id is null or exists (select 1 from public.marketing_plan_review_turn where deliberation_turn_id = c.id) then
    return jsonb_build_object('ok', true, 'taken', false, 'why', 'no new CEO comparison');
  end if;
  select * into m from public.marketing_plan_review_turn where month = p_month and seat = 'marketing' order by id desc limit 1;
  o := coalesce(c.output, '{}'::jsonb);
  v_move := case c.verdict when 'approve' then 'accept' when 'revise' then 'request_changes' else 'reject' end;
  v_changes := case when jsonb_typeof(o->'changes') = 'array' and jsonb_array_length(o->'changes') > 0 then o->'changes'
                    else jsonb_build_array(jsonb_build_object('what', coalesce(c.disagreements, 'see the reasoning'),
                                                              'why', coalesce(o->>'reasoning', c.steelman_against))) end;
  v_cited := cardinality(public.fn_marketing_assets_cited(m.evidence));
  if v_move = 'accept' and coalesce(v_cited, 0) <= 2
     and public.fn_marketing_jbool(o->'criteria'->'evidence_strength'->'flagged') is not true then
    v_move := 'request_changes'; v_measured := true;
    v_changes := jsonb_build_array(jsonb_build_object(
      'what', 'Treat the plan''s central claim as a hypothesis, not a finding: it rests on ' || coalesce(v_cited, 0)
              || ' video(s)/post(s). Say how next month tests it.',
      'why', 'Criterion 2 (evidence strength), measured by code: the CEO approved without flagging a claim on 1-2 posts.'));
  end if;
  if m.round >= 3 and v_move in ('request_changes', 'reject') then v_move := 'decide'; end if;
  v_ev := case when jsonb_typeof(o->'evidence') = 'array' and jsonb_array_length(o->'evidence') > 0
                    and cardinality(public.fn_marketing_evidence_problems(o->'evidence')) = 0 then o->'evidence'
               else jsonb_build_array(jsonb_build_object('kind', 'turn', 'ref', m.id::text, 'point', 'the proposal this review answers')) end;
  insert into public.marketing_plan_review_turn (month, round, seat, move, reasoning, evidence, changes, criteria, plan, model, deliberation_turn_id)
  values (p_month, m.round, 'ceo', v_move,
          concat_ws(E'\n', o->>'reasoning', 'Agreements: ' || c.agreements, 'Disagreements: ' || c.disagreements,
                    'Strongest case against: ' || c.steelman_against,
                    case when v_measured then 'Criterion 2 applied by code: the approval became a request.' end),
          v_ev, case when v_move in ('request_changes', 'reject', 'decide') then v_changes end,
          coalesce(o->'criteria', jsonb_build_object('not_itemised', true)),
          case when v_move = 'decide' then p.plan end, c.model, c.id)
  returning id into v_turn;
  update public.marketing_month_plan
     set rounds = greatest(rounds, m.round), updated_at = now(),
         status = case when v_move in ('accept', 'decide') then 'agreed' else 'with_ceo' end,
         content_brief = case when v_move = 'accept' then public.fn_marketing_content_brief(p_month, plan)
                              when v_move = 'decide' then public.fn_marketing_content_brief(p_month, plan) || jsonb_build_object('ceo_conditions', v_changes)
                              else content_brief end
   where month = p_month;
  insert into public.marketing_model_run (step, subject, seat, task_class, outcome, model, output_table, output_ref)
  values ('ceo_review', p_month::text, 'ceo', coalesce(c.task_class, 'seat_deliberation_compare'), 'written', c.model,
          'marketing_plan_review_turn', v_turn::text);
  return jsonb_build_object('ok', true, 'taken', true, 'turn_id', v_turn, 'move', v_move, 'criterion_2_applied', v_measured);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_takes_the_inbox_placement_fix(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object('waiting', 'marketing to fix the cause the diagnosis names ('
           || coalesce(a.detail ->> 'verdict', 'misplaced') || ' on ' || coalesce(a.detail ->> 'dubai_day', a.target_id)
           || '); it_engineer closes this when a seed lands in both Inboxes')
    from public.agent_actions a where a.id = p_id
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_tick(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_rep jsonb; v_ads jsonb;
begin
  begin v_rep := public.fn_marketing_report_tick(p_at);
  exception when others then v_rep := jsonb_build_object('ok', false, 'error', left(sqlerrm, 300)); end;
  begin v_ads := public.fn_marketing_closes_ad_spend_loops();
  exception when others then v_ads := jsonb_build_object('ok', false, 'error', left(sqlerrm, 300)); end;
  return jsonb_build_object('ok', coalesce((v_rep->>'ok')::boolean, false) and coalesce((v_ads->>'ok')::boolean, false),
                            'report', v_rep, 'ad_spend_loops', v_ads);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_time_slot(p_at timestamp with time zone)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case when p_at is null then 'unscheduled' else
    to_char(p_at at time zone 'Asia/Dubai', 'Dy') || ' ' ||
    case when extract(hour from p_at at time zone 'Asia/Dubai') < 11 then 'morning'
         when extract(hour from p_at at time zone 'Asia/Dubai') < 14 then 'midday'
         when extract(hour from p_at at time zone 'Asia/Dubai') < 17 then 'afternoon'
         else 'evening' end end
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_trend_judged(p_id bigint, p_relevant boolean, p_why text, p_by text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_relevant is null then raise exception 'a trend is judged relevant or not; null is not a judgement'; end if;
  update public.marketing_trend set relevant = p_relevant, why_it_matters = nullif(btrim(p_why), ''),
         judged_at = now(), judged_by = left(p_by, 120)
   where id = p_id and relevant is null;
  return found;
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_trend_next_to_judge()
 RETURNS TABLE(id bigint, title text, url text, source text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select t.id, t.title, t.url, s.name from public.marketing_trend t join public.marketing_trend_source s on s.id = t.source_id
   where t.relevant is null and t.seen_at > now() - interval '14 days'
   order by t.seen_at desc, t.id desc limit 1
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_trend_seen(p_source_id bigint, p_items jsonb, p_error text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_new integer := 0;
begin
  update public.marketing_trend_source set last_read_at = now(), last_error = left(p_error, 500) where id = p_source_id;
  if p_error is not null then return 0; end if;
  with ins as (
    insert into public.marketing_trend (source_id, url, title, published_at)
    select p_source_id, left(i->>'url', 2000), left(i->>'title', 500), nullif(i->>'published_at', '')::timestamptz
      from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) i
     where coalesce(i->>'url', '') ~ '^https?://' and coalesce(btrim(i->>'title'), '') <> ''
    on conflict (url) do nothing returning 1)
  select count(*) into v_new from ins;
  return v_new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_trend_sources_due(p_limit integer DEFAULT 2)
 RETURNS TABLE(id bigint, name text, feed_url text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select s.id, s.name, s.feed_url from public.marketing_trend_source s
   where s.active and (s.last_read_at is null or s.last_read_at < now() - interval '20 hours')
   order by s.last_read_at nulls first, s.id limit greatest(p_limit, 0)
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_trends_for_plan(p_month date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'title', t.title, 'url', t.url, 'why_it_matters', t.why_it_matters,
                                               'published_at', t.published_at) order by t.published_at desc nulls last), '[]'::jsonb)
    from (select * from public.marketing_trend
           where relevant and coalesce(published_at, seen_at) >= (p_month - interval '45 days')
           order by coalesce(published_at, seen_at) desc limit 20) t
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_variant_problems(v marketing_post_variant)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r text[];
begin
  if to_regprocedure('public.fn_marketing_platform_spec_problems(text,text,text,text[],text,text,text)') is null then
    return null;
  end if;
  execute 'select public.fn_marketing_platform_spec_problems($1,$2,$3,$4,$5,$6,$7)'
    -- the hashtags are passed EMPTY: body already ends with them, so passing them again would count them twice
    -- (review of #874); the spec routine reads them from the body it is given
    into r using v.platform, v.post_type, v.body, '{}'::text[], v.title, v.alt_text, v.first_comment;
  return coalesce(r, '{}');
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_variant_text(p_caption text, p_hashtags text[])
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select btrim(p_caption) || case when cardinality(coalesce(p_hashtags, '{}')) > 0
                                  then E'\n\n#' || array_to_string(p_hashtags, ' #') else '' end
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_variant_violations(p_variant jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_pf text := lower(btrim(coalesce(p_variant->>'platform', '')));
  v_sf text := lower(btrim(coalesce(p_variant->>'surface', '')));
  v_cap text := coalesce(p_variant->>'caption', p_variant->>'text', '');
  v_media jsonb := coalesce(p_variant->'media', '{}'::jsonb);
  v_out jsonb := '[]'::jsonb; s record; v_actual numeric; v_bad boolean;
begin
  if not exists (select 1 from public.marketing_platform_spec where platform = v_pf and surface = v_sf) then
    return jsonb_build_array(jsonb_build_object('attribute', 'platform_surface', 'actual', v_pf || '/' || v_sf,
      'message', 'No spec rows for ' || v_pf || '/' || v_sf || '; nothing may be posted to a surface the seat has no limits for.'));
  end if;
  for s in select * from public.marketing_platform_spec
            where platform = v_pf and surface = v_sf and value_num is not null
              and attribute in ('caption_max', 'title_max', 'hashtag_max', 'mention_max', 'items_max', 'min_duration_s',
                                'max_duration_s', 'max_file_bytes', 'aspect_min', 'aspect_max', 'min_width', 'min_height',
                                'fps_min', 'fps_max') loop
    v_actual := case s.attribute
      when 'caption_max' then public.fn_marketing_caption_length(v_cap, s.counted_as)
      when 'title_max'   then case when p_variant ? 'title' then public.fn_marketing_caption_length(p_variant->>'title', coalesce(s.counted_as, 'codepoints')) end
      when 'hashtag_max' then (select count(*) from regexp_matches(v_cap, '#[^[:space:]#]+', 'g'))
      when 'mention_max' then (select count(*) from regexp_matches(v_cap, '(^|[^[:alnum:]_.])@[[:alnum:]_.]+', 'g'))
      when 'items_max'   then (v_media->>'items')::numeric
      when 'min_duration_s' then (v_media->>'duration_s')::numeric
      when 'max_duration_s' then (v_media->>'duration_s')::numeric
      when 'max_file_bytes' then (v_media->>'bytes')::numeric
      when 'aspect_min' then (v_media->>'width')::numeric / nullif((v_media->>'height')::numeric, 0)
      when 'aspect_max' then (v_media->>'width')::numeric / nullif((v_media->>'height')::numeric, 0)
      when 'min_width'  then (v_media->>'width')::numeric
      when 'min_height' then (v_media->>'height')::numeric
      when 'fps_min' then (v_media->>'fps')::numeric
      when 'fps_max' then (v_media->>'fps')::numeric
    end;
    continue when v_actual is null;
    v_bad := case when s.attribute in ('min_duration_s', 'aspect_min', 'min_width', 'min_height', 'fps_min')
                  then v_actual < s.value_num else v_actual > s.value_num end;
    if v_bad then
      v_out := v_out || jsonb_build_object('attribute', s.attribute, 'limit', s.value_num, 'actual', round(v_actual, 4),
        'counted_as', s.counted_as, 'unit', s.unit, 'source_url', s.source_url, 'read_on', s.read_on,
        'message', format('%s/%s %s: %s against a limit of %s %s (%s)', v_pf, v_sf, s.attribute, round(v_actual, 4),
                          s.value_num, coalesce(s.unit, ''), s.source_url));
    end if;
  end loop;
  -- YouTube: < and > are refused by the API in the title and the description regardless of length.
  if v_pf = 'youtube' and coalesce(p_variant->>'title', '') ~ '[<>]' then
    v_out := v_out || jsonb_build_object('attribute', 'title_characters', 'actual', p_variant->>'title',
      'source_url', 'https://developers.google.com/youtube/v3/docs/videos', 'message', 'A YouTube title may not contain < or >.');
  end if;
  if v_pf = 'youtube' and v_cap ~ '[<>]' then
    v_out := v_out || jsonb_build_object('attribute', 'caption_characters', 'actual', left(v_cap, 200),
      'source_url', 'https://developers.google.com/youtube/v3/docs/videos', 'message', 'A YouTube description may not contain < or >.');
  end if;
  return v_out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_video_days(p_month date, p_n integer DEFAULT 12)
 RETURNS SETOF date
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select d from (
    select d::date d from generate_series(p_month, (p_month + interval '1 month' - interval '1 day'), interval '1 day') d
     where public.fn_is_working_day(d::date)
     order by (extract(isodow from d) in (1, 3, 4)) desc, d
     limit p_n) x
  order by d
$function$


CREATE OR REPLACE FUNCTION public.fn_marketing_wa_supplier_invites()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  return public.fn_wa_supplier_invite_queue(20, now(), false);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketplace_analytics()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare res jsonb;
begin
  with ri as (  -- real inquiries only
    select i.* from inquiries i where not public.fn_inquiry_is_demo(i.id)
  ),
  rq as (       -- real quotes: a real inquiry and a real supplier
    select q.* from quotes q join ri on ri.id = q.inquiry_id
     where not exists (select 1 from leads l where l.id = q.supplier_id and l.is_demo)
  ),
  q_first as (  -- first quote latency per rfq
    select i.id, min(qq.created_at) as first_quote_at, i.created_at, i.category
    from ri i left join rq qq on qq.inquiry_id = i.id group by i.id, i.created_at, i.category
  ),
  spread as (  -- savings potential per rfq with >=2 quotes
    select inquiry_id, min(quote_amount) lo, max(quote_amount) hi, count(*) n
    from rq where quote_amount > 0 group by inquiry_id having count(*) >= 2
  )
  select jsonb_build_object(
    'rfqs_today',   (select count(*) from ri where created_at >= date_trunc('day', now())),
    'rfqs_7d',      (select count(*) from ri where created_at >= now() - interval '7 days'),
    'rfqs_30d',     (select count(*) from ri where created_at >= now() - interval '30 days'),
    'avg_first_quote_hours', (select round(avg(extract(epoch from (first_quote_at - created_at))/3600.0)::numeric,1) from q_first where first_quote_at is not null),
    'response_rate_pct', (
      select case when count(*)>0 then round(100.0 * count(*) filter (where exists (
        select 1 from rq q where q.inquiry_id = m.inquiry_id and q.supplier_id = m.supplier_id)) / count(*), 1) else null end
      from inquiry_matches m join ri on ri.id = m.inquiry_id),
    'avg_savings_pct', (select round(avg(case when hi>0 then 100.0*(hi-lo)/hi else 0 end)::numeric,1) from spread),
    'abandoned_rfqs', (select count(*) from ri i where i.created_at < now() - interval '7 days'
                        and coalesce(i.status,'') not in ('completed','cancelled')
                        and not exists (select 1 from rq q where q.inquiry_id = i.id)),
    'active_suppliers_30d', (select count(distinct supplier_id) from rq where created_at >= now() - interval '30 days'),
    'supplier_capacity_avg', (select round(avg(c)::numeric,1) from (select supplier_id, count(*) c from rq where created_at >= now() - interval '30 days' group by supplier_id) s),
    'competitive_categories', (
      select coalesce(jsonb_agg(x order by x.avg_quotes desc), '[]'::jsonb) from (
        select i.category, round(avg(qc.c)::numeric,2) as avg_quotes, count(*) as rfqs
        from ri i join (select inquiry_id, count(*) c from rq group by inquiry_id) qc on qc.inquiry_id=i.id
        where i.created_at >= now() - interval '90 days' and i.category is not null
        group by i.category order by avg_quotes desc limit 8) x),
    'category_growth', (
      select coalesce(jsonb_agg(g), '[]'::jsonb) from (
        select category,
          count(*) filter (where created_at >= now() - interval '30 days') as this_30d,
          count(*) filter (where created_at >= now() - interval '60 days' and created_at < now() - interval '30 days') as prev_30d
        from ri where category is not null and created_at >= now() - interval '60 days'
        group by category order by this_30d desc limit 10) g),
    'generated_at', now()
  ) into res;
  return res;
end $function$


CREATE OR REPLACE FUNCTION public.fn_mask_bank_text(p text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v text := p;
begin
  if v is null then return null; end if;
  -- An IBAN printed in groups of four, then a compact one.
  v := regexp_replace(v, '\m[A-Z]{2}[0-9]{2} [A-Z0-9]{4}( [0-9]{4}){2,6}( [0-9]{1,4})?\M', '[IBAN]', 'g');
  v := regexp_replace(v, '\m[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}\M', '[IBAN]', 'g');
  -- Any alphanumeric token holding 8+ digits, in ONE positional pass. The lookahead holds at a token's
  -- first character exactly when the token has 8+ digits, and the match then runs to the token's end.
  -- (Review of #684: a per-token text replace let one overlapping token rewrite another first and
  -- leaked 9 digits.) A date splits into short tokens and survives; output holds no digit run to re-mask.
  return regexp_replace(v, '(?=(?:[A-Za-z]*[0-9]){8})[A-Za-z0-9]+', '[ref]', 'g');
end $function$


CREATE OR REPLACE FUNCTION public.fn_mask_email(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case when position('@' in coalesce(p, '')) > 1
              then left(split_part(lower(btrim(p)), '@', 1), 2) || '***@' || split_part(lower(btrim(p)), '@', 2)
              else '***' end
$function$


CREATE OR REPLACE FUNCTION public.fn_match_capability(p_trades text[], p_need text DEFAULT 'executes'::text, p_products text[] DEFAULT '{}'::text[], p_brands text[] DEFAULT '{}'::text[], p_project_type text DEFAULT NULL::text, p_value numeric DEFAULT NULL::numeric, p_emirate text DEFAULT NULL::text, p_limit integer DEFAULT 12, p_services text[] DEFAULT '{}'::text[])
 RETURNS TABLE(supplier_id bigint, company_name text, score numeric, trades text[], roles text[], product_hits integer, brand_hit boolean, ptype_hit boolean, track numeric, why text, service_hits text[], via_implication text[])
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
with w as (
  select coalesce((select value::text::numeric from decision_policy where key='score_w_product'),40)      as w_prod,
         coalesce((select value::text::numeric from decision_policy where key='score_w_brand'),20)        as w_brand,
         coalesce((select value::text::numeric from decision_policy where key='score_w_project_type'),15) as w_ptype,
         coalesce((select value::text::numeric from decision_policy where key='score_w_track_record'),15) as w_track,
         coalesce((select value::text::numeric from decision_policy where key='score_w_size_fit'),10)     as w_size
),
-- EXACT (23 Sep 2026, decision point 25): the request's terms and the supplier's, each lower-cased and
-- trimmed, then compared for equality. A substring is not a match: "door" is not "door closer".
q as (
  select array(select distinct lower(btrim(x)) from unnest(coalesce(p_products, '{}'::text[])) x where nullif(btrim(x), '') is not null) as products,
         array(select distinct lower(btrim(x)) from unnest(coalesce(p_brands, '{}'::text[])) x where nullif(btrim(x), '') is not null) as brands,
         nullif(lower(btrim(coalesce(p_project_type, ''))), '') as ptype,
         nullif(lower(btrim(coalesce(p_emirate, ''))), '') as emirate
),
req_auth as (
  select coalesce(array_agg(distinct a),'{}') as codes
  from public.taxonomy_trade t, unnest(t.authority_required) a
  where t.code = any(p_trades)
),
named as (
  select distinct s as key, split_part(s, '.', 1) as tr
  from unnest(coalesce(p_services, '{}'::text[])) s
  where position('.' in s) > 0
    and exists (select 1 from public.taxonomy_trade_service ts
                where ts.active and ts.trade_code || '.' || ts.code = s)
),
n as (select count(*)::int as k from named),
loc as (
  select sc.supplier_id,
         array(select distinct lower(btrim(e)) from unnest(coalesce(sc.coverage_emirates, '{}'::text[])
                                           || coalesce(l.service_emirates, '{}'::text[])) e
                where nullif(btrim(e), '') is not null) as stated
  from public.supplier_capabilities sc
  join public.leads l on l.id = sc.supplier_id
),
cand as (
  select sc.supplier_id, sc.trades, sc.roles, sc.products_norm, sc.brands, sc.project_types,
         sc.min_project_value, sc.max_project_value, sc.coverage_emirates,
         sc.services, sc.services_removed,
         l.company_name, l.emirate as lead_emirate,
         -- 23 Sep 2026 (sales_engineer.supplier_performance): the measured score comes first; the view's quote rate
         -- and perf_score remain the fallback for a supplier the platform has not measured yet.
         least(1, greatest(0, coalesce(pf.score, sp.quote_rate, sp.perf_score, 0))) as track,
         ((select emirate from q) is not null and (select emirate from q) = any(loc.stated)) as in_emirate,
         cardinality(loc.stated) as stated_n
  from public.supplier_capabilities sc
  join public.leads l on l.id = sc.supplier_id
  join loc on loc.supplier_id = sc.supplier_id
  left join public.supplier_perf sp on sp.supplier_id = sc.supplier_id
  left join public.supplier_performance pf on pf.lead_id = sc.supplier_id
  left join public.supplier_availability av on av.supplier_id = sc.supplier_id
  where sc.confirmed_at is not null
    and sc.trades && p_trades
    and not (sc.excluded_trades && p_trades)
    and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked,
                               l.approval_status, l.permanently_closed, l.chat_strikes)
    -- 29 Sep 2026 (ledger 1033): a supplier who said he is busy or paused is not sent a request. No row = available;
    -- a busy date that has come reads as available here, whether or not the duty has rewritten the row yet.
    and public.fn_supplier_available(av.state, av.busy_until)
    and exists (
      select 1 from public.taxonomy_role r
      where r.code = any(sc.roles)
        and case p_need when 'supplies'    then r.supplies
                        when 'whole_scope' then r.whole_scope
                        else r.executes end
    )
    and not exists (
      select 1 from unnest((select codes from req_auth)) a
      where not (sc.authority_approvals ? a)
    )
    and (p_value is null or (
          (sc.min_project_value is null or p_value >= sc.min_project_value)
      and (sc.max_project_value is null or p_value <= sc.max_project_value)))
    and ((select emirate from q) is null
      or cardinality(loc.stated) = 0
      or (select emirate from q) = any(loc.stated))
),
eff as (
  select c.*,
         case when (select k from n) = 0 then '{}'::text[]
              else public.fn_services_effective(c.services, c.trades, c.services_removed) end as eff_services
  from cand c
),
svc as (
  select e.*,
    array(select unnest(e.eff_services) intersect select key from named) as service_hits,
    not exists (select 1 from named t where t.tr = any(coalesce(e.trades, '{}'::text[]))) as never_asked,
    -- ponytail: one scan of service_implication per candidate (113 curated rows); batch it with a single
    -- unnest+join if the map or the candidate count grows an order of magnitude.
    array(
      select distinct i.from_code || ' -> ' || i.implies_trade || '.' || i.implies_code
      from public.service_implication i
      where i.active
        and (i.implies_trade || '.' || i.implies_code) = any(e.eff_services)
        and (i.implies_trade || '.' || i.implies_code) in (select key from named)
        and not ((i.implies_trade || '.' || i.implies_code) = any(coalesce(e.services, '{}'::text[])))
        and (i.from_code = any(coalesce(e.trades, '{}'::text[]))
          or i.from_code = any(coalesce(e.services, '{}'::text[])))
      order by 1) as via_implication
  from eff e
),
scored as (
  select c.*,
    -- EXACT: a requested product counts when the supplier declares that same product.
    (select count(*) from unnest((select products from q)) pq
      where pq = any(array(select lower(btrim(pp)) from unnest(coalesce(c.products_norm, '{}'::text[])) pp)))::int as product_hits,
    (cardinality((select brands from q)) > 0 and exists (
       select 1 from unnest(coalesce(c.brands, '{}'::text[])) bb where lower(btrim(bb)) in (select unnest(q.brands) from q)
     )) as brand_hit,
    ((select ptype from q) is not null and exists (
       select 1 from unnest(coalesce(c.project_types, '{}'::text[])) pt where lower(btrim(pt)) = (select ptype from q)
     )) as ptype_hit,
    (p_value is not null and c.min_project_value is not null and c.max_project_value is not null) as size_known
  from svc c
  where (select k from n) = 0
     or cardinality(c.service_hits) > 0
     or c.never_asked
),
ranked as (
  select s.*,
    round(
        w.w_prod  * (case when cardinality((select products from q)) > 0
                          then s.product_hits::numeric / cardinality((select products from q)) else 0 end)
      + w.w_brand * (case when s.brand_hit then 1 else 0 end)
      + w.w_ptype * (case when s.ptype_hit then 1 else 0 end)
      + w.w_track * s.track
      + w.w_size  * (case when s.size_known then 1 else 0.5 end)
    , 1) as score_v
  from scored s, w
)
select r.supplier_id, r.company_name, r.score_v as score,
  r.trades, r.roles, r.product_hits, r.brand_hit, r.ptype_hit, round(r.track,3) as track,
  concat_ws(' · ',
    'trades ' || array_to_string(array(select unnest(r.trades) intersect select unnest(p_trades)), '+'),
    case when cardinality(r.service_hits) > 0 then cardinality(r.service_hits)||'/'||(select k from n)||' services' end,
    case when (select k from n) > 0 and r.never_asked and cardinality(r.service_hits) = 0
           then 'trade level (no service named in this supplier''s trades)' end,
    case when cardinality(r.via_implication) > 0 then 'implied: ' || array_to_string(r.via_implication, ', ') end,
    case when r.product_hits > 0 then r.product_hits||'/'||cardinality((select products from q))||' products' end,
    case when r.brand_hit then 'brand match' end,
    case when r.ptype_hit then 'project type' end,
    case when p_emirate is not null then
      case when r.in_emirate then 'in ' || p_emirate else 'UAE-wide (no stated limit)' end end
  ) as why,
  r.service_hits, r.via_implication
from ranked r
order by r.score_v desc, cardinality(r.service_hits) desc, r.in_emirate desc, r.track desc, r.supplier_id
limit greatest(1, p_limit);
$function$


CREATE OR REPLACE FUNCTION public.fn_matching_strike_limit()
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce((select value::text::int from public.decision_policy where key='matching_strike_limit'), 3);
$function$


CREATE OR REPLACE FUNCTION public.fn_memory_search(p_q text, p_kinds text[] DEFAULT NULL::text[], p_lim integer DEFAULT 20)
 RETURNS TABLE(kind text, ref text, snippet text, ts timestamp with time zone, score real)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with qy as (select plainto_tsquery('english', coalesce(p_q,'')) q)
  select s.kind, s.ref, s.snippet, s.ts, s.score from (
    select 'rfq'::text kind, i.id::text ref, left(coalesce(i.summary, i.raw_input, i.spec::text),220) snippet,
           i.created_at ts, ts_rank(to_tsvector('english', coalesce(i.summary,'')||' '||coalesce(i.raw_input,'')||' '||coalesce(i.spec::text,'')||' '||coalesce(i.category,'')), qy.q) score
    from inquiries i, qy where (p_kinds is null or 'rfq'=any(p_kinds))
      and to_tsvector('english', coalesce(i.summary,'')||' '||coalesce(i.raw_input,'')||' '||coalesce(i.spec::text,'')||' '||coalesce(i.category,'')) @@ qy.q
    union all
    select 'quote', q.id::text, left(coalesce(q.scope, q.notes),220), q.created_at,
           ts_rank(to_tsvector('english', coalesce(q.scope,'')||' '||coalesce(q.notes,'')||' '||coalesce(q.conditions,'')), qy.q)
    from quotes q, qy where (p_kinds is null or 'quote'=any(p_kinds))
      and to_tsvector('english', coalesce(q.scope,'')||' '||coalesce(q.notes,'')||' '||coalesce(q.conditions,'')) @@ qy.q
    union all
    select 'supplier', l.id::text, left(coalesce(l.company_name,'')||' — '||coalesce(l.capability_summary, l.description, l.services),220), l.created_at,
           ts_rank(to_tsvector('english', coalesce(l.company_name,'')||' '||coalesce(l.capability_summary,'')||' '||coalesce(l.services,'')||' '||coalesce(l.description,'')||' '||coalesce(l.categories,'')), qy.q)
    from leads l, qy where (p_kinds is null or 'supplier'=any(p_kinds))
      and to_tsvector('english', coalesce(l.company_name,'')||' '||coalesce(l.capability_summary,'')||' '||coalesce(l.services,'')||' '||coalesce(l.description,'')||' '||coalesce(l.categories,'')) @@ qy.q
    union all
    select 'customer', c.id::text, left(coalesce(c.full_name,'')||' '||coalesce(c.email,''),220), c.created_at,
           ts_rank(to_tsvector('english', coalesce(c.full_name,'')||' '||coalesce(c.email,'')), qy.q)
    from customers c, qy where (p_kinds is null or 'customer'=any(p_kinds))
      and to_tsvector('english', coalesce(c.full_name,'')||' '||coalesce(c.email,'')) @@ qy.q
    union all
    select 'case', a.rfq_id, left(coalesce(a.ai_summary->>'summary',''),220), a.created_at,
           ts_rank(to_tsvector('english', coalesce(a.ai_summary->>'summary','')||' '||coalesce(a.category,'')), qy.q)
    from rfq_archives a, qy where (p_kinds is null or 'case'=any(p_kinds))
      and to_tsvector('english', coalesce(a.ai_summary->>'summary','')||' '||coalesce(a.category,'')) @@ qy.q
    union all
    select 'knowledge', k.agent_key||' :: '||k.topic, left(k.content,220), k.created_at,
           ts_rank(to_tsvector('english', coalesce(k.topic,'')||' '||coalesce(k.content,'')), qy.q)
    from agent_knowledge k, qy where (p_kinds is null or 'knowledge'=any(p_kinds))
      and to_tsvector('english', coalesce(k.topic,'')||' '||coalesce(k.content,'')) @@ qy.q
    union all
    select 'decision', dl.id::text, left(dl.kind||' -> '||coalesce(dl.decision,'')||' '||coalesce(dl.reasons::text,''),220), dl.created_at,
           ts_rank(to_tsvector('english', coalesce(dl.kind,'')||' '||coalesce(dl.decision,'')||' '||coalesce(dl.reasons::text,'')), qy.q)
    from decision_log dl, qy where (p_kinds is null or 'decision'=any(p_kinds))
      and to_tsvector('english', coalesce(dl.kind,'')||' '||coalesce(dl.decision,'')||' '||coalesce(dl.reasons::text,'')) @@ qy.q
  ) s
  order by s.score desc, s.ts desc
  limit greatest(1, coalesce(p_lim,20));
$function$


CREATE OR REPLACE FUNCTION public.fn_ml_embed_claim(p_limit integer DEFAULT 16)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_go     text := (select value from public.app_secrets where key = 'ml_embed_golive');
  v_cap    integer := coalesce((select nullif(value, '')::integer from public.app_secrets where key = 'ml_embed_daily_cap'), 0);
  v_today  integer;
  v_want   integer;
  v_rows   jsonb := '[]'::jsonb;
  v_src    text;
  v_part   jsonb;
  v_reached_kb boolean := false;
begin
  if coalesce(v_go, 'false') <> 'true' then
    return jsonb_build_object('ok', true, 'rows', v_rows, 'reason', 'ml_embed_golive is not true');
  end if;
  select count(*) into v_today from public.knowledge_vector_ml where embedded_at >= date_trunc('day', now());
  v_want := least(greatest(coalesce(p_limit, 16), 1), 64, greatest(v_cap - v_today, 0));
  if v_want = 0 then
    return jsonb_build_object('ok', true, 'rows', v_rows, 'reason', 'daily cap reached', 'today', v_today, 'cap', v_cap);
  end if;
  delete from public.knowledge_ml_claim where claimed_at < now() - interval '5 minutes';
  -- One source at a time, in priority order: each query is a limited anti-join on one table's key (the view
  -- prunes every other branch on src) and stops as soon as it has enough rows.
  for v_src in select unnest(array['seat_case_memory', 'ceo_knowledge', 'support_knowledge', 'accountant_knowledge',
      'it_engineer_knowledge', 'marketing_knowledge', 'sales_knowledge', 'company_faq', 'agent_knowledge', 'ops_knowledge',
      'reasoning_knowledge_candidate', 'kb_chunks']) loop
    exit when jsonb_array_length(v_rows) >= v_want;
    -- Reaching kb_chunks with nothing claimed means every earlier source had nothing unclaimed. Only THIS
    -- proves the priority sources are done; an empty answer for another reason (the cap, the gate) proves nothing.
    if v_src = 'kb_chunks' and jsonb_array_length(v_rows) = 0 then v_reached_kb := true; end if;
    with pick as (
      select s.src, s.row_id, s.title, s.body
        from public.v_knowledge_ml_source s
       where s.src = v_src and btrim(coalesce(s.body, '')) <> ''
         and not exists (select 1 from public.knowledge_vector_ml v where v.src = s.src and v.row_id = s.row_id)
         and not exists (select 1 from public.knowledge_ml_claim c where c.src = s.src and c.row_id = s.row_id)
       limit v_want - jsonb_array_length(v_rows)
    ), claimed as (
      insert into public.knowledge_ml_claim (src, row_id) select src, row_id from pick
      on conflict do nothing returning src, row_id
    )
    select coalesce(jsonb_agg(jsonb_build_object('src', p.src, 'row_id', p.row_id, 'title', p.title,
             'body', left(p.body, 8000), 'hash', md5(coalesce(p.title, '') || E'\n' || coalesce(p.body, '')))), '[]'::jsonb)
      into v_part
      from pick p join claimed c using (src, row_id);
    v_rows := v_rows || v_part;
  end loop;
  -- The read switch: the first time nothing but kb_chunks is left, the seats may read the ml space.
  if v_reached_kb and (select priority_complete_at from public.knowledge_ml_status) is null
     and not exists (select 1 from public.knowledge_ml_claim c where c.src <> 'kb_chunks') then
    update public.knowledge_ml_status set priority_complete_at = now(),
      note = 'every source except kb_chunks embedded; fn_ml_read_space answers ml unless ml_embed_read overrides'
     where id and priority_complete_at is null;
  end if;
  return jsonb_build_object('ok', true, 'rows', v_rows, 'today', v_today, 'cap', v_cap);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ml_embed_write(p_src text, p_row_id text, p_hash text, p_embedding vector, p_embedding_gte vector DEFAULT NULL::vector)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare v_now_hash text;
begin
  if p_embedding is null then raise exception 'fn_ml_embed_write: no vector for %/%', p_src, p_row_id; end if;
  if p_src in ('support_knowledge', 'ceo_knowledge') and p_embedding_gte is null then
    raise exception 'fn_ml_embed_write: % rows carry their gte-small vector too', p_src;
  end if;
  if p_src = 'kb_chunks' then
    if p_row_id ~ '^[0-9]{1,18}$' then
      select md5(coalesce(k.title, '') || E'\n' || coalesce(k.content, '')) into v_now_hash
        from public.kb_chunks k where k.id = p_row_id::bigint;
    end if;
  else
    select md5(coalesce(s.title, '') || E'\n' || coalesce(s.body, '')) into v_now_hash
      from public.v_knowledge_ml_source s where s.src = p_src and s.row_id = p_row_id;
  end if;
  delete from public.knowledge_ml_claim where src = p_src and row_id = p_row_id;
  if v_now_hash is distinct from p_hash then return false; end if;
  insert into public.knowledge_vector_ml (src, row_id, text_hash, embedding) values (p_src, p_row_id, p_hash, p_embedding)
  on conflict (src, row_id) do update set text_hash = excluded.text_hash, embedding = excluded.embedding, embedded_at = now();
  if p_src = 'support_knowledge' then
    update public.support_knowledge set embedding_gte = p_embedding_gte where record_id = p_row_id;
  elsif p_src = 'ceo_knowledge' then
    update public.ceo_knowledge set embedding_gte = p_embedding_gte where record_id = p_row_id;
  end if;
  return true;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ml_read_space()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case coalesce((select value from public.app_secrets where key = 'ml_embed_read'), 'auto')
           when 'gte' then 'gte'
           when 'ml' then 'ml'
           else case when (select priority_complete_at from public.knowledge_ml_status) is not null then 'ml' else 'gte' end
         end;
$function$


CREATE OR REPLACE FUNCTION public.fn_ml_vectors_stale()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  delete from public.knowledge_vector_ml where src = tg_argv[0] and row_id = to_jsonb(old) ->> tg_argv[1];
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_model_catalogue_decide(p_registry jsonb, p_matrix text[], p_catalogue jsonb)
 RETURNS TABLE(model_id text, field text, old_value numeric, new_value numeric, drift_pct numeric, matrix boolean, decision text)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with reg as (
    select r->>'model_id' as id, (r->>'in')::numeric as v_in, (r->>'out')::numeric as v_out, (r->>'ctx')::numeric as v_ctx,
           (r->>'model_id') = any (coalesce(p_matrix, '{}')) as m
      from jsonb_array_elements(coalesce(p_registry, '[]')) r
  ), cat as (
    select c->>'id' as id,
           round(nullif(c->'pricing'->>'prompt', '')::numeric * 1000000, 4)     as l_in,
           round(nullif(c->'pricing'->>'completion', '')::numeric * 1000000, 4) as l_out,
           nullif(c->>'context_length', '')::numeric                             as l_ctx
      from jsonb_array_elements(coalesce(p_catalogue, '[]')) c
  ), joined as (
    -- exact id first; a variant such as ':online' is priced as its base model
    select reg.*, coalesce(e.id, b.id) as cid,
           coalesce(e.l_in, b.l_in) l_in, coalesce(e.l_out, b.l_out) l_out, coalesce(e.l_ctx, b.l_ctx) l_ctx
      from reg
      left join cat e on e.id = reg.id
      left join cat b on e.id is null and b.id = split_part(reg.id, ':', 1)
  ), pairs as (
    select j.id, j.m, f.field, f.o, f.l
      from joined j
      cross join lateral (values ('in', j.v_in, j.l_in), ('out', j.v_out, j.l_out), ('ctx', j.v_ctx, j.l_ctx)) f(field, o, l)
     where j.cid is not null
  )
  select p.id, p.field, p.o, p.l,
         case when coalesce(p.o, 0) = 0 then null else round(abs(p.l - p.o) / p.o * 100, 2) end,
         p.m, 'changed'
    from pairs p
   where p.l is not null and p.o is distinct from p.l
  union all
  select j.id, 'absent', null, null, null, j.m, 'absent' from joined j where j.cid is null
$function$


CREATE OR REPLACE FUNCTION public.fn_model_catalogue_matrix()
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(array_agg(distinct m) filter (where m is not null), '{}') from (
    select model_primary m from public.model_policy where active
    union all select model_fallback from public.model_policy where active
    union all select primary_model from public.model_policy_by_identity
    union all select fallback_model from public.model_policy_by_identity
    union all select model_id from public.review_pool where active
  ) x
$function$


CREATE OR REPLACE FUNCTION public.fn_model_catalogue_sync(p_catalogue jsonb, p_only text[] DEFAULT NULL::text[], p_matrix text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_reg jsonb; v_matrix text[]; d record; c public.model_catalogue_change; v_items jsonb := '[]'::jsonb;
  n_open int := 0; n_new int := 0; n_resolved int := 0; v_res jsonb;
begin
  if jsonb_typeof(p_catalogue) is distinct from 'array' or jsonb_array_length(p_catalogue) < 50 then
    raise exception 'fn_model_catalogue_sync: the catalogue is not an array of at least 50 models (got %), so nothing is compared',
      coalesce(jsonb_typeof(p_catalogue), 'null') || case when jsonb_typeof(p_catalogue) = 'array' then ' of ' || jsonb_array_length(p_catalogue) else '' end;
  end if;
  v_matrix := coalesce(p_matrix, public.fn_model_catalogue_matrix());
  select coalesce(jsonb_agg(jsonb_build_object('model_id', r.model_id, 'in', r.in_per_mtok_usd, 'out', r.out_per_mtok_usd,
                                               'ctx', r.context_len)), '[]')
    into v_reg from public.model_registry r
   where r.active and (p_only is null or r.model_id = any (p_only));

  for d in select * from public.fn_model_catalogue_decide(v_reg, v_matrix, p_catalogue) loop
    select * into c from public.model_catalogue_change
     where model_id = d.model_id and field = d.field and closed_at is null;
    if not found then
      insert into public.model_catalogue_change (model_id, field, old_value, new_value, drift_pct, matrix)
      values (d.model_id, d.field, d.old_value, d.new_value, d.drift_pct, d.matrix) returning * into c;
      n_new := n_new + 1;
    else
      update public.model_catalogue_change
         set old_value = d.old_value, new_value = d.new_value, drift_pct = d.drift_pct, matrix = d.matrix, last_seen_at = now()
       where id = c.id returning * into c;
    end if;
    n_open := n_open + 1;
    v_items := v_items || case when d.decision = 'absent' then
      jsonb_build_object('item', 'absent:' || d.model_id, 'owner_seat', 'it_engineer', 'subject', d.model_id,
        'blast', case when d.matrix then 'customer_facing' else 'internal' end,
        'title', d.model_id || ' is active in model_registry but the OpenRouter catalogue no longer lists it'
                 || case when d.matrix then ' - a route of the founder''s matrix names it, so those calls will fail at the provider' else '' end,
        'evidence', jsonb_build_object('change_id', c.id, 'model_id', d.model_id, 'matrix', d.matrix))
    else
      jsonb_build_object('item', 'change:' || d.model_id || ':' || d.field, 'owner_seat', 'it_engineer',
        'subject', d.model_id, 'blast', 'internal',
        'title', 'The catalogue serves ' || d.model_id || ' ' || d.field || ' at ' || d.new_value || ', the registry states '
                 || coalesce(d.old_value::text, 'null') || coalesce(' (' || d.drift_pct || '%)', '')
                 || case when d.matrix then ', a model of the founder''s matrix' else '' end
                 || '. Nothing was changed: a correction is a reviewed SQL file.',
        'evidence', jsonb_build_object('change_id', c.id, 'model_id', d.model_id, 'field', d.field, 'old', d.old_value,
                                       'new', d.new_value, 'drift_pct', d.drift_pct, 'matrix', d.matrix))
    end;
  end loop;

  -- An open row the catalogue and the registry agree on again is resolved.
  with gone as (
    update public.model_catalogue_change m set outcome = 'resolved', closed_at = now()
     where m.closed_at is null
       and (p_only is null or m.model_id = any (p_only))
       and not exists (select 1 from public.fn_model_catalogue_decide(v_reg, v_matrix, p_catalogue) x
                        where x.model_id = m.model_id and x.field = m.field)
    returning 1)
  select count(*) into n_resolved from gone;

  v_res := jsonb_build_object('compared', jsonb_array_length(v_reg), 'open', n_open, 'new', n_new,
                              'resolved', n_resolved, 'items', v_items);
  if p_only is null then
    v_res := v_res || jsonb_build_object('settle', public.fn_it_duty_settle('model_catalogue', v_items));
    perform public.fn_it_duty_ran('model_catalogue', v_res - 'items');
  end if;
  return v_res;
end $function$


CREATE OR REPLACE FUNCTION public.fn_model_cost_usd(p_model text, p_in_tokens integer, p_out_tokens integer, p_cached_in_tokens integer DEFAULT 0)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select round(
      ( (greatest(coalesce(p_in_tokens,0) - coalesce(p_cached_in_tokens,0), 0)::numeric / 1000000) * r.in_per_mtok_usd
      + (coalesce(p_cached_in_tokens,0)::numeric / 1000000) * coalesce(r.cache_read_per_mtok_usd, r.in_per_mtok_usd)
      + (coalesce(p_out_tokens,0)::numeric / 1000000) * r.out_per_mtok_usd
      )::numeric, 6)
  from model_registry r where r.model_id = p_model;
$function$


CREATE OR REPLACE FUNCTION public.fn_money_move_hold_release(p_hold_id bigint, p_by text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare h public.money_move_hold;
begin
  if coalesce(btrim(p_by), '') in ('', 'screen') then raise exception 'a release names the person or seat who reviewed it'; end if;
  if coalesce(btrim(p_note), '') = '' then raise exception 'a release says why the money may move'; end if;
  select * into h from public.money_move_hold where id = p_hold_id for update;
  if not found then raise exception 'no money hold %', p_hold_id; end if;
  if h.status <> 'held' then return jsonb_build_object('released', false, 'reason', 'the move is ' || h.status || ', not held'); end if;
  update public.money_move_hold set status = 'released', released_at = now(), released_by = btrim(p_by), release_reason = btrim(p_note)
   where id = h.id;
  perform public.fn_seat_handoff('accountant', 'customer_support', 'fraud.money_released', 'money_move_hold', h.id::text,
    jsonb_build_object('hold_id', h.id, 'move', h.move, 'ref', h.ref));
  return jsonb_build_object('released', true, 'hold_id', h.id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_norm_trades(p_text text)
 RETURNS text[]
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- A live taxonomy code or an intake slug resolves exactly; free text resolves to NULL, which every
  -- caller already treats as "no trade" and which a TS caller reasons (think()) instead.
  select case when cardinality(r.codes) > 0 then r.codes end
    from (select array(select c from unnest(public.fn_taxonomy_trades_for(array[btrim(coalesce(p_text, ''))])) c
                        where exists (select 1 from public.taxonomy_trade t where t.code = c and t.active)
                        order by c) as codes) r;
$function$


CREATE OR REPLACE FUNCTION public.fn_norm_trades_many(p_texts text[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- phrase -> the codes fn_norm_trades resolves it to; a phrase that resolves to nothing is left out.
  -- ponytail: 400 phrases per call is the caller's cap (trade_resolve.ts EXACT_MAX_PHRASES).
  select coalesce(jsonb_object_agg(x.t, to_jsonb(x.codes)), '{}'::jsonb)
    from (select distinct u.t, public.fn_norm_trades(u.t) as codes
            from unnest(coalesce(p_texts, '{}'::text[])) u(t)
           where nullif(btrim(u.t), '') is not null) x
   where x.codes is not null;
$function$


CREATE OR REPLACE FUNCTION public.fn_normalize_founder_alert_level()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF lower(coalesce(NEW.level,'')) = 'crit' THEN NEW.level := 'critical'; END IF;
  RETURN NEW;
END
$function$


CREATE OR REPLACE FUNCTION public.fn_notification_attachment_policy()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_a jsonb; v_bucket text; v_path text; v_file text; v_n int;
begin
  if new.attachments is null then return new; end if;

  if jsonb_typeof(new.attachments) <> 'array' then
    raise exception 'notifications.attachments must be a jsonb ARRAY of {bucket, path, filename}, got %',
      jsonb_typeof(new.attachments);
  end if;

  v_n := jsonb_array_length(new.attachments);
  if v_n = 0 then
    -- An empty array is the caller saying "attach nothing", which is what NULL means. Normalise it
    -- so send_outbox has one shape to read and cannot tell the two apart.
    new.attachments := null;
    return new;
  end if;
  if v_n > 5 then
    raise exception 'notifications.attachments holds % entries; a covering email carries at most 5', v_n;
  end if;

  for v_a in select jsonb_array_elements(new.attachments) loop
    v_bucket := v_a->>'bucket'; v_path := v_a->>'path'; v_file := v_a->>'filename';

    if v_bucket is null or v_path is null or v_file is null then
      raise exception 'each attachment needs bucket, path and filename; got %', v_a::text;
    end if;

    -- The allow-list. Every bucket here holds documents THIS COMPANY generated for itself.
    if v_bucket not in ('finance-reports','finance-docs','agent-docs','reports','compliance-docs') then
      raise exception 'attachment bucket % is not attachable. Allowed: finance-reports, finance-docs, agent-docs, reports, compliance-docs', v_bucket;
    end if;

    if v_path = '' or v_path like '%..%' then
      raise exception 'attachment path % is refused (empty, or contains "..")', v_path;
    end if;

    if v_file !~ '^[A-Za-z0-9 ._-]{1,120}$' then
      raise exception 'attachment filename % is refused: only letters, digits, space, dot, underscore and hyphen, up to 120 characters', v_file;
    end if;
  end loop;

  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_notification_is_promotional(p_type text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$ select coalesce(p_type, '') like 'promo\_%' $function$


CREATE OR REPLACE FUNCTION public.fn_notification_severity(p_severity text, p_type text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(p_severity, (select t.severity from public.notification_type_severity t where t.type = p_type))
$function$


CREATE OR REPLACE FUNCTION public.fn_notifications_claim(p_channel text, p_limit integer DEFAULT 25)
 RETURNS SETOF notifications
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_lim int := greatest(1, least(coalesce(p_limit, 25), 200));
begin
  -- A sender that died holding a claim must not hold it forever. `claimed_at is null` is in the
  -- predicate deliberately (added after independent review): notifications has NO check constraint on
  -- status, so a row in 'sending' with no claimed_at is reachable — a hand-written UPDATE, a restore, a
  -- future writer — and `claimed_at < now() - interval` is NULL for it, so without this branch such a
  -- row would sit in 'sending' for ever, drained by nobody and requeued by nobody. A row that says it
  -- is being sent but cannot say since when is not a claim; it goes back on the queue.
  update public.notifications n
     set status = 'queued', claimed_at = null,
         last_error = left(case when n.claimed_at is null
                                then 'status was sending with no claimed_at, which is not a claim; requeued'
                                else 'a send claim expired after 5 minutes without an outcome; requeued' end, 500)
   where n.status = 'sending' and (n.claimed_at is null or n.claimed_at < now() - interval '5 minutes');

  return query
    update public.notifications n
       set status = 'sending', claimed_at = now()
     where n.id in (
       select c.id from public.notifications c
        where (c.status in ('queued', 'pending') or c.status is null)
          -- THE SAME OWNERSHIP RULE AS channels.ts, in one place. 'email' owns a NULL channel and
          -- anything that is not sms or whatsapp; any other value is that channel exactly.
          and (case when p_channel = 'email' then (c.channel is null or c.channel not in ('sms', 'whatsapp'))
                    else c.channel = p_channel end)
          -- NOT BEFORE ITS TIME: enqueue_supplier_invites spreads a day's invitations across the Dubai
          -- working window with not_before. NULL means now.
          and (c.not_before is null or c.not_before <= now())
          -- A channel that addresses a handset cannot send a row with no handset on it.
          and (p_channel <> 'whatsapp' or c.to_phone is not null)
        order by c.created_at
        limit v_lim
        for update skip locked)
    returning n.*;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_notifications_demo_capture()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- Only a row that a dispatcher could still pick up is judged; a terminal state is left alone.
  -- 'digest' is on that list: trg_notifications_digest parks admin/founder rows there for the
  -- founder's digest mail, so a row about a demo entity would otherwise reach him in a digest.
  if coalesce(NEW.status, 'pending') not in ('queued', 'pending', 'held', 'digest') then return NEW; end if;
  if TG_OP = 'UPDATE' and coalesce(NEW.status, '') not in ('queued', 'pending', 'digest') then return NEW; end if;
  if public.fn_is_demo_email(NEW.to_email)
     or public.fn_is_demo_phone(NEW.to_phone)
     or (NEW.lead_id is not null and exists (select 1 from public.leads l where l.id = NEW.lead_id and l.is_demo))
     or (NEW.inquiry_id is not null and public.fn_inquiry_is_demo(NEW.inquiry_id))
     or (NEW.quote_id is not null and exists (
           select 1 from public.quotes q
            where q.id = NEW.quote_id
              and (public.fn_inquiry_is_demo(q.inquiry_id)
                   or exists (select 1 from public.leads l where l.id = q.supplier_id and l.is_demo))))
  then
    NEW.status := 'suppressed';
    NEW.last_error := 'captured: a demo recipient or a demo subject (zzzz_notifications_demo_capture). '
                   || 'Recorded for the rehearsal, never handed to Resend or Twilio.';
  end if;
  return NEW;
exception when others then
  -- Fail closed, the same discipline as zzz_notifications_demo_guard: an unreadable row is held.
  NEW.status := 'held';
  NEW.last_error := 'HELD by zzzz_notifications_demo_capture (guard itself errored: ' || sqlerrm || ')';
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.fn_notifications_digest()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare types jsonb;
begin
  if coalesce(NEW.channel,'email') <> 'email' then return NEW; end if;
  if NEW.status is not null and NEW.status not in ('queued','pending') then return NEW; end if;
  if coalesce(NEW.to_role,'') not in ('admin','founder','owner') then return NEW; end if;
  -- What the producer marked urgent always goes at once. Nothing else is inferred: only a type the policy
  -- lists BY NAME is folded into the brief.
  NEW.severity := public.fn_notification_severity(NEW.severity, NEW.type);
  if NEW.severity in ('high', 'critical') then return NEW; end if;
  select value into types from public.decision_policy where key='alert_digest_types';
  if types is not null and types ? coalesce(NEW.type,'') then
    NEW.status := 'digest';
  end if;
  return NEW;
exception when others then
  return NEW;  -- a classifier error must never block a notification insert
end $function$


CREATE OR REPLACE FUNCTION public.fn_notifications_founder_mail_policy()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_admin text; v_phone text; v_kind text; v_allowed boolean; v_level text;
begin
  if coalesce(NEW.channel, 'email') not in ('email', 'whatsapp') then return NEW; end if;
  -- a format guard on OUR OWN fixture addresses (the reserved .invalid domain), not a reading of meaning
  if coalesce(NEW.to_email, '') ~* '@example[.]invalid$' then return NEW; end if;

  select lower(nullif(split_part(coalesce(value, ''), ',', 1), '')) into v_admin from public.app_secrets where key = 'admin_emails';
  select regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g') into v_phone from public.app_secrets where key = 'admin_mfa_phone';
  if not (coalesce(NEW.to_role, '') in ('founder', 'admin', 'owner')
          or (NEW.to_email is not null and lower(NEW.to_email) = coalesce(v_admin, 'management@quotesdone.com'))
          or (NEW.to_phone is not null and coalesce(v_phone, '') <> ''
              and regexp_replace(NEW.to_phone, '[^0-9]', '', 'g') = v_phone)) then
    return NEW;
  end if;

  v_kind := coalesce(nullif(btrim(NEW.kind), ''), nullif(btrim(NEW.type), ''), 'unregistered');

  -- THE FIXTURE FENCE (13 Oct 2026): a walk's registration is not a record anyone keeps. Dropped, never routed.
  if v_kind = 'supplier_registered' and NEW.lead_id is not null and exists (
       select 1 from public.leads l
        where l.id = NEW.lead_id
          and (public.fn_seat_clock_lead_is_fixture(l)
               or exists (select 1 from unnest(coalesce(l.tags, '{}'::text[])) t where t like 'qd\_run:%'))) then
    return null;
  end if;

  select allowed_to_email into v_allowed from public.founder_mail_policy where kind = v_kind;
  if coalesce(v_allowed, false) then
    NEW.kind := v_kind;
    return NEW;
  end if;

  -- The routed task's level is what the producer STATED; unstated is filed at the normal level.
  NEW.severity := public.fn_notification_severity(NEW.severity, NEW.type);
  v_level := coalesce(NEW.severity, case when NEW.type = 'founder_alert' then 'high' end, 'warn');
  begin
    perform public.fn_founder_mail_route(v_kind, NEW.subject, NEW.body, v_level);
  exception when others then
    insert into public.founder_alerts (level, event, detail, channel)
    values ('high', 'founder_mail:route_failed', left('kind ' || v_kind || ' / ' || coalesce(NEW.subject, '') || ' — ' || sqlerrm, 1000), 'os');
  end;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_notifications_never_reach_a_sanctioned_party()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v bigint;
begin
  if new.lead_id is not null and public.fn_is_sanctioned_lead(new.lead_id) then
    v := new.lead_id;
  elsif coalesce(btrim(new.to_email), '') <> '' then
    select b.lead_id into v from public.sanctions_ban b
      where b.account_email = lower(btrim(new.to_email)) or b.contact_email = lower(btrim(new.to_email))
      limit 1;
  end if;
  if v is not null then
    raise exception 'SANCTIONED_PARTY_BLOCKED: nothing is sent to lead #%, which carries a confirmed sanctions ban (notification type %).', v, coalesce(new.type, '(none)')
      using errcode = '42501';
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_notifications_no_test_mail_to_the_founder()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_hit text;
begin
  select a into v_hit
    from unnest(array[NEW.to_email] || coalesce(NEW.cc_emails, '{}'::text[])) a
   where public.fn_is_founder_own_inbox(a)
   limit 1;
  if v_hit is not null then
    raise exception 'no_test_mail_to_the_founder: a % (kind %) may not be addressed to the founder''s own inbox %; '
      'founder instruction of 27 Oct 2026, "stop doing tests on my email". GlockApps seeds decide deliverability '
      '(ledger 1312, 1344).', NEW.type, coalesce(NEW.kind, '-'), v_hit
      using errcode = 'check_violation';
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.fn_notifications_promotional_consent_gate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.status in ('queued', 'pending') and public.fn_notification_is_promotional(new.type)
     and not public.fn_promotional_consent(new.to_email, new.to_phone) then
    new.status := 'suppressed';
    new.last_error := 'no promotional consent: the recipient has not opted in to offers and news (or withdrew)';
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_notifications_release_held(p_limit integer DEFAULT 1000)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_on boolean; v_queued int := 0; v_suppressed int := 0; v_other int := 0;
begin
  select coalesce((d.value #>> '{}')::boolean, false) into v_on
    from public.decision_policy d where d.key = 'demo_rehearsal_active';
  if coalesce(v_on, false) then
    raise exception 'fn_notifications_release_held refuses while decision_policy.demo_rehearsal_active is true: tear the rehearsal down and set it false first';
  end if;

  with picked as (
    select n.id from public.notifications n
     where n.status = 'held'
       and starts_with(coalesce(n.last_error, ''), 'HELD by zzz_notifications_demo_guard')
     order by n.id
     limit greatest(coalesce(p_limit, 0), 0)
     for update skip locked
  ), released as (
    update public.notifications n
       set status = 'queued',
           last_error = left('released by fn_notifications_release_held at ' || now()::text
                             || '; was: ' || coalesce(n.last_error, ''), 500)
      from picked where n.id = picked.id
    returning n.status   -- the stored status, after zzzz_notifications_demo_capture has judged it
  )
  select count(*) filter (where status = 'queued'),
         count(*) filter (where status = 'suppressed'),
         count(*) filter (where status not in ('queued', 'suppressed'))
    into v_queued, v_suppressed, v_other
    from released;

  return jsonb_build_object('released_to_queue', v_queued, 'captured_as_demo', v_suppressed, 'other', v_other);
end $function$


CREATE OR REPLACE FUNCTION public.fn_notifications_sender_of_record()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  NEW.sender := coalesce(nullif(btrim(NEW.sender), ''), 'customer_support');
  NEW.requested_by := coalesce(nullif(btrim(NEW.requested_by), ''), public.fn_channel_requester(NEW.type, NEW.kind));
  if NEW.requested_by <> 'platform'
     and not exists (select 1 from public.org_role r where r.role_id = NEW.requested_by and r.status = 'active') then
    raise exception 'notifications.requested_by % is not an active seat: a delivery request must name the seat that asked (customer_support sends it)', NEW.requested_by
      using errcode = 'check_violation';
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.fn_notifications_speak_the_recipients_language()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_all text; v_ar boolean; v_latin boolean; c public.notification_copy; v_ref text; v_inq text;
        v_name text; v_sup_ar boolean;
begin
  if coalesce(new.to_role, '') not in ('customer', 'supplier') then return new; end if;
  -- 28 Sep 2026 (founder): a supplier is always written in English, whatever the caller set; a customer is
  -- written in the language they chose for the inquiry the message is about.
  if new.to_role = 'supplier' then
    new.lang := 'en';
  elsif new.inquiry_id is not null then
    v_inq := public.fn_inquiry_locale(new.inquiry_id);
    if v_inq is not null then new.lang := v_inq; end if;
  end if;
  if new.lang is null or new.lang not in ('en', 'ar') then
    new.lang := coalesce(public.fn_registered_locale(new.to_role, null, new.lead_id, new.to_email), 'en');
  end if;
  v_all := coalesce(new.subject, '') || ' ' || coalesce(new.body, '');
  v_ar := v_all ~ '[؀-ۿ]';
  -- coalesce: fn_language_mismatch answers null for pure Arabic, and a null here would make the
  -- pure-Arabic-to-an-English-recipient case below evaluate to null and never be corrected.
  v_latin := coalesce(public.fn_language_mismatch('ar', v_all) like 'English inside Arabic%', false)
             or (not v_ar and v_all ~ '[A-Za-z]{2,}');
  -- A supplier gets no Arabic at all, not even an Arabic half of a bilingual body (28 Sep 2026). The
  -- supplier's own company name is a name, not a language: an English invitation to a company registered
  -- under an Arabic name is English and is left alone (the name is removed before the test, nothing else).
  if new.to_role = 'supplier' and v_ar then
    select nullif(btrim(l.company_name), '') into v_name from public.leads l where l.id = new.lead_id;
    v_sup_ar := case when v_name is null then v_all else replace(v_all, v_name, '') end ~ '[؀-ۿ]';
  end if;
  if (new.lang = 'ar' and not v_ar) or (new.lang = 'en' and v_ar and not v_latin)
     or coalesce(v_sup_ar, false) then
    select * into c from public.notification_copy where type = new.type;
    if not found then select * into c from public.notification_copy where type = '*'; end if;
    if found then
      -- 21 Sep 2026: the reference is the job number (inquiries.rfq_no), the same one both portals print.
      v_ref := case when new.inquiry_id is not null
                    then 'QD-' || public.fn_job_no(new.inquiry_id) end;
      new.subject := case when new.lang = 'ar' then c.subject_ar else c.subject_en end;
      new.body := replace(case when new.lang = 'ar' then c.body_ar else c.body_en end,
                          ' {ref}', coalesce(' ' || v_ref, ''));
      new.html := null;   -- a pre-rendered html copy would still carry the old language
    end if;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_notifications_supplier_invite_is_whole()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare l public.leads;
begin
  if coalesce(new.type, '') <> 'supplier_invite' then return new; end if;
  -- 28 Oct 2026: the approved invitation carries no link (#1614). An empty body, or one with a placeholder the
  -- composer never filled, is refused instead.
  if btrim(coalesce(new.body, '')) = '' then
    raise exception 'SUPPLIER_INVITE_REFUSED: the invitation to % has no body', new.to_email using errcode = 'check_violation';
  end if;
  if position('{{' in coalesce(new.body, '')) > 0 then
    raise exception 'SUPPLIER_INVITE_REFUSED: the invitation to % still carries an unfilled placeholder', new.to_email using errcode = 'check_violation';
  end if;
  -- The link was never the opt-out; the reply-"stop" line is (m365_lane.ts STOP_LINE, the approved body's last line).
  -- A body without it is refused, so the guard still asks for the one thing an unsolicited invitation must carry.
  if coalesce(new.body, '') !~* 'reply[[:space:]]+["“”'']?stop' then
    raise exception 'SUPPLIER_INVITE_REFUSED: the invitation to % has no reply-"stop" opt-out line', new.to_email using errcode = 'check_violation';
  end if;
  if coalesce(new.lang, 'en') = 'ar' and coalesce(new.body, '') !~ '[؀-ۿ]' then
    raise exception 'SUPPLIER_INVITE_REFUSED: an Arabic invitation to % has no Arabic in it', new.to_email using errcode = 'check_violation';
  end if;
  if public.fn_is_demo_email(new.to_email) then return new; end if;   -- the test path
  if new.lead_id is null then
    raise exception 'SUPPLIER_INVITE_REFUSED: an invitation to % names no lead', new.to_email using errcode = 'check_violation';
  end if;
  select * into l from public.leads where id = new.lead_id;
  if not found or lower(btrim(coalesce(l.email, ''))) <> lower(btrim(coalesce(new.to_email, '')))
     or not public.fn_supplier_invite_eligible(l) then
    raise exception 'SUPPLIER_INVITE_REFUSED: lead #% is not eligible for an invitation (demo, banned, screened, closed, already invited, unsendable, or the address is not the lead''s)', new.lead_id
      using errcode = 'check_violation';
  end if;
  return new;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_notifications_supplier_is_english()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if tg_op = 'UPDATE'
     and old.lang is not distinct from new.lang and old.subject is not distinct from new.subject
     and old.body is not distinct from new.body and old.to_role is not distinct from new.to_role then
    return new;
  end if;
  if coalesce(new.to_role, '') = 'supplier' and coalesce(new.lang, 'en') <> 'en' then
    raise exception 'notifications_supplier_is_english: a supplier is always written in English (notification %, lang %)',
      new.id, new.lang using errcode = '23514';
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_notifications_supplier_notice_follows_the_accepted_agreement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_route jsonb; v_to text;
begin
  if coalesce(new.to_role, '') <> 'supplier' or coalesce(new.channel, '') not in ('whatsapp', 'sms')
     or coalesce(new.status, 'queued') not in ('queued', 'skipped')
     or not exists (select 1 from public.decision_policy p, jsonb_array_elements_text(p.value) t
                     where p.key = 'supplier_formal_notice_types' and t = new.type) then
    return new;
  end if;
  v_route := public.fn_supplier_notice_route(new.lead_id, new.to_email) -> new.channel;
  v_to := v_route->>'to';
  if v_to is not null then
    new.to_phone := v_to; new.status := 'queued'; new.last_error := null;
  else
    new.status := 'skipped';
    new.last_error := 'not sent on ' || new.channel || ': ' || coalesce(v_route->>'reason', 'no agreed number')
                      || '; email and the portal carry this notice (Supplier Agreement clause 21)';
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_notifications_whatsapp_goes_to_a_confirmed_number()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_dest text; v_opt text;
begin
  if coalesce(new.channel, '') <> 'whatsapp' or coalesce(new.to_role, '') not in ('customer', 'supplier') then return new; end if;
  v_dest := public.fn_whatsapp_destination(new.to_role, null, new.lead_id, new.to_email);
  if v_dest is not null then new.to_phone := v_dest; return new; end if;
  if new.to_role = 'customer' then
    select c.whatsapp_opt into v_opt from public.customers c where lower(c.email) = lower(btrim(coalesce(new.to_email, ''))) limit 1;
  else
    select l.whatsapp_opt into v_opt from public.leads l where l.id = new.lead_id or (new.lead_id is null and lower(l.claimed_by) = lower(btrim(coalesce(new.to_email, '')))) order by l.id limit 1;
  end if;
  new.status := 'skipped';
  new.last_error := case when v_opt = 'none'
    then 'not sent on WhatsApp: the recipient said they do not use WhatsApp; email or SMS carries this message'
    else 'not sent on WhatsApp: no confirmed WhatsApp number on file (an unverified number is never used)' end;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_notify_founder(p_event text, p_detail text, p_level text DEFAULT 'high'::text, p_kind text DEFAULT NULL::text, p_dedupe_key text DEFAULT NULL::text, p_owner_agent text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_email text; v_phone text; v_kind text; v_level text; v_allowed boolean; v_route jsonb; v_sev text;
begin
  v_level := coalesce(nullif(btrim(p_level), ''), 'high');
  v_kind  := coalesce(nullif(btrim(p_kind), ''), 'unregistered');
  -- p_level is the producer's own closed vocabulary; this maps it onto notifications.severity by exact value.
  v_sev := case lower(v_level) when 'critical' then 'critical' when 'urgent' then 'critical' when 'danger' then 'critical'
                               when 'high' then 'high' when 'error' then 'high' when 'info' then 'info' when 'low' then 'info'
                               when 'warn' then 'warn' when 'warning' then 'warn' else 'warn' end;
  select allowed_to_email into v_allowed from public.founder_mail_policy where kind = v_kind;

  if not coalesce(v_allowed, false) then
    v_route := public.fn_founder_mail_route(v_kind, p_event, p_detail, v_level, p_owner_agent);
    insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
    values (v_level, p_event,
            coalesce(p_detail, '') || E'\n\n-> routed to ' || coalesce(v_route ->> 'owner', v_route ->> 'dept')
              || ' as org_task #' || (v_route ->> 'task_id') || ' (founder_mail_policy: ' || v_kind || ')',
            'routed', p_dedupe_key);
    return v_route || jsonb_build_object('emailed', false);
  end if;

  if p_dedupe_key is not null and exists (
       select 1 from public.founder_alerts f
        where f.dedupe_key = p_dedupe_key and f.channel in ('email', 'whatsapp')
          and f.created_at > now() - interval '24 hours') then
    insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
    values (v_level, p_event, p_detail, 'deduped', p_dedupe_key);
    return jsonb_build_object('mode', 'email', 'emailed', false, 'deduped', true, 'kind', v_kind);
  end if;

  select nullif(split_part(coalesce(value, ''), ',', 1), '') into v_email from public.app_secrets where key = 'admin_emails';
  v_email := coalesce(v_email, 'management@quotesdone.com');
  select nullif(btrim(value), '') into v_phone from public.app_secrets where key = 'admin_mfa_phone';

  insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
  values (v_level, p_event, p_detail, 'email', p_dedupe_key);

  insert into public.notifications (type, kind, to_email, to_role, subject, body, status, channel, severity)
  values ('founder_alert', v_kind, v_email, 'founder', '[Attention] ' || p_event, p_detail, 'queued', 'email', v_sev);

  if v_phone is not null and lower(v_level) in ('critical', 'urgent', 'high', 'danger') then
    insert into public.notifications (type, kind, to_phone, to_role, subject, body, status, channel, severity)
    values ('founder_alert', v_kind, v_phone, 'founder', p_event,
            'QuotesDone [' || v_level || ']: ' || p_event
              || coalesce(E'\n' || nullif(btrim(p_detail), ''), ''), 'queued', 'whatsapp', v_sev);
  end if;
  return jsonb_build_object('mode', 'email', 'emailed', true, 'kind', v_kind, 'severity', v_sev);
end $function$


CREATE OR REPLACE FUNCTION public.fn_notify_supplier(p_transaction uuid, p_actor text DEFAULT 'customer'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t record; st jsonb; sup record; cust_email text; v_window int; v_final_at timestamptz; v_amt numeric; v_req bigint;
begin
  st := public.fn_refund_state(p_transaction);
  if st ? 'error' then return st; end if;
  if (st->>'can_notify') <> 'true' then
    return jsonb_build_object('ok', false, 'error', 'not_available', 'state', st->>'state', 'notify_available_at', st->>'notify_available_at');
  end if;
  select * into t from public.transactions where id = p_transaction;
  select company_name, coalesce(claimed_by, email) as email into sup from public.leads where id = t.supplier_id;
  select email into cust_email from public.customers where id = t.customer_id;
  v_window   := coalesce((st->>'refund_window_working_days')::int, 5);
  v_final_at := (st->>'founder_call_due_at')::timestamptz;
  v_amt      := round(coalesce(t.total_charged, t.reveal_fee, 0), 2);

  -- The customer's own formal notice, in the sales engineer's voice, delivered by support. It does
  -- NOT move the ladder: the window is fixed from payment (founder, 6 Sep 2026).
  v_req := public.fn_sales_engineer_writes('reveal_no_response_notice', 'supplier', sup.email, t.supplier_id, null, t.inquiry_id, t.quote_id,
    'Awaiting your response — QuotesDone reveal #' || left(t.id::text, 8),
    'Hello,' || E'\n\n'
      || 'A customer paid to reveal your contact details on QuotesDone on ' || to_char(t.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY')
      || ' and has not yet heard from you. The customer is copied on this email so you can simply reply to all and pick it up here.' || E'\n\n'
      || 'Under the Supplier Agreement you must respond within ' || v_window || ' working days of the reveal, that is by '
      || to_char(v_final_at at time zone 'Asia/Dubai', 'DD Mon YYYY') || '. If we have not seen a response by then, our chief executive decides the case and the customer is refunded everything they paid (AED '
      || v_amt || '). Under the supplier terms that amount is then recovered from your account, with an administrative fee of AED 250 and interest at 9% per annum until it is settled, and matching is paused until it is paid.' || E'\n\n'
      || 'If you have already been in touch with this customer, reply here and we will close this off.',
    'بانتظار ردّكم — QuotesDone',
    'سدّد أحد العملاء رسوم الكشف عن بيانات التواصل معكم ولم يتلقَّ ردًّا بعد، والعميل مُدرَج في نسخة هذه الرسالة. ويتعيّن الرد خلال ' || v_window
      || ' أيام عمل من تاريخ الكشف، وإلا فسيُردّ إلى العميل كامل ما دفعه (' || v_amt || ' درهم)، ويُسترد المبلغ من حسابكم مع رسوم إدارية قدرها 250 درهمًا وفائدة 9% سنويًا.',
    array_remove(array[cust_email], null), 'customer_notice:' || t.id, null,
    jsonb_build_object('step', 'customer_notice', 'transaction_id', t.id));

  update public.transactions
     set customer_notified_at = now(), refund_deadline = coalesce(refund_deadline, v_final_at)
   where id = p_transaction;

  return jsonb_build_object('ok', true, 'notified_at', now(), 'recipients', jsonb_build_array(sup.email, cust_email),
                            'founder_call_due_at', v_final_at, 'delivery_request', v_req,
                            'state', public.fn_refund_state(p_transaction));
end $function$


CREATE OR REPLACE FUNCTION public.fn_open_remediation(p_agent_key text, p_failure_class text, p_competency text, p_detail jsonb DEFAULT '{}'::jsonb)
 RETURNS bigint
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  insert into agent_remediation (agent_key, failure_class, competency, detail, status, blocks_autonomy)
  values (p_agent_key, p_failure_class, p_competency, coalesce(p_detail,'{}'::jsonb), 'open',
          -- blocks_autonomy defaults true, but a KPI-miss remediation is a COACHING signal (it opens a
          -- task + assigns practice), NOT grounds to freeze the agent from all autonomous action.
          -- Blocking autonomy on a routine KPI-review flag freezes working agents wholesale — the first
          -- weekly review opened 30 such remediations (including cfo), and the autonomy guard then
          -- correctly refused those agents' actions, stalling the approval/dispatch path. Serious
          -- classes (security incidents, money, proven-harmful action) still block by default.
          p_failure_class not in ('kpi_miss'))
  returning id;
$function$


CREATE OR REPLACE FUNCTION public.fn_ops_authority_check(p_dept_key text, p_action_class text, p_amount_aed numeric DEFAULT NULL::numeric, p_risk text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare v_prod text; v_thresh numeric; v_map record; v_gate record; v_tier text; v_reason text;
begin
  select max_tier, threshold_aed into v_prod, v_thresh
    from public.org_authority where dept_key = p_dept_key and action_class = p_action_class;

  select * into v_map from public.action_class_gate where action_class = p_action_class;

  select * into v_gate from ops_kb_stage.hard_gates
   where raw->>'action_class' = coalesce(v_map.gate_action_class, p_action_class) limit 1;

  v_tier := coalesce(v_prod, 'gated');
  v_reason := case when v_prod is null
                   then 'no org_authority row for this department and action class - defaulting to gated'
                   else 'org_authority.max_tier' end;

  -- DECLARED GATES WIN. An action class nobody has reviewed cannot be autonomous. This is the rule
  -- that closes 7.1: previously an autonomous org_authority row with no matching gate sailed through,
  -- which is exactly how refund_within_window, content_publish, code_selfheal and role_define ran
  -- outside the gates that name them.
  if v_map.action_class is null and v_tier <> 'gated' then
    v_tier := 'gated';
    v_reason := 'action class "' || p_action_class || '" has no row in action_class_gate. Unreviewed is not unrestricted: '
             || 'map it to a hard gate, or to NULL with a stated rationale, before it can act on its own.';
  end if;

  if v_gate.record_id is not null and coalesce(v_gate.raw->>'default_tier','gated') = 'gated' and v_tier <> 'gated' then
    if v_thresh is not null and p_amount_aed is not null and p_amount_aed <= v_thresh then
      v_reason := format('hard gate "%s" applies but %s AED is within the delegated threshold of %s AED',
                         v_gate.title, p_amount_aed, v_thresh);
    else
      v_tier := 'gated';
      v_reason := 'hard gate "' || v_gate.title || '" overrides org_authority (a hard gate may only tighten, never widen)'
               || case when v_thresh is not null and p_amount_aed is null
                       then '; a delegated threshold of ' || v_thresh || ' AED exists but no amount was stated'
                       else '' end;
    end if;
  end if;

  if v_thresh is not null and p_amount_aed is not null and p_amount_aed > v_thresh then
    v_tier := 'gated';
    v_reason := format('amount %s AED exceeds the department threshold of %s AED', p_amount_aed, v_thresh);
  end if;

  if p_risk = 'critical' and v_tier = 'autonomous' then
    v_tier := 'gated';
    v_reason := 'risk_level=critical is never executed autonomously';
  end if;

  return jsonb_build_object(
    'department', p_dept_key, 'action_class', p_action_class,
    'effective_tier', v_tier,
    'may_act_autonomously', (v_tier = 'autonomous'),
    'requires_approval', (v_tier = 'gated'),
    'reviewed', (v_map.action_class is not null),
    'hard_gate', case when v_gate.record_id is null then null else jsonb_build_object(
        'title', v_gate.title, 'approval_role', v_gate.raw->>'approval_role',
        'threshold', v_gate.raw->>'threshold', 'rollback', v_gate.raw->>'rollback') end,
    'production_tier', v_prod, 'threshold_aed', v_thresh, 'reason', v_reason,
    'source', 'org_authority + action_class_gate + ops_kb_stage.hard_gates (deterministic, no model call)');
end $function$


CREATE OR REPLACE FUNCTION public.fn_ops_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  active_rfqs int; rfqs_today int; done_today int; ttfq numeric; qpr numeric;
  accept_rate numeric; conv numeric;
  rev_today numeric; rev_month numeric; pending_fees numeric; outstanding_inv int; cash_recv numeric;
  ai_conf numeric; waiting int; onboard_q int; disputes int; escalations int; held int; with_ceo int;
  uptime numeric; queue_size int; failed int; last_backup timestamptz; api_lat numeric;
  health jsonb;
  v_dc uuid[]; v_dl bigint[]; v_di uuid[];
begin
  -- DEMO: the three id sets every business count below leaves out.
  select coalesce(array_agg(id), '{}') into v_dc from customers where is_demo;
  select coalesce(array_agg(id), '{}') into v_dl from leads where is_demo;
  select coalesce(array_agg(id), '{}') into v_di from inquiries where public.fn_inquiry_is_demo(id);

  -- MARKETPLACE
  select count(*) into active_rfqs from inquiries where status not in ('completed','accepted','closed','cancelled') and (id = any (v_di)) is not true;
  select count(*) into rfqs_today from inquiries where created_at::date=current_date and (id = any (v_di)) is not true;
  select count(*) into done_today from inquiries where ((completed_at::date=current_date) or (status in ('completed','accepted') and stage_changed_at::date=current_date)) and (id = any (v_di)) is not true;
  select round(avg(extract(epoch from (fq - ic))/3600.0),1) into ttfq from (
    select i.created_at ic, min(q.created_at) fq from inquiries i join quotes q on q.inquiry_id=i.id
    where i.created_at>=now()-interval '30 days' and (i.id = any (v_di)) is not true and (q.supplier_id = any (v_dl)) is not true
    group by i.id) z where fq is not null;
  select round(avg(qc),1) into qpr from (select count(*) qc from quotes q join inquiries i on i.id=q.inquiry_id
    where i.created_at>=now()-interval '30 days' and (i.id = any (v_di)) is not true and (q.supplier_id = any (v_dl)) is not true
    group by q.inquiry_id) z;
  select round(avg(nullif(rv_response_rate,0)) ,1) into accept_rate from leads where coalesce(rv_reveals,0)>0 and (id = any (v_dl)) is not true;
  select round(100.0*count(distinct t.inquiry_id)/nullif(count(distinct i.id),0),1) into conv
    from inquiries i left join transactions t on t.inquiry_id=i.id and (t.supplier_id = any (v_dl)) is not true
   where i.created_at>=now()-interval '30 days' and (i.id = any (v_di)) is not true;

  -- REVENUE
  select coalesce(sum(reveal_fee),0) into rev_today from transactions where revealed_at::date=current_date and coalesce(refund_status,'')<>'approved'
     and (customer_id = any (v_dc)) is not true and (supplier_id = any (v_dl)) is not true and (inquiry_id = any (v_di)) is not true;
  select coalesce(sum(reveal_fee),0) into rev_month from transactions where date_trunc('month',revealed_at)=date_trunc('month',now()) and coalesce(refund_status,'')<>'approved'
     and (customer_id = any (v_dc)) is not true and (supplier_id = any (v_dl)) is not true and (inquiry_id = any (v_di)) is not true;
  begin select coalesce(sum(amount_due),0) into pending_fees from supplier_dues where public.fn_supplier_due_is_owed(status, paid_at) and (supplier_id = any (v_dl)) is not true; exception when others then pending_fees:=0; end;
  begin select count(*) into outstanding_inv from reveal_invoices ri left join transactions t on t.id=ri.transaction_id where coalesce(t.fee_status,'')<>'paid'
     and (t.customer_id = any (v_dc)) is not true and (t.supplier_id = any (v_dl)) is not true and (t.inquiry_id = any (v_di)) is not true; exception when others then outstanding_inv:=0; end;
  select coalesce(sum(reveal_fee),0) into cash_recv from transactions where coalesce(fee_status,'')='paid'
     and (customer_id = any (v_dc)) is not true and (supplier_id = any (v_dl)) is not true and (inquiry_id = any (v_di)) is not true;

  -- OPERATIONS
  begin select public.fn_health_index() into health; exception when others then health:=null; end;
  select round(100.0*count(*) filter (where nullif(quality->>'score','')::numeric>=60)/nullif(count(*) filter (where quality is not null),0),1) into ai_conf
    from quotes where created_at>=now()-interval '7 days' and (inquiry_id = any (v_di)) is not true and (supplier_id = any (v_dl)) is not true;
  select count(*) into waiting from inquiries where status in ('clarify','clarifying','awaiting_customer','needs_info') and (id = any (v_di)) is not true;
  select count(*) into onboard_q from leads where approval_status='pending' and (id = any (v_dl)) is not true;
  select count(*) into disputes from transactions where refund_status='requested'
     and (customer_id = any (v_dc)) is not true and (supplier_id = any (v_dl)) is not true and (inquiry_id = any (v_di)) is not true;
  -- REFUNDS ARE THE CEO'S. Open = a refunds row still 'requested'. What reaches the founder is only the
  -- CEO's summary when that refund's latest review cycle escalated, plus severe alerts.
  select count(*), count(*) filter (where rv.outcome = 'escalated') into with_ceo, escalations
    from refunds r
    left join lateral (select x.outcome from refund_ceo_review x where x.refund_id = r.id order by x.cycle desc limit 1) rv on true
   where r.status = 'requested'
     and (r.customer_id = any (v_dc)) is not true and (r.supplier_lead_id = any (v_dl)) is not true and (r.inquiry_id = any (v_di)) is not true;
  escalations := escalations
        + (select count(*) from founder_alerts where public.fn_alert_severe(level) and created_at>=now()-interval '24 hours');
  select count(*) into held from agent_actions a left join agent_action_kind_policy p on p.kind=a.kind
   where a.status in ('pending','needs_review') and coalesce(p.policy,'')<>'founder';

  -- INFRASTRUCTURE
  select round(100.0*count(*) filter (where ok)/nullif(count(*),0),1) into uptime from health_checks where created_at>=now()-interval '24 hours';
  select count(*) into queue_size from notifications where coalesce(status,'')in('queued','pending','');
  begin select count(*) into failed from agent_runs where status='error' and coalesce(finished_at,started_at)>=now()-interval '24 hours'; exception when others then failed:=0; end;
  select max(updated_at) into last_backup from storage.objects where bucket_id='backups' and name like '%/_manifest.json';
  select round(avg(latency_ms),0) into api_lat from health_checks where created_at>=now()-interval '1 hour' and latency_ms is not null;

  return jsonb_build_object(
    'as_of', now(),
    'marketplace', jsonb_build_object('active_rfqs',active_rfqs,'rfqs_today',rfqs_today,'completed_today',done_today,
        'avg_hours_to_first_quote',ttfq,'avg_quotes_per_rfq',qpr,'supplier_acceptance_pct',accept_rate,'conversion_pct',conv),
    'revenue', jsonb_build_object('today_aed',rev_today,'month_aed',rev_month,'pending_fees_aed',pending_fees,
        'outstanding_invoices',outstanding_inv,'cash_received_aed',cash_recv),
    'operations', jsonb_build_object('ai_confidence_pct',ai_conf,'rfqs_waiting_clarification',waiting,
        'onboarding_queue',onboard_q,'disputes',disputes,'escalations',escalations,'refunds_with_ceo',with_ceo,'held_with_roles',held),
    'infrastructure', jsonb_build_object('uptime_pct',uptime,'queue_size',queue_size,'failed_jobs_24h',failed,
        'backup_age_hours', case when last_backup is null then null else round(extract(epoch from (now()-last_backup))/3600.0,1) end,
        'api_latency_ms',api_lat),
    'health_index', coalesce(health->>'index',null));
end $function$


CREATE OR REPLACE FUNCTION public.fn_ops_knowledge_embedding_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- content changed and the writer did not supply a fresh vector: the old vector describes text
  -- that no longer exists, so drop it and let the backfill picker (embedding_gte is null) re-embed.
  if tg_op = 'UPDATE'
     and (new.title is distinct from old.title or new.content is distinct from old.content)
     and new.embedding_gte is not distinct from old.embedding_gte then
    new.embedding_gte := null;
  end if;
  new.embedding_status := case when new.embedding_gte is null then 'pending' else 'embedded' end;
  return new;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_ops_knowledge_match(p_query_embedding vector, p_agent_key text, p_match_count integer DEFAULT 8, p_record_types text[] DEFAULT NULL::text[])
 RETURNS TABLE(record_id text, title text, content text, layer text, record_type text, authority_tier text, dept_key text, role_key text, similarity real)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
 SET "hnsw.iterative_scan" TO 'relaxed_order'
 SET "hnsw.ef_search" TO '200'
AS $function$
declare
  v_key      text;
  v_dept     text;
  v_scope    text[];
  v_modules  text[];
  v_role_ids text[];
begin
  if p_query_embedding is null then return; end if;
  -- resolve exactly as v3 does, so an alias or packaged role resolves to the same identity
  v_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  select a.department into v_dept from public.org_agents a where a.agent_key = v_key;
  if v_dept is null then return; end if;
  v_scope   := public.fn_dept_scope(v_dept);
  v_modules := public.fn_dept_module_scope(v_dept);
  select array_agg(packaged_role_id) into v_role_ids
    from public.org_role_identity where agent_key = v_key;

  return query
    select o.record_id, o.title, o.content, o.layer, o.record_type, o.authority_tier,
           o.dept_key, o.role_key,
           (1 - (o.embedding_gte <=> p_query_embedding))::real as similarity
      from public.ops_knowledge o
     where o.embedding_gte is not null
       and o.runtime_eligible
       and o.supersession_state = 'current'
       and (p_record_types is null or o.record_type = any(p_record_types))
       and (
             o.scope_type in ('company','external_source')
          or (o.scope_type = 'department' and o.dept_key = any(v_scope))
          or (o.scope_type = 'department' and o.module = any(v_modules))
          or (o.role_key = any(coalesce(v_role_ids, '{}')))
       )
     order by o.embedding_gte <=> p_query_embedding
     limit greatest(1, least(coalesce(p_match_count, 8), 20));
end
$function$


CREATE OR REPLACE FUNCTION public.fn_ops_knowledge_search(p_dept text, p_query text, p_limit integer DEFAULT 5)
 RETURNS TABLE(record_id text, title text, content text, record_type text, authority_tier text, implementation_status text, rank real)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare q_or tsquery; words text[]; v_scope text[]; v_modules text[];
begin
  words := array(select w from unnest(regexp_split_to_array(lower(regexp_replace(coalesce(p_query,''),'[^a-z0-9 ]',' ','g')),'\s+')) w where length(w)>2);
  if array_length(words,1) is null then return; end if;
  begin q_or := to_tsquery('english', array_to_string(words,' | ')); exception when others then return; end;
  -- THE SAME SCOPE THE PLAYBOOK BINDER USES. fn_dept_scope reads org_departments.merged_into plus the
  -- declared dept aliases; fn_dept_module_scope the declared module aliases. `dept_key = p_dept` alone
  -- hid every merged-in package from keyword retrieval (people_ops never saw hr; supply never saw
  -- marketplace_expert) while the cosine path and fn_apply_playbook could see them.
  v_scope   := public.fn_dept_scope(p_dept);
  v_modules := public.fn_dept_module_scope(p_dept);
  return query
    select o.record_id, o.title, o.content, o.record_type, o.authority_tier,
           o.implementation_status, ts_rank(o.tsv, q_or) as rank
      from ops_knowledge o
     where (p_dept is null
            or o.dept_key = any(v_scope)
            or o.module = any(v_modules)
            -- company principles and the UAE source registry apply to every department, and a
            -- cross-department workflow that names no single owner belongs to all of them by
            -- definition. Without these three branches 884 of 3,959 records were reachable by
            -- nothing at all — the same defect as the corpus itself, one level down.
            or o.scope_type in ('company','external_source')
            or (o.scope_type = 'workflow' and o.dept_key is null))
       and o.tsv @@ q_or
     order by ts_rank(o.tsv, q_or) desc, o.record_id
     limit greatest(1, least(coalesce(p_limit,5),20));
end $function$


CREATE OR REPLACE FUNCTION public.fn_ops_metrics()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare res jsonb;
begin
  select jsonb_build_object(
    'open_rfqs_no_quotes_7d', (select count(*) from inquiries i where i.created_at < now()-interval '7 days'
        and coalesce(i.status,'') not in ('completed','cancelled','closed')
        and not public.fn_inquiry_is_demo(i.id)
        and not exists (select 1 from quotes q where q.inquiry_id=i.id)),
    'matched_not_quoted', (select count(*) from inquiry_matches m
        where not public.fn_inquiry_is_demo(m.inquiry_id)
          and not exists (select 1 from quotes q where q.inquiry_id=m.inquiry_id and q.supplier_id=m.supplier_id)),
    'avg_first_quote_hours', (select (fn_marketplace_analytics()->>'avg_first_quote_hours')::numeric),
    'response_rate_pct', (select (fn_marketplace_analytics()->>'response_rate_pct')::numeric),
    'pipeline_by_stage', (select coalesce(jsonb_agg(jsonb_build_object('stage',label,'deals',deals,'value',value) order by sort_order),'[]'::jsonb) from crm_pipeline_report),
    'overdue_activities', (select overdue_activities from crm_deal_kpis)
  ) into res;
  return res;
end $function$


CREATE OR REPLACE FUNCTION public.fn_opt_out_types()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select array['supplier_invite', 'supplier_invite_nudge', 'supplier_registration_reminder', 'supplier_rfq_widened_invite']::text[]
$function$


CREATE OR REPLACE FUNCTION public.fn_org_action_executor_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_scope text[];
begin
  if new.kind = 'edge' then
    select c.scope into v_scope
      from public.internal_credential c
     where c.context = 'fn.cos_execute'
       and c.active and c.retired_at is null
     limit 1;

    if v_scope is null then
      raise exception
        'org_action_executor: no live fn.cos_execute credential, so an edge executor target cannot be validated. Refusing the write rather than registering a callee nothing has authorised.'
        using errcode = 'check_violation';
    end if;

    if not (new.target = any (v_scope)) then
      raise exception
        'org_action_executor: edge target % is outside the fn.cos_execute credential scope. cos_execute would POST service-role authority to it. Widen the credential scope deliberately if this executor is intended; do not widen it to make an INSERT succeed.',
        new.target
        using errcode = 'check_violation';
    end if;

  elsif new.kind = 'rpc' then
    if not exists (select 1 from public.org_action_executor_rpc_allowed a where a.target = new.target) then
      raise exception
        'org_action_executor: rpc target % is not in org_action_executor_rpc_allowed. cos_execute runs rpc executors as service-role, so this is a grant of arbitrary database authority. Add it to the allow-list deliberately first.',
        new.target
        using errcode = 'check_violation';
    end if;

  else
    raise exception
      'org_action_executor: unknown kind %. cos_execute only understands edge and rpc, so a row with any other kind is either dead or a mistake. Refusing it rather than storing it.', new.kind
      using errcode = 'check_violation';
  end if;

  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_org_agent_resolve(p_addressee text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(
    (select o.agent_key from public.org_agents o
      where o.agent_key = p_addressee and o.active),
    (select a.agent_key from public.org_agent_alias a
       join public.org_agents o on o.agent_key = a.agent_key and o.active
      where a.alias = p_addressee),
    -- THE TITLE ARM (11 Aug 2026). 30 of the 66 workflow actor_role values are job titles, and
    -- five of them are a second spelling of an employee the alias table already knew by key.
    -- Ordered so a title held by more than one employee resolves to the senior holder rather than
    -- to whichever row the planner returned first.
    (select o.agent_key from public.org_agents o
      where lower(btrim(o.title)) = lower(btrim(p_addressee)) and o.active
      order by case o.seniority
                 when 'executive' then 0 when 'chief' then 1 when 'director' then 2
                 when 'lead'      then 3 when 'manager' then 4 when 'senior' then 5 else 6 end,
               o.agent_key
      limit 1),
    (select o.agent_key from public.org_agents o
      where o.department = p_addressee and o.active
      order by case o.seniority
                 when 'executive' then 0 when 'chief' then 1 when 'director' then 2
                 when 'lead'      then 3 when 'manager' then 4 when 'senior' then 5 else 6 end,
               o.agent_key
      limit 1)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_org_authority_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_reason text := nullif(trim(coalesce(current_setting('app.change_reason', true), '')), '');
  v_widen  boolean;
  v_obj    text := 'org_authority:' || coalesce(new.dept_key, old.dept_key) || '/'
                                    || coalesce(new.action_class, old.action_class);
begin
  if tg_op = 'DELETE' then
    v_widen := false;   -- removing a row removes a permission
  else
    v_widen := public.fn_authority_rank(new.max_tier) > public.fn_authority_rank(coalesce(old.max_tier, 'advisory'))
            or coalesce(new.threshold_aed, 0) > coalesce(old.threshold_aed, 0);
  end if;

  if v_widen and (v_reason is null or length(v_reason) < 12) then
    raise exception
      'org_authority %: raising a department''s tier or money threshold needs a stated reason. '
      'Run `set local app.change_reason = ''why, in a sentence'';` in the same transaction. '
      'Lowering never needs one.', v_obj
      using errcode = 'check_violation';
  end if;

  insert into public.autonomy_control_audit (object, op, direction, old_value, new_value, reason)
  values (v_obj, tg_op,
          case when v_widen then 'widen' else 'tighten' end,
          coalesce(old.max_tier,'') || '/' || coalesce(old.threshold_aed::text,''),
          coalesce(new.max_tier,'') || '/' || coalesce(new.threshold_aed::text,''),
          v_reason);
  return coalesce(new, old);
end $function$


CREATE OR REPLACE FUNCTION public.fn_org_phase_baseline_append_only()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  raise exception
    'org_phase_baseline is append-only: % on the frozen phase % baseline is refused',
    tg_op, coalesce(old.phase, '?')
    using errcode = '23514',
          hint = 'These rows are the founder-approved record of what a phase WAS when it was '
              || 'approved, and four drift checks read them as the fixed point they measure '
              || 'against. To change one, raise a Phase change request: write '
              || 'scripts/sql/pacr_NNN_<what_and_why>.sql which drops trigger '
              || 'a00_org_phase_baseline_append_only, makes the change with every digest '
              || 'RECOMPUTED in place, recreates the trigger in the same transaction, and is '
              || 'appended to scripts/sql/MANIFEST.txt. The dropped trigger in that file is the '
              || 'record that the freeze was deliberately opened.';
end $function$


CREATE OR REPLACE FUNCTION public.fn_org_role_resolve(p_any text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  select coalesce(
    (select r.role_id from public.org_role r where r.role_id = p_any and r.status = 'active'),
    (select a.role_id from public.org_role_alias a
        join public.org_role r on r.role_id = a.role_id and r.status = 'active'
       where a.alias = p_any),
    (select r.role_id from public.org_role r
       where r.runtime_agent_key = p_any and r.status = 'active' limit 1),
    -- last arm: whatever org_agents' own alias table already knew, mapped forward
    (select r.role_id from public.org_agent_alias g
        join public.org_role r on r.runtime_agent_key = g.agent_key and r.status = 'active'
       where g.alias = p_any limit 1)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_org_task_assign(p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r record; v_pick text;
  v_assigned int := 0; v_no_capacity int := 0; v_considered int := 0; v_saturated text;
  v_released int := 0; v_gone int := 0; v_rehomed int := 0;
  v_promote jsonb;
  REVIEW_CLASSES constant text[] := array['review','audit','verify','qa_gate','security_review',
                                          'compliance_check','legal_review','supplier_verify',
                                          'capability_review','self_review'];
begin
  -- A MERGED DEPARTMENT HAS NO COLLEAGUES (5 Sep 2026). Two open tasks were addressed to 'evolution' and
  -- 'knowledge_eng', both merged away on 3 Sep; the picker found nobody, and the row said "every eligible
  -- colleague is at max_open_tasks", which was not the reason. Open work follows the merge to the live
  -- department, and the row says so. The chain is followed so a department merged twice still lands.
  update public.org_tasks t
     set dept_key = m.live_dept, updated_at = now(),
         result = coalesce(t.result,'{}'::jsonb) || jsonb_build_object(
           'rehomed', jsonb_build_object('at', now(), 'by', 'fn_org_task_assign', 'from', t.dept_key, 'to', m.live_dept,
             'reason', 'the department was merged into ' || m.live_dept || ' and has no colleagues; open work follows the merge'))
    from (select d0.dept_key, coalesce(d2.dept_key, d1.dept_key) as live_dept
            from public.org_departments d0
            join public.org_departments d1 on d1.dept_key = d0.merged_into
            left join public.org_departments d2 on d2.dept_key = d1.merged_into and not d1.active
           where not d0.active and d0.merged_into is not null) m
   where m.dept_key = t.dept_key
     and t.status in ('proposed','assigned','in_progress','blocked')
     and exists (select 1 from public.org_departments x where x.dept_key = m.live_dept and x.active);
  get diagnostics v_rehomed = row_count;

  -- a re-homed task (or any open task) with no objective serves the live department's primary active
  -- objective — the same default a05_org_task_fill_ownership applies at insert, which does not fire on
  -- an update of dept_key. org_connectivity_scenarios counts open tasks without one and expects 0.
  update public.org_tasks t
     set objective_id = (select o.id from public.department_objective o
                          where o.active and o.status = 'active' and o.dept_key = t.dept_key
                          order by (coalesce(o.measure_sql, '') <> '') desc, o.sort, o.id
                          limit 1),
         updated_at = now()
   where t.objective_id is null
     and t.status in ('proposed','assigned','in_progress','blocked')
     and exists (select 1 from public.department_objective o
                  where o.active and o.status = 'active' and o.dept_key = t.dept_key);

  -- release unworked work from a head nobody can review, where a colleague exists
  update public.org_tasks t
     set assigned_agent = null, updated_at = now(),
         result = coalesce(t.result,'{}'::jsonb) || jsonb_build_object(
           'released', jsonb_build_object('at', now(), 'by', 'fn_org_task_assign', 'from', t.assigned_agent,
             'reason', 'the department head has no manager, so work it authors cannot be reviewed; '
                    || 'released to a colleague the head can review'))
    from public.org_departments d
   where d.dept_key = t.dept_key
     and t.status in ('assigned','in_progress')
     and t.assigned_agent = d.lead_agent
     and coalesce(t.attempts, 0) = 0
     and not exists (select 1 from public.org_agents h
                      join public.org_agents m on m.agent_key = h.manager_key and m.active
                     where h.agent_key = d.lead_agent)
     and exists (select 1 from public.org_agents b
                  left join public.org_role rb on rb.runtime_agent_key = b.agent_key and rb.status = 'active'
                 where b.active and coalesce(b.available, true) and b.department = d.dept_key
                   and b.agent_key <> d.lead_agent
                   and coalesce(rb.runtime_mode, 'on_demand_specialist') <> 'independent_reviewer')
     and not exists (select 1 from public.workflow_step_run sr
                      join public.workflow_run wr on wr.id = sr.workflow_run_id
                     where wr.workflow_key = 'employee_task' and wr.context->>'task_id' = t.id::text
                       and sr.status = 'running');
  get diagnostics v_released = row_count;

  -- release work held by a colleague who is no longer active or available: fn_workflow_actor_resolve
  -- resolves such an owner to no employee and the promotion is refused (10 open tasks, 5 Sep 2026,
  -- surfaced the moment the promoter stopped swallowing the refusal)
  update public.org_tasks t
     set assigned_agent = null, updated_at = now(),
         result = coalesce(t.result,'{}'::jsonb) || jsonb_build_object(
           'released', jsonb_build_object('at', now(), 'by', 'fn_org_task_assign', 'from', t.assigned_agent,
             'reason', 'the assignee is no longer an active, available colleague; released to be re-homed'))
   where t.status in ('assigned','in_progress')
     and t.assigned_agent is not null
     and not exists (select 1 from public.org_agents a
                      where a.agent_key = t.assigned_agent and a.active and coalesce(a.available, true)
                        and (a.unavailable_until is null or a.unavailable_until < now()));
  get diagnostics v_gone = row_count;
  v_released := v_released + v_gone;

  for r in
    select t.id, t.dept_key, t.action_class
      from public.org_tasks t
     where t.assigned_agent is null
       and t.status in ('assigned','in_progress')
     order by t.priority desc, t.created_at, t.id
     limit greatest(coalesce(p_limit, 200), 1)
  loop
    v_considered := v_considered + 1;
    select a.agent_key into v_pick
      from public.org_agents a
      left join public.agent_reputation p on p.agent_key = a.agent_key
      left join public.org_role rr on rr.runtime_agent_key = a.agent_key and rr.status = 'active'
      join public.org_departments d on d.dept_key = a.department
     where a.active
       and coalesce(a.available, true)
       and (a.unavailable_until is null or a.unavailable_until < now())
       and a.department = r.dept_key
       and (coalesce(rr.runtime_mode, 'on_demand_specialist') <> 'independent_reviewer'
            or coalesce(r.action_class, '') = any (REVIEW_CLASSES))
       -- the picker knows who it must not select: a head nobody can review, while a colleague exists
       and not (a.agent_key = d.lead_agent
                and not exists (select 1 from public.org_agents h
                                 join public.org_agents m on m.agent_key = h.manager_key and m.active
                                where h.agent_key = d.lead_agent)
                and exists (select 1 from public.org_agents b
                             left join public.org_role rb on rb.runtime_agent_key = b.agent_key and rb.status = 'active'
                            where b.active and coalesce(b.available, true) and b.department = d.dept_key
                              and b.agent_key <> d.lead_agent
                              and coalesce(rb.runtime_mode, 'on_demand_specialist') <> 'independent_reviewer'))
       and (select count(*) from public.org_tasks o
             where o.assigned_agent = a.agent_key
               and o.status in ('assigned','in_progress')) < coalesce(a.max_open_tasks, 6)
     order by case when p.tier = 'probation' then 1 else 0 end,
              (select count(*) from public.org_tasks o
                where o.assigned_agent = a.agent_key
                  and o.status in ('assigned','in_progress')),
              a.agent_key
     limit 1;

    if v_pick is not null then
      update public.org_tasks set assigned_agent = v_pick, updated_at = now() where id = r.id;
      v_assigned := v_assigned + 1;
    else
      v_no_capacity := v_no_capacity + 1;
    end if;
  end loop;

  select string_agg(x.dept_key||' '||x.unowned||'/'||x.capacity, ', ' order by x.unowned desc)
    into v_saturated
    from (select t.dept_key, count(*) as unowned,
                 (select coalesce(sum(coalesce(a.max_open_tasks,6)),0) from public.org_agents a
                   where a.active and coalesce(a.available,true) and a.department = t.dept_key) as capacity
            from public.org_tasks t
           where t.assigned_agent is null and t.status in ('assigned','in_progress')
           group by t.dept_key
          having count(*) > 0
           order by count(*) desc
           limit 6) x;

  -- an unowned task carries its reason on the row: every eligible colleague is at max_open_tasks
  update public.org_tasks t
     set result = coalesce(t.result,'{}'::jsonb) || jsonb_build_object(
           'waiting', jsonb_build_object('at', now(), 'by', 'fn_org_task_assign',
             'reason', 'unowned: every eligible colleague in ' || t.dept_key || ' is at max_open_tasks; '
                    || 'it is assigned and promoted onto the spine as capacity frees (hourly)'))
   where t.assigned_agent is null and t.status in ('assigned','in_progress')
     and not (coalesce(t.result,'{}'::jsonb) ? 'waiting');

  begin
    v_promote := public.fn_org_task_promote();
  exception when others then
    v_promote := jsonb_build_object('error', sqlerrm);
  end;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('org_task_assign', now(), now(), 'ok',
          jsonb_build_object('considered', v_considered, 'assigned', v_assigned,
                             'released_from_unreviewable_head', v_released,
                             'left_unowned', v_no_capacity, 'oversubscribed', coalesce(v_saturated,'none'),
                             'promoted_to_spine', v_promote),
          'Assigned '||v_assigned||' of '||v_considered||' unowned open task(s) to the currently '
          ||'least-loaded named colleague in the owning department, spreading within the department, '
          ||'skipping independent reviewers for non-review work and never a head nobody can review ('
          ||v_released||' released from one). '||v_no_capacity||' left unowned '
          ||'only where every eligible colleague was already at max_open_tasks - deliberate: an '
          ||'unowned task is visible, an overloaded one is not. Departments still carrying more open '
          ||'work than they staff (unowned/capacity): '||coalesce(v_saturated,'none')||'. Promoted onto '
          ||'the workflow spine: '||coalesce(v_promote::text,'{}')||'.');

  return jsonb_build_object('considered', v_considered, 'assigned', v_assigned,
                            'rehomed_from_merged_department', v_rehomed,
                            'released_from_unreviewable_head', v_released,
                            'left_unowned', v_no_capacity, 'oversubscribed', coalesce(v_saturated,'none'),
                            'promoted_to_spine', v_promote);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_org_task_autonomy_brake()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb;
begin
  if new.status is distinct from 'in_progress' or old.status = 'in_progress' then
    return new;
  end if;
  if coalesce(new.tier, 'advisory') = 'advisory' then
    return new;   -- WI-001 permits shadow development; advice-only work is not broad autonomy
  end if;
  v := public.fn_autonomy_status();
  if (v ->> 'allowed')::boolean then
    return new;
  end if;
  raise exception
    'org_tasks: task % cannot start at tier %. Broad autonomy is blocked: %. This is WI-001 being '
    'enforced rather than merely declared — clear the blocker, or drop the task to advisory.',
    new.id, new.tier, (v ->> 'blockers')
    using errcode = 'check_violation';
end $function$


CREATE OR REPLACE FUNCTION public.fn_org_task_close_as_fact(p_task_id bigint, p_decided_by text, p_deliverable text, p_basis jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t          record;
  v_deliv    text;
  v_employee text;
  v_review   jsonb;
  v_trace    uuid;
begin
  select o.id, o.dept_key, o.title, o.action_class, o.tier, o.status, o.assigned_agent, o.result
    into t from public.org_tasks o where o.id = p_task_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no such org_task ' || p_task_id);
  end if;
  if t.status = 'done' then
    return jsonb_build_object('ok', false, 'reason', 'org_task ' || p_task_id || ' is already done');
  end if;
  if coalesce(btrim(p_decided_by), '') = '' then
    return jsonb_build_object('ok', false, 'reason', 'a fact close must name who resolved it (p_decided_by)');
  end if;
  v_deliv := btrim(coalesce(p_deliverable, ''));
  if length(v_deliv) < 40 then
    return jsonb_build_object('ok', false, 'reason', 'a fact close needs the resolution in words (>= 40 characters), not a status flip');
  end if;

  -- the employee accountable for the fact: the incident owner when it is an active colleague, else the
  -- task's assignee, else the department (which fn_org_agent_resolve maps to its head)
  select a.agent_key into v_employee
    from public.org_agents a
   where a.active and a.agent_key = coalesce(p_basis->>'owner', '');
  v_employee := coalesce(v_employee, nullif(t.assigned_agent, ''), t.dept_key);

  update public.org_tasks
     set result = coalesce(result, '{}'::jsonb) || jsonb_build_object(
                    'deliverable', left(v_deliv, 20000),
                    'summary',     left(v_deliv, 300),
                    'mode',        'fact_close',
                    'used_llm',    false,
                    'lane',        'fact',
                    'employee',    v_employee,
                    'basis',       coalesce(p_basis, '{}'::jsonb),
                    'at',          now()),
         decided_by  = p_decided_by,
         last_run_at = now(),
         attempts    = coalesce(attempts, 0) + 1,
         updated_at  = now()
   where id = p_task_id;

  v_review := public.fn_task_review(p_task_id);

  insert into public.decision_trace(
      correlation_id, entity_type, entity_id, decision_type,
      proposed_by, decided_by, policy_keys, knowledge_refs, evidence_refs, alternatives,
      assumptions, risk, confidence, authority_result,
      decision, outcome_status, agent_key, department_id, task_class,
      knowledge_versions, source_freshness, tools_requested, tools_executed, tool_result_refs,
      uncertainty, escalation_decision, proposed_action, expected_outcome,
      model, provider, input_tokens, output_tokens, estimated_cost_aed, final_status, sealed_at)
  values (
      gen_random_uuid(), 'org_task', p_task_id::text, 'fact_close',
      v_employee, p_decided_by, array['org_task_lane','fact_close']::text[],
      '[]'::jsonb,
      jsonb_build_array(jsonb_build_object('org_task_id', p_task_id, 'dept_key', t.dept_key,
                                           'title', t.title, 'action_class', t.action_class,
                                           'basis', coalesce(p_basis, '{}'::jsonb), 'review', v_review)),
      '[]'::jsonb,
      jsonb_build_array('the task closes because the fact it was raised for has been recorded as resolved by a named resolver'),
      jsonb_build_object('level', 'low', 'note', 'closes a task on a recorded fact; moves no money, sends nothing, approves nobody'),
      1.0,
      jsonb_build_object('mode', 'fact', 'tier', t.tier, 'paid_provider', 'not used'),
      jsonb_build_object('determination', left(v_deliv, 8000), 'basis', 'recorded resolution; no model call'),
      'closed', v_employee, t.dept_key, 'org_task',
      '{}'::jsonb, jsonb_build_object('os_incidents', 'live at close time'), '{}'::text[], '{}'::text[], '[]'::jsonb,
      'none: the close restates a recorded fact', 'not_escalated',
      'close the org_task on the recorded resolution', 'the mirroring employee_task run, if any, closes with it',
      'none', 'deterministic', 0, 0, 0, 'auto_done', now())
  returning id into v_trace;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values (v_employee, now(), now(), 'ok',
          jsonb_build_object('org_task_id', p_task_id, 'lane', 'fact', 'decision_trace_id', v_trace,
                             'decided_by', p_decided_by, 'review_outcome', v_review->>'outcome'),
          left('org_task ' || p_task_id || ' closed on a recorded fact by ' || p_decided_by || ': ' || v_deliv, 500));

  update public.org_tasks
     set status  = 'done',
         updated_at = now(),
         result  = coalesce(result, '{}'::jsonb) || jsonb_build_object(
                     'review', v_review, 'decision_trace_id', v_trace, 'disposition', 'fact_close')
   where id = p_task_id;

  return jsonb_build_object('ok', true, 'org_task_id', p_task_id, 'employee', v_employee,
                            'decision_trace_id', v_trace, 'review_outcome', v_review->>'outcome');
end
$function$


CREATE OR REPLACE FUNCTION public.fn_org_task_close_needs_an_act()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_has_act boolean;
begin
  if new.status <> 'done' or old.status = 'done' then
    return new;
  end if;
  if not coalesce(new.requires_evidence, false) then
    return new;
  end if;

  -- An act is any ONE of: a recorded decision, a fallback rung taken, an escalation raised, or a
  -- named change with evidence. Gathering facts is not an act, which is the whole point.
  v_has_act :=
       coalesce(new.result ? 'decision', false)
    or coalesce(new.result ? 'fallback_rung', false)
    or coalesce(new.result ? 'escalated_to', false)
    or coalesce(new.result ? 'change_made', false)
    or coalesce(jsonb_array_length(coalesce(new.result->'events','[]'::jsonb)) > 0, false);

  if not v_has_act then
    raise exception using
      errcode = 'check_violation',
      message = format('Task %s cannot be closed: its result records facts but no act.', new.id),
      detail  = 'A close must carry one of: result->decision, result->fallback_rung, result->escalated_to, '
             || 'result->change_made, or at least one entry in result->events.',
      hint    = 'If nothing could be done, set status to blocked or escalated and say why. '
             || 'Marking done without an act is how 113 KPI tasks closed while every KPI stayed missed.';
  end if;

  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_org_task_consume_tick(p_limit integer DEFAULT 4, p_task_id bigint DEFAULT NULL::bigint, p_dry_run boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r          record;
  v_q        text;
  v_pg       jsonb;
  v_best     record;
  v_deliv    text;
  v_reason   text;
  v_handler  text;
  v_basis    jsonb;
  v_close    jsonb;
  v_gap_id   bigint;
  v_gap_status text;
  v_exp      record;
  v_inq      uuid;
  v_inq_seen boolean;
  v_matches  int;
  v_vendor   text;
  v_amount   numeric;
  v_ccy      text;
  v_charged  date;
  v_back     interval;
  v_done     jsonb := '[]'::jsonb;
  v_left     jsonb := '[]'::jsonb;
  v_items    jsonb := '[]'::jsonb;
  v_settled  jsonb;
  v_seen     int := 0;
  v_refused  int := 0;
  v_raised   int := 0;
  v_t0       timestamptz := clock_timestamp();
  v_faq_id   bigint;
  v_faq_q    text;
  v_faq_a    text;
  v_lead     record;
  v_rev      record;
  v_agg      record;
  v_lic      text;
  v_decision text;
  v_tracked  boolean;
  v_read     record;
begin
  for r in
    select o.*
      from public.org_tasks o
     where o.status = 'assigned'
       and (p_task_id is null or o.id = p_task_id)
       and (p_task_id is not null
            or o.last_run_at is null
            or o.last_run_at < now() - make_interval(mins => (15 * power(2, least(o.attempts, 6)))::int)
            -- A BACK-OFF EARNED UNDER OTHER HANDLERS DOES NOT BIND THESE. Measured on apply,
            -- 21 Sep 2026: the first v2 tick scanned 0 of 8 assigned rows, because every one was
            -- inside a 4h/16h window earned from a v1 "not_yet" -- a verdict v2 no longer gives.
            -- A row whose last verdict came from an older consumer version is retried at once.
            or coalesce(o.result->'consumer'->>'version', '') <> 'v3')
     order by (o.last_run_at is null) desc, o.priority desc, o.id
     limit greatest(1, least(coalesce(p_limit, 4), 25))
     -- TWO TICKS MUST NOT PICK THE SAME ROW. The 15-minute cron can double-fire or retry, and a
     -- p_task_id replay can be issued by hand while a batch tick is in flight. Without this, both
     -- callers select the row under READ COMMITTED; the loser's fn_org_task_close_as_fact refuses
     -- (it guards on status='done') but its earlier result-merge update still lands on top of the
     -- winner's. skip locked rather than for update: a row another tick is already working is not
     -- this tick's work, and waiting on it would spend the budget queueing.
       for update of o skip locked
  loop
    v_seen   := v_seen + 1;
    v_deliv  := null;
    v_reason := null;
    v_basis  := '{}'::jsonb;
    v_gap_id := null;
    v_gap_status := null;
    v_handler := null;
    v_close  := null;
    v_tracked := false;

    -- ONE BAD ROW MUST NOT TAKE THE BATCH, AND MUST NOT TAKE THE FINDING. Everything from routing
    -- to the close runs inside this block, so a handler that raises -- a ::date cast on a captured
    -- "Date: 2026-13-45", a ::uuid cast on 36 hex characters with the dashes in the wrong places, a
    -- trigger refusing a close -- rolls back to the point this row was picked up instead of
    -- aborting fn_org_task_consume_tick. Without it, one poisoned row would undo every close
    -- already made in the same batch AND skip the per-class census at the end, so the tick would
    -- lose the finding that says the queue is stuck, stamp nothing, and re-select the same poisoned
    -- batch every 15 minutes with no forward progress and no explanation. The row itself is then
    -- stamped and parked on the queued path below, carrying SQLERRM as its reason.
    begin

    -- ── knowledge_gap ─────────────────────────────────────────────────────────────────────────
    if r.action_class = 'knowledge_gap' then
      v_q := nullif(btrim(coalesce(substring(r.detail from 'QUESTION: ([^\n]+)'), '')), '');

      -- THE GAP LEDGER IS THE WRITER'S OWN RECORD, SO READ IT FIRST. Measured 18 Sep 2026:
      -- sales_knowledge_gap #13 ("how much does it cost to charter a helicopter to the moon") has
      -- carried status='not_a_gap' since it was judged, while org_task 578944 stayed 'assigned'
      -- for nine days -- the founder's own rule, a status column is not a delivery record, showing
      -- up inside the very table that records the judgement. A question already judged out of
      -- scope has nothing left to answer, and the judgement is the fact the close cites.
      select g.id, g.status into v_gap_id, v_gap_status
        from public.sales_knowledge_gap g where g.task_id = r.id;

      if v_gap_status = 'not_a_gap' then
        v_handler := 'sales_knowledge_gap';
        v_deliv := 'ALREADY JUDGED. public.sales_knowledge_gap #' || v_gap_id || ', the record this '
          || 'task''s own detail points at, carries status = ''not_a_gap'': the question was reviewed '
          || 'and found not to be a gap in company knowledge.'
          || E'\n\nQUESTION: ' || coalesce(v_q, '(none recorded on the task)')
          || E'\n\nThere is nothing to answer and nothing to add to a corpus. The task stayed open '
          || 'only because the judgement was written to the gap ledger and never carried back to the '
          || 'queue -- which is the defect this consumer exists to end.';
        v_basis := jsonb_build_object('answered_by', 'sales_knowledge_gap',
                                      'sales_knowledge_gap_id', v_gap_id, 'gap_status', v_gap_status);

      elsif v_q is null then
        v_handler := 'none';
        v_reason  := 'the task carries no "QUESTION:" line, so there is nothing to ask again';

      else
        -- WHAT THE QUESTION ASKS IS A REASONED READING (org_task_question_reading, 23 Sep 2026,
        -- founder_instruction 886-903): which published trade's price, or which approved public FAQ,
        -- answers it -- chosen by the sales engineer's reasoning (reasoned_suppliers.ts
        -- reasonOrgTaskQuestions), never by the question's words against a lexicon or FAQ lexemes.
        -- Not read yet (the model hold): the row is parked with that reason and retried; nothing is guessed.
        select q.* into v_read from public.org_task_question_reading q
         where q.task_id = r.id and q.question_md5 = md5(v_q) and q.status = 'reasoned';
        if not found then
          v_handler := 'none';
          v_reason  := 'the question waits for the sales engineer''s reasoning (which published price or approved '
                    || 'FAQ answers it); nothing is matched by its words meanwhile';
        else
        -- 1. the price answerer, for the trade the reasoning chose
        v_pg := case when v_read.trade is not null then public.fn_price_guidance(v_read.trade, 6) end;

        if coalesce((v_pg->>'ok')::boolean, false) then
          v_handler := 'fn_price_guidance';
          v_deliv := 'ANSWERED TODAY by public.fn_price_guidance, the published-price answerer.'
            || E'\n\nQUESTION: ' || v_q
            || E'\n\nTRADE (reasoned by the sales engineer): ' || coalesce(v_pg->>'trade', '?') || ', '
            || coalesce(v_pg->>'band_count', '0') || ' published UAE bands for the trade as a whole.'
            || E'\n\nBANDS: ' || coalesce(v_pg->'bands', '[]'::jsonb)::text
            || E'\n\nThese are published guide ranges in AED, never a quotation: QuotesDone does not '
            || 'price the work, suppliers do.';
          v_basis := jsonb_build_object('answered_by', 'fn_price_guidance', 'price_guidance', v_pg, 'reading', 'org_task_question_reading');

        elsif coalesce(v_pg->>'reason', '') = 'trade_has_a_recorded_gap' then
          v_handler := 'fn_price_guidance';
          v_deliv := 'ANSWERED TODAY by public.fn_price_guidance: the company holds a DELIBERATE '
            || 'recorded gap for this trade, which is an answer and not a silence.'
            || E'\n\nQUESTION: ' || v_q
            || E'\n\nTRADE: ' || coalesce(v_pg->>'trade', '?')
            || E'\nRECORDED GAP: ' || coalesce(v_pg->>'gap_reason', '')
            || E'\n\nTHE ANSWER TO GIVE: QuotesDone publishes no price range for this trade. Say so '
            || 'plainly, never estimate one, and offer to put the job out to suppliers for real '
            || 'quotes. ' || coalesce(v_pg->>'note', '');
          v_basis := jsonb_build_object('answered_by', 'fn_price_guidance', 'price_guidance', v_pg);

        else
          -- 2. the approved public company_faq entry the reasoning chose, if any.
          v_faq_id := null;
          if v_read.faq_id is not null then
            select f.id, f.question, f.answer into v_faq_id, v_faq_q, v_faq_a
              from public.company_faq f where f.id = v_read.faq_id and f.public and f.status = 'approved';
          end if;

          -- 3. the corpus the writer named. Arabic-aware, read-only, public rows only.
          if v_faq_id is null then
            select s.src, s.src_id, s.title, s.content, s.citation, s.rank
              into v_best
              from public.fn_support_corpus_search(v_q, true, 3) s
             order by s.rank desc
             limit 1;
          end if;

          if v_faq_id is not null then
            v_handler := 'company_faq';
            v_deliv := 'ANSWERED TODAY by the approved public company_faq entry the sales engineer''s '
              || 'reasoning chose for this question (org_task_question_reading).'
              || E'\n\nQUESTION: ' || v_q
              || E'\n\nSOURCE: company_faq #' || v_faq_id || ' -- ' || v_faq_q
              || E'\n\nANSWER: ' || left(coalesce(v_faq_a, ''), 4000);
            v_basis := jsonb_build_object('answered_by', 'company_faq', 'company_faq_id', v_faq_id, 'reading', 'org_task_question_reading');

          elsif v_best.rank is not null and v_best.rank >= 1.5 then
            v_handler := 'fn_support_corpus_search';
            v_deliv := 'ANSWERED TODAY by public.fn_support_corpus_search over v_support_corpus '
              || '(company_faq + support_knowledge + ops_knowledge) -- the corpus this task names.'
              || E'\n\nQUESTION: ' || v_q
              || E'\n\nSOURCE: ' || v_best.src || ':' || v_best.src_id
              || ' -- ' || coalesce(v_best.citation, coalesce(v_best.title, ''))
              || ' (rank ' || round(v_best.rank::numeric, 3) || ', floor 1.5)'
              || E'\n\nANSWER: ' || left(coalesce(v_best.content, ''), 4000);
            v_basis := jsonb_build_object(
              'answered_by', 'fn_support_corpus_search',
              'src', v_best.src, 'src_id', v_best.src_id, 'rank', round(v_best.rank::numeric, 4));
          else
            -- 4. NOTHING ANSWERS: CLOSE AS A TRACKED GAP. Re-asking every few hours cannot create
            --    knowledge; it only kept a duplicate of the gap ledger in the queue and paged about
            --    it. The gap row IS the seat's record of the unanswered question (the writers bump
            --    its asks on every repeat and reuse this task), so the task ends by citing it and
            --    the row stays 'open' -- it is NOT marked knowledge_added.
            v_handler := 'sales_knowledge_gap';
            v_tracked := true;
            if v_gap_id is null and not p_dry_run then
              insert into public.sales_knowledge_gap (question_norm, question, refusal, nearest_corpus, task_id)
              values (lower(btrim(v_q)), v_q, 'consumer_tracked_gap', 'support_corpus', r.id)
              on conflict (question_norm) do nothing;
              select g.id, g.status into v_gap_id, v_gap_status
                from public.sales_knowledge_gap g where g.question_norm = lower(btrim(v_q));
            end if;
            v_deliv := 'NOT ANSWERED -- FILED AS A TRACKED KNOWLEDGE GAP. No corpus answers this today: '
              || 'the reasoning found no published trade price (' || coalesce(nullif(v_pg->>'reason', ''), 'no trade')
              || ') and no approved public company_faq entry that answers it, and the best '
              || 'company-knowledge hit ranked ' || coalesce(round(v_best.rank::numeric, 3)::text, 'nothing')
              || ' against a floor of 1.5.'
              || E'\n\nQUESTION: ' || v_q
              || E'\n\nTRACKED AT: public.sales_knowledge_gap #' || coalesce(v_gap_id::text, '(filed on the live run)')
              || ', status ' || coalesce(v_gap_status, 'open') || ', owned by the ' || coalesce(r.assigned_agent, '?')
              || ' seat. It stays open until the answer is written into company_faq or support_knowledge; '
              || 'this task closes because re-running the same search cannot produce that answer.';
            v_basis := jsonb_build_object('answered_by', 'none', 'outcome', 'tracked_gap',
                                          'sales_knowledge_gap_id', v_gap_id,
                                          'best_corpus_rank', round(v_best.rank::numeric, 4));
          end if;
        end if;
        end if;
      end if;

    -- ── routine_operational_decision ──────────────────────────────────────────────────────────
    elsif r.action_class = 'routine_operational_decision'
          and coalesce(r.result->'founder_mail'->>'kind', '') = 'expense_logged' then
      v_handler := 'expense_entries';
      v_vendor := btrim(coalesce(substring(r.title from '^Expense logged: (.+) [0-9.]+ [A-Za-z]{3}$'), ''));
      v_amount := nullif(coalesce(substring(r.title from '([0-9]+\.?[0-9]*) [A-Za-z]{3}$'), ''), '')::numeric;
      v_ccy    := upper(coalesce(substring(r.title from '([A-Za-z]{3})$'), ''));
      -- THE DATE IS PART OF THE IDENTITY, AND LEAVING IT OUT CITED THE WRONG RECEIPT. Measured in
      -- the rolled-back dry run of 18 Sep 2026: matching on vendor + amount + currency alone closed
      -- "Expense logged: GoDaddy 93.8 AED" (announced 10 Sep) on expense_entries #62 charged
      -- 10 AUGUST, and "Resend 20 USD" (15 Sep) on #52 charged 15 August -- because a monthly
      -- subscription bills the same vendor the same amount every month and the oldest row won.
      -- A close that cites the wrong month's receipt is worse than an open task. The announced date
      -- is in the task's own body and matched exactly on all four live rows, so it is required: no
      -- exact match means the row stays queued and says why, rather than closing on a near miss.
      v_charged := nullif(coalesce(substring(r.detail from 'Date: ([0-9]{4}-[0-9]{2}-[0-9]{2})'), ''), '')::date;

      select e.id, e.vendor, e.amount, e.currency, e.charged_on, e.source, e.category, e.doc_path
        into v_exp
        from public.expense_entries e
       where e.vendor = v_vendor and e.amount = v_amount and upper(e.currency) = v_ccy
         and v_charged is not null and e.charged_on = v_charged
       order by e.id
       limit 1;

      if found then
        v_deliv := 'ALREADY DONE BEFORE THIS TASK EXISTED. The expense is booked: '
          || 'public.expense_entries #' || v_exp.id || ' -- ' || v_exp.vendor || ' '
          || v_exp.amount || ' ' || v_exp.currency || ' charged on ' || v_exp.charged_on
          || ', category ' || coalesce(v_exp.category, '(none)') || ', source ' || coalesce(v_exp.source, '?')
          || ', document ' || coalesce(v_exp.doc_path, '(none -- founder-reported)') || '.'
          || E'\n\nsupabase/functions/resend_inbound books the entry and posts it to the general '
          || 'ledger through fn_expense_post_to_gl at intake, and only THEN requests the notification '
          || 'that became this task. The task''s own words are "a booked expense is a record, not a '
          || 'decision": the record exists, so the condition it was raised for is resolved and there '
          || 'was never a decision to take.'
          || case when coalesce((r.result->'founder_mail'->>'seen_count')::int, 1) > 1
                  then E'\n\nThis signal recurred ' || (r.result->'founder_mail'->>'seen_count')
                       || ' times; each recurrence is its own booked entry.'
                  else '' end;
        v_basis := jsonb_build_object('answered_by', 'expense_entries', 'expense_entry_id', v_exp.id,
                                      'vendor', v_exp.vendor, 'amount', v_exp.amount, 'currency', v_exp.currency);
      else
        v_reason := 'no row in public.expense_entries matches ' || coalesce(v_vendor, '?') || ' '
          || coalesce(v_amount::text, '?') || ' ' || coalesce(v_ccy, '?') || ' charged on '
          || coalesce(v_charged::text, '(the task carries no "Date:" line)')
          || '. Either the receipt was announced and never booked -- which is the accountant''s duty '
          || 'failing rather than a task waiting -- or the booked entry carries a different date. Do '
          || 'NOT close this until the exact entry exists: a monthly subscription bills the same '
          || 'vendor the same amount every month, so vendor and amount alone identify nothing.';
      end if;

    elsif r.action_class = 'routine_operational_decision'
          and coalesce(r.result->'founder_mail'->>'kind', '') = 'rfq_no_supplier' then
      v_handler := 'inquiries + inquiry_matches';
      v_inq := nullif(coalesce(substring(r.detail from 'Inquiry: ([0-9a-fA-F-]{36})'), ''), '')::uuid;

      if v_inq is null then
        v_reason := 'the task names no inquiry id, so the claim "the customer is waiting" cannot be checked';
      else
        select true into v_inq_seen from public.inquiries i where i.id = v_inq;
        v_inq_seen := coalesce(v_inq_seen, false);
        select count(*) into v_matches from public.inquiry_matches m where m.inquiry_id = v_inq;

        if not v_inq_seen then
          v_deliv := 'THE CONDITION IS GONE. This task was raised because inquiry ' || v_inq
            || ' matched zero suppliers and a customer was waiting. That inquiry no longer exists in '
            || 'public.inquiries, so there is no customer waiting on it and nothing to route.'
            || E'\n\nThe underlying supply-coverage gap is NOT closed by this and is not claimed to '
            || 'be: it remains recorded in public.agent_actions under kind=''coverage_gap'', which is '
            || 'where a coverage decision belongs. What closes here is this signal, which named a '
            || 'request that is no longer live.';
          v_basis := jsonb_build_object('answered_by', 'inquiries', 'inquiry_id', v_inq, 'inquiry_present', false);
        elsif v_matches > 0 then
          v_deliv := 'THE CONDITION IS GONE. Inquiry ' || v_inq || ' now has ' || v_matches
            || ' row(s) in public.inquiry_matches, so it no longer matches zero suppliers and the '
            || 'signal this task carries is out of date.';
          v_basis := jsonb_build_object('answered_by', 'inquiry_matches', 'inquiry_id', v_inq, 'matches', v_matches);
        else
          v_reason := 'inquiry ' || v_inq || ' is still live and still matches zero suppliers. There is '
            || 'NO handler for this and this tick will not invent one: onboarding or contacting '
            || 'suppliers in a trade and emirate is a commercial act, fn_supply_gap_scan was dropped '
            || 'on 7 Sep 2026, and no live routine owns supply coverage. It stays queued for the ceo '
            || 'seat, and the class carries a finding saying exactly this.';
        end if;
      end if;

    -- ── routine_operational_decision / supplier_registered (fn_founder_mail_route) ─────────────
    -- The task announces a decision already taken ("... No action needed; this is a record."). The
    -- decider checks the record against public.leads and closes on it.
    --
    -- 21 SEP 2026 — THE LICENCE IS NOT PART OF THE ANNOUNCEMENT'S IDENTITY. Measured on
    -- production (the project ref used to be spelled here; it made the schema export unportable, and a
    -- routine body is not the place to name one database — 23 Sep 2026): org_tasks 579041 and 579076
    -- stayed 'assigned' and re-raised
    -- duty:org_task_queue:routine_operational_decision:sales_engineer to the founder because v2
    -- required a "Licence X," line, and supplier_api/index.ts writes that line only when the lead has
    -- a trade_license_no (its licInfo is '' otherwise). Both announcements named ZZ DEMO registration
    -- walks whose leads the walk had already deleted, and 579076 announced 'action_required' (the
    -- terms certificate on its way) -- a record, not a pending decision, which v2 also refused as
    -- "the register disagrees". Now: the name identifies the lead (the licence narrows it when the
    -- announcement carries one); a removed ZZ DEMO fixture is a condition that is gone; only a
    -- 'pending' announcement still waiting on the seat stays queued, because that one IS a decision.
    elsif r.action_class = 'routine_operational_decision'
          and coalesce(r.result->'founder_mail'->>'kind', '') = 'supplier_registered' then
      v_handler  := 'leads';
      v_vendor   := substring(r.detail from 'New supplier "([^"]+)"');
      v_lic      := nullif(btrim(substring(r.detail from 'Licence ([^,]+),')), '');
      v_decision := lower(substring(r.detail from 'Decision: ([A-Za-z_]+)'));

      select count(*)::int into v_matches
        from public.leads l
       where l.company_name = v_vendor and (v_lic is null or l.trade_license_no = v_lic);

      select l.id, l.company_name, l.trade_license_no, l.approval_status, l.approval_decided_by,
             l.approved_at, coalesce(l.banned, false) as banned, l.license_expiry, l.is_demo
        into v_lead
        from public.leads l
       where l.company_name = v_vendor and (v_lic is null or l.trade_license_no = v_lic)
       order by l.id desc limit 1;

      if v_vendor is null or v_decision is null then
        v_reason := 'the task does not carry the supplier name and decision in the form '
          || 'supplier_api writes them ("New supplier \"<name>\" ... Decision: <status>"), so the '
          || 'record cannot be checked';
      elsif v_matches = 0 and v_vendor ~ '^ZZ DEMO' then
        v_deliv := 'THE CONDITION IS GONE. The task announced the ZZ DEMO fixture supplier "' || v_vendor
          || '" as ' || v_decision || '. public.leads no longer holds it: the rehearsal that registered '
          || 'it removed its own fixture, so there is no supplier to welcome and no record to reconcile.';
        v_basis := jsonb_build_object('answered_by', 'leads', 'lead_present', false, 'fixture', true,
                                      'announced', v_decision);
      elsif v_matches = 0 then
        v_reason := 'no public.leads row is named "' || v_vendor || '"'
          || coalesce(' with licence ' || v_lic, '')
          || ': the announcement names a supplier the register does not hold';
      elsif v_matches > 1 then
        v_reason := v_matches || ' public.leads rows are named "' || v_vendor || '" and the announcement '
          || 'carries no licence to tell them apart; the seat identifies which one registered';
      elsif v_lead.banned then
        v_reason := 'leads #' || v_lead.id || ' is BANNED while the task announced "' || v_decision
          || '". That is the seat''s to reconcile.';
      elsif v_decision = 'pending' and coalesce(v_lead.approval_status, 'pending') = 'pending' then
        v_reason := 'leads #' || v_lead.id || ' is still pending: auto-approve is off and the approval '
          || 'is the ' || coalesce(r.assigned_agent, '?') || ' seat''s decision, not a record';
      elsif v_decision = 'approved' and v_lead.approval_status is distinct from 'approved' then
        v_reason := 'the register disagrees with the announcement: leads #' || v_lead.id
          || ' has approval_status ' || coalesce(v_lead.approval_status, 'null')
          || ' while the task announced "approved". That is the seat''s to reconcile.';
      else
        v_deliv := 'RECORD CONFIRMED -- NO DECISION WAS PENDING. The task announced supplier "'
          || v_vendor || '"' || coalesce(' (licence ' || v_lic || ')', '') || ' as ' || v_decision
          || '. public.leads #' || v_lead.id || ' holds it: approval_status '
          || coalesce(v_lead.approval_status, 'null') || coalesce(' by ' || v_lead.approval_decided_by, '')
          || coalesce(' at ' || v_lead.approved_at::text, '')
          || ', licence ' || coalesce(v_lead.trade_license_no, '(none recorded)')
          || coalesce(' expiring ' || v_lead.license_expiry::text, '') || ', not banned.'
          || E'\n\nThe task''s own words are "No action needed; this is a record": the record exists, '
          || 'so it closes on that fact. What the supplier still owes is on its own registration '
          || 'email and portal, not on this seat.';
        v_basis := jsonb_build_object('answered_by', 'leads', 'lead_id', v_lead.id, 'announced', v_decision,
                                      'approval_status', v_lead.approval_status, 'is_demo', v_lead.is_demo);
      end if;

    -- ── routine_operational_decision / sales_rating (the rating trigger's task) ────────────────
    -- The judgement asked: does this rating change the supplier's standing, capability or
    -- eligibility? Deterministic rule: a rating of 3-5 changes none of them (the aggregate already
    -- carries it). A rating of 1-2 is a standing judgement with no written policy, so it stays
    -- queued with that reason rather than having a suspension rule invented here.
    elsif r.action_class = 'routine_operational_decision' and r.result ? 'sales_rating' then
      v_handler := 'reviews + leads';
      select rv.id, rv.rating, rv.supplier_id into v_rev
        from public.reviews rv
       where rv.id = nullif(r.result->'sales_rating'->>'review_id', '')::bigint;

      if not found then
        v_deliv := 'THE CONDITION IS GONE. Review #' || coalesce(r.result->'sales_rating'->>'review_id', '?')
          || ' no longer exists in public.reviews, so there is no rating left to incorporate into the '
          || 'supplier record.';
        v_basis := jsonb_build_object('answered_by', 'reviews', 'review_present', false);
      else
        select round(avg(x.rating)::numeric, 2) as avg_rating, count(*)::int as n
          into v_agg from public.reviews x where x.supplier_id = v_rev.supplier_id;
        select l.id, l.company_name, l.app_rating, l.app_reviews into v_lead
          from public.leads l where l.id = v_rev.supplier_id;

        if not found then
          v_reason := 'review #' || v_rev.id || ' names supplier ' || v_rev.supplier_id
            || ' and public.leads has no such row';
        elsif v_lead.app_rating is distinct from v_agg.avg_rating
              or v_lead.app_reviews is distinct from v_agg.n then
          v_reason := 'the supplier aggregate is stale: leads #' || v_lead.id || ' shows '
            || coalesce(v_lead.app_rating::text, 'null') || ' over ' || coalesce(v_lead.app_reviews::text, 'null')
            || ' review(s) but public.reviews holds ' || coalesce(v_agg.avg_rating::text, 'null') || ' over '
            || v_agg.n || '. recompute_supplier_rating did not run, which is a defect, not a decision.';
        elsif v_rev.rating >= 3 then
          v_deliv := 'DECIDED: NO CHANGE TO STANDING, CAPABILITY OR ELIGIBILITY. Review #' || v_rev.id
            || ' rates ' || v_lead.company_name || ' ' || v_rev.rating || '/5. The supplier aggregate '
            || 'already carries it (' || v_lead.app_rating || ' over ' || v_lead.app_reviews
            || ' review(s), equal to public.reviews). Rule applied: a rating of 3 to 5 does not change a '
            || 'supplier''s standing, declared capability or trade eligibility; only a rating of 1 or 2 '
            || 'is held for the seat''s judgement.';
          v_basis := jsonb_build_object('answered_by', 'reviews', 'review_id', v_rev.id,
                                        'rating', v_rev.rating, 'supplier_id', v_rev.supplier_id,
                                        'app_rating', v_lead.app_rating, 'app_reviews', v_lead.app_reviews,
                                        'rule', 'rating >= 3 => no change to standing');
        else
          v_reason := 'review #' || v_rev.id || ' rates the supplier ' || v_rev.rating || '/5. A rating '
            || 'of 1 or 2 may change the supplier''s standing and no written policy decides that, so it '
            || 'stays with the ' || coalesce(r.assigned_agent, '?') || ' seat.';
        end if;
      end if;

    else
      v_handler := 'none';
      v_reason  := 'no handler is mapped for action_class ' || coalesce(r.action_class, '(null)')
        || ' on seat ' || coalesce(r.assigned_agent, '(unassigned)')
        || '. Mapping one is a deliberate act, not a default.';
    end if;

    ------------------------------------------------------------------------------------------
    -- SETTLE THE ROW
    ------------------------------------------------------------------------------------------
      if v_deliv is not null and not p_dry_run then
        -- z50_task_close_needs_an_act refuses a close on a requires_evidence task whose result
        -- records facts but no act. Flipping the knowledge gap and citing the source IS the act,
        -- and it is written before the close so fn_org_task_close_as_fact merges onto it.
        update public.org_tasks
           set result = coalesce(result, '{}'::jsonb) || jsonb_build_object(
                 'change_made', jsonb_build_object(
                   'what', 'the condition this task was raised for was re-checked against the handler '
                           || 'the writer named, and it is resolved',
                   'handler', v_handler, 'basis', v_basis, 'at', now()))
         where id = r.id;

        v_close := public.fn_org_task_close_as_fact(r.id, 'fn_org_task_consume_tick', v_deliv,
                     v_basis || jsonb_build_object('owner', r.assigned_agent, 'handler', v_handler));

        -- A REFUSAL IS RETURNED, NOT RAISED, AND IT IS NOT A CLOSE. fn_org_task_close_as_fact
        -- answers {ok:false, reason} when the task is already done, the resolver is unnamed or the
        -- deliverable is too short. Flipping the gap ledger on that return would mark a customer's
        -- question knowledge_added while the task never left 'assigned' -- the exact shape of "a
        -- status column is not a delivery record", and worse: the refusal paths return before
        -- stamping last_run_at, so the row would keep sorting first on every tick and re-run the
        -- search forever behind a ledger already claiming success. So the refusal becomes the
        -- reason and the row falls through to the queued path, where it is stamped and backs off.
        if coalesce((v_close->>'ok')::boolean, false) then
          -- what both writers asked for in words, done in one place at last
          -- (a tracked-gap close answered nothing, so its gap row stays 'open')
          if r.action_class = 'knowledge_gap' and not v_tracked then
            update public.sales_knowledge_gap
               set status = 'knowledge_added', closed_at = now()
             where task_id = r.id and status = 'open'
            returning id into v_gap_id;
          end if;
        else
          v_reason := 'fn_org_task_close_as_fact REFUSED this close: '
            || coalesce(nullif(btrim(v_close->>'reason'), ''), '(no reason given)')
            || '. The handler had an answer and the close path rejected it, so nothing is recorded '
            || 'as delivered and the row backs off instead.';
          v_deliv  := null;
          v_refused := v_refused + 1;
        end if;
      end if;

    exception when others then
      v_deliv  := null;
      v_close  := null;
      v_reason := 'the handler RAISED and this row was rolled back to the point it was picked up: '
        || sqlerrm || ' (SQLSTATE ' || sqlstate || '). The rest of this batch and the per-class '
        || 'finding are unaffected; this row is stamped and backs off so the failure is visible '
        || 'rather than repeating every 15 minutes.';
      v_raised := v_raised + 1;
    end;

    v_back := make_interval(mins => (15 * power(2, least(r.attempts + 1, 6)))::int);

    if v_deliv is not null then
      if p_dry_run then
        v_done := v_done || jsonb_build_object('id', r.id, 'class', r.action_class, 'seat', r.assigned_agent,
                    'handler', v_handler, 'would', 'close', 'basis', v_basis, 'deliverable', left(v_deliv, 1200));
      else
        v_done := v_done || jsonb_build_object('id', r.id, 'class', r.action_class, 'seat', r.assigned_agent,
                    'handler', v_handler, 'closed', true,
                    'close', v_close, 'sales_knowledge_gap', v_gap_id);
      end if;

    else
      if p_dry_run then
        v_left := v_left || jsonb_build_object('id', r.id, 'class', r.action_class, 'seat', r.assigned_agent,
                    'handler', v_handler, 'would', 'stay queued', 'reason', v_reason,
                    'attempts_would_be', r.attempts + 1, 'next_attempt_after', now() + v_back);
      else
        update public.org_tasks
           set last_run_at = now(),
               attempts    = coalesce(attempts, 0) + 1,
               updated_at  = now(),
               result      = coalesce(result, '{}'::jsonb) || jsonb_build_object(
                 'consumer', jsonb_build_object(
                   'at', now(), 'version', 'v3', 'handler', v_handler, 'verdict', 'not_yet', 'reason', v_reason,
                   'attempts', coalesce(r.attempts, 0) + 1, 'next_attempt_after', now() + v_back))
         where id = r.id;

        v_left := v_left || jsonb_build_object('id', r.id, 'class', r.action_class, 'seat', r.assigned_agent,
                    'handler', v_handler, 'reason', v_reason, 'attempts', r.attempts + 1,
                    'next_attempt_after', now() + v_back);
      end if;
    end if;
  end loop;

  ------------------------------------------------------------------------------------------------
  -- ONE FINDING PER CLASS, OVER THE WHOLE TABLE. Not one per row, not one per tick.
  ------------------------------------------------------------------------------------------------
  if p_task_id is null and not p_dry_run then
    select coalesce(jsonb_agg(jsonb_build_object(
             'item',  x.action_class || ':' || x.seat,
             'title', x.n || ' org_task(s) of class ' || x.action_class || ' are queued on the '
                      || x.seat || ' seat and the consumer cannot finish them; the oldest has waited '
                      || x.age_days || ' day(s)',
             'owner_seat', x.seat,
             'subject', 'org_tasks',
             'blast',  'agent_facing',
             'affected', x.n,
             -- A STANDING GAP, NOT A FRESH FAILURE EVERY FIFTEEN MINUTES. This is the convention
             -- #744 added on 18 Sep 2026 after duty:renewal:...:date_unknown was re-raised 320
             -- times in four days: fn_it_duty_settle holds an already-open finding carrying
             -- 'config' => true, refreshing its title and evidence to today's reading while
             -- seen_count, last_seen_at and started_at stand still. That is exactly this subject.
             -- Nothing about the running system changes between two ticks over the same queue;
             -- what is missing is knowledge nobody has written or a supplier nobody has onboarded.
             -- Without the flag this finding's seen_count would climb 96 times a day and bury
             -- every finding that did move. A CLOSED one still reopens, because a class that
             -- emptied and came back IS news.
             'config', true,
             'evidence', jsonb_build_object(
               'ids', x.ids, 'oldest_created_at', x.oldest, 'max_attempts', x.max_attempts,
               'last_reason', x.reason,
               'look_at', 'select id, title, result->''consumer'' from public.org_tasks where status = ''assigned'''))), '[]'::jsonb)
      into v_items
      from (
        select o.action_class,
               coalesce(o.assigned_agent, 'unassigned')          as seat,
               count(*)::int                                     as n,
               array_agg(o.id order by o.id)                     as ids,
               min(o.created_at)                                 as oldest,
               (extract(epoch from (now() - min(o.created_at))) / 86400)::int as age_days,
               max(o.attempts)                                   as max_attempts,
               max(o.result->'consumer'->>'reason')              as reason
          from public.org_tasks o
         where o.status = 'assigned'
         group by 1, 2
      ) x;

    declare v_lt text := current_setting('lock_timeout'); begin
      perform set_config('lock_timeout', '2s', true);
      v_settled := public.fn_it_duty_settle('org_task_queue', v_items);
      perform set_config('lock_timeout', v_lt, true);
    exception when lock_not_available then
      perform set_config('lock_timeout', v_lt, true);
      v_settled := jsonb_build_object('skipped', true, 'why', 'a finding row was locked by another transaction for 2 s; settled on the next tick');
    end;
  end if;

  -- THE STEP RUNNER ONLY COUNTS {ok:false, error:'<string>'} AS A FAILURE (resilience_ping/steps.ts,
  -- failureOf). A hardcoded ok:true would mean a refused close or a raising handler never reaches
  -- settleFailures and never becomes duty:heartbeat:orgtasks -- a broken consumer reporting health.
  -- So a tick that could not finish what it started says so in the shape the runner reads.
  return jsonb_build_object(
    'ok', (v_refused + v_raised) = 0,
    'error', case when (v_refused + v_raised) > 0
                  then v_refused || ' close(s) refused and ' || v_raised || ' handler(s) raised; '
                       || 'see result->''consumer''->>''reason'' on the rows still at status=''assigned'''
                  else null end,
    'refused', v_refused,
    'raised', v_raised,
    'dry_run', p_dry_run,
    'scanned', v_seen,
    'closed', jsonb_array_length(v_done),
    'still_queued', jsonb_array_length(v_left),
    'done', v_done,
    'queued', v_left,
    'findings', v_settled,
    'ms', round(extract(epoch from (clock_timestamp() - v_t0)) * 1000));
end
$function$


CREATE OR REPLACE FUNCTION public.fn_org_task_cross_os_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_target_os text; v_author_os text;
begin
  if coalesce(new.status,'proposed') = 'proposed' then return new; end if;
  if coalesce(new.decided_by,'') in ('fn_event_dispatch','cos','approval_path','dept_plan') then
    return new;
  end if;

  select od.os_key into v_target_os from os_department od where od.dept_key = new.dept_key;

  select od.os_key into v_author_os
    from org_agents a join os_department od on od.dept_key = a.department
   where a.agent_key = new.decided_by;

  -- An unattributed writer is a company-level routine, not an Operating System, and the blueprint
  -- does not forbid those. Only a named OS reaching across is refused.
  if v_author_os is null or v_target_os is null or v_author_os = v_target_os then
    return new;
  end if;

  raise exception
    'org_tasks: % (%) cannot ASSIGN work to % (%). No OS calls another OS directly — emit the '
    'event and let the bus route it, or lower this to status=''proposed'' so the receiving OS can '
    'decline it.', new.decided_by, v_author_os, new.dept_key, v_target_os
    using errcode = 'check_violation';
end $function$


CREATE OR REPLACE FUNCTION public.fn_org_task_demo_files_nothing()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if public.fn_seat_work_is_demo(coalesce(new.title, '') || ' ' || coalesce(new.detail, ''), new.result) then
    return null;   -- ruling 1199: a demo row files no seat task
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_org_task_deterministic_done(p_task_id bigint, p_step_run_id bigint, p_output jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t            record;
  v_floor      numeric := 0.85;      -- fn_apply_playbook's floor; a caller cannot lower it here
  v_sim        numeric;
  v_terms      int;
  v_total      int;
  v_deliv      text;
  v_outcome    text;
  v_employee   text;
  v_review     jsonb;
  v_verdict    text;
  v_trace      uuid;
  v_queue      bigint;
  v_rc         text;
  v_known      int;
  -- the record applied
  v_pb_id text; v_pb_title text; v_pb_type text; v_pb_content text; v_pb_sd jsonb;
  -- facts + rendering
  v_facts jsonb; v_bound int; v_disp text; v_mode text; v_source text := 'task_facts_rendered';
  -- executor
  ex record; v_needs_model boolean := false; v_exec_status text; v_exec_id uuid; v_exec_result jsonb; v_exec_text text;
  v_req_args int; v_argnames text[]; v_kind text := null; v_target text; v_err text; x jsonb;
  -- measurement
  v_step_started timestamptz; v_llm int := 0; v_cost int := 0; v_used_llm boolean; v_llm_basis text;
begin
  select o.id, o.dept_key, o.title, o.detail, o.action_class, o.tier, o.status, o.assigned_agent
    into t from public.org_tasks o where o.id = p_task_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no such org_task ' || p_task_id);
  end if;
  if t.status not in ('assigned','in_progress') then
    return jsonb_build_object('ok', false, 'reason', 'org_task ' || p_task_id || ' is ' || t.status || ', not open work');
  end if;

  v_deliv   := coalesce(p_output->>'deliverable', '');
  v_sim     := nullif(p_output->>'similarity', '')::numeric;
  v_terms   := coalesce(nullif(p_output->>'terms_matched','')::int, 0);
  v_total   := coalesce(nullif(p_output->>'terms_total','')::int, 0);
  v_employee := coalesce(nullif(p_output->>'employee',''), t.assigned_agent, t.dept_key);

  -- FALSE-SUCCESS GUARDS, UNCHANGED. Nothing below runs unless the match has substance.
  if coalesce(p_output->>'playbook_record_id','') = '' then
    return jsonb_build_object('ok', false, 'reason', 'no playbook_record_id: a determination must cite the company knowledge it applied');
  end if;
  select k.record_id, k.title, k.record_type, k.content, coalesce(k.structured_data, '{}'::jsonb)
    into v_pb_id, v_pb_title, v_pb_type, v_pb_content, v_pb_sd
    from public.ops_knowledge k
   where k.record_id = p_output->>'playbook_record_id'
     and k.runtime_eligible and k.supersession_state = 'current'
     and k.record_type in ('decision_playbook','decision_rule','standard_operating_procedure','exception_playbook');
  if v_pb_id is null then
    return jsonb_build_object('ok', false, 'reason', 'playbook ' || (p_output->>'playbook_record_id')
             || ' is not a current, runtime-eligible, ACTIONABLE ops_knowledge record');
  end if;
  if v_sim is null or v_sim < v_floor then
    return jsonb_build_object('ok', false, 'reason', 'similarity ' || coalesce(v_sim::text,'null') || ' is below the apply floor ' || v_floor);
  end if;
  if v_terms < 2 or v_total < 1 or (v_terms::numeric / v_total) < 0.30 then
    return jsonb_build_object('ok', false, 'reason', 'corroboration ' || v_terms || ' of ' || v_total
             || ' task terms is under the 2-and-30% bar the applier demands');
  end if;
  if length(v_deliv) < 300 then
    return jsonb_build_object('ok', false, 'reason', 'deliverable shorter than 300 characters is not a determination');
  end if;

  -- THE FACTS, then the deliverable AS A FUNCTION OF THEM.
  v_facts := public.fn_org_task_facts(p_task_id, p_step_run_id);
  v_bound := coalesce((v_facts->>'facts_bound')::int, 0);

  -- THE EXECUTOR of the task's action class. Read the registry row and decide from it, in words.
  select e.action_class, e.kind, e.target, e.risk_tier, e.advisory_safe, e.reversible, e.notifies_human, e.required_authority
    into ex
    from public.org_action_executor e
   where e.action_class = t.action_class and e.active
   order by (e.kind = 'rpc') desc, e.kind limit 1;
  if not found then
    v_exec_status := 'none: no active executor is mapped to action_class ' || coalesce(t.action_class, '(null)') || '; rendered from the task''s facts';
  else
    v_kind := ex.kind; v_target := ex.target;
    v_needs_model := public.fn_executor_needs_model(ex.target);
    if v_needs_model then
      v_exec_status := 'held: ' || ex.target || ' is routed to a model task class by fn_task_class and the paid provider is held; not invoked — this close is advisory';
    elsif coalesce(ex.required_authority, '') = 'founder' then
      v_exec_status := 'withheld: ' || ex.target || ' is reserved to the founder';
    elsif ex.notifies_human then
      v_exec_status := 'withheld: ' || ex.target || ' notifies a human (org_action_executor.notifies_human); the deterministic close never sends';
    elsif not (ex.risk_tier = 'low' and ex.advisory_safe and ex.reversible) then
      v_exec_status := format('withheld: %s is risk_tier=%s advisory_safe=%s reversible=%s; the close invokes low/advisory_safe/reversible only',
                              ex.target, ex.risk_tier, ex.advisory_safe, ex.reversible);
    elsif ex.kind <> 'rpc' then
      -- ponytail: an edge executor needs the HTTP invoker and a step left running for the sweep to settle;
      -- the task lane closes the run with the task, so it invokes rpc inline only. Upgrade path: queue an
      -- action_execution here and let fn_workflow_step_sweep close the task when it settles.
      v_exec_status := 'withheld: ' || ex.target || ' is a ' || ex.kind || ' executor; the org_task lane invokes rpc executors inline only';
    else
      select coalesce(p.pronargs - p.pronargdefaults, -1), p.proargnames into v_req_args, v_argnames
        from pg_proc p where p.proname = ex.target and p.pronamespace = 'public'::regnamespace
       order by p.pronargs limit 1;
      if v_req_args is null then
        v_exec_status := 'failed: public.' || ex.target || '() does not exist';
      elsif v_req_args > 0 then
        v_exec_status := 'withheld: public.' || ex.target || '() requires ' || v_req_args || ' argument(s) an org_task cannot supply';
      else
        v_exec_id := gen_random_uuid();
        begin
          if p_step_run_id is not null and 'p_step_run_id' = any(coalesce(v_argnames, '{}'::text[])) then
            execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from public.%I(p_step_run_id => $1) t', ex.target)
               into v_exec_result using p_step_run_id;
          else
            execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from public.%I() t', ex.target) into v_exec_result;
          end if;
          insert into public.action_execution(id, correlation_id, workflow_step_run_id, action_class, executor, idempotency_key,
                                              risk_tier, reversible, request, response, status, attempts, started_at, finished_at)
          values (v_exec_id, gen_random_uuid(), p_step_run_id, t.action_class, ex.target,
                  'org_task:' || p_task_id || ':det:' || to_char(now(), 'YYYYMMDDHH24MISSMS'),
                  ex.risk_tier, ex.reversible,
                  jsonb_build_object('org_task_id', p_task_id, 'workflow_step_run_id', p_step_run_id, 'dept_key', t.dept_key,
                                     'actor', v_employee, 'source', 'fn_org_task_deterministic_done', 'kind', 'rpc'),
                  jsonb_build_object('invoker', 'succeeded', 'at', now(), 'kind', 'rpc', 'inline', true,
                                     'result_rows', coalesce(jsonb_array_length(v_exec_result), 0),
                                     'result', case when pg_column_size(v_exec_result) > 20000 then to_jsonb(left(v_exec_result::text, 20000)) else v_exec_result end),
                  'succeeded', 1, now(), now());
          v_exec_status := 'ran: public.' || ex.target || '(' || case when p_step_run_id is not null and 'p_step_run_id' = any(coalesce(v_argnames, '{}'::text[]))
                                                                      then 'p_step_run_id => ' || p_step_run_id else '' end
                           || ') inline, ' || coalesce(jsonb_array_length(v_exec_result), 0) || ' row(s), action_execution ' || v_exec_id;
          v_source := 'executor:' || ex.target;
          -- the executor's own words into the deliverable
          v_exec_text := '';
          for x in select * from jsonb_array_elements(v_exec_result) loop
            if x ? 'deliverable' or x ? 'determination' or x ? 'outcome' then
              v_exec_text := v_exec_text
                || case when x ? 'determination' then 'determination: ' || (x->>'determination') || E'\n' else '' end
                || case when x ? 'outcome' then 'outcome: ' || (x->>'outcome') || E'\n' else '' end
                || case when x ? 'deliverable' then (x->>'deliverable') || E'\n' else '' end;
            else
              v_exec_text := v_exec_text || left(x::text, 1500) || E'\n';
            end if;
            exit when length(v_exec_text) > 8000;
          end loop;
          v_exec_text := left(coalesce(nullif(v_exec_text, ''), '(the executor returned no rows)'), 8000);
        exception when others then
          v_err := sqlstate || ' ' || left(sqlerrm, 400);
          -- the failure is a fact: record it and refuse the close, so the step is released with the reason
          insert into public.action_execution(id, correlation_id, workflow_step_run_id, action_class, executor, idempotency_key,
                                              risk_tier, reversible, request, response, status, attempts, started_at, finished_at)
          values (v_exec_id, gen_random_uuid(), p_step_run_id, t.action_class, ex.target,
                  'org_task:' || p_task_id || ':det:' || to_char(now(), 'YYYYMMDDHH24MISSMS'),
                  ex.risk_tier, ex.reversible,
                  jsonb_build_object('org_task_id', p_task_id, 'workflow_step_run_id', p_step_run_id, 'dept_key', t.dept_key,
                                     'actor', v_employee, 'source', 'fn_org_task_deterministic_done', 'kind', 'rpc'),
                  jsonb_build_object('invoker', 'failed', 'at', now(), 'kind', 'rpc', 'inline', true, 'error', v_err),
                  'failed', 1, now(), now());
          return jsonb_build_object('ok', false, 'reason', 'executor public.' || ex.target || '() failed: ' || v_err,
                                    'action_execution_id', v_exec_id);
        end;
      end if;
    end if;
  end if;

  -- THE DELIVERABLE, rendered from the facts, with the executor's output. RESULT: is the org_task
  -- quality standard's major criterion; the outcome sentence is it.
  v_disp := case when v_bound = 0 then 'needs_narrative'
                 when v_needs_model then 'advisory_held_model'
                 else 'determined' end;
  v_mode := case when v_disp = 'determined' then 'determined' else 'advisory' end;
  v_outcome := case when v_disp = 'needs_narrative'
                    then 'No fact was bound for org_task ' || p_task_id || ' (no event, objective, KPI row, department number or prior review); the record "'
                         || v_pb_title || '" applies as written and the task needs narrative from a reviewer.'
                    else coalesce(nullif(v_facts#>>'{derived,band}', '') || ' '
                                  || coalesce(v_facts#>>'{kpi,metric}', v_facts#>>'{derived,event_type}', t.action_class) || ': ', '')
                         || 'applied ' || v_pb_type || ' "' || v_pb_title || '" to ' || v_bound || ' bound fact(s) of org_task ' || p_task_id
                         || case when v_facts#>>'{derived,cause}' is not null then '; cause ' || (v_facts#>>'{derived,cause}') else '' end
                         || '; executor ' || split_part(coalesce(v_exec_status, 'none'), ':', 1) end;
  v_deliv := public.fn_org_task_render(v_facts, v_pb_title, v_pb_type, v_pb_content, v_pb_sd, v_exec_status, v_exec_text);
  if v_deliv !~* '(^|\n)\s*RESULT:' then
    v_deliv := v_deliv || E'\n\nRESULT: ' || left(v_outcome, 300);
  end if;

  -- A KPI-miss task cannot close without a root cause (trg_org_task_root_cause). The cause class and
  -- its evidence come from the facts (the live employee_kpi row, else the task's own numbers).
  if t.title ilike 'KPI missed%' or t.title ~* 'KPI missed: ' then
    v_rc := left('Root cause (deterministic, no model call): ' || coalesce(v_facts#>>'{derived,cause}', 'not established')
              || ' — ' || coalesce(v_facts#>>'{derived,cause_evidence}', 'no attainment figure available')
              || '. Closing action taken from company playbook "' || coalesce(v_pb_title,'') || '" ('
              || v_pb_id || ', cosine ' || v_sim || ', corroborated ' || v_terms || '/' || v_total || ')'
              || case when v_source like 'executor:%' then '; executor ' || v_target || ' ran' else '' end || '.', 500);
  end if;

  -- used_llm IS A MEASUREMENT: the provider ledgers since the dispatcher claimed the step.
  if p_step_run_id is not null then
    select s.started_at into v_step_started from public.workflow_step_run s where s.id = p_step_run_id;
  end if;
  v_step_started := coalesce(v_step_started, now() - interval '10 minutes');
  select count(*) into v_llm  from public.llm_attempt a where a.fn = 'workflow_dispatch' and a.created_at >= v_step_started;
  select count(*) into v_cost from public.ai_cost_log c where c.fn = 'workflow_dispatch' and c.occurred_at >= v_step_started;
  v_used_llm := (v_llm + v_cost) > 0;
  v_llm_basis := 'measured at close: ' || v_llm || ' llm_attempt + ' || v_cost || ' ai_cost_log row(s) by workflow_dispatch since '
                 || v_step_started || case when p_step_run_id is null then ' (no step_run id: a 10-minute window)' else ' (the step was claimed)' end;

  -- The deliverable must be ON THE ROW before the review: fn_task_review reads it off org_tasks, and
  -- so does the author derivation (result.employee).
  update public.org_tasks
     set result = jsonb_build_object(
                    'deliverable', left(v_deliv, 20000),
                    'summary',     left(v_outcome, 300),
                    'mode',        v_mode,
                    'disposition', v_disp,
                    'determination_source', v_source,
                    'executor_status', v_exec_status,
                    'executor_kind', v_kind,
                    'action_execution_id', v_exec_id,
                    'facts_bound', v_bound,
                    'facts',       v_facts,
                    'used_llm',    v_used_llm,
                    'used_llm_basis', v_llm_basis,
                    'lane',        'org_task',
                    'worked_by',   'workflow_dispatch',
                    'employee',    v_employee,
                    'playbook_record_id',   v_pb_id,
                    'playbook_title',       v_pb_title,
                    'playbook_record_type', v_pb_type,
                    'similarity',   v_sim,
                    'terms_matched', v_terms,
                    'terms_total',   v_total,
                    'workflow_step_run_id', p_step_run_id,
                    'at', now())
                  || case when coalesce(result,'{}'::jsonb) ? 'parked'
                          then jsonb_build_object('previously_parked', result->'parked') else '{}'::jsonb end,
         root_cause  = coalesce(v_rc, root_cause),
         decided_by  = 'workflow_dispatch',
         last_run_at = now(),
         attempts    = coalesce(attempts, 0) + 1,
         updated_at  = now()
   where id = p_task_id;

  -- THE PUBLISHER. Department head -> Chief of Staff -> ownership -> cross-department challenge.
  v_review  := public.fn_task_review(p_task_id);
  v_verdict := coalesce(v_review->>'outcome', 'unknown');
  -- result.review: the chain's verdict, labelled as the chain's; queue_status is added once a queue row exists.
  v_review := v_review || jsonb_build_object('chain_outcome', v_verdict, 'chain_by', 'fn_task_review',
                'note', 'chain_outcome is fn_task_review''s verdict on the deliverable (head, chief of staff, ownership, challenge). '
                     || 'queue_status is the review_queue row an independent reviewer has yet to decide. They are not the same thing.');

  -- A VERDICT THAT IS NOT A CLOSE IS A RESTING STATE, NOT A RETRY. The determination is a pure
  -- function of (task facts, executor, playbook), so the same verdict comes back every tick; the task
  -- moves to the state the verdict actually means and fn_workflow_step_claim stops picking it.
  if v_verdict not in ('published','approve') then
    if v_verdict = 'escalate' then
      update public.org_tasks
         set status = 'escalated', updated_at = now(),
             result = coalesce(result,'{}'::jsonb) || jsonb_build_object(
               'review', v_review || jsonb_build_object('queue_status', 'no queue row: the close did not complete'),
               'escalated', jsonb_build_object('at', now(), 'by', 'workflow_dispatch (org_task lane)',
                 'reason', coalesce(v_review->>'reason', 'the review chain could not resolve an available approver'),
                 'note', 'The determination was produced and stored; it is the REVIEW that could not '
                      || 'complete, because this department has no approver independent of the author. '
                      || 'That is an org finding, not a work failure, and it rests here rather than '
                      || 'being retried against the same chain every ten minutes.'))
       where id = p_task_id;
    else
      v_known := public.fn_org_task_lane_knowledge(t.dept_key);
      update public.org_tasks
         set status = 'blocked', updated_at = now(),
             result = coalesce(result,'{}'::jsonb) || jsonb_build_object(
               'review', v_review || jsonb_build_object('queue_status', 'no queue row: the close did not complete'),
               'parked', jsonb_build_object('at', now(), 'by', 'workflow_dispatch (org_task lane)',
                 'reason', 'the review returned ' || v_verdict,
                 'violations', coalesce(v_review->'violations','[]'::jsonb),
                 'knowledge_at_park', v_known,
                 'note', 'The deterministic determination did not meet the org_task quality standard. '
                      || 'The determination is a pure function of this task''s facts and the playbook applied, so '
                      || 'another attempt returns the same verdict; what has to change is the KNOWLEDGE or the facts. '
                      || 'fn_org_task_promote re-opens this when the department holds more actionable '
                      || 'in-scope knowledge than the ' || v_known || ' records it held here.'))
       where id = p_task_id;
    end if;

    -- THE RUN IS THE EMPLOYEE'S: 'ok' when the verdict is an org finding (escalate: no approver),
    -- 'rejected' when the determination itself failed review. Never 'error': fn_watch_failed_runs pages
    -- the founder on error rows and nothing here is an outage.
    insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
    values (v_employee, now(), now(), case when v_verdict = 'escalate' then 'ok' else 'rejected' end,
            jsonb_build_object('org_task_id', p_task_id, 'lane', 'org_task', 'review_outcome', v_verdict,
                               'workflow_step_run_id', p_step_run_id, 'used_llm', v_used_llm,
                               'disposition', v_disp, 'executor_status', v_exec_status, 'action_execution_id', v_exec_id),
            left('org_task ' || p_task_id || ' determined from ' || v_bound || ' fact(s) and playbook ' || coalesce(v_pb_title,'')
                 || '; review returned ' || v_verdict || ' and the task rests as '
                 || case when v_verdict = 'escalate' then 'escalated' else 'blocked' end, 500));

    return jsonb_build_object('ok', false, 'terminal', true, 'review_outcome', v_verdict,
             'reason', 'review returned ' || v_verdict
               || coalesce(': ' || left((v_review->'violations')::text, 300), '')
               || '; the org_task now rests as '
               || case when v_verdict = 'escalate' then 'escalated' else 'blocked' end
               || ' and is not retried',
             'review', v_review, 'disposition', v_disp, 'executor_status', v_exec_status, 'action_execution_id', v_exec_id);
  end if;

  -- The sealed record of what was decided, on what, by which rule, with what confidence.
  insert into public.decision_trace(
      correlation_id, entity_type, entity_id, decision_type,
      proposed_by, decided_by, policy_keys, knowledge_refs, evidence_refs, alternatives,
      assumptions, risk, confidence, authority_result,
      decision, outcome_status, agent_key, department_id, task_class,
      knowledge_versions, source_freshness, tools_requested, tools_executed, tool_result_refs,
      uncertainty, escalation_decision, proposed_action, expected_outcome,
      model, provider, input_tokens, output_tokens, estimated_cost_aed, final_status, sealed_at)
  values (
      gen_random_uuid(), 'org_task', p_task_id::text, 'deterministic_playbook_application',
      v_employee, 'fn_org_task_deterministic_done', array['deterministic_first','org_task_lane']::text[],
      jsonb_build_array(jsonb_build_object('record_id', v_pb_id, 'title', v_pb_title, 'record_type', v_pb_type,
                                           'similarity', v_sim, 'terms_matched', v_terms, 'terms_total', v_total)),
      jsonb_build_array(jsonb_build_object('org_task_id', p_task_id, 'dept_key', t.dept_key,
                                           'title', t.title, 'action_class', t.action_class,
                                           'workflow_step_run_id', p_step_run_id,
                                           'facts', v_facts, 'review', v_review)),
      coalesce(p_output->'candidates', '[]'::jsonb),
      jsonb_build_array('the nearest CORROBORATED actionable company record is the applicable one for this task',
                        'the facts read at close time are the facts the task is about'),
      jsonb_build_object('level', 'low', 'note', case when v_source like 'executor:%'
                                                      then 'a low-risk, advisory-safe, reversible executor was invoked; moves no money, sends nothing, approves nobody'
                                                      else 'determination only; moves no money, sends nothing, approves nobody' end),
      v_sim,
      jsonb_build_object('mode', v_mode, 'tier', t.tier, 'paid_provider', 'held', 'executor', v_exec_status),
      jsonb_build_object('determination', left(v_deliv, 8000), 'outcome', left(v_outcome, 400), 'disposition', v_disp,
                         'determination_source', v_source, 'basis', 'facts of the task rendered against the corroborated record; no model call'),
      'pending', v_employee, t.dept_key, 'org_task',
      '{}'::jsonb, jsonb_build_object('ops_knowledge', 'live at decision time', 'facts_read_at', v_facts->>'read_at'),
      case when v_target is not null then array[v_target] else '{}'::text[] end,
      case when v_source like 'executor:%' then array[v_target] else '{}'::text[] end,
      case when v_exec_id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('action_execution_id', v_exec_id)) end,
      case v_disp when 'determined' then 'determined from ' || v_bound || ' bound fact(s); queued for review'
                  when 'advisory_held_model' then 'determined from ' || v_bound || ' bound fact(s), but the task''s executor needs the held model; advisory until the hold lifts'
                  else 'no fact bound: the record applies as written; narrative is needed' end,
      'review_queued', 'close the org_task with disposition ' || v_disp,
      'the mirroring employee_task run closes with it; a reviewer can overturn the determination',
      'none', 'deterministic', 0, 0, 0, 'auto_done', now())
  returning id into v_trace;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values (v_employee, now(), now(), 'ok',
          jsonb_build_object('org_task_id', p_task_id, 'lane', 'org_task', 'review_outcome', v_verdict,
                             'decision_trace_id', v_trace, 'workflow_step_run_id', p_step_run_id,
                             'playbook_record_id', v_pb_id, 'similarity', v_sim, 'used_llm', v_used_llm,
                             'disposition', v_disp, 'facts_bound', v_bound, 'executor_status', v_exec_status,
                             'action_execution_id', v_exec_id),
          left('org_task ' || p_task_id || ' determined from ' || v_bound || ' fact(s) and playbook ' || coalesce(v_pb_title,'')
               || ' (cosine ' || v_sim || ', corroborated ' || v_terms || '/' || v_total || '); executor '
               || split_part(coalesce(v_exec_status,'none'), ':', 1) || '; review chain ' || v_verdict, 500));

  -- Never a silent pass: the determination is queued for an independent reviewer, with everything
  -- needed to overturn it. The row is NOT decided here.
  insert into public.review_queue(kind, dept_key, title, summary, payload, status)
  values ('deterministic_org_task', t.dept_key,
          left(initcap(replace(v_disp, '_', ' ')) || ': org_task ' || p_task_id || ' — ' || coalesce(t.title,''), 240),
          left(v_outcome, 600),
          jsonb_build_object('org_task_id', p_task_id, 'dept_key', t.dept_key,
                             'workflow_step_run_id', p_step_run_id,
                             'employee', v_employee,
                             'playbook_record_id', v_pb_id, 'playbook_title', v_pb_title,
                             'similarity', v_sim, 'terms_matched', v_terms, 'terms_total', v_total,
                             'decision_trace_id', v_trace, 'review_chain', v_review,
                             'disposition', v_disp, 'determination_source', v_source,
                             'executor_status', v_exec_status, 'action_execution_id', v_exec_id,
                             'facts_bound', v_bound, 'used_llm', v_used_llm),
          'pending')
  returning id into v_queue;

  update public.org_tasks
     set status     = 'done',
         updated_at = now(),
         result     = coalesce(result,'{}'::jsonb) || jsonb_build_object(
                        'review', v_review || jsonb_build_object('queue_status', 'pending', 'review_queue_id', v_queue),
                        'decision_trace_id', v_trace,
                        'review_queue_id', v_queue,
                        'review_queue_status', 'pending',
                        'disposition', v_disp)
   where id = p_task_id;

  return jsonb_build_object('ok', true, 'org_task_id', p_task_id, 'review_outcome', v_verdict,
                            'review', jsonb_build_object('chain_outcome', v_verdict, 'queue_status', 'pending', 'review_queue_id', v_queue),
                            'decision_trace_id', v_trace, 'review_queue_id', v_queue,
                            'disposition', v_disp, 'determination_source', v_source,
                            'executor_status', v_exec_status, 'action_execution_id', v_exec_id,
                            'facts_bound', v_bound, 'used_llm', v_used_llm, 'root_cause', v_rc);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_org_task_done_needs_a_determination()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.status = 'done' and (tg_op = 'INSERT' or coalesce(old.status, '') <> 'done') then
    if coalesce(btrim(new.result->>'deliverable'), '') = '' or coalesce(btrim(new.decided_by), '') = '' then
      raise exception
        'org_tasks #% (%) cannot close to done without a determination: % — a task is done when it carries '
        'result.deliverable (what was determined or resolved) and decided_by (who decided it). Close it through '
        'the spine (fn_org_task_deterministic_done: playbook, review, decision_trace) or, for a recorded fact such '
        'as a resolved incident, through fn_org_task_close_as_fact(task, resolver, resolution). A bare status flip '
        'is the second closing path this guard exists to refuse.',
        new.id, left(coalesce(new.title, ''), 70),
        case when coalesce(btrim(new.result->>'deliverable'), '') = '' and coalesce(btrim(new.decided_by), '') = ''
             then 'no deliverable and no decided_by'
             when coalesce(btrim(new.result->>'deliverable'), '') = '' then 'no deliverable'
             else 'no decided_by' end
        using errcode = 'check_violation';
    end if;
  end if;
  return new;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_org_task_facts(p_task_id bigint, p_step_run_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t record;
  v_bound int := 0;
  v_obj jsonb := null;
  v_events jsonb := '[]'::jsonb; v_deliveries int := 0;
  v_entity_type text; v_entity_id text; v_event_type text;
  v_kpi jsonb := null; v_kpi_metric text; v_kpi_owner text;
  k record; v_prev numeric; v_prev_on date; v_missed14 int := 0; v_met14 int := 0;
  v_att numeric; v_band text; v_cause text; v_cause_why text; v_att_source text;
  v_depts text[]; v_dept jsonb := null;
  v_kpi_rows int := 0; v_kpi_measured int := 0; v_kpi_met int := 0; v_kpi_missed int := 0; v_worst jsonb;
  v_sc_rows int := 0; v_sc_off int := 0; v_sc_list jsonb;
  v_hist jsonb; v_rq jsonb; v_rc_n int := 0; v_rc_last text; v_dt_n int := 0;
  v_step jsonb := null; v_step_bound int := 0;
  v_derived jsonb;
begin
  select o.id, o.dept_key, o.title, o.detail, o.action_class, o.tier, o.priority, o.status, o.assigned_agent,
         coalesce(o.attempts, 0) as attempts, o.created_at, o.updated_at, o.root_cause, o.needs_founder,
         o.objective_id, coalesce(o.result, '{}'::jsonb) as result, o.decided_by
    into t from public.org_tasks o where o.id = p_task_id;
  if not found then return null; end if;

  -- THE OBJECTIVE the task serves
  if t.objective_id is not null then
    select jsonb_strip_nulls(jsonb_build_object('id', d.id, 'objective', d.objective, 'goal_key', d.goal_key,
             'horizon', d.horizon, 'status', d.status, 'target_value', d.target_value, 'unit', d.unit,
             'actual_value', d.actual_value, 'measured_at', d.measured_at))
      into v_obj from public.department_objective d where d.id = t.objective_id;
    if v_obj is not null then v_bound := v_bound + 1; end if;
  end if;

  -- THE EVENTS it was minted from (event_delivery is the provenance; decided_by is overwritten at close)
  select count(*) into v_deliveries from public.event_delivery ed where ed.task_id = t.id;
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'event_id', ce.id, 'event_type', ce.event_type, 'entity_type', ce.entity_type, 'entity_id', ce.entity_id,
           'actor', ce.actor, 'occurred_at', ce.occurred_at, 'delivered_to', ed.agent_key,
           'payload', coalesce(ce.payload, '{}'::jsonb))) order by ce.occurred_at desc), '[]'::jsonb)
    into v_events
    from (select * from public.event_delivery ed where ed.task_id = t.id order by ed.delivered_at desc limit 5) ed
    join public.company_event ce on ce.id = ed.event_id;
  v_bound := v_bound + jsonb_array_length(v_events)
             + (select count(*) from jsonb_array_elements(v_events) e, jsonb_each(e->'payload') p
                 where jsonb_typeof(p.value) in ('string','number','boolean'))::int;

  -- THE ENTITY it is about: the newest event's, else parsed from the bus title "<type> on <entity_type> <id>"
  if jsonb_array_length(v_events) > 0 then
    v_event_type  := v_events->0->>'event_type';
    v_entity_type := v_events->0->>'entity_type';
    v_entity_id   := v_events->0->>'entity_id';
  else
    v_event_type  := substring(t.title from '^(?:ZZ DEMO\s*[—-]?\s*)?([a-z_]+\.[a-z_]+) on ');
    v_entity_type := substring(t.title from ' on ([a-z_]+) ');
    v_entity_id   := substring(t.title from ' on [a-z_]+ (\S+)\s*$');
  end if;

  -- THE KPI ROW a "KPI missed: <metric> (<owner>)" task is about, live
  if t.title ~* 'KPI missed: ' then
    v_kpi_metric := substring(t.title from 'KPI missed: (.+) \([a-z0-9_]+\)\s*$');
    v_kpi_owner  := substring(t.title from 'KPI missed: .+ \(([a-z0-9_]+)\)\s*$');
    select e.id, e.metric, e.target_value, e.actual_value, e.unit, e.cadence, e.serves_goal, e.measured_at,
           e.no_measure_reason, e.kpi_class
      into k
      from public.employee_kpi e
     where e.agent_key = v_kpi_owner and e.metric = v_kpi_metric
     order by e.active desc, e.measured_at desc nulls last limit 1;
    if found then
      select h.actual_value, h.measured_on into v_prev, v_prev_on
        from public.employee_kpi_history h
       where h.kpi_id = k.id and (k.measured_at is null or h.measured_at < k.measured_at - interval '1 hour')
       order by h.measured_at desc limit 1;
      select count(*) filter (where h.verdict = 'MISSED'), count(*) filter (where h.verdict = 'MET')
        into v_missed14, v_met14
        from public.employee_kpi_history h
       where h.kpi_id = k.id and h.measured_on >= current_date - 14;
      v_att := case when k.actual_value is null or k.target_value is null then null
                    when k.unit in ('percent_max', 'minutes') or k.unit ilike '%max%' then
                         case when k.actual_value > 0 then round(100 * k.target_value / k.actual_value, 1) else 100 end
                    when k.target_value > 0 then round(100 * k.actual_value / k.target_value, 1)
                    when k.actual_value <= 0 then 100 else null end;
      v_att_source := 'employee_kpi live (' || coalesce(k.measured_at::text, 'never measured') || ')';
      v_kpi := jsonb_strip_nulls(jsonb_build_object(
                 'kpi_id', k.id, 'owner', v_kpi_owner, 'metric', k.metric, 'target', k.target_value, 'actual', k.actual_value,
                 'unit', k.unit, 'cadence', k.cadence, 'serves_goal', k.serves_goal, 'measured_at', k.measured_at,
                 'no_measure_reason', k.no_measure_reason, 'kpi_class', k.kpi_class,
                 'previous_value', v_prev, 'previous_on', v_prev_on,
                 'missed_verdicts_14d', v_missed14, 'met_verdicts_14d', v_met14, 'attainment_pct', v_att));
      v_bound := v_bound + (k.actual_value is not null)::int + (k.target_value is not null)::int
                 + (v_prev is not null)::int + ((v_missed14 + v_met14) > 0)::int;
    end if;
    if v_att is null then
      -- the minter wrote "actual X (Y% of target)" into the detail; it is a fact of the task even without a live row
      v_att := nullif(substring(coalesce(t.detail,'') from '\(([0-9]+(?:\.[0-9]+)?)% of target\)'), '')::numeric;
      if v_att is not null then
        v_att_source := 'task detail as written by fn_kpi_review';
        v_bound := v_bound + 1;
      end if;
    end if;
    v_band := case when v_att is null then 'UNMEASURED'
                   when v_att >= 100 then 'ON_TARGET'
                   when v_att >= 70 then 'BEHIND'
                   else 'OFF_TARGET' end;
    if k.no_measure_reason is not null then
      v_cause := 'INSTRUMENT'; v_cause_why := 'employee_kpi.no_measure_reason: ' || k.no_measure_reason;
    elsif v_att is null then
      v_cause := 'INSTRUMENT'; v_cause_why := 'no attainment figure on the row or in the task: the variance class cannot be read';
    elsif v_att >= 100 then
      v_cause := 'NONE'; v_cause_why := 'attainment ' || v_att || '% is at or above target, so the miss is in how the metric is measured or dated, not in the work';
    elsif v_att < 5 then
      v_cause := 'EXECUTION'; v_cause_why := 'no throughput: attainment ' || v_att || '% means the input that feeds this metric has not started, not that it under-performed';
    elsif v_att < 50 then
      v_cause := 'EXECUTION'; v_cause_why := 'capacity or conversion shortfall: attainment ' || v_att || '% is real activity falling well short of the target';
    elsif v_met14 = 0 and v_missed14 >= 3 then
      v_cause := 'TARGET_MIS_SET'; v_cause_why := 'near-miss at ' || v_att || '% with ' || v_missed14 || ' MISSED and 0 MET verdicts in 14 days: the target sits above what the process currently reaches';
    else
      v_cause := 'EXECUTION'; v_cause_why := 'near-miss at ' || v_att || '% (' || v_missed14 || ' MISSED / ' || v_met14 || ' MET verdicts in 14 days): execution against a target the process has reached before';
    end if;
  end if;

  -- THE DEPARTMENT'S LIVE NUMBERS (the same sources fn_workflow_step_facts / fn_recommend_deterministic read)
  select coalesce(array_agg(d.dept_key), array[t.dept_key]) into v_depts
    from public.org_departments d where d.merged_into = t.dept_key or d.dept_key = t.dept_key;
  with kp as (
    select e.id, e.agent_key, e.metric, e.target_value, e.actual_value, e.unit,
           (select h.verdict from public.employee_kpi_history h where h.kpi_id = e.id order by h.measured_at desc limit 1) verdict,
           (select h.attainment from public.employee_kpi_history h where h.kpi_id = e.id order by h.measured_at desc limit 1) attainment
      from public.employee_kpi e join public.org_agents a on a.agent_key = e.agent_key
     where e.active and a.department = t.dept_key)
  select count(*), count(*) filter (where actual_value is not null),
         count(*) filter (where verdict = 'MET'), count(*) filter (where verdict = 'MISSED'),
         (select jsonb_agg(jsonb_build_object('owner', agent_key, 'metric', metric, 'actual', actual_value, 'target', target_value,
                                              'unit', unit, 'attainment_pct', attainment))
            from (select * from kp where verdict = 'MISSED' and attainment is not null order by attainment asc limit 3) w)
    into v_kpi_rows, v_kpi_measured, v_kpi_met, v_kpi_missed, v_worst
    from kp;
  select count(*), count(*) filter (where sc.state is distinct from 'ON_TARGET'),
         (select jsonb_agg(jsonb_build_object('label', s2.label, 'metric_key', s2.metric_key, 'value', s2.value, 'target', s2.target,
                                              'state', s2.state, 'error', s2.error) order by s2.state, s2.label)
            from (select * from public.v_bi_scorecard s2 where s2.owner_dept = any(v_depts) and s2.state is distinct from 'ON_TARGET'
                  order by s2.state, s2.label limit 6) s2)
    into v_sc_rows, v_sc_off, v_sc_list
    from public.v_bi_scorecard sc where sc.owner_dept = any(v_depts);
  v_dept := jsonb_strip_nulls(jsonb_build_object(
              'dept_key', t.dept_key, 'crosswalk', to_jsonb(v_depts),
              'kpi_rows', v_kpi_rows, 'kpi_measured', v_kpi_measured, 'kpi_met', v_kpi_met, 'kpi_missed', v_kpi_missed,
              'worst_missed', v_worst,
              'scorecard_rows', v_sc_rows, 'scorecard_off_target', v_sc_off, 'scorecard_off_target_list', v_sc_list));
  v_bound := v_bound + (v_kpi_measured > 0)::int + (v_sc_rows > 0)::int;

  -- PRIOR ATTEMPTS AND REVIEWS on this row
  select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'kind', q.kind, 'status', q.status, 'decided_by', q.decided_by,
                                               'created_at', q.created_at) order by q.created_at desc), '[]'::jsonb)
    into v_rq
    from (select * from public.review_queue q where q.payload->>'org_task_id' = t.id::text order by q.created_at desc limit 5) q;
  select count(*), max(rc.stage || '/' || rc.decision || ' by ' || rc.reviewer_agent) into v_rc_n, v_rc_last
    from public.review_chain rc where rc.subject_type = 'org_task' and rc.subject_id = t.id::text;
  select count(*) into v_dt_n from public.decision_trace d where d.entity_type = 'org_task' and d.entity_id = t.id::text;
  v_hist := jsonb_strip_nulls(jsonb_build_object(
              'attempts', t.attempts, 'decided_by_before', t.decided_by, 'root_cause_before', t.root_cause,
              'parked', t.result->'parked', 'previously_parked', t.result->'previously_parked',
              'held', t.result->'held', 'escalated', t.result->'escalated',
              'prior_review_chain_outcome', t.result->'review'->>'outcome',
              'review_queue_rows', v_rq, 'review_chain_rows', v_rc_n, 'review_chain_last', v_rc_last,
              'decision_traces', v_dt_n));
  v_bound := v_bound + (t.attempts > 0)::int + (v_rc_n > 0)::int + (jsonb_array_length(v_rq) > 0)::int;

  -- THE STEP'S FACTS when the lane's run has a step_run (a trigger event and its metric, when any)
  if p_step_run_id is not null then
    v_step := public.fn_workflow_step_facts(p_step_run_id);
    if v_step is not null then
      v_step_bound := coalesce((v_step->>'facts_bound')::int, 0);
      v_step := v_step - 'context' - 'read_at';
      v_bound := v_bound + v_step_bound;
      if v_band is null and v_step#>>'{derived,band}' is not null then
        v_band := v_step#>>'{derived,band}'; v_cause := v_step#>>'{derived,cause}'; v_cause_why := v_step#>>'{derived,cause_evidence}';
      end if;
    end if;
  end if;

  v_derived := jsonb_strip_nulls(jsonb_build_object(
    'band', v_band, 'attainment_pct', v_att, 'attainment_source', v_att_source,
    'cause', v_cause, 'cause_evidence', v_cause_why,
    'event_type', v_event_type, 'entity_type', v_entity_type, 'entity_id', v_entity_id,
    'recurrence', v_deliveries, 'days_open', round(extract(epoch from (now() - t.created_at)) / 86400.0, 1),
    'dept_kpi_attainment_pct', case when v_kpi_met + v_kpi_missed > 0 then round(100.0 * v_kpi_met / (v_kpi_met + v_kpi_missed), 1) end,
    'dept_scorecard_off_target', v_sc_off));

  return jsonb_strip_nulls(jsonb_build_object(
    'task', jsonb_build_object('id', t.id, 'dept_key', t.dept_key, 'title', t.title, 'detail', left(coalesce(t.detail,''), 2000),
                               'action_class', t.action_class, 'tier', t.tier, 'priority', t.priority, 'status', t.status,
                               'assigned_agent', t.assigned_agent, 'needs_founder', t.needs_founder, 'created_at', t.created_at),
    'objective', v_obj,
    'events', v_events, 'deliveries_total', v_deliveries,
    'entity', case when v_entity_type is null then null else jsonb_build_object('type', v_entity_type, 'id', v_entity_id) end,
    'kpi', v_kpi,
    'department', v_dept,
    'history', v_hist,
    'step_facts', v_step,
    'derived', v_derived,
    'facts_bound', v_bound,
    'read_at', now()));
end
$function$


CREATE OR REPLACE FUNCTION public.fn_org_task_fill_ownership()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_pick text; v_obj bigint; v_text text;
  REVIEW_CLASSES constant text[] := array['review','audit','verify','qa_gate','security_review',
    'compliance_check','legal_review','supplier_verify','capability_review','self_review'];
begin
  -- OBJECTIVE: the live department objective this task serves.
  if new.objective_id is null and coalesce(new.dept_key,'') <> '' then
    v_text := lower(coalesce(new.title,'')||' '||coalesce(new.detail,''));
    select o.id into v_obj
      from public.department_objective o
     where o.active and o.status='active' and o.dept_key = new.dept_key
       and coalesce(o.goal_key,'') <> ''
       and v_text ~ ('\y'||o.goal_key||'\y')
     order by length(o.goal_key) desc, o.id
     limit 1;
    if v_obj is null then
      -- DEFAULT: a department's work serves its PRIMARY active objective unless its text names
      -- another. This replaced 'exactly one objective', which never fired (every department has
      -- several) and left the spine empty. Measurable objectives are preferred for the default.
      select o.id into v_obj
        from public.department_objective o
       where o.active and o.status='active' and o.dept_key = new.dept_key
       order by (coalesce(o.measure_sql,'') <> '') desc, o.sort, o.id
       limit 1;
    end if;
    new.objective_id := v_obj;
  end if;

  -- OWNER: a task born as real work gets the least-loaded eligible colleague in its department.
  if new.assigned_agent is null and coalesce(new.status,'') in ('assigned','in_progress')
     and coalesce(new.dept_key,'') <> '' then
    select a.agent_key into v_pick
      from public.org_agents a
      left join public.agent_reputation p on p.agent_key = a.agent_key
      left join public.org_role rr on rr.runtime_agent_key = a.agent_key and rr.status='active'
     where a.active and coalesce(a.available,true)
       and (a.unavailable_until is null or a.unavailable_until < now())
       and a.department = new.dept_key
       and (coalesce(rr.runtime_mode,'on_demand_specialist') <> 'independent_reviewer'
            or coalesce(new.action_class,'') = any(REVIEW_CLASSES))
       and (select count(*) from public.org_tasks o
             where o.assigned_agent = a.agent_key
               and o.status in ('assigned','in_progress')) < coalesce(a.max_open_tasks,6)
     order by case when p.tier='probation' then 1 else 0 end,
              (select count(*) from public.org_tasks o
                where o.assigned_agent = a.agent_key and o.status in ('assigned','in_progress')),
              a.agent_key
     limit 1;
    new.assigned_agent := v_pick;   -- may remain null if the department is saturated
  end if;

  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_org_task_incident_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.status='in_progress' and coalesce(old.status,'') <> 'in_progress' then
    update public.os_incidents set acknowledged_at = now()
     where org_task_id = new.id and acknowledged_at is null;
  elsif new.status='done' and coalesce(old.status,'') <> 'done' then
    update public.os_incidents
       set status='resolved', resolved_at=coalesce(resolved_at, now()),
           resolution=coalesce(resolution, 'Linked task '||new.id||' completed')
     where org_task_id = new.id and status='open';
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_org_task_lane_knowledge(p_dept text)
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select count(*)::int
    from public.ops_knowledge k
   where k.runtime_eligible
     and k.supersession_state = 'current'
     and k.embedding_gte is not null
     and k.record_type in ('decision_playbook','decision_rule','standard_operating_procedure','exception_playbook')
     and (k.scope_type in ('company','external_source')
          or (k.scope_type = 'department' and k.dept_key = any(public.fn_dept_scope(coalesce(p_dept,'exec')))));
$function$


CREATE OR REPLACE FUNCTION public.fn_org_task_promote(p_limit integer DEFAULT 12, p_in_flight_ceiling integer DEFAULT 60)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r record; v_run uuid;
  v_unparked int := 0; v_promoted int := 0; v_in_flight int; v_room int; v_backlog int;
  v_reopened_cos int := 0; v_reopened_head int := 0; v_held int := 0;
begin
  -- 1. a park heals when the company learns something
  for r in
    select t.id, t.dept_key, coalesce((t.result->'parked'->>'knowledge_at_park')::int, 0) was
      from public.org_tasks t
     where t.status = 'blocked' and (t.result ? 'parked')
     order by t.id
     limit 200
  loop
    if public.fn_org_task_lane_knowledge(r.dept_key) > r.was then
      update public.org_tasks
         set status = 'assigned', updated_at = now(),
             result = coalesce(result,'{}'::jsonb) || jsonb_build_object(
               'unparked', jsonb_build_object('at', now(),
                 'knowledge_at_park', r.was,
                 'knowledge_now', public.fn_org_task_lane_knowledge(r.dept_key),
                 'reason', 'the department now holds more actionable in-scope knowledge than when this parked'))
       where id = r.id;
      update public.workflow_step_run sr
         set status = 'ready', attempts = 0, error = null
        from public.workflow_run wr
       where wr.id = sr.workflow_run_id and wr.workflow_key = 'employee_task'
         and wr.context->>'task_id' = r.id::text
         and sr.finished_at is null
         and coalesce(sr.error->>'disposition','') = 'awaiting_model';
      v_unparked := v_unparked + 1;
    end if;
  end loop;

  -- 2. the retired executor's outages are not verdicts
  update public.org_tasks t
     set status = 'assigned', updated_at = now(),
         attempts = 0,
         result = coalesce(t.result,'{}'::jsonb) || jsonb_build_object(
           'reopened', jsonb_build_object('at', now(), 'by', 'fn_org_task_promote',
             'from', 'escalated', 'previous_attempts', coalesce(t.attempts, 0),
             'previous_decided_by', t.decided_by,
             'reason', 'escalated by cos_execute (retired 3 Sep 2026) after its model call failed; '
                    || 'that was the executor''s outage, not a verdict on the task. It re-enters the '
                    || 'deterministic org_task lane, which determines it from company knowledge or parks it with a reason'))
   where t.status = 'escalated'
     and t.decided_by = 'cos'
     and not (coalesce(t.result,'{}'::jsonb) ? 'escalated')
     and not (coalesce(t.result,'{}'::jsonb) ? 'reopened');
  get diagnostics v_reopened_cos = row_count;

  -- 3. no approver because the head authored it: re-enter unowned, a colleague will author it
  update public.org_tasks t
     set status = 'assigned', updated_at = now(), assigned_agent = null,
         result = coalesce(t.result,'{}'::jsonb) || jsonb_build_object(
           'reopened', jsonb_build_object('at', now(), 'by', 'fn_org_task_promote',
             'from', 'escalated', 'previous_author', t.assigned_agent,
             'reason', 'the review chain had no approver because the department head (' || t.assigned_agent
                    || ', who has no manager) authored the work; re-entered unowned so that a colleague the '
                    || 'head can review performs it'))
    from public.org_departments d
   where d.dept_key = t.dept_key
     and t.status = 'escalated'
     and (t.result ? 'escalated')
     -- who AUTHORED it, as the review recorded — a task claimed while unowned resolves to the head too
     and coalesce(t.result->'review'->>'author', t.assigned_agent) = d.lead_agent
     -- once per escalation: a task claimed while it was still on the head can escalate again after
     -- its first re-open, and that later verdict is re-examined too — never a loop, because a task
     -- the assigner has re-homed no longer carries the head as its assignee
     and coalesce((t.result->'reopened'->>'at')::timestamptz, '-infinity'::timestamptz)
         < coalesce((t.result->'escalated'->>'at')::timestamptz, now())
     and not exists (select 1 from public.org_agents h
                      join public.org_agents m on m.agent_key = h.manager_key and m.active
                     where h.agent_key = d.lead_agent)
     and exists (select 1 from public.org_agents b
                  left join public.org_role rb on rb.runtime_agent_key = b.agent_key and rb.status = 'active'
                 where b.active and coalesce(b.available, true) and b.department = d.dept_key
                   and b.agent_key <> d.lead_agent
                   and coalesce(rb.runtime_mode, 'on_demand_specialist') <> 'independent_reviewer');
  get diagnostics v_reopened_head = row_count;

  -- 4. a held proposal says on the row why it is held
  update public.org_tasks t
     set result = coalesce(t.result,'{}'::jsonb) || jsonb_build_object(
           'held', jsonb_build_object('at', now(), 'by', 'fn_task_approve', 'reason', h.reason, 'decided_at', h.created_at))
    from (select distinct on (rc.subject_id) rc.subject_id, rc.reason, rc.created_at
            from public.review_chain rc
           where rc.subject_type = 'org_task' and rc.stage = 'approval' and rc.decision = 'hold'
           order by rc.subject_id, rc.created_at desc) h
   where t.status = 'proposed'
     and h.subject_id = t.id::text
     and coalesce(t.result->'held'->>'reason', '') is distinct from h.reason;
  get diagnostics v_held = row_count;

  select count(*) into v_in_flight
    from public.workflow_run wr where wr.workflow_key = 'employee_task' and wr.status = 'running';
  v_room := greatest(least(coalesce(p_limit, 12), coalesce(p_in_flight_ceiling, 60) - v_in_flight), 0);

  select count(*) into v_backlog
    from public.org_tasks t
   where t.status in ('assigned','in_progress')
     -- a RUNNING run, not any run: a task re-opened after an escalation keeps its earlier (failed) run
     -- and needs a new one — measured 5 Sep: 18 re-opened exec tasks sat unpromoted behind this predicate
     and not exists (select 1 from public.workflow_run wr
                      where wr.workflow_key = 'employee_task' and wr.context->>'task_id' = t.id::text
                        and wr.status = 'running');

  if v_room > 0 then
    for r in
      select t.id, t.dept_key
        from public.org_tasks t
       where t.status in ('assigned','in_progress')
         and coalesce(t.needs_founder, false) = false
         and exists (select 1 from public.org_agents a where a.agent_key = t.assigned_agent and a.active)
         and not exists (select 1 from public.workflow_run wr
                          where wr.workflow_key = 'employee_task' and wr.context->>'task_id' = t.id::text
                            and wr.status = 'running')
       order by t.priority desc nulls last, t.created_at, t.id
       limit v_room
    loop
      begin
        v_run := public.fn_workflow_start('employee_task', null, 'org_task', r.id::text,
                   jsonb_build_object('task_id', r.id::text, 'dept_key', r.dept_key,
                                      'promoted_by', 'fn_org_task_promote',
                                      'promoted_at', now()));
        if v_run is not null then v_promoted := v_promoted + 1; end if;
      exception when others then
        -- 4 Sep 2026: two swallowed errors here hid a leg that never ran. A refusal is recorded ON THE
        -- TASK, in words, so the next census reads it instead of counting a healthy promoter.
        update public.org_tasks
           set result = coalesce(result,'{}'::jsonb) || jsonb_build_object(
                 'promotion_refused', jsonb_build_object('at', now(), 'sqlstate', sqlstate, 'error', left(sqlerrm, 400)))
         where id = r.id;
      end;
    end loop;
  end if;

  return jsonb_build_object('unparked', v_unparked, 'promoted', v_promoted,
                            'reopened_from_retired_executor', v_reopened_cos,
                            'reopened_head_authored', v_reopened_head,
                            'held_proposals_annotated', v_held,
                            'in_flight_before', v_in_flight, 'room', v_room,
                            'backlog_without_a_run', v_backlog, 'ran_at', now());
end
$function$


CREATE OR REPLACE FUNCTION public.fn_org_task_question_candidates(p_embedding vector, p_k integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'question', f.question) order by f.d), '[]'::jsonb)
    from (select f.id, f.question, f.embedding_gte <=> p_embedding as d
            from public.company_faq f
           where f.public and f.status = 'approved' and f.embedding_gte is not null
           order by f.embedding_gte <=> p_embedding
           limit greatest(1, least(coalesce(p_k, 8), 20))) f
$function$


CREATE OR REPLACE FUNCTION public.fn_org_task_question_reading_record(p_task_id bigint, p_question_md5 text, p_choice text, p_reasoned boolean, p_held_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_trade text; v_faq bigint; v_status text := case when p_reasoned then 'reasoned' else 'needs_reasoning' end;
begin
  if p_reasoned and left(p_choice, 6) = 'price:' then
    v_trade := substr(p_choice, 7);
    if not exists (select 1 from public.price_benchmark where category = v_trade) then
      raise exception 'not a published trade: %', v_trade using errcode = '22023';
    end if;
  elsif p_reasoned and left(p_choice, 4) = 'faq:' then
    v_faq := substr(p_choice, 5)::bigint;
    if not exists (select 1 from public.company_faq where id = v_faq and public and status = 'approved') then
      raise exception 'not an approved public faq: %', v_faq using errcode = '22023';
    end if;
  elsif p_reasoned and coalesce(p_choice, '') <> 'neither' then
    raise exception 'not an option: %', p_choice using errcode = '22023';
  end if;
  insert into public.org_task_question_reading as x (task_id, question_md5, trade, faq_id, status, held_id, reasoned_at, updated_at)
  values (p_task_id, p_question_md5, v_trade, v_faq, v_status, p_held_id, case when p_reasoned then now() end, now())
  on conflict (task_id) do update set question_md5 = excluded.question_md5, trade = excluded.trade, faq_id = excluded.faq_id,
    status = excluded.status, held_id = coalesce(excluded.held_id, x.held_id), reasoned_at = excluded.reasoned_at, updated_at = now()
  where not (excluded.status = 'needs_reasoning' and x.status = 'reasoned' and x.question_md5 = excluded.question_md5);
  return jsonb_build_object('task_id', p_task_id, 'status', v_status, 'trade', v_trade, 'faq_id', v_faq);
end $function$


CREATE OR REPLACE FUNCTION public.fn_org_task_questions_due(p_limit integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'trades', (select coalesce(jsonb_agg(distinct pb.category order by pb.category), '[]'::jsonb) from public.price_benchmark pb),
    'questions', coalesce((select jsonb_agg(jsonb_build_object('task_id', t.id, 'question', t.q, 'question_md5', md5(t.q)) order by t.id)
      from (select u.* from (select o.id, nullif(btrim(coalesce(substring(o.detail from 'QUESTION: ([^\n]+)'), '')), '') q
                               from public.org_tasks o
                              where o.status = 'assigned' and o.action_class = 'knowledge_gap') u
             where u.q is not null
               and not exists (select 1 from public.org_task_question_reading x where x.task_id = u.id and x.question_md5 = md5(u.q))
             order by u.id
             limit greatest(1, least(coalesce(p_limit, 3), 10))) t), '[]'::jsonb))
$function$


CREATE OR REPLACE FUNCTION public.fn_org_task_render(p_facts jsonb, p_title text, p_record_type text, p_content text, p_structured jsonb, p_executor_status text DEFAULT NULL::text, p_executor_output text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  f jsonb := coalesce(p_facts, '{}'::jsonb);
  d jsonb := coalesce(p_facts->'derived', '{}'::jsonb);
  tk jsonb := coalesce(p_facts->'task', '{}'::jsonb);
  kp jsonb := p_facts->'kpi';
  dp jsonb := p_facts->'department';
  h jsonb := coalesce(p_facts->'history', '{}'::jsonb);
  t text := '';
  sel text[]; k text; v jsonb; s text; x jsonb; n int := 0; lines text := '';
begin
  t := 'DETERMINATION — QuotesDone org_task #' || coalesce(tk->>'id', '?') || ' (' || coalesce(tk->>'dept_key', '?') || ', '
       || coalesce(tk->>'action_class', '?') || ', tier ' || coalesce(tk->>'tier', '?') || '): ' || coalesce(tk->>'title', '') || E'\n'
       || 'Decided by ' || coalesce(tk->>'assigned_agent', tk->>'dept_key', '?') || ' at ' || coalesce(f->>'read_at', '') || ' from '
       || coalesce(f->>'facts_bound', '0') || ' bound fact(s); no model call.' || E'\n\n';

  t := t || E'FACTS THIS TASK DECIDED FROM\n';
  t := t || '- the task: ' || coalesce(tk->>'detail', '(no detail)') || E'\n';
  t := t || '- open ' || coalesce(d->>'days_open', '?') || ' day(s), attempts before this one ' || coalesce(h->>'attempts', '0')
       || ', priority ' || coalesce(tk->>'priority', 'none') || E'\n';
  if f ? 'objective' then
    t := t || '- objective served: "' || coalesce(f#>>'{objective,objective}', '?') || '" (goal ' || coalesce(f#>>'{objective,goal_key}', 'none')
         || ', ' || coalesce(f#>>'{objective,status}', '?') || ', target ' || coalesce(f#>>'{objective,target_value}', 'null') || ' '
         || coalesce(f#>>'{objective,unit}', '') || ', actual ' || coalesce(f#>>'{objective,actual_value}', 'null')
         || case when f#>>'{objective,measured_at}' is not null then ' measured ' || (f#>>'{objective,measured_at}') else '' end || ')' || E'\n';
  else
    t := t || E'- objective served: none linked on the row\n';
  end if;
  if jsonb_typeof(f->'events') = 'array' and jsonb_array_length(f->'events') > 0 then
    t := t || '- minted from ' || coalesce(f->>'deliveries_total', '?') || ' event delivery(ies); newest first:' || E'\n';
    for x in select * from jsonb_array_elements(f->'events') loop
      t := t || '    · ' || coalesce(x->>'event_type', '?') || ' on ' || coalesce(x->>'entity_type', '?') || ' ' || coalesce(x->>'entity_id', '?')
           || ' by ' || coalesce(x->>'actor', 'system') || ' at ' || coalesce(x->>'occurred_at', '?') || ' (event ' || coalesce(x->>'event_id', '?')
           || ') payload ' || left(coalesce((x->'payload')::text, '{}'), 700) || E'\n';
    end loop;
  elsif f ? 'entity' then
    t := t || '- about ' || coalesce(f#>>'{entity,type}', '?') || ' ' || coalesce(f#>>'{entity,id}', '?') || ' (from the title; no event_delivery row links this task to a company_event)' || E'\n';
  else
    t := t || E'- minted from: no company_event delivery on this task\n';
  end if;
  if kp is not null then
    t := t || '- the KPI: "' || coalesce(kp->>'metric', '?') || '" owned by ' || coalesce(kp->>'owner', '?') || ' (employee_kpi ' || coalesce(kp->>'kpi_id', '?')
         || '): actual ' || coalesce(kp->>'actual', 'null') || ' ' || coalesce(kp->>'unit', '') || ' against target ' || coalesce(kp->>'target', 'null')
         || ', cadence ' || coalesce(kp->>'cadence', '?') || ', serves ' || coalesce(kp->>'serves_goal', 'no goal')
         || ', measured ' || coalesce(kp->>'measured_at', 'never')
         || case when kp ? 'previous_value' then '; previous ' || (kp->>'previous_value') || ' on ' || coalesce(kp->>'previous_on', '?') else '; no earlier measurement' end
         || '; last 14 days ' || coalesce(kp->>'missed_verdicts_14d', '0') || ' MISSED / ' || coalesce(kp->>'met_verdicts_14d', '0') || ' MET'
         || case when kp ? 'no_measure_reason' then '; no_measure_reason: ' || (kp->>'no_measure_reason') else '' end || E'\n';
  elsif (tk->>'title') ~* 'KPI missed' then
    t := t || E'- the KPI: no employee_kpi row matches the owner and metric in the title; the task''s own numbers are used\n';
  end if;
  if dp is not null then
    t := t || '- the department ' || coalesce(dp->>'dept_key', '?') || ': ' || coalesce(dp->>'kpi_rows', '0') || ' active KPI(s), '
         || coalesce(dp->>'kpi_measured', '0') || ' measured, ' || coalesce(dp->>'kpi_met', '0') || ' MET / ' || coalesce(dp->>'kpi_missed', '0') || ' MISSED at the latest verdict'
         || case when d ? 'dept_kpi_attainment_pct' then ' (' || (d->>'dept_kpi_attainment_pct') || '% of verdicts met)' else '' end
         || '; scorecard ' || coalesce(dp->>'scorecard_rows', '0') || ' metric(s), ' || coalesce(dp->>'scorecard_off_target', '0') || ' not on target' || E'\n';
    if jsonb_typeof(dp->'worst_missed') = 'array' then
      for x in select * from jsonb_array_elements(dp->'worst_missed') loop
        t := t || '    · worst missed: ' || coalesce(x->>'metric', '?') || ' (' || coalesce(x->>'owner', '?') || ') ' || coalesce(x->>'actual', 'null')
             || '/' || coalesce(x->>'target', 'null') || ' ' || coalesce(x->>'unit', '') || ' = ' || coalesce(x->>'attainment_pct', '?') || '%' || E'\n';
      end loop;
    end if;
    if jsonb_typeof(dp->'scorecard_off_target_list') = 'array' then
      for x in select * from jsonb_array_elements(dp->'scorecard_off_target_list') loop
        t := t || '    · scorecard ' || coalesce(x->>'state', '?') || ': ' || coalesce(x->>'label', '?') || ' [' || coalesce(x->>'metric_key', '?') || '] value='
             || coalesce(x->>'value', 'null') || ' target=' || coalesce(x->>'target', 'null')
             || case when (x->>'error') is not null then ' ERROR=' || (x->>'error') else '' end || E'\n';
      end loop;
    end if;
  end if;
  if h ? 'review_chain_rows' and (h->>'review_chain_rows')::int > 0 then
    t := t || '- prior review: ' || (h->>'review_chain_rows') || ' review_chain row(s), last ' || coalesce(h->>'review_chain_last', '?')
         || '; ' || coalesce(jsonb_array_length(h->'review_queue_rows')::text, '0') || ' review_queue row(s); ' || coalesce(h->>'decision_traces', '0') || ' decision trace(s)' || E'\n';
  end if;
  if h ? 'parked' or h ? 'previously_parked' then
    t := t || '- previously parked: ' || left(coalesce((h->'parked')::text, (h->'previously_parked')::text), 400) || E'\n';
  end if;
  if h ? 'held' then t := t || '- previously held: ' || left((h->'held')::text, 300) || E'\n'; end if;
  if h ? 'escalated' then t := t || '- previously escalated: ' || left((h->'escalated')::text, 300) || E'\n'; end if;
  if f ? 'step_facts' and (f#>'{step_facts,trigger}') is not null then
    t := t || '- the run''s trigger: ' || coalesce(f#>>'{step_facts,trigger,event_type}', '?') || ' on ' || coalesce(f#>>'{step_facts,trigger,entity_type}', '?')
         || ' ' || coalesce(f#>>'{step_facts,trigger,entity_id}', '?') || ' payload ' || left(coalesce((f#>'{step_facts,trigger,payload}')::text, '{}'), 400) || E'\n';
  end if;
  if f ? 'step_facts' and (f#>'{step_facts,metric}') is not null then
    t := t || '- the run''s metric: ' || left((f#>'{step_facts,metric}')::text, 600) || E'\n';
  end if;

  t := t || E'\nDETERMINED\n';
  if d ? 'band' then
    t := t || '- variance: ' || coalesce(kp->>'metric', f#>>'{step_facts,metric,label}', tk->>'title') || ' is ' || (d->>'band')
         || case when d ? 'attainment_pct' then ' at ' || (d->>'attainment_pct') || '% attainment (' || coalesce(d->>'attainment_source', '?') || ')' else '' end || E'\n'
         || '- cause class: ' || coalesce(d->>'cause', 'not established') || ' — ' || coalesce(d->>'cause_evidence', '') || E'\n';
  end if;
  if coalesce((d->>'recurrence')::int, 0) > 1 then
    t := t || '- recurrence: ' || (d->>'recurrence') || ' deliveries of the same event landed on this one task; the condition is standing, not new' || E'\n';
  end if;
  t := t || '- executor: ' || coalesce(p_executor_status, 'none: no active executor is mapped to this action class') || E'\n';

  -- resolve keyed maps in structured_data at the facts
  sel := array_remove(array[d->>'band', d->>'cause', tk->>'action_class', d->>'event_type', d->>'entity_type', tk->>'tier', tk->>'dept_key',
                            lower(d->>'band'), lower(d->>'cause')], null);
  if p_structured is not null and jsonb_typeof(p_structured) = 'object' then
    for k, v in select * from jsonb_each(p_structured) loop
      if jsonb_typeof(v) = 'object' then
        foreach s in array coalesce(sel, '{}'::text[]) loop
          if v ? s then
            n := n + 1;
            lines := lines || '- ' || k || '[' || s || '] → ' || case when jsonb_typeof(v->s) = 'string' then v->>s else (v->s)::text end || E'\n';
          end if;
        end loop;
      end if;
    end loop;
  end if;
  if n > 0 then
    t := t || 'Selected from "' || coalesce(p_title, '?') || '" at the facts above (' || n || ' rule(s)):' || E'\n' || lines;
  else
    t := t || 'No keyed rule in "' || coalesce(p_title, '?') || '" resolves at these facts; the record applies as written below.' || E'\n';
  end if;

  if p_executor_output is not null then
    t := t || E'\nEXECUTOR OUTPUT (the work performed for this task)\n' || p_executor_output || E'\n';
  end if;

  t := t || E'\nAPPLIED RECORD: ' || coalesce(p_record_type, '?') || ' "' || coalesce(p_title, '?') || E'"\n' || coalesce(p_content, '');
  if p_structured is not null and p_structured <> '{}'::jsonb then
    t := t || E'\n\nSTRUCTURED DATA OF THE RECORD:\n' || jsonb_pretty(p_structured);
  end if;
  return t;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_org_task_root_cause_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_rc text;
begin
  if new.status = 'done' and coalesce(old.status, '') <> 'done'
     and new.title ilike 'KPI missed%' and coalesce(btrim(new.root_cause), '') = '' then

    v_rc := nullif(btrim(regexp_replace(
              coalesce(substring(coalesce(new.result ->> 'deliverable', '')
                                 from '(?i)root[-_ ]?cause[^\n]{0,250}'), ''),
              '\s+', ' ', 'g')), '');

    if v_rc is null then
      raise exception 'org_tasks #% (%) is a KPI-miss task and cannot close without root_cause: record the cause of the variance in org_tasks.root_cause, or state it under a "Root cause" heading in the deliverable and this trigger captures it.', new.id, left(new.title, 70);
    end if;

    new.root_cause := left(v_rc, 500);
  end if;
  return new;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_org_task_subject(p_title text, p_action_class text, p_dept_key text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select btrim(regexp_replace(
           regexp_replace(
             regexp_replace(
               regexp_replace(coalesce(p_title, ''),
                 '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', ' ', 'gi'),
               '[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?', ' ', 'g'),
             '\m[0-9]+\M', ' ', 'g'),
           '\s+', ' ', 'g'))
      || ' ' || coalesce(p_action_class, '')
      || ' ' || coalesce(p_dept_key, '');
$function$


CREATE OR REPLACE FUNCTION public.fn_originator_checks_delivery(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  a public.agent_actions; req public.agent_actions; n public.notifications; v_seat text; v_result text; v_seen jsonb;
  v_verdict text; v_phone text; v_email text; v_channel text; v_retry bigint; v_rep jsonb; v_origin bigint;
begin
  select * into a from public.agent_actions where id = p_id;
  v_seat := a.agent; v_result := a.detail->>'result';
  select * into req from public.agent_actions where id = (a.detail->>'request_id')::bigint;
  if req.id is null then return jsonb_build_object('closed', false, 'reason', 'the request this result answers is gone'); end if;

  select * into n from public.notifications
   where id = coalesce((req.detail->>'retry_notification_id')::bigint, (req.evidence->>'notification_id')::bigint);
  v_seen := jsonb_build_object('notification_id', n.id, 'status', n.status, 'channel', n.channel,
                               'provider_message_id', n.provider_message_id, 'sent_at', n.sent_at, 'checked_at', now(),
                               'provider_status', n.provider_status, 'provider_error_code', n.provider_error_code);

  if v_result in ('proof_of_response', 'no_response_confirmation') then
    v_verdict := 'handled_by_the_ladder';
  -- 22 Sep 2026: for WhatsApp and SMS the seat's own re-check also reads Twilio's delivery report; a SID
  -- alone is only Twilio's acceptance (every_whatsapp_says_whether_it_arrived.sql).
  elsif v_result = 'delivered' and n.status = 'sent' and coalesce(btrim(n.provider_message_id), '') <> ''
        and (coalesce(n.channel, 'email') not in ('whatsapp', 'sms') or n.provider_status in ('delivered', 'read')) then
    v_verdict := 'confirmed';
  -- 'held' and 'record_removed' close here (22 Sep 2026, UNSOLVED-06): a message the founder's own switch
  -- holds, and a queued row that was deleted afterwards, are both recorded rather than retried on the other
  -- channel and escalated to the CEO. Neither is a delivery the seat can correct.
  elsif v_result in ('routed', 'stubbed', 'digested', 'cancelled', 'held', 'record_removed') then
    v_verdict := v_result;
  end if;

  if v_verdict is null and v_result not in ('not_queued', 'sent_unconfirmed') and req.detail->'retry_of' is null
     and coalesce(req.detail->>'recipient_role', n.to_role) in ('customer', 'supplier') then
    -- THE OTHER CHANNEL, ONCE. Email that did not arrive goes to the number on file; WhatsApp that did
    -- not arrive goes to the address. A refused request (not_queued) is a defect, not a channel
    -- problem, and a send that may have left (sent_unconfirmed) is never sent twice: both escalate.
    v_email := coalesce(n.to_email, req.detail->>'to_email');
    if coalesce(n.channel, req.detail->'prepared'->>'channel', 'email') = 'whatsapp' then
      if coalesce(v_email, '') ~ '@' then v_channel := 'email'; end if;
    else
      -- 14 Sep 2026 (#322): the CONFIRMED WhatsApp number, else SMS on the verified mobile. This used to
      -- take leads.whatsapp (a scraped listing number) or any phone on file.
      v_phone := public.fn_whatsapp_destination(coalesce(req.detail->>'recipient_role', n.to_role), null,
                   coalesce((req.detail->>'supplier_id')::bigint, n.lead_id), v_email);
      if v_phone is not null then v_channel := 'whatsapp';
      else
        v_phone := public.fn_verified_mobile(coalesce(req.detail->>'recipient_role', n.to_role), null,
                     coalesce((req.detail->>'supplier_id')::bigint, n.lead_id), v_email);
        if v_phone is not null then v_channel := 'sms'; end if;
      end if;
    end if;
    if v_channel is not null and n.id is not null then
      v_retry := public.fn_seat_handoff(v_seat, 'customer_support', 'delivery.request', 'notifications', 'retry:' || req.id,
        jsonb_build_object('retry_of', req.id, 'msg_type', n.type, 'recipient_role', coalesce(n.to_role, req.detail->>'recipient_role'),
                           'to_email', v_email, 'supplier_id', coalesce(req.detail->'supplier_id', to_jsonb(n.lead_id)),
                           'inquiry_id', n.inquiry_id, 'quote_id', n.quote_id,
                           'prepared', jsonb_build_object('type', n.type, 'kind', n.kind, 'to_role', n.to_role, 'lead_id', n.lead_id,
                                                          'inquiry_id', n.inquiry_id, 'quote_id', n.quote_id, 'subject', n.subject,
                                                          'body', n.body, 'lang', n.lang, 'channel', v_channel,
                                                          'to_email', case when v_channel = 'email' then v_email else n.to_email end,
                                                          'to_phone', case when v_channel in ('whatsapp', 'sms') then v_phone end)));
      v_verdict := 'retried_on_' || v_channel;
    end if;
  end if;

  if v_verdict is null then
    v_rep := public.fn_support_report_to_ceo(
      'delivery_undelivered:' || req.id, 'elevated',
      'A ' || coalesce(req.detail->>'msg_type', 'notice') || ' for the ' || coalesce(req.detail->>'recipient_role', n.to_role, 'recipient')
        || ' did not arrive (' || v_result || ')',
      jsonb_build_object('request_id', req.id, 'result', v_result, 'support_evidence', a.detail->'evidence', 'rechecked', v_seen,
                         'retry_of', req.detail->'retry_of'),
      jsonb_build_array(v_seat || ' asked customer_support to send it',
                        case when req.detail->'retry_of' is not null then 'it was already a retry on the other channel'
                             else 'no other channel was on file' end),
      'Decide how this reaches them: correct the address or number, reach them another way, or record that it need not go.',
      'agent_actions#' || req.id, p_source_agent => v_seat);
    v_verdict := case when coalesce((v_rep->>'ok')::boolean, false) then 'escalated' else 'escalation_refused' end;
  end if;

  update public.agent_actions
     set detail = detail || jsonb_build_object('loop', v_verdict, 'closed_by', v_seat, 'closed_at', now(), 'close_check', v_seen,
                                               'retry_request_id', v_retry, 'escalation', v_rep)
   where id = req.id;
  -- A retry's outcome is the original's outcome too: whoever reads the first request sees how it ended.
  v_origin := (req.detail->>'retry_of')::bigint;
  if v_origin is not null then
    update public.agent_actions set detail = detail || jsonb_build_object('loop', 'retry_' || v_verdict) where id = v_origin;
  end if;
  return jsonb_build_object('checked_by', v_seat, 'result', v_result, 'verdict', v_verdict, 'rechecked', v_seen,
                            'retry_request_id', v_retry, 'escalation', v_rep);
end $function$


CREATE OR REPLACE FUNCTION public.fn_originators_reverify_handoffs(p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c_questions constant text[] := array['refund.requested', 'billing.question', 'charge.disputed'];
  c_notices constant text[] := array['reveal.paid', 'payment.failed', 'payment.received', 'refund.request_checked', 'refund.paid',
    'refund.declined', 'refund.in_progress', 'nonresponse.charge_raised', 'charge.corrected', 'subscription.due', 'billing.answer',
    'charge.dispute_answer', 'nonresponse.charge_reminder', 'nonresponse.final_demand', 'subscription.dunning',
    'subscription.payment_failed', 'subscription.renewal_reminder'];
  h public.agent_actions; k public.seat_handoff_kind; rep public.support_ceo_report; v_rep jsonb; v_answer bigint;
  v_reqs bigint[]; v_outs jsonb; v_verdict text; v_waiting boolean; v_failed jsonb; v_undecided int;
  n_answered int := 0; n_q_closed_by_ceo int := 0; n_q_reported int := 0; n_q_wait int := 0;
  n_closed int := 0; n_recorded int := 0; n_reported int := 0; n_wait int := 0; v_err jsonb := '[]'::jsonb;
  f record; v_type text; v_ok boolean; n_cleared int := 0; n_generic int := 0; n_reopened int := 0;
begin
  -- 1. THE SALES ENGINEER: did the accountant answer the question it was asked?
  for h in select * from public.agent_actions a
            where a.kind = 'handoff' and a.detail->>'from' = 'sales_engineer' and a.agent = 'accountant'
              and a.detail->>'type' = any (c_questions) and a.status in ('pending', 'failed')
            order by (a.detail ? 'escalated_report_id'), a.id limit greatest(coalesce(p_limit, 200), 1) loop
    begin
      select * into k from public.seat_handoff_kind where type = h.detail->>'type' and from_seat = 'sales_engineer' and to_seat = 'accountant';
      -- An answer counts whatever became of it afterwards: relaying it is the accountant's notice loop.
      v_answer := null;
      select a.id into v_answer from public.agent_actions a
       where a.kind = 'handoff' and a.agent = 'sales_engineer' and a.detail->>'from' = 'accountant'
         and a.target_id = case h.detail->>'type'
                             when 'refund.requested' then 'refund.request_checked:' || (h.detail->>'subject_id')
                             when 'billing.question' then 'billing.answer:' || h.id end
       limit 1;
      if v_answer is null and h.detail->>'type' = 'charge.disputed' then
        select a.id into v_answer from public.agent_actions a
         where a.kind = 'handoff' and a.agent = 'sales_engineer' and a.detail->>'type' = 'charge.dispute_answer'
           and a.target_id like 'charge.dispute\_answer:%:' || h.id
         limit 1;
      end if;
      rep := null;
      if h.detail ? 'escalated_report_id' then
        select * into rep from public.support_ceo_report where id = (h.detail->>'escalated_report_id')::bigint;
      end if;
      v_verdict := case
        when v_answer is not null then 'answered by the accountant (handoff ' || v_answer || ')'
        when rep.status in ('accepted', 'completed') then 'unanswered; the CEO decided: ' || left(rep.acceptance_receipt, 400)
      end;

      if v_verdict is not null then
        perform set_config('qd.handoff_closer', 'sales_engineer', true);
        perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
          'verified_by', 'sales_engineer', 'verified_at', now(), 'verdict', v_verdict));
        perform set_config('qd.handoff_closer', '', true);
        if v_answer is not null then n_answered := n_answered + 1; else n_q_closed_by_ceo := n_q_closed_by_ceo + 1; end if;
      elsif rep.id is null and (h.status = 'failed' or now() > h.created_at + coalesce(k.reply_within, interval '1 hour')) then
        v_rep := public.fn_support_report_to_ceo('handoff_unanswered:' || h.id, 'serious',
          'The accountant did not answer "' || (h.detail->>'type') || '" from the sales engineer (handoff ' || h.id || ')',
          jsonb_build_object('handoff_id', h.id, 'type', h.detail->>'type', 'handoff_status', h.status,
                             'error', h.detail->>'error', 'asked_at', h.created_at, 'reply', h.evidence),
          jsonb_build_array('sales_engineer asked the accountant at ' || to_char(h.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' (Dubai)'),
          'Decide what fixes the accountant''s answer. The sales engineer closes the question with your decision.',
          'agent_actions#' || h.id, p_review_in => interval '4 hours', p_source_agent => 'sales_engineer');
        if not coalesce((v_rep->>'ok')::boolean, false) then
          raise exception 'the CEO report for handoff % was refused: %', h.id, v_rep->>'reason';
        end if;
        update public.agent_actions set detail = detail || jsonb_build_object('escalated_report_id', (v_rep->>'report_id')::bigint, 'escalated_at', now())
         where id = h.id;
        n_q_reported := n_q_reported + 1;
      else
        n_q_wait := n_q_wait + 1;
      end if;
    exception when others then
      v_err := v_err || jsonb_build_object('handoff', h.id, 'error', left(sqlerrm, 300));
    end;
  end loop;

  -- 2. THE ACCOUNTANT: did the money notice it asked for reach the customer or supplier?
  for h in select * from public.agent_actions a
            where a.kind = 'handoff' and a.detail->>'from' = 'accountant' and a.agent = 'sales_engineer'
              and a.detail->>'type' = any (c_notices) and not (a.detail ? 'originator_verdict')
              and (a.status in ('done', 'failed') or (a.status = 'pending' and a.detail ? 'replied_at'))
            order by (a.detail ? 'escalated_report_id'), a.id limit greatest(coalesce(p_limit, 200), 1) loop
    begin
      select * into k from public.seat_handoff_kind where type = h.detail->>'type' and from_seat = 'accountant' and to_seat = 'sales_engineer';
      v_verdict := null; rep := null;
      -- Every send the notice made: the one the handler names, and on a reveal the supplier's as well.
      v_reqs := array_remove(array[(h.evidence->>'delivery_request')::bigint,
                  case when h.detail->>'type' = 'reveal.paid' then
                    (select a.id from public.agent_actions a where a.agent = 'customer_support' and a.kind = 'handoff'
                      and a.target_id = 'delivery.request:quote_accepted:' || (h.detail->>'subject_id') order by a.id desc limit 1) end], null);
      if h.detail ? 'escalated_report_id' then
        select * into rep from public.support_ceo_report where id = (h.detail->>'escalated_report_id')::bigint;
      end if;

      if h.detail ? 'superseded_by_incident' then
        v_verdict := 'superseded by refund incident ' || (h.detail->>'superseded_by_incident');
      elsif rep.id is not null then
        -- Reported already: it ends with the CEO's decision.
        -- A send recorded on the report that has since failed is decided on its own delivery_undelivered
        -- report; the notice waits for that decision too, and carries it in the verdict.
        if rep.status = 'completed'
           and not exists (select 1 from jsonb_array_elements(coalesce(rep.verified_evidence->'sends', '[]'::jsonb)) o
                            cross join lateral public.fn_delivery_request_outcome((o->>'request_id')::bigint) oc
                            where oc->>'state' = 'failed'
                              and not exists (select 1 from public.support_ceo_report s
                                               where s.idempotency_key = oc->>'report_key' and s.status = 'completed')) then
          v_verdict := 'the CEO decided: ' || left(coalesce(rep.completion_note, rep.acceptance_receipt), 400)
            || coalesce(' | ' || (select string_agg(left(coalesce(s.completion_note, s.acceptance_receipt), 300), ' | ')
                                    from jsonb_array_elements(coalesce(rep.verified_evidence->'sends', '[]'::jsonb)) o
                                    cross join lateral public.fn_delivery_request_outcome((o->>'request_id')::bigint) oc
                                    join public.support_ceo_report s on s.idempotency_key = oc->>'report_key'
                                   where oc->>'state' = 'failed'), '');
        end if;
      elsif h.status = 'failed' or cardinality(v_reqs) = 0
            or (h.detail->>'type' = 'reveal.paid'
                and (h.evidence->>'customer_reachable' = 'false' or h.evidence->>'supplier_reachable' = 'false')) then
        -- The notice never left: no address on file, or the sales engineer could not write it.
        v_rep := public.fn_support_report_to_ceo('notice_undelivered:' || h.id, 'elevated',
          'A ' || (h.detail->>'type') || ' notice the accountant asked for was not sent (handoff ' || h.id || ')',
          jsonb_build_object('handoff_id', h.id, 'type', h.detail->>'type', 'handoff_status', h.status,
                             'reply', h.evidence, 'error', h.detail->>'error'),
          jsonb_build_array('accountant asked the sales engineer at ' || to_char(h.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' (Dubai)'),
          'Decide how this customer or supplier learns of it: an address to use, another channel, or record that it cannot go.',
          'agent_actions#' || h.id, p_review_in => interval '1 day', p_source_agent => 'accountant');
        if not coalesce((v_rep->>'ok')::boolean, false) then
          raise exception 'the CEO report for handoff % was refused: %', h.id, v_rep->>'reason';
        end if;
        update public.agent_actions set detail = detail || jsonb_build_object('escalated_report_id', (v_rep->>'report_id')::bigint, 'escalated_at', now())
         where id = h.id;
        n_reported := n_reported + 1;
      else
        select coalesce(jsonb_agg(public.fn_delivery_request_outcome(x)), '[]'::jsonb) into v_outs from unnest(v_reqs) x;
        v_waiting := exists (select 1 from jsonb_array_elements(v_outs) o where o->>'state' in ('waiting', 'missing'));
        v_failed := (select coalesce(jsonb_agg(o), '[]'::jsonb) from jsonb_array_elements(v_outs) o where o->>'state' = 'failed');
        if v_waiting then
          if now() > h.created_at + coalesce(k.reply_within, interval '24 hours') then
            v_rep := public.fn_support_report_to_ceo('notice_unverified:' || h.id, 'elevated',
              'A ' || (h.detail->>'type') || ' notice has no delivery outcome after ' || coalesce(k.reply_within, interval '24 hours') || ' (handoff ' || h.id || ')',
              jsonb_build_object('handoff_id', h.id, 'type', h.detail->>'type', 'sends', v_outs,
                                 'delivery_loop', (select string_agg(o->>'loop', ', ') from jsonb_array_elements(v_outs) o)),
              jsonb_build_array('accountant asked the sales engineer at ' || to_char(h.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' (Dubai)'),
              'Find out what became of this send. The accountant closes the notice with your decision.',
              'agent_actions#' || h.id, p_review_in => interval '1 day', p_source_agent => 'accountant');
            if not coalesce((v_rep->>'ok')::boolean, false) then
              raise exception 'the CEO report for handoff % was refused: %', h.id, v_rep->>'reason';
            end if;
            update public.agent_actions set detail = detail || jsonb_build_object('escalated_report_id', (v_rep->>'report_id')::bigint, 'escalated_at', now())
             where id = h.id;
            n_reported := n_reported + 1;
          end if;
        elsif jsonb_array_length(v_failed) > 0 then
          -- It did not arrive: the sales engineer's delivery_undelivered report carries it to the CEO.
          -- The notice closes with the CEO's decision on that report once it is decided and completed.
          select count(*) into v_undecided from jsonb_array_elements(v_failed) o
           where not exists (select 1 from public.support_ceo_report s where s.idempotency_key = o->>'report_key' and s.status = 'completed');
          if v_undecided = 0 then
            v_verdict := 'did not arrive; the CEO decided: ' || (select string_agg(left(coalesce(s.completion_note, s.acceptance_receipt), 300), ' | ')
              from jsonb_array_elements(v_failed) o join public.support_ceo_report s on s.idempotency_key = o->>'report_key');
          end if;
        else
          -- Only a send that arrived is 'reached'; a stubbed, routed or cancelled one ended without arriving.
          v_verdict := case when exists (select 1 from jsonb_array_elements(v_outs) o where o->>'state' <> 'reached')
                            then 'ended: ' else 'reached: ' end || (select string_agg((o->>'loop') || ' (request ' || (o->>'request_id') || ')', ', ') from jsonb_array_elements(v_outs) o);
        end if;
      end if;

      if v_verdict is null then
        n_wait := n_wait + 1;
      else
        -- Only a pending row is closed; a done or failed row is already terminal and gets the verdict recorded.
        if h.status = 'pending' and k.originator_closes then
          perform set_config('qd.handoff_closer', 'accountant', true);
          perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
            'verified_by', 'accountant', 'verified_at', now(), 'verdict', v_verdict));
          perform set_config('qd.handoff_closer', '', true);
          n_closed := n_closed + 1;
        else
          n_recorded := n_recorded + 1;
        end if;
        update public.agent_actions
           set detail = detail || jsonb_build_object('originator_verdict', v_verdict, 'originator_verified_by', 'accountant', 'originator_verified_at', now())
         where id = h.id;
      end if;
    exception when others then
      v_err := v_err || jsonb_build_object('handoff', h.id, 'error', left(sqlerrm, 300));
    end;
  end loop;

  -- 4. EVERY OTHER ORIGINATOR CLOSES WHAT WAS ANSWERED (4 Oct 2026). Sections 1 and 2 cover the two
  -- money conversations; every other kind with originator_closes had no closer at all, so an answered
  -- handoff stayed open until the SLA duty raised it. The originator reads the reply its handler wrote:
  --   no 'waiting' and no error  -> the contract is met: closed, the reply is the verdict;
  --   an error or ok=false       -> sent back with the reason and handled again (ruling 1059: a rejection
  --                                 never ends the cycle); after 3 rounds the SLA duty raises it to the CEO;
  --   'waiting', a future due_at, or a step held by the model hold -> the contract is not finished; left.
  for h in select a.* from public.agent_actions a
             join public.seat_handoff_kind sk on sk.type = a.detail->>'type' and sk.from_seat = a.detail->>'from'
                                             and sk.to_seat = a.agent and sk.originator_closes
            where a.kind = 'handoff' and a.status = 'pending' and a.detail ? 'replied_at'
              and a.detail->>'type' not in ('it.finding', 'delivery.request')
              and not (a.detail->>'type' = any (c_questions || c_notices))
              and not (coalesce(a.evidence, '{}'::jsonb) ? 'waiting')
              and coalesce(a.evidence#>>'{step,action}', '') <> 'held'
              and coalesce((a.detail->>'due_at')::timestamptz, '-infinity') <= now()
              and coalesce((a.detail->>'reopened')::int, 0) < 3
            order by a.id limit greatest(coalesce(p_limit, 200), 1) loop
    begin
      if coalesce(h.evidence, '{}'::jsonb) ? 'error' or h.evidence->>'ok' = 'false' then
        update public.agent_actions
           set detail = (detail - 'replied_at') || jsonb_build_object('reopened', coalesce((detail->>'reopened')::int, 0) + 1,
                 'reopen_reasons', coalesce(detail->'reopen_reasons', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
                   'at', now(), 'by', h.detail->>'from', 'why', 'the reply did not meet the contract: '
                   || left(coalesce(h.evidence->>'error', h.evidence->>'reason', h.evidence::text), 300))))
         where id = h.id;
        -- Its own block: a handler that raises still counts as a round, so the 3-round limit holds.
        begin
          perform public.fn_seat_handoff_act(h.id);
        exception when others then
          v_err := v_err || jsonb_build_object('handoff', h.id, 'sent_back_error', left(sqlerrm, 300));
        end;
        n_reopened := n_reopened + 1;
      else
        perform set_config('qd.handoff_closer', h.detail->>'from', true);
        perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
          'verified_by', h.detail->>'from', 'verified_at', now(),
          'verdict', 'answered within the contract of ' || (h.detail->>'type') || '; closed by the originator'));
        perform set_config('qd.handoff_closer', '', true);
        n_generic := n_generic + 1;
      end if;
    exception when others then
      v_err := v_err || jsonb_build_object('handoff', h.id, 'error', left(sqlerrm, 300));
    end;
  end loop;

  -- 3. A DEFECT THE CEO RAISED CLEARS WHEN THE SAME CONVERSATION WORKS AGAIN. The finding's key names
  -- the conversation; it closes when the latest one of that kind was answered (a question), written
  -- (a notice the sales engineer could not write) or delivered (a notice with no outcome). Closing it
  -- lets the IT loop close its own handoff. What was missed while broken is not re-sent automatically:
  -- the CEO's decision on each is on its report.
  for f in select q.issue_key from public.it_engineer_finding q
            where q.closed_at is null
              and (q.issue_key like 'monitor:handoff\_unanswered:%' or q.issue_key like 'monitor:notice\_undelivered:%'
                   or q.issue_key like 'monitor:notice\_unverified:%') loop
    begin
      v_type := split_part(f.issue_key, ':', 3);
      h := null;
      if f.issue_key like 'monitor:handoff\_unanswered:%' then
        select * into h from public.agent_actions a
         where a.kind = 'handoff' and a.detail->>'type' = v_type and a.detail->>'from' = 'sales_engineer'
           and a.agent = split_part(f.issue_key, ':', 4) and a.status = 'done'
         order by a.id desc limit 1;
        v_ok := h.evidence->>'verdict' like 'answered%';
      elsif f.issue_key like 'monitor:notice\_undelivered:%' then
        select * into h from public.agent_actions a
         where a.kind = 'handoff' and a.detail->>'type' = v_type and a.detail->>'from' = 'accountant'
           and (a.status <> 'pending' or a.detail ? 'replied_at')
         order by a.id desc limit 1;
        v_ok := h.status <> 'failed' and (h.evidence->>'delivery_request') is not null;
      else
        select * into h from public.agent_actions a
         where a.kind = 'handoff' and a.detail->>'type' = v_type and a.detail->>'from' = 'accountant'
           and a.detail ? 'originator_verdict'
         order by a.id desc limit 1;
        -- 'ended' (routed, stubbed, digested, cancelled) is an outcome too: the finding was "no outcome".
        v_ok := h.detail->>'originator_verdict' ~ '^(reached|ended): ';
      end if;
      if coalesce(v_ok, false) then
        perform public.fn_it_engineer_finding_close(f.issue_key,
          'handoff ' || h.id || ' of the same kind worked again, re-checked by fn_originators_reverify_handoffs');
        n_cleared := n_cleared + 1;
      end if;
    exception when others then
      v_err := v_err || jsonb_build_object('finding', f.issue_key, 'error', left(sqlerrm, 300));
    end;
  end loop;

  return jsonb_build_object(
    'defects_cleared', n_cleared,
    'every_originator', jsonb_build_object('closed', n_generic, 'sent_back', n_reopened),
    'sales_engineer', jsonb_build_object('answered', n_answered, 'closed_with_ceo_decision', n_q_closed_by_ceo,
                                         'reported', n_q_reported, 'waiting', n_q_wait),
    'accountant', jsonb_build_object('closed', n_closed, 'recorded', n_recorded, 'reported', n_reported, 'waiting', n_wait),
    'errors', v_err);
end $function$


CREATE OR REPLACE FUNCTION public.fn_os_ai_quality()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with nights as (
  select at, row_number() over (order by at desc) rn
  from (select distinct at from public.ai_quality_snapshots) d
),
latest_at as (select at from nights where rn = 1),
-- one row per agent for the most recent night, whichever era wrote it
latest as (
  select s.agent,
         round(sum(s.override_pct * greatest(s.actions_30d,1))::numeric
               / nullif(sum(greatest(s.actions_30d,1)),0), 1) as override_pct,
         sum(s.actions_30d)::int as actions_30d
  from public.ai_quality_snapshots s
  where s.at = (select at from latest_at)
  group by s.agent
),
-- the trailing picture, excluding the night we are reporting on
prev as (
  select s.agent,
         round(sum(s.override_pct * greatest(s.actions_30d,1))::numeric
               / nullif(sum(greatest(s.actions_30d,1)),0), 1) as avg_prev,
         count(distinct s.at) as nights
  from public.ai_quality_snapshots s
  where s.at < (select at from latest_at)
  group by s.agent
)
select jsonb_build_object(
  'as_of', (select at from latest_at),
  'nights_held', (select count(*) from nights),
  'agents', (select count(*) from latest),
  -- the one headline, weighted the same way as every row under it
  'override_pct_overall', (select round(sum(override_pct * greatest(actions_30d,1))::numeric
                                        / nullif(sum(greatest(actions_30d,1)),0), 1) from latest),
  'actions_30d_total', (select coalesce(sum(actions_30d),0) from latest),
  'meaning', 'override_pct is the share of that agent''s proposed actions in the last 30 days that a human rejected, dismissed, declined or overrode. Higher is worse.',
  'rows', coalesce((
    select jsonb_agg(r order by r->>'sort_key')
    from (
      select jsonb_build_object(
               'agent', l.agent,
               'override_pct', l.override_pct,
               'actions_30d', l.actions_30d,
               'avg_prev', p.avg_prev,
               'nights_of_history', coalesce(p.nights, 0),
               -- stated only when there IS a history to compare against, so a first-night agent
               -- reads as 'new' rather than as 'no change'
               'delta', case when p.avg_prev is null then null
                             else round(l.override_pct - p.avg_prev, 1) end,
               'sort_key', lpad((1000 - least(999, l.actions_30d))::text, 4, '0') || l.agent
             ) as r
      from latest l left join prev p on p.agent = l.agent
    ) x), '[]'::jsonb)
);
$function$


CREATE OR REPLACE FUNCTION public.fn_os_automation_list()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 6 SEP 2026: ONE pass over the last 8 days of run details (distinct on jobid), joined to the jobs,
  -- instead of a per-job LATERAL over the whole 250k-row table. 10.9 s -> well under the 8 s wall.
  with latest as (
    select distinct on (d.jobid) d.jobid, d.status, d.start_time, d.end_time, d.return_message
      from cron.job_run_details d
     where d.start_time > now() - interval '8 days'
     order by d.jobid, d.start_time desc nulls last
  )
  select coalesce(jsonb_agg(x order by x->>'category', x->>'human_name'), '[]'::jsonb) from (
    select jsonb_build_object(
      'jobid', j.jobid, 'jobname', j.jobname,
      'human_name', coalesce(r.human_name, initcap(replace(replace(j.jobname,'_',' '),'-',' '))),
      'category', coalesce(r.category,'Operations'), 'purpose', coalesce(r.purpose,''),
      'schedule', j.schedule, 'active', j.active,
      'last_status', lr.status, 'last_start', lr.start_time, 'last_end', lr.end_time,
      'last_message', left(coalesce(lr.return_message,''), 240)
    ) as x
    from cron.job j
    left join public.cron_registry r on r.jobname = j.jobname
    left join latest lr on lr.jobid = j.jobid
  ) q;
$function$


CREATE OR REPLACE FUNCTION public.fn_os_automation_reschedule(p_jobid bigint, p_schedule text, p_actor text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE nm text; oldsched text;
BEGIN
  SELECT jobname, schedule INTO nm, oldsched FROM cron.job WHERE jobid = p_jobid;
  IF nm IS NULL THEN RETURN jsonb_build_object('ok',false,'error','job_not_found'); END IF;
  IF coalesce(array_length(regexp_split_to_array(btrim(p_schedule), '\s+'),1),0) <> 5 THEN
    RETURN jsonb_build_object('ok',false,'error','schedule_must_have_5_fields'); END IF;
  BEGIN PERFORM cron.alter_job(job_id := p_jobid, schedule := p_schedule);
  EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok',false,'error',SQLERRM); END;
  INSERT INTO public.os_audit_log(actor,action,entity,entity_id,detail,ok)
  VALUES (coalesce(p_actor,'os'),'automation_reschedule','cron_job',p_jobid::text,jsonb_build_object('jobname',nm,'old',oldsched,'new',p_schedule),true);
  RETURN jsonb_build_object('ok',true,'schedule',p_schedule);
END $function$


CREATE OR REPLACE FUNCTION public.fn_os_automation_run(p_jobid bigint, p_actor text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE cmd text; nm text; ok boolean := true; msg text := '';
BEGIN
  SELECT command, jobname INTO cmd, nm FROM cron.job WHERE jobid = p_jobid;
  IF cmd IS NULL THEN RETURN jsonb_build_object('ok',false,'error','job_not_found'); END IF;
  BEGIN EXECUTE cmd; EXCEPTION WHEN others THEN ok := false; msg := SQLERRM; END;
  INSERT INTO public.os_audit_log(actor,action,entity,entity_id,detail,ok)
  VALUES (coalesce(p_actor,'os'),'automation_run','cron_job',p_jobid::text,jsonb_build_object('jobname',nm,'error',msg),ok);
  RETURN jsonb_build_object('ok',ok,'error',nullif(msg,''));
END $function$


CREATE OR REPLACE FUNCTION public.fn_os_automation_set_active(p_jobid bigint, p_active boolean, p_actor text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE nm text;
BEGIN
  SELECT jobname INTO nm FROM cron.job WHERE jobid = p_jobid;
  IF nm IS NULL THEN RETURN jsonb_build_object('ok',false,'error','job_not_found'); END IF;
  PERFORM cron.alter_job(job_id := p_jobid, active := p_active);
  INSERT INTO public.os_audit_log(actor,action,entity,entity_id,detail,ok)
  VALUES (coalesce(p_actor,'os'),'automation_active','cron_job',p_jobid::text,jsonb_build_object('jobname',nm,'active',p_active),true);
  RETURN jsonb_build_object('ok',true,'active',p_active);
END $function$


CREATE OR REPLACE FUNCTION public.fn_os_catalog_get(p_category text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'category', cs.category,
    'label', coalesce(cs.label, cs.category),
    'fields', coalesce(cs.fields, '[]'::jsonb),
    'spec_group', g.grp,
    'specs', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', q.id, 'aspect', q.aspect, 'label', q.label, 'match_regex', q.match_regex,
        'mandatory', q.mandatory, 'note', coalesce(q.note,'')) order by q.mandatory desc, q.aspect), '[]'::jsonb)
      from public.category_quote_specs q where q.spec_group = g.grp)
  )
  from public.category_specs cs, lateral (select public.fn_quote_spec_group(cs.category) as grp) g
  where cs.category = p_category;
$function$


CREATE OR REPLACE FUNCTION public.fn_os_catalog_list()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'category', cs.category,
    'label', coalesce(cs.label, cs.category),
    'n_fields', coalesce(jsonb_array_length(cs.fields), 0),
    'spec_group', public.fn_quote_spec_group(cs.category),
    'n_specs', (select count(*) from public.category_quote_specs q where q.spec_group = public.fn_quote_spec_group(cs.category))
  ) order by cs.category), '[]'::jsonb)
  from public.category_specs cs;
$function$


CREATE OR REPLACE FUNCTION public.fn_os_catalog_save_fields(p_category text, p_fields jsonb, p_actor text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE oldf jsonb;
BEGIN
  IF jsonb_typeof(p_fields) <> 'array' THEN RETURN jsonb_build_object('ok',false,'error','fields_must_be_a_list'); END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_fields) e
             WHERE jsonb_typeof(e) <> 'object' OR coalesce(e->>'question','')='' OR coalesce(e->>'key','')='') THEN
    RETURN jsonb_build_object('ok',false,'error','each_question_needs_a_key_and_question_text'); END IF;
  SELECT fields INTO oldf FROM public.category_specs WHERE category = p_category;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','category_not_found'); END IF;
  UPDATE public.category_specs SET fields = p_fields, updated_at = now() WHERE category = p_category;
  INSERT INTO public.os_audit_log(actor,action,entity,entity_id,detail,ok)
  VALUES (coalesce(p_actor,'os'),'catalog_save_fields','category',p_category,
          jsonb_build_object('n_fields', jsonb_array_length(p_fields)), true);
  RETURN jsonb_build_object('ok',true,'n_fields', jsonb_array_length(p_fields));
END $function$


CREATE OR REPLACE FUNCTION public.fn_os_catalog_spec_delete(p_id bigint, p_actor text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE g text; a text;
BEGIN
  SELECT spec_group, aspect INTO g, a FROM public.category_quote_specs WHERE id=p_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','spec_not_found'); END IF;
  DELETE FROM public.category_quote_specs WHERE id=p_id;
  INSERT INTO public.os_audit_log(actor,action,entity,entity_id,detail,ok)
  VALUES (coalesce(p_actor,'os'),'catalog_spec_delete','quote_spec',p_id::text,jsonb_build_object('spec_group',g,'aspect',a), true);
  RETURN jsonb_build_object('ok',true);
END $function$


CREATE OR REPLACE FUNCTION public.fn_os_catalog_spec_upsert(p_id bigint, p_spec_group text, p_aspect text, p_label text, p_regex text, p_mandatory boolean, p_note text, p_actor text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE newid bigint;
BEGIN
  IF coalesce(p_spec_group,'')='' OR coalesce(p_aspect,'')='' OR coalesce(p_label,'')='' OR coalesce(p_regex,'')='' THEN
    RETURN jsonb_build_object('ok',false,'error','group_aspect_label_and_pattern_required'); END IF;
  BEGIN PERFORM regexp_match('validation probe', p_regex);
  EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok',false,'error','invalid_pattern: '||SQLERRM); END;
  IF p_id IS NOT NULL AND p_id > 0 THEN
    UPDATE public.category_quote_specs SET spec_group=p_spec_group, aspect=p_aspect, label=p_label, match_regex=p_regex, mandatory=coalesce(p_mandatory,false), note=nullif(p_note,'')
      WHERE id=p_id RETURNING id INTO newid;
    IF newid IS NULL THEN RETURN jsonb_build_object('ok',false,'error','spec_not_found'); END IF;
  ELSE
    INSERT INTO public.category_quote_specs(spec_group,aspect,label,match_regex,mandatory,note)
      VALUES (p_spec_group,p_aspect,p_label,p_regex,coalesce(p_mandatory,false),nullif(p_note,'')) RETURNING id INTO newid;
  END IF;
  INSERT INTO public.os_audit_log(actor,action,entity,entity_id,detail,ok)
  VALUES (coalesce(p_actor,'os'),'catalog_spec_upsert','quote_spec',newid::text,
          jsonb_build_object('spec_group',p_spec_group,'aspect',p_aspect,'mandatory',coalesce(p_mandatory,false)), true);
  RETURN jsonb_build_object('ok',true,'id',newid);
END $function$


CREATE OR REPLACE FUNCTION public.fn_os_catalog_test_gate(p_category text, p_present text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare grp text; res jsonb;
begin
  grp := public.fn_quote_spec_group(p_category);
  with asp as (
    select q.aspect, q.label, q.mandatory, (q.aspect = any(coalesce(p_present, '{}'::text[]))) as matched
      from public.category_quote_specs q where q.spec_group = grp
  )
  select jsonb_build_object(
    'category', p_category, 'spec_group', grp, 'read_by', 'reasoning',
    'aspects', coalesce((select jsonb_agg(jsonb_build_object('aspect',aspect,'label',label,'mandatory',mandatory,'matched',matched) order by mandatory desc, aspect) from asp),'[]'::jsonb),
    'total', (select count(*) from asp),
    'matched_count', (select count(*) from asp where matched),
    'mandatory_missing', coalesce((select jsonb_agg(label order by label) from asp where mandatory and not matched),'[]'::jsonb),
    'passes', (select coalesce(bool_and(matched),true) from asp where mandatory)
  ) into res;
  return res;
end $function$


CREATE OR REPLACE FUNCTION public.fn_os_command()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_health jsonb; v_ops jsonb; v_counts jsonb; v_attention jsonb; v_pipeline jsonb;
begin
  v_health := to_jsonb(fn_health_index());
  v_ops    := to_jsonb(fn_ops_dashboard());

  select jsonb_build_object(
    'suppliers_total', (select count(*) from leads),
    'rfqs_total',      (select count(*) from inquiries),
    'rfqs_active',     (select count(*) from inquiries where status = 'quoted'),
    'rfqs_revealed',   (select count(*) from inquiries where status = 'revealed'),
    'rfqs_cancelled',  (select count(*) from inquiries where status = 'cancelled'),
    'quotes_total',    (select count(*) from quotes),
    'decisions_7d',    (select count(*) from decision_log where created_at > now() - interval '7 days'),
    'decisions_24h',   (select count(*) from decision_log where created_at > now() - interval '24 hours')
  ) into v_counts;

  select jsonb_build_object(
    'sent',      (select count(*) from inquiries where status = 'sent' and parent_inquiry_id is null),
    'matched',   (select count(distinct im.inquiry_id) from inquiry_matches im join inquiries i on i.id = im.inquiry_id where i.status = 'sent'),
    'quoted',    (select count(*) from inquiries where status = 'quoted'),
    'revealed',  (select count(*) from inquiries where status = 'revealed'),
    'completed', (select count(*) from inquiries where status in ('completed','won'))
  ) into v_pipeline;

  -- THE ESCALATIONS LOG. decision_log is append-only; this reads forward from the fresh-start
  -- watermark. A decision is listed only while its action is open, and each names the ROLE that
  -- holds it: none of these is the founder's to approve.
  select coalesce(jsonb_agg(x order by created_at desc), '[]'::jsonb) into v_attention
  from (
    select id, actor, kind, decision, confidence, route_to, created_at,
           jsonb_build_object('id', id, 'actor', actor, 'kind', kind,
             'kind_label', public.fn_ui_label('action_kind', kind), 'decision', decision,
             'policies', public.fn_action_policies(kind, confidence),
             'confidence', confidence, 'route_to', route_to, 'created_at', created_at,
             'os', public.fn_owning_os(actor),
             'holder', public.fn_action_holder(kind, actor),
             'yours', false,
             'reasons', reasons,
             'alternatives', alternatives,
             'outcome', case when exists (select 1 from public.agent_actions a where a.decision_log_id = decision_log.id)
                  then (select coalesce(a.status,'recorded') || ' — ' || coalesce(a.title,'action taken')
                          || ', held with ' || public.fn_action_holder(a.kind, a.agent)
                          from public.agent_actions a where a.decision_log_id = decision_log.id
                         order by a.created_at desc limit 1)
                  else 'held for ' || coalesce(route_to,'review') || ', no follow-up action recorded since ' || created_at::date end
           ) as x
    from decision_log
    where route_to is not null and route_to <> 'auto'
      and created_at >= public.fn_os_fresh_start_at()
      and exists (select 1 from public.agent_actions a
                   where a.decision_log_id = decision_log.id
                     and a.status in ('pending','needs_review'))
    order by created_at desc limit 8
  ) z;

  return jsonb_build_object(
    'health', v_health, 'health_index', v_health->>'index',
    'ops', v_ops, 'counts', v_counts, 'pipeline', v_pipeline,
    'attention', v_attention, 'generated_at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_os_dashboard_viz()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  out jsonb := '{}'::jsonb;
  v_total bigint; v_contacted bigint; v_invited bigint; v_claimed bigint;
  v_registered bigint; v_verified bigint; v_approved bigint;
  v_runs24 bigint; v_agents24 bigint; v_failed24 bigint;
  j_sector jsonb; j_emirate jsonb; j_invites jsonb; j_agents jsonb; j_funnel jsonb; j_pipeline jsonb;
begin
  select count(*) into v_total from leads where not is_demo;
  select count(*) into v_contacted from leads where contacted is true and not is_demo;
  select count(*) into v_invited from leads where invited_at is not null and not is_demo;
  select count(*) into v_claimed from leads where claimed is true and not is_demo;
  select count(*) into v_registered from leads where registration_submitted_at is not null and not is_demo;
  select count(*) into v_verified from leads where verified is true and not is_demo;
  select count(*) into v_approved from leads where approved_at is not null and not is_demo;

  -- agent activity from agent_runs (the same source the header/Smart Engine use)
  begin
    select count(*) filter (where started_at > now() - interval '24 hours'),
           count(distinct agent) filter (where started_at > now() - interval '24 hours'),
           count(*) filter (where started_at > now() - interval '24 hours' and status in ('error','failed'))
      into v_runs24, v_agents24, v_failed24 from agent_runs;
    select coalesce(jsonb_agg(x), '[]'::jsonb) into j_agents from (
      select agent as label, count(*)::int as n
      from agent_runs where started_at > now() - interval '24 hours'
      group by agent order by count(*) desc limit 8
    ) x;
  exception when others then v_runs24 := 0; v_agents24 := 0; v_failed24 := 0; j_agents := '[]'::jsonb; end;

  select coalesce(jsonb_agg(x), '[]'::jsonb) into j_sector from (
    select coalesce(nullif(trim(sector),''),'unspecified') as label, count(*)::int as n
    from leads where not is_demo group by 1 order by count(*) desc limit 12
  ) x;

  select coalesce(jsonb_agg(x), '[]'::jsonb) into j_emirate from (
    select coalesce(nullif(trim(emirate),''),'unknown') as label, count(*)::int as n
    from leads where not is_demo group by 1 order by count(*) desc limit 9
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object('d', to_char(d.day,'Mon DD'), 'n', coalesce(c.n,0)) order by d.day), '[]'::jsonb)
    into j_invites
  from (select generate_series((current_date - interval '13 days')::date, current_date, interval '1 day')::date as day) d
  left join (select invited_at::date as day, count(*)::int as n from leads where invited_at > now() - interval '14 days' and not is_demo group by 1) c
    on c.day = d.day;

  j_funnel := jsonb_build_array(
    jsonb_build_object('stage','Sourced', 'n', v_total),
    jsonb_build_object('stage','Contacted', 'n', v_contacted),
    jsonb_build_object('stage','Invited', 'n', v_invited),
    jsonb_build_object('stage','Claimed', 'n', v_claimed),
    jsonb_build_object('stage','Registered', 'n', v_registered),
    jsonb_build_object('stage','Verified', 'n', v_verified),
    jsonb_build_object('stage','Approved', 'n', v_approved)
  );

  j_pipeline := jsonb_build_array(
    jsonb_build_object('stage','New', 'n', (select count(*) from inquiries where not (inquiries.provenance->>'qd_run' is not null or inquiries.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = inquiries.customer_id and dc.is_demo)))),
    jsonb_build_object('stage','Matched', 'n', (select count(distinct inquiry_id) from quotes where not exists (select 1 from public.leads dl where dl.id = quotes.supplier_id and dl.is_demo) and not exists (select 1 from public.inquiries di where di.id = quotes.inquiry_id and (di.provenance->>'qd_run' is not null or di.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = di.customer_id and dc.is_demo))))),
    jsonb_build_object('stage','Quoted', 'n', (select count(*) from quotes where not exists (select 1 from public.leads dl where dl.id = quotes.supplier_id and dl.is_demo) and not exists (select 1 from public.inquiries di where di.id = quotes.inquiry_id and (di.provenance->>'qd_run' is not null or di.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = di.customer_id and dc.is_demo))))),
    jsonb_build_object('stage','Revealed', 'n', (select count(*) from transactions t where not exists (select 1 from public.customers dc where dc.id = t.customer_id and dc.is_demo) and not exists (select 1 from public.leads dl where dl.id = t.supplier_id and dl.is_demo) and not public.fn_inquiry_is_demo(t.inquiry_id))),
    jsonb_build_object('stage','Won', 'n', (select count(*) from inquiries where status = 'won' and not (inquiries.provenance->>'qd_run' is not null or inquiries.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = inquiries.customer_id and dc.is_demo))))
  );

  out := jsonb_build_object(
    'headline', jsonb_build_object(
      'suppliers_total', v_total, 'invited_total', v_invited, 'verified_total', v_verified,
      'approved_total', v_approved, 'registered_total', v_registered,
      'agents_active_24h', v_agents24, 'runs_24h', v_runs24, 'runs_failed_24h', v_failed24),
    'funnel', j_funnel,
    'pipeline', j_pipeline,
    'by_sector', j_sector,
    'by_emirate', j_emirate,
    'invites_14d', j_invites,
    'agents_24h', j_agents,
    'generated_at', to_char(now(),'YYYY-MM-DD"T"HH24:MI:SSOF')
  );
  return out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_os_detail(p_entity text, p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v_tbl text; v_idcol text := 'id'; v_row jsonb;
begin
  case p_entity
    when 'inquiries' then v_tbl:='inquiries';
    when 'quotes' then v_tbl:='quotes';
    when 'transactions' then v_tbl:='transactions';
    when 'customers' then v_tbl:='customers';
    when 'suppliers' then v_tbl:='leads';
    when 'agent_actions' then v_tbl:='agent_actions';
    when 'doc_reviews' then v_tbl:='doc_reviews';
    when 'kb_revisions' then v_tbl:='kb_revisions';
    when 'inbox' then v_tbl:='inbound_messages';
    when 'documents' then v_tbl:='documents';
    when 'dropbox' then v_tbl:='dropbox_files';
    when 'invoices' then v_tbl:='reveal_invoices'; v_idcol:='transaction_id';
    when 'notifications' then v_tbl:='notifications';
    when 'tasks' then v_tbl:='crm_tasks';
    when 'po' then v_tbl:='po_orders';
    when 'expenses' then v_tbl:='expenses';
    when 'agent_runs' then v_tbl:='agent_runs';
    when 'fraud' then v_tbl:='fraud_flags'; v_idcol:='subject_id';
    else return jsonb_build_object('error','unknown_entity');
  end case;
  execute format('select to_jsonb(t) from %I t where %I::text = %L limit 1', v_tbl, v_idcol, p_id) into v_row;
  if v_row is null then return jsonb_build_object('error','not_found'); end if;
  return jsonb_build_object('entity',p_entity,'record',v_row);
end $function$


CREATE OR REPLACE FUNCTION public.fn_os_fresh_start_at()
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select coalesce((select f.effective_from from public.os_fresh_start f
                    order by f.effective_from desc, f.id desc limit 1),
                  '-infinity'::timestamptz);
$function$


CREATE OR REPLACE FUNCTION public.fn_os_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE res jsonb;
BEGIN
  SELECT jsonb_build_object(
    'generated_at', now(),
    'failing_crons', coalesce((
      SELECT jsonb_agg(jsonb_build_object('job', j.jobname, 'status', lr.status, 'when', lr.end_time,
                                          'message', left(coalesce(lr.return_message,''),160))
                       ORDER BY lr.end_time DESC)
      FROM (SELECT DISTINCT ON (jobid) jobid, status, end_time, return_message
              FROM cron.job_run_details
             WHERE start_time > now() - interval '7 days'
             ORDER BY jobid, start_time DESC) lr
      JOIN cron.job j ON j.jobid = lr.jobid
      WHERE lr.status = 'failed' AND lr.end_time > now() - interval '24 hours'
    ), '[]'::jsonb),
    'agent_errors_24h', (SELECT count(*) FROM public.agent_runs WHERE status='error' AND started_at > now() - interval '24 hours'),
    'top_error_agents', coalesce((SELECT jsonb_agg(x) FROM (SELECT jsonb_build_object('agent',agent,'errors',count(*)) x FROM public.agent_runs WHERE status='error' AND started_at > now()-interval '24 hours' GROUP BY agent ORDER BY count(*) DESC LIMIT 6) q),'[]'::jsonb),
    'health_check_fails_24h', (SELECT count(*) FROM public.health_checks WHERE ok=false AND created_at > now()-interval '24 hours'),
    'ai_health_fails', coalesce((SELECT value FROM public.app_secrets WHERE key='ai_health_fails'),'0'),
    'payments_7d_count', (SELECT count(*) FROM public.transactions WHERE revealed_at > now()-interval '7 days' AND not exists (select 1 from public.customers dc where dc.id = transactions.customer_id and dc.is_demo) and not exists (select 1 from public.leads dl where dl.id = transactions.supplier_id and dl.is_demo) and not exists (select 1 from public.inquiries di where di.id = transactions.inquiry_id and (di.provenance->>'qd_run' is not null or di.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = di.customer_id and dc.is_demo)))),
    'payments_7d_revenue_aed', coalesce((SELECT round(sum(reveal_fee)::numeric,2) FROM public.transactions WHERE revealed_at > now()-interval '7 days' AND not exists (select 1 from public.customers dc where dc.id = transactions.customer_id and dc.is_demo) and not exists (select 1 from public.leads dl where dl.id = transactions.supplier_id and dl.is_demo) and not exists (select 1 from public.inquiries di where di.id = transactions.inquiry_id and (di.provenance->>'qd_run' is not null or di.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = di.customer_id and dc.is_demo)))),0),
    -- CAN A REQUEST REACH ANYONE? Each number is counted at the gate it actually has to pass, so
    -- the drop between them says WHERE the reach is lost rather than only that it is small.
    'supplier_reach', jsonb_build_object(
      'leads', (SELECT count(*) FROM public.leads WHERE NOT is_demo),
      'with_capability', (SELECT count(*) FROM public.supplier_capabilities WHERE coalesce(cardinality(trades),0) > 0 AND NOT EXISTS (SELECT 1 FROM public.leads dl WHERE dl.id = supplier_capabilities.supplier_id AND dl.is_demo)),
      'confirmed', (SELECT count(*) FROM public.supplier_capabilities WHERE confirmed_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.leads dl WHERE dl.id = supplier_capabilities.supplier_id AND dl.is_demo)),
      -- the real ceiling: confirmed AND the lead itself still admissible to matching
      'matchable_now', (
        SELECT count(*) FROM public.supplier_capabilities sc
        JOIN public.leads l ON l.id = sc.supplier_id
        WHERE sc.confirmed_at IS NOT NULL AND NOT l.is_demo
          AND coalesce(cardinality(sc.trades),0) > 0
          AND public.fn_is_matchable(l.verified, l.banned, l.matching_blocked,
                                     l.approval_status, l.permanently_closed, l.chat_strikes)),
      'meaning', 'matchable_now is the most suppliers the structured matcher can shortlist for any request. fn_match_capability requires a supplier to have CONFIRMED their own scope; that gate is deliberate. When this is far below with_capability the shortage is confirmations, not suppliers.'
    )
  ) INTO res;
  RETURN res;
END
$function$


CREATE OR REPLACE FUNCTION public.fn_os_health_brief()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_period text; v_n int := 0; v_pool int := 0;
begin
  -- ---------------------------------------------------------------------------------------
  -- 1. ONE CAPACITY ROW PER ACTIVE OS, in the one unit every OS has: its own people's
  -- attention. The seed carried a single company-wide row (550 open tasks, keyed to
  -- leadership), which is why six operating systems reported no capacity at all. Both sides
  -- are measured live — org_agents.max_open_tasks is the declared ceiling, org_tasks the
  -- load — so this figure moves on its own and is falsifiable by looking at the org.
  delete from resource_pool where source_ref = 'org_agents.max_open_tasks';

  insert into resource_pool (resource, kind, owner_dept, unit, capacity, committed,
                             window_label, degrade_at_pct, halt_at_pct, source_ref, note, os_key)
  select 'Employee attention - ' || o.name, 'capacity',
         (select min(od.dept_key) from os_department od where od.os_key = o.os_key),
         'open tasks',
         coalesce((select sum(a.max_open_tasks) from os_department od
                     join org_agents a on a.department = od.dept_key and a.active
                    where od.os_key = o.os_key), 0),
         coalesce((select count(*) from os_department od
                     join public.v_org_open_tasks t on t.dept_key = od.dept_key
                    where od.os_key = o.os_key), 0),
         'rolling', 80, 100, 'org_agents.max_open_tasks',
         'Open tasks in this OS''s departments against the sum of max_open_tasks for its '
         || 'active staff. Refreshed weekly by fn_os_health_brief.', o.os_key
    from operating_system o where o.active;
  get diagnostics v_pool = row_count;

  -- 2. EVERY OTHER POOLED RESOURCE GETS A MEASURED NUMERATOR TOO. Each expression is the
  -- system of record for that resource; a resource whose consumption nothing records would
  -- otherwise sit at zero for ever and drag the OS's ratio down with it, which is the same
  -- "populated but never measured" defect one level down.
  update resource_pool rp set committed = m.v, updated_at = now()
    from (values
      ('AI token budget - company',
        (select coalesce(sum(cost_aed), 0)::numeric from ai_cost_log
          where occurred_at >= date_trunc('month', now()))),
      ('Supplier invites',
        (select coalesce(sum(sent), 0)::numeric from invite_schedule where day = current_date)),
      ('Outbound email',
        (select count(*)::numeric from notifications
          where coalesce(channel, 'email') = 'email' and created_at > now() - interval '1 day')),
      ('WhatsApp / SMS',
        (select count(*)::numeric from wa_messages where created_at > now() - interval '1 day')
      + (select count(*)::numeric from notifications
          where channel in ('sms', 'whatsapp') and created_at > now() - interval '1 day')),
      -- A FLOOR, NOT A TOTAL: this counts the scheduled invocations, which is every edge call
      -- the database itself can see. Browser and webhook traffic is not in cron.job_run_details.
      ('Edge function invocations',
        (select count(*)::numeric from cron.job_run_details d
           join cron.job j on j.jobid = d.jobid
          where j.command ~* 'net\.http_post' and d.start_time >= date_trunc('month', now()))),
      ('Database storage',
        round(pg_database_size(current_database()) / 1073741824.0, 2)::numeric),
      ('Document storage',
        (select round(coalesce(sum((o.metadata->>'size')::bigint), 0) / 1073741824.0, 2)::numeric
           from storage.objects o)),
      ('Scraping / enrichment',
        (select coalesce(sum(fetched), 0)::numeric from scrape_runs
          where created_at >= date_trunc('month', now()))),
      ('Payment processing',
        (select count(*)::numeric from transactions where revealed_at > now() - interval '1 day'))
    ) as m(resource, v)
   where rp.resource = m.resource;

  -- 3. The report is computed FROM those inputs, so recompute it now that they are current.
  -- Without this the week's capacity_pct would be derived from last Monday's numerator.
  perform fn_os_review();

  -- ---------------------------------------------------------------------------------------
  select max(period) into v_period from os_review;
  if v_period is null then
    return jsonb_build_object('written', 0, 'reason', 'os_review is empty');
  end if;

  -- Only active OSes with an ACTIVE owner: a brief addressed to a departed employee is another
  -- write with no reader, which is the defect this function exists to close.
  for r in
    select o.os_key, o.name, o.owner_agent, rv.health, rv.metrics
      from operating_system o
      join os_review rv  on rv.os_key = o.os_key and rv.period = v_period
      join org_agents  a on a.agent_key = o.owner_agent and a.active
     where o.active
     order by o.num
  loop
    -- Scoped to this function's own rows by source, so it can never touch a memory it did not
    -- write. This is what makes the weekly run idempotent instead of cumulative.
    delete from agent_memory
     where agent_key = r.owner_agent and source = 'fn_os_health_brief';

    -- ->> everywhere, never ->. text || jsonb resolves to jsonb || jsonb and silently builds an
    -- array instead of a sentence; that has already cost this project two call-time failures.
    insert into agent_memory (agent_key, kind, content, source, importance, horizon)
    values (r.owner_agent, 'os_health',
      'OS HEALTH, week ' || v_period || ' - ' || r.name || ' (' || r.os_key || '), which you own. '
      || 'HEALTH SCORE ' || coalesce(r.metrics->>'health_score', '?') || '/100 ('
        || coalesce(r.health, 'unrated') || '). '
      || 'RISK: open_risks ' || coalesce(r.metrics->>'open_risks', '0') || '. '
      || 'PERFORMANCE: kpi_gaps ' || coalesce(r.metrics->>'kpi_gaps', '0') || ' against '
        || coalesce(r.metrics->>'kpis', '0') || ' KPI(s). '
      || 'CAPACITY: capacity_pct ' || coalesce(r.metrics->>'capacity_pct', 'unmeasured') || '%. '
      || 'BACKLOG: ' || coalesce(r.metrics->>'open_tasks', '0') || ' open, stale_tasks '
        || coalesce(r.metrics->>'stale_tasks', '0') || ', backlog_per_head '
        || coalesce(r.metrics->>'backlog_per_head', '0') || '. '
      || 'QUALITY: review_pass_pct ' || coalesce(r.metrics->>'review_pass_pct', 'unmeasured') || '%. '
      || 'COST: budget_pct ' || coalesce(r.metrics->>'budget_pct', '0') || '% of the AI budget. '
      || 'AUTOMATION: needs_founder_pct ' || coalesce(r.metrics->>'needs_founder_pct', '0')
        || '% of open work still needs the founder. '
      || 'Act on the worst figure before it becomes a finding.',
      'fn_os_health_brief', 7, 'short');

    v_n := v_n + 1;
  end loop;

  return jsonb_build_object('period', v_period, 'written', v_n, 'capacity_rows', v_pool);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_os_incident_close_task()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_task record;
begin
  if new.status in ('resolved','closed') and coalesce(old.status,'') not in ('resolved','closed') then
    -- close the corrective task the incident opened — with the resolution ON the task (5 Sep 2026):
    -- a bare status flip is refused by a10_org_task_done_needs_a_determination now
    if new.org_task_id is not null then
      select o.id, o.status into v_task from public.org_tasks o where o.id = new.org_task_id;
      if found and v_task.status <> 'done' then
        perform public.fn_org_task_close_as_fact(new.org_task_id,
          coalesce(nullif(new.resolved_by, ''), 'os_incidents#' || new.id),
          'Incident #' || new.id || ' (' || coalesce(new.kind, 'incident') || ', severity ' || coalesce(new.severity, '?')
            || ') "' || coalesce(new.title, '') || '" was ' || new.status || ' by '
            || coalesce(nullif(new.resolved_by, ''), 'an unnamed resolver') || ' at '
            || coalesce(coalesce(new.resolved_at, now())::text, '?') || '. Resolution: '
            || coalesce(nullif(new.resolution, ''), nullif(new.detail->>'resolution', ''), '(none recorded on the incident)')
            || '. Opened ' || coalesce(new.opened_at::text, '?') || ' by ' || coalesce(new.opened_by, '?')
            || '; owner ' || coalesce(new.owner, '(none)') || '.',
          jsonb_build_object('os_incident_id', new.id, 'kind', new.kind, 'severity', new.severity,
                             'owner', new.owner, 'resolved_by', new.resolved_by, 'resolved_at', new.resolved_at,
                             'source', 'fn_os_incident_close_task'));
      end if;
    end if;
    -- capture the lesson so the resolution is remembered, not re-learned
    begin
      insert into public.institutional_memory
        (kind, subject_type, subject_id, headline, detail, outcome, learned_by, confidence, evidence_ref, occurred_at)
      values ('incident', 'os_incident', new.id::text,
              left('Incident resolved: '||coalesce(new.title, '#'||new.id::text), 200),
              left(coalesce(new.detail->>'resolution', new.detail->>'description',
                            'Resolved on '||to_char(now(),'DD Mon YYYY')), 2000),
              'resolved', coalesce(new.owner, 'system'), 0.7, 'os_incident#'||new.id, now());
    exception when others then null; end;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_os_incident_list(p_status text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'title',title,'kind',kind,'severity',severity,'status',status,
    'description',detail->>'description','opened_by',opened_by,'opened_at',opened_at,
    'resolved_at',resolved_at,'resolution',resolution) order by (status='open') desc, opened_at desc), '[]'::jsonb)
  from public.os_incidents
  where p_status is null or p_status='' or status = p_status;
$function$


CREATE OR REPLACE FUNCTION public.fn_os_incident_open(p_title text, p_kind text, p_severity text, p_detail jsonb, p_actor text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare nid bigint;
begin
  if coalesce(p_title, '') = '' then return jsonb_build_object('ok', false, 'error', 'title_required'); end if;
  insert into public.os_incidents (title, kind, severity, detail, opened_by)
  values (p_title, coalesce(nullif(p_kind, ''), 'other'), coalesce(nullif(p_severity, ''), 'medium'),
          coalesce(p_detail, '{}'::jsonb), coalesce(p_actor, 'os'))
  returning id into nid;
  insert into public.os_audit_log (actor, action, entity, entity_id, detail, ok)
  values (coalesce(p_actor, 'os'), 'incident_open', 'incident', nid::text,
          jsonb_build_object('title', p_title, 'severity', p_severity), true);
  -- Best effort, as before: an incident is recorded even when telling someone about it fails.
  begin
    perform public.fn_notify_founder(
      p_event       => 'OS incident #' || nid || ' (' || coalesce(nullif(p_severity, ''), 'medium') || '): ' || p_title,
      p_detail      => left(coalesce(p_detail->>'description', ''), 300),
      p_level       => coalesce(nullif(p_severity, ''), 'medium'),
      p_kind        => 'os_incident',
      p_dedupe_key  => 'os_incident:' || nid,
      p_owner_agent => 'it_engineer');
  exception when others then
    insert into public.os_audit_log (actor, action, entity, entity_id, detail, ok)
    values (coalesce(p_actor, 'os'), 'incident_notify', 'incident', nid::text,
            jsonb_build_object('error', left(sqlerrm, 500)), false);
  end;
  return jsonb_build_object('ok', true, 'id', nid);
end $function$


CREATE OR REPLACE FUNCTION public.fn_os_incident_open_task()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_task bigint; v_dept text;
begin
  if new.org_task_id is not null then return new; end if;
  begin
    v_dept := coalesce((select department from public.org_agents where agent_key = new.owner), 'assurance');
    insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
    values (
      v_dept,
      'Incident #'||new.id||': '||new.title,
      'Severity '||coalesce(new.severity,'medium')||', kind '||coalesce(new.kind,'other')
        ||'. Owner '||coalesce(new.owner,'security')
        ||'. Due '||to_char(new.due_at,'YYYY-MM-DD HH24:MI')||' UTC. '
        ||coalesce(new.detail->>'description', left(new.detail::text,300)),
      'assigned',
      case when coalesce(new.severity,'medium') in ('critical','high') then 'supervised' else 'advisory' end,
      false,
      'incident')
    returning id into v_task;
    update public.os_incidents set org_task_id = v_task where id = new.id;
  exception when others then
    -- the incident is recorded regardless; the task is a best-effort companion
    null;
  end;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_os_incident_resolve(p_id bigint, p_resolution text, p_actor text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE public.os_incidents SET status='resolved', resolved_by=coalesce(p_actor,'os'), resolved_at=now(), resolution=nullif(p_resolution,'')
  WHERE id=p_id AND status <> 'resolved';
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','not_found_or_already_resolved'); END IF;
  INSERT INTO public.os_audit_log(actor,action,entity,entity_id,detail,ok)
  VALUES (coalesce(p_actor,'os'),'incident_resolve','incident',p_id::text,jsonb_build_object('resolution',p_resolution),true);
  RETURN jsonb_build_object('ok',true);
END $function$


CREATE OR REPLACE FUNCTION public.fn_os_incident_set_owner_and_due()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_sla interval;
begin
  if new.owner is null then
    new.owner := 'it_engineer';
  end if;
  if new.due_at is null then
    v_sla := case coalesce(new.severity,'medium')
               when 'critical' then interval '4 hours'
               when 'high'     then interval '24 hours'
               when 'medium'   then interval '72 hours'
               else interval '7 days' end;
    new.due_at := coalesce(new.opened_at, now()) + v_sla;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_os_list(p_entity text, p_params jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  v_tbl text; v_cols text; v_search text[]; v_status text; v_order text; v_idcol text := 'id';
  v_q text := coalesce(nullif(trim(p_params->>'q'),''), null);
  v_st text := coalesce(nullif(trim(p_params->>'status'),''), null);
  v_limit int := least(coalesce((p_params->>'limit')::int, 60), 300);
  v_offset int := greatest(coalesce((p_params->>'offset')::int, 0), 0);
  v_where text := ' where true'; v_rows jsonb; v_total bigint; v_sql text; v_fk text; v_fv text;
begin
  case p_entity
    when 'inquiries' then v_tbl:='inquiries'; v_cols:='id,category,emirate,status,pipeline_stage,scope_type,budget,expected_value,rfq_ready,customer_id,hired_supplier_id,outcome,created_at'; v_search:=array['category','emirate','summary','role_needed']; v_status:='status'; v_order:=' order by created_at desc';
    when 'quotes' then v_tbl:='quotes'; v_cols:='id,inquiry_id,supplier_id,quote_amount,customer_price,app_fee,status,review_status,lead_time,warranty,created_at,expires_at'; v_search:=array['notes','scope','payment_terms']; v_status:='status'; v_order:=' order by created_at desc';
    when 'transactions' then v_tbl:='transactions'; v_cols:='id,inquiry_id,supplier_id,customer_id,quote_amount,reveal_fee,app_fee,fee_status,refund_status,revealed_at,payment_ref'; v_search:=array['payment_ref','refund_reason']; v_status:='fee_status'; v_order:=' order by revealed_at desc nulls last';
    when 'customers' then v_tbl:='customers'; v_cols:='id,full_name,email,phone,email_verified,phone_verified,banned,chat_strikes,locale,created_at'; v_search:=array['full_name','email','phone']; v_status:=null; v_order:=' order by created_at desc';
    when 'suppliers' then v_tbl:='leads'; v_cols:='id,company_name,sector,emirate,city,approval_status,verification_status,verified,matching_blocked,banned,rating,app_rating,capability_score,registration_status,contact_name,email,phone,created_at'; v_search:=array['company_name','email','sector','phone']; v_status:='approval_status'; v_order:=' order by created_at desc';
    when 'agent_actions' then v_tbl:='agent_actions'; v_cols:='id,agent,kind,title,status,risk,confidence,target_table,target_id,escalated,created_at,decided_at,decided_by'; v_search:=array['title','recommendation','agent','kind']; v_status:='status'; v_order:=' order by (status=''pending'') desc, created_at desc';
    when 'doc_reviews' then v_tbl:='doc_reviews'; v_cols:='id,from_email,subject,file_name,ai_category,ai_suggested_field,ai_confidence,status,auto_applied,created_at,file_path'; v_search:=array['subject','from_email','file_name','ai_category']; v_status:='status'; v_order:=' order by created_at desc';
    when 'kb_revisions' then v_tbl:='kb_revisions'; v_cols:='id,entry_kind,entry_ref,version,status,author,reviewer,created_at,decided_at'; v_search:=array['entry_ref','entry_kind','author']; v_status:='status'; v_order:=' order by created_at desc';
    when 'inbox' then v_tbl:='inbound_messages'; v_cols:='id,from_email,to_email,subject,ai_category,needs_review,attachments_count,replied_at,created_at'; v_search:=array['subject','from_email','ai_summary']; v_status:='ai_category'; v_order:=' order by created_at desc';
    when 'documents' then v_tbl:='documents'; v_cols:='id,file_name,kind,ref_table,ref_id,mime,status,indexed,bucket,path,created_at'; v_search:=array['file_name','kind','ref_table']; v_status:='status'; v_order:=' order by created_at desc';
    when 'dropbox' then v_tbl:='dropbox_files'; v_cols:='id,path,name,is_folder,size,server_modified,synced_at'; v_search:=array['path','name']; v_status:=null; v_order:=' order by is_folder desc, name asc';
    when 'invoices' then v_tbl:='reveal_invoices'; v_cols:='transaction_id,invoice_no,bucket,path,created_at'; v_search:=array['invoice_no']; v_status:=null; v_order:=' order by created_at desc'; v_idcol:='transaction_id';
    when 'notifications' then v_tbl:='notifications'; v_cols:='id,type,to_email,to_role,subject,status,channel,created_at,sent_at,last_error'; v_search:=array['subject','to_email','type']; v_status:='status'; v_order:=' order by created_at desc';
    when 'tasks' then v_tbl:='crm_tasks'; v_cols:='id,title,status,priority,entity,entity_id,due_date,created_at,done_at'; v_search:=array['title','detail']; v_status:='status'; v_order:=' order by (status<>''done'') desc, due_date asc nulls last';
    when 'notes' then v_tbl:='crm_notes'; v_cols:='id,entity,entity_id,body,author,created_at'; v_search:=array['body','author']; v_status:=null; v_order:=' order by created_at desc';
    when 'po' then v_tbl:='po_orders'; v_cols:='id,po_no,vendor_id,status,subtotal,currency,order_date,expected_date,approved_by,approved_at,created_at'; v_search:=array['po_no','memo']; v_status:='status'; v_order:=' order by created_at desc';
    when 'expenses' then v_tbl:='expenses'; v_cols:='id,vendor,category,description,amount,currency,cadence,expense_date,active,created_at'; v_search:=array['vendor','description','category']; v_status:=null; v_order:=' order by expense_date desc nulls last';
    when 'agent_runs' then v_tbl:='agent_runs'; v_cols:='id,agent,status,started_at,finished_at,note'; v_search:=array['agent','note']; v_status:='status'; v_order:=' order by started_at desc nulls last';
    when 'fraud' then v_tbl:='fraud_flags'; v_cols:='kind,subject_type,subject_id,severity,status,detail,created_at'; v_search:=array['kind','subject_type','subject_id']; v_status:='status'; v_order:=' order by created_at desc'; v_idcol:='subject_id';
    else return jsonb_build_object('error','unknown_entity','entity',p_entity);
  end case;

  if v_st is not null and v_status is not null then v_where := v_where || format(' and %I = %L', v_status, v_st); end if;
  if v_q is not null then
    v_where := v_where || ' and (' || array_to_string(array(select format('coalesce(%I::text,'''') ilike %L', c, '%'||v_q||'%') from unnest(v_search) c), ' or ') || ')';
  end if;
  if p_params ? 'filters' then
    for v_fk, v_fv in select key, value from jsonb_each_text(p_params->'filters') loop
      if v_fk = any(array['inquiry_id','supplier_id','customer_id','quote_id','ref_table','ref_id','agent','entity','entity_id','category','emirate','lead_id','vendor_id','target_table','target_id']) and position(v_fk in v_cols) > 0 and v_fv is not null then
        v_where := v_where || format(' and %I::text = %L', v_fk, v_fv);
      end if;
    end loop;
  end if;

  execute format('select count(*) from %I%s', v_tbl, v_where) into v_total;
  v_sql := format('select coalesce(jsonb_agg(to_jsonb(t)),''[]''::jsonb) from (select %s from %I%s%s limit %s offset %s) t', v_cols, v_tbl, v_where, v_order, v_limit, v_offset);
  execute v_sql into v_rows;
  return jsonb_build_object('entity',p_entity,'id_col',v_idcol,'columns',string_to_array(v_cols, ','),'total',v_total,'rows',v_rows);
end $function$


CREATE OR REPLACE FUNCTION public.fn_os_memory(p_q text DEFAULT NULL::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with b as (select coalesce(nullif(btrim(p_q), ''), '') q,
                    coalesce(p_from, '-infinity'::date) lo,
                    coalesce(p_to, 'infinity'::date) hi)
  select jsonb_build_object(
    'subject', (select q from b), 'from', p_from, 'to', p_to,

    -- Every decision about a subject, over a period.
    'decisions', coalesce((select jsonb_agg(jsonb_build_object(
          'id', l.id, 'actor', l.actor, 'kind', l.kind, 'decision', l.decision,
          'confidence', l.confidence, 'reasons', l.reasons, 'route_to', l.route_to, 'at', l.created_at)
        order by l.created_at desc)
      from (select l.* from public.decision_log l, b
             where (b.q = '' or l.decision ilike '%'||b.q||'%' or l.actor ilike '%'||b.q||'%'
                    or l.kind ilike '%'||b.q||'%' or l.ctx::text ilike '%'||b.q||'%')
               and l.created_at::date between b.lo and b.hi
             order by l.created_at desc limit 25) l), '[]'::jsonb),

    -- Why something was rejected: the recorded reasoning behind a past decision.
    'rejection_reason', coalesce((select jsonb_agg(jsonb_build_object(
          'id', d.id, 'problem', d.problem, 'recommendation', d.recommendation,
          'risks', d.risks, 'options', d.options, 'status', d.status,
          'decided_by', d.decided_by, 'actual_outcome', d.actual_outcome, 'at', d.created_at)
        order by d.created_at desc)
      from (select d.* from public.decision_record d, b
             where (b.q = '' or d.problem ilike '%'||b.q||'%' or d.recommendation ilike '%'||b.q||'%'
                    or d.context ilike '%'||b.q||'%')
               and d.created_at::date between b.lo and b.hi
             order by d.created_at desc limit 15) d), '[]'::jsonb),

    -- When something changed, and who changed it. undo_log is the row-level change history.
    'changes', coalesce((select jsonb_agg(jsonb_build_object(
          'id', u.id, 'table_name', u.table_name, 'row_id', u.row_id, 'op', u.op,
          'actor', u.actor, 'reverted', u.reverted, 'at', u.created_at)
        order by u.created_at desc)
      from (select u.* from public.undo_log u, b
             where (b.q = '' or u.table_name ilike '%'||b.q||'%' or u.actor ilike '%'||b.q||'%')
               and u.created_at::date between b.lo and b.hi
             order by u.created_at desc limit 25) u), '[]'::jsonb),
    'change_subjects', coalesce((select jsonb_agg(jsonb_build_object('table_name', t.table_name, 'n', t.n) order by t.n desc)
      from (select table_name, count(*) n from public.undo_log group by 1) t), '[]'::jsonb),

    -- Lessons, scoped to a period.
    'lessons', coalesce((select jsonb_agg(jsonb_build_object(
          'id', m.id, 'headline', m.headline, 'detail', left(m.detail, 300), 'outcome', m.outcome,
          'kind', m.kind, 'os_key', m.os_key, 'confidence', m.confidence, 'occurred_at', m.occurred_at)
        order by coalesce(m.occurred_at, m.created_at) desc)
      from (select m.* from public.institutional_memory m, b
             where (b.q = '' or m.headline ilike '%'||b.q||'%' or m.detail ilike '%'||b.q||'%'
                    or m.category_slug ilike '%'||b.q||'%')
               and coalesce(m.occurred_at, m.created_at)::date between b.lo and b.hi
             order by coalesce(m.occurred_at, m.created_at) desc limit 20) m), '[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_os_nav()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'badges', jsonb_build_object(
      'approvals', (select count(*) from agent_actions where status='pending'),
      'tasks', (select count(*) from crm_tasks where coalesce(status,'') <> 'done'),
      'suppliers_review', (select count(*) from leads where coalesce(approval_status,'') in ('submitted','pending','under_review','pending_review')),
      'notifications', (select count(*) from notifications where coalesce(status,'') not in ('sent','delivered','read')),
      'knowledge_review', (select count(*) from kb_revisions where coalesce(status,'')='pending'),
      'documents_review', (select count(*) from doc_reviews where coalesce(status,'')='pending'),
      'disputes', (select count(*) from transactions where coalesce(refund_status,'') in ('requested','pending')),
      'fraud_open', (select count(*) from fraud_flags where coalesce(status,'open') not in ('dismissed','resolved','closed')),
      'rfqs_active', (select count(*) from inquiries where coalesce(status,'') not in ('completed','cancelled','closed'))
    ),
    'generated_at', now()
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_os_open_access()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce((select state = 'open' from public.os_open_access_log order by id desc limit 1), false);
$function$


CREATE OR REPLACE FUNCTION public.fn_os_reconcile()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE res jsonb; gl_diff numeric;
BEGIN
  BEGIN SELECT coalesce(sum(debit),0) - coalesce(sum(credit),0) INTO gl_diff FROM public.gl_journal_lines;
  EXCEPTION WHEN others THEN gl_diff := NULL; END;
  SELECT jsonb_build_object(
    'generated_at', now(),
    'transactions_total', (SELECT count(*) FROM public.transactions),
    'revenue_reveal_fees_aed', coalesce((SELECT round(sum(reveal_fee)::numeric,2) FROM public.transactions),0),
    'refunds_pending', (SELECT count(*) FROM public.transactions WHERE refund_status='requested'),
    'refunds_resolved', (SELECT count(*) FROM public.transactions WHERE refund_status IS NOT NULL AND refund_status <> 'requested'),
    'stripe_events_total', (SELECT count(*) FROM public.stripe_events),
    'stripe_paid_checkouts', (SELECT count(*) FROM public.stripe_events WHERE type='checkout.session.completed' AND payment_status='paid'),
    'gl_debits_minus_credits', CASE WHEN gl_diff IS NULL THEN NULL ELSE round(gl_diff,2) END,
    'gl_balanced', CASE WHEN gl_diff IS NULL THEN NULL ELSE (abs(gl_diff) < 0.01) END
  ) INTO res;
  RETURN res;
END $function$


CREATE OR REPLACE FUNCTION public.fn_os_record(p_entity text, p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v jsonb;
begin
  if p_entity='supplier' then select to_jsonb(l) into v from leads l where l.id = p_id::bigint;
  elsif p_entity='rfq' then select to_jsonb(i) into v from inquiries i where i.id = p_id::uuid;
  elsif p_entity='customer' then select to_jsonb(c) into v from customers c where c.id = p_id::uuid;
  elsif p_entity='quote' then select to_jsonb(q) into v from quotes q where q.id = p_id::uuid;
  elsif p_entity='agent_action' then select to_jsonb(a) into v from agent_actions a where a.id = p_id::bigint;
  elsif p_entity='task' then select to_jsonb(t) into v from crm_tasks t where t.id = p_id::bigint;
  else v := null; end if;
  return jsonb_build_object('entity',p_entity,'id',p_id,'record',v);
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_os_review()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_period text := to_char(now(),'IYYY-"W"IW');
  v_health text; v_find jsonb; v_act int; v_total int := 0; v_red int := 0; v_amber int := 0;
  v_missed int; v_stale int; v_overspend numeric; v_score numeric; v_dept text; v_dept_os text;
  v_emitted int := 0; v_prev text;
begin
  -- BOTH views, joined, and not one or the other. v_os_health projects only a SUBSET of
  -- v_os_scoreboard: it carries open_risks/review_pass_pct/needs_founder_pct/backlog_per_head but
  -- drops kpis, kpis_unmeasurable and departments. Swapping the source outright would have
  -- compiled, deployed, reported success and then failed at call time on r.kpis — the exact class
  -- of bug that only a fixture catches.
  for r in select h.*, s.kpis, s.kpis_unmeasurable, s.departments
             from v_os_health h join v_os_scoreboard s on s.os_key = h.os_key loop
    v_find := '[]'::jsonb; v_act := 0;

    v_missed    := coalesce(r.kpi_gaps, 0);
    v_stale     := coalesce(r.stale_tasks, 0);
    v_overspend := coalesce(r.budget_pct, 0);

    if r.employees = 0 then
      v_find := v_find || jsonb_build_array(jsonb_build_object('issue','no employees','detail','This operating system has no staff.'));
    end if;
    if r.kpis = 0 then
      v_find := v_find || jsonb_build_array(jsonb_build_object('issue','no KPIs','detail','This operating system cannot be held to account.'));
    end if;
    if r.kpis_unmeasurable > 0 then
      v_find := v_find || jsonb_build_array(jsonb_build_object('issue','unmeasurable KPIs','detail',r.kpis_unmeasurable||' KPI(s) have no measure.'));
    end if;
    if v_missed > 0 then
      v_find := v_find || jsonb_build_array(jsonb_build_object('issue','KPIs missing target','detail',v_missed||' unclosed KPI gap(s).'));
    end if;
    if v_stale > 0 then
      v_find := v_find || jsonb_build_array(jsonb_build_object('issue','stale work','detail',v_stale||' task(s) open more than 14 days.'));
    end if;
    if coalesce(r.open_risks,0) > 0 then
      v_find := v_find || jsonb_build_array(jsonb_build_object('issue','open risks','detail',r.open_risks||' risk(s) owned inside this OS.'));
    end if;
    if v_overspend >= 95 then
      v_find := v_find || jsonb_build_array(jsonb_build_object('issue','budget halt','detail',v_overspend||'% of monthly AI budget spent.'));
    elsif v_overspend >= 70 then
      v_find := v_find || jsonb_build_array(jsonb_build_object('issue','budget degrade','detail',v_overspend||'% of monthly AI budget spent.'));
    end if;

    v_health := case
      when r.employees = 0 or r.kpis = 0 or v_overspend >= 95 then 'red'
      when jsonb_array_length(v_find) > 0 then 'amber'
      else 'green' end;

    -- The two verdicts are driven by the same inputs on purpose. A green OS scores at least 85 and
    -- a red one at most 60, so "green with a score of 40" is not a state this can produce — a text
    -- verdict and a number that can disagree is worse than either alone.
    v_score := greatest(0, 100
      - (case when r.employees = 0 then 40 else 0 end)
      - (case when r.kpis = 0 then 40 else 0 end)
      - least(20, coalesce(r.kpis_unmeasurable,0) * 4)
      - least(15, v_missed * 3)
      - least(15, v_stale * 2)
      - least(10, coalesce(r.open_risks,0) * 3)
      - (case when v_overspend >= 95 then 25 when v_overspend >= 70 then 10 else 0 end));

    select os.health_score::text into v_prev from operating_system os where os.os_key = r.os_key;

    update operating_system
       set health_score = v_score, last_health_at = now()
     where os_key = r.os_key;

    -- xos-12 / comp-07. Own OS -> a task, which is not a cross-OS call. Anything else -> the bus.
    select coalesce(a.department, null) into v_dept from org_agents a where a.agent_key = r.owner_agent;
    select od.os_key into v_dept_os from os_department od where od.dept_key = v_dept;

    if v_health <> 'green' then
      if v_dept is not null and v_dept_os is not distinct from r.os_key then
        insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
        select v_dept,
               'OS review ['||v_health||']: '||r.name,
               'Owner: '||coalesce(r.owner_agent,'unassigned')||'. Week '||v_period||'. Findings: '||v_find::text
               ||'. Close each finding or bring evidence the standard is wrong.',
               'proposed','advisory', false, 'exec_review'
        where not exists (select 1 from org_tasks t2 where t2.title like 'OS review [%]: '||r.name and t2.status <> 'done');
        get diagnostics v_act = row_count;
      else
        -- The old code wrote this into 'exec' — a different OS — which is exactly what xos-12
        -- forbids. Emitting means leadership receives it through the bus it already subscribes to.
        perform public.fn_emit('os.health_changed', 'operating_system', r.os_key, 'fn_os_review',
                 jsonb_build_object('os_key', r.os_key, 'health', v_health, 'score', v_score,
                                    'period', v_period, 'findings', v_find,
                                    'reason', 'owner agent resolves to no department inside this OS'));
        v_emitted := v_emitted + 1;
      end if;
    end if;

    -- comp-07 / xos-13. os.health_changed was DECLARED by leadership and had never once fired.
    -- Emitted on a real transition only: emitting every week whether or not anything moved is how
    -- an event stream becomes noise nobody subscribes to.
    if v_prev is distinct from v_score::text then
      perform public.fn_emit('os.health_changed', 'operating_system', r.os_key, 'fn_os_review',
               jsonb_build_object('os_key', r.os_key, 'health', v_health, 'score', v_score,
                                  'previous_score', v_prev, 'period', v_period));
      v_emitted := v_emitted + 1;
    end if;

    insert into os_review (os_key, period, owner_agent, health, metrics, findings, actions)
    values (r.os_key, v_period, r.owner_agent, v_health,
            jsonb_build_object('departments',r.departments,'employees',r.employees,'open_tasks',r.open_tasks,
                               'kpis',r.kpis,'kpis_unmeasurable',r.kpis_unmeasurable,
                               'budget_pct',v_overspend,'kpi_gaps',v_missed,'stale_tasks',v_stale,
                               -- the four v_os_health columns that had no reader at all
                               'health_score',v_score,
                               'open_risks',coalesce(r.open_risks,0),
                               'review_pass_pct',r.review_pass_pct,
                               'needs_founder_pct',r.needs_founder_pct,
                               'backlog_per_head',r.backlog_per_head,
                               -- comp-16-capacity. resource_pool is `committed` against
                               -- `capacity`; there is no `used` column, and guessing one would
                               -- have deployed and failed at call time.
                               'capacity_pct',(select round(100.0*sum(rp.committed)/nullif(sum(rp.capacity),0),1)
                                                 from resource_pool rp where rp.os_key = r.os_key)),
            v_find, v_act)
    on conflict (os_key, period) do update
      set health=excluded.health, metrics=excluded.metrics, findings=excluded.findings,
          actions=excluded.actions, created_at=now();

    v_total := v_total + 1;
    if v_health='red' then v_red := v_red+1; elsif v_health='amber' then v_amber := v_amber+1; end if;
  end loop;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  -- A review that FOUND red KPIs succeeded: the reds are its findings, carried in counts (red/amber/
  -- green) exactly as kpi_review / objective_review / promotion_review carry theirs. Logging them as
  -- status='error' made the failed-run reader count a working review as a failure every week, and
  -- fn_self_review — which reads agent_runs errors to find RECURRING failures — would have read the
  -- review itself as a repeatedly-failing agent. Fixed 3 Sep 2026.
  values ('os_review', now(), now(), 'ok',
          jsonb_build_object('reviewed',v_total,'red',v_red,'amber',v_amber,'green',v_total-v_red-v_amber,'emitted',v_emitted),
          'Operating system review, week '||v_period||': '||(v_total-v_red-v_amber)||' green, '||v_amber||' amber, '||v_red||' red.');

  return jsonb_build_object('reviewed',v_total,'red',v_red,'amber',v_amber,'green',v_total-v_red-v_amber,
                            'events_emitted',v_emitted);
end $function$


CREATE OR REPLACE FUNCTION public.fn_os_runbooks()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('slug',slug,'title',title,'category',category,'when_to_use',when_to_use,'steps',steps) order by sort, title), '[]'::jsonb)
  from public.os_runbooks;
$function$


CREATE OR REPLACE FUNCTION public.fn_os_search(p_q text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with b as (select coalesce(nullif(btrim(p_q), ''), '') q,
                    '-infinity'::date lo, 'infinity'::date hi)
  select jsonb_build_object(
    'query', (select q from b),

    'suppliers', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',company_name,'sub',emirate||' · '||coalesce(sector,''))) from (
        select l.id, l.company_name, l.emirate, l.sector from public.leads l, b
         where b.q <> '' and l.company_name ilike '%'||b.q||'%'
         order by l.capability_score desc nulls last limit 6) s),'[]'::jsonb),

    'rfqs', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',coalesce(summary,category),'sub',category)) from (
        select i.id, i.summary, i.category from public.inquiries i, b
         where b.q <> '' and (i.summary ilike '%'||b.q||'%' or i.category ilike '%'||b.q||'%')
           and i.created_at::date between b.lo and b.hi
         order by i.created_at desc limit 6) r),'[]'::jsonb),

    'customers', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',full_name,'sub',email)) from (
        select c.id, c.full_name, c.email from public.customers c, b
         where b.q <> '' and (c.full_name ilike '%'||b.q||'%' or c.email ilike '%'||b.q||'%') limit 6) c),'[]'::jsonb),

    -- ── WHAT THE COMPANY KNOWS ───────────────────────────────────────────────────────────────
    -- 2.69M chunks: the generated `fts` column and its GIN index are the only way through this
    -- table inside the 8 s request budget. First eight hits, unordered — an ORDER BY here makes
    -- Postgres collect every match before it can return one (measured 8 s+ for "fit").
    'knowledge', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',title,'sub',citation,'at',effective_date)) from (
        select k.id, k.title, k.citation, k.effective_date from public.kb_chunks k, b
         where b.q <> '' and k.fts @@ plainto_tsquery('english', b.q)
         limit 8) k),'[]'::jsonb),

    'documents', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',file_name,'sub',kind,'at',created_at)) from (
        select d.id, d.file_name, d.kind, d.created_at from public.documents d, b
         where b.q <> '' and (d.file_name ilike '%'||b.q||'%' or d.kind ilike '%'||b.q||'%')
           and d.created_at::date between b.lo and b.hi
         order by d.created_at desc limit 6) d),'[]'::jsonb),

    -- ── WHAT THE COMPANY REMEMBERS ───────────────────────────────────────────────────────────
    'lessons', coalesce((select jsonb_agg(jsonb_build_object(
          'id',id,'name',headline,'sub',outcome,'detail',left(detail,240),'kind',kind,
          'os_key',os_key,'confidence',confidence,'occurred_at',occurred_at)) from (
        select m.* from public.institutional_memory m, b
         where (b.q = '' or m.headline ilike '%'||b.q||'%' or m.detail ilike '%'||b.q||'%'
                or m.category_slug ilike '%'||b.q||'%')
           and coalesce(m.occurred_at, m.created_at)::date between b.lo and b.hi
         order by coalesce(m.occurred_at, m.created_at) desc limit 10) m),'[]'::jsonb),

    'org_memory', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',left(content,120),'sub',scope||' · '||coalesce(kind,''),'at',created_at)) from (
        select o.id, o.content, o.scope, o.kind, o.created_at from public.org_memory o, b
         where b.q <> '' and (o.content ilike '%'||b.q||'%' or o.scope ilike '%'||b.q||'%')
           and o.created_at::date between b.lo and b.hi
         order by o.created_at desc limit 8) o),'[]'::jsonb),

    'agent_memory', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',left(content,120),'sub',agent_key||' · '||coalesce(kind,''),'at',created_at)) from (
        select a.id, a.content, a.agent_key, a.kind, a.created_at from public.agent_memory a, b
         where b.q <> '' and (a.content ilike '%'||b.q||'%' or a.agent_key ilike '%'||b.q||'%')
           and a.created_at::date between b.lo and b.hi
         order by a.created_at desc limit 8) a),'[]'::jsonb),

    -- ── WHAT THE COMPANY DECIDED ─────────────────────────────────────────────────────────────
    'decisions', coalesce((select jsonb_agg(jsonb_build_object(
          'id',id,'name',decision,'sub',actor||' · '||coalesce(kind,''),'reasons',reasons,
          'confidence',confidence,'route_to',route_to,'at',created_at)) from (
        select l.* from public.decision_log l, b
         where (b.q = '' or l.decision ilike '%'||b.q||'%' or l.actor ilike '%'||b.q||'%'
                or l.kind ilike '%'||b.q||'%' or l.ctx::text ilike '%'||b.q||'%')
           and l.created_at::date between b.lo and b.hi
         order by l.created_at desc limit 10) l),'[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_os_settings_history(p_key text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'at', at, 'actor', actor, 'action', action,
    'old', detail->>'old', 'new', detail->>'new') order by at desc), '[]'::jsonb)
  from public.os_audit_log
  where entity='setting' and entity_id=p_key and action in ('settings_set','settings_revert')
  limit 50;
$function$


CREATE OR REPLACE FUNCTION public.fn_os_settings_list()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(x order by x->>'grp', (x->>'sort')::int, x->>'label'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'key', m.key, 'grp', m.grp, 'type', m.type, 'label', m.label,
      'help', coalesce(m.help,''), 'validation', m.validation, 'dangerous', m.dangerous,
      'sort', m.sort, 'value', coalesce(s.value,'')
    ) as x
    from public.os_settings_meta m
    left join public.app_secrets s on s.key = m.key
  ) q;
$function$


CREATE OR REPLACE FUNCTION public.fn_os_settings_revert(p_key text, p_actor text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE prev text; oldv text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.os_settings_meta WHERE key=p_key) THEN
    RETURN jsonb_build_object('ok',false,'error','key_not_editable'); END IF;
  SELECT detail->>'old' INTO prev FROM public.os_audit_log
    WHERE entity='setting' AND entity_id=p_key AND action IN ('settings_set','settings_revert')
    ORDER BY at DESC LIMIT 1;
  IF prev IS NULL THEN RETURN jsonb_build_object('ok',false,'error','no_history_to_revert'); END IF;
  SELECT value INTO oldv FROM public.app_secrets WHERE key=p_key;
  INSERT INTO public.app_secrets(key,value) VALUES (p_key, prev)
    ON CONFLICT (key) DO UPDATE SET value = excluded.value;
  INSERT INTO public.os_audit_log(actor, action, entity, entity_id, detail, ok)
  VALUES (coalesce(p_actor,'os'), 'settings_revert', 'setting', p_key,
          jsonb_build_object('old', coalesce(oldv,''), 'new', prev), true);
  RETURN jsonb_build_object('ok',true,'key',p_key,'old',coalesce(oldv,''),'new',prev);
END $function$


CREATE OR REPLACE FUNCTION public.fn_os_settings_set(p_key text, p_value text, p_actor text, p_confirm boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE m public.os_settings_meta; v text := coalesce(p_value,''); n numeric; oldv text; mn numeric; mx numeric; ml int;
BEGIN
  SELECT * INTO m FROM public.os_settings_meta WHERE key = p_key;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','key_not_editable'); END IF;
  IF m.dangerous AND NOT p_confirm THEN RETURN jsonb_build_object('ok',false,'needs_confirm',true,'label',m.label); END IF;

  mn := nullif(m.validation->>'min','')::numeric;
  mx := nullif(m.validation->>'max','')::numeric;
  ml := nullif(m.validation->>'maxlen','')::int;

  IF m.type IN ('money','number','int') THEN
    BEGIN n := v::numeric; EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok',false,'error','must_be_a_number'); END;
    IF m.type='int' AND n <> trunc(n) THEN RETURN jsonb_build_object('ok',false,'error','must_be_a_whole_number'); END IF;
    IF mn IS NOT NULL AND n < mn THEN RETURN jsonb_build_object('ok',false,'error','below_minimum','min',mn); END IF;
    IF mx IS NOT NULL AND n > mx THEN RETURN jsonb_build_object('ok',false,'error','above_maximum','max',mx); END IF;
    v := n::text;
  ELSIF m.type='bool' THEN
    v := lower(v);
    IF v IN ('true','1','yes','on') THEN v:='true'; ELSIF v IN ('false','0','no','off','') THEN v:='false';
    ELSE RETURN jsonb_build_object('ok',false,'error','must_be_true_or_false'); END IF;
  ELSIF m.type='email' THEN
    IF v <> '' AND position('@' in v) = 0 THEN RETURN jsonb_build_object('ok',false,'error','not_an_email'); END IF;
    IF ml IS NOT NULL AND length(v) > ml THEN RETURN jsonb_build_object('ok',false,'error','too_long','maxlen',ml); END IF;
  ELSE
    IF ml IS NOT NULL AND length(v) > ml THEN RETURN jsonb_build_object('ok',false,'error','too_long','maxlen',ml); END IF;
  END IF;

  SELECT value INTO oldv FROM public.app_secrets WHERE key = p_key;
  INSERT INTO public.app_secrets(key,value) VALUES (p_key, v)
    ON CONFLICT (key) DO UPDATE SET value = excluded.value;

  INSERT INTO public.os_audit_log(actor, action, entity, entity_id, detail, ok)
  VALUES (coalesce(p_actor,'os'), 'settings_set', 'setting', p_key,
          jsonb_build_object('old', coalesce(oldv,''), 'new', v, 'label', m.label), true);

  RETURN jsonb_build_object('ok',true,'key',p_key,'old',coalesce(oldv,''),'new',v);
END $function$


CREATE OR REPLACE FUNCTION public.fn_otp_prefix_blocked(p_phone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists (select 1 from public.otp_blocked_prefix b
                  where regexp_replace(coalesce(p_phone, ''), '\D', '', 'g') like b.prefix || '%'
                    and (b.expires_at is null or b.expires_at > now()))
$function$


CREATE OR REPLACE FUNCTION public.fn_outcome_open(p_actor text, p_decision text, p_subject_type text DEFAULT 'manual'::text, p_subject_id text DEFAULT NULL::text, p_expected_kpi_id bigint DEFAULT NULL::bigint, p_rationale text DEFAULT NULL::text, p_evidence jsonb DEFAULT '[]'::jsonb, p_direction text DEFAULT 'up'::text, p_measure_after interval DEFAULT '14 days'::interval)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_sql text; v_base numeric; v_metric text; v_dept text; v_id bigint;
begin
  p_actor := coalesce(public.fn_org_agent_resolve(p_actor), p_actor);
  if p_expected_kpi_id is not null then
    select measure_sql, metric into v_sql, v_metric from employee_kpi where id = p_expected_kpi_id;
    begin
      if v_sql is not null then execute v_sql into v_base; end if;
    exception when others then v_base := null; end;
  end if;

  select a.department into v_dept from org_agents a where a.agent_key = p_actor;

  insert into outcome_record (actor, dept_key, subject_type, subject_id, decision, rationale,
                              evidence, expected_kpi_id, expected_metric, expected_direction,
                              baseline_value, measure_after, due_at)
  values (p_actor, v_dept, p_subject_type, p_subject_id, p_decision, p_rationale,
          coalesce(p_evidence,'[]'::jsonb), p_expected_kpi_id, v_metric,
          coalesce(p_direction,'up'), v_base, coalesce(p_measure_after, interval '14 days'),
          now() + coalesce(p_measure_after, interval '14 days'))
  returning id into v_id;
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_outcome_record(p_table text, p_id text, p_kind text, p_correct boolean, p_reason text, p_default_seat text DEFAULT NULL::text, p_case_kind text DEFAULT NULL::text, p_situation text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_seat text; v_n integer; v_lesson text;
begin
  if coalesce(btrim(p_kind), '') = '' or coalesce(btrim(p_reason), '') = '' then
    raise exception 'an outcome names its kind and its reason' using errcode = '22023';
  end if;
  -- THE SEAT THAT DECIDED: the latest judgement on this subject. The default only opens a case where none decided.
  select j.seat into v_seat from public.seat_judgement j
   where j.subject_table = p_table and j.subject_id = p_id order by j.id desc limit 1;
  v_seat := coalesce(v_seat, p_default_seat);
  v_n := public.fn_judgement_outcome(p_table, p_id, p_kind || ': ' || p_reason, p_correct, true, v_seat, p_case_kind, p_situation);
  update public.seat_judgement set outcome_kind = p_kind, outcome_reason = left(p_reason, 1000)
   where subject_table = p_table and subject_id = p_id;
  if p_correct is false then
    v_lesson := left('Outcome ' || p_kind || ': ' || p_reason, 500);
    update public.seat_case_memory
       set lessons = case when v_lesson = any (lessons) then lessons else lessons || v_lesson end, updated_at = now()
     where source_table = p_table and source_id = p_id;
  end if;
  return jsonb_build_object('judgements', v_n, 'seat', v_seat, 'kind', p_kind, 'correct', p_correct);
end $function$


CREATE OR REPLACE FUNCTION public.fn_owning_os(p_agent text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with a as (select coalesce(nullif(btrim(p_agent), ''), '~none~') k),
  stripped as (
    -- widened from _(ai|director|ops|monitor|watch|agent|bot) so a role title resolves too
    select regexp_replace(a.k, '_(ai|director|ops|monitor|watch|agent|bot|controller|curator|analyst|engineer|manager|lead|head|specialist)$', '') s
    from a)
  select coalesce(
    (select o.os_key from public.operating_system o, a where o.owner_agent = a.k and o.active limit 1),
    (select r.os_key from public.os_responsibility r, a where r.responsibility = a.k limit 1),
    (select r.os_key from public.os_responsibility r
       join public.org_agents g on g.department = r.responsibility, a
      where g.agent_key = a.k limit 1),
    (select r.os_key from public.os_responsibility r, stripped where r.responsibility = stripped.s limit 1),
    (select o.os_key from public.operating_system o, a where o.os_key = a.k and o.active limit 1),
    (select o.os_key from public.operating_system o, stripped where o.os_key = stripped.s and o.active limit 1),
    -- the live department -> OS map, which this function never consulted
    (select d.os_key from public.os_department d
       join public.org_agents g on g.department = d.dept_key, a
      where g.agent_key = a.k limit 1),
    -- a category desk ('cat:signage') is owned by whichever OS owns category coverage
    (select r.os_key from public.os_responsibility r, a
      where a.k like 'cat:%' and r.responsibility = 'category_coverage' limit 1),
    -- last resort: a role name whose stem appears in a responsibility. Ordered by the shortest
    -- responsibility so the most specific owner wins rather than whichever row is read first.
    (select r.os_key from public.os_responsibility r, stripped
      where length(stripped.s) >= 4 and r.responsibility like '%' || stripped.s || '%'
      order by length(r.responsibility), r.responsibility limit 1)
  );
$function$


