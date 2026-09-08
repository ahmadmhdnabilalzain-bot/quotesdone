// RETIRED 8 September 2026 — its subject was removed from the company, not from the check.
//
// Subject: the department re-carve of the ten-department organisation.
//
// fn_ops_department_context returned a projection per department. There are no departments: the founder
// removed the organisation chart on 7 September and the company is two seats, ceo and
// customer_support. fn_org_role_agent, fn_org_role_violations and fn_specialist_invoke, which this file
// also drives, were already absent from production before today.
//
// RETIRED RATHER THAN SOFTENED. Editing the assertions until they pass would leave a check that goes
// green while the thing it checks does not exist, which converts an absence into confidence and is
// worse than having no check at all. Renaming it out of the .test.mjs glob keeps every word of the
// reasoning on disk for whoever rebuilds the surface, and brings nothing green with it.
//
// TO REVIVE: rebuild the subject, then rename this back to .test.mjs and re-point the routine names.
// AGENT COMPANY REORGANISATION — BEHAVIOURAL TESTS.
//
// Every test here runs the real runtime path, on production. None of them asserts on a source
// string, a row count that a seed could satisfy, or a function merely existing. Where a behaviour
// must NOT occur, the test constructs the input that would make it occur and asserts the refusal:
// a new guard returning zero proves nothing until you force it to fire.
//
// Writes run inside an aborted transaction — do the write, count the effect, raise with the counts
// so the transaction rolls back and the numbers still come out.
//
//   node --test scripts/checks/org_reorg_behaviour.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const mgmtToken = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

// CI runs `npm test` with no SUPABASE_ACCESS_TOKEN, so these skip there and run locally. Without
// the guard every one fails on a 401 that reads like a data failure and is not one.
// staging was a second target until its Supabase project was deleted on 15 Aug 2026; the same
// assertions now run against production alone.
const PROJECTS = { production: 'htdblwldjkcgjvmqkbeh' };

async function post(project, query) {
  for (let attempt = 0; ; attempt++) {
    const r = await fetch(`https://api.supabase.com/v1/projects/${project}/database/query`, {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + mgmtToken, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query }),
    });
    const text = await r.text();
    // A mass of failures with the other project passing is throttling, not a finding.
    if ((r.status === 429 || r.status >= 500) && attempt < 8) {
      await new Promise((s) => setTimeout(s, Math.min(1500 * 2 ** attempt, 20000))); continue;
    }
    return { ok: r.ok, status: r.status, text };
  }
}

const q = async (project, query) => {
  const r = await post(project, query);
  assert.ok(r.ok, `query failed on ${project}: ${r.status} ${r.text}`);
  return JSON.parse(r.text);
};
const one = async (project, query) => (await q(project, query))[0];

