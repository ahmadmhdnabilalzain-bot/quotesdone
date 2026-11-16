-- PROBE: AN UNDELIVERED STRIKE WARNING IS SENT AGAIN ANOTHER WAY. Seat: sales_engineer. Agent: W3_PEOPLE, 16 Nov 2026.
-- Pure probe: no DDL, never applied; run after an_undelivered_strike_warning_is_sent_again_another_way.sql on a LOCAL Postgres 16.
-- It always raises, so every row is rolled back. Every party is a ZZ DEMO fixture on @example.invalid.
-- PROBE OK only if, for a supplier one short of the stop whose warning e-mail BOUNCED:
--   1. the warning is sent again to another address the company has (its listed e-mail, then an active member's), one per run;
--   2. with no other address left, a WhatsApp copy goes to his confirmed number when none was sent;
--   3. with nothing left to try, the sales engineer gets ONE task to reach him another way (never silent);
--   4. a warning that was delivered, a supplier not at the warning, and one whose count was cleared get nothing;
--   5. the stop itself is still refused while no warning reached him (the production rule, unchanged).
do $probe$
declare
  fails text := ''; s bigint; s_ok bigint; s_wa bigint; j jsonb; n int; v_limit int := public.fn_matching_strike_limit();
  v_owner text := 'zz-demo-w3s-owner@example.invalid'; v_list text := 'zz-demo-w3s-office@example.invalid'; v_mem text := 'zz-demo-w3s-mem@example.invalid';
begin
  insert into public.leads (company_name, email, claimed_by, claimed, emirate, phone, owner_email_verified, chat_strikes)
  values ('ZZ DEMO W3S Bounced', v_list, v_owner, true, 'Dubai', '+971500000721', true, v_limit - 1) returning id into s;
  insert into public.leads (company_name, email, claimed_by, claimed, emirate, phone, owner_email_verified, chat_strikes)
  values ('ZZ DEMO W3S Delivered', 'zz-demo-w3s-ok@example.invalid', 'zz-demo-w3s-ok@example.invalid', true, 'Dubai', '+971500000722', true, v_limit - 1) returning id into s_ok;
  insert into public.leads (company_name, email, claimed_by, claimed, emirate, phone, owner_email_verified, chat_strikes, whatsapp_opt, whatsapp_phone, whatsapp_verified_at)
  values ('ZZ DEMO W3S WhatsApp', 'zz-demo-w3s-wa@example.invalid', 'zz-demo-w3s-wa@example.invalid', true, 'Dubai', '+971500000723', true, v_limit - 1, 'other', '+971500000724', now())
  returning id into s_wa;
  insert into public.supplier_member (lead_id, email, name, role, status, invited_by, accepted_at, email_verified_at)
  values (s, v_mem, 'ZZ DEMO W3S Estimator', 'estimator', 'active', v_owner, now() - interval '30 days', now() - interval '30 days');
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, channel, status, provider_status, created_at, sent_at)
  values ('supplier_strike_warning', v_owner, 'supplier', s, 'Please answer your QuotesDone job requests', 'ZZ DEMO You did not answer 2 job requests.', 'email', 'sent', 'undelivered', now() - interval '5 hours', now() - interval '5 hours'),
         ('supplier_strike_warning', 'zz-demo-w3s-ok@example.invalid', 'supplier', s_ok, 'Please answer your QuotesDone job requests', 'ZZ DEMO', 'email', 'sent', 'delivered', now() - interval '5 hours', now() - interval '5 hours'),
         ('supplier_strike_warning', 'zz-demo-w3s-wa@example.invalid', 'supplier', s_wa, 'Please answer your QuotesDone job requests', 'ZZ DEMO wa', 'email', 'sent', 'undelivered', now() - interval '5 hours', now() - interval '5 hours');
  delete from public.notifications where lead_id = s_wa and channel = 'whatsapp';   -- no WhatsApp copy was made for him

  -- 1. another address, one per run: the listed e-mail first, then the member
  j := public.fn_supplier_strike_warning_redeliver();
  if not exists (select 1 from public.notifications where type = 'supplier_strike_warning' and lead_id = s and lower(to_email) = v_list and body ~ 'You did not answer 2') then
    fails := fails || ' 1:listed(' || coalesce(j::text, '') || ')'; end if;
  if exists (select 1 from public.notifications where type = 'supplier_strike_warning' and lead_id = s and lower(to_email) = v_mem) then fails := fails || ' 1:two_at_once'; end if;
  perform public.fn_supplier_strike_warning_redeliver();
  select count(*) into n from public.notifications where type = 'supplier_strike_warning' and lead_id = s and lower(to_email) = v_list;
  if n <> 1 then fails := fails || ' 1:listed_twice(' || n || ')'; end if;
  update public.notifications set provider_status = 'undelivered', status = 'sent' where lead_id = s and lower(to_email) = v_list and type = 'supplier_strike_warning';
  perform public.fn_supplier_strike_warning_redeliver();
  if not exists (select 1 from public.notifications where type = 'supplier_strike_warning' and lead_id = s and lower(to_email) = v_mem) then fails := fails || ' 1:member'; end if;

  -- 3. every address bounced and no number: one task for the sales engineer
  update public.notifications set provider_status = 'undelivered', status = 'sent' where lead_id = s and lower(to_email) = v_mem and type = 'supplier_strike_warning';
  perform public.fn_supplier_strike_warning_redeliver();
  perform public.fn_supplier_strike_warning_redeliver();
  select count(*) into n from public.agent_actions where kind = 'supplier_strike_warning_undelivered' and target_id = 'supplier_strike_warning_undelivered:' || s and status = 'pending';
  if n <> 1 then fails := fails || ' 3:task(' || n || ')'; end if;

  -- 2. his confirmed number gets the copy
  if not exists (select 1 from public.notifications where type = 'supplier_strike_warning' and lead_id = s_wa and channel = 'whatsapp') then fails := fails || ' 2:whatsapp'; end if;

  -- 4. nothing for a delivered warning, a supplier not at the warning, or after a clear
  if exists (select 1 from public.notifications where type = 'supplier_strike_warning' and lead_id = s_ok and created_at > now() - interval '1 minute') then fails := fails || ' 4:delivered_resent'; end if;
  update public.leads set chat_strikes = 0 where id = s_wa;
  delete from public.notifications where lead_id = s_wa and channel = 'whatsapp';
  perform public.fn_supplier_strike_warning_redeliver();
  if exists (select 1 from public.notifications where type = 'supplier_strike_warning' and lead_id = s_wa and channel = 'whatsapp') then fails := fails || ' 4:not_at_warning'; end if;

  -- 5. the stop still waits for a warning that reached him (production fn_sales_engineer_counts_unanswered_request reads the same rows)
  if exists (select 1 from public.notifications w where w.type = 'supplier_strike_warning' and w.lead_id = s
              and (w.provider_status in ('delivered', 'read') or (w.status = 'sent' and coalesce(w.sent_at, w.created_at) <= now() - interval '3 days'
                   and coalesce(w.provider_status, '') not in ('undelivered', 'failed')))) then fails := fails || ' 5:counted_as_reached'; end if;

  if coalesce(fails, 'a check wrote null') <> '' then raise exception 'CHK<<PROBE FAILED:%>>', fails; end if;
  raise exception 'CHK<<PROBE OK: a bounced warning goes again to the listed address, then a member, one per run; a confirmed number gets a WhatsApp copy; with nothing left one task for the sales engineer; nothing for a delivered warning or a cleared count; the stop still waits>>';
end $probe$;
