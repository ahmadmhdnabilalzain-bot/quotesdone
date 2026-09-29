// THE CEO'S JOB-DESCRIPTION GAPS ARE CLOSED (24 Sep 2026, ceo; seat audit GAPS.md, CEO section; ledger 983).
//
// WHAT FAILS IF THE CAUSE RETURNS.
//   * static: a routine of these files is unpinned or unrevoked, a table has no policy, a duty is registered to
//     another seat, a file carries both a pending note and a MANIFEST line (or neither), a routine other than the
//     sales escalation calls a model, a routine decides by matching words, or the report door (fn_ceo_decide_report)
//     can again return with a report still 'sent';
//   * production, in ONE aborted transaction (the pending files replayed in their apply order first, the founder
//     path stubbed, fixtures ZZ DEMO / example.invalid): a report of a family nobody coded stays unanswered; a
//     heartbeat alarm closes without the daily check having run, or stays open after it ran; the daily backup
//     confirmation is left 'sent'; any report is still 'sent' after the CEO's hourly sweep; the binding constraint
//     opens no improvement, or opens it twice; the launch gate is missing a trade, decides before December, tells the
//     founder twice; the board pack drops the runway, the supply or the gate; a late marketing plan is not chased, or
//     is not released when the plan arrives; the quarterly audit misses a seat or runs twice; a sales escalation has
//     no door, is not reasoned, or its answer does not close the handoff; an unknown escalation is silently accepted.
//
//   node --test scripts/checks/the_ceo_job_description_gaps_are_closed.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { manifestHas } from '../lib/pending_sql.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
// in their apply order (each pending note says what it needs first)
const FILES = [
  'scripts/sql/the_ceo_answers_every_report_it_is_sent_the_day_it_arrives.sql',
  'scripts/sql/the_ceo_turns_the_binding_constraint_into_an_improvement_every_week.sql',
  'scripts/sql/the_ceo_decides_whether_january_holds_on_supply_coverage.sql',
  'scripts/sql/the_ceo_monthly_report_is_a_board_pack.sql',
  'scripts/sql/the_ceo_holds_the_marketing_seat_to_its_month_plan_date.sql',
  'scripts/sql/the_ceo_audits_every_seat_each_quarter.sql',
  'scripts/sql/the_sales_engineer_can_escalate_a_decision_to_the_ceo.sql',
];
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));
const code = (p) => read(p).split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const bodyOf = (src, name) => src.slice(src.indexOf(`function public.${name}(`)).split('$fn$')[1] ?? '';

