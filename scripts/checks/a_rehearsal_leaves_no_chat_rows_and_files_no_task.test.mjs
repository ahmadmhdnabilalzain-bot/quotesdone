// A REHEARSAL LEAVES NO CHAT ROWS AND FILES NO TASK (27 Oct 2026, customer_support - owner of the conversation bank).
//
// MEASURED on PR #1635: one conversation-bank session (22 scenarios, ~270 portal turns as ZZ DEMO customers) left 273
// assistant_logs, 269 sales_decision_log and 273 support_reply_readability rows (demo = false) after its own teardown,
// and filed 97 sales_knowledge_gap rows with 97 org_tasks nobody confirmed. Separately, every customer:<id> chat row
// opens a support profile and case (z50_support_wire_widget): 76 ZZ DEMO profiles and 113 cases had accumulated.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: teardown loses a chat or support step; leftovers() stops counting a table; closeRun stops counting the
//     gaps a run filed; the bank stops failing on a leftover; the SQL loses a revoke or its pinned search_path; the
//     file carries both (or neither of) a pending note and a MANIFEST line;
//   * production, in ONE aborted transaction (the file replayed first while pending; nothing commits): under a probe
//     rehearsal tag fn_sales_assist and fn_support_knowledge_gap file no gap and no org_task, and the decision,
//     readability and assistant_logs rows carry the tag (readability demo = true); with the tag cleared, the same
//     kind of question files its gap and task and the rows carry no tag. The probe's question avoids "ZZ DEMO", so
//     it is the routine's own rehearsal branch that is measured, not the older demo-task trigger.
//
//   node --test scripts/checks/a_rehearsal_leaves_no_chat_rows_and_files_no_task.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/a_rehearsal_files_no_knowledge_gap_and_its_chat_rows_carry_its_run_tag.sql';
const pending = () => existsSync(join(REPO, 'scripts/sql/pending', FILE.split('/').pop().replace(/\.sql$/, '.txt')));

