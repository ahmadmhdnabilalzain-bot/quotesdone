-- NEXT MONTH'S VIDEO PLAN LEANS ON WHAT BROUGHT SUPPLIERS (marketing). 28 Sep 2026, founder instruction 1009, upgrade 6.
--
-- The founder: each month, compute which topics, channels, formats and posting times brought supplier
-- registrations, per category; when drafting next month's plan, shift the mix towards what worked, within
-- his rules (organic only until every category has 10 suppliers; no weekends or holidays; his one-shot
-- approval); the email shows the evidence behind the shift; plain code, no model; with no data yet, keep the
-- current mix and say so.
--
-- MEASURED BEFORE THIS FILE (mirror, 28 Sep 2026):
--   * attribution exists: marketing_first_touch (lead -> utm_source, post_id; #875), marketing_post
--     (title, channels, video_path, published_at/scheduled_at), marketing_post_variant.post_type per platform,
--     lead_category (primary slug per lead), supply_gap (trade x emirate, matchable vs target 10).
--   * fn_marketing_month_plan_tick (one_approve_schedules_and_publishes_the_month_on_working_days.sql) picks the
--     12 ideas by plain rotation (last_planned_month nulls first) and never looks at a result.
--   * #1012 (invitation refs, funnel stage) is OPEN, not merged: this file reads only what is live. An
--     invitation-link registration carries utm_source/utm_medium like any other first touch, so it is
--     counted by channel here without depending on #1012's tables.
--
-- WHAT THIS ADDS (all code, no model):
--   fn_marketing_time_slot(ts)          'Wed midday' style slot in Asia/Dubai.
--   fn_marketing_learning(month, demo)  per dimension (topic, channel, format, time) and value: posts
--       published, supplier registrations whose first touch names it, registrations per post, and the split by
--       supplier category. Topic = the video idea whose title the post carries (else the post title). Channel
--       counts every first touch with a utm_source (with or without a post); the other three need the post.
--       Also states the organic-only rule from supply_gap: categories (UAE rows) under their target.
--   fn_marketing_learning_text(learned) the evidence paragraph the plan email carries.
--   fn_marketing_month_plan_tick        now: learns from the month it runs in (month to date, the same
--       'evaluated_month' fn_marketing_plan_calendar names), stores it in marketing_month_plan.plan->'learned',
--       puts ideas whose topic brought registrations first (best registrations per post; at most 6 of 12, so
--       half the month keeps testing the rotation), fills the rest by the unchanged rotation, and prints the
--       evidence. No registrations traced -> the rotation is unchanged and the email says so. Dates still come
--       from fn_marketing_video_days (working days only); approval is still his one reply.
-- Nothing new is stored in a new table: the learning lives in marketing_month_plan.plan (already exported).
--
-- Prevented by: scripts/checks/next_months_video_plan_leans_on_what_brought_suppliers.test.mjs and the probe
--   scripts/sql/next_months_video_plan_leans_on_what_brought_suppliers_probe.sql (ZZ DEMO posts + registrations).
--
--   node scripts/apply_sql.mjs scripts/sql/next_months_video_plan_leans_on_what_brought_suppliers.sql --apply --ddl

create or replace function public.fn_marketing_time_slot(p_at timestamptz)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case when p_at is null then 'unscheduled' else
    to_char(p_at at time zone 'Asia/Dubai', 'Dy') || ' ' ||
    case when extract(hour from p_at at time zone 'Asia/Dubai') < 11 then 'morning'
         when extract(hour from p_at at time zone 'Asia/Dubai') < 14 then 'midday'
         when extract(hour from p_at at time zone 'Asia/Dubai') < 17 then 'afternoon'
         else 'evening' end end
$fn$;
revoke execute on function public.fn_marketing_time_slot(timestamptz) from public, anon, authenticated;

create or replace function public.fn_marketing_learning(p_month date, p_include_demo boolean default false)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
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
$fn$;
revoke execute on function public.fn_marketing_learning(date, boolean) from public, anon, authenticated;

create or replace function public.fn_marketing_learning_text(p_learned jsonb, p_shifted jsonb default '[]'::jsonb)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
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
$fn$;
revoke execute on function public.fn_marketing_learning_text(jsonb, jsonb) from public, anon, authenticated;

-- Copied from one_approve_schedules_and_publishes_the_month_on_working_days.sql (the canonical body); changed:
-- the learning, the idea order, the evidence in the email, plan->'learned', and p_include_demo (default false)
-- so the probe can prove the shift on ZZ DEMO rows. Callers pass 0 or 1 argument; both still resolve.
drop function if exists public.fn_marketing_month_plan_tick(date);
create function public.fn_marketing_month_plan_tick(p_today date default null, p_include_demo boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare
  v_today date := coalesce(p_today, (now() at time zone 'Asia/Dubai')::date);
  v_month date := (date_trunc('month', v_today) + interval '1 month')::date;
  v_token text := encode(extensions.gen_random_bytes(16), 'hex'); v_ideas jsonb; v_body text; v_nid bigint; v_mname text;
  v_learned jsonb; v_shifted jsonb;
begin
  if v_month < date '2026-11-01' then return jsonb_build_object('sent', false, 'reason', 'the monthly loop starts with November 2026'); end if;
  if exists (select 1 from public.marketing_month_plan where month = v_month
              and (plan_sent_at is not null or status not in ('draft', 'with_ceo'))) then
    return jsonb_build_object('sent', false, 'reason', 'already planned', 'month', v_month);
  end if;
  v_mname := to_char(v_month, 'FMMonth YYYY');
  v_learned := public.fn_marketing_learning(date_trunc('month', v_today)::date, p_include_demo);

  -- topics that brought registrations, best per post first; only enabled ideas can be planned; at most 6 of 12
  with won as (select r->>'value' as topic, (r->>'per_post')::numeric as pp, (r->>'registrations')::int as n
                 from jsonb_array_elements(coalesce(v_learned->'dimensions'->'topic', '[]'::jsonb)) r
                where (r->>'registrations')::int > 0),
       ranked as (select i.id, i.idea_key, row_number() over (order by w.pp desc nulls last, w.n desc, i.id) as won_rank
                    from public.marketing_video_idea i join won w on w.topic in (i.idea_key, lower(i.title)) where i.enabled)
  select coalesce(jsonb_agg(idea_key order by won_rank), '[]'::jsonb) into v_shifted from ranked where won_rank <= 6;

  with days as (select d, row_number() over (order by d) n from public.fn_marketing_video_days(v_month, 12) d),
       picks as (select i.*, row_number() over (order by coalesce(array_position(array(select jsonb_array_elements_text(v_shifted)), i.idea_key), 1000),
                                                         i.last_planned_month nulls first, i.id) n
                   from public.marketing_video_idea i where i.enabled)
  select jsonb_agg(jsonb_build_object('n', d.n, 'date', d.d, 'idea_key', p.idea_key, 'title', p.title, 'hook', p.hook,
                                      'film_plan', p.film_plan, 'cta', p.cta, 'audience', p.audience,
                                      'why', case when v_shifted ? p.idea_key then 'brought registrations' else 'rotation' end) order by d.n)
    into v_ideas
    from days d join picks p on p.n = d.n;
  if v_ideas is null then raise exception 'marketing_month_plan: no enabled ideas or no working days in %', v_month; end if;

  v_body := 'Here is the video plan for ' || v_mname || ': ' || jsonb_array_length(v_ideas)
         || ' short videos on UAE working days (Monday, Wednesday, Thursday first; no weekends or public holidays).' || E'\n\n'
         || public.fn_marketing_learning_text(v_learned, v_shifted) || E'\n\n'
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
  insert into public.marketing_month_plan as t (month, status, verdict, plan, content_brief, plan_token, plan_notification_id, plan_sent_at)
  values (v_month, 'sent_to_founder', jsonb_build_object('by', 'code', 'rule', 'founder 24 Sep 2026: the monthly idea plan is routine work, coded; 28 Sep (1009): it leans on what brought registrations'),
          jsonb_build_object('by', 'code', 'ideas', v_ideas, 'learned', v_learned, 'shifted_to', v_shifted),
          jsonb_build_object('videos', jsonb_build_object('count', jsonb_array_length(v_ideas)), 'ideas', v_ideas),
          v_token, v_nid, now())
  on conflict (month) do update set status = excluded.status, verdict = coalesce(t.verdict, excluded.verdict), plan = excluded.plan,
         content_brief = excluded.content_brief, plan_token = excluded.plan_token, plan_notification_id = excluded.plan_notification_id,
         plan_sent_at = excluded.plan_sent_at, updated_at = now();
  update public.marketing_video_idea set last_planned_month = v_month
   where idea_key in (select e->>'idea_key' from jsonb_array_elements(v_ideas) e);
  return jsonb_build_object('sent', true, 'month', v_month, 'ideas', jsonb_array_length(v_ideas), 'notification_id', v_nid,
                            'has_data', v_learned->'has_data', 'shifted_to', v_shifted);
end $function$;
revoke execute on function public.fn_marketing_month_plan_tick(date, boolean) from public, anon, authenticated;
