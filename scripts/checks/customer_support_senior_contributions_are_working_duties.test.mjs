// CUSTOMER SUPPORT'S SENIOR CONTRIBUTIONS ARE WORKING DUTIES (19 Oct 2026, customer_support; founder ledger 1003 stage 2).
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static, per file: a routine loses its revoke or pinned search_path, a new table loses RLS or its policy, the duty is
//     not registered on customer_support's clock, a duty calls a model (routine work is code), or the file carries both
//     (or neither of) a pending note and a MANIFEST line;
//   * production, in ONE aborted transaction through scripts/lib/safe_replay.mjs (every file replayed while pending,
//     ZZ DEMO / example.invalid fixtures only, qd.duty_fixtures = 'on', nothing commits): each duty ACTS on its fixture
//     (a case opened and an acknowledgement written; a knowledge request routed with a deadline and chased; a complaint
//     moved to in_review with its update written; a refused opt-out from a mailed address recorded; a data request
//     registered with its identity code and an objection fulfilled; incident holding and resolved notices written; a
//     public complaint turned into a social case and answered back; the weekly quality and monthly VoC measured), and
//     NO founder notification and NO CEO report is written by a fixture run.
//
//   node --test scripts/checks/customer_support_senior_contributions_are_working_duties.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));

// contribution -> [file, duty, routine, tables it creates]
const DUTIES = [
  ['CS-C01', 'customer_support_drives_every_unanswered_message_to_a_reply_or_a_case', 'customer_support.unanswered_inbound', 'fn_customer_support_unanswered_inbound_tick', ['customer_support_inbound_drive']],
  ['CS-C03', 'customer_support_closes_every_knowledge_request_by_a_deadline', 'customer_support.knowledge_request_deadline', 'fn_customer_support_knowledge_request_tick', []],
  ['CS-C06', 'customer_support_scores_its_replies_every_week_and_counts_what_went_unscored', 'customer_support.reply_quality_week', 'fn_customer_support_reply_quality_week', ['customer_support_reply_quality_week']],
  ['CS-C08', 'customer_support_returns_every_delivery_outcome_on_its_own_clock', 'customer_support.delivery_outcome_return', 'fn_customer_support_delivery_outcome_tick', []],
  ['CS-C09', 'customer_support_watches_delivery_health_every_day_and_never_loses_an_opt_out', 'customer_support.delivery_health', 'fn_customer_support_delivery_health_tick', ['unsubscribe_refusal']],
  ['CS-C10', 'customer_support_acts_on_a_complaint_before_its_deadline', 'customer_support.complaint_deadlines', 'fn_customer_support_complaint_deadline_tick', []],
  ['CS-C11', 'customer_support_registers_every_personal_data_request_and_keeps_its_clock', 'customer_support.data_requests', 'fn_customer_support_data_request_tick', ['customer_support_data_request']],
  ['CS-C12', 'customer_support_tells_affected_customers_during_an_incident', 'customer_support.incident_notices', 'fn_customer_support_incident_notice_tick', []],
  ['CS-C13', 'customer_support_turns_every_public_complaint_into_a_case', 'customer_support.public_complaints', 'fn_customer_support_public_complaint_tick', []],
  ['CS-C14', 'customer_support_reports_the_voice_of_the_customer_to_the_ceo_every_month', 'customer_support.voice_of_customer', 'fn_customer_support_voice_of_customer_month', ['customer_support_voc_month']],
];
const LEAK = 'scripts/sql/no_external_answer_can_state_an_internal_number.sql';
const CONTEXT = 'scripts/sql/internal_seats_read_the_live_business_figures_in_the_company_block.sql';
const manifest = () => read('scripts/sql/MANIFEST.txt').split(/\r?\n/);

