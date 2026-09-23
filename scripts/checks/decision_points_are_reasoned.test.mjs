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
  for (const s of ["deps.rpc(rt.retrieve, ", "gte: { retrieve: 'fn_reason_retrieve', recall: 'fn_case_recall'", "ml: { retrieve: 'fn_reason_retrieve_ml', recall: 'fn_case_recall_ml'", "deps.rpc('fn_reason_hold'", "deps.rpc('fn_reason_propose_knowledge'", 'counterpartModel: model', 'refuse(draft']) {
    assert.ok(th.includes(s), `think.ts lost ${s}`);
  }
  // Case memory: think() recalls through the one shared recall (#910), which calls fn_case_recall itself.
  assert.ok(th.includes('await recallCases(deps, '), 'think.ts lost its case recall (recallCases)');
  assert.ok(read('supabase/functions/_shared/case_recall.ts').includes("admin.rpc(ml ? 'fn_case_recall_ml' : 'fn_case_recall', {"), 'case_recall.ts lost fn_case_recall');
  assert.match(read('supabase/functions/resilience_ping/index.ts'), /step\('reasoning_held', async \(\) => replayHeld\(admin, 3, undefined, \(row, r\) => deliverReasoned\(row, r, liveDeliveryIO\(admin\)\)\)\)/);
});

