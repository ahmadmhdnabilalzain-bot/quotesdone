// CUSTOMER SUPPORT AND THE ACCOUNTANT DO THEIR DUTIES (23 Sep 2026, customer_support + accountant; founder_instruction 898).
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: either duty file loses a routine's revoke or pinned search_path, a new table loses RLS or its policy,
//     a duty routine is registered that the file does not define, a reasoning apply function stops validating the
//     choice against the options, a seat-to-seat judgement loses its registered review pair, or a file carries
//     both (or neither of) a pending note and a MANIFEST line;
//   * production, in ONE aborted transaction (framework file and both duty files replayed while pending, ZZ DEMO
//     fixtures with @example.invalid addresses, qd.duty_fixtures = 'on' so only demo rows are selected, nothing
//     commits): each duty's effect, and that a second run does nothing again:
//       activation - a sign-up with no request and a request with no quote are written to once through the door;
//                    a request 10 days without a quote is filed as a high-stakes reasoning question and its answer
//                    sends one message; a choice outside the options is refused;
//       win-back   - a customer dormant 60-90 days after a reveal is written to once;
//       disputes   - a message reasoned to be a dispute opens a case and notifies both parties; evidence closes it
//                    into review; the reasoned finding goes to the CEO with a cross-family deliberation; an overdue
//                    decision is a finding; the CEO's decision closes it and tells both parties;
//       fraud      - duplicate phone and licence are flagged by equality; a silent-after-reveal signal is flagged and
//                    reasoned; a 'circumvention' verdict escalates the flag with a cross-family deliberation;
//       sanctions  - a registered demo supplier whose signatory is on the latest list becomes a screening hit.
//   Inside the aborted transaction only, the probe lets mail to example.invalid through fn_email_sendable so the
//   door's queued rows can be counted; the transaction rolls back, so nothing is ever sent.
//
//   node --test scripts/checks/customer_support_and_accountant_duties_act.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FRAME = 'scripts/sql/every_seat_duty_has_an_owner_a_clock_and_a_check.sql';
const FILES = ['scripts/sql/customer_support_activates_wins_back_and_settles_disputes.sql',
               'scripts/sql/the_accountant_watches_for_fee_circumvention_and_rescreens_sanctions.sql'];
// the dispute finding moved to the sales_engineer; replayed while it is pending
const REVEAL = 'scripts/sql/reveal_follow_up_and_dispute_findings_belong_to_the_sales_engineer.sql';
const MANIFEST = read('scripts/sql/MANIFEST.txt').split(/\r?\n/);
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));

