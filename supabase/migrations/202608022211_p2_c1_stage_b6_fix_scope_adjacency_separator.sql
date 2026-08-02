-- P2-C1 STAGE B.6 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802182423   name: p2_c1_stage_b6_fix_scope_adjacency_separator
-- SHA-256 of the applied SQL: 179c9b90ce342fcf6b752bfa486f9f6e930e0a7490635ef3299dc83202418a68
-- Recovered by scripts/recover_stage_b6.mjs. The body below is byte-for-byte as applied;
-- only this header was added, and it is excluded from the checksum.

-- DEFECT found by frozen holdout case m04. The Stage B.5 adjacency rule was supposed to stop a
-- full-scope modifier reaching an MEP anchor across a clause boundary. It excluded '.' ';' ',' from
-- the intervening WORDS but not from the SEPARATORS, so with zero intervening words
-- "The building is complete. MEP works required." matched `complete` + separator ". " + `mep` and
-- activated all three core trades. That is the exact false positive B.5 claimed to have closed.
--
-- This is a defect fix, not a fit to the holdout: the rule's stated intent was already "in the same
-- clause", and the regex did not implement it.

create or replace function public.fn_mep_full_scope(p_text_norm text)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare r record; v_re text; v_sep text := '[^[:alnum:].;,،؛' || chr(10) || ']+';
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
    v_re := '(^|[^[:alnum:]])' || r.anchor || '(' || v_sep || '[[:alnum:]]+){0,2}' || v_sep
            || r.modifier || '($|[^[:alnum:]])';
    if p_text_norm ~ v_re then
      return jsonb_build_object('matched', true, 'basis', 'anchor_plus_modifier',
                                'anchor', r.anchor, 'modifier', r.modifier);
    end if;
    v_re := '(^|[^[:alnum:]])' || r.modifier || '(' || v_sep || '[[:alnum:]]+){0,2}' || v_sep
            || r.anchor || '($|[^[:alnum:]])';
    if p_text_norm ~ v_re then
      return jsonb_build_object('matched', true, 'basis', 'modifier_plus_anchor',
                                'anchor', r.anchor, 'modifier', r.modifier);
    end if;
  end loop;

  return jsonb_build_object('matched', false, 'basis', null);
end $fn$;
;