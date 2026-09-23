// EVERY JUDGEMENT CARRIES ITS RECALL AND ITS OUTCOME — the learning loop's regression check.
//
// For scripts/sql/every_judgement_learns_from_its_outcome.sql, _shared/case_recall.ts, _shared/think.ts
// and _shared/learning_loop.ts (it_engineer, 23 Sep 2026). The founder's top priority: six seats that
// measurably improve. The loop needs every judgement recorded with what the seat remembered before it
// decided, and its real outcome laid on it afterwards.
//
// TWO HALVES.
//   1. OFFLINE. think() — the one engine every reasoning seat uses — recalls through the shared
//      recallCases, and recallCases opens the judgement row carrying its recall. No think() caller runs
//      another engine. The SQL has an outcome trigger on every table where an outcome lands, groups
//      lessons by vector distance with no word route, and the heartbeat runs both loop steps.
//   2. AGAINST PRODUCTION, in a transaction that always raises (nothing commits; if the file is not
//      applied yet it runs inside the same aborted transaction). The live ledger has 0 judgements without
//      a recall record — and the probe proves that count bites by writing one. A ZZ DEMO judgement gets
//      its outcome through the trigger path (an IT finding closed), a demo group of three cases is found
//      by meaning and its cross-family-verified lesson is approved and promoted, the daily metric has a
//      row per seat, and the CEO's weekly report carries the LEARNING section.
//
//   node --test scripts/checks/every_judgement_carries_its_recall_and_its_outcome.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const SQL_FILE = 'scripts/sql/every_judgement_learns_from_its_outcome.sql';
const OUTCOME_TABLES = ['quotes', 'inquiries', 'complaint_tickets', 'stripe_dispute', 'notifications', 'supplier_response_watch',
  'target_verdict', 'marketing_post_metric', 'expense_entries', 'it_engineer_finding'];

function walk(dir, out = []) {
  for (const f of readdirSync(dir)) {
    const p = join(dir, f);
    if (statSync(p).isDirectory()) walk(p, out); else if (p.endsWith('.ts') && !p.endsWith('.test.ts')) out.push(p);
  }
  return out;
}

