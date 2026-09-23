// DECISION POINTS ARE REASONED, NOT WORD-MATCHED (23 Sep 2026, it_engineer; founder_instruction 886-903).
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: a decision point registered as migrated in supabase/functions/_shared/decision_points.json
//     goes back to a word list (its must_not_contain reappears in CODE — comments are stripped first, so
//     the header that quotes the old regex does not indict itself), or loses its think() call;
//   * static: the registry points at a file that does not exist, or the evaluation harness is missing;
//   * static: either SQL file gains a begin/commit, a routine without a revoke, or a table without RLS + policy;
//   * production, inside ONE aborted transaction (both files replayed first while they are pending, so
//     nothing survives and nothing can reach a person):
//       - fn_wa_route escalates "is it legal to build a pool?" without being told to, or does not escalate
//         when the reasoning says so, or the 3-argument overload survives;
//       - a founder command is routed before it is understood, or fn_ceo_classify still exists;
//       - fn_rfq_required_check counts a required spec as answered because an option word is in the text;
//       - the held queue, the replay gate, retrieval by meaning or the research write-back misbehave;
//       - anon or authenticated can execute any new routine.
//
//   node --test scripts/checks/decision_points_are_reasoned.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const REGISTRY = JSON.parse(read('supabase/functions/_shared/decision_points.json'));
const ENGINE = 'scripts/sql/every_seat_reasons_before_it_answers.sql';
const MIGRATE = 'scripts/sql/meaning_is_decided_by_reasoning_not_by_word_lists.sql';
// The resolver that calls fn_reason_apply_<surface> (one routine per migrated surface, one file per batch).
const DISPATCH = 'scripts/sql/a_reasoned_answer_is_applied_by_its_own_surface.sql';
// Every SQL file a migrated point's proof names, in registry order after the three the engine needs:
// the batch files replay in this order inside a probe, and each must be replay-safe (the test below).
const BATCH_SQL = [...new Set(REGISTRY.points.filter((p) => p.status === 'migrated').flatMap((p) => (p.proof ?? []).map((x) => x.file))
  .filter((f) => f.startsWith('scripts/sql/') && f.endsWith('.sql') && ![ENGINE, MIGRATE, DISPATCH, 'scripts/sql/a_held_question_never_expires_it_is_escalated_at_48_hours.sql'].includes(f)))];
// A held question never expires; at 48 hours it is escalated to its seat (applies after DISPATCH).
const LIFECYCLE = 'scripts/sql/a_held_question_never_expires_it_is_escalated_at_48_hours.sql';
const CHAIN = [ENGINE, MIGRATE, DISPATCH, LIFECYCLE, ...BATCH_SQL];

