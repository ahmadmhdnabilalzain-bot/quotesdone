// THE SUPPLIER FUNNEL RUNS ITSELF (15 Nov 2026; sales_engineer + marketing + ceo; founder rulings 1696/1701/1705/1706).
//
// Text checks over the four files of 15 Nov and the copy variants (no database; the probes run the rules on a local Postgres):
//   * the bounce brake judges by kind, provider class, segment and the Wilson lower bound; the old 3-day single-number rule is
//     gone from the batch, the nudges and the ramp; every brake and restart is recorded; the CEO restarts within a limit held
//     as data (append-only, a change waits a day) and never over a complaint;
//   * the ramp steps up on the 14-day judgement, the copy test assigns deterministically and promotes a winner only past its
//     minimum sample, and the variants the database names are the variants send_outbox can write;
//   * a supplier reply owed an answer is put back to the MODEL's answerer (ruling 1339): the duty itself writes no reply;
//     the parked leads get one e-mail with a click-to-chat link, never a WhatsApp message, to the number the site publishes;
//   * the CEO, not the founder, accepts the month, approves a calendar and moves marketing_golive; the founder's emergency
//     stop is never written by the CEO.
//
//   node --test scripts/checks/the_supplier_funnel_runs_itself.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const NAMES = [
  'the_bounce_brake_judges_each_bounce_by_kind_provider_and_sample_and_the_ceo_restarts_within_a_limit',
  'the_invitation_ramps_on_measured_health_and_tests_its_copy',
  'every_interested_supplier_reply_is_answered_the_same_day_and_the_parked_get_one_last_note',
  'the_ceo_approves_the_marketing_month_publishes_articles_and_holds_the_marketing_switch',
];
const [BRAKE, RAMP, REPLY, MKT] = NAMES.map((n) => R(`scripts/sql/${n}.sql`));
const code = (s) => s.replace(/--[^\n]*/g, '');
/** The body of a routine as the file defines it, in either spelling (the generated live definitions keep pg_get_functiondef's). */
function body(src, fn) {
  const m = new RegExp(`create or replace function public\\.${fn}\\(`, 'i').exec(src);
  assert.ok(m, `${fn} is not defined`);
  const rest = src.slice(m.index);
  const end = rest.search(/\$(fn|function)\$;?\s*\n(?:\s*;)?\s*\n?revoke|\n\$function\$/i);
  return rest.slice(0, end > 0 ? end + 12 : 4000);
}

test('each file and its probe exist, wait for the apply as pending notes, and carry no MANIFEST line yet', () => {
  const manifest = R('scripts/sql/MANIFEST.txt');
  for (const n of NAMES) for (const f of [n, n + '_probe']) {
    assert.ok(existsSync(join(ROOT, `scripts/sql/${f}.sql`)), `${f}.sql is missing`);
    const note = join(ROOT, `scripts/sql/pending/${f}.txt`);
    assert.ok(existsSync(note) && readFileSync(note, 'utf8').trim().length > 40, `${f} has no pending note with its reason`);
    assert.ok(!manifest.split(/\r?\n/).includes(`scripts/sql/${f}.sql`), `${f} has a MANIFEST line before it is applied`);
  }
});

