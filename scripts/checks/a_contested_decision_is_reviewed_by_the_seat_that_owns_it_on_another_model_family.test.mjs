// A CONTESTED AUTOMATED DECISION GOES TO THE SEAT THAT OWNS THE DECISION (ledger 1152, 19 Oct 2026, seat ceo).
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: review_route misses a decision type the founder named (matching, specs, quotes, reports -> sales_engineer;
//     fees, refunds, charges -> accountant; messaging, account -> customer_support; security, access -> it_engineer;
//     dispute, approval -> ceo), routes one to another seat, or any route names the founder;
//   * static: the different-model-family CHECK, the (decision_type, owner_seat) foreign key, a revoke, RLS or a policy
//     is gone, the founder is reached outside the one explicit-person branch (ruling 1264), or it carries
//     both or neither of a pending note and a MANIFEST line;
//   * static: wa_inbound or email_triage stops filing a person request through fileReviewRequest;
//   * production, ONE aborted transaction (the file replayed while pending, ZZ DEMO / @example.invalid requesters):
//     a request per decision type lands with another seat than its route, is decided by the original decision's
//     model family, a same-family verdict is accepted, or any row reaches founder_alerts or a founder notification;
//     an explicit person request is not the CEO's on an escalation clock ('with_ceo', 16 Nov 2026, rulings 1696/1706/1710),
//     or reaches the founder.
//
//   node --test scripts/checks/a_contested_decision_is_reviewed_by_the_seat_that_owns_it_on_another_model_family.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';
import { functionSource } from '../lib/function_sources.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/a_contested_decision_is_reviewed_by_the_seat_that_owns_it_on_another_model_family.sql';
const PROBE = FILE.replace(/\.sql$/, '_probe.sql');
// the person route's later owner (16 Nov 2026): replayed before the probe while it is pending, so the probe reads what will be live
const CLOCK = 'scripts/sql/every_escalation_carries_a_clock_and_the_ceo_decides_it_not_the_founder.sql';
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));

// The founder's own routing (ledger 1152). A type missing from the table, or moved to another seat, fails here.
const ROUTES = {
  matching: 'sales_engineer', specs: 'sales_engineer', quotes: 'sales_engineer', reports: 'sales_engineer',
  fees: 'accountant', refunds: 'accountant', charges: 'accountant',
  messaging: 'customer_support', account: 'customer_support',
  security: 'it_engineer', access: 'it_engineer',
  dispute: 'ceo', approval: 'ceo',
  person: 'customer_support',   // not a decision; the record is support's, the decision the CEO's on its escalation clock (16 Nov 2026)
};

