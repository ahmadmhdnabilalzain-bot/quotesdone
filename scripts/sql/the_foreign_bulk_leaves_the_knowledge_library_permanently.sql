-- THE FOREIGN BULK LEAVES THE KNOWLEDGE LIBRARY PERMANENTLY
--
-- Seat: it_engineer. Spec: docs/KNOWLEDGE_DOCTRINE.md §6 (the classification rule) and §8 (the
-- read-only preview). Authority: founder instruction 520 (18 Sep 2026) — "anything that is not
-- related need to be deleted permanently".
--
-- MEASURED FIRST (21 Sep 2026, read-only, production):
--   public.kb_chunks: 2,615,397 live rows (reltuples 2,686,026; 358,790 dead; last autovacuum
--   31 Aug), 9,313 MB total = 4,206 MB heap + 3,228 MB TOAST + ~1.9 GB indexes (fts 949 MB,
--   emb_hnsw 438 MB, cat_id 192 MB). id range 3557..3087832. No foreign key references kb_chunks.
--   Four statement-level triggers (z90_kb_chunks_export_change_*) record every deleted id in
--   public.table_export_change so the incremental export sees the deletes — they stay ON.
--   The management API's statement_timeout is 2 min (platform-defaults.conf, every session).
--   Classifying every row (two regexes over `citation`) runs at ~12,500 rows/s: the whole table
--   is ~210 s, so a full-table count times out; per source_kind it does not
--   (reference: 265,903 rows in 21 s; the 17 non-`standard` delete/unsure kinds: 21 s).
--
-- THE CITATION LEDGER §6 CLAUSE 2 COULD NOT NAME — found. It is public.sales_decision_log.cited
-- (text[] of 'corpus:record_id', written by fn_sales_assist on every answer). 98 rows, 181 cited
-- entries (176 at the 18 Sep audit, 5 since): agent_knowledge 66, kb_chunks 39, ops_knowledge 37,
-- sales_knowledge 18, support_knowledge 11, company_faq 5, QD-SE-DEEP-009 5. The 39 kb_chunks
-- citations name 14 distinct chunk ids (trade 5, company_faq 2, standard 2, document 1,
-- generated 1, reference 1). kb_usage_log holds 0 rows; decision_log.sources never mentions
-- kb_chunks. Clause 2 is joined below as `id in (select … from sales_decision_log, unnest(cited))`.
--
-- FOUNDER RULING, 21 Sep 2026 (instruction 535): "remove anything related to US standards or laws
--   unless its related to UAE". Measured before the change, the UNSURE set's biggest groups were US
--   codes held by clause 4a/4b: NFPA 70 (NEC) 3,585, NFPA 1 2,485, NFPA 101 2,164, NFPA 13 1,853,
--   Uniform Plumbing Code 1,529, NFPA 99 1,143, NFPA 30 827, NFPA 54 722, International Plumbing Code
--   577, NFPA 58 516 (code kind). A US code or US law now goes to DELETE unless the row cites a UAE/GCC
--   authority (clause 3 runs first). fn_kb_is_us_code() is that test, named once, used by the clause
--   and the probe. Non-US foreign codes (BS EN / Eurocodes, IEC, ISO, EU and WHO GMP, IETF RFCs) are
--   not covered by the ruling and stay UNSURE for the founder.
--   Boundary: "related to UAE" is read from the CITATION string only; a US-code row whose text
--   discusses the UAE but whose citation does not name it is deleted. The 18 Sep full export holds
--   every such row.
-- ALSO FIXED: clause 3 did not know DIFC, ADGM or ADNOC, so "DIFC Companies Law, DIFC Law No. 5 of
--   2018" (257 rows) was held as UNSURE instead of KEPT as UAE law. Added.
--
-- WHAT THIS FILE CREATES (nothing is deleted by applying it):
--   fn_kb_purge_clause(source_kind, category, citation) — the §6 rule as ONE immutable SQL
--     function returning the clause number 1..5 (clause 2 is a row-id join, added by the callers).
--     Every reader (the batch, the probe, the census, the CI check) evaluates the same predicate.
--   kb_purge_ledger — the audit record §6 demands "before any delete": census rows per
--     (verdict, clause, source_kind, category) with batch_no NULL, then one row per
--     (source_kind, category) per delete batch, then SIZE rows before/after.
--   fn_kb_purge_batch(p_limit) — deletes ONE batch of clause-5 rows in id order from the ledger's
--     cursor, never a clause 1-4 row, never a cited id, never a QD/UAE citation (clauses 1 and 3
--     precede 5). Refuses to run until the census is in the ledger. Resumable: the cursor is
--     max(id_to) of the recorded batches; a failed batch rolls back and leaves no row.
--
-- NOT CHANGED: kb_chunk_quarantine (the purge moves nothing there — §5), the export triggers,
-- every index (REINDEX and VACUUM are run afterwards by scripts/kb/purge_kb_bulk.mjs), and
-- UNSURE rows (clause 4), which are held for the founder.
--
-- PROOF: the verdict row at the end (PROBE OK / PROBE FAILED) is read-only and bounded to the
-- kinds that fit the 2-minute limit; the `standard` kind (2,061,332 rows) is counted by id slices
-- in the census step of purge_kb_bulk.mjs, and its count is compared with §8 there.