test('static: revokes, search_path, RLS + policy, duties defined, choices validated, pending XOR MANIFEST', () => {
  for (const f of FILES) {
    const src = code(read(f));
    assert.ok(!/^\s*(begin|commit)\s*;/im.test(src), `${f}: carries its own transaction control`);
    const made = [...src.matchAll(/create or replace function public\.(\w+)\(/g)].map((m) => m[1]);
    assert.ok(made.length > 0, `${f}: defines no routine`);
    for (const name of made) {
      const head = src.slice(src.indexOf(`function public.${name}(`)).split('$')[0];
      assert.match(head, /security definer\s+set search_path to 'public', 'pg_temp'/, `${f}: ${name} is not security definer with a pinned search_path`);
      assert.match(src, new RegExp(`revoke execute on function public\\.${name}\\([^)]*\\) from public, anon, authenticated;`), `${f}: ${name} is not revoked`);
      if (name.startsWith('fn_reason_apply_')) {
        const body = src.slice(src.indexOf(`function public.${name}(`)).split('$fn$;')[0];
        // a non-answer must RAISE: fn_reason_held_resolve marks a row applied whenever its apply returns, even null
        assert.match(body, /raise exception 'CHOICE_NOT_AN_OPTION/, `${f}: ${name} does not raise on a choice outside the options`);
      }
    }
    for (const [, t] of src.matchAll(/create table if not exists public\.(\w+)/g)) {
      assert.match(src, new RegExp(`alter table public\\.${t} enable row level security`), `${f}: ${t} has no RLS`);
      assert.match(src, new RegExp(`create policy ${t}_service_role_only on public\\.${t}[\\s\\S]{0,80}using \\(false\\) with check \\(false\\)`), `${f}: ${t} has no service-role-only policy`);
      assert.match(src, new RegExp(`revoke all on public\\.${t} from anon, authenticated`), `${f}: ${t} is not revoked`);
    }
    const duties = [...src.matchAll(/\('(\w+\.\w+)', '(\w+)', interval '[^']+', '(fn_\w+)'/g)];
    assert.ok(duties.length >= 2, `${f}: registers fewer than two seat duties`);
    for (const [, duty, seat, fn] of duties) {
      assert.equal(duty.split('.')[0], seat, `${f}: ${duty} is not owned by its own seat`);
      assert.ok(made.includes(fn), `${f}: ${duty} runs ${fn}, which the file does not define`);
    }
    assert.match(src, /insert into public\.seat_handoff_kind[\s\S]{0,200}'deliberation\.review', '\w+', 'ceo'/, `${f}: its seat-to-seat judgement has no registered cross-family review pair`);
    assert.ok(pending(f) !== MANIFEST.includes(f), `${f}: exactly one of a pending note and a MANIFEST line`);
  }
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: every duty acts on ZZ DEMO fixtures, once', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const replay = [FRAME, ...FILES, REVEAL].filter(pending).map(read).join('\n');
  let o;
  try { await sql(replay + '\n' + PROBE, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  // 24 Sep 2026: the dispute clock moved to the sales_engineer (reveal_follow_up_and_dispute_findings_belong_to_the_sales_engineer.sql)
  for (const duty of ['accountant.fraud_watch', 'accountant.sanctions_rescreen', 'customer_support.activation',
    'sales_engineer.disputes', 'customer_support.winback']) assert.ok(o.duties.includes(duty), `${duty} is not registered on its clock`);
  assert.ok(!o.duties.includes('customer_support.disputes'), 'customer_support still holds the dispute clock');
  assert.deepEqual(o.act1, { first_request: 1, no_quote: 1, stalled_filed: 1 }, 'activation did not act');
  assert.deepEqual(o.act2, { first_request: 0, no_quote: 0, stalled_filed: 0 }, 'activation acted twice');
  assert.deepEqual(o.stalled_held, { seat: 'customer_support', stakes: 'high', status: 'held' }, 'the stalled case is not a reasoned question');
  assert.equal(o.stalled, 'applied', 'the reasoned answer on a stalled request was not applied');
  assert.equal(o.bad_choice, false, 'a choice outside the options was applied');
  assert.deepEqual([o.wb1.written, o.wb2.written], [1, 0], 'win-back did not write exactly once');
  assert.deepEqual(o.fr1, { duplicates_flagged: 2, signals_flagged: 1, reasoning_filed: 1 }, 'fraud watch did not flag');
  assert.deepEqual(o.fr2, { duplicates_flagged: 0, signals_flagged: 0, reasoning_filed: 0 }, 'fraud watch flagged twice');
  assert.deepEqual(o.flags, ['dup_customer_phone/open', 'duplicate_license/open', 'silent_after_reveal/open']);
  assert.equal(o.circ, true, 'a circumvention verdict opened no cross-family deliberation');
  assert.equal(o.flag_status, 'escalated');
  assert.deepEqual(o.hit, ['owner'], 'the re-screen did not hit the listed signatory');
  assert.equal(o.intake, true, 'a reasoned dispute did not open a case');
  assert.deepEqual([o.dt1.to_review, o.dt2.to_review], [1, 0], 'evidence did not close into review exactly once');
  assert.equal(o.fault, true, 'the finding reached the CEO without a cross-family deliberation');
  assert.equal(o.stage_after_fault, 'ceo_decision');
  assert.deepEqual([o.dt3.decision_overdue, o.overdue_open, o.overdue_after], [1, 1, 0], 'an overdue CEO decision is not a finding that closes on decision');
  assert.equal(o.stage, 'decided');
  assert.deepEqual(o.msgs, ['activation.first_request/queued', 'activation.no_quote/queued', 'activation.stalled/queued',
    'dispute.decided/queued', 'dispute.decided/queued', 'dispute.opened/queued', 'dispute.opened/queued', 'winback.dormant/queued'],
    'a message was not queued through the door, or was queued twice');
  assert.ok(o.notes.includes('duty_activation_no_quote/ar'), 'an Arabic-locale customer was not written to in Arabic');
});

const PROBE = String.raw`
do $$ declare o jsonb := '{}'; ca uuid; cb uuid; cc uuid; l1 bigint; l2 bigint; i1 uuid; i2 uuid; q2 uuid; t2 uuid; h bigint; hf bigint; d bigint; ent text;
  m text := '{"status":"answered","answer":"x","model":"qwen/qwen3.7-plus","decision":{"choice":"%s"}}';
begin
  perform set_config('qd.duty_fixtures', 'on', true);
  -- inside this aborted transaction only: let the door queue mail to the fixture domain so the effect is countable
  delete from email_domain_mx where domain = 'example.invalid';
  update email_block_pattern set active = false where 'zz.duty.a@example.invalid' ~ pattern;
  insert into customers (full_name, email, created_at) values ('ZZ DEMO A', 'zz.duty.a@example.invalid', now() - interval '4 days') returning id into ca;
  insert into customers (full_name, email, phone, created_at, locale) values ('ZZ DEMO B', 'zz.duty.b@example.invalid', '+971500009991', now() - interval '20 days', 'ar') returning id into cb;
  insert into customers (full_name, email, phone, created_at) values ('ZZ DEMO C', 'zz.duty.c@example.invalid', '0500009991', now() - interval '200 days') returning id into cc;
  select name into ent from screening_entry where run_id = (select max(id) from screening_run where status = 'ok' and source = 'un_consolidated')
     and name ~ '^[A-Za-z]+ [A-Za-z]+ [A-Za-z]+$' limit 1;
  insert into leads (company_name, email, lifecycle_stage, trade_license_no, signatory_name)
    values ('ZZ DEMO — Duty Supplier One', 'zz.duty.s1@example.invalid', 'registered', 'ZZ-123456', ent) returning id into l1;
  insert into leads (company_name, email, lifecycle_stage, trade_license_no)
    values ('ZZ DEMO — Duty Supplier Two', 'zz.duty.s2@example.invalid', 'registered', 'zz 123456') returning id into l2;
  insert into inquiries (customer_id, category, status, created_at, raw_input) values (cb, 'flooring', 'quoted', now() - interval '11 days', 'ZZ DEMO floor') returning id into i1;
  insert into inquiries (customer_id, category, status, created_at, raw_input) values (cc, 'flooring', 'revealed', now() - interval '80 days', 'ZZ DEMO floor 2') returning id into i2;
  insert into quotes (inquiry_id, supplier_id, quote_amount, status) values (i2, l1, 1000, 'revealed') returning id into q2;
  insert into transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, fee_status, revealed_at)
    values (q2, i2, l1, cc, 1000, 'paid', now() - interval '70 days') returning id into t2;

  o := o || jsonb_build_object('act1', fn_customer_support_activation_tick());
  o := o || jsonb_build_object('act2', fn_customer_support_activation_tick());
  o := o || jsonb_build_object('wb1', fn_customer_support_winback_tick());
  o := o || jsonb_build_object('wb2', fn_customer_support_winback_tick());
  o := o || jsonb_build_object('fr1', fn_accountant_fraud_watch_tick());
  o := o || jsonb_build_object('fr2', fn_accountant_fraud_watch_tick());
  o := o || jsonb_build_object('flags', (select jsonb_agg(kind || '/' || status order by kind) from fraud_flags where detail->>'raised_by' = 'accountant'));
  o := o || jsonb_build_object('sx', fn_accountant_sanctions_rescreen() - 'sources' - 'oldest_list' - 'runs');
  o := o || jsonb_build_object('hit', (select jsonb_agg(field) from supplier_screening_hit where lead_id in (l1, l2)));

  select id into h from reasoning_held_question where dedupe_key = 'stalled_request:' || i1;
  o := o || jsonb_build_object('stalled_held', (select jsonb_build_object('seat', seat, 'stakes', request->>'stakes', 'status', status) from reasoning_held_question where id = h));
  o := o || jsonb_build_object('stalled', fn_reason_held_resolve(h, format(m, 'add_details')::jsonb)->'status');
  begin
    perform fn_reason_apply_customer_support__stalled_request(h, format(m, 'nonsense')::jsonb);
    o := o || jsonb_build_object('bad_choice', true);
  exception when others then o := o || jsonb_build_object('bad_choice', sqlerrm not like 'CHOICE_NOT_AN_OPTION%'); end;

  select id into h from reasoning_held_question where dedupe_key = 'circumvention:silent_after_reveal:' || t2;
  o := o || jsonb_build_object('circ', fn_reason_held_resolve(h, format(m, 'circumvention')::jsonb)->'effect'->'review'->'deliberation_id' is not null);
  o := o || jsonb_build_object('flag_status', (select status from fraud_flags where kind = 'silent_after_reveal' and subject_id = t2::text));

  h := fn_customer_support_dispute_consider(t2, 'customer', 'ZZ DEMO the tiles were never laid');
  o := o || jsonb_build_object('intake', fn_reason_held_resolve(h, format(m, 'dispute')::jsonb)->'effect'->'opened');
  select id into d from post_reveal_dispute where transaction_id = t2;
  perform fn_customer_support_dispute_evidence(d, 'supplier', '{"text":"ZZ DEMO we laid them"}');
  o := o || jsonb_build_object('dt1', fn_sales_engineer_disputes_tick());
  o := o || jsonb_build_object('dt2', fn_sales_engineer_disputes_tick());
  select fault_question_id into hf from post_reveal_dispute where id = d;
  o := o || jsonb_build_object('fault', fn_reason_held_resolve(hf, format(m, 'supplier_upheld')::jsonb)->'effect'->'review'->'deliberation_id' is not null);
  o := o || jsonb_build_object('stage_after_fault', (select stage from post_reveal_dispute where id = d));
  update post_reveal_dispute set decision_due = now() - interval '1 minute' where id = d;
  o := o || jsonb_build_object('dt3', fn_sales_engineer_disputes_tick());
  o := o || jsonb_build_object('overdue_open', (select count(*) from it_engineer_finding where issue_key = 'dispute_decision_overdue:' || d and closed_at is null));
  perform fn_ceo_decides_post_reveal_dispute(d, 'supplier_upheld', 'ZZ DEMO');
  o := o || jsonb_build_object('stage', (select stage from post_reveal_dispute where id = d),
     'overdue_after', (select count(*) from it_engineer_finding where issue_key = 'dispute_decision_overdue:' || d and closed_at is null));
  o := o || jsonb_build_object('msgs', (select jsonb_agg(stage || '/' || outcome order by stage, subject_key) from customer_support_duty_message
                                       -- only this probe's subjects: a ZZ DEMO customer left in production by another run is selected too
                                       where customer_id in (ca, cb, cc) or lead_id in (l1, l2)));
  o := o || jsonb_build_object('notes', (select jsonb_agg(type || '/' || coalesce(lang, '?') order by type, lang) from notifications where to_email like 'zz.duty.%'));
  o := o || jsonb_build_object('duties', (select jsonb_agg(duty order by duty) from seat_duty where duty in ('accountant.fraud_watch', 'accountant.sanctions_rescreen', 'customer_support.activation', 'customer_support.disputes', 'sales_engineer.disputes', 'customer_support.winback')));
  raise exception 'CHK<<%>>', o::text;
end $$;
`;
