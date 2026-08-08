-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706020122   name: materials_and_supplier_capabilities
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Material Knowledge Library
create table if not exists materials (
  id bigint generated always as identity primary key,
  category text not null,
  item text not null,
  properties jsonb default '{}'::jsonb,
  standards text[] default '{}',
  price_band text,
  alternatives jsonb default '[]'::jsonb,
  pros text[] default '{}',
  cons text[] default '{}',
  source text,
  created_at timestamptz default now()
);
create index if not exists materials_cat on materials(category);
alter table materials enable row level security;
revoke all on materials from anon, authenticated;

-- Structured Supplier Capability profile (populated at/after onboarding)
create table if not exists supplier_capabilities (
  supplier_id bigint primary key references leads(id) on delete cascade,
  services text[] default '{}',
  brands text[] default '{}',
  authorized_distributor jsonb default '[]'::jsonb,
  certifications text[] default '{}',
  team_size int, engineers int, technicians int,
  equipment text[] default '{}',
  coverage_emirates text[] default '{}',
  insurance jsonb default '{}'::jsonb,          -- {professional_indemnity, public_liability, workmen}
  warranty_policy text,
  emergency_support boolean,
  response_time_hours numeric,
  languages text[] default '{}',
  fleet int, warehouse text,
  min_project_value numeric, max_project_value numeric,
  annual_capacity text, years_in_business int,
  updated_at timestamptz default now()
);
alter table supplier_capabilities enable row level security;
revoke all on supplier_capabilities from anon, authenticated;

-- Seed flagship materials
insert into materials (category, item, properties, standards, price_band, alternatives, pros, cons, source) values
('interior-design','Fire-rated door (FD60)',
 '{"core":"Mineral/solid timber core","fire_rating":"60 minutes","typical_leaf_thickness_mm":"54-58","intumescent_seals":"required","vision_panel":"fire-rated glazing optional","hardware":"CE/UL fire-rated hinges & closer"}'::jsonb,
 array['UAE Fire Code','BS 476-22','EN 1634-1','UL 10C'],'Mid–High',
 '[{"item":"FD30 door","note":"30-min rating where code permits"},{"item":"Steel fire door","note":"higher durability, industrial"}]'::jsonb,
 array['Certified fire performance','Durable, code-compliant'], array['Heavier','Requires certified installation & ironmongery'],'QuotesDone material library'),
('cctv-security','IP dome camera (4MP)',
 '{"resolution":"4MP","sensor":"1/3in CMOS","lens":"2.8-3.6mm","ir_range_m":"20-30","ip_rating":"IP66/IP67","poe":"802.3af","onvif":"Profile S","codec":"H.265"}'::jsonb,
 array['ONVIF Profile S','IEC 62676','SIRA-approved models'],'Low–Mid',
 '[{"item":"Bullet camera","note":"longer range, visible deterrent"},{"item":"Turret camera","note":"less IR flare"}]'::jsonb,
 array['Discreet','Wide coverage','PoE single-cable'], array['Limited zoom','Ceiling mount preferred'],'QuotesDone material library'),
('electrical','XLPE/PVC copper cable',
 '{"conductor":"Copper","insulation":"XLPE or PVC","voltage_rating":"450/750V or 0.6/1kV","common_sizes_mm2":"1.5, 2.5, 4, 6, 10, 16","colour_code":"per DEWA"}'::jsonb,
 array['DEWA regulations','BS 6004','IEC 60227'],'Market-linked (copper)',
 '[{"item":"Aluminium cable","note":"lower cost for large feeders, larger size"}]'::jsonb,
 array['Reliable','DEWA-compliant sizing'], array['Copper price volatility'],'QuotesDone material library');

-- Extend Knowledge Factory refresh to include materials
create or replace function kb_sync() returns jsonb language plpgsql as $$
declare n int;
begin
  delete from kb_chunks where source_kind in ('regulation','trade','material');
  insert into kb_chunks(source_kind,source_id,category,title,content,citation,effective_date)
  select 'regulation', r.id::text, cat, r.title,
    coalesce(r.summary,'') || case when jsonb_array_length(coalesce(r.key_requirements,'[]'::jsonb))>0
      then E'\nKey requirements: ' || (select string_agg(x, '; ') from jsonb_array_elements_text(r.key_requirements) x) else '' end,
    r.authority || ' — ' || r.title || coalesce(' [' || r.source_url || ']','') || coalesce(' (effective ' || r.effective_date::text || ')',''),
    r.effective_date
  from regulations r
  left join lateral unnest(case when array_length(r.categories,1) is null then array[null::text] else r.categories end) as cat on true
  where r.status = 'active';
  insert into kb_chunks(source_kind,source_id,category,title,content,citation,effective_date)
  select 'trade', ak.id::text, ak.agent_key, ak.topic, ak.content,
    'QuotesDone trade knowledge: ' || coalesce(ak.agent_key,'') || ' / ' || coalesce(ak.topic,''), null
  from agent_knowledge ak;
  insert into kb_chunks(source_kind,source_id,category,title,content,citation,effective_date)
  select 'material', m.id::text, m.category, m.item,
    m.item || ' — ' || coalesce(m.properties::text,'') ||
      case when array_length(m.standards,1) is not null then E'\nStandards: ' || array_to_string(m.standards,', ') else '' end ||
      case when m.price_band is not null then E'\nPrice band: ' || m.price_band else '' end,
    'QuotesDone material library: ' || m.item, null
  from materials m;
  select count(*) into n from kb_chunks;
  return jsonb_build_object('chunks', n);
end $$;
revoke all on function kb_sync() from anon, authenticated;

select kb_sync();