test('provider webhooks are acknowledged at once and handled after (reasoning never runs inside Twilio\'s or Meta\'s deadline)', () => {
  assert.match(read('supabase/functions/wa_inbound/index.ts'), /return ackThenWork\(TW\(200\), \(\) => handleInbound\(copy\), 'wa_inbound'\);/);
  assert.match(read('supabase/functions/marketing_social_inbox/index.ts'), /return ackThenWork\(new Response\(/);
  // the timing itself is proved in supabase/functions/_shared/async_webhook.test.ts (ack < 100 ms while the work runs on)
  assert.match(read('supabase/functions/_shared/async_webhook.test.ts'), /ms < 100/);
});

test('the pack loader and the reasoning agree on every spec code (a filled value lands where the reasoning reads)', async () => {
  const { specCode: loaderCode } = await import(join(REPO, 'scripts/kb/load_trade_spec_checklists.mjs').replace(/\\/g, '/').replace(/^([A-Za-z]):/, 'file:///$1:'));
  const { specCode: engineCode } = await import(join(REPO, 'supabase/functions/_shared/line_specs/reasoned_specs.ts').replace(/\\/g, '/').replace(/^([A-Za-z]):/, 'file:///$1:'));
  for (const s of ['cavity width and gas fill (air/argon %)', 'outer pane: thickness, type (annealed/HS/tempered)', 'Rated capacity; tonnes', 'sizes (max/min) and quantity in m²']) {
    assert.equal(loaderCode(s), engineCode(s), s);
  }
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
  // A routine a LATER file of the chain redefines counts as live when that later definition is (measured 23 Sep
  // 18:30: the dispatch and lifecycle files went live, so the engine's own fn_reason_hold/held_due/held_resolve no
  // longer match production — superseded, not missing — and replaying the engine failed 42501 again).
  const pend = CHAIN.filter((x) => existsSync(join(REPO, 'scripts/sql/pending', x.split('/').pop().replace(/\.sql$/, '.txt'))));
  const defs = CHAIN.map((f) => [f, [...read(f).matchAll(/create (?:or replace )?function public\.([a-z0-9_]+)\([\s\S]*?\$(\w*)\$([\s\S]*?)\$\2\$/g)].map((m) => [m[1], m[3].trim()])]);
  const names = [...new Set(defs.flatMap(([, b]) => b.map(([n]) => n)))];
  const rows = names.length ? await sql(`select proname, prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = any(array[${names.map((n) => `'${n}'`).join(',')}])`, { readOnly: true }) : [];
  const liveBody = (n, b) => rows.some((r) => r.proname === n && String(r.prosrc).trim() === b);
  const out = [];
  defs.forEach(([f, bodies], i) => {
    if (!pend.includes(f)) return;
    const later = defs.slice(i + 1).flatMap(([, b]) => b);
    const live = bodies.length > 0 && bodies.every(([n, b]) => liveBody(n, b) || later.some(([m, c]) => m === n && liveBody(m, c)));
    if (!live) out.push(read(f));
  });
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
    'service_can', has_function_privilege('service_role', 'public.fn_wa_route(text,text,boolean,boolean,text)', 'execute'));

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

// ── batch B6: routing and the CEO's decisions (points 47-54; ceo + sales_engineer) ──────────────────
const B6 = 'scripts/sql/routing_and_ceo_decisions_are_reasoned_not_word_matched.sql';

// Batch B1 (decision points 7-14, customer channels): the WhatsApp intent table answers the REASONED intent and
// never reads the body for meaning; the old overloads are gone; only service_role executes.
test('production, aborted: fn_wa_answer / fn_wa_route answer the reasoned intent, never the words (wa_inbound.intent_table)',
  { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const out = await probe(String.raw`
do $p$
declare o jsonb := '{}'::jsonb; v jsonb;
begin
  -- Words that the old match_patterns caught ('hi', 'price', 'register', 'speak to a human') decide nothing now.
  v := public.fn_wa_answer('+971500000021', 'ZZ DEMO hi, what is the price, how do I register, speak to a human', null);
  o := o || jsonb_build_object('held_matched', v->>'matched', 'held_by', v->>'intent_decided_by');
  v := public.fn_wa_answer('+971500000021', 'ZZ DEMO hi, what is the price', 'none');
  o := o || jsonb_build_object('none_matched', v->>'matched', 'none_by', v->>'intent_decided_by');
  -- ...and a body with none of pricing's words is answered as pricing when that is what was reasoned.
  v := public.fn_wa_answer('+971500000021', 'ZZ DEMO is it free for me?', 'pricing');
  o := o || jsonb_build_object('reasoned_intent', v->>'intent', 'reasoned_matched', v->>'matched');
  v := public.fn_wa_answer('+971500000021', 'ZZ DEMO', 'not_a_row');
  o := o || jsonb_build_object('unknown_row_matched', v->>'matched');
  o := o || jsonb_build_object('held_log', (select refusal_reason from public.wa_answer_log where from_phone = '+971500000021' and body like 'ZZ DEMO hi, what is the price, how%' order by id desc limit 1));
  -- The route passes the intent through; a reasoned contact_human is the one way to the number by intent.
  v := public.fn_wa_route('+971500000021', 'ZZ DEMO is anyone actually there?', false, false, 'contact_human');
  o := o || jsonb_build_object('route_intent', v->>'deterministic_intent', 'route_person', v->>'needs_a_person', 'route_by', v->>'person_decided_by');
  v := public.fn_wa_route('+971500000021', 'ZZ DEMO speak to a human please', false, null);
  o := o || jsonb_build_object('route_held_intent', v->'deterministic_intent', 'route_held_person', v->>'needs_a_person', 'route_held_by', v->>'intent_decided_by');
  o := o || jsonb_build_object(
    'old_answer', to_regprocedure('public.fn_wa_answer(text,text)') is not null,
    'old_route', to_regprocedure('public.fn_wa_route(text,text,boolean,boolean)') is not null,
    'reads_patterns', position('match_patterns' in pg_get_functiondef('public.fn_wa_answer(text,text,text)'::regprocedure)) > 0,
    'anon_can', (select bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
                   from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('fn_wa_answer', 'fn_wa_route')),
    'service_can', has_function_privilege('service_role', 'public.fn_wa_answer(text,text,text)', 'execute')
                   and has_function_privilege('service_role', 'public.fn_wa_route(text,text,boolean,boolean,text)', 'execute'));
  raise exception 'CHK<<%>>', o::text;
end $p$;`);
  console.log(JSON.stringify(out, null, 1));
  assert.equal(out.held_matched, 'false', 'unreasoned: the words decide nothing');
  assert.equal(out.held_by, 'held: not yet reasoned');
  assert.match(out.held_log, /^Not reasoned yet \(the model hold\)/);
  assert.equal(out.none_matched, 'false');
  assert.equal(out.none_by, 'reasoning');
  assert.equal(out.reasoned_intent, 'pricing');
  assert.equal(out.reasoned_matched, 'true');
  assert.equal(out.unknown_row_matched, 'false', 'an intent that is not an active row is not answered');
  assert.equal(out.route_intent, 'contact_human');
  assert.equal(out.route_person, 'true');
  assert.equal(out.route_by, 'intent');
  assert.equal(out.route_held_intent, null, '"speak to a human" held: no intent from the words');
  assert.equal(out.route_held_person, 'false');
  assert.equal(out.route_held_by, 'held: not yet reasoned');
  assert.equal(out.old_answer, false);
  assert.equal(out.old_route, false);
  assert.equal(out.reads_patterns, false);
  assert.equal(out.anon_can, false);
  assert.equal(out.service_can, true);
});

test('B6: the routing and CEO routines read no free text for meaning', () => {
  const sql = code(B6, read(B6));
  const body = (name) => { const a = sql.indexOf('function public.' + name + '('); const ends = ['$function$;', '$fn$;'].map((e) => sql.indexOf(e, a)).filter((i) => i > a); const b = Math.min(...ends); assert.ok(a > 0 && ends.length, name); return sql.slice(a, b); };
  for (const n of ['fn_resolve_cat_agent', 'trg_inquiry_enrich', 'fn_supplier_document_home', 'fn_should_escalate', 'fn_task_review', 'fn_twin',
                   'fn_lead_reclassify_tick', 'fn_reason_apply_lead_trade__classify', 'fn_category_key_for_slug', 'fn_category_key_ask', 'fn_reason_apply_category__key_for_slug']) {
    assert.doesNotMatch(body(n), /~\*|~ '|ilike|\blike\b|position\(|strpos\(|similar to|regexp_(match|matches|like|split|substr|count|instr)|substring\([^)]*\bfrom\b/i, `${n} matches text again`);
  }
  // fn_decide and the refund checklist keep format guards on OUR keys and addresses (ilike 'supplier@%',
  // a ':'-suffixed source_ref); no pattern may touch the category text or the refund notes.
  assert.doesNotMatch(body('fn_decide'), /categories,''\)\)\|\||~\*/, 'fn_decide reads the category text by substring again');
  assert.doesNotMatch(body('fn_ceo_refund_checklist'), /reason_note[^;]*~|close_reason[^;]*~/, 'the refund notes are pattern-matched again');
  assert.doesNotMatch(sql.slice(sql.indexOf('function public.fn_category_expert_ref('), sql.indexOf('end $fn$;', sql.indexOf('function public.fn_category_expert_ref('))), /~\*/);
});

test('production, aborted (B6): escalation, refunds, tasks, documents, repeats and desks wait for reasoning and apply it',
  { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const out = await probe(String.raw`
do $p$
declare
  o jsonb := '{}'::jsonb; v jsonb; v_id bigint; n bigint; c record; v_lead bigint; v_doc bigint; v_tx uuid; v_ref bigint;
  v_cust uuid; v_i1 uuid; v_i2 uuid; v_i3 uuid; v_task bigint; v_resp text;
begin
  -- 1. The desk: a fragment of a catalogue name is no longer a desk; the slug and the exact name are.
  select * into c from public.category_agents where coalesce(active, true) and length(name) > 8 order by slug limit 1;
  o := o || jsonb_build_object('frag', public.fn_resolve_cat_agent(substr(lower(c.name), 2, 5)),
    'slug', public.fn_resolve_cat_agent(c.slug) = 'cat:' || c.slug, 'name', public.fn_resolve_cat_agent(c.name) is not null,
    'expert_nothing', public.fn_category_expert_ref('zz demo no such trade'));

  -- 2. Escalation: the words decide nothing; the text waits, nothing is recorded; the reasoned answer decides.
  v := public.fn_should_escalate(jsonb_build_object('text', 'ZZ DEMO is a refund dispute over a contract change legal here?', 'actor', 'sales_engineer'));
  o := o || jsonb_build_object('esc_reasons', v->'reasons', 'esc_needs', v->'needs_reasoning'->>'surface',
    'esc_opts', (select jsonb_agg(x->>'id') from jsonb_array_elements(v->'needs_reasoning'->'options') x where x->>'id' in ('legal_matter', 'neither')));
  select count(*) into n from public.decision_record;
  v := public.fn_decide('escalate', jsonb_build_object('text', 'ZZ DEMO the supplier kept the deposit and we will take him to court'), 'sales_engineer');
  o := o || jsonb_build_object('dec_wait', v->>'decision', 'dec_route', v->>'route_to', 'dec_records', (select count(*) from public.decision_record) - n);
  v_id := (v->>'held_id')::bigint;
  o := o || jsonb_build_object('dec_row', (select seat || ':' || surface || ':' || status || ':' || (expires_at is null) from public.reasoning_held_question where id = v_id));
  v := public.fn_reason_held_resolve(v_id, '{"status":"answered","answer":"ZZ","decision":{"choice":"legal_matter"}}'::jsonb);
  o := o || jsonb_build_object('dec_applied', v->>'status', 'dec_after', v->'effect'->'decided'->>'decision',
    'dec_after_reason', v->'effect'->'decided'->'reasons'->>0);
  v := public.fn_decide('approve', jsonb_build_object('text', 'ZZ DEMO please approve the brochure reprint'), 'sales_engineer');
  perform public.fn_reason_held_resolve((v->>'held_id')::bigint, '{"status":"answered","answer":"ZZ","decision":{"choice":"neither"}}'::jsonb);
  o := o || jsonb_build_object('neither', public.fn_should_escalate(jsonb_build_object('text', 'ZZ DEMO please approve the brochure reprint'))->'reasons');

  -- 3. The refund: its note is read by reasoning; until then it waits (no cycle, no decline on a word).
  select id into v_tx from public.transactions order by revealed_at desc nulls last limit 1;
  if v_tx is not null then
    insert into public.refunds (transaction_id, stripe_payment_intent, amount_fils, reason_code, reason_note, requested_by, status, currency)
    select t.id, t.payment_ref, round(coalesce(t.total_charged, t.reveal_fee) * 100)::bigint, 'supplier_unresponsive',
           'ZZ DEMO the customer says she paid the supplier in cash at the site', 'customer', 'requested', 'AED'
      from public.transactions t where t.id = v_tx
    returning id into v_ref;
    v := public.fn_ceo_refund_checklist(v_tx, 'approve', false);
    o := o || jsonb_build_object('rf_item', (select i->>'kind' from jsonb_array_elements(v->'items') i where i->>'item' = 'off_platform_engagement_reasoned'),
      'rf_offp_before', (select i->'evidence'->'off_platform_engagement_recorded' from jsonb_array_elements(v->'items') i where i->>'item' = 'no_refund_exclusion_applies'),
      'rf_nonrem_other', (select count(*) from jsonb_array_elements(v->'failed') i where not coalesce((i->>'remediable')::boolean, false)));
    -- The review runs inside a savepoint that is rolled back, so the refund is still open for the replay below.
    begin
      select count(*) into n from public.refund_ceo_review where refund_id = v_ref;
      v := public.fn_ceo_refund_review(v_ref, 'probe');
      o := o || jsonb_build_object('rf_review', v->>'outcome', 'rf_review_reason', v->>'reason', 'rf_cycles', (select count(*) from public.refund_ceo_review where refund_id = v_ref) - n);
      raise exception 'zz_b6_rollback';
    exception when others then if sqlerrm <> 'zz_b6_rollback' then raise; end if;
    end;
    -- The only live payment carries its own non-remediable findings (measured 23 Sep 2026: the supplier
    -- responded, the customer rated), so the waiting branch is proved against a checklist whose ONLY
    -- failures are remediable work and the unread note — the checklist's own shape, stubbed inside a
    -- rolled-back savepoint. The refund must WAIT: no cycle, no handoff, no decline, no founder page.
    begin
      -- the REAL checklist, over the live payment with its non-remediable facts taken away (all rolled back)
      update public.transactions set supplier_ack_at = null where id = v_tx;
      update public.messages set blocked = true where inquiry_id = (select inquiry_id from public.transactions where id = v_tx) and sender = 'supplier';
      delete from public.reviews where transaction_id = v_tx;
      delete from public.refund_ladder_evidence where transaction_id = v_tx;
      update public.supplier_response_watch set first_response_at = null where transaction_id = v_tx;
      delete from public.transactions x where x.id <> v_tx and x.customer_id = (select customer_id from public.transactions where id = v_tx)
        and x.supplier_id = (select supplier_id from public.transactions where id = v_tx);
      update public.inquiries set status = 'open' where id = (select inquiry_id from public.transactions where id = v_tx) and status in ('completed', 'closed');
      v := public.fn_ceo_refund_checklist(v_tx, 'approve', false);
      o := o || jsonb_build_object('rf2_failed', (select jsonb_agg(i->>'item' order by i->>'item') from jsonb_array_elements(v->'failed') i),
        'rf2_nonrem', (select count(*) from jsonb_array_elements(v->'failed') i where not coalesce((i->>'remediable')::boolean, false)));
      select count(*) into n from public.refund_ceo_review where refund_id = v_ref;
      -- the review runs in its own statement, so the counts below see what it wrote
      v := public.fn_ceo_refund_review(v_ref, 'probe');
      o := o || jsonb_build_object('rf2_review', v->>'outcome',
        'rf2_cycles', (select count(*) from public.refund_ceo_review where refund_id = v_ref) - n,
        'rf2_handoffs', (select count(*) from public.agent_actions a where a.detail->>'type' = 'refund.remediate' and a.detail->>'refund_id' = v_ref::text),
        'rf2_reasoning_handoffs', (select count(*) from public.agent_actions a where a.detail->>'type' = 'refund.remediate' and a.detail->>'refund_id' = v_ref::text and a.detail->>'remedy_key' = 'reasoning'));
      -- Now the ladder is complete too, so the unread note is the ONLY failure: the refund must rest.
      delete from public.agent_actions where detail->>'type' = 'refund.remediate' and detail->>'refund_id' = v_ref::text;
      delete from public.refund_ceo_review where refund_id = v_ref;
      insert into public.refund_ladder_evidence (transaction_id, refund_id, step, result, delivered)
      values (v_tx, v_ref, 'chase', 'no_response_confirmation', true), (v_tx, v_ref, 'final_call', 'no_response_confirmation', true);
      v := public.fn_ceo_refund_checklist(v_tx, 'approve', false);
      o := o || jsonb_build_object('rf3_failed', (select jsonb_agg(i->>'item') from jsonb_array_elements(v->'failed') i),
        'rf3_review', null);
      v := public.fn_ceo_refund_review(v_ref, 'probe');
      o := o || jsonb_build_object('rf3_review', v->>'outcome',
        'rf3_cycles', (select count(*) from public.refund_ceo_review where refund_id = v_ref),
        'rf3_handoffs', (select count(*) from public.agent_actions a where a.detail->>'type' = 'refund.remediate' and a.detail->>'refund_id' = v_ref::text));
      raise exception 'zz_b6_rollback';
    exception when others then if sqlerrm <> 'zz_b6_rollback' then raise; end if;
    end;
    select id into v_id from public.reasoning_held_question where surface = 'ceo.refund_off_platform' and subject->>'refund_id' = v_ref::text;
    -- The reasoned answer is read by the checklist; the replay re-runs the review, which now cites it.
    update public.reasoning_held_question set status = 'reasoned', result = '{"status":"answered","decision":{"choice":"engaged_off_platform"}}'::jsonb where id = v_id;
    v := public.fn_ceo_refund_checklist(v_tx, 'approve', false);
    o := o || jsonb_build_object('rf_offp_after', (select i->'evidence'->'off_platform_engagement_recorded' from jsonb_array_elements(v->'items') i where i->>'item' = 'no_refund_exclusion_applies'),
      'rf_reasoned_item_gone', not exists (select 1 from jsonb_array_elements(v->'items') i where i->>'item' = 'off_platform_engagement_reasoned'));
    update public.reasoning_held_question set status = 'held' where id = v_id;
    v := public.fn_reason_held_resolve(v_id, '{"status":"answered","answer":"ZZ","decision":{"choice":"engaged_off_platform"}}'::jsonb);
    o := o || jsonb_build_object('rf_row', (select status from public.reasoning_held_question where id = v_id),
      'rf_apply_review', v->'effect'->'review'->>'outcome', 'rf_apply_reason', v->'effect'->'review'->>'reason');
    update public.refunds set reason_note = 'The customer reported that the revealed supplier has not responded.' where id = v_ref;
    v := public.fn_ceo_refund_checklist(v_tx, 'approve', false);
    o := o || jsonb_build_object('rf_default_note_asks', exists (select 1 from jsonb_array_elements(v->'items') i where i->>'item' = 'off_platform_engagement_reasoned'));
  end if;

  -- 4. The supplier's document: filed on save; fills no slot until reasoned; then fills the ISO slot.
  select id into v_lead from public.leads where iso_doc_path is null order by id limit 1;
  insert into public.documents (bucket, path, file_name, kind, ref_table, ref_id, status)
  values ('supplier-docs', 'supporting/' || v_lead || '/zz_demo.pdf', 'ZZ DEMO ISO 9001:2015 certificate', 'supporting:certificate', 'supplier_supporting', v_lead::text, 'received')
  returning id into v_doc;
  select id into v_id from public.reasoning_held_question where dedupe_key = 'supdoc:' || v_doc || ':' || md5('ZZ DEMO ISO 9001:2015 certificate');
  o := o || jsonb_build_object('doc_asked', (select seat || ':' || surface from public.reasoning_held_question where id = v_id),
    'doc_before', (select source from public.fn_supplier_document_home(v_lead) where key = 'iso'));
  perform public.fn_reason_held_resolve(v_id, '{"status":"answered","answer":"ZZ","decision":{"choice":"iso"}}'::jsonb);
  o := o || jsonb_build_object('doc_after', (select source || ':' || (path like '%zz_demo.pdf') from public.fn_supplier_document_home(v_lead) where key = 'iso'),
    'doc_backfilled', (select count(*) from public.reasoning_held_question where surface = 'supplier_documents.subject'));

  -- 5. A repeat request: the same summary is flagged at once; a different wording waits for reasoning.
  insert into public.customers (email, full_name) values ('zz-demo-b6@example.invalid', 'ZZ DEMO B6') returning id into v_cust;
  insert into public.inquiries (customer_id, category, summary) values (v_cust, 'tiling', 'ZZ DEMO lay 20 m2 of porcelain tiles in a villa kitchen') returning id into v_i1;
  insert into public.inquiries (customer_id, category, summary) values (v_cust, 'tiling', 'ZZ DEMO lay 20 m2 of porcelain tiles in a villa kitchen') returning id into v_i2;
  insert into public.inquiries (customer_id, category, summary) values (v_cust, 'tiling', 'ZZ DEMO kitchen floor tiling, about twenty square metres, porcelain') returning id into v_i3;
  o := o || jsonb_build_object('dup_same', (select plausibility->>'possible_duplicate' from public.inquiries where id = v_i2),
    'dup_reworded_before', (select plausibility->>'possible_duplicate' from public.inquiries where id = v_i3));
  select id into v_id from public.reasoning_held_question where dedupe_key = 'inquiry_dup:' || v_i3;
  perform public.fn_reason_held_resolve(v_id, '{"status":"answered","answer":"ZZ","decision":{"choice":"same_request"}}'::jsonb);
  o := o || jsonb_build_object('dup_reworded_after', (select plausibility->>'duplicate_by' from public.inquiries where id = v_i3));

  -- 6. A task's owner: no owner on a word; the reasoned responsibility records it.
  select id into v_task from public.org_tasks where coalesce(result->>'deliverable', '') <> '' order by id desc limit 1;
  v := public.fn_task_review(v_task);
  o := o || jsonb_build_object('task_waits', v->'awaiting_reasoning'->0->>'surface', 'task_owner_before', v->>'owns_responsibility');
  select responsibility into v_resp from public.os_responsibility order by responsibility limit 1;
  v := public.fn_reason_held_resolve((select id from public.reasoning_held_question where dedupe_key like 'task_resp:' || v_task || ':%'),
         jsonb_build_object('status', 'answered', 'answer', 'ZZ', 'decision', jsonb_build_object('choice', v_resp)));
  o := o || jsonb_build_object('task_applied', v->>'status', 'task_owner_after', v->'effect'->>'owns_responsibility' = v_resp);

  -- 7. Only service_role executes.
  o := o || jsonb_build_object('anon_can', (select bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
            from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
            ('fn_reason_route_ask', 'fn_reason_route_answer', 'fn_resolve_cat_agent', 'fn_category_expert_ref', 'trg_inquiry_enrich',
             'fn_supplier_document_home', 'fn_should_escalate', 'fn_decide', 'fn_ceo_refund_checklist', 'fn_ceo_refund_review', 'fn_task_review',
             'fn_task_ownership_record', 'fn_supplier_document_subject_ask', 'trg_supplier_document_subject_asked',
             'fn_reason_apply_ceo__escalation_meaning', 'fn_reason_apply_ceo__refund_off_platform', 'fn_reason_apply_ceo__task_responsibility',
             'fn_reason_apply_ceo__task_collaboration_rule', 'fn_reason_apply_inquiry__same_request')));
  raise exception 'CHK<<%>>', o::text;
end $p$;`);
  console.log(JSON.stringify(out, null, 1));
  assert.equal(out.frag, null, 'a fragment of a catalogue name is not a desk');
  assert.equal(out.slug, true);
  assert.equal(out.name, true);
  assert.equal(out.expert_nothing, '');

  assert.deepEqual(out.esc_reasons, [], 'legal_triggers words in the text decide nothing');
  assert.equal(out.esc_needs, 'ceo.escalation_meaning');
  assert.deepEqual(out.esc_opts, ['legal_matter', 'neither']);
  assert.equal(out.dec_wait, 'awaiting_reasoning');
  assert.equal(out.dec_route, 'ceo', 'the waiting escalation sits with the CEO seat, never the founder');
  assert.equal(out.dec_records, 0, 'nothing is recorded before the meaning is reasoned');
  assert.equal(out.dec_row, 'ceo:ceo.escalation_meaning:held:true');
  assert.equal(out.dec_applied, 'applied');
  assert.equal(out.dec_after, 'escalate');
  assert.match(out.dec_after_reason, /legal matter \(reasoned/);
  assert.deepEqual(out.neither, [], 'a reasoned "neither" escalates nothing');

  if (out.rf_item !== undefined) {
    assert.equal(out.rf_item, 'needs_reasoning');
    assert.equal(out.rf_offp_before, null, 'no exclusion is assumed before the note is read');
    if (out.rf_nonrem_other > 0) {
      assert.equal(out.rf_review, 'declined');
      assert.doesNotMatch(String(out.rf_review_reason), /off the platform/);
    } else {
      assert.equal(out.rf_review, 'waiting_on_reasoning');
      assert.equal(out.rf_cycles, 0, 'a question still being reasoned spends no cycle and pages nobody');
    }
    // the real checklist: only remediable work fails besides the unread note
    assert.equal(out.rf2_nonrem, 0, 'the savepoint left no non-remediable finding: ' + JSON.stringify(out.rf2_failed));
    assert.ok(out.rf2_failed.includes('off_platform_engagement_reasoned'));
    assert.equal(out.rf2_review, 'rejected', 'the other remediable work still goes to its owners while the note is reasoned');
    assert.ok(out.rf2_handoffs > 0);
    assert.equal(out.rf2_reasoning_handoffs, 0, 'no person is handed a question only reasoning answers');
    assert.deepEqual(out.rf3_failed, ['off_platform_engagement_reasoned'], 'the real checklist: only the unread note fails');
    assert.equal(out.rf3_review, 'waiting_on_reasoning', 'a refund whose note is unread waits');
    assert.equal(out.rf3_cycles, 0, 'no cycle is spent, so three of them can never page the founder');
    assert.equal(out.rf3_handoffs, 0);
    assert.equal(out.rf_offp_after, true);
    assert.equal(out.rf_reasoned_item_gone, true);
    assert.equal(out.rf_row, 'applied');
    assert.equal(out.rf_apply_review, 'declined', 'the replay re-runs the CEO review on the reasoned answer');
    assert.match(String(out.rf_apply_reason), /off the platform \(reasoned/);
    assert.equal(out.rf_default_note_asks, false, 'our own default note asks nothing');
  }

  assert.equal(out.doc_asked, 'sales_engineer:supplier_documents.subject');
  assert.notEqual(out.doc_before, 'supporting', 'an unreasoned label fills no slot');
  assert.equal(out.doc_after, 'supporting:true');
  assert.ok(out.doc_backfilled >= 7, 'the live supporting documents were asked about');

  assert.equal(out.dup_same, 'true');
  assert.equal(out.dup_reworded_before, null, 'a differently worded request is not flagged on a substring');
  assert.equal(out.dup_reworded_after, 'reasoning');

  assert.equal(out.task_waits, 'ceo.task_responsibility');
  assert.equal(out.task_owner_before, null);
  assert.equal(out.task_applied, 'applied');
  assert.equal(out.task_owner_after, true);
  assert.equal(out.anon_can, false);
});

test('production, aborted (B6): supplier trades are reasoned behind a gate and a cap; category keys are declared or reasoned',
  { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const out = await probe(String.raw`
do $p$
declare o jsonb := '{}'::jsonb; v jsonb; a bigint; b bigint; c bigint; v_id bigint; v_code text; v_word text; v_key text;
begin
  insert into public.leads (company_name, categories, description) values ('ZZ DEMO B6 One', 'ZZ DEMO', 'ZZ DEMO we install split air conditioners') returning id into a;
  insert into public.leads (company_name, categories, description) values ('ZZ DEMO B6 Two', 'ZZ DEMO', 'ZZ DEMO') returning id into b;
  insert into public.leads (company_name, categories, description) values ('ZZ DEMO B6 Three', 'ZZ DEMO', 'ZZ DEMO') returning id into c;

  -- 1. No gate, nothing filed; a value other than exactly go is no gate.
  delete from public.app_secrets where key = 'lead_reclassify_backfill';
  v := public.fn_lead_reclassify_tick(20, array[a, b, c]);
  o := o || jsonb_build_object('off', v->>'reason', 'off_filed', (select count(*) from public.reasoning_held_question where surface = 'lead_trade.classify' and subject->>'lead_id' in (a::text, b::text, c::text)));
  insert into public.app_secrets (key, value) values ('lead_reclassify_backfill', 'maybe');
  o := o || jsonb_build_object('not_go', public.fn_lead_reclassify_tick(20, array[a, b, c])->>'reason');

  -- 2. 'go' under the model hold: nothing is filed (it would only wait and pile up in the seat's queue).
  update public.app_secrets set value = 'go' where key = 'lead_reclassify_backfill';
  o := o || jsonb_build_object('held_gate', public.fn_lead_reclassify_tick(20, array[a, b, c])->>'reason');
  -- ... and with the models open (the gate stubbed inside this aborted transaction) and room for exactly two more
  -- today: two filed, then the cap stops the third.
  create or replace function public.fn_kernel_paid_provider_gate(p_model text default null) returns jsonb language sql as $g$ select '{"allowed":true,"rule":"zz_probe_open"}'::jsonb $g$;
  insert into public.app_secrets (key, value) values ('lead_reclassify_daily_cap', '0') on conflict (key) do update set value = '0';
  update public.app_secrets set value = ((select count(*) from public.reasoning_held_question where surface = 'lead_trade.classify'
    and created_at >= date_trunc('day', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai') + 2)::text where key = 'lead_reclassify_daily_cap';
  v := public.fn_lead_reclassify_tick(20, array[a, b, c]);
  o := o || jsonb_build_object('go_filed', v->'filed', 'capped', public.fn_lead_reclassify_tick(20, array[a, b, c])->>'reason',
    'go_rows', (select count(*) from public.reasoning_held_question where surface = 'lead_trade.classify' and subject->>'lead_id' in (a::text, b::text, c::text)),
    'go_seat', (select seat || ':' || jsonb_array_length(request->'decision'->'options') from public.reasoning_held_question where dedupe_key = 'lead_trade:' || a));

  -- 3. The reasoned trade is stored with its evidence; an invented one is not; the twin counts it.
  select code into v_code from public.taxonomy_trade where active order by sort, code limit 1;
  v_id := (select id from public.reasoning_held_question where dedupe_key = 'lead_trade:' || a);
  perform public.fn_reason_held_resolve(v_id, jsonb_build_object('status', 'answered', 'answer', 'ZZ the description says it installs split units', 'confidence', 0.8, 'decision', jsonb_build_object('choice', v_code)));
  v_id := (select id from public.reasoning_held_question where dedupe_key = 'lead_trade:' || b);
  perform public.fn_reason_held_resolve(v_id, '{"status":"answered","answer":"ZZ","decision":{"choice":"zz_not_a_trade"}}'::jsonb);
  update public.app_secrets set value = '100000' where key = 'lead_reclassify_daily_cap';   -- room for the re-ask below
  v := public.fn_lead_reclassify_tick(20, array[b]);
  o := o || jsonb_build_object('invented_reasked', v->>'filed', 'invented_new_row', (select status from public.reasoning_held_question where dedupe_key = 'lead_trade:' || b));
  o := o || jsonb_build_object('stored', (select trade_code || ':' || confidence || ':' || (evidence like 'ZZ the description%') from public.lead_trade_class where lead_id = a),
    'invented_stored', exists (select 1 from public.lead_trade_class where lead_id = b),
    'no_shortlist_agreed', (select shortlist_agreed from public.lead_trade_class where lead_id = a),
    'twin_pool', (public.fn_twin('category', v_code)->>'supplier_pool_total')::int >= 1,
    'twin_words', (public.fn_twin('category', 'zz demo')->>'supplier_pool_total')::int);

  -- 4. A vocabulary word no declared rung maps has no key until reasoned; the reasoned key is then read back.
  select w into v_word from (select distinct lower(btrim(category)) w from public.category_specs) s
   where not exists (select 1 from public.category_route_map m where m.category = s.w)
     and not exists (select 1 from public.catalog_supplier_categories x where x.slug = s.w) order by w limit 1;
  o := o || jsonb_build_object('word', v_word, 'word_before', public.fn_category_key_for_slug(v_word),
    'word_asked', exists (select 1 from public.reasoning_held_question where dedupe_key = 'category_key:' || v_word));
  select category_key into v_key from public.org_category_identity order by category_key limit 1;
  perform public.fn_reason_held_resolve((select id from public.reasoning_held_question where dedupe_key = 'category_key:' || v_word),
    jsonb_build_object('status', 'answered', 'answer', 'ZZ', 'decision', jsonb_build_object('choice', v_key)));
  o := o || jsonb_build_object('word_after', public.fn_category_key_for_slug(v_word) = v_key);

  o := o || jsonb_build_object('anon_can', (select bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
            from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
            ('fn_lead_reclassify_tick', 'fn_reason_apply_lead_trade__classify', 'fn_category_key_for_slug', 'fn_category_key_ask', 'trg_category_key_asked',
             'fn_twin')));
  raise exception 'CHK<<%>>', o::text;
end $p$;`);
  console.log(JSON.stringify(out, null, 1));
  assert.equal(out.off, 'gate_off');
  assert.equal(out.off_filed, 0, 'without the gate nothing is filed');
  assert.equal(out.not_go, 'gate_off', 'only the exact word go opens it');
  assert.equal(out.held_gate, 'model_hold', 'under the hold the backfill files nothing, even at go');
  assert.equal(out.go_filed, 2);
  assert.equal(out.capped, 'daily_cap', 'the daily cap stops the third');
  assert.equal(out.go_rows, 2);
  assert.match(out.go_seat, /^sales_engineer:(19[0-9]|2[0-9][0-9])$/, 'every active trade (195) plus none is offered');
  assert.match(out.stored, /:0\.8:true$/);
  assert.equal(out.invented_stored, false, 'an option that does not exist is never stored');
  assert.equal(out.invented_new_row, 'held', 'the lead is asked again rather than left unclassified forever');
  assert.equal(out.no_shortlist_agreed, null, 'no shortlist is not a disagreement');
  assert.equal(out.twin_pool, true);
  assert.equal(out.twin_words, 0, 'the free-text categories column counts no supplier');
  assert.ok(out.word, 'a vocabulary word without a declared key exists (measured 23 Sep 2026: 40)');
  assert.equal(out.word_before, null, 'no key on a substring');
  assert.equal(out.word_asked, true);
  assert.equal(out.word_after, true);
  assert.equal(out.anon_can, false);
});

test('production, aborted: documents.boq_arabic — a replayed heading reading is remembered; the table and routine are service_role only',
  { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const out = await probe(String.raw`
do $p$
declare o jsonb := '{}'::jsonb; v_id bigint;
begin
  v_id := public.fn_reason_hold('sales_engineer', 'documents.boq_arabic', 'ZZ DEMO heading', '{"seat":"sales_engineer"}'::jsonb, '{}'::jsonb,
    '{"section_key":"zz demo ceilings","section":"ZZ DEMO Ceilings"}'::jsonb, 'model_hold', 'boq_section:zz demo ceilings');
  o := o || jsonb_build_object('resolved', public.fn_reason_held_resolve(v_id, '{"status":"answered","answer":"ZZ","decision":{"choice":"ceilings"}}'::jsonb));
  o := o || jsonb_build_object('reading', (select reading || ':' || reasoned_by from public.boq_section_reading where section_key = 'zz demo ceilings'));
  v_id := public.fn_reason_hold('sales_engineer', 'documents.boq_arabic', 'ZZ DEMO heading 2', '{"seat":"sales_engineer"}'::jsonb, '{}'::jsonb,
    '{"section_key":"zz demo bill 9"}'::jsonb, 'model_hold', 'boq_section:zz demo bill 9');
  o := o || jsonb_build_object('no_choice', public.fn_reason_apply_documents__boq_arabic(v_id, '{"status":"answered","answer":"ZZ","decision":null}'::jsonb)->>'applied');
  o := o || jsonb_build_object('anon_can', has_function_privilege('anon', 'public.fn_reason_apply_documents__boq_arabic(bigint, jsonb)', 'execute'),
    'auth_table', has_table_privilege('authenticated', 'public.boq_section_reading', 'select'),
    'service_can', has_function_privilege('service_role', 'public.fn_reason_apply_documents__boq_arabic(bigint, jsonb)', 'execute'),
    'rls', (select relrowsecurity from pg_class where oid = 'public.boq_section_reading'::regclass),
    'reads_text', (select prosrc ~* '(ilike|~\*| like )' from pg_proc where proname = 'fn_reason_apply_documents__boq_arabic'));
  raise exception 'CHK<<%>>', o::text;
end $p$;`);
  assert.equal(out.resolved.status, 'applied');
  assert.equal(out.reading, 'ceilings:replay');
  assert.equal(out.no_choice, 'false', 'no reasoned choice, nothing remembered — never a guess');
  assert.equal(out.anon_can, false);
  assert.equal(out.auth_table, false);
  assert.equal(out.service_can, true);
  assert.equal(out.rls, true);
  assert.equal(out.reads_text, false);
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

// Batch 8, the gate the pending note names: once the vector columns exist, no runtime-eligible support or CEO record may
// be without one (it would be invisible: those packs are read by meaning only). Before the apply the columns do not
// exist and there is nothing to measure yet; the check says so rather than passing silently.
test('production: no eligible support or ceo record is without its gte-small vector', { skip: hasToken ? false : 'no Supabase management token' }, async (t) => {
  const { sql } = await import('../lib/db.mjs');
  const [c] = await sql(`select count(*)::int n from information_schema.columns where table_schema = 'public'
                           and table_name in ('support_knowledge', 'ceo_knowledge') and column_name = 'embedding_gte'`, { readOnly: true });
  if (c.n < 2) { t.skip('the_books_and_the_knowledge_are_read_by_meaning_not_by_words.sql is not applied yet'); return; }
  const [r] = await sql(`select (select count(*) from public.support_knowledge where runtime_index_eligible and embedding_gte is null)::int s,
                                 (select count(*) from public.ceo_knowledge where runtime_index_eligible and embedding_gte is null)::int c`, { readOnly: true });
  assert.deepEqual(r, { s: 0, c: 0 }, 'run node scripts/kb/embed_sales_knowledge.mjs --table=support_knowledge and --table=ceo_knowledge');
});

// Batch B7 (seat ceo): governance reads keys and reasons. scripts/sql/governance_reads_keys_and_reasons_rather_than_spotting_words.sql
test('production, aborted: B7 — demand, challenge, what-if, founder mail, digest, governance, knowledge jurisdiction and Arabic read no words for meaning',
  { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const out = await probe(String.raw`
do $p$
declare o jsonb := '{}'::jsonb; v jsonb; v_id bigint; v_n bigint; v_h bigint;
begin
  -- 55 demand: an exact key, and the spelling of an unregistered one decides nothing
  o := o || jsonb_build_object('demand_invite', public.fn_task_is_demand('invite'), 'demand_analysis', public.fn_task_is_demand('analysis'),
                               'demand_spelled', public.fn_task_is_demand('zz_invite_customer_quote'));
  -- 56 challenge: held (no stance from the words), then applied by its surface
  v := public.fn_challenge('ZZ DEMO raise the reveal fee and skip the review', 'founder', 'zz_demo');
  o := o || jsonb_build_object('challenge_stance', v->>'stance');
  v_id := (v->>'held_id')::bigint;
  select jsonb_build_object('challenge_surface', surface, 'challenge_has_none', exists (select 1 from jsonb_array_elements(request->'decision'->'options') x where x->>'id' = 'none'),
                            'challenge_has_rank1', exists (select 1 from jsonb_array_elements(request->'decision'->'options') x where x->>'id' = 'h' || (select min(id) from public.challenge_heuristic where active and rank_touched = 1)))
    into v from public.reasoning_held_question where id = v_id;
  o := o || v;
  v := public.fn_reason_held_resolve(v_id, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO reasoned',
         'decision', jsonb_build_object('choice', 'h' || (select min(id) from public.challenge_heuristic where active and rank_touched = 1))));
  o := o || jsonb_build_object('challenge_applied', v->>'status', 'challenge_reasoned_stance', v->'effect'->>'stance',
                               'challenge_record', (select stance from public.challenge_record where id = (v->'effect'->>'challenge_record_id')::bigint));
  v := public.fn_board_review('ZZ DEMO expand to a new market', null);
  o := o || jsonb_build_object('board_verdict', v->>'board_verdict', 'board_proceed', (v->>'proceed')::int);
  -- 57 what-if: held, then the reasoned scenario key runs the simulation
  v := public.fn_what_if('ZZ DEMO what if we lower the reveal fee', '{}'::jsonb);
  o := o || jsonb_build_object('what_if_status', v->>'status');
  v := public.fn_reason_held_resolve((v->>'held_id')::bigint, '{"status":"answered","answer":"ZZ","decision":{"choice":"reveal_fee_discount"}}'::jsonb);
  o := o || jsonb_build_object('what_if_applied', v->>'status',
    'what_if_scenario', (select result->>'scenario' from public.simulations where id = (v->'effect'->>'simulation_id')::bigint));
  -- 58 founder mail: the level is the stated severity; a CRITICAL subject decides nothing
  insert into public.notifications (type, kind, to_role, subject, body, status, channel)
  values ('zz_demo_signal', 'zz_demo_unregistered', 'founder', 'CRITICAL URGENT system down', 'ZZ DEMO', 'queued', 'email');
  o := o || jsonb_build_object('mail_queued_to_founder', exists (select 1 from public.notifications where kind = 'zz_demo_unregistered'),
    'mail_task_level', (select result->'founder_mail'->>'level' from public.org_tasks where result->'founder_mail'->>'kind' = 'zz_demo_unregistered' order by id desc limit 1));
  -- 58/59 THROUGH THE REAL PRODUCER: fn_notify_founder (the uptime / platform_down / outbox-heartbeat path) states
  -- severity from its p_level, so a real outage goes at once. Inside this aborted transaction nothing commits, so
  -- send_outbox can never see these rows: incapable of reaching the founder, not merely careful.
  v := public.fn_notify_founder('ZZ DEMO probe outage', 'ZZ DEMO', 'critical', 'uptime_alert', 'zz-demo-b7-probe', null);
  select jsonb_build_object('producer_severity', min(severity), 'producer_status', min(status), 'producer_rows', count(*))
    into v from public.notifications where subject = '[Attention] ZZ DEMO probe outage' and channel = 'email';
  o := o || v;
  -- A producer that inserts directly and states nothing: its TYPE's registered severity decides (an outage type
  -- goes at once, a routine type folds), never its subject. No address at all (a demo address is captured to
  -- 'suppressed' after the digest runs); uptime_alert / ai_quality_alert are both listed digest types.
  insert into public.notifications (type, kind, to_role, subject, body, status, channel)
  values ('uptime_alert', 'uptime_alert', 'founder', 'routine words', 'ZZ DEMO', 'queued', 'email') returning id into v_n;
  o := o || jsonb_build_object('type_outage', (select status || ':' || severity from public.notifications where id = v_n));
  insert into public.notifications (type, kind, to_role, subject, body, status, channel)
  values ('ai_quality_alert', 'uptime_alert', 'founder', 'CRITICAL failed down', 'ZZ DEMO', 'queued', 'email') returning id into v_n;
  o := o || jsonb_build_object('type_routine', (select status || ':' || severity from public.notifications where id = v_n));
  -- the lifecycle: a failed held question filed again is REOPENED (held, attempts 0, not escalated)
  v_id := public.fn_reason_hold('ceo', 'ceo.kb_jurisdiction', 'ZZ DEMO', '{"seat":"ceo"}'::jsonb, '{}'::jsonb, null, 'model_hold', 'zz-demo-b7-reopen');
  update public.reasoning_held_question set status = 'failed', attempts = 5, escalated_at = now() where id = v_id;
  perform public.fn_reason_hold('ceo', 'ceo.kb_jurisdiction', 'ZZ DEMO', '{"seat":"ceo"}'::jsonb, '{}'::jsonb, null, 'model_hold', 'zz-demo-b7-reopen');
  o := o || jsonb_build_object('reopened', (select status || ':' || attempts || ':' || (escalated_at is null) || ':' || (expires_at is null) || ':' || (created_at >= now()) from public.reasoning_held_question where id = v_id));
  -- a line that is only a code is kept as written (else its document would be held for ever); a waiting quotation is
  -- found by its own id once its lines are in, whoever filed them
  perform public.fn_arabic_document_wait('zz-demo-b7-quote', array['ZZ DEMO IP65', 'ZZ DEMO waiter line']);
  perform public.fn_arabic_translation_store('{"ZZ DEMO IP65":"ZZ DEMO IP65","Zz Demo Wardrobe":"Zz Demo Wardrobe"}'::jsonb, null);
  o := o || jsonb_build_object('prose_echo_rejected', not (public.fn_arabic_translations(array['Zz Demo Wardrobe']) ? 'Zz Demo Wardrobe'));
  o := o || jsonb_build_object('kept_code', public.fn_arabic_translations(array['ZZ DEMO IP65'])->>'ZZ DEMO IP65',
    'waiter_early', (select public.fn_arabic_waiters_ready(100) ? 'zz-demo-b7-quote'));
  perform public.fn_arabic_translation_store('{"ZZ DEMO waiter line":"سطر"}'::jsonb, null);
  o := o || jsonb_build_object('waiter_ready', (select public.fn_arabic_waiters_ready(100) ? 'zz-demo-b7-quote'));
  -- 60 governance: a registered kind escalates; a kind merely SPELLED like one does not
  insert into public.agent_actions (agent, kind, title, confidence) values ('ceo', 'finance_alert', 'ZZ DEMO', 0.9) returning id into v_n;
  o := o || jsonb_build_object('gov_registered', (select escalated from public.agent_actions where id = v_n));
  insert into public.agent_actions (agent, kind, title, confidence) values ('ceo', 'zz_legal_refund_payment', 'ZZ DEMO', 0.9) returning id into v_n;
  o := o || jsonb_build_object('gov_spelled', (select escalated from public.agent_actions where id = v_n));
  -- 61 knowledge: undecided is kept; a reasoned 'us' is deleted; the citation regex is gone
  o := o || jsonb_build_object('kb_null', public.fn_kb_purge_clause('standard', 'x', null), 'kb_us', public.fn_kb_purge_clause('standard', 'x', 'us'),
    'kb_uae', public.fn_kb_purge_clause('standard', 'x', 'uae'), 'kb_ours', public.fn_kb_purge_clause('standard', 'x', 'quotesdone'),
    'kb_citation_text', public.fn_kb_purge_clause('standard', 'x', 'NFPA 13 United States Code'),
    'kb_is_us_code_gone', to_regprocedure('public.fn_kb_is_us_code(text)') is null);
  -- the paid backfill: nothing without the founder's 'go', and never past the daily cap
  delete from public.app_secrets where key = 'kb_jurisdiction_backfill';
  o := o || jsonb_build_object('kb_no_go', public.fn_kb_jurisdiction_file(5));
  insert into public.app_secrets (key, value) values ('kb_jurisdiction_backfill', 'go');
  update public.decision_policy set value = to_jsonb((select count(*) from public.reasoning_held_question
      where surface = 'ceo.kb_jurisdiction' and created_at >= date_trunc('day', now() at time zone 'utc') at time zone 'utc')::int + 1)
   where key = 'kb_jurisdiction_daily_cap';
  o := o || jsonb_build_object('kb_filed', public.fn_kb_jurisdiction_file(5), 'kb_at_cap', public.fn_kb_jurisdiction_file(5));
  select id into v_h from public.reasoning_held_question where surface = 'ceo.kb_jurisdiction' order by id desc limit 1;
  v := public.fn_reason_held_resolve(v_h, '{"status":"answered","answer":"ZZ","decision":{"choice":"us"}}'::jsonb);
  o := o || jsonb_build_object('kb_applied', v->>'status',
    'kb_row', (select jurisdiction from public.kb_citation_jurisdiction where held_id = v_h));
  -- 62 Arabic: the replay stores only Arabic-script lines against the filed sources
  v_id := public.fn_reason_hold('sales_engineer', 'sales_engineer.document_arabic', 'ZZ DEMO', '{"seat":"sales_engineer"}'::jsonb, '{}'::jsonb,
            '{"sources":["ZZ DEMO wardrobe carcass","ZZ DEMO second line"]}'::jsonb, 'model_hold', 'zz-demo-arabic-1');
  v := public.fn_reason_held_resolve(v_id, jsonb_build_object('status', 'answered', 'answer', '{"1":"هيكل خزانة","2":"still English"}'));
  o := o || jsonb_build_object('ar_applied', v->>'status', 'ar_stored', v->'effect'->'stored',
    'ar_lookup', public.fn_arabic_translations(array['ZZ DEMO wardrobe carcass', 'ZZ DEMO second line']));
  -- an Arabic MESSAGE is parked until its line is reasoned, then sent whole (never with English or a placeholder)
  v_n := public.fn_arabic_outbound_park(array['ZZ DEMO parked line'],
    jsonb_build_array(jsonb_build_object('type', 'spec_offer_accepted', 'kind', 'customer_support_spec_offer_accepted', 'to_role', 'customer',
      'channel', 'email', 'to_email', 'zz-demo-b7@example.invalid', 'subject', 'ZZ', 'body', 'سنمضي باعتماد ⟦ZZ DEMO parked line⟧', 'status', 'queued',
      'lang', 'ar', 'requested_by', 'customer_support', 'sender', 'customer_support', 'dedupe_key', 'zz-demo-b7-parked')));
  o := o || jsonb_build_object('parked_before', (select status from public.arabic_outbound_hold where id = v_n));
  perform public.fn_arabic_translation_store('{"ZZ DEMO parked line":"سطر مترجم"}'::jsonb, null);
  o := o || jsonb_build_object('parked_after', (select status from public.arabic_outbound_hold where id = v_n),
    'parked_body', (select body from public.notifications where to_email = 'zz-demo-b7@example.invalid' order by id desc limit 1));
  -- grants: service_role only on every new routine
  o := o || jsonb_build_object('anon_any', (select bool_or(has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute'))
      from unnest(array['public.fn_challenge(text,text,text,jsonb)', 'public.fn_what_if(text,jsonb,text)', 'public.fn_kb_jurisdiction_file(integer)',
                        'public.fn_reason_apply_ceo__challenge(bigint,jsonb)', 'public.fn_reason_apply_ceo__what_if(bigint,jsonb)',
                        'public.fn_reason_apply_ceo__kb_jurisdiction(bigint,jsonb)', 'public.fn_reason_apply_sales_engineer__document_arabic(bigint,jsonb)',
                        'public.fn_arabic_translations(text[])', 'public.fn_arabic_translation_store(jsonb,bigint)', 'public.fn_kb_purge_clause(text,text,text)',
                        'public.fn_arabic_outbound_park(text[],jsonb)', 'public.fn_arabic_outbound_flush(integer)', 'public.fn_notification_severity(text,text)',
                        'public.fn_notify_founder(text,text,text,text,text,text)', 'public.fn_arabic_document_wait(text,text[])',
                        'public.fn_arabic_waiters_ready(integer)', 'public.fn_spec_offer_restart_clock(bigint)', 'public.fn_reason_hold(text,text,text,jsonb,jsonb,jsonb,text,text)']) f),
    'service_all', (select bool_and(has_function_privilege('service_role', f, 'execute'))
      from unnest(array['public.fn_challenge(text,text,text,jsonb)', 'public.fn_what_if(text,jsonb,text)', 'public.fn_arabic_translations(text[])']) f),
    'old_overloads', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and ((p.proname = 'fn_challenge' and pronargs = 3) or (p.proname = 'fn_what_if' and pronargs = 2))));
  raise exception 'CHK<<%>>', o::text;
end $p$;`);
  assert.deepEqual([out.demand_invite, out.demand_analysis, out.demand_spelled], [true, false, false], 'the revenue path is a key, not a spelling');
  assert.equal(out.challenge_stance, 'held', 'no stance is taken from the words');
  assert.equal(out.challenge_surface, 'ceo.challenge');
  assert.ok(out.challenge_has_none && out.challenge_has_rank1);
  assert.equal(out.challenge_applied, 'applied');
  assert.equal(out.challenge_reasoned_stance, 'recommend_against');
  assert.equal(out.challenge_record, 'recommend_against');
  assert.match(out.board_verdict, /^HELD/);
  assert.equal(out.board_proceed, 0, 'no advisor proceeds on a guessed stance');
  assert.equal(out.what_if_status, 'held');
  assert.equal(out.what_if_applied, 'applied');
  assert.equal(out.what_if_scenario, 'reveal_fee_discount');
  assert.equal(out.mail_queued_to_founder, false, 'an unregistered kind is never mailed to the founder');
  assert.equal(out.mail_task_level, 'warn', '"CRITICAL URGENT" in the subject sets nothing; the unstated level is the normal one');
  assert.equal(out.producer_severity, 'critical', 'fn_notify_founder states the severity of what it queues');
  assert.equal(out.producer_status, 'queued', 'a real outage from the real producer is sent at once, not digested');
  assert.equal(out.type_outage, 'queued:critical', 'an outage type goes at once whatever its subject says');
  assert.equal(out.type_routine, 'digest:warn', 'a routine type folds whatever its subject says');
  assert.equal(out.reopened, 'held:0:true:true:true', 'a failed question filed again is reopened (its 48-hour clock restarts), never left dead or expiring');
  assert.equal(out.kept_code, 'ZZ DEMO IP65');
  assert.equal(out.prose_echo_rejected, true, 'title-case English echoed back is not stored as its Arabic');
  assert.equal(out.waiter_early, false);
  assert.equal(out.waiter_ready, true);
  assert.equal(out.parked_before, 'held');
  assert.equal(out.parked_after, 'sent');
  assert.equal(out.parked_body, 'سنمضي باعتماد سطر مترجم', 'the parked message goes out whole, in Arabic');
  assert.equal(out.gov_registered, true);
  assert.equal(out.gov_spelled, false, 'a kind spelled "legal/refund/payment" is not sensitive unless registered');
  assert.deepEqual([out.kb_null, out.kb_us, out.kb_uae, out.kb_ours, out.kb_citation_text], [4, 5, 3, 1, 4], 'undecided knowledge is kept; citation text decides nothing');
  assert.equal(out.kb_is_us_code_gone, true);
  assert.equal(out.kb_no_go, 0, 'no paid backfill without app_secrets.kb_jurisdiction_backfill = go');
  assert.equal(out.kb_filed, 1, 'with go, it files up to the daily cap (5 asked, cap leaves 1)');
  assert.equal(out.kb_at_cap, 0, 'at the daily cap it files nothing more');
  assert.equal(out.kb_applied, 'applied');
  assert.equal(out.kb_row, 'us');
  assert.equal(out.ar_applied, 'applied');
  assert.equal(out.ar_stored, 1, 'a line the answer left in English is not stored');
  assert.deepEqual(out.ar_lookup, { 'ZZ DEMO wardrobe carcass': 'هيكل خزانة' });
  assert.equal(out.anon_any, false);
  assert.equal(out.service_all, true);
  assert.equal(out.old_overloads, 0);
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

// ── batch B2 (menus, comments, trades): the replay writes the reasoned trade on the row it was held for ─────────────
test('production, aborted: a held lead sector is set by its own routine — exact slug or nothing, empty sectors only',
  { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const out = await probe(String.raw`
do $p$
declare o jsonb := '{}'::jsonb; v_slug text; v_lead bigint; v_lead2 bigint; v_id bigint;
begin
  select category into v_slug from public.category_specs order by category limit 1;
  insert into public.leads (company_name, email, source, business_role) values ('ZZ DEMO probe lead', 'zz-b2-probe@example.invalid', 'email_inbound', 'supplier')
    returning id into v_lead;
  insert into public.leads (company_name, email, source, business_role, sector) values ('ZZ DEMO probe lead 2', 'zz-b2-probe3@example.invalid', 'email_inbound', 'supplier', 'zz-set-by-a-person')
    returning id into v_lead2;
  v_id := public.fn_reason_hold('sales_engineer', 'inbound_email.infer_sector', 'ZZ DEMO', '{"seat":"sales_engineer"}'::jsonb, '{}'::jsonb,
            jsonb_build_object('lead_id', v_lead), 'model_hold', 'zz-b2-sector-1');
  o := o || jsonb_build_object('sector_status', public.fn_reason_held_resolve(v_id, jsonb_build_object('status', 'answered', 'answer', 'ZZ', 'decision', jsonb_build_object('choice', v_slug)))->>'status');
  o := o || jsonb_build_object('sector_row', (select sector = v_slug from public.leads where id = v_lead));
  v_id := public.fn_reason_hold('sales_engineer', 'inbound_email.infer_sector', 'ZZ DEMO', '{"seat":"sales_engineer"}'::jsonb, '{}'::jsonb,
            jsonb_build_object('lead_id', v_lead2), 'model_hold', 'zz-b2-sector-2');
  perform public.fn_reason_held_resolve(v_id, jsonb_build_object('status', 'answered', 'answer', 'ZZ', 'decision', jsonb_build_object('choice', v_slug)));
  o := o || jsonb_build_object('sector_kept', (select sector from public.leads where id = v_lead2));
  v_id := public.fn_reason_hold('sales_engineer', 'inbound_email.infer_sector', 'ZZ DEMO', '{"seat":"sales_engineer"}'::jsonb, '{}'::jsonb,
            jsonb_build_object('lead_id', v_lead), 'model_hold', 'zz-b2-sector-3');
  update public.leads set sector = null where id = v_lead;
  perform public.fn_reason_held_resolve(v_id, '{"status":"answered","answer":"ZZ","decision":{"choice":"none"}}'::jsonb);
  o := o || jsonb_build_object('sector_none', (select sector from public.leads where id = v_lead));

  -- the routines read no free text, and only service_role executes them
  o := o || jsonb_build_object('reads_text', (select bool_or(p.prosrc ~ '(raw_input|summary|~\*|ilike)') from pg_proc p
            where p.proname = 'fn_reason_apply_inbound_email__infer_sector'),
    'anon_can', (select bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
            from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'fn_reason_apply_inbound_email__infer_sector'),
    'keywords_routine', to_regprocedure('public.fn_reason_apply_customer_api__keywords(bigint,jsonb)') is not null,
    'service_can', has_function_privilege('service_role', 'public.fn_reason_apply_inbound_email__infer_sector(bigint,jsonb)', 'execute'));
  raise exception 'CHK<<%>>', o::text;
end $p$;`);
  console.log(JSON.stringify(out));
  assert.equal(out.sector_status, 'applied');
  assert.equal(out.sector_row, true);
  assert.equal(out.sector_kept, 'zz-set-by-a-person', 'a sector already set is never overwritten');
  assert.equal(out.sector_none, null, "'none' writes no sector");
  assert.equal(out.reads_text, false);
  assert.equal(out.anon_can, false);
  assert.equal(out.keywords_routine, false, 'create_inquiry needs no replay routine: its trade is the intake\'s own');
  assert.equal(out.service_can, true);
});

// BATCH B3 (sales_engineer, points 23-27 + 77): trades, catalogue categories, product matches and spec groups read no
// free text for meaning. Aborted transaction; the batch file replays first while pending; nothing reaches a person.
test('production, aborted: batch B3 routines read no words for meaning, route only a reasoned category, and are service_role only',
  { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const out = await probe(String.raw`
do $p$
declare o jsonb := '{}'::jsonb; v jsonb; v_cat int;
begin
  o := o || jsonb_build_object('norm_free_text', public.fn_norm_trades('ZZ DEMO we need air conditioning for my villa'),
                               'norm_slug', public.fn_norm_trades('glass'));
  v := public.fn_kb_route_decide('ZZ DEMO supply and install aluminium windows for a villa');
  o := o || jsonb_build_object('route_unreasoned', v->>'action', 'route_candidates', jsonb_array_length(v->'candidates'), 'route_cat', v->'catalog_num');
  v_cat := (v->'candidates'->0->>'catalog_num')::int;
  v := public.fn_kb_route_decide('ZZ DEMO', v_cat);
  o := o || jsonb_build_object('route_reasoned', v->>'action', 'route_reasoned_cat', (v->>'catalog_num')::int = v_cat,
                               'route_bogus', public.fn_kb_route_decide('ZZ DEMO', -1)->>'action',
                               'kb_route_gone', to_regprocedure('public.fn_kb_route(text,integer)') is null,
                               'decide_old_gone', to_regprocedure('public.fn_kb_route_decide(text)') is null);
  o := o || jsonb_build_object('match_src_ilike', (select prosrc ~* 'ilike' from pg_proc where oid = 'public.fn_match_capability(text[],text,text[],text[],text,numeric,text,integer,text[])'::regprocedure),
    'product_status', public.fn_supplier_product_match('00000000-0000-4000-8000-000000000000'::uuid, -1)->>'status',
    'product_old_gone', to_regprocedure('public.fn_supplier_product_match(uuid,bigint)') is null,
    'group_marble', public.fn_quote_spec_group('marble-granite'), 'group_free_text', public.fn_quote_spec_group('air con duct cleaning'),
    'group_src_regex', (select position('~*' in prosrc) > 0 from pg_proc where oid = 'public.fn_quote_spec_group(text)'::regprocedure));
  o := o || jsonb_build_object('anon_can', (select bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
            from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
            ('fn_norm_trades', 'fn_kb_route_decide', 'fn_match_capability', 'fn_supplier_product_match', 'fn_quote_spec_group')),
    'service_can', has_function_privilege('service_role', 'public.fn_kb_route_decide(text,integer)', 'execute'));
  raise exception 'CHK<<%>>', o::text;
end $p$;`);
  console.log(JSON.stringify(out));
  assert.equal(out.norm_free_text, null, 'free text is not read for a trade: it needs reasoning');
  assert.ok(Array.isArray(out.norm_slug) && out.norm_slug.length > 0, 'a slug still resolves exactly');
  assert.equal(out.route_unreasoned, 'needs_reasoning');
  assert.ok(out.route_candidates > 0);
  assert.equal(out.route_cat, null, 'nothing is routed on the words');
  assert.equal(out.route_reasoned, 'route_or_ask_scope_details');
  assert.equal(out.route_reasoned_cat, true);
  assert.equal(out.route_bogus, 'ask_clarifying_question');
  assert.equal(out.kb_route_gone, true); assert.equal(out.decide_old_gone, true);
  assert.equal(out.match_src_ilike, false);
  assert.equal(out.product_status, 'needs_reasoning'); assert.equal(out.product_old_gone, true);
  assert.equal(out.group_marble, 'tiling'); assert.equal(out.group_free_text, null); assert.equal(out.group_src_regex, false);
  assert.equal(out.anon_can, false); assert.equal(out.service_can, true);
});