test('static: pinned, revoked, policed, owned, and pending XOR MANIFEST', () => {
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/);
  for (const f of FILES) {
    const src = code(f);
    const made = [...new Set([...src.matchAll(/create or replace function public\.(\w+)\(/g)].map((m) => m[1]))];
    assert.ok(made.length >= 1, `${f} defines no routine`);
    for (const name of made) {
      const head = src.slice(src.indexOf(`function public.${name}(`)).split('$fn$')[0];
      assert.match(head, /set search_path to 'public', 'pg_temp'/, `${name} has no pinned search_path`);
      assert.match(head, /security definer/, `${name} is not security definer`);
      assert.match(src, new RegExp(`revoke execute on function public\\.${name}\\([^)]*\\) from public, anon, authenticated;`), `${name} is not revoked`);
      const body = bodyOf(src, name);
      // routine work is code: only the sales escalation hands a judgement to think()
      if (name !== 'fn_ceo_takes_sales_escalation') {
        assert.ok(!/fn_seat_duty_reason|fn_reason_hold|fn_seat_duty_cross_review/.test(body), `${name} calls a model; routine work is code`);
      }
      // no decision by matching words (instruction 890): no regex on text, no position() of a pattern
      assert.ok(!/~\*|position\s*\(/.test(body), `${name} matches words`);
    }
    for (const t of [...src.matchAll(/create table if not exists public\.(\w+)/g)].map((m) => m[1])) {
      assert.match(src, new RegExp(`alter table public\\.${t} enable row level security`), `${t} has no RLS`);
      assert.match(src, new RegExp(`create policy ${t}_service_role_only on public\\.${t}[^;]*using \\(false\\) with check \\(false\\)`), `${t} has no policy`);
      assert.match(src, new RegExp(`revoke all on public\\.${t} from anon, authenticated`), `${t} is not revoked`);
    }
    for (const [, prefix, owner] of src.matchAll(/\('(\w+)\.\w+', '(\w+)', interval/g)) assert.equal(prefix, owner, `duty ${prefix} registered to ${owner}`);
    assert.ok(pending(f) !== manifestHas(f), `${f}: exactly one of a pending note and a MANIFEST line`);
  }
  // the report door never returns with a report still 'sent'
  const door = bodyOf(code(FILES[0]), 'fn_ceo_decide_report');
  assert.match(door, /status = 'sent'\)\s+and coalesce\(v ->> 'reason', ''\) not like 'undecided%' then\s+v := public\.fn_ceo_report_default_decide/,
    'fn_ceo_decide_report has no fallback for an unanswered report, or it waves through a founder alert its decider left undecided');
  for (const fam of ['backup_escalation', 'dropbox_backup_escalation', 'delivery_undelivered', 'it_backup_heartbeat', 'dropbox_backup_daily']) {
    assert.match(door, new RegExp(`when '${fam}'`), `the door lost the ${fam} family`);
  }
  // the board pack carries the whole month report of #923, not a shortened copy
  const pack = read(FILES[3]);
  for (const line of ['1. close last month\'s directives', '2. the founder\'s monthly report', '3. this month\'s directive per seat']) {
    assert.ok(pack.includes(line), `fn_ceo_month_plan lost: ${line}`);
  }
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token';

async function probe(block) {
  const { sql } = await import('../lib/db.mjs');
  try { await sql(FILES.filter(pending).map(read).join('\n') + '\n' + block, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(-1500));
    return JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.fail('the probe committed instead of rolling back');
}

test('production, aborted: every CEO gap acts', { skip: SKIP }, async () => {
  const o = await probe(String.raw`
do $$ declare o jsonb := '{}'; v jsonb; hb bigint; unk bigint; dl bigint; hid bigint; bad bigint; held bigint; imp bigint; begin
  perform set_config('app.qd_stub_founder_notify', 'on', true);

  -- GAP 1: a heartbeat alarm, a family nobody coded, a daily confirmation (ZZ DEMO)
  insert into public.support_ceo_report (idempotency_key, source_agent, severity, subject, verified_evidence, attempted_actions, requested_outcome, owner_role_id, next_review_at, status, created_at)
  values ('it_backup_heartbeat:zz-demo', 'it_engineer', 'serious', 'ZZ DEMO heartbeat', '{"zz":"demo"}', '[]', 'ZZ DEMO repair the chain', 'it_engineer', now() - interval '1 hour', 'sent', now() + interval '1 second') returning id into hb;
  insert into public.support_ceo_report (idempotency_key, source_agent, severity, subject, verified_evidence, attempted_actions, requested_outcome, owner_role_id, next_review_at, status)
  values ('zz_demo_family:1', 'it_engineer', 'elevated', 'ZZ DEMO unknown family', '{"zz":"demo"}', '[]', 'ZZ DEMO do the thing', 'it_engineer', now() + interval '1 day', 'sent') returning id into unk;
  v := public.fn_ceo_report_answer_sweep();
  o := o || jsonb_build_object('sweep', jsonb_build_object('s', (select count(*) from public.support_ceo_report where status = 'sent' and idempotency_key not like 'delivery_undelivered:%'), 'f', v->'failed'),
    'hb', (select jsonb_build_object('status', status, 'owner', owner_role_id, 'review_h', round(extract(epoch from next_review_at - now()) / 3600)) from public.support_ceo_report where id = hb),
    'unk', (select jsonb_build_object('status', status, 'owner', owner_role_id, 'receipt', acceptance_receipt like 'ceo: accepted%', 'review_h', round(extract(epoch from next_review_at - now()) / 3600)) from public.support_ceo_report where id = unk));
  insert into public.support_ceo_report (idempotency_key, source_agent, severity, subject, verified_evidence, attempted_actions, requested_outcome, owner_role_id, next_review_at, status, created_at)
  values ('dropbox_backup_daily:zz-demo', 'it_engineer', 'elevated', 'ZZ DEMO daily', '{"zz":"demo"}', '[]', 'NOTHING IS REQUESTED', 'it_engineer', now() + interval '1 day', 'sent', now() + interval '2 seconds') returning id into dl;
  v := public.fn_ceo_report_answer_sweep();
  o := o || jsonb_build_object('sweep2', jsonb_build_object('s', (select count(*) from public.support_ceo_report where status = 'sent' and idempotency_key not like 'delivery_undelivered:%')),
    'hb_after', (select status from public.support_ceo_report where id = hb),
    'daily', (select status from public.support_ceo_report where id = dl));

  -- GAP 2: the binding constraint becomes one improvement, once
  -- A live improvement for today's constraint makes the first call answer "proposed already" (29 Sep 2026:
  -- #4411, invitations:2026-09-22:L1), which proves only the second half. Its key is moved aside inside this
  -- rolled-back transaction so the first call must open one again and the second must refuse it.
  update public.ceo_improvement set source_ref = source_ref || ':zz-demo-aside'
   where source_kind = 'binding_constraint' and status in ('open', 'assigned');
  v := public.fn_ceo_constraint_lever();
  o := o || jsonb_build_object('lever', jsonb_build_object('proposed', v->'proposed', 'stage', v->'stage'), 'lever_again', public.fn_ceo_constraint_lever()->'proposed',
    'lever_row', (select jsonb_build_object('seat', seat, 'status', status, 'handoff', (select status from public.agent_actions where id = i.handoff_id), 'has_due', proposal like '%Due:%')
                    from public.ceo_improvement i where i.id = (v->>'proposed')::bigint));

  -- GAP 3: the gate; no decision in September, a decision in December told once
  v := public.fn_ceo_launch_readiness(now());
  o := o || jsonb_build_object('gate_now', jsonb_build_object('trades_total', v->'trades_total', 'decision', v->'decision', 'verdict', v->'verdict'),
    'trades_active', (select count(*) from public.taxonomy_trade where active));
  v := public.fn_ceo_launch_readiness(timestamptz '2026-12-07 10:00+04');
  -- after the launch window, the first run of a quarter decides, whatever the weekday; the next week does not
  -- (one statement each: a subquery does not see what a function in the same statement wrote)
  o := o || jsonb_build_object('gate_apr', public.fn_ceo_launch_readiness(timestamptz '2027-04-08 10:00+04')->'decision');
  perform public.fn_ceo_launch_readiness(timestamptz '2027-04-08 11:00+04');
  o := o || jsonb_build_object('gate_apr_rerun_keeps', (select decision from public.ceo_launch_gate where week = date '2027-04-05') is not null);
  o := o || jsonb_build_object('gate_apr_next', public.fn_ceo_launch_readiness(timestamptz '2027-04-15 10:00+04')->'decision');
  o := o || jsonb_build_object('gate_dec', jsonb_build_object('decision', v->'decision', 'founder_notice', v->'founder_notice'), 'gate_dec_again', public.fn_ceo_launch_readiness(timestamptz '2026-12-08 10:00+04')->'founder_notice');

  -- GAP 4: the board pack for August (the accountant closed it)
  v := public.fn_ceo_board_pack(date '2026-08-01');
  o := o || jsonb_build_object('pack', jsonb_build_object('runway', v->'cash_position'->'runway'->'months', 'has_supply', v->'supply' ? 'by_emirate',
    'seats', (select count(*) from jsonb_object_keys(v->'seats')), 'gate', v->'launch_gate' is not null and v->>'launch_gate' <> 'null',
    'text_runway', position('Runway' in v->>'text') > 0, 'text_gate', position('Customer launch gate' in v->>'text') > 0));

  -- GAP 5: a late November plan is chased, then released when the plan arrives
  v := public.fn_ceo_marketing_plan_watch(timestamptz '2026-10-27 10:00+04');
  imp := (v->>'improvement')::bigint;
  o := o || jsonb_build_object('mkt_late', jsonb_build_object('late', v->'late'), 'mkt_imp_seat', (select seat from public.ceo_improvement where id = imp));
  insert into public.marketing_month_plan (month, status) values (date '2026-11-01', 'with_ceo')
  on conflict (month) do update set status = 'with_ceo';
  v := public.fn_ceo_marketing_plan_watch(timestamptz '2026-10-28 10:00+04');
  o := o || jsonb_build_object('mkt_after', jsonb_build_object('late', v->'late'), 'mkt_imp_status', (select status from public.ceo_improvement where id = imp));

  -- GAP 7: the quarterly audit, every seat but the CEO, once
  v := public.fn_ceo_seat_audit(now());
  o := o || jsonb_build_object('audit_again', public.fn_ceo_seat_audit(now())->'already',
    'audit_seats', (select jsonb_agg(seat order by seat) from public.ceo_seat_audit where quarter = date_trunc('quarter', now() at time zone 'Asia/Dubai')::date));

  -- GAP 8: the sales engineer's door to the CEO
  hid := public.fn_seat_handoff('sales_engineer', 'ceo', 'sales.escalation', 'inquiries', 'zz-demo-thin',
    jsonb_build_object('escalation', 'thin_supply', 'case', jsonb_build_object('customer', 'ZZ DEMO customer', 'email', 'zz@example.invalid', 'trade', 'zz-demo', 'matchable', 1)));
  held := (select (evidence->>'held_question')::bigint from public.agent_actions where id = hid);
  o := o || jsonb_build_object('esc_status', (select status from public.agent_actions where id = hid), 'esc_held', held is not null,
    'esc_surface', (select surface from public.reasoning_held_question where id = held));
  -- the answer says why: a reasonless CEO decision is refused since 29 Sep 2026 (founder_instruction 1059)
  v := public.fn_reason_apply_ceo__sales_escalation(held, '{"decision":{"choice":"send_to_matched"},"answer":"ZZ DEMO reasoning: the one exact-trade supplier can serve it, so it goes now","model":"zz-demo"}');
  o := o || jsonb_build_object('esc_done', (select jsonb_build_object('status', status, 'choice', evidence->>'choice') from public.agent_actions where id = hid));
  bad := public.fn_seat_handoff('sales_engineer', 'ceo', 'sales.escalation', 'inquiries', 'zz-demo-bad', '{"escalation":"zz_demo_nonsense"}');
  o := o || jsonb_build_object('esc_bad', (select status from public.agent_actions where id = bad));
  raise exception 'CHK<<%>>', o::text;
end $$;`);

  // GAP 1
  assert.deepEqual(o.hb, { status: 'accepted', owner: 'it_engineer', review_h: 24 }, 'a heartbeat alarm with no daily report since was not accepted and owned');
  assert.equal(o.unk.status, 'accepted', 'a report of a family nobody coded was left unanswered');
  assert.equal(o.unk.receipt, true); assert.equal(o.unk.review_h, 24);
  assert.equal(o.sweep.s, 0, 'a report (other than an undecided founder-alert delivery) is still sent after the CEO\'s sweep: ' + JSON.stringify(o.sweep));
  assert.equal(o.sweep.f, 0, 'a decider raised: ' + JSON.stringify(o.sweep));
  assert.equal(o.daily, 'completed', 'the daily confirmation was left open');
  assert.equal(o.hb_after, 'completed', 'the heartbeat stayed open after the daily check ran again');
  assert.equal(o.sweep2.s, 0);
  // GAP 2
  assert.ok(o.lever.proposed || o.lever.stage === 'on_plan', 'the binding constraint opened no improvement: ' + JSON.stringify(o.lever));
  assert.equal(o.lever_again, null, 'the same constraint was proposed twice');
  if (o.lever.proposed) {
    assert.equal(o.lever_row.status, 'assigned'); assert.equal(o.lever_row.has_due, true, 'the idea carries no date');
    assert.ok(['pending', 'done'].includes(o.lever_row.handoff), 'the owner seat was not handed the improvement: ' + o.lever_row.handoff);
  }
  // GAP 3
  assert.equal(o.gate_now.trades_total, o.trades_active, 'the gate does not count every active trade');
  assert.equal(o.gate_now.decision, null, 'the gate decided January in September');
  assert.ok(['not_ready', 'ready', 'not_measurable'].includes(o.gate_now.verdict));
  assert.equal(o.gate_dec.decision === 'launch_waits' || o.gate_dec.decision === 'january_holds', true);
  assert.ok(o.gate_dec.founder_notice, 'the founder was not told the December decision');
  assert.equal(o.gate_dec_again, null, 'the founder was told the same decision twice in a week');
  assert.ok(['launch_waits', 'january_holds'].includes(o.gate_apr), 'the first run of a quarter took no decision');
  assert.equal(o.gate_apr_rerun_keeps, true, 'a rerun in the same week erased the decision');
  assert.equal(o.gate_apr_next, null, 'the quarter was decided twice');
  // GAP 4
  assert.equal(o.pack.runway, 0.3, 'the board pack does not quote the accountant\'s August runway');
  assert.equal(o.pack.has_supply, true); assert.ok(o.pack.seats >= 5, 'the pack misses seats');
  assert.equal(o.pack.gate, true); assert.equal(o.pack.text_runway, true); assert.equal(o.pack.text_gate, true);
  // GAP 5
  assert.equal(o.mkt_late.late, true, 'a plan past its deadline was not late'); assert.equal(o.mkt_imp_seat, 'marketing');
  assert.equal(o.mkt_after.late, false); assert.equal(o.mkt_imp_status, 'done', 'the chase was not closed when the plan arrived');
  // GAP 7
  assert.deepEqual(o.audit_seats, ['accountant', 'customer_support', 'it_engineer', 'marketing', 'sales_engineer'], 'the audit missed a seat');
  assert.equal(o.audit_again, true, 'the audit ran twice in a quarter');
  // GAP 8
  assert.equal(o.esc_status, 'pending', 'the escalation did not wait for the CEO\'s answer');
  assert.equal(o.esc_held, true); assert.equal(o.esc_surface, 'ceo.sales_escalation');
  assert.deepEqual(o.esc_done, { status: 'done', choice: 'send_to_matched' }, 'the CEO\'s answer did not close the handoff');
  assert.equal(o.esc_bad, 'failed', 'an unknown escalation was accepted silently');
});