begin;

-- ── 0. What counts as a US standard or a US law (founder instruction 535) ─────────────────────
create or replace function public.fn_kb_is_us_code(p_citation text)
returns boolean
language sql
immutable
parallel safe
set search_path to 'public', 'pg_temp'
as $$
  select coalesce(p_citation ~* '(\mNFPA\M|National Fire Protection Association|National Electrical Code|Uniform Plumbing Code|Uniform Mechanical Code|\mIAPMO\M|International (Building|Plumbing|Mechanical|Fire|Fuel Gas|Residential|Energy Conservation|Existing Building|Swimming Pool and Spa) Code|International Code Council|ASHRAE|\mASTM\M|SMACNA|\mANSI\M|\mUL ?[0-9]|Underwriters Laboratories|\mASME\M|American Petroleum Institute|\mAPI (RP|Spec|Std|Standard)|\mAPI ?[0-9]{1,4}[A-Z]{0,2}\M|American Welding Society|\mAWS ?D1|FM ?Global|\mCFR\M|Code of Federal Regulations|United States Code|\mUS Code|\mOSHA\M|\mEPA\M|\mFDA\M|\mFAA\M|Federal Register|\mNIST\M|U\.S\. (Army|Navy|Department|Government)|\mUS (Army|Navy|Department|Government|federal))', false)
$$;
revoke all on function public.fn_kb_is_us_code(text) from public, anon, authenticated;
comment on function public.fn_kb_is_us_code(text) is
  'True when a kb_chunks citation names a US standard or US law (founder instruction 535, 21 Sep 2026). fn_kb_purge_clause calls it AFTER the UAE test, so a US code that cites a UAE authority is still kept.';