// Run a write, count its effect, then abort so nothing is left behind. The counts come back in
// the error text because the transaction that produced them no longer exists.
async function probe(project, body) {
  const r = await post(project, `do $$
declare v_out text;
begin
${body}
  raise exception 'PROBE %', v_out;
end $$;`);
  const m = /PROBE ([^"\\]*)/.exec(r.text);
  assert.ok(m, `probe produced no counts on ${project}: ${r.text}`);
  return m[1];
}

for (const [label, ref] of Object.entries(PROJECTS)) {
  const it = (name, fn) => test(`${name} [${label}]`, { skip: !mgmtToken && 'no SUPABASE_ACCESS_TOKEN' }, fn);

  // ---- 1. Unique role resolution -------------------------------------------------------------
  it('every role_id is unique and every active runtime agent maps to exactly one role', async () => {
    const r = await one(ref, `select
      (select count(*) from org_role where status='active') roles,
      (select count(*) from org_role where status='active' and runtime_mode='knowledge_overlay') overlays,
      (select count(*) from (select runtime_agent_key from org_role
         where status='active' and runtime_agent_key is not null
         group by 1 having count(*)>1) d) dupes,
      (select count(*) from org_agents a where a.active and not exists
         (select 1 from org_role r where r.status='active' and r.runtime_agent_key=a.agent_key)) unowned_agents`);
    assert.equal(Number(r.dupes), 0, 'an agent holds two active canonical roles');
    assert.equal(Number(r.unowned_agents), 0, 'an active employee maps to no canonical role');
    assert.equal(Number(r.overlays), 86, 'the 86 category overlays must all exist as roles');
    // 3 SEP 2026 (PACR-004): the approved size lives in the Phase A baseline, not in this file.
    const approved = await one(ref, `select (counts->>'canonical_roles')::int + (counts->>'category_overlays')::int n from org_phase_baseline where phase='A'`);
    assert.ok(Number(r.roles) >= Number(approved.n), `expected at least ${approved.n} active roles (Phase A baseline), got ${r.roles}`);
  });

  // ---- 2. Old IDs still resolve --------------------------------------------------------------
  it('every legacy and merged agent id still resolves to a live executor', async () => {
    const legacy = ['brief', 'followup', 'procurement', 'marketing', 'legal', 'analytics', 'it',
      'security', 'onboarding', 'docs', 'sales_director', 'ops_director', 'bookkeeper',
      'innovation_mgr', 'analytics_director', 'supplier_intel_analyst', 'notification_ops',
      'marketing_copy'];
    const rows = await q(ref, `select x.n,
        fn_org_agent_resolve(x.n) agent, fn_org_role_resolve(x.n) role, fn_org_role_agent(x.n) exec
      from (values ${legacy.map((k) => `('${k}')`).join(',')}) x(n)`);
    for (const row of rows) {
      assert.ok(row.agent, `legacy id ${row.n} resolves to no agent — every caller using it breaks silently`);
      assert.ok(row.role, `legacy id ${row.n} resolves to no canonical role`);
      assert.ok(row.exec, `legacy id ${row.n} has no executing agent`);
    }
    // and the canonical names work too
    const canon = await q(ref, `select x.n, fn_org_agent_resolve(x.n) agent from (values
      ('chief_of_staff'),('customer_success_director'),('marketplace_director'),('general_counsel'),
      ('cybersecurity_engineer'),('chief_revenue_officer'),('chief_operating_officer'),
      ('financial_controller'),('product_manager'),('data_engineer'),
      ('it_operations_engineer'),('supplier_onboarding_specialist'),
      ('document_operations_specialist'),('site_reliability_engineer'),
      ('data_protection_officer')) x(n)`);
    for (const row of canon) assert.ok(row.agent, `canonical id ${row.n} does not resolve to an agent`);
  });

  // ---- 3. Manager chains, no cycles ----------------------------------------------------------
  it('every role reaches the CEO through a finite manager chain', async () => {
    const r = await one(ref, `with recursive up as (
        select role_id, manager_role_id, 0 d, role_id as top from org_role where status='active'
        union all
        select u.role_id, m.manager_role_id, u.d+1, m.role_id
          from up u join org_role m on m.role_id=u.manager_role_id and m.status='active'
         where u.d < 40)
      select count(*) filter (where d >= 40) as runaway,
             count(distinct role_id) filter (where manager_role_id is null and top='ceo') as reach_ceo,
             (select count(*) from org_role where status='active') as total
        from up`);
    assert.equal(Number(r.runaway), 0, 'a manager chain did not terminate — cycle or depth blow-up');
    assert.equal(Number(r.reach_ceo), Number(r.total), 'a role does not reach the CEO');
  });

  it('a reporting cycle is refused, not merely absent', async () => {
    // Force the branch: make the CEO report to one of its own reports.
    const r = await post(ref, `do $$ begin
      update org_role set manager_role_id='chief_of_staff' where role_id='ceo';
      raise exception 'CYCLE NOT REFUSED';
    end $$;`);
    assert.ok(/reporting cycle/i.test(r.text),
      `the no-cycle trigger did not fire on a constructed cycle: ${r.text}`);
  });

  // ---- 4. Department ownership ---------------------------------------------------------------
  it('exactly ten active departments, each with a lead who is a member', async () => {
    const r = await one(ref, `select
      (select count(*) from org_departments where active) depts,
      (select count(*) from org_departments d where d.active and (d.lead_agent is null or not exists
        (select 1 from org_agents a where a.agent_key=d.lead_agent and a.active and a.department=d.dept_key))) bad_lead,
      (select count(*) from org_agents a join org_departments d on d.dept_key=a.department
        where a.active and not d.active) in_dead_dept,
      (select count(*) from org_tasks t join org_departments d on d.dept_key=t.dept_key
        where t.status in ('assigned','in_progress') and not d.active) open_in_dead_dept`);
    assert.equal(Number(r.depts), 10, 'the target is ten primary departments');
    assert.equal(Number(r.bad_lead), 0, 'a department head is not a member of the department it leads');
    assert.equal(Number(r.in_dead_dept), 0, 'an active employee sits in a closed department');
    assert.equal(Number(r.open_in_dead_dept), 0, 'open work sits in a closed department');
  });

  // ---- 5. Knowledge retrieval survived the merge ---------------------------------------------
  it('a moved employee still retrieves its own department knowledge and its canonical role', async () => {
    const rows = await q(ref, `select a.agent_key,
        jsonb_array_length(c->'department_knowledge') dept_k,
        c->'identity'->>'role_id' role_id,
        c->'identity'->>'runtime_mode' mode,
        jsonb_array_length(c->'identity'->'owned_decisions') owned,
        jsonb_array_length(c->'identity'->'forbidden_decisions') forbidden,
        jsonb_array_length(c->'identity'->'authority') auth,
        (c->>'knowledge_count')::int kc
      from org_agents a, lateral (select fn_agent_context_v3(a.agent_key) c) x
      -- marketing and docs were parked by the 3 Sep 2026 re-carve; bd and qa_manager moved that day.
      where a.agent_key in ('bd','procurement','it','security','followup','cfo','onboarding','qa_manager')`);
    assert.equal(rows.length, 8);
    for (const row of rows) {
      assert.ok(Number(row.dept_k) > 0,
        `${row.agent_key} retrieved no department knowledge after the merge — the dept scope is broken`);
      assert.ok(row.role_id, `${row.agent_key} has no canonical role in its context`);
      assert.ok(Number(row.owned) > 0, `${row.agent_key} carries no owned decisions`);
      assert.ok(Number(row.forbidden) > 0, `${row.agent_key} carries no forbidden decisions`);
      assert.ok(Number(row.auth) > 0, `${row.agent_key} carries no authority`);
      assert.ok(Number(row.kc) > 10, `${row.agent_key} assembled only ${row.kc} knowledge records`);
    }
  });

  it('the authority block carries one row per action class, not one per predecessor department', async () => {
    const r = await one(ref, `with a as (select fn_agent_context_v3('marketing') c)
      select jsonb_array_length(c->'identity'->'authority') n,
             (select count(distinct e->>'action_class')
                from a, jsonb_array_elements(c->'identity'->'authority') e) distinct_n from a`);
    assert.equal(Number(r.n), Number(r.distinct_n),
      'the same action class appears more than once with possibly different tiers');
  });

  // ---- 6. Independent review: the author is never the reviewer --------------------------------
  it('a department head cannot be picked to review its own work', async () => {
    const rows = await q(ref, `select d.dept_key, d.lead_agent,
        fn_pick_reviewer(d.dept_key, d.lead_agent)->>'reviewer' reviewer,
        fn_pick_reviewer(d.dept_key, d.lead_agent)->>'basis' basis
      from org_departments d where d.active`);
    assert.equal(rows.length, 10);
    for (const row of rows) {
      assert.notEqual(row.reviewer, row.lead_agent,
        `${row.dept_key}: the head ${row.lead_agent} was picked to review its own work`);
    }
    // and with no author the behaviour is unchanged, so no existing caller changed meaning
    const unchanged = await one(ref, `select fn_pick_reviewer('marketplace')->>'reviewer' r`);
    assert.equal(unchanged.r, 'procurement');
  });

  it('fn_review_submit records a reviewer that is not the author, for a head-authored draft', async () => {
    const counts = await probe(ref, `
      perform fn_review_submit('social_post','reorg-probe-1','marketplace','procurement','probe body');
      select count(*)||'/'||count(*) filter (where reviewer_agent = author_agent)
        into v_out from review_chain where subject_id='reorg-probe-1';`);
    const [total, self] = counts.trim().split('/').map(Number);
    assert.ok(total > 0, 'the review probe wrote no review_chain rows');
    assert.equal(self, 0, `${self} of ${total} rows written by fn_review_submit are self-reviews`);
  });

  it('a self-review row is refused by the constraint, not merely avoided by the picker', async () => {
    const r = await post(ref, `do $$ begin
      insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage, decision)
      values ('social_post','reorg-probe-2','marketplace','procurement','procurement','dept_review','approve');
      raise exception 'SELF APPROVAL NOT REFUSED';
    end $$;`);
    // Either guard refusing is a pass. The CHECK constraint still exists and still fires on its
    // own; since 14 Aug 2026 the a00_ BEFORE trigger simply gets there first, and it is strictly
    // stronger — the CHECK compares the two columns as written, the trigger resolves both sides
    // and so also catches the case where author and reviewer are one employee under two names.
    // Asserting on the constraint NAME would have made a stronger guard look like a regression.
    assert.ok(/review_chain_no_self_approval_ck|refuses a self-review/i.test(r.text),
      `a self-approval insert was accepted: ${r.text}`);
  });

  // ---- 7. Specialist invocation and handoff --------------------------------------------------
  it('a manager invokes a specialist as a tool and keeps ownership', async () => {
    // Two statements, not one: a single SELECT reads its snapshot before the function inside it
    // performs the INSERT, so the count would be 0 for a row that exists.
    const counts = await probe(ref, `
      -- boq_analyst was parked on 4 Sep 2026 (STAFF_ORG seat-at-plan-size); the Match-eval analyst is the
      -- on-demand specialist the RFQ qualification manager reaches for now.
      select (fn_specialist_invoke('rfq_qualification_manager','supplier_analyst','inquiry','reorg-probe-3',
                'supplier reliability judgement')->>'ok') into v_out;
      select v_out||'/'||(select count(*)::text from review_chain
                           where subject_id='reorg-probe-3' and stage='specialist_invocation')
        into v_out;`);
    const [ok, rows] = counts.trim().split('/');
    assert.equal(ok, 'true', 'the specialist invocation was refused');
    assert.equal(Number(rows), 1, 'the invocation left no trace');
  });

  it('invoking a standing manager as a tool is refused and named as a handoff instead', async () => {
    const r = await one(ref, `select fn_specialist_invoke('rfq_qualification_manager','cfo','inquiry','x','y') j`);
    assert.equal(r.j.ok, false, 'a scheduled manager was accepted as a tool');
    assert.match(r.j.error, /scheduled_manager/);
    assert.equal(r.j.use, 'fn_role_handoff');
  });

  it('a cross-department handoff names exactly one accountable owner', async () => {
    const counts = await probe(ref, `
      select (fn_role_handoff('customer_support','general_counsel','dispute','reorg-probe-4',
                'customer alleges a contractual breach')->>'accountable_owner') into v_out;
      select v_out||'/'||(select count(*)::text from review_chain
                           where subject_id='reorg-probe-4' and stage='handoff')
        into v_out;`);
    const [owner, rows] = counts.trim().split('/');
    assert.equal(owner, 'general_counsel');
    assert.equal(Number(rows), 1, 'the handoff left no trace');
  });

  it('a role cannot hand off to itself', async () => {
    const r = await one(ref, `select fn_role_handoff('cfo','cfo','x','y','z') j`);
    assert.equal(r.j.ok, false);
  });

  // ---- 8. Overlay invocation -----------------------------------------------------------------
  it('every category resolves to an overlay role invoked by the Inquiry Router', async () => {
    const r = await one(ref, `select
      count(*) n,
      count(*) filter (where (fn_overlay_for_category(category_key)->>'exists')::boolean) with_role,
      count(*) filter (where fn_overlay_for_category(category_key)->>'invoked_by_role' = 'inquiry_router') routed
      from org_category_identity`);
    assert.equal(Number(r.n), 86);
    assert.equal(Number(r.with_role), 86, 'a category has no overlay role');
    assert.equal(Number(r.routed), 86, 'a category overlay is not invoked by the Inquiry Router');
  });

  it('an overlay has no standing executor and cannot own work', async () => {
    const r = await one(ref, `select
      count(*) filter (where runtime_agent_key is not null) with_agent,
      count(*) filter (where 'dispatching to suppliers' = any(forbidden_decisions)) cannot_dispatch,
      count(*) filter (where 'exposing customer identity' = any(forbidden_decisions)) cannot_expose,
      count(*) n
      from org_role where status='active' and runtime_mode='knowledge_overlay'`);
    assert.equal(Number(r.with_agent), 0, 'an overlay holds a standing model instance');
    assert.equal(Number(r.cannot_dispatch), Number(r.n));
    assert.equal(Number(r.cannot_expose), Number(r.n));
  });

  // ---- 9. Task assignment: one accountable owner, reviewers left independent -----------------
  it('independent reviewers are not handed ordinary departmental work', async () => {
    const r = await one(ref, `select count(*) n from org_tasks t
       join org_role r on r.runtime_agent_key = t.assigned_agent and r.status='active'
      where t.status in ('assigned','in_progress')
        and r.runtime_mode='independent_reviewer'
        and coalesce(t.action_class,'') not in ('review','audit','verify','qa_gate','security_review',
              'compliance_check','legal_review','supplier_verify','capability_review','self_review')`);
    assert.equal(Number(r.n), 0,
      `${r.n} open non-review tasks sit with an independent reviewer, which is what makes it not independent`);
  });

  it('no open task is assigned to an inactive or unknown employee', async () => {
    const r = await one(ref, `select count(*) n from org_tasks t
      where t.status in ('assigned','in_progress') and t.assigned_agent is not null
        and not exists (select 1 from org_agents a where a.agent_key=t.assigned_agent and a.active)`);
    assert.equal(Number(r.n), 0, 'open work is assigned to somebody who no longer exists');
  });

  // ---- 10. Completeness: no active role without the things it needs ---------------------------
  it('fn_org_role_violations is empty', async () => {
    const rows = await q(ref, `select rule, role_id, detail from fn_org_role_violations() limit 40`);
    assert.equal(rows.length, 0,
      'roles violate the canonical rules: ' + rows.map((x) => `${x.rule}:${x.role_id}`).join(', '));
  });

  it('committee membership never creates a second role', async () => {
    const r = await one(ref, `select
      (select count(*) from org_role_committee) seats,
      (select count(distinct role_id) from org_role_committee) roles_with_seats,
      (select count(*) from org_role_committee c
         where not exists (select 1 from org_role r where r.role_id=c.role_id and r.status='active')) orphan_seats,
      (select count(*) from org_role r where r.status='active'
         and (select count(*) from org_role x where x.status='active'
               and x.display_name = r.display_name) > 1) duplicate_names`);
    assert.ok(Number(r.seats) > Number(r.roles_with_seats),
      'nobody sits on more than one committee, which would mean the seats are not being used');
    assert.equal(Number(r.orphan_seats), 0);
    assert.equal(Number(r.duplicate_names), 0, 'two active roles share a display name');
  });

  // ---- 11. The objective cascade reaches the revenue target -----------------------------------
  it('the cascade reaches AED 1,000,000 and reports what is unlinked rather than hiding it', async () => {
    const r = await one(ref, `select fn_objective_cascade() c`);
    assert.equal(Number(r.c.revenue_objective_aed), 1000000);
    assert.ok(Number(r.c.department_objectives) > 0);
    assert.ok(Number(r.c.role_kpis_linked_upward) > 0);
    // the honest part: the function must SAY what is unlinked, never report completeness it lacks
    assert.ok('unlinked_department_objectives' in r.c);
    assert.ok('unlinked_role_kpis' in r.c);
  });

  it('an unmeasurable category metric reports null and a reason, never 100', async () => {
    const r = await one(ref, `select fn_category_specialist_scorecard(1) c`);
    for (const k of ['routing_accuracy', 'supplier_response_rate', 'valid_quotations']) {
      if (r.c[k] === null) {
        // A null metric must say WHY. The rule being enforced is that an absent input never scores
        // as satisfied — pct(got, 0) = 100 is how 56 unmeasured goals once read as perfect.
        assert.ok(typeof r.c[`${k}_basis`] === 'string' && r.c[`${k}_basis`].length > 20,
          `${k} is null but gives no stated reason`);
      } else {
        assert.ok(Number(r.c[k]) >= 0 && Number(r.c[k]) <= 100);
      }
    }
    assert.equal(Number(r.c.overlays_active), 86);
  });

  // ---- 12. The target operating model still reaches every department -------------------------
  it('every active department resolves target departments and decision rules', async () => {
    // ops_kb_stage.department_crosswalk is keyed on the PRODUCTION department key and is the only
    // table outside `public` that is. The merge did not touch it, so fn_ops_department_context
    // returned 0 targets and 0 rules for every new department and the "TARGET OPERATING MODEL"
    // block silently left every moved employee's context. The pack scorecard caught it at 36/37.
    const rows = await q(ref, `select d.dept_key,
        jsonb_array_length(coalesce(fn_ops_department_context(d.dept_key,null,2)->'target_departments','[]')) tdepts,
        jsonb_array_length(coalesce(fn_ops_department_context(d.dept_key,null,2)->'decision_rules','[]')) rules
      from org_departments d where d.active order by d.sort`);
    assert.equal(rows.length, 10);
    for (const r of rows) {
      assert.ok(Number(r.tdepts) > 0, `${r.dept_key} maps to no target department`);
      assert.ok(Number(r.rules) > 0, `${r.dept_key} resolves no decision rule`);
    }
    const ctx = await one(ref, `select position('TARGET OPERATING MODEL' in c) tom
      from (select public.fn_agent_context('procurement', 24000) c) z`);
    assert.ok(Number(ctx.tom) > 0, 'fn_agent_context no longer emits the target operating model');
  });

  // ---- 13. The resolver is ON the path every employee turn goes through -----------------------
  it('context assembly resolves canonical, legacy, merged and packaged identifiers', async () => {
    // Of 68 routines taking an agent/actor/assignee argument, one resolved. This is the path
    // agent_brain, action_worker, dept_plan, agent_act and exec_agents all reach context through.
    const r = await one(ref, `select
      fn_agent_context_v3('chief_of_staff')->'identity'->>'agent_key' canonical,
      fn_agent_context_v3('brief')->'identity'->>'agent_key' legacy,
      fn_agent_context_v3('analytics_director')->'identity'->>'agent_key' merged,
      fn_agent_context_v3('legal-and-compliance-director')->'identity'->>'agent_key' packaged,
      fn_org_agent_resolve('Marketplace Director') new_title,
      fn_org_agent_resolve('Procurement Director') old_title`);
    assert.equal(r.canonical, 'brief', 'the canonical role id does not reach its employee');
    assert.equal(r.legacy, 'brief');
    assert.equal(r.merged, 'intel_director', 'a merged-away key does not reach its survivor');
    assert.equal(r.packaged, 'legal', 'a packaged role id does not reach its employee');
    assert.equal(r.new_title, 'procurement', 'the canonical job title does not resolve');
    assert.equal(r.old_title, 'procurement', 'the previous job title stopped resolving');
  });

  it('an inactive employee gets no context, and an unknown one gets no context', async () => {
    // Before the fix fn_agent_context_v3('analytics_director') assembled a full context for an
    // employee merged away that morning, because the lookup never checked `active`. A context is
    // what lets an employee act.
    const r = await one(ref, `select
      left(fn_agent_context_capped('no_such_agent_xyz', 3000, 'x'), 24) unknown_capped,
      (select count(*) from org_agents a where a.active
         and (fn_agent_context_v3(a.agent_key)->>'error') is not null) active_refused,
      (select count(*) from org_agents a where not a.active
         and coalesce(fn_org_agent_resolve(a.agent_key), a.agent_key) = a.agent_key
         and (fn_agent_context_v3(a.agent_key)->>'error') is null) inactive_assembled`);
    assert.match(r.unknown_capped, /No such employee/,
      'an unknown employee still receives an assembled context');
    assert.equal(Number(r.active_refused), 0, 'an ACTIVE employee was refused a context');
    assert.equal(Number(r.inactive_assembled), 0,
      'an inactive employee with no surviving alias still assembles a context');
  });

  it('all 96 packaged knowledge roles reach an active canonical role', async () => {
    const r = await one(ref, `select
      (select count(distinct packaged_role_id) from org_role_identity) packaged,
      (select count(*) from (
         select i.packaged_role_id from org_role_identity i
          where not exists (select 1 from org_role_identity x
                              join org_agents a on a.agent_key = x.agent_key and a.active
                             where x.packaged_role_id = i.packaged_role_id)
          group by 1) z) unreachable`);
    assert.equal(Number(r.packaged), 96, 'the packaged role count moved');
    assert.equal(Number(r.unreachable), 0,
      'a packaged role is held only by a deactivated employee, so its knowledge reaches nobody');
  });

  // ---- 14. Authority refusal ------------------------------------------------------------------
  it('raising a department tier without a stated reason is refused', async () => {
    const r = await post(ref, `do $$ begin
      insert into org_authority (dept_key, action_class, max_tier, threshold_aed, note)
      values ('assurance','reorg_probe_widen','autonomous', 999999, 'probe')
      on conflict (dept_key, action_class) do update set max_tier='autonomous';
      raise exception 'WIDEN NOT REFUSED';
    end $$;`);
    assert.ok(/needs a stated reason/i.test(r.text),
      `org_authority accepted a widening with no change_reason: ${r.text}`);
  });

  it('every independent reviewer holds stop authority', async () => {
    const r = await one(ref, `select count(*) n from org_role r
      where r.status='active' and r.runtime_mode='independent_reviewer'
        and not exists (select 1 from employee_authority e
          where e.agent_key=r.runtime_agent_key and e.action_class='review_block' and e.max_tier='autonomous')`);
    assert.equal(Number(r.n), 0, 'an independent reviewer cannot actually block anything');
  });

  // ---- 15. The canonical shape, frozen -------------------------------------------------------
  // The founder froze the ten-department structure on 14 Aug 2026. These numbers are not targets
  // to reach; they are the accepted organisation, and a change to any of them is a reorganisation
  // that must be a deliberate commit rather than a side effect.
  it('the canonical organisation shape holds', async () => {
    const r = await one(ref, `select
      (select count(*) from org_departments where coalesce(active,false)) active_depts,
      (select count(*) from org_departments where merged_into is not null) merged_rows,
      (select count(*) from org_role where status='active' and runtime_mode<>'knowledge_overlay') accountable,
      (select count(*) from org_role where status='active' and runtime_mode='knowledge_overlay') overlays,
      (select count(distinct packaged_role_id) from org_role_identity) packaged,
      (select count(distinct agent_key) from org_role_identity) identity_agents,
      (select count(*) from fn_org_role_violations()) violations,
      -- every merged department points at a department that is actually alive
      (select count(*) from org_departments d where d.merged_into is not null and not exists
        (select 1 from org_departments c where c.dept_key=d.merged_into and coalesce(c.active,false))) merged_to_dead,
      -- no accountable role without an identity, no identity without a live employee
      (select count(*) from org_role r where r.status='active' and r.runtime_mode<>'knowledge_overlay'
        and not exists (select 1 from org_role_identity i where i.agent_key=r.runtime_agent_key)) role_without_identity,
      (select count(*) from org_role_identity i where not exists
        (select 1 from org_agents a where a.agent_key=i.agent_key and a.active)) identity_without_employee,
      -- knowledge scoped to a department that no longer exists would be retrieved by nobody
      (select count(*) from ops_knowledge k where k.runtime_eligible and k.supersession_state='current'
        and k.dept_key is not null and not exists
        (select 1 from org_departments d where d.dept_key=k.dept_key)) orphaned_knowledge,
      (select count(*) from org_agents a where a.active and a.manager_key=a.agent_key) self_managed`);
    assert.equal(Number(r.active_depts), 10, 'the ten-department structure is frozen');
    // 3 SEP 2026 (PACR-004): assurance merged into product_eng (23 merged rows); the accountable role
    // count is the Phase A baseline's, recomputed by every PACR, not a literal typed here.
    const base = await one(ref, `select (counts->>'canonical_roles')::int n from org_phase_baseline where phase='A'`);
    assert.equal(Number(r.merged_rows), 23, '23 departments were merged away');
    assert.equal(Number(r.accountable), Number(base.n), `${base.n} accountable runtime roles (Phase A baseline)`);
    assert.equal(Number(r.overlays), 86, '86 category overlays');
    assert.equal(Number(r.packaged), 96, 'all 96 packaged roles are held');
    assert.equal(Number(r.identity_agents), Number(base.n), `the ${base.n} accountable roles are the identity holders`);
    assert.equal(Number(r.violations), 0, 'fn_org_role_violations() must return no rows');
    assert.equal(Number(r.merged_to_dead), 0, 'a department merged into a dead department');
    assert.equal(Number(r.role_without_identity), 0, 'an accountable role with no packaged identity');
    assert.equal(Number(r.identity_without_employee), 0,
      'a packaged identity naming an employee the merge deactivated — resolves, so nothing fails');
    assert.equal(Number(r.orphaned_knowledge), 0, 'knowledge scoped to a department that no longer exists');
    assert.equal(Number(r.self_managed), 0, 'an employee is its own manager');
  });

  // ---- 16. Ambiguity is confined to the composite mappings that declare it -------------------
  // DECIDED 14 Aug 2026, not merely reported. 22 packaged roles resolve to more than one active
  // employee — marketing-operations-specialist is held by five real marketing desks. That is the
  // package_composite pattern: the knowledge pack ships archetypes, the company has desks, and one
  // archetype legitimately covers several. Forcing one holder each would either delete real desks
  // or invent fake archetypes, and the structure is frozen.
  //
  // So the boundary is not "one holder per packaged role". It is: a packaged role may be shared
  // ONLY through a mapping that says so. A one_to_one row sharing its archetype is a mistake,
  // because one_to_one is the claim that it is not shared.
  // The contradiction is one_to_one, not "not composite". Measured on both projects:
  //   package_composite 48 rows / 47 shared  - the archetype legitimately covering several desks
  //   requires_split    33 rows /  1 shared  - a flag that this holder should be split out; it is
  //                                            an acknowledgement, not a claim of exclusivity
  //   runtime_composite 27 rows /  0 shared
  //   one_to_one        19 rows /  0 shared  - the claim that it is NOT shared, and it holds
  // An earlier version of this test forbade any non-composite mapping from sharing, which made
  // requires_split look like a violation the moment v3_repair_06 set one. That was the assertion
  // being wider than the property it was defending.
  it('a mapping that claims exclusivity never shares its packaged role', async () => {
    const rows = await q(ref, `select i.packaged_role_id, i.agent_key, i.mapping_type
      from org_role_identity i
      where i.mapping_type = 'one_to_one'
        and exists (select 1 from org_role_identity j
                     where j.packaged_role_id = i.packaged_role_id and j.agent_key <> i.agent_key)
      order by 1, 2`);
    assert.equal(rows.length, 0,
      `a one_to_one mapping shares its packaged role, which is a contradiction in terms: ${JSON.stringify(rows)}`);
  });

  // requires_split is tracked debt, not a failure — but it must not quietly become the way new
  // sharing is introduced. One is the measured baseline; a second means somebody used the flag
  // instead of deciding.
  it('shared packaged roles under requires_split do not grow past the known one', async () => {
    const r = await one(ref, `select count(*) n from org_role_identity i
      where i.mapping_type = 'requires_split'
        and exists (select 1 from org_role_identity j
                     where j.packaged_role_id = i.packaged_role_id and j.agent_key <> i.agent_key)`);
    assert.ok(Number(r.n) <= 1,
      `${r.n} requires_split rows now share a packaged role, up from the known 1 `
      + '(supplier_analyst on data-analytics-and-intelligence-analyst-controller)');
  });

  // ---- 17. Reviewer independence survives the alias ------------------------------------------
  // Measured on production 14 Aug 2026 BEFORE the fix: passing the author under an alias defeated
  // the self-review guard in all ten departments, because fn_pick_reviewer compared raw strings
  // and every head carries aliases. A guard that only holds for one spelling of the author is not
  // a guard, so this asserts the behaviour for the alias, not for the canonical key.
  it('an author passed under an alias is never returned as its own reviewer', async () => {
    const rows = await q(ref, `with h as (
        select d.dept_key, d.lead_agent, al.alias
        from org_departments d
        join org_agent_alias al on al.agent_key = d.lead_agent and al.alias <> d.lead_agent
        where coalesce(d.active,false) and d.lead_agent is not null)
      select h.dept_key, h.lead_agent, h.alias,
             public.fn_pick_reviewer(h.dept_key, h.alias)->>'reviewer' reviewer
        from h`);
    assert.ok(rows.length >= 10, `expected every department head to carry an alias, got ${rows.length} rows`);
    for (const row of rows) {
      assert.notEqual(row.reviewer, row.lead_agent,
        `${row.dept_key}: author "${row.alias}" resolves to ${row.lead_agent}, who was returned as its own reviewer`);
    }
  });

  it('review_chain refuses a self-review written straight to the table', async () => {
    const r = await post(ref, `do $$ begin
      insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent,
                                stage, decision, reason, confidence)
      select 'probe','zz_selfreview_probe', d.dept_key, d.lead_agent, al.alias,
             'dept_review','approve','probe',1.0
        from org_departments d
        join org_agent_alias al on al.agent_key = d.lead_agent and al.alias <> d.lead_agent
       where coalesce(d.active,false) limit 1;
      raise exception 'SELF REVIEW NOT REFUSED';
    end $$;`);
    assert.ok(/refuses a self-review/i.test(r.text),
      `review_chain accepted an alias self-review by direct insert: ${r.text}`);
  });

  // ---- 18. Every dirham is inside some ceiling ------------------------------------------------
  // Measured before the fix: 64% of staging's month-to-date AI spend was outside every budget,
  // 29.87 AED with no dept_key and 37.87 AED under 22 department keys the merge had removed. The
  // halt could not bite on money no budget could see.
  it('no month-to-date AI spend falls outside every department ceiling', async () => {
    const r = await one(ref, `with m as (
        select * from ai_cost_log where occurred_at >= date_trunc('month', now()))
      select round(coalesce(sum(cost_aed),0),2) total,
             round(coalesce(sum(cost_aed) filter (where dept_key is null),0),2) no_dept,
             round(coalesce(sum(cost_aed) filter (where dept_key is not null and not exists
               (select 1 from department_budget b
                 where m.dept_key = any(public.fn_dept_scope(b.dept_key)))),0),2) no_ceiling
        from m`);
    // Rows written before the attribution fix keep their NULL; this asserts the SHARE now, and the
    // trigger test below asserts that a NEW un-departmented call cannot land outside a ceiling.
    const outside = Number(r.no_dept) + Number(r.no_ceiling);
    const pct = Number(r.total) > 0 ? (100 * outside) / Number(r.total) : 0;
    assert.ok(pct < 35,
      `${pct.toFixed(1)}% of this month's AI spend is outside every ceiling `
      + `(${r.no_dept} AED with no department, ${r.no_ceiling} AED under a department with no budget)`);
  });

  it('a new AI cost row cannot be logged outside every ceiling, and the halt fires', async () => {
    const out = await probe(ref, `
  declare v_dept text; v_canon text; v_before text; v_after text; v_burn numeric;
begin
  insert into ai_cost_log (occurred_at, fn, model_used, prompt_tokens, output_tokens, cost_aed, ok)
  values (now(),'drawing_redact','probe',1,1,0,true) returning dept_key into v_dept;

  insert into ai_cost_log (occurred_at, fn, dept_key, model_used, prompt_tokens, output_tokens, cost_aed, ok)
  values (now(),'zz_probe','marketing','probe',1,1,0,true) returning dept_key into v_canon;

  v_before := public.fn_ai_route(p_fn=>'agent_brain', p_dept_key=>'growth')->>'use_llm';
  select monthly_aed * 0.96 into v_burn from department_budget where dept_key='growth';
  insert into ai_cost_log (occurred_at, fn, dept_key, model_used, prompt_tokens, output_tokens, cost_aed, ok)
  values (now(),'zz_probe_burn','growth','probe',1,1, v_burn, true);
  v_after := public.fn_ai_route(p_fn=>'agent_brain', p_dept_key=>'growth')->>'use_llm';

  v_out := v_dept || '/' || v_canon || '/' || v_before || '/' || v_after;
end;`);
    const [dept, canon, before, after] = out.trim().split('/');
    assert.equal(dept, 'marketplace',
      'an un-departmented drawing_redact call was logged with no department, so no ceiling can see it');
    assert.equal(canon, 'growth',
      'a call logged under the merged-away key "marketing" was not canonicalised to growth');
    assert.equal(before, 'true', 'growth was already halted before the probe burned its budget');
    assert.equal(after, 'false',
      'the department budget halt did not fire after 96% of the budget was spent');
  });
}
