-- A SUPPLIER'S DOCUMENTS NAME TRADES BY EXACT CODE OR BY MEANING, NEVER BY THEIR WORDS.
-- Seat: sales_engineer. 29 Sep 2026, founder ledger 1054 (round 3 of 1018), against ruling 890.
--
-- supabase/functions/_shared/trade_words.ts proposed a supplier's trades from the aliases its documents
-- contained - the TypeScript twin of the word matcher #893 removed from fn_norm_trades on 23 Sep 2026. It is
-- replaced by supabase/functions/_shared/trade_resolve.ts: a line that IS a live code or intake slug resolves
-- exactly, and anything else is read by meaning over the stored service vectors. The exact path must be decided
-- by fn_norm_trades itself, not by a TypeScript copy of it, and a document has hundreds of lines; this routine
-- asks fn_norm_trades about many phrases in one call and returns only the ones that resolve.
--
-- MEASURED BEFORE THIS FILE (production, 29 Sep 2026, read-only): fn_norm_trades('HVAC') = {hvac},
-- fn_norm_trades('We do HVAC works') = NULL, fn_norm_trades('Fit-Out') = NULL (the slug is 'fitout');
-- 229 active codes, 31 intake slugs; 1,047 active services, every one with a stored gte-small vector.
--
-- Pending: scripts/sql/pending/a_suppliers_documents_name_trades_by_exact_code_or_meaning_never_by_words.txt.
-- Proved by scripts/checks/a_suppliers_documents_name_trades_by_exact_code_or_meaning_never_by_words.test.mjs.

create or replace function public.fn_norm_trades_many(p_texts text[])
returns jsonb
language sql
stable
set search_path to 'public', 'pg_temp'
as $fn$
  -- phrase -> the codes fn_norm_trades resolves it to; a phrase that resolves to nothing is left out.
  -- ponytail: 400 phrases per call is the caller's cap (trade_resolve.ts EXACT_MAX_PHRASES).
  select coalesce(jsonb_object_agg(x.t, to_jsonb(x.codes)), '{}'::jsonb)
    from (select distinct u.t, public.fn_norm_trades(u.t) as codes
            from unnest(coalesce(p_texts, '{}'::text[])) u(t)
           where nullif(btrim(u.t), '') is not null) x
   where x.codes is not null;
$fn$;
revoke execute on function public.fn_norm_trades_many(text[]) from public, anon, authenticated;
grant execute on function public.fn_norm_trades_many(text[]) to service_role;

-- Verdict row (DDL file, so no raise): a code and a slug resolve, a sentence and a near spelling do not.
select case
  when public.fn_norm_trades_many(array['HVAC', 'Carpentry', 'We do HVAC works', 'Fit-Out', '']) = public.fn_norm_trades_many(array['HVAC', 'Carpentry'])
   and public.fn_norm_trades_many(array['HVAC']) ? 'HVAC'
   and not (public.fn_norm_trades_many(array['We do HVAC works']) ? 'We do HVAC works')
  then 'PROBE OK fn_norm_trades_many: ' || public.fn_norm_trades_many(array['HVAC', 'Carpentry', 'We do HVAC works', 'Fit-Out'])::text
  else 'PROBE FAILED: fn_norm_trades_many resolved a sentence or missed an exact code' end as verdict;
