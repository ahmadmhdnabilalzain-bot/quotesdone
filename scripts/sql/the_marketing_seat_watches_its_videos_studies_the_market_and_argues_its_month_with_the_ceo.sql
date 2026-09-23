-- THE MARKETING SEAT WATCHES ITS VIDEOS, STUDIES THE MARKET, AND ARGUES ITS MONTH WITH THE CEO.
-- marketing, 23 September 2026. Founder instructions 865 (plan the next month from the last one), 866 (the plan
-- goes to the CEO first, a real debate, organic only, the agreed plan is the content brief) and 867 (the seat
-- must see and hear the posts, like a person). Build-plan items 6-9; item 10 is
-- the_marketing_seat_gets_a_model_ceiling_and_every_class_it_thinks_with.sql, applied BEFORE this file.
--
-- WHY THIS SHAPE. The model is HELD today (llm_route_health open_until 2126-08-15 on every route) and will be
-- opened. When it opens, every judgement the seat makes must be grounded in rows, bounded in cost, and written
-- to a table -- never lost in a chat reply. So every model step here is the same three parts, the pattern
-- ceo_agent's 'judgement' already uses:
--   fn_marketing_step_request(step, subject)  -> the measured input, the output schema, the class, the cap
--   (TypeScript, supabase/functions/_shared/marketing_judgement.ts: hold check, ONE gateway call)
--   fn_marketing_step_accept(step, subject, seat, output, outcome, reason, model)
--                                              -> validates, writes the step's table, logs marketing_model_run
-- While held the TypeScript calls accept with outcome 'held': ONE marketing_model_run row per step, subject and
-- Dubai day saying "held, not run", and nothing else is written. A malformed answer is 'rejected' with the
-- reason and writes nothing either.
--
-- THE STEPS (seat, class, table):
--   watch            marketing  marketing_watch           marketing_asset_perception   (867: whole video + sound)
--   quality_review   marketing  marketing_quality_review  marketing_asset_review
--   research         marketing  marketing_research        marketing_insight_note       (weekly)
--   evaluate         marketing  marketing_evaluate        marketing_month_plan.verdict (the month's verdict)
--   plan             marketing  marketing_plan            marketing_plan_review_turn + marketing_month_plan.plan
--   plan_defend      marketing  marketing_plan_defend     marketing_plan_review_turn
--   (the CEO's review) ceo  seat_deliberation_*      seat_deliberation_turn -> marketing_plan_review_turn (873)
-- Deterministic, no model: marketing_asset_feature (scripts/media/measure_marketing_assets.mjs on GitHub Actions),
-- market_intel rows (fn_marketing_intel_upsert), the calendar, the brief, the founder's decision.
--
-- THE DEBATE (866), ON THE COMPANY'S ONE REVIEW MACHINE (873, it_engineer's
-- a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql, applied BEFORE this file). Marketing proposes with its
-- reasons and cited evidence; this file opens a seat_deliberation (marketing -> ceo) with the EVIDENCE and the
-- PROPOSAL as separate fields, so the CEO's first pass is BLIND. The review machine routes the CEO to another model
-- family (marketing writes on Sol -> the CEO reviews on Opus 5.5), caps it (AED 50/month, charged to marketing) and
-- records every turn. The CEO's question carries the five criteria (goal, evidence strength, production cost, truth
-- and brand fit, risk if wrong) and the evidence carries each cited video's perception, features, results and key
-- frames. fn_marketing_takes_the_ceo_review reads each recorded CEO comparison back into marketing_plan_review_turn:
-- approve -> accept, revise -> request_changes, reject -> reject; at round 3 the CEO's word decides. Criterion 2 is
-- MEASURED, not trusted: when marketing's turn rests on 1-2 videos/posts and the CEO approved without flagging it, the
-- approval becomes a request to treat the claim as a hypothesis. Marketing answers EVERY ask (concede and adjust, or
-- defend with evidence) and the answer is revised into the same deliberation. At most 3 rounds.
-- The agreed plan becomes the CONTENT BRIEF (topics, formats, music, voice-over, length, count, cadence), sent to the
-- founder ONCE through customer_support's door (founder_mail_policy 'marketing_content_brief'); his acceptance is
-- recorded by fn_marketing_month_plan_founder_decides. The one-approval PDF after the content is ingested is the
-- sibling build's. Marketing, the author, closes the deliberation.
--
-- ORGANIC ONLY (866). fn_marketing_plan_problems refuses any plan with ad spend above zero or that speaks of
-- boosting, sponsoring or paid ads. The only money in the plan is the model ceiling.
--
-- THE CALENDAR (866: "at least a week before the month end", working-day aware). The plan must reach the CEO by
-- the DEADLINE: month end minus 7 days, moved back to a UAE working day (Mon-Fri). Work starts two working days
-- before the deadline so the debate has room.
--
-- CONSUMED, NOT BUILT: marketing_post_metric and fn_marketing_scorecard belong to the sibling metrics build. They
-- are read by name at run time (to_regclass / to_regprocedure) so this file applies before or after them.
--
-- WHAT THIS DOES NOT DO: open the hold, call a model, create an org_task, or plan any paid promotion.

