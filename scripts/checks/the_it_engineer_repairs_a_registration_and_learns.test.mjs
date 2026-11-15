// THE IT ENGINEER REPAIRS A REGISTRATION AND LEARNS (it_engineer, 15 Nov 2026; founder rulings 1574, 1705, 1706).
// Measured that day (SP/audit/SUPPORT_IT.md): the charter row said "It never repairs production itself"; 8 safe-fix families,
// none on the registration path, while 368 licence reads failed on an open circuit, 19 acceptances produced no certificate and
// >= 54 SMS sign-ins were refused for a shared mobile; 0 support.root_cause hand-overs reached it_engineer; it_session_fix_day
// was never read.
// Fix: scripts/sql/support_and_the_it_engineer_hand_a_fault_both_ways.sql, a_code_defect_goes_to_the_engineer_session.sql,
//      the_it_engineer_repairs_a_registration_and_learns.sql, the_it_engineer_repairs_within_its_guardrails.sql (in that order),
//      _shared/support_fault_handover.ts, docs/runbooks/the-code-defect-session.md.
//   env -u SUPABASE_ACCESS_TOKEN -u SUPABASE_DB_URL QD_LOCAL_DB_URL="$(node scripts/db/local_pg16.mjs url)" \
//     node --test scripts/checks/the_it_engineer_repairs_a_registration_and_learns.test.mjs
// The replay runs ONLY on the local database (the target is QD_LOCAL_DB_URL, never production); without one it is skipped.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILES = ['scripts/sql/support_and_the_it_engineer_hand_a_fault_both_ways.sql', 'scripts/sql/a_code_defect_goes_to_the_engineer_session.sql',
  'scripts/sql/the_it_engineer_repairs_a_registration_and_learns.sql', 'scripts/sql/the_it_engineer_repairs_within_its_guardrails.sql'];
const PROBE = 'scripts/sql/the_it_engineer_repairs_a_registration_and_learns_probe.sql';
const FAMILIES = ['licence_read_rerun', 'terms_certificate_retry', 'code_resend_assist', 'held_registration_explain', 'duplicate_mobile_guide',
  'stuck_job_rerun', 'route_failover'];
const strip = (s) => s.replace(/--[^\n]*/g, '').replace(/'(?:[^']|'')*'/g, "''");
const bodyOf = (src, fn) => {
  const i = src.indexOf(`create or replace function public.${fn}(`);
  assert.ok(i >= 0, `${fn} is not defined`);
  const j = src.indexOf('$fn$;', i);
  return src.slice(i, j);
};

test('every routine of the four files is SECURITY DEFINER, pinned and revoked by its exact signature', () => {
  for (const f of FILES) {
    const src = read(f);
    for (const m of src.matchAll(/create or replace function public\.([a-z0-9_]+)\(/g)) {
      assert.match(src, new RegExp(`revoke execute on function public\\.${m[1]}\\(`), `${f}: ${m[1]} is not revoked`);
      const b = bodyOf(src, m[1]);
      assert.match(b, /set search_path to 'p(?:ublic|g_catalog)', 'pg_temp'/, `${f}: ${m[1]} has no pinned search_path`);
    }
    assert.doesNotMatch(src, /^\s*(begin|commit)\s*;/im, `${f} carries its own transaction`);
    assert.match(src, /select case when problems is null then 'PROBE OK'/, `${f} has no verdict row`);
  }
});

test('the seven families carry ruling 1705, a routine and a stated guardrail, and are dispatched by the one dispatcher', () => {
  const src = read(FILES[2]);
  for (const f of FAMILIES) assert.match(src, new RegExp(`\\('${f}', '[^']+', 'fn_it_safe_fix_${f}',`), `${f} is not registered with its routine`);
  assert.equal((src.match(/, 1705, true,/g) || []).length, FAMILIES.length, 'every family carries ruling 1705');
  const tick = bodyOf(src, 'fn_it_safe_fix_tick');
  for (const re of [/< fam\.max_runs_per_occurrence/, /exit when n >= fam\.max_per_tick/, /outcome = 'failed' and r\.ran_at > now\(\) - interval '1 day'\) >= 2/,
    /qd\.safe_fix_only_ruling/, /insert into public\.it_safe_fix_run/]) assert.match(tick, re, `the dispatcher lost ${re}`);
  const watch = bodyOf(src, 'fn_it_registration_watch');
  assert.match(watch, /set_config\('qd\.safe_fix_only_ruling', '1705', true\)/, 'the watch does not repair at once');
  assert.match(watch, /set_config\('qd\.safe_fix_only_ruling', '', true\)/, 'the watch leaves the filter on for the rest of the transaction');
});

