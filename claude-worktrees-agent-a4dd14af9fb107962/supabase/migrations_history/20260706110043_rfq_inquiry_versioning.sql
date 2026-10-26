-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706110043   name: rfq_inquiry_versioning
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- RFQ (inquiry) versioning into the shared doc_versions store
create or replace function public.trg_version_rfq() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare snap jsonb; chg text[] := '{}';
begin
  snap := jsonb_build_object('category',NEW.category,'emirate',NEW.emirate,'summary',NEW.summary,
    'spec',NEW.spec,'budget',NEW.budget,'scope_type',NEW.scope_type,'trades',NEW.trades,
    'boq',NEW.boq,'status',NEW.status,'pipeline_stage',NEW.pipeline_stage,'outcome',NEW.outcome);
  if TG_OP='UPDATE' then
    if NEW.spec is distinct from OLD.spec then chg:=array_append(chg,'spec'); end if;
    if NEW.budget is distinct from OLD.budget then chg:=array_append(chg,'budget'); end if;
    if NEW.scope_type is distinct from OLD.scope_type then chg:=array_append(chg,'scope_type'); end if;
    if NEW.trades is distinct from OLD.trades then chg:=array_append(chg,'trades'); end if;
    if NEW.boq is distinct from OLD.boq then chg:=array_append(chg,'boq'); end if;
    if NEW.status is distinct from OLD.status then chg:=array_append(chg,'status'); end if;
    if NEW.pipeline_stage is distinct from OLD.pipeline_stage then chg:=array_append(chg,'pipeline_stage'); end if;
    if NEW.category is distinct from OLD.category then chg:=array_append(chg,'category'); end if;
    if array_length(chg,1) is null then return NEW; end if;
  end if;
  insert into public.doc_versions(entity_type,entity_id,version,snapshot,checksum,changed_fields)
  values ('rfq', NEW.id::text, public._next_docver('rfq',NEW.id::text), snap, md5(snap::text), chg)
  on conflict do nothing;
  return NEW;
end $$;
drop trigger if exists version_rfq on public.inquiries;
create trigger version_rfq after insert or update on public.inquiries
  for each row execute function public.trg_version_rfq();

-- backfill current inquiries as v1
insert into public.doc_versions(entity_type,entity_id,version,snapshot,checksum,changed_fields)
select 'rfq', id::text, 1,
  jsonb_build_object('category',category,'emirate',emirate,'summary',summary,'spec',spec,'budget',budget,
    'scope_type',scope_type,'trades',trades,'boq',boq,'status',status,'pipeline_stage',pipeline_stage,'outcome',outcome),
  md5(id::text), array['initial']
from public.inquiries
on conflict (entity_type,entity_id,version) do nothing;

select (select count(*) from doc_versions where entity_type='rfq') as rfq_versions;
