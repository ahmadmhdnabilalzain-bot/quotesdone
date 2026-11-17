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
// The review of 15 Nov (scratchpad REVIEW_growth, items 1-7) added: any complaint on any campaign mail stops the company; the
// limits are written only by their routines (service_role revoked, BEFORE TRUNCATE, one waiting change, clock_timestamp); a pause
// and send time stop what is queued; the last note is a lane nudge with no link inside the cap; the emergency stop is read at
// release time; "engaged" is an interested reply or a question; the founder is never told to reply "approve".
//
//   node --test scripts/checks/the_supplier_funnel_runs_itself.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { applyState } from '../lib/pending_sql.mjs';

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

// The four files were applied 16 Nov 00:53-01:00 UTC (cc0e08868) and moved to MANIFEST; their probes are never applied.
test('each file and its probe exist; a file waits with its reason XOR has its MANIFEST line; a probe is never applied', () => {
  for (const n of NAMES) for (const f of [n, n + '_probe']) {
    assert.ok(existsSync(join(ROOT, `scripts/sql/${f}.sql`)), `${f}.sql is missing`);
    const st = applyState(`scripts/sql/${f}.sql`);
    assert.ok(st.note === null || st.note.length > 40, `${f} has a pending note with no reason`);
    if (f.endsWith('_probe')) assert.ok(st.note !== null && !st.applied, `${f} is applied, or has no note saying it never is`);
    else assert.ok(st.applied !== (st.note !== null), `${f} is pending and in MANIFEST at once, or neither`);
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
  assert.match(BRAKE, /new\.effective_at := clock_timestamp\(\) \+ interval '24 hours'/, 'a limit change does not wait a day on the wall clock');
  assert.match(BRAKE, /select 'ceo_invite_restarts_per_30d', 2,/, 'the seeded limit is not 2');
  const ceo = body(BRAKE, 'fn_ceo_restarts_invites');
  assert.match(ceo, /fn_growth_limit\('ceo_invite_restarts_per_30d'\)/);
  assert.match(ceo, /v_used >= v_limit/);
  assert.match(ceo, /never restarted over a complaint/);
  assert.match(ceo, /interval '24 hours'/);
  assert.match(ceo, /insert into public\.email_suppressions/, 'the CEO restarts before the bounced addresses are suppressed');
  assert.doesNotMatch(code(BRAKE), /invite_ceo_ceiling'?\s*(=|,)\s*'?[1-9]/, 'this file raises the old ceiling instead of using its own limit');
});

test('the limits are written only by their routines: service_role revoked, no TRUNCATE, one waiting change, the wall clock (review item 3)', () => {
  for (const [src, t] of [[BRAKE, 'growth_limit_change'], [BRAKE, 'invite_brake_decision'], [MKT, 'marketing_ceo_decision']]) {
    assert.match(src, new RegExp(`revoke insert, update, delete, truncate, references, trigger on public\\.${t} from service_role`), `${t}: service_role can still write it`);
    assert.match(src, new RegExp(`before truncate on public\\.${t}\\s+for each statement`), `${t}: no BEFORE TRUNCATE trigger`);
  }
  const set = code(body(BRAKE, 'fn_ceo_sets_growth_limit'));
  assert.ok(set.indexOf("pg_advisory_xact_lock(hashtext('growth_limit_change:' || p_key))") > 0
            && set.indexOf("pg_advisory_xact_lock") < set.indexOf('already waits'), 'the "already waits" check runs without the per-limit lock');
  const trg = code(body(BRAKE, 'trg_growth_limit_change_waits_a_day'));
  assert.match(trg, /new\.set_at := clock_timestamp\(\)/); assert.doesNotMatch(trg, /new\.set_at := now\(\)/);
  assert.match(trg, /already waits/, 'the trigger lets a second waiting change in');
});

test('any complaint on any supplier campaign mail stops the company; every campaign type is judged (review item 2)', () => {
  const judge = code(body(BRAKE, 'fn_invite_bounce_judgement'));
  assert.match(judge, /n\.type = any \(public\.fn_invite_campaign_types\(\)\)/, 'the judgement reads only the invitation');
  assert.doesNotMatch(judge, /n\.type = 'supplier_invite'/);
  assert.match(judge, /if coalesce\(\(v_all->>'complaint'\)::int, 0\) > 0 then\s+v_company := 'complaint'/, 'a complaint is still judged on a lower bound');
  const types = /fn_invite_campaign_types\(\)[\s\S]*?select array\[([^\]]*)\]/.exec(BRAKE);
  const lane = /export const LANE_CAPPED_TYPES: readonly string\[\] = \[([^\]]*)\]/.exec(R('supabase/functions/send_outbox/invite_lane.ts'));
  assert.ok(types && lane, 'a campaign type list is missing');
  const list = (m) => [...m[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]).sort();
  assert.deepEqual(list(types), list(lane), 'the judged campaign types and the lane-capped types differ');
  const trg = code(body(BRAKE, 'fn_invite_same_day_brake'));
  assert.match(trg, /new\.invite_status = 'complained'/); assert.match(trg, /fn_invite_brake_company\('invite_same_day_brake'/);
  assert.doesNotMatch(trg, /fn_invite_send_health/, 'the same-hour brake still counts only today\'s invitations');
  assert.match(code(body(RAMP, 'fn_invite_ramp')), /v_j->>'company_reason', ''\) = 'complaint'[\s\S]*fn_invite_brake_company/, 'the ramp stops on complaints only at two in 48 hours');
  assert.match(BRAKE, /'policy_limit', 0, 'policy_min', 2/, 'policy refusals do not hold a class on two');
});