-- ═══ 1. TABLES ═══════════════════════════════════════════════════════════════════════════════════
create table if not exists public.marketing_asset_feature (
  file_sha256          text not null check (file_sha256 ~ '^[0-9a-f]{64}$'),
  extractor_version    text not null,
  asset_bucket         text not null,
  asset_path           text not null,
  bytes                bigint not null check (bytes > 0),
  duration_s           numeric(8,3) not null,
  width                int not null, height int not null,
  aspect               text not null,
  fps                  numeric(8,3) not null,
  scene_cuts           int not null,
  cuts_per_10s         numeric(8,3) not null,
  hook_cuts_first_3s   int not null,
  hook_motion_first_3s numeric(10,4),              -- mean frame difference in the first 3 s (0..255)
  audio_present        boolean not null,
  loudness_lufs        numeric(8,2),                -- EBU R128 integrated, null when silent
  true_peak_db         numeric(8,2),
  speech_band_ratio    numeric(8,4),                -- share of energy in 300-3400 Hz; a PROXY, see the worker
  voiceover_suspected  boolean,
  frames_with_text     int, frames_sampled int,
  text_chars_per_frame numeric(8,2),                -- tesseract over the sampled frames
  keyframes            jsonb not null default '[]'::jsonb check (jsonb_typeof(keyframes) = 'array'),
  music                jsonb not null default '{}'::jsonb, -- {track, bpm, mood} from the campaign Manifest.csv
  toolchain            jsonb not null default '{}'::jsonb,
  measured_at          timestamptz not null default now(),
  primary key (file_sha256, extractor_version)
);
create index if not exists marketing_asset_feature_path on public.marketing_asset_feature (asset_bucket, asset_path);

create table if not exists public.marketing_asset_perception (
  id             bigserial primary key,
  file_sha256    text not null,
  model          text not null,
  prompt_version text not null,
  perception     jsonb not null check (jsonb_typeof(perception) = 'object'),
  disagreements  jsonb not null default '[]'::jsonb,   -- what the model claimed that the measurement contradicts
  created_at     timestamptz not null default now(),
  unique (file_sha256, model, prompt_version)
);

create table if not exists public.marketing_asset_review (
  id          bigserial primary key,
  file_sha256 text not null,
  review      jsonb not null check (jsonb_typeof(review) = 'object'),
  evidence    jsonb not null check (jsonb_typeof(evidence) = 'array' and jsonb_array_length(evidence) > 0),
  inputs      jsonb not null,                            -- which perception, feature and metric rows it was given
  model       text,
  created_at  timestamptz not null default now()
);
create index if not exists marketing_asset_review_sha on public.marketing_asset_review (file_sha256, created_at desc);

create table if not exists public.marketing_insight_note (
  week_start date primary key check (extract(isodow from week_start) = 1),
  synthesis  jsonb not null check (jsonb_typeof(synthesis) = 'object'),
  intel_ids  bigint[] not null,
  model      text,
  created_at timestamptz not null default now()
);

