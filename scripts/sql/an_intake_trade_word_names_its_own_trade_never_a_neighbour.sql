-- AN INTAKE TRADE WORD NAMES ITS OWN TRADE, NEVER A NEIGHBOUR. Seat: sales_engineer. 24 Sep 2026.
-- Founder rulings: "exact trade match or none; no nearest mapping" and instructions 895/899/900 (the
-- missing trades join the taxonomy first).
--
-- MEASURED (production htdblwldjkcgjvmqkbeh, read-only, 24 Sep 2026). fn_norm_trades resolves a word
-- only through a taxonomy code or public.intake_trade_taxonomy (31 rows). Twelve words were ambiguous:
--   * ten intake slugs resolved to a NEIGHBOUR trade because their own trade did not exist:
--       demolition -> civil_works            general-building-contracting -> civil_works
--       masonry -> civil_works               interior-design -> interior_fitout
--       swimming-pools -> landscaping        insulation -> waterproofing
--       marble-granite -> flooring           blinds-curtains -> upholstery
--       movers -> logistics_moving (freight) it-networking -> {av_it, it_services} (one word, two trades)
--   * two aliases named two trades at once: 'pest control' (cleaning AND pest_control) and
--     'structured cabling' (av_it AND it_services).
-- The first nine now have a trade of their own (the_missing_trades_join_the_taxonomy_under_twelve_groups.sql,
-- same PR, 195 -> 213 trades), so each word resolves to exactly that trade.
--
-- WHAT THIS CHANGES
--   1. The nine slugs point at their own new trade; engineering-and-architectural-consultancies names BOTH
--      trades its words name (engineering and architectural design), which is two exact trades, not a guess.
--   2. it-networking resolves to it_services only (network installation and structured cabling are its
--      services; av_it is audio-visual and low current).
--   3. 'pest control' leaves cleaning's aliases and 'structured cabling' leaves av_it's: each alias names one trade.
--
-- CONSEQUENCE, stated so nobody is surprised: an inquiry naming demolition now reaches suppliers who hold
-- demolition_works, not every civil_works supplier. A civil_works supplier is offered demolition_works on
-- his Services tab as a 'refine' trade (umbrella_code) and receives those inquiries once he ticks one of its
-- services. Pre-launch: 0 real inquiries use these slugs (customers and inquiries are 0).
--
-- NOT CHANGED: fn_norm_trades, fn_taxonomy_trades_for, fn_match_capability, any supplier row, any inquiry.
-- Depends on the seed above being applied FIRST (the new codes must exist; the verdict checks it).
-- Committed, not applied: scripts/sql/pending/an_intake_trade_word_names_its_own_trade_never_a_neighbour.txt.

update public.intake_trade_taxonomy m set trade_codes = v.codes,
       note = coalesce(m.note || ' | ', '') || '24 Sep 2026: own trade, never a neighbour'
  from (values
    ('demolition', array['demolition_works']),
    ('general-building-contracting', array['general_contracting']),
    ('masonry', array['masonry_blockwork']),
    ('interior-design', array['design_consultancy']),
    ('swimming-pools', array['swimming_pools']),
    ('insulation', array['thermal_insulation']),
    ('marble-granite', array['marble_stone']),
    ('blinds-curtains', array['curtains_blinds']),
    ('movers', array['removals_relocation']),
    ('engineering-and-architectural-consultancies', array['design_consultancy','engineering_consultancy']),
    ('it-networking', array['it_services'])
  ) as v(slug, codes)
 where m.intake_slug = v.slug
   and m.trade_codes is distinct from v.codes::text[]
   and not exists (select 1 from unnest(v.codes) c where not exists (select 1 from public.taxonomy_trade t where t.code = c and t.active));

update public.taxonomy_trade set aliases = array_remove(aliases, 'pest control') where code = 'cleaning' and 'pest control' = any(aliases);
update public.taxonomy_trade set aliases = array_remove(aliases, 'structured cabling') where code = 'av_it' and 'structured cabling' = any(aliases);

-- PROBE: one verdict row. Every intake slug resolves to active trades; no alias names two trades; each
-- of the eleven words resolves to exactly the trade(s) above.
select case
  when exists (select 1 from public.intake_trade_taxonomy m, unnest(m.trade_codes) c
                where not exists (select 1 from public.taxonomy_trade t where t.code = c and t.active))
    then 'PROBE FAILED: an intake slug names a trade that is missing or inactive (apply the seed first)'
  when exists (select 1 from public.taxonomy_trade, unnest(aliases) a where active group by lower(a) having count(distinct code) > 1)
    then 'PROBE FAILED: an alias still names two trades'
  when public.fn_norm_trades('demolition') <> array['demolition_works']
    or public.fn_norm_trades('swimming-pools') <> array['swimming_pools']
    or public.fn_norm_trades('movers') <> array['removals_relocation']
    or public.fn_norm_trades('it-networking') <> array['it_services']
    or public.fn_norm_trades('engineering-and-architectural-consultancies') <> array['design_consultancy','engineering_consultancy']
    then 'PROBE FAILED: a word still resolves to a neighbour'
  else 'PROBE OK' end as verdict;
