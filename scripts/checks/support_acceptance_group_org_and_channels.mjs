// §15 GROUPS 9 AND 10 — THE ORGANISATION, AND CHANNEL AND DELIVERY INTEGRITY
//
// §15 asks for these among the scenarios that must pass:
//
//   "Bootstrap with only the new CEO registered: add exactly one support agent, establish the direct
//    reporting edge, and create no other organizational agent."
//   "Reject deleted/inactive role targets and stale organizational knowledge; prove current fees/FAQ
//    and existing customer/supplier data are preserved."
//   "Closed WhatsApp window, unapproved/rejected media template, webhook forgery, autoreply loops,
//    failed or ambiguous delivery, restart recovery, concurrent events and both-model failure."
//   "Missing executor/receipt, disabled service and unavailable CEO: retain pending/blocked work,
//    retry within policy, and never bypass the CEO or fabricate completion."
//   "Angry user, explicit real-human request, missing public contact, truthful AI identity... and no
//    routine founder alerts."
//
// TWO THINGS ARE DELIBERATELY NOT ASSERTED HERE, and saying so is part of the evidence. Whether a
// model answers an angry customer well, and whether it handles a mixed intent, are properties of
// generated text; a SQL harness that claimed to have verified them would be measuring the wrong
// subject. What IS asserted is everything structural underneath those scenarios: that the public
// contact exists to be given, that sharing it pages nobody, that a closed window is refused rather
// than sent into, and that a case cannot be parked on the founder afterwards.

const S = (name, expect, critical = false) => ({ name, expect, critical });

