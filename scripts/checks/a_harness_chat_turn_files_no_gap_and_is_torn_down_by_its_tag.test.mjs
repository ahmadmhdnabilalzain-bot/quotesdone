// A harness chat turn files no knowledge gap and no task, and teardown removes it by its run tag (it_engineer, 27 Oct 2026).
//
// One sandbox run left 273 assistant_logs, 269 sales_decision_log, 273 support_reply_readability, 97 sales_knowledge_gap
// and the 97 org_tasks those gaps opened, after its teardown reported clean; existing gaps had their ask counters bumped.
// Fails if any part of the fix is undone:
//   - the SQL file stops stamping the three tables with the function that stamps ai_cost_log, or builds a guard of its own;
//   - fn_sales_assist or fn_support_knowledge_gap can reach a gap insert, a counter bump or a task insert/raise for test
//     traffic (a run tag, or a ZZ DEMO question);
//   - teardown stops deleting the run's chat turns, or stage2 --verify-clean stops counting them;
// Offline over the committed tree, plus (with a management token) a REPLAY: the file and teardown's own statements run
// inside one aborted transaction against seeded ZZ DEMO rows; nothing can commit (the block always raises).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const NAME = 'a_harness_chat_turn_carries_its_run_tag_and_files_no_gap_or_task';
const FILE = `scripts/sql/${NAME}.sql`;
const SQL = read(FILE);
const body = (name) => {
  const i = SQL.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  assert.ok(i >= 0, `${name} is defined in ${FILE}`);
  return SQL.slice(i, SQL.indexOf('$function$;', i));
};
const code = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');   // comments may quote what they forbid

test('the file is either applied (MANIFEST) or pending (its note), and its probe is kept', () => {
  const manifest = read('scripts/sql/MANIFEST.txt').split('\n').map((l) => l.trim());
  const note = existsSync(join(REPO, `scripts/sql/pending/${NAME}.txt`));
  assert.ok(manifest.includes(FILE) !== note, 'exactly one of: a MANIFEST line, a pending note');
  const probe = read(`scripts/sql/${NAME}_probe.sql`);
  assert.match(probe, /raise exception 'CHK<<%>>'/, 'the probe always raises, so it never commits');
  assert.ok(existsSync(join(REPO, `scripts/sql/pending/${NAME}_probe.txt`)), 'the probe carries its never-applied note');
});

