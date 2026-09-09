-- THE SAME QUESTION IN ARABIC GETS THE SAME ANSWER.
--
-- The founder, 9 September 2026: "Arabic is needed for everyone, and you need to work on that as
-- well."
--
-- MEASURED OVER HTTP AGAINST THE LIVE ENDPOINT, 10 September 2026, minutes after the English price
-- answer started working:
--
--   EN  "what should a gypsum false ceiling cost per square metre in Dubai"
--       -> four AED bands, sourced, dated 28 June 2026
--   AR  "كم تكلفة السقف الجبسي المستعار للمتر المربع في دبي"   (the same question)
--       -> "I do not have a sourced answer to that yet, and I will not guess at it."
--
-- Same question, same trade, same rows sitting in price_benchmark. The Arabic speaker got nothing.
--
-- WHY, precisely: fn_price_guidance reduced the question to words with
-- `regexp_split_to_table(lower(q), '[^a-z0-9]+')`. That character class keeps latin letters and
-- digits and discards everything else, so an Arabic sentence reduces to the EMPTY SET and the
-- routine returned 'no_substantive_terms'. It was not a weak Arabic match. There was no Arabic path
-- at all, and the refusal it produced was indistinguishable from an honest "we do not hold this".
--
-- AND THE TRADE NAMES ARE ENGLISH SLUGS. Even with correct tokenising there is nothing for an
-- Arabic word to match: price_benchmark.category holds 'gypsum', 'hvac', 'marble-granite'. Arabic
-- retrieval needs a vocabulary, and the estate did not have one -- mep_trade carries five labelled
-- trades (hvac, electrical, plumbing, fire, elv) and none of the fifty-two that carry prices.
--
-- WHAT THIS FILE ADDS
--
-- 1. public.price_trade_term -- a term lexicon. Each row maps a phrase a real person might type, in
--    Arabic or English, to one of the trades that actually holds price rows. It also carries an
--    optional item_hint: an English word to use when picking WHICH bands to show, so that an Arabic
--    question about a ceiling gets the ceiling bands rather than every gypsum band. Without that,
--    an Arabic answer would always be trade-level while the English one was item-level, which is
--    the same inequality one layer down.
--
-- 2. Matching by SUBSTRING over the normalised question rather than by token, because the useful
--    Arabic phrases are multi-word -- "سقف مستعار" (false ceiling), "تنسيق حدائق" (landscaping),
--    "نقل عفش" (furniture moving). A tokeniser splits those into halves that mean other things.
--
-- 3. fn_ar_norm, which the estate already has and which the widget's own corpus search already
--    uses, applied to BOTH sides of the comparison so that alef and ta-marbuta spelling variants do
--    not decide whether a customer gets an answer.
--
-- A NOTE ON WHAT IS DELIBERATELY NOT HERE: no translation of the item names themselves. The bands
-- come back with their English item labels ("Plain gypsum ceiling (per sqm)") because that is the
-- text the evidence is filed under and mistranslating a priced line item is worse than showing it
-- in English next to an Arabic sentence. The surrounding answer is Arabic; the sourced label is not
-- invented.

create table if not exists public.price_trade_term (
  term       text primary key,
  category   text not null,
  lang       text not null default 'ar',
  item_hint  text,
  note       text,
  created_at timestamptz not null default now()
);

-- A NEW TABLE NEEDS AN EXPLICIT POLICY, not just RLS on. RLS enabled with no policy denies everyone,
-- which is the same end state -- but it is indistinguishable from somebody meaning to write a policy
-- and forgetting. service_role bypasses RLS, so the seats keep full access; this says "service-role
-- only, on purpose" in the schema instead of in someone's memory.
alter table public.price_trade_term enable row level security;
drop policy if exists price_trade_term_service_role_only on public.price_trade_term;
create policy price_trade_term_service_role_only on public.price_trade_term
  as permissive for all to public using (false) with check (false);
revoke all on public.price_trade_term from anon, authenticated;

