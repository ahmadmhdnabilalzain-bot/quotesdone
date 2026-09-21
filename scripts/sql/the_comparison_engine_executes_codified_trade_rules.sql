-- THE COMPARISON ENGINE EXECUTES CODIFIED TRADE RULES, STARTING WITH GYPSUM.
-- Seat: sales_engineer. 21 Sep 2026. Implements docs/KNOWLEDGE_DOCTRINE.md section 7 (founder
-- instructions 520-523: "the brain of combined technical directors of all fields and sectors we
-- cover", codified as rules the comparison engine executes; OpenRouter is held, nothing here calls a
-- model).
--
-- MEASURED BEFORE THIS FILE (production, 21 Sep 2026, via the Supabase MCP):
--   * taxonomy_trade.code 'gypsum' exists ("Gypsum, partitions & ceilings" / "الجبس والقواطع والأسقف").
--   * public.trade_scope_line, spec_equivalence, trade_comparability, trade_approval: do not exist.
--   * public.price_benchmark: 18 columns, none of trade_code / red_flag_reason_en / red_flag_reason_ar;
--     category 'gypsum' holds 9 blog_post rows (ids 82-86, 203-206) and 20 kb_chunk rows. The five
--     rows this file annotates are ids 82, 83, 84, 85, 86 (cost-of-false-ceiling-uae, as_of 2026-06-28).
--   * public.fn_price_confidence(text, numeric, numeric, text) exists and is NOT changed: its
--     p_category for gypsum is already the trade code, so the engine passes the trade code to it.
--   * public.fn_trade_rules: does not exist.
--   * quote_compare reads no rule table; compare.ts sameValue() has no equivalence notion (doctrine
--     section 3).
--
-- WHAT THIS CHANGES
--   1. Four rule tables, one per family (mandatory scope lines + common omissions; non-equivalent
--      substitutions + brand equivalence classes; comparability keys; approvals per emirate). The
--      doctrine's five admission tests are CHECK constraints on every row: decision enum, label enum,
--      jurisdiction, citation + effective_date not null, licence enum, rule_en and rule_ar both present
--      and different, rule_ar containing Arabic script.
--   2. price_benchmark gains trade_code, line_regex and the red_flag_* columns (reason EN/AR, citation,
--      effective date, expiry, label, licence) so a price band can say WHY a price lands outside it.
--   3. public.v_trade_rules_live: what the engine reads. Active, in date, both languages present,
--      approvals unexpired. One shape (family, trade_code, key, rule jsonb) over the five sources.
--   4. public.fn_trade_rules(p_trade_code text) returns jsonb: the five families as arrays, read by
--      quote_compare once per run. security definer, search_path pinned, revoked from public/anon/
--      authenticated (service role only: the report is the customer's paid deliverable, the rules are
--      not a public API).
--   5. The gypsum seed, rendered VERBATIM from supabase/functions/_shared/rules/gypsum.json by
--      scripts/lib/trade_rules_sql.mjs; scripts/checks/the_rule_seeds_match_their_tables.test.mjs
--      re-renders the JSON and asserts this file carries the same text. Rows with active=false are
--      authored but not live (their source was not verified in-browser on 21 Sep 2026).
--   6. A probe that reads fn_trade_rules('gypsum') back and returns one verdict ROW.
--
-- NOT CHANGED: fn_price_confidence (signature and body), category_quote_specs, line_specs/model.ts
-- readers, any other trade (the other 39 trades have no rows until authored the same way), RLS on
-- price_benchmark.
--
-- Apply: node scripts/apply_sql.mjs scripts/sql/the_comparison_engine_executes_codified_trade_rules.sql --apply --ddl
-- Then deploy supabase/functions/quote_compare.

-- ---------------------------------------------------------------------------------------------
-- 1. The rule tables. The shared columns are the doctrine's tests (section 1) as constraints.
-- ---------------------------------------------------------------------------------------------
create table if not exists public.trade_scope_line (
  trade_code      text not null references public.taxonomy_trade(code) on update cascade,
  job_type        text not null default '',          -- '' = every job of the trade
  line_key        text not null check (line_key ~ '^[a-z][a-z0-9_]*$'),
  line_en         text not null check (btrim(line_en) <> ''),
  line_ar         text not null check (line_ar ~ '[ء-ي]'),
  kind            text not null check (kind in ('mandatory','commonly_omitted')),
  proof_regex_en  text not null,                     -- what in a quotation proves the line is included
  proof_regex_ar  text not null,
  applies_regex   text,                              -- null = every request; else only when the request text matches
  decision        text not null check (decision in ('hold_quote','flag_substitution','flag_omission','flag_price','not_comparable','approval_required','route_inquiry','recognise_service')),
  label           text not null check (label in ('law','practice','manufacturer_data')),
  jurisdiction    text not null check (btrim(jurisdiction) <> ''),
  citation        text not null check (btrim(citation) <> ''),
  effective_date  date not null,
  expires_on      date,
  licence         text not null check (licence in ('government','licensed_standard','manufacturer_public','quotesdone')),
  rule_en         text not null check (btrim(rule_en) <> ''),
  rule_ar         text not null check (rule_ar ~ '[ء-ي]' and rule_ar <> rule_en),
  source_ref      text,
  active          boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  primary key (trade_code, job_type, line_key)
);
comment on table public.trade_scope_line is 'Rule family: mandatory scope lines (a quotation missing one is held) and commonly omitted lines (absent ones are reported as missing_from_request). One row = one rule the comparison engine fires. Seeded from supabase/functions/_shared/rules/<trade>.json. Seat: sales_engineer, 21 Sep 2026.';

create table if not exists public.spec_equivalence (
  trade_code       text not null references public.taxonomy_trade(code) on update cascade,
  attr_code        text not null,                    -- _shared/line_specs/model.ts attribute code
  class_key        text not null check (class_key ~ '^[a-z][a-z0-9_.]*$'),
  value            text not null check (btrim(value) <> ''),
  equivalent       boolean not null,                 -- true: member of the class; false: explicitly NOT equivalent to it
  evidence_kind    text not null check (evidence_kind in ('authority_approval','conformity_cert','consultant_list','datasheet')),
  approval_ref     text,
  approval_expires date,
  decision        text not null check (decision in ('hold_quote','flag_substitution','flag_omission','flag_price','not_comparable','approval_required','route_inquiry','recognise_service')),
  label           text not null check (label in ('law','practice','manufacturer_data')),
  jurisdiction    text not null check (btrim(jurisdiction) <> ''),
  citation        text not null check (btrim(citation) <> ''),
  effective_date  date not null,
  expires_on      date,
  licence         text not null check (licence in ('government','licensed_standard','manufacturer_public','quotesdone')),
  rule_en         text not null check (btrim(rule_en) <> ''),
  rule_ar         text not null check (rule_ar ~ '[ء-ي]' and rule_ar <> rule_en),
  source_ref      text,
  active          boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  primary key (trade_code, attr_code, class_key, value)
);
comment on table public.spec_equivalence is 'Rule family: non-equivalent substitutions and brand equivalence classes. A class is "these values are accepted as equivalent for this attribute"; equivalent=false names a value that is explicitly NOT. A brand in no class is unclassified, never ranked. Approvals expire; v_trade_rules_live drops expired rows. Seat: sales_engineer, 21 Sep 2026.';

create table if not exists public.trade_comparability (
  trade_code      text not null references public.taxonomy_trade(code) on update cascade,
  line_type       text not null check (line_type ~ '^[a-z][a-z0-9_]*$'),
  line_regex      text not null,                     -- which request/quote lines this key applies to
  required_attrs  text[] not null check (cardinality(required_attrs) > 0),
  decision        text not null check (decision in ('hold_quote','flag_substitution','flag_omission','flag_price','not_comparable','approval_required','route_inquiry','recognise_service')),
  label           text not null check (label in ('law','practice','manufacturer_data')),
  jurisdiction    text not null check (btrim(jurisdiction) <> ''),
  citation        text not null check (btrim(citation) <> ''),
  effective_date  date not null,
  expires_on      date,
  licence         text not null check (licence in ('government','licensed_standard','manufacturer_public','quotesdone')),
  rule_en         text not null check (btrim(rule_en) <> ''),
  rule_ar         text not null check (rule_ar ~ '[ء-ي]' and rule_ar <> rule_en),
  source_ref      text,
  active          boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  primary key (trade_code, line_type)
);
comment on table public.trade_comparability is 'Rule family: comparability keys. A line is comparable between two quotations only when both state every attribute in required_attrs; otherwise the report says not comparable (marker ≁) and does not rank that line. Seat: sales_engineer, 21 Sep 2026.';