test('the three chat-turn tables are stamped by the function that stamps ai_cost_log; no new guard is built', () => {
  for (const t of ['assistant_logs', 'sales_decision_log', 'support_reply_readability']) {
    assert.match(SQL, new RegExp(`alter table public\\.${t}\\s+add column if not exists e2e_run_tag text;`), `${t} gains e2e_run_tag`);
    assert.match(SQL, new RegExp(`create or replace trigger a00_${t}_e2e_run_tag before insert on public\\.${t}\\s+for each row execute function public\\.fn_ai_cost_log_e2e_run_tag\\(\\);`),
      `${t} is stamped by fn_ai_cost_log_e2e_run_tag`);
  }
  const defined = [...SQL.matchAll(/create\s+(?:or\s+replace\s+)?function\s+public\.([a-z0-9_]+)\(/gi)].map((m) => m[1]).sort();
  assert.deepEqual(defined, ['fn_sales_assist', 'fn_support_knowledge_gap'], 'only the two filing routines are (re)defined');
});

test('fn_sales_assist: test traffic reaches no gap, no counter and no task', () => {
  const b = code(body('fn_sales_assist'));
  assert.match(b, /v_test\s+boolean := public\.fn_e2e_run_tag_current\(\) is not null or public\.fn_seat_work_is_demo\(p_text, null\);/);
  const branch = b.indexOf('if v_test then'), other = b.indexOf('else', branch);
  assert.ok(branch > 0 && other > branch, 'the test branch exists');
  for (const w of ['select * into v_gap from sales_knowledge_gap', 'insert into org_tasks', 'insert into sales_knowledge_gap',
    'update sales_knowledge_gap', 'update org_tasks']) {
    const at = b.indexOf(w);
    assert.ok(at > other, `"${w}" is only reached on the else of if v_test`);
    assert.equal(b.indexOf(w, at + 1), -1, `"${w}" appears once`);
  }
  assert.match(b, /'gap_recorded', cardinality\(v_cited\) = 0 and not v_test,/);
  assert.match(b, /'test_traffic', v_test,/);
});

test('fn_support_knowledge_gap: test traffic reaches no gap, no counter and no task', () => {
  const b = code(body('fn_support_knowledge_gap'));
  assert.match(b, /v_test boolean := public\.fn_e2e_run_tag_current\(\) is not null or public\.fn_seat_work_is_demo\(p_question, null\);/);
  const open = b.indexOf('if not v_test then'), ret = b.lastIndexOf('return jsonb_build_object(');
  assert.ok(open > 0 && ret > open, 'the guard opens before the filing and the return follows it');
  const close = b.lastIndexOf('end if;', ret);
  for (const w of ['insert into public.org_tasks', 'insert into public.sales_knowledge_gap', 'update public.sales_knowledge_gap', 'update public.org_tasks']) {
    const at = b.indexOf(w);
    assert.ok(at > open && at < close, `"${w}" is inside if not v_test`);
  }
  assert.match(b, /'test_traffic', v_test,/);
});

test('teardown deletes the run\'s chat turns, gap and gap task; stage2 --verify-clean counts them', async () => {
  const { chatTurnSql, CHAT_TURN_TABLES } = await import('../lib/demo_factory.mjs');
  assert.deepEqual(CHAT_TURN_TABLES, ['assistant_logs', 'sales_decision_log', 'support_reply_readability']);
  const on = chatTurnSql('tagx1234', new Set(CHAT_TURN_TABLES), [['org_task_child', 'task_id']]);
  const labels = on.steps.map(([l]) => l);
  const order = ['sales_knowledge_gap (run)', 'org_task_child (fk task_id -> org_tasks, run gap task)', 'decision_trace (run gap task)',
    'org_tasks (run gap task)', 'undo_log (run gap task)', 'assistant_logs (run chat turns)', 'sales_decision_log (run chat turns)',
    'support_reply_readability (run chat turns)'];
  assert.deepEqual(labels, order, 'children before parents, the turns that name a task last');
  for (const t of CHAT_TURN_TABLES) assert.match(on.steps.find(([l]) => l.startsWith(t))[1], /x\.e2e_run_tag = 'tagx1234'/, `${t} is deleted by its tag`);
  assert.match(on.steps.find(([l]) => l.startsWith('assistant_logs'))[1], /'customer:' \|\| id::text[\s\S]*'a-c-' \|\| id::text/, 'and by the run\'s own parties');
  const gap = on.steps[0][1];
  assert.match(gap, /first_asked_at >= \(select min\(w\.started_at\) from public\.rehearsal_window w where w\.run_tag = 'qd_run:tagx1234'\)/);
  assert.match(gap, /x\.asks <= \(select count\(\*\)/, 'a gap a person also asked is never removed');
  assert.match(on.steps.find(([l]) => l.startsWith('org_tasks'))[1], /action_class = 'knowledge_gap'/);
  for (const k of ['assistant_logs', 'sales_decision_log', 'support_reply_readability', 'sales_knowledge_gap', 'org_tasks'])
    assert.match(on.count, new RegExp(`::int ${k}\\b`), `the count reports ${k}`);
  const off = chatTurnSql('tagx1234', new Set());
  assert.doesNotMatch(off.steps.map(([, s]) => s).join('\n'), /e2e_run_tag/, 'before the column exists, no statement names it');

  const df = code(read('scripts/lib/demo_factory.mjs'));
  const td = df.slice(df.indexOf('export async function teardown('));
  const at = td.indexOf('...(await chatTurnSteps(tag))');
  assert.ok(at > 0 && at < td.indexOf("['leads',") && at < td.indexOf("['customers',"), 'teardown runs them while the run\'s customers and leads exist');
  const s2 = code(read('scripts/e2e/stage2.mjs'));
  const vc = s2.slice(s2.indexOf('async function verifyClean('), s2.indexOf('async function preconditions('));
  assert.match(vc, /chat_turns = await chatTurnCounts\(tag\)/);
  assert.match(vc, /chatLeft === 0/, 'a chat-turn leftover makes the run not clean');
  assert.match(vc, /unverified\.push\(\{ table: 'chat turns'/, 'an unreadable count is unverified, never clean');
});

// ---- the replay ------------------------------------------------------------------------------------------------
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('REPLAY: tagged turns file nothing, and teardown\'s own statements leave 0 of a run and every control', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  // The replay carries scripts/sql text (SQL, before merge), so it is sent through safe_replay, which refuses a
  // statement that could commit and proves by fingerprint that nothing it creates survived the rollback
  // (every_sql_replay_goes_through_safe_replay). sql() is kept for the read above, which sends no file text.
  const { replaySql } = await import('../lib/safe_replay.mjs');
  const { chatTurnSql, countedDelete, CHAT_TURN_TABLES } = await import('../lib/demo_factory.mjs');
  const live = (await sql(`select count(*)::int n from information_schema.columns where table_schema = 'public'
      and column_name = 'e2e_run_tag' and table_name in ('assistant_logs', 'sales_decision_log', 'support_reply_readability')`))[0].n;
  // Before merge the file rides in the same aborted transaction (its ALTERs wait at most 3 s for a lock); after, it is live.
  const prefix = "select set_config('lock_timeout', '3s', true), set_config('statement_timeout', '90s', true);\n" + (live === 3 ? '' : SQL + '\n');
  const { steps, count } = chatTurnSql('zzreplay', new Set(CHAT_TURN_TABLES));
  const run = steps.map(([label, s], i) => `  execute $s${i}$${countedDelete(s)}$s${i}$ into v_n; v_out := v_out || jsonb_build_object(${`'${label.replace(/'/g, "''")}'`}, v_n);`).join('\n');
  const block = `do $replay$
declare v jsonb; v_out jsonb := '{}'; v_n int; v_c uuid := gen_random_uuid(); v_task bigint; v_shared bigint; v_ctrl bigint; v_left jsonb;
        v_t0 bigint; v_gaps0 int;
begin
  insert into public.rehearsal_window (run_tag, opened_by, note) values ('qd_run:zzreplay', 'scripts/checks (replay)', 'ZZ DEMO replay');
  insert into public.customers (id, email, full_name) values (v_c, 'qd-zzreplay-c1@example.invalid', 'ZZ DEMO replay customer');
  select coalesce(max(id), 0) into v_t0 from public.org_tasks;

  -- TAGGED: the turns of a run as the edge functions write them. They must file nothing.
  perform set_config('app.e2e_run_tag', 'zzreplay', true);
  select count(*) into v_gaps0 from public.sales_knowledge_gap;
  insert into public.assistant_logs (message, reply, seat, answered, audience, path) values ('zzreplay visitor qlorvent', 'reply', 'customer_support', true, 'visitor', 'zz_replay');
  perform public.fn_support_reply_readability_log('widget', 'en', 'reasoned', false, 90, 90, '{}'::text[], 'ZZ DEMO replay zzreplay', true);
  perform public.fn_sales_assist('zzreplay drimbalux quenterfold', null::vector);
  perform public.fn_support_knowledge_gap('zzreplay vremlotic sandquorbel', 'replay', 'zz_replay');
  v_out := v_out || jsonb_build_object('tagged_gaps_filed', (select count(*) from public.sales_knowledge_gap) - v_gaps0,
                                       'tagged_tasks_opened', (select count(*) from public.org_tasks where id > v_t0));

  -- UNTAGGED but the run's own customer (a turn the tag could not reach): its gap and task are the run's.
  perform set_config('app.e2e_run_tag', '', true);
  v := public.fn_support_knowledge_gap('zzreplay mabbistrode plinquet', 'replay', 'zz_replay');
  v_task := (v->>'task_id')::bigint;
  insert into public.assistant_logs (message, seat, answered, audience, path, gap_task_id, conv_id)
  values ('zzreplay mabbistrode plinquet', 'sales_engineer', false, 'customer:' || v_c, 'portal', v_task, 'a-c-' || v_c);
  update public.org_tasks set priority = priority where id = v_task;   -- an undo row, as a real bump writes

  -- CONTROLS that are not the run: a visitor turn, and a gap a person asked twice that one run turn also names.
  insert into public.assistant_logs (message, seat, answered, audience, path) values ('zzreplay control turn', 'customer_support', true, 'visitor', 'zz_replay')
  returning id into v_ctrl;
  perform public.fn_support_knowledge_gap('zzreplay shared question plimbovar', 'replay', 'zz_replay');
  v := public.fn_support_knowledge_gap('zzreplay shared question plimbovar', 'replay', 'zz_replay');
  v_shared := (v->>'task_id')::bigint;
  insert into public.assistant_logs (message, seat, answered, audience, path, gap_task_id)
  values ('zzreplay shared question plimbovar', 'sales_engineer', false, 'customer:' || v_c, 'portal', v_shared);

  -- TEARDOWN'S OWN STATEMENTS, as teardown() runs them.
${run}
  select to_jsonb(c) into v_left from (${count}) c;
  raise exception 'CHK<<%>>CHK', jsonb_build_object('removed', v_out, 'left', v_left,
    'run_task_gone', not exists (select 1 from public.org_tasks where id = v_task),
    'run_task_undo_left', (select count(*) from public.undo_log where table_name = 'org_tasks' and row_id = v_task::text),
    'control_turn_kept', exists (select 1 from public.assistant_logs where id = v_ctrl),
    'shared_gap_kept', exists (select 1 from public.sales_knowledge_gap where task_id = v_shared),
    'shared_task_kept', exists (select 1 from public.org_tasks where id = v_shared));
end $replay$;`;
  let out = null;
  try { await replaySql(prefix + block, { label: 'the chat-turn teardown replay', retry: false }); } catch (e) {
    let msg = String(e?.message || e);
    const brace = msg.indexOf('{');
    if (brace >= 0) { try { msg = JSON.parse(msg.slice(brace))?.message ?? msg; } catch { /* not an HTTP body */ } }
    const m = /CHK<<([\s\S]*)>>CHK/.exec(msg);
    if (!m) throw new Error('the replay did not report: ' + msg.slice(0, 600));
    out = JSON.parse(m[1]);
  }
  assert.ok(out, 'the replay committed instead of rolling back');
  console.log('replay (rolled back): ' + JSON.stringify(out));
  assert.equal(out.removed.tagged_gaps_filed, 0, 'a tagged turn filed a gap');
  assert.equal(out.removed.tagged_tasks_opened, 0, 'a tagged turn opened a task');
  for (const [k, v] of Object.entries(out.left)) assert.equal(v, 0, `${k}: ${v} of the run left after teardown (${JSON.stringify(out.removed)})`);
  assert.equal(out.run_task_gone, true, 'the run\'s gap task survived');
  assert.equal(out.run_task_undo_left, 0, 'the run\'s gap task left undo rows');
  assert.equal(out.control_turn_kept, true, 'teardown removed a turn that is not the run\'s');
  assert.equal(out.shared_gap_kept, true, 'teardown removed a gap a person also asked');
  assert.equal(out.shared_task_kept, true, 'teardown removed the task of a gap a person also asked');
  assert.ok(out.removed['assistant_logs (run chat turns)'] >= 3 && out.removed['sales_decision_log (run chat turns)'] >= 1
    && out.removed['support_reply_readability (run chat turns)'] >= 1, `teardown removed the run's rows: ${JSON.stringify(out.removed)}`);
});
