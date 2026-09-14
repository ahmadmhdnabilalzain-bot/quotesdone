// NO SUPPLIER QUOTED THE EXACT SPEC: YES, NO AND SILENCE, ON DEMO DATA (founder_instruction #321).
//
// Proved against production inside ONE transaction that raises at the end, so it commits nothing:
// no customer, inquiry, quote, offer or notification survives, and the dispatchers never see a row.
// The customer is a ZZ DEMO fixture at an @example.invalid address with a reserved number, created
// inside the transaction; the supplier is an existing ZZ DEMO lead (a lead insert can consume a
// founding-rank number that a rollback does not return). The routines never send anything
// themselves (the sales_engineer sweep does, through customer_support), so no message can leave.
//
//   the candidate rule (every invited supplier quoted) · YES over WhatsApp with an Arabic-Indic digit:
//   the acceptance is recorded on the inquiry, which stays open · a second answer is refused · NO in
//   the portal: the inquiry closes 'no_exact_spec_declined' and the sibling offer is superseded ·
//   SILENCE: two reminders, the last one final, and the offer never lapses before its final reminder;
//   then 'no_exact_spec_no_reply' · a message that is not a reply is left to the normal route · the
//   table refuses an alternative carrying a supplier identity · no fee row anywhere.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

const PROBE = String.raw`
do $probe$
declare
  r jsonb := '{}'::jsonb; v_before jsonb; v_cust uuid; v_lead bigint; v_rfq int;
  v_a uuid; v_b uuid; v_c uuid; o jsonb; v_o1 bigint; v_o2 bigint; v_o3 bigint; v_o4 bigint; v_res jsonb;
  v_phone text := '+971500000094'; v_alts jsonb := '[{"option_id":"o1","value":"8 mm tempered","suppliers":2},{"option_id":"o2","value":"10 mm laminated","suppliers":1}]';
  v_refused boolean := false; v_due jsonb;
begin
  select l.id into v_lead from public.leads l where l.company_name ilike 'ZZ DEMO%' order by l.id limit 1;
  if v_lead is null then raise exception 'PROBE<<{"skipped":"no ZZ DEMO lead to stand in as the invited supplier"}>>'; end if;
  select jsonb_build_object('offers', (select count(*) from public.spec_alternative_offer), 'notifications', (select count(*) from public.notifications),
                            'transactions', (select count(*) from public.transactions)) into v_before;

  -- customers.is_demo is GENERATED from the ZZ DEMO name / @example.invalid address; asserted below.
  insert into public.customers (full_name, email, phone, phone_verified, email_verified, locale)
  values ('ZZ DEMO spec offer probe', 'zz-demo-specoffer-probe@example.invalid', v_phone, true, true, 'ar') returning id into v_cust;
  if not (select is_demo from public.customers where id = v_cust) then raise exception 'PROBE<<{"skipped":"the fixture customer is not recognised as demo; refusing to continue"}>>'; end if;
  select coalesce(max(rfq_no), 0) + 900000 into v_rfq from public.inquiries;
  insert into public.inquiries (customer_id, category, summary, status, rfq_no) values (v_cust, 'glass', 'ZZ DEMO spec offer probe A', 'sent', v_rfq) returning id into v_a;
  insert into public.inquiries (customer_id, category, summary, status, rfq_no) values (v_cust, 'glass', 'ZZ DEMO spec offer probe B', 'sent', v_rfq + 1) returning id into v_b;
  insert into public.inquiries (customer_id, category, summary, status, rfq_no) values (v_cust, 'glass', 'ZZ DEMO spec offer probe C', 'sent', v_rfq + 2) returning id into v_c;

  -- CANDIDATE RULE: A has one invited supplier, and that supplier quoted.
  insert into public.inquiry_matches (inquiry_id, supplier_id, sent_at) values (v_a, v_lead, now());
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status, source) values (v_a, v_lead, 1000, 'submitted', 'form');
  r := r || jsonb_build_object('candidate_why', (select why from public.fn_spec_offer_candidates(100) where inquiry_id = v_a));

  -- STRUCTURAL: an alternative with a supplier identity key is refused by the table itself.
  begin
    insert into public.spec_alternative_offer (inquiry_id, customer_id, line_no, attr, label_en, label_ar, requested, alternatives, reply_by)
    values (v_a, v_cust, 9, 'glass_type', 'Glass', 'الزجاج', 'x', '[{"option_id":"o1","value":"y","suppliers":1,"quote_id":"abc"}]', now() + interval '1 day');
  exception when check_violation then v_refused := true; end;
  r := r || jsonb_build_object('identity_refused', v_refused);

  -- YES, on WhatsApp, with an Arabic-Indic digit.
  select jsonb_agg(to_jsonb(x)) into o from public.fn_spec_offer_open(v_a, jsonb_build_array(jsonb_build_object('line_no', 1, 'item', 'Glass partition', 'attr', 'glass_type',
    'label_en', 'Glass type', 'label_ar', 'نوع الزجاج', 'requested', '10 mm tempered', 'alternatives', v_alts))) x;
  v_o1 := (o -> 0 ->> 'id')::bigint;
  perform public.fn_spec_offer_mark(v_o1, 'sent', '[]');
  r := r || jsonb_build_object('checked_marked', (select spec_offer_checked_at is not null from public.inquiries where id = v_a),
                               'not_a_reply', public.fn_spec_offer_whatsapp_reply(v_phone, 'hello, when is delivery?') -> 'handled');
  v_res := public.fn_spec_offer_whatsapp_reply(v_phone, '٢');
  r := r || jsonb_build_object('yes', v_res, 'yes_row', (select jsonb_build_object('state', state, 'accepted_option', accepted_option, 'accepted_value', accepted_value, 'channel', answer_channel) from public.spec_alternative_offer where id = v_o1),
    'yes_recorded', (select accepted_alternatives from public.inquiries where id = v_a),
    'yes_inquiry', (select jsonb_build_object('status', status, 'lost_reason', lost_reason) from public.inquiries where id = v_a),
    'answer_twice', public.fn_spec_offer_answer(v_o1, v_cust, 'o1', 'portal'),
    'someone_else', public.fn_spec_offer_answer(v_o1, gen_random_uuid(), 'o1', 'portal'));

  -- NO, in the portal. B has two offers; declining one closes the inquiry and supersedes the other.
  select jsonb_agg(to_jsonb(x)) into o from public.fn_spec_offer_open(v_b, jsonb_build_array(
    jsonb_build_object('line_no', 1, 'item', 'Glass partition', 'attr', 'glass_type', 'label_en', 'Glass type', 'label_ar', 'نوع الزجاج', 'requested', '10 mm tempered', 'alternatives', v_alts),
    jsonb_build_object('line_no', 2, 'item', 'Door', 'attr', 'finish', 'label_en', 'Finish', 'label_ar', 'التشطيب', 'requested', 'RAL 9016', 'alternatives', '[{"option_id":"o1","value":"RAL 9010","suppliers":1}]'::jsonb))) x;
  v_o2 := (o -> 0 ->> 'id')::bigint; v_o3 := (o -> 1 ->> 'id')::bigint;
  v_res := public.fn_spec_offer_answer(v_o2, v_cust, 'no', 'portal');
  r := r || jsonb_build_object('no', v_res,
    'no_inquiry', (select jsonb_build_object('status', status, 'lost_reason', lost_reason) from public.inquiries where id = v_b),
    'no_sibling', (select state from public.spec_alternative_offer where id = v_o3));

  -- SILENCE. Sent; then the clock moves. The offer must not lapse before the final reminder even if
  -- reply_by has passed; after the final reminder and past reply_by it lapses.
  select jsonb_agg(to_jsonb(x)) into o from public.fn_spec_offer_open(v_c, jsonb_build_array(jsonb_build_object('line_no', 1, 'item', 'Glass partition', 'attr', 'glass_type',
    'label_en', 'Glass type', 'label_ar', 'نوع الزجاج', 'requested', '10 mm tempered', 'alternatives', v_alts))) x;
  v_o4 := (o -> 0 ->> 'id')::bigint;
  perform public.fn_spec_offer_mark(v_o4, 'sent', '[]');
  r := r || jsonb_build_object('due_at_start', (select count(*) from public.fn_spec_offer_due() where offer_id = v_o4));
  update public.spec_alternative_offer set opened_at = now() - interval '25 hours', reply_by = now() - interval '1 minute' where id = v_o4;
  select to_jsonb(d) into v_due from public.fn_spec_offer_due() d where d.offer_id = v_o4;
  r := r || jsonb_build_object('due_1', v_due);
  perform public.fn_spec_offer_mark(v_o4, 'remind', '[]');
  update public.spec_alternative_offer set opened_at = now() - interval '49 hours' where id = v_o4;
  select to_jsonb(d) into v_due from public.fn_spec_offer_due() d where d.offer_id = v_o4;
  r := r || jsonb_build_object('due_2', v_due);
  perform public.fn_spec_offer_mark(v_o4, 'remind', '[]');
  select to_jsonb(d) into v_due from public.fn_spec_offer_due() d where d.offer_id = v_o4;
  r := r || jsonb_build_object('due_3', v_due);
  perform public.fn_spec_offer_mark(v_o4, 'close_no_reply', '[]');
  r := r || jsonb_build_object('silence_row', (select jsonb_build_object('state', state, 'closed_reason', closed_reason, 'reminders', reminders_sent) from public.spec_alternative_offer where id = v_o4),
    'silence_inquiry', (select jsonb_build_object('status', status, 'lost_reason', lost_reason) from public.inquiries where id = v_c),
    'due_after', (select count(*) from public.fn_spec_offer_due() where offer_id = v_o4));

  -- WHO MAY ANSWER (review of #652). An UNVERIFIED number with an open offer is not a reply; a
  -- number two verified customers with open offers share records nothing and opens a support_case.
  declare v_c2 uuid; v_c3 uuid; v_d uuid; v_e uuid; v_o5 bigint; v_o6 bigint; v_amb jsonb; v_unv jsonb;
  begin
    insert into public.customers (full_name, email, phone, phone_verified, email_verified, locale)
    values ('ZZ DEMO spec offer probe unverified', 'zz-demo-specoffer-probe-unv@example.invalid', '+971500000095', false, true, 'en') returning id into v_c3;
    insert into public.inquiries (customer_id, category, summary, status, rfq_no) values (v_c3, 'glass', 'ZZ DEMO spec offer probe D', 'sent', v_rfq + 3) returning id into v_d;
    select (to_jsonb(x) ->> 'id')::bigint into v_o5 from public.fn_spec_offer_open(v_d, jsonb_build_array(jsonb_build_object('line_no', 1, 'item', 'Glass', 'attr', 'glass_type',
      'label_en', 'Glass type', 'label_ar', 'نوع الزجاج', 'requested', '10 mm tempered', 'alternatives', v_alts))) x limit 1;
    v_unv := public.fn_spec_offer_whatsapp_reply('+971500000095', '1');
    -- A second VERIFIED customer on the first customer's number, with an open offer: ambiguous.
    insert into public.customers (full_name, email, phone, phone_verified, email_verified, locale)
    values ('ZZ DEMO spec offer probe twin', 'zz-demo-specoffer-probe-twin@example.invalid', v_phone, true, true, 'en') returning id into v_c2;
    insert into public.inquiries (customer_id, category, summary, status, rfq_no) values (v_c2, 'glass', 'ZZ DEMO spec offer probe E', 'sent', v_rfq + 4) returning id into v_e;
    select (to_jsonb(x) ->> 'id')::bigint into v_o6 from public.fn_spec_offer_open(v_e, jsonb_build_array(jsonb_build_object('line_no', 1, 'item', 'Glass', 'attr', 'glass_type',
      'label_en', 'Glass type', 'label_ar', 'نوع الزجاج', 'requested', '10 mm tempered', 'alternatives', v_alts))) x limit 1;
    -- v_cust still has v_o3? No: B was closed by the decline. Give v_cust a fresh open offer on A's line 2.
    perform public.fn_spec_offer_open(v_a, jsonb_build_array(jsonb_build_object('line_no', 2, 'item', 'Door', 'attr', 'finish', 'label_en', 'Finish', 'label_ar', 'التشطيب',
      'requested', 'RAL 9016', 'alternatives', '[{"option_id":"o1","value":"RAL 9010","suppliers":1}]'::jsonb)));
    v_amb := public.fn_spec_offer_whatsapp_reply(v_phone, '1');
    r := r || jsonb_build_object('unverified', v_unv, 'unverified_state', (select state from public.spec_alternative_offer where id = v_o5),
      'ambiguous', v_amb, 'ambiguous_states', (select jsonb_agg(state order by id) from public.spec_alternative_offer where customer_id in (v_cust, v_c2) and state = 'open'),
      'ambiguous_case', (select count(*) from public.support_case where case_ref = v_amb ->> 'case_ref' and owner_role_id = 'customer_support'));
  end;

  -- NO FEE: nothing was revealed on any of the three.
  r := r || jsonb_build_object('fee_rows', (select count(*) from public.transactions t join public.quotes q on q.id = t.quote_id where q.inquiry_id in (v_a, v_b, v_c)),
                               'before', v_before);
  raise exception 'PROBE<<%>>', r::text;
end $probe$;`;

