-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260724153309   name: category_aware_quote_gate
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============================================================================
-- CATEGORY-AWARE QUOTE GATE (2026-07-24). The generic scorer checks that specs
-- EXIST; this checks the RIGHT domain specs are present per trade, by scanning the
-- quote's full text (scope/conditions/notes + every line item) for required aspects.
-- A CCTV quote is now blocked until it states resolution + NVR channels + storage.
-- Research-grounded (SIRA, DCD, Al Sa'fat, DEWA, DM) 2026.
-- ============================================================================

create table if not exists public.category_quote_specs (
  id bigserial primary key,
  spec_group text not null,      -- canonical trade group
  aspect text not null,          -- machine key
  label text not null,           -- human label shown to the supplier
  match_regex text not null,     -- case-insensitive; found anywhere in quote text = present
  mandatory boolean not null default true,
  note text,
  created_at timestamptz default now(),
  unique (spec_group, aspect)
);
alter table public.category_quote_specs enable row level security;

-- Map any inquiry/category slug to its canonical quote-spec group.
create or replace function public.fn_quote_spec_group(p_category text)
returns text language sql immutable as $fn$
  select case
    when p_category ~* 'cctv|security|surveillance|access.?control|intercom|alarm' then 'security'
    when p_category ~* 'fire|safety|sprinkler|extinguisher|civil.?defen' then 'fire'
    when p_category ~* 'hvac|^ac-|air.?con|duct|chiller|cooling|maintenance' then 'hvac'
    when p_category ~* 'glass|glaz|alumin|facade|curtain.?wall|shopfront|balustrad' then 'glazing'
    when p_category ~* 'joinery|kitchen|furniture|carpentr|cabinet|wardrobe|cupboard' then 'joinery'
    when p_category ~* 'electric|wiring|^mep$|dewa' then 'electrical'
    when p_category ~* 'plumb|sanitary|drainage|water.?tank' then 'plumbing'
    else null end;
$fn$;

-- Score a quote against its category's required aspects (text-match over the whole quote).
create or replace function public.fn_quote_category_score(p_quote text)
returns jsonb language plpgsql stable security definer set search_path to 'public','pg_temp'
as $fn$
declare q record; grp text; blob text; r record;
        tot int:=0; okc int:=0; miss jsonb:='[]'::jsonb; pres jsonb:='[]'::jsonb; mand_missing int:=0;
begin
  select * into q from quotes where id=p_quote::uuid;
  if q is null then return jsonb_build_object('applicable',false,'reason','quote not found'); end if;
  grp := fn_quote_spec_group(coalesce((select category from inquiries where id=q.inquiry_id),''));
  if grp is null then return jsonb_build_object('applicable',false,'reason','no category spec group'); end if;
  if not exists (select 1 from category_quote_specs where spec_group=grp) then
    return jsonb_build_object('applicable',false,'reason','no specs defined for '||grp); end if;

  select lower(concat_ws(' ', q.scope, q.conditions, q.exclusions, q.notes, q.warranty,
           q.payment_terms, q.lead_time, q.validity,
           (select string_agg(concat_ws(' ',description,brand,model,specification),' ')
              from quote_items where quote_id=p_quote)))
    into blob;
  blob := coalesce(blob,'');

  for r in select * from category_quote_specs where spec_group=grp order by mandatory desc, aspect loop
    tot := tot + 1;
    if blob ~* r.match_regex then
      okc := okc + 1; pres := pres || to_jsonb(r.aspect);
    else
      miss := miss || jsonb_build_object('aspect',r.aspect,'label',r.label,'mandatory',r.mandatory);
      if r.mandatory then mand_missing := mand_missing + 1; end if;
    end if;
  end loop;

  return jsonb_build_object(
    'applicable', true, 'group', grp,
    'aspects_total', tot, 'aspects_present', okc,
    'mandatory_missing', mand_missing,
    'category_pass', (mand_missing = 0),
    'present', pres, 'missing', miss);
end $fn$;
revoke execute on function public.fn_quote_category_score(text) from public, anon, authenticated;

-- Combined submittable = generic completeness (>=70) AND all mandatory category aspects present.
create or replace function public.fn_quote_recompute_submittable()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare qid uuid; sc jsonb; cat jsonb; ok boolean;
begin
  qid := coalesce(NEW.quote_id, OLD.quote_id);
  begin sc := public.fn_quote_structured_score(qid::text); exception when others then sc := null; end;
  begin cat := public.fn_quote_category_score(qid::text); exception when others then cat := null; end;
  if sc is not null then
    ok := (sc->>'submittable')::boolean
          and (cat is null or (cat->>'applicable')::boolean is not true or (cat->>'category_pass')::boolean);
    update public.quotes set submittable = ok
      where id = qid and submittable is distinct from ok;
  end if;
  return coalesce(NEW, OLD);
end $fn$;

-- ---- SEED: research-grounded mandatory aspects per trade ----
insert into public.category_quote_specs (spec_group, aspect, label, match_regex, mandatory, note) values
-- SECURITY / CCTV (SIRA)
('security','resolution','Camera resolution (MP / 4K)','\d+\s*mp|megapixel|\d{3,4}\s*[x×]\s*\d{3,4}|\b4k\b|1080p|2mp|4mp|8mp', true,'SIRA: 4MP general, 8MP entries/cash points'),
('security','nvr_channels','NVR/DVR channel count','\d+\s*-?\s*ch(annel)?|\bnvr\b|\bdvr\b|recorder', true,null),
('security','storage','Storage / retention (TB or days)','\d+\s*tb|\d+\s*day|retention|\bhdd\b|surveillance drive', true,'SIRA: 31 days standard, 90 days high-security'),
('security','night_ip','IR night-vision / IP weather rating','\bir\b|infrared|night.?vision|starlight|colou?rvu|ip6\d|ik\d', false,'required for outdoor/low-light'),
('security','warranty','Warranty','warrant|guarantee', true,null),
('security','sira','SIRA compliance / licence','sira', false,'mandatory for Dubai installs'),
-- FIRE / SAFETY (DCD, NFPA)
('fire','system_type','System type (addressable/conventional)','addressable|conventional|fire alarm|control panel|sprinkler|suppression', true,null),
('fire','devices','Detection/notification devices','detector|smoke|heat|sounder|call point|sprinkler head|extinguisher|hose reel', true,null),
('fire','standard','Approval / listing (DCD, UL/FM, NFPA)','nfpa|civil defen|\bdcd\b|\bul\b|\bfm\b|listed|approved|circular 33', true,'must be Civil Defence approved products'),
('fire','amc','Maintenance / AMC','amc|maintenance|annual', false,'DCD requires AMC before final inspection'),
('fire','warranty','Warranty','warrant|guarantee', true,null),
-- HVAC (ESMA)
('hvac','capacity','Cooling capacity (BTU/TR/kW)','\d+\s*(btu|ton|\btr\b|kw)', true,null),
('hvac','unit_type','Unit type','split|ducted|vrf|vrv|chiller|cassette|package|\bahu\b|\bfahu\b|concealed', true,null),
('hvac','refrigerant','Refrigerant type','r-?410a?|r-?32|r-?22|refrigerant', true,'R-22 banned; disclose type'),
('hvac','efficiency','Efficiency (EER/SEER/ESMA star)','\beer\b|\bcop\b|seer|star rating|esma|inverter', false,'ESMA label required'),
('hvac','warranty','Warranty (compressor/parts)','warrant|guarantee|compressor.*year', true,null),
-- GLAZING / ALUMINIUM (DM, Al Safat)
('glazing','glass_makeup','Glass make-up (type/coating)','tempered|toughened|laminated|double.?glaz|\bigu\b|low-?e|annealed|heat.?strength', true,null),
('glazing','thickness','Glass thickness (mm)','\d+\s*mm|\d+\.\d+\s*mm', true,null),
('glazing','dimensions','Dimensions / area','\d+\s*[x×]\s*\d+|sq\.?m|\bm2\b|m²|width|height|linear', true,null),
('glazing','system_finish','Aluminium system / finish','aluminium|aluminum|profile|thermal.?break|powder.?coat|anodiz|qualicoat', false,null),
('glazing','safety','Safety-glass / performance','safety glass|tempered|laminated|en ?12150|u-?value|shgc', false,'DM mandates safety glass near doors/low level/wet areas'),
('glazing','warranty','Warranty','warrant|guarantee', true,null),
-- JOINERY / KITCHENS / FURNITURE
('joinery','carcass','Carcass material','\bmdf\b|plywood|\bply\b|marine ply|chipboard|melamine|blockboard|mr-?mdf', true,null),
('joinery','finish','Finish','laminate|acrylic|lacquer|veneer|melamine|\bpu\b|duco|matt|gloss|membrane', true,null),
('joinery','dimensions','Dimensions / quantity','\d+\s*mm|linear.?met|running.?met|\d+\s*[x×]\s*\d+', true,null),
('joinery','hardware','Hardware brand/tier','blum|hettich|hafele|häfele|hinge|runner|soft.?close|drawer|aventos', false,null),
('joinery','warranty','Warranty','warrant|guarantee', true,null),
-- ELECTRICAL (DEWA)
('electrical','cable','Cable size/type','\d+\s*mm2?|mm²|\bcable\b|copper|\bcu\b|xlpe|ducab|oman cable', true,null),
('electrical','db_board','DB board / protection','distribution board|db board|\bmcb\b|breaker|\brcd\b|rccb|rcbo|schneider|\babb\b|hager|legrand|isolator|way\b', true,null),
('electrical','load','Load (kW/kVA/A)','\d+\s*(kw|kva|amp|\ba\b)|load calc|maximum demand', true,null),
('electrical','earthing_test','Earthing / testing / certificate','earth|bonding|tn-?[cs]|insulation resist|megger|test certificate|commission', false,'DEWA earthing + test cert required'),
('electrical','warranty','Warranty','warrant|guarantee', true,null),
-- PLUMBING (DM)
('plumbing','pipe_material','Pipe material','\bppr\b|upvc|\bpex\b|cpvc|copper|\bhdpe\b|multilayer|polypropylene', true,null),
('plumbing','diameter','Pipe diameter','\d+\s*mm|ø\s*\d+|\d+\s*inch|\bpn\d+\b|dia\b', true,null),
('plumbing','fixtures','Fixtures / tank','\bwc\b|basin|mixer|faucet|shower|water tank|\bgeyser\b|water heater|floor drain|cistern|grohe|rak', true,null),
('plumbing','testing','Pressure/drainage test','pressure test|hydrostatic|\d+\s*bar|test certificate|drainage test', false,'DM requires pressure test before handover'),
('plumbing','warranty','Warranty','warrant|guarantee', true,null);
