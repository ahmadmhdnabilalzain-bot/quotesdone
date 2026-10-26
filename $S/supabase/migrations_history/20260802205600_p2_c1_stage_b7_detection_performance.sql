-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802205600   name: p2_c1_stage_b7_detection_performance
-- SHA-256 of the applied SQL: ee50e55d2080552eec1f9d4549a0d6a6ebfd3a9f263bb6cceae5742ac2fb5b59
-- Recovered by scripts/recover_one.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- P2-C1 STAGE B.7 (7/7) - PART 3: detection performance. No semantic change.
--
-- Measured cost of the party and supply detectors over the 54-case corpus in both languages:
-- mean interpretation 81.3 ms before Part 3, 106.2 ms after. A 31% increase on the interpretation
-- hot path is not something to discover in production later, so it is measured here and paid down
-- now rather than left as a note.
--
-- Where it went: fn_scope_party ran up to 58 regexp_instr calls per clause - twenty-nine party
-- markers, two roles each - and fn_scope_supply_attribution read four catalogue tables before it
-- had established that the clause contains a supply anchor at all. Both costs are paid on EVERY
-- clause, including the large majority that contain no party word and no supply word.
--
-- Two changes, both pure short-circuits:
--
--   1. A single permissive alternation over every party pattern is tested once. It has no word
--      boundaries and no morphology, so it matches strictly more text than any real party rule
--      can - if it does not match, no party marker can match either, and the function returns
--      without building a single per-marker regex.
--   2. The supply detector establishes the supply anchor first and reads the connector vocabulary
--      only afterwards, so a clause with no supply word costs two catalogue reads instead of four
--      plus a loop.
--
-- Neither changes which clauses match. The B.7 regression suite, the holdout and every prior suite
-- are re-run afterwards and must be identical, which is the only reason this is safe to do.

create or replace function public.fn_scope_party(p_clause_norm text)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare r record; v_re text; v_pos int;
        v_any text; v_conn_en text; v_conn_ar text;
        v_best jsonb := null; v_best_pos int := null;
begin
  if coalesce(btrim(p_clause_norm),'') = '' then
    return jsonb_build_object('identified', false); end if;

  -- Superset filter: no word boundaries and no affixes, so it accepts strictly more text than any
  -- real party rule can. The one thing it MUST keep is the optional Arabic article between the
  -- words of a multi-word pattern - `صاحب عمل` is written `صاحب العمل`, and a filter without it
  -- rejects a clause the rule would have matched. Being a superset is the whole safety argument;
  -- a filter that is only nearly a superset is a silent false negative.
  select string_agg(replace(pattern_norm,' ','[[:space:]]+(ال)?'), '|') into v_any
    from public.scope_marker where marker_type = 'party';
  if v_any is null or p_clause_norm !~ ('(' || v_any || ')') then
    return jsonb_build_object('identified', false); end if;

  select string_agg(replace(pattern_norm,' ','[[:space:]]+'), '|') into v_conn_en
    from public.scope_marker where marker_type = 'attribution' and lang = 'en';
  select string_agg(replace(pattern_norm,' ','[[:space:]]+'), '|') into v_conn_ar
    from public.scope_marker where marker_type = 'attribution' and lang = 'ar';

  for r in select pattern_norm, lang, party_class from public.scope_marker
            where marker_type = 'party' order by priority, length(pattern_norm) desc loop
    v_re := case when r.lang = 'en'
      then '(^|[^[:alnum:]])(' || v_conn_en || ')[[:space:]]+(the[[:space:]]+)?'
           || replace(r.pattern_norm,' ','[[:space:]]+') || '(s)?($|[^[:alnum:]])'
      else '(^|[^[:alnum:]])(' || v_conn_ar || ')[[:space:]]+(ال)?'
           || replace(r.pattern_norm,' ','[[:space:]]+(ال)?') || '(ات|ين|ون|ها|هم|ه)?($|[^[:alnum:]])'
    end;
    v_pos := coalesce(nullif(regexp_instr(p_clause_norm, v_re), 0), 0);
    if v_pos > 0 and (v_best_pos is null or v_pos < v_best_pos) then
      v_best := jsonb_build_object('identified', true, 'party', r.pattern_norm,
                                   'party_class', r.party_class, 'role', 'attributed');
      v_best_pos := v_pos;
    end if;
  end loop;
  if v_best is not null then return v_best; end if;

  for r in select pattern_norm, lang, party_class from public.scope_marker
            where marker_type = 'party' order by priority, length(pattern_norm) desc loop
    v_re := case when r.lang = 'en'
      then '(^|[^[:alnum:]])(the[[:space:]]+)?' || replace(r.pattern_norm,' ','[[:space:]]+')
           || '(s)?[[:space:]]+(is[[:space:]]+to|are[[:space:]]+to|to|will|shall|would|is[[:space:]]+responsible|are[[:space:]]+responsible)($|[^[:alnum:]])'
      else '(^|[^[:alnum:]])(ال)?' || replace(r.pattern_norm,' ','[[:space:]]+(ال)?')
           || '[[:space:]]+(سيقوم|يقوم|مسؤول|سوف|سيتولي|يتولي)($|[^[:alnum:]])'
    end;
    v_pos := coalesce(nullif(regexp_instr(p_clause_norm, v_re), 0), 0);
    if v_pos > 0 and (v_best_pos is null or v_pos < v_best_pos) then
      v_best := jsonb_build_object('identified', true, 'party', r.pattern_norm,
                                   'party_class', r.party_class, 'role', 'subject');
      v_best_pos := v_pos;
    end if;
  end loop;

  return coalesce(v_best, jsonb_build_object('identified', false));