insert into public.price_trade_term (term, category, lang, item_hint) values
  -- gypsum / false ceilings. 'سقف' alone maps here because the ceiling bands live in this trade.
  ('جبس','gypsum','ar',null), ('جبسي','gypsum','ar',null), ('جبسوم','gypsum','ar',null),
  ('سقف مستعار','gypsum','ar','ceiling'), ('اسقف مستعارة','gypsum','ar','ceiling'),
  ('سقف','gypsum','ar','ceiling'), ('اسقف','gypsum','ar','ceiling'),
  ('false ceiling','gypsum','en','ceiling'), ('drywall','gypsum','en',null),
  ('تكييف','hvac','ar',null), ('مكيف','hvac','ar',null), ('تبريد','hvac','ar',null),
  ('تهوية','hvac','ar',null), ('air conditioning','hvac','en',null),
  ('ارضيات','flooring','ar',null), ('ارضية','flooring','ar',null), ('باركيه','flooring','ar',null),
  ('بلاط','tiling','ar',null), ('سيراميك','tiling','ar',null), ('تبليط','tiling','ar',null),
  ('رخام','marble-granite','ar',null), ('جرانيت','marble-granite','ar',null),
  ('دهان','painting','ar',null), ('دهانات','painting','ar',null), ('طلاء','painting','ar',null),
  ('صباغة','painting','ar',null),
  ('تصميم داخلي','interior-design','ar',null), ('ديكور','interior-design','ar',null),
  ('مسبح','swimming-pools','ar',null), ('مسابح','swimming-pools','ar',null),
  ('حمام سباحة','swimming-pools','ar',null),
  ('تشطيب','fitout','ar',null), ('تشطيبات','fitout','ar',null), ('تجهيز محل','fitout','ar',null),
  ('اثاث','custom-furniture','ar',null), ('موبيليا','custom-furniture','ar',null),
  ('تنسيق حدائق','landscaping','ar',null), ('حدائق','landscaping','ar',null), ('حديقة','landscaping','ar',null),
  ('عزل مائي','waterproofing','ar',null), ('عزل','waterproofing','ar',null),
  ('عزل حراري','insulation','ar',null),
  ('زجاج','glass','ar',null), ('سيكوريت','glass','ar',null),
  ('المنيوم','aluminium','ar',null), ('الومنيوم','aluminium','ar',null),
  ('تنظيف','cleaning','ar',null), ('نظافة','cleaning','ar',null),
  ('تنظيف واجهات','facade-cleaning','ar',null), ('واجهات','facade-cleaning','ar',null),
  ('طاقة شمسية','solar','ar',null), ('الواح شمسية','solar','ar',null), ('شمسية','solar','ar',null),
  ('لافتات','signage','ar',null), ('يافطة','signage','ar',null), ('لوحات اعلانية','signage','ar',null),
  ('نقل اثاث','movers','ar',null), ('نقل عفش','movers','ar',null),
  ('كاميرات مراقبة','security','ar',null), ('مراقبة','security','ar',null), ('انذار','security','ar',null),
  ('ايبوكسي','epoxy-flooring','ar',null),
  ('ستائر','blinds-curtains','ar',null), ('ستارة','blinds-curtains','ar',null),
  ('نجارة','carpentry-joinery','ar',null), ('نجار','carpentry-joinery','ar',null),
  ('مكافحة حشرات','pest','ar',null), ('حشرات','pest','ar',null), ('رش مبيدات','pest','ar',null),
  ('سباكة','plumbing','ar',null), ('سباك','plumbing','ar',null),
  ('ورق جدران','wallpaper','ar',null), ('ورق حائط','wallpaper','ar',null),
  ('مطابخ','kitchens','ar',null), ('مطبخ','kitchens','ar',null),
  ('سجاد','carpets','ar',null), ('موكيت','carpets','ar',null),
  ('حديد','structural-steel-fabrication','ar',null), ('هيكل حديدي','structural-steel-fabrication','ar',null),
  ('مظلات','tents-and-shade-structures','ar',null), ('سواتر','tents-and-shade-structures','ar',null),
  ('خيام','tents-and-shade-structures','ar',null),
  ('اطفاء','safety','ar',null), ('سلامة','safety','ar',null), ('حريق','safety','ar',null),
  ('كهرباء','electrical','ar',null), ('كهربائي','electrical','ar',null),
  ('مقاولات','general-building-contracting','ar',null), ('بناء','general-building-contracting','ar',null),
  ('اسطح','roofing','ar',null), ('سقالات','scaffolding','ar',null), ('هدم','demolition','ar',null),
  ('تنجيد','upholstery','ar',null), ('ابواب جراج','garage-doors','ar',null),
  ('مولدات','generators','ar',null), ('مولد كهرباء','generators','ar',null),
  ('شبكات','it-networking','ar',null), ('منزل ذكي','smart-home','ar',null),
  ('انظمة صوت','av-systems','ar',null),
  -- THE FOUR TRADES THAT HOLD NO PRICE AT ALL still need Arabic terms, and it is easy to leave them
  -- out because the lexicon was seeded from the trades that HAVE rows. Measured over HTTP: the
  -- Arabic elevator question came back 'no_substantive_terms' — the generic "I have no sourced
  -- answer" — while the English one returned the recorded gap and its reason. A deliberate gap is
  -- the more useful answer of the two: it says we chose not to publish a figure rather than that we
  -- did not understand the question, and it is exactly the distinction those gap rows exist to keep.
  ('مصعد','elevators','ar',null), ('مصاعد','elevators','ar',null), ('اسانسير','elevators','ar',null),
  ('خزان مياه','water-tank-cleaning','ar',null), ('تنظيف خزانات','water-tank-cleaning','ar',null),
  ('استشارات هندسية','engineering-and-architectural-consultancies','ar',null),
  ('مكتب هندسي','engineering-and-architectural-consultancies','ar',null),
  ('كهروميكانيك','combined-mep','ar',null)
