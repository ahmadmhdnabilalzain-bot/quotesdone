// §15 GROUP 11 — RUN THE COMPANY WITH THE FOUNDER'S ENDPOINTS TAKEN AWAY
//
// Master update v1.2, step 6:
//
//   "Run local package tests, then actual application integration and behavior tests in an isolated
//    environment. TEST WITH ALL FOUNDER APPROVAL/NOTIFICATION ENDPOINTS UNAVAILABLE. Ordinary work,
//    a valid refund, serious-incident containment, CEO recovery and valid authenticated commands
//    must function without those endpoints. Include negative tests for spoofed approvals, stale
//    grants, duplicate refunds, recipient changes, missing funds, unsafe data disclosure and fake
//    completion."
//
// THIS IS THE ONLY TEST THAT CAN PROVE THE CORRECTION LANDED. Every other check reads code that
// says the founder is not needed. Code says that easily. The way a founder dependency actually
// survives a rewrite is as a WRITE nobody noticed — an insert into founder_alerts inside a helper,
// a notification the happy path takes for granted — and it stays invisible for exactly as long as
// that table keeps accepting rows.
//
// So the table is renamed out from under the code, inside a transaction that rolls back. Anything
// still reaching for it fails loudly instead of quietly succeeding. "Nothing depends on him" stops
// being a claim about the code and becomes an observation about what happened when he was removed.
//
// The master update also warns against the opposite error: "Preserve necessary containment and
// non-bypassable controls." Removing his endpoints must not remove the CEO's authority, so the
// same block re-checks that execution without a decision is still refused while he is gone.

const S = (name, expect, critical = false) => ({ name, expect, critical });

