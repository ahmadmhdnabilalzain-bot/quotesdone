-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706101759   name: mdm_master_data_management
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ MASTER DATA MANAGEMENT ============
-- Authoritative reference lists. Each carries aliases[] for normalization/dedup.

create table if not exists public.mdm_emirates(
  code text primary key, name text not null, name_ar text, aliases text[] default '{}', active boolean default true);
create table if not exists public.mdm_cities(
  id bigserial primary key, name text not null, emirate_code text references public.mdm_emirates(code),
  aliases text[] default '{}', active boolean default true, unique(name, emirate_code));
create table if not exists public.mdm_currencies(
  code text primary key, name text not null, symbol text, is_base boolean default false, active boolean default true);
create table if not exists public.mdm_units(
  code text primary key, name text not null, dimension text, aliases text[] default '{}', active boolean default true);
create table if not exists public.mdm_standards(
  id bigserial primary key, code text not null unique, title text, authority text, domain text,
  aliases text[] default '{}', active boolean default true);
create table if not exists public.mdm_brands(
  id bigserial primary key, name text not null unique, category text, manufacturer text,
  aliases text[] default '{}', active boolean default true);
create table if not exists public.mdm_manufacturers(
  id bigserial primary key, name text not null unique, country text, aliases text[] default '{}', active boolean default true);

-- lock down (edge functions use service_role which bypasses RLS)
do $$ declare t text; begin
  foreach t in array array['mdm_emirates','mdm_cities','mdm_currencies','mdm_units','mdm_standards','mdm_brands','mdm_manufacturers']
  loop execute format('alter table public.%I enable row level security', t);
       execute format('revoke all on public.%I from anon, authenticated', t); end loop; end $$;

-- ---- Emirates (7) ----
insert into public.mdm_emirates(code,name,name_ar,aliases) values
 ('AUH','Abu Dhabi','أبوظبي','{"abu dhabi","abudhabi","auh"}'),
 ('DXB','Dubai','دبي','{"dubai","dxb"}'),
 ('SHJ','Sharjah','الشارقة','{"sharjah","shj"}'),
 ('AJM','Ajman','عجمان','{"ajman"}'),
 ('UAQ','Umm Al Quwain','أم القيوين','{"umm al quwain","umm al quwan","uaq"}'),
 ('RAK','Ras Al Khaimah','رأس الخيمة','{"ras al khaimah","rak"}'),
 ('FUJ','Fujairah','الفجيرة','{"fujairah","fuj"}')
on conflict (code) do nothing;

-- ---- Cities / key areas ----
insert into public.mdm_cities(name,emirate_code) values
 ('Abu Dhabi','AUH'),('Al Ain','AUH'),('Ruwais','AUH'),('Madinat Zayed','AUH'),('Liwa','AUH'),('Ghayathi','AUH'),
 ('Dubai','DXB'),('Jebel Ali','DXB'),('Hatta','DXB'),
 ('Sharjah','SHJ'),('Khor Fakkan','SHJ'),('Kalba','SHJ'),('Dibba Al Hisn','SHJ'),
 ('Ajman','AJM'),
 ('Umm Al Quwain','UAQ'),
 ('Ras Al Khaimah','RAK'),
 ('Fujairah','FUJ'),('Dibba Al Fujairah','FUJ')
on conflict do nothing;

-- ---- Currencies ----
insert into public.mdm_currencies(code,name,symbol,is_base) values
 ('AED','UAE Dirham','د.إ',true),('USD','US Dollar','$',false),('EUR','Euro','€',false),
 ('GBP','Pound Sterling','£',false),('SAR','Saudi Riyal','﷼',false),('QAR','Qatari Riyal','﷼',false),
 ('KWD','Kuwaiti Dinar','د.ك',false),('BHD','Bahraini Dinar','.د.ب',false),('OMR','Omani Rial','﷼',false),
 ('INR','Indian Rupee','₹',false),('CNY','Chinese Yuan','¥',false)
on conflict (code) do nothing;

