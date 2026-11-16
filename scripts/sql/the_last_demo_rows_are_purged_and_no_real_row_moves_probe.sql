-- PROBE: NO DEMO ROW IS LEFT, AND THE KEPT ACCOUNTS ARE THERE (ledger 1121, 1199, 1214, 1539; it_engineer).
--
-- A pure probe, no DDL, nothing written: it always raises CHK<<...>>. Run it after
-- scripts/sql/the_last_demo_rows_are_purged_and_no_real_row_moves.sql. Before that apply it prints PROBE FAILED and names
-- what is left (16 Nov 2026: 12 logins, 2 customers, 1 lead, 3 inquiries, ...); after it, PROBE OK.
--   1. fn_demo_purge_verify reads 0 for every table it counts. The storage and Dropbox queues of the demo purge, and the
--      backup records waiting on them, are reported, not failed: dropbox_backup drains them after the apply (~3 hours);
--      `node scripts/it/purge_demo_data.mjs --verify-zero` is the check that they reached 0.
--   2. By the same markers, nothing demo is left where fn_demo_purge_verify does not look: quotes, transactions, support
--      cases, WhatsApp conversations, suppressions, verification codes, intake rows.
--   3. Kept: the founder's two customer accounts (0dc8c94f, ba61fa16) and their logins, leads 19398, 158318 and 143027,
--      none of them demo.
do $probe$
declare v jsonb; v_bad text; v_more jsonb; v_kept jsonb;
begin
  v := public.fn_demo_purge_verify();
  select string_agg(t.key || ' ' || t.value, ', ') into v_bad from jsonb_each_text(v) t
   where t.key not in ('storage_queue_open', 'dropbox_queue_open', 'doc_backups') and t.value::bigint <> 0;
  v_more := jsonb_build_object(
    'quotes', (select count(*) from public.quotes q where public.fn_quote_is_demo(q.id)),
    'transactions', (select count(*) from public.transactions t where public.fn_transaction_is_demo(t.id)),
    'support_case', (select count(*) from public.support_case where public.fn_party_is_demo(party_kind, party_id)),
    'wa_conversation', (select count(*) from public.wa_conversation where public.fn_is_demo_phone(phone_e164) or public.fn_party_is_demo(party_kind, party_id)),
    'email_suppressions', (select count(*) from public.email_suppressions where public.fn_demo_purge_address(email)),
    'phone_verifications', (select count(*) from public.phone_verifications where public.fn_demo_purge_address(email) or public.fn_is_demo_phone(phone)),
    'inquiry_intake', (select count(*) from public.inquiry_intake where public.fn_demo_purge_address(email)));
  select concat_ws(', ', v_bad, string_agg(t.key || ' ' || t.value, ', ')) into v_bad from jsonb_each_text(v_more) t where t.value::bigint <> 0;
  v_kept := jsonb_build_object(
    'founder_customers', (select count(*) from public.customers where left(id::text, 8) in ('0dc8c94f', 'ba61fa16') and not coalesce(is_demo, false)),
    'founder_logins', (select count(*) from auth.users u join public.customers c on lower(c.email) = lower(u.email)
                        where left(c.id::text, 8) in ('0dc8c94f', 'ba61fa16') and not coalesce(c.is_demo, false)),
    'kept_leads', (select count(*) from public.leads where id in (19398, 158318, 143027) and not coalesce(is_demo, false)));
  if nullif(v_bad, '') is not null then
    raise exception 'CHK<<PROBE FAILED: demo rows left: %; kept %>>', v_bad, v_kept;
  end if;
  if v_kept <> '{"founder_customers": 2, "founder_logins": 2, "kept_leads": 3}'::jsonb then
    raise exception 'CHK<<PROBE FAILED: a kept account or lead is missing or demo: %>>', v_kept;
  end if;
  raise exception 'CHK<<PROBE OK: 0 demo rows in every table; kept %; still queued for dropbox_backup: storage % , Dropbox %, backup records %>>',
    v_kept, v->>'storage_queue_open', v->>'dropbox_queue_open', v->>'doc_backups';
end $probe$;
