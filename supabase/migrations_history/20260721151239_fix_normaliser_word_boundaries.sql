-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260721151239   name: fix_normaliser_word_boundaries
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- The first cut used LIKE '%alias%', which matches inside words:
--   'ac'   -> "access", "surface"     'it'  -> "fitted", "unit", "site"
--   'sign' -> "design"                'av'  -> "have"
-- That is precisely the substring failure this whole design exists to remove.
-- Fix: anchor every alias to a WORD START (\m) so 'sign' matches "signage" but not "design",
-- while 'paint' still matches "painting" and 'weld' still matches "welding".
-- Two-letter aliases are removed outright: no boundary rule makes 'it' or 'ac' safe.

update public.taxonomy_trade set aliases = '{hvac,air conditioning,air-conditioning,a/c unit,vrf,chiller,ducting,ductwork,ventilation,fcu,ahu}'      where code='hvac';
update public.taxonomy_trade set aliases = '{electrical,electric,wiring,switchgear,db panel,distribution board,cable tray,lighting,busbar}'            where code='electrical';
update public.taxonomy_trade set aliases = '{plumbing,plumber,sanitary,sanitaryware,drainage,pipework,water supply}'                                    where code='plumbing';
update public.taxonomy_trade set aliases = '{fire fighting,firefighting,fire alarm,fire pump,sprinkler,fire suppression,life safety,fire protection}'   where code='fire_fighting';
update public.taxonomy_trade set aliases = '{joinery,carpentry,carpenter,woodwork,wooden,millwork,cabinet,wardrobe,kitchen unit}'                       where code='joinery';
update public.taxonomy_trade set aliases = '{glass,glazing,glazed,mirror,tempered glass,laminated glass,frameless}'                                     where code='glazing';
update public.taxonomy_trade set aliases = '{aluminium,aluminum,cladding,facade,curtain wall,acp panel,louvre}'                                         where code='aluminium';
update public.taxonomy_trade set aliases = '{steel,metal fabrication,welding,welded,stainless,mild steel,structural steel,handrail}'                    where code='steel';
update public.taxonomy_trade set aliases = '{flooring,floor tiles,tiling,vinyl,epoxy floor,carpet,parquet,marble,skirting}'                             where code='flooring';
update public.taxonomy_trade set aliases = '{painting,painter,paint work,coating,protective coating,decoration}'                                        where code='painting';
update public.taxonomy_trade set aliases = '{gypsum,partition,partitions,false ceiling,drywall,plasterboard,plastering,bulkhead}'                       where code='gypsum';
update public.taxonomy_trade set aliases = '{signage,signboard,sign board,3d letters,acrylic letters,lightbox,wayfinding}'                              where code='signage';
update public.taxonomy_trade set aliases = '{landscaping,landscape,softscape,hardscape,irrigation,swimming pool,garden}'                                where code='landscaping';
update public.taxonomy_trade set aliases = '{security system,cctv,access control,intruder alarm,surveillance,gate barrier,turnstile}'                   where code='security_systems';
update public.taxonomy_trade set aliases = '{elevator,elevators,lift installation,escalator,travelator,dumbwaiter}'                                     where code='elevators';
update public.taxonomy_trade set aliases = '{door,doors,window,windows,shutter,automatic door,fire door,ironmongery}'                                   where code='doors';
update public.taxonomy_trade set aliases = '{waterproofing,waterproof,insulation,membrane,thermal insulation,acoustic insulation}'                      where code='waterproofing';
update public.taxonomy_trade set aliases = '{upholstery,upholstered,curtain,curtains,blinds,soft furnishing,sofa}'                                      where code='upholstery';
update public.taxonomy_trade set aliases = '{wallpaper,wall covering,wall panelling,wall cladding}'                                                     where code='wallpaper';
update public.taxonomy_trade set aliases = '{scaffolding,scaffold,formwork,shoring,access platform}'                                                    where code='scaffolding';
update public.taxonomy_trade set aliases = '{cleaning,facility management,housekeeping,pest control,janitorial}'                                        where code='cleaning';
update public.taxonomy_trade set aliases = '{audio visual,audio-visual,low current,structured cabling,networking,telecom,data cabling,public address}'  where code='av_it';
update public.taxonomy_trade set aliases = '{fitout,fit-out,fit out,interior design,interior works,turnkey interior,refurbishment}'                     where code='interior_fitout';
update public.taxonomy_trade set aliases = '{civil work,civil works,construction,concrete,masonry,blockwork,demolition,screed}'                         where code='civil_works';
update public.taxonomy_trade set aliases = '{mep,mechanical electrical plumbing,building services,mep works}'                                           where code='mep_general';

update public.taxonomy_role set aliases = '{manufacturer,manufacturing,factory,producer}'                                    where code='manufacturer';
update public.taxonomy_role set aliases = '{distributor,authorised dealer,authorized dealer,sole agent,exclusive agent}'     where code='distributor';
update public.taxonomy_role set aliases = '{supplier,supply,trading,building material,building materials,wholesale}'         where code='supplier';
update public.taxonomy_role set aliases = '{installer,installation,applicator,erection,fixing works}'                        where code='installer';
update public.taxonomy_role set aliases = '{contractor,subcontractor,sub-contractor}'                                        where code='contractor';
update public.taxonomy_role set aliases = '{turnkey,fitout,fit-out,main contractor,general contractor}'                      where code='turnkey_fitout';
update public.taxonomy_role set aliases = '{maintenance,amc,servicing,annual maintenance}'                                   where code='maintenance';
update public.taxonomy_role set aliases = '{consultant,consultancy,engineering design,architect}'                            where code='consultant';

-- word-START anchored matching, with regex metacharacters in aliases escaped
create or replace function public.fn_norm_trades(p_text text)
returns text[] language sql stable set search_path to 'public','pg_temp' as $$
  select coalesce(array_agg(distinct t.code order by t.code), '{}')
  from public.taxonomy_trade t
  where t.active
    and exists (
      select 1 from unnest(t.aliases || t.code) a
      where length(a) >= 3
        and coalesce(p_text,'') ~* ('\m' || regexp_replace(a, '([.*+?^${}()|\[\]\\])', '\\\1', 'g'))
    );
$$;

create or replace function public.fn_norm_roles(p_text text)
returns text[] language sql stable set search_path to 'public','pg_temp' as $$
  select coalesce(array_agg(distinct r.code order by r.code), '{}')
  from public.taxonomy_role r
  where r.active
    and exists (
      select 1 from unnest(r.aliases || r.code) a
      where length(a) >= 3
        and coalesce(p_text,'') ~* ('\m' || regexp_replace(a, '([.*+?^${}()|\[\]\\])', '\\\1', 'g'))
    );
$$;