test('a pause and send time stop what is already queued (review item 4)', () => {
  const pause = code(body(BRAKE, 'fn_invite_campaign_pause'));
  assert.match(pause, /where type = any \(public\.fn_invite_campaign_types\(\)\) and status = 'queued'/, 'the pause leaves queued nudges');
  const chk = code(body(BRAKE, 'fn_invite_campaign_send_check'));
  for (const w of ["'cancel'", "'requeue'", 'invite_enabled', 'fn_supplier_outreach_golive()', 'resumed_at is null', 'held_classes', 'fn_invite_placement_open_providers']) {
    assert.ok(chk.includes(w), `fn_invite_campaign_send_check does not read ${w}`);
  }
  assert.match(BRAKE, /grant execute on function public\.fn_invite_campaign_send_check\(bigint\[\]\) to service_role/);
  const idx = R('supabase/functions/send_outbox/index.ts');
  assert.match(idx, /admin\.rpc\('fn_invite_campaign_send_check', \{ p_ids: campIds \}\)/, 'send_outbox does not ask the live switches');
  const at = idx.indexOf('const st = campaignStep(campVerdicts, n.id, new Date())');
  assert.ok(at > 0 && at < idx.indexOf('const laneHold = holdFor('), 'the live switches are asked after the row could already be routed to a lane');
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
  const ro = code(body(RAMP, 'fn_invite_copy_readout'));
  assert.match(ro, /replied or clicked or registered/);
  // review item 7: a reply counts only when it is interested or a question, never a stop, a decline or an automatic reply
  assert.match(ro, /fn_supplier_reply_kind\(m\.body\) in \('interested', 'question'\)/, 'engaged counts any reply');
  assert.match(ro, /not public\.fn_inbound_is_auto_reply\(/); assert.match(ro, /not public\.fn_is_machine_sender\(/);
  assert.ok(RAMP.indexOf('create or replace function public.fn_supplier_reply_kind(') < RAMP.indexOf('create or replace function public.fn_invite_copy_readout('),
    'the readout is created before the reply kind it reads');
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
  assert.match(d, /'escalated'/); assert.match(d, /'not_owed'/); assert.match(d, /fn_seat_handoff\('sales_engineer', 'ceo', 'supplier\.reply_overdue'/);
  assert.match(REPLY, /\('supplier\.reply_overdue', 'sales_engineer', 'ceo',/, 'the overdue conversation is not registered (fn_seat_handoff files it failed)');
  assert.match(d, /r\.attempts < 3/); assert.match(d, /interval '30 minutes'/);
  assert.match(d, /not r\.may_reply/, 'a reading that refused an answer is overridden');
});

test('the parked get one last note: a lane nudge, inside the cap, with no link, never a WhatsApp message (review item 5)', () => {
  const t = code(body(REPLY, 'fn_sales_engineer_final_touch_parked_suppliers'));
  assert.doesNotMatch(t, /'channel', 'whatsapp'|wa_messages|fn_send_whatsapp|twilio/i, 'the final touch messages on WhatsApp');
  assert.match(t, /'channel', 'email'/);
  assert.match(t, /'type', 'supplier_invite_nudge'/, 'the last note is not a lane type');
  assert.doesNotMatch(t, /supplier_registration_reminder/, 'the last note still leaves as a registration reminder (Resend, outside the cap)');
  assert.match(t, /set kind = 'invite_final_touch'/);
  assert.doesNotMatch(t, /https?:|wa\.me|fn_supplier_invite_link|claim_token/, 'the last note carries a link (founder_instruction 1301)');
  assert.match(t, /invite_daily_cap/); assert.match(t, /nudge_share/); assert.match(t, /supplier_final_touch_daily/);
  assert.match(t, /t\.lead_id is null or exists \(select 1 from public\.notifications x where x\.id = t\.notification_id and x\.status = 'cancelled'\)/, 'a parked lead can be touched twice');
  assert.match(t, /fn_supplier_outreach_reachable\(r\.lead, r\.email\)/); assert.match(t, /fn_invite_placement_open_providers/);
  assert.doesNotMatch(REPLY, /supplier_whatsapp_click_to_chat'?, '/, 'a click-to-chat number is still seeded');
  const lane = R('supabase/functions/send_outbox/m365_lane.ts');
  assert.match(lane, /export const FINAL_TOUCH_KIND = 'invite_final_touch';/, 'send_outbox names another last-note kind');
  assert.match(lane, /row\.type === 'supplier_invite_nudge' && row\.kind === FINAL_TOUCH_KIND/);
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
  const rel = code(body(MKT, 'fn_marketing_article_release_due'));
  assert.match(rel, /d\.subject_kind = 'article' and d\.subject_ref = v_next\.slug and d\.decision = 'publish'/,
    'the weekly release does not read the CEO\'s publish decision');
  // review item 6: the founder's emergency stop is read when the article is released, before any CEO decision can release it
  assert.ok(rel.indexOf('if not public.fn_marketing_publishing_on() then') > 0
            && rel.indexOf('if not public.fn_marketing_publishing_on() then') < rel.indexOf("d.decision = 'publish'"), 'the release does not read the emergency stop at release time');
  // the founder's acknowledgement no longer asks him to approve the calendar (the CEO approves it)
  const ack = body(MKT, 'fn_marketing_month_plan_reply');
  assert.doesNotMatch(ack, /reply "approve"/i, 'the founder is still told to reply "approve"');
  assert.match(ack, /the CEO approves it/);
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
