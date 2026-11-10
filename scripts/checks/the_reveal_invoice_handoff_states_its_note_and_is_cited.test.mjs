// THE REVEAL INVOICE HANDOFF IS A REGISTERED CONVERSATION THAT STATES ITS NOTE, AND ITS RECEIVER CITES IT
// (accountant, 27 Oct 2026). scripts/sql/the_reveal_invoice_handoff_is_a_registered_conversation_that_states_its_note.sql
//
// Before it, the accountant's reveal-invoice handoff carried no type and had no row in public.seat_handoff_kind,
// and the sales engineer closed it with a bare UPDATE, so its answer cited no note (founder ledger 1013). This fails
// when that comes back:
//   1. (source) the file stops registering the conversation, the accountant's handoff stops naming its type and
//      decision, or the receiver's door stops dispatching through fn_seat_handoff_act;
//   2. (production, one rolled-back replay; the file is replayed first while it is pending) attaching the stored
//      Stripe PDF to a ZZ DEMO sale (doc_path 'invoices/...') must succeed and leave: the invoice in Documents once;
//      exactly one invoice.issued handoff from the accountant, closed by the sales engineer; a note naming the
//      registered handler and its reply window; an answer that cites that handoff; and the customer's
//      invoice_ready notice in the inquiry's language (Arabic here), captured - never sent.
//
//   node --test scripts/checks/the_reveal_invoice_handoff_states_its_note_and_is_cited.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';
import { manifestHas } from '../lib/pending_sql.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const FILE = 'scripts/sql/the_reveal_invoice_handoff_is_a_registered_conversation_that_states_its_note.sql';
const body = readFileSync(join(REPO, FILE), 'utf8');

