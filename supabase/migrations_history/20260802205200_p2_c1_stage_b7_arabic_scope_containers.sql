-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802205200   name: p2_c1_stage_b7_arabic_scope_containers
-- SHA-256 of the applied SQL: 8b342509a1c951359cecb9059e7f70d60837360f6303bb4886db91b98ffa1878
-- Recovered by scripts/recover_one.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- P2-C1 STAGE B.7 (3/6) - PART 3: Arabic scope and package modifiers.
--
-- English had two kinds of word doing one job. `complete`, `full`, `entire`, `whole`, `turnkey`
-- are COMPLETENESS modifiers - they say how much of something. `package` is a CONTAINER word - it
-- says the work is bundled, and on its own it says nothing at all about which trades. Both were
-- filed under scope_full, which worked only because fn_mep_full_scope demands an MEP anchor beside
-- them anyway.
--
-- Arabic had neither. حزمة كهروميكانيكية is exactly "MEP package", and it activated nothing,
-- because the Arabic vocabulary carried كامل and شامل but no container word at all. The English
-- reading of the same enquiry activated three trades; the Arabic reading activated none. That is
-- the worst kind of defect - the same customer gets a different company depending on which
-- language they wrote in.
--
-- The correction is the container class, in both languages, with the anchoring requirement made
-- explicit rather than incidental:
--
--   container word + MEP anchor, same clause  -> the three core trades
--   container word + trade name               -> that trade, and only through the trade name
--   container word alone                      -> NOTHING. Not a trade, not the core trio.
--
-- "حزمة أثاث كاملة" is a furniture package and must stay silent. So must "باقة مكتبية كاملة" and
-- "complete office package". The adjacency window is unchanged and still refuses to cross a
-- full stop, a semicolon or either comma, so a container word cannot reach an anchor in the next
-- clause.

alter table public.mep_trade_pattern drop constraint if exists mep_trade_pattern_kind_check;
alter table public.mep_trade_pattern add constraint mep_trade_pattern_kind_check
  check (kind in ('trade_name','trade_hint','mep_anchor','mep_full_phrase',
                  'scope_full','scope_container','scope_only'));

-- `package` was never a completeness word. Reclassified, not re-scoped: fn_mep_full_scope reads
-- both kinds, so English behaviour is unchanged and the twelve scope negatives prove it.
update public.mep_trade_pattern set kind = 'scope_container'
 where kind = 'scope_full' and pattern in ('package');

insert into public.mep_trade_pattern (trade_key, kind, pattern, lang) values
  (null,'scope_container','bundle','en'),
  (null,'scope_container','حزمه','ar'),
  (null,'scope_container','باقه','ar'),
  (null,'scope_container','طقم','ar'),
  (null,'scope_container','مجموعه','ar'),
  (null,'scope_full','متكامله','ar'),
  (null,'scope_full','متكامل','ar'),
  (null,'scope_full','تسليم مفتاح','ar')
on conflict (kind, pattern, lang) do nothing;

create or replace function public.fn_mep_full_scope(p_text_norm text)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare r record; v_re text; v_sep text := '[^[:alnum:].;,،؛' || chr(10) || ']+';
begin
  for r in select pattern_norm, lang from public.mep_trade_pattern where kind = 'mep_full_phrase' loop
    if public.fn_term_matches(p_text_norm, r.pattern_norm, r.lang) then
      return jsonb_build_object('matched', true, 'basis', 'explicit_full_mep_phrase',
                                'anchor', r.pattern_norm, 'modifier', null, 'modifier_kind', null);
    end if;
  end loop;

  for r in
    select a.pattern_norm as anchor, m.pattern_norm as modifier, m.kind as modifier_kind, a.lang
      from public.mep_trade_pattern a
      join public.mep_trade_pattern m on m.kind in ('scope_full','scope_container')
     where a.kind = 'mep_anchor'
  loop
    v_re := '(^|[^[:alnum:]])' || r.anchor || '(' || v_sep || '[[:alnum:]]+){0,2}' || v_sep
            || r.modifier || '($|[^[:alnum:]])';
    if p_text_norm ~ v_re then
      return jsonb_build_object('matched', true, 'basis', 'anchor_plus_modifier',
                                'anchor', r.anchor, 'modifier', r.modifier,
                                'modifier_kind', r.modifier_kind);
    end if;
    v_re := '(^|[^[:alnum:]])' || r.modifier || '(' || v_sep || '[[:alnum:]]+){0,2}' || v_sep
            || r.anchor || '($|[^[:alnum:]])';
    if p_text_norm ~ v_re then
      return jsonb_build_object('matched', true, 'basis', 'modifier_plus_anchor',
                                'anchor', r.anchor, 'modifier', r.modifier,
                                'modifier_kind', r.modifier_kind);
    end if;
  end loop;

  return jsonb_build_object('matched', false, 'basis', null);
end $fn$;

comment on function public.fn_mep_full_scope(text) is
  'The only path by which a completeness modifier (full, complete, كامل) or a container word (package, حزمة) reaches the three core trades. The modifier must sit within two words of an MEP anchor in the same clause, or the text must carry an explicit full-MEP phrase. A modifier with no anchor beside it activates nothing in either language.';
;