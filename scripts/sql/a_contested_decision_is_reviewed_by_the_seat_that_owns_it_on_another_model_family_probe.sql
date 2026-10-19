-- PROBE (ledger 1152, seat ceo): one ZZ DEMO review request per decision type lands with the seat review_route
-- names, is decided by a model family other than the original decision's, a same-family verdict is refused by
-- the CHECK, and 0 rows reach the founder (founder_alerts, notifications to_role='founder'). Pure probe: it always
-- raises CHK<<json>>, so every row it writes rolls back. Run with the main file prepended while that file is
-- pending (scripts/checks/a_contested_decision_is_reviewed_by_the_seat_that_owns_it_on_another_model_family.test.mjs does).
-- Subjects are ZZ DEMO text with @example.invalid requesters, and no real customer, supplier or lead is named,
-- so fn_seat_handoff files no handoff. RULING 1264: afterwards an EXPLICIT person request on WhatsApp, site chat and
-- e-mail must each reach the founder through founder_mail_policy (founder_alerts + queued founder notifications, all
-- rolled back with the rest, so nothing is ever sent), a person request from the portal is refused, and a founder
-- delivery stamped on a decision row is refused by the CHECK.
do $probe$
declare
  t record; v_open jsonb; v_dec jsonb; v_out jsonb := '[]'::jsonb; i int := 0;
  v_orig text; v_same_refused int := 0; v_unknown jsonb; v_id bigint;
  v_founder_alerts int; v_founder_notes int; v_handoffs int; v_rows int;
  v_person jsonb := '{}'::jsonb; v_ch text; v_fa0 int; v_fn0 int; v_portal jsonb; v_portal_contest jsonb; v_stamp_refused int := 0;
begin
  for t in select decision_type, owner_seat from public.review_route where decision_type <> 'person' order by decision_type loop
    i := i + 1;
    -- the original automated decision: alternate families, and one made by code with no model at all
    v_orig := case i % 3 when 0 then 'openai/gpt-6-luna-pro' when 1 then 'anthropic/claude-sonnet-5.5' else null end;
    v_open := public.fn_review_request_open(t.decision_type, (array['whatsapp','email','site_chat'])[1 + i % 3],
                'zz.demo.review.' || t.decision_type || '@example.invalid',
                'ZZ DEMO please review the automated ' || t.decision_type || ' decision again',
                null, null, t.owner_seat, v_orig, null, 'zz_demo_probe_1152:' || t.decision_type);
    v_dec := public.fn_review_request_decide((v_open ->> 'id')::bigint, 'upheld',
                'ZZ DEMO probe verdict for ' || t.decision_type);
    v_out := v_out || jsonb_build_object('type', t.decision_type, 'route_seat', t.owner_seat,
               'landed_seat', v_open ->> 'owner_seat', 'handoff_id', v_open -> 'handoff_id',
               'original_family', v_dec ->> 'original_family', 'reviewer_model', v_dec ->> 'reviewer_model',
               'reviewer_family', v_dec ->> 'reviewer_family', 'decided', v_dec ->> 'ok');
  end loop;

  -- a same-family verdict must be refused by the table itself, whoever calls
  v_open := public.fn_review_request_open('quotes', 'email', 'zz.demo.same@example.invalid',
              'ZZ DEMO same family attempt', null, null, 'sales_engineer', 'openai/gpt-6-luna-pro', null, 'zz_demo_probe_1152:same');
  v_id := (v_open ->> 'id')::bigint;
  begin
    perform public.fn_review_request_decide(v_id, 'upheld', 'ZZ DEMO same family', 'openai/gpt-6-luna-pro');
  exception when check_violation then v_same_refused := 1;
  end;

  v_unknown := public.fn_review_request_open('not_a_type', 'email', 'zz.demo.x@example.invalid', 'ZZ DEMO unknown');

  select count(*) into v_founder_alerts from public.founder_alerts where created_at = now();
  select count(*) into v_founder_notes from public.notifications where created_at = now() and to_role = 'founder';
  select count(*) into v_handoffs from public.agent_actions where created_at = now() and target_id like 'review.requested:%';
  select count(*) into v_rows from public.decision_review_request where dedupe_key like 'zz_demo_probe_1152:%';

  -- RULING 1264: the one founder route. Each channel's explicit person request reaches him through founder_mail_policy.
  foreach v_ch in array array['whatsapp', 'site_chat', 'email'] loop
    select count(*) into v_fa0 from public.founder_alerts where created_at = now();
    select count(*) into v_fn0 from public.notifications where created_at = now() and to_role = 'founder';
    v_open := public.fn_review_request_open('person', v_ch,
                case when v_ch = 'whatsapp' then 'whatsapp:+971500000' || (100 + i)::text else 'zz.demo.person.' || v_ch || '@example.invalid' end,
                'ZZ DEMO I want to speak to a person, please', null, null, null, null, null, 'zz_demo_probe_1152:person:' || v_ch);
    v_person := v_person || jsonb_build_object(v_ch, jsonb_build_object(
      'status', (select status from public.decision_review_request where id = (v_open ->> 'id')::bigint),
      'kind', v_open -> 'founder_notified' ->> 'kind', 'emailed', v_open -> 'founder_notified' -> 'emailed',
      'founder_alerts', (select count(*) from public.founder_alerts where created_at = now()) - v_fa0,
      'founder_notifications', (select count(*) from public.notifications where created_at = now() and to_role = 'founder') - v_fn0));
  end loop;
  v_portal := public.fn_review_request_open('person', 'portal', 'zz.demo.person.portal@example.invalid', 'ZZ DEMO a person please');
  v_portal_contest := public.fn_review_request_open('refunds', 'portal', 'zz.demo.contest.portal@example.invalid', 'ZZ DEMO contest from the portal');
  -- a founder delivery stamped on a decision review is refused by the table
  begin
    update public.decision_review_request set founder_notified = '{}'::jsonb, status = 'with_founder'
     where dedupe_key = 'zz_demo_probe_1152:quotes';
  exception when check_violation then v_stamp_refused := 1;
  end;

  raise exception 'CHK<<%>>', jsonb_build_object(
    'requests', (select jsonb_agg((e->>'type') || ' -> ' || (e->>'landed_seat') || ' | ' || (e->>'original_family') || ' -> ' || coalesce(e->>'reviewer_family','none') || coalesce(' | handoff ' || (e->>'handoff_id'), '')) from jsonb_array_elements(v_out) e), 'types', i, 'rows', v_rows,
    'misrouted', (select count(*) from jsonb_array_elements(v_out) e where e ->> 'route_seat' is distinct from e ->> 'landed_seat'),
    'same_family_decisions', (select count(*) from jsonb_array_elements(v_out) e where e ->> 'reviewer_family' is not distinct from e ->> 'original_family'),
    'undecided', (select count(*) from jsonb_array_elements(v_out) e where e ->> 'decided' is distinct from 'true'),
    'same_family_refused', v_same_refused, 'unknown_type', v_unknown,
    'founder_alerts', v_founder_alerts, 'founder_notifications', v_founder_notes, 'demo_handoffs', v_handoffs,
    'person', v_person, 'person_from_portal', v_portal, 'contest_from_portal', v_portal_contest, 'founder_stamp_on_a_review_refused', v_stamp_refused)::text;
end $probe$;
