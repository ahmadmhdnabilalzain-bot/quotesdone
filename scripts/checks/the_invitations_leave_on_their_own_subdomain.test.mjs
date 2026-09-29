// THE INVITATIONS LEAVE ON THEIR OWN SUBDOMAIN (24 Sep 2026; Assigned: marketing (campaign) + it_engineer (mail path)).
//
// Measured: invitations, sign-up codes (login_otp) and every notice left from info@quotesdone.com, so a campaign's
// reputation hit would land on the sign-up codes. The lane moves invitations only, behind a flag seeded OFF.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * the flag is seeded anything but 'false', or a second invitation ramp appears (the lane's fn_invite_ramp must
//     be the previous one plus the lane scope and nothing else, so OFF is today's ramp);
//   * whichever fn_invite_ramp will win (MANIFEST order, a pending file after it) reads its restart/growth history
//     without the lane scope and the sent-only condition (so info@'s history, or held invitations, would warm the
//     new subdomain), or scopes the 48 h complaint/bounce read (activation would hide complaints from the pause);
//     or the flag-off run log gains a lane key; or the 18:00 list stops predicting day 1;
//   * with the flag on and the domain refused, a lane invitation is sent from the main sender instead of held;
//   * send_outbox picks its From anywhere but senderFor, or the lane reaches a type other than the invitation and
//     its seed, or any other sender (login_otp above all) reads an invite_lane_* key;
//   * production, in ONE aborted transaction (the pending file replayed without its begin/commit; no lead, no
//     real row written; nothing commits): with the lane OFF the ramp counts the whole history; switched ON, the
//     activation is stamped, the ramp counts none of it and restarts at invite_warmup.base_cap.
//
//   node --test scripts/checks/the_invitations_leave_on_their_own_subdomain.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/the_invitations_leave_on_their_own_subdomain_so_a_campaign_cannot_cost_the_sign_up_codes.sql';
const PREVIOUS_RAMP = 'scripts/sql/the_daily_supplier_list_goes_only_before_a_sending_day_and_a_company_is_invited_once.sql';
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));
const body = (src, name) => {
  const i = src.indexOf('create or replace function public.' + name + '(');
  if (i < 0) return null;
  return src.slice(i, src.indexOf('$fn$;', i));
};
const squash = (s) => s.replace(/\s+/g, ' ').trim();
// The lane scope on a restart/growth read: since activation, and only an invitation that actually left.
const LANE_SCOPE = " and invited_at >= v_since and (v_since = '-infinity'::timestamptz or public.fn_invite_lane_sent(id))";