test('every routine is revoked from public, anon and authenticated and pins its search_path; every table is service-role only', () => {
  for (const [i, src] of [BRAKE, RAMP, REPLY, MKT].entries()) {
    for (const m of src.matchAll(/create or replace function public\.(\w+)\(([^)]*)\)/gi)) {
      const fn = m[1];
      assert.match(src, new RegExp(`revoke execute on function public\\.${fn}\\([^)]*\\) from public, anon, authenticated`), `${NAMES[i]}: ${fn} is not revoked`);
      assert.match(body(src, fn), /set search_path to 'public', 'pg_temp'/i, `${NAMES[i]}: ${fn} has no pinned search_path`);
    }
    for (const m of src.matchAll(/create table if not exists public\.(\w+)/g)) {
      const t = m[1];
      assert.match(src, new RegExp(`alter table public\\.${t} enable row level security`), `${t}: RLS`);
      assert.match(src, new RegExp(`create policy ${t}_service_role_only on public\\.${t}`), `${t}: no policy`);
      assert.match(src, new RegExp(`revoke all on public\\.${t} from anon, authenticated`), `${t}: not revoked`);
      assert.match(src, new RegExp(`\\('${t}', true,`), `${t}: not in table_export_registry`);
    }
    assert.match(src, /set local lock_timeout = '1500ms'/, `${NAMES[i]}: no lock_timeout`);
    assert.doesNotMatch(code(src), /\bcommit\b/i, `${NAMES[i]}: a COMMIT would make a rolled-back replay live`);
  }
  for (const n of NAMES) {
    const p = R(`scripts/sql/${n}_probe.sql`);
    assert.match(p, /raise exception 'CHK<<%>>'/, `${n}_probe does not always raise its verdict`);
    assert.match(p, /LOCAL only/, `${n}_probe does not say it is local only`);
    assert.doesNotMatch(code(p), /\bcommit\b/i);
  }
});

