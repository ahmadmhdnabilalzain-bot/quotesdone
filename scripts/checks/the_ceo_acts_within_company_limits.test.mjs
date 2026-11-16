// THE CEO ACTS WITHIN COMPANY LIMITS AND ORDERS THE SEATS TO GROW SUPPLY (ceo, 15 Nov 2026).
// Founder, ledger 1696: "CEO is having full authority ... He doesnt rely on me in anything." Ledger 1701: "we need enough
// registered suppliers to be able to start a customer campaign later to fulfill their inquiries ... i want him to be able to
// take actions and give tasks to the agent". The third review of the pool branch (15 Nov) found a grant with no amount was
// unlimited money, a seat could be let e-mail a supplier, fix orders never closed, authority ran on the expensive route and
// starved the IT findings, nothing called the new check, and two refusals at once threw.
// Offline, from the text. This fails when:
//   1. a path asks or waits on the founder again (ask_founder, needs_founder, an escalation to 'founder');
//   2. a hard limit leaves code: the limits stop being append-only, a change stops waiting a day, the value in force reads a
//      waiting change, a commitment is checked outside its lock, money is read only by amount, a deploy is asked, a gate can
//      be weakened, or the NULL-amount grant comes back;
//   3. the authority questions lose their half-room cap or their routine route, a fix order stops closing with its finding,
//      a late order is offered chase, or a duplicate refusal is no longer caught;
//   4. the coverage objective stops being data (no proposal rows, a number without its source, a second coverage routine)
//      or an order loses its measure, its leads or its date, or the summary to the founder stops being information;
//   5. 'match' leaves the subject-aware form or loses its 202, or another caller joins it (deploy, refunds, the grant reports);
//   6. a routine of the three files is not revoked from public, anon and authenticated with its search_path pinned, a table
//      has no policy, or a file is in MANIFEST.txt without being applied (each carries its pending note until it is).
//   node --test scripts/checks/the_ceo_acts_within_company_limits.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const LIMITS = 'scripts/sql/the_company_limits_bind_every_seat_and_the_ceo_changes_one_only_after_a_day.sql';
const POOL = 'scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql';
const COVER = 'scripts/sql/the_ceo_reads_supplier_coverage_and_orders_the_seats_to_grow_it.sql';
const FILES = [LIMITS, POOL, COVER];
/** SQL with comments removed, so a check never matches the prose that explains it. */
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const fnBody = (text, name) => {
  const at = text.indexOf(`create or replace function public.${name}(`);
  return at < 0 ? '' : text.slice(at, text.indexOf('$fn$;', at));
};

