-- THE CEO APPROVES THE MARKETING MONTH, PUBLISHES THE ARTICLES, AND HOLDS THE MARKETING SWITCH. Seat: ceo (the decisions) +
-- marketing (the pipes it decides on). 15 Nov 2026. Founder ruling 1696 (15 Nov 2026): "CEO is having full authority ... He
-- doesnt rely on me in anything." Rulings 1701/1705.
--
-- WHAT WAS THERE (READ from origin/main 06881a2d6; SELECT 15 Nov 2026):
--   * marketing_month_plan 2026-12-01: status 'sent_to_founder' since 10 Nov 23:45, waiting for the founder's reply. The CEO
--     seat had already reviewed and approved it ('ceo_approved' is the step before); the founder's reply was the acceptance
--     (fn_marketing_month_plan_reply). November's plan was withdrawn: no month has been accepted since September.
--   * The social calendar is published only after marketing_campaign.approved_hash is set, and only fn_marketing_calendar_reply
--     sets it, on the founder's "approve" e-mail (constraint marketing_campaign_approved_by_check: approved_by = 'founder').
--   * app_secrets.marketing_golive = 'false', switched by nobody but a person; the CEO-approved article of 13 Oct
--     ("fire-safety-procurement-in-the-uae-...") has waited 33 days for it (fn_marketing_article_release_due: "marketing_golive
--     is not true"). No social post since 21 Oct.
-- WHAT THIS DOES:
--   1. public.marketing_ceo_decision: every CEO decision on marketing (a month accepted, a calendar approved, the switch moved,
--      an article published), with its reason (20 characters or more) and its evidence. Append-only.
--   2. fn_marketing_month_plan_tick: a month the CEO approved is ACCEPTED by the CEO (recorded), and the founder is sent it for
--      information and as the request for the videos only he films; fn_ceo_accepts_marketing_month accepts a month already
--      waiting on the founder (December 2026), with the CEO's review as the reason.
--   3. fn_ceo_approves_marketing_calendar: the CEO approves a calendar exactly as built (approved_hash = the content hash, as the
--      founder's reply did), only when the calendar was not edited after it was built, it is organic only (spend_policy
--      'organic_only'; money goes through the CEO's own limits, never this approval), and it has posts still to go out.
--      marketing_campaign.approved_by may now read 'ceo'.
--   4. fn_ceo_switches_marketing_golive(on, reason): marketing_golive is data the CEO moves with a reason, no deploy. The
--      founder's emergency stop (marketing_publishing_enabled) is never touched by the CEO and still outranks it.
--   5. fn_ceo_publishes_article(slug, reason): the CEO's publish decision for an article it approved; fn_marketing_article_release_due
--      releases an article with that decision on its weekly slot (one a week, a UAE working day), with or without
--      marketing_golive. marketing_golive also starts the founder's morning LinkedIn list (fn_marketing_outreach_due), so the
--      CEO's round does not switch it on by itself: that stays a decision the CEO takes with its reason (point 4).
--   6. fn_ceo_decides_marketing (seat duty ceo.marketing_decisions, hourly): accepts a month waiting on the founder, approves
--      a calendar that meets the boundaries, and publishes every article the CEO approved that has no publish decision yet,
--      while the founder's emergency stop is off.
-- REVIEW OF 15 NOV 2026 (scratchpad REVIEW_growth, item 6, item 3 and a note), fixed here:
--   * fn_marketing_article_release_due checks the founder's emergency stop (fn_marketing_publishing_on) AT RELEASE TIME: a CEO
--     publish decision written while the stop was off no longer releases an article after he switched it on.
--   * marketing_ceo_decision is written only by these routines: INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER revoked from
--     service_role, and a BEFORE TRUNCATE trigger (as growth_limit_change and invite_brake_decision).
--   * fn_marketing_month_plan_reply: the founder's acknowledgement no longer tells him to reply "approve" to the calendar (the
--     CEO approves it now; he is informed, ruling 1696).
-- NOT BUILT HERE (stated, not hidden): a released article still reaches the website only when it is baked into
-- src/content/blog.json and deployed (marketing_outreach release step); serving released articles from the database is the
-- audit's M4 and needs a site change and a public read path.
-- prevented by: scripts/checks/the_supplier_funnel_runs_itself.test.mjs (text) and
-- the_ceo_approves_the_marketing_month_publishes_articles_and_holds_the_marketing_switch_probe.sql (LOCAL).
-- APPLY ORDER: last of the four files of 15 Nov (it depends on none of the other three).
-- LOCKS: one new table; marketing_campaign (a handful of rows) has one CHECK constraint replaced (ACCESS EXCLUSIVE for
-- milliseconds); three routines replaced in place (fn_marketing_month_plan_tick, fn_marketing_article_release_due, fn_marketing_month_plan_reply).
set local lock_timeout = '1500ms';

create table if not exists public.marketing_ceo_decision (
  id bigserial primary key,
  subject_kind text not null check (subject_kind in ('month_plan', 'calendar', 'marketing_golive', 'article')),
  subject_ref text not null,
  decision text not null check (decision in ('accept', 'approve', 'switch_on', 'switch_off', 'publish', 'hold')),
  reason text not null check (length(btrim(reason)) >= 20),
  evidence jsonb not null default '{}'::jsonb,
  decided_at timestamptz not null default now());
comment on table public.marketing_ceo_decision is 'Every CEO decision on marketing: a month accepted, a calendar approved, marketing_golive moved, an article published, or a hold, with its reason (ruling 1696). Append-only. the_ceo_approves_the_marketing_month_publishes_articles_and_holds_the_marketing_switch.sql';
create index if not exists marketing_ceo_decision_subject on public.marketing_ceo_decision (subject_kind, subject_ref, decided_at desc);

create or replace function public.trg_marketing_ceo_decision_is_history()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  raise exception 'marketing_ceo_decision is history: a decision is never edited or deleted';
end $fn$;
revoke execute on function public.trg_marketing_ceo_decision_is_history() from public, anon, authenticated;
create or replace trigger trg_marketing_ceo_decision_is_history before update or delete on public.marketing_ceo_decision
  for each row execute function public.trg_marketing_ceo_decision_is_history();
create or replace trigger trg_marketing_ceo_decision_never_truncated before truncate on public.marketing_ceo_decision
  for each statement execute function public.trg_marketing_ceo_decision_is_history();

do $guard$
begin
  if not (select relrowsecurity from pg_class where oid = 'public.marketing_ceo_decision'::regclass) then
    alter table public.marketing_ceo_decision enable row level security;
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'marketing_ceo_decision' and policyname = 'marketing_ceo_decision_service_role_only') then
    create policy marketing_ceo_decision_service_role_only on public.marketing_ceo_decision as permissive for all to public using (false) with check (false);
  end if;
  -- the CEO approves a calendar too (ruling 1696); a founder approval already recorded stays valid
  if exists (select 1 from pg_constraint where conname = 'marketing_campaign_approved_by_check' and conrelid = 'public.marketing_campaign'::regclass
              and pg_get_constraintdef(oid) not like '%ceo%') then
    alter table public.marketing_campaign drop constraint marketing_campaign_approved_by_check;
    alter table public.marketing_campaign add constraint marketing_campaign_approved_by_check check (approved_by = any (array['founder'::text, 'ceo'::text]));
  end if;