-- ── 1. The rule, once ─────────────────────────────────────────────────────────────────────────
create or replace function public.fn_kb_purge_clause(p_source_kind text, p_category text, p_citation text)
returns smallint
language sql
immutable
parallel safe
set search_path to 'public', 'pg_temp'
as $$
  select case
    -- 1. KEEP — QuotesDone-authored
    when p_source_kind in ('qd_kb_pack','company_faq','memory','generated','trade','material','document','library')
      or p_citation ilike '%QD-KB%' or p_citation ilike '%quotesdone%'
      or p_category like 'cat:%' or p_category like 'exec:%' then 1
    -- 2. KEEP — ever cited: a row-id join, applied by the caller (see fn_kb_purge_batch)
    -- 3. KEEP — cites a UAE/GCC authority
    when p_citation ~* '(\mUAE\M|United Arab Emirates|Emirat|Dubai|Abu Dhabi|Sharjah|Ajman|Fujairah|Ras Al Khaimah|Umm Al Quwain|\mDEWA\M|\mADDC\M|\mAADC\M|\mSEWA\M|\mFEWA\M|Etihad ?WE|Civil Defen[cs]e|\mSIRA\M|\mESMA\M|\mMOIAT\M|\mGSO\M|\mGCC\M|Trakhees|Municipality|\mADQCC\M|\mRTA\M|\mTDRA\M|Estidama|Sa''fat|Tadweer|\mOSHAD\M|\mDMT\M|\mJAFZA\M|\mDDA\M|\mTECOM\M|\mDIFC\M|\mADGM\M|\mADNOC\M)' then 3
    -- 3b. DELETE — a US standard or US law that does not cite the UAE (founder instruction 535)
    when public.fn_kb_is_us_code(p_citation) then 5
    -- 4a. UNSURE — statute and code text is never deleted on a pattern
    when p_source_kind in ('code','regulation','spec') then 4
    -- 4b. UNSURE — a foreign code a UAE document may adopt. §6 limits this to in-scope trade
    --     families; this file applies it to EVERY category, which only moves rows from DELETE to
    --     UNSURE (never the other way), so the delete set is a subset of §8's. Measured effect on
    --     the non-`standard` kinds: 1,013 more rows held (guide 869, paper 144) than §8 shows.
    when p_citation ~* '(\mNFPA\M|\mNEC\M|\mBS ?EN\M|Eurocode|\mIEC\M|\mISO\M|ASHRAE|\mASTM\M|SMACNA|IAPMO|\mUPC\M|\mIPC\M|\mIBC\M|\mICC\M|CIBSE|BS ?7671|AWS ?D1|\mAPI\M|\mASME\M|\mANSI\M|\mUL\M|\mEN ?54\M|\mEN ?12845\M|LPCB|FM ?Global)' then 4
    -- 5. DELETE — foreign bulk
    else 5 end;
$$;
revoke all on function public.fn_kb_purge_clause(text, text, text) from public, anon, authenticated;
comment on function public.fn_kb_purge_clause(text, text, text) is
  'docs/KNOWLEDGE_DOCTRINE.md §6 as one predicate: 1 keep (QD-authored), 3 keep (UAE/GCC authority cited), 4 unsure (code/regulation/spec, or a foreign adoptable code), 5 delete (foreign bulk). Clause 2 (ever cited in sales_decision_log.cited) is a row-id join done by the caller.';

-- ── 2. The audit ledger ───────────────────────────────────────────────────────────────────────
create table if not exists public.kb_purge_ledger (
  id          bigint generated always as identity primary key,
  verdict     text not null check (verdict in ('KEEP','UNSURE','DELETE','SIZE')),
  clause      smallint not null check (clause between 0 and 5),
  source_kind text not null,
  category    text,
  rows        bigint,
  bytes       bigint,             -- octet_length(content) summed; NULL on census rows (a full detoast of 9 GB does not fit the API limit)
  batch_no    integer,            -- NULL = census row written BEFORE the first delete; n = the n-th delete batch
  id_from     bigint,             -- delete batches: cursor the batch started after
  id_to       bigint,             -- delete batches: highest id the batch deleted (the next cursor)
  note        text,
  created_at  timestamptz not null default now()
);
comment on table public.kb_purge_ledger is
  'Audit record of the kb_chunks purge (founder instruction 520; docs/KNOWLEDGE_DOCTRINE.md §6/§8). Census rows (batch_no NULL) are written before the first delete; each delete batch adds one row per (source_kind, category); SIZE rows record pg_total_relation_size before and after.';
create index if not exists kb_purge_ledger_batch_idx on public.kb_purge_ledger (batch_no) where batch_no is not null;
alter table public.kb_purge_ledger enable row level security;
drop policy if exists kb_purge_ledger_service_role_only on public.kb_purge_ledger;
create policy kb_purge_ledger_service_role_only on public.kb_purge_ledger
  as permissive for all to public using (false) with check (false);