test('the flag is seeded OFF next to the campaign flags, and every new routine is closed', () => {
  const src = code(read(FILE));
  assert.match(src, /\('invite_lane_enabled', 'false'\)/);
  assert.match(src, /\('invite_lane_from', 'QuotesDone <invite@hello\.quotesdone\.com>'\)/);
  assert.match(src, /on conflict \(key\) do nothing/, 'the seed must never overwrite a value the founder set');
  for (const sig of ['trg_invite_lane_since()', 'fn_invite_lane_since()', 'fn_invite_lane_sent(bigint)', 'fn_invite_ramp()', 'fn_supplier_campaign_next_list(date)']) {
    assert.ok(src.includes(`revoke execute on function public.${sig} from public, anon, authenticated;`), 'no revoke on ' + sig);
  }
  for (const f of ['trg_invite_lane_since', 'fn_invite_lane_since', 'fn_invite_lane_sent', 'fn_invite_ramp']) {
    assert.match(body(src, f), /security definer\s+set search_path to 'public', 'pg_temp'/, f + ' search_path');
  }
  assert.match(body(src, 'fn_invite_lane_since'), /if not v_on then return '-infinity'::timestamptz; end if;/);
  assert.match(src, /after insert or update on public\.app_secrets\s+for each row when \(new\.key = 'invite_lane_enabled'\)/);
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/);
  assert.ok(pending(FILE) !== manifest.includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

test('no second ramp: the lane\'s fn_invite_ramp is the previous one plus the lane scope and nothing else', () => {
  const lane = body(code(read(FILE)), 'fn_invite_ramp');
  const prev = body(code(read(PREVIOUS_RAMP)), 'fn_invite_ramp');
  const stripped = lane
    .replace(/\s*v_since timestamptz := public\.fn_invite_lane_since\(\);/, '')
    .replaceAll(LANE_SCOPE, '')
    .replace(/\s*\|\| case when v_since > '-infinity'::timestamptz\s+then ' on the invitation lane[^\n]*else '' end/, '')
    .replace(/\s*\|\| case when v_since > '-infinity'::timestamptz then jsonb_build_object\('lane_since', v_since\) else '\{\}'::jsonb end/, '');
  assert.equal(squash(stripped), squash(prev), 'fn_invite_ramp differs from the previous ramp by more than the lane scope');
});

// The file that will define fn_invite_ramp once everything committed is applied: MANIFEST order, then pending files.
function winningRamp() {
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim()).filter((l) => l.endsWith('.sql'));
  const pend = readdirSync(join(REPO, 'scripts/sql/pending')).filter((f) => f.endsWith('.txt'))
    .map((f) => 'scripts/sql/' + f.replace(/\.txt$/, '.sql')).filter((f) => existsSync(join(REPO, f))).sort();
  let win = null;
  for (const f of [...manifest, ...pend]) if (body(code(read(f)), 'fn_invite_ramp')) win = f;
  return win;
}

test('the winning ramp counts only the lane\'s own sends while the lane is on', () => {
  const f = winningRamp();
  const ramp = body(code(read(f)), 'fn_invite_ramp');
  assert.match(ramp, /v_since timestamptz := public\.fn_invite_lane_since\(\)/, f + ' does not read the lane stamp');
  const reads = [...ramp.matchAll(/from leads where ([^;]*);/g)].map((m) => m[1]).filter((w) => /invited_at/.test(w) && !/invited_at is null and coalesce/.test(w));
  const health = reads.filter((w) => /interval '48 hours'/.test(w));
  const history = reads.filter((w) => !/interval '48 hours'/.test(w));
  assert.equal(health.length, 1, 'expected one 48 h health read');
  assert.doesNotMatch(health[0], /v_since|fn_invite_lane_sent/, 'the 48 h complaint/bounce read is lane-scoped: switching the lane on would hide complaints from the pause');
  assert.equal(history.length, 3, 'expected the three restart/growth reads, found ' + history.length);
  for (const w of history) assert.ok(w.includes(LANE_SCOPE.trim()), f + ' reads restart/growth history unscoped: ' + squash(w).slice(0, 140));
  assert.match(ramp, /\|\| case when v_since > '-infinity'::timestamptz then jsonb_build_object\('lane_since', v_since\) else '\{\}'::jsonb end/,
    'the flag-off run log must carry no lane key');
  assert.doesNotMatch(ramp, /'lane_since', case/, 'lane_since written as null with the flag off');
  assert.match(ramp, /elsif v_last_sent is null or v_last_sent < now\(\) - interval '3 days' then\s+v_restart := true; v_new := v_base;/,
    'the restart branch that starts a new lane at day 1 is gone');
  const list = body(code(read(FILE)), 'fn_supplier_campaign_next_list');
  assert.match(list, /l\.invited_at >= public\.fn_invite_lane_since\(\)/, 'the 18:00 list would not predict the lane\'s day 1');
});

test('send_outbox takes its From from senderFor, and the lane carries the invitation, its seed and its nudge only', () => {
  const idx = read('supabase/functions/send_outbox/index.ts');
  const froms = [...idx.matchAll(/const from = ([^;]+);/g)].map((m) => m[1]);
  assert.deepEqual(froms, ['senderFor({ type: n.type, supplierSide, fromSup, fromInfo, lane })']);
  assert.match(idx, /resolveLane\(\{ enabled: await setting\('invite_lane_enabled'\), from: await setting\('invite_lane_from'\)/);
  assert.match(idx, /fn_it_engineer_finding_upsert/);
  const hold = idx.indexOf('const laneHold = holdFor(');
  assert.ok(hold > 0 && hold < idx.indexOf('const from = senderFor('), 'the lane hold must be decided before the From');
  assert.match(idx.slice(hold, hold + 700), /status: 'queued', claimed_at: null, not_before: heldUntil\(laneHold, new Date\(\)\)/);
  assert.match(idx.slice(hold, hold + 900), /laneHeld\+\+; continue;/);
  const lane = read('supabase/functions/send_outbox/invite_lane.ts');
  // 29 Sep 2026 (review of #1007): the day-3/7/14 nudge of an unopened invitation leaves from the lane too, inside its cap.
  assert.match(lane, /export const INVITE_LANE_TYPES: readonly string\[\] = \['supplier_invite', 'supplier_invite_seed', 'supplier_invite_nudge'\];/);
  assert.match(lane, /export const LANE_CAPPED_TYPES: readonly string\[\] = \['supplier_invite', 'supplier_invite_nudge'\];/, 'the nudge must share the invitation\'s daily cap');
  assert.match(lane, /INVITE_LANE_TYPES\.includes\(type\)/, 'the lane must match types exactly, never by prefix');
  assert.match(lane, /if \(o\.lane\.refused\) return 'unverified';/, 'a refused lane must hold its invitations, not divert them');
  assert.match(lane, /return \{ active: false, refused: true, from: '', domain, why: 'refused: ' \+ status \};/);
  assert.match(lane, /if \(o\.lane\.active && o\.supplierSide && isLaneType\(o\.type\)\) return o\.lane\.from;\s+return o\.supplierSide \? o\.fromSup : o\.fromInfo;/);
  assert.match(lane, /fetchFn\('https:\/\/api\.resend\.com\/domains', \{ method: 'GET'/);
  assert.doesNotMatch(lane, /method: '(POST|PATCH|PUT|DELETE)'/, 'the verification read must be read-only');
});

test('no sign-up code or notice sender can reach the lane', () => {
  const dir = join(REPO, 'supabase/functions');
  const hits = [];
  for (const fn of readdirSync(dir)) {
    const p = join(dir, fn, 'index.ts');
    if (fn === 'send_outbox' || !existsSync(p)) continue;
    if (/invite_lane|hello\.quotesdone\.com/.test(readFileSync(p, 'utf8'))) hits.push(fn);
  }
  for (const f of readdirSync(join(dir, '_shared')).filter((f) => f.endsWith('.ts'))) {
    if (/invite_lane|hello\.quotesdone\.com/.test(readFileSync(join(dir, '_shared', f), 'utf8'))) hits.push('_shared/' + f);
  }
  assert.deepEqual(hits, [], 'a sender outside send_outbox reads the invitation lane');
  assert.match(read('supabase/functions/login_otp/index.ts'), /sec\('email_from_info'\)/, 'login_otp no longer sends from email_from_info');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: switching the lane on restarts the same ramp at the base cap', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  // The replay must not commit: drop the file's own transaction lines and its verdict select.
  const replay = pending(FILE)
    ? read(FILE).replace(/^\s*(begin|commit);\s*$/gim, '').replace(/-- ── VERDICT[\s\S]*$/, '')
    : '';
  assert.doesNotMatch(code(replay), /^\s*commit\b/im, 'the replay would commit');
  let o;
  try { await sql(replay + '\n' + PROBE, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  assert.equal(o.off_since, '-infinity', 'with the lane off the ramp is not reading the whole history');
  assert.ok(!('lane_since' in o.off), 'the flag-off run log carries a lane key');
  assert.equal(o.on.sent_48h, o.off.sent_48h, 'switching the lane on changed the 48 h health read the pause depends on');
  assert.ok(o.stamped, 'switching the lane on did not stamp invite_lane_since');
  assert.equal(o.on.sent_total, 0, 'the lane inherited the main sender\'s history: ' + JSON.stringify(o.on));
  assert.equal(o.on.restart, true, 'the lane did not restart');
  assert.equal(o.on_cap, o.base, 'the lane\'s first cap is not invite_warmup.base_cap');
  assert.ok(o.off.sent_total >= o.on.sent_total, 'the scoped count exceeds the unscoped one');
});

const PROBE = String.raw`
do $$ declare o jsonb := '{}'; v_cap int;
begin
  update app_secrets set value = 'true' where key = 'invite_enabled';
  update app_secrets set value = 'false' where key = 'invite_lane_enabled';
  o := o || jsonb_build_object('off_since', fn_invite_lane_since()::text,
                               'base', coalesce((select (nullif(value,'')::jsonb->>'base_cap')::int from app_secrets where key = 'invite_warmup'), 30));
  perform fn_invite_ramp();
  o := o || jsonb_build_object('off', (select counts from agent_runs where agent = 'invite_ramp' order by id desc limit 1));
  update app_secrets set value = 'true' where key = 'invite_lane_enabled';
  o := o || jsonb_build_object('stamped', (select nullif(value, '') is not null from app_secrets where key = 'invite_lane_since'));
  v_cap := fn_invite_ramp();
  o := o || jsonb_build_object('on_cap', v_cap, 'on', (select counts from agent_runs where agent = 'invite_ramp' order by id desc limit 1));
  raise exception 'CHK<<%>>', o::text;
end $$;`;
