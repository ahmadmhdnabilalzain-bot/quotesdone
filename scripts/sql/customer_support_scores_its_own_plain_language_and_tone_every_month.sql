-- CUSTOMER SUPPORT SCORES ITS OWN PLAIN LANGUAGE AND TONE EVERY MONTH.
--
-- Seat: customer_support. Founder instruction 1013, item 7 (29 Sep 2026): plain-language customer answers.
-- The gate itself is code, in the one shared reply path (supabase/functions/_shared/support_reply.ts and
-- _shared/readability.ts): every reply is scored for sentence length, jargon and the customer's language;
-- a failure is rewritten once through the model, a second failure (or the model hold) sends the plain
-- canned answer. This file is where those scores land and where the seat reviews them each month.
--
--   support_reply_readability            one row per reply sent through supportReply(): channel, language,
--                                        path (reasoned | fallback), rewritten, readability score, tone score,
--                                        the issues found. Written by fn_support_reply_readability_log only.
--   customer_support_monthly_review      one row per Dubai calendar month: the seat's monthly self-review.
--   fn_customer_support_monthly_self_review()
--                                        scores the last complete month: replies, average readability and
--                                        tone, share that passed first time, rewrites, canned fall-backs the
--                                        gate caused, by channel and language, and the most frequent issues.
--                                        A month under target says so in below_target; it never changes a reply.
--
-- Targets (each reasoned in the comment next to it, so no number decides alone):
--   readability average >= 90   the gate fails anything that is not 100 minus small penalties; a month
--                               averaging under 90 means rewrites are carrying the seat.
--   tone average >= 90          one shouted word or one blaming phrase costs 10-20; under 90 is a pattern.
--   first-time pass >= 80%      more than one reply in five needing a rewrite is a prompt to fix, not luck.
--
-- Demo rows (a message starting "ZZ DEMO") are marked demo and only a fixture run (qd.duty_fixtures = on)
-- reads them, the same separation the weekly case review keeps. Nothing here is applied before the PR merges.

create table if not exists public.support_reply_readability (
  id          bigserial primary key,
  created_at  timestamptz not null default now(),
  channel     text not null check (channel in ('widget', 'whatsapp', 'email', 'portal')),
  lang        text not null check (lang in ('en', 'ar')),
  path        text not null check (path in ('reasoned', 'fallback')),
  rewritten   boolean not null default false,
  score       smallint not null check (score between 0 and 100),
  tone        smallint not null check (tone between 0 and 100),
  issues      text[] not null default '{}',
  reason      text,
  demo        boolean not null default false
);
comment on table public.support_reply_readability is
  'customer_support: the plain-language gate''s score for every reply sent through _shared/support_reply.ts (founder instruction 1013 item 7). Read by fn_customer_support_monthly_self_review.';
create index if not exists support_reply_readability_created_at on public.support_reply_readability (created_at);
alter table public.support_reply_readability enable row level security;
drop policy if exists support_reply_readability_service_role_only on public.support_reply_readability;
create policy support_reply_readability_service_role_only on public.support_reply_readability
  as permissive for all to public using (false) with check (false);
revoke all on public.support_reply_readability from anon, authenticated;

create table if not exists public.customer_support_monthly_review (
  month        date primary key check (month = date_trunc('month', month)::date),
  metrics      jsonb not null,
  below_target text[] not null default '{}',
  fixture      boolean not null default false,
  reviewed_at  timestamptz not null default now()
);
comment on table public.customer_support_monthly_review is
  'customer_support: the monthly self-review of reply readability and tone (founder instruction 1013 item 7).';
alter table public.customer_support_monthly_review enable row level security;
drop policy if exists customer_support_monthly_review_service_role_only on public.customer_support_monthly_review;
create policy customer_support_monthly_review_service_role_only on public.customer_support_monthly_review
  as permissive for all to public using (false) with check (false);
revoke all on public.customer_support_monthly_review from anon, authenticated;

create or replace function public.fn_support_reply_readability_log(
  p_channel text, p_lang text, p_path text, p_rewritten boolean, p_score integer, p_tone integer,
  p_issues text[], p_reason text, p_demo boolean)
returns void language sql security definer set search_path to 'public', 'pg_temp' as $fn$
  insert into public.support_reply_readability (channel, lang, path, rewritten, score, tone, issues, reason, demo)
  values (p_channel, p_lang, p_path, coalesce(p_rewritten, false), p_score, p_tone, coalesce(p_issues, '{}'),
          left(p_reason, 300), coalesce(p_demo, false));