function routesIn(src) {
  const block = src.slice(src.indexOf('insert into public.review_route'), src.indexOf('on conflict (decision_type)'));
  return Object.fromEntries([...block.matchAll(/\('([a-z_]+)',\s*'([a-z_]+)',/g)].map((m) => [m[1], m[2]]));
}

test('static: every decision type routes to its owning seat and no route names the founder', () => {
  const src = code(read(FILE));
  const routes = routesIn(src);
  assert.deepEqual(routes, ROUTES, 'review_route differs from the founder\'s routing');
  for (const seat of Object.values(routes)) assert.notEqual(seat, 'founder');
  assert.match(src, /owner_seat\s+text not null references public\.org_role \(role_id\)\s+check \(owner_seat <> 'founder'\)/, 'a route can name something that is not a live seat, or the founder');
  assert.match(src, /foreign key \(decision_type, owner_seat\) references public\.review_route \(decision_type, owner_seat\)/, 'a request can land with a seat its route does not name');
  assert.match(src, /constraint decision_review_is_decided_by_a_different_model_family\s+check \(reviewer_model is null\s+or split_part\(reviewer_model, '\/', 1\) is distinct from coalesce\(nullif\(split_part\(original_model, '\/', 1\), ''\), 'deterministic'\)\)/, 'the different-family CHECK is gone');
  // Ruling 1264: exactly ONE call to fn_notify_founder, inside the 'person' branch, through founder_mail_policy kinds.
  assert.equal((src.match(/fn_notify_founder/g) || []).length, 1, 'the founder is reached from more than the one person branch');
  const branch = src.slice(src.indexOf("if v_route.decision_type = 'person' then"), src.indexOf('-- the owning seat'));
  assert.ok(branch.includes('public.fn_notify_founder('), 'the founder call is outside the explicit-person branch');
  assert.ok(branch.includes("then 'whatsapp_human_request' else 'person_request' end"), 'the person request no longer names its founder_mail_policy kind');
  assert.doesNotMatch(src, /founder_alerts|to_role\s*=?\s*'founder'/, 'the file writes to the founder outside founder_mail_policy');
  assert.ok(src.includes("check ((founder_notified is null and status <> 'with_founder')\n           or (decision_type = 'person' and channel in ('whatsapp', 'site_chat', 'email') and status = 'with_founder'))"),
    'the CHECK that keeps every other row away from the founder is gone');
  assert.match(src, /values \('person_request', true,/, 'the person_request kind is not on founder_mail_policy');
  assert.ok(src.includes("channel           text not null check (channel in ('whatsapp', 'site_chat', 'email')),"), 'a channel other than chat or e-mail can file a contest (ruling 1264)');
  for (const t of ['review_route', 'decision_review_request']) {
    assert.match(src, new RegExp(`alter table public\\.${t} enable row level security`), `${t} without RLS`);
    assert.match(src, new RegExp(`create policy ${t}_service_role_only on public\\.${t}`), `${t} without a policy`);
    assert.match(src, new RegExp(`revoke all on public\\.${t} from anon, authenticated`), `${t} not revoked`);
  }
  for (const sig of ['fn_review_request_waits(bigint)', 'fn_review_request_reviewer_model(bigint)',
    'fn_review_request_open(text, text, text, text, text, text, text, text, bigint, text)', 'fn_review_request_decide(bigint, text, text, text)',
    'fn_review_request_due(integer, bigint)', 'fn_review_request_attempt_failed(bigint, text)', 'fn_review_request_conclude(bigint, text, text, text, text)']) {
    assert.ok(src.includes(`revoke execute on function public.${sig} from public, anon, authenticated`), `${sig} is not revoked`);
  }
  assert.equal((src.match(/set search_path to 'public', 'pg_temp'/g) || []).length, 7, 'a routine without a pinned search_path');
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/);
  assert.ok(pending(FILE) !== manifest.includes(FILE), 'exactly one of a pending note and a MANIFEST line');
  assert.ok(pending(PROBE) && !manifest.includes(PROBE), 'the probe is never applied and keeps its note');
});

test('static: an open review is decided by the heartbeat, on another family, and the seats act on it', () => {
  const ping = functionSource('resilience_ping');
  assert.ok(ping.includes("await step('review_requests', async () => {") && ping.includes("action: 'review_requests', limit: 1 })"), 'the heartbeat no longer drives the review');
  const ceo = read('supabase/functions/ceo_agent/index.ts');
  assert.ok(ceo.includes("if (action === 'review_requests') {") && ceo.includes('await decideOpenReviews(liveReviewIO(admin), '), 'ceo_agent no longer decides open reviews');
  const live = read('supabase/functions/_shared/review_request.ts');
  assert.ok(live.includes('counterpartModel: r.counterpart_model'), 'the reviewer is no longer routed against the original model (another family)');
  assert.ok(live.includes("admin.rpc('fn_review_request_conclude', {"), 'the verdict no longer goes through fn_review_request_conclude');
  const sql = code(read(FILE));
  assert.ok(sql.includes("insert into public.decision_log (actor, kind, ctx, decision, reasons, route_to)") && sql.includes("values (r.owner_seat, 'review_' || r.verdict,"), 'the owning seat no longer acts on an overturn');
  assert.ok(sql.includes("public.fn_seat_handoff('customer_support', 'customer_support', 'delivery.request',"), 'customer_support no longer replies to the requester');
});

test('static: WhatsApp, site chat and e-mail person requests enter the path', () => {
  // 3 Nov 2026 (customer_support): started beside the reply and awaited in the turn's finally, no longer before the reply.
  const wa = functionSource('wa_inbound');
  assert.match(wa, /\breviewP = needsPerson === true\s+\? fileReviewRequest\(admin, defaultDeps\(admin, 'wa_inbound'\), \{ channel: 'whatsapp'/);
  assert.match(wa, /\n\s+await t\.reviewP;/, 'the review of a decision is still awaited before the turn ends');
  assert.match(read('supabase/functions/email_triage/index.ts'), /how = 'person';\s+(\/\/.*\s+)?await fileReviewRequest\(admin, deps, \{ channel: 'email'/);
  const shared = read('supabase/functions/_shared/review_request.ts');
  assert.ok(shared.includes("admin.rpc('fn_review_request_open', {"), 'the shared entry no longer files through the one door');
  assert.ok(read('supabase/functions/site_assistant/index.ts').includes("await fileReviewRequest(admin, defaultDeps(admin, 'site_assistant'), { channel: 'site_chat'"), 'site chat no longer enters the path');
  assert.ok(shared.includes("admin.from('review_route').select('decision_type,meaning')"), 'the options are no longer the routing table');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: one ZZ DEMO request per type lands with its seat, another family decides, 0 reach the founder; an explicit person request goes to the CEO on a clock', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const replay = (pending(FILE) ? read(FILE) + '\n' : '') + (pending(CLOCK) ? read(CLOCK) : '');
  let o;
  try { await replaySql(replay + '\n' + read(PROBE), { retry: false }); }
  catch (e) {
    const m = String(e.message).replace(/\\"/g, '"').match(/CHK<<(\{.*\})>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1]);
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  assert.equal(o.types, Object.keys(ROUTES).length - 1, 'not one request per decision type');
  assert.equal(o.rows, Object.keys(ROUTES).length, 'the requests were not all filed');
  assert.equal(o.misrouted, 0, 'a request landed with another seat than its route: ' + o.requests.join('; '));
  assert.equal(o.undecided, 0, 'a request could not be decided');
  assert.equal(o.same_family_decisions, 0, 'a review was decided by the original decision\'s model family');
  assert.equal(o.same_family_refused, 1, 'a same-family verdict was accepted');
  assert.equal(o.unknown_type.ok, false, 'an unknown decision type was filed');
  assert.equal(o.founder_alerts, 0, 'the review path wrote a founder alert');
  assert.equal(o.founder_notifications, 0, 'the review path queued a notification to the founder');
  assert.equal(o.demo_handoffs, 0, 'a ZZ DEMO request filed a seat handoff (ruling 1199)');
  // 16 Nov 2026 (rulings 1696/1706/1710 supersede ruling 1264 here): the explicit person request is the CEO's, on an escalation clock,
  // on chat and e-mail alike, and the founder is not reached
  for (const ch of ['whatsapp', 'site_chat', 'email']) {
    const p = o.person[ch];
    assert.equal(p.status, 'with_ceo', ch + ': the person request is not with the CEO');
    assert.equal(p.owner_seat, 'ceo', ch + ': the person request is not owned by the CEO seat');
    assert.equal(p.clock_ok, true, ch + ': no escalation clock was opened');
    assert.equal(p.founder_alerts, 0, ch + ': the person request wrote a founder alert');
    assert.equal(p.founder_notifications, 0, ch + ': the person request queued a founder notification');
  }
  assert.equal(o.person_from_portal.ok, false, 'a person request from the portal reached the founder');
  assert.equal(o.contest_from_portal.ok, false, 'a contest from the portal was filed (ruling 1264: chat or e-mail only)');
  assert.equal(o.founder_stamp_on_a_review_refused, 1, 'a decision review could be stamped as delivered to the founder');
});
