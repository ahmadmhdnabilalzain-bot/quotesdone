// A SANDBOX SUCCESS NEVER LIFTS THE MODEL HOLD. Founder, 7 Oct 2026: "Stop a sandbox success lifting
// the model hold." The hold (llm_route_health.open_until 2126 on every route, app_secrets.no_paid_ai)
// stays on until he lifts it, with `set local app.change_reason = 'founder:<ledger id>'`.
// Seat: it_engineer. Subject: scripts/sql/a_sandbox_success_never_lifts_the_model_hold.sql.
//
// Measured 7 Oct 2026: fn_record_llm_attempt cleared open_until on every successful attempt and set it
// to now()+15 min on a tripping failure. The stage-2 window (#1230) lets tagged calls past the hold, so
// the first tagged success would have un-held its route for everyone. This check fails if that returns.
//
//   node --test scripts/checks/a_sandbox_success_never_lifts_the_model_hold.test.mjs
//   HOLD_NO_REPLAY=1 ...   run the probe against production as it is (before the file is applied it FAILS: that is the bug)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, relative } from 'node:path';
import { homedir } from 'node:os';

const ROOT = new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const FILE = join(ROOT, 'scripts/sql/a_sandbox_success_never_lifts_the_model_hold.sql');
const SELF = 'scripts/checks/a_sandbox_success_never_lifts_the_model_hold.test.mjs';
const sqlText = readFileSync(FILE, 'utf8');
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

function walk(dir, out = []) {
  for (const n of readdirSync(dir)) {
    if (['node_modules', '.git', 'retired', 'full_schema', '.next', 'worktrees'].includes(n)) continue;
    const p = join(dir, n);
    const s = statSync(p);
    if (s.isDirectory()) walk(p, out);
    else if (/\.(mjs|js|ts|tsx|yml|yaml|sql|sh)$/.test(n) && !/RETIRED/.test(n)) out.push(p);
  }
  return out;
}
const files = ['scripts', 'supabase/functions', '.github', 'src'].filter((d) => existsSync(join(ROOT, d)))
  .flatMap((d) => walk(join(ROOT, d))).map((p) => ({ rel: relative(ROOT, p).replace(/\\/g, '/'), src: readFileSync(p, 'utf8') }));