test('static: teardown removes every chat side effect, leftovers counts it, the bank fails on it', () => {
  const td = read('scripts/lib/demo_factory.mjs');
  assert.match(td, /\['assistant_logs \(audience\)', `delete from public\.assistant_logs where audience in \(select 'customer:' \|\| id::text from public\.customers where id in \$\{CUST\}/,
    'teardown no longer removes the chat rows of the run\'s customers');
  assert.match(td, /\.\.\.\['assistant_logs', 'sales_decision_log', 'support_reply_readability'\]\.map\(\(t\) => \[`\$\{t\} \(run tag\)`,\s*`delete from public\.\$\{t\} where e2e_run_tag = '\$\{tag\}'`\]\)/,
    'teardown no longer removes the run-tagged chat rows');
  for (const t of ['feedback (support)', 'support_document_intake', 'support_notification', 'support_case', 'support_customer_profile'])
    assert.ok(td.includes(`['${t}', `), `teardown lost its ${t} step`);
  assert.match(td, /support_customer_profile where email like 'qd-\$\{tag\}-%@example\.%' or customer_id in \$\{CUST\} or lead_id in \$\{LEAD\}/,
    'support rows are no longer scoped to the run\'s own email and ids');

  const fx = read('scripts/e2e/fixtures.mjs');
  for (const k of ['assistant_logs', 'support_customer_profile', 'support_case'])
    assert.match(fx, new RegExp(`\\)::int ${k}[,\`]`), `leftovers() no longer counts ${k}`);
  assert.match(fx, /const byTag = \['assistant_logs', 'sales_decision_log', 'support_reply_readability'\]\.filter/, 'leftovers() no longer counts the run-tagged chat rows');
  assert.match(fx, /r\[k\] = tagged\.has\(x\) \? Number\(n\[x\]\) : 'not applied';/, 'an unmeasured tag count must say so, never read 0');
  assert.match(fx, /filed = await gapsFiled\(run\)/, 'closeRun no longer counts the gaps a run filed before its teardown');
  assert.match(fx, /left\.total \+= filed\.gaps \+ filed\.tasks;/, 'a filed gap or task no longer fails the run');
  assert.match(fx, /from public\.support_customer_profile where email like 'qd-%@example\.invalid'\)/, 'the stale-run sweep no longer finds runs that left only support profiles');

  const bank = read('scripts/e2e/live_seat_conversations.mjs');
  assert.match(bank, /if \(closed\.leftovers\?\.total \|\| closed\.leftovers\?\.knowledge_gaps_filed_error\) process\.exitCode = 1;/,
    'the bank no longer fails when its teardown leaves a row');

  const sql = read(FILE);
  for (const fn of ['fn_e2e_rehearsal_tag', 'fn_chat_row_e2e_run_tag']) {
    assert.match(sql, new RegExp(`create or replace function public\\.${fn}\\(\\)\\s+returns \\w+ language plpgsql (stable )?security definer\\s+set search_path to 'public', 'pg_temp'`), `${fn} lost its pinned search_path`);
    assert.match(sql, new RegExp(`revoke execute on function public\\.${fn}\\(\\) from public, anon, authenticated;`), `${fn} lost its revoke`);
  }
  for (const t of ['assistant_logs', 'sales_decision_log', 'support_reply_readability'])
    assert.match(sql, new RegExp(`create trigger a00_chat_row_e2e_run_tag before insert on public\\.${t}\\b`), `${t} is no longer stamped`);
  assert.equal((sql.match(/if v_rehearsal is not null then/g) || []).length, 2, 'a gap routine lost its rehearsal branch');
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim());
  assert.ok(pending() !== manifest.includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: a rehearsal files no gap or task and its chat rows carry its tag', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { replaySql: sql } = await import('../lib/safe_replay.mjs');   // the one door: cannot commit
  const replay = pending() ? read(FILE) + '\n' : '';
  let o;
  try {
    await sql(replay + `
do $$
declare
  tag text := 'chk' || substr(md5(clock_timestamp()::text), 1, 8);
  q1 text; q2 text; q3 text; r1 jsonb; r2 jsonb; r3 jsonb;
  tasks0 int; gaps0 int; out jsonb := '{}'::jsonb;
begin
  -- Nonsense no corpus answers, and no "ZZ DEMO" in it, so the older demo-task trigger is not what stops a task.
  q1 := 'qdprobe portal xyzzy plugh frobnicate ' || tag;
  q2 := 'qdprobe widget xyzzy plugh frobnicate ' || tag;
  q3 := 'qdprobe control xyzzy plugh frobnicate ' || tag;
  insert into public.rehearsal_window (run_tag, opened_by, note, models_allowed, cap_usd, expires_at)
  values ('qd_run:' || tag, 'scripts/checks/a_rehearsal_leaves_no_chat_rows_and_files_no_task', 'aborted probe', false, 1, now() + interval '10 minutes');
  select count(*) into tasks0 from public.org_tasks;
  select count(*) into gaps0 from public.sales_knowledge_gap;

  perform set_config('app.e2e_run_tag', tag, true);
  r1 := public.fn_sales_assist(q1, null);
  r2 := public.fn_support_knowledge_gap(q2, 'probe', 'website_widget');
  perform public.fn_support_reply_readability_log('portal', 'en', 'reasoned', false, 80, 80, '{}', 'probe rehearsal ' || tag, false);
  insert into public.assistant_logs (message, reply, seat, answered, audience, path) values ('probe rehearsal ' || tag, 'r', 'sales_engineer', true, 'probe', 'portal');
  out := out || jsonb_build_object(
    'portal_rehearsal', r1->>'rehearsal' = tag, 'portal_gap_recorded', (r1->>'gap_recorded')::boolean, 'portal_task', r1->'task_id',
    'widget_rehearsal', r2->>'rehearsal' = tag, 'widget_task', r2->'task_id',
    'tasks_added', (select count(*) from public.org_tasks) - tasks0, 'gaps_added', (select count(*) from public.sales_knowledge_gap) - gaps0,
    'decision_tagged', (select count(*) from public.sales_decision_log where query = q1 and e2e_run_tag = tag),
    'readability_tagged_demo', (select count(*) from public.support_reply_readability where reason = 'probe rehearsal ' || tag and e2e_run_tag = tag and demo),
    'assistant_log_tagged', (select count(*) from public.assistant_logs where message = 'probe rehearsal ' || tag and e2e_run_tag = tag));

  perform set_config('app.e2e_run_tag', '', true);
  r3 := public.fn_sales_assist(q3, null);
  perform public.fn_support_reply_readability_log('portal', 'en', 'reasoned', false, 80, 80, '{}', 'probe control ' || tag, false);
  out := out || jsonb_build_object(
    'control_gap_recorded', (r3->>'gap_recorded')::boolean, 'control_has_task', r3->'task_id' <> 'null'::jsonb,
    'control_tasks_added', (select count(*) from public.org_tasks) - tasks0,
    'control_decision_untagged', (select count(*) from public.sales_decision_log where query = q3 and e2e_run_tag is null),
    'control_readability_untagged', (select count(*) from public.support_reply_readability where reason = 'probe control ' || tag and e2e_run_tag is null and not demo));
  raise exception 'CHK<<%>>', out::text;
end $$;`, { retry: false });
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  assert.deepEqual(o, {
    portal_rehearsal: true, portal_gap_recorded: false, portal_task: null, widget_rehearsal: true, widget_task: null,
    tasks_added: 0, gaps_added: 0, decision_tagged: 1, readability_tagged_demo: 1, assistant_log_tagged: 1,
    control_gap_recorded: true, control_has_task: true, control_tasks_added: 1, control_decision_untagged: 1, control_readability_untagged: 1,
  });
});