end $guard$;
revoke all on public.marketing_ceo_decision from anon, authenticated;
revoke all on sequence public.marketing_ceo_decision_id_seq from anon, authenticated;
-- written only by the CEO's routines below (SECURITY DEFINER, as the owner); service_role keeps SELECT (review item 3)
revoke insert, update, delete, truncate, references, trigger on public.marketing_ceo_decision from service_role;
revoke usage, update on sequence public.marketing_ceo_decision_id_seq from service_role;

-- ── THE CEO'S DECISIONS ───────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_switches_marketing_golive(p_on boolean, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_was boolean := public.fn_marketing_publishing_live();
begin
  if p_on is null then return jsonb_build_object('ok', false, 'reason', 'say on or off'); end if;
  if length(btrim(coalesce(p_reason, ''))) < 20 then return jsonb_build_object('ok', false, 'reason', 'say why, in a sentence (20 characters or more)'); end if;
  if v_was = p_on then return jsonb_build_object('ok', true, 'changed', false, 'marketing_golive', p_on); end if;
  insert into public.app_secrets (key, value) values ('marketing_golive', case when p_on then 'true' else 'false' end)
  on conflict (key) do update set value = excluded.value;
  insert into public.marketing_ceo_decision (subject_kind, subject_ref, decision, reason, evidence)
  values ('marketing_golive', 'app_secrets.marketing_golive', case when p_on then 'switch_on' else 'switch_off' end, btrim(p_reason),
          jsonb_build_object('was', v_was, 'emergency_stop_off', public.fn_marketing_publishing_on()));
  return jsonb_build_object('ok', true, 'changed', true, 'marketing_golive', p_on,
                            'note', case when not public.fn_marketing_publishing_on() then 'the founder''s emergency stop (marketing_publishing_enabled) is on: nothing posts until it is lifted' end);
