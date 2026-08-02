-- P2-C1 STAGE B.6 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802181932   name: p2_c1_stage_b6_fix_arabic_internal_definite_article
-- SHA-256 of the applied SQL: 41bff6141f4f177e700f761874a578800cf33bbff0957fd0bde28f33d6be4196
-- Recovered by scripts/recover_stage_b6.mjs. The body below is byte-for-byte as applied;
-- only this header was added, and it is excluded from the checksum.

-- DEFECT: Arabic proclitic tolerance was applied only to the FIRST word of a pattern. So
-- كاميرات مراقبه matched "كاميرات مراقبة" but not "كاميرات المراقبة", and تيار خفيف did not match
-- "التيار الخفيف" - the definite article on the SECOND word broke the phrase.
--
-- Arabic attaches ال to any noun in a phrase, so a multi-word pattern must tolerate it at every
-- word boundary, not just the front. Found by the Arabic half of the disposition tests
-- (d05, d06, d08 all failed for this one reason). A morphology rule, not a threshold.

create or replace function public.fn_term_matches(
  p_text_norm text, p_pattern_norm text, p_lang text default 'en')
returns boolean language sql immutable as $fn$
  select case when p_lang = 'ar'
    then p_text_norm ~ ('(^|[^[:alnum:]])(وال|بال|فال|كال|ال|لل|و|ف|ب|ك|ل)?'
                        || replace(p_pattern_norm, ' ', '[[:space:]]+(ال)?')
                        || '(ات|ين|ون|ها|هم|ه)?($|[^[:alnum:]])')
    else p_text_norm ~ ('(^|[^[:alnum:]])' || p_pattern_norm || '(es|s)?($|[^[:alnum:]])')
  end;
$fn$;

comment on function public.fn_term_matches(text, text, text) is
  'Word-boundary matching with light morphology on both sides. English tolerates a trailing s/es. Arabic tolerates the common proclitics, the enclitics, AND the definite article on every word of a multi-word phrase - because that is how Arabic phrases are actually written. Never substring matching.';
;