revoke all on public.kb_purge_ledger from public, anon, authenticated;

-- ── 3. One batch ──────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_kb_purge_batch(p_limit integer default 50000)
returns table (batch_no integer, deleted_count bigint, deleted_bytes bigint,
               cursor_from bigint, cursor_to bigint, remaining_count bigint)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_planned bigint;
  v_done    bigint;
  v_from    bigint;
  v_to      bigint;
  v_batch   integer;
  v_deleted bigint;
  v_bytes   bigint;
begin
  if p_limit is null or p_limit < 1 or p_limit > 200000 then
    raise exception 'fn_kb_purge_batch: p_limit must be 1..200000 (got %)', p_limit;
  end if;

  -- §6: the audit row per (verdict, source_kind, category) is written FIRST. No census, no delete.
  select sum(l.rows) into v_planned
    from public.kb_purge_ledger l where l.verdict = 'DELETE' and l.clause = 5 and l.batch_no is null;
  if v_planned is null then
    raise exception 'fn_kb_purge_batch: no census in kb_purge_ledger — run scripts/kb/purge_kb_bulk.mjs, which writes it before the first batch';
  end if;

  select coalesce(max(l.id_to), 0), coalesce(max(l.batch_no), 0), coalesce(sum(l.rows), 0)
    into v_from, v_batch, v_done
    from public.kb_purge_ledger l where l.verdict = 'DELETE' and l.batch_no is not null;
  v_batch := v_batch + 1;

  -- ponytail: id-ordered cursor, so a batch never rescans what an earlier batch already walked;
  -- the predicate is evaluated on ~p_limit rows per call (~4 s per 50,000), not on the table.
  with pick as (
    select k.id
      from public.kb_chunks k
     where k.id > v_from
       and public.fn_kb_purge_clause(k.source_kind, k.category, k.citation) = 5
       and k.id not in (select split_part(x, ':', 2)::bigint
                          from public.sales_decision_log s, unnest(s.cited) x
                         where x ~ '^kb_chunks:[0-9]+$')            -- clause 2
     order by k.id
     limit p_limit
  ), del as (
    delete from public.kb_chunks k
     using pick p
     where k.id = p.id
    returning k.id, k.source_kind, k.category, octet_length(k.content) as b
  ), rec as (
    insert into public.kb_purge_ledger (verdict, clause, source_kind, category, rows, bytes, batch_no, id_from, id_to)
    select 'DELETE', 5, d.source_kind, d.category, count(*), sum(d.b), v_batch, v_from, (select max(id) from del)
      from del d
     group by d.source_kind, d.category
    returning rows, bytes, id_to
  )
  select coalesce(sum(r.rows), 0), coalesce(sum(r.bytes), 0), coalesce(max(r.id_to), v_from)
    into v_deleted, v_bytes, v_to
    from rec r;

  return query select v_batch, v_deleted, v_bytes, v_from, v_to,
                      greatest(v_planned - v_done - v_deleted, 0);
end $$;
revoke all on function public.fn_kb_purge_batch(integer) from public, anon, authenticated;
comment on function public.fn_kb_purge_batch(integer) is
  'Deletes one id-ordered batch of kb_chunks rows that docs/KNOWLEDGE_DOCTRINE.md §6 classes DELETE (clause 5), skipping every id cited in sales_decision_log.cited (clause 2). Refuses without a census in kb_purge_ledger; records the batch there; resumable from max(id_to). Driven by scripts/kb/purge_kb_bulk.mjs.';

commit;

