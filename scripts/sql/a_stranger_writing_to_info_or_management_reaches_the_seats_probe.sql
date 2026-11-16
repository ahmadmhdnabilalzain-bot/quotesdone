-- PROBE: A STRANGER WRITING TO info@ OR management@ REACHES THE SEATS (ledger 1446, 1453, 1543; it_engineer).
--
-- A pure probe, no DDL, nothing written: it always raises CHK<<...>>. It fails before
-- scripts/sql/a_stranger_writing_to_info_or_management_reaches_the_seats.sql is applied (no switch: every stranger's mail
-- to info@ and management@ is 'skipped' by pollTenantMailboxes) and passes after it.
--   1. app_secrets.m365_tenant_strangers_from exists and is the ISO form Date.parse reads (YYYY-MM-DDTHH:MM:SSZ);
--   2. it is not in the future (a future time would hand nothing until then);
--   3. the mail path it opens still exists: the reply address of the sign-in code and KYC mails is info@quotesdone.com,
--      the mailbox pollTenantMailboxes reads (app_secrets.email_reply_info; login_otp and kyc fall back to the same address).
do $probe$
declare v text; v_reply text;
begin
  select value into v from public.app_secrets where key = 'm365_tenant_strangers_from';
  select lower(btrim(value)) into v_reply from public.app_secrets where key = 'email_reply_info';
  if v is null then
    raise exception 'CHK<<PROBE FAILED: app_secrets.m365_tenant_strangers_from is not set, so a stranger''s mail to info@ and management@ is never handed>>';
  end if;
  if v !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$' then
    raise exception 'CHK<<PROBE FAILED: m365_tenant_strangers_from = % is not the ISO form the poller reads>>', v;
  end if;
  if v::timestamptz > now() then
    raise exception 'CHK<<PROBE FAILED: m365_tenant_strangers_from % is in the future>>', v;
  end if;
  if coalesce(v_reply, 'info@quotesdone.com') <> 'info@quotesdone.com' then
    raise exception 'CHK<<PROBE FAILED: the code and KYC mails reply to %, not the info@ mailbox this switch opens>>', v_reply;
  end if;
  raise exception 'CHK<<PROBE OK: a stranger''s new mail to info@ and management@ is handed from % (replies to code and KYC mails go to info@quotesdone.com)>>', v;
end $probe$;