-- ---- Units of measure ----
insert into public.mdm_units(code,name,dimension,aliases) values
 ('m2','Square metre','area','{"sqm","sq.m","m²","square meter","square metre"}'),
 ('ft2','Square foot','area','{"sqft","sq.ft","ft²","square foot"}'),
 ('m','Metre','length','{"mtr","meter","metre"}'),
 ('lm','Linear metre','length','{"rm","running metre","linear meter","lin.m"}'),
 ('mm','Millimetre','length','{"millimetre","millimeter"}'),
 ('m3','Cubic metre','volume','{"cbm","cu.m","m³","cubic meter"}'),
 ('nos','Number','count','{"no","nos.","pcs","piece","pieces","unit","units","ea","each"}'),
 ('set','Set','count','{"sets"}'),
 ('lot','Lot','count','{"lots"}'),
 ('ls','Lump sum','count','{"lumpsum","lump-sum","l.s"}'),
 ('kg','Kilogram','mass','{"kilogram","kilo","kgs"}'),
 ('ton','Tonne','mass','{"tonne","mt","metric ton"}'),
 ('ltr','Litre','volume','{"l","liter","litre","ltrs"}'),
 ('gal','Gallon','volume','{"gallon","gallons"}'),
 ('hr','Hour','time','{"hour","hrs","man-hour","manhour"}'),
 ('day','Day','time','{"days","man-day"}'),
 ('roll','Roll','count','{"rolls"}'),
 ('sheet','Sheet','count','{"sheets","board"}'),
 ('bag','Bag','count','{"bags"}'),
 ('point','Point','count','{"points","pt"}'),
 ('kw','Kilowatt','power','{"kilowatt"}'),
 ('kwp','Kilowatt-peak','power','{"kilowatt peak","kw-peak"}'),
 ('tr','Refrigeration ton','cooling','{"ton refrigeration","ton ac","rt"}')
on conflict (code) do nothing;

-- ---- Standards / codes (UAE-relevant) ----
insert into public.mdm_standards(code,title,authority,domain,aliases) values
 ('SIRA','Security Industry Regulatory Agency requirements','SIRA (Dubai)','security','{"sira"}'),
 ('DCD','Dubai Civil Defence Fire & Life Safety Code','DCD','fire','{"dcd","civil defence","civil defense"}'),
 ('ADCD','Abu Dhabi Civil Defence Code','ADCD','fire','{"adcd"}'),
 ('DEWA','DEWA electrical/solar connection standards','DEWA','electrical','{"dewa","shams dubai"}'),
 ('Al Safat','Dubai Green Building (Al Sa''fat)','Dubai Municipality','sustainability','{"al safat","al sa''fat","alsafat"}'),
 ('Estidama','Estidama Pearl Rating','DMT Abu Dhabi','sustainability','{"estidama","pearl rating"}'),
 ('ESMA','Emirates Authority for Standardization & Metrology','ESMA/MoIAT','products','{"esma","moiat"}'),
 ('BS 7671','IET Wiring Regulations','BSI','electrical','{"bs7671","iet wiring","wiring regs"}'),
 ('IEC 60364','Low-voltage electrical installations','IEC','electrical','{"iec 60364"}'),
 ('NFPA 72','National Fire Alarm and Signaling Code','NFPA','fire','{"nfpa72","nfpa 72"}'),
 ('BS 5839','Fire detection and alarm systems','BSI','fire','{"bs5839","bs 5839"}'),
 ('EN 50131','Intruder & hold-up alarm systems','CENELEC','security','{"en50131"}'),
 ('EN 62676','Video surveillance systems','CENELEC','security','{"en62676","iec 62676"}'),
 ('IEC 61215','PV module design qualification','IEC','solar','{"iec61215"}'),
 ('IEC 61730','PV module safety qualification','IEC','solar','{"iec61730"}'),
 ('EN 1090','Execution of steel & aluminium structures','CEN','steel','{"en1090"}'),
 ('AWS D1.1','Structural welding code (steel)','AWS','steel','{"aws d1.1","d1.1"}'),
 ('IP Rating','Ingress Protection rating','IEC 60529','general','{"ip54","ip55","ip65","ip66","ip67","ingress protection"}'),
 ('ISO 9001','Quality management systems','ISO','general','{"iso9001"}'),
 ('ISO 45001','Occupational health & safety','ISO','hse','{"iso45001","ohsas"}'),
 ('ISO 14001','Environmental management','ISO','hse','{"iso14001"}'),
 ('LEED','Leadership in Energy & Environmental Design','USGBC','sustainability','{"leed"}')
on conflict (code) do nothing;

