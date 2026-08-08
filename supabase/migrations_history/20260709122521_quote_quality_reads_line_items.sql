-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709122521   name: quote_quality_reads_line_items
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

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
    -- line-item-derived signals (the missing half)
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
    NEW.submittable := coalesce((NEW.quality->>'pass')::boolean, false);
    NEW.structured := jsonb_build_object('items', n, 'priced_items', priced, 'brand_model_items', brandmodel,
                                         'submittable', coalesce((NEW.quality->>'pass')::boolean,false), 'scored_at', now());
  exception when others then null; end;
  return NEW;
end $function$;

-- Recompute a quote whenever its line items change
create or replace function public.trg_quote_items_rescore()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $function$
begin
  update public.quotes set status = status where id::text = coalesce(NEW.quote_id, OLD.quote_id);
  return null;
end $function$;

drop trigger if exists quote_items_rescore on public.quote_items;
create trigger quote_items_rescore after insert or update or delete on public.quote_items
  for each row execute function public.trg_quote_items_rescore();

-- Recompute existing quotes now (touch fires the scorer)
update public.quotes set status = status;
