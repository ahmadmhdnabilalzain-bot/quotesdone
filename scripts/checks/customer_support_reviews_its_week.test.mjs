// CUSTOMER SUPPORT REVIEWS ITS WEEK (24 Sep 2026, customer_support; job description approved in ledger 983).
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: the weekly case review loses its revoke or pinned search_path, its table loses RLS or its policy, the
//     duty is not registered on the seat's clock, the review calls a model (it is routine work: code, never an LLM),
//     an unanswered question is filed anywhere but the one knowledge door (fn_support_knowledge_gap), or the file
//     carries both (or neither of) a pending note and a MANIFEST line;
//   * production, in ONE aborted transaction (the file replayed while pending, ZZ DEMO rows with @example.invalid
//     addresses, qd.duty_fixtures = 'on' so only demo rows are counted and filed, nothing commits): the review
//     counts a repeat contact and a first-reply time, files an unanswered chat question exactly once and links the
//     log row to the knowledge request, and writes one review row for the week.
//
//   node --test scripts/checks/customer_support_reviews_its_week.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/customer_support_reviews_its_week_and_files_what_it_could_not_answer.sql';
// 30 Sep 2026 (senior-hire audit): the review counts only customers and times the WhatsApp reply.
const FILE2 = 'scripts/sql/the_case_review_counts_only_customers_and_times_the_whatsapp_reply.sql';
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));