-- ── PROOF, AS A ROW (read-only; bounded to what the 2-minute API limit allows) ────────────────
-- §8 counts this checks against: reference DELETE 81,379 + 184,524 = 265,903 (this rule holds 39 of
-- them as clause 2/4, so 265,864); cert DELETE 75,466 exactly; the 14 cited chunk ids; and zero
-- clause-5 hits on every KEEP kind and on code/regulation/spec.
with cited as (
  select distinct split_part(x, ':', 2)::bigint as id
    from public.sales_decision_log s, unnest(s.cited) x where x ~ '^kb_chunks:[0-9]+$'
), m as (
  select
    -- reference (265,903 rows) is no longer counted here: with the US test added (instruction 535) the
    -- two regexes over it plus the rest no longer fit the 2-minute limit (measured: 57014 on 21 Sep).
    -- purge_kb_bulk.mjs counts every kind in its census, by kind and id slice, before any delete.
    null::bigint                                                                        as reference_delete,
    (select count(*) from public.kb_chunks k where k.source_kind = 'cert'
       and public.fn_kb_purge_clause(k.source_kind, k.category, k.citation) = 5)        as cert_delete,
    (select count(*) from public.kb_chunks k
      where k.source_kind in ('qd_kb_pack','company_faq','memory','generated','trade','material','document','library','code','regulation','spec')
        and public.fn_kb_purge_clause(k.source_kind, k.category, k.citation) = 5
        and not (k.source_kind in ('code','regulation','spec') and public.fn_kb_is_us_code(k.citation))) as keep_or_unsure_kinds_hit,
    (select count(*) from public.kb_chunks k where k.source_kind = 'code'
       and public.fn_kb_purge_clause(k.source_kind, k.category, k.citation) = 5)        as us_code_rows_deleted,
    (select count(*) from cited)                                                        as cited_ids,
    (select count(*) from public.kb_chunks k join cited c on c.id = k.id
      where public.fn_kb_purge_clause(k.source_kind, k.category, k.citation) = 5)       as cited_saved_by_clause_2,
    (select count(*) from public.kb_purge_ledger)                                       as ledger_rows,
    public.fn_kb_purge_clause('standard', 'x', 'DEWA Regulations 2017')                 as uae_is_3,
    public.fn_kb_purge_clause('standard', 'x', 'QD-KB-0001')                            as qd_is_1,
    public.fn_kb_purge_clause('textbook', 'x', 'NFPA 72 2019')                          as nfpa_is_5,
    public.fn_kb_purge_clause('code', 'x', 'US CFR Title 14')                           as us_law_is_5,
    public.fn_kb_purge_clause('code', 'x', 'NFPA 13 as adopted by UAE Civil Defence')   as uae_nfpa_is_3,
    public.fn_kb_purge_clause('code', 'x', 'BS EN 1992-1-1:2004 Eurocode 2')            as eurocode_is_4,
    public.fn_kb_purge_clause('regulation', 'x', 'DIFC Companies Law, DIFC Law No. 5 of 2018') as difc_is_3,
    public.fn_kb_purge_clause('reference', 'x', 'PostgreSQL 16 documentation')          as bulk_is_5
)
select case
  when m.cert_delete = 75466
   and m.keep_or_unsure_kinds_hit = 0 and m.cited_ids = 14
   and m.uae_is_3 = 3 and m.qd_is_1 = 1 and m.nfpa_is_5 = 5 and m.us_law_is_5 = 5 and m.bulk_is_5 = 5
   and m.uae_nfpa_is_3 = 3 and m.eurocode_is_4 = 4 and m.difc_is_3 = 3 and m.us_code_rows_deleted > 10000
  then 'PROBE OK' else 'PROBE FAILED' end
  || format(': reference_delete=%s (§8 265,903 before clause 2/4b) cert_delete=%s (§8 75,466) keep_or_unsure_kinds_hit=%s cited_ids=%s cited_saved_by_clause_2=%s ledger_rows=%s us_code_rows_deleted=%s unit=%s%s%s%s%s%s%s%s',
            m.reference_delete, m.cert_delete, m.keep_or_unsure_kinds_hit, m.cited_ids, m.cited_saved_by_clause_2, m.ledger_rows,
            m.us_code_rows_deleted, m.qd_is_1, m.uae_is_3, m.nfpa_is_5, m.us_law_is_5, m.bulk_is_5, m.uae_nfpa_is_3, m.eurocode_is_4, m.difc_is_3) as verdict
  from m;
