-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260710223646   name: pdpl_dsar_workflow
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- PDPL (UAE) data-subject workflow over the existing pdpl_requests intake table.
-- Export = access/portability (read-only). Plan = dry-run. Redact = governed, approval-gated, non-destructive.

create or replace function public.fn_pdpl_export(p_email text)
returns jsonb language sql stable security definer set search_path to 'public','pg_temp' as $$
  select jsonb_build_object(
    'subject', p_email,
    'generated_at', now(),
    'customers',           (select coalesce(jsonb_agg(to_jsonb(c)),'[]'::jsonb) from public.customers c where c.email=p_email),
    'inquiries',           (select coalesce(jsonb_agg(to_jsonb(i)),'[]'::jsonb) from public.inquiries i where i.customer_id in (select id from public.customers where email=p_email)),
    'supplier_leads',      (select coalesce(jsonb_agg(to_jsonb(l)),'[]'::jsonb) from public.leads l where l.email=p_email),
    'notifications',       (select coalesce(jsonb_agg(to_jsonb(n)),'[]'::jsonb) from public.notifications n where n.to_email=p_email),
    'outreach',            (select coalesce(jsonb_agg(to_jsonb(o)),'[]'::jsonb) from public.outreach o where o.email=p_email),
    'email_verifications', (select coalesce(jsonb_agg(to_jsonb(e)),'[]'::jsonb) from public.email_verifications e where e.email=p_email),
    'phone_verifications', (select coalesce(jsonb_agg(to_jsonb(p)),'[]'::jsonb) from public.phone_verifications p where p.email=p_email),
    'email_suppressions',  (select coalesce(jsonb_agg(to_jsonb(s)),'[]'::jsonb) from public.email_suppressions s where s.email=p_email),
    'ai_usage',            (select coalesce(jsonb_agg(to_jsonb(a)),'[]'::jsonb) from public.ai_usage a where a.email=p_email)
  );
$$;
revoke all on function public.fn_pdpl_export(text) from anon, authenticated;

create or replace function public.fn_pdpl_erase_plan(p_email text)
returns jsonb language sql stable security definer set search_path to 'public','pg_temp' as $$
  select jsonb_build_object(
    'subject', p_email,
    'customers',           (select count(*) from public.customers where email=p_email),
    'inquiries',           (select count(*) from public.inquiries where customer_id in (select id from public.customers where email=p_email)),
    'supplier_leads',      (select count(*) from public.leads where email=p_email),
    'notifications',       (select count(*) from public.notifications where to_email=p_email),
    'outreach',            (select count(*) from public.outreach where email=p_email),
    'email_verifications', (select count(*) from public.email_verifications where email=p_email),
    'phone_verifications', (select count(*) from public.phone_verifications where email=p_email),
    'ai_usage',            (select count(*) from public.ai_usage where email=p_email),
    'note','Redaction anonymises personal fields (name/phone/email/DOB) and keeps financial/audit records as legally required. email_suppressions is deliberately retained as a do-not-contact record.'
  );
$$;
revoke all on function public.fn_pdpl_erase_plan(text) from anon, authenticated;

-- Approval-gated, non-destructive redaction. Requires the pdpl_requests row to be status='approved'.
create or replace function public.fn_pdpl_redact(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v_email text; v_status text; c_cust int:=0; c_lead int:=0; c_notif int:=0; c_out int:=0; c_ev int:=0; c_pv int:=0; c_ai int:=0;
begin
  select email, status into v_email, v_status from public.pdpl_requests where id=p_request_id;
  if not found then raise exception 'pdpl request % not found', p_request_id; end if;
  if coalesce(v_status,'') <> 'approved' then
    raise exception 'pdpl request % must be status=approved before redaction (current: %)', p_request_id, coalesce(v_status,'null');
  end if;
  if v_email is null then raise exception 'pdpl request % has no email', p_request_id; end if;

  update public.customers set full_name='[erased-PDPL]', phone=null, date_of_birth=null,
         email='erased_'||id||'@removed.invalid' where email=v_email;
  get diagnostics c_cust = row_count;
  update public.leads set phone=null, whatsapp=null, email=null, matching_blocked=true where email=v_email;
  get diagnostics c_lead = row_count;
  update public.notifications set to_email='[erased]', to_phone=null where to_email=v_email;
  get diagnostics c_notif = row_count;
  update public.outreach set email='[erased]' where email=v_email;
  get diagnostics c_out = row_count;
  update public.email_verifications set email='[erased]' where email=v_email;
  get diagnostics c_ev = row_count;
  update public.phone_verifications set email='[erased]' where email=v_email;
  get diagnostics c_pv = row_count;
  update public.ai_usage set email='[erased]' where email=v_email;
  get diagnostics c_ai = row_count;

  update public.pdpl_requests set status='completed', handled_at=now(),
         handled_by=coalesce(handled_by,'fn_pdpl_redact') where id=p_request_id;

  insert into public.security_events(kind,severity,source,subject,detail)
  values('pdpl_redaction','high','pdpl', v_email,
         jsonb_build_object('request_id',p_request_id,'customers',c_cust,'leads',c_lead,'notifications',c_notif,
                            'outreach',c_out,'email_verifications',c_ev,'phone_verifications',c_pv,'ai_usage',c_ai));

  return jsonb_build_object('subject',v_email,'redacted',
    jsonb_build_object('customers',c_cust,'supplier_leads',c_lead,'notifications',c_notif,'outreach',c_out,
                       'email_verifications',c_ev,'phone_verifications',c_pv,'ai_usage',c_ai),
    'kept','email_suppressions retained as do-not-contact');
end $$;
revoke all on function public.fn_pdpl_redact(uuid) from anon, authenticated;
