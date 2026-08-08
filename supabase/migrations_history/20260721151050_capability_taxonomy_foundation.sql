-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260721151050   name: capability_taxonomy_foundation
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Controlled vocabulary shared by BOTH sides of the match. Additive only.
-- Nothing here is read by any live code path yet; wiring into route_inquiry is a separate, gated step.

create table if not exists public.taxonomy_authority (
  code        text primary key,
  label       text not null,
  emirates    text[] not null default '{}',   -- which emirates this body governs
  reg_catalog_ids int[] not null default '{}',
  notes       text
);

create table if not exists public.taxonomy_trade (
  code        text primary key,
  label       text not null,
  aliases     text[] not null default '{}',   -- maps legacy free-text sector/products onto the code
  authority_required text[] not null default '{}',  -- generic authority codes that are MANDATORY for this trade
  sort        int not null default 100,
  active      boolean not null default true
);

create table if not exists public.taxonomy_role (
  code        text primary key,
  label       text not null,
  aliases     text[] not null default '{}',
  supplies    boolean not null default false,  -- can provide goods
  executes    boolean not null default false,  -- can perform work on site
  whole_scope boolean not null default false,  -- can take a multi-trade / turnkey scope
  sort        int not null default 100,
  active      boolean not null default true
);

-- ---------------- authorities (sourced from reg_catalog) ----------------
insert into public.taxonomy_authority (code,label,emirates,reg_catalog_ids,notes) values
 ('civil_defence','Civil Defence (MOI / DCD / ADCD / SCD)','{dubai,abu_dhabi,sharjah,ajman,rak,fujairah,uaq}','{1,9,21,30}','Mandatory approval to design/install/maintain fire & life-safety systems.'),
 ('electrical_utility','Electricity & water authority (DEWA/ADDC/AADC/SEWA/FEWA)','{dubai,abu_dhabi,sharjah,ajman,rak,fujairah,uaq}','{7,10,23,24,29}','Contractor must be enrolled with the emirate utility for connected electrical work.'),
 ('sira','SIRA (Dubai Police)','{dubai}','{12}','Mandatory for security systems: CCTV, access control, alarms.'),
 ('trakhees','Trakhees (PCFC)','{dubai}','{16}','Free-zone EHS/building approvals.'),
 ('dda','Dubai Development Authority (TECOM)','{dubai}','{17}','DDA free-zone fit-out approvals.'),
 ('municipality','Municipality','{dubai,abu_dhabi,sharjah,ajman,rak,fujairah,uaq}','{8,14,15,20,28,31,32,33,34}','General building/works permits.')
on conflict (code) do nothing;

