-- THE MULTILINGUAL EMBEDDER IS THE IT ENGINEER'S (24 Sep 2026; seat: it_engineer).
-- embed_ml (#907) went live without a public.function_owner row, and every_deployed_function_has_an_owner
-- refuses a deployed function nobody owns. It is shared platform, like ai_gateway: the it_engineer owns it.
--   node scripts/apply_sql.mjs scripts/sql/the_multilingual_embedder_is_the_it_engineers.sql --apply --ddl --seat it_engineer
insert into public.function_owner (function_slug, owner, note) values
  ('embed_ml', 'it_engineer',
   'The multilingual embedder (multilingual-e5-small, trimmed, from the ml-models bucket): question vectors for think() and case recall, and the knowledge_vector_ml queue tick. Free, in-region, not OpenRouter.')
on conflict (function_slug) do update set owner = excluded.owner, note = excluded.note;
