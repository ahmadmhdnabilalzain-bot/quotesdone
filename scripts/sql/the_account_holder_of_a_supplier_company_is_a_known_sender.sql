-- THE ACCOUNT HOLDER OF A SUPPLIER COMPANY IS A KNOWN SENDER (2 Nov 2026). Assigned: customer_support.
--
-- MEASURED: lead 19398 holds leads.email info@algouri.com and leads.claimed_by sales@algouri.com. send_outbox gives a
-- claimed_by address the Reply-To supplier@quotesdone.com, and email_triage answers mail to that mailbox only when
-- fn_mail_sender_known says 'supplier'. The routine read leads.email alone, so the account holder's next reply was
-- declined as a stranger's. It now also reads claimed_by, through the leads_claimed_by_lower_uidx expression.
--
-- The body is production's, read 2 Nov 2026, plus the one clause. CREATE OR REPLACE keeps the ACL, so there is no revoke.
-- Prevented by: scripts/checks/the_account_holder_of_a_supplier_company_is_a_known_sender.test.mjs
create or replace function public.fn_mail_sender_known(p_email text)
 returns text
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare e text := lower(btrim(coalesce(p_email, '')));
begin
  if e = '' then return null; end if;
  if exists (select 1 from public.app_secrets s, unnest(string_to_array(lower(s.value), ',')) a
              where s.key in ('admin_emails', 'expense_forwarders', 'founder_email') and btrim(a) = e) then return 'staff'; end if;
  if exists (select 1 from public.customers where lower(email) = e) then return 'customer'; end if;
  if exists (select 1 from public.leads where lower(email) = e) then return 'supplier'; end if;
  if exists (select 1 from public.leads where lower(btrim(claimed_by)) = e) then return 'supplier'; end if;
  return null;
end $function$;