on conflict (term) do update
  set category = excluded.category, item_hint = excluded.item_hint, lang = excluded.lang;

-- ── THE ROUTINE, NOW BILINGUAL ──────────────────────────────────────────────────────────────────
-- Everything the English path already did is unchanged, including the ten-to-one weighting of a
-- trade-name match over an item-text match (which the probe in the sibling file caught paying for
-- itself when "elevator installation" resolved to FLOORING). The lexicon is consulted FIRST and
-- scores like a trade-name match, because a person naming their trade in Arabic is being at least
-- as specific as one naming it in English.
create or replace function public.fn_price_guidance(p_question text, p_limit int default 6)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_q         text;
  v_terms     text[];
  v_cat       text;
  v_gap       text;
  v_items     jsonb;
  v_hit       boolean;
  v_matched   text[];
  v_unmatched text[];
  v_hints     text[];
  v_lex       text[];
begin
  -- THE DEFINITE ARTICLE IS STRIPPED FROM BOTH SIDES, and the probe below is why. A person does not
  -- write "عزل حراري", they write "العزل الحراري" -- the article attaches to each word. So the
  -- two-word lexicon term is NOT a substring of the sentence, while the bare "عزل" still is, and
  -- the first version of this file answered a thermal-insulation question with WATERPROOFING rates.
  -- Removing "ال" at word starts on the question and on the term makes the comparison fair; doing it
  -- on only one side would just move the failure.
  v_q := regexp_replace(public.fn_ar_norm(lower(coalesce(p_question, ''))),
                        '(^|[[:space:]])ال', '\1', 'g');

  -- LATIN WORDS, as before: four characters is the floor, and the words that make it a price
  -- question rather than a gypsum question are dropped explicitly.
  select array_agg(distinct t)
    into v_terms
    from regexp_split_to_table(lower(coalesce(p_question, '')), '[^a-z0-9]+') as t
   where length(t) >= 4
     and t not in ('what','cost','costs','much','price','prices','pricing','should','would','does',
                   'about','around','many','rate','rates','average','typical','range','dubai','uae',
                   'emirates','abu','dhabi','sharjah','from','with','that','this','have','need',
                   'your','you','per','the','and','for','square','metre','meter','sqft','feet');
  v_terms := coalesce(v_terms, '{}'::text[]);

  -- THE LEXICON, matched as a SUBSTRING of the normalised question. Multi-word Arabic phrases are
  -- the useful ones and a tokeniser destroys them. Longest term first, so that "عزل حراري"
  -- (thermal insulation) is preferred over the bare "عزل" (insulation) it contains -- a shorter
  -- term winning here would silently answer an insulation question with waterproofing rates.
  select array_agg(x.category order by x.len desc), array_agg(x.item_hint) filter (where x.item_hint is not null)
    into v_lex, v_hints
    from (select t.category, t.item_hint, length(t.term) as len
            from public.price_trade_term t
           where v_q like '%' || regexp_replace(public.fn_ar_norm(lower(t.term)),
                                                '(^|[[:space:]])ال', '\1', 'g') || '%'
           order by length(t.term) desc) x;

  if (v_lex is null or array_length(v_lex, 1) = 0) and array_length(v_terms, 1) is null then
    return jsonb_build_object('ok', false, 'reason', 'no_substantive_terms',
      'note', 'The question carried no trade word to look up, in either language. Ask the visitor '
           || 'which trade they mean.');
  end if;

  -- The lexicon decides when it fired; otherwise fall back to scoring the latin words against the
  -- trade slugs and item text.
  if v_lex is not null and array_length(v_lex, 1) > 0 then
    v_cat := v_lex[1];
    -- An item hint from the lexicon joins the latin words used to pick WHICH bands to show, so an
    -- Arabic ceiling question narrows to ceiling bands exactly as the English one does.
    v_terms := v_terms || coalesce(v_hints, '{}'::text[]);
  else
    select r.category
      into v_cat
      from (
        select c.category, c.n,
               10 * (select count(distinct x) from unnest(v_terms) x
                      where replace(c.category, '-', ' ') like '%' || x || '%')::int
                  + (select count(distinct x) from unnest(v_terms) x
                      where c.items like '%' || x || '%')::int as score
          from (select pb.category,
                       count(*) as n,
                       lower(string_agg(coalesce(pb.item, ''), ' ')) as items
                  from public.price_benchmark pb
                 group by pb.category) c
      ) r
     where r.score > 0
     order by r.score desc, r.n desc
     limit 1;
  end if;

  -- NO CORROBORATION, NO ANSWER.
  if v_cat is null then
    return jsonb_build_object('ok', false, 'reason', 'no_trade_matched',
      'terms_tried', to_jsonb(v_terms),
      'note', 'No trade in the estate shares a word with this question, in either language. Do not '
           || 'substitute a nearby trade; say the platform holds no published range for it and '
           || 'offer to collect quotes.');
  end if;

  select pb.gap_reason into v_gap
    from public.price_benchmark pb
   where pb.category = v_cat and pb.source_kind = 'gap'
   limit 1;
  if v_gap is not null then
    return jsonb_build_object('ok', false, 'reason', 'trade_has_a_recorded_gap',
      'trade', v_cat, 'gap_reason', v_gap,
      'note', 'Tell the visitor plainly that we publish no range for this trade rather than '
           || 'estimating one, and offer to put it out to suppliers.');
  end if;

  select bool_or(q.hit) into v_hit
    from (select exists (select 1 from unnest(v_terms) x
                          where lower(coalesce(pb.item, '')) like '%' || x || '%') as hit
            from public.price_benchmark pb
           where pb.category = v_cat and pb.source_kind <> 'gap' and pb.item is not null) q;
  v_hit := coalesce(v_hit, false);

  select coalesce(jsonb_agg(jsonb_build_object(
           'item', i.item, 'unit', i.unit, 'basis', i.basis_kind,
           'low', i.low, 'high', i.high, 'currency', coalesce(i.currency, 'AED'),
           'evidence', left(i.evidence, 180),
           'source', i.source_kind || coalesce(':' || i.source_ref, ''),
           'as_of', i.as_of) order by i.low), '[]'::jsonb)
    into v_items
    from (
      select distinct on (pb.item, pb.unit)
             pb.item, pb.unit, pb.basis_kind, pb.low, pb.high, pb.currency, pb.evidence,
             pb.source_kind, pb.source_ref, pb.as_of
        from public.price_benchmark pb
       where pb.category = v_cat and pb.source_kind <> 'gap' and pb.item is not null
         and (not v_hit
              or exists (select 1 from unnest(v_terms) x
                          where lower(coalesce(pb.item, '')) like '%' || x || '%'))
       order by pb.item, pb.unit, (case when pb.source_kind = 'blog_post' then 0 else 1 end)
    ) i;

  select array_agg(distinct x) into v_matched
    from unnest(v_terms) x
   where replace(v_cat, '-', ' ') like '%' || x || '%'
      or exists (select 1 from public.price_benchmark pb
                  where pb.category = v_cat and lower(coalesce(pb.item, '')) like '%' || x || '%');

  -- THE WORDS THE ESTATE HAD NOTHING FOR. item_specific alone was not enough: "what does an HVAC
  -- chiller replacement cost" sets it true on the strength of 'replacement' appearing in hvac item
  -- text, while the estate holds no chiller row at all. Naming the unmatched word beats trying to
  -- classify 'replacement' as too generic to count.
  select array_agg(distinct x) into v_unmatched
    from unnest(v_terms) x
   where not (replace(v_cat, '-', ' ') like '%' || x || '%')
     and not exists (select 1 from public.price_benchmark pb
                      where pb.category = v_cat and lower(coalesce(pb.item, '')) like '%' || x || '%');

  return jsonb_build_object(
    'ok', true,
    'trade', v_cat,
    'item_specific', v_hit,
    'resolved_via', case when v_lex is not null and array_length(v_lex, 1) > 0
                         then 'trade_term_lexicon' else 'latin_terms' end,
    'matched_terms', to_jsonb(coalesce(v_matched, '{}'::text[])),
    'unmatched_terms', to_jsonb(coalesce(v_unmatched, '{}'::text[])),
    'band_count', jsonb_array_length(v_items),
    'bands', case when jsonb_array_length(v_items) > greatest(1, coalesce(p_limit, 6))
                  then (select jsonb_agg(s.e)
                          from (select e from jsonb_array_elements(v_items) e
                                 limit greatest(1, coalesce(p_limit, 6))) s)
                  else v_items end,
    'how_to_use', 'These are PUBLISHED GUIDE RANGES in AED for the UAE market, with their source '
               || 'and date. They are orientation, never a quotation. QuotesDone does not price the '
               || 'work - suppliers do. Give the range, name it as a guide, and offer to collect '
               || 'real quotes. Never present a single figure as the price, never average a band '
               || 'into one number, and never state a figure that is not in bands above. If '
               || 'unmatched_terms is not empty, say plainly that the platform publishes no range '
               || 'for that specific thing, rather than letting the trade-level bands stand in for '
               || 'it. Answer in the language the visitor used; the item labels stay in English '
               || 'because that is how the evidence is filed.');