for (const [id, name, duty, fn, tables] of DUTIES) {
  test(`static ${id}: ${duty} is a revoked, pinned, model-free duty on customer_support's clock`, () => {
    const file = `scripts/sql/${name}.sql`;
    const src = code(read(file));
    assert.match(src, new RegExp(`function public\\.${fn}\\(\\)[\\s\\S]{0,160}security definer set search_path to 'public', 'pg_temp'`), `${fn}: search_path not pinned`);
    assert.ok(src.includes(`revoke execute on function public.${fn}() from public, anon, authenticated;`), `${fn} is not revoked`);
    assert.ok(src.includes(`('${duty}', 'customer_support', interval`) && src.includes(`'${fn}'`), `${duty} is not registered on the seat clock`);
    assert.doesNotMatch(src, /fn_reason_hold|fn_seat_duty_reason|think\(|openrouter|fn_llm_/i, `${duty} calls a model: routine work is code`);
    assert.ok(src.includes("current_setting('qd.duty_fixtures', true)") || id === 'CS-C08', `${duty} has no fixture switch`);
    for (const t of tables) {
      assert.ok(src.includes(`alter table public.${t} enable row level security`), `${t}: RLS off`);
      assert.match(src, new RegExp(`create policy ${t}_service_role_only on public\\.${t}[\\s\\S]{0,120}using \\(false\\) with check \\(false\\)`), `${t}: no policy`);
      assert.ok(src.includes(`revoke all on public.${t} from anon, authenticated`), `${t}: not revoked`);
    }
    for (const m of src.matchAll(/create or replace function public\.(fn_[a-z0-9_]+)\(([^)]*)\)/g)) {
      assert.ok(new RegExp(`revoke execute on function public\\.${m[1]}\\(`).test(src), `${m[1]} is not revoked`);
    }
    assert.ok(pending(file) !== manifest().includes(file), `${file}: exactly one of a pending note and a MANIFEST line`);
  });
}

test('static: the leak fix withholds live-figure rows, filters the corpus, and the guard backs every channel', () => {
  const src = code(read(LEAK));
  assert.ok(src.includes("revoke execute on function public.fn_knowledge_internal_figures_withheld() from public, anon, authenticated;"));
  assert.match(src, /before insert or update on public\.ops_knowledge/);
  assert.ok(src.includes("'qd-company:business-entities'"), 'the row that leaked the supplier count is not withheld');
  assert.match(src, /WHERE \(\(COALESCE\(k\.supersession_state, 'current'::text\) = 'current'::text\) AND k\.runtime_eligible\)/, 'the support corpus still reads withdrawn ops rows');
  const guard = read('supabase/functions/_shared/support_reply_guard.ts');
  assert.ok(guard.includes("if (hasInternalNumber(s)) v.push('internal_number');"), 'replyViolations no longer refuses an internal count');
  assert.ok(src.includes('revoke all on public.v_support_corpus from public, anon, authenticated;'), 'the view is not revoked from public');
  assert.ok(pending(LEAK) !== manifest().includes(LEAK), 'exactly one of a pending note and a MANIFEST line');
  const cc = code(read(CONTEXT));
  assert.ok(cc.includes('jsonb_each_text(public.fn_business_entity_summary())'), 'internal seats lost the live figures');
  assert.ok(pending(CONTEXT) !== manifest().includes(CONTEXT), 'exactly one of a pending note and a MANIFEST line');
  const dh = code(read('scripts/sql/customer_support_watches_delivery_health_every_day_and_never_loses_an_opt_out.sql'));
  assert.doesNotMatch(dh, /recovered_refused_link/, 'a refused attempt is turned into an opt-out without proof of ownership');
  assert.ok(dh.includes("'confirmed_by_reply'") && dh.includes('fn_unsubscribe_signed_link(r.email)') && dh.includes('a00_unsubscribe_refusal_throttle'), 'the ownership proof or the throttle is gone');
});

test('static: every road that sends a widget or portal reply scores it, and a refused opt-out is kept', () => {
  assert.ok(read('supabase/functions/site_assistant/index.ts').includes("admin.rpc('fn_support_reply_readability_log'"), 'site_assistant sends unscored replies again');
  assert.ok(read('supabase/functions/unsubscribe/index.ts').includes("from('unsubscribe_refusal').insert"), 'a refused opt-out is no longer recorded');
});

const token = () => process.env.SUPABASE_ACCESS_TOKEN || (existsSync(join(homedir(), '.supabase', 'access-token')) ? 'file' : '');

