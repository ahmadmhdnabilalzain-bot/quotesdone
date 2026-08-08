-- Declared STABLE but it increments the template usage counter, which Postgres
-- correctly refuses. Usage counts are how we later learn which templates are
-- earning their keep, so keep the write and make the function VOLATILE.
create or replace function fn_faq_answer(p_text text, p_min_rank numeric default 0.30)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare r record; v_q tsquery; v_tpl record;
begin
  if p_text is null or length(btrim(p_text)) < 3 then
    return jsonb_build_object('answered', false, 'reason', 'input too short');
  end if;

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

revoke execute on function fn_faq_answer(text,numeric) from public, anon, authenticated;