create table if not exists public.marketing_month_plan (
  month               date primary key check (extract(day from month) = 1),   -- the month the plan is FOR
  status              text not null default 'draft'
                      check (status in ('draft','with_ceo','agreed','sent_to_founder','accepted','rejected')),
  verdict             jsonb,                  -- marketing_evaluate on the month before
  plan                jsonb,                  -- the plan as it stands (latest propose/adjust/decide)
  content_brief       jsonb,                  -- the agreed plan as the founder's production brief
  rounds              int not null default 0,
  deliberation_id     bigint,                 -- the seat_deliberation (873) the CEO reviews it in
  sent_turn_id        bigint,                 -- the marketing turn last put before the CEO (so it is sent once)
  brief_handoff_id    bigint,
  founder_decided_at  timestamptz,
  founder_note        text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create table if not exists public.marketing_plan_review_turn (
  id         bigserial primary key,
  month      date not null references public.marketing_month_plan(month),
  round      int not null check (round between 1 and 3),
  seat       text not null check (seat in ('marketing','ceo')),
  move       text not null check (move in ('propose','adjust','defend','accept','request_changes','reject','decide')),
  reasoning  text not null check (length(btrim(reasoning)) >= 40),
  evidence   jsonb not null check (jsonb_typeof(evidence) = 'array' and jsonb_array_length(evidence) > 0),
  changes    jsonb,                          -- the CEO's specific asks (request_changes / reject)
  answers    jsonb,                          -- marketing's answer to EACH ask: concede (and adjust) or defend, with evidence
  deliberation_turn_id bigint,               -- a CEO turn: the seat_deliberation_turn (compare) it was read from
  criteria   jsonb,                          -- the CEO's five criteria, each with its reasoning and evidence
  plan       jsonb,
  model      text,
  created_at timestamptz not null default now(),
  unique (month, round, seat),
  check ((seat = 'marketing') = (move in ('propose','adjust','defend'))),
  check (move not in ('request_changes','reject') or (changes is not null and jsonb_array_length(changes) > 0)),
  check (seat <> 'ceo' or criteria is not null)
);

create table if not exists public.marketing_model_run (
  id           bigserial primary key,
  step         text not null,
  subject      text not null,
  seat         text not null check (seat in ('marketing','ceo')),
  task_class   text not null,
  outcome      text not null check (outcome in ('held_not_run','written','rejected','failed')),
  reason       text,
  model        text,
  output_table text,
  output_ref   text,
  run_day      date not null default ((now() at time zone 'Asia/Dubai')::date),
  created_at   timestamptz not null default now(),
  check ((outcome = 'written') = (output_ref is not null))
);
create unique index if not exists marketing_model_run_held_once_a_day
  on public.marketing_model_run (step, subject, run_day) where outcome = 'held_not_run';

-- market_intel (0 rows, 23 Sep) gains the columns one-row-per-competitor-post needs; competitor gains handles.
alter table public.market_intel add column if not exists source_url text;
alter table public.market_intel add column if not exists platform text;
alter table public.market_intel add column if not exists external_id text;
alter table public.market_intel add column if not exists competitor_id bigint;
alter table public.market_intel add column if not exists posted_at timestamptz;
alter table public.market_intel add column if not exists metrics jsonb;
alter table public.market_intel add column if not exists fetched_at timestamptz;
create unique index if not exists market_intel_one_row_per_post on public.market_intel (platform, external_id) where external_id is not null;
alter table public.competitor add column if not exists social_handles jsonb not null default '{}'::jsonb;

do $$
declare t text;
begin
  foreach t in array array['marketing_asset_feature','marketing_asset_perception','marketing_asset_review',
                           'marketing_insight_note','marketing_month_plan','marketing_plan_review_turn',
                           'marketing_model_run','market_intel'] loop
    execute format('alter table public.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = t) then
      execute format('create policy %I on public.%I as permissive for all to public using (false) with check (false)',
                     t || '_service_role_only', t);
    end if;
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- ═══ 2. DETERMINISTIC DOORS ══════════════════════════════════════════════════════════════════════
-- The media worker records one asset's measured features. Same file + same extractor = same row (upsert).
create or replace function public.fn_marketing_asset_feature_record(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
end $fn$;

-- One row per competitor post, the URL cited. p_rows: [{platform, external_id, competitor_id, source_url,
-- posted_at, caption, media_type, metrics}]. A row without a URL or an id is refused, not guessed.
create or replace function public.fn_marketing_intel_upsert(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
end $fn$;

-- The calendar: which month is being planned, when work starts, and the deadline.
create or replace function public.fn_marketing_plan_calendar(p_at timestamptz default now())
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_today date := (p_at at time zone 'Asia/Dubai')::date;
        v_next date := (date_trunc('month', v_today) + interval '1 month')::date;
        v_deadline date := v_next - 1 - 7; v_start date; n int := 0;
begin
  while extract(isodow from v_deadline) in (6, 7) loop v_deadline := v_deadline - 1; end loop;   -- UAE weekend Sat/Sun
  v_start := v_deadline;
  while n < 2 loop v_start := v_start - 1; if extract(isodow from v_start) not in (6, 7) then n := n + 1; end if; end loop;
  return jsonb_build_object('today', v_today, 'plan_month', v_next, 'evaluated_month', date_trunc('month', v_today)::date,
                            'start', v_start, 'deadline', v_deadline, 'in_window', v_today >= v_start);
end $fn$;

-- Every citation must name something that exists. Returns the problems (empty = fine).
create or replace function public.fn_marketing_evidence_problems(p_evidence jsonb)
returns text[] language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
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
      when 'scorecard'        then r ~ '^\d{4}-\d{2}-01$'
      when 'post_metric'      then to_regclass('public.marketing_post_metric') is not null and coalesce(r, '') <> ''
      else false end;
    if not coalesce(v_ok, false) then
      bad := bad || ('evidence ' || coalesce(k,'?') || ':' || coalesce(r,'?') || ' does not exist');
    end if;
  end loop;
  return bad;
end $fn$;

-- ORGANIC ONLY and complete: the problems with a plan (empty = fine).
create or replace function public.fn_marketing_plan_problems(p_plan jsonb)
returns text[] language plpgsql immutable set search_path to 'public', 'pg_temp' as $fn$
declare bad text[] := '{}'; k text;
begin
  if p_plan is null or jsonb_typeof(p_plan) <> 'object' then return array['plan must be an object']; end if;
  foreach k in array array['topics','formats','music','voiceover','video','cadence','budget'] loop
    if not p_plan ? k then bad := bad || ('plan is missing ' || k); end if;
  end loop;
  if jsonb_typeof(p_plan->'topics') is distinct from 'array' or jsonb_array_length(coalesce(p_plan->'topics','[]')) = 0 then
    bad := bad || 'plan names no topics'::text; end if;
  if coalesce((p_plan->'video'->>'count')::numeric, 0) <= 0 then bad := bad || 'plan.video.count must be above 0'::text; end if;
  if coalesce((p_plan->'video'->>'length_s')::numeric, 0) <= 0 then bad := bad || 'plan.video.length_s must be above 0'::text; end if;
  if coalesce((p_plan->'budget'->>'ad_spend_aed')::numeric, 0) <> 0 then
    bad := bad || 'ORGANIC ONLY (founder 866): plan.budget.ad_spend_aed must be 0'::text; end if;
  if p_plan::text ~* '(boost(ed|ing)?\s+(the\s+)?post|sponsor(ed)?\s+(post|content|ad)|paid\s+(ad|ads|promotion|reach|media)|ad\s*spend\s*(of|:)?\s*(aed|usd)?\s*[1-9]|promoted\s+post|ads\s+manager)' then
    bad := bad || 'ORGANIC ONLY (founder 866): the plan proposes paid promotion'::text; end if;
  return bad;
end $fn$;

-- The same evidence marketing used, per video (867 follow-up: the CEO must SEE the content, not read marketing's
-- summary of it): measured features, the perception row, key frames, and the per-post results.
create or replace function public.fn_marketing_asset_dossier(p_sha text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare f public.marketing_asset_feature; q public.marketing_asset_perception; v_metrics jsonb := '[]'::jsonb;
begin
  select * into f from public.marketing_asset_feature where file_sha256 = p_sha order by measured_at desc limit 1;
  select * into q from public.marketing_asset_perception where file_sha256 = p_sha order by id desc limit 1;
  if to_regclass('public.marketing_post_metric') is not null and f.file_sha256 is not null then
    execute 'select coalesce(jsonb_agg(to_jsonb(m)), ''[]''::jsonb) from (select * from public.marketing_post_metric m '
         || 'where to_jsonb(m)::text like ''%'' || $1 || ''%'' or to_jsonb(m)::text like ''%'' || $2 || ''%'' limit 50) m'
      into v_metrics using p_sha, f.asset_path;
  end if;
  return jsonb_build_object('asset', p_sha, 'path', f.asset_path,
    'features', case when f.file_sha256 is null then null else to_jsonb(f) - 'toolchain' end,
    'perception', case when q.id is null then null else jsonb_build_object('id', q.id, 'model', q.model, 'perception', q.perception, 'disagreements', q.disagreements) end,
    'keyframes', coalesce(f.keyframes, '[]'::jsonb), 'post_metrics', v_metrics,
    'posts_measured', jsonb_array_length(v_metrics));
end $fn$;

-- The videos a turn relies on: every asset its evidence cites, resolved to the file (review/perception id -> sha).
create or replace function public.fn_marketing_assets_cited(p_evidence jsonb)
returns text[] language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(array_agg(distinct sha) filter (where sha is not null), '{}')
    from (select case e->>'kind'
                   when 'asset_feature' then e->>'ref'
                   when 'asset_review' then (select file_sha256 from public.marketing_asset_review where id::text = e->>'ref')
                   when 'asset_perception' then (select file_sha256 from public.marketing_asset_perception where id::text = e->>'ref')
                   when 'post_metric' then 'post:' || (e->>'ref') end sha
            from jsonb_array_elements(coalesce(p_evidence, '[]'::jsonb)) e) x
$fn$;

-- ═══ 3. WHAT IS DUE ══════════════════════════════════════════════════════════════════════════════
-- Bounded: at most 6 perceptions and 6 reviews written per Dubai day, research once a week, the month's work
-- only inside its window. The duty runs at most 1 model step per 30-minute beat (48 a day).
create or replace function public.fn_marketing_steps_due(p_at timestamptz default now())
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare out jsonb := '[]'::jsonb; cal jsonb := public.fn_marketing_plan_calendar(p_at);
        v_day date := (p_at at time zone 'Asia/Dubai')::date; v_week date; p public.marketing_month_plan;
        t public.marketing_plan_review_turn; x record;
begin
  -- watch: every measured asset without a perception by the current prompt version
  if (select count(*) from public.marketing_model_run where step = 'watch' and outcome = 'written' and run_day = v_day) < 6 then
    for x in select distinct on (f.file_sha256) f.file_sha256 from public.marketing_asset_feature f
              where not exists (select 1 from public.marketing_asset_perception q
                                 where q.file_sha256 = f.file_sha256 and q.prompt_version = 'watch-v1')
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
              order by q.id limit 3 loop
      out := out || jsonb_build_object('step', 'quality_review', 'subject', x.file_sha256, 'seat', 'marketing');
    end loop;
  end if;
  -- research: the last complete week, once, when there is anything to read
  v_week := (date_trunc('week', v_day) - interval '7 days')::date;
  if not exists (select 1 from public.marketing_insight_note where week_start = v_week)
     and exists (select 1 from public.market_intel where platform is not null
                   and coalesce(posted_at, created_at) >= v_week and coalesce(posted_at, created_at) < v_week + 7) then
    out := out || jsonb_build_object('step', 'research', 'subject', v_week::text, 'seat', 'marketing');
  end if;
  -- the month: evaluate -> plan -> (the CEO's review on seat_deliberation <-> plan_defend)
  if (cal->>'in_window')::boolean then
    select * into p from public.marketing_month_plan where month = (cal->>'plan_month')::date;
    if p.month is null or p.verdict is null then
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
end $fn$;

-- ═══ 4. THE REQUEST: the measured input for one step ═════════════════════════════════════════════
create or replace function public.fn_marketing_step_request(p_step text, p_subject text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
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
      execute 'select coalesce(jsonb_agg(to_jsonb(m)), ''[]''::jsonb) from (select * from public.marketing_post_metric m '
           || 'where to_jsonb(m)::text like ''%'' || $1 || ''%'' or to_jsonb(m)::text like ''%'' || $2 || ''%'' limit 50) m'
        into v_metrics using p_subject, f.asset_path;
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
    if to_regprocedure('public.fn_marketing_scorecard(date)') is not null then
      begin execute 'select to_jsonb(public.fn_marketing_scorecard($1))' into v_score using (v_month - interval '1 month')::date;
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
end $fn$;

-- ═══ 4b. THE CEO'S REVIEW PACKET (873): question, EVIDENCE and PROPOSAL as three separate things ═══════
-- The evidence is the raw material with no marketing opinion in it, so seat_deliberation's BLIND pass can be given
-- it alone: for every video marketing's turns cite (all perceived videos when none are cited) the perception row
-- (what it shows and sounds like), the measured features, the per-post results and the key frames; the company plan;
-- the market posts; and the measured criterion-2 flag. The proposal is marketing's plan, reasoning, answers and
-- readings. The question carries the CEO's five criteria and the shape its answer must add to the machine's own.
-- KEY FRAMES: listed in evidence.key_frames (bucket/path). seat_deliberation sends its payload as text today; when it
-- attaches image parts these become pictures with no change here.
create or replace function public.fn_marketing_plan_review_packet(p_month date)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
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
end $fn$;

-- ═══ 5. THE ACCEPT: validate, write the step's table, log the run ═════════════════════════════════
create or replace function public.fn_marketing_step_accept(p_step text, p_subject text, p_seat text, p_output jsonb,
  p_outcome text default 'answered', p_reason text default null, p_model text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
              where (a->>'ask') ~ '^\d+$' and (a->>'ask')::int < jsonb_array_length(coalesce(v_last.changes,'[]'))
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
    if abs(coalesce((p_output->>'duration_s_claimed')::numeric, f.duration_s) - f.duration_s) > 1.5 then
      v_dis := v_dis || jsonb_build_object('field', 'duration_s', 'model', p_output->'duration_s_claimed', 'measured', f.duration_s); end if;
    if (p_output->>'has_audio_claimed')::boolean is distinct from f.audio_present and p_output ? 'has_audio_claimed' then
      v_dis := v_dis || jsonb_build_object('field', 'audio_present', 'model', p_output->'has_audio_claimed', 'measured', f.audio_present); end if;
    if f.voiceover_suspected is not null and (p_output->'voiceover'->>'present')::boolean is distinct from f.voiceover_suspected then
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
    -- the CEO reviews it on seat_deliberation (873): opened on the proposal, revised on each answer
    perform public.fn_marketing_plan_to_ceo(v_month);
  end if;

  insert into public.marketing_model_run (step, subject, seat, task_class, outcome, model, output_table, output_ref)
  values (p_step, p_subject, p_seat, v_class, 'written', p_model, v_table, v_ref) returning id into v_run;
  return jsonb_build_object('ok', true, 'outcome', 'written', 'written', true, 'table', v_table, 'ref', v_ref, 'run_id', v_run);
end $fn$;

-- ═══ 6. THE BRIEF, THE CONVERSATION, THE FOUNDER ═════════════════════════════════════════════════
-- The agreed plan, as the production brief the founder and Claude make the videos from. Deterministic.
create or replace function public.fn_marketing_content_brief(p_month date, p_plan jsonb)
returns jsonb language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object('month', p_month, 'organic_only', true,
    'videos', p_plan->'video', 'topics', p_plan->'topics', 'formats', p_plan->'formats',
    'music', p_plan->'music', 'voiceover', p_plan->'voiceover', 'cadence', p_plan->'cadence',
    'who_makes_it', 'The founder and Claude produce the videos; the marketing seat decided what is in them.')
$fn$;

-- ═══ 6b. THE ADAPTER TO THE COMPANY'S REVIEW MACHINE (873) — the ONLY two routines that touch seat_deliberation ═══
-- OUT: marketing's proposal (and each later answer) goes to the CEO as a seat_deliberation. Opened on round 1,
-- revised into the same deliberation after a revise verdict; after a reject marketing's new proposal opens a new
-- one. The machine's own rules apply unchanged: blind first, another family, AED 50/month, "held, not run".
create or replace function public.fn_marketing_plan_to_ceo(p_month date)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
  v_author := coalesce((select model_id from public.model_registry where model_id = v_mkt.model), 'openai/gpt-5.6-sol');
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
end $fn$;

-- IN: each recorded CEO comparison becomes the CEO's turn in marketing's ledger, once. approve -> accept,
-- revise -> request_changes, reject -> reject; in round 3 the CEO's word decides. Criterion 2 is MEASURED here:
-- an approval of a proposal that rests on 1-2 videos/posts, without criteria.evidence_strength.flagged, becomes a
-- request to treat the claim as a hypothesis and say how next month tests it.
create or replace function public.fn_marketing_takes_the_ceo_review(p_month date)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
     and coalesce((o->'criteria'->'evidence_strength'->>'flagged')::boolean, false) is not true then
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
end $fn$;

insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role)
values ('marketing_content_brief', true,
        'Founder instruction 866, 23 Sep 2026: the plan the CEO and marketing agreed is the content brief the founder and Claude produce the videos from. Sent once per month.',
        'marketing')
on conflict (kind) do update set allowed_to_email = excluded.allowed_to_email, reason = excluded.reason,
                                 owner_role = excluded.owner_role, updated_at = now();

-- The originator's loop (marketing, the author): send a waiting plan to the CEO's review, take each CEO comparison
-- back, close the deliberation once the plan is agreed, and send the brief to the founder ONCE.
create or replace function public.fn_marketing_plan_loop_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare p public.marketing_month_plan; n_closed int := 0; n_sent int := 0; n_taken int := 0; v_id bigint; b jsonb; v_status text; r jsonb;
begin
  for p in select * from public.marketing_month_plan where status = 'with_ceo' order by month loop
    perform public.fn_marketing_plan_to_ceo(p.month);
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
      update public.marketing_month_plan set brief_handoff_id = v_id, status = 'sent_to_founder', updated_at = now() where month = p.month;
      n_sent := n_sent + 1;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'ceo_reviews_taken', n_taken, 'deliberations_closed', n_closed, 'briefs_sent', n_sent);
end $fn$;

-- The founder's answer on the brief, recorded (from his portal or by the CEO on his word).
create or replace function public.fn_marketing_month_plan_founder_decides(p_month date, p_accepted boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare p public.marketing_month_plan;
begin
  update public.marketing_month_plan
     set status = case when p_accepted then 'accepted' else 'rejected' end, founder_decided_at = now(),
         founder_note = p_note, updated_at = now()
   where month = p_month and status = 'sent_to_founder' returning * into p;
  if p.month is null then raise exception 'no brief for % is waiting for the founder', p_month; end if;
  return jsonb_build_object('ok', true, 'month', p.month, 'status', p.status);
end $fn$;

-- ═══ 7. NOBODY OUTSIDE THE SERVICE ROLE CALLS THESE (every routine is new: CREATE grants PUBLIC) ══
revoke execute on function public.fn_marketing_asset_feature_record(jsonb) from public, anon, authenticated;
revoke execute on function public.fn_marketing_intel_upsert(jsonb) from public, anon, authenticated;
revoke execute on function public.fn_marketing_plan_calendar(timestamptz) from public, anon, authenticated;
revoke execute on function public.fn_marketing_evidence_problems(jsonb) from public, anon, authenticated;
revoke execute on function public.fn_marketing_plan_problems(jsonb) from public, anon, authenticated;
revoke execute on function public.fn_marketing_steps_due(timestamptz) from public, anon, authenticated;
revoke execute on function public.fn_marketing_asset_dossier(text) from public, anon, authenticated;
revoke execute on function public.fn_marketing_assets_cited(jsonb) from public, anon, authenticated;
revoke execute on function public.fn_marketing_step_request(text, text) from public, anon, authenticated;
revoke execute on function public.fn_marketing_step_accept(text, text, text, jsonb, text, text, text) from public, anon, authenticated;
revoke execute on function public.fn_marketing_content_brief(date, jsonb) from public, anon, authenticated;
revoke execute on function public.fn_marketing_plan_review_packet(date) from public, anon, authenticated;
revoke execute on function public.fn_marketing_plan_to_ceo(date) from public, anon, authenticated;
revoke execute on function public.fn_marketing_takes_the_ceo_review(date) from public, anon, authenticated;
revoke execute on function public.fn_marketing_plan_loop_tick() from public, anon, authenticated;
revoke execute on function public.fn_marketing_month_plan_founder_decides(date, boolean, text) from public, anon, authenticated;

-- ═══ 8. THE DAILY TABLE EXPORT: + this build's tables, and every sibling marketing build's ═══════════
-- Copied from main's winner (the_marketing_seat_writes_articles_and_drafts_linkedin_outreach.sql) with this file's
-- seven tables plus market_intel and competitor added, AND the tables of the three sibling marketing PRs that each
-- restate this function (#873 marketing_platform_spec, marketing_platform_spec_source; #874 marketing_campaign,
-- marketing_post_variant; #875 marketing_post_platform, marketing_post_metric, marketing_first_touch, marketing_goal,
-- marketing_scorecard_report). Applies are serial and the last definition wins, so every restatement carries all.
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
    ('marketing_campaign','marketing'), ('marketing_post_variant','marketing'),
    ('marketing_post_platform','marketing'), ('marketing_post_metric','marketing'), ('marketing_first_touch','marketing'),
    ('marketing_goal','marketing'), ('marketing_scorecard_report','marketing'),
    ('marketing_asset_feature','marketing'), ('marketing_asset_perception','marketing'), ('marketing_asset_review','marketing'),
    ('marketing_insight_note','marketing'), ('marketing_month_plan','marketing'), ('marketing_plan_review_turn','marketing'),
    ('marketing_model_run','marketing'), ('market_intel','marketing'), ('competitor','marketing'),
    ('table_export_change','backup')
  ) v(t, s)
  -- The sibling PRs' tables may not exist yet when this applies; backup/index.ts fails the whole day on a
  -- missing table, so ONLY those nine are skipped until their own file creates them. Every other table in the
  -- list still fails loudly if it disappears.
  where v.t not in ('marketing_platform_spec','marketing_platform_spec_source','marketing_campaign','marketing_post_variant',
                    'marketing_post_platform','marketing_post_metric','marketing_first_touch','marketing_goal','marketing_scorecard_report')
     or to_regclass('public.' || v.t) is not null
$fn$;

-- ═══ 9. VERDICT — the probe cleans up after itself (this file carries DDL) and touches only ZZ DEMO ids ═══
select case
  when public.fn_marketing_plan_problems('{"topics":[{"title":"x"}],"formats":["reel"],"music":{},"voiceover":{},"video":{"count":8,"length_s":25},"cadence":{},"budget":{"ad_spend_aed":0}}'::jsonb) <> '{}'::text[]
    then 'PROBE FAILED: a complete organic plan was refused'
  when cardinality(public.fn_marketing_plan_problems('{"topics":[{"title":"x"}],"formats":["reel"],"music":{},"voiceover":{},"video":{"count":8,"length_s":25},"cadence":{},"budget":{"ad_spend_aed":500}}'::jsonb)) = 0
    then 'PROBE FAILED: a plan with ad spend passed'
  when cardinality(public.fn_marketing_plan_problems('{"topics":[{"title":"boost the post to reach more"}],"formats":["reel"],"music":{},"voiceover":{},"video":{"count":8,"length_s":25},"cadence":{},"budget":{"ad_spend_aed":0}}'::jsonb)) = 0
    then 'PROBE FAILED: a plan proposing boosting passed'
  when cardinality(public.fn_marketing_evidence_problems('[{"kind":"market_intel","ref":"-1","point":"x"}]'::jsonb)) = 0
    then 'PROBE FAILED: a citation to a missing row passed'
  when (public.fn_marketing_plan_calendar('2026-09-23 08:00+00')->>'deadline') <> '2026-09-23'
    then 'PROBE FAILED: September''s deadline is not Wed 23 Sep (30 Sep - 7)'
  when (public.fn_marketing_plan_calendar('2026-10-10 08:00+00')->>'deadline') <> '2026-10-23'
    then 'PROBE FAILED: October''s deadline is not Fri 23 Oct (24 Oct is a Saturday)'
  when not exists (select 1 from public.seat_handoff_kind where type = 'deliberation.review' and from_seat = 'marketing' and to_seat = 'ceo')
    then 'PROBE FAILED: the review machine (873) has no marketing -> ceo conversation; apply a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql first'
  else 'PROBE OK' end as verdict;
