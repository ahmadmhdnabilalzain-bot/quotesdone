-- A SEAT IS NEVER REVIEWED BY A MODEL OF ITS OWN FAMILY.
-- it_engineer (routing, tables, guard, monitor) with ceo (the reviewer's independent context).
-- 23 September 2026. founder_instruction 873, verbatim:
--
--   "let's generalize this whenever two agents are talking to each other like the marketing talking
--    with the CEO and the CEO need to discuss it with the marketing or the sales engineer is sharing
--    something with the CEO and the CEO has to give his opinion they shouldn't be on the same model how
--    can we do that so that we make sure that they don't agree unless it's actually right"
--
-- MEASURED BEFORE THIS FILE, read-only against htdblwldjkcgjvmqkbeh, 23 Sep 2026:
--   model_policy: ceo_judgement, ceo_approval_decision, ceo_strategic_planning, marketing_copy and
--   sales_engineer_reasoning ALL route to openai/gpt-5.6-sol with anthropic/claude-opus-5.5 behind it.
--   So today, when marketing proposes and the CEO judges, the same model writes and approves. Nothing in
--   fn_ai_route knows which model wrote the thing being judged, so nothing could have prevented it.
--   public.review_chain (8,766 rows) records author/reviewer AGENTS from the department era; it carries
--   no model, no provider, no blind pass and no steelman, so it cannot hold this rule and is not reused.
--
-- ─── THE FIVE RULES AND WHERE EACH IS ENFORCED ──────────────────────────────────────────────────
--
-- 1. DIFFERENT FAMILIES, IN ROUTING.  fn_ai_route_review(task_class, counterpart_model, ...) asks
--    fn_ai_route for the class (tokens, budget halt, refusals) and then replaces the model with the
--    first HEALTHY member of public.review_pool whose model_registry.provider differs from the author's.
--    The fallback is drawn the same way, so the gateway's ladder cannot fall back into the author's
--    family either. No healthy member of another family => use_llm false, no_independent_reviewer true.
--    It NEVER falls back to the author's family. ai_gateway calls it whenever a request carries
--    counterpart_model, and refuses a seat_deliberation_* class that does not.
--    "Healthy": registered, active, approved, has an llm_route_health row, and its breaker is not
--    TRIPPED (open_until in the future WITH an opened_class). The founder's hold (open_until in the
--    future, opened_class NULL — hold_01_stop_all_openrouter_calls.sql) is a deliberate stop, not ill
--    health: a held reviewer is still the right reviewer, and the step records "held, not run".
--
--    THE DATABASE BACKSTOP: trg_seat_deliberation_turn_guard refuses ANY review turn (blind or
--    compare, recorded or held) whose provider equals the provider of the proposal it reviews. The
--    provider is taken from model_registry, never from the caller.
--
-- 2. BLIND FIRST PASS, IN CODE.  fn_seat_deliberation_blind_payload builds the reviewer's first
--    payload from question + evidence + independent context. It never reads the proposal column into
--    the payload, and it raises BLIND_PASS_LEAK if the proposal's text appears anywhere in what it
--    built (an author who pastes the proposal into the evidence is caught here). The compare payload
--    refuses to build until a RECORDED blind turn exists, and the guard refuses a compare turn with no
--    recorded blind turn before it.
--
-- 3. STEELMAN AGAINST, IN THE GUARD.  Every recorded review turn needs steelman_against as a JSON string
--    of at least six words that is not a placeholder ('none', 'n/a', 'no counter-case' ...); the compare
--    turn's must differ from the blind turn's. An approval without one raises MALFORMED_REVIEW. A compare
--    turn also needs explicit agreements and disagreements.
--    The blind leak test walks every proposal string of >= 24 normalised characters (and strings that are
--    themselves JSON) and refuses the deliberation if one appears in the question or the evidence.
--    The leak test reads the STRING VALUES of the evidence, never its JSON text (escapes hid multi-line copies).
--    KNOWN LIMIT: evidence.key_frames are sent to the reviewer as IMAGES (_shared/seat_deliberation.ts), and an
--    image's content cannot be checked for leaked proposal text. What is enforced instead: only server-produced
--    key frame paths (features/<sha256>/<frame>.jpg|jpeg|png|webp; marketing_asset_feature's list once #876
--    lands), image/* by metadata, <= 1.5 MB, <= 6, checked before any download.
--    The author's model is not taken on trust: the seat's LATEST successful ai_cost_log call on
--    p_author_task_class (mandatory) in the last 24 hours must be on it (only a ZZ DEMO deliberation is
--    exempt, and a demo deliberation never reaches call_model). Provider names compare as lower(btrim()).
--
-- 4. INDEPENDENT INFORMATION, ASSEMBLED BY THE REVIEW STEP.  fn_seat_deliberation_independent_context
--    reads ceo_plan_month (this month and next), fn_ceo_plan_funnel with the drop-off ratios, and the
--    supplier gap by trade from v_supply_gap (the sales engineer's lead pool). It takes no argument
--    from the author; the author cannot supply, filter or omit it.
--
-- 5. AGREEMENT MONITOR, A DETERMINISTIC DUTY.  fn_it_deliberation_independence_items computes, per
--    reviewer x author pair over 30 days, the approval rate and how often the blind verdict equalled
--    the final one. >= 90% approvals over >= 10 reviews raises duty:deliberation_independence:
--    rubber_stamp:<reviewer>:<author> for the CEO, and it_founder_decision_class sends it to the
--    founder's 19:00 report. It never forces disagreement: nothing below 90% is raised, and a high
--    blind-match rate is reported as evidence, not as a fault. The same duty carries every
--    deliberation that ended "no independent reviewer" until it is closed.
--
-- ─── THE INTERFACE, FOR ANY PAIR OF SEATS ───────────────────────────────────────────────────────
--
--   id := fn_seat_deliberation_open(kind, author_seat, reviewer_seat, question, evidence, proposal,
--                                   author_model [, author_task_class, subject_table, subject_id, demo])
--        The author has already written the proposal on author_model. Opening records that as the
--        round-1 proposal turn and starts a 'deliberation.review' handoff (nothing is one-way: the
--        reviewing seat's handler replies, the author closes).
--   fn_seat_deliberation_step(id)      -> {action: call_model|held|escalated|none, ...} deterministic;
--        records "held, not run" or "no independent reviewer" itself. On call_model the runner
--        (_shared/seat_deliberation.ts advanceDeliberation) calls ai_gateway with task_class and
--        counterpart_model and hands the answer to
--   fn_seat_deliberation_record(id, phase, model_used, output [, prompt_tokens, output_tokens, status, why])
--   fn_seat_deliberation_revise(id, proposal, author_model)   -- only after a 'revise', bounded by max_rounds
--   fn_seat_deliberation_close(id, closed_by, outcome)         -- the author seat only
--   A NEW PAIR IS TWO ROWS, added by the build that calls open() for it: ('deliberation.review', <author>,
--   <reviewer>) in seat_handoff_kind and its monthly cap in seat_deliberation_ceiling. open() refuses an
--   unregistered pair; the step holds a pair with no ceiling. Registered here: none. marketing -> ceo
--   (AED 50/month charged to marketing) is added by #876 with its call site.
--
-- ─── COST PER REVIEW, catalogue prices (opus-5.5 USD 4/20, sol 2/10 per Mtok) ───────────────────
--   Estimate: blind ~6,000 in / ~900 out; compare ~8,000 in / ~1,100 out (caps 1,500 and 1,800).
--   Author on sol, reviewer on opus:  0.024+0.018 + 0.032+0.022 = USD 0.096 (AED 0.35); cap USD 0.122.
--   Author on opus, reviewer on sol:  0.012+0.009 + 0.016+0.011 = USD 0.048 (AED 0.18); cap USD 0.061.
--   Sol's hidden reasoning tokens bill at USD 10/Mtok and cannot be measured while the hold stands.
--   Token counts are estimates until ai_cost_log holds a first week of real calls.
--
-- WHAT THIS FILE DOES NOT DO: it does not open the hold, change fn_ai_route, or call a model.
--
--   node scripts/apply_sql.mjs scripts/sql/a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql --apply --ddl
--
-- Idempotent on purpose (if not exists / create or replace / on conflict do nothing): the check
-- scripts/checks/a_seat_is_never_reviewed_by_a_model_of_its_own_family.test.mjs replays this whole file
-- inside an aborted transaction before it is applied. It must therefore carry no begin/commit.

-- ── 1. THE REVIEW POOL ──────────────────────────────────────────────────────────────────────────
create table if not exists public.review_pool (
  model_id text primary key references public.model_registry (model_id),
  rank     integer not null,
  active   boolean not null default true,
  note     text not null check (btrim(note) <> ''),
  added_at timestamptz not null default now()
);
alter table public.review_pool enable row level security;
drop policy if exists review_pool_service_role_only on public.review_pool;
create policy review_pool_service_role_only on public.review_pool as permissive for all to public using (false) with check (false);
revoke all on public.review_pool from anon, authenticated;

insert into public.review_pool (model_id, rank, active, note) values
  ('openai/gpt-5.6-sol', 1, true,
   'Judgement default by the founder''s model ruling (instructions 844/854): every judgement class is on Sol. '
   || 'Reviews an author who wrote on any non-openai model.'),
  ('anthropic/claude-opus-5.5', 2, true,
   'Plan B for every reasoning class (instruction 841) and the only other large-or-above judgement model in the fleet. '
   || 'Reviews every author who wrote on Sol - which today is every CEO, marketing and sales engineer class.'),
  ('google/gemini-3.8-flash', 3, false,
   'Registered as the THIRD FAMILY but NOT in rotation, deliberately. It is a medium-tier row (USD 0.75/3.75) chosen '
   || 'for speech and redaction, not judgement, and fn_ai_route''s own doctrine for reviewer_auditor seats is that '
   || '"a reviewer on the cheap model is a green check that means nothing". A review that passes because the '
   || 'reviewer was weaker is exactly the false agreement instruction 873 forbids, and "no independent reviewer" is '
   || 'the honest answer when both judgement families are down. Set active=true only after a measured judgement '
   || 'comparison on real deliberations shows it disagrees where Sol and Opus disagree.')
on conflict (model_id) do nothing;

-- ── 2. THE TWO REVIEW CLASSES ───────────────────────────────────────────────────────────────────
-- Primary/fallback follow the ruling (judgement -> Sol, Opus behind it). fn_ai_route_review then
-- replaces whichever one shares the author's family, so the class never needs a per-author row.
insert into public.model_policy (task_class, tier, model_primary, model_fallback, max_tokens, rationale, deterministic_alternative, active, cache_ttl_min)
values
  ('seat_deliberation_blind', 'large', 'openai/gpt-5.6-sol', 'anthropic/claude-opus-5.5', 1500,
   'founder_instruction 873: the reviewing seat''s BLIND pass - question, evidence and independent context only, '
   || 'never the proposal. Routed ONLY through fn_ai_route_review, which swaps in the other family from the author''s. '
   || 'Never cached: a review replayed is not a review.', null, true, 0),
  ('seat_deliberation_compare', 'large', 'openai/gpt-5.6-sol', 'anthropic/claude-opus-5.5', 1800,
   'founder_instruction 873: the reviewing seat compares its own blind verdict with the revealed proposal and states '
   || 'agreements, disagreements and the strongest case against. Routed ONLY through fn_ai_route_review. Never cached.',
   null, true, 0)
on conflict (task_class) do nothing;

-- ── 3. THE ROUTER ───────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ai_route_review(p_task_class text, p_counterpart_model text,
  p_agent_key text default null, p_fn text default null, p_dept_key text default null)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fam  text;
  v_base jsonb;
  v_rej  jsonb := '[]'::jsonb;
  v_pick text; v_pick_fam text; v_fb text;
  c record;
begin
  select lower(btrim(r.provider)) into v_fam from public.model_registry r where r.model_id = p_counterpart_model;
  if v_fam is null then
    return jsonb_build_object('use_llm', false, 'no_independent_reviewer', true, 'task_class', p_task_class,
      'author_model', p_counterpart_model,
      'why', 'NO INDEPENDENT REVIEWER: the author''s model ' || coalesce(p_counterpart_model, '(none given)')
             || ' is not in model_registry, so its family is unknown and independence cannot be proved.');
  end if;

  v_base := public.fn_ai_route(p_task_class, p_dept_key, null, p_fn, false, null, p_agent_key);
  if not coalesce((v_base->>'use_llm')::boolean, false) then
    return v_base || jsonb_build_object('author_model', p_counterpart_model, 'author_family', v_fam);
  end if;

  for c in
    select p.model_id, lower(btrim(r.provider)) provider, coalesce(r.active and r.approved, false) reg_ok,
           h.model_id is not null measured,
           coalesce(h.open_until > now() and h.opened_class is not null, false) tripped
      from public.review_pool p
      left join public.model_registry r on r.model_id = p.model_id
      left join public.llm_route_health h on h.model_id = p.model_id
      left join public.model_policy pol on pol.task_class = v_base->>'task_class'
     where p.active
     order by (p.model_id = pol.model_primary) desc nulls last, (p.model_id = pol.model_fallback) desc nulls last, p.rank
  loop
    if c.provider is null then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'not in model_registry');
    elsif c.provider = v_fam then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'same family as the author (' || v_fam || ')');
    elsif not c.reg_ok then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'inactive or unapproved in model_registry');
    elsif not c.measured then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'no llm_route_health row: unmeasured is not healthy');
    elsif c.tripped then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'breaker tripped by real failures');
    elsif v_pick is null then
      v_pick := c.model_id; v_pick_fam := c.provider;
    elsif v_fb is null then
      v_fb := c.model_id;
    end if;
  end loop;

  if v_pick is null then
    return jsonb_build_object('use_llm', false, 'no_independent_reviewer', true,
      'task_class', v_base->>'task_class', 'author_model', p_counterpart_model, 'author_family', v_fam,
      'pool_rejected', v_rej,
      'why', 'NO INDEPENDENT REVIEWER: no active, healthy review_pool model outside the ' || v_fam
             || ' family. The review does not fall back to the author''s family (founder_instruction 873).');
  end if;

  return v_base || jsonb_build_object(
    'model', v_pick, 'fallback', v_fb,
    'in_per_mtok_usd', (select in_per_mtok_usd from public.model_registry where model_id = v_pick),
    'out_per_mtok_usd', (select out_per_mtok_usd from public.model_registry where model_id = v_pick),
    'reviewer_family', v_pick_fam, 'author_model', p_counterpart_model, 'author_family', v_fam,
    'independent', true, 'pool_rejected', v_rej,
    'why', coalesce(v_base->>'why', '') || ' | INDEPENDENT REVIEW: author wrote on ' || p_counterpart_model
           || ' (' || v_fam || '), reviewer routed to ' || v_pick || ' (' || v_pick_fam || ')'
           || coalesce(', fallback ' || v_fb, ', no fallback outside ' || v_fam));
end $fn$;
revoke execute on function public.fn_ai_route_review(text, text, text, text, text) from public, anon, authenticated;

-- ── 4. THE DELIBERATION AND ITS TURNS ───────────────────────────────────────────────────────────
create table if not exists public.seat_deliberation (
  id              bigint generated always as identity primary key,
  kind            text not null check (kind ~ '^[a-z_]+(\.[a-z_]+)*$'),
  author_seat     text not null,
  reviewer_seat   text not null,
  question        text not null check (btrim(question) <> ''),
  evidence        jsonb not null check (jsonb_typeof(evidence) = 'object' and length(evidence::text) <= 60000),
  proposal        jsonb not null check (jsonb_typeof(proposal) = 'object' and proposal <> '{}'::jsonb and length(proposal::text) <= 30000),
  author_model    text not null,
  author_provider text not null,
  max_rounds      integer not null default 2 check (max_rounds between 1 and 3),
  round           integer not null default 1 check (round >= 1),
  status          text not null default 'open' check (status in ('open', 'reviewed', 'no_independent_reviewer', 'closed')),
  outcome         text,
  subject_table   text,
  subject_id      text,
  handoff_id      bigint,
  demo            boolean not null default false,
  opened_at       timestamptz not null default now(),
  closed_at       timestamptz,
  check (author_seat <> reviewer_seat),
  check (round <= max_rounds)
);
alter table public.seat_deliberation enable row level security;
drop policy if exists seat_deliberation_service_role_only on public.seat_deliberation;
create policy seat_deliberation_service_role_only on public.seat_deliberation as permissive for all to public using (false) with check (false);
revoke all on public.seat_deliberation from anon, authenticated;

create table if not exists public.seat_deliberation_turn (
  id               bigint generated always as identity primary key,
  deliberation_id  bigint not null references public.seat_deliberation (id) on delete cascade,
  round            integer not null check (round >= 1),
  phase            text not null check (phase in ('proposal', 'blind', 'compare')),
  seat             text not null,
  status           text not null check (status in ('recorded', 'held_not_run', 'no_independent_reviewer', 'failed')),
  task_class       text,
  model            text,
  provider         text,
  reviews_turn_id  bigint references public.seat_deliberation_turn (id),
  verdict          text check (verdict in ('approve', 'reject', 'revise')),
  steelman_against text,
  agreements       text,
  disagreements    text,
  output           jsonb not null default '{}'::jsonb,
  payload_sha256   text,
  why              text,
  prompt_tokens    integer,
  output_tokens    integer,
  created_at       timestamptz not null default now()
);
create unique index if not exists seat_deliberation_turn_one_recorded
  on public.seat_deliberation_turn (deliberation_id, round, phase) where status = 'recorded';
create unique index if not exists seat_deliberation_turn_one_waiting
  on public.seat_deliberation_turn (deliberation_id, round, phase) where status in ('held_not_run', 'no_independent_reviewer');
create index if not exists seat_deliberation_turn_by_deliberation on public.seat_deliberation_turn (deliberation_id);
alter table public.seat_deliberation_turn enable row level security;
drop policy if exists seat_deliberation_turn_service_role_only on public.seat_deliberation_turn;
create policy seat_deliberation_turn_service_role_only on public.seat_deliberation_turn as permissive for all to public using (false) with check (false);
revoke all on public.seat_deliberation_turn from anon, authenticated;

-- The author's family is read from the registry, never taken from the caller; both seats must be live.
create or replace function public.trg_seat_deliberation_guard()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if tg_op = 'INSERT' or new.author_model is distinct from old.author_model then
    select lower(btrim(r.provider)) into new.author_provider from public.model_registry r where r.model_id = new.author_model;
    if new.author_provider is null then
      raise exception 'seat_deliberation: author model % is not in model_registry; its family cannot be known', new.author_model;
    end if;
  end if;
  if tg_op = 'INSERT' then
    if not exists (select 1 from public.org_agents a where a.agent_key = new.author_seat and a.active)
       or not exists (select 1 from public.org_agents a where a.agent_key = new.reviewer_seat and a.active) then
      raise exception 'seat_deliberation: % and % must both be active seats', new.author_seat, new.reviewer_seat;
    end if;
  end if;
  return new;
end $fn$;
revoke execute on function public.trg_seat_deliberation_guard() from public, anon, authenticated;
drop trigger if exists trg_seat_deliberation_guard on public.seat_deliberation;
create trigger trg_seat_deliberation_guard before insert or update on public.seat_deliberation
  for each row execute function public.trg_seat_deliberation_guard();

-- Text reduced to comparable words: lower case, every run of punctuation, quotes, escapes or space one space.
-- JSON-escaped and plain copies of the same sentence normalise to the same words. The Arabic block is written as
-- regex escapes (U+0600..U+06FF), so the file carries no Arabic characters that are not a message.
create or replace function public.fn_seat_deliberation_norm(p text)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select btrim(regexp_replace(lower(coalesce(p, '')), '[^a-z0-9\u0600-\u06ff]+', ' ', 'g'))
$fn$;
revoke execute on function public.fn_seat_deliberation_norm(text) from public, anon, authenticated;

-- THE BLIND LEAK TEST. Every string in the proposal (and inside any string that is itself JSON) of at least
-- 24 normalised characters is looked for in the normalised haystack. Returns the first fragment found, or null.
-- ponytail: 24 characters is the floor; a proposal made only of short strings is not protected below it.
-- The haystack is the STRING VALUES of a document, never its JSON text: in JSON text a newline is the two
-- characters backslash-n, which normalise to a stray 'n' and hide a multi-line copy (review of #877).
create or replace function public.fn_seat_deliberation_strings(p jsonb)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(string_agg(x #>> '{}', ' '), '') from jsonb_path_query(coalesce(p, 'null'::jsonb), 'strict $.**') x
   where jsonb_typeof(x) = 'string'
$fn$;
revoke execute on function public.fn_seat_deliberation_strings(jsonb) from public, anon, authenticated;

create or replace function public.fn_seat_deliberation_proposal_leak(p_proposal jsonb, p_haystack text)
returns text language plpgsql immutable set search_path to 'public', 'pg_temp' as $fn$
declare v_hay text := ' ' || public.fn_seat_deliberation_norm(p_haystack) || ' '; s text; n text; j jsonb; v text;
begin
  for s in select x #>> '{}' from jsonb_path_query(coalesce(p_proposal, 'null'::jsonb), 'strict $.**') x
            where jsonb_typeof(x) = 'string' loop
    n := public.fn_seat_deliberation_norm(s);
    if length(n) >= 24 and strpos(v_hay, ' ' || n || ' ') > 0 then return left(n, 80); end if;
    if btrim(s) ~ '^[\[{"]' then
      begin j := s::jsonb; exception when others then j := null; end;
      if j is not null then
        v := public.fn_seat_deliberation_proposal_leak(j, p_haystack);
        if v is not null then return v; end if;
      end if;
    end if;
  end loop;
  return null;
end $fn$;
revoke execute on function public.fn_seat_deliberation_proposal_leak(jsonb, text) from public, anon, authenticated;

-- THE GUARD. Append-only; provider from the registry; a review turn is never the author's family;
-- blind before compare; every recorded review states the strongest case against.
create or replace function public.trg_seat_deliberation_turn_guard()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  d public.seat_deliberation;
  v_prov text; v_auth_prov text; v_auth_model text; v_steel text;
begin
  if tg_op = 'UPDATE' then
    raise exception 'seat_deliberation_turn % is append-only: record a new turn instead', old.id;
  end if;
  select * into d from public.seat_deliberation where id = new.deliberation_id;

  if new.model is not null then
    select lower(btrim(r.provider)) into v_prov from public.model_registry r where r.model_id = new.model;
    if v_prov is null then
      raise exception 'seat_deliberation_turn: model % is not in model_registry', new.model;
    end if;
    if new.provider is not null and lower(btrim(new.provider)) <> v_prov then
      raise exception 'seat_deliberation_turn: provider % does not match model_registry (% is %)', new.provider, new.model, v_prov;
    end if;
    new.provider := v_prov;
  end if;

  if new.phase = 'proposal' then
    if new.seat <> d.author_seat or new.model is null or new.status <> 'recorded' then
      raise exception 'seat_deliberation_turn: a proposal is a recorded turn by the author seat % on a named model', d.author_seat;
    end if;
    return new;
  end if;

  if new.seat <> d.reviewer_seat then
    raise exception 'seat_deliberation_turn: a % turn belongs to the reviewer seat %, not %', new.phase, d.reviewer_seat, new.seat;
  end if;
  if new.reviews_turn_id is null then
    select t.id into new.reviews_turn_id from public.seat_deliberation_turn t
     where t.deliberation_id = new.deliberation_id and t.phase = 'proposal' and t.status = 'recorded' and t.round <= new.round
     order by t.round desc, t.id desc limit 1;
  end if;
  select lower(btrim(t.provider)), t.model into v_auth_prov, v_auth_model from public.seat_deliberation_turn t
   where t.id = new.reviews_turn_id and t.deliberation_id = new.deliberation_id and t.phase = 'proposal';
  if v_auth_prov is null then
    raise exception 'seat_deliberation_turn: a % turn must review a recorded proposal of the same deliberation', new.phase;
  end if;

  if new.provider = v_auth_prov then
    raise exception using errcode = 'check_violation',
      message = 'SAME_FAMILY_REVIEW: ' || new.model || ' (' || new.provider || ') may not review a proposal written on '
                || v_auth_model || ' (' || v_auth_prov || '). founder_instruction 873: the reviewer comes from another family.';
  end if;

  if new.status = 'recorded' then
    if new.model is null or new.verdict is null then
      raise exception 'MALFORMED_REVIEW: a recorded % turn names its model and its verdict', new.phase;
    end if;
    -- A steelman is a sentence of at least six words that is not a placeholder, and the comparison's is not
    -- the blind pass's copied forward. fn_seat_deliberation_record passes a steelman only when it is a JSON string.
    v_steel := public.fn_seat_deliberation_norm(new.steelman_against);
    if coalesce(array_length(regexp_split_to_array(nullif(v_steel, ''), ' '), 1), 0) < 6
       or v_steel ~ '^(none|n a|na|nil|nothing|tbd|not applicable|no (real |strong |serious |obvious )?(counter ?case|case against|counter ?argument|objection|concern|argument|risk|downside)s?|there (is|are) (nothing|no (counter ?case|case|objection|argument|risk|downside)s?))( |$)' then
      raise exception using errcode = 'check_violation',
        message = case when new.verdict = 'approve'
                       then 'MALFORMED_REVIEW: an approval without the strongest case against the proposal is malformed and is rejected'
                       else 'MALFORMED_REVIEW: every review turn states the strongest case against the proposal' end
                  || ' (at least six words, not a placeholder)';
    end if;
    if new.phase = 'compare' and exists (select 1 from public.seat_deliberation_turn b where b.deliberation_id = new.deliberation_id
          and b.phase = 'blind' and b.status = 'recorded' and public.fn_seat_deliberation_norm(b.steelman_against) = v_steel) then
      raise exception using errcode = 'check_violation',
        message = 'MALFORMED_REVIEW: the comparison''s steelman repeats the blind one; argue against the proposal now revealed';
    end if;
    if new.phase = 'compare' then
      if not exists (select 1 from public.seat_deliberation_turn b where b.deliberation_id = new.deliberation_id
                        and b.phase = 'blind' and b.status = 'recorded' and b.round <= new.round) then
        raise exception 'BLIND_FIRST: the reviewer compares only after its own blind verdict is recorded';
      end if;
      if coalesce(btrim(new.agreements), '') = '' or coalesce(btrim(new.disagreements), '') = '' then
        raise exception 'MALFORMED_REVIEW: a comparison states its agreements and its disagreements explicitly (write "none" if there are none)';
      end if;
    end if;
  end if;
  return new;
end $fn$;
revoke execute on function public.trg_seat_deliberation_turn_guard() from public, anon, authenticated;
drop trigger if exists trg_seat_deliberation_turn_guard on public.seat_deliberation_turn;
create trigger trg_seat_deliberation_turn_guard before insert or update on public.seat_deliberation_turn
  for each row execute function public.trg_seat_deliberation_turn_guard();

-- ── 5. WHAT THE REVIEWER KNOWS THAT THE AUTHOR DID NOT SUPPLY (ceo) ────────────────────────────
-- ponytail: every reviewer seat gets the same company picture; give a seat its own when one needs it.
create or replace function public.fn_seat_deliberation_independent_context(p_reviewer_seat text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_m0 date := date_trunc('month', now() at time zone 'Asia/Dubai')::date;
  v_f jsonb := public.fn_ceo_plan_funnel();
  v_mtd jsonb := v_f->'month_to_date';
  r numeric;
begin
  return jsonb_build_object(
    'assembled_by', 'fn_seat_deliberation_independent_context for the reviewing seat ' || p_reviewer_seat
                    || '; the author did not supply, filter or see this',
    'assembled_at', now(),
    'plan_targets', (select coalesce(jsonb_agg(to_jsonb(p) - 'updated_at' order by p.month), '[]'::jsonb)
                       from public.ceo_plan_month p where p.month in (v_m0, (v_m0 + interval '1 month')::date)),
    'funnel', v_f,
    'funnel_drop_offs', jsonb_build_object(
      'registered_per_invite',   round((v_mtd->>'registrations_submitted')::numeric / nullif((v_mtd->>'invitations_delivered')::numeric, 0), 4),
      'verified_per_registered', round((v_mtd->>'registrations_verified')::numeric  / nullif((v_mtd->>'registrations_submitted')::numeric, 0), 4),
      'reveals_per_inquiry',     round((v_mtd->>'reveals_paid')::numeric            / nullif((v_mtd->>'inquiries_posted')::numeric, 0), 4),
      'note', 'month to date; null where the denominator is zero'),
    'supplier_gap_by_trade', (select coalesce(jsonb_agg(to_jsonb(g) order by g.gap_to_target desc, g.sendable_shortfall desc), '[]'::jsonb)
                                from (select slug, name, approved, gap_to_target, sendable, invited, sendable_shortfall, status
                                        from public.v_supply_gap where status <> 'TARGET MET'
                                       order by gap_to_target desc, sendable_shortfall desc limit 12) g),
    'supplier_gap_totals', (select jsonb_build_object('trades', count(*),
                                     'target_met', count(*) filter (where status = 'TARGET MET'),
                                     'no_pool', count(*) filter (where status like 'NO POOL%'),
                                     'pool_too_thin', count(*) filter (where status like 'POOL TOO THIN%'))
                              from public.v_supply_gap));
end $fn$;
revoke execute on function public.fn_seat_deliberation_independent_context(text) from public, anon, authenticated;

-- ── 6. THE TWO PAYLOADS ────────────────────────────────────────────────────────────────────────
create or replace function public.fn_seat_deliberation_blind_payload(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare d public.seat_deliberation; v jsonb;
begin
  select * into d from public.seat_deliberation where id = p_id;
  if not found then raise exception 'no seat_deliberation %', p_id; end if;
  -- Built from named columns only. The proposal column is read below solely to prove it is absent.
  v := jsonb_build_object(
    'phase', 'blind', 'deliberation_id', d.id, 'kind', d.kind,
    'author_seat', d.author_seat, 'reviewer_seat', d.reviewer_seat,
    'question', d.question, 'evidence', d.evidence,
    'independent_context', public.fn_seat_deliberation_independent_context(d.reviewer_seat),
    'instructions', 'You are the ' || d.reviewer_seat || ' seat. You have NOT seen what the ' || d.author_seat
      || ' seat proposes, on purpose. Answer the question from the evidence and the independent context alone. '
      || 'verdict: approve = proceed as the question asks; reject = do not; revise = proceed only with changes you name. '
      || 'Give the strongest case AGAINST your own verdict in steelman_against, even if you approve. Agree only if it is right.',
    'output_contract', jsonb_build_object('verdict', 'approve|reject|revise', 'recommendation', 'text',
      'reasoning', 'text', 'steelman_against', 'text, at least one full sentence'));
  if v ? 'proposal' or public.fn_seat_deliberation_proposal_leak(d.proposal, public.fn_seat_deliberation_strings(v)) is not null then
    raise exception 'BLIND_PASS_LEAK: the blind payload for deliberation % carries the proposal (was it pasted into the question or the evidence?)', p_id;
  end if;
  return v;
end $fn$;
revoke execute on function public.fn_seat_deliberation_blind_payload(bigint) from public, anon, authenticated;

create or replace function public.fn_seat_deliberation_compare_payload(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare d public.seat_deliberation; b public.seat_deliberation_turn;
begin
  select * into d from public.seat_deliberation where id = p_id;
  if not found then raise exception 'no seat_deliberation %', p_id; end if;
  select * into b from public.seat_deliberation_turn t
   where t.deliberation_id = p_id and t.phase = 'blind' and t.status = 'recorded' order by t.round desc limit 1;
  if not found then
    raise exception 'BLIND_FIRST: deliberation % has no recorded blind verdict; the proposal is not revealed before it', p_id;
  end if;
  return jsonb_build_object(
    'phase', 'compare', 'deliberation_id', d.id, 'kind', d.kind, 'round', d.round,
    'author_seat', d.author_seat, 'reviewer_seat', d.reviewer_seat,
    'question', d.question, 'evidence', d.evidence,
    'independent_context', public.fn_seat_deliberation_independent_context(d.reviewer_seat),
    'your_blind_verdict', jsonb_build_object('verdict', b.verdict, 'steelman_against', b.steelman_against, 'output', b.output),
    'proposal', d.proposal,
    'instructions', 'The ' || d.author_seat || ' seat''s proposal is now revealed. Compare it with YOUR blind verdict above. '
      || 'State explicitly what you agree with and what you do not (write "none" if there is nothing). Give the strongest '
      || 'case AGAINST the proposal even if you approve; an approval without it is rejected as malformed. Do not agree '
      || 'because the proposal is confident, and do not disagree for its own sake.',
    'output_contract', jsonb_build_object('verdict', 'approve|reject|revise', 'agreements', 'text', 'disagreements', 'text',
      'steelman_against', 'text, at least one full sentence', 'reasoning', 'text',
      'changed_from_blind_because', 'text, or "unchanged"'));
end $fn$;
revoke execute on function public.fn_seat_deliberation_compare_payload(bigint) from public, anon, authenticated;

-- ── 7. OPEN, STEP, RECORD, REVISE, CLOSE ───────────────────────────────────────────────────────
create or replace function public.fn_seat_deliberation_open(p_kind text, p_author_seat text, p_reviewer_seat text,
  p_question text, p_evidence jsonb, p_proposal jsonb, p_author_model text, p_author_task_class text default null,
  p_subject_table text default null, p_subject_id text default null, p_demo boolean default false)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint; v_h bigint; v_leak text; v_last text;
begin
  if not exists (select 1 from public.seat_handoff_kind k
                  where k.type = 'deliberation.review' and k.from_seat = p_author_seat and k.to_seat = p_reviewer_seat) then
    raise exception 'no deliberation.review conversation from % to % in seat_handoff_kind: register the pair in the file of the build that starts it',
      p_author_seat, p_reviewer_seat;
  end if;
  v_leak := public.fn_seat_deliberation_proposal_leak(p_proposal, coalesce(p_question, '') || ' ' || public.fn_seat_deliberation_strings(p_evidence));
  if v_leak is not null then
    raise exception 'BLIND_PASS_LEAK: the question or the evidence carries the proposal ("%"); the reviewer would not be blind', v_leak;
  end if;
  -- THE AUTHOR'S MODEL IS A MEASUREMENT, NOT A CLAIM: ai_gateway logged a call by this seat on this model in the
  -- last 24 hours, or the family the reviewer must avoid is unproven. Only a ZZ DEMO deliberation is exempt.
  -- The seat's LATEST successful call on the class that wrote the proposal must be on p_author_model.
  if not (coalesce(p_demo, false) and p_question like 'ZZ DEMO%') then
    if coalesce(btrim(p_author_task_class), '') = '' then
      raise exception 'AUTHOR_MODEL_UNPROVEN: name the task class the proposal was written on (p_author_task_class)';
    end if;
    select l.model_used into v_last from public.ai_cost_log l
     where l.ok and l.task_class = p_author_task_class and l.occurred_at > now() - interval '24 hours'
       and (l.agent_key = p_author_seat or l.seat = p_author_seat)
     order by l.occurred_at desc, l.id desc limit 1;
    if v_last is distinct from p_author_model then
      raise exception 'AUTHOR_MODEL_UNPROVEN: the latest successful % call by % in the last 24 hours was on %, not %',
        p_author_task_class, p_author_seat, coalesce(v_last, 'nothing'), p_author_model;
    end if;
  end if;
  insert into public.seat_deliberation (kind, author_seat, reviewer_seat, question, evidence, proposal, author_model,
                                        author_provider, subject_table, subject_id, demo)
  values (p_kind, p_author_seat, p_reviewer_seat, p_question, p_evidence, p_proposal, p_author_model, '?',
          p_subject_table, p_subject_id, coalesce(p_demo, false))
  returning id into v_id;
  insert into public.seat_deliberation_turn (deliberation_id, round, phase, seat, status, task_class, model, output)
  values (v_id, 1, 'proposal', p_author_seat, 'recorded', p_author_task_class, p_author_model, p_proposal);

  v_h := public.fn_seat_handoff(p_author_seat, p_reviewer_seat, 'deliberation.review', 'seat_deliberation', v_id::text,
           jsonb_build_object('deliberation_id', v_id, 'kind', p_kind, 'demo', coalesce(p_demo, false),
                              'question', left(p_question, 300)));
  update public.seat_deliberation set handoff_id = v_h where id = v_id;
  return v_id;
end $fn$;
revoke execute on function public.fn_seat_deliberation_open(text, text, text, text, jsonb, jsonb, text, text, text, text, boolean) from public, anon, authenticated;

-- WHAT A PAIR MAY SPEND ON ITS REVIEWS, and the department that pays. One row per registered pair; a pair with no
-- row is held (fail closed). marketing -> ceo: AED 50 a month charged to marketing, the founder's approval of
-- 23 Sep 2026 (opus-5.5 for the CEO's review of marketing, the same cap #876's fn_marketing_class_ceiling holds
-- for its own ceo_marketing_review class). Spend is what ai_gateway logged through fn_llm_log into ai_cost_log.
create table if not exists public.seat_deliberation_ceiling (
  author_seat   text not null,
  reviewer_seat text not null,
  dept_key      text not null,
  cap_aed_month numeric not null check (cap_aed_month >= 0),
  note          text not null check (btrim(note) <> ''),
  primary key (author_seat, reviewer_seat)
);
alter table public.seat_deliberation_ceiling enable row level security;
drop policy if exists seat_deliberation_ceiling_service_role_only on public.seat_deliberation_ceiling;
create policy seat_deliberation_ceiling_service_role_only on public.seat_deliberation_ceiling as permissive for all to public using (false) with check (false);
revoke all on public.seat_deliberation_ceiling from anon, authenticated;
-- No rows here: the build that opens a pair adds its row (marketing -> ceo: #876, AED 50/month, marketing).

create or replace function public.fn_seat_deliberation_budget(p_author_seat text, p_reviewer_seat text, p_at timestamptz default now())
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select case when c.author_seat is null
    then jsonb_build_object('ok', false, 'dept', null, 'why', 'no seat_deliberation_ceiling row for ' || p_author_seat || ' -> ' || p_reviewer_seat)
    else jsonb_build_object('ok', s.spent < c.cap_aed_month, 'dept', c.dept_key, 'cap_aed', c.cap_aed_month, 'spent_aed', s.spent,
                            'why', 'reviews ' || p_author_seat || ' -> ' || p_reviewer_seat || ' spent AED ' || s.spent || ' of '
                                   || c.cap_aed_month || ' this month (' || c.dept_key || ')') end
    from (select 1) one
    left join public.seat_deliberation_ceiling c on c.author_seat = p_author_seat and c.reviewer_seat = p_reviewer_seat
    left join lateral (select coalesce(sum(l.cost_aed), 0) spent from public.ai_cost_log l
                        where l.task_class in ('seat_deliberation_blind', 'seat_deliberation_compare')
                          and l.dept_key = c.dept_key and l.agent_key = p_reviewer_seat
                          and l.occurred_at >= (date_trunc('month', p_at at time zone 'Asia/Dubai') at time zone 'Asia/Dubai')) s on true
$fn$;
revoke execute on function public.fn_seat_deliberation_budget(text, text, timestamptz) from public, anon, authenticated;

create or replace function public.fn_seat_deliberation_step(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  d public.seat_deliberation; a public.seat_deliberation_turn;
  v_phase text; v_class text; v_route jsonb; v_gate jsonb; v_payload jsonb; v_sha text; v_budget jsonb;
begin
  select * into d from public.seat_deliberation where id = p_id for update;
  if not found then raise exception 'no seat_deliberation %', p_id; end if;
  if d.status <> 'open' then return jsonb_build_object('action', 'none', 'status', d.status); end if;

  if not exists (select 1 from public.seat_deliberation_turn t where t.deliberation_id = p_id and t.phase = 'blind' and t.status = 'recorded') then
    v_phase := 'blind';
  elsif not exists (select 1 from public.seat_deliberation_turn t where t.deliberation_id = p_id and t.phase = 'compare'
                       and t.status = 'recorded' and t.round = d.round) then
    v_phase := 'compare';
  else
    return jsonb_build_object('action', 'none', 'status', d.status, 'why', 'round ' || d.round || ' is already compared');
  end if;
  v_class := 'seat_deliberation_' || v_phase;

  select * into a from public.seat_deliberation_turn t
   where t.deliberation_id = p_id and t.phase = 'proposal' and t.status = 'recorded' and t.round <= d.round
   order by t.round desc, t.id desc limit 1;

  -- THE PAIR'S CEILING comes first: a spent ceiling is held exactly like the founder's hold, before any routing.
  v_budget := public.fn_seat_deliberation_budget(d.author_seat, d.reviewer_seat);
  if not coalesce((v_budget->>'ok')::boolean, false) then
    insert into public.seat_deliberation_turn (deliberation_id, round, phase, seat, status, task_class, reviews_turn_id, why)
    values (p_id, d.round, v_phase, d.reviewer_seat, 'held_not_run', v_class, a.id, 'held, not run: pair_ceiling - ' || (v_budget->>'why'))
    on conflict (deliberation_id, round, phase) where status in ('held_not_run', 'no_independent_reviewer') do nothing;
    return jsonb_build_object('action', 'held', 'phase', v_phase, 'why', v_budget->>'why');
  end if;
  v_route := public.fn_ai_route_review(v_class, a.model, d.reviewer_seat, 'seat_deliberation', v_budget->>'dept');

  if coalesce((v_route->>'no_independent_reviewer')::boolean, false) then
    insert into public.seat_deliberation_turn (deliberation_id, round, phase, seat, status, task_class, reviews_turn_id, why)
    values (p_id, d.round, v_phase, d.reviewer_seat, 'no_independent_reviewer', v_class, a.id, v_route->>'why')
    on conflict (deliberation_id, round, phase) where status in ('held_not_run', 'no_independent_reviewer') do nothing;
    update public.seat_deliberation set status = 'no_independent_reviewer' where id = p_id;
    -- ESCALATE: the monitor duty carries it to the CEO and, through it_founder_decision_class, the founder.
    perform public.fn_it_deliberation_independence_watch(d.demo);
    return jsonb_build_object('action', 'escalated', 'phase', v_phase, 'why', v_route->>'why', 'route', v_route);
  end if;

  if not coalesce((v_route->>'use_llm')::boolean, false) then
    insert into public.seat_deliberation_turn (deliberation_id, round, phase, seat, status, task_class, reviews_turn_id, why)
    values (p_id, d.round, v_phase, d.reviewer_seat, 'held_not_run', v_class, a.id, 'held, not run: ' || coalesce(v_route->>'why', 'the router refused'))
    on conflict (deliberation_id, round, phase) where status in ('held_not_run', 'no_independent_reviewer') do nothing;
    return jsonb_build_object('action', 'held', 'phase', v_phase, 'why', v_route->>'why');
  end if;

  v_payload := case v_phase when 'blind' then public.fn_seat_deliberation_blind_payload(p_id)
                            else public.fn_seat_deliberation_compare_payload(p_id) end;
  v_sha := encode(sha256(convert_to(v_payload::text, 'UTF8')), 'hex');

  v_gate := public.fn_kernel_paid_provider_gate(v_route->>'model');
  if not coalesce((v_gate->>'allowed')::boolean, false) then
    insert into public.seat_deliberation_turn (deliberation_id, round, phase, seat, status, task_class, model, reviews_turn_id, payload_sha256, why)
    values (p_id, d.round, v_phase, d.reviewer_seat, 'held_not_run', v_class, v_route->>'model', a.id, v_sha,
            'held, not run: ' || coalesce(v_gate->>'rule', '?') || ' - ' || coalesce(v_gate->>'reason', ''))
    on conflict (deliberation_id, round, phase) where status in ('held_not_run', 'no_independent_reviewer') do nothing;
    return jsonb_build_object('action', 'held', 'phase', v_phase, 'model', v_route->>'model', 'why', v_gate->>'reason');
  end if;

  -- A DEMO DELIBERATION NEVER REACHES A PAID MODEL, hold or no hold.
  if d.demo then
    insert into public.seat_deliberation_turn (deliberation_id, round, phase, seat, status, task_class, model, reviews_turn_id, payload_sha256, why)
    values (p_id, d.round, v_phase, d.reviewer_seat, 'held_not_run', v_class, v_route->>'model', a.id, v_sha, 'held, not run: demo deliberation')
    on conflict (deliberation_id, round, phase) where status in ('held_not_run', 'no_independent_reviewer') do nothing;
    return jsonb_build_object('action', 'held', 'phase', v_phase, 'why', 'demo deliberation');
  end if;
  return jsonb_build_object('action', 'call_model', 'deliberation_id', p_id, 'phase', v_phase, 'round', d.round,
    'task_class', v_class, 'model', v_route->>'model', 'fallback', v_route->>'fallback',
    'counterpart_model', a.model, 'max_tokens', (v_route->>'max_tokens')::int,
    'reviewer_seat', d.reviewer_seat, 'dept', v_budget->>'dept', 'budget', v_budget,
    'payload', v_payload, 'payload_sha256', v_sha,
    'system', 'You are the ' || d.reviewer_seat || ' seat of Quotes Done reviewing work from the ' || d.author_seat
              || ' seat. Reply with ONE JSON object matching output_contract and nothing else.');
end $fn$;
revoke execute on function public.fn_seat_deliberation_step(bigint) from public, anon, authenticated;

create or replace function public.fn_seat_deliberation_record(p_id bigint, p_phase text, p_model text, p_output jsonb,
  p_prompt_tokens integer default null, p_output_tokens integer default null, p_status text default 'recorded', p_why text default null)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare d public.seat_deliberation; v_id bigint; o jsonb := coalesce(p_output, '{}'::jsonb);
begin
  select * into d from public.seat_deliberation where id = p_id for update;
  if not found then raise exception 'no seat_deliberation %', p_id; end if;
  if d.status <> 'open' then raise exception 'seat_deliberation % is %, not open', p_id, d.status; end if;
  if p_phase not in ('blind', 'compare') then raise exception 'only the reviewer''s blind and compare turns are recorded here'; end if;
  -- A gateway that held the call after the step did not: "held, not run" is recorded once per round and phase.
  if p_status = 'held_not_run' then
    select t.id into v_id from public.seat_deliberation_turn t where t.deliberation_id = p_id and t.round = d.round
       and t.phase = p_phase and t.status = 'held_not_run';
    if v_id is not null then return v_id; end if;
  end if;

  insert into public.seat_deliberation_turn (deliberation_id, round, phase, seat, status, task_class, model, verdict,
    steelman_against, agreements, disagreements, output, why, prompt_tokens, output_tokens, payload_sha256)
  values (p_id, d.round, p_phase, d.reviewer_seat, p_status, 'seat_deliberation_' || p_phase, p_model,
          case when p_status = 'recorded' then lower(o->>'verdict') end,
          case when jsonb_typeof(o->'steelman_against') = 'string' then o->>'steelman_against' end, o->>'agreements', o->>'disagreements', o, p_why, p_prompt_tokens, p_output_tokens,
          o->>'_payload_sha256')
  returning id into v_id;

  if p_status = 'recorded' and p_phase = 'compare' then
    update public.seat_deliberation set status = 'reviewed' where id = p_id;
    update public.agent_actions
       set evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('deliberation_id', p_id, 'round', d.round,
                        'verdict', lower(o->>'verdict'), 'compare_turn_id', v_id, 'reviewed_at', now()),
           detail = detail || jsonb_build_object('awaiting', d.author_seat || ' closes the deliberation')
     where id = d.handoff_id and kind = 'handoff';
    perform public.fn_seat_handoff_event(d.handoff_id, 'reviewed');
  end if;
  return v_id;
end $fn$;
revoke execute on function public.fn_seat_deliberation_record(bigint, text, text, jsonb, integer, integer, text, text) from public, anon, authenticated;

create or replace function public.fn_seat_deliberation_revise(p_id bigint, p_proposal jsonb, p_author_model text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare d public.seat_deliberation; v_last text;
begin
  select * into d from public.seat_deliberation where id = p_id for update;
  if not found then raise exception 'no seat_deliberation %', p_id; end if;
  select t.verdict into v_last from public.seat_deliberation_turn t
   where t.deliberation_id = p_id and t.phase = 'compare' and t.status = 'recorded' and t.round = d.round;
  if d.status <> 'reviewed' or v_last is distinct from 'revise' then
    raise exception 'deliberation % can be revised only after the reviewer asked for a revision', p_id;
  end if;
  if d.round >= d.max_rounds then
    raise exception 'deliberation % is at its last round (%); the author closes it with the reviewer''s verdict', p_id, d.max_rounds;
  end if;
  update public.seat_deliberation set round = round + 1, proposal = p_proposal, status = 'open' where id = p_id;
  insert into public.seat_deliberation_turn (deliberation_id, round, phase, seat, status, model, output)
  values (p_id, d.round + 1, 'proposal', d.author_seat, 'recorded', p_author_model, p_proposal);
  return public.fn_seat_deliberation_step(p_id);
end $fn$;
revoke execute on function public.fn_seat_deliberation_revise(bigint, jsonb, text) from public, anon, authenticated;

create or replace function public.fn_seat_deliberation_close(p_id bigint, p_closed_by text, p_outcome text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare d public.seat_deliberation; c public.seat_deliberation_turn;
begin
  select * into d from public.seat_deliberation where id = p_id for update;
  if not found then raise exception 'no seat_deliberation %', p_id; end if;
  if p_closed_by is distinct from d.author_seat then
    raise exception 'only the originating seat % closes deliberation %', d.author_seat, p_id;
  end if;
  if d.status not in ('reviewed', 'no_independent_reviewer') or coalesce(btrim(p_outcome), '') = '' then
    raise exception 'deliberation % closes after the review (or its escalation), with an outcome', p_id;
  end if;
  select * into c from public.seat_deliberation_turn t
   where t.deliberation_id = p_id and t.phase = 'compare' and t.status = 'recorded' order by t.round desc limit 1;
  update public.seat_deliberation set status = 'closed', outcome = p_outcome, closed_at = now() where id = p_id;
  if d.handoff_id is not null then
    -- trg_handoff_only_originator_closes: the author seat names itself, only for this transaction.
    perform set_config('qd.handoff_closer', d.author_seat, true);
    perform public.fn_seat_handoff_complete(d.handoff_id, jsonb_build_object('deliberation_id', p_id,
      'final_verdict', c.verdict, 'reviewer_model', c.model, 'reviewer_provider', c.provider,
      'ended', d.status, 'outcome', p_outcome, 'closed_by', p_closed_by));
  end if;
  return jsonb_build_object('ok', true, 'deliberation_id', p_id, 'final_verdict', c.verdict, 'ended', d.status);
end $fn$;
revoke execute on function public.fn_seat_deliberation_close(bigint, text, text) from public, anon, authenticated;

-- WHICH OPEN DELIBERATIONS THE HEARTBEAT ADVANCES. Least recently attempted first, so a held or failing one
-- cannot starve a newer one; three failed model turns in a round stop the retries (each is a paid call) and
-- the monitor names it for the CEO instead.
create or replace function public.fn_seat_deliberation_due(p_limit integer default 3)
returns setof bigint language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select d.id from public.seat_deliberation d
   where d.status = 'open'
     and (select count(*) from public.seat_deliberation_turn t
           where t.deliberation_id = d.id and t.round = d.round and t.status = 'failed') < 3
   order by (select max(t.created_at) from public.seat_deliberation_turn t
              where t.deliberation_id = d.id and t.phase <> 'proposal') asc nulls first, d.id
   limit greatest(p_limit, 0);
$fn$;
revoke execute on function public.fn_seat_deliberation_due(integer) from public, anon, authenticated;

-- ── 8. THE HANDOFF (nothing is one-way) ────────────────────────────────────────────────────────
-- The reviewing seat answers at once with the deterministic step (held / escalated / ready for the
-- model); the model turns follow from the heartbeat; the author closes.
create or replace function public.fn_seat_deliberation_acts_on_handoff(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; v_did bigint; v jsonb;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  v_did := nullif(a.detail->>'deliberation_id', '')::bigint;
  if v_did is null then raise exception 'handoff % names no deliberation', p_id; end if;
  -- open() sets handoff_id after fn_seat_handoff returns; the step below does not need it.
  v := public.fn_seat_deliberation_step(v_did);
  return jsonb_build_object('waiting', a.agent || '''s independent review (blind pass, then comparison), then '
                                       || (a.detail->>'from') || ' closes', 'deliberation_id', v_did, 'step', v);
end $fn$;
revoke execute on function public.fn_seat_deliberation_acts_on_handoff(bigint) from public, anon, authenticated;

-- No pair is registered here. The build that calls fn_seat_deliberation_open for a pair adds its
-- ('deliberation.review', <author>, <reviewer>) row with handler fn_seat_deliberation_acts_on_handoff (marketing -> ceo: #876).

-- ── 9. THE AGREEMENT MONITOR ───────────────────────────────────────────────────────────────────
-- p_include_demo exists for the check's rolled-back ZZ DEMO history only; the duty never passes it.
create or replace function public.fn_it_deliberation_independence_items(p_include_demo boolean default false,
  p_window interval default interval '30 days', p_min_reviews integer default 10, p_threshold numeric default 0.90)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with fin as (
    select d.id, d.reviewer_seat, d.author_seat,
           (select t.verdict from public.seat_deliberation_turn t where t.deliberation_id = d.id and t.phase = 'compare'
               and t.status = 'recorded' order by t.round desc limit 1) final_verdict,
           (select t.verdict from public.seat_deliberation_turn t where t.deliberation_id = d.id and t.phase = 'blind'
               and t.status = 'recorded' order by t.round limit 1) blind_verdict,
           (select string_agg(distinct t.model, ', ') from public.seat_deliberation_turn t where t.deliberation_id = d.id
               and t.phase in ('blind', 'compare') and t.status = 'recorded') reviewer_models
      from public.seat_deliberation d
     where d.opened_at >= now() - p_window and (p_include_demo or not d.demo)
  ), pair as (
    select reviewer_seat, author_seat, count(*) n,
           count(*) filter (where final_verdict = 'approve') approvals,
           count(*) filter (where blind_verdict = final_verdict) blind_matched,
           string_agg(distinct reviewer_models, ', ') models
      from fin where final_verdict is not null group by reviewer_seat, author_seat
  ), stamp as (
    select jsonb_build_object(
             'item', 'rubber_stamp:' || reviewer_seat || ':' || author_seat, 'owner_seat', 'ceo', 'subject', 'seat_deliberation',
             'title', reviewer_seat || ' approved ' || approvals || ' of ' || n || ' proposals from ' || author_seat
                      || ' in ' || p_window || ' (' || round(100.0 * approvals / n) || '%); its blind verdict matched the final one '
                      || blind_matched || ' of ' || n || ' times. A reviewer that approves almost everything is a failed check '
                      || '(founder_instruction 873) - read the steelmans before the next approval.',
             'blast', 'agent_facing', 'affected', n,
             'evidence', jsonb_build_object('reviews', n, 'approvals', approvals, 'approval_rate', round(1.0 * approvals / n, 4),
                           'blind_matched', blind_matched, 'blind_match_rate', round(1.0 * blind_matched / n, 4),
                           'threshold', p_threshold, 'min_reviews', p_min_reviews, 'window', p_window::text, 'reviewer_models', models,
                           'look_at', 'select * from public.seat_deliberation_turn where deliberation_id in (select id from public.seat_deliberation where reviewer_seat = '''
                                      || reviewer_seat || ''' and author_seat = ''' || author_seat || ''') order by id')) x
      from pair where n >= p_min_reviews and approvals >= p_threshold * n
  ), noind as (
    select jsonb_build_object(
             'item', 'no_independent_reviewer:' || reviewer_seat || ':' || author_seat, 'owner_seat', 'ceo', 'subject', 'seat_deliberation',
             'title', count(*) || ' deliberation(s) from ' || author_seat || ' to ' || reviewer_seat
                      || ' have no independent reviewer: no healthy model outside the author''s family. They were not '
                      || 'reviewed on the same family instead; close them or restore a reviewer.',
             'blast', 'agent_facing', 'affected', count(*),
             'evidence', jsonb_build_object('deliberation_ids', jsonb_agg(id order by id))) x
      from public.seat_deliberation d
     where d.status = 'no_independent_reviewer' and (p_include_demo or not d.demo)
     group by reviewer_seat, author_seat
  ), failing as (
    select jsonb_build_object(
             'item', 'review_failing:' || reviewer_seat || ':' || author_seat, 'owner_seat', 'ceo', 'subject', 'seat_deliberation',
             'title', count(*) || ' deliberation(s) from ' || author_seat || ' to ' || reviewer_seat
                      || ' stopped after three failed review turns in one round; read the why on each failed turn.',
             'blast', 'agent_facing', 'affected', count(*),
             'evidence', jsonb_build_object('deliberation_ids', jsonb_agg(id order by id))) x
      from public.seat_deliberation d
     where d.status = 'open' and (p_include_demo or not d.demo)
       and (select count(*) from public.seat_deliberation_turn t
             where t.deliberation_id = d.id and t.round = d.round and t.status = 'failed') >= 3
     group by reviewer_seat, author_seat
  )
  select coalesce((select jsonb_agg(x) from stamp), '[]'::jsonb) || coalesce((select jsonb_agg(x) from noind), '[]'::jsonb)
         || coalesce((select jsonb_agg(x) from failing), '[]'::jsonb);
$fn$;
revoke execute on function public.fn_it_deliberation_independence_items(boolean, interval, integer, numeric) from public, anon, authenticated;

create or replace function public.fn_it_deliberation_independence_watch(p_include_demo boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_items jsonb := public.fn_it_deliberation_independence_items(p_include_demo);
begin
  -- A demo deliberation's escalation is judged with the demo rows included and settled under its own duty,
  -- so a rolled-back probe can never close or open the real duty's findings.
  return jsonb_build_object('items', jsonb_array_length(v_items),
    'settle', public.fn_it_duty_settle(case when p_include_demo then 'deliberation_independence_demo' else 'deliberation_independence' end, v_items));
end $fn$;
revoke execute on function public.fn_it_deliberation_independence_watch(boolean) from public, anon, authenticated;

insert into public.it_founder_decision_class (issue_key_like, to_founder, why) values
  ('duty:deliberation_independence:%', true,
   'founder_instruction 873: two seats must not agree unless it is right. A reviewer that approves nearly everything, or a '
   || 'review that had no independent model to run on, is his to see in the regular report.')
on conflict (issue_key_like) do nothing;