/** Code only: SQL `--` comments and TS `//` line comments removed (a check that greps source matches its own comment). */
function code(path, text) {
  if (path.endsWith('.sql')) return text.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
  return text.split('\n').filter((l) => !/^\s*\/\//.test(l)).map((l) => l.replace(/\s\/\/ .*$/, '')).join('\n');
}

test('the registry is the whole list, ordered, and points at nothing that is not there', () => {
  const pts = REGISTRY.points;
  assert.ok(pts.length >= 70, `the audit found 70+ class (i) decision points; the registry lists ${pts.length}`);
  assert.deepEqual(pts.map((p) => p.order), pts.map((_, i) => i + 1), 'orders are 1..n with no gap');
  assert.equal(new Set(pts.map((p) => p.id)).size, pts.length, 'ids are unique');
  for (const p of pts) {
    assert.ok(['migrated', 'pending'].includes(p.status), p.id);
    assert.ok(['customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing', 'ceo'].includes(p.seat), `${p.id}: ${p.seat} is not a seat`);
    assert.ok(existsSync(join(REPO, p.where)), `${p.id}: ${p.where} does not exist`);
  }
  assert.ok(pts.filter((p) => p.status === 'migrated').length >= 5, 'the five top critical points are migrated in this build');
});

test('no migrated decision point is decided by a word list again, and each one asks think()', () => {
  for (const p of REGISTRY.points.filter((x) => x.status === 'migrated')) {
    assert.ok(Array.isArray(p.proof) && p.proof.length, `${p.id}: a migrated point needs a proof`);
    for (const pr of p.proof) {
      const src = code(pr.file, read(pr.file));
      for (const s of pr.must_contain ?? []) assert.ok(src.includes(s), `${p.id}: ${pr.file} no longer contains ${s}`);
      for (const s of pr.must_not_contain ?? []) assert.ok(!src.includes(s), `${p.id}: ${pr.file} is word-matching again (${s})`);
    }
  }
  // A point migrated by a batch (order > 18) names the word matching it replaced, so a regression is caught
  // by fingerprint and not only by a missing call: at least one must_not_contain across its proofs.
  for (const p of REGISTRY.points.filter((x) => x.status === 'migrated' && x.order > 18)) {
    assert.ok(p.proof.some((pr) => (pr.must_not_contain ?? []).length), `${p.id}: a migrated point names the word matching it replaced (must_not_contain)`);
    assert.ok(typeof p.held === 'string' && p.held.length > 20, `${p.id}: a migrated point says what happens under the hold (held)`);
  }
  // the engine every migrated point goes through
  const th = read('supabase/functions/_shared/think.ts');
  for (const s of ["deps.rpc('fn_reason_retrieve'", "deps.rpc('fn_case_recall'", "deps.rpc('fn_reason_hold'", "deps.rpc('fn_reason_propose_knowledge'", 'counterpartModel: model', 'refuse(draft']) {
    assert.ok(th.includes(s), `think.ts lost ${s}`);
  }
  assert.match(read('supabase/functions/resilience_ping/index.ts'), /step\('reasoning_held', async \(\) => replayHeld\(admin, 3, undefined, \(row, r\) => deliverReasoned\(row, r, liveDeliveryIO\(admin\)\)\)\)/);
});

test('provider webhooks are acknowledged at once and handled after (reasoning never runs inside Twilio\'s or Meta\'s deadline)', () => {
  assert.match(read('supabase/functions/wa_inbound/index.ts'), /return ackThenWork\(TW\(200\), \(\) => handleInbound\(copy\), 'wa_inbound'\);/);
  assert.match(read('supabase/functions/marketing_social_inbox/index.ts'), /return ackThenWork\(new Response\(/);
  // the timing itself is proved in supabase/functions/_shared/async_webhook.test.ts (ack < 100 ms while the work runs on)
  assert.match(read('supabase/functions/_shared/async_webhook.test.ts'), /ms < 100/);
});

test('the migrated SQL routines read no free text for meaning: no ~*, ilike or like-on-text in their bodies', () => {
  const sql = code(MIGRATE, read(MIGRATE));
  const body = (name) => { const a = sql.indexOf('function public.' + name + '('); const b = sql.indexOf('$function$;', a); assert.ok(a > 0 && b > a, name); return sql.slice(a, b); };
  const wa = body('fn_wa_route');
  assert.equal((wa.match(/~\*|ilike/g) || []).length, 0, 'fn_wa_route matches meaning again');
  assert.doesNotMatch(body('fn_rfq_required_check'), /i\.(summary|raw_input)/, 'fn_rfq_required_check reads the free text again');
  assert.doesNotMatch(body('fn_ceo_command_submit'), /pattern|position\(/, 'fn_ceo_command_submit matches patterns again');
});

test('the evaluation harness exists, holds the founder\'s example, and passes in mock mode with its adversarial passes', () => {
  assert.match(read('scripts/eval/reasoning_eval.mjs'), /await think\(/);
  const bank = JSON.parse(read('scripts/eval/reasoning_bank.json')).cases;
  assert.ok(bank.some((c) => /build a pool at my villa/i.test(c.q) && c.expect.asked_back === true), 'the founder\'s pool example is in the bank');
  for (const seat of ['customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing', 'ceo']) assert.ok(bank.some((c) => c.seat === seat), `no ${seat} case`);
  const r = spawnSync(process.execPath, [join(REPO, 'scripts/eval/reasoning_eval.mjs')], { encoding: 'utf8', timeout: 120_000 });
  assert.equal(r.status, 0, 'the harness failed:\n' + (r.stdout + r.stderr).slice(-2000));
  assert.match(r.stdout, /HARNESS OK/);
});

test('the SQL files replay safely: no begin/commit, a revoke per routine, RLS and a policy per table, a pending note each', () => {
  const manifest = read('scripts/sql/MANIFEST.txt');
  for (const f of CHAIN) {
    const sql = code(f, read(f));
    assert.doesNotMatch(sql, /^\s*(begin|commit)\s*;/im, `${f}: no begin/commit — the probe replays it inside an aborted transaction`);
    for (const m of sql.matchAll(/create (?:or replace )?function public\.([a-z0-9_]+)\(/g)) {
      assert.match(sql, new RegExp(`revoke execute on function public\\.${m[1]}\\(`), `${f}: ${m[1]} has no revoke`);
      assert.match(sql.slice(m.index, m.index + 600), /search_path to 'public', 'pg_temp'/, `${f}: ${m[1]} has no pinned search_path`);
    }
    for (const m of sql.matchAll(/create table if not exists public\.([a-z0-9_]+)/g)) {
      assert.match(sql, new RegExp(`alter table public\\.${m[1]} enable row level security`), `${m[1]}: RLS`);
      assert.match(sql, new RegExp(`create policy \\w+ on public\\.${m[1]}`), `${m[1]}: policy`);
    }
    const base = f.split('/').pop();
    const note = existsSync(join(REPO, 'scripts/sql/pending', base.replace(/\.sql$/, '.txt')));
    assert.ok(note !== manifest.split(/\r?\n/).includes('scripts/sql/' + base), `${base}: exactly one of a pending note and a MANIFEST line`);
  }
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
/** Every file of the chain still pending (a note in scripts/sql/pending, no MANIFEST line), in order: what a probe
 *  replays inside its aborted transaction so it measures the committed code, not only what production has.
 *  A pending file whose every routine production ALREADY carries verbatim (prosrc) is not replayed: re-running it
 *  would test nothing new and can fail on a privileged SET the probe role may not issue (measured 23 Sep 17:45:
 *  #884's two files were live on production, unrecorded, and replaying them failed 42723 / 42501). */
async function pendingReplay() {
  const { sql } = await import('../lib/db.mjs');
  const out = [];
  for (const f of CHAIN.filter((x) => existsSync(join(REPO, 'scripts/sql/pending', x.split('/').pop().replace(/\.sql$/, '.txt'))))) {
    const text = read(f);
    const bodies = [...text.matchAll(/create (?:or replace )?function public\.([a-z0-9_]+)\([\s\S]*?\$(\w*)\$([\s\S]*?)\$\2\$/g)].map((m) => [m[1], m[3].trim()]);
    let live = false;
    if (bodies.length) {
      const names = [...new Set(bodies.map(([n]) => n))];
      const rows = await sql(`select proname, prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = any(array[${names.map((n) => `'${n}'`).join(',')}])`, { readOnly: true });
      live = bodies.every(([n, b]) => rows.some((r) => r.proname === n && String(r.prosrc).trim() === b));
    }
    if (!live) out.push(text);
  }
  return out.join('\n') + '\n';
}
/** Runs a DO block that ends in raise exception 'CHK<<json>>' after the pending chain; returns the json. Nothing commits. */
async function probe(block, prefix = '') {
  const { sql } = await import('../lib/db.mjs');
  try { await sql(prefix + (await pendingReplay()) + block, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 600));
    return JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.fail('the probe committed instead of rolling back');
}


const PROBE = String.raw`
do $p$
declare
  o jsonb := '{}'::jsonb; v jsonb; v_id bigint; v_cmd bigint; v_intake uuid; e text; v_vec vector(384); v_i public.inquiries;
begin
  -- 1. WhatsApp: a question that mentions law is not a complaint; the reasoned answer decides.
  v := public.fn_wa_route('+971500000000', 'is it legal to build a pool in my garden?', false, null);
  o := o || jsonb_build_object('legal_q_person', v->>'needs_a_person', 'legal_q_by', v->>'person_decided_by');
  v := public.fn_wa_route('+971500000000', 'you took my money and vanished', false, true);
  o := o || jsonb_build_object('complaint_person', v->>'needs_a_person', 'complaint_opened', v->>'opened_by', 'complaint_by', v->>'person_decided_by');
  v := public.fn_wa_route('+971500000000', 'I have a complaint about a refund dispute', false, false);
  o := o || jsonb_build_object('words_but_reasoned_no', v->>'needs_a_person');
  o := o || jsonb_build_object('old_overload', to_regprocedure('public.fn_wa_route(text,text,boolean)') is not null);

  -- 2. The founder's command: recorded, not routed, until understood.
  select command_id into v_cmd from public.fn_ceo_command_submit('api', 'ZZ DEMO probe', 'ZZ DEMO check why the refund failed');
  select jsonb_build_object('intent', intent_id, 'state', state) into v from public.ceo_command where command_id = v_cmd;
  o := o || jsonb_build_object('submitted', v, 'tasks_before', (select count(*) from public.ceo_task where command_id = v_cmd));
  v := public.fn_ceo_command_interpret(v_cmd, 'fix', 'ZZ DEMO something is broken');
  o := o || jsonb_build_object('interpreted', v->>'state', 'interpreted_intent', v->>'intent', 'tasks_after', (select count(*) from public.ceo_task where command_id = v_cmd));
  o := o || jsonb_build_object('interpret_again', public.fn_ceo_command_interpret(v_cmd, 'build')->>'changed');
  begin perform public.fn_ceo_command_interpret(v_cmd, 'not_an_intent'); o := o || '{"bad_intent":"accepted"}'; exception when others then o := o || jsonb_build_object('bad_intent', sqlstate); end;
  o := o || jsonb_build_object('classify_exists', to_regprocedure('public.fn_ceo_classify(text)') is not null);

  -- 3. Exact spec: an option WORD in the text no longer answers the field; a keyed answer does.
  v_i := jsonb_populate_record(null::public.inquiries, jsonb_build_object('category', 'flooring', 'raw_input', 'ZZ DEMO we want vinyl flooring, supply installation, remove existing', 'summary', 'ZZ DEMO vinyl'));
  o := o || jsonb_build_object('text_only_present', public.fn_rfq_required_check(v_i)->'present');
  v_i := jsonb_populate_record(null::public.inquiries, jsonb_build_object('category', 'flooring', 'raw_input', 'ZZ DEMO', 'spec', jsonb_build_object('floor_type', 'Vinyl/LVT')));
  o := o || jsonb_build_object('keyed_present', public.fn_rfq_required_check(v_i)->'present');

  -- 4. The held queue, the replay gate, and the resolver's SQL effect.
  v_id := public.fn_reason_hold('ceo', 'ceo.command_intent', 'ZZ DEMO stop the campaign', '{"seat":"ceo"}'::jsonb, '{}'::jsonb,
            jsonb_build_object('command_id', (select command_id from public.fn_ceo_command_submit('api', 'ZZ DEMO probe', 'ZZ DEMO stop the campaign'))), 'model_hold', 'zz-demo-probe-1');
  o := o || jsonb_build_object('hold_dedupe', public.fn_reason_hold('ceo', 'ceo.command_intent', 'ZZ DEMO again', '{"seat":"ceo"}'::jsonb, '{}'::jsonb, null, 'model_failed: x', 'zz-demo-probe-1') = v_id);
  o := o || jsonb_build_object('gate_rule', public.fn_kernel_paid_provider_gate('hold-probe/not-a-model')->>'rule', 'due_under_gate', public.fn_reason_held_due(3));
  o := o || jsonb_build_object('resolve_held', public.fn_reason_held_resolve(v_id, '{"status":"held"}'::jsonb)->>'status',
                               'resolve_answered', public.fn_reason_held_resolve(v_id, '{"status":"answered","answer":"ZZ DEMO halt","decision":{"choice":"stop"}}'::jsonb)->>'status');
  select jsonb_build_object('row', h.status, 'cmd', c.state || ':' || c.intent_id) into v
    from public.reasoning_held_question h join public.ceo_command c on c.command_id = (h.subject->>'command_id')::bigint where h.id = v_id;
  o := o || jsonb_build_object('resolved', v);

  -- 5. Retrieval by meaning, and research written back as pending knowledge.
  select embedding_gte into v_vec from public.kb_chunks where embedding_gte is not null and source_kind = 'regulation' limit 1;
  v := public.fn_reason_retrieve('sales_engineer', v_vec, 4);
  o := o || jsonb_build_object('retrieved', jsonb_array_length(v), 'top_similarity', (v->0->>'similarity')::numeric, 'top_source', v->0->>'source');
  begin perform public.fn_reason_propose_knowledge('customer_support', 'ZZ DEMO q', 'ZZ DEMO finding', '[{"url":"http://x.ae"}]'::jsonb, v_vec);
        o := o || '{"http_source":"accepted"}'; exception when others then o := o || jsonb_build_object('http_source', sqlstate); end;
  perform public.fn_reason_propose_knowledge('customer_support', 'ZZ DEMO q', 'ZZ DEMO a private pool in Dubai needs a permit', '[{"url":"https://www.dm.gov.ae/x","title":"ZZ"}]'::jsonb, v_vec);
  v := public.fn_reason_retrieve('customer_support', v_vec, 12);
  o := o || jsonb_build_object('research_trust', (select x->>'trust' from jsonb_array_elements(v) x where x->>'source' = 'research' limit 1));

  -- 5b. Readiness: no live inquiry the old check called ready is un-readied by the new one.
  o := o || jsonb_build_object('rfq_flipped', (select count(*) from public.inquiries i join zz_rfq_before b on b.id = i.id
            where b.ok and not coalesce((public.fn_rfq_required_check(i)->>'required_ok')::boolean, true)
              and i.status not in ('quoted', 'revealed', 'closed', 'completed', 'cancelled', 'awarded')),
    'rfq_flipped_after_dispatch', (select count(*) from public.inquiries i join zz_rfq_before b on b.id = i.id
            where b.ok and not coalesce((public.fn_rfq_required_check(i)->>'required_ok')::boolean, true)
              and i.status in ('quoted', 'revealed', 'closed', 'completed', 'cancelled', 'awarded')));

  -- 5c. A held intake gets its reasoned trade and reopens; the delivery outcome is recorded; old rows expire.
  insert into public.inquiry_intake (email, status, turns, raw_input) values ('zz-demo-probe@example.invalid', 'held', '[]'::jsonb, 'ZZ DEMO fire alarm for a warehouse')
    returning id into v_intake;
  v_id := public.fn_reason_hold('sales_engineer', 'inquiry_intake.trade', 'ZZ DEMO fire alarm', '{"seat":"sales_engineer"}'::jsonb, '{}'::jsonb,
            jsonb_build_object('intake_id', v_intake::text), 'model_hold', 'zz-demo-probe-2');
  perform public.fn_reason_held_resolve(v_id, jsonb_build_object('status', 'answered', 'answer', 'ZZ', 'decision', jsonb_build_object('choice', (select category from public.category_specs order by category limit 1))));
  o := o || jsonb_build_object('intake_after', (select status || ':' || (brief->>'category_by') from public.inquiry_intake where id = v_intake),
                               'intake_expires', (select expires_at is null from public.reasoning_held_question where id = v_id));
  v_id := public.fn_reason_hold('customer_support', 'wa_inbound.needs_a_person', 'ZZ DEMO', '{"seat":"customer_support"}'::jsonb, '{}'::jsonb, null, 'model_hold', 'zz-demo-probe-3');
  o := o || jsonb_build_object('channel_expires', (select expires_at is not null from public.reasoning_held_question where id = v_id));
  perform public.fn_reason_held_resolve(v_id, '{"status":"answered","answer":"ZZ","decision":{"choice":"needs_a_person"}}'::jsonb);
  perform public.fn_reason_held_delivered(v_id, '{"delivered":true,"via":"whatsapp_template"}'::jsonb);
  o := o || jsonb_build_object('delivered_row', (select status || ':' || (result->'delivery'->>'via') from public.reasoning_held_question where id = v_id));
  -- Held 49 hours: never expired; escalated once to its seat as a pending item, and still held for the replay.
  update public.reasoning_held_question set status = 'held', created_at = now() - interval '49 hours' where id = v_id;
  perform public.fn_reason_held_due(1);
  o := o || jsonb_build_object('old_status', (select status from public.reasoning_held_question where id = v_id),
    'escalated', (select count(*) from jsonb_array_elements(public.fn_reason_held_escalate(100)) x where (x->>'id')::bigint = v_id),
    'escalated_again', (select count(*) from jsonb_array_elements(public.fn_reason_held_escalate(100)) x where (x->>'id')::bigint = v_id));
  -- its own statement: a subquery in the statement that escalated would read the snapshot before the insert
  o := o || jsonb_build_object('seat_item', (select agent || ':' || status from public.agent_actions where kind = 'held_question' and target_id = v_id::text));

  -- 6. Only service_role executes.
  o := o || jsonb_build_object('anon_can', (select bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
            from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
            ('fn_wa_route', 'fn_ceo_command_submit', 'fn_ceo_command_interpret', 'fn_rfq_required_check', 'fn_reason_retrieve',
             'fn_reason_hold', 'fn_reason_held_due', 'fn_reason_held_resolve', 'fn_reason_propose_knowledge', 'fn_reason_held_delivered')),
    'service_can', has_function_privilege('service_role', 'public.fn_wa_route(text,text,boolean,boolean)', 'execute'));

  raise exception 'CHK<<%>>', o::text;
end $p$;`;

test('production, in one aborted transaction: escalation, commands, exact spec, the queue, retrieval, grants', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const [r] = await sql(`select to_regprocedure('public.fn_reason_retrieve(text,vector,integer)') is not null applied`, { readOnly: true });
  // Measured BEFORE the files replay: which live inquiries the current check calls ready (review finding 5).
  const before = 'create temporary table zz_rfq_before on commit drop as select i.id, coalesce((public.fn_rfq_required_check(i)->>\'required_ok\')::boolean, true) ok from public.inquiries i;\n';
  // Every pending file replays, whether or not the engine is already applied (a later file may still be pending).
  void r;
  const body = before + (await pendingReplay()) + PROBE;
  let out;
  try {
    await sql(body, { retry: false });
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 600));
    out = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(out, 'the probe committed instead of rolling back');
  console.log(JSON.stringify(out, null, 1));

  assert.equal(out.legal_q_person, 'false', '"is it legal ..." is not a complaint');
  assert.equal(out.legal_q_by, 'held: not yet reasoned');
  assert.equal(out.complaint_person, 'true');
  assert.equal(out.complaint_opened, 'complaint or dispute');
  assert.equal(out.complaint_by, 'reasoning');
  assert.equal(out.words_but_reasoned_no, 'false', 'the words complaint/refund/dispute decide nothing');
  assert.equal(out.old_overload, false);

  assert.deepEqual(out.submitted, { intent: 'ambiguous', state: 'interpreting' });
  assert.equal(out.tasks_before, 0, 'nothing is routed before it is understood');
  assert.equal(out.interpreted, 'tasks_created');
  assert.equal(out.interpreted_intent, 'fix');
  assert.equal(out.tasks_after, 1);
  assert.equal(out.interpret_again, 'false', 'a replay after a live answer is a no-op');
  assert.equal(out.bad_intent, '22023');
  assert.equal(out.classify_exists, false);

  assert.ok(!out.text_only_present.includes('floor_type'), 'an option word in the text is not an answer');
  assert.ok(out.keyed_present.includes('floor_type'), 'a keyed answer is');

  assert.equal(out.hold_dedupe, true, 'one held row per inbound message');
  assert.equal(out.gate_rule, 'founder_hold', 'this check assumes the founder\'s hold is on; if released, rewrite the due assertion');
  assert.deepEqual(out.due_under_gate, [], 'under the hold nothing is replayed');
  assert.equal(out.resolve_held, 'still_held');
  assert.equal(out.resolve_answered, 'applied');
  assert.deepEqual(out.resolved, { row: 'applied', cmd: 'tasks_created:stop' });

  assert.ok(out.retrieved >= 1);
  assert.ok(out.top_similarity > 0.99, 'a chunk\'s own embedding finds itself first');
  assert.equal(out.top_source, 'kb_chunks');
  assert.equal(out.http_source, '22023');
  assert.equal(out.research_trust, 'pending_review');

  assert.equal(out.rfq_flipped, 0, 'an inquiry not yet dispatched that the old check called ready would be un-readied: do not apply');
  // Measured 23 Sep 2026: 3 — the only 3 inquiries on production, all quoted or revealed, so readiness no longer gates them.
  console.log('already-dispatched inquiries whose readiness the text scan had supplied:', out.rfq_flipped_after_dispatch);
  assert.equal(out.intake_after, 'needs_info:reasoning', 'the held intake reopens with the reasoned trade');
  assert.equal(out.intake_expires, true, 'a held intake never expires');
  assert.equal(out.channel_expires, false, 'a held question never expires (the hold lasts a while)');
  assert.equal(out.delivered_row, 'applied:whatsapp_template');
  assert.equal(out.old_status, 'held', 'a 49-hour-old question is still held for the replay, never expired');
  assert.equal(out.escalated, 1, 'at 48 hours it is escalated to its seat');
  assert.equal(out.escalated_again, 0, 'once');
  assert.equal(out.seat_item, 'customer_support:pending', 'a human-visible pending item in the owning seat queue');
  assert.equal(out.anon_can, false);
  assert.equal(out.service_can, true);
});

test('production, aborted: a surface\'s own fn_reason_apply_ routine applies its reasoned answer; a surface without one is left reasoned',
  { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const out = await probe(String.raw`
do $p$
declare o jsonb := '{}'::jsonb; v_id bigint;
begin
  create function public.fn_reason_apply_zz_probe__applies(p_id bigint, p_result jsonb) returns jsonb language sql
    as $f$ select jsonb_build_object('choice', p_result->'decision'->>'choice', 'id', p_id) $f$;
  v_id := public.fn_reason_hold('it_engineer', 'zz_probe.applies', 'ZZ DEMO', '{"seat":"it_engineer"}'::jsonb, '{}'::jsonb, null, 'model_hold', 'zz-dispatch-1');
  o := o || jsonb_build_object('with', public.fn_reason_held_resolve(v_id, '{"status":"answered","answer":"ZZ","decision":{"choice":"yes"}}'::jsonb));
  v_id := public.fn_reason_hold('it_engineer', 'zz_probe.no_routine', 'ZZ DEMO', '{"seat":"it_engineer"}'::jsonb, '{}'::jsonb, null, 'model_hold', 'zz-dispatch-2');
  o := o || jsonb_build_object('without', public.fn_reason_held_resolve(v_id, '{"status":"answered","answer":"ZZ","decision":{"choice":"yes"}}'::jsonb)->>'status');
  raise exception 'CHK<<%>>', o::text;
end $p$;`);
  assert.equal(out.with.status, 'applied');
  assert.equal(out.with.effect.choice, 'yes');
  assert.equal(out.without, 'reasoned');
});

// ── Batch B5 (sales_engineer): prices, supplier profiles and quote quality ─────────────────────────────
// scripts/sql/prices_supplier_profiles_and_quote_quality_are_read_by_reasoning.sql. Every routine it replaced
// read free text for meaning; after the replay none does, the meaning arrives as a reasoned reading, and each
// surface's replay effect lands through fn_reason_held_resolve. ZZ DEMO text only; nothing commits.
test('production, aborted: B5 — price by reasoned trade, quote quality held until read, twin and own words read by reasoning, grants',
  { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const out = await probe(String.raw`
do $p$
declare o jsonb := '{}'::jsonb; v jsonb; v_due jsonb; v_q uuid; v_id bigint; v_lead bigint; v_sup bigint; v_key text; v_name text; v_catkey text; v_trade text; v_fields jsonb;
begin
  -- 40. fn_price_guidance reads no question: a sentence is not a trade; a reasoned trade is.
  v := public.fn_price_guidance(null, 6);
  o := o || jsonb_build_object('price_null', v->>'reason', 'price_trades', jsonb_array_length(v->'trades'),
    'price_sentence', public.fn_price_guidance('ZZ DEMO what does a gypsum false ceiling cost per sqm', 6)->>'reason',
    'price_old_overload', to_regprocedure('public.fn_price_guidance(text,integer)') is not null);
  select category into v_trade from public.price_benchmark group by category having bool_and(source_kind <> 'gap') order by category limit 1;
  v := public.fn_price_guidance(v_trade, 3, 'ZZ DEMO item');
  o := o || jsonb_build_object('price_ok', v->>'ok', 'price_item', v->>'asked_item', 'price_capped', jsonb_array_length(v->'bands') between 1 and 3);

  -- 45. A quote's category verdict is held until reasoned, then applied by the replay.
  select q.id into v_q from public.quotes q join public.inquiries i on i.id = q.inquiry_id
   where exists (select 1 from public.category_quote_specs c where c.spec_group = public.fn_quote_spec_group(coalesce(i.category, ''))) order by q.id limit 1;
  update public.quotes set quality = quality where id = v_q;
  select quality into v from public.quotes where id = v_q;
  o := o || jsonb_build_object('q_before', v->'category'->>'status', 'q_pass_before', v->>'pass');
  v_due := public.fn_quote_aspects_due(v_q);
  o := o || jsonb_build_object('q_due_aspects', jsonb_array_length(v_due->'aspects'));
  perform public.fn_quote_aspect_reading_record(v_q, v_due->>'content_md5', null, null);
  o := o || jsonb_build_object('q_due_after_held', public.fn_quote_aspects_due(v_q) is null);
  select jsonb_object_agg(c.aspect, jsonb_build_object('value', 'ZZ', 'evidence', 'ZZ DEMO words')) into v_fields
    from public.category_quote_specs c where c.spec_group = v_due->>'spec_group';
  v_id := public.fn_reason_hold('sales_engineer', 'sql.trg_quote_quality', 'ZZ DEMO', '{"seat":"sales_engineer"}'::jsonb, '{}'::jsonb,
            jsonb_build_object('quote_id', v_q, 'content_md5', v_due->>'content_md5'), 'model_hold', 'zz-b5-quote');
  o := o || jsonb_build_object('q_resolve', public.fn_reason_held_resolve(v_id, jsonb_build_object('status', 'answered', 'answer', 'ZZ',
            'decision', jsonb_build_object('choice', null, 'fields', v_fields)))->>'status');
  select quality into v from public.quotes where id = v_q;
  o := o || jsonb_build_object('q_after', v->'category'->>'status', 'q_cat_pass_after', v->'category'->>'pass', 'q_missing_after', v->'category'->>'mandatory_missing');

  -- 42. The twin: installation from the reasoned reading of the current summary only.
  select id into v_lead from public.leads where nullif(btrim(coalesce(capability_summary, '')), '') is not null
     and coalesce(engineers_count, 0) = 0 and jsonb_typeof(machinery) is distinct from 'array'
     and not exists (select 1 from public.supplier_capability_reading r where r.lead_id = leads.id) order by id limit 1;
  v := public.fn_supplier_twin(v_lead);
  o := o || jsonb_build_object('twin_before', v->>'capability_reading', 'twin_install_before', v->'capabilities'->1->>'has');
  v_due := public.fn_supplier_readings_due(v_lead);
  v_id := public.fn_reason_hold('sales_engineer', 'sql.fn_supplier_twin', 'ZZ DEMO', '{"seat":"sales_engineer"}'::jsonb, '{}'::jsonb,
            jsonb_build_object('lead_id', v_lead, 'summary_md5', v_due->'capability'->>'summary_md5'), 'model_hold', 'zz-b5-twin');
  perform public.fn_reason_held_resolve(v_id, '{"status":"answered","answer":"ZZ","decision":{"choice":null,"fields":{"installation":{"value":"ZZ","evidence":"ZZ DEMO"}}}}'::jsonb);
  -- a late replay of an OLD summary (another md5) must not replace the reading of the current one
  v_id := public.fn_reason_hold('sales_engineer', 'sql.fn_supplier_twin', 'ZZ DEMO', '{"seat":"sales_engineer"}'::jsonb, '{}'::jsonb,
            jsonb_build_object('lead_id', v_lead, 'summary_md5', repeat('f', 32)), 'model_hold', 'zz-b5-twin-stale');
  o := o || jsonb_build_object('twin_stale', public.fn_reason_held_resolve(v_id, '{"status":"answered","answer":"ZZ","decision":{"choice":null,"fields":{}}}'::jsonb)->'effect'->>'skipped');
  v := public.fn_supplier_twin(v_lead);
  o := o || jsonb_build_object('twin_after', v->>'capability_reading', 'twin_install_after', v->'capabilities'->1->>'has',
    'twin_design_after', v->'capabilities'->3->>'has', 'twin_due_after', jsonb_typeof(public.fn_supplier_readings_due(v_lead)->'capability'));

  -- 43. An own word names a service only by a reasoned reading.
  select supplier_id, trades[1] into v_sup, v_trade from public.supplier_capabilities
   where confirmed_at is not null and coalesce(cardinality(trades), 0) > 0 order by supplier_id limit 1;
  update public.supplier_capabilities set services = coalesce(services, '{}'::text[]) || array['ZZ DEMO own words'] where supplier_id = v_sup;
  o := o || jsonb_build_object('gaps_before', (select jsonb_agg(x->>'code') from jsonb_array_elements(public.fn_supplier_portfolio_gaps(v_sup)) x),
    'gaps_due', public.fn_supplier_readings_due(v_sup)->'own_words');
  select s.trade_code || '.' || s.code into v_key from public.taxonomy_trade_service s where s.active and s.trade_code = v_trade order by s.sort, s.code limit 1;
  v_id := public.fn_reason_hold('sales_engineer', 'sql.fn_supplier_portfolio_gaps', 'ZZ DEMO', '{"seat":"sales_engineer"}'::jsonb, '{}'::jsonb,
            jsonb_build_object('supplier_id', v_sup, 'word', 'ZZ DEMO own words'), 'model_hold', 'zz-b5-word');
  perform public.fn_reason_held_resolve(v_id, jsonb_build_object('status', 'answered', 'answer', 'ZZ', 'decision', jsonb_build_object('choice', v_key)));
  v := public.fn_supplier_portfolio_gaps(v_sup);
  o := o || jsonb_build_object('gaps_after', (select jsonb_agg(x->>'code') from jsonb_array_elements(v) x),
    'gaps_named', (select x->'services'->>0 from jsonb_array_elements(v) x where x->>'code' = 'own_word_is_a_service') = v_key);
  begin perform public.fn_supplier_own_word_reading_record(v_sup, 'ZZ DEMO x', 'not.a_service', true, null); o := o || '{"bad_key":"accepted"}';
  exception when others then o := o || jsonb_build_object('bad_key', sqlstate); end;

  -- 46. A catalogue name in a task's words names no category; a key in its own format does.
  select c.name, i.category_key into v_name, v_catkey from public.catalog_supplier_categories c
    join public.org_category_identity i on i.catalog_num = c.num order by c.num limit 1;
  o := o || jsonb_build_object('cat_by_name', public.fn_category_key_from_text('ZZ DEMO a task about ' || v_name),
                               'cat_by_key', public.fn_category_key_from_text('ZZ DEMO key ' || v_catkey) = v_catkey);

  -- 41, 44 and every body: no free text read for meaning.
  o := o || jsonb_build_object('bodies', (select jsonb_object_agg(p.proname, case p.proname
      when 'fn_supplier_opportunities' then p.prosrc !~ 'position\(|capability_summary'
      when 'fn_rfq_short_of_quotes_tick' then p.prosrc !~* 'ilike|~\*'
      when 'fn_supplier_twin' then p.prosrc !~ 'capability_summary ilike'
      when 'fn_supplier_portfolio_gaps' then p.prosrc !~ 'aliases'
      when 'trg_quote_quality' then p.prosrc !~ 'match_regex'
      when 'fn_price_guidance' then p.prosrc !~* 'like|~'
      when 'fn_category_key_from_text' then p.prosrc !~* 'like' end)
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('fn_supplier_opportunities', 'fn_rfq_short_of_quotes_tick',
      'fn_supplier_twin', 'fn_supplier_portfolio_gaps', 'trg_quote_quality', 'fn_price_guidance', 'fn_category_key_from_text')));

  o := o || jsonb_build_object('anon_can', (select bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
            from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('fn_price_guidance', 'fn_supplier_opportunities', 'fn_supplier_twin',
              'fn_supplier_portfolio_gaps', 'fn_rfq_short_of_quotes_tick', 'trg_quote_quality', 'fn_category_key_from_text', 'fn_supplier_readings_due',
              'fn_supplier_capability_reading_record', 'fn_supplier_own_word_reading_record', 'fn_quote_aspect_text', 'fn_quote_aspects_due',
              'fn_quote_aspect_reading_record', 'fn_reason_field_stated', 'fn_reason_apply_sql__fn_supplier_twin',
              'fn_reason_apply_sql__fn_supplier_portfolio_gaps', 'fn_reason_apply_sql__trg_quote_quality')),
    'service_can', has_function_privilege('service_role', 'public.fn_quote_aspect_reading_record(uuid,text,text[],bigint)', 'execute'),
    'rls', (select bool_and(c.relrowsecurity) from pg_class c where c.oid in ('public.supplier_capability_reading'::regclass,
              'public.supplier_own_word_reading'::regclass, 'public.quote_aspect_reading'::regclass)));
  raise exception 'CHK<<%>>', o::text;
end $p$;`);
  console.log(JSON.stringify(out, null, 1));
  assert.equal(out.price_null, 'needs_reasoning');
  assert.ok(out.price_trades >= 1);
  assert.equal(out.price_sentence, 'no_trade_matched', 'a sentence is never read for its trade');
  assert.equal(out.price_old_overload, false);
  assert.equal(out.price_ok, 'true'); assert.equal(out.price_item, 'ZZ DEMO item'); assert.equal(out.price_capped, true);

  assert.equal(out.q_before, 'needs_reasoning', 'an unread quote is not scored by a regex');
  assert.equal(out.q_pass_before, 'false', 'held, never passed on a guess');
  assert.ok(out.q_due_aspects >= 1);
  assert.equal(out.q_due_after_held, true, 'a queued reading is not re-asked on every write');
  assert.equal(out.q_resolve, 'applied');
  assert.equal(out.q_after, 'reasoned'); assert.equal(out.q_cat_pass_after, 'true'); assert.equal(out.q_missing_after, '0');

  assert.equal(out.twin_before, 'needs_reasoning'); assert.equal(out.twin_install_before, 'false');
  assert.equal(out.twin_after, 'reasoned'); assert.equal(out.twin_install_after, 'true'); assert.equal(out.twin_design_after, 'false');
  assert.equal(out.twin_due_after, 'null', 'a read summary is not read again');
  assert.equal(out.twin_stale, 'stale', 'a replay of an edited summary does not overwrite the current reading');

  assert.ok(out.gaps_before.includes('own_words') && !out.gaps_before.includes('own_word_is_a_service'), JSON.stringify(out.gaps_before));
  assert.ok(out.gaps_due.includes('ZZ DEMO own words'));
  assert.ok(out.gaps_after.includes('own_word_is_a_service'), JSON.stringify(out.gaps_after));
  assert.equal(out.gaps_named, true);
  assert.equal(out.bad_key, '22023');

  assert.equal(out.cat_by_name, null, 'a catalogue name in the words decides nothing');
  assert.equal(out.cat_by_key, true);
  for (const [fn, clean] of Object.entries(out.bodies)) assert.equal(clean, true, `${fn} reads free text for meaning again`);
  assert.equal(Object.keys(out.bodies).length, 7);
  assert.equal(out.anon_can, false); assert.equal(out.service_can, true); assert.equal(out.rls, true);
});
