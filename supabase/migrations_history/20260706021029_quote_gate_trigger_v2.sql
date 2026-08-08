-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706021029   name: quote_gate_trigger_v2
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function trg_quote_quality() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare cat text; lic text; qobj jsonb;
begin
  select category into cat from inquiries where id = NEW.inquiry_id;
  select trade_license_no into lic from leads where id = NEW.supplier_id;
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
    'unit_price',     case when NEW.quote_amount > 0 then true else null end
  ));
  begin
    NEW.quality := quote_gate(coalesce(cat,'default'), qobj);
  exception when others then null; end;
  return NEW;
end $$;

drop trigger if exists quotes_quality on quotes;
create trigger quotes_quality before insert or update on quotes
for each row execute function trg_quote_quality();

update quotes set quote_amount = quote_amount where quality is null;
