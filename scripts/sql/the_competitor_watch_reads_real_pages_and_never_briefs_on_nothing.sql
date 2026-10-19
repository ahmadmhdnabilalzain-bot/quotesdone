-- THE COMPETITOR WATCH READS REAL PAGES AND NEVER BRIEFS ON NOTHING (marketing, ledger 1003 stage 2, MKT-C06, 19 Oct 2026).
--
-- Assigned: marketing. Duties marketing.competitor_scan (hourly) and marketing.competitor_refresh (weekly brief).
--
-- ══ MEASURED, 19 Oct 2026, htdblwldjkcgjvmqkbeh (read-only) ══════════════════════════════════════════════════════
--   * seat_duty last_result: competitor_scan {"requested":0,"collected":0}; competitor_refresh week 2026-10-12
--     {"watched":36,"scan":{"requested":0,"collected":0},"social_posts_seen":0}. The brief was written on nothing.
--   * competitor_scan: 36 rows, ALL requested 24 Sep (31 'fetched' HTTP 200, 5 'failed'). Every page then waited
--     30 days, so three weeks in four the scan requests 0 and the brief reads 0 -- and a failed page waited the
--     same 30 days as a good one.
--   * THE TEXT WAS EATEN. The 31 'fetched' pages average 53 characters of page_text; 1 of 31 has more than 200.
--     fn_competitor_scan_ingest stripped scripts with '<script[^>]*>.*?</script>'. In Postgres ARE the FIRST
--     quantifier sets the whole pattern's greediness: '[^>]*' is greedy, so '.*?' ran greedy and deleted from the
--     first <script to the LAST </script> -- the whole body. Proved on production:
--       regexp_replace('<script a>x</script> KEEP THIS TEXT <script>y</script> tail', '<script[^>]*>.*?</script>', ' ', 'gi')
--       = '  tail'   ;   with '<script[^>]*?>.*?</script>'  = '  KEEP THIS TEXT   tail'
--     So the 'fetched' pages were empty shells, and an empty shell hashed the same every month ("unchanged").
--   * Social: 0 of 36 watched competitors carry any social handle, so competitor_study (Instagram business_discovery,
--     the official API) has nobody to read, and market_intel has 0 rows. Apify is paused until 2027 and is not used.
--
-- ══ WHAT THIS CHANGES ═════════════════════════════════════════════════════════════════════════════════════════════
--   1. fn_competitor_scan_ingest: the strip patterns are non-greedy from their first quantifier; a page with under 200
--      characters of readable text, or a firewall "Request Rejected" page, is 'failed' with that reason -- an empty
--      shell is never counted as collected again. Hashes are prefixed 'v2:' and a page is compared only with a v2
--      reading, so the shells of 24 Sep can never raise a false "changed" to the CEO.
--   2. The same ingest reads the competitor's OWN home page for its public profile links (Instagram, LinkedIn,
--      Facebook, X, TikTok, YouTube) and its RSS/Atom feed, and fills competitor.social_handles where a key is empty.
--      That gives competitor_study real handles, and gives the watch a POST source that needs no login and no Apify:
--      the competitor's public feed (page_kind 'feed'), whose items are stored in market_intel (platform 'rss').
--   3. fn_marketing_competitor_scan: home, pricing and feed weekly; a failed page retried after a day; three
--      failures in 30 days back that page off for the rest of the 30 days (a site that blocks us is not hammered).
--   4. fn_marketing_competitor_refresh_duty: the brief states its INPUTS (pages read this week, readable pages on
--      file, posts seen, failures by reason). With no page read and no post seen it claims no finding and says so in
--      'verdict'; 'claims_findings' is false and 'changes' is empty.
-- NOT CHANGED: what counts as a material change (fn_seat_duty_reason surface marketing.competitor_change, model held
-- under the founder's OpenRouter hold), who receives it (a CEO task), and fn_marketing_intel_upsert.
-- Prevented by: scripts/checks/the_competitor_watch_reads_real_pages.test.mjs (replays the greedy pattern and fails
-- if it returns), and the probe the_marketing_seat_closes_the_loops_a_senior_marketer_closes_probe.sql.
--
--   node scripts/apply_sql.mjs scripts/sql/the_competitor_watch_reads_real_pages_and_never_briefs_on_nothing.sql --apply --ddl

alter table public.competitor_scan drop constraint if exists competitor_scan_page_kind_check;
alter table public.competitor_scan add constraint competitor_scan_page_kind_check check (page_kind in ('home', 'pricing', 'feed'));

-- The competitor's public profile links and feed, read from its own home page HTML. Pure: no table is read.
create or replace function public.fn_competitor_public_links(p_html text, p_base_url text)
returns jsonb language plpgsql immutable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v jsonb := '{}'::jsonb; m text; tag text; origin text := substring(p_base_url from '^(https://[^/]+)');
begin
  if coalesce(p_html, '') = '' then return v; end if;
  m := substring(p_html from 'instagram\.com/([A-Za-z0-9_.]{2,30})');
  if m is not null and lower(m) not in ('p', 'reel', 'reels', 'explore', 'accounts', 'sharer', 'share') then v := v || jsonb_build_object('instagram', m); end if;
  m := substring(p_html from 'linkedin\.com/company/([A-Za-z0-9_-]{2,80})');
  if m is not null then v := v || jsonb_build_object('linkedin', 'https://www.linkedin.com/company/' || m); end if;
  m := substring(p_html from 'facebook\.com/([A-Za-z0-9.]{2,80})');
  if m is not null and lower(m) not in ('sharer', 'sharer.php', 'share', 'dialog', 'tr', 'plugins', 'groups') then v := v || jsonb_build_object('facebook', 'https://www.facebook.com/' || m); end if;
  m := substring(p_html from '(?:twitter|x)\.com/([A-Za-z0-9_]{2,15})');
  if m is not null and lower(m) not in ('intent', 'share', 'home', 'i') then v := v || jsonb_build_object('x', m); end if;
  m := substring(p_html from 'tiktok\.com/@([A-Za-z0-9_.]{2,30})');
  if m is not null then v := v || jsonb_build_object('tiktok', m); end if;
  m := substring(p_html from 'youtube\.com/((?:@|channel/|c/)[A-Za-z0-9_.-]{2,80})');
  if m is not null then v := v || jsonb_build_object('youtube', 'https://www.youtube.com/' || m); end if;
  -- the feed the site itself advertises (<link rel="alternate" type="application/rss+xml" href="...">)
  tag := substring(p_html from '<link[^>]*?application/(?:rss|atom)\+xml[^>]*?>');
  m := substring(tag from 'href="([^"]+)"');
  if m is not null then
    m := replace(m, '&amp;', '&');
    if m ~ '^/' and origin is not null then m := origin || m; end if;
    if m ~ '^https://' then v := v || jsonb_build_object('rss', m); end if;
  end if;
  return v;
end $fn$;
revoke execute on function public.fn_competitor_public_links(text, text) from public, anon, authenticated;
grant execute on function public.fn_competitor_public_links(text, text) to service_role;

-- A competitor's public feed, item by item, into market_intel (platform 'rss'). Returns the upsert's counts.
create or replace function public.fn_competitor_feed_ingest(p_competitor_id bigint, p_xml text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare it text; v_title text; v_link text; v_id text; v_when text; v_at timestamptz; v_rows jsonb := '[]'::jsonb; n int := 0;
begin
  -- two patterns, not one alternation: a top-level (a|b) group ran greedy and returned every item as one (measured)
  for it in select x[1] from regexp_matches(coalesce(p_xml, ''), '<item[\s>].*?</item>', 'gi') x
            union all select x[1] from regexp_matches(coalesce(p_xml, ''), '<entry[\s>].*?</entry>', 'gi') x loop
    exit when n >= 25;
    it := regexp_replace(it, '<!\[CDATA\[(.*?)\]\]>', '\1', 'g');
    v_title := btrim(regexp_replace(coalesce(substring(it from '<title[^>]*?>(.*?)</title>'), ''), '<[^>]+>', ' ', 'g'));
    v_link := btrim(coalesce(substring(it from '<link>\s*(https://[^<\s]+)'), substring(it from '<link[^>]*?href="(https://[^"]+)"')));
    v_id := btrim(coalesce(substring(it from '<guid[^>]*?>(.*?)</guid>'), substring(it from '<id>(.*?)</id>'), v_link));
    v_when := btrim(coalesce(substring(it from '<pubDate>(.*?)</pubDate>'), substring(it from '<published>(.*?)</published>'),
                             substring(it from '<updated>(.*?)</updated>')));
    begin v_at := v_when::timestamptz; exception when others then v_at := null; end;
    continue when coalesce(v_link, '') = '' or coalesce(v_id, '') = '';
    v_rows := v_rows || jsonb_build_array(jsonb_build_object('platform', 'rss', 'source', 'public_feed', 'external_id', left(v_id, 300),
                'competitor_id', p_competitor_id, 'source_url', v_link, 'posted_at', v_at, 'caption', nullif(left(v_title, 500), ''),
                'media_type', 'article', 'metrics', '{}'::jsonb));
    n := n + 1;
  end loop;
  return public.fn_marketing_intel_upsert(v_rows) || jsonb_build_object('items', n);
end $fn$;
revoke execute on function public.fn_competitor_feed_ingest(bigint, text) from public, anon, authenticated;
grant execute on function public.fn_competitor_feed_ingest(bigint, text) to service_role;

CREATE OR REPLACE FUNCTION public.fn_competitor_scan_ingest(p_scan_id bigint, p_status integer, p_content text, p_error text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s public.competitor_scan; c public.competitor; v_text text; v_hash text; prev public.competitor_scan; v_held bigint; v_first boolean;
  v_links jsonb; v_feed jsonb;
begin
  select * into s from public.competitor_scan where id = p_scan_id for update;
  if not found or s.status <> 'fetching' then return jsonb_build_object('scan', p_scan_id, 'skipped', true); end if;
  select * into c from public.competitor where id = s.competitor_id;
  if p_status is null or p_status not between 200 and 399 or coalesce(btrim(p_content), '') = '' then
    update public.competitor_scan set status = 'failed', http_status = p_status, error = left(coalesce(p_error, 'empty page'), 500) where id = s.id;
    return jsonb_build_object('scan', s.id, 'status', 'failed');
  end if;

  -- A FEED is posts, not a page to compare: its items go to market_intel and the scan row records how many.
  if s.page_kind = 'feed' then
    v_feed := public.fn_competitor_feed_ingest(c.id, p_content);
    if coalesce((v_feed->>'items')::int, 0) = 0 then
      update public.competitor_scan set status = 'failed', http_status = p_status, error = 'the feed carried no item with a link' where id = s.id;
      return jsonb_build_object('scan', s.id, 'status', 'failed');
    end if;
    update public.competitor_scan set status = 'fetched', http_status = p_status, content_hash = 'v2:' || md5(p_content), fields = v_feed where id = s.id;
    return jsonb_build_object('scan', s.id, 'status', 'fetched', 'feed', v_feed);
  end if;

  -- The competitor's own public profile links and feed: filled where empty, never overwritten.
  if s.page_kind = 'home' then
    v_links := public.fn_competitor_public_links(p_content, s.url);
    if v_links <> '{}'::jsonb then
      update public.competitor set social_handles = v_links || coalesce(social_handles, '{}'::jsonb) where id = c.id;
    end if;
  end if;

  -- NON-GREEDY FROM THE FIRST QUANTIFIER: '[^>]*?' makes the whole pattern non-greedy (see the header).
  v_text := regexp_replace(p_content, '<script[^>]*?>.*?</script>', ' ', 'gi');
  v_text := regexp_replace(v_text, '<style[^>]*?>.*?</style>', ' ', 'gi');
  v_text := regexp_replace(v_text, '<!--.*?-->', ' ', 'g');
  v_text := regexp_replace(v_text, '<[^>]+>', ' ', 'g');
  v_text := replace(replace(replace(replace(v_text, '&nbsp;', ' '), '&amp;', '&'), '&#39;', ''''), '&quot;', '"');
  v_text := left(btrim(regexp_replace(v_text, '\s+', ' ', 'g')), 20000);
  if length(v_text) < 200 or v_text ~* '^request rejected' then
    update public.competitor_scan set status = 'failed', http_status = p_status,
      error = case when v_text ~* '^request rejected' then 'the site''s firewall rejected the request'
                   else 'no readable text (' || length(v_text) || ' characters): a script shell or a blocked page' end
     where id = s.id;
    return jsonb_build_object('scan', s.id, 'status', 'failed', 'chars', length(v_text));
  end if;
  v_hash := 'v2:' || md5(v_text);

  -- compared only with a v2 reading: the empty shells of 24 Sep are never "the last reading"
  select * into prev from public.competitor_scan
   where competitor_id = s.competitor_id and page_kind = s.page_kind and id <> s.id and status in ('unchanged', 'fetched', 'reasoned')
     and content_hash like 'v2:%'
   order by requested_at desc limit 1;
  v_first := prev.id is null;
  if not v_first and prev.content_hash = v_hash then
    update public.competitor_scan set status = 'unchanged', http_status = p_status, content_hash = v_hash where id = s.id;
    update public.competitor set verified_at = (now() at time zone 'Asia/Dubai')::date where id = c.id;
    return jsonb_build_object('scan', s.id, 'status', 'unchanged');
  end if;
  if not v_first and prev.page_text is null then
    select * into prev from public.competitor_scan
     where competitor_id = s.competitor_id and page_kind = s.page_kind and id <> s.id and page_text is not null and content_hash like 'v2:%'
     order by requested_at desc limit 1;
    v_first := prev.id is null;
  end if;

  update public.competitor_scan set status = 'fetched', http_status = p_status, content_hash = v_hash, page_text = v_text where id = s.id;
  update public.competitor set verified_at = (now() at time zone 'Asia/Dubai')::date where id = c.id;
  v_held := public.fn_seat_duty_reason('marketing', 'marketing.competitor_change',
    case when v_first then
      'Read this competitor''s public ' || s.page_kind || ' page for the first time and record its pricing, positioning and features '
        || 'as they stand, so later readings can be compared with it. Say unreadable if the page carries no usable content.'
    else
      'Compare this competitor''s public ' || s.page_kind || ' page with the last reading. Decide whether its pricing, positioning '
        || 'or features changed in a way that matters to QuotesDone (a construction and home-services quotation marketplace in the UAE: '
        || 'best-3 comparison, 3 per cent reveal fee paid by the buyer, no supplier commission). Cosmetic or rotating content is not a change.'
    end,
    case when v_first then
      '[{"id":"profiled","meaning":"the page was read and its pricing, positioning and features are recorded"},{"id":"unreadable","meaning":"the page has no usable content (blocked, empty or only a script shell)"}]'::jsonb
    else
      '[{"id":"no_material_change","meaning":"nothing that matters to us changed"},{"id":"changed","meaning":"pricing, positioning or features changed in a way the CEO should act on"},{"id":"unreadable","meaning":"the page has no usable content (blocked, empty or only a script shell)"}]'::jsonb
    end,
    jsonb_build_object('competitor', to_jsonb(c) - 'watch', 'page_kind', s.page_kind, 'url', s.url, 'page_text', left(v_text, 12000),
                       'last_reading', case when v_first then null else jsonb_build_object('fetched', prev.requested_at, 'fields', prev.fields,
                                                                                          'page_text', left(prev.page_text, 6000)) end),
    jsonb_build_object('scan_id', s.id), 'mkt_competitor:' || s.id);
  perform public.fn_ambition_ask_fields(v_held, jsonb_build_array(
    jsonb_build_object('key', 'pricing', 'question', 'who pays what, as the page states it (or "not published")'),
    jsonb_build_object('key', 'positioning', 'question', 'who it is for and what it claims, in one sentence'),
    jsonb_build_object('key', 'features', 'question', 'the features that compete with QuotesDone'),
    jsonb_build_object('key', 'what_changed', 'question', 'for changed: exactly what changed and why it matters to us')));
  update public.competitor_scan set held_id = v_held where id = s.id;
  return jsonb_build_object('scan', s.id, 'status', 'fetched', 'held', v_held, 'first', v_first, 'chars', length(v_text));
end $function$;

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

  -- Weekly per page. A failed page is retried after a day; three failures in 30 days rest that page for the 30 days.
  for c in
    select x.id, p.page_kind, p.url
      from public.competitor x
      cross join lateral (values ('home', x.url), ('pricing', x.pricing_url), ('feed', x.social_handles->>'rss')) p(page_kind, url)
     where x.watched and x.kind <> 'incumbent_behaviour' and p.url ~ '^https://'
       and not exists (select 1 from public.competitor_scan z where z.competitor_id = x.id and z.page_kind = p.page_kind
                         and (z.status = 'fetching'
                              or (z.status <> 'failed' and z.requested_at > now() - interval '7 days')
                              or (z.status = 'failed' and z.requested_at > now() - interval '1 day')))
       and (select count(*) from public.competitor_scan z where z.competitor_id = x.id and z.page_kind = p.page_kind
             and z.status = 'failed' and z.requested_at > now() - interval '30 days') < 3
     order by x.id, p.page_kind limit 10
  loop
    v_req := net.http_get(c.url, '{}'::jsonb,
               jsonb_build_object('User-Agent', 'QuotesDone market watch (+https://www.quotesdone.ae)',
                                  'Accept', case when c.page_kind = 'feed' then 'application/rss+xml, application/atom+xml, application/xml' else 'text/html' end), 20000);
    insert into public.competitor_scan (competitor_id, page_kind, url, request_id) values (c.id, c.page_kind, c.url, v_req);
    n_out := n_out + 1;
  end loop;
  return jsonb_build_object('collected', n_in, 'requested', n_out);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_marketing_competitor_refresh_duty()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_week date := date_trunc('week', now() at time zone 'Asia/Dubai')::date;
  v_body jsonb; v_stale int; v_scan jsonb; v_read int; v_posts int; v_on_file int; v_held int; v_claims boolean;
begin
  v_scan := public.fn_marketing_competitor_scan();
  select count(*) into v_stale from public.competitor
   where watched and kind <> 'incumbent_behaviour' and (verified_at is null or verified_at < current_date - 90);
  select count(*) into v_read from public.competitor_scan
   where page_kind in ('home', 'pricing') and status in ('fetched', 'unchanged', 'reasoned') and content_hash like 'v2:%'
     and requested_at >= now() - interval '7 days';
  select count(distinct (competitor_id, page_kind)) into v_on_file from public.competitor_scan
   where page_kind in ('home', 'pricing') and status in ('fetched', 'reasoned') and content_hash like 'v2:%' and length(page_text) >= 200;
  select count(*) into v_posts from public.market_intel where kind = 'competitor' and fetched_at >= now() - interval '7 days';
  select count(*) into v_held from public.competitor_scan where status = 'fetched' and decided_at is null and held_id is not null
     and requested_at >= now() - interval '7 days';
  v_claims := v_read > 0 or v_posts > 0;
  v_body := jsonb_build_object(
    'week', v_week,
    'watched', (select count(*) from public.competitor where watched),
    'stale_profiles', v_stale,
    'inputs', jsonb_build_object(
       'pages_read_this_week', v_read,
       'readable_pages_on_file', v_on_file,
       'posts_seen_this_week', v_posts,
       'posts_by_platform', (select coalesce(jsonb_object_agg(platform, n), '{}'::jsonb) from
                             (select platform, count(*) n from public.market_intel where kind = 'competitor' and fetched_at >= now() - interval '7 days' group by 1) p),
       'competitors_with_a_social_handle', (select count(*) from public.competitor where watched and social_handles is not null and social_handles <> '{}'::jsonb),
       'failures_by_reason', (select coalesce(jsonb_object_agg(reason, n), '{}'::jsonb) from
                              (select left(coalesce(error, 'unknown'), 80) reason, count(*) n from public.competitor_scan
                                where status = 'failed' and requested_at >= now() - interval '7 days' group by 1) f),
       'awaiting_reasoning', v_held),
    'claims_findings', v_claims,
    'verdict', case when v_claims
       then format('%s page reading(s) and %s post(s) this week; %s reading(s) still await reasoning.', v_read, v_posts, v_held)
       else 'NO INPUT THIS WEEK: no competitor page was read and no post was seen, so this brief claims no finding.' end,
    'changes', case when not v_claims then '[]'::jsonb else
               (select coalesce(jsonb_agg(jsonb_build_object('competitor', c.name, 'page', s.page_kind, 'decision', s.decision,
                  'what_changed', s.fields->>'what_changed', 'ceo_task', s.task_id) order by s.decided_at), '[]'::jsonb)
                  from public.competitor_scan s join public.competitor c on c.id = s.competitor_id
                 where s.decided_at >= now() - interval '7 days') end,
    'fetch_failures', (select count(*) from public.competitor_scan where status = 'failed' and requested_at >= now() - interval '7 days'),
    'social_posts_seen', v_posts,
    'scan', v_scan);
  insert into public.marketing_plan_doc (kind, period, body) values ('competitor_intel', v_week, v_body)
  on conflict (kind, period) do update set body = excluded.body, updated_at = now();
  return v_body - 'changes';
end $function$;