end $fn$;
revoke execute on function public.fn_ceo_switches_marketing_golive(boolean, text) from public, anon, authenticated;
grant execute on function public.fn_ceo_switches_marketing_golive(boolean, text) to service_role;

create or replace function public.fn_ceo_accepts_marketing_month(p_month date, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare p public.marketing_month_plan;
begin
  if length(btrim(coalesce(p_reason, ''))) < 20 then return jsonb_build_object('ok', false, 'reason', 'say why, in a sentence (20 characters or more)'); end if;
  update public.marketing_month_plan set status = 'accepted', updated_at = now(),
         verdict = coalesce(verdict, '{}'::jsonb) || jsonb_build_object('accepted_by', 'ceo', 'accepted_at', now())
   where month = p_month and status = 'sent_to_founder' returning * into p;
  if p.month is null then return jsonb_build_object('ok', false, 'reason', 'no plan for ' || p_month || ' is waiting on the founder'); end if;
  insert into public.marketing_ceo_decision (subject_kind, subject_ref, decision, reason, evidence)
  values ('month_plan', p_month::text, 'accept', btrim(p_reason), jsonb_build_object('ceo', p.verdict->'ceo', 'plan_sent_at', p.plan_sent_at));
  return jsonb_build_object('ok', true, 'month', p.month, 'status', p.status);
end $fn$;
revoke execute on function public.fn_ceo_accepts_marketing_month(date, text) from public, anon, authenticated;
grant execute on function public.fn_ceo_accepts_marketing_month(date, text) to service_role;

create or replace function public.fn_ceo_approves_marketing_calendar(p_campaign_key text, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare c public.marketing_campaign; v_now text; v_last timestamptz; v_refuse text; v_id bigint;
begin
  select * into c from public.marketing_campaign where campaign_key = p_campaign_key for update;
  if c.id is null then return jsonb_build_object('ok', false, 'reason', 'no such campaign'); end if;
  v_now := public.fn_marketing_campaign_hash(c.id);
  select max(scheduled_at) into v_last from public.marketing_post where campaign_id = c.id and status <> 'cancelled';
  v_refuse := case
    when length(btrim(coalesce(p_reason, ''))) < 20 then 'say why, in a sentence (20 characters or more)'
    when c.is_demo then 'a demo campaign is never approved'
    when c.approved_hash is not null and c.approved_hash = v_now then 'already approved exactly as it is'
    when c.calendar_hash is null then 'the calendar was never built'
    when c.calendar_hash is distinct from v_now then 'the calendar was changed after it was built: it is rebuilt first'
    when c.spend_policy <> 'organic_only' then 'a calendar that spends money is not approved here: spending goes through the CEO''s company limits'
    when v_last is null or v_last <= now() then 'no post left to go out'
    end;
  if v_refuse is not null then return jsonb_build_object('ok', false, 'reason', v_refuse); end if;
  insert into public.marketing_ceo_decision (subject_kind, subject_ref, decision, reason, evidence)
  values ('calendar', c.campaign_key, 'approve', btrim(p_reason), jsonb_build_object('hash', v_now, 'last_post_at', v_last, 'spend_policy', c.spend_policy))
  returning id into v_id;
  update public.marketing_campaign set approved_by = 'ceo', approved_at = now(), approved_hash = v_now,
         approved_message_id = 'ceo_decision:' || v_id, updated_at = now()
   where id = c.id;
  return jsonb_build_object('ok', true, 'campaign_key', c.campaign_key, 'hash', v_now, 'decision', v_id);
end $fn$;
revoke execute on function public.fn_ceo_approves_marketing_calendar(text, text) from public, anon, authenticated;
grant execute on function public.fn_ceo_approves_marketing_calendar(text, text) to service_role;

create or replace function public.fn_ceo_publishes_article(p_slug text, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.marketing_article;
begin
  if length(btrim(coalesce(p_reason, ''))) < 20 then return jsonb_build_object('ok', false, 'reason', 'say why, in a sentence (20 characters or more)'); end if;
  select * into a from public.marketing_article where slug = p_slug and not is_demo;
  if a.id is null then return jsonb_build_object('ok', false, 'reason', 'no such article'); end if;
  if a.status <> 'approved' or a.approved_by is distinct from 'ceo' then
    return jsonb_build_object('ok', false, 'reason', 'only an article the CEO approved after its review rounds is published (status ' || a.status || ')');
  end if;
  if exists (select 1 from public.marketing_ceo_decision d where d.subject_kind = 'article' and d.subject_ref = p_slug and d.decision = 'publish') then
    return jsonb_build_object('ok', true, 'changed', false, 'slug', p_slug);
  end if;
  insert into public.marketing_ceo_decision (subject_kind, subject_ref, decision, reason, evidence)
  values ('article', p_slug, 'publish', btrim(p_reason), jsonb_build_object('article_id', a.id, 'approved_at', a.approved_at));
  return jsonb_build_object('ok', true, 'changed', true, 'slug', p_slug, 'released', 'on its weekly slot by fn_marketing_article_release_due');
end $fn$;
revoke execute on function public.fn_ceo_publishes_article(text, text) from public, anon, authenticated;
grant execute on function public.fn_ceo_publishes_article(text, text) to service_role;

-- The CEO seat's hourly marketing round: code decides inside the boundaries above, each decision with its reason.
create or replace function public.fn_ceo_decides_marketing()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare p record; c record; v jsonb; v_out jsonb := '[]'::jsonb;
begin
  -- a month waiting on the founder: the CEO accepts the plan it already reviewed
  for p in select * from public.marketing_month_plan where status = 'sent_to_founder' order by month loop
    v := public.fn_ceo_accepts_marketing_month(p.month, left('The CEO accepts the ' || to_char(p.month, 'FMMonth YYYY') || ' plan it reviewed'
           || coalesce(' in round ' || (p.verdict->'ceo'->>'round'), '') || ': ' || coalesce(nullif(p.verdict->'ceo'->>'reasons', ''), 'its review passed every criterion')
           || '. Ruling 1696: the month no longer waits on the founder.', 4000));
    v_out := v_out || jsonb_build_object('month', p.month, 'result', v);
  end loop;
  -- a calendar built from the accepted month, unedited, organic, with posts to come: the CEO approves it as built
  for c in select m.campaign_key, m.month from public.marketing_campaign m
            where not m.is_demo and m.calendar_hash is not null and m.spend_policy = 'organic_only'
              and (m.approved_hash is null or m.approved_hash <> m.calendar_hash)
              and m.calendar_hash = public.fn_marketing_campaign_hash(m.id)
              and exists (select 1 from public.marketing_post x where x.campaign_id = m.id and x.status <> 'cancelled' and x.scheduled_at > now()) loop
    v := public.fn_ceo_approves_marketing_calendar(c.campaign_key, 'The CEO approves the calendar exactly as built (content hash recorded): organic only, '
           || 'UAE working days only, every post through the brand and hard-rule lint at build; ruling 1696.');
    v_out := v_out || jsonb_build_object('calendar', c.campaign_key, 'result', v);
  end loop;
  -- an article the CEO approved and has not yet published: the CEO publishes it (released on its weekly slot), unless the
  -- founder's emergency stop is on
  if public.fn_marketing_publishing_on() then
    for c in select a.slug from public.marketing_article a
              where a.status = 'approved' and a.approved_by = 'ceo' and a.kind = 'market_topic' and not a.is_demo
                and not exists (select 1 from public.marketing_ceo_decision d where d.subject_kind = 'article' and d.subject_ref = a.slug and d.decision = 'publish')
              order by a.approved_at loop
      v := public.fn_ceo_publishes_article(c.slug, 'The CEO publishes the market article it approved after its review rounds: one blog a week on a UAE working day (rulings 1058, 1696).');
      v_out := v_out || jsonb_build_object('article', c.slug, 'result', v);
    end loop;
  end if;
  return jsonb_build_object('decisions', v_out, 'marketing_golive', public.fn_marketing_publishing_live(), 'emergency_stop_off', public.fn_marketing_publishing_on());
end $fn$;
revoke execute on function public.fn_ceo_decides_marketing() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.marketing_decisions', 'ceo', interval '1 hour', 'fn_ceo_decides_marketing',
   'The CEO, not the founder, accepts the marketing month it reviewed, approves a calendar exactly as built (organic, unedited, posts to come) and publishes the articles it approved (released one a week); marketing_golive is the CEO''s to move with a reason; the founder''s emergency stop outranks all. Ruling 1696.',
   'scripts/sql/the_ceo_approves_the_marketing_month_publishes_articles_and_holds_the_marketing_switch.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('marketing_ceo_decision', true, 'ceo', 'Every CEO decision on marketing, with its reason (ruling 1696).', 'ceo')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category, reason = excluded.reason, added_by = excluded.added_by;

-- ── THE TWO PIPES, NOW RECORDING THE CEO'S DECISION (the live definitions of 15 Nov 2026, changed only where marked) ───
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

  -- ceo_approved: THE CEO ACCEPTS IT (15 Nov 2026, rulings 1696/1705; was: the founder's "approve" reply). The plan is
  -- accepted here, recorded in marketing_ceo_decision with the CEO's own review as its reason, and the founder is sent it once
  -- for information and as the request for the videos only he films (content, not approval).
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
         || E'\n\nThe CEO has accepted this plan; nothing waits for your approval. When the videos are ready, reply to this email with them '
         || '(attachments or links), and say so in the same reply if you want an idea changed. '
         || 'The marketing seat then builds the calendar (dates, times per platform, captions, hashtags, links); the CEO approves it and it is published. '
         || 'You are told what goes out.';
  v_nid := public.fn_marketing_mail_founder('marketing_month_plan', 'Video plan for ' || v_mname || ' [plan ' || v_token || ']',
                                            v_body, null, 'plan+' || v_token || '@mail.quotesdone.com');
  update public.marketing_month_plan set status = 'accepted', plan_token = v_token, plan_notification_id = v_nid,
         plan_sent_at = now(), updated_at = now(),
         verdict = coalesce(verdict, '{}'::jsonb) || jsonb_build_object('accepted_by', 'ceo', 'accepted_at', now())
   where month = v_month;
  insert into public.marketing_ceo_decision (subject_kind, subject_ref, decision, reason, evidence)
  values ('month_plan', v_month::text, 'accept',
          left('The CEO accepted the ' || v_mname || ' plan it reviewed' || coalesce(' in round ' || (p.verdict->'ceo'->>'round'), '') || ': '
               || coalesce(nullif(p.verdict->'ceo'->>'reasons', ''), 'its review passed every criterion') || ' (ruling 1696: the CEO, not the founder, accepts the month).', 4000),
          jsonb_build_object('ideas', jsonb_array_length(v_ideas), 'ceo', p.verdict->'ceo'));
  return jsonb_build_object('sent', true, 'month', v_month, 'ideas', jsonb_array_length(v_ideas), 'notification_id', v_nid,
                            'ceo_round', p.verdict->'ceo'->'round', 'has_data', p.plan->'learned'->'has_data', 'shifted_to', p.plan->'shifted_to');
end $function$

;
revoke execute on function public.fn_marketing_month_plan_tick(date, boolean) from public, anon, authenticated;

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
  -- THE CEO PUBLISHES IT (15 Nov 2026, ruling 1696): a CEO publish decision for this article (fn_ceo_publishes_article, with
  -- its reason) releases it on its weekly slot; marketing_golive, which also starts the founder's morning LinkedIn list, is no
  -- longer the only key. Neither: held, as before.
  -- THE FOUNDER'S EMERGENCY STOP, AT RELEASE TIME (review item 6): a CEO decision written while it was off does not release an
  -- article once he has switched it on (fn_ceo_decides_marketing reads it only when the decision is written).
  if not public.fn_marketing_publishing_on() then
    return jsonb_build_object('released', null, 'held', true, 'would_release', v_next.slug, 'reason', 'the founder''s emergency stop (marketing_publishing_enabled) is on');
  end if;
  if not public.fn_marketing_publishing_live()
     and not exists (select 1 from public.marketing_ceo_decision d where d.subject_kind = 'article' and d.subject_ref = v_next.slug and d.decision = 'publish') then
    return jsonb_build_object('released', null, 'held', true, 'would_release', v_next.slug, 'reason', 'no CEO publish decision and marketing_golive is not true');
  end if;
  update public.marketing_article set status = 'released', released_at = now(), updated_at = now() where id = v_next.id;
  return jsonb_build_object('released', v_next.slug, 'this_week', v_week + 1);
end $function$

;
revoke execute on function public.fn_marketing_article_release_due() from public, anon, authenticated;

-- THE FOUNDER'S ACKNOWLEDGEMENT (the review's note): the live definition of 15 Nov 2026 (pg_get_functiondef, SELECT; identical to
-- the mirror), changed only in its comment and its message. It still told him "reply "approve" to that calendar and it is scheduled
-- and published"; the CEO approves the calendar now (fn_ceo_approves_marketing_calendar) and he is informed, not asked (ruling 1696).
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
    -- his reply with the content: the CEO accepted the month already (fn_marketing_month_plan_tick, fn_ceo_accepts_marketing_month);
    -- the status stays 'accepted' for a month that reached him before that (the calendar builder reads it), and his words are kept
    update public.marketing_month_plan set status = 'accepted', founder_decided_at = now(),
           founder_note = left(btrim(coalesce(p->>'text', '')), 2000), updated_at = now() where month = m.month;
    v_out := 'content_received';
    v_msg := 'Received for ' || to_char(m.month, 'FMMonth YYYY') || ' (' || cardinality(v_atts) || ' attachment(s)). The marketing seat builds the calendar from it '
             || '(request ' || v_rid || '); the CEO approves it and it is scheduled and published. You are told what goes out; nothing waits for you.';
  end if;
  perform public.fn_marketing_mail_founder('marketing_month_plan_reply',
    case when v_out = 'content_received' then 'Received: ' else 'Not filed: ' end || 'video plan ' || coalesce(to_char(m.month, 'FMMonth YYYY'), ''), v_msg);
  return jsonb_build_object('outcome', v_out, 'month', m.month, 'request_id', v_rid);
end $function$

;
revoke execute on function public.fn_marketing_month_plan_reply(jsonb) from public, anon, authenticated;