create table if not exists public.trade_approval (
  trade_code      text not null references public.taxonomy_trade(code) on update cascade,
  emirate         text not null check (btrim(emirate) <> ''),
  authority       text not null check (btrim(authority) <> ''),
  approval_en     text not null check (btrim(approval_en) <> ''),
  approval_ar     text not null check (approval_ar ~ '[ء-ي]'),
  stage           text not null check (stage in ('before_works','on_completion','supplier_licence')),
  evidence_doc    text,
  cost_bearer     text not null check (cost_bearer in ('supplier','customer','either')),
  applies_regex   text,                              -- null = every job of the trade in that emirate
  decision        text not null check (decision in ('hold_quote','flag_substitution','flag_omission','flag_price','not_comparable','approval_required','route_inquiry','recognise_service')),
  label           text not null check (label in ('law','practice','manufacturer_data')),
  jurisdiction    text not null check (btrim(jurisdiction) <> ''),
  citation        text not null check (btrim(citation) <> ''),
  effective_date  date not null,
  expires_on      date,
  licence         text not null check (licence in ('government','licensed_standard','manufacturer_public','quotesdone')),
  rule_en         text not null check (btrim(rule_en) <> ''),
  rule_ar         text not null check (rule_ar ~ '[ء-ي]' and rule_ar <> rule_en),
  source_ref      text,
  active          boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  primary key (trade_code, emirate, authority, approval_en)
);
comment on table public.trade_approval is 'Rule family: approvals per trade per emirate (authority, stage, evidence document, who bears the cost). Rows for the inquiry''s emirate (or UAE) become watch_outs in the comparison report. Seat: sales_engineer, 21 Sep 2026.';

-- Service role only, like service_implication: the rules are the engine's, not a public API.
alter table public.trade_scope_line     enable row level security;
alter table public.spec_equivalence     enable row level security;
alter table public.trade_comparability  enable row level security;
alter table public.trade_approval       enable row level security;
drop policy if exists trade_scope_line_service_role_only    on public.trade_scope_line;
drop policy if exists spec_equivalence_service_role_only    on public.spec_equivalence;
drop policy if exists trade_comparability_service_role_only on public.trade_comparability;
drop policy if exists trade_approval_service_role_only      on public.trade_approval;
create policy trade_scope_line_service_role_only    on public.trade_scope_line    as permissive for all to public using (false) with check (false);
create policy spec_equivalence_service_role_only    on public.spec_equivalence    as permissive for all to public using (false) with check (false);
create policy trade_comparability_service_role_only on public.trade_comparability as permissive for all to public using (false) with check (false);
create policy trade_approval_service_role_only      on public.trade_approval      as permissive for all to public using (false) with check (false);
revoke all on public.trade_scope_line, public.spec_equivalence, public.trade_comparability, public.trade_approval from anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 2. Price red flags live on the band row itself (doctrine section 7).
-- ---------------------------------------------------------------------------------------------
alter table public.price_benchmark
  add column if not exists trade_code             text references public.taxonomy_trade(code) on update cascade,
  add column if not exists line_regex             text,
  add column if not exists red_flag_reason_en     text,
  add column if not exists red_flag_reason_ar     text check (red_flag_reason_ar is null or red_flag_reason_ar ~ '[ء-ي]'),
  add column if not exists red_flag_citation      text,
  add column if not exists red_flag_effective_date date,
  add column if not exists red_flag_expires_on    date,
  add column if not exists red_flag_label         text check (red_flag_label is null or red_flag_label in ('law','practice','manufacturer_data')),
  add column if not exists red_flag_licence       text check (red_flag_licence is null or red_flag_licence in ('government','licensed_standard','manufacturer_public','quotesdone'));
comment on column public.price_benchmark.red_flag_reason_en is 'Why a unit rate lands outside this band (thinner spec, dropped scope, unlicensed labour / premium spec, access, small quantity). Set only on rows a trade''s rules file annotates; carried into the comparison report beside fn_price_confidence''s band. Seat: sales_engineer, 21 Sep 2026.';

-- ---------------------------------------------------------------------------------------------
-- 3. What the engine reads: active, in date, both languages present, approvals unexpired.
-- ---------------------------------------------------------------------------------------------
create or replace view public.v_trade_rules_live as
  select 'scope_line'::text as family, trade_code, line_key as key,
         jsonb_build_object('line_key', line_key, 'job_type', nullif(job_type, ''), 'line_en', line_en, 'line_ar', line_ar, 'kind', kind,
           'proof_regex_en', proof_regex_en, 'proof_regex_ar', proof_regex_ar, 'applies_regex', applies_regex,
           'decision', decision, 'label', label, 'jurisdiction', jurisdiction, 'citation', citation, 'effective_date', effective_date, 'expires_on', expires_on,
           'licence', licence, 'rule_en', rule_en, 'rule_ar', rule_ar, 'source_ref', source_ref) as rule
    from public.trade_scope_line
   where active and effective_date <= current_date and (expires_on is null or expires_on >= current_date)
  union all
  select 'equivalence', trade_code, class_key || ':' || value,
         jsonb_build_object('attr_code', attr_code, 'class_key', class_key, 'value', value, 'equivalent', equivalent, 'evidence_kind', evidence_kind,
           'approval_ref', approval_ref, 'approval_expires', approval_expires,
           'decision', decision, 'label', label, 'jurisdiction', jurisdiction, 'citation', citation, 'effective_date', effective_date, 'expires_on', expires_on,
           'licence', licence, 'rule_en', rule_en, 'rule_ar', rule_ar, 'source_ref', source_ref)
    from public.spec_equivalence
   where active and effective_date <= current_date and (expires_on is null or expires_on >= current_date)
     and (approval_expires is null or approval_expires >= current_date)
  union all
  select 'price_flag', trade_code, item || ':' || unit,
         jsonb_build_object('benchmark_id', id, 'item', item, 'unit', unit, 'low', low, 'high', high, 'line_regex', line_regex,
           'decision', 'flag_price', 'label', red_flag_label, 'jurisdiction', 'UAE', 'citation', red_flag_citation, 'effective_date', red_flag_effective_date, 'expires_on', red_flag_expires_on,
           'licence', red_flag_licence, 'rule_en', red_flag_reason_en, 'rule_ar', red_flag_reason_ar, 'source_ref', source_kind || ':' || source_ref)
    from public.price_benchmark
   where trade_code is not null and red_flag_reason_en is not null and red_flag_reason_ar is not null and source_kind <> 'gap'
     and red_flag_effective_date <= current_date and (red_flag_expires_on is null or red_flag_expires_on >= current_date)
  union all
  select 'comparability', trade_code, line_type,
         jsonb_build_object('line_type', line_type, 'line_regex', line_regex, 'required_attrs', to_jsonb(required_attrs),
           'decision', decision, 'label', label, 'jurisdiction', jurisdiction, 'citation', citation, 'effective_date', effective_date, 'expires_on', expires_on,
           'licence', licence, 'rule_en', rule_en, 'rule_ar', rule_ar, 'source_ref', source_ref)
    from public.trade_comparability
   where active and effective_date <= current_date and (expires_on is null or expires_on >= current_date)
  union all
  select 'approval', trade_code, emirate || ':' || authority || ':' || approval_en,
         jsonb_build_object('emirate', emirate, 'authority', authority, 'approval_en', approval_en, 'approval_ar', approval_ar, 'stage', stage,
           'evidence_doc', evidence_doc, 'cost_bearer', cost_bearer, 'applies_regex', applies_regex,
           'decision', decision, 'label', label, 'jurisdiction', jurisdiction, 'citation', citation, 'effective_date', effective_date, 'expires_on', expires_on,
           'licence', licence, 'rule_en', rule_en, 'rule_ar', rule_ar, 'source_ref', source_ref)
    from public.trade_approval
   where active and effective_date <= current_date and (expires_on is null or expires_on >= current_date);
