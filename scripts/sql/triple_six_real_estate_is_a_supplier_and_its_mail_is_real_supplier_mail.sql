-- TRIPLE SIX REAL ESTATE IS A SUPPLIER, AND ITS MAIL IS REAL SUPPLIER MAIL.
-- Seat: sales_engineer. 18 Nov 2026. Founder ruling 1729 (ledger row 1729).
--
-- WHAT WAS MEASURED (production, read-only, 18 Nov 2026):
--   * fn_is_founder_own_inbox named 'ahmad@666realestate.ae' in its literal list since a_supplier_reply_gets_the_action_it_asked_for.sql
--     (review of #1746: a warm-up reply to the founder's hand-sent test). No other routine body names 666realestate; app_secrets
--     founder_email and admin_emails do not either. 'info@666realestate.ae' was never on the list.
--   * Triple Six Real Estate is lead 158318: approved, verified, claimed_by info@666realestate.ae, is_demo false. Its owner writes
--     from ahmad@666realestate.ae. The founder has e-mail authority over the company, and it is a legitimate supplier: ruling 1729,
--     "its mail must be treated as real supplier mail, not test mail".
--   * Nine routines read fn_is_founder_own_inbox: trg_a05_test_reply_leaves_review (a founder inbox's reply leaves review as a test),
--     fn_notifications_no_test_mail_to_the_founder (a seed may not be addressed to him: a01 trigger, seed kinds only), the supplier
--     mailbox owners (fn_supplier_mailbox_mail_gets_its_owner, fn_mailbox_reply_hard_rule) and the reply / follow-up / chase handlers
--     of the sales engineer, and the contact-message trigger. Each treats a founder inbox as "nobody is waiting, nothing is sent".
--
-- WHAT THIS CHANGES: fn_is_founder_own_inbox without 'ahmad@666realestate.ae', so Triple Six's mail from either address is read,
-- owned, answered and chased like any other supplier's. The founder's own inboxes (management@, his Gmail, the Dorata, DJ Zaino
-- and family addresses, and app_secrets founder_email / admin_emails) are unchanged, so his own test flows (no seed to his
-- inboxes, a test reply leaves review) are unchanged. Rows already closed as "the founder's own address" (handoff 329843, case
-- QD-S-SDGR7P) stay closed: they are history, and a new message opens its own. Rollback: the body in
-- a_supplier_reply_gets_the_action_it_asked_for.sql.
--
-- Pending: scripts/sql/pending/triple_six_real_estate_is_a_supplier_and_its_mail_is_real_supplier_mail.txt
-- Prevented by: scripts/checks/a_registered_supplier_is_never_the_founders_own_inbox.test.mjs

create or replace function public.fn_is_founder_own_inbox(p_addr text)
returns boolean
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_list text[]; v text;
begin
  if p_addr is null or btrim(p_addr) = '' then return false; end if;
  select array_agg(public.fn_mailbox_fold(a)) into v_list
    from (select unnest(array['management@quotesdone.com', 'ahmadmhdnabilalzain@gmail.com',
                              'management@doratajewelries.com', 'djzaino@outlook.com', 'bookings@djzaino.com',
                              'fati.labib@icloud.com']) a
          union all
          select btrim(x) from public.app_secrets s, regexp_split_to_table(coalesce(s.value, ''), ',') x
           where s.key in ('founder_email', 'admin_emails') and btrim(x) like '%@%') l;
  v := public.fn_mailbox_fold(p_addr);
  return v = any(v_list);
end $fn$;
revoke execute on function public.fn_is_founder_own_inbox(text) from public, anon, authenticated;

select case
  when public.fn_is_founder_own_inbox('ahmad@666realestate.ae') then 'PROBE FAILED: ahmad@666realestate.ae is still read as the founder''s own inbox'
  when public.fn_is_founder_own_inbox('info@666realestate.ae') then 'PROBE FAILED: info@666realestate.ae is read as the founder''s own inbox'
  when not public.fn_is_founder_own_inbox('management@quotesdone.com') then 'PROBE FAILED: management@ is no longer his'
  when not public.fn_is_founder_own_inbox('ahmadmhdnabilalzain@gmail.com') then 'PROBE FAILED: his Gmail is no longer his'
  when not public.fn_is_founder_own_inbox('fati.labib@icloud.com') then 'PROBE FAILED: a family address is no longer his'
  when has_function_privilege('anon', 'public.fn_is_founder_own_inbox(text)', 'execute') then 'PROBE FAILED: anon may execute it'
  else 'PROBE OK: Triple Six Real Estate is a supplier; the founder''s own inboxes are unchanged' end as verdict;