test('the brake judges by kind, provider class, segment and the Wilson lower bound; the 3-day single number is gone', () => {
  const judge = body(BRAKE, 'fn_invite_bounce_judgement');
  for (const k of ["'hard'", "'policy'", "'soft'", "'complaint'"]) assert.ok(BRAKE.includes(k), `no ${k} kind`);
  assert.match(judge, /fn_mail_provider_of_email/, 'the judgement does not split by provider class');
  assert.match(judge, /'checked' else 'unchecked'/, 'the judgement does not split by list segment');
  assert.match(body(BRAKE, 'fn_invite_judge_cell'), /fn_invite_wilson_lower/, 'a rate is judged without its lower bound');
  assert.match(BRAKE, /'hard_limit', 0\.03, 'hard_min', 2/, 'the hard-bounce limit is not data');
  // the old rule (>= 15 sends and over the rate, or 5 bounces in 3 days) is in no routine that sends or ramps any more
  for (const [src, fn] of [[RAMP, 'enqueue_supplier_invites'], [RAMP, 'fn_sales_engineer_nudges_invited_suppliers'], [RAMP, 'fn_sales_engineer_supplier_outreach_tick']]) {
    const b = code(body(src, fn));
    assert.doesNotMatch(b, /v_inv_recent >= 15|greatest\(5, ceil\(/, `${fn} still brakes on the 3-day single number`);
    assert.match(b, /fn_invite_(judge_and_brake|bounce_judgement)\(/, `${fn} does not read the judgement`);
  }
  assert.doesNotMatch(code(body(RAMP, 'fn_invite_ramp')), /too few to judge health; growth needs/, 'the ramp still waits for 20 sends in 48 hours');
  assert.match(body(BRAKE, 'fn_invite_same_day_brake'), /fn_invite_judge_and_brake\('invite_same_day_brake'\)/);
});

test('every brake, held class, restart and hold is recorded with its reason; the history cannot be rewritten', () => {
  assert.match(BRAKE, /decision text not null check \(decision in \('brake', 'class_held', 'restart', 'restart_refused', 'hold'\)\)/);
  assert.match(BRAKE, /reason text not null check \(length\(btrim\(reason\)\) >= 10\)/);
  assert.match(BRAKE, /trg_invite_brake_decision_is_history before update or delete/);
  for (const fn of ['fn_invite_judge_and_brake', 'fn_sales_engineer_restarts_invites_after_a_brake', 'fn_ceo_restarts_invites', 'fn_ceo_reviews_the_invite_brake']) {
    assert.match(body(BRAKE, fn), /insert into public\.invite_brake_decision/, `${fn} decides without a record`);
  }
});

test('the CEO restarts within a limit held as data, never over a complaint, never under 24 hours', () => {
  assert.match(BRAKE, /limit_key text not null check \(limit_key in \('ceo_invite_restarts_per_30d'\)\)/);
  assert.match(BRAKE, /new\.effective_at := now\(\) \+ interval '24 hours'/, 'a limit change does not wait a day');
  assert.match(BRAKE, /select 'ceo_invite_restarts_per_30d', 2,/, 'the seeded limit is not 2');
  const ceo = body(BRAKE, 'fn_ceo_restarts_invites');
  assert.match(ceo, /fn_growth_limit\('ceo_invite_restarts_per_30d'\)/);
  assert.match(ceo, /v_used >= v_limit/);
  assert.match(ceo, /never restarted over a complaint/);
  assert.match(ceo, /interval '24 hours'/);
  assert.match(ceo, /insert into public\.email_suppressions/, 'the CEO restarts before the bounced addresses are suppressed');
  assert.doesNotMatch(code(BRAKE), /invite_ceo_ceiling'?\s*(=|,)\s*'?[1-9]/, 'this file raises the old ceiling instead of using its own limit');
});

test('the ramp steps up only on the 14-day judgement, from the cap it is at, never above the ceiling', () => {
  const r = code(body(RAMP, 'fn_invite_ramp'));
  assert.match(r, /fn_invite_bounce_judgement\(now\(\)\)/);
  assert.match(r, /least\(v_ceiling, greatest\(v_cur \+ v_min_step, ceil\(v_cur \* v_growth\)::int\)\)/);
  assert.match(RAMP, /'grow_max_hard_rate', 0\.03, 'backoff_hard_lb', 0\.025, 'min_step', 2, 'new_class_cap', 3, 'nudge_share', 0\.5/);
  // the placement gate is untouched: Microsoft and Yahoo/AOL never open (founder instruction 1537)
  for (const s of [BRAKE, RAMP, REPLY]) assert.doesNotMatch(code(s), /create or replace function public\.fn_invite_placement_open_providers/);
});

test('the copy test: deterministic, fixed once, measured on engagement, promoted only past the minimum sample', () => {
  const v = body(RAMP, 'fn_invite_variant_for_lead');
  assert.match(v, /hashtext\('invite_variant:' \|\| p_lead_id::text\)/, 'the variant is not deterministic');
  assert.match(v, /invite_variant_assignment a where a\.lead_id = p_lead_id/, 'an assigned lead is not fixed');
  const d = body(RAMP, 'fn_marketing_decides_the_invite_copy');
  assert.match(d, /'min_sends'\)::int, 150/); assert.match(d, /'min_engaged'\)::int, 5/); assert.match(d, /v_zmin >= v_z/);
  assert.match(body(RAMP, 'fn_invite_copy_readout'), /replied or clicked or registered/);
  const keys = [...RAMP.matchAll(/^\s*\('([a-z])', '[^']+', (true|false),/gm)].map((m) => m[1]).sort();
  const lane = R('supabase/functions/send_outbox/m365_lane.ts');
  const ts = /export const INVITE_VARIANTS: readonly InviteVariant\[\] = \[([^\]]*)\]/.exec(lane);
  assert.ok(ts, 'm365_lane.ts names no INVITE_VARIANTS');
  assert.deepEqual(keys, [...ts[1].matchAll(/'([a-z])'/g)].map((m) => m[1]).sort(), 'the database and send_outbox name different variants');
  assert.match(RAMP, /'invite_variant:' \|\| c\.variant/, 'the batch does not put the variant on the row');
  assert.match(body(RAMP, 'fn_sales_engineer_nudges_invited_suppliers'), /kind = 'invite_variant:'/, 'the nudge does not carry the lead\'s variant');
});

test('an owed supplier reply goes back to the MODEL\'s answerer: the duty writes no reply itself (ruling 1339)', () => {
  const d = code(body(REPLY, 'fn_sales_engineer_answers_supplier_replies_same_day'));
  assert.match(d, /set triaged_at = null, ai_category = null, owner_role = null, needs_review = true/);
  assert.doesNotMatch(d, /fn_inbox_send|fn_customer_support_takes_delivery|insert into public\.notifications/, 'the same-day duty writes a reply in code');
  assert.match(d, /'escalated'/); assert.match(d, /'not_owed'/); assert.match(d, /fn_seat_handoff\('sales_engineer', 'ceo', 'review\.requested'/);
  assert.match(d, /r\.attempts < 3/); assert.match(d, /interval '30 minutes'/);
  assert.match(d, /not r\.may_reply/, 'a reading that refused an answer is overridden');
});

test('the parked get one e-mail with a click-to-chat link to the number the site publishes, never a WhatsApp message', () => {
  const t = code(body(REPLY, 'fn_sales_engineer_final_touch_parked_suppliers'));
  assert.doesNotMatch(t, /'channel', 'whatsapp'|wa_messages|fn_send_whatsapp|twilio/i, 'the final touch messages on WhatsApp');
  assert.match(t, /'channel', 'email'/);
  assert.match(t, /not exists \(select 1 from public\.supplier_final_touch t where t\.lead_id = l\.id\)/, 'a parked lead can be touched twice');
  assert.match(t, /fn_supplier_outreach_reachable\(r, r\.email\)/); assert.match(t, /fn_invite_placement_open_providers/);
  assert.match(body(REPLY, 'fn_supplier_final_touch_text'), /'https:\/\/wa\.me\/'/);
  const company = JSON.parse(R('src/content/company.json'));
  const seeded = /\('supplier_whatsapp_click_to_chat', '(\d+)'\)/.exec(REPLY);
  assert.ok(seeded, 'no click-to-chat number seeded');
  assert.equal(seeded[1], String(company.phone.tel).replace(/\D/g, ''), 'the click-to-chat number is not the WhatsApp number the site publishes');
});

test('the CEO, not the founder, accepts the month, approves the calendar and moves marketing_golive; the emergency stop is his', () => {
  const tick = code(body(MKT, 'fn_marketing_month_plan_tick'));
  assert.doesNotMatch(tick, /set status = 'sent_to_founder'/, 'the month still waits for the founder');
  assert.match(tick, /insert into public\.marketing_ceo_decision/);
  for (const fn of ['fn_ceo_switches_marketing_golive', 'fn_ceo_accepts_marketing_month', 'fn_ceo_approves_marketing_calendar', 'fn_ceo_publishes_article']) {
    assert.match(body(MKT, fn), /length\(btrim\(coalesce\(p_reason, ''\)\)\) < 20/, `${fn} decides without a reason`);
    assert.match(body(MKT, fn), /insert into public\.marketing_ceo_decision/, `${fn} decides without a record`);
  }
  assert.doesNotMatch(code(MKT), /key = 'marketing_publishing_enabled'[^;]*update|update public\.app_secrets set value[^;]*marketing_publishing_enabled|\('marketing_publishing_enabled',/,
    'the CEO writes the founder\'s emergency stop');
  const round = code(body(MKT, 'fn_ceo_decides_marketing'));
  assert.match(round, /public\.fn_marketing_publishing_on\(\)/, 'the CEO publishes over the emergency stop');
  assert.doesNotMatch(round, /fn_ceo_switches_marketing_golive\(true/, 'the CEO round switches marketing_golive on by itself (it also starts the founder\'s LinkedIn list)');
  assert.match(body(MKT, 'fn_marketing_article_release_due'), /d\.subject_kind = 'article' and d\.subject_ref = v_next\.slug and d\.decision = 'publish'/,
    'the weekly release does not read the CEO\'s publish decision');
  assert.match(MKT, /check \(approved_by = any \(array\['founder'::text, 'ceo'::text\]\)\)/);
});

test('every new seat duty names a routine this change defines and the file that owns it', () => {
  const want = [1, 1, 2, 1];
  for (const [i, src] of [BRAKE, RAMP, REPLY, MKT].entries()) {
    const duties = [...src.matchAll(/\('([a-z_]+\.[a-z_]+)', '([a-z_]+)', interval '[^']+', '(\w+)',[\s\S]*?'(scripts\/sql\/[^']+\.sql)'\)/g)];
    assert.equal(duties.length, want[i], `${NAMES[i]}: expected ${want[i]} seat duty row(s), read ${duties.length}`);
    for (const m of duties) {
      assert.match(src, new RegExp(`create or replace function public\\.${m[3]}\\(`), `${m[1]}: ${m[3]} is not defined in ${NAMES[i]}`);
      assert.equal(m[4], `scripts/sql/${NAMES[i]}.sql`, `${m[1]} names another owner file`);
    }
  }
});
