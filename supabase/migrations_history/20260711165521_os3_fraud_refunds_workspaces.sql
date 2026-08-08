-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260711165521   name: os3_fraud_refunds_workspaces
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Read-only workspace RPCs to surface Fraud queue + Refund requests inside os3 (parity with legacy admin/crm)
create or replace function public.fn_ws_fraud()
returns jsonb language sql stable security definer set search_path to 'public','pg_catalog' as $$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'open_flags', (select count(*) from fraud_flags where coalesce(status,'open') not in ('dismissed','resolved','closed')),
      'high_severity', (select count(*) from fraud_flags where lower(coalesce(severity,'')) in ('high','critical') and coalesce(status,'open') not in ('dismissed','resolved','closed')),
      'flags_7d', (select count(*) from fraud_flags where created_at > now() - interval '7 days'),
      'banned_actors', (select (select count(*) from customers where banned) + (select count(*) from leads where banned))
    ),
    'open_flags', (select coalesce(jsonb_agg(f order by f.created desc),'[]'::jsonb) from (
        select kind, subject_type, subject_id, coalesce(severity,'—') severity, coalesce(status,'open') status,
               to_char(created_at,'YYYY-MM-DD HH24:MI') created, detail
        from fraud_flags where coalesce(status,'open') not in ('dismissed','resolved','closed')
        order by created_at desc limit 100) f),
    'banned', (select coalesce(jsonb_agg(b),'[]'::jsonb) from (
        select 'customer' kind, id::text subject_id, full_name name, banned_reason reason from customers where banned
        union all
        select 'supplier', id::text, company_name, banned_reason from leads where banned limit 100) b)
  );
$$;

create or replace function public.fn_ws_refunds()
returns jsonb language sql stable security definer set search_path to 'public','pg_catalog' as $$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'pending', (select count(*) from transactions where refund_status in ('requested','pending')),
      'within_window', (select count(*) from transactions where refund_status in ('requested','pending') and refund_deadline > now()),
      'resolved_30d', (select count(*) from transactions where refund_resolved_at > now() - interval '30 days')
    ),
    'pending', (select coalesce(jsonb_agg(r order by r.requested desc),'[]'::jsonb) from (
        select t.quote_id, t.reveal_fee, coalesce(t.refund_status,'—') refund_status, coalesce(t.refund_reason,'—') reason,
               to_char(t.refund_requested_at,'YYYY-MM-DD') requested, to_char(t.refund_deadline,'YYYY-MM-DD') deadline,
               (t.refund_deadline > now()) in_window, coalesce(c.full_name,'—') customer, coalesce(l.company_name,'—') supplier
        from transactions t left join customers c on c.id=t.customer_id left join leads l on l.id=t.supplier_id
        where t.refund_status in ('requested','pending') order by t.refund_requested_at desc limit 100) r),
    'recent_resolved', (select coalesce(jsonb_agg(r order by r.resolved desc),'[]'::jsonb) from (
        select t.quote_id, coalesce(t.refund_status,'—') refund_status, coalesce(t.refund_note,'—') note,
               to_char(t.refund_resolved_at,'YYYY-MM-DD') resolved
        from transactions t where t.refund_resolved_at is not null order by t.refund_resolved_at desc limit 25) r)
  );
$$;

revoke all on function public.fn_ws_fraud() from public, anon, authenticated;
revoke all on function public.fn_ws_refunds() from public, anon, authenticated;
grant execute on function public.fn_ws_fraud() to service_role;
grant execute on function public.fn_ws_refunds() to service_role;
