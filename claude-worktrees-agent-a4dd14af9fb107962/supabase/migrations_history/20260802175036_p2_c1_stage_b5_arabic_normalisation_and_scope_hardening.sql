-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802175036   name: p2_c1_stage_b5_arabic_normalisation_and_scope_hardening
-- SHA-256 of the applied SQL: 2089bfe20a015cfb589b0424e252a63b9ae638dfd740d3a50b1a61047df02340
-- Recovered by scripts/recover_stage_a_b_b5.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- P2-C1 STAGE B.5 (2/5) - Arabic normalisation, prefix-tolerant matching, hardened scope rule.
--
-- THREE DEFECTS FOUND AND CORRECTED. None is a threshold; all three are rules or aliases.
--
-- (a) Arabic definite article. The matcher required a non-alphanumeric boundary, so the pattern
--     سباكة did not match أعمال السباكة - the ال prefix is alphanumeric. Every Arabic noun in a
--     real sentence carries a proclitic (ال، وال، بال، لل، و، ف، ب، ك، ل), so the Arabic patterns
--     matched almost nothing outside a bare keyword list.
-- (b) Orthographic variants. كهربائيه vs كهربائية, إطفاء vs اطفاء. Same word, two typists.
-- (c) The scope rule fired across a sentence boundary: "Full fit-out of offices. MEP coordination
--     by others." matched `full` and `mep` anywhere and would have activated all three core trades.

create or replace function public.fn_norm_text(p_text text)
returns text language sql immutable as $fn$
  select translate(
           regexp_replace(
             lower(btrim(regexp_replace(coalesce(p_text,''), '\s+', ' ', 'g'))),
             '[ًٌٍَُِّْـٰ]', '', 'g'),
           'أإآٱىة', 'اااايه');
$fn$;

comment on function public.fn_norm_text(text) is
  'Lower-cases, collapses whitespace, strips Arabic diacritics and tatweel, folds alef forms (أإآٱ→ا), alef maqsura (ى→ي) and ta marbuta (ة→ه). Applied to both sides of every comparison. Harmless on Latin text.';

create or replace function public.fn_term_matches(
  p_text_norm text, p_pattern_norm text, p_lang text default 'en')
returns boolean language sql immutable as $fn$
  select case when p_lang = 'ar'
    then p_text_norm ~ ('(^|[^[:alnum:]])(وال|بال|فال|كال|ال|لل|و|ف|ب|ك|ل)?'
                        || p_pattern_norm || '(ات|ين|ون|ها|هم|ه)?($|[^[:alnum:]])')
    else p_text_norm ~ ('(^|[^[:alnum:]])' || p_pattern_norm || '($|[^[:alnum:]])')
  end;
$fn$;

create or replace function public.fn_text_matches_pattern(p_text text, p_pattern text)
returns boolean language sql immutable as $fn$
  select public.fn_term_matches(public.fn_norm_text(p_text), public.fn_norm_text(p_pattern), 'en');
$fn$;

-- Drop the old constraint FIRST, then reclassify, then tighten.
alter table public.mep_trade_pattern drop constraint if exists mep_trade_pattern_kind_check;

update public.mep_trade_pattern set kind = 'mep_anchor' where kind = 'umbrella';
delete from public.mep_trade_pattern where kind = 'scope_full' and pattern in ('all trades','all disciplines');