test('1. nothing waits on the founder (ledger 1696)', () => {
  for (const f of FILES) {
    const c = code(read(f));
    assert.doesNotMatch(c, /'ask_founder'|needs_founder|ceo_needs_the_founder|fn_ceo_founder_options|fn_founder_brief_overdue_handoffs/, `${f} asks the founder`);
    assert.doesNotMatch(c, /v_sup := 'founder'/, `${f} escalates to the founder`);
  }
  const pool = read(POOL);
  assert.match(fnBody(pool, 'fn_ceo_files_judgements'), /jsonb_build_object\('id', 'allow_once'[\s\S]*jsonb_build_object\('id', 'refuse'/, 'an authority question is allow_once or refuse');
  assert.match(fnBody(pool, 'fn_reason_apply_ceo__authority'), /v_choice not in \('allow_once', 'refuse'\)/, 'any other answer decides nothing');
});

test('2. the hard limits are in code and data', () => {
  const lim = code(read(LIMITS));
  const trg = fnBody(lim, 'trg_company_limit_change_waits_a_day');
  assert.match(trg, /if tg_op <> 'INSERT' then\s+raise exception/, 'append-only: an edit or a delete is refused');
  // review 4, item 1: from the clock, not the transaction's start (a row written late in a long transaction waited less)
  assert.match(trg, /new\.effective_at := clock_timestamp\(\) \+ interval '24 hours';/, 'a change waits a day whatever the writer asked');
  assert.match(lim, /before insert or update or delete on public\.company_limit_change/);
  assert.match(fnBody(lim, 'fn_company_limit'), /c\.effective_at <= now\(\)/, 'the value in force never reads a waiting change');
  assert.match(fnBody(lim, 'fn_company_spend_commit'), /pg_advisory_xact_lock\(hashtext\('qd\.company_spend_commitment'\)\);\s+v := public\.fn_company_spend_fits/, 'the check and the write are one step under one lock');
  assert.match(fnBody(lim, 'fn_ceo_sets_company_limit'), /length\(btrim\(coalesce\(p_reason, ''\)\)\) < 20/, 'a change carries a reason');
  assert.match(lim, /from public\.ad_spend_policy p where p\.policy_key = 'default'\), 30\)/, 'the seed is the ads cap the company already runs');
  assert.match(fnBody(lim, 'fn_company_message_gates'), /public\.fn_email_sendable\(v_email\)[\s\S]*public\.fn_invite_placement_open_providers\([\s\S]*supplier_whatsapp_optin/, 'the existing gates, not new ones');
  const pool = read(POOL);
  const may = code(fnBody(pool, 'fn_agent_may_act'));
  assert.doesNotMatch(may, /o\.amount_aed is null or/, 'review 3 item 1: a grant with no amount is unlimited money');
  assert.match(may, /\(o\.amount_aed is null and p_amount_aed is null\)\s+or \(o\.amount_aed is not null and p_amount_aed is not null and p_amount_aed <= o\.amount_aed\)/);
  assert.match(may, /if v_money and \(p_amount_aed is null or p_amount_aed <= 0\) then/, 'money by name with no amount is refused unasked');
  assert.match(may, /fn_action_is_destructive_production_change\(p_action_class\) then[\s\S]{0,120}'route', 'release_path', 'asked', false/, 'a deploy is never asked');
  assert.match(may, /fn_action_weakens_a_message_gate\(p_action_class, a\)/);
  assert.match(may, /fn_company_spend_commit\(p_grantee_role_id, p_action_class, v_subject, p_amount_aed, 'ceo_allow_once', g\.id\)/, 'a grant commits its amount at use');
  assert.match(may, /'standing_grant', null\)/, 'a standing permit for money is still inside the limits');
  assert.match(code(fnBody(pool, 'fn_reason_apply_ceo__authority')), /v_guard := public\.fn_ceo_authority_guard\([\s\S]*if cardinality\(v_guard\) > 0 then/, 'the limits are read again when the answer lands');
});

test('3. the review-3 findings stay fixed', () => {
  const pool = read(POOL);
  const files = code(fnBody(pool, 'fn_ceo_files_judgements'));
  assert.match(files, /v_auth_room := case when n <= 1 then n else n \/ 2 end;/, 'item 5: authority takes at most half of the room');
  assert.match(files, /order by a\.created_at limit v_auth_room loop/);
  assert.match(read('supabase/functions/_shared/think/routing.ts'), /EASY_DUTY_SURFACE = \/(\\\.\(knowledge_refresh\|it_finding\|overdue_handoff\|authority\)\$|\(\\\.\(knowledge_refresh\|it_finding\|overdue_handoff\|authority\)\|\^ceo\\\.order_\(answer\|response\|next\)\)\$)\//, 'item 4: the routine route');
  const orders = code(fnBody(pool, 'fn_ceo_orders_reported'));
  assert.match(orders, /a\.detail->>'finding_handoff_id'[\s\S]{0,120}x\.status <> 'pending'[\s\S]*'closed with its finding'/, 'item 3: a fix order closes with its finding');
  assert.match(files, /case when r\.detail->>'type' = 'ceo\.order'\s+then jsonb_build_array\(jsonb_build_object\('id', 'withdraw'/, 'item 3: a late order is never chased');
  assert.match(code(fnBody(pool, 'fn_agent_may_act')), /exception when unique_violation then\s+select id into v_h from public\.agent_actions/, 'item 7: a duplicate refusal reads the first one back');
  const ov = code(fnBody(pool, 'fn_reason_apply_ceo__overdue_handoff'));
  assert.match(ov, /if v_choice = 'withdraw' then\s+perform public\.fn_seat_handoff_complete\(h\.id/);
});

test('4. the objective is data, and the CEO orders with a measure, the leads and a date', () => {
  const cov = read(COVER); const c = code(cov);
  assert.match(c, /create table if not exists public\.supplier_coverage_target \([\s\S]*source text not null check \(length\(btrim\(source\)\) >= 20\)/, 'every target says where it comes from');
  const prop = fnBody(c, 'fn_supplier_coverage_target_propose');
  for (const src of ['from public.inquiries i', 'from public.customer_trade_waitlist q', 'from public.supply_gap g']) assert.ok(prop.includes(src), `the proposal reads ${src}`);
  assert.match(prop, /trade_opening_rule\.open_at_suppliers/, 'the target is the company\'s own opening level, not invented');
  // demo is never demand, and a probe's world is only demo (the fixture seam): every reading carries the same predicate
  assert.match(prop, /where coalesce\(public\.fn_seat_clock_customer_is_fixture\(c\), false\) = \(coalesce\(current_setting\('qd\.duty_fixtures', true\), ''\) = 'on'\)/);
  assert.match(fnBody(c, 'fn_supplier_coverage'), /coalesce\(l\.is_demo, false\) = \(coalesce\(current_setting\('qd\.duty_fixtures', true\), ''\) = 'on'\)/);
  assert.match(c, /select public\.fn_supplier_coverage_target_propose\(\);\s*$/, 'the proposal is written at apply');
  // ONE routine for the numbers: no other SQL file defines it
  const owners = read('scripts/sql/MANIFEST.txt').split('\n').filter((l) => l.endsWith('.sql')).map((l) => l.trim())
    .filter((f) => existsSync(join(REPO, f.startsWith('scripts/') ? f : 'scripts/sql/' + f)) && read(f.startsWith('scripts/') ? f : 'scripts/sql/' + f).includes('function public.fn_supplier_coverage('));
  assert.deepEqual(owners, [], 'a second definition of fn_supplier_coverage');
  const loop = code(fnBody(c, 'fn_ceo_grows_supply'));
  for (const m of ["'invitations'", "'stuck_followed_up'", "'held_unblocked'"]) assert.ok(loop.includes(`'measure', ${m}`), `an order on ${m}`);
  assert.equal((loop.match(/public\.fn_seat_handoff\('ceo', [^,]+, 'ceo\.order', 'supplier_coverage'/g) || []).length, 3, 'three orders, through the pool');
  assert.equal((loop.match(/'due_at', v_due/g) || []).length, 3, 'every order has a due date');
  assert.equal((loop.match(/'lead_ids', to_jsonb\(v_ids\)/g) || []).length, 2, 'the registration orders name their leads');
  assert.match(loop, /elsif not v_on then\s+v_reason := 'invitations are switched off/, 'no invitation order while invitations are off');
  assert.match(loop, /insert into public\.ceo_supply_decision/, 'every decision is recorded with its reason');
  const sum = fnBody(c, 'fn_ceo_daily_summary_to_the_founder');
  assert.match(sum, /'info', 'ceo_daily_summary', v_key, 'ceo'\)/, 'information, once a day');
  assert.match(fnBody(c, 'fn_ceo_daily_summary_text'), /Nothing here waits on you\./);
  assert.match(c, /\('ceo\.supply_coverage', 'ceo', interval '1 hour', 'fn_ceo_supply_coverage_tick'/);
});

test('5. only the sales engineer\'s match uses the subject-aware form, and answers 202 when it asked', () => {
  const op = read('supabase/functions/sales_engineer/actions/operator.ts');
  assert.match(op, /const auth = await matchAuthority\(\(fn, args\) => admin\.rpc\(fn, args\), String\(body\.inquiry_id \|\| ''\)\);/);
  assert.match(op, /return J\(auth\.body, auth\.status\);/);
  const ma = read('supabase/functions/sales_engineer/lib/match_authority.ts');
  assert.match(ma, /p_subject: id \? 'inquiry:' \+ id : null,/);
  assert.match(ma, /status: 202, body: \{/);
  assert.match(ma, /call again after allow_once/);
  // the others stay on the three-argument form (review 3, item 6)
  // (each fn_agent_may_act call's argument object, up to its closing brace: another routine's p_subject does not count)
  const calls = (t) => [...t.matchAll(/rpc\('fn_agent_may_act', \{([^}]*)\}/g)].map((m) => m[1]);
  for (const f of ['supabase/functions/it_engineer/index.ts', 'supabase/functions/accountant/actions/refunds.ts', 'supabase/functions/accountant/actions/seat.ts',
                   'supabase/functions/sales_engineer/actions/operator.ts']) {
    const cs = calls(read(f));
    assert.ok(f.endsWith('operator.ts') || cs.length > 0, `${f} no longer calls the authority rule: re-read review 3 item 6`);
    for (const a of cs) assert.doesNotMatch(a, /p_subject|p_ask/, `${f} joined the subject-aware form`);
  }
});

test('6. every routine is revoked and pinned, every table has a policy, and nothing unapplied is in MANIFEST', () => {
  const manifest = read('scripts/sql/MANIFEST.txt');
  for (const f of FILES) {
    const t = code(read(f));
    const fns = [...t.matchAll(/create or replace function public\.([a-z0-9_]+)\(/g)].map((m) => m[1]);
    for (const n of new Set(fns)) {
      assert.match(t, new RegExp(`revoke execute on function public\\.${n}\\([^)]*\\) from public, anon, authenticated;`), `${f}: ${n} is not revoked`);
      const body = fnBody(t, n);
      assert.match(body, /set search_path to 'public', 'pg_temp'/, `${f}: ${n} has no pinned search_path`);
    }
    for (const m of t.matchAll(/create table if not exists public\.([a-z0-9_]+) \(/g)) {
      const tb = m[1];
      assert.match(t, new RegExp(`alter table public\\.${tb} enable row level security`), `${f}: ${tb} has no RLS`);
      assert.match(t, new RegExp(`create policy ${tb}_service_role_only on public\\.${tb}`), `${f}: ${tb} has no policy`);
      assert.match(t, new RegExp(`revoke all on public\\.${tb} from anon, authenticated;`), `${f}: ${tb} is not revoked`);
    }
    const base = f.split('/').pop();
    const listed = manifest.split('\n').some((l) => l.trim().endsWith(base));
    const pending = existsSync(join(REPO, 'scripts/sql/pending', base.replace(/\.sql$/, '.txt')));
    assert.ok(listed !== pending, `${base}: exactly one of a MANIFEST line (applied) or a pending note (not applied)`);
  }
});