// code lines only: a comment that explains the rule must not trip it
const code = (s) => s.split('\n').filter((l) => !/^\s*(--|\/\/|#|\*)/.test(l)).join('\n');
const WRITES_HOLD = /(update|delete\s+from)\s+(public\.)?llm_route_health\b/i;
const FOUNDER_REASON = /founder:[0-9]/;

test('the file: one definition of "founder-held", a guarded table, a fixed recorder, every routine closed', () => {
  assert.match(sqlText, /p_open_until > now\(\) \+ interval '1 year'/);
  assert.match(sqlText, /'\^\(founder:\[0-9\]\+\|probe:\[a-z0-9_\]\+\)'/);
  assert.match(sqlText, /create trigger trg_llm_route_health_founder_hold before update or delete on public\.llm_route_health/);
  assert.match(sqlText, /create trigger trg_app_secrets_no_paid_ai_founder_switch before update or delete on public\.app_secrets/);
  const rec = sqlText.slice(sqlText.indexOf('CREATE OR REPLACE FUNCTION public.fn_record_llm_attempt'));
  assert.ok(rec.length > 100, 'fn_record_llm_attempt is redefined here');
  assert.doesNotMatch(code(rec), /open_until = null/, 'a success must not null open_until unconditionally');
  assert.match(rec, /open_until\s+= case when public\.fn_llm_route_founder_held\(open_until\) then open_until end/);
  assert.match(rec, /and not public\.fn_llm_route_founder_held\(open_until\);/);
  for (const f of ['fn_llm_route_founder_held(timestamptz)', 'fn_founder_hold_change_allowed()',
    'fn_llm_route_health_founder_hold_guard()', 'fn_app_secrets_no_paid_ai_guard()']) {
    assert.ok(sqlText.includes(`revoke execute on function public.${f} from public, anon, authenticated`), f);
  }
});

test('no routine, script, function or workflow carries the founder\'s release reason', () => {
  const bad = files.filter((f) => f.rel !== SELF && FOUNDER_REASON.test(code(f.src))).map((f) => f.rel);
  assert.deepEqual(bad, [], 'only the founder releases the hold; no file may set founder:<id>');
});

test('outside the SQL history, only an aborted, named probe writes the hold, and it says so', () => {
  const bad = [];
  for (const f of files) {
    if (f.rel.startsWith('scripts/sql/') || f.rel === SELF) continue;   // routine bodies are read live below
    const c = code(f.src);
    if (!WRITES_HOLD.test(c) && !/app_secrets[\s\S]{0,200}no_paid_ai/i.test(c.match(/(update|delete\s+from)\s+(public\.)?app_secrets[^;]*/gi)?.join('\n') ?? '')) continue;
    if (!/set_config\('app\.change_reason', 'probe:[a-z0-9_]+', true\)|app\.change_reason = 'probe:/.test(c)) bad.push(`${f.rel}: writes the hold without a probe: reason`);
    if (!/raise exception 'CHK<</.test(c)) bad.push(`${f.rel}: writes the hold outside a probe that raises (it could commit)`);
  }
  assert.deepEqual(bad, []);
});

test('the sandbox harness and the gateway never write the hold; a tagged call goes through the gate', () => {
  for (const rel of ['scripts/e2e/stage2.mjs', 'scripts/lib/demo_factory.mjs', 'scripts/e2e/run.mjs']) {
    const f = files.find((x) => x.rel === rel);
    if (!f) continue;
    assert.doesNotMatch(code(f.src), WRITES_HOLD, rel);
    assert.doesNotMatch(code(f.src), /no_paid_ai/, rel);
  }
  // ai_gateway, including think.ts once the stage-2 gateway fix lands: it may let a TAGGED call through only
  // because fn_kernel_paid_provider_gate said so (an open window for that tag); it never edits route state.
  for (const f of files.filter((x) => x.rel.startsWith('supabase/functions/ai_gateway/'))) {
    assert.doesNotMatch(code(f.src), WRITES_HOLD, f.rel);
    assert.doesNotMatch(code(f.src), /open_until\s*[:=]/, f.rel);
    if (/e2eRunTag|x-qd-e2e-run|rehearsal/i.test(code(f.src))) {
      const gw = files.filter((x) => x.rel.startsWith('supabase/functions/ai_gateway/')).map((x) => x.src).join('\n');
      assert.match(gw, /fn_kernel_paid_provider_gate|fn_llm_preflight/, `${f.rel} reads a run tag; the gate must still decide`);
    }
  }
  // no workflow flips settings when a run passes
  for (const f of files.filter((x) => x.rel.startsWith('.github/'))) {
    assert.doesNotMatch(code(f.src), WRITES_HOLD, f.rel);
    assert.doesNotMatch(code(f.src), /no_paid_ai/, f.rel);
  }
});

// ---- production -------------------------------------------------------------------------------------
const PROBE = `
do $p$
declare
  h_before text; h_after text; s_before text; s_after text; o jsonb := '{}'; g jsonb; m text := 'google/gemini-3.8-flash';
  c_tag text := 'zzholdprobe';
begin
  -- Ledger 1175 (7 Oct 2026) lifted the founder's hold on production, so nothing is held there. The property this
  -- check guards (a sandbox success never lifts a hold) is still proved: a founder hold is planted on the probe's
  -- route inside this aborted transaction, then the change reason is cleared so the guard is armed again.
  perform set_config('app.change_reason', 'probe:a_sandbox_success_never_lifts_the_model_hold', true);
  update public.llm_route_health set open_until = now() + interval '100 years',
         opened_reason = 'HELD BY THE FOUNDER (probe: a_sandbox_success_never_lifts_the_model_hold)' where model_id = m;
  perform set_config('app.change_reason', '', true);
  select md5(string_agg(model_id || '|' || coalesce(open_until::text,'') || '|' || coalesce(opened_reason,'') || '|' || coalesce(opened_class,''), ',' order by model_id))
    into h_before from public.llm_route_health;
  select md5(coalesce(string_agg(key || '=' || coalesce(value,''), ','), '')) into s_before from public.app_secrets where key = 'no_paid_ai';
  o := o || jsonb_build_object('held_routes', (select count(*) from public.llm_route_health where open_until > now() + interval '1 year'),
                               'routes', (select count(*) from public.llm_route_health));

  -- a stage-2 window opens for a tagged run
  insert into public.rehearsal_window (run_tag, opened_by, models_allowed, cap_usd, expires_at)
  values ('qd_run:' || c_tag, 'probe:a_sandbox_success_never_lifts_the_model_hold', true, 1, now() + interval '1 hour');
  perform set_config('app.e2e_run_tag', c_tag, true);
  g := public.fn_kernel_paid_provider_gate(m);
  o := o || jsonb_build_object('tagged_gate', coalesce(g->>'rule', '') || ':' || coalesce(g->>'allowed', ''));

  -- the run "passes": its call succeeds; another trips a breaker
  perform public.fn_record_llm_attempt(jsonb_build_object('model_route', m, 'ok', true, 'fn', 'zz_hold_probe', 'latency_ms', 10));
  perform public.fn_record_llm_attempt(jsonb_build_object('model_route', m, 'ok', false, 'fn', 'zz_hold_probe',
    'http_status', 401, 'err_excerpt', 'auth failed invalid api key', 'latency_ms', 10));

  -- the window closes
  update public.rehearsal_window set ended_at = now(), models_allowed = false where run_tag = 'qd_run:' || c_tag;
  perform set_config('app.e2e_run_tag', '', true);
  g := public.fn_kernel_paid_provider_gate(m);
  o := o || jsonb_build_object('untagged_gate_after', coalesce(g->>'rule', '') || ':' || coalesce(g->>'allowed', ''));

  -- nobody but the founder may clear it directly either
  begin
    update public.llm_route_health set open_until = null where model_id = m;
    o := o || jsonb_build_object('direct_clear', 'ALLOWED');
  exception when others then
    o := o || jsonb_build_object('direct_clear', case when sqlerrm like 'FOUNDER_HOLD:%' then 'refused' else 'error: ' || left(sqlerrm, 80) end);
  end;

  select md5(string_agg(model_id || '|' || coalesce(open_until::text,'') || '|' || coalesce(opened_reason,'') || '|' || coalesce(opened_class,''), ',' order by model_id))
    into h_after from public.llm_route_health;
  select md5(coalesce(string_agg(key || '=' || coalesce(value,''), ','), '')) into s_after from public.app_secrets where key = 'no_paid_ai';
  o := o || jsonb_build_object('hold_identical', h_before = h_after, 'switch_identical', s_before = s_after,
    'route_after', (select coalesce(open_until::text, 'NULL') from public.llm_route_health where model_id = m));
  raise exception 'CHK<<%>>', o::text;
end $p$;`;

test('production: the only routine that writes the hold is the guarded recorder, and none carries a founder reason', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`select p.oid::regprocedure::text sig,
      p.prosrc ~* '(update|delete\\s+from)\\s+(public\\.)?llm_route_health' w_route,
      p.prosrc ~* '(update|delete\\s+from|insert\\s+into)\\s+(public\\.)?app_secrets' and p.prosrc ~* 'no_paid_ai' w_switch,
      p.prosrc ~ 'founder:[0-9]' founder_reason,
      p.prosrc like '%fn_llm_route_founder_held%' guarded
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
      and (p.prosrc ~* 'llm_route_health|no_paid_ai' or p.prosrc ~ 'founder:[0-9]')`, { readOnly: true });
  const [t] = await sql(`select count(*)::int n from pg_trigger where tgname in ('trg_llm_route_health_founder_hold','trg_app_secrets_no_paid_ai_founder_switch')`, { readOnly: true });
  const applied = t.n === 2;
  const bad = [];
  for (const r of rows) {
    if (r.founder_reason) bad.push(`${r.sig}: carries a founder: reason`);
    if (r.w_switch) bad.push(`${r.sig}: writes app_secrets no_paid_ai`);
    if (r.w_route && r.sig !== 'fn_record_llm_attempt(jsonb)') bad.push(`${r.sig}: writes llm_route_health`);
    if (applied && r.sig === 'fn_record_llm_attempt(jsonb)' && !r.guarded) bad.push('fn_record_llm_attempt: not guarded by fn_llm_route_founder_held');
  }
  console.log(JSON.stringify({ applied, routines_read: rows.length, findings: bad }));
  assert.deepEqual(bad, []);
});

test('production, one aborted transaction: a window opens, the run passes, the window closes, the hold is byte-identical', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { replaySql } = await import('../lib/safe_replay.mjs');
  const body = (process.env.HOLD_NO_REPLAY === '1' ? '' : sqlText + '\n') + PROBE;
  let out;
  try { await replaySql(body, { retry: false }); } catch (e) {
    const mm = String(e.message).match(/CHK<<(.*?)>>/s);
    if (!mm) throw e;
    out = JSON.parse(mm[1].replace(/\\"/g, '"'));
  }
  assert.ok(out, 'the probe committed instead of rolling back');
  console.log(JSON.stringify(out));
  assert.ok(out.held_routes > 0, 'nothing is held: the probe would prove nothing');
  assert.equal(out.hold_identical, true, `the hold changed during a sandbox run (route after: ${out.route_after})`);
  assert.equal(out.switch_identical, true);
  assert.match(out.tagged_gate, /^rehearsal_window:true$/, 'a tagged call inside its open window passes the hold');
  assert.match(out.untagged_gate_after, /^founder_hold:false$/, 'after the window closes, untagged traffic meets the hold');
  if (process.env.HOLD_NO_REPLAY !== '1') assert.equal(out.direct_clear, 'refused');
});
