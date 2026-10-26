-- PROBE: THE MARKETING SEAT WRITES ARTICLES AND DRAFTS THE FOUNDER'S LINKEDIN OUTREACH (22 Sep 2026; seat: marketing).
--
-- A pure probe (no DDL): it always ends in raise exception 'CHK<<...>>', so every row it writes -- the ZZ DEMO
-- people, messages, articles, their LinkedIn post drafts, and the switch it turns on for its own transaction --
-- rolls back with it. The verdict is the first key of the CHK payload: PROBE OK, or PROBE FAILED with what failed.
-- Run AFTER the_marketing_seat_publishes_measures_and_reports_spend.sql (#834) and
-- the_marketing_seat_writes_articles_and_drafts_linkedin_outreach.sql are applied.
--
-- WHAT IT PROVES: a person without a public source, or found only on LinkedIn, is refused; while the switch is
-- off the morning list is DRAFTS, nobody is used up and the email is a dry run; with the switch on (inside this
-- rolled-back transaction) a real-shaped person is listed and used up while a ZZ DEMO one never is; the marks move
-- a person forward only, a declining reply closes the person and drafts the courteous close; an article whose
-- checks are not clean is refused, a clean one lands as a draft with its LinkedIn post as a marketing_post draft,
-- the cadence releases only approved non-demo articles and only while the switch is on, and going live schedules
-- the post; the three tables are in the daily export; the report view reads.
-- It never calls fn_marketing_outreach_deliver on the live path, so no founder notification row is written at all.
--
--   node scripts/apply_sql.mjs scripts/sql/the_marketing_seat_writes_articles_and_drafts_linkedin_outreach_probe.sql --apply

do $probe$
declare
  r jsonb := '{}'::jsonb; x jsonb; v_bad text[] := '{}'; v_day date := (now() at time zone 'Asia/Dubai')::date;
  v_demo bigint; v_real bigint; v_tok uuid; v_follow uuid; v_art jsonb;
  v_clean jsonb := '{"lint":[],"ungrounded":[]}'::jsonb;
  v_src jsonb := '[{"ref":"src/content/marketing.json#faq.en.html","sha":"000000000000"}]'::jsonb;
begin
  update public.app_secrets set value = 'false' where key = 'marketing_golive';

  -- people
  x := public.fn_marketing_prospect_upsert('{"full_name":"ZZ DEMO Nosource","role_title":"PM","company":"ZZ DEMO Co","segment":"developer","is_demo":true}');
  if coalesce(x->>'error', '') <> 'source_urls_required' then v_bad := array_append(v_bad, 'no_source_accepted'::text); end if;
  x := public.fn_marketing_prospect_upsert('{"full_name":"ZZ DEMO Lionly","role_title":"PM","company":"ZZ DEMO Co","segment":"developer","is_demo":true,"source_urls":["https://www.linkedin.com/in/zz-demo"]}');
  if coalesce(x->>'error', '') <> 'linkedin_is_not_a_source' then v_bad := array_append(v_bad, 'linkedin_only_accepted'::text); end if;
  x := public.fn_marketing_prospect_upsert('{"full_name":"ZZ DEMO Sara","role_title":"Procurement Manager","company":"ZZ DEMO Contracting","segment":"contractor_procurement","is_demo":true,"source_urls":["https://example.invalid/team"],"opening_line":"Congratulations on the handover.","opening_line_url":"https://example.invalid/news"}');
  v_demo := (x->>'id')::bigint;
  if v_demo is null then v_bad := array_append(v_bad, 'demo_person_refused'::text); end if;

  -- held: drafts only, nobody used up, dry-run email
  x := public.fn_marketing_outreach_due(true);
  r := r || jsonb_build_object('due_held', x - 'prospects');
  if not exists (select 1 from jsonb_array_elements(x->'prospects') e where (e->>'id')::bigint = v_demo) then v_bad := array_append(v_bad, 'demo_not_offered_to_probe'::text); end if;
  x := public.fn_marketing_outreach_record(v_day, jsonb_build_array(jsonb_build_object('prospect_id', v_demo, 'language', 'en',
         'body', 'Hello ZZ DEMO,' || chr(10) || 'probe', 'note', 'Hello ZZ DEMO, probe', 'lint', '[]'::jsonb)));
  r := r || jsonb_build_object('record_held', x);
  if x->'items'->0->>'status' <> 'draft' then v_bad := array_append(v_bad, 'held_list_not_draft'::text); end if;
  if (select status from public.marketing_prospect where id = v_demo) <> 'new' then v_bad := array_append(v_bad, 'held_list_used_up_person'::text); end if;
  x := public.fn_marketing_outreach_deliver(v_day, array[(x->'items'->0->>'id')::bigint], 'probe', 'probe');
  if x->>'mode' <> 'dry_run' then v_bad := array_append(v_bad, 'held_list_emailed'::text); end if;
  -- re-drafting the same day replaces the draft in place (one first message per person)
  perform public.fn_marketing_outreach_record(v_day, jsonb_build_array(jsonb_build_object('prospect_id', v_demo, 'language', 'en', 'body', 'again', 'note', 'again')));
  if (select count(*) from public.marketing_outreach_message where prospect_id = v_demo) <> 1 then v_bad := array_append(v_bad, 'draft_duplicated'::text); end if;

  -- live, inside this transaction only
  update public.app_secrets set value = 'true' where key = 'marketing_golive';
  x := public.fn_marketing_prospect_upsert('{"full_name":"ZZ DEMO Realshape","role_title":"Head of Procurement","company":"ZZ DEMO Developer","segment":"developer","is_demo":false,"source_urls":["https://example.invalid/about"]}');
  v_real := (x->>'id')::bigint;
  x := public.fn_marketing_outreach_record(v_day, jsonb_build_array(
         jsonb_build_object('prospect_id', v_real, 'language', 'en', 'body', 'Hello', 'note', 'Hello'),
         jsonb_build_object('prospect_id', v_demo, 'language', 'en', 'body', 'Hello', 'note', 'Hello')));
  r := r || jsonb_build_object('record_live', x);
  if (select status from public.marketing_prospect where id = v_real) <> 'listed' then v_bad := array_append(v_bad, 'live_not_listed'::text); end if;
  if (select status from public.marketing_outreach_message where prospect_id = v_demo and kind = 'first') <> 'draft' then v_bad := array_append(v_bad, 'demo_listed'::text); end if;

  -- marks
  select mark_token into v_tok from public.marketing_outreach_message where prospect_id = v_real and kind = 'first';
  x := public.fn_marketing_outreach_mark(v_tok, 'sent');
  if (select status from public.marketing_prospect where id = v_real) <> 'sent' then v_bad := array_append(v_bad, 'sent_not_recorded'::text); end if;
  x := public.fn_marketing_outreach_mark(v_tok, 'replied', null);
  if coalesce(x->>'error', '') <> 'paste_the_reply' then v_bad := array_append(v_bad, 'empty_reply_accepted'::text); end if;
  x := public.fn_marketing_outreach_mark(v_tok, 'replied', 'Not interested, thanks', 'decline', 'Understood, and thank you for replying. I will not follow up further.');
  v_follow := (x->>'follow_up_token')::uuid;
  r := r || jsonb_build_object('mark_reply', x, 'page', public.fn_marketing_outreach_page(v_tok) - 'body');
  if (select status from public.marketing_prospect where id = v_real) <> 'declined' then v_bad := array_append(v_bad, 'decline_not_final'::text); end if;
  if v_follow is null then v_bad := array_append(v_bad, 'no_follow_up'::text); end if;
  perform public.fn_marketing_outreach_mark(v_tok, 'sent');
  if (select status from public.marketing_prospect where id = v_real) <> 'declined' then v_bad := array_append(v_bad, 'late_tap_undid_decline'::text); end if;
  if (public.fn_marketing_outreach_due(true)->'prospects') @> jsonb_build_array(jsonb_build_object('id', v_real)) then
    v_bad := array_append(v_bad, 'declined_person_offered_again'::text);
  end if;

  -- articles
  v_art := jsonb_build_object('kind', 'how_it_works', 'ingested_by', 'claude', 'sources', v_src,
    'en', jsonb_build_object('title', 'ZZ DEMO How it works', 'excerpt', 'x', 'meta_desc', 'x', 'category', 'Guide', 'body_html', '<p>x</p>'),
    'ar', jsonb_build_object('title', 'كيف تعمل المنصة', 'excerpt', 'مقدمة', 'meta_desc', 'وصف', 'category', 'دليل', 'body_html', '<p>نص</p>'),
    'post', jsonb_build_object('text_en', 'ZZ DEMO How it works', 'text_ar', 'كيف تعمل المنصة'));
  x := public.fn_marketing_article_ingest(v_art || jsonb_build_object('slug', 'zz-demo-dirty', 'is_demo', true, 'checks', '{"lint":[{"rule":"ai_tell.en","match":"delve"}],"ungrounded":[]}'::jsonb));
  if coalesce(x->>'error', '') <> 'checks_not_clean' then v_bad := array_append(v_bad, 'dirty_article_accepted'::text); end if;
  x := public.fn_marketing_article_ingest(v_art || jsonb_build_object('slug', 'zz-demo-how-it-works', 'is_demo', true, 'checks', v_clean));
  r := r || jsonb_build_object('article_demo', x - 'linkedin_post');
  if not exists (select 1 from public.marketing_post where ingest_key = 'article-zz-demo-how-it-works' and status = 'draft' and channels = array['linkedin']) then
    v_bad := array_append(v_bad, 'article_post_not_drafted'::text);
  end if;
  perform public.fn_marketing_article_approve('zz-demo-how-it-works', 'claude');
  x := public.fn_marketing_article_ingest(v_art || jsonb_build_object('slug', 'zz-probe-real-shape', 'is_demo', false, 'checks', v_clean,
         'en', (v_art->'en') || '{"title":"Probe real shape"}'::jsonb, 'post', '{"text_en":"Probe real shape","text_ar":"كيف تعمل المنصة"}'::jsonb));
  perform public.fn_marketing_article_approve('zz-probe-real-shape', 'claude');
  -- cadence counted against what production already released this week
  x := public.fn_marketing_article_release_due();
  r := r || jsonb_build_object('release_live', x);
  if x->>'released' is not null and x->>'released' <> 'zz-probe-real-shape' then v_bad := array_append(v_bad, 'released_the_wrong_article'::text); end if;
  if (select status from public.marketing_article where slug = 'zz-demo-how-it-works') <> 'approved' then v_bad := array_append(v_bad, 'demo_article_released'::text); end if;
  if x->>'released' = 'zz-probe-real-shape' then
    x := public.fn_marketing_article_mark_live('zz-probe-real-shape');
    if not coalesce((x->>'linkedin_post_scheduled')::boolean, false) then v_bad := array_append(v_bad, 'live_did_not_schedule_post'::text); end if;
  end if;
  update public.app_secrets set value = 'false' where key = 'marketing_golive';
  update public.marketing_article set status = 'approved', released_at = null, live_at = null where slug = 'zz-probe-real-shape';
  x := public.fn_marketing_article_release_due();
  if x->>'released' is not null then v_bad := array_append(v_bad, 'released_while_held'::text); end if;
  x := public.fn_marketing_article_mark_live('zz-demo-how-it-works');
  if coalesce(x->>'error', '') <> 'not_released' then v_bad := array_append(v_bad, 'unreleased_went_live'::text); end if;

  if (select count(*) from public.fn_table_export_list() where table_name in ('marketing_article', 'marketing_prospect', 'marketing_outreach_message')) <> 3 then
    v_bad := array_append(v_bad, 'bd_tables_not_in_the_daily_export'::text);
  end if;
  r := r || jsonb_build_object('figures', (select to_jsonb(f) from public.marketing_bd_figures f),
                               'credential', (select count(*) from public.internal_credential where context = 'fn.marketing_outreach'),
                               'step', (select count(*) from public.resilience_step where step = 'marketingOutreach'));
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when cardinality(v_bad) = 0 then 'PROBE OK' else 'PROBE FAILED' end, 'bad', v_bad, 'r', r);
end $probe$;