test('no family routine deletes, approves, bans, writes a licence value, touches money or weakens a gate', () => {
  const src = read(FILES[2]);
  for (const f of FAMILIES) {
    const code = strip(bodyOf(src, `fn_it_safe_fix_${f}`));
    assert.doesNotMatch(code, /\bdelete\s+from\b|\btruncate\b|\bdrop\s+/i, `${f} deletes`);
    assert.doesNotMatch(code, /\b(approval_status|approved_at|verified|banned|banned_reason|trade_license_no|license_expiry|license_authority|license_activity|licence_gate_reason|company_name)\s*=/i,
      `${f} writes an approval, a ban or a licence value`);
    assert.doesNotMatch(code, /\b(insert\s+into|update)\s+public\.(transactions|refunds|refund_case|supplier_dues|gl_journal|expense_entries|quotes|inquiries|email_suppressions|otp_blocked_prefix|app_secrets)\b/i,
      `${f} writes money, a quote, a suppression, an OTP gate or a secret`);
    if (f !== 'licence_read_rerun') assert.doesNotMatch(code, /\bupdate\s+public\.leads\b/i, `${f} writes a lead`);
  }
  // the one lead write, and only the reader's own schedule: never its tries (review of f79833d44, FIX 2: tries 8 is the reader's
  // deliberate stop for a file held for a person and a wrong document, supplier_api/actions/documents.ts)
  const rerun = strip(bodyOf(src, 'fn_it_safe_fix_licence_read_rerun'));
  const m = rerun.match(/update public\.leads set ([^;]*?) where/i);
  assert.ok(m, 'licence_read_rerun names its write');
  assert.deepEqual([...m[1].matchAll(/(?:^|,)\s*([a-z_]+)\s*=/g)].map((x) => x[1]).sort(), ['licence_read_at']);
  assert.match(bodyOf(src, 'fn_it_safe_fix_licence_read_rerun'), /licence_read_tries >= 8 then\s*return jsonb_build_object\('outcome', 'refused_by_guardrail'/,
    'a licence the reader stopped on is not refused');
});

test('review of f79833d44: the budget counts attempts, one dispatcher at a time, the watch never rolls back, the plan B waits for its eval', () => {
  const src = read(FILES[2]);
  const tick = bodyOf(src, 'fn_it_safe_fix_tick');
  assert.match(tick, /r\.outcome in \('fixed', 'failed'\)\) < fam\.max_runs_per_occurrence/, 'FIX 1: a refusal spends the run budget');
  assert.match(tick, /if not v_same then\s*insert into public\.it_safe_fix_run/, 'FIX 1: an unchanged refusal is written every tick');
  const watch = bodyOf(src, 'fn_it_registration_watch');
  for (const b of [tick, watch]) assert.match(b, /pg_try_advisory_xact_lock\(hashtext\('public\.it_safe_fix_dispatch'\)\)/, 'FIX 9: no lock between the hourly tick and the watch');
  assert.match(tick, /if v_only is null then\s*insert into public\.agent_runs/, 'FIX 9: the watch writes playbook agent_runs rows');
  // restore, each finding of the close step, raise and classify each have their own handler; the repair step has its own too
  assert.ok((watch.match(/exception when others then v_errors := v_errors \|\|/g) || []).length >= 4, 'FIX 5: a watch step has no handler');
  assert.match(watch, /v_errors := v_errors \|\| jsonb_build_object\('step', 'repair'/, 'FIX 5: the repair step has no handler');
  assert.doesNotMatch(src, /left\(md5\([^)]*phone/i, 'FIX 9: the shared-mobile key is md5 of the phone');
  assert.doesNotMatch(src, /'email', v_email\), '\{\}'::jsonb, '\{"Content-Type"/, 'FIX 9: the certificate retry sends an address');
  assert.doesNotMatch(src, /\('json_extraction(?:_text)?', 'anthropic\/claude-sonnet-5\.5'/, 'FIX 8: the dead sonnet plan B is seeded');
  assert.match(src, /\('document_extraction', 'qwen\/qwen3\.8-flash',[\s\S]*?'ceo', false, 'one licence-read eval on ZZ DEMO licences/, 'FIX 8: no pending qwen plan B for the licence reader');
  assert.match(src, /it_route_plan_b_eval_before_active/, 'FIX 8: a plan B can be active without its eval');
  const defect = read(FILES[1]);
  assert.match(defect, /check \(cardinality\(affected_cases\) <= 200\)/);
  assert.match(defect, /affected_count integer not null default 0/, 'FIX 5: no count beside the sample');
  assert.match(bodyOf(defect, 'fn_it_code_defect_progress'), /v_to not in \(v_at, v_at \+ 1\)/, 'FIX 7: a step can be skipped');
  assert.match(read(FILES[0]), /fn_it_told_recently\(v_to, 'fixed'\) is not null then return false/, 'FIX 3: one person can hear "fixed" twice');
  assert.match(read('supabase/functions/site_assistant/index.ts'), /email: who\?\.email \?\? null/, 'FIX 9: the widget does not pass the signed-in e-mail');
  assert.match(read('scripts/eval/model_routing/eval_licence_plan_b.ts'), /qwen\/qwen3\.8-flash/, 'FIX 8: no eval for the plan B');
});

test('the charter says repair, keeps every refusal tag, and routes no repair to the founder', () => {
  const src = read(FILES[3]);
  assert.doesNotMatch(src.match(/responsibilities =[\s\S]*?owned_decisions/)[0], /never repairs/i);
  for (const t of ['deploy', 'code_change', 'production_config', 'data_mutation', 'approval', 'licence_value', 'money', 'gate', 'job_rerun', 'ceo_direction']) {
    assert.match(src, new RegExp(`'\\[${t}\\] [A-Z]`), `the charter lost the [${t}] refusal`);
  }
  assert.doesNotMatch(src.match(/forbidden_decisions = array\[[\s\S]*?\],\n  activation_conditions/)[0], /the route is the founder/i);
  assert.match(src, /it_code_defect/, 'the charter does not name the engineer session');
  assert.match(src, /set active = true[\s\S]*?it_rerunnable_job/, 'job_rerun is not bounded by its register');
});

test('support hands a fault over through the model\'s reading, and the engineer session has its prompt', () => {
  const dec = read('supabase/functions/_shared/reasoned_decisions.ts');
  assert.match(dec, /id: 'site_fault'/, 'needs_a_person has no site_fault option');
  assert.match(dec, /if \(fault && o\.fault\) await handFaultToIt/, 'a site_fault is not handed over');
  for (const f of ['supabase/functions/site_assistant/index.ts', 'supabase/functions/email_triage/index.ts', 'supabase/functions/wa_inbound/classification.ts']) {
    assert.match(read(f), /support_fault_handover\.ts/, `${f} does not hand a fault over`);
  }
  assert.match(read('supabase/functions/_shared/support_reply.ts'), /r\.route === 'it_engineer' && req\.handover/, 'support_reply only names the IT engineer');
  const rb = read('docs/runbooks/the-code-defect-session.md');
  for (const step of ['fn_it_code_defect_queue', 'fn_it_code_defect_claim', 'FAILING TEST', 'ANOTHER model family', 'npm run gate -- --offline',
    'release-without-ci.md', 'fn_it_code_defect_verified', 'fn_it_attach_learning', 'remedy_routine', 'fn_case_record_verified_resolution',
    '.claude/memory', 'compile_brief', 'it.defect_fixed', 'create_new_session_on_fire']) assert.ok(rb.includes(step), `the runbook lacks: ${step}`);
});

const local = process.env.QD_LOCAL_DB_URL;
test('LOCAL database, rolled back: each planted failure is repaired once, refused where the guardrail says, and the person told once',
  { skip: local ? false : 'no local database (QD_LOCAL_DB_URL): this replay never runs on production' }, async () => {
    const { replaySql } = await import('../lib/safe_replay.mjs');
    // the four files twice (they must replay cleanly over themselves), then the probe
    const text = "set local lock_timeout = '1s';\nset local statement_timeout = '120s';\n" + [...FILES, ...FILES, PROBE].map(read).join('\n;\n');
    let verdict = null;
    try { await replaySql(text, { target: local, label: 'the self-healing probe', retry: false }); } catch (e) {
      const msg = String(e?.body ?? e?.message ?? e);
      verdict = (msg.match(/(PROBE (?:OK|FAILED|REFUSED)[^\n]*)/) || [])[1] ?? ('the replay failed before its probe could report: ' + msg.slice(0, 2000));
    }
    assert.ok(verdict, 'the probe returned without raising: it would have committed');
    assert.match(verdict, /^PROBE OK/, verdict);
  });