test('production, aborted: every duty acts on its fixture, and nothing reaches the founder or the CEO', { skip: !token() && 'no Supabase access token' }, async () => {
  const replay = [LEAK, CONTEXT, ...DUTIES.map((d) => `scripts/sql/${d[1]}.sql`)]
    .filter((f) => !manifest().includes(f)).map(read).join('\n;\n');
  let o = null;
  try { await replaySql(replay + '\n' + PROBE, { retry: false, label: 'customer_support senior duties' }); }
  catch (e) {
    const msg = String(e.message); if (process.env.PROBE_DUMP) writeFileSync(process.env.PROBE_DUMP, msg);
    const m = msg.match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + msg.slice(0, 1500));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  console.log(JSON.stringify(o));
  assert.equal(o.duties, 10, 'not every duty is on customer_support\'s clock');
  assert.ok(o.c01.email_driven >= 1 && o.c01_ack >= 1 && o.c01_case, 'C01: the unanswered email was not put into a case and acknowledged: ' + JSON.stringify(o.c01));
  assert.ok(o.c01.whatsapp_driven >= 1, 'C01: the unanswered WhatsApp message was not put into a case');
  assert.equal(o.c01_again, 0, 'C01: a message was driven twice');
  assert.ok(o.c03 >= 1 && o.c03_owner === 'sales_engineer' && o.c03_due, 'C03: the request was not routed with a deadline');
  assert.ok(o.c03_chase >= 1, 'C03: the overdue request was not chased');
  assert.equal(o.c06, true, 'C06: the weekly review does not count sent against scored');
  assert.equal(o.c08, true, 'C08: the delivery outcome tick failed');
  assert.equal(o.c09_throttled_to, 3, 'C09: refusals for one address are not throttled');
  assert.equal(o.c09_after_refusal, 0, 'C09: a refused attempt alone unsubscribed the address');
  assert.equal(o.c09_confirm, 1, 'C09: the mailed address was not sent a signed confirmation');
  assert.equal(o.c09_link_signed, true, 'C09: the confirmation link is not signed the way the endpoint verifies');
  assert.ok(o.c09 >= 1 && o.c09_suppressed === 'confirmed_by_reply', 'C09: a reply from the address did not confirm the opt-out');
  assert.equal(o.cc_internal, true, 'internal seats do not get the live figures in the company block');
  assert.equal(o.cc_public, false, 'the public company block carries the live figures');
  assert.equal(o.c10_status, 'in_review', 'C10: the complaint was not moved to in_review before its deadline');
  assert.ok(o.c10_update >= 1, 'C10: the customer update was not written');
  assert.ok(o.c11 >= 1 && o.c11_kind === 'erasure' && o.c11_pdpl, 'C11: the data request was not registered with its identity check: ' + JSON.stringify(o.c11));
  assert.equal(o.c11_objection, 'fulfilled', 'C11: a verified objection was not fulfilled');
  assert.ok(o.c12_hold >= 1 && o.c12_res >= 1, 'C12: holding and resolved notices were not written');
  assert.ok(o.c13 >= 1 && o.c13_channel === 'social' && o.c13_category === 'complaint', 'C13: the public complaint did not become a case');
  assert.ok(o.c13_answered, 'C13: the closed case was not written back for marketing to close');
  assert.ok(o.c14 >= 1, 'C14: the VoC report has no actions');
  assert.equal(o.leak_withdrawn, true, 'the live-figures row is still retrievable');
  assert.equal(o.leak_corpus, 0, 'the support corpus still returns the live-figures row');
  assert.equal(o.founder_notifications, 0, 'a fixture run wrote to the founder');
  assert.equal(o.ceo_reports, 0, 'a fixture run wrote to the CEO');
});