end $fn$;

create or replace function public.fn_scope_supply_attribution(p_clause_norm text)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare r record; v_re text;
        v_sup_en text; v_sup_ar text; v_conn_en text; v_conn_ar text; v_party_any text;
        v_has_en boolean := false; v_has_ar boolean := false;
begin
  if coalesce(btrim(p_clause_norm),'') = '' then
    return jsonb_build_object('matched', false); end if;

  -- establish the supply anchor before reading anything else
  select string_agg(replace(pattern_norm,' ','[[:space:]]+'), '|') into v_sup_en
    from public.scope_marker where marker_type = 'supply_anchor' and lang = 'en';
  select string_agg(replace(pattern_norm,' ','[[:space:]]+'), '|') into v_sup_ar
    from public.scope_marker where marker_type = 'supply_anchor' and lang = 'ar';
  v_sup_ar := '(وال|بال|فال|كال|ال|لل|و|ف|ب|ك|ل)?(' || v_sup_ar || ')';
  v_has_en := p_clause_norm ~ ('(^|[^[:alnum:]])(' || v_sup_en || ')(es|s|d|ing)?($|[^[:alnum:]])');
  v_has_ar := p_clause_norm ~ ('(^|[^[:alnum:]])' || v_sup_ar || '(ات|ين|ون|ها|هم|ه)?($|[^[:alnum:]])');
  if not (v_has_en or v_has_ar) then return jsonb_build_object('matched', false); end if;

  -- and the counterparty before building any attribution regex
  select string_agg(replace(pattern_norm,' ','[[:space:]]+(ال)?'), '|') into v_party_any
    from public.scope_marker where marker_type = 'party' and party_class = 'counterparty';
  if v_party_any is null or p_clause_norm !~ ('(' || v_party_any || ')') then
    return jsonb_build_object('matched', false); end if;

  select string_agg(replace(pattern_norm,' ','[[:space:]]+'), '|') into v_conn_en
    from public.scope_marker where marker_type = 'attribution' and lang = 'en';
  select string_agg(replace(pattern_norm,' ','[[:space:]]+'), '|') into v_conn_ar
    from public.scope_marker where marker_type = 'attribution' and lang = 'ar';

  for r in select pattern_norm, lang, party_class from public.scope_marker
            where marker_type = 'party' and party_class = 'counterparty'
            order by priority, length(pattern_norm) desc loop
    if r.lang = 'en' and v_has_en then
      v_re := '(^|[^[:alnum:]])(' || v_conn_en || ')[[:space:]]+(the[[:space:]]+)?'
              || replace(r.pattern_norm,' ','[[:space:]]+') || '(s)?($|[^[:alnum:]])';
      if p_clause_norm ~ v_re then
        return jsonb_build_object('matched', true, 'party', r.pattern_norm,
                                  'party_class', r.party_class, 'role', 'attributed'); end if;
      v_re := '(^|[^[:alnum:]])(the[[:space:]]+)?' || replace(r.pattern_norm,' ','[[:space:]]+')
              || '(s)?[[:space:]]+(is[[:space:]]+to|are[[:space:]]+to|to|will|shall|would)[[:space:]]+(be[[:space:]]+)?('
              || v_sup_en || ')(es|s|d|ing)?($|[^[:alnum:]])';
      if p_clause_norm ~ v_re then
        return jsonb_build_object('matched', true, 'party', r.pattern_norm,
                                  'party_class', r.party_class, 'role', 'subject'); end if;
    elsif r.lang = 'ar' and v_has_ar then
      v_re := '(^|[^[:alnum:]])(' || v_conn_ar || ')[[:space:]]+(ال)?'
              || replace(r.pattern_norm,' ','[[:space:]]+(ال)?') || '(ات|ين|ون|ها|هم|ه)?($|[^[:alnum:]])';
      if p_clause_norm ~ v_re then
        return jsonb_build_object('matched', true, 'party', r.pattern_norm,
                                  'party_class', r.party_class, 'role', 'attributed'); end if;
      v_re := '(^|[^[:alnum:]])' || v_sup_ar || '(ات|ه)?[[:space:]]+(ال)?'
              || replace(r.pattern_norm,' ','[[:space:]]+(ال)?') || '($|[^[:alnum:]])';
      if p_clause_norm ~ v_re then
        return jsonb_build_object('matched', true, 'party', r.pattern_norm,
                                  'party_class', r.party_class, 'role', 'idafa'); end if;
      v_re := '(^|[^[:alnum:]])(ال)?' || replace(r.pattern_norm,' ','[[:space:]]+(ال)?')
              || '[[:space:]]+(سيقوم[[:space:]]+)?' || v_sup_ar || '($|[^[:alnum:]])';
      if p_clause_norm ~ v_re then
        return jsonb_build_object('matched', true, 'party', r.pattern_norm,
                                  'party_class', r.party_class, 'role', 'subject'); end if;
    end if;
  end loop;

  return jsonb_build_object('matched', false);