comment on view public.v_trade_rules_live is 'The rules the comparison engine executes: active, in date, both languages present, approvals unexpired; one shape over the five families. Read through fn_trade_rules. Seat: sales_engineer, 21 Sep 2026.';
revoke all on public.v_trade_rules_live from anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 4. The one read quote_compare makes per run.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_trade_rules(p_trade_code text)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  select jsonb_build_object(
    'trade_code', p_trade_code,
    'scope_lines',   coalesce((select jsonb_agg(rule order by key) from public.v_trade_rules_live where trade_code = p_trade_code and family = 'scope_line'),    '[]'::jsonb),
    'equivalence',   coalesce((select jsonb_agg(rule order by key) from public.v_trade_rules_live where trade_code = p_trade_code and family = 'equivalence'),   '[]'::jsonb),
    'price_flags',   coalesce((select jsonb_agg(rule order by key) from public.v_trade_rules_live where trade_code = p_trade_code and family = 'price_flag'),    '[]'::jsonb),
    'comparability', coalesce((select jsonb_agg(rule order by key) from public.v_trade_rules_live where trade_code = p_trade_code and family = 'comparability'), '[]'::jsonb),
    'approvals',     coalesce((select jsonb_agg(rule order by key) from public.v_trade_rules_live where trade_code = p_trade_code and family = 'approval'),      '[]'::jsonb));