test('production: yes, no and silence on demo data, and nothing survives', { skip: SKIP }, async (t) => {
  const { sql } = await import('../lib/db.mjs');
  let out = null;
  const parse = (s) => { try { return JSON.parse(s); } catch { return JSON.parse(s.replace(/\\\\/g, '\\').replace(/\\"/g, '"')); } };
  try { await sql(PROBE); } catch (e) { const m = String(e.message || e).match(/PROBE<<([\s\S]*)>>/); if (!m) throw e; out = parse(m[1]); }
  assert.ok(out, 'the probe did not report');
  if (out.skipped) { t.skip(out.skipped); return; }

  assert.equal(out.candidate_why, 'every_invited_supplier_quoted', 'A is ready: its one invited supplier quoted');
  assert.equal(out.identity_refused, true, 'the table refuses an alternative that carries a supplier identity');
  assert.equal(out.checked_marked, true);
  assert.equal(out.not_a_reply, false, 'an ordinary message is left to the normal WhatsApp route');

  // YES
  assert.equal(out.yes.handled, true); assert.equal(out.yes.ok, true); assert.equal(out.yes.state, 'accepted');
  assert.deepEqual(out.yes_row, { state: 'accepted', accepted_option: 'o2', accepted_value: '10 mm laminated', channel: 'whatsapp' });
  assert.equal(out.yes_recorded.length, 1);
  assert.equal(out.yes_recorded[0].option_id, 'o2'); assert.equal(out.yes_recorded[0].accepted, '10 mm laminated');
  assert.equal(out.yes_recorded[0].channel, 'whatsapp'); assert.equal(out.yes_recorded[0].attr, 'glass_type'); assert.ok(out.yes_recorded[0].at);
  assert.notEqual(out.yes_inquiry.status, 'closed', 'a yes keeps the request going');
  assert.equal(out.answer_twice.ok, false); assert.equal(out.answer_twice.error, 'not_open');
  assert.equal(out.someone_else.error, 'not_your_offer', 'another customer cannot answer this offer');

  // NO
  assert.equal(out.no.ok, true); assert.equal(out.no.state, 'declined'); assert.equal(out.no.inquiry_closed, true);
  assert.deepEqual(out.no_inquiry, { status: 'closed', lost_reason: 'no_exact_spec_declined' });
  assert.equal(out.no_sibling, 'superseded');

  // SILENCE
  assert.equal(out.due_at_start, 0, 'nothing is due the moment the question goes out');
  assert.equal(out.due_1.action, 'remind'); assert.equal(out.due_1.reminder_no, 1); assert.equal(out.due_1.final, false, 'past reply_by but no final reminder yet: remind, never lapse');
  assert.equal(out.due_2.action, 'remind'); assert.equal(out.due_2.reminder_no, 2); assert.equal(out.due_2.final, true);
  assert.equal(out.due_3.action, 'close_no_reply');
  assert.deepEqual(out.silence_row, { state: 'no_reply', closed_reason: 'no_exact_spec_no_reply', reminders: 2 });
  assert.deepEqual(out.silence_inquiry, { status: 'closed', lost_reason: 'no_exact_spec_no_reply' });
  assert.equal(out.due_after, 0);

  // WHO MAY ANSWER (review of #652)
  assert.equal(out.unverified.handled, false, 'an unverified number cannot answer an offer');
  assert.equal(out.unverified.reason, 'no_verified_customer_with_open_offer');
  assert.equal(out.unverified_state, 'open', 'the unverified reply recorded nothing');
  assert.equal(out.ambiguous.handled, false, 'a number two verified customers share answers nobody');
  assert.equal(out.ambiguous.reason, 'ambiguous_sender'); assert.equal(out.ambiguous.matches, 2);
  assert.deepEqual(out.ambiguous_states, ['open', 'open'], 'neither customer\'s offer was touched');
  assert.equal(out.ambiguous_case, 1, 'customer_support gets a tracked case instead');

  assert.equal(out.fee_rows, 0, 'nothing was revealed, so nothing is charged');

  // Rolled back: nothing the probe wrote is left.
  const [after] = await sql(`select jsonb_build_object('offers', (select count(*) from public.spec_alternative_offer), 'transactions', (select count(*) from public.transactions)) as a`);
  assert.equal(Number(after.a.offers), Number(out.before.offers), 'no offer survived the probe');
  assert.equal(Number(after.a.transactions), Number(out.before.transactions));
});
