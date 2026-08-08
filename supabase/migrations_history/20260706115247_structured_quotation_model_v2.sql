-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706115247   name: structured_quotation_model_v2
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists public.quote_items(
  id bigserial primary key, quote_id text not null, line_no int, description text,
  brand text, model text, specification text, qty numeric, unit text, unit_price numeric,
  labour numeric, install numeric, commissioning numeric, amount numeric,
  country_of_origin text, datasheet_path text, notes text, created_at timestamptz default now());
create index if not exists idx_quote_items_quote on public.quote_items(quote_id);
alter table public.quote_items enable row level security;
revoke all on public.quote_items from anon, authenticated;
alter table public.quotes add column if not exists structured jsonb;
alter table public.quotes add column if not exists submittable boolean default false;

create or replace function public.fn_quote_structured_score(p_quote text)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare n int; priced int; branded int; laboured int; spec_n int; q record; pts int:=0; miss text[]:='{}';
begin
  select count(*), count(*) filter (where unit_price is not null and unit_price>0),
         count(*) filter (where coalesce(brand,'')<>'' and coalesce(model,'')<>''),
         count(*) filter (where labour is not null or install is not null),
         count(*) filter (where coalesce(specification,'')<>'')
    into n, priced, branded, laboured, spec_n from quote_items where quote_id=p_quote;
  select * into q from quotes where id=p_quote::uuid;
  if n=0 then miss:=array_append(miss,'line_items');
  else pts:=pts+15; if priced=n then pts:=pts+20; else miss:=array_append(miss,'unit_prices_on_all_items'); end if; end if;
  if n>0 and branded=n then pts:=pts+15; else miss:=array_append(miss,'brand_model_per_item'); end if;
  if n>0 and spec_n>=greatest(1,n/2) then pts:=pts+10; else miss:=array_append(miss,'specifications'); end if;
  if laboured>0 then pts:=pts+10; else miss:=array_append(miss,'labour_or_installation'); end if;
  if coalesce(q.warranty,'')<>'' then pts:=pts+6; else miss:=array_append(miss,'warranty'); end if;
  if coalesce(q.lead_time,'')<>'' then pts:=pts+6; else miss:=array_append(miss,'lead_time'); end if;
  if coalesce(q.payment_terms,'')<>'' then pts:=pts+6; else miss:=array_append(miss,'payment_terms'); end if;
  if coalesce(q.exclusions,'')<>'' then pts:=pts+6; else miss:=array_append(miss,'exclusions'); end if;
  if coalesce(q.validity,'')<>'' then pts:=pts+6; else miss:=array_append(miss,'validity'); end if;
  return jsonb_build_object('score',pts,'submittable',pts>=70,'items',n,'priced_items',priced,'missing',to_jsonb(miss),'scored_at',now());
end $$;

create or replace function public.trg_quote_items_roll() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare qid text; s jsonb;
begin
  qid := coalesce(NEW.quote_id, OLD.quote_id);
  s := public.fn_quote_structured_score(qid);
  update quotes set structured=s, submittable=(s->>'submittable')::boolean where id=qid::uuid;
  return null;
end $$;
drop trigger if exists quote_items_roll on public.quote_items;
create trigger quote_items_roll after insert or update or delete on public.quote_items
  for each row execute function public.trg_quote_items_roll();

create or replace function public.fn_quote_coaching(p_quote text)
returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
  select jsonb_build_object(
    'structured', public.fn_quote_structured_score(p_quote),
    'gate', (select quality from quotes where id=p_quote::uuid),
    'advice', 'Complete every missing field above. Buyers compare quotes line-by-line — priced BOQ items with brand/model, labour, warranty, lead time, payment terms and exclusions win more often.');
$$;
select 'ok';