end $fn$;
revoke execute on function public.fn_price_guidance(text, int) from public, anon, authenticated;

-- ── PROVE THE TWO LANGUAGES GET THE SAME ANSWER ─────────────────────────────────────────────────
-- This file defines a table and a routine, so the probe cleans up after itself and ends in a
-- notice. A raise here would roll the DDL back with it and the apply would report success over an
-- un-built function.
do $do$
declare ar jsonb; en jsonb; ins jsonb; wp jsonb; n jsonb;
begin
  -- 1. THE QUESTION THAT CAME BACK EMPTY, verbatim.
  ar := public.fn_price_guidance('كم تكلفة السقف الجبسي المستعار للمتر المربع في دبي');
  if not (ar->>'ok')::boolean then
    raise exception 'the Arabic question is still unanswered: %', ar->>'reason';
  end if;
  if ar->>'trade' <> 'gypsum' then
    raise exception 'the Arabic question resolved to % instead of gypsum', ar->>'trade';
  end if;
  if ar->>'resolved_via' <> 'trade_term_lexicon' then
    raise exception 'Arabic resolved via % rather than the lexicon', ar->>'resolved_via';
  end if;

  -- 2. THE SAME ANSWER, NOT MERELY AN ANSWER. Both languages must land on the same trade and the
  --    same item-level precision, or the Arabic speaker is still second class.
  en := public.fn_price_guidance('what should a gypsum false ceiling cost per square metre in Dubai');
  if (ar->>'trade') is distinct from (en->>'trade') then
    raise exception 'the two languages resolved to different trades: % vs %', ar->>'trade', en->>'trade';
  end if;
  if not (ar->>'item_specific')::boolean then
    raise exception 'the Arabic answer is trade-level while the English one is item-level';
  end if;

  -- 3. THE LONGEST TERM WINS. "عزل حراري" (thermal insulation) contains "عزل" (which maps to
  --    waterproofing). A shorter term winning would answer an insulation question with
  --    waterproofing rates and nobody would see it happen.
  ins := public.fn_price_guidance('كم سعر العزل الحراري للمتر');
  if ins->>'trade' <> 'insulation' then
    raise exception 'thermal insulation resolved to % -- the containing shorter term won', ins->>'trade';
  end if;
  wp := public.fn_price_guidance('كم سعر العزل المائي');
  if wp->>'trade' <> 'waterproofing' then
    raise exception 'waterproofing resolved to %', wp->>'trade';
  end if;

  -- 3b. A RECORDED GAP MUST BE REACHABLE IN ARABIC TOO. Answering "I have no sourced answer" to an
  --     Arabic elevator question, while the English one returns the gap and its reason, is the same
  --     inequality this file exists to remove.
  ins := public.fn_price_guidance('كم تكلفة تركيب مصعد');
  if ins->>'reason' <> 'trade_has_a_recorded_gap' then
    raise exception 'the Arabic elevator question refused as % rather than the recorded gap', ins->>'reason';
  end if;

  -- 4. ARABIC DOES NOT LOWER THE BAR. A question in Arabic about something the estate has no trade
  --    for must still refuse rather than reach for the nearest lexicon entry.
  n := public.fn_price_guidance('كم تكلفة استئجار طائرة هليكوبتر الى القمر');
  if (n->>'ok')::boolean then
    raise exception 'an off-estate Arabic question was answered as trade %', n->>'trade';
  end if;

  raise notice 'ARABIC IS NOT SECOND CLASS ANY MORE. The Arabic gypsum-ceiling question resolves to % via the lexicon with % band(s), item-specific, the same trade and the same precision the English question gets. Thermal insulation beats plain insulation on term length. An off-estate Arabic question still refuses. % lexicon terms live.',
    ar->>'trade', jsonb_array_length(ar->'bands'),
    (select count(*) from public.price_trade_term);
end
$do$;
