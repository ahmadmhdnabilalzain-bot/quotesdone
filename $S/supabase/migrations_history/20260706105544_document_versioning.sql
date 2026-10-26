-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706105544   name: document_versioning
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ DOCUMENT VERSIONING ============
create table if not exists public.doc_versions(
  id bigserial primary key,
  entity_type text not null,          -- 'quote' | 'document'
  entity_id text not null,
  version int not null,
  snapshot jsonb not null,
  checksum text,
  changed_fields text[] default '{}',
  created_at timestamptz default now(),
  unique(entity_type, entity_id, version));
create index if not exists idx_docver_entity on public.doc_versions(entity_type, entity_id, version desc);
alter table public.doc_versions enable row level security;
revoke all on public.doc_versions from anon, authenticated;

create or replace function public._next_docver(p_type text, p_id text) returns int
language sql stable security definer set search_path=public,pg_temp as
$$ select coalesce(max(version),0)+1 from public.doc_versions where entity_type=p_type and entity_id=p_id $$;

-- ---- QUOTES versioning (AFTER trigger; only writes doc_versions, never mutates quotes) ----
create or replace function public.trg_version_quote() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare snap jsonb; chg text[] := '{}';
begin
  snap := jsonb_build_object(
    'quote_amount',NEW.quote_amount,'customer_price',NEW.customer_price,'status',NEW.status,
    'scope',NEW.scope,'committed_items',NEW.committed_items,'quality',NEW.quality,
    'review_status',NEW.review_status,'lead_time',NEW.lead_time,'warranty',NEW.warranty,
    'payment_terms',NEW.payment_terms,'conditions',NEW.conditions,'exclusions',NEW.exclusions);
  if TG_OP='UPDATE' then
    if NEW.quote_amount   is distinct from OLD.quote_amount   then chg:=array_append(chg,'quote_amount'); end if;
    if NEW.customer_price is distinct from OLD.customer_price then chg:=array_append(chg,'customer_price'); end if;
    if NEW.status         is distinct from OLD.status         then chg:=array_append(chg,'status'); end if;
    if NEW.scope          is distinct from OLD.scope          then chg:=array_append(chg,'scope'); end if;
    if NEW.committed_items is distinct from OLD.committed_items then chg:=array_append(chg,'committed_items'); end if;
    if NEW.quality        is distinct from OLD.quality        then chg:=array_append(chg,'quality'); end if;
    if NEW.review_status  is distinct from OLD.review_status  then chg:=array_append(chg,'review_status'); end if;
    if NEW.lead_time      is distinct from OLD.lead_time      then chg:=array_append(chg,'lead_time'); end if;
    if NEW.warranty       is distinct from OLD.warranty       then chg:=array_append(chg,'warranty'); end if;
    if NEW.payment_terms  is distinct from OLD.payment_terms  then chg:=array_append(chg,'payment_terms'); end if;
    if array_length(chg,1) is null then return NEW; end if;   -- nothing meaningful changed
  end if;
  insert into public.doc_versions(entity_type,entity_id,version,snapshot,checksum,changed_fields)
  values ('quote', NEW.id::text, public._next_docver('quote',NEW.id::text), snap, md5(snap::text), chg)
  on conflict do nothing;
  return NEW;
end $$;
drop trigger if exists version_quote on public.quotes;
create trigger version_quote after insert or update on public.quotes
  for each row execute function public.trg_version_quote();

-- ---- DOCUMENTS versioning (each re-extraction = new version) ----
create or replace function public.trg_version_document() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if NEW.extracted is not null and (TG_OP='INSERT' or NEW.extracted is distinct from OLD.extracted) then
    insert into public.doc_versions(entity_type,entity_id,version,snapshot,checksum,changed_fields)
    values ('document', NEW.id::text, public._next_docver('document',NEW.id::text),
            jsonb_build_object('extracted',NEW.extracted,'kind',NEW.kind,'status',NEW.status),
            md5(coalesce(NEW.extracted::text,'')), array['extracted'])
    on conflict do nothing;
  end if;
  return NEW;
end $$;
drop trigger if exists version_document on public.documents;
create trigger version_document after insert or update of extracted on public.documents
  for each row execute function public.trg_version_document();

-- ---- history + diff helpers ----
create or replace function public.fn_doc_history(p_type text, p_id text)
returns table(version int, changed_fields text[], checksum text, created_at timestamptz)
language sql stable security definer set search_path=public,pg_temp as
$$ select version, changed_fields, checksum, created_at from public.doc_versions
   where entity_type=p_type and entity_id=p_id order by version desc $$;

create or replace function public.fn_doc_diff(p_type text, p_id text, p_va int, p_vb int)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare a jsonb; b jsonb; k text; res jsonb := '{}';
begin
  select snapshot into a from public.doc_versions where entity_type=p_type and entity_id=p_id and version=p_va;
  select snapshot into b from public.doc_versions where entity_type=p_type and entity_id=p_id and version=p_vb;
  if a is null or b is null then return jsonb_build_object('error','version not found'); end if;
  for k in select distinct key from (select jsonb_object_keys(a) key union select jsonb_object_keys(b)) z loop
    if (a->k) is distinct from (b->k) then
      res := res || jsonb_build_object(k, jsonb_build_object('from', a->k, 'to', b->k));
    end if;
  end loop;
  return jsonb_build_object('entity',p_type||':'||p_id,'from_version',p_va,'to_version',p_vb,'changes',res);
end $$;

-- ---- backfill current quotes as v1 ----
insert into public.doc_versions(entity_type,entity_id,version,snapshot,checksum,changed_fields)
select 'quote', id::text, 1,
  jsonb_build_object('quote_amount',quote_amount,'customer_price',customer_price,'status',status,
    'scope',scope,'committed_items',committed_items,'quality',quality,'review_status',review_status,
    'lead_time',lead_time,'warranty',warranty,'payment_terms',payment_terms,'conditions',conditions,'exclusions',exclusions),
  md5(id::text), array['initial']
from public.quotes
on conflict (entity_type,entity_id,version) do nothing;

select (select count(*) from doc_versions where entity_type='quote') as quote_versions;
