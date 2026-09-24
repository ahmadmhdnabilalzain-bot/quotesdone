-- EVERY SEAT HOLDS ITS SECOND WAVE OF PROFESSIONAL KNOWLEDGE — a read-only verdict probe. 24 Sep 2026.
-- Seats: ceo, customer_support, marketing, accountant, it_engineer (each owns its own pack file).
-- Founder instructions 889/893/894/903/961: every seat's knowledge to professional standard, the sales
-- engineer excepted for now (961); a stepwise reasoning sequence for every seat (903).
--
-- WHAT CHANGED (knowledge/seats/*.json, loaded by scripts/kb/load_verified_packs.mjs --apply):
--   ceo 88 -> 129 entries, customer_support 90 -> 128, marketing 89 -> 130, accountant 82 -> 120,
--   it_engineer 99 -> 143. 202 new entries, each EN + AR = 404 new rows; each seat gained 4-6
--   "Reasoning sequence" method entries. Every pack passes the gate in scripts/kb/verified_packs.mjs.
-- MEASURED before the load (production, 24 Sep 2026): verified_pack rows ceo 176, support 180,
--   marketing 178, accountant 164, it_engineer 198, all embedded.
--
-- THIS FILE WRITES NOTHING. It is the verdict the release operator reads after the loader ran: each
-- seat table holds at least the rows the dry run planned, and every verified_pack row is embedded
-- (an unembedded row is invisible to fn_reason_retrieve, which ranks by vector).
with t(seat, want, have, unembedded) as (
  select 'ceo', 258, count(*), count(*) filter (where embedding_gte is null) from public.ceo_knowledge where 'verified_pack' = any(tags)
  union all select 'customer_support', 256, count(*), count(*) filter (where embedding_gte is null) from public.support_knowledge where 'verified_pack' = any(tags)
  union all select 'marketing', 260, count(*), count(*) filter (where embedding_gte is null) from public.marketing_knowledge where 'verified_pack' = any(tags)
  union all select 'accountant', 240, count(*), count(*) filter (where embedding_gte is null) from public.accountant_knowledge where 'verified_pack' = any(tags)
  union all select 'it_engineer', 286, count(*), count(*) filter (where embedding_gte is null) from public.it_engineer_knowledge where 'verified_pack' = any(tags)
)
select case
  when exists (select 1 from t where have < want)
    then 'PROBE FAILED: rows short: ' || (select string_agg(seat || ' ' || have || '/' || want, ', ') from t where have < want)
  when exists (select 1 from t where unembedded > 0)
    then 'PROBE FAILED: unembedded rows: ' || (select string_agg(seat || ' ' || unembedded, ', ') from t where unembedded > 0)
  else 'PROBE OK' end as verdict;