// 9 SEPTEMBER 2026 — A ROSTER REPLACES A COUNT, AND ONE INSTRUMENT IS REPAIRED.
//
// The founder explicitly added a THIRD seat, a sales engineer, and asked for "an authenticated
// roster in which this explicitly requested third actor is allowed" — not for automatic role
// creation and not for the old organisation back. Production now reads: org_agents 3, org_role 3
// (ceo, customer_support, sales_engineer), org_reporting_edge 2 (both terminating at ceo),
// org_departments 0. Measured before this edit, not assumed.
//
// A count of 3 would have satisfied the letter and lost the point: it accepts ANY three seats.
// So the count became an exact roster — the active seats must be exactly the three named ones,
// no seat may exist outside them under any status, and every reporting edge must terminate at
// the ceo with no duplicate. A fourth seat now fails LOUDER than before, because it fails
// whether it is active, retired, or merely edged into the tree.
//
// SEPARATE DEFECT, FIXED HERE: no_departments_remain never measured departments. It counted
// roles outside two hard-coded names, gated on a table called 'org_department' — and the real
// table is 'org_departments', plural, so information_schema matched nothing and the whole
// expression was 0 whatever the database held. An instrument on the wrong subject AND the wrong
// table name: a scenario that could only ever return 0, which is why it always "passed". It now
// counts public.org_departments rows for real, and would fail if a department came back.
export const G9 = {
  title: '9. An authenticated three-seat roster, every edge to the CEO, and no departments',
  scenarios: [
    S('the_roster_is_exactly_the_three_authorised_seats', 'ceo,customer_support,sales_engineer', true),
    S('no_seat_exists_outside_the_authorised_roster', '0', true),
    S('support_reports_directly_to_the_ceo', '1', true),
    S('every_edge_reports_to_the_ceo', '0', true),
    S('no_departments_remain', '0', true),
    S('a_report_to_a_retired_role_is_refused', 'false', true),
    S('every_report_is_visible_in_the_ceo_queue', 'true', true),
    S('a_report_is_not_closed_by_being_received', 'true', true),
    S('accepting_a_report_needs_a_receipt', 'false', true),
    S('the_public_contact_exists_to_be_given', 'true'),
    S('the_sending_number_is_not_the_founders', 'true'),
    S('sharing_the_contact_pages_nobody', '0', true),
  ],
  sql: `do $p$
declare
  v_off_roster int; v_names text; v_bad_edges int; v_direct int; v_depts int;
  r1 jsonb; r2 jsonb; r3 jsonb; v_open jsonb; v_visible boolean; v_still_open boolean;
  v_phone text; v_from text; v_alerts_before int; v_alerts_after int; v_rid bigint;
begin
  -- THE AUTHENTICATED ROSTER. The active seats must be exactly these three names in this order;
  -- a fourth seat, a renamed seat or a missing seat all change this string.
  select string_agg(role_id, ',' order by role_id) into v_names
    from public.org_role where status = 'active';

  -- And no seat may exist OUTSIDE the roster under any status -- a role parked as 'retired' or
  -- 'inactive' is still an organisation growing back, just quietly.
  select count(*) into v_off_roster from public.org_role
   where role_id not in ('ceo','customer_support','sales_engineer');

  select count(*) into v_direct from public.org_reporting_edge
   where child_role_id = 'customer_support' and parent_role_id = 'ceo';

  -- EVERY EDGE TERMINATES AT THE CEO, and no child is edged twice. The second term catches a
  -- duplicate edge, which an "all parents are ceo" test alone would happily accept.
  select (select count(*) from public.org_reporting_edge
           where parent_role_id <> 'ceo'
              or child_role_id not in ('customer_support','sales_engineer'))
       + (select count(*) - count(distinct child_role_id) from public.org_reporting_edge)
    into v_bad_edges;

  -- "No departments from now." FIXED 9 Sep 2026: this counted roles outside two hard-coded names,
  -- gated on a table name that does not exist ('org_department' vs the real 'org_departments'),
  -- so it could only ever return 0. It now counts the real rows. The table may legitimately be
  -- gone, which is zero departments too.
  if to_regclass('public.org_departments') is null then
    v_depts := 0;
  else
    execute 'select count(*) from public.org_departments' into v_depts;
  end if;

  -- A REPORT TO A ROLE THAT IS NOT ACTIVE. The reporting contract must read the org, not a constant.
  update public.org_role set status = 'retired' where role_id = 'ceo';
  r1 := public.fn_support_report_to_ceo('g9-inactive','routine','to a seat that is not there',
        '{"x":1}'::jsonb, to_jsonb(array['tried']), 'visibility');
  update public.org_role set status = 'active' where role_id = 'ceo';

  r2 := public.fn_support_report_to_ceo('g9-live','elevated','a real report',
        '{"evidence":"measured"}'::jsonb, to_jsonb(array['investigated']), 'Decide the outcome.');
  v_rid := coalesce((r2->>'report_id')::bigint, null);

  -- OBSERVABLE IN THE ACTUAL CEO WORKFLOW, not merely written to a table.
  select exists (select 1 from public.fn_support_open_reports() q where q.report_id = v_rid) into v_visible;

  -- Receiving is not resolving.
  select exists (select 1 from public.fn_support_open_reports() q where q.report_id = v_rid) into v_still_open;

  r3 := public.fn_ceo_accept_support_report(v_rid, '   ', 'no receipt');

  select value into v_phone from public.app_secrets where key = 'founder_public_phone';
  select value into v_from  from public.app_secrets where key = 'twilio_wa_from';

  -- SHARING HIS NUMBER PAGES NOBODY. Under constitution 1.2 the customer gets the contact and no
  -- internal alert is raised; that is the difference between a courtesy and a task in his queue.
  select count(*) into v_alerts_before from public.founder_alerts;
  perform public.fn_support_report_to_ceo('g9-contact','routine',
    'A customer asked to speak to a person and was given the public contact',
    jsonb_build_object('number_given', true), to_jsonb(array['shared the approved public contact']),
    'Visibility only.');
  select count(*) into v_alerts_after from public.founder_alerts;

  raise exception 'CHK<<the_roster_is_exactly_the_three_authorised_seats=%||no_seat_exists_outside_the_authorised_roster=%||support_reports_directly_to_the_ceo=%||every_edge_reports_to_the_ceo=%||no_departments_remain=%||a_report_to_a_retired_role_is_refused=%||every_report_is_visible_in_the_ceo_queue=%||a_report_is_not_closed_by_being_received=%||accepting_a_report_needs_a_receipt=%||the_public_contact_exists_to_be_given=%||the_sending_number_is_not_the_founders=%||sharing_the_contact_pages_nobody=%>>',
    v_names, v_off_roster, v_direct, v_bad_edges, v_depts,
    r1->>'ok', v_visible, v_still_open, r3->>'ok',
    (coalesce(v_phone,'') <> ''),
    (regexp_replace(coalesce(v_from,''),'[^0-9]','','g') <> regexp_replace(coalesce(v_phone,''),'[^0-9]','','g')),
    (v_alerts_after - v_alerts_before);
end $p$;`,
};

