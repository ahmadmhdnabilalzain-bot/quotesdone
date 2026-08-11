-- PHASE 7 HYGIENE: the duplicates, and the only dead routine in 698.
--
-- ============================================================================================
-- RE-MEASURED FIRST. The audit's counts do not all reproduce, and the key matters, so both are
-- stated. Key used here: md5(coalesce(title,'') || '|' || coalesce(content,'')) — an exact,
-- byte-identical pair of title and body. Production, 11 Aug 2026:
--
--   table            rows      duplicate rows (this key)     audit said
--   kb_chunks      120,535     24,694                        28,521
--   ops_knowledge    3,959        224                         1,197
--   os_runbooks        106          0                            21
--
-- The audit's larger figures were measured on a different key (content alone, or including rows
-- this key treats as distinct). Neither is wrong; only one of them is stated, and this is it.
-- os_runbooks holds NO duplicates by title+steps+when_to_use, so nothing is deleted there.
--
-- WHY THE kb_chunks DUPLICATES ARE WORTH DELETING AND NOT JUST COUNTING. They are a retrieval
-- corpus. An exact duplicate cannot add a fact; it can only take a slot in the top-k that a
-- different fact would have had, twice. And the embedding backfill is 42% done at ~600 rows an
-- hour — one row in five of the remaining work is a byte-identical copy of a row already embedded.
--
-- WHICH COPY SURVIVES. The EMBEDDED one, and among equals the lowest id. Keeping the oldest
-- blindly would have thrown away 4,000-odd vectors and made the backlog worse.
--
-- No foreign key anywhere references kb_chunks or ops_knowledge — checked against pg_constraint
-- before writing this, because the reason to check is that a cascade would be silent.
-- ============================================================================================

with ranked as (
  select id,
         row_number() over (
           partition by md5(coalesce(title,'') || '|' || coalesce(content,''))
           order by (embedding_gte is not null) desc, id
         ) rn
    from public.kb_chunks
)
delete from public.kb_chunks k using ranked r where k.id = r.id and r.rn > 1;

with ranked as (
  select record_id,
         row_number() over (
           partition by md5(coalesce(title,'') || '|' || coalesce(content,''))
           order by (validation_status = 'approved') desc, record_id
         ) rn
    from public.ops_knowledge
)
delete from public.ops_knowledge o using ranked r where o.record_id = r.record_id and r.rn > 1;

-- ============================================================================================
-- THE ONE DEAD ROUTINE IN 698.
--
-- fn_simulate_growth(p_invites_per_day, p_invite_accept_rate, p_verification_rate, p_months,
-- p_target_verified). Three of the four routines that LOOKED dead in the audit were load-bearing —
-- fn_enforce_rls_on_new_tables is a live EVENT TRIGGER whose removal would silently stop RLS on
-- every table created afterwards. So this one was checked five ways before dropping it, on
-- production, today:
--
--   other routine bodies referencing it   0
--   triggers bound to it                  0
--   cron jobs invoking it                 0
--   views depending on it                 0
--   references in the repo                migration history, audit docs and schema dumps only —
--                                         no edge function, no script, no page
--
-- It is a what-if calculator for supplier growth that nothing ever asks. The Maturity Index and
-- the what-if simulator the specs DO ask for are separate, unbuilt items (spec #3 §"what-if"),
-- and this is not a partial implementation of them: it takes invite rates and returns a month
-- count.
-- ============================================================================================

drop function if exists public.fn_simulate_growth(integer, numeric, numeric, integer, integer);
