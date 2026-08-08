-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706115127   name: rfq_completeness_gate_v2
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.inquiries add column if not exists completeness jsonb;
alter table public.inquiries add column if not exists rfq_ready boolean default false;

create or replace function public.fn_rfq_score(i public.inquiries)
returns jsonb language plpgsql stable set search_path=public,pg_temp as $$
declare pts int:=0; miss text[]:='{}'; have text[]:='{}'; spectxt text;
begin
  spectxt := coalesce(i.spec::text,'');
  if coalesce(i.category,'')<>'' then pts:=pts+20; have:=array_append(have,'category'); else miss:=array_append(miss,'category'); end if;
  if coalesce(i.emirate,'')<>'' then pts:=pts+10; have:=array_append(have,'emirate'); else miss:=array_append(miss,'emirate'); end if;
  if length(regexp_replace(spectxt,'[^a-zA-Z0-9]','','g')) > 20 then pts:=pts+25; have:=array_append(have,'scope_detail'); else miss:=array_append(miss,'scope_detail'); end if;
  if coalesce(i.scope_type,'')<>'' then pts:=pts+15; have:=array_append(have,'scope_type'); else miss:=array_append(miss,'scope_type'); end if;
  if i.budget is not null then pts:=pts+15; have:=array_append(have,'budget'); else miss:=array_append(miss,'budget'); end if;
  if coalesce(array_length(i.trades,1),0)>0 or coalesce(i.drawing_file_path,'')<>'' or i.boq is not null then
     pts:=pts+15; have:=array_append(have,'supporting_detail'); else miss:=array_append(miss,'supporting_detail'); end if;
  return jsonb_build_object('score',pts,'ready',pts>=70,'have',to_jsonb(have),'missing',to_jsonb(miss),'scored_at',now());
end $$;

create or replace function public.trg_rfq_complete() returns trigger
language plpgsql set search_path=public,pg_temp as $$
declare c jsonb;
begin
  c := public.fn_rfq_score(NEW);
  NEW.completeness := c; NEW.rfq_ready := (c->>'ready')::boolean;
  return NEW;
end $$;
drop trigger if exists rfq_complete on public.inquiries;
create trigger rfq_complete before insert or update on public.inquiries
  for each row execute function public.trg_rfq_complete();

update public.inquiries set spec = spec where true;

delete from public.agent_knowledge where agent_key='_global' and topic='RFQ completeness rule';
insert into public.agent_knowledge(agent_key,topic,content,priority) values
 ('_global','RFQ completeness rule',
  'Do not finalise or route an RFQ until it reaches a completeness score of 70+. An RFQ needs: category, emirate/location, a specific scope description (not one vague line), scope type (supply-only vs turnkey), an indicative budget or range, and at least one supporting detail (trades list, a drawing/photo, or a BOQ). If any are missing, ask focused clarifying questions for the missing items before proceeding, guided by the category''s engineered qualification checklist.',
  900);

select count(*) filter (where rfq_ready) as ready, count(*) as total, round(avg((completeness->>'score')::numeric),1) as avg_score from public.inquiries;
