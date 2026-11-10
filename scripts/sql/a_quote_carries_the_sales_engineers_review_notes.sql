-- Seat: sales_engineer
-- a_quote_carries_the_sales_engineers_review_notes.sql — 10 Nov 2026, founder ledger 1588-1590.
--
-- THE FOUNDER (1588): when quotations arrive, the sales engineer reviews them as an expert and flags where a supplier
-- ignored part of the requested scope or deviated from a requirement (the customer asked for Italian origin and the
-- supplier quoted Chinese); these appear as NOTES on the quotations shared with the customer, in English and Arabic.
--
-- WHAT WAS MEASURED (10 Nov 2026, the schema mirror supabase/schema/full_schema/01_*.sql): public.quotes has no column
-- for such a note. quote_quality_hold.flags holds the hold desk's CODES for a quote held for missing details, and
-- fn_quote_spec_mismatches the routine class's judged cells; neither is a customer-facing review of a COMPLETE quote
-- against what the customer asked for, and neither carries both languages.
--
-- WHAT THIS CHANGES
--   1. quotes.review_notes (jsonb) and quotes.review_notes_at: the record of the notes the customer was shown, written by
--      supplier_api when a quote goes live (lib/quote_acceptance.ts storeReviewNotes). The notes themselves are computed
--      by code (supabase/functions/_shared/quote_review_notes.ts); my_inquiries, quote_compare and the quotation PDF
--      recompute them from the same rows, so this column is the record, never the only copy.
--   2. public.fn_quote_review_notes_are_valid(jsonb) and the CHECK quotes_review_notes_shape: a stored note names one of
--      the eleven codes, a severity, and carries BOTH an English and an Arabic sentence (the Arabic one in Arabic
--      letters). A rule that lives only in prose is broken; the founder's "EN and AR" is enforced here.
--
-- WHAT IT DOES NOT CHANGE: no row is written, nothing is backfilled (quotes holds 0 real rows pre-launch), no policy or
-- grant on quotes moves, and no existing trigger is touched. It does not decide whether a note is right — the code does,
-- and its corpus measures that (scripts/e2e/quote_review_corpus.mjs).
--
-- PENDING: committed, rehearsed on production rolled back (scripts/ci/rehearse_sql.mjs), NOT applied. See
-- scripts/sql/pending/a_quote_carries_the_sales_engineers_review_notes.txt. Until applied, storeReviewNotes' update is
-- refused by PostgREST (unknown column) and nothing else changes: the quote is live and every surface still shows notes.
--
-- prevented by: scripts/sql/a_quote_carries_the_sales_engineers_review_notes_probe.sql (the shape rule, both ways, and
-- anon/authenticated cannot execute), and supabase/functions/_shared/quote_review_notes.test.ts (every note the code
-- writes passes the same shape: both languages, a known code).

alter table public.quotes add column if not exists review_notes jsonb;
alter table public.quotes add column if not exists review_notes_at timestamp with time zone;
comment on column public.quotes.review_notes is
  'The sales engineer''s review of this quote against the request, as shown to the customer (EN + AR, no brand named). Written by supplier_api storeReviewNotes when the quote goes live; computed by supabase/functions/_shared/quote_review_notes.ts. Founder ledger 1588, 10 Nov 2026. Seat: sales_engineer.';
comment on column public.quotes.review_notes_at is 'When review_notes was last written. Seat: sales_engineer.';

create or replace function public.fn_quote_review_notes_are_valid(p_notes jsonb)
returns boolean
language plpgsql
immutable
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_note jsonb;
begin
  if p_notes is null then return true; end if;
  if jsonb_typeof(p_notes) <> 'array' then return false; end if;
  for v_note in select value from jsonb_array_elements(p_notes) loop
    if jsonb_typeof(v_note) <> 'object' then return false; end if;
    if coalesce(v_note->>'code', '') not in ('scope_missing', 'scope_excluded', 'origin_deviation', 'origin_not_stated', 'brand_match',
        'brand_alternative', 'brand_tier_lower', 'grade_lower', 'quantity_mismatch', 'lead_time_late', 'warranty_short') then return false; end if;
    if coalesce(v_note->>'severity', '') not in ('high', 'medium', 'info') then return false; end if;
    if length(btrim(coalesce(v_note->>'en', ''))) < 10 then return false; end if;
    -- the Arabic sentence is written in Arabic letters, not left in English
    if coalesce(v_note->>'ar', '') !~ '[ء-ي]' then return false; end if;
  end loop;
  return true;
end
$fn$;
comment on function public.fn_quote_review_notes_are_valid(jsonb) is
  'The shape of quotes.review_notes: an array of {code (one of eleven), severity (high|medium|info), en, ar (Arabic letters)}. Used by the CHECK quotes_review_notes_shape. Founder ledger 1588. Seat: sales_engineer.';
-- CREATE grants EXECUTE to PUBLIC; the CHECK runs as the writer, and only service_role writes quotes.
revoke execute on function public.fn_quote_review_notes_are_valid(jsonb) from public, anon, authenticated;
grant execute on function public.fn_quote_review_notes_are_valid(jsonb) to service_role;

alter table public.quotes drop constraint if exists quotes_review_notes_shape;
alter table public.quotes add constraint quotes_review_notes_shape check (public.fn_quote_review_notes_are_valid(review_notes));

-- VERDICT (a file with DDL returns a row; it never raises, which would roll its own DDL back).
select case
  when not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'quotes' and column_name = 'review_notes' and data_type = 'jsonb')
    then 'PROBE FAILED: quotes.review_notes is not a jsonb column'
  when not exists (select 1 from pg_constraint where conname = 'quotes_review_notes_shape' and conrelid = 'public.quotes'::regclass)
    then 'PROBE FAILED: the shape CHECK is missing'
  when not public.fn_quote_review_notes_are_valid('[{"code":"origin_deviation","severity":"high","en":"You asked for Italian origin; this quote states Chinese origin.","ar":"طلبت منشأً من إيطاليا، بينما يذكر هذا العرض أن المنشأ الصين."}]'::jsonb)
    then 'PROBE FAILED: a well-formed note is refused'
  when public.fn_quote_review_notes_are_valid('[{"code":"origin_deviation","severity":"high","en":"You asked for Italian origin; this quote states Chinese origin.","ar":"Italian vs Chinese"}]'::jsonb)
    then 'PROBE FAILED: a note with no Arabic is accepted'
  when has_function_privilege('anon', 'public.fn_quote_review_notes_are_valid(jsonb)', 'execute')
    then 'PROBE FAILED: anon can execute the shape routine'
  else 'PROBE OK'
end as verdict;
