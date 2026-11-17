-- PROBE for the_forty_six_tables_made_after_the_12_november_mirror_are_in_the_daily_export.sql. Seat: it_engineer. Never
-- applied: it writes nothing and always raises CHK<<...>>, so the transaction rolls back either way. Run it after the file.
-- Asserts: each of the 46 tables exists and has its registry row as the file decided it; the 43 exported ones are in
-- fn_table_export_list() (what backup/index.ts exports every day); no public table is left without a row; and no exported
-- row names a table that does not exist (the export would fail that day on it).
do $probe$
declare
  v_excluded text[] := array['pool_event_class', 'seat_pool_digest', 'demo_shadow_trace'];
  v_exported text[] := array['accountant_cost_driver', 'accountant_request_economics', 'accountant_reveal_payment_check',
    'ceo_grant_once', 'ceo_growth_channel', 'ceo_own_decision', 'ceo_plan_bet', 'ceo_plan_week', 'ceo_supply_decision',
    'company_limit_change', 'company_spend_commitment', 'customer_referral', 'engineer_session_request', 'escalation_clock',
    'expense_awaiting_document', 'founder_funding_commitment', 'inquiry_decision_reason', 'inquiry_revision',
    'marketing_search_day', 'marketing_search_sitemap', 'quote_figure_confirmation', 'request_reveal_outcome',
    'reveal_bill_to', 'seat_capability', 'seat_order_thread', 'seat_order_turn', 'subject_link', 'supplier_account_closure',
    'supplier_contact_removal_notice', 'supplier_coverage_target', 'supplier_customer_silence', 'supplier_demand_signal',
    'supplier_loss_reason', 'supplier_member', 'supplier_ownership_claim', 'supplier_ownership_transfer', 'supplier_referral',
    'supplier_referral_code', 'supplier_strike_warning_retry', 'supplier_trade_correction', 'supplier_whatsapp_offer_declined',
    'supplier_whatsapp_optin_code_miss', 'supplier_whatsapp_optin_pending'];
  v_bad text := ''; v_t text; v_listed int; v_left text; v_gone text;
begin
  if cardinality(v_exported) <> 43 then v_bad := v_bad || ' exported-list=' || cardinality(v_exported); end if;
  foreach v_t in array v_exported || v_excluded loop
    if to_regclass('public.' || v_t) is null then v_bad := v_bad || ' no-table:' || v_t; end if;
  end loop;
  foreach v_t in array v_exported loop
    if not exists (select 1 from public.table_export_registry r where r.table_name = v_t and r.exported) then
      v_bad := v_bad || ' not-exported:' || v_t; end if;
  end loop;
  foreach v_t in array v_excluded loop
    if not exists (select 1 from public.table_export_registry r where r.table_name = v_t and not r.exported) then
      v_bad := v_bad || ' not-excluded:' || v_t; end if;
  end loop;
  select count(*) into v_listed from public.fn_table_export_list() l where l.table_name = any (v_exported);
  if v_listed <> 43 then v_bad := v_bad || ' listed=' || v_listed; end if;
  select string_agg(c.relname, ',') into v_left from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p')
     and not exists (select 1 from public.table_export_registry r where r.table_name = c.relname);
  if v_left is not null then v_bad := v_bad || ' still-unregistered:' || v_left; end if;
  select string_agg(r.table_name, ',') into v_gone from public.table_export_registry r
   where r.exported and to_regclass('public.' || r.table_name) is null;
  if v_gone is not null then v_bad := v_bad || ' exported-but-missing:' || v_gone; end if;
  if v_bad <> '' then raise exception 'CHK<<PROBE FAILED:%>>', v_bad; end if;
  raise exception 'CHK<<PROBE OK 43 exported and listed, 3 excluded, no public table without a row>>';
end $probe$;
