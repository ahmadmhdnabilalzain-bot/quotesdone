// THE CEO WEEKLY REVIEW AND THE SEATS' MONTHLY SELF-REVIEW ACT (29 Sep 2026, ceo; founder instruction 1009).
//
// What fails if the causes come back:
//   * the review stops going through fn_notify_founder with its own kind, or grows a model call  -> static
//   * an improvement is opened without a due date or a closing check                            -> static
//   * the heartbeat step or a seat's self-review duty is dropped                                -> static
//   * a routine loses its revoke or its pinned search_path                                      -> static
//   * the behaviour itself (open, close, escalate, deliver; grade, trend, slip, close)          -> the two probes,
//     rolled back on production, each answering one PROBE OK verdict row (run once the files are applied).
//
//   node --test scripts/checks/the_ceo_review_and_the_seat_self_review_act.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const WEEKLY = R('scripts/sql/the_ceo_weekly_review_acts_on_every_missed_target.sql');
const MONTHLY = R('scripts/sql/every_seat_reviews_itself_every_month.sql');
const PING = R('supabase/functions/resilience_ping/index.ts');
const applied = (f) => R('scripts/sql/MANIFEST.txt').split('\n').some((l) => l.trim() === `scripts/sql/${f}.sql`);

test('the weekly review is delivered through fn_notify_founder with kind ceo_weekly_review, at level info, by code', () => {
  assert.match(WEEKLY, /public\.fn_notify_founder\(p_event => v_event,[\s\S]{0,400}p_level => 'info', p_kind => 'ceo_weekly_review'/, 'delivery does not call fn_notify_founder(…, p_level => info, p_kind => ceo_weekly_review)');
  assert.match(WEEKLY, /insert into public\.founder_mail_policy[\s\S]{0,120}'ceo_weekly_review', true/, 'the kind is not allowed in founder_mail_policy');
  assert.doesNotMatch(WEEKLY + MONTHLY, /fn_seat_duty_reason\(|ai_gateway|think\(/, 'a review now calls a model');
});

test('every improvement the two reviews open carries a due date and a closing check', () => {
  assert.match(WEEKLY, /set due_on = p_week \+ 7, close_check = t->>'close_check' where id = v_id/);
  assert.match(MONTHLY, /set due_on = \(v_m \+ interval '1 month'\)::date \+ 4,\s*close_check =/);
  assert.match(WEEKLY, /escalations = escalations \+ 1[\s\S]{0,120}due_on = v_today \+ 7/, 'a missed action is not escalated a week on');
});

test('the review runs on the heartbeat and every seat has its self-review duty', () => {
  assert.match(PING, /ceoWeeklyReview:\s*\{\s*run:\s*ceoWeeklyReviewTick\s*\}/);
  assert.match(PING, /rpc\('fn_ceo_weekly_review_tick'\)[\s\S]{0,400}'fn_ceo_weekly_review_attach_pdf'/);
  assert.match(WEEKLY, /insert into public\.resilience_step[\s\S]{0,120}'ceoWeeklyReview'/);
  for (const s of ['accountant', 'ceo', 'customer_support', 'it_engineer', 'marketing', 'sales_engineer']) {
    assert.match(MONTHLY, new RegExp(`create or replace function public\\.fn_${s}_self_review\\(\\)`), `${s} has no self-review door`);
    assert.match(MONTHLY, new RegExp(`'${s}'`), `${s} is not in the duty list`);
  }
});

test('every routine the two files create is revoked and pins its search_path', () => {
  for (const src of [WEEKLY, MONTHLY]) {
    for (const m of src.matchAll(/create or replace function public\.(\w+)\(/g)) {
      assert.match(src, new RegExp(`revoke execute on function public\\.${m[1]}\\([^)]*\\) from public, anon, authenticated`), `${m[1]} is not revoked`);
      const head = src.slice(m.index, src.indexOf('$fn$', m.index));
      assert.match(head, /set search_path to 'public', 'pg_temp'/, `${m[1]} has no pinned search_path`);
    }
  }
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
for (const f of ['the_ceo_weekly_review_acts_on_every_missed_target', 'every_seat_reviews_itself_every_month']) {
  const skip = !hasToken ? 'no Supabase management token' : !applied(f) ? `${f}.sql is not applied yet (pending)` : false;
  test(`${f}: the rolled-back rehearsal answers PROBE OK`, { skip }, async () => {
    const { sql } = await import('../lib/db.mjs');
    // while the sweep fix (fn_ceo_weekly_review reports 'carried') is pending, it is replayed inside the probe's own
    // transaction, which then rolls back instead of committing
    const FIX = 'the_ceo_improvement_sweep_closes_before_it_proposes_and_settles_in_one_run';
    let body = R(`scripts/sql/${f}_probe.sql`);
    if (f === 'the_ceo_weekly_review_acts_on_every_missed_target' && !applied(FIX)) {
      body = body.replace(/^begin;$/m, () => 'begin;\n' + R(`scripts/sql/${FIX}.sql`)).replace(/^commit;\s*$/m, 'rollback;');
      assert.match(body, /^rollback;/m, 'the replayed fix would commit');
    }
    const r = await sql(body, { retry: false });
    const verdict = Array.isArray(r) && r[0] ? String(r[0].verdict) : JSON.stringify(r).slice(0, 500);
    assert.match(verdict, /^PROBE OK/, verdict);
  });
}
