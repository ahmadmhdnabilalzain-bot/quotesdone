-- CUSTOMER SUPPORT SCORES EVERY NOTICE A CUSTOMER OR SUPPLIER READS FOR PLAIN LANGUAGE, AND SENDS A FAILING TEMPLATE
-- BACK TO THE SEAT THAT WRITES IT.
--
-- Assigned: customer_support (the communication seat: it delivers every message, 24 Sep 2026 ownership map). 27 Oct 2026.
-- Founder ledger 1013, item 7: "plain-language customer answers".
--
-- ══ MEASURED, 27 Oct 2026, htdblwldjkcgjvmqkbeh (read-only) ═════════════════════════════════════════════════════════
--   The plain-language gate (supabase/functions/_shared/readability.ts) scores replies that pass supportReply(): 132 rows
--   in support_reply_readability (105 real), and PR #1549 adds the widget's main road. Neither scores a NOTICE: the
--   templated messages routines write straight into public.notifications. In the last 30 days 378 notifications went to
--   a customer or a supplier (supplier_invite_seed 333, support_csat_request 41, duty_activation_first_request 2,
--   support_case_closed 2), and not one of them was scored. Answers that reach people as notices (billing answers,
--   refund decisions, charge-dispute answers, case closures) take the same road.
--
-- ══ WHAT THIS ADDS (code only; no model) ═══════════════════════════════════════════════════════════════════════════
--   fn_plain_language_score(text, lang)  the SQL twin of checkReadability() in _shared/readability.ts: the same three
--       rules (longest sentence <= 28 words, average <= 20 from 3 sentences up, no jargon or internal identifiers, the
--       reader's language) and the same tone deductions. A bare figure is not a word. Parity with the TypeScript is
--       held by scripts/checks/the_plain_language_score_is_the_same_in_sql_and_typescript.test.mjs.
--   notice_plain_language           one row per notification to a customer or a supplier: its score, tone, issues.
--   notice_plain_language_cause     one row per notice TYPE that fails: opened, handed to the seat that writes it,
--                                   measured, closed by customer_support when the type passes again.
--   customer_support.notice_plain_language (daily) fn_customer_support_notice_plain_language():
--       1. scores every unscored notice of the last 35 days (500 a run);
--       2. a type with 3+ notices in 30 days and more than one in five failing opens ONE cause. If the writer is another
--          seat (notifications.requested_by, the most frequent one), customer_support hands it over as support.root_cause
--          (registered: originator closes) with the failing share, the top issues and the worst example's issues;
--          a type support writes itself is support's own to fix (no handoff);
--       3. a cause whose type has 3+ notices written after it opened (a notification-id watermark, so the notices that
--          opened it never count towards closing it), 80%+ passing, is CLOSED by customer_support, which
--          re-reads the scores itself (nothing is one-way: the receiver never closes it).
--   Language: a supplier is always written to in English (founder, 28 Sep 2026); a customer in notifications.lang, else
--   the language most of the letters are in.
--   Demo: a notice to a demo address or carrying "ZZ DEMO" in its subject or body is scored and marked demo; only a fixture run
--   (qd.duty_fixtures = on) opens causes from demo rows, the separation every support duty keeps.
--
-- WHAT IT DOES NOT DO. It rewrites no notice and holds no send: a template is code, changed by its owning seat. It does
-- not touch support_reply_readability or the monthly review, which stay the reply road's.
--
-- Prevented by: scripts/checks/the_plain_language_score_is_the_same_in_sql_and_typescript.test.mjs
-- Pending: scripts/sql/pending/customer_support_scores_every_notice_a_customer_or_supplier_reads_for_plain_language.txt

create table if not exists public.notice_plain_language (
  notification_id bigint primary key,
  scored_at       timestamptz not null default now(),
  sent_at         timestamptz,
  type            text not null,
  to_role         text not null,
  requested_by    text,
  channel         text,
  lang            text not null check (lang in ('en', 'ar')),
  ok              boolean not null,
  score           smallint not null check (score between 0 and 100),
  tone            smallint not null check (tone between 0 and 100),
  issues          text[] not null default '{}',
  demo            boolean not null default false
);
comment on table public.notice_plain_language is
  'customer_support: the plain-language score of every notification sent to a customer or a supplier (ledger 1013 item 7). Written by fn_customer_support_notice_plain_language only.';
create index if not exists notice_plain_language_type_scored on public.notice_plain_language (type, scored_at);
alter table public.notice_plain_language enable row level security;
drop policy if exists notice_plain_language_service_role_only on public.notice_plain_language;
create policy notice_plain_language_service_role_only on public.notice_plain_language
  as permissive for all to public using (false) with check (false);
revoke all on public.notice_plain_language from anon, authenticated;

create table if not exists public.notice_plain_language_cause (
  id           bigserial primary key,
  type         text not null,
  owner_seat   text not null references public.org_role (role_id),
  opened_at    timestamptz not null default now(),
  baseline     jsonb not null,
  status       text not null default 'open' check (status in ('open', 'handed_off', 'closed')),
  handoff_id   bigint,
  measurements jsonb not null default '[]'::jsonb,
  closed_at    timestamptz,
  fixture      boolean not null default false
);
comment on table public.notice_plain_language_cause is
  'customer_support: a notice type failing the plain-language score, handed to the seat that writes it and closed by customer_support when it passes again.';
create unique index if not exists notice_plain_language_cause_one_open
  on public.notice_plain_language_cause (type, fixture) where status <> 'closed';
alter table public.notice_plain_language_cause enable row level security;
drop policy if exists notice_plain_language_cause_service_role_only on public.notice_plain_language_cause;
create policy notice_plain_language_cause_service_role_only on public.notice_plain_language_cause
  as permissive for all to public using (false) with check (false);
revoke all on public.notice_plain_language_cause from anon, authenticated;

-- THE SCORE. Every constant and list below is the one in supabase/functions/_shared/readability.ts; the parity check
-- reads both files and fails when they part.
create or replace function public.fn_plain_language_score(p_text text, p_lang text)
returns jsonb
language plpgsql
immutable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  c_max_sentence constant int := 28;      -- MAX_SENTENCE_WORDS
  c_max_avg      constant int := 20;      -- MAX_AVG_SENTENCE_WORDS
  c_min_for_avg  constant int := 3;       -- MIN_SENTENCES_FOR_AVERAGE
  c_jargon_en constant text[] := array['pursuant', 'herein', 'hereby', 'aforementioned', 'heretofore', 'notwithstanding',
    'utilise', 'utilize', 'leverage', 'synergy', 'facilitate', 'escalation matrix', 'ticket id', 'workflow', 'backend',
    'endpoint', 'payload', 'webhook', 'database', 'null', 'undefined', 'rfq', 'sla', 'kyc', 'api', 'rls', 'sku', 'moq',
    'incoterm'];
  c_jargon_ar constant text[] := array['بموجب', 'المذكور أعلاه', 'آنف الذكر', 'حيثما ينطبق', 'قاعدة البيانات'];
  c_acronyms constant text[] := array['UAE', 'AED', 'VAT', 'FAQ', 'PDF', 'OTP', 'USD', 'GCC', 'DED', 'LLC', 'FZE', 'FZCO', 'OK'];
  -- letters: any alphabetic character (Latin, accented, Arabic)
  c_letter constant text := '[[:alpha:]]';
  v_body text; v_lower text;
  v_counts int[] := '{}'; v_s text; v_n int; v_max int := 0; v_avg numeric := 0; v_sentences int := 0;
  v_jargon text[] := '{}'; j text;
  v_ar int; v_la int; v_share numeric := 0;
  v_issues text[] := '{}'; v_score numeric := 100; v_tone numeric := 100; v_averaged boolean;
  v_shout int := 0;
begin
  v_body := btrim(regexp_replace(coalesce(p_text, ''), 'https?://\S+|www\.\S+|\S+@\S+\.\S+', ' ', 'g'));

  -- a sentence ends at . ! ? ؟ or a line break; a decimal point inside a number is not an end
  for v_s in select btrim(x) from regexp_split_to_table(v_body, '(?<![0-9])[.!?؟]+(?![0-9])|\n+') x loop
    continue when v_s !~ '[[:alnum:]]';
    select count(*) into v_n from regexp_split_to_table(v_s, '\s+') w where w ~ c_letter;
    v_counts := v_counts || v_n;
  end loop;
  v_sentences := coalesce(cardinality(v_counts), 0);
  if v_sentences > 0 then
    select max(c), round(avg(c), 1) into v_max, v_avg from unnest(v_counts) c;
  end if;

  v_lower := lower(v_body);
  foreach j in array c_jargon_en loop
    if v_lower ~ ('(^|[^[:alpha:]])' || replace(j, ' ', '\s+') || '([^[:alpha:]]|$)') then v_jargon := v_jargon || j; end if;
  end loop;
  foreach j in array c_jargon_ar loop
    if position(j in v_body) > 0 then v_jargon := v_jargon || j; end if;
  end loop;
  -- anything shaped like an internal identifier (snake_case, fn_ names)
  v_jargon := v_jargon || coalesce((select array_agg(x[1]) from regexp_matches(v_body, '(\m[a-z]+(?:_[a-z0-9]+)+\M)', 'g') x), '{}');
  -- distinct, first-seen order kept (the TypeScript reports [...new Set(jargon)])
  select coalesce(array_agg(x order by o), '{}') into v_jargon
    from (select x, min(o) o from unnest(v_jargon) with ordinality u(x, o) where x is not null group by x) d;

  v_ar := length(regexp_replace(v_body, '[^؀-ۿ]', '', 'g'));
  v_la := length(regexp_replace(v_body, '[^A-Za-z]', '', 'g'));
  if v_ar + v_la > 0 then v_share := round(v_ar::numeric / (v_ar + v_la), 2); end if;

  v_averaged := v_sentences >= c_min_for_avg;
  if v_max > c_max_sentence then v_issues := v_issues || ('long_sentence:' || v_max); end if;
  -- printed as JavaScript prints a number: 22, not 22.0
  if v_averaged and v_avg > c_max_avg then
    v_issues := v_issues || ('long_average:' || case when v_avg = trunc(v_avg) then trunc(v_avg)::text else v_avg::text end);
  end if;
  if cardinality(v_jargon) > 0 then
    v_issues := v_issues || ('jargon:' || array_to_string((select array_agg(x) from (select x from unnest(v_jargon) x limit 5) z), ','));
  end if;
  if v_ar + v_la > 0 and p_lang = 'ar' and v_share < 0.6 then v_issues := v_issues || 'wrong_language:expected_ar'::text; end if;
  if v_ar + v_la > 0 and p_lang = 'en' and v_share > 0.1 then v_issues := v_issues || 'wrong_language:expected_en'::text; end if;

  v_score := v_score - greatest(0, v_max - c_max_sentence) * 2;
  if v_averaged then v_score := v_score - greatest(0, v_avg - c_max_avg) * 3; end if;
  v_score := v_score - cardinality(v_jargon) * 10;
  if exists (select 1 from unnest(v_issues) i where i like 'wrong_language%') then v_score := v_score - 50; end if;

  select count(*) into v_shout from regexp_matches(v_body, '\m([A-Z]{4,})\M', 'g') x where not (x[1] = any (c_acronyms));
  v_tone := v_tone - v_shout * 10;
  v_tone := v_tone - (select count(*) from regexp_matches(v_body, '!{2,}', 'g')) * 10;
  v_tone := v_tone - 20 * ((v_body ~* '\myou (failed|forgot|should have|must have|did not read|didn''?t read)\M')::int
                         + (v_body ~* '\myour fault\M')::int
                         + (v_body ~* '\mobviously\M')::int
                         + (v_body ~* '\mas (i|we) (already )?(said|explained|told you)\M')::int
                         + (v_body ~ 'كما ذكرنا سابقا')::int
                         + (v_body ~ 'خطؤك')::int);

  return jsonb_build_object(
    'ok', cardinality(v_issues) = 0,
    'score', greatest(0, least(100, round(v_score)))::int,
    'tone', greatest(0, least(100, round(v_tone)))::int,
    'issues', to_jsonb(v_issues),
    'sentences', v_sentences,
    'max_sentence_words', v_max,
    'avg_sentence_words', v_avg,
    'jargon', to_jsonb(v_jargon),
    'arabic_share', v_share);
end $fn$;

revoke execute on function public.fn_plain_language_score(text, text) from public, anon, authenticated;

create or replace function public.fn_customer_support_notice_plain_language()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  n_scored int := 0; n_opened int := 0; n_handed int := 0; n_closed int := 0;
  r record; v_id bigint; v_hid bigint; v_since jsonb; v_owner text;
begin
  -- 1. score what has not been scored
  with todo as (
    select n.id, n.type, n.to_role, n.requested_by, n.channel, coalesce(n.sent_at, n.created_at) as sent_at,
           case when n.to_role = 'supplier' then 'en'
                when n.lang in ('en', 'ar') then n.lang
                when length(regexp_replace(n.body, '[^؀-ۿ]', '', 'g')) > length(regexp_replace(n.body, '[^A-Za-z]', '', 'g')) then 'ar'
                else 'en' end as lang,
           -- measured 27 Oct: fixture invitations greet "Hi ZZ DEMO Supplier team" / "السادة/ ZZ DEMO Supplier", so the
           -- marker is looked for anywhere in the body, not only at its start
           (position('ZZ DEMO' in n.body) > 0 or position('ZZ DEMO' in coalesce(n.subject, '')) > 0
            or coalesce(public.fn_is_demo_email(n.to_email), false)) as demo,
           n.body
      from public.notifications n
     where n.to_role in ('customer', 'supplier') and n.created_at > now() - interval '35 days'
       and nullif(btrim(n.body), '') is not null
       and not exists (select 1 from public.notice_plain_language p where p.notification_id = n.id)
     order by n.id limit 500),
  scored as (select t.*, public.fn_plain_language_score(t.body, t.lang) s from todo t)
  insert into public.notice_plain_language (notification_id, sent_at, type, to_role, requested_by, channel, lang, ok, score, tone, issues, demo)
  select id, sent_at, type, to_role, requested_by, channel, lang, (s->>'ok')::boolean, (s->>'score')::int, (s->>'tone')::int,
         coalesce((select array_agg(x) from jsonb_array_elements_text(s->'issues') x), '{}'), demo
    from scored
  on conflict (notification_id) do nothing;
  get diagnostics n_scored = row_count;

  -- 2. a failing type opens one cause, handed to the seat that writes it
  for r in
    select p.type, count(*) n, count(*) filter (where not p.ok) failing, round(avg(p.score), 1) score_avg,
           -- the kinds of failure, most frequent first: 'long_sentence (12)', 'jargon (3)'
           (select array_agg(k || ' (' || c || ')' order by c desc, k) from (
              select split_part(i, ':', 1) k, count(*) c from public.notice_plain_language q, unnest(q.issues) i
               where q.type = p.type and q.demo = v_fx and coalesce(q.sent_at, q.scored_at) > now() - interval '30 days'
               group by 1) z) as top_issues,
           (select q.requested_by from public.notice_plain_language q where q.type = p.type and q.demo = v_fx
             group by q.requested_by order by count(*) desc limit 1) as writer,
           (select q.notification_id from public.notice_plain_language q where q.type = p.type and q.demo = v_fx
             order by q.score, q.notification_id desc limit 1) as worst_id
      from public.notice_plain_language p
     where p.demo = v_fx and coalesce(p.sent_at, p.scored_at) > now() - interval '30 days'
     group by p.type
    having count(*) >= 3 and count(*) filter (where not p.ok) * 5 > count(*)
  loop
    continue when exists (select 1 from public.notice_plain_language_cause c where c.type = r.type and c.fixture = v_fx and c.status <> 'closed');
    v_owner := case when r.writer in (select role_id from public.org_role where status = 'active') then r.writer else 'customer_support' end;
    insert into public.notice_plain_language_cause (type, owner_seat, baseline, fixture)
    values (r.type, v_owner,
            jsonb_build_object('notices_30d', r.n, 'failing', r.failing, 'score_avg', r.score_avg, 'top_issues', to_jsonb(r.top_issues),
                               'worst_notification_id', r.worst_id,
                               -- the watermark: only notices written AFTER this one can show the template was fixed
                               'after_notification_id', (select max(q.notification_id) from public.notice_plain_language q
                                                          where q.type = r.type and q.demo = v_fx),
                               'worst_issues', (select to_jsonb(q.issues) from public.notice_plain_language q where q.notification_id = r.worst_id)),
            v_fx)
    returning id into v_id;
    n_opened := n_opened + 1;
    if v_owner <> 'customer_support' then
      v_hid := public.fn_seat_handoff('customer_support', v_owner, 'support.root_cause', 'notice_plain_language_cause', v_id::text,
        jsonb_build_object('cause_key', 'plain_language:' || r.type, 'category', 'plain_language', 'topic_tag', r.type,
                           'notice_type', r.type, 'notices_30d', r.n, 'failing', r.failing, 'score_avg', r.score_avg,
                           'top_issues', to_jsonb(r.top_issues), 'worst_notification_id', r.worst_id,
                           'decision', format('customer_support decided the %s template is not plain language: %s of %s notices in 30 days failed (%s)',
                                              r.type, r.failing, r.n, array_to_string(r.top_issues, ', ')),
                           'asks', jsonb_build_array(format('Rewrite the %s template: sentences under 28 words, no internal terms, the reader''s language. customer_support re-reads the scores and closes this.', r.type))));
      update public.notice_plain_language_cause set status = 'handed_off', handoff_id = v_hid where id = v_id;
      n_handed := n_handed + 1;
    end if;
  end loop;

  -- 3. customer_support re-reads and closes a cause whose type passes again
  for r in select c.* from public.notice_plain_language_cause c where c.fixture = v_fx and c.status <> 'closed' loop
    select jsonb_build_object('at', now(), 'notices', count(*), 'passing', count(*) filter (where p.ok),
                              'score_avg', round(avg(p.score), 1))
      into v_since
      from public.notice_plain_language p
     where p.type = r.type and p.demo = v_fx and p.notification_id > coalesce((r.baseline->>'after_notification_id')::bigint, 0);
    update public.notice_plain_language_cause set measurements = measurements || jsonb_build_array(v_since) where id = r.id;
    if (v_since->>'notices')::int >= 3 and (v_since->>'passing')::int * 5 >= (v_since->>'notices')::int * 4 then
      update public.notice_plain_language_cause set status = 'closed', closed_at = now() where id = r.id;
      if r.handoff_id is not null and exists (select 1 from public.agent_actions a where a.id = r.handoff_id and a.status <> 'done') then
        perform set_config('qd.handoff_closer', 'customer_support', true);
        perform public.fn_seat_handoff_complete(r.handoff_id, jsonb_build_object(
          'verified_by', 'customer_support', 'verified_at', now(),
          'verdict', format('the %s notices pass again: %s of %s since the cause opened', r.type, v_since->>'passing', v_since->>'notices'),
          'measurement', v_since));
      end if;
      n_closed := n_closed + 1;
    end if;
  end loop;

  return jsonb_build_object('scored', n_scored, 'causes_opened', n_opened, 'handed_off', n_handed, 'closed', n_closed,
    'open_causes', (select count(*) from public.notice_plain_language_cause where fixture = v_fx and status <> 'closed'),
    'fixture', v_fx);
end $fn$;

revoke execute on function public.fn_customer_support_notice_plain_language() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('customer_support.notice_plain_language', 'customer_support', interval '1 day', 'fn_customer_support_notice_plain_language',
   'Every notice a customer or supplier reads is scored for plain language (the SQL twin of the reply gate); a notice type failing more than one in five opens a cause handed to the seat that writes it, closed by customer_support when the type passes again.',
   'scripts/sql/customer_support_scores_every_notice_a_customer_or_supplier_reads_for_plain_language.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;