$fn$;
revoke execute on function public.fn_support_reply_readability_log(text, text, text, boolean, integer, integer, text[], text, boolean) from public, anon, authenticated;
grant execute on function public.fn_support_reply_readability_log(text, text, text, boolean, integer, integer, text[], text, boolean) to service_role;

create or replace function public.fn_customer_support_monthly_self_review()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  -- the last COMPLETE Dubai calendar month
  v_month date := (date_trunc('month', now() at time zone 'Asia/Dubai') - interval '1 month')::date;
  v_from timestamptz := v_month::timestamp at time zone 'Asia/Dubai';
  v_to timestamptz := (v_month + interval '1 month')::timestamp at time zone 'Asia/Dubai';
  v_m jsonb; v_below text[] := '{}';
begin
  select jsonb_build_object(
           'month', v_month, 'replies', count(*),
           'readability_avg', round(avg(r.score), 1), 'tone_avg', round(avg(r.tone), 1),
           'first_time_pass_share', round(avg(case when r.path = 'reasoned' and not r.rewritten and r.score = 100 and r.issues = '{}' then 1 else 0 end)
                                          filter (where r.path = 'reasoned' or r.reason like 'readability:%'), 3),
           'rewritten', count(*) filter (where r.rewritten),
           'canned_because_unreadable', count(*) filter (where r.reason like 'readability:%'),
           'canned_because_no_model', count(*) filter (where r.path = 'fallback' and coalesce(r.reason, '') not like 'readability:%'),
           'by_channel', (select coalesce(jsonb_object_agg(c.channel, jsonb_build_object('replies', c.n, 'readability_avg', c.s, 'tone_avg', c.t)), '{}')
                            from (select channel, count(*) n, round(avg(score), 1) s, round(avg(tone), 1) t from public.support_reply_readability
                                   where created_at >= v_from and created_at < v_to and demo = v_fx group by channel) c),
           'by_language', (select coalesce(jsonb_object_agg(l.lang, jsonb_build_object('replies', l.n, 'readability_avg', l.s, 'tone_avg', l.t)), '{}')
                             from (select lang, count(*) n, round(avg(score), 1) s, round(avg(tone), 1) t from public.support_reply_readability
                                    where created_at >= v_from and created_at < v_to and demo = v_fx group by lang) l),
           'top_issues', (select coalesce(jsonb_agg(jsonb_build_object('issue', i.k, 'count', i.n) order by i.n desc), '[]')
                            from (select split_part(x, ':', 1) k, count(*) n
                                    from public.support_reply_readability, unnest(issues) x
                                   where created_at >= v_from and created_at < v_to and demo = v_fx
                                   group by 1 order by 2 desc limit 5) i))
    into v_m
    from public.support_reply_readability r
   where r.created_at >= v_from and r.created_at < v_to and r.demo = v_fx;

  if (v_m->>'replies')::int > 0 then
    if (v_m->>'readability_avg')::numeric < 90 then v_below := array_append(v_below, 'readability_avg<90'); end if;
    if (v_m->>'tone_avg')::numeric < 90 then v_below := array_append(v_below, 'tone_avg<90'); end if;
    if (v_m->>'first_time_pass_share')::numeric < 0.8 then v_below := array_append(v_below, 'first_time_pass<80%'); end if;
  end if;

  -- a fixture run never overwrites the real month's row
  if not v_fx or not exists (select 1 from public.customer_support_monthly_review where month = v_month and not fixture) then
    insert into public.customer_support_monthly_review (month, metrics, below_target, fixture)
    values (v_month, v_m, v_below, v_fx)
    on conflict (month) do update set metrics = excluded.metrics, below_target = excluded.below_target,
                                      fixture = excluded.fixture, reviewed_at = now();
  end if;
  return v_m || jsonb_build_object('below_target', to_jsonb(v_below), 'fixture', v_fx);
end $fn$;
revoke execute on function public.fn_customer_support_monthly_self_review() from public, anon, authenticated;
grant execute on function public.fn_customer_support_monthly_self_review() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('customer_support.monthly_self_review', 'customer_support', interval '30 days', 'fn_customer_support_monthly_self_review',
   'the monthly self-review: readability and tone of every reply of the last complete month, rewrites, canned fall-backs, by channel and language',
   'scripts/sql/customer_support_scores_its_own_plain_language_and_tone_every_month.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;