test('think() recalls through the shared recall, which opens the judgement WITH its recall record', () => {
  const think = read('supabase/functions/_shared/think.ts');
  const body = think.slice(think.indexOf('export async function think('), think.indexOf('// ── the live dependencies'));
  const at = body.indexOf('await recallCases(deps');
  assert.ok(at > 0, 'think() no longer recalls through recallCases');
  assert.ok(at < body.indexOf("deps.llm('synthesise'"), 'think() recalls after it has decided');
  assert.doesNotMatch(body, /rpc\('fn_case_recall'/, 'think() grew a second recall that records no judgement');
  assert.match(body, /settle\('answered'/, 'an answered judgement is no longer closed with its decision');
  assert.match(body, /settle\('held'/, 'a held judgement is no longer closed');
  const recall = read('supabase/functions/_shared/case_recall.ts');
  assert.match(recall, /rpc\('fn_judgement_record',[\s\S]{0,300}p_recall: recallTrace\(m\)/, 'recallCases no longer records its recall');
});

test('no think() caller runs another engine, and every reasoning seat routes through think()', () => {
  const offenders = [];
  for (const f of walk(join(REPO, 'supabase', 'functions'))) {
    const src = readFileSync(f, 'utf8');
    if (/(^|[^.\w])think\(deps|await think\(/.test(src) && !/from '(\.\/|\.\.\/|\.\.\/_shared\/)think\.ts'/.test(src) && !f.endsWith('think.ts')) offenders.push(f);
  }
  assert.deepEqual(offenders, []);
});

test('an outcome trigger on every table where an outcome lands; lessons grouped by meaning, never words', () => {
  const sql = read(SQL_FILE);
  for (const t of OUTCOME_TABLES) {
    assert.match(sql, new RegExp(`create trigger z91_judgement_outcome [^;]* on public\\.${t} `), `no outcome trigger on ${t}`);
    assert.match(sql, new RegExp(`tg_table_name = '${t}'`), `no outcome mapping for ${t}`);
  }
  const clusters = sql.slice(sql.indexOf('create or replace function public.fn_lesson_clusters'), sql.indexOf('create or replace function public.fn_reason_apply_learning__distil'));
  assert.match(clusters, /embedding <=> seed\.embedding/, 'lessons are no longer grouped by vector distance');
  assert.doesNotMatch(clusters, /ilike|to_tsvector|tsquery|similarity\(|~\*/, 'lesson grouping grew a word route');
  assert.match(sql, /'approved' when v_ver = 'disagreed' then 'rejected'/, 'the cross-family verdict no longer decides the lesson');
  const ping = read('supabase/functions/resilience_ping/index.ts');
  for (const s of ['learningMeasure', 'learningDistil']) {
    assert.match(ping, new RegExp(`${s}: \\{ run:`), `resilience_ping does not run ${s}`);
    assert.match(sql, new RegExp(`\\('${s}'`), `no resilience_step row for ${s}`);
  }
  const loop = read('supabase/functions/_shared/learning_loop.ts');
  assert.match(loop, /stakes: 'high'/, 'a lesson is no longer verified by another family');
});

// ── against production ──────────────────────────────────────────────────────────────────────────────
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

test('production: no judgement without its recall; outcomes, lessons, the metric and the CEO section work',
  { skip: SKIP, timeout: 180_000 }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const live = (await sql(`select to_regclass('public.seat_judgement') is not null as ok`))[0].ok;
  const vec = "'[" + Array.from({ length: 384 }, (_, i) => (i % 7 === 0 ? 0.11 : 0.03)).join(',') + "]'::vector(384)";
  const probe = `
do $p$
declare v_live jsonb; v_rogue jsonb; v_j bigint; v_it jsonb; v_c bigint[] := '{}'; v_id bigint; v_clusters jsonb; v_key text;
        v_apply jsonb; v_ak int; v_days int; v_body text; i int;
begin
  v_live := public.fn_judgement_without_recall();
  insert into public.seat_judgement (seat, surface, question) values ('it_engineer', 'zz_demo_check', 'ZZ DEMO a judgement with no recall');
  v_rogue := public.fn_judgement_without_recall();
  begin
    perform public.fn_judgement_record('it_engineer', 'zz_demo_check', null, 'ZZ DEMO', null);
    raise exception 'CHK<<%>>', '{"error":"fn_judgement_record accepted a judgement with no recall"}';
  exception when sqlstate '22023' then null;
  end;
  -- The trigger path: a ZZ DEMO IT finding, judged with its recall, then closed with a fix.
  insert into public.it_engineer_finding (issue_key, title, where_it_is, blast, affected, evidence, ruled_out, undetermined, raised_by)
  values ('zz_demo_check:judgement', 'ZZ DEMO the outbox stopped draining', 'ZZ DEMO send_outbox', 'internal', 0, '{}'::jsonb, '{}', '{}', 'it_engineer');
  v_j := public.fn_judgement_record('it_engineer', 'triage', '{"issue_key":"zz_demo_check:judgement"}'::jsonb, 'ZZ DEMO outbox', '{"available":true,"cases":[]}'::jsonb);
  update public.it_engineer_finding set closed_at = now(), close_note = 'ZZ DEMO restarted the drain' where issue_key = 'zz_demo_check:judgement';
  select jsonb_build_object('outcome', outcome, 'correct', outcome_correct, 'finalised', finalised) into v_it from public.seat_judgement where id = v_j;
  -- Three ZZ DEMO marketing cases with outcomes, identical in meaning (one vector), form one group.
  for i in 1..3 loop
    v_id := public.fn_case_remember('marketing', 'zz_demo', 'zz_demo_check', 'lesson-' || i, null, 'ZZ DEMO a reel posted at 3am reached few people ' || i,
      'posted at 3am', null, 'engagement below median', true, '{}', now(), null);
    update public.seat_case_memory set embedding = ${vec} where id = v_id;
    v_c := v_c || v_id;
  end loop;
  v_clusters := public.fn_lesson_clusters(20);
  select c->>'cluster_key' into v_key from jsonb_array_elements(v_clusters) c
   where (select array_agg((x->>'case_id')::bigint order by (x->>'case_id')::bigint) from jsonb_array_elements(c->'cases') x) @> v_c limit 1;
  v_apply := public.fn_reason_apply_learning__distil(null, jsonb_build_object('status', 'answered',
    'answer', 'ZZ DEMO Posts at 3am reach few people; schedule reels for the evening.',
    'verified', jsonb_build_object('status', 'agreed', 'by', 'openai/gpt-sol-5.6'), 'subject', jsonb_build_object('cluster_key', v_key)));
  select count(*) into v_ak from public.agent_knowledge where source_ref = 'lesson:' || (v_apply->>'candidate_id');
  perform public.fn_seat_learning_measure();
  select count(*) into v_days from public.seat_learning_daily where day = (now() at time zone 'Asia/Dubai')::date;
  insert into public.ceo_weekly_report (iso_year, iso_week, week_start, week_end, report_key, body)
  values (2099, 1, date '2099-01-05', date '2099-01-11', 'zz_demo_check:learning', 'ZZ DEMO body') returning body into v_body;
  raise exception 'CHK<<%>>', jsonb_build_object('live', v_live, 'rogue', v_rogue, 'it', v_it, 'cluster', v_key,
    'apply', v_apply, 'agent_knowledge', v_ak, 'days', v_days, 'learning_section', v_body like '%THE SEATS, LEARNING%',
    'lessons_on_cases', (select count(*) from public.seat_case_memory where id = any(v_c) and cardinality(lessons) > 0))::text;
end $p$;`;
  let r;
  try { await sql((live ? '' : read(SQL_FILE) + '\n') + probe, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    if (!m) throw e;
    r = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(r, 'the probe committed instead of rolling back');
  assert.equal(r.error, undefined, r.error);
  assert.equal(r.live.without_recall, 0, `judgements without a recall record in production: ${JSON.stringify(r.live.ids)}`);
  assert.equal(r.rogue.without_recall, r.live.without_recall + 1, 'the recall probe does not bite');
  assert.deepEqual(r.it, { outcome: 'resolved: ZZ DEMO restarted the drain', correct: true, finalised: true });
  assert.ok(r.cluster, 'three cases identical in meaning were not grouped');
  assert.equal(r.apply.status, 'approved');
  assert.equal(r.agent_knowledge, 1, 'an approved lesson was not promoted into the seat\'s knowledge');
  assert.equal(r.lessons_on_cases, 3, 'the lesson did not reach the cases it came from');
  assert.equal(r.days, 6, 'the daily metric does not cover all six seats');
  assert.equal(r.learning_section, true, 'the CEO weekly report has no LEARNING section');
});