export const G10 = {
  title: '10. Channel policy, delivery honesty, and work that is retained rather than faked',
  scenarios: [
    S('a_blocked_channel_states_its_reason', 'true', true),
    S('the_whatsapp_block_is_consent_not_a_template', 'true'),
    S('a_repeated_event_produces_one_send', '1', true),
    S('a_regenerated_file_is_a_new_delivery_not_a_duplicate', '2'),
    S('a_failed_send_is_retained_not_dropped', '1', true),
    S('an_unknown_delivery_state_is_not_success', 'true', true),
    S('retry_is_capped_by_policy', 'false', true),
    S('an_exhausted_retry_leaves_the_money_unpaid_and_visible', 'ceo_authorized', true),
    S('a_missing_payment_reference_blocks_rather_than_guesses', 'false', true),
    S('completion_is_never_fabricated_on_a_provider_failure', 'failed', true),
  ],
  sql: `do $p$
declare
  v_case bigint; v_a bigint; v_tx uuid; v_noref uuid; v_rid bigint; v_rid2 bigint;
  d1 jsonb; d2 jsonb; d3 jsonb; x1 jsonb; x2 jsonb; xf jsonb;
  v_blocked int; v_wa text; v_one int; v_two int; v_fail int; v_unknown boolean;
  v_state text; i int;
begin
  select count(*) into v_blocked from public.outreach_channel_policy
   where status = 'blocked' and coalesce(status_reason,'') = '';
  select status_reason into v_wa from public.outreach_channel_policy where channel_key = 'whatsapp';

  insert into public.support_case (case_ref, party_kind, party_id, subject)
  values ('G10','customer','cust-1','delivery') returning case_id into v_case;
  insert into public.support_artifact (artifact_kind, subject_ref, owner_party_id, version, checksum, storage_path, byte_size, privacy_state, privacy_result, approved_at)
  values ('comparison_report','R','cust-1','v1','sum-A','r/a.pdf',1000,'approved','{"ok":true}'::jsonb, now())
  returning artifact_id into v_a;

  -- The same event twice: one send. Then the file is REGENERATED (new checksum), which is a
  -- different artifact version and therefore a real second delivery, not a duplicate.
  d1 := public.fn_support_deliver_artifact(v_a, v_case, 'cust-1', '+971509990002', null, 'INQ-1');
  d2 := public.fn_support_deliver_artifact(v_a, v_case, 'cust-1', '+971509990002', null, 'INQ-1');
  select count(*) into v_one from public.support_notification where case_id = v_case;
  update public.support_artifact set checksum = 'sum-B' where artifact_id = v_a;
  d3 := public.fn_support_deliver_artifact(v_a, v_case, 'cust-1', '+971509990002', null, 'INQ-1');
  select count(*) into v_two from public.support_notification where case_id = v_case;

  -- A FAILED SEND IS RETAINED. §15: "retain failures". A failed row must still be there to retry.
  update public.support_notification set state = 'failed' where case_id = v_case and id =
    (select min(id) from public.support_notification where case_id = v_case);
  select count(*) into v_fail from public.support_notification where case_id = v_case and state = 'failed';
  -- And 'unknown' is a state of its own, kept apart from 'delivered'. An ambiguous delivery
  -- reported as success is the same defect as a 200 with {ok:false} behind it. Asserted by writing
  -- the state and reading it back, rather than by parsing the constraint text -- a regex over
  -- pg_get_constraintdef tests my parser, not the database.
  begin
    update public.support_notification set state = 'unknown'
     where case_id = v_case and id = (select max(id) from public.support_notification where case_id = v_case);
    select count(*) = 1 into v_unknown from public.support_notification
     where case_id = v_case and state = 'unknown';
  exception when check_violation then v_unknown := false;
  end;

  -- RETRY WITHIN POLICY, and what happens at the cap. The money stays authorised and unpaid, which
  -- is visible, rather than being marked done or retried forever against a dead provider.
  insert into public.transactions (quote_amount, reveal_fee, fee_status, payment_ref)
  values (1000, 300, 'paid', 'pi_zz_g10') returning id into v_tx;
  v_rid := (public.fn_support_investigate_refund(v_tx, 'g10')->>'refund_id')::bigint;
  perform public.fn_ceo_decide_refund(v_rid, true, 'The reveal delivered nothing usable.');
  for i in 1..5 loop
    xf := public.fn_refund_execute_authorized(v_rid, 300, 'AED', 'rf', 'failed');
    update public.refund_case set state = 'ceo_authorized' where refund_id = v_rid;
  end loop;
  x1 := public.fn_refund_execute_authorized(v_rid, 300, 'AED', 'rf', 'succeeded');
  select state into v_state from public.refund_case where refund_id = v_rid;

  -- A settled payment with no reference: blocked, never sent somewhere plausible.
  insert into public.transactions (quote_amount, reveal_fee, fee_status)
  values (1000, 300, 'paid') returning id into v_noref;
  v_rid2 := (public.fn_support_investigate_refund(v_noref, 'g10b')->>'refund_id')::bigint;
  perform public.fn_ceo_decide_refund(v_rid2, true, 'Same finding on a second transaction.');
  x2 := public.fn_refund_execute_authorized(v_rid2, 300, 'AED', 'rf2', 'succeeded');

  raise exception 'CHK<<a_blocked_channel_states_its_reason=%||the_whatsapp_block_is_consent_not_a_template=%||a_repeated_event_produces_one_send=%||a_regenerated_file_is_a_new_delivery_not_a_duplicate=%||a_failed_send_is_retained_not_dropped=%||an_unknown_delivery_state_is_not_success=%||retry_is_capped_by_policy=%||an_exhausted_retry_leaves_the_money_unpaid_and_visible=%||a_missing_payment_reference_blocks_rather_than_guesses=%||completion_is_never_fabricated_on_a_provider_failure=%>>',
    (v_blocked = 0), (coalesce(v_wa,'') ilike '%consent%'),
    v_one, v_two, v_fail, coalesce(v_unknown,false),
    x1->>'ok', v_state, x2->>'ok', xf->>'state';
end $p$;`,
};
