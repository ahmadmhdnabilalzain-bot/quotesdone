-- EVERY SERVICE IS EMBEDDED FROM ITS NAMES AND ALIASES, IN BOTH LANGUAGES.
-- Seat: sales_engineer. 29 Sep 2026, decision point 93 (b) (coordinator's ruling on ruling 890).
--
-- The meaning layer (supabase/functions/_shared/service_meaning.ts) is now the only way a line that is not written
-- as a service's name names one, so it has to read what the alias words used to catch, and it has to read Arabic.
--   * embedding_gte is re-made from serviceEmbedText: the English name AND the English aliases (aliases feed the
--     vector; they are never string-matched), the Arabic name and the trade's names. MEASURED 29 Sep 2026 on the
--     ZZ DEMO catalogue with the vectors computed in memory: name-only vectors missed hardware supply ("Laptops") and
--     POS terminals ("POS"); with aliases in the vector both are read and no false hit appears.
--   * embedding_ml is new: the multilingual-e5-small already deployed for knowledge (embed_ml), made from
--     serviceMlText (both names, every alias, the trade's names). An Arabic line is read against it. MEASURED 29 Sep
--     2026: 6 of 8 Arabic service clauses read to a service of the right trade, 0 of 6 Arabic noise clauses.
--   * embedding_gte_sha / embedding_ml_sha: the SHA-256 of the text each vector was made from, so a stored vector is
--     known to be current (a renamed service or a new alias makes it stale, and the backfill re-embeds it).
-- Nullable columns with no default: a catalogue-only change, no table rewrite, no long lock.
--
-- THE BACKFILL RUNS AT RELEASE, after this file: node scripts/kb/embed_taxonomy_services.mjs --write
-- (embeds every row whose sha is not current, both spaces, through embed_ml; free, in-region, not OpenRouter).
-- Until it has run, production reads the old gte vectors and has no Arabic ones: the meaning layer reports
-- service_vectors_missing for an Arabic line rather than guessing.
--
-- Pending: scripts/sql/pending/every_service_is_embedded_from_its_names_and_aliases_in_both_languages.txt.
-- Proved by scripts/checks/services_are_named_by_exact_name_or_meaning_never_by_alias_words.test.mjs.
alter table public.taxonomy_trade_service add column if not exists embedding_ml vector(384);
alter table public.taxonomy_trade_service add column if not exists embedding_gte_sha text;
alter table public.taxonomy_trade_service add column if not exists embedding_ml_sha text;
comment on column public.taxonomy_trade_service.embedding_ml is
  'sales_engineer: multilingual-e5-small (embed_ml query) vector of service_meaning.serviceMlText; an Arabic line is read against it.';
comment on column public.taxonomy_trade_service.embedding_gte_sha is
  'sales_engineer: SHA-256 of the service_meaning.serviceEmbedText the embedding_gte vector was made from (current when equal).';
comment on column public.taxonomy_trade_service.embedding_ml_sha is
  'sales_engineer: SHA-256 of the service_meaning.serviceMlText the embedding_ml vector was made from (current when equal).';

-- Verdict row (DDL file, so no raise): the three columns exist with their types.
select case
  when (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'taxonomy_trade_service'
          and ((column_name = 'embedding_ml' and udt_name = 'vector') or (column_name in ('embedding_gte_sha', 'embedding_ml_sha') and data_type = 'text'))) = 3
  then 'PROBE OK taxonomy_trade_service carries embedding_ml and both text shas'
  else 'PROBE FAILED: a service vector column is missing or of the wrong type' end as verdict;