insert into public.mep_trade_pattern (trade_key, kind, pattern, lang) values
  (null,'mep_full_phrase','mep package','en'),
  (null,'mep_full_phrase','full mep','en'),
  (null,'mep_full_phrase','complete mep','en'),
  (null,'mep_full_phrase','entire mep','en'),
  (null,'mep_full_phrase','whole mep','en'),
  (null,'mep_full_phrase','turnkey mep','en'),
  (null,'mep_full_phrase','full electromechanical','en'),
  (null,'mep_full_phrase','complete electromechanical','en'),
  (null,'mep_anchor','mep works','en'),
  (null,'mep_anchor','كهروميكانيكي','ar'),
  (null,'mep_anchor','كهروميكانيكيه','ar'),
  (null,'mep_full_phrase','اعمال كهروميكانيكيه كامله','ar'),
  (null,'scope_full','كامله','ar'),
  (null,'scope_full','شامله','ar'),
  (null,'scope_full','بالكامل','ar'),
  ('hvac','trade_name','تكييف','ar'), ('hvac','trade_name','مكيف','ar'),
  ('hvac','trade_name','تبريد','ar'), ('hvac','trade_name','تهويه','ar'),
  ('hvac','trade_name','تكييف مركزي','ar'),
  ('electrical','trade_name','كهربائيه','ar'), ('electrical','trade_name','كهربائي','ar'),
  ('electrical','trade_name','لوحات كهربائيه','ar'), ('electrical','trade_name','تمديدات كهربائيه','ar'),
  ('plumbing','trade_name','سباكه','ar'), ('plumbing','trade_name','صحيه','ar'),
  ('plumbing','trade_name','صرف صحي','ar'), ('plumbing','trade_name','ادوات صحيه','ar'),
  ('fire','trade_name','مكافحه الحريق','ar'), ('fire','trade_name','انذار الحريق','ar'),
  ('fire','trade_name','اطفاء','ar'), ('fire','trade_name','رشاشات','ar'),
  ('elv','trade_name','تيار خفيف','ar'), ('elv','trade_name','انظمه امنيه','ar'),
  ('elv','trade_name','كاميرات مراقبه','ar')
on conflict (kind, pattern, lang) do nothing;

alter table public.mep_trade_pattern add constraint mep_trade_pattern_kind_check
  check (kind in ('trade_name','mep_anchor','mep_full_phrase','scope_full','scope_only'));

alter table public.mep_trade_pattern add column if not exists pattern_norm text;
update public.mep_trade_pattern set pattern_norm = public.fn_norm_text(pattern);
alter table public.mep_trade_pattern alter column pattern_norm set not null;

create or replace function public.fn_mep_full_scope(p_text_norm text)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare r record; v_re text;
begin
  for r in select pattern_norm, lang from public.mep_trade_pattern where kind = 'mep_full_phrase' loop
    if public.fn_term_matches(p_text_norm, r.pattern_norm, r.lang) then
      return jsonb_build_object('matched', true, 'basis', 'explicit_full_mep_phrase',
                                'anchor', r.pattern_norm, 'modifier', null);
    end if;
  end loop;

  for r in
    select a.pattern_norm as anchor, m.pattern_norm as modifier, a.lang
      from public.mep_trade_pattern a
      join public.mep_trade_pattern m on m.kind = 'scope_full'
     where a.kind = 'mep_anchor'
  loop
    v_re := '(^|[^[:alnum:]])' || r.anchor || '([^[:alnum:]]+[^[:space:].;،؛]+){0,2}[^[:alnum:]]+'
            || r.modifier || '($|[^[:alnum:]])';
    if p_text_norm ~ v_re then
      return jsonb_build_object('matched', true, 'basis', 'anchor_plus_modifier',
                                'anchor', r.anchor, 'modifier', r.modifier);
    end if;
    v_re := '(^|[^[:alnum:]])' || r.modifier || '([^[:alnum:]]+[^[:space:].;،؛]+){0,2}[^[:alnum:]]+'
            || r.anchor || '($|[^[:alnum:]])';
    if p_text_norm ~ v_re then
      return jsonb_build_object('matched', true, 'basis', 'modifier_plus_anchor',
                                'anchor', r.anchor, 'modifier', r.modifier);
    end if;
  end loop;

  return jsonb_build_object('matched', false, 'basis', null);
end $fn$;

comment on function public.fn_mep_full_scope(text) is
  'The only path by which generic words like full/complete/package reach the three core trades. They must sit within two words of an MEP anchor in the same clause, or the text must carry an explicit full-MEP phrase.';

revoke all on function public.fn_norm_text(text) from public, anon, authenticated;
revoke all on function public.fn_term_matches(text, text, text) from public, anon, authenticated;
revoke all on function public.fn_mep_full_scope(text) from public, anon, authenticated;
;