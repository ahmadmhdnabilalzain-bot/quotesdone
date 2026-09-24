// REVEAL WORK IS THE SALES ENGINEER'S; CUSTOMER SUPPORT ONLY DELIVERS IT (24 Sep 2026, sales_engineer, from customer_support).
//
// Founder's seat map, 24 Sep 2026: the sales_engineer owns reveals; customer_support "does NOT own reveals".
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: the 7-day reveal outcome check is requested by any seat but the sales_engineer, the dispute finding is
//     reasoned on a customer_support surface, the customer_support dispute routines are not dropped or the
//     customer_support.disputes duty survives, a routine loses its revoke or pinned search_path, the fault applier
//     stops refusing a choice outside its options, or the file carries both (or neither of) a pending note and a
//     MANIFEST line;
//   * production, in ONE aborted transaction (file replayed while pending, a ZZ DEMO customer, supplier, request, quote
//     and a reveal 8 days old, all @example.invalid; nothing commits): the outcome check's delivery request names the
//     sales_engineer as the asking seat and is held by customer_support, exactly once; the duty clock and the old
//     routines are where the file says. The dispute path itself is proved end to end by
//     scripts/checks/customer_support_and_accountant_duties_act.test.mjs, which replays this file.
//
//   node --test scripts/checks/reveal_work_is_the_sales_engineers.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/reveal_follow_up_and_dispute_findings_belong_to_the_sales_engineer.sql';
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));

test('static: the sales_engineer asks and finds; support routines for it are gone; hygiene', () => {
  const src = code(read(FILE));
  assert.match(src, /fn_seat_clock_deliver\('sales_engineer', 'reveal_outcome_check'/, 'the outcome check is not asked by the sales_engineer');
  assert.doesNotMatch(src, /fn_seat_clock_deliver\('customer_support'/);
  assert.match(src, /fn_seat_duty_reason\('sales_engineer', 'sales_engineer\.dispute_fault'/);
  assert.doesNotMatch(src, /'customer_support\.dispute_fault'\s*,/, 'a dispute finding is still reasoned on a support surface');
  assert.match(src, /fn_seat_duty_cross_review\('post_reveal_dispute', 'sales_engineer', 'ceo'/);
  assert.match(src, /delete from public\.seat_duty where duty = 'customer_support\.disputes'/);
  assert.match(src, /\('sales_engineer\.disputes', 'sales_engineer', interval '30 minutes', 'fn_sales_engineer_disputes_tick'/);
  assert.match(src, /drop function if exists public\.fn_customer_support_disputes_tick\(\);/);
  assert.match(src, /drop function if exists public\.fn_reason_apply_customer_support__dispute_fault\(bigint, jsonb\);/);
  for (const [, name] of src.matchAll(/create or replace function public\.(\w+)\(/g)) {
    const head = src.slice(src.indexOf(`function public.${name}(`)).split('$fn$')[0];
    assert.match(head, /security definer\s+set search_path to 'public', 'pg_temp'/, `${name}: not security definer with a pinned search_path`);
    assert.match(src, new RegExp(`revoke execute on function public\\.${name}\\([^)]*\\) from public, anon, authenticated;`), `${name} is not revoked`);
  }
  const apply = src.slice(src.indexOf('function public.fn_reason_apply_sales_engineer__dispute_fault(')).split('$fn$;')[0];
  assert.match(apply, /raise exception 'CHOICE_NOT_AN_OPTION/);
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/);
  assert.ok(pending(FILE) !== manifest.includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: the sales_engineer asks the 7-day question and support delivers it once', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const replay = pending(FILE) ? read(FILE) : '';
  let o;
  try { await sql(replay + '\n' + PROBE, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  // asked counts every ZZ DEMO reveal in production (include_fixtures); this probe's own quote is judged by req below
  assert.ok(o.r1.asked >= 1, 'the outcome check did not ask: ' + JSON.stringify(o.r1));
  assert.equal(o.r2.asked, 0, 'the outcome check asked twice');
  assert.deepEqual(o.req, [{ agent: 'customer_support', from: 'sales_engineer' }], 'the delivery request is not the sales_engineer\'s, held by support');
  assert.deepEqual(o.duties, ['sales_engineer.disputes'], 'the dispute clock is not the sales_engineer\'s alone');
  assert.equal(o.old_fns, 0, 'a customer_support dispute routine survived');
});

const PROBE = String.raw`
do $$ declare o jsonb := '{}'; c uuid; l bigint; i uuid; q uuid; t uuid;
begin
  -- inside this aborted transaction only: let the door queue mail to the fixture domain so the effect is countable
  delete from email_domain_mx where domain = 'example.invalid';
  update email_block_pattern set active = false where 'zz.reveal.c@example.invalid' ~ pattern;
  insert into customers (full_name, email, created_at) values ('ZZ DEMO Reveal', 'zz.reveal.c@example.invalid', now() - interval '30 days') returning id into c;
  insert into leads (company_name, email, lifecycle_stage) values ('ZZ DEMO — Reveal Supplier', 'zz.reveal.s@example.invalid', 'registered') returning id into l;
  insert into inquiries (customer_id, category, status, created_at, raw_input) values (c, 'flooring', 'revealed', now() - interval '12 days', 'ZZ DEMO floor') returning id into i;
  insert into quotes (inquiry_id, supplier_id, quote_amount, status) values (i, l, 1000, 'revealed') returning id into q;
  insert into transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, fee_status, revealed_at)
    values (q, i, l, c, 1000, 'paid', now() - interval '8 days') returning id into t;
  o := o || jsonb_build_object('r1', (select x - 'not_written' from fn_reveal_outcome_check_tick(true) x));
  o := o || jsonb_build_object('r2', (select x - 'not_written' from fn_reveal_outcome_check_tick(true) x));
  o := o || jsonb_build_object('req', (select jsonb_agg(jsonb_build_object('agent', a.agent, 'from', a.detail->>'from'))
                                         from agent_actions a where a.kind = 'handoff'
                                          and a.target_id = 'delivery.request:reveal_outcome_check:' || q));
  o := o || jsonb_build_object('duties', (select jsonb_agg(duty order by duty) from seat_duty where duty in ('customer_support.disputes', 'sales_engineer.disputes')));
  o := o || jsonb_build_object('old_fns', (select count(*) from pg_proc where proname in ('fn_customer_support_disputes_tick', 'fn_reason_apply_customer_support__dispute_fault')));
  raise exception 'CHK<<%>>', o::text;
end $$;
`;
