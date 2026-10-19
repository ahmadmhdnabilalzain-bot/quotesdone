// A REQUEST FOR HUMAN REVIEW GOES TO THE SEAT THAT OWNS THE DECISION (ledger 1152, 19 Oct 2026, seat ceo).
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: review_route misses a decision type the founder named (matching, specs, quotes, reports -> sales_engineer;
//     fees, refunds, charges -> accountant; messaging, account -> customer_support; security, access -> it_engineer;
//     dispute, approval -> ceo), routes one to another seat, or any route names the founder;
//   * static: the different-model-family CHECK, the (decision_type, owner_seat) foreign key, a revoke, RLS or a policy
//     is gone, the file reaches the founder (fn_notify_founder / founder_alerts / to_role founder), or it carries
//     both or neither of a pending note and a MANIFEST line;
//   * static: wa_inbound or email_triage stops filing a person request through fileReviewRequest;
//   * production, ONE aborted transaction (the file replayed while pending, ZZ DEMO / @example.invalid requesters):
//     a request per decision type lands with another seat than its route, is decided by the original decision's
//     model family, a same-family verdict is accepted, or any row reaches founder_alerts or a founder notification.
//
//   node --test scripts/checks/a_request_for_human_review_goes_to_the_seat_that_owns_the_decision.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/a_request_for_human_review_goes_to_the_seat_that_owns_the_decision.sql';
const PROBE = FILE.replace(/\.sql$/, '_probe.sql');
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));

// The founder's own routing (ledger 1152). A type missing from the table, or moved to another seat, fails here.
const ROUTES = {
  matching: 'sales_engineer', specs: 'sales_engineer', quotes: 'sales_engineer', reports: 'sales_engineer',
  fees: 'accountant', refunds: 'accountant', charges: 'accountant',
  messaging: 'customer_support', account: 'customer_support',
  security: 'it_engineer', access: 'it_engineer',
  dispute: 'ceo', approval: 'ceo',
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
  assert.doesNotMatch(src, /fn_notify_founder|founder_alerts|to_role\s*=?\s*'founder'/, 'the review path reaches the founder');
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
  const ping = read('supabase/functions/resilience_ping/index.ts');
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

test('static: WhatsApp and e-mail person requests enter the review path', () => {
  assert.match(read('supabase/functions/wa_inbound/index.ts'), /if \(needsPerson === true\) \{\s+await fileReviewRequest\(admin, defaultDeps\(admin, 'wa_inbound'\), \{ channel: 'whatsapp'/);
  assert.match(read('supabase/functions/email_triage/index.ts'), /how = 'person';\s+(\/\/.*\s+)?await fileReviewRequest\(admin, deps, \{ channel: 'email'/);
  const shared = read('supabase/functions/_shared/review_request.ts');
  assert.ok(shared.includes("admin.rpc('fn_review_request_open', {"), 'the shared entry no longer files through the one door');
  assert.ok(shared.includes("admin.from('review_route').select('decision_type,meaning')"), 'the options are no longer the routing table');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: one ZZ DEMO request per type lands with its seat, another family decides, 0 reach the founder', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const replay = pending(FILE) ? read(FILE) : '';
  let o;
  try { await replaySql(replay + '\n' + read(PROBE), { retry: false }); }
  catch (e) {
    const m = String(e.message).replace(/\\"/g, '"').match(/CHK<<(\{.*\})>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1]);
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  assert.equal(o.types, Object.keys(ROUTES).length, 'not one request per decision type');
  assert.equal(o.rows, Object.keys(ROUTES).length + 1, 'the requests were not all filed');
  assert.equal(o.misrouted, 0, 'a request landed with another seat than its route: ' + o.requests.join('; '));
  assert.equal(o.undecided, 0, 'a request could not be decided');
  assert.equal(o.same_family_decisions, 0, 'a review was decided by the original decision\'s model family');
  assert.equal(o.same_family_refused, 1, 'a same-family verdict was accepted');
  assert.equal(o.unknown_type.ok, false, 'an unknown decision type was filed');
  assert.equal(o.founder_alerts, 0, 'the review path wrote a founder alert');
  assert.equal(o.founder_notifications, 0, 'the review path queued a notification to the founder');
  assert.equal(o.demo_handoffs, 0, 'a ZZ DEMO request filed a seat handoff (ruling 1199)');
});
