// Drive the org_task lane through its REAL doors until every open task has a run or a reason.
//   cron 262 (fn_kernel_cron_exec -> fn_org_task_assign -> fn_org_task_promote) and
//   cron 255's own body (net.http_post to workflow_dispatch with cred_cron_agents), fanned out.
//   node scripts/phase_c/drive_org_task_lane.mjs [cycles] [posts_per_cycle] [limit_per_post]
import { sql } from './lib/db.mjs';

const CYCLES = Number(process.argv[2]) || 30;
const POSTS = Number(process.argv[3]) || 4;
const LIMIT = Number(process.argv[4]) || 10;
const SLEEP_MS = (Number(process.argv[5]) || 95) * 1000;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const census = () => sql(`
  select (select count(*) from org_tasks where status in ('assigned','in_progress')) open_assigned,
         (select count(*) from org_tasks t where t.status in ('assigned','in_progress')
             and not exists (select 1 from workflow_run r where r.workflow_key='employee_task' and r.context->>'task_id'=t.id::text and r.status='running')) without_run,
         (select count(*) from org_tasks t where t.status in ('assigned','in_progress') and t.assigned_agent is null) unowned,
         (select count(*) from workflow_step_run sr join workflow_run r on r.id=sr.workflow_run_id
           where r.workflow_key='employee_task' and r.status='running' and sr.status='ready') ready_steps,
         (select count(*) from org_tasks where status='blocked') blocked,
         (select count(*) from org_tasks where status='escalated') escalated,
         (select count(*) from org_tasks where status='proposed') proposed,
         (select count(*) from org_tasks where status='done') done`);

for (let i = 1; i <= CYCLES; i++) {
  const t0 = Date.now();
  await sql(`select public.fn_kernel_cron_exec(262)`);
  const [assign] = await sql(`select counts from agent_runs where agent='org_task_assign' order by started_at desc limit 1`);
  const posts = [];
  for (let k = 0; k < POSTS; k++) {
    posts.push(`select net.http_post(
      url := 'https://' || (select value from app_secrets where key = 'project_ref') || '.supabase.co/functions/v1/workflow_dispatch',
      headers := '{"Content-Type":"application/json"}'::jsonb,
      body := jsonb_build_object('__secret', (select value from app_secrets where key = 'cred_cron_agents'), 'limit', ${LIMIT}),
      timeout_milliseconds := 150000) as req`);
  }
  await sql(posts.join(' union all '));
  await sleep(SLEEP_MS);
  const [c] = await census();
  const p = assign?.counts?.promoted_to_spine ?? {};
  console.log(`[${new Date().toISOString()}] cycle ${i}: assigned ${assign?.counts?.assigned} released ${assign?.counts?.released_from_unreviewable_head} promoted ${p.promoted} reopened cos ${p.reopened_from_retired_executor} head ${p.reopened_head_authored} held ${p.held_proposals_annotated} | open ${c.open_assigned} without_run ${c.without_run} unowned ${c.unowned} ready ${c.ready_steps} blocked ${c.blocked} escalated ${c.escalated} proposed ${c.proposed} done ${c.done} (${Math.round((Date.now() - t0) / 1000)}s)`);
  if (Number(c.without_run) === 0 && Number(c.ready_steps) === 0) { console.log('drained'); break; }
}