-- ---- Manufacturers ----
insert into public.mdm_manufacturers(name,country) values
 ('Hikvision','China'),('Dahua','China'),('Axis Communications','Sweden'),('Bosch','Germany'),
 ('Honeywell','USA'),('Schneider Electric','France'),('ABB','Switzerland'),('Siemens','Germany'),
 ('Legrand','France'),('Daikin','Japan'),('Carrier','USA'),('LG','South Korea'),('Samsung','South Korea'),
 ('Huawei','China'),('Jotun','Norway'),('Saint-Gobain','France'),('Kohler','USA'),('LIXIL (Grohe)','Japan'),
 ('Otis','USA'),('KONE','Finland'),('Knauf','Germany'),('RAK Ceramics','UAE')
on conflict (name) do nothing;

-- ---- Brands (starter set by category; grows over time) ----
insert into public.mdm_brands(name,category,manufacturer) values
 ('Hikvision','cctv-security','Hikvision'),('Dahua','cctv-security','Dahua'),('Axis','cctv-security','Axis Communications'),
 ('Hanwha','cctv-security','Hanwha'),('Uniview','cctv-security','Uniview'),('HID','access-control','HID'),
 ('Suprema','access-control','Suprema'),('ZKTeco','access-control','ZKTeco'),
 ('Schneider Electric','electrical','Schneider Electric'),('ABB','electrical','ABB'),('Legrand','electrical','Legrand'),
 ('Siemens','electrical','Siemens'),('Hager','electrical','Hager'),
 ('Daikin','ac-maintenance','Daikin'),('Carrier','ac-maintenance','Carrier'),('O General','ac-maintenance','Fujitsu General'),
 ('Gree','ac-maintenance','Gree'),('Midea','ac-maintenance','Midea'),('Trane','ac-maintenance','Trane'),('York','ac-maintenance','Johnson Controls'),('Zamil','ac-maintenance','Zamil'),
 ('Jinko Solar','solar','Jinko'),('Trina Solar','solar','Trina'),('JA Solar','solar','JA Solar'),('LONGi','solar','LONGi'),
 ('Canadian Solar','solar','Canadian Solar'),('Huawei','solar','Huawei'),('SMA','solar','SMA'),('Fronius','solar','Fronius'),('Sungrow','solar','Sungrow'),
 ('Grohe','plumbing','LIXIL (Grohe)'),('Hansgrohe','plumbing','Hansgrohe'),('Kohler','plumbing','Kohler'),('Roca','plumbing','Roca'),
 ('Duravit','plumbing','Duravit'),('Geberit','plumbing','Geberit'),('RAK Ceramics','tiling-marble','RAK Ceramics'),
 ('Jotun','painting','Jotun'),('National Paints','painting','National Paints'),('Dulux','painting','AkzoNobel'),('Asian Paints','painting','Asian Paints'),('Berger','painting','Berger'),
 ('Knauf','false-ceiling','Knauf'),('Gyproc','false-ceiling','Saint-Gobain'),('USG Boral','false-ceiling','USG Boral'),('Danube','false-ceiling','Danube'),
 ('Notifier','fire','Honeywell'),('Simplex','fire','Johnson Controls'),('Otis','lifts','Otis'),('KONE','lifts','KONE'),('Schindler','lifts','Schindler')
on conflict (name) do nothing;

-- ---- Normalizer helper: map a raw string to a canonical MDM value ----
create or replace function public.mdm_normalize(p_kind text, p_raw text)
returns text language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v text; r text := lower(trim(coalesce(p_raw,'')));
begin
  if r = '' then return null; end if;
  if p_kind = 'emirate' then
     select code into v from public.mdm_emirates where lower(name)=r or r = any(aliases) limit 1; return v;
  elsif p_kind = 'currency' then
     select code into v from public.mdm_currencies where lower(code)=r or lower(name)=r limit 1; return v;
  elsif p_kind = 'unit' then
     select code into v from public.mdm_units where lower(code)=r or r = any(aliases) limit 1; return v;
  elsif p_kind = 'brand' then
     select name into v from public.mdm_brands where lower(name)=r or r = any(aliases) limit 1; return v;
  elsif p_kind = 'manufacturer' then
     select name into v from public.mdm_manufacturers where lower(name)=r or r = any(aliases) limit 1; return v;
  elsif p_kind = 'standard' then
     select code into v from public.mdm_standards where lower(code)=r or r = any(aliases) limit 1; return v;
  end if;
  return null;
end $$;
