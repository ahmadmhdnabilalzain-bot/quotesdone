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

// ── Batch 8 (accountant, marketing, it_engineer): the books and the knowledge read by meaning (points 63-71) ──
// scripts/sql/the_books_and_the_knowledge_are_read_by_meaning_not_by_words.sql, replayed with the pending chain inside
// ONE aborted transaction. ZZ DEMO rows only (account zz_demo, is_demo prospects, ZZ DEMO vendors); nothing commits,
// nothing reaches a person. What fails if the word matching returns:
//   * a bank line whose TEXT says fee / transfer / interest books while its kind is NULL (the old regexes would);
//   * a reasoned kind does not book, is overwritten, or accepts a kind that does not exist;
//   * the renewal budget or the Meta ad-spend figure is chosen by the vendor's NAME rather than read_as / renews_item;
//   * the LinkedIn replay does not close a decline or draft its follow-up once, or accepts an unknown class;
//   * an incident's owner is read off an event subscriber's free-text reason instead of being the it_engineer;
//   * support/ceo knowledge is found by words, is not found by its vector, or keeps its vector after its text changed;
//   * anon or authenticated can execute a new routine.
test('production, aborted: batch 8 — bank lines, expenses, outreach, incidents and the support/ceo knowledge by meaning',
  { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const out = await probe(String.raw`
do $p$
declare
  o jsonb := '{}'::jsonb; v jsonb; v_d bigint; v_c bigint; v_n bigint; v_id bigint; v_pr bigint; v_tok uuid; v_vec vector(384); v_m date;
begin
  -- A. Bank lines. Every word the old patterns keyed on is in these descriptions; with kind NULL nothing books.
  insert into public.bank_statement_intake (source_ref, account, state, lines) values ('zz-demo-b8', 'zz_demo', 'parsed', 3);
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash)
    values ('zz_demo', 'zz-demo-b8', current_date - 30, 'ZZ DEMO Monthly Maintenance Fee commission charge', -199, 'zz-demo-b8-1') returning id into v_d;
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash)
    values ('zz_demo', 'zz-demo-b8', current_date - 30, 'ZZ DEMO IPP TRANSFER P2P interest CIDAED 00001', 1000, 'zz-demo-b8-2') returning id into v_c;
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash)
    values ('zz_demo', 'zz-demo-b8', current_date - 30, 'ZZ DEMO STRIPE PAYOUT', 250, 'zz-demo-b8-3') returning id into v_n;
  perform public.fn_accountant_book_bank_charges();
  perform public.fn_accountant_book_bank_credits();
  o := o || jsonb_build_object('unreasoned_booked', (select count(*) from public.gl_journal where source_ref in (v_d::text, v_c::text, v_n::text)));
  v := public.fn_accountant_bank_lines_to_reason(50);
  o := o || jsonb_build_object('to_reason_has_new', (select count(*) from jsonb_array_elements(v->'lines') x where (x->>'id')::bigint in (v_d, v_c, v_n)),
                               'to_reason_has_owner', v ? 'owner');
  -- the replay applies the reasoned kind; a direct record is never overwritten; an unknown kind is refused
  v_id := public.fn_reason_hold('accountant', 'accountant.bank_line', 'ZZ DEMO line', '{"seat":"accountant"}'::jsonb, '{}'::jsonb,
            jsonb_build_object('line_id', v_d), 'model_hold', 'zz-b8-line-1');
  o := o || jsonb_build_object('replay', public.fn_reason_held_resolve(v_id, '{"status":"answered","answer":"ZZ","decision":{"choice":"bank_charge"}}'::jsonb)->>'status');
  perform public.fn_accountant_bank_line_reasoned(v_c, 'owner_transfer', 'zz-probe');
  o := o || jsonb_build_object('rerecord', public.fn_accountant_bank_line_reasoned(v_c, 'other', 'zz-probe')->>'recorded',
                               'kinds', (select jsonb_object_agg(line_hash, kind) from public.bank_statement_line where source_ref = 'zz-demo-b8'));
  begin perform public.fn_accountant_bank_line_reasoned(v_n, 'salary', 'zz-probe'); o := o || '{"bad_kind":"accepted"}';
  exception when others then o := o || jsonb_build_object('bad_kind', sqlstate); end;
  perform public.fn_accountant_book_bank_charges();
  perform public.fn_accountant_book_bank_credits();
  o := o || jsonb_build_object('charge_source', (select string_agg(source, ',') from public.gl_journal where source_ref = v_d::text),
                               'credit_source', (select string_agg(source, ',') from public.gl_journal where source_ref = v_c::text),
                               'unreasoned_still_unbooked', (select count(*) from public.gl_journal where source_ref = v_n::text));

  -- B. The renewal budget reads renews_item, never the vendor's name.
  v := public.fn_accountant_renewal_budget_line('domain:quotesdone.ae');
  o := o || jsonb_build_object('domain_budget_before', v->>'budget_aed');
  insert into public.expense_entries (vendor, amount, currency, charged_on, note, read_as, renews_item)
    values ('ZZ DEMO Registrar', 77, 'AED', current_date, 'ZZ DEMO probe', 'renewal', 'domain:quotesdone.ae');
  o := o || jsonb_build_object('domain_budget_after', public.fn_accountant_renewal_budget_line('domain:quotesdone.ae')->>'budget_aed',
                               'licence_budget', public.fn_accountant_renewal_budget_line('trade_licence_det_1633275')->>'budget_aed');

  -- C. Meta ad spend is what was REASONED a Meta ads invoice; a vendor merely named Meta is not counted.
  v_m := (date_trunc('month', current_date) - interval '3 months')::date;
  insert into public.expense_entries (vendor, amount, currency, charged_on, note, read_as) values
    ('ZZ DEMO Meta ads', 100, 'AED', v_m + 3, 'ZZ DEMO probe', 'meta_ads_invoice'),
    ('ZZ DEMO Meta Platforms (not ads)', 900, 'AED', v_m + 4, 'ZZ DEMO probe', null);
  v := public.fn_accountant_ad_spend_figures(v_m);
  o := o || jsonb_build_object('meta_invoices', v->'meta_invoices', 'meta_invoiced', v->'invoiced_aed');
  v := public.fn_accountant_reading_context();
  o := o || jsonb_build_object('ctx_zz_vendor', exists (select 1 from jsonb_array_elements_text(v->'vendors') x where x ~* 'zz[ _-]?demo'),
                               'ctx_renewal', exists (select 1 from jsonb_array_elements(v->'renewals') x where x->>'item' = 'trade_licence_det_1633275'));

  -- D. The LinkedIn reply reasoned after the hold: class recorded, decline closes the person, one follow-up.
  insert into public.marketing_prospect (full_name, role_title, company, segment, source_urls, researched_by, status, is_demo)
    values ('ZZ DEMO B8 Sara', 'ZZ DEMO Procurement', 'ZZ DEMO B8 Co', 'developer', array['https://example.invalid/zz'], 'claude', 'replied', true)
    returning id into v_pr;
  insert into public.marketing_outreach_message (prospect_id, kind, language, body, note, listed_on, status, reply_text, is_demo)
    values (v_pr, 'first', 'en', 'ZZ DEMO hello', 'ZZ DEMO note', current_date, 'replied', 'ZZ DEMO thanks, not for us', true)
    returning mark_token into v_tok;
  -- (each call its own statement: a subquery in the SAME statement reads the snapshot from before the call)
  o := o || jsonb_build_object('outreach', public.fn_marketing_outreach_reply_reasoned(v_tok, 'decline', 'ZZ DEMO understood, I will not follow up')->>'class');
  o := o || jsonb_build_object('outreach_again', public.fn_marketing_outreach_reply_reasoned(v_tok, 'positive', 'ZZ DEMO x')->>'already');
  o := o || jsonb_build_object('prospect', (select status from public.marketing_prospect where id = v_pr),
                               'follow_ups', (select count(*) from public.marketing_outreach_message where prospect_id = v_pr and kind = 'follow_up'));
  begin perform public.fn_marketing_outreach_reply_reasoned(v_tok, 'maybe', null); o := o || '{"bad_class":"accepted"}';
  exception when others then o := o || jsonb_build_object('bad_class', sqlstate); end;

  -- E. An incident belongs to the it_engineer seat; a writer that names an owner keeps it.
  insert into public.os_incidents (title, severity) values ('ZZ DEMO B8 incident', 'low') returning id into v_id;
  o := o || jsonb_build_object('incident_owner', (select owner from public.os_incidents where id = v_id));
  insert into public.os_incidents (title, severity, owner) values ('ZZ DEMO B8 incident 2', 'low', 'accountant') returning id into v_id;
  o := o || jsonb_build_object('incident_named_owner', (select owner from public.os_incidents where id = v_id));

  -- F. Support and CEO knowledge by meaning: found by its vector, never by words, and a changed text drops its vector.
  select embedding_gte into v_vec from public.kb_chunks where embedding_gte is not null and source_kind = 'regulation' limit 1;
  insert into public.support_knowledge
    select (jsonb_populate_record(null::public.support_knowledge, to_jsonb(k) || jsonb_build_object('record_id', 'zz-demo-b8-sk',
              'title', 'ZZ DEMO B8 probe record', 'body', 'ZZ DEMO B8 probe body', 'body_sha256', md5('zz-demo-b8-sk'),
              'runtime_index_eligible', true, 'embedding_gte', v_vec::text))).*
      from public.support_knowledge k limit 1;
  insert into public.ceo_knowledge
    select (jsonb_populate_record(null::public.ceo_knowledge, to_jsonb(k) || jsonb_build_object('record_id', 'zz-demo-b8-ck',
              'title', 'ZZ DEMO B8 probe record', 'body', 'ZZ DEMO B8 probe body', 'body_sha256', md5('zz-demo-b8-ck'),
              'runtime_index_eligible', true, 'embedding_gte', v_vec::text))).*
      from public.ceo_knowledge k limit 1;
  v := public.fn_reason_retrieve('customer_support', v_vec, 12);
  o := o || jsonb_build_object('support_retrieved', exists (select 1 from jsonb_array_elements(v) x where x->>'source' = 'support_knowledge' and x->>'id' = 'zz-demo-b8-sk'));
  v := public.fn_reason_retrieve('ceo', v_vec, 12);
  o := o || jsonb_build_object('ceo_retrieved', exists (select 1 from jsonb_array_elements(v) x where x->>'source' = 'ceo_knowledge' and x->>'id' = 'zz-demo-b8-ck'));
  v := public.fn_reason_retrieve('sales_engineer', v_vec, 12);
  o := o || jsonb_build_object('other_seat_sees_support', exists (select 1 from jsonb_array_elements(v) x where x->>'source' in ('support_knowledge', 'ceo_knowledge')));
  o := o || jsonb_build_object(
    'support_search_top', (select record_id from public.fn_support_knowledge_search('ZZ DEMO B8 probe record', 3, null, v_vec) limit 1),
    'support_search_words_only', (select count(*) from public.fn_support_knowledge_search('ZZ DEMO B8 probe record', 3, null, null)),
    'ceo_search_top', (select record_id from public.fn_ceo_knowledge_search('ZZ DEMO B8 probe record', 3, p_embedding => v_vec) limit 1),
    'ceo_context_records', jsonb_array_length(public.fn_ceo_context('anything at all', 4000, 3, v_vec)->'records'),
    'ceo_context_no_vec', public.fn_ceo_context('ZZ DEMO B8 probe record', 4000, 3)->>'record_count');
  update public.support_knowledge set body = 'ZZ DEMO B8 probe body, edited' where record_id = 'zz-demo-b8-sk';
  update public.ceo_knowledge set title = 'ZZ DEMO B8 probe record, retitled' where record_id = 'zz-demo-b8-ck';
  o := o || jsonb_build_object('support_vec_after_edit', (select embedding_gte is not null from public.support_knowledge where record_id = 'zz-demo-b8-sk'),
                               'ceo_vec_after_edit', (select embedding_gte is not null from public.ceo_knowledge where record_id = 'zz-demo-b8-ck'));

  -- G. The old patterns are gone, and only service_role executes the new routines.
  o := o || jsonb_build_object('patterns_left', (select count(*) from public.gl_settings where key in ('bank_charge_pattern', 'owner_transfer_pattern', 'bank_interest_pattern', 'bank_interest_reference_pattern'))
              + (select count(*) from public.decision_policy where key in ('accountant_meta_invoice_vendor_pattern', 'accountant_renewal_vendor_patterns')),
    'owner_fn_exists', to_regprocedure('public.fn_bank_line_is_owner_transfer(text,text)') is not null,
    'old_search_overloads', (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
                               and oid in (to_regprocedure('public.fn_support_knowledge_search(text,integer,text)'), to_regprocedure('public.fn_ceo_knowledge_search(text,integer,text,text)'),
                                           to_regprocedure('public.fn_support_context(text,integer,integer)'), to_regprocedure('public.fn_ceo_context(text,integer,integer)'))),
    'anon_can', (select bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
                   from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
                   ('fn_accountant_bank_lines_to_reason', 'fn_accountant_bank_line_reasoned', 'fn_reason_apply_accountant__bank_line',
                    'fn_accountant_reading_context', 'fn_marketing_outreach_reply_reasoned', 'fn_support_knowledge_search', 'fn_ceo_knowledge_search',
                    'fn_support_context', 'fn_ceo_context', 'fn_accountant_renewal_budget_line', 'fn_accountant_book_bank_credits')),
    'service_can', has_function_privilege('service_role', 'public.fn_accountant_bank_line_reasoned(bigint,text,text)', 'execute')
                   and has_function_privilege('service_role', 'public.fn_accountant_reading_context()', 'execute'));

  raise exception 'CHK<<%>>', o::text;
end $p$;`);
  console.log(JSON.stringify(out, null, 1));
  // A. meaning from kind, never from the description
  assert.equal(out.unreasoned_booked, 0, 'a line with kind NULL booked: its words decided');
  assert.equal(out.to_reason_has_new, 3);
  assert.equal(out.to_reason_has_owner, true);
  assert.equal(out.replay, 'applied', 'the held bank line is applied by fn_reason_apply_accountant__bank_line');
  assert.equal(out.rerecord, 'false', 'a reasoned kind is never overwritten');
  assert.deepEqual(out.kinds, { 'zz-demo-b8-1': 'bank_charge', 'zz-demo-b8-2': 'owner_transfer', 'zz-demo-b8-3': null });
  assert.equal(out.bad_kind, '22023');
  assert.equal(out.charge_source, 'bank_charge');
  assert.equal(out.credit_source, 'owner_capital', 'an owner transfer is capital unless he says loan');
  assert.equal(out.unreasoned_still_unbooked, 0, '"STRIPE PAYOUT" in the text books nothing while the kind is unreasoned');
  // B, C. the budget and the ad spend read the reasoned columns
  assert.equal(out.domain_budget_before, null, 'the GoDaddy e-mail subscription no longer budgets a domain renewal');
  assert.equal(out.domain_budget_after, '77.00');
  assert.equal(out.licence_budget, '1200.00', '#122 is the licence renewal, carried by renews_item');
  assert.equal(out.meta_invoices, 1, 'only the invoice reasoned to be Meta ads counts, not a vendor merely named Meta');
  assert.equal(out.meta_invoiced, 100);
  assert.equal(out.ctx_zz_vendor, false);
  assert.equal(out.ctx_renewal, true);
  // D. outreach
  assert.equal(out.outreach, 'decline');
  assert.equal(out.outreach_again, 'decline', 'a class already recorded is not replaced');
  assert.equal(out.prospect, 'declined');
  assert.equal(out.follow_ups, 1);
  assert.equal(out.bad_class, '22023');
  // E. incidents
  assert.equal(out.incident_owner, 'it_engineer', 'the owner is the seat, not a subscriber whose reason reads "incident response"');
  assert.equal(out.incident_named_owner, 'accountant');
  // F. knowledge by meaning
  assert.equal(out.support_retrieved, true);
  assert.equal(out.ceo_retrieved, true);
  assert.equal(out.other_seat_sees_support, false, 'the support and CEO packs are their own seats\' sources');
  assert.equal(out.support_search_top, 'zz-demo-b8-sk');
  assert.equal(out.support_search_words_only, 0, 'no embedding: nothing, never a word match');
  assert.equal(out.ceo_search_top, 'zz-demo-b8-ck');
  assert.ok(out.ceo_context_records >= 1);
  assert.equal(out.ceo_context_no_vec, '0');
  assert.equal(out.support_vec_after_edit, false, 'an edited record is not read by its old meaning');
  assert.equal(out.ceo_vec_after_edit, false);
  // G. housekeeping and grants
  assert.equal(out.patterns_left, 0);
  assert.equal(out.owner_fn_exists, false);
  assert.equal(out.old_search_overloads, 0);
  assert.equal(out.anon_can, false);
  assert.equal(out.service_can, true);
});
