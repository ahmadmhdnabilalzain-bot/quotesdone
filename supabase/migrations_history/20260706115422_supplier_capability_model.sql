-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706115422   name: supplier_capability_model
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ DEEP SUPPLIER CAPABILITY MODEL ============
alter table public.leads add column if not exists vat_number text;
alter table public.leads add column if not exists vat_doc_path text;
alter table public.leads add column if not exists insurance_doc_path text;
alter table public.leads add column if not exists insurance_expiry date;
alter table public.leads add column if not exists manufacturer_authorizations jsonb;   -- [{brand, authority, expiry, doc_path}]
alter table public.leads add column if not exists machinery jsonb;                      -- [{name, count}]
alter table public.leads add column if not exists team_size int;
alter table public.leads add column if not exists engineers_count int;
alter table public.leads add column if not exists warehouse_area text;
alter table public.leads add column if not exists brands_carried jsonb;                 -- ["Hikvision","ABB",...]
alter table public.leads add column if not exists client_references jsonb;              -- [{client, project, contact, value}]
alter table public.leads add column if not exists iso_certifications jsonb;             -- [{standard, cert_no, expiry, doc_path}]
alter table public.leads add column if not exists capability_score int;                 -- 0-100 profile completeness

-- capability/profile completeness score (drives onboarding coaching + ranking)
create or replace function public.fn_supplier_capability_score(l public.leads)
returns jsonb language plpgsql stable set search_path=public,pg_temp as $$
declare pts int:=0; miss text[]:='{}';
begin
  if coalesce(l.trade_license_no,'')<>'' then pts:=pts+15; else miss:=array_append(miss,'trade_licence'); end if;
  if coalesce(l.trn,'')<>'' or coalesce(l.vat_number,'')<>'' then pts:=pts+10; else miss:=array_append(miss,'vat_trn'); end if;
  if coalesce(l.insurance_doc_path,'')<>'' then pts:=pts+10; else miss:=array_append(miss,'insurance'); end if;
  if l.iso_certifications is not null and jsonb_array_length(l.iso_certifications)>0 then pts:=pts+10; else miss:=array_append(miss,'certifications'); end if;
  if l.manufacturer_authorizations is not null and jsonb_array_length(l.manufacturer_authorizations)>0 then pts:=pts+10; else miss:=array_append(miss,'manufacturer_authorizations'); end if;
  if coalesce(l.team_size,0)>0 then pts:=pts+8; else miss:=array_append(miss,'team_size'); end if;
  if coalesce(l.engineers_count,0)>0 then pts:=pts+7; else miss:=array_append(miss,'engineers'); end if;
  if l.brands_carried is not null and jsonb_array_length(l.brands_carried)>0 then pts:=pts+8; else miss:=array_append(miss,'brands_carried'); end if;
  if l.client_references is not null and jsonb_array_length(l.client_references)>0 then pts:=pts+12; else miss:=array_append(miss,'references'); end if;
  if coalesce(array_length(l.service_emirates,1),0)>0 then pts:=pts+5; else miss:=array_append(miss,'coverage_area'); end if;
  if coalesce(l.warehouse_area,'')<>'' or (l.machinery is not null and jsonb_array_length(l.machinery)>0) then pts:=pts+5; else miss:=array_append(miss,'facilities'); end if;
  return jsonb_build_object('score',pts,'missing',to_jsonb(miss),'scored_at',now());
end $$;

create or replace function public.trg_supplier_capability() returns trigger
language plpgsql set search_path=public,pg_temp as $$
begin NEW.capability_score := (public.fn_supplier_capability_score(NEW)->>'score')::int; return NEW; end $$;
drop trigger if exists supplier_capability on public.leads;
create trigger supplier_capability before insert or update on public.leads
  for each row execute function public.trg_supplier_capability();

-- multi-document expiry monitor (licence + insurance + registration + ISO + manufacturer auth)
create or replace function public.fn_doc_expiry_scan()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare rec record; n int:=0; owner text;
begin
  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into owner from app_secrets where key='admin_emails';
  for rec in
    select id, company_name, 'trade licence' as doc, license_expiry as exp from leads where license_expiry is not null and license_expiry <= current_date+30 and coalesce(approval_status,'')='approved'
    union all
    select id, company_name, 'insurance', insurance_expiry from leads where insurance_expiry is not null and insurance_expiry <= current_date+30 and coalesce(approval_status,'')='approved'
    union all
    select id, company_name, 'registration', registration_expires_at::date from leads where registration_expires_at is not null and registration_expires_at::date <= current_date+30 and coalesce(approval_status,'')='approved'
  loop
    if not exists (select 1 from notifications where type='doc_expiry' and lead_id=rec.id and subject like '%'||rec.doc||'%' and created_at > now()-interval '20 days') then
      insert into notifications(type,to_email,to_role,lead_id,channel,subject,body)
      values ('doc_expiry', owner, 'admin', rec.id, 'email',
        'Supplier document expiring: '||rec.doc,
        coalesce(rec.company_name,'Supplier #'||rec.id)||' — '||rec.doc||' expires '||rec.exp||'. Follow up for renewal.');
      n:=n+1;
    end if;
  end loop;
  return jsonb_build_object('flagged',n,'scanned_at',now());
end $$;

select cron.schedule('doc_expiry_daily','20 5 * * *', $$select public.fn_doc_expiry_scan();$$);
update public.leads set trn = trn where true;  -- fire capability trigger to backfill scores
select count(*) filter (where capability_score>=60) as strong_profiles, count(*) as total, round(avg(capability_score),1) as avg_cap from public.leads;