end $fn$;

comment on function public.fn_scope_party(text) is
  'The responsible party named in this clause, if any, with the role that binds it. `identified:false` is a positive finding: it is what makes removed scope `excluded` rather than `by_others`. Short-circuits on a boundary-free superset filter before building any per-marker regex.';
comment on function public.fn_scope_supply_attribution(text) is
  'True when this clause says material or equipment comes from the counterparty. Requires a supply anchor AND a counterparty bound to it by a connector, as the actor, or by Arabic genitive attachment. A third party in the same position gives by_others, never client_supplied. Establishes the anchor and the counterparty before building any attribution regex.';

revoke all on function public.fn_scope_party(text) from public, anon, authenticated;
revoke all on function public.fn_scope_supply_attribution(text) from public, anon, authenticated;

-- ---------------------------------------------------------------- the real cost, and the real fix
-- Arithmetic, not guesswork. Every clause runs fn_term_position once per marker: seven exception
-- markers, then every disposition marker until one matches, then the MEP and trade patterns.
-- Part 3 grew the disposition list from 72 patterns to 113, and 41/180 is 23% - which is the
-- latency increase, to within a millisecond.
--
-- Twenty-one of those additions are phrases the semantic rule already derives. `supply by client`
-- is a supply anchor plus a counterparty bound by a connector; `client to supply` is the same
-- counterparty as the actor; `توريد صاحب العمل` is the Arabic genitive form. Keeping them as
-- literals costs a regex on every clause in the system and re-creates exactly the phrase list
-- Part 3 exists to replace.
--
-- They are deleted. What stays is only what the rule genuinely cannot derive: forms with no
-- attribution grammar at all (`employer supplied`, `client supplied`, `free issue material`) and
-- the two Arabic enclitic forms (`يوفرها العميل`, `يوردها المالك`) whose morphology the genitive
-- rule does not reach. Those are complete statements standing on their own, not shorthand for a
-- rule. The suites re-run afterwards and must be identical - if any of these twenty-one changed an
-- outcome, the rule did not really cover it and the deletion is wrong.
delete from public.scope_marker
 where marker_type = 'disposition' and disposition = 'client_supplied'
   and pattern in ('supply by client','supply by the client','supplied by the owner',
     'supplied by the employer','supplied by the customer','client to supply','client will supply',
     'client shall supply','client to provide','client will provide','owner to supply',
     'employer to supply','customer to supply','free issue by the employer','free issue by the client',
     'free issued by the client','توريد صاحب العمل','توريد الزبون','العميل يورد','العميل يوفر',
     'من توريد العميل');
;