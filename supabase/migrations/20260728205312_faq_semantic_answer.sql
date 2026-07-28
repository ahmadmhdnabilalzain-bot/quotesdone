-- Calibration, measured rather than guessed. Real ts_rank values against the live
-- FAQ set: "do you charge commission?" -> 0.185 (a genuinely correct match),
-- "is registration free" -> 0.098 (a vague one that deserves better). A 0.30 default
-- rejected everything; 0.15 accepts the good match and still rejects the vague one.
--
-- More importantly, plain full-text found NOTHING for two of five realistic questions
-- ("how does blind quoting work", "what documents do I need to register"). Keyword
-- search cannot answer a question phrased differently from the FAQ. So the function
-- now takes an optional embedding and falls back to semantic similarity, which is
-- free in-region and is exactly the plan's "retrieval instead of generation".

alter table company_faq add column if not exists embedding_gte vector(384);
create index if not exists company_faq_emb_idx on company_faq
  using ivfflat (embedding_gte vector_cosine_ops) with (lists = 20);

create or replace function fn_faq_answer(
  p_text text,
  p_min_rank numeric default 0.15,
  p_embedding vector(384) default null,
  p_min_similarity numeric default 0.86
) returns jsonb
language plpgsql volatile
security definer
set search_path = public, pg_temp
as $$
declare r record; v_q tsquery; v_tpl record; v_sim numeric;
begin
  if p_text is null or length(btrim(p_text)) < 2 then
    return jsonb_build_object('answered', false, 'reason', 'input too short');
  end if;

  -- 1. Fixed intents. No retrieval, no model.
  select * into v_tpl from response_template
   where active and (
     (intent='greeting' and p_text ~* '^\s*(hi|hey|hello|salam|marhaba|good (morning|afternoon|evening))\W*$') or
     (intent='thanks'   and p_text ~* '^\s*(thanks|thank you|thx|shukran|much appreciated)\W*$')
   ) limit 1;
  if found then
    update response_template set used_count = used_count + 1 where key = v_tpl.key;
    return jsonb_build_object('answered', true, 'source', 'template', 'key', v_tpl.key,
                              'answer', v_tpl.body, 'confidence', 1.0);
  end if;

  -- 2. Keyword match. Cheap and precise when the wording lines up.
  v_q := websearch_to_tsquery('english', p_text);
  if v_q is not null then
    select f.question, f.answer,
           ts_rank(to_tsvector('english', coalesce(f.question,'')||' '||coalesce(f.answer,'')), v_q) as rank
      into r
      from company_faq f
     where f.public and f.status='approved'
       and to_tsvector('english', coalesce(f.question,'')||' '||coalesce(f.answer,'')) @@ v_q
     order by rank desc limit 1;
    if found and r.rank >= p_min_rank then
      return jsonb_build_object('answered', true, 'source', 'faq_keyword', 'question', r.question,
                                'answer', r.answer, 'confidence', round(r.rank::numeric, 4));
    end if;
  end if;

  -- 3. Semantic match. Catches the same question asked in different words.
  if p_embedding is not null then
    select f.question, f.answer, 1 - (f.embedding_gte <=> p_embedding) as sim into r
      from company_faq f
     where f.public and f.status='approved' and f.embedding_gte is not null
     order by f.embedding_gte <=> p_embedding limit 1;
    if found then
      v_sim := round((r.sim)::numeric, 4);
      if v_sim >= p_min_similarity then
        return jsonb_build_object('answered', true, 'source', 'faq_semantic', 'question', r.question,
                                  'answer', r.answer, 'confidence', v_sim);
      end if;
      return jsonb_build_object('answered', false, 'reason', 'no confident FAQ match',
                                'best_similarity', v_sim);
    end if;
  end if;

  return jsonb_build_object('answered', false, 'reason', 'no confident FAQ match');
end $$;

revoke execute on function fn_faq_answer(text,numeric,vector,numeric) from public, anon, authenticated;
drop function if exists fn_faq_answer(text, numeric);