test('the conversation is registered, the sender states it, and the receiver answers through the dispatcher', () => {
  assert.match(body, /insert into public\.seat_handoff_kind[\s\S]{0,200}'invoice\.issued', 'accountant', 'sales_engineer'[\s\S]{0,300}'fn_sales_engineer_answers_reveal_invoice', interval '24 hours', false/,
    'the reveal invoice conversation is not registered with its handler and reply window');
  assert.match(body, /jsonb_build_object\('type', 'invoice\.issued', 'from', 'accountant'[\s\S]{0,300}'decision', /,
    'the accountant\'s handoff no longer names its type and its decision, so its note cannot be stated');
  assert.match(body, /function public\.fn_sales_engineer_tells_customer_invoice_ready\(\)[\s\S]*?perform public\.fn_seat_handoff_act\(new\.id\)/,
    'the sales engineer closes the handoff without the dispatcher, so the answer cites no note');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

const PROBE = String.raw`
do $p$
declare c uuid := gen_random_uuid(); i uuid; t uuid := gen_random_uuid(); err text;
begin
  insert into public.customers (id, email, full_name, locale)
  values (c, 'zz-demo-revinv-' || substr(md5(random()::text), 1, 8) || '@example.invalid', 'ZZ DEMO Reveal Invoice Customer', 'en');
  insert into public.inquiries (customer_id, summary, lang) values (c, 'ZZ DEMO reveal invoice handoff probe', 'ar') returning id into i;
  insert into public.transactions (id, customer_id, inquiry_id, stripe_invoice_number) values (t, c, i, 'ZZDEMO-REVINV');
  begin
    update public.transactions set doc_path = 'invoices/zz-demo-revinv/' || t || '.pdf' where id = t;
  exception when others then err := sqlerrm;
  end;
  perform set_config('qd.revinv_err', coalesce(err, ''), true);
  perform set_config('qd.revinv_t', t::text, true);
  perform set_config('qd.revinv_c', c::text, true);
end $p$;
select current_setting('qd.revinv_err') as err,
  (select count(*)::int from public.documents where path = 'invoices/zz-demo-revinv/' || current_setting('qd.revinv_t') || '.pdf' and kind = 'invoice') as documents,
  (select coalesce(jsonb_agg(jsonb_build_object(
            'id', a.id, 'type', a.detail->>'type', 'from', a.detail->>'from', 'status', a.status, 'decided_by', a.decided_by,
            'handler', a.detail->'summary'->'needed'->>'handler', 'deadline_source', a.detail->'summary'->>'deadline_source',
            'has_four', a.detail->'summary' ?& array['context','decision','open_asks','deadline'],
            'cites', a.evidence->'cites_note'->>'handoff_id', 'notification_id', a.evidence->>'notification_id')), '[]'::jsonb)
     from public.agent_actions a
    where a.kind = 'handoff' and a.detail->>'transaction_id' = current_setting('qd.revinv_t')
      and a.detail->>'subject' = 'reveal_invoice') as handoffs,
  (select coalesce(jsonb_agg(jsonb_build_object('id', n.id, 'lang', n.lang, 'status', n.status) order by n.id), '[]'::jsonb)
     from public.notifications n join public.customers cu on cu.email = n.to_email
    where n.type = 'invoice_ready' and coalesce(n.channel, 'email') = 'email' and cu.id::text = current_setting('qd.revinv_c')) as notices,
  (select coalesce(jsonb_agg(jsonb_build_object('id', n.id, 'status', n.status) order by n.id), '[]'::jsonb)
     from public.notifications n join public.customers cu on cu.email = n.to_email
    where n.type = 'invoice_ready' and n.channel = 'whatsapp' and cu.id::text = current_setting('qd.revinv_c')) as twins`;

test('production, rolled back: a ZZ DEMO invoice attach files once, hands off a stated note and is answered citing it',
  { skip: hasToken ? false : 'no Supabase management token in this environment', timeout: 300000 }, async () => {
    const text = (manifestHas(FILE) ? '' : body + '\n;\n') + PROBE;
    const [r] = await replaySql(text, { label: 'reveal invoice handoff probe', rows: true });
    assert.equal(r.err, '', `attaching the invoice raised: ${r.err}`);
    assert.equal(r.documents, 1, 'the invoice is not in the customer\'s Documents exactly once');
    assert.equal(r.handoffs.length, 1, `expected one reveal_invoice handoff, found ${JSON.stringify(r.handoffs)}`);
    const h = r.handoffs[0];
    assert.deepEqual({ type: h.type, from: h.from, status: h.status, decided_by: h.decided_by },
      { type: 'invoice.issued', from: 'accountant', status: 'done', decided_by: 'sales_engineer' });
    assert.equal(h.has_four, true, 'the note does not state context, decision, open asks and deadline');
    assert.equal(h.handler, 'fn_sales_engineer_answers_reveal_invoice', 'the note names no registered conversation');
    assert.match(String(h.deadline_source), /^reply window of invoice\.issued/, 'the deadline is not the conversation\'s reply window');
    assert.equal(String(h.cites), String(h.id), 'the sales engineer\'s answer does not cite the note it was handed');
    // 10 Nov 2026 (it_engineer): every confirmation reaches the person on email AND WhatsApp (founder ledger 1535,
    // 3 Nov: "Not a single thing in our app is one-way communication"; #1846,
    // every_confirmation_reaches_the_person_on_email_and_whatsapp.sql). fn_wa_fanout now ALWAYS writes a WhatsApp twin
    // for invoice_ready, 'skipped' with its reason when the number is not confirmed. One email notice, one twin.
    assert.equal(r.notices.length, 1, `expected one invoice_ready email notice, found ${JSON.stringify(r.notices)}`);
    assert.equal(r.twins.length, 1, `expected one invoice_ready WhatsApp twin (ledger 1535), found ${JSON.stringify(r.twins)}`);
    assert.notEqual(r.twins[0].status, 'queued', 'a demo WhatsApp twin was left queued to send');
    assert.equal(String(r.notices[0].id), String(h.notification_id), 'the answer does not name the notice it queued');
    assert.equal(r.notices[0].lang, 'ar', 'the notice is not in the inquiry\'s language');
    assert.notEqual(r.notices[0].status, 'queued', 'a demo notice was left queued to send');
  });