$$;
comment on function public.fn_trade_rules(text) is 'The five rule families of one trade as JSON, live rows only (v_trade_rules_live). quote_compare calls it once per run and executes the rules deterministically (_shared/line_specs/rules.ts). Seat: sales_engineer, 21 Sep 2026.';
revoke all on function public.fn_trade_rules(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 5. The gypsum seed (rendered; the check re-renders the JSON and compares).
-- ---------------------------------------------------------------------------------------------
-- ==== SEED gypsum (rendered from supabase/functions/_shared/rules/gypsum.json by scripts/lib/trade_rules_sql.mjs; do not hand-edit) ====
delete from public.trade_scope_line where trade_code = 'gypsum';
insert into public.trade_scope_line (trade_code, job_type, line_key, line_en, line_ar, kind, proof_regex_en, proof_regex_ar, applies_regex, decision, label, jurisdiction, citation, effective_date, expires_on, licence, rule_en, rule_ar, source_ref, active) values
  ('gypsum','','framing','Metal stud / channel framing with section size, gauge and centres','هيكل معدني (قوائم وقنوات) مع مقاس القطاع وسماكة الصاج والمسافة بين القوائم','mandatory','\b(stud|studs|channel|channels|framing|frame|runner|track|c-?section|furring)\b','(قوائم|قطاعات|هيكل|مجرى|قناة)',null,'hold_quote','practice','UAE','BS EN 14195:2014 Metal framing components for gypsum board systems; manufacturer system tables (stud size x gauge x centres -> maximum height)','2014-01-01',null,'quotesdone','A gypsum partition or ceiling quotation must itemise its metal framing (stud/channel section, sheet gauge and centres). Without it the partition height, deflection and fixing capacity cannot be checked, and the board price alone is not the system price.','يجب أن يفصّل عرض سعر قواطع أو أسقف الجبس هيكله المعدني (مقاس القائم/القناة وسماكة الصاج والمسافة بين القوائم). بدونه لا يمكن التحقق من ارتفاع القاطع ولا من الانحراف ولا من قدرة التثبيت، وسعر اللوح وحده ليس سعر النظام.','gypsum.json scope_lines',true),
  ('gypsum','','board','Gypsum board supply: type (BS EN 520 letter or trade name), thickness and layers per face','توريد ألواح الجبس: النوع (حرف BS EN 520 أو الاسم التجاري) والسماكة وعدد الطبقات لكل وجه','mandatory','\b(board|boards|plasterboard|gypsum|drywall|tile|tiles)\b','(لوح|ألواح|جبس|بلاط)',null,'hold_quote','practice','UAE','BS EN 520:2004+A1:2009 Gypsum plasterboards: definitions, requirements and test methods (board types A, H1-H3, F, D, E, I, P, R)','2009-01-01',null,'quotesdone','Every board line must state the board type, thickness (mm) and layers per face. ''Gypsum board'' with no type is not a specification: a Type A board is not moisture-resistant (H) and not fire-rated (F).','يجب أن يذكر كل بند ألواح نوع اللوح والسماكة (مم) وعدد الطبقات لكل وجه. عبارة «لوح جبس» بلا نوع ليست مواصفة: اللوح من النوع A ليس مقاومًا للرطوبة (H) وليس مقاومًا للحريق (F).','gypsum.json scope_lines',true),
  ('gypsum','','jointing_finish','Taping, jointing compound and finish level (ready for paint)','شريط الوصلات ومعجون الوصلات ومستوى التشطيب (جاهز للدهان)','mandatory','\b(joint|jointing|taping|tape|filler|compound|skim|skimming|finish|finished|finishing|level\s*[3-5]|q[1-4])\b','(معجون|شريط|وصلات|تشطيب|تعبئة)',null,'hold_quote','practice','UAE','BS EN 13963:2014 Jointing materials for gypsum boards; finish levels Q1-Q4 per manufacturer system manuals','2014-01-01',null,'quotesdone','Jointing and finish are a separate cost line. A quotation silent on taping, compound and finish level either excludes them (the wall is not paintable) or hides them; both make the price incomparable.','الوصلات والتشطيب بند تكلفة مستقل. العرض الذي لا يذكر الشريط والمعجون ومستوى التشطيب إمّا يستثنيها (فالجدار غير جاهز للدهان) أو يخفيها؛ وفي الحالتين لا يمكن مقارنة السعر.','gypsum.json scope_lines',true),
  ('gypsum','','suspension_grid','Ceiling suspension system: hangers, main runners / cross tees or furring channels, perimeter trim','نظام تعليق السقف: علاقات وحوامل رئيسية/عرضية أو قنوات، وشريط المحيط','mandatory','\b(grid|hanger|hangers|suspension|main\s*runner|cross\s*tee|tees?|furring|perimeter\s*(?:trim|angle)|wall\s*angle|t-?bar)\b','(تعليق|علاقات|شبكة|حوامل|زاوية محيط)','ceiling|bulkhead|سقف|أسقف','hold_quote','practice','UAE','BS EN 13964:2014 Suspended ceilings: requirements and test methods (load class, deflection, corrosion class of grid)','2014-01-01',null,'quotesdone','A suspended ceiling quotation must itemise the suspension system (hangers, grid or channels, perimeter trim). Tiles or boards priced without their carrier are supply-only, whatever the line says.','يجب أن يفصّل عرض السقف المعلق نظام التعليق (العلاقات، الشبكة أو القنوات، شريط المحيط). البلاط أو الألواح المسعّرة بلا حاملها هي توريد فقط مهما قال البند.','gypsum.json scope_lines',true),
  ('gypsum','','fixings_accessories','Fixings and accessories: screws, anchors, corner beads, edge trims','مواد التثبيت والإكسسوارات: براغٍ ومراسٍ وزوايا حماية وأشرطة حواف','mandatory','\b(screw|screws|anchor|anchors|fixing|fixings|bead|beads|trim|trims|accessory|accessories|consumables)\b','(براغي|مسامير|مراسي|زوايا|إكسسوارات|مستهلكات)',null,'hold_quote','practice','UAE','BS EN 14566:2008+A1:2009 Mechanical fasteners for gypsum plasterboard systems','2009-01-01',null,'quotesdone','Fixings and accessories are 5-10% of a drywall system''s material cost and are the first item a low quotation drops. They must be itemised or stated as included.','مواد التثبيت والإكسسوارات تمثل 5-10% من تكلفة مواد نظام الجبس، وهي أول ما يُسقطه العرض المنخفض. يجب تفصيلها أو النص على شمولها.','gypsum.json scope_lines',true),
  ('gypsum','','insulation','Cavity insulation (rock wool / glass wool, density and thickness)','عزل التجويف (صوف صخري / صوف زجاجي، بالكثافة والسماكة)','commonly_omitted','\b(rock\s*wool|rockwool|glass\s*wool|mineral\s*wool|insulation|kg/m3)\b','(صوف صخري|صوف زجاجي|عزل)','partition|wall|acoustic|قاطع|قواطع|جدار|صوت','flag_omission','practice','UAE','BS EN 13162:2012+A1:2015 Mineral wool factory-made products; acoustic build-up tables in manufacturer system manuals (ISO 10140-2 laboratory Rw)','2015-01-01',null,'quotesdone','A partition without cavity insulation has a laboratory Rw roughly 6-10 dB lower than the same build-up with 50 mm mineral wool. A quotation that omits insulation is cheaper because it is a different wall.','القاطع بلا عزل في التجويف يقل معامل عزله الصوتي المخبري Rw بنحو 6-10 ديسيبل عن التركيب نفسه مع 50 مم صوف معدني. العرض الذي يُسقط العزل أرخص لأنه جدار مختلف.','gypsum.json scope_lines',true),
  ('gypsum','','deflection_head','Deflection head / slip track at the slab soffit','رأس انحراف / مجرى انزلاقي عند بطنية البلاطة','commonly_omitted','\b(deflection|slip\s*track|head\s*track|deep\s*track|slotted\s*track)\b','(رأس انحراف|مجرى انزلاقي|مجرى علوي عميق)','partition|wall|full\s*height|slab|قاطع|قواطع|جدار','flag_omission','practice','UAE','Manufacturer system manuals: deflection head detail for full-height partitions under slabs with live-load deflection (typically 15-25 mm allowance)','2014-01-01',null,'quotesdone','A full-height partition fixed rigidly to a slab that deflects will crack at the head. The deflection head (deep or slotted top track) is a separate material and labour item and is commonly omitted.','القاطع الممتد حتى البلاطة والمثبت بها تثبيتًا صلبًا يتشقق عند رأسه عندما تنحرف البلاطة. رأس الانحراف (مجرى علوي عميق أو مشقوق) بند مواد وعمالة مستقل ويُسقط عادةً.','gypsum.json scope_lines',true),
  ('gypsum','','fire_stopping','Fire stopping and sealant at head, perimeter and service penetrations','مانع انتشار الحريق ومادة الإحكام عند الرأس والمحيط واختراقات الخدمات','commonly_omitted','\b(fire\s*-?\s*stop|fire\s*-?\s*stopping|intumescent|fire\s*sealant|fire\s*mastic|penetration\s*seal)\b','(مانع حريق|مانع انتشار الحريق|مادة إحكام مقاومة للحريق|سد الاختراقات)','fire|\bfr\b|rated|حريق','flag_omission','law','UAE','UAE Fire and Life Safety Code of Practice, September 2018 edition (CDGH-OP-25), Chapter 1: fire-rated assemblies must be continuous, with penetrations and joints sealed with listed fire-stop systems (section number not verified in-browser on 21 Sep 2026)','2018-09-01',null,'government','A fire-rated partition is only rated if its head joint, perimeter and every penetration are fire-stopped with a listed system. A quotation for a fire-rated wall that omits fire stopping is not a fire-rated wall.','القاطع المقاوم للحريق لا يكون مصنّفًا إلا إذا أُحكمت وصلة رأسه ومحيطه وكل اختراق فيه بنظام مانع حريق معتمد. عرض جدار مقاوم للحريق يُسقط مانع الحريق ليس جدارًا مقاومًا للحريق.','gypsum.json scope_lines',true),
  ('gypsum','','access_panels','Access panels to services above the ceiling','فتحات وصول إلى الخدمات فوق السقف','commonly_omitted','\b(access\s*panel|access\s*panels|access\s*hatch|inspection\s*hatch)\b','(فتحة وصول|فتحات وصول|باب تفتيش|فتحة تفتيش)','gypsum\s*(false\s*)?ceiling|plasterboard\s*ceiling|bulkhead|سقف جبس|بلكونة','flag_omission','practice','UAE','Manufacturer ceiling system manuals; MEP maintenance access is a standard fit-out requirement','2014-01-01',null,'quotesdone','A plasterboard (non-demountable) ceiling needs access panels at valves, dampers and junction boxes. They are priced per unit and commonly omitted; a mineral-fibre grid ceiling does not need them.','السقف الجبسي (غير القابل للفك) يحتاج فتحات وصول عند المحابس والدمبرات وعلب التوصيل. تُسعّر بالوحدة وتُسقط عادةً؛ أما سقف البلاط المعدني الشبكي فلا يحتاجها.','gypsum.json scope_lines',true),
  ('gypsum','','cutouts_for_services','Cut-outs for lights, diffusers, sprinklers and detectors','فتحات للإنارة وفتحات التكييف والرشاشات وكواشف الحريق','commonly_omitted','\b(cut\s*-?\s*outs?|openings?\s*for|holes?\s*for|light\s*points?)\b','(فتحات|تخريم|فتحات الإنارة)','ceiling|bulkhead|سقف|أسقف','flag_omission','practice','UAE','QuotesDone cost guide cost-of-false-ceiling-uae (28 Jun 2026): cut-outs priced AED 20-60 each','2026-06-28',null,'quotesdone','Cut-outs are charged per unit in the UAE market (AED 20-60 each). A ceiling price that does not mention them will grow on site by the number of fittings.','تُحتسب الفتحات بالوحدة في سوق الإمارات (20-60 درهمًا للفتحة). سعر السقف الذي لا يذكرها سيزيد في الموقع بعدد التجهيزات.','gypsum.json scope_lines',true),
  ('gypsum','','painting_finish','Painting / decoration of the finished board','دهان / تشطيب اللوح بعد التركيب','commonly_omitted','\b(paint|painted|painting|emulsion|primer|decoration|decorated)\b','(دهان|طلاء|بوية)','paint|painted|دهان|مدهون','flag_omission','practice','UAE','Trade practice: drywall contractors quote to a finish level (Q2/Q3) and exclude paint unless stated','2026-09-21',null,'quotesdone','When the request asks for a painted finish, a quotation that does not mention painting has excluded it. Drywall contractors quote to finish level, not to paint, unless the line says so.','عندما يطلب العميل تشطيبًا مدهونًا، فإن العرض الذي لا يذكر الدهان قد استثناه. مقاولو الجبس يسعّرون إلى مستوى التشطيب لا إلى الدهان ما لم يذكر البند ذلك.','gypsum.json scope_lines',true),
  ('gypsum','','access_equipment','Mobile towers / scaffolding for ceilings above 3.5 m','أبراج متنقلة / سقالات للأسقف التي يزيد ارتفاعها على 3.5 م','commonly_omitted','\b(scaffold|scaffolding|mobile\s*tower|access\s*equipment|mewp|scissor\s*lift)\b','(سقالة|سقالات|برج متنقل|رافعة مقصية)','(?:[4-9]|1\d)(?:\.\d)?\s*(?:m\b|meter|metre|م\b)\s*(?:high|height|ceiling|ارتفاع)|high\s*level|double\s*height|atrium','flag_omission','practice','UAE','Trade practice: ceiling rates are quoted for work to about 3.5 m from a floor; above that, access equipment is a separate item','2026-09-21',null,'quotesdone','Ceiling and high-level rates assume work from the floor to about 3.5 m. Where the request states a greater height, a quotation silent on access equipment has either excluded it or under-priced the labour.','أسعار الأسقف والأعمال العلوية تفترض العمل من الأرض حتى نحو 3.5 م. عندما يذكر الطلب ارتفاعًا أكبر، فإن العرض الذي لا يذكر معدات الوصول إمّا استثناها أو قلّل تسعير العمالة.','gypsum.json scope_lines',true),
  ('gypsum','','debris_removal','Removal of off-cuts and debris from site','إزالة القصاصات والمخلفات من الموقع','commonly_omitted','\b(debris|disposal|waste|off\s*-?\s*cuts?|clean-?up|cleaning|skip)\b','(مخلفات|نفايات|تنظيف|إزالة)',null,'flag_omission','practice','Dubai','Dubai Municipality waste management: construction waste is removed by a licensed carrier to a designated facility; the charge is a real cost line (regulation number not verified in-browser on 21 Sep 2026)','2026-09-21',null,'quotesdone','Drywall generates 5-10% off-cuts by area. Debris removal is a chargeable item; a quotation that does not mention it usually leaves it to the customer.','تنتج أعمال الجبس قصاصات بنسبة 5-10% من المساحة. إزالة المخلفات بند يُحتسب؛ والعرض الذي لا يذكره يتركه للعميل عادةً.','gypsum.json scope_lines',true);
delete from public.spec_equivalence where trade_code = 'gypsum';
insert into public.spec_equivalence (trade_code, attr_code, class_key, value, equivalent, evidence_kind, approval_ref, approval_expires, decision, label, jurisdiction, citation, effective_date, expires_on, licence, rule_en, rule_ar, source_ref, active) values
  ('gypsum','board_type','board.standard_type_a','Standard gypsum board',true,'datasheet',null,null,'flag_substitution','practice','UAE','BS EN 520:2004+A1:2009, Type A: gypsum plasterboard with a face to receive decoration or plaster; no reduced water absorption, no improved core cohesion at high temperature','2009-01-01',null,'quotesdone','Type A (standard) board is the baseline for dry internal partitions and ceilings. It is the class only where the request asks for standard board.','اللوح القياسي من النوع A هو الأساس للقواطع والأسقف الداخلية الجافة. وهو الفئة المطلوبة فقط عندما يطلب العميل لوحًا قياسيًا.','gypsum.json equivalence',true),
  ('gypsum','board_type','board.moisture_resistant_type_h','Moisture-resistant board',true,'datasheet',null,null,'flag_substitution','practice','UAE','BS EN 520:2004+A1:2009, Type H1/H2/H3: reduced total water absorption (H1 <= 5%, H2 <= 10%, H3 <= 25%) and surface water absorption <= 180 g/m2','2009-01-01',null,'quotesdone','Moisture-resistant (Type H, ''MR'', green board) is the class for pantries, toilets, wet-area ceilings and any board within 300 mm of a wet floor.','اللوح المقاوم للرطوبة (النوع H، «MR»، اللوح الأخضر) هو الفئة المطلوبة للمطابخ الصغيرة ودورات المياه وأسقف المناطق الرطبة وأي لوح على بعد 300 مم من أرضية رطبة.','gypsum.json equivalence',true),
  ('gypsum','board_type','board.moisture_resistant_type_h','Standard gypsum board',false,'datasheet',null,null,'flag_substitution','practice','UAE','BS EN 520:2004+A1:2009: Type A carries no water-absorption limit; Type H does','2009-01-01',null,'quotesdone','Standard (Type A) board is NOT equivalent to moisture-resistant (Type H) board. It has no water-absorption limit and will swell and lose strength in a wet area. A quotation offering standard board against an MR request is a substitution, not a match.','اللوح القياسي (النوع A) ليس مكافئًا للوح المقاوم للرطوبة (النوع H). فلا حد لامتصاصه الماء، وسينتفخ ويفقد قوته في المناطق الرطبة. العرض الذي يقدّم لوحًا قياسيًا مقابل طلب لوح MR هو استبدال لا مطابقة.','gypsum.json equivalence',true),
  ('gypsum','board_type','board.fire_rated_type_f','Fire-rated board',true,'datasheet',null,null,'flag_substitution','practice','UAE','BS EN 520:2004+A1:2009, Type F: improved core cohesion at high temperatures (glass-fibre reinforced core); the RATING belongs to the tested system (BS EN 1364-1 / BS 476-22), not to the board alone','2009-01-01',null,'quotesdone','Fire-rated (Type F, ''FR'', pink board) is the class where a fire-resistance period is required. The period (30/60/90/120 min) comes from the tested system (board type, thickness, layers, stud, insulation), not from the board alone.','اللوح المقاوم للحريق (النوع F، «FR»، اللوح الوردي) هو الفئة المطلوبة عندما تُشترط مدة مقاومة للحريق. المدة (30/60/90/120 دقيقة) تأتي من النظام المختبر (نوع اللوح وسماكته وعدد الطبقات والقائم والعزل)، لا من اللوح وحده.','gypsum.json equivalence',true),
  ('gypsum','board_type','board.fire_rated_type_f','Standard gypsum board',false,'datasheet',null,null,'flag_substitution','law','UAE','BS EN 520:2004+A1:2009 Type A vs Type F; UAE Fire and Life Safety Code of Practice, September 2018 (CDGH-OP-25) requires fire-rated assemblies to be tested / listed systems','2018-09-01',null,'government','Standard (Type A) board is NOT equivalent to fire-rated (Type F) board. Its core loses cohesion in fire and the assembly has no tested rating. Offering it against a fire-rated request voids the fire rating and the Civil Defence approval of the wall.','اللوح القياسي (النوع A) ليس مكافئًا للوح المقاوم للحريق (النوع F). يفقد قلبه تماسكه في الحريق ولا يحمل التركيب أي تصنيف مختبر. تقديمه مقابل طلب لوح مقاوم للحريق يُبطل تصنيف الحريق واعتماد الدفاع المدني للجدار.','gypsum.json equivalence',true),
  ('gypsum','board_type','board.fire_rated_type_f','Moisture-resistant board',false,'datasheet',null,null,'flag_substitution','practice','UAE','BS EN 520:2004+A1:2009: Type H addresses water absorption, not core cohesion at high temperature; a board is Type FH2 (both) only if so classified','2009-01-01',null,'quotesdone','Moisture-resistant board is NOT a fire-rated board. Only a board classified as both (e.g. Type FH2 / ''FR-MR'') satisfies a request for fire-rated board in a wet area.','اللوح المقاوم للرطوبة ليس لوحًا مقاومًا للحريق. اللوح المصنّف بالخاصيتين معًا (مثل النوع FH2 / «FR-MR») هو وحده ما يفي بطلب لوح مقاوم للحريق في منطقة رطبة.','gypsum.json equivalence',true),
  ('gypsum','board_type','board.acoustic','Acoustic board',true,'datasheet',null,null,'flag_substitution','practice','UAE','BS EN 520:2004+A1:2009 Type D (controlled density) / high-density acoustic boards per manufacturer datasheet; laboratory Rw per ISO 10140-2','2009-01-01',null,'quotesdone','Acoustic (high-density, Type D or manufacturer ''sound'' board) is the class where the request states an Rw or dB target. The target is met by the build-up, so the quotation must also state layers, stud and insulation.','اللوح الصوتي (عالي الكثافة، النوع D أو لوح «الصوت» لدى المصنّع) هو الفئة المطلوبة عندما يحدد الطلب معامل Rw أو هدفًا بالديسيبل. الهدف يتحقق بالتركيب كاملًا، لذا يجب أن يذكر العرض الطبقات والقائم والعزل أيضًا.','gypsum.json equivalence',true),
  ('gypsum','board_type','board.acoustic','Standard gypsum board',false,'datasheet',null,null,'flag_substitution','practice','UAE','Manufacturer acoustic build-up tables: single-layer 12.5 mm Type A each side, 70 mm stud, no insulation about Rw 38-40 dB; high-density board + 50 mm mineral wool about Rw 48-52 dB (laboratory, ISO 10140-2)','2009-01-01',null,'quotesdone','Standard board is NOT equivalent to acoustic board where an Rw target was requested: the same wall drops roughly 8-12 dB. It is a substitution, not a match.','اللوح القياسي ليس مكافئًا للوح الصوتي عندما يُطلب معامل Rw محدد: الجدار نفسه ينخفض عزله بنحو 8-12 ديسيبل. هذا استبدال لا مطابقة.','gypsum.json equivalence',true),
  ('gypsum','board_type','ceiling.mineral_fibre_600','Mineral fibre tile',true,'datasheet',null,null,'flag_substitution','practice','UAE','BS EN 13964:2014 suspended ceilings; tile acoustic values NRC (ASTM C423) / alpha-w (ISO 11654) and CAC (ASTM E1414) from the manufacturer datasheet; reaction to fire EN 13501-1 class','2014-01-01',null,'quotesdone','A 600x600 mineral-fibre (or stone-wool) lay-in tile on an exposed grid is the class for a demountable, accessible ceiling. Comparable tiles state NRC (or alpha-w), CAC, thickness, edge (square / tegular) and EN 13501-1 class.','بلاط الألياف المعدنية (أو الصوف الصخري) 600×600 على شبكة مكشوفة هو الفئة المطلوبة للسقف القابل للفك والوصول. البلاط القابل للمقارنة يذكر NRC (أو αw) وCAC والسماكة ونوع الحافة (مستقيمة/تيغولار) وتصنيف EN 13501-1.','gypsum.json equivalence',true),
  ('gypsum','board_type','ceiling.mineral_fibre_600','Standard gypsum board',false,'datasheet',null,null,'flag_substitution','practice','UAE','BS EN 13964:2014: a plasterboard ceiling on concealed grid is a different, non-demountable system with no lay-in access and no tile NRC/CAC','2014-01-01',null,'quotesdone','A plasterboard ceiling is NOT equivalent to a 600x600 mineral-fibre tile ceiling. It cannot be lifted for access, has no tile acoustic rating and needs cut access panels. A quotation offering gypsum board against a tile request is a substitution.','السقف الجبسي ليس مكافئًا لسقف بلاط الألياف المعدنية 600×600. لا يمكن رفعه للوصول، ولا يحمل تصنيفًا صوتيًا للبلاط، ويحتاج فتحات وصول مقطوعة. العرض الذي يقدّم لوح جبس مقابل طلب بلاط هو استبدال.','gypsum.json equivalence',true),
  ('gypsum','thickness_mm','thickness.partition_12.5','12.5',true,'datasheet',null,null,'flag_substitution','practice','UAE','BS EN 520 nominal thicknesses; manufacturer system tables: 12.5 mm is the minimum single-layer board for partitions; 9.5 mm is a ceiling / lining board only','2009-01-01',null,'quotesdone','12.5 mm is the standard single-layer partition board and the thickness in every published UAE partition rate.','12.5 مم هي السماكة القياسية للوح القاطع أحادي الطبقة، وهي السماكة في كل سعر قاطع منشور في الإمارات.','gypsum.json equivalence',true),
  ('gypsum','thickness_mm','thickness.partition_12.5','9.5',false,'datasheet',null,null,'flag_substitution','practice','UAE','Manufacturer system tables: 9.5 mm board is not listed in partition height tables; impact resistance and screw-holding are below 12.5 mm','2009-01-01',null,'quotesdone','9.5 mm board is NOT equivalent to 12.5 mm on a partition: it is a ceiling board, weaker in impact and screw-holding, and the manufacturer height tables do not cover it. A cheaper price with 9.5 mm is a thinner wall.','لوح 9.5 مم ليس مكافئًا للوح 12.5 مم في القاطع: فهو لوح أسقف، أضعف في مقاومة الصدم وتثبيت البراغي، وجداول الارتفاع لدى المصنّع لا تشمله. السعر الأرخص بلوح 9.5 مم هو جدار أنحف.','gypsum.json equivalence',true),
  ('gypsum','thickness_mm','thickness.fire_15','15',true,'datasheet',null,null,'flag_substitution','practice','UAE','Manufacturer fire-test listings (BS EN 1364-1): 1 x 15 mm Type F each side about 60 min; 2 x 12.5 mm or 2 x 15 mm Type F each side about 90-120 min depending on system','2009-01-01',null,'quotesdone','15 mm Type F single layer each side is the usual 60-minute build-up; 90 and 120 minutes need two layers. The rating changes with every parameter (board, layers, stud, insulation), so the tested system reference must be quoted.','لوح 15 مم من النوع F بطبقة واحدة لكل وجه هو التركيب المعتاد لمدة 60 دقيقة؛ أما 90 و120 دقيقة فتحتاج طبقتين. التصنيف يتغير مع كل عامل (اللوح والطبقات والقائم والعزل)، لذا يجب ذكر مرجع النظام المختبر.','gypsum.json equivalence',true),
  ('gypsum','thickness_mm','thickness.fire_15','12.5',false,'datasheet',null,null,'flag_substitution','practice','UAE','Manufacturer fire-test listings (BS EN 1364-1): a single 12.5 mm Type F layer each side is typically listed at 30 min, not 60','2009-01-01',null,'quotesdone','12.5 mm is NOT equivalent to 15 mm in a fire-rated build-up: single-layer 12.5 mm Type F is typically a 30-minute system, single-layer 15 mm a 60-minute one. Substituting the thinner board halves the rating.','لوح 12.5 مم ليس مكافئًا للوح 15 مم في تركيب مقاوم للحريق: الطبقة الواحدة من 12.5 مم نوع F هي عادةً نظام 30 دقيقة، والطبقة الواحدة من 15 مم نظام 60 دقيقة. استبدال اللوح الأنحف يُنصّف التصنيف.','gypsum.json equivalence',true),
  ('gypsum','frame','stud.gauge_0.6','0.6 mm',true,'datasheet',null,null,'flag_substitution','practice','UAE','BS EN 14195:2014 metal framing; manufacturer height tables: 0.6 mm gauge C-stud, 70 mm at 600 mm centres about 3.3-3.6 m; 92-100 mm about 4.0-4.5 m; 150 mm about 5.5-6.0 m (values vary by system and deflection limit L/240)','2014-01-01',null,'quotesdone','0.6 mm galvanised C-stud is the standard partition gauge in UAE fit-out. Maximum height is set by stud width x gauge x centres against a deflection limit; the quotation must state all three.','القائم المجلفن على شكل C بسماكة 0.6 مم هو المقياس القياسي للقواطع في تجهيزات الإمارات. الارتفاع الأقصى يحدده عرض القائم × سماكة الصاج × المسافة بين القوائم مقابل حد الانحراف؛ ويجب أن يذكر العرض الثلاثة.','gypsum.json equivalence',true),
  ('gypsum','frame','stud.gauge_0.6','0.5 mm',false,'datasheet',null,null,'flag_substitution','practice','UAE','Manufacturer height tables: a 0.5 mm stud of the same width carries roughly 10-15% less height at the same deflection limit','2014-01-01',null,'quotesdone','0.5 mm stud is NOT equivalent to 0.6 mm: same width, lower stiffness, lower maximum height and weaker screw pull-out. On partitions above 3 m it is a different wall.','القائم بسماكة 0.5 مم ليس مكافئًا لسماكة 0.6 مم: العرض نفسه لكن صلابة أقل وارتفاعًا أقصى أقل وتثبيتًا أضعف للبراغي. في القواطع التي تزيد على 3 م هو جدار مختلف.','gypsum.json equivalence',true),
  ('gypsum','brand','brand.plasterboard_uae','Knauf',true,'datasheet','knauf.com/en-ae, UAE regional site, states ''locally manufactured boards'' for GCC projects (fetched 21 Sep 2026)','2027-09-21','flag_substitution','manufacturer_data','UAE','Knauf UAE regional website (knauf.com/en-ae), fetched 21 Sep 2026: gypsum boards locally manufactured for GCC projects','2026-09-21','2027-09-21','manufacturer_public','Knauf is a plasterboard brand manufactured in and supplied to the UAE (manufacturer''s own regional site). Membership of this class means ''available in the UAE with published datasheets'', not ''better than'' another member.','Knauf علامة ألواح جبس تُصنّع في الإمارات وتُورَّد إليها (موقع المصنّع الإقليمي). الانتماء إلى هذه الفئة يعني «متوفر في الإمارات بنشرات فنية منشورة»، لا «أفضل من» عضو آخر.','gypsum.json equivalence',true),
  ('gypsum','brand','brand.plasterboard_uae','Gyproc',true,'datasheet','gyproc.ae returned HTTP 403 to the fetch on 21 Sep 2026; NOT verified','2027-09-21','flag_substitution','manufacturer_data','UAE','Saint-Gobain Gyproc Middle East regional site (gyproc.ae): not fetched (403) on 21 Sep 2026','2026-09-21','2027-09-21','manufacturer_public','Gyproc (Saint-Gobain) plasterboard: authored as a UAE-supplied brand but NOT live. Its regional site could not be fetched on 21 Sep 2026, so the presence is unverified.','ألواح Gyproc (سان جوبان): أُدرجت كعلامة مورَّدة في الإمارات لكنها غير مفعّلة. تعذّر جلب موقعها الإقليمي في 21 سبتمبر 2026، فالوجود غير متحقق منه.','gypsum.json equivalence',false),
  ('gypsum','brand','brand.plasterboard_uae','USG Boral',true,'datasheet','usg.com Middle East page fetched 21 Sep 2026: no UAE presence stated; NOT verified','2027-09-21','flag_substitution','manufacturer_data','UAE','USG Middle East site (usg.com/content/usgcom/en_ME.html) fetched 21 Sep 2026: states no UAE presence','2026-09-21','2027-09-21','manufacturer_public','USG Boral plasterboard: authored but NOT live. The manufacturer page fetched on 21 Sep 2026 states no UAE presence.','ألواح USG Boral: أُدرجت لكنها غير مفعّلة. صفحة المصنّع التي جُلبت في 21 سبتمبر 2026 لا تذكر وجودًا في الإمارات.','gypsum.json equivalence',false),
  ('gypsum','brand','brand.plasterboard_uae','Siniat',true,'datasheet','siniat.com redirected to the UK site on 21 Sep 2026; no UAE page found; NOT verified','2027-09-21','flag_substitution','manufacturer_data','UAE','Siniat (Etex): no UAE regional page reached on 21 Sep 2026','2026-09-21','2027-09-21','manufacturer_public','Siniat plasterboard: authored but NOT live. No UAE manufacturer page was reached on 21 Sep 2026.','ألواح Siniat: أُدرجت لكنها غير مفعّلة. لم يُتوصَّل إلى صفحة للمصنّع في الإمارات في 21 سبتمبر 2026.','gypsum.json equivalence',false),
  ('gypsum','brand','brand.mineral_fibre_tile_uae','Armstrong',true,'datasheet','armstrongceilings.com/commercial/en-me returned HTTP 410 on 21 Sep 2026; NOT verified','2027-09-21','flag_substitution','manufacturer_data','UAE','Armstrong Ceilings Middle East page: gone (410) on 21 Sep 2026','2026-09-21','2027-09-21','manufacturer_public','Armstrong mineral-fibre tiles: authored but NOT live. The Middle East page returned 410 on 21 Sep 2026.','بلاط Armstrong من الألياف المعدنية: أُدرج لكنه غير مفعّل. صفحة الشرق الأوسط أعادت 410 في 21 سبتمبر 2026.','gypsum.json equivalence',false),
  ('gypsum','brand','brand.mineral_fibre_tile_uae','Rockfon',true,'datasheet','rockfon.ae did not resolve and rockfon.com/me returned 500 on 21 Sep 2026; NOT verified','2027-09-21','flag_substitution','manufacturer_data','UAE','Rockfon (ROCKWOOL) Middle East: not reachable on 21 Sep 2026','2026-09-21','2027-09-21','manufacturer_public','Rockfon stone-wool tiles: authored but NOT live. The Middle East site was not reachable on 21 Sep 2026.','بلاط Rockfon من الصوف الصخري: أُدرج لكنه غير مفعّل. تعذّر الوصول إلى موقع الشرق الأوسط في 21 سبتمبر 2026.','gypsum.json equivalence',false);
delete from public.trade_comparability where trade_code = 'gypsum';
insert into public.trade_comparability (trade_code, line_type, line_regex, required_attrs, decision, label, jurisdiction, citation, effective_date, expires_on, licence, rule_en, rule_ar, source_ref, active) values
  ('gypsum','partition','partition|drywall|stud\s*wall|قاطع|قواطع|جدار جبس',array['board_type','thickness_mm','frame']::text[],'not_comparable','practice','UAE','BS EN 520 (board type, thickness) and BS EN 14195 (stud) define the partition; a price without them prices an undefined wall','2014-01-01',null,'quotesdone','Two partition prices are comparable only when both state board type, board thickness and the stud system. If either is silent on any of the three, the line is reported as not comparable rather than ranked.','لا يمكن مقارنة سعرَي قاطعين إلا عندما يذكر كلاهما نوع اللوح وسماكته ونظام القوائم. إذا سكت أحدهما عن أيٍّ من الثلاثة، يُبلَّغ عن البند بأنه غير قابل للمقارنة بدلًا من ترتيبه.','gypsum.json comparability',true),
  ('gypsum','gypsum_ceiling','(gypsum|plain|plasterboard|board|cove|tray|designed)\s*(false\s*)?ceiling|bulkhead|سقف جبس|بلكونة|كورنيش',array['board_type','thickness_mm','frame']::text[],'not_comparable','practice','UAE','BS EN 520 (board) and BS EN 13964 (suspension) define a plasterboard ceiling','2014-01-01',null,'quotesdone','Two plasterboard ceiling or bulkhead prices are comparable only when both state board type, thickness and the furring/suspension system.','لا يمكن مقارنة سعرَي سقف جبسي أو بلكونة إلا عندما يذكر كلاهما نوع اللوح وسماكته ونظام القنوات/التعليق.','gypsum.json comparability',true),
  ('gypsum','tile_ceiling','mineral|fib(?:er|re)\s*tile|tile\s*ceiling|grid\s*ceiling|600\s*[x×]\s*600|بلاط|شبكة',array['board_type','thickness_mm','brand']::text[],'not_comparable','practice','UAE','BS EN 13964; tile NRC/CAC and EN 13501-1 class are brand- and product-specific, so the brand/product is part of the specification','2014-01-01',null,'quotesdone','Two tile-ceiling prices are comparable only when both state the tile type, thickness and brand/product: acoustic and fire values belong to the product, not to ''600x600 tile''.','لا يمكن مقارنة سعرَي سقف بلاط إلا عندما يذكر كلاهما نوع البلاط وسماكته والعلامة/المنتج: القيم الصوتية وقيم الحريق تخص المنتج لا عبارة «بلاط 600×600».','gypsum.json comparability',true);
delete from public.trade_approval where trade_code = 'gypsum';
insert into public.trade_approval (trade_code, emirate, authority, approval_en, approval_ar, stage, evidence_doc, cost_bearer, applies_regex, decision, label, jurisdiction, citation, effective_date, expires_on, licence, rule_en, rule_ar, source_ref, active) values
  ('gypsum','Dubai','Dubai Civil Defence','Fire-rated partition / ceiling system: tested-system certificate (BS EN 1364-1 or BS 476-22) and Civil Defence product approval for the boards and fire-stop','نظام قاطع/سقف مقاوم للحريق: شهادة نظام مختبر (BS EN 1364-1 أو BS 476-22) واعتماد الدفاع المدني للألواح ومانع الحريق','before_works','Civil Defence material approval certificate + fire test report for the exact system','supplier','fire|\bfr\b|rated|حريق','approval_required','law','Dubai','UAE Fire and Life Safety Code of Practice, September 2018 edition (CDGH-OP-25), published by Civil Defence (dcd.gov.ae, fetched 21 Sep 2026); Chapter 1 governs building materials and fire-rated assemblies; the section number was not verified in-browser on 21 Sep 2026','2018-09-01',null,'government','Where a fire-rated partition or ceiling is requested in Dubai, the supplier must produce the tested-system certificate and Civil Defence approval of the materials before works. A quotation that excludes these, or a supplier that cannot produce them, is flagged.','عندما يُطلب قاطع أو سقف مقاوم للحريق في دبي، يجب أن يقدّم المورّد شهادة النظام المختبر واعتماد الدفاع المدني للمواد قبل بدء الأعمال. العرض الذي يستثنيها، أو المورّد الذي لا يستطيع تقديمها، يُعلَّم.','gypsum.json approvals',true),
  ('gypsum','Abu Dhabi','Abu Dhabi Civil Defence','Fire-rated partition / ceiling system: tested-system certificate and Civil Defence approval of materials','نظام قاطع/سقف مقاوم للحريق: شهادة نظام مختبر واعتماد الدفاع المدني للمواد','before_works','Civil Defence material approval certificate + fire test report','supplier','fire|\bfr\b|rated|حريق','approval_required','law','Abu Dhabi','UAE Fire and Life Safety Code of Practice, September 2018 (CDGH-OP-25), applied nationally by each emirate''s Civil Defence; Abu Dhabi-specific circulars not verified on 21 Sep 2026','2018-09-01',null,'government','Same requirement as Dubai under the national code, administered by Abu Dhabi Civil Defence.','المتطلب نفسه كما في دبي بموجب الكود الوطني، ويديره الدفاع المدني في أبوظبي.','gypsum.json approvals',true),
  ('gypsum','Dubai','Dubai Municipality / Trakhees / DDA (by plot jurisdiction)','Fit-out / interior modification permit before partition and ceiling works in a leased or owned unit','تصريح تجهيز / تعديل داخلي قبل أعمال القواطع والأسقف في وحدة مؤجرة أو مملوكة','before_works','Fit-out permit (DM building permit, Trakhees or DDA fit-out NOC) and landlord NOC','either',null,'approval_required','practice','Dubai','Dubai Building Code 2021 and the building-permit regime of Dubai Municipality; free-zone plots are administered by Trakhees (PCFC) or DDA; the exact clause was not verified in-browser on 21 Sep 2026','2021-01-01',null,'quotesdone','Office and retail fit-out partitions and ceilings need a fit-out permit from the plot''s authority and the landlord''s NOC. A quotation should say who obtains it and whether the fee is included; silence usually leaves it with the customer.','قواطع وأسقف تجهيز المكاتب والمحلات تحتاج تصريح تجهيز من جهة القطعة وموافقة المالك. ينبغي أن يذكر العرض من يستخرجه وما إذا كانت الرسوم مشمولة؛ والسكوت يتركه للعميل عادةً.','gypsum.json approvals',true),
  ('gypsum','UAE','Department of Economy (trade licence)','Supplier''s trade licence activity covers gypsum / false ceiling / partition works','نشاط الرخصة التجارية للمورّد يشمل أعمال الجبس / الأسقف المستعارة / القواطع','supplier_licence','Trade licence with a gypsum, false-ceiling, partitions or interior-decoration activity','supplier',null,'approval_required','practice','UAE','QuotesDone supplier verification: the mandatory six (licence is one); DET activity codes not verified in-browser on 21 Sep 2026','2026-09-01',null,'quotesdone','A supplier quoting gypsum works must hold a licence whose activity covers them. This is checked at supplier verification, not per quotation; it is listed here so the report can say which approvals were checked.','المورّد الذي يقدّم عرضًا لأعمال الجبس يجب أن يحمل رخصة يشمل نشاطها هذه الأعمال. يُتحقق من ذلك عند اعتماد المورّد لا لكل عرض؛ وأُدرج هنا ليقول التقرير أي الاعتمادات فُحصت.','gypsum.json approvals',true);
update public.price_benchmark set trade_code = 'gypsum', line_regex = 'partition|drywall|قاطع|قواطع', red_flag_reason_en = 'Gypsum partition, 12.5 mm board both faces on 0.6 mm studs, taped and finished: AED 60-130/m2 in the UAE. Below the band usually means 9.5 mm board, 0.5 mm studs, no insulation, no jointing/finish, or unlicensed labour; above it means acoustic/fire spec, double layers, height above 3.5 m or a very small quantity.', red_flag_reason_ar = 'قاطع جبس بلوح 12.5 مم على الوجهين على قوائم 0.6 مم مع الوصلات والتشطيب: 60-130 درهمًا/م² في الإمارات. ما دون النطاق يعني عادةً لوح 9.5 مم أو قوائم 0.5 مم أو بلا عزل أو بلا وصلات وتشطيب أو عمالة غير مرخّصة؛ وما فوقه يعني مواصفة صوتية/حريق أو طبقتين أو ارتفاعًا فوق 3.5 م أو كمية صغيرة جدًا.', red_flag_citation = 'QuotesDone cost guide cost-of-false-ceiling-uae (28 Jun 2026): gypsum partition wall AED 60-130 per sqm supply and install', red_flag_effective_date = '2026-06-28', red_flag_expires_on = '2027-06-28', red_flag_label = 'practice', red_flag_licence = 'quotesdone' where id = 84 and item = 'Gypsum partition wall (per sqm)' and unit = 'sqm' and low = 60 and high = 130;
update public.price_benchmark set trade_code = 'gypsum', line_regex = '(gypsum|plain|plasterboard|board)\s*(false\s*)?ceiling|bulkhead|سقف جبس|بلكونة|كورنيش', red_flag_reason_en = 'Plain gypsum board ceiling on furring channels: AED 35-70/m2. Below the band means 9 mm board, wide channel spacing, no perimeter trim or no finish; above it means bulkheads/cove details, MR or FR board, or high-level access.', red_flag_reason_ar = 'سقف جبس مستوٍ على قنوات: 35-70 درهمًا/م². ما دون النطاق يعني لوح 9 مم أو تباعدًا واسعًا للقنوات أو بلا شريط محيط أو بلا تشطيب؛ وما فوقه يعني تفاصيل بلكونات/كورنيش أو لوح MR أو FR أو وصولًا علويًا.', red_flag_citation = 'QuotesDone cost guide cost-of-false-ceiling-uae (28 Jun 2026): plain gypsum ceiling AED 35-70 per sqm', red_flag_effective_date = '2026-06-28', red_flag_expires_on = '2027-06-28', red_flag_label = 'practice', red_flag_licence = 'quotesdone' where id = 86 and item = 'Plain gypsum ceiling (per sqm)' and unit = 'sqm' and low = 35 and high = 70;
update public.price_benchmark set trade_code = 'gypsum', line_regex = 'mineral|tile|grid|600\s*[x×]\s*600|بلاط|شبكة', red_flag_reason_en = '600x600 mineral-fibre lay-in tile on exposed T-grid: AED 45-90/m2. Below the band means an unbranded 12 mm tile with no stated NRC/CAC, a light-duty grid, or tiles without the grid; above it means a branded 15-19 mm tile with NRC >= 0.7, tegular edge, or a corrosion-class grid.', red_flag_reason_ar = 'بلاط ألياف معدنية 600×600 على شبكة T مكشوفة: 45-90 درهمًا/م². ما دون النطاق يعني بلاطًا بلا علامة بسماكة 12 مم دون NRC/CAC مذكور، أو شبكة خفيفة، أو بلاطًا بلا شبكة؛ وما فوقه يعني بلاطًا من علامة معروفة بسماكة 15-19 مم وNRC ≥ 0.7 أو حافة تيغولار أو شبكة بتصنيف مقاومة للتآكل.', red_flag_citation = 'QuotesDone cost guide cost-of-false-ceiling-uae (28 Jun 2026): grid / mineral-fibre tile ceiling AED 45-90 per sqm', red_flag_effective_date = '2026-06-28', red_flag_expires_on = '2027-06-28', red_flag_label = 'practice', red_flag_licence = 'quotesdone' where id = 83 and item = 'Grid / mineral-fibre tile ceiling (per sqm)' and unit = 'sqm' and low = 45 and high = 90;
update public.price_benchmark set trade_code = 'gypsum', line_regex = 'cove|tray|design|coffer|stepped|curved|كورنيش|مجوف|تصميم', red_flag_reason_en = 'Designed ceilings (coves, trays, steps, curves): AED 60-120/m2. The extra over a plain ceiling is framing labour; a price at plain-ceiling level for a designed ceiling has not priced the framing.', red_flag_reason_ar = 'الأسقف المصمّمة (كورنيش، مجوف، مدرّج، منحنٍ): 60-120 درهمًا/م². الزيادة عن السقف المستوي هي عمالة الهيكل؛ والسعر بمستوى السقف المستوي لسقف مصمّم لم يسعّر الهيكل.', red_flag_citation = 'QuotesDone cost guide cost-of-false-ceiling-uae (28 Jun 2026): designed / cove / tray ceiling AED 60-120 per sqm', red_flag_effective_date = '2026-06-28', red_flag_expires_on = '2027-06-28', red_flag_label = 'practice', red_flag_licence = 'quotesdone' where id = 82 and item = 'Designed / cove / tray ceiling (per sqm)' and unit = 'sqm' and low = 60 and high = 120;
update public.price_benchmark set trade_code = 'gypsum', line_regex = 'cut\s*-?\s*out|opening|فتحة|فتحات', red_flag_reason_en = 'Cut-outs for lights and diffusers: AED 20-60 each. Above the band is usually a diffuser frame or a curved opening; a zero price means they were folded into the m2 rate and should be so stated.', red_flag_reason_ar = 'فتحات الإنارة وفتحات التكييف: 20-60 درهمًا للفتحة. ما فوق النطاق هو عادةً إطار فتحة تكييف أو فتحة منحنية؛ والسعر الصفري يعني أنها أُدمجت في سعر المتر المربع ويجب النص على ذلك.', red_flag_citation = 'QuotesDone cost guide cost-of-false-ceiling-uae (28 Jun 2026): light / AC cut-outs AED 20-60 each', red_flag_effective_date = '2026-06-28', red_flag_expires_on = '2027-06-28', red_flag_label = 'practice', red_flag_licence = 'quotesdone' where id = 85 and item = 'Light / AC cut-outs (each)' and unit = 'each' and low = 20 and high = 60;
-- ==== END SEED gypsum ====

-- ---------------------------------------------------------------------------------------------
-- 6. Probe: read the gypsum rules back through the function the engine uses. One verdict ROW.
--    Expected live counts (active rows only): scope_lines 13, equivalence 17 (22 authored, 5 brand
--    rows inactive pending in-browser verification), price_flags 5, comparability 3, approvals 4.
-- ---------------------------------------------------------------------------------------------
with r as (select public.fn_trade_rules('gypsum') as j)
select case
         when jsonb_array_length(j->'scope_lines') = 13
          and jsonb_array_length(j->'equivalence') = 17
          and jsonb_array_length(j->'price_flags') = 5
          and jsonb_array_length(j->'comparability') = 3
          and jsonb_array_length(j->'approvals') = 4
          and not exists (select 1 from public.v_trade_rules_live where trade_code = 'gypsum' and (rule->>'rule_ar') !~ '[ء-ي]')
         then 'PROBE OK'
         else 'PROBE FAILED'
       end as verdict,
       jsonb_array_length(j->'scope_lines') as scope_lines, jsonb_array_length(j->'equivalence') as equivalence,
       jsonb_array_length(j->'price_flags') as price_flags, jsonb_array_length(j->'comparability') as comparability,
       jsonb_array_length(j->'approvals') as approvals
  from r;
