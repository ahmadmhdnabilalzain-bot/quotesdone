-- THE MONTH'S CALENDAR LOADS IN ENGLISH ONLY (marketing, 23 Sep 2026).
--
-- Founder, 23 Sep 2026 (memory profile-copy-rules): "the bio should be always in English. Only in English.
-- Everywhere." and, for this October plan, English only on social. MEASURED 23 Sep 2026 (read-only): production
-- had 0 marketing_campaign, 0 marketing_post and 0 marketing_post_variant rows although the month-1 calendar
-- (docs/marketing/month1_social_calendar.json, #870) and its 12 videos existed. Nothing could have been loaded:
--   * fn_marketing_calendar_load refused any post without an Arabic caption_ar, and marketing_post.text_ar was
--     NOT NULL with CHECK (text_ar ~ Arabic) -- an English-only month could not be stored at all;
--   * the #870 file was not in the loader's shape (ingest_key/scheduled_at_dubai/media.storage_path, a campaign
--     key with underscores that the loader's key rule refuses, and no key frames: marketing_asset_feature had 0
--     rows because the asset worker had never run on main).
-- The October calendar is docs/marketing/2026-10_social_calendar.json, in the loader's shape.
--
-- WHAT THIS CHANGES:
--   marketing_post.text_ar   nullable; when present it must still be Arabic (CHECK kept for that case)
--   marketing_post_demo_text_is_flagged   coalesces text_ar, so a NULL cannot blind the ZZ DEMO check
--   fn_marketing_calendar_load   caption_en required, caption_ar optional; without it the variant is 'en'
--                                (caption only), and 'ar'/'bi'/'thread' without an Arabic caption is refused
-- Everything else in the loader, the hash, the calendar email and the publish gate is unchanged: the month still
-- waits for the founder's "approve" reply and for app_secrets.marketing_golive.
--
--   node scripts/apply_sql.mjs scripts/sql/the_months_calendar_loads_in_english_only.sql --apply --ddl
begin;

alter table public.marketing_post alter column text_ar drop not null;
alter table public.marketing_post drop constraint if exists marketing_post_text_ar_check;
alter table public.marketing_post add constraint marketing_post_text_ar_check check (text_ar is null or text_ar ~ '[؀-ۿ]');
alter table public.marketing_post drop constraint if exists marketing_post_demo_text_is_flagged;
alter table public.marketing_post add constraint marketing_post_demo_text_is_flagged
  check (is_demo or (text_en || ' ' || coalesce(text_ar, '') || ' ' || coalesce(title, '')) !~* 'zz[ _-]?demo');

create or replace function public.fn_marketing_calendar_load(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
end $fn$;
revoke execute on function public.fn_marketing_calendar_load(jsonb) from public, anon, authenticated;

commit;