const PROBE = String.raw`
do $$ declare o jsonb := '{}'; v jsonb; v_case text; v_prof bigint; v_aa bigint; v_inc bigint; v_ceo0 int; v_dsr bigint; v_founder text[];
begin
  select count(*) into v_ceo0 from support_ceo_report;
  perform set_config('qd.duty_fixtures', 'on', true);
  o := o || jsonb_build_object('duties', (select count(*) from seat_duty where owner_seat = 'customer_support' and duty in
    ('customer_support.unanswered_inbound','customer_support.knowledge_request_deadline','customer_support.reply_quality_week',
     'customer_support.delivery_outcome_return','customer_support.delivery_health','customer_support.complaint_deadlines',
     'customer_support.data_requests','customer_support.incident_notices','customer_support.public_complaints','customer_support.voice_of_customer')));

  -- C01
  insert into inbound_messages (from_email, to_email, subject, body, created_at)
    values ('zz.cs01@example.invalid', 'support@quotesdone.com', 'ZZ DEMO where is my quote', 'ZZ DEMO', now() - interval '3 hours');
  insert into wa_messages (wa_from, wa_to, profile_name, inbound, created_at) values ('+000000000123', '+971000000000', 'ZZ DEMO wa', 'ZZ DEMO hello', now() - interval '3 hours');
  v := fn_customer_support_unanswered_inbound_tick(); o := o || jsonb_build_object('c01', v);
  o := o || jsonb_build_object('c01_ack', (select count(*) from customer_support_duty_message where stage = 'inbound.ack' and to_email = 'zz.cs01@example.invalid'),
                               'c01_case', (select case_ref from customer_support_inbound_drive d join inbound_messages m on m.id = d.message_id and d.channel = 'email' where m.from_email = 'zz.cs01@example.invalid'));
  v := fn_customer_support_unanswered_inbound_tick(); o := o || jsonb_build_object('c01_again', v->'email_driven');

  -- C03
  insert into sales_knowledge_gap (question_norm, question, asks, first_asked_at, last_asked_at, status, kind, nearest_corpus)
    values ('zz demo cs03 probe', 'ZZ DEMO what is the warranty on chillers', 2, now() - interval '20 days', now() - interval '20 days', 'open', 'refusal', 'kb_chunks');
  v := fn_customer_support_knowledge_request_tick(); o := o || jsonb_build_object('c03', v->'routed');
  o := o || jsonb_build_object('c03_owner', (select owner_seat from sales_knowledge_gap where question_norm = 'zz demo cs03 probe'),
                               'c03_due', (select due_at is not null from sales_knowledge_gap where question_norm = 'zz demo cs03 probe'));
  update sales_knowledge_gap set due_at = now() - interval '1 hour' where question_norm = 'zz demo cs03 probe';
  v := fn_customer_support_knowledge_request_tick(); o := o || jsonb_build_object('c03_chase', v->'chased');

  -- C06, C08
  v := fn_customer_support_reply_quality_week(); o := o || jsonb_build_object('c06', (v ? 'sent') and (v ? 'scored_share'), 'c06_scored_share', v->'scored_share');
  v := fn_customer_support_delivery_outcome_tick(); o := o || jsonb_build_object('c08', v->'ok', 'c08_unreturned', v->'unreturned', 'c08_returned', v->'watch'->'results_returned');

  -- C09
  insert into notifications (type, to_email, to_role, subject, body, status, sent_at, channel)
    values ('zz_probe', 'zz.cs09@example.invalid', 'supplier', 'ZZ DEMO', 'ZZ DEMO', 'sent', now() - interval '2 days', 'email');
  update notifications set status = 'sent', sent_at = now() - interval '2 days' where to_email = 'zz.cs09@example.invalid';
  insert into unsubscribe_refusal (email, method, token_present) select 'zz.cs09@example.invalid', 'POST', true from generate_series(1, 5);
  o := o || jsonb_build_object('c09_throttled_to', (select count(*) from unsubscribe_refusal where email = 'zz.cs09@example.invalid'));
  v := fn_customer_support_delivery_health_tick();
  o := o || jsonb_build_object('c09_after_refusal', (select count(*) from email_suppressions where email = 'zz.cs09@example.invalid'),
           'c09_confirm', (select count(*) from customer_support_duty_message where stage = 'optout.confirm' and to_email = 'zz.cs09@example.invalid'),
           'c09_link_signed', public.fn_unsubscribe_signed_link('zz.cs09@example.invalid') ~ '[?&]e=zz.cs09%40example.invalid&t=[0-9a-f]{20}$');
  insert into inbound_messages (from_email, to_email, subject, body, created_at) values ('zz.cs09@example.invalid', 'support@quotesdone.com', 'ZZ DEMO stop', 'ZZ DEMO stop', now() + interval '1 second');
  v := fn_customer_support_delivery_health_tick();
  o := o || jsonb_build_object('c09', v->'opt_outs_confirmed', 'c09_suppressed', (select source from email_suppressions where email = 'zz.cs09@example.invalid'));

  -- C10
  insert into complaint_tickets (ticket_no, email, name, message, status, created_at, acknowledge_due, respond_due, acknowledged_at, handled_by)
    values ('QD-C-ZZDEMA', 'zz.cs10@example.invalid', 'ZZ DEMO', 'ZZ DEMO the supplier never came', 'acknowledged',
            now() - interval '10 days', now() - interval '8 days', now() + interval '3 days', now() - interval '10 days', 'customer_support');
  perform fn_customer_support_complaint_deadline_tick(); o := o || jsonb_build_object(
                               'c10_status', (select status from complaint_tickets where ticket_no = 'QD-C-ZZDEMA'),
                               'c10_update', (select count(*) from customer_support_duty_message where stage = 'complaint.update' and subject_key = 'QD-C-ZZDEMA'));

  -- C11
  insert into support_customer_profile (party_kind, email) values ('unknown', 'zz.cs11@example.invalid') returning id into v_prof;
  v_case := fn_support_case_new_ref();
  insert into support_case (case_ref, party_kind, party_id, subject, state, identity_verified, owner_role_id, customer_profile_id, channel, category, topic_tags)
    values (v_case, 'unknown', 'zz.cs11@example.invalid', 'ZZ DEMO please erase my data', 'open', false, 'customer_support', v_prof, 'email', 'data_request', array['erase']);
  v := fn_customer_support_data_request_tick(); o := o || jsonb_build_object('c11', v->'registered', 'c11_codes', v->'identity_codes_sent');
  o := o || jsonb_build_object('c11_kind', (select kind from customer_support_data_request where case_ref = v_case),
                               'c11_pdpl', (select pdpl_request_id is not null from customer_support_data_request where case_ref = v_case));
  v := fn_customer_support_data_request_open('zz.cs11b@example.invalid', 'objection', 'probe', null);
  update customer_support_data_request set identity_status = 'verified' where id = (v->>'id')::bigint;
  perform fn_customer_support_data_request_tick();
  o := o || jsonb_build_object('c11_objection', (select status from customer_support_data_request where id = (v->>'id')::bigint));

  -- C12 (the C11 fixture case is an active customer conversation)
  update support_case set party_kind = 'customer' where case_ref = v_case;
  insert into agent_actions (agent, kind, status, title, detail) values ('it_engineer', 'probe', 'done', 'ZZ DEMO', '{}') returning id into v_aa;
  insert into it_incident (handoff_id, issue_key, title, what, impact, started_at, customer_impact)
    values (v_aa, 'zz_demo_cs12', 'ZZ DEMO outage', 'ZZ DEMO', 'the customer portal', now() - interval '10 minutes', 'customers') returning id into v_inc;
  perform fn_customer_support_incident_notice_tick();
  update it_incident set ended_at = now() where id = v_inc;
  perform fn_customer_support_incident_notice_tick();
  o := o || jsonb_build_object('c12_hold', (select count(*) from customer_support_duty_message where stage = 'incident.holding' and subject_key like v_inc || ':%'),
                               'c12_res', (select count(*) from customer_support_duty_message where stage = 'incident.resolved' and subject_key like v_inc || ':%'));

  -- C13
  insert into agent_actions (agent, kind, status, title, detail, target_table, target_id)
    values ('customer_support', 'handoff', 'pending', 'ZZ DEMO social', jsonb_build_object('type', 'social.escalation', 'from', 'marketing',
            'text', 'ZZ DEMO your supplier ruined my kitchen', 'platform', 'instagram', 'handle', 'zz_demo', 'classification', 'complaint'),
            'social_message', 'social.escalation:instagram:zz') returning id into v_aa;
  v := fn_customer_support_public_complaint_tick(); o := o || jsonb_build_object('c13', v->'cases_opened');
  o := o || jsonb_build_object('c13_channel', (select s.channel from support_case s where s.case_ref = (select detail->>'case_ref' from agent_actions where id = v_aa)),
                               'c13_category', (select s.category from support_case s where s.case_ref = (select detail->>'case_ref' from agent_actions where id = v_aa)));
  update support_case set state = 'closed', closed_at = now(), close_reason = 'ZZ DEMO answered privately'
   where case_ref = (select detail->>'case_ref' from agent_actions where id = v_aa);
  perform fn_customer_support_public_complaint_tick();
  o := o || jsonb_build_object('c13_answered', (select detail ? 'answered_at' from agent_actions where id = v_aa));

  -- C14
  v := fn_customer_support_voice_of_customer_month(); o := o || jsonb_build_object('c14', jsonb_array_length(v->'actions'));

  -- the leak
  update ops_knowledge set content = content || ' ' where record_id = 'qd-company:business-entities';
  o := o || jsonb_build_object('leak_withdrawn', (select supersession_state = 'withdrawn' and not runtime_eligible from ops_knowledge where record_id = 'qd-company:business-entities'),
                               'leak_corpus', (select count(*) from v_support_corpus where src = 'ops' and src_id = 'qd-company:business-entities'));

  o := o || jsonb_build_object('cc_internal', (fn_company_context(16000, 'internal')->>'block') like '%suppliers_total:%',
                               'cc_public', (fn_company_context(16000, 'public')->>'block') like '%suppliers_total:%');

  -- nothing reached the founder or the CEO
  select coalesce(array_agg(lower(btrim(e))), '{}') into v_founder from app_secrets s, unnest(string_to_array(s.value, ',')) e
   where s.key in ('admin_emails', 'founder_email') and btrim(e) <> '';
  o := o || jsonb_build_object('founder_notifications', (select count(*) from notifications n where n.created_at >= now()
           and (n.to_role = 'founder' or lower(btrim(coalesce(n.to_email, ''))) = any (v_founder))),
         'ceo_reports', (select count(*) from support_ceo_report) - v_ceo0);
  raise exception 'CHK<<%>>', o::text;
end $$;`;
