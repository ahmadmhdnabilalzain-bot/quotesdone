-- ============================================================================
-- ACTION-EXECUTOR REGISTRY + SUPPLIER SUCCESS executors.
-- The general mechanism that turns a department's ledger task into a REAL side
-- effect: cos_execute (v3) consults org_action_executor — an action_class with
-- an active executor is EXECUTED (mode:'executed'), otherwise the advisory
-- deliverable path runs (mode:'prepared'/'delivered'). Every future department
-- wires its real executors here by INSERT — no code edits.
-- ============================================================================
create table if not exists public.org_action_executor (
  action_class text primary key,
  kind text not null check (kind in ('rpc','edge')),
  target text not null,                 -- rpc: function name; edge: function slug
  params jsonb not null default '{}',   -- static args passed to the executor
  active boolean not null default true,
  note text,
  created_at timestamptz not null default now()
);
alter table public.org_action_executor enable row level security;

-- Supplier Success executor #1: send the next batch of invites, safely.
-- Thin jsonb wrapper over enqueue_supplier_invites (self-limits to the daily cap,
-- targets under-served trades, auto-pauses on bounce). Honest when the campaign is off.
create or replace function public.fn_org_exec_invite(p_cap int default null)
returns jsonb language plpgsql security definer set search_path to 'public','pg_catalog'
as $function$
declare v_enabled boolean; v_cap int; v_sent int;
begin
  v_enabled := coalesce((select value from app_secrets where key='invite_enabled'),'false')='true';
  v_cap := coalesce((select nullif(value,'')::int from app_secrets where key='invite_daily_cap'), 10);
  select public.enqueue_supplier_invites(p_cap) into v_sent;
  return jsonb_build_object(
    'invited', coalesce(v_sent,0),
    'campaign_enabled', v_enabled,
    'daily_cap', v_cap,
    'note', case when not v_enabled then 'Invite campaign is not enabled yet — 0 sent. It starts on its scheduled date; the deliverability-gated ramp will then send within the daily cap.'
                 else 'Enqueued '||coalesce(v_sent,0)||' invite(s) this run, within the daily cap of '||v_cap||' and bounce-rate guard.' end
  );
end $function$;
revoke execute on function public.fn_org_exec_invite(int) from public, anon, authenticated;
grant execute on function public.fn_org_exec_invite(int) to service_role;

-- Supplier Success executor #2: auto-approve ONLY licence-OCR-clean suppliers (supervised — founder
-- audits; approval_decided_by tags each row and the daily brief counts 'chief_of_staff (auto)').
-- STRICT clean criteria; anything not fully clean is left for manual review, never rejected.
create or replace function public.fn_supplier_autoapprove_clean(p_limit int default 25)
returns jsonb language plpgsql security definer set search_path to 'public','pg_catalog'
as $function$
declare v_ids bigint[]; v_approved int := 0; v_scanned int; r record;
begin
  select count(*) into v_scanned from leads
    where approval_status in ('pending','submitted') and coalesce(banned,false)=false;

  select array_agg(id) into v_ids from (
    select id from leads
    where approval_status in ('pending','submitted')
      and coalesce(banned,false) = false
      and registration_submitted_at is not null
      and license_doc_path is not null
      and doc_extracted_at is not null
      and trade_license_no is not null and length(trade_license_no) > 3
      and license_expiry is not null and license_expiry > current_date + 30
      and coalesce(owner_email_verified,false) = true
    order by registration_submitted_at
    limit greatest(1, coalesce(p_limit,25))
  ) z;

  if v_ids is null then
    return jsonb_build_object('approved',0,'candidates_scanned',v_scanned,'note','No licence-OCR-clean applicants to auto-approve; any remaining applicants need manual review.');
  end if;

  for r in select id, company_name, coalesce(claimed_by,email) as contact from leads where id = any(v_ids) loop
    update leads set approval_status='approved', verified=true, verification_status='verified',
      lifecycle_stage='active', approved_at=now(), approval_decided_by='chief_of_staff (auto)'
      where id = r.id;
    if r.contact is not null then
      insert into notifications(type,to_email,to_role,lead_id,channel,subject,body)
      values('registration_approved', r.contact, 'supplier', r.id, 'email',
        'You''re verified on QuotesDone',
        'Good news — '||coalesce(r.company_name,'your company')||' has been verified on QuotesDone (trade licence checks passed). You can now receive inquiries and quote: https://quotesdone.com/suppliers/');
    end if;
    v_approved := v_approved + 1;
  end loop;

  return jsonb_build_object('approved',v_approved,'candidates_scanned',v_scanned,'approved_ids',v_ids,
    'note','Auto-approved '||v_approved||' licence-OCR-clean supplier(s); '||(v_scanned - v_approved)||' applicant(s) left for manual review.');
end $function$;
revoke execute on function public.fn_supplier_autoapprove_clean(int) from public, anon, authenticated;
grant execute on function public.fn_supplier_autoapprove_clean(int) to service_role;

-- Seed the registry for Supplier Success.
insert into public.org_action_executor(action_class, kind, target, params, note) values
('invite','rpc','fn_org_exec_invite','{}','Send the next batch of supplier invites within the deliverability-gated daily ramp.'),
('supplier_approve_clean','rpc','fn_supplier_autoapprove_clean','{}','Auto-approve only licence-OCR-clean suppliers; leave the rest for manual review (founder audits).')
on conflict (action_class) do update set kind=excluded.kind, target=excluded.target, params=excluded.params, note=excluded.note, active=true;

insert into public.org_memory(scope,kind,content,source) values
('supplier_success','policy','Supplier Success executes real actions via the action registry: invite (autonomous) sends within the deliverability-gated ramp; supplier_approve_clean (supervised) auto-approves ONLY licence-OCR-clean suppliers (licence uploaded + OCR''d + licence number + valid 30+ day expiry + verified owner email + not banned), leaving anything else for manual review. Every auto-approval is tagged chief_of_staff (auto) and surfaced in the founder brief.','founder_directive')
on conflict do nothing;