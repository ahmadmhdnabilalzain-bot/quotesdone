-- ---------------------------------------------------------------------------
-- SEMANTIC CACHE + THE NO-AI LAYER
--
-- Two ideas from the plan that together remove the majority of calls:
--   * a cache that matches MEANING, not bytes ("how do I secure my API" and
--     "how do I protect my backend" are one answer, one call)
--   * a Level 0 path that answers from the database and never reaches a model
--
-- Both run on gte-small, which is in-region and FREE, so the lookup itself costs
-- nothing. That is what makes it worth checking before every single call.
-- ---------------------------------------------------------------------------

alter table llm_cache add column if not exists embedding_gte vector(384);
alter table llm_cache add column if not exists saved_usd numeric not null default 0;
create index if not exists llm_cache_emb_idx on llm_cache
  using ivfflat (embedding_gte vector_cosine_ops) with (lists = 50);
create index if not exists llm_cache_expiry_idx on llm_cache (expires_at);

-- Exact hit first (free, index lookup), then semantic. Returns the row so the caller
-- can log which kind of hit it was.
create or replace function fn_llm_cache_lookup(
  p_key       text,
  p_embedding vector(384) default null,
  p_task_class text default null,
  p_min_similarity numeric default 0.95
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare r record; v_sim numeric;
begin
  -- 1. exact
  select * into r from llm_cache
   where cache_key = p_key and (expires_at is null or expires_at > now()) limit 1;
  if found then
    update llm_cache set hits = hits + 1, last_hit_at = now() where cache_key = r.cache_key;
    return jsonb_build_object('hit', true, 'kind', 'exact', 'response', r.response,
                              'model', r.model_used, 'similarity', 1.0);
  end if;

  -- 2. semantic. Deliberately scoped to the same task_class: a research answer must
  -- never be served to a classification prompt just because they read alike.
  if p_embedding is not null then
    select c.*, 1 - (c.embedding_gte <=> p_embedding) as sim into r
      from llm_cache c
     where c.embedding_gte is not null
       and (c.expires_at is null or c.expires_at > now())
       and (p_task_class is null or c.task_class is not distinct from p_task_class)
     order by c.embedding_gte <=> p_embedding
     limit 1;
    if found then
      v_sim := round((r.sim)::numeric, 4);
      if v_sim >= p_min_similarity then
        update llm_cache set hits = hits + 1, last_hit_at = now() where cache_key = r.cache_key;
        return jsonb_build_object('hit', true, 'kind', 'semantic', 'response', r.response,
                                  'model', r.model_used, 'similarity', v_sim);
      end if;
    end if;
  end if;

  return jsonb_build_object('hit', false);
end $$;

create or replace function fn_llm_cache_store(
  p_key text, p_fn text, p_task_class text, p_model text, p_response text,
  p_ttl_minutes integer, p_embedding vector(384) default null, p_saved_usd numeric default 0
) returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  insert into llm_cache (cache_key, fn, task_class, model_used, response, prompt_hash,
                         expires_at, embedding_gte, saved_usd)
  values (p_key, p_fn, p_task_class, p_model, p_response, p_key,
          now() + make_interval(mins => greatest(coalesce(p_ttl_minutes,60),1)), p_embedding, coalesce(p_saved_usd,0))
  on conflict (cache_key) do update set response = excluded.response, model_used = excluded.model_used,
    expires_at = excluded.expires_at, embedding_gte = coalesce(excluded.embedding_gte, llm_cache.embedding_gte);
$$;

-- ---------------------------------------------------------------------------
-- LEVEL 0 — answer without a model at all.
-- ---------------------------------------------------------------------------

-- Response template library (plan item: "Add Response Templates" / "Email Response Library").
create table if not exists response_template (
  key         text primary key,
  channel     text not null default 'any',   -- any | whatsapp | email | web
  intent      text not null,
  body        text not null,
  active      boolean not null default true,
  used_count  integer not null default 0,
  created_at  timestamptz not null default now()
);
alter table response_template enable row level security;
revoke all on response_template from public, anon, authenticated;

insert into response_template (key, channel, intent, body) values
 ('greeting','any','greeting','Hello, and thanks for contacting QuotesDone. Tell me what you need a quote for and I will take it from there.'),
 ('thanks','any','thanks','Happy to help. Anything else you need?'),
 ('hours','any','opening_hours','We operate online, so requests can be submitted at any time. Suppliers are matched within one working day.'),
 ('location','any','location','QuotesDone is a UAE marketplace operating across all seven emirates.'),
 ('pricing_model','any','pricing','QuotesDone charges suppliers no commission. Registration is free until 31 July 2027, and the first 1,000 suppliers to register never pay the annual subscription.'),
 ('anonymity','any','anonymity','Quoting is blind. Clients compare offers on merit, and suppliers never see each other prices.')
on conflict (key) do nothing;

-- Deterministic FAQ answer. Full-text ranked over the 151 approved public FAQs.
-- Returns an answer ONLY when the match is strong; anything ambiguous falls through
-- to a model, because a confidently wrong canned answer is worse than paying.
create or replace function fn_faq_answer(p_text text, p_min_rank numeric default 0.30)
returns jsonb
language plpgsql stable
security definer
set search_path = public, pg_temp
as $$
declare r record; v_q tsquery; v_tpl record;
begin
  if p_text is null or length(btrim(p_text)) < 3 then
    return jsonb_build_object('answered', false, 'reason', 'input too short');
  end if;

  -- Templates first: greetings and other fixed intents never need retrieval.
  select * into v_tpl from response_template
   where active and (
     (intent='greeting' and p_text ~* '^\s*(hi|hey|hello|salam|good (morning|afternoon|evening))\W*$') or
     (intent='thanks'   and p_text ~* '^\s*(thanks|thank you|shukran|much appreciated)\W*$')
   ) limit 1;
  if found then
    update response_template set used_count = used_count + 1 where key = v_tpl.key;
    return jsonb_build_object('answered', true, 'source', 'template', 'key', v_tpl.key,
                              'answer', v_tpl.body, 'confidence', 1.0);
  end if;

  v_q := websearch_to_tsquery('english', p_text);
  if v_q is null then return jsonb_build_object('answered', false, 'reason', 'unparseable'); end if;

  select f.question, f.answer,
         ts_rank(to_tsvector('english', coalesce(f.question,'') || ' ' || coalesce(f.answer,'')), v_q) as rank
    into r
    from company_faq f
   where f.public and f.status = 'approved'
     and to_tsvector('english', coalesce(f.question,'') || ' ' || coalesce(f.answer,'')) @@ v_q
   order by rank desc
   limit 1;

  if not found or r.rank < p_min_rank then
    return jsonb_build_object('answered', false, 'reason', 'no confident FAQ match',
                              'best_rank', coalesce(round(r.rank::numeric,4), 0));
  end if;

  return jsonb_build_object('answered', true, 'source', 'faq', 'question', r.question,
                            'answer', r.answer, 'confidence', round(r.rank::numeric, 4));
end $$;

-- Generic rate limiter. site_assistant had its own; this is the shared one so every
-- public surface can be capped, especially wa_inbound which had none and also spends
-- Twilio credit on every call.
create table if not exists ai_rate_limit (
  bucket      text primary key,
  window_start timestamptz not null default now(),
  count       integer not null default 0
);
alter table ai_rate_limit enable row level security;
revoke all on ai_rate_limit from public, anon, authenticated;

create or replace function fn_rate_limit(p_bucket text, p_limit integer, p_window_seconds integer)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare r ai_rate_limit%rowtype;
begin
  insert into ai_rate_limit (bucket, window_start, count) values (p_bucket, now(), 0)
    on conflict (bucket) do nothing;
  select * into r from ai_rate_limit where bucket = p_bucket for update;
  if r.window_start < now() - make_interval(secs => p_window_seconds) then
    update ai_rate_limit set window_start = now(), count = 1 where bucket = p_bucket;
    return jsonb_build_object('allowed', true, 'count', 1, 'limit', p_limit);
  end if;
  if r.count >= p_limit then
    return jsonb_build_object('allowed', false, 'count', r.count, 'limit', p_limit,
      'retry_after_seconds', greatest(1, p_window_seconds - extract(epoch from (now() - r.window_start))::int));
  end if;
  update ai_rate_limit set count = count + 1 where bucket = p_bucket;
  return jsonb_build_object('allowed', true, 'count', r.count + 1, 'limit', p_limit);
end $$;

revoke execute on function fn_llm_cache_lookup(text,vector,text,numeric) from public, anon, authenticated;
revoke execute on function fn_llm_cache_store(text,text,text,text,text,integer,vector,numeric) from public, anon, authenticated;
revoke execute on function fn_faq_answer(text,numeric) from public, anon, authenticated;
revoke execute on function fn_rate_limit(text,integer,integer) from public, anon, authenticated;

comment on function fn_faq_answer(text,numeric) is
  'Level 0: answers from templates or the approved public FAQ with no model call. Returns answered=false whenever the match is not strong, because a confidently wrong canned answer costs more than a model call.';