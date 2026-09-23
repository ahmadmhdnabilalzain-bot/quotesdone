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
  .filter((f) => f.startsWith('scripts/sql/') && f.endsWith('.sql') && ![ENGINE, MIGRATE, DISPATCH].includes(f)))];
const CHAIN = [ENGINE, MIGRATE, DISPATCH, ...BATCH_SQL];

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
 *  replays inside its aborted transaction so it measures the committed code, not only what production has. */
const pendingReplay = () => CHAIN.filter((f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt'))))
  .map((f) => read(f)).join('\n') + '\n';
/** Runs a DO block that ends in raise exception 'CHK<<json>>' after the pending chain; returns the json. Nothing commits. */
async function probe(block, prefix = '') {
  const { sql } = await import('../lib/db.mjs');
  try { await sql(prefix + pendingReplay() + block, { retry: false }); }
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
  o := o || jsonb_build_object('channel_expires_days', (select round(extract(epoch from expires_at - now()) / 86400) from public.reasoning_held_question where id = v_id));
  perform public.fn_reason_held_resolve(v_id, '{"status":"answered","answer":"ZZ","decision":{"choice":"needs_a_person"}}'::jsonb);
  perform public.fn_reason_held_delivered(v_id, '{"delivered":true,"via":"whatsapp_template"}'::jsonb);
  o := o || jsonb_build_object('delivered_row', (select status || ':' || (result->'delivery'->>'via') from public.reasoning_held_question where id = v_id));
  update public.reasoning_held_question set status = 'held', expires_at = now() - interval '1 minute' where id = v_id;
  perform public.fn_reason_held_due(1);
  o := o || jsonb_build_object('expired_status', (select status from public.reasoning_held_question where id = v_id));

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
  const body = before + pendingReplay() + PROBE;
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
  assert.equal(out.channel_expires_days, 7);
  assert.equal(out.delivered_row, 'applied:whatsapp_template');
  assert.equal(out.expired_status, 'expired', 'an expired channel question is closed, not replayed');
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

// ── batch B2 (menus, comments, trades): the replay writes the reasoned trade on the row it was held for ─────────────
test('production, aborted: a held create_inquiry trade reopens its intake and a held lead sector is set — exact slug or nothing, held/empty rows only',
  { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const out = await probe(String.raw`
do $p$
declare o jsonb := '{}'::jsonb; v_slug text; v_in uuid; v_in2 uuid; v_lead bigint; v_lead2 bigint; v_id bigint;
begin
  select category into v_slug from public.category_specs order by category limit 1;
  insert into public.inquiry_intake (email, status, turns, raw_input) values ('zz-b2-probe@example.invalid', 'held', '[]'::jsonb, 'ZZ DEMO aluminium windows')
    returning id into v_in;
  insert into public.inquiry_intake (email, status, turns, raw_input) values ('zz-b2-probe2@example.invalid', 'held', '[]'::jsonb, 'ZZ DEMO bake a cake')
    returning id into v_in2;
  -- the reasoned trade reopens a held intake, ready to post
  v_id := public.fn_reason_hold('sales_engineer', 'customer_api.keywords', 'ZZ DEMO', '{"seat":"sales_engineer"}'::jsonb, '{}'::jsonb,
            jsonb_build_object('intake_id', v_in::text), 'model_hold', 'zz-b2-kw-1');
  o := o || jsonb_build_object('kw_resolve', public.fn_reason_held_resolve(v_id, jsonb_build_object('status', 'answered', 'answer', 'ZZ', 'decision', jsonb_build_object('choice', v_slug))));
  o := o || jsonb_build_object('kw_row', (select status || ':' || (category = v_slug) from public.inquiry_intake where id = v_in));
  -- an intake no longer held is never touched
  v_id := public.fn_reason_hold('sales_engineer', 'customer_api.keywords', 'ZZ DEMO', '{"seat":"sales_engineer"}'::jsonb, '{}'::jsonb,
            jsonb_build_object('intake_id', v_in::text), 'model_hold', 'zz-b2-kw-2');
  o := o || jsonb_build_object('kw_again', public.fn_reason_held_resolve(v_id, '{"status":"answered","answer":"ZZ","decision":{"choice":"none"}}'::jsonb)->'effect'->'reopened');
  -- 'none' (no nearest mapping): back to the questions, as general
  v_id := public.fn_reason_hold('sales_engineer', 'customer_api.keywords', 'ZZ DEMO', '{"seat":"sales_engineer"}'::jsonb, '{}'::jsonb,
            jsonb_build_object('intake_id', v_in2::text), 'model_hold', 'zz-b2-kw-3');
  perform public.fn_reason_held_resolve(v_id, '{"status":"answered","answer":"ZZ","decision":{"choice":"none"}}'::jsonb);
  o := o || jsonb_build_object('kw_none', (select status || ':' || category from public.inquiry_intake where id = v_in2));

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
            where p.proname in ('fn_reason_apply_customer_api__keywords', 'fn_reason_apply_inbound_email__infer_sector')),
    'anon_can', (select bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
            from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('fn_reason_apply_customer_api__keywords', 'fn_reason_apply_inbound_email__infer_sector')),
    'service_can', has_function_privilege('service_role', 'public.fn_reason_apply_inbound_email__infer_sector(bigint,jsonb)', 'execute'));
  raise exception 'CHK<<%>>', o::text;
end $p$;`);
  console.log(JSON.stringify(out));
  assert.equal(out.kw_resolve.status, 'applied');
  assert.equal(out.kw_resolve.effect.reopened, true);
  assert.equal(out.kw_row, 'ready:true', 'the held intake reopens ready, with the reasoned trade');
  assert.equal(out.kw_again, false, 'an intake no longer held is never touched');
  assert.equal(out.kw_none, 'needs_info:general', "'none' goes back to the questions — no nearest mapping");
  assert.equal(out.sector_status, 'applied');
  assert.equal(out.sector_row, true);
  assert.equal(out.sector_kept, 'zz-set-by-a-person', 'a sector already set is never overwritten');
  assert.equal(out.sector_none, null, "'none' writes no sector");
  assert.equal(out.reads_text, false);
  assert.equal(out.anon_can, false);
  assert.equal(out.service_can, true);
});
