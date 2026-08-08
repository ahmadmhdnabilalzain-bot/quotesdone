-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709080450   name: supplier_cert_expiry_monitoring
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- 1) expiry + doc tracking for ISO and manufacturer authorisations
alter table public.leads
  add column if not exists iso_expiry date,
  add column if not exists iso_doc_path text,
  add column if not exists manufacturer_auth_expiry date,
  add column if not exists manufacturer_auth_doc_path text;

-- 2) extend the owner-facing expiry scan to include ISO + manufacturer authorisations
create or replace function public.fn_doc_expiry_scan()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public','pg_temp'
as $function$
declare rec record; n int:=0; owner text;
begin
  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into owner from app_secrets where key='admin_emails';
  for rec in
    select id, company_name, 'trade licence' as doc, license_expiry as exp from leads where license_expiry is not null and license_expiry <= current_date+30 and coalesce(approval_status,'')='approved'
    union all
    select id, company_name, 'insurance', insurance_expiry from leads where insurance_expiry is not null and insurance_expiry <= current_date+30 and coalesce(approval_status,'')='approved'
    union all
    select id, company_name, 'registration', registration_expires_at::date from leads where registration_expires_at is not null and registration_expires_at::date <= current_date+30 and coalesce(approval_status,'')='approved'
    union all
    select id, company_name, 'ISO certification', iso_expiry from leads where iso_expiry is not null and iso_expiry <= current_date+30 and coalesce(approval_status,'')='approved'
    union all
    select id, company_name, 'manufacturer authorisation', manufacturer_auth_expiry from leads where manufacturer_auth_expiry is not null and manufacturer_auth_expiry <= current_date+30 and coalesce(approval_status,'')='approved'
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
end $function$;
