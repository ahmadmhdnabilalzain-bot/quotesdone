-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260711172717   name: fn_ws_refunds_add_txid
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_ws_refunds()
returns jsonb language sql stable security definer set search_path to 'public','pg_catalog' as $$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'pending', (select count(*) from transactions where refund_status in ('requested','pending')),
      'within_window', (select count(*) from transactions where refund_status in ('requested','pending') and refund_deadline > now()),
      'resolved_30d', (select count(*) from transactions where refund_resolved_at > now() - interval '30 days')
    ),
    'pending', (select coalesce(jsonb_agg(r order by r.requested desc),'[]'::jsonb) from (
        select t.id as transaction_id, t.quote_id, t.reveal_fee, coalesce(t.refund_status,'—') refund_status, coalesce(t.refund_reason,'—') reason,
               to_char(t.refund_requested_at,'YYYY-MM-DD') requested, to_char(t.refund_deadline,'YYYY-MM-DD') deadline,
               (t.refund_deadline > now()) in_window, coalesce(c.full_name,'—') customer, coalesce(l.company_name,'—') supplier
        from transactions t left join customers c on c.id=t.customer_id left join leads l on l.id=t.supplier_id
        where t.refund_status in ('requested','pending') order by t.refund_requested_at desc limit 100) r),
    'recent_resolved', (select coalesce(jsonb_agg(r order by r.resolved desc),'[]'::jsonb) from (
        select t.id as transaction_id, t.quote_id, coalesce(t.refund_status,'—') refund_status, coalesce(t.refund_note,'—') note,
               to_char(t.refund_resolved_at,'YYYY-MM-DD') resolved
        from transactions t where t.refund_resolved_at is not null order by t.refund_resolved_at desc limit 25) r)
  );
$$;
grant execute on function public.fn_ws_refunds() to service_role;
