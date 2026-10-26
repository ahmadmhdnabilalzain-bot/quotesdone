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
// So the count became an exact roster — the active seats must be exactly the named ones,
// no seat may exist outside them under any status, and every reporting edge must terminate at
// the ceo with no duplicate. An unauthorised seat fails LOUDER than a count would, because it
// fails whether it is active, retired, or merely edged into the tree.
//
// 9 SEPTEMBER 2026, LATER THE SAME DAY — A FOURTH SEAT IS AUTHORISED, AND ONLY THE FOURTH.
//
// The founder added an accountant by name: "any financial thing on the platform including refunds.
// reports to CEO." Production now reads: org_agents 4, org_role 4 (accountant, ceo,
// customer_support, sales_engineer), org_reporting_edge 3 (all three terminating at ceo),
// org_departments 0. Measured before this edit, not assumed — the three assertions below failed
// with exactly those values on the run immediately preceding it.
//
// THE ROSTER IS WIDENED BY ONE NAME, NOT LOOSENED INTO A COUNT. Every property the 3-seat version
// held is held here. A FIFTH seat still fails, and each of the three ways it could appear is
// caught by a named assertion:
//   * inserted active                     → the_roster_is_exactly_the_four_authorised_seats
//                                           (v_names is a sorted string; a fifth name changes it)
//                                           AND no_seat_exists_outside_the_authorised_roster
//   * inserted 'retired' and never edged  → no_seat_exists_outside_the_authorised_roster ALONE.
//                                           v_names reads status='active' only and the edge test
//                                           sees nothing, so this off-roster count is the only
//                                           instrument that can see a seat parked out of sight.
//   * edged to the ceo                    → every_edge_reports_to_the_ceo (the child is not in the
//                                           authorised child list, so the edge is a bad edge even
//                                           though its parent IS the ceo)
// Measured 9 Sep 2026 inside an aborted transaction against production: a fifth seat 'zz_demo_seat'
// inserted retired and never edged left v_names and v_bad_edges unchanged and moved v_off_roster
// from 0 to 1. The retired case is the one a roster-of-active-names alone would miss, which is why
// the off-roster count exists.
//
// SEPARATE DEFECT, FIXED HERE: no_departments_remain never measured departments. It counted
// roles outside two hard-coded names, gated on a table called 'org_department' — and the real
// table is 'org_departments', plural, so information_schema matched nothing and the whole
// expression was 0 whatever the database held. An instrument on the wrong subject AND the wrong
// table name: a scenario that could only ever return 0, which is why it always "passed". It now
// counts public.org_departments rows for real, and would fail if a department came back.
// 9 SEPTEMBER 2026, LATER AGAIN — A FIFTH SEAT IS AUTHORISED, AND IT IS THE FIRST ONE THAT DOES NOT
// REPORT TO THE CEO.
//
// The founder: "fine then we build the it engineer to monitor everything. once their is an issue, he
// will email me directly so i can open a session with you to fix it... he reports to me directly
// only. however he monitor literally everything in the app and the website"
//
// Production now reads: org_agents 5, org_role 5 (accountant, ceo, customer_support, it_engineer,
// sales_engineer), org_reporting_edge STILL 3 — all three terminating at ceo — and org_departments 0.
// Measured before this edit, not assumed: the roster assertion failed with exactly those five names
// and the off-roster count read 1 on the run immediately preceding it, while every_edge_reports_to_
// the_ceo was UNCHANGED at 0, because the new seat holds no edge.
//
// THE ROSTER IS WIDENED BY ONE NAME. IT IS NOT LOOSENED INTO A COUNT, AND THE EDGE TEST IS NOT
// RELAXED TO LET A SEAT OFF. Every property the 4-seat version held is held here, and a SIXTH seat
// still fails through all three of the same instruments:
//   * inserted active                     → the_roster_is_exactly_the_six_authorised_seats
//                                           (v_names is a sorted string; a sixth name changes it)
//                                           AND no_seat_exists_outside_the_authorised_roster
//   * inserted 'retired' and never edged  → no_seat_exists_outside_the_authorised_roster ALONE
//   * edged to the ceo                    → every_edge_reports_to_the_ceo
// Measured 9 Sep 2026 inside an aborted transaction against production, with the positive control
// taken in the same block: a sixth seat 'zz_demo_seat' moved v_names, v_off_roster and (when edged)
// v_bad_edges away from their passing values, while the control read them unchanged first.
//
// WHY THE EDGE TEST STILL PASSES, AND WHY THAT IS NOT AN ACCIDENT. every_edge_reports_to_the_ceo
// counts edges whose parent is not the ceo or whose child is not on the authorised child list. The
// IT engineer has NO edge at all, so it contributes nothing to that count — the check would have
// gone on passing whether or not anybody had thought about it. An exception nobody asserts is
// indistinguishable from an omission, so the founder-reporting exception is made EXPLICIT and NAMED
// in its own scenario, the_it_engineer_reports_to_the_founder_and_has_no_edge, which fails if the
// seat is ever quietly edged under the CEO — and equally if it stops naming the founder, because a
// seat with no edge and no named escalation reports to nobody at all.
//
// 22 SEP 2026 — THE SIXTH SEAT, marketing (founder instruction 721: it "reports to the CEO for the overall
// picture"). The roster string and the off-roster list gain one name, and marketing joins the authorised-
// child list because it holds an edge to the ceo by the founder's ruling. A SEVENTH seat still fails the
// same three instruments.
//
// The authorised-child list in v_bad_edges is DELIBERATELY not widened to include it_engineer: that
// list is what may hold an edge, and this seat may not.
export const G9 = {
  title: '9. An authenticated six-seat roster, every edge to the CEO except the founder-reporting seat, and no departments',
  scenarios: [
    S('the_roster_is_exactly_the_six_authorised_seats', 'accountant,ceo,customer_support,it_engineer,marketing,sales_engineer', true),
    S('no_seat_exists_outside_the_authorised_roster', '0', true),
    S('support_reports_directly_to_the_ceo', '1', true),
    S('every_edge_reports_to_the_ceo', '0', true),
    S('the_it_engineer_reports_to_the_founder_and_has_no_edge', 'true', true),
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
  v_it_edges int; v_it_esc text[]; v_it_founder boolean;
begin
  -- THE AUTHENTICATED ROSTER. The active seats must be exactly these five names in this order;
  -- a sixth seat, a renamed seat or a missing seat all change this string.
  select string_agg(role_id, ',' order by role_id) into v_names
    from public.org_role where status = 'active';

  -- And no seat may exist OUTSIDE the roster under any status -- a role parked as 'retired' or
  -- 'inactive' is still an organisation growing back, just quietly. This is the ONLY assertion
  -- that sees a sixth seat inserted retired and never edged.
  select count(*) into v_off_roster from public.org_role
   where role_id not in ('accountant','ceo','customer_support','it_engineer','marketing','sales_engineer');

  -- THE FOUNDER-REPORTING EXCEPTION, ASSERTED RATHER THAN ASSUMED. The founder, 9 Sep 2026: the IT
  -- engineer "reports to me directly only". org_reporting_edge.parent_role_id is a foreign key to
  -- org_role and the founder is a human, not a role, so the exception is expressed as NO EDGE AT ALL
  -- plus escalation_targets naming him. Both halves are required here:
  --   * an edge appearing later is a silent reorganisation that every_edge_reports_to_the_ceo would
  --     NOT catch on its own -- it would see a well-formed edge to the ceo and pass.
  --   * an escalation_targets that stops naming the founder leaves a seat with no edge and no route,
  --     which is not "reports to the founder", it is "reports to nobody".
  select count(*) into v_it_edges from public.org_reporting_edge where child_role_id = 'it_engineer';
  select escalation_targets into v_it_esc from public.org_role where role_id = 'it_engineer';
  v_it_founder := (v_it_edges = 0) and ('founder' = any(coalesce(v_it_esc, array[]::text[])));

  select count(*) into v_direct from public.org_reporting_edge
   where child_role_id = 'customer_support' and parent_role_id = 'ceo';

  -- EVERY EDGE TERMINATES AT THE CEO, and no child is edged twice. The second term catches a
  -- duplicate edge, which an "all parents are ceo" test alone would happily accept.
  select (select count(*) from public.org_reporting_edge
           where parent_role_id <> 'ceo'
              or child_role_id not in ('accountant','customer_support','marketing','sales_engineer'))
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

  raise exception 'CHK<<the_roster_is_exactly_the_six_authorised_seats=%||no_seat_exists_outside_the_authorised_roster=%||support_reports_directly_to_the_ceo=%||every_edge_reports_to_the_ceo=%||the_it_engineer_reports_to_the_founder_and_has_no_edge=%||no_departments_remain=%||a_report_to_a_retired_role_is_refused=%||every_report_is_visible_in_the_ceo_queue=%||a_report_is_not_closed_by_being_received=%||accepting_a_report_needs_a_receipt=%||the_public_contact_exists_to_be_given=%||the_sending_number_is_not_the_founders=%||sharing_the_contact_pages_nobody=%>>',
    v_names, v_off_roster, v_direct, v_bad_edges, v_it_founder, v_depts,
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
