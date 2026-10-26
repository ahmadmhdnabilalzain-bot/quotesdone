-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709123225   name: quote_quality_trigger_no_submittable_override
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Trigger computes the display 'quality' checklist ONLY (now line-item aware).
-- It must NOT set 'submittable' or 'structured' — those are owned by the submit path
-- (fn_quote_structured_score, threshold >=70), so we don't override the operational gate.
create or replace function public.trg_quote_quality()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $function$
declare cat text; lic text; qobj jsonb;
  n int; brandmodel int; specs int; descs int; origins int; datasheets int; installs int; comms int; priced int;
begin
  select category into cat from inquiries where id = NEW.inquiry_id;
  select trade_license_no into lic from leads where id = NEW.supplier_id;

  select count(*),
    count(*) filter (where coalesce(brand,'')<>'' or coalesce(model,'')<>''),
    count(*) filter (where coalesce(specification,'')<>''),
    count(*) filter (where coalesce(description,'')<>''),
    count(*) filter (where coalesce(country_of_origin,'')<>''),
    count(*) filter (where coalesce(datasheet_path,'')<>''),
    count(*) filter (where coalesce(install,0)>0),
    count(*) filter (where coalesce(commissioning,0)>0),
    count(*) filter (where coalesce(unit_price,0)>0 and coalesce(qty,0)>0)
  into n, brandmodel, specs, descs, origins, datasheets, installs, comms, priced
  from public.quote_items where quote_id = NEW.id::text;

  qobj := jsonb_strip_nulls(jsonb_build_object(
    'company_details', true,
    'trade_license',  lic,
    'scope',          nullif(btrim(coalesce(NEW.scope,'')),''),
    'warranty',       nullif(btrim(coalesce(NEW.warranty,'')),''),
    'exclusions',     nullif(btrim(coalesce(NEW.exclusions,'')),''),
    'lead_time',      nullif(btrim(coalesce(NEW.lead_time,'')),''),
    'payment_terms',  nullif(btrim(coalesce(NEW.payment_terms,'')),''),
    'validity',       nullif(btrim(coalesce(NEW.validity,'')),''),
    'assumptions',    nullif(btrim(coalesce(NEW.conditions,'')),''),
    'unit_price',            case when coalesce(NEW.quote_amount,0) > 0 or priced > 0 then true else null end,
    'boq',                   case when n >= 1 then true else null end,
    'brand_model',           case when brandmodel >= 1 then true else null end,
    'materials',             case when descs >= 1 then true else null end,
    'specifications',        case when specs >= 1 then true else null end,
    'country_of_origin',     case when origins >= 1 then true else null end,
    'datasheets',            case when datasheets >= 1 then true else null end,
    'installation_method',   case when installs >= 1 then true else null end,
    'testing_commissioning', case when comms >= 1 then true else null end
  ));

  begin
    NEW.quality := quote_gate(coalesce(cat,'default'), qobj);
  exception when others then null; end;
  return NEW;
end $function$;

-- recompute display quality on existing quotes (does not touch submittable/status)
update public.quotes set scope = scope;