test('static: revoke, search_path, RLS + policy, the duty, no model, one knowledge door, pending XOR MANIFEST', () => {
  const src = code(read(FILE));
  const fn = 'fn_customer_support_case_review_tick';
  assert.match(src, new RegExp(`function public\\.${fn}\\(\\)[\\s\\S]{0,120}security definer\\s+set search_path to 'public', 'pg_temp'`));
  assert.match(src, new RegExp(`revoke execute on function public\\.${fn}\\(\\) from public, anon, authenticated;`));
  assert.match(src, /alter table public\.customer_support_case_review enable row level security/);
  assert.match(src, /create policy customer_support_case_review_service_role_only[\s\S]{0,120}using \(false\) with check \(false\)/);
  assert.match(src, /revoke all on public\.customer_support_case_review from anon, authenticated/);
  assert.match(src, new RegExp(`\\('customer_support\\.case_review', 'customer_support', interval '7 days', '${fn}'`));
  assert.doesNotMatch(src, /fn_reason_hold|fn_seat_duty_reason|think\(|openrouter/i, 'the weekly review calls a model: routine work is code');
  assert.match(src, /public\.fn_support_knowledge_gap\(g\.message, 'weekly_case_review', 'website_widget'\)/);
  assert.doesNotMatch(src, /insert into public\.(org_tasks|sales_knowledge_gap)/, 'a knowledge request is filed around the one door');
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/);
  assert.ok(pending(FILE) !== manifest.includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

test('static: the email a review counts is a customer, and WhatsApp is timed from replied_at', () => {
  const src = code(read(FILE2));
  const g = 'fn_support_email_is_a_customer_contact';
  assert.ok(src.includes(`revoke execute on function public.${g}(text, text, text, text, boolean) from public, anon, authenticated;`), `${g} is not revoked`);
  assert.ok(src.includes('no-?reply'), 'a machine sender is not excluded');
  assert.ok(src.includes('^(expenses@|calendar\\+|approve\\+)'), 'the expenses, calendar+ and approve+ mailboxes are not excluded');
  assert.ok(src.includes("('admin_emails', 'founder_email')"), "the founder's own addresses are not excluded");
  assert.ok(src.includes("like 'ZZ DEMO%') = p_fixtures"), 'a ZZ DEMO subject is not a fixture');
  assert.equal(src.split(`public.${g}(m.from_email`).length - 1, 2, 'email and repeat contacts must share the one test');
  assert.ok(src.includes('add column if not exists replied_at timestamptz'));
  assert.ok(src.includes('w.replied_at - w.created_at'), 'WhatsApp is not timed from replied_at');
  assert.ok(src.includes("'not_answered_filed'"), 'the review does not show what was already filed');
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/);
  assert.ok(pending(FILE2) !== manifest.includes(FILE2), 'exactly one of a pending note and a MANIFEST line');
});

const hasToken =!!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: a ZZ DEMO week is reviewed and its unanswered question filed once', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const replay = (pending(FILE) ? read(FILE) : '') + '\n' + (pending(FILE2) ? read(FILE2) : '');
  let o;
  try { await sql(replay + '\n' + PROBE, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  assert.equal(o.r1.fixture, true);
  assert.ok(o.r1.email.received >= 2 && o.r1.email.replied >= 1, 'the demo email was not counted: ' + JSON.stringify(o.r1.email));
  // the 30 Sep review (FILE2) is live or replayed: a machine and a calendar+ approval are not customers
  assert.equal(o.robot, false, 'a noreply sender is counted as a customer');
  assert.equal(o.cal, false, 'a calendar+ approval is counted as a customer');
  assert.ok(o.r1.whatsapp.timed >= 1 && o.r1.whatsapp.median_first_reply_minutes !== null, 'the WhatsApp reply was not timed: ' + JSON.stringify(o.r1.whatsapp));
  assert.ok(o.r1.email.median_first_reply_minutes !== null, 'no first-reply time was measured');
  assert.ok(o.r1.repeat_contacts.people >= 1, 'a person who wrote on two days is not a repeat contact');
  assert.ok(o.r1.chat.not_answered >= 1, 'the unanswered chat question was not counted');
  assert.ok(o.r1.knowledge_filed >= 1, 'the unanswered question was not filed');
  assert.equal(o.linked, true, 'the chat log row is not linked to its knowledge request');
  assert.equal(o.gap, 1, 'the question is not in sales_knowledge_gap exactly once');
  assert.equal(o.r2.knowledge_filed, 0, 'a second review filed again');
  assert.equal(o.rows, 1, 'the week has more or fewer than one review row');
  assert.equal(o.duty, 'customer_support', 'the duty is not on the seat\'s clock');
});

const PROBE = String.raw`
do $$ declare o jsonb := '{}'; g bigint;
begin
  perform set_config('qd.duty_fixtures', 'on', true);
  insert into inbound_messages (from_email, to_email, subject, body, created_at, replied_at)
    values ('zz.review.a@example.invalid', 'support@quotesdone.com', 'ZZ DEMO one', 'ZZ DEMO', now() - interval '3 days', now() - interval '3 days' + interval '30 minutes'),
           ('zz.review.a@example.invalid', 'support@quotesdone.com', 'ZZ DEMO two', 'ZZ DEMO', now() - interval '1 day', null),
           ('zz-noreply@example.invalid', 'support@quotesdone.com', 'ZZ DEMO robot', 'ZZ DEMO', now() - interval '1 day', null),
           ('zz.review.b@example.invalid', 'calendar+zz@mail.quotesdone.com', 'ZZ DEMO approval', 'ZZ DEMO', now() - interval '1 day', null);
  insert into wa_messages (wa_from, wa_to, profile_name, inbound, reply, lang, escalated, sent, meta, created_at, replied_at)
    values ('whatsapp:+10000000000', 'whatsapp:+10000000001', 'ZZ DEMO review', 'ZZ DEMO hi', 'hello', 'en', false, true, '{}', now() - interval '2 days', now() - interval '2 days' + interval '4 minutes');
  insert into assistant_logs (message, reply, matched_ids, seat, answered, gap_task_id, audience, created_at)
    values ('ZZ DEMO weekly review question ' || gen_random_uuid(), 'n/a', '{}', 'customer_support', false, null, 'visitor', now() - interval '2 days')
    returning id into g;
  o := o || jsonb_build_object('r1', fn_customer_support_case_review_tick());
  o := o || jsonb_build_object('linked', (select gap_task_id is not null from assistant_logs where id = g));
  o := o || jsonb_build_object('gap', (select count(*) from sales_knowledge_gap k join assistant_logs a on a.id = g
                                        where k.question = a.message));
  o := o || jsonb_build_object('r2', fn_customer_support_case_review_tick());
  o := o || jsonb_build_object(
    'robot', fn_support_email_is_a_customer_contact('zz-noreply@example.invalid', 'support@quotesdone.com', null, 'ZZ DEMO robot', true),
    'cal', fn_support_email_is_a_customer_contact('zz.review.b@example.invalid', 'calendar+zz@mail.quotesdone.com', null, 'ZZ DEMO approval', true));
  o := o || jsonb_build_object('rows', (select count(*) from customer_support_case_review where week_ending = (now() at time zone 'Asia/Dubai')::date));
  o := o || jsonb_build_object('duty', (select owner_seat from seat_duty where duty = 'customer_support.case_review'));
  raise exception 'CHK<<%>>', o::text;
end $$;
`;
