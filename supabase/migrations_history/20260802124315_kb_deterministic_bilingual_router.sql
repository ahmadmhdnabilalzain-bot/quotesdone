-- DETERMINISTIC BILINGUAL ROUTER.
-- This is the piece that is supposed to make the platform cheaper and more predictable: first-pass
-- category routing with no model call at all. A model is only worth paying for when this returns
-- nothing or returns a tie.
--
-- kb_norm() must stay byte-identical in behaviour to the normaliser the importer used to write
-- alias_norm, or the index is useless. Arabic is the reason it is not just lower(): the same phrase
-- is typed with or without hamza on the alef (ا/أ/إ/آ), with ta-marbuta or ha (ة/ه), with ya or
-- alef-maqsura (ي/ى), and with or without harakat. A UAE buyer writing "مقاولو المرافق" must reach
-- the same route as the alias stored from the manifest even when neither of them agrees on hamza.
create or replace function public.kb_norm(p text)
returns text language sql immutable parallel safe as $$
  select nullif(
    btrim(regexp_replace(
      translate(
        regexp_replace(lower(normalize(coalesce(p,''), NFKC)), '[ً-ْٰـ]', '', 'g'),
        'أإآةىؤئ', 'اااهيوي'
      ),
      '[^[:alnum:]؀-ۿ]+', ' ', 'g')),
    '');
$$;

comment on function public.kb_norm(text) is
  'Normaliser shared by the alias importer and the router. Any change here invalidates every stored kb_operational_alias.alias_norm and the aliases must be re-imported.';

-- Scores every route against a customer sentence and explains itself.
-- Scoring, and why it is shaped this way:
--   * a match must be a WHOLE WORD or phrase - substring matching makes "AC" match "vacuum" and
--     "lift" match "shoplifting", and a router that is confidently wrong is worse than one that
--     asks;
--   * specificity beats frequency. "DEWA NOC" (2 words) outranks "electrical" (1 word) because the
--     score multiplies the alias weight by its word count. Without this, every construction inquiry
--     lands on whichever route happens to own the most generic vocabulary;
--   * negative aliases subtract, so a route can actively disown a phrase - that is how "lift" is
--     kept away from forklifts and how "materials" does not swallow "raw materials for catering".
create or replace function public.fn_kb_route(p_text text, p_limit int default 5)
returns table (catalog_num int, live_slug text, live_name text, score numeric,
               matched_aliases jsonb, languages text[])
language sql stable as $$
with q as (select ' ' || kb_norm(p_text) || ' ' as t),
hits as (
  select a.catalog_num, a.alias, a.language, a.weight, a.negative,
         array_length(string_to_array(a.alias_norm, ' '), 1) as words
  from public.kb_operational_alias a, q
  where length(a.alias_norm) >= 3
    and q.t like '%' || ' ' || a.alias_norm || ' ' || '%'
),
scored as (
  select h.catalog_num,
         sum(case when h.negative then -1 else 1 end * h.weight * h.words) as score,
         jsonb_agg(jsonb_build_object('alias', h.alias, 'lang', h.language,
                                      'w', h.weight, 'words', h.words, 'neg', h.negative)
                   order by h.weight * h.words desc) as matched,
         array_agg(distinct h.language) as langs
  from hits h group by h.catalog_num
)
select s.catalog_num, c.slug, c.name, s.score, s.matched, s.langs
from scored s join public.catalog_supplier_categories c on c.num = s.catalog_num
where s.score > 0
order by s.score desc, s.catalog_num
limit greatest(p_limit, 1);
$$;

-- The decision, separated from the scoring so the thresholds are visible and tunable in one place.
-- Returns exactly what the control pack asks a router to return: ranked candidates, confidence,
-- reasons, and an action - route, ask ONE clarifying question, or admit it has nothing.
create or replace function public.fn_kb_route_decide(p_text text)
returns jsonb language plpgsql stable as $$
declare
  v jsonb; top numeric; second numeric; n int; v_action text; v_conf numeric;
begin
  select coalesce(jsonb_agg(to_jsonb(r) order by r.score desc), '[]'::jsonb) into v
  from (select * from public.fn_kb_route(p_text, 5)) r;

  n := jsonb_array_length(v);
  if n = 0 then
    return jsonb_build_object(
      'action', 'ask_clarifying_question', 'confidence', 0, 'candidates', '[]'::jsonb,
      'reason', 'no deterministic alias matched the customer wording',
      'clarification', 'Could you tell me in your own words what you need done or supplied? For example "waterproof a warehouse roof" or "supply 200 office chairs".',
      'normalised', public.kb_norm(p_text));
  end if;

  top    := (v->0->>'score')::numeric;
  second := case when n > 1 then (v->1->>'score')::numeric else 0 end;

  -- Confidence is the winner's share of the top-two mass. Two routes tied at 12 give 0.5 and a
  -- question; a winner at 30 against a runner-up at 4 gives 0.88 and a route. The 0.62 threshold
  -- and the >=6 floor were set so the supplied "ambiguous" tests ask rather than guess, without
  -- making the exact-phrase tests ask too.
  v_conf := round(top / nullif(top + second, 0), 3);
  if top < 6 or v_conf < 0.62 then
    v_action := 'ask_clarifying_question';
  else
    v_action := 'route_or_ask_scope_details';
  end if;

  return jsonb_build_object(
    'action', v_action,
    'confidence', v_conf,
    'top_score', top,
    'candidates', v,
    'catalog_num', case when v_action = 'route_or_ask_scope_details' then (v->0->>'catalog_num')::int else null end,
    'multi_category', (n > 1 and second >= top * 0.75),
    'reason', case when v_action = 'route_or_ask_scope_details'
                   then 'deterministic alias match'
                   else 'leading routes are too close, or the match was too weak to act on' end,
    'clarification', case when v_action = 'ask_clarifying_question' then
        coalesce('Just to point this to the right suppliers - is this closer to "' ||
                 (v->0->>'live_name') || '" or "' || coalesce(v->1->>'live_name','something else') || '"?',
                 'Could you describe what you need in a little more detail?')
      end,
    'normalised', public.kb_norm(p_text));
end $$;

grant execute on function public.kb_norm(text), public.fn_kb_route(text,int), public.fn_kb_route_decide(text) to service_role;
