-- Four thousand suppliers, and the first five hundred were lost to a hyphen
-- =========================================================================
--
-- The brief put this as a decision to make and not to ask about: "~4,000 leads still match no
-- trade even at 40 trades - in_vocab 16,444 of 20,470. Either the taxonomy grows again or those
-- suppliers are out of scope."
--
-- Measured, it is neither. Of the 4,026 leads with no trade:
--
--     general             3,104     no sector at all
--     building-materials    514     a trade that HAS existed since the taxonomy was created
--     contractor            146     too generic to route without guessing
--     safety                 69     safety_equipment exists
--     events / garments / catering / visa-pro-services   71   genuinely out of scope
--     security 37 · printing 31 · acrylic 25 · movers 25 · pool 3 · fencing 1
--
-- fn_norm_trades matches taxonomy_trade.aliases against the text with a word-boundary regex, and
-- building_materials has carried the alias 'building materials' the whole time. The scraper writes
-- its sector as a HYPHENATED SLUG. So:
--
--     fn_norm_trades('building materials')  ->  {building_materials}
--     fn_norm_trades('building-materials')  ->  {}
--
-- Five hundred and fourteen suppliers were outside the matcher's vocabulary because of one
-- character. \m is a word boundary and '-' is not a word character, so 'building' and 'materials'
-- are two words with a boundary between them and the two-word alias cannot span it.
--
-- THE DECISION, since it was asked for: the taxonomy does NOT grow. It already names every trade
-- this marketplace serves, and 25 -> 40 yesterday was the growth this needed. What was wrong is the
-- INPUT normalisation, and that is fixed here by treating hyphens, underscores, slashes and dots as
-- the word separators they are in a slug.
--
-- The aliases are deliberately NOT loosened to bare words. 'safety', 'security' and 'printing' as
-- single-word aliases would match any company with those words in its name, and invite_trades is
-- what decides who receives a cold approach - a false trade there sends a fire-safety firm an
-- invitation to quote for PPE. Those sectors stay unmatched until a supplier states its own scope,
-- which is exactly what the confirmation screen shipped this morning is for. 'contractor' likewise
-- stays unmatched: a contractor with no other signal could be any of the forty, and guessing which
-- is worse than admitting we do not know.
--
-- events, garments, catering and visa-pro-services (71 leads) are out of scope for a construction
-- and MEP quotation marketplace. They stay in the directory and simply never receive a
-- trade-targeted invitation, which enqueue_supplier_invites already handles: its '~none' bucket is
-- ordered last and the comment there reads "never spend the cap on a lead whose trade we do not
-- know". Nothing needs deleting.

create or replace function public.fn_norm_trades(p_text text)
returns text[]
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  -- SLUG SEPARATORS ARE WORD SEPARATORS (12 Aug 2026). The scraper writes sector as
  -- 'building-materials'; every multi-word alias in taxonomy_trade is written with spaces. \m is a
  -- word boundary, '-' is not a word character, so a two-word alias can never span the hyphen and
  -- 514 leads sat outside the vocabulary over one character. Normalising the INPUT rather than
  -- rewriting 40 trades' aliases into every punctuation variant they might arrive in.
  select coalesce(array_agg(distinct t.code order by t.code), '{}')
  from public.taxonomy_trade t
  where t.active
    and exists (
      select 1 from unnest(t.aliases || t.code) a
      where length(a) >= 3
        and regexp_replace(coalesce(p_text,''), '[-_/.]+', ' ', 'g')
            ~* ('\m' || regexp_replace(a, '([.*+?^${}()|\[\]\\])', '\\\1', 'g'))
    );
$function$;
