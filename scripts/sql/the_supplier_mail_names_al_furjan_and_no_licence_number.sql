-- THE SUPPLIER MAIL NAMES AL FURJAN AND NO LICENCE NUMBER, AND THE INVITATION HAS A PREHEADER
-- (24 Sep 2026, marketing seat - it owns the invitation. Ledger 993.)
--
-- The founder's go for the supplier campaign is hours away. The invitation was rendered from the live
-- rows (scripts/invitation_inbox_check.mjs, fn_supplier_invite_candidates(1)) and checked against his
-- campaign rules. MEASURED, 24 Sep 2026 11:06 UTC:
--   1. templates.email_supplier's footer read "QuotesDone Technologies · Dubai, UAE · DET Trader Licence
--      No. 1633275 · TDRA NOL-26-100000665". The rule: no trade licence number, and the address is
--      Dubai - Al Furjan. (The text/plain footer in send_outbox/supplier_mail.ts said the same; it is
--      changed in the same PR.)
--   2. No preheader. The inbox line beside the subject was the first words of the body, "Dear <company>,".
--   3. app_secrets.invite_body ended "If you would prefer not to receive these invitations, simply reply
--      and we will remove you." A reply goes to suppliers@mail.quotesdone.com, and resend_inbound only
--      suppresses a reply whose subject or first line is ONLY the request (_shared/unsubscribe_mailbox.ts),
--      so "please remove me from your list" would not remove anyone. The footer already carries a one-click
--      link and the unsubscribe@ mailbox; the sentence now points at them.
--
-- WHAT THIS CHANGES: the footer of templates.email_supplier (every supplier mail, not only the invitation),
-- the last sentence of app_secrets.invite_body, and a new app_secrets.invite_preheader, read by send_outbox
-- for type supplier_invite*. English only: invitations are always English.
-- WHAT IT DOES NOT CHANGE: invite_enabled / supplier_outreach_golive, the Arabic invite_body_ar (no Arabic
-- invitation is sent), the customer template, the TDRA permit line (the site's permit, not the licence).
--
-- ORDER: apply this, then deploy send_outbox. Either half alone is safe: an older function renders the
-- new template with no preheader; a newer function renders the old template with the licence line.

update public.templates
   set content = replace(content,
         'QuotesDone Technologies &middot; Dubai, UAE &middot; DET Trader Licence No. 1633275 &middot; TDRA NOL-26-100000665',
         'QuotesDone Technologies &middot; Al Furjan, Dubai, UAE &middot; TDRA NOL-26-100000665')
 where name = 'email_supplier';

update public.app_secrets
   set value = replace(value,
         'If you would prefer not to receive these invitations, simply reply and we will remove you.',
         'If you would prefer not to receive these invitations, use the unsubscribe link at the foot of this email and we will not write again.')
 where key = 'invite_body';

insert into public.app_secrets (key, value)
values ('invite_preheader', 'Free for the first 1,000 suppliers, permanently. No commission, ever. Register in minutes.')
on conflict (key) do nothing;

do $probe$
declare v_tpl text; v_body text; v_pre text;
begin
  select content into v_tpl from public.templates where name = 'email_supplier';
  select value into v_body from public.app_secrets where key = 'invite_body';
  select value into v_pre from public.app_secrets where key = 'invite_preheader';
  if v_tpl like '%1633275%' or v_tpl not like '%Al Furjan, Dubai, UAE%' then
    raise exception 'email_supplier footer not corrected (the stored wording differs from the measured one; read it and edit this file)';
  end if;
  if v_body like '%simply reply and we will remove you%' or v_body not like '%unsubscribe link at the foot%' then
    raise exception 'invite_body closing sentence not corrected';
  end if;
  if coalesce(v_pre, '') = '' or v_pre ~* '\mAI\M' then raise exception 'invite_preheader missing or says AI'; end if;
end $probe$;
