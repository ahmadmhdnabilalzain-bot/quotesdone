-- THE TAXONOMY NAMED TWENTY-FIVE TRADES AND THE DIRECTORY SELLS FORTY.
--
-- Founder decision, 12 Aug 2026: "the taxonomy grows."
--
-- After scripts/sql/twenty_thousand_suppliers_filed_under_a_vocabulary_the_matcher_cannot_read.sql
-- re-normalised leads.invite_trades into taxonomy_trade codes, ~7,400 suppliers came out with an
-- EMPTY trade array - fn_norm_trades matched none of the 25 codes against their own text. Measured,
-- the top of that list is not exotic at all:
--
--   building material suppliers        1,063     consultants engineers         229
--   contractors general                  619     chemical chemical products    178
--   building contractors                 349     interior decorators           166
--   contractors electro mechanical       248     architects                    116
--
-- TWO DIFFERENT FAILURES, AND ONLY ONE OF THEM IS A MISSING TRADE.
--
-- 1. ALIAS GAPS on trades that already exist. "contractors electro mechanical" is mep_general and
--    always was; "building contractors" and "contractors general" are civil_works; "security control
--    equipment systems" is security_systems. 1,216 suppliers were unfindable because nobody had
--    written down the phrase the directory actually uses. No new trade needed - just the words.
--
-- 2. TRADES THE TAXONOMY GENUINELY NEVER NAMED. Building materials, engineering consultancy,
--    generators, heavy equipment, labour supply, safety equipment, solar, chemicals, plastics and
--    pipes, oilfield, home automation, logistics, packaging, marine and IT services are real UAE
--    B2B categories with real suppliers in this directory and no code to file them under.
--
-- WHY THE ALIASES ARE MULTI-WORD. fn_norm_trades matches `p_text ~* '\m' || alias` - a word boundary
-- at the START only, no boundary at the end. A bare 'contractor' would match "contractor",
-- "contractors", "contracting" and therefore most of the directory, and every one of those suppliers
-- would be offered for every civil job. Specific phrases cost nothing and a false trade costs a
-- customer a wrong shortlist, which is the failure the confirmed_at gate exists to catch and this
-- would slip past it because the SUPPLIER would confirm a scope they do read as theirs.
--
-- authority_required is '{}' on every new row deliberately. taxonomy_authority drives a real licence
-- check; claiming a trade needs DCD or ADCD approval when nobody has verified that is a fabricated
-- compliance requirement, and the wrong direction to be wrong in. It is added when someone confirms
-- it, not guessed here.
--
-- ALIASES ARE UNIONED, NEVER REPLACED, on the existing five. An `on conflict do update set aliases =
-- excluded.aliases` would silently drop whatever is already there.

insert into public.taxonomy_trade (code, label, aliases, authority_required, sort, active) values
  ('building_materials',  'Building & Construction Materials',
     array['building material','building materials','construction material','construction materials',
           'cement','aggregate','ready mix','blocks and bricks','sanitary ware'], '{}', 26, true),
  ('engineering_consultancy','Engineering Consultancy & Architecture',
     array['consultants engineers','consulting engineer','engineering consultant','engineers contractors',
           'architect','architects','architectural','design consultancy','structural engineer'], '{}', 27, true),
  ('power_generators',     'Generators & Power Equipment',
     array['generator','generators','genset','gen set','power generation','diesel generator','ups system'], '{}', 28, true),
  ('heavy_equipment',      'Heavy Equipment & Plant',
     array['heavy duty equipment','heavy equipment','earthmoving','excavator','crane hire','forklift',
           'construction equipment','plant hire'], '{}', 29, true),
  ('labour_supply',        'Manpower & Labour Supply',
     array['labour supply','labor supply','manpower supply','manpower service','staffing supply'], '{}', 30, true),
  ('safety_equipment',     'Safety Equipment & PPE',
     array['safety equipment','personal protective','ppe supplier','safety clothing','fall protection'], '{}', 31, true),
  ('solar',                'Solar & Renewable Energy',
     array['solar energy','solar panel','solar power','photovoltaic','solar water heater'], '{}', 32, true),
  ('chemicals',            'Industrial & Construction Chemicals',
     array['chemical products','industrial chemical','construction chemical','adhesive and sealant',
           'coating chemical'], '{}', 33, true),
  ('plastics_pipes',       'Plastics, Pipes & Fittings',
     array['plastic products','pipe fitting','pipes and fittings','pvc pipe','hdpe','plastic manufactur'], '{}', 34, true),
  ('oilfield',             'Oilfield & Industrial Supplies',
     array['oil field suppl','oilfield','oil and gas suppl','petrochemical suppl'], '{}', 35, true),
  ('home_automation',      'Home & Building Automation',
     array['home automation','building automation','smart home','building management system','bms system'], '{}', 36, true),
  ('logistics_moving',     'Logistics, Movers & Storage',
     array['moving and storage','movers and packers','relocation service','freight forwarding','warehousing service'], '{}', 37, true),
  ('packaging',            'Packaging & Printing Supplies',
     array['packaging company','packaging material','corrugated','printing press'], '{}', 38, true),
  ('marine',               'Marine & Offshore Supplies',
     array['marine supply','marine equipment','ship chandler','offshore supply'], '{}', 39, true),
  ('it_services',          'IT & Network Services',
     array['computer support','it services','network support','structured cabling','computer security service'], '{}', 40, true)
on conflict (code) do update
  set label = excluded.label,
      aliases = (select array_agg(distinct a) from unnest(public.taxonomy_trade.aliases || excluded.aliases) a),
      active = true;

-- The alias gaps on trades that already existed. UNION, never replace.
update public.taxonomy_trade t
   set aliases = (select array_agg(distinct a) from unnest(t.aliases || v.add) a)
  from (values
    ('mep_general',      array['contractors electro mechanical','electro mechanical','electromechanical',
                               'mechanical electrical plumbing']),
    ('civil_works',      array['building contractor','contractors general','general contracting',
                               'contracting company','civil contracting','construction company']),
    ('security_systems', array['security control equipment','security guard service','cctv','access control']),
    ('interior_fitout',  array['interior decorator','interior design','fit out contractor','turnkey fitout']),
    ('cleaning',         array['facility management','facilities management','property maintenance','handyman'])
  ) as v(code, add)
 where t.code = v.code;
