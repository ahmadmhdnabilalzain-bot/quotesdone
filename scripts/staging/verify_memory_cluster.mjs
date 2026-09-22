// Fixture gate for spec file #2, components 11-13 (the memory cluster).
//
// Everything this proves is BEHAVIOUR AT CALL TIME, against real rows, on STAGING. A DO block that
// merely rewrites pg_get_functiondef reports success for a body that raises the moment it is
// invoked — that has already cost this project three bugs. So each assertion here executes the
// thing and reads the effect back.
//
// The whole fixture runs inside one DO block that ends by RAISING, so every row it created is
// rolled back and staging is left as it was. The findings travel out in the exception message,
// which is the only channel a deliberately-aborted transaction has.
//
//   node scripts/staging/verify_memory_cluster.mjs
import { mgmtWrite } from '../lib/qd_guard.mjs';
import { REF as STAGE } from '../lib/demo_factory.mjs';

const SQL = `
do $fixture$
declare
  v_out text := '';
  v_task bigint;
  v_dept text; v_lead text; v_peer text;
  v_r jsonb;
  v_n int;
  v_ok boolean;
  v_err text;
  v_rc text;
begin
  -- 1. A KPI-miss task with no cause on record anywhere cannot close.
  insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
  values ('exec', 'KPI missed: fixture metric (fixture)', 'fixture', 'proposed', 'advisory', false, 'recommend')
  returning id into v_task;

  v_ok := false; v_err := '';
  begin
    update org_tasks set status = 'done' where id = v_task;
  exception when others then v_ok := true; v_err := left(sqlerrm, 70);
  end;
  v_out := v_out || case when v_ok then 'PASS' else 'FAIL' end
        || ' guard refuses a KPI-miss close with no root cause anywhere [' || v_err || ']' || chr(10);

  -- 2. The same close succeeds once the deliverable states a cause, and the cause is CAPTURED into
  --    the column rather than being demanded a second time.
  update org_tasks
     set result = jsonb_build_object('deliverable',
           '# Diagnosis' || chr(10) || 'Root cause: the measure has no source rows yet.' || chr(10) || 'Next steps.'),
         status = 'done'
   where id = v_task;
  select root_cause into v_rc from org_tasks where id = v_task;
  v_out := v_out || case when v_rc ~* 'no source rows yet' then 'PASS' else 'FAIL' end
        || ' guard captures the root cause the deliverable already states [' || coalesce(left(v_rc, 60), 'null') || ']' || chr(10);

  -- 3. A task that is not a KPI miss is untouched by the guard.
  insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
  values ('exec', 'Fixture ordinary task', 'fixture', 'proposed', 'advisory', false, 'recommend')
  returning id into v_task;
  v_ok := true; v_err := '';
  begin
    update org_tasks set status = 'done' where id = v_task;
  exception when others then v_ok := false; v_err := left(sqlerrm, 70);
  end;
  v_out := v_out || case when v_ok then 'PASS' else 'FAIL' end
        || ' guard leaves non-KPI tasks alone [' || v_err || ']' || chr(10);

  -- 4. horizon is constrained to the two values the blueprint distinguishes, and defaults to short.
  v_ok := false;
  begin
    insert into agent_memory (agent_key, kind, content, importance, horizon)
    values ('fixture_agent', 'learned', repeat('x', 130), 5, 'medium');
  exception when others then v_ok := true;
  end;
  v_out := v_out || case when v_ok then 'PASS' else 'FAIL' end
        || ' agent_memory.horizon rejects a third vocabulary' || chr(10);

  insert into agent_memory (agent_key, kind, content, importance)
  values ('fixture_agent', 'learned', repeat('x', 130), 5);
  v_out := v_out || case when (select horizon from agent_memory where agent_key = 'fixture_agent' limit 1) = 'short'
                    then 'PASS' else 'FAIL' end
        || ' a new memory defaults to short-term' || chr(10);

  -- 5. Measured performance changes who reviews. Staging carries no reputation rows, so the
  --    fixture supplies them: a probation head and a stronger peer in the same department.
  select d.dept_key, d.lead_agent, p.agent_key into v_dept, v_lead, v_peer
    from org_departments d
    join org_agents h on h.agent_key = d.lead_agent
     and h.active and h.available and (h.unavailable_until is null or h.unavailable_until < current_date)
    join org_agents p on p.department = d.dept_key and p.agent_key <> d.lead_agent
     and p.active and p.available and (p.unavailable_until is null or p.unavailable_until < current_date)
   limit 1;

  if v_dept is null then
    v_out := v_out || 'FAIL no department on staging has an available head and an available peer' || chr(10);
  else
    insert into agent_reputation (agent_key, score, tier, computed_at)
    values (v_lead, 41.0, 'probation', now()), (v_peer, 80.0, 'trusted', now())
    on conflict (agent_key) do update set score = excluded.score, tier = excluded.tier;

    v_r := fn_pick_reviewer(v_dept);
    v_out := v_out || case when v_r ->> 'reviewer' = v_peer and v_r ->> 'delegated_from' = v_lead
                      then 'PASS' else 'FAIL' end
          || ' probation head ' || v_lead || ' replaced by higher-scoring ' || v_peer
          || ' [got ' || coalesce(v_r ->> 'reviewer', 'null') || ']' || chr(10);

    -- No better-scoring alternative: the head must KEEP the review rather than the department
    -- being stranded with reviewer=null, which would break fn_review_submit.
    update agent_reputation set score = 10.0, tier = 'probation' where agent_key = v_peer;
    v_r := fn_pick_reviewer(v_dept);
    v_out := v_out || case when v_r ->> 'reviewer' = v_lead and (v_r ->> 'available')::boolean
                      then 'PASS' else 'FAIL' end
          || ' no better-scoring peer: the head still reviews rather than the department stranding'
          || ' [got ' || coalesce(v_r ->> 'reviewer', 'null') || ']' || chr(10);
  end if;

  -- 6. Both writers are idempotent: a second run must not duplicate what the first produced.
  select (fn_sop_update() ->> 'written')::int into v_n;
  v_out := v_out || case when v_n = 0 then 'PASS' else 'FAIL' end
        || ' fn_sop_update writes nothing on a repeat run [wrote ' || v_n || ']' || chr(10);

  select (fn_promote_memory_sweep(5) ->> 'failed')::int into v_n;
  v_out := v_out || case when v_n = 0 then 'PASS' else 'FAIL' end
        || ' fn_promote_memory_sweep promotes without errors [failed ' || v_n || ']' || chr(10);

  select count(*) into v_n from agent_memory where horizon is null or horizon not in ('short','long');
  v_out := v_out || case when v_n = 0 then 'PASS' else 'FAIL' end
        || ' every memory carries a horizon [' || v_n || ' without one]' || chr(10);

  raise exception 'FIXTURE_RESULTS%', chr(10) || v_out;
end
$fixture$;
`;

let raw = '';
try {
  await mgmtWrite(STAGE, SQL, 'memory cluster fixture');
  console.log('THE FIXTURE DID NOT ABORT — it must always end by raising so nothing is left behind.');
  process.exit(1);
} catch (e) { raw = String(e.body || e.message || e); }

const body = raw.includes('FIXTURE_RESULTS') ? raw.slice(raw.indexOf('FIXTURE_RESULTS') + 15) : raw;
const lines = body.split(/\\n|\n/).map(s => s.trim()).filter(l => /^(PASS|FAIL)/.test(l));
for (const l of lines) console.log(l);
if (!lines.length) { console.log('NO RESULTS — the fixture never reached its report:\n' + raw.slice(0, 1200)); process.exit(1); }
const fails = lines.filter(l => l.startsWith('FAIL')).length;
console.log(`\n${lines.length - fails}/${lines.length} fixture assertions passed on staging ${STAGE}`);
process.exit(fails ? 1 : 0);