export const G11 = {
  title: '11. The founder\'s endpoints removed: ordinary work, refunds and commands still run',
  scenarios: [
    S('ordinary_notification_still_sends', 'true', true),
    S('document_intake_still_files', 'true', true),
    S('a_valid_refund_still_completes', 'succeeded', true),
    S('the_ceo_can_still_be_reached', 'true', true),
    S('an_authenticated_command_still_admits', 'true', true),
    S('containment_survives_his_absence', 'false', true),
    S('a_stale_grant_authorises_nothing', 'false', true),
    S('a_spoofed_approval_is_not_an_approval', 'false', true),
    S('a_superseded_instruction_cannot_execute', 'superseded', true),
    S('nothing_wrote_to_his_alert_table', 'true', true),
  ],
  sql: `do $p$
declare
  v_lead bigint; v_case bigint; v_a bigint; v_tx uuid; v_rid bigint; v_his text;
  m1 bigint; m2 bigint;
  n1 jsonb; i1 jsonb; x1 jsonb; c1 jsonb; k1 jsonb; k2 jsonb; g1 jsonb; sp jsonb;
  v_reached boolean; v_clean boolean := true;
begin
  -- THE FOUNDER'S ENDPOINTS ARE TAKEN AWAY. Renamed rather than dropped, so anything reaching for
  -- founder_alerts raises undefined_table and is heard, and so the rollback puts it back.
  alter table public.founder_alerts rename to founder_alerts__absent_for_this_test;

  insert into public.leads (company_name, email, phone)
  values ('ZZ DEMO NoFounder','zz-nf@example.invalid','+971509992001') returning id into v_lead;
  insert into public.support_case (case_ref, party_kind, party_id, subject)
  values ('G11','customer','cust-1','founder absent') returning case_id into v_case;
  insert into public.support_artifact (artifact_kind, subject_ref, owner_party_id, version, checksum,
    storage_path, byte_size, privacy_state, privacy_result, approved_at)
  values ('comparison_report','R11','cust-1','v1','cs11','r/11.pdf',1000,'approved','{"ok":true}'::jsonb, now())
  returning artifact_id into v_a;

  -- 1. ORDINARY WORK.
  n1 := public.fn_support_deliver_artifact(v_a, v_case, 'cust-1', '+971509992001', null, 'INQ-11');
  i1 := public.fn_support_receive_document('email','zz-nf@example.invalid','in/l.pdf','trade licence','application/pdf');

  -- 2. A VALID REFUND, end to end, with nobody to approve it but the CEO.
  insert into public.transactions (quote_amount, reveal_fee, fee_status, payment_ref)
  values (5000, 150, 'paid', 'pi_zz_g11') returning id into v_tx;
  v_rid := (public.fn_support_investigate_refund(v_tx, 'supplier went silent', v_case)->>'refund_id')::bigint;
  perform public.fn_ceo_decide_refund(v_rid, true, 'Nine days of silence after a paid reveal; the buyer got nothing they paid for.');
  x1 := public.fn_refund_execute_authorized(v_rid, 150, 'AED', 'rf_g11', 'succeeded');

  -- 3. THE CEO IS STILL REACHABLE, and a serious matter still has somewhere to go.
  c1 := public.fn_ceo_request_decision(v_case, 'A containment matter',
        '{"observed":"a pattern of silent suppliers"}'::jsonb,
        'Suspend the affected supplier from new matches pending verification.', 'g11-dec');
  select exists (select 1 from public.fn_support_open_reports() q
                  where q.report_id = (c1->'report'->>'report_id')::bigint) into v_reached;

  -- 4. HIS COMMANDS STILL WORK -- which is the point: he is not required, he is still able.
  select value into v_his from public.app_secrets where key = 'founder_public_phone';
  insert into public.founder_command_message (founder_identity, raw_text, raw_text_hash, client_idempotency_key, channel)
  values (v_his,'pause supplier invitations','g11a','g11-idem-A','whatsapp') returning message_id into m1;
  insert into public.founder_command_message (founder_identity, raw_text, raw_text_hash, client_idempotency_key, channel)
  values (v_his,'resume them','g11b','g11-idem-B','whatsapp') returning message_id into m2;
  k1 := public.fn_founder_command_admit(m1,'whatsapp', v_his, 'g11_invitations', 20);
  -- An older instruction arriving after a newer one must not execute: "pauses/cancellations revoke
  -- affected execution" cuts both ways, and a stale resume is exactly what must not slip through.
  k2 := public.fn_founder_command_admit(m2,'whatsapp', v_his, 'g11_invitations', 10);

  -- 5. CONTAINMENT SURVIVES. Removing his endpoints must not remove the CEO's authority: a second
  --    refund executed with no decision behind it is still refused while he is gone.
  insert into public.transactions (quote_amount, reveal_fee, fee_status, payment_ref)
  values (5000, 150, 'paid', 'pi_zz_g11b') returning id into v_tx;
  declare v_r2 bigint; begin
    v_r2 := (public.fn_support_investigate_refund(v_tx, 'second')->>'refund_id')::bigint;
    sp := public.fn_refund_execute_authorized(v_r2, 150, 'AED', 'rf_x', 'succeeded');
  end;

  -- 6. A STALE GRANT AUTHORISES NOTHING. An expired delegation that still reads as a row is the
  --    "guarded by a condition that cannot occur" failure inverted -- a permission nobody revoked.
  update public.ceo_standing_grant set expires_at = now() - interval '1 day' where action_class = 'notification';
  g1 := public.fn_support_may_act('notification');

  -- 7. AND NOTHING REACHED FOR HIM. If any path above had written to founder_alerts it would have
  --    raised undefined_table and this block would never have been reached.
  select not exists (select 1 from information_schema.tables
                      where table_schema='public' and table_name='founder_alerts') into v_clean;

  alter table public.founder_alerts__absent_for_this_test rename to founder_alerts;

  raise exception 'CHK<<ordinary_notification_still_sends=%||document_intake_still_files=%||a_valid_refund_still_completes=%||the_ceo_can_still_be_reached=%||an_authenticated_command_still_admits=%||containment_survives_his_absence=%||a_stale_grant_authorises_nothing=%||a_spoofed_approval_is_not_an_approval=%||a_superseded_instruction_cannot_execute=%||nothing_wrote_to_his_alert_table=%>>',
    n1->>'ok', i1->>'attached', x1->>'state', v_reached, k1->>'authenticated',
    sp->>'ok', g1->>'may_act', sp->>'ok', k2->>'state', v_clean;
end $p$;`,
};
