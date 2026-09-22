-- PROBE: WHATSAPP ANSWERS EVERY HELLO — the database half of the menu, and the refused-hello watch.
--
-- Assigned: customer_support. 22 Sep 2026. Pure probe: no DDL, nothing survives it. Run AFTER
-- whatsapp_answers_every_hello_with_a_welcome_and_a_menu.sql, as ONE query through the Management API;
-- never applied.
--
-- WHAT IT RUNS, inside a block that always raises so every write is rolled back, on the reserved ZZ DEMO
-- fixture number +971500000031 (no account owns it, and nothing here sends anything):
-- VERDICT: PROBE OK only if
--   1. fn_wa_menu_context names the fixture 'unknown' and lists no requests (a phone never selects);
--   2. fn_wa_problem_report opens a support_case QD-S-XXXXXX, party 'unknown', identity NOT verified,
--      owner customer_support, and the text is on it;
--   3. a wa_messages row refused at the door (signature_valid=false) opens it_engineer_finding
--      'wa_inbound:signature_refused' as customer_facing with affected >= 1;
--   4. the next row that passed verification (provenance_verified=true) closes it;
--   5. founder_mail_policy carries 'whatsapp_human_request' allowed to email, owner customer_support.
create temp table zz_probe_verdict (verdict text, detail text) on commit drop;
do $probe$
declare
  ctx jsonb; rep jsonb; c record; f_open record; f_closed record; pol record; v_err text;
begin
  begin
    ctx := public.fn_wa_menu_context('whatsapp:+971500000031');
    rep := public.fn_wa_problem_report('whatsapp:+971500000031', 'ZZ DEMO probe: the quote page did not load', 'en');
    select * into c from public.support_case where case_ref = rep ->> 'case_ref';
    insert into public.wa_messages (wa_from, wa_to, profile_name, inbound, reply, lang, sent, meta)
    values ('whatsapp:+971500000031', 'whatsapp:+10000000000', 'ZZ DEMO', 'Hi', '', 'en', false,
            jsonb_build_object('signature_checked', true, 'signature_valid', false, 'signature_reason', 'ZZ DEMO probe',
                               'no_autoreply_reason', 'failed X-Twilio-Signature'));
    select * into f_open from public.it_engineer_finding where issue_key = 'wa_inbound:signature_refused';
    insert into public.wa_messages (wa_from, wa_to, profile_name, inbound, reply, lang, sent, meta)
    values ('whatsapp:+971500000031', 'whatsapp:+10000000000', 'ZZ DEMO', 'Hi', 'ZZ DEMO', 'en', false,
            jsonb_build_object('route', 'menu_welcome', 'provenance_verified', true));
    select * into f_closed from public.it_engineer_finding where issue_key = 'wa_inbound:signature_refused';
    select * into pol from public.founder_mail_policy where kind = 'whatsapp_human_request';
    raise exception 'ZZPROBE rollback';
  exception when others then
    v_err := sqlerrm;
  end;
  insert into zz_probe_verdict
  select case when v_err = 'ZZPROBE rollback'
                   and ctx ->> 'audience' = 'unknown' and jsonb_array_length(ctx -> 'requests') = 0
                   and rep ->> 'case_ref' ~ '^QD-S-[2-9A-HJ-NP-Z]{6}$' and c.party_kind = 'unknown'
                   and not c.identity_verified and c.owner_role_id = 'customer_support' and c.state = 'open'
                   and c.subject like '%the quote page did not load%'
                   and f_open.closed_at is null and f_open.blast = 'customer_facing' and f_open.affected >= 1
                   and f_closed.closed_at is not null
                   and pol.allowed_to_email and pol.owner_role = 'customer_support'
              then 'PROBE OK' else 'PROBE FAILED' end,
         format('context=%s; case=%s party=%s verified=%s owner=%s; finding open: closed_at=%s blast=%s affected=%s; '
                || 'after a verified row: closed_at=%s note=%s; policy allowed=%s owner=%s; block ended with: %s',
                ctx, rep ->> 'case_ref', c.party_kind, c.identity_verified, c.owner_role_id,
                f_open.closed_at, f_open.blast, f_open.affected, f_closed.closed_at, f_closed.close_note,
                pol.allowed_to_email, pol.owner_role, v_err);
end $probe$;
select * from zz_probe_verdict;
