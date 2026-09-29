-- THE BLOG CLASSES RUN ON THE FOUNDER'S MODEL MATRIX.
-- Seat: marketing. 29 Sep 2026. Founder_instruction 1056 (the model matrix).
--
-- MEASURED BEFORE THIS FILE (production htdblwldjkcgjvmqkbeh, read-only, 29 Sep 2026):
--   * a_blog_article_is_a_market_topic_the_ceo_reviews_until_it_is_useful.sql (#1114) merged after the matrix file
--     (#1126) and wrote three classes on the routes 1056 replaced:
--       marketing_article_draft   openai/gpt-5.6-sol -> anthropic/claude-opus-5.5, 8000 tokens
--       marketing_article_revise  openai/gpt-5.6-sol -> anthropic/claude-opus-5.5, 8000 tokens
--       ceo_article_review        anthropic/claude-opus-5.5 -> openai/gpt-5.6-sol, 1500 tokens, no reviews_class
--   * every_seat_runs_the_founders_model_matrix_probe.sql: PROBE FAILED count=5 routes=74 pairs=150 - Sol still
--     named by an active policy, the three classes off the matrix, an Opus class under 4000 tokens.
--
-- WHAT THIS FILE CHANGES
--   1. Drafting and redrawing are marketing's work, and marketing is "every other seat": google/gemini-3.8-flash ->
--      deepseek/deepseek-v4.1-flash. 8000 tokens stay (a whole article in two languages).
--   2. The CEO's article review is a CEO hard judgement on another seat's output: anthropic/claude-opus-5.5 ->
--      openai/gpt-6-luna, 4000 tokens like every other Opus class (room for thinking; the caller in
--      supabase/functions/marketing/duties.ts asks for 4000 too - ai_gateway sends min(caller, class)).
--   3. ceo_article_review now DECLARES what it reviews (reviews_class = the two drafting classes), so ai_gateway refuses
--      it without counterpart_model and the probe walks every author/reviewer pair. The authors write on Gemini or
--      DeepSeek (or luna, marketing never; the probe walks every seat's plan B anyway); Opus is neither, and the
--      router picks a fallback outside the author's family.
-- Idempotent: a row already on its route is untouched.

update public.model_policy mp
   set tier = v.tier, model_primary = v.p, model_fallback = v.f, max_tokens = v.max_tokens, reviews_class = v.reviews,
       rationale = coalesce(mp.rationale, '') || ' | 29 Sep 2026 (founder_instruction 1056, the_blog_classes_run_on_the_founders_model_matrix.sql): '
                   || v.seat || ', ' || v.p || ' -> ' || v.f || '.'
  from (values
    ('marketing_article_draft',  'marketing', 'medium', 'google/gemini-3.8-flash',   'deepseek/deepseek-v4.1-flash', 8000, null::text[]),
    ('marketing_article_revise', 'marketing', 'medium', 'google/gemini-3.8-flash',   'deepseek/deepseek-v4.1-flash', 8000, null),
    ('ceo_article_review',       'ceo',       'xlarge', 'anthropic/claude-opus-5.5', 'openai/gpt-6-luna',            4000,
     array['marketing_article_draft', 'marketing_article_revise'])
  ) as v(task_class, seat, tier, p, f, max_tokens, reviews)
 where mp.task_class = v.task_class
   and (mp.tier, mp.model_primary, mp.model_fallback, mp.max_tokens, coalesce(mp.reviews_class, '{}'))
       is distinct from (v.tier, v.p, v.f, v.max_tokens, coalesce(v.reviews, '{}'));

select case
  when exists (select 1 from public.model_policy where active and 'openai/gpt-5.6-sol' in (model_primary, model_fallback))
    then 'PROBE FAILED: an active class still names openai/gpt-5.6-sol'
  when (select count(*) from public.model_policy where active
          and ((task_class in ('marketing_article_draft', 'marketing_article_revise')
                and (model_primary, model_fallback) = ('google/gemini-3.8-flash', 'deepseek/deepseek-v4.1-flash'))
            or (task_class = 'ceo_article_review' and (model_primary, model_fallback) = ('anthropic/claude-opus-5.5', 'openai/gpt-6-luna')
                and max_tokens >= 4000))) <> 3
    then 'PROBE FAILED: a blog class is off the matrix'
  else 'PROBE OK' end as verdict;