-- ---------------- 25 trades, grounded in the live sector distribution ----------------
-- authority_required is deliberately CONSERVATIVE: only where approval is genuinely mandatory.
-- Over-gating silently excludes legitimate suppliers, which is the same failure as spam in reverse.
insert into public.taxonomy_trade (code,label,aliases,authority_required,sort) values
 ('hvac','HVAC & air conditioning','{hvac,ac,air conditioning,vrf,chiller,ducting,ventilation,mep}','{}',10),
 ('electrical','Electrical','{electrical,electric,wiring,db panel,switchgear,lighting,mep}','{electrical_utility}',20),
 ('plumbing','Plumbing & sanitary','{plumbing,sanitary,drainage,water,pipes,mep}','{}',30),
 ('fire_fighting','Fire fighting & life safety','{fire,fire fighting,firefighting,sprinkler,fire alarm,fire pump,life safety,safety}','{civil_defence}',40),
 ('joinery','Joinery & carpentry','{carpentry,joinery,woodwork,wood,mdf,furniture,cabinets,kitchen}','{}',50),
 ('glazing','Glass & glazing','{glass,glazing,mirror,partition glass,facade glass}','{}',60),
 ('aluminium','Aluminium & cladding','{aluminium,aluminum,cladding,facade,curtain wall,acp}','{}',70),
 ('steel','Steel & metal fabrication','{steel,metal,fabrication,welding,stainless,mild steel}','{}',80),
 ('flooring','Flooring','{flooring,floor,tiles,tiling,vinyl,epoxy,carpet,parquet,marble}','{}',90),
 ('painting','Painting & finishes','{painting,paint,coating,finishes,decoration}','{}',100),
 ('gypsum','Gypsum, partitions & ceilings','{gypsum,partition,ceiling,drywall,false ceiling,plaster}','{}',110),
 ('signage','Signage & printing','{signage,sign,printing,acrylic,3d letters,branding}','{}',120),
 ('landscaping','Landscaping & pools','{landscaping,landscape,garden,softscape,hardscape,pool,irrigation}','{}',130),
 ('security_systems','Security systems','{security,cctv,access control,alarm,surveillance,gate barrier}','{sira}',140),
 ('elevators','Elevators & escalators','{elevator,lift,escalator,travelator}','{}',150),
 ('doors','Doors & windows','{doors,door,windows,shutters,automatic doors,fire door}','{}',160),
 ('waterproofing','Waterproofing & insulation','{waterproofing,insulation,membrane,thermal,acoustic}','{}',170),
 ('upholstery','Upholstery & soft furnishing','{upholstery,curtains,blinds,fabric,soft furnishing,sofa}','{}',180),
 ('wallpaper','Wallpaper & wall finishes','{wallpaper,wall covering,cladding interior,panelling}','{}',190),
 ('scaffolding','Scaffolding & access','{scaffolding,scaffold,access equipment,formwork}','{}',200),
 ('cleaning','Cleaning & facility services','{cleaning,facility management,fm,housekeeping,pest control}','{}',210),
 ('av_it','AV, IT & low current','{av,audio visual,it,network,structured cabling,low current,telecom}','{}',220),
 ('interior_fitout','Interior fit-out','{fitout,fit-out,fit out,interior,interior design,turnkey}','{}',230),
 ('civil_works','Civil & construction works','{civil,construction,concrete,masonry,blockwork,demolition,contractor}','{}',240),
 ('mep_general','MEP (combined)','{mep,mechanical electrical plumbing,building services}','{}',250)
on conflict (code) do nothing;

-- ---------------- 8 roles: the axis that was missing entirely ----------------
-- These three booleans make role-gating declarative:
--   supply-only inquiry  -> requires supplies
--   installation inquiry -> requires executes
--   turnkey/multi-trade  -> requires whole_scope
-- This is precisely what prevents a fire-pump MANUFACTURER receiving a plumbing INSTALLATION job.
insert into public.taxonomy_role (code,label,aliases,supplies,executes,whole_scope,sort) values
 ('manufacturer','Manufacturer','{manufacturer,factory,producer,mill}',true,false,false,10),
 ('distributor','Authorised distributor','{distributor,authorized dealer,agent,sole agent}',true,false,false,20),
 ('supplier','Supplier / trading','{supplier,trading,building-materials,materials,wholesale,equipment}',true,false,false,30),
 ('installer','Installer / applicator','{installer,applicator,fixing,erection}',false,true,false,40),
 ('contractor','Contractor','{contractor,subcontractor,works}',true,true,false,50),
 ('turnkey_fitout','Turnkey / fit-out contractor','{turnkey,fitout,fit-out,main contractor,general contractor,interior_design}',true,true,true,60),
 ('maintenance','Maintenance / AMC','{maintenance,amc,servicing,repair,fm}',false,true,false,70),
 ('consultant','Consultant / designer','{consultant,consultancy,design,engineering,architect}',false,false,false,80)
on conflict (code) do nothing;

create index if not exists idx_taxonomy_trade_aliases on public.taxonomy_trade using gin (aliases);
create index if not exists idx_taxonomy_role_aliases  on public.taxonomy_role  using gin (aliases);
