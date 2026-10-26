// RETIRED 8 September 2026 — its subject was deleted.
//
// Subject: the workflow system
//
// It fails with "no step runs exist at all, so this proves nothing" and "roles no workflow calls: ceo, customer_support" — both true and both expected: every pre-programmed workflow was removed on 7 Sep 2026 at the founder's instruction, and the two seats that remain do not run on workflow steps.
//
// RETIRED RATHER THAN SOFTENED. Editing it to pass would leave a check going green while the
// thing it checks does not exist, which converts an absence into confidence. Renaming it out of
// the .test.mjs glob keeps the reasoning on disk and brings nothing green with it.
//
// TO REVIVE: rebuild the subject, then rename back to .test.mjs.
// THE THIRTEEN WORKFLOWS, PROVED WITHOUT SPENDING ANYTHING.
//
// Free verification first. Everything in this file is a deterministic query or a guard forced to
// fire inside an aborted transaction. Nothing here calls a model. What it CANNOT prove is the part
// that genuinely needs a run — that a specialist was actually invoked, that knowledge was actually
// retrieved, that a real cost was recorded — and that is the capped staging smoke, run separately,
// which is deliberately the only part that costs money.
//
// The distinction matters and is stated in the evidence document: a registry assertion proves the
// company is WIRED to do the right thing. Only a run proves it DID.
//
//   node --test scripts/checks/workflow_ownership_alignment.test.mjs
import { SUPABASE_TOKEN_FILE } from '../../lib/supabase_token.mjs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const LOCAL_TOKEN = SUPABASE_TOKEN_FILE;
const mgmtToken = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();
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
    // 17 AUG 2026 — THE BUDGET WAS SMALLER THAN THE THROTTLE WINDOW.
    //   Five attempts at 1500 * 2^n is 1.5+3+6+12+24 = 46.5s. The independent acceptance measured
    //   this check failing on `429 ThrottlerException` after 47.5s — it exhausted every retry and
    //   the window had still not opened. run.mjs now serialises the suite, which took the 429
    //   failures from ten to one; this is the one. Eight attempts with the delay capped at 20s is
    //   ~102s, which clears it. Capping matters: doubling unbounded reaches four minutes on a
    //   single query and looks like a hang.
    // ponytail: per-file retry, replace with a shared limiter in front of the API when one exists.
    if ((r.status === 429 || r.status >= 500) && attempt < 8) {
      await new Promise((s) => setTimeout(s, Math.min(1500 * 2 ** attempt, 20000))); continue;
    }
    return { ok: r.ok, status: r.status, text };
  }
}
const q = async (p, sql) => {
  const r = await post(p, sql);
  assert.ok(r.ok, `query failed on ${p}: ${r.status} ${r.text}`);
  return JSON.parse(r.text);
};
const one = async (p, sql) => (await q(p, sql))[0];
const lit = (s) => `'${String(s).replace(/'/g, "''")}'`;

// The founder's thirteen scenarios, each mapped to the workflow that carries it and the owners
// that must appear in order. A step named here must exist, must resolve to a real employee, and
// must appear in this relative order — order is the property that made the 14 Aug harness green
// while proving nothing: it created the row before the step that needed it missing.
const SCENARIOS = [
  { n: 1,  name: 'customer inquiry without documents',
    workflow: 'rfq_handling',
    owners: ['customer_onboarding', 'rfq_qualification_manager', 'inquiry_router',
             'marketplace_content_privacy_reviewer', 'supplier_matching_dispatch_operator',
             'lifecycle_channel_operations'] },
  { n: 2,  name: 'customer inquiry with a drawing',
    workflow: 'rfq_handling',
    owners: ['rfq_qualification_manager', 'document_intelligence_manager', 'drawing_analyst',
             'inquiry_quality_analyst', 'marketplace_content_privacy_reviewer',
             'supplier_matching_dispatch_operator'] },
  { n: 3,  name: 'multi-category MEP / fit-out inquiry',
    workflow: 'rfq_handling',
    owners: ['inquiry_router', 'rfq_qualification_manager', 'inquiry_quality_analyst'] },
  { n: 4,  name: 'supplier onboarding and verification',
    workflow: 'supplier_onboarding',
    owners: ['supplier_onboarding_specialist', 'supplier_verification',
             'compliance_and_privacy_officer', 'supplier_coverage', 'supplier_retention'] },
  { n: 5,  name: 'supplier matching and idempotent dispatch',
    workflow: 'rfq_handling',
    owners: ['supplier_matching_dispatch_operator', 'lifecycle_channel_operations'] },
  { n: 6,  name: 'supplier-safe payload and redaction rejection',
    workflow: 'rfq_handling',
    owners: ['document_intelligence_manager', 'marketplace_content_privacy_reviewer',
             'supplier_matching_dispatch_operator'] },
  { n: 7,  name: 'quotation submission and technical comparison',
    workflow: 'rfq_handling',
    owners: ['quote_evaluation', 'marketplace_director'] },
  { n: 8,  name: 'customer comparison and reveal',
    workflow: 'payment',
    owners: ['billing_operations'] },
  { n: 9,  name: 'refund / dispute escalation',
    workflow: 'refund',
    owners: ['customer_support', 'billing_operations', 'customer_success_director'] },
  { n: 10, name: 'social content, artifact review, publish, learn',
    workflow: 'campaign_publishing',
    owners: ['content_strategy_and_copy', 'social_media_and_community', 'visual_design',
             'brand_and_creative', 'marketing_director'] },
  { n: 11, name: 'revenue underperformance diagnosis',
    workflow: 'metric_lifecycle',
    owners: ['data_intelligence_director', 'forecasting_analyst', 'chief_performance_officer',
             'business_intelligence_analyst'] },
  { n: 12, name: 'agent competency failure and remediation',
    workflow: 'improvement_lifecycle',
    owners: ['chief_performance_officer', 'knowledge_director'] },
  { n: 13, name: 'security incident and release block',
    workflow: 'incident_response',
    owners: ['it_operations_engineer', 'cybersecurity_engineer', 'cto', 'knowledge_director'] },
];

// employee_task binds these two per run rather than naming an employee, and the step-run evidence
// proves it does: 2,901+ recorded actors, every one a real resolvable employee, not one of them
// recorded as the placeholder itself. Anything ELSE that fails to resolve is an unowned step.
const RUN_BOUND_PLACEHOLDERS = ['owner', 'Director'];

for (const [name, ref] of Object.entries(PROJECTS)) {
  if (!mgmtToken) break;

  // -------------------------------------------------------------------------------------------
  // the completion standard, item by item
  // -------------------------------------------------------------------------------------------
  test(`${name}: every workflow step has one accountable owner that resolves to an employee`, async () => {
    const rows = await q(ref, `
      select workflow_key, step_no, actor_role
        from workflow_step
       where fn_org_agent_resolve(actor_role) is null
         and fn_org_role_resolve(actor_role) is null
         and actor_role not in (${RUN_BOUND_PLACEHOLDERS.map(lit).join(',')})
       order by workflow_key, step_no`);
    assert.deepEqual(rows, [],
      'these steps name an actor that resolves to nobody: '
      + rows.map((r) => `${r.workflow_key}#${r.step_no} "${r.actor_role}"`).join(', '));
  });

  test(`${name}: no LIVE step run is addressed to an identity nobody models`, async () => {
    // The placeholders are legitimate in the REGISTRY and not in a RUN. Measured on 15 Aug: 22
    // step runs carried a placeholder as their actor. 21 were 'skipped' — a step that never
    // executed keeps what it had, and those are deliberately left alone rather than rewritten.
    // ONE was still 'queued' from 10 Aug: a department-head review nobody could pick up, because
    // no employee answers to "Director". org_align_06 bound it to the head the registry already
    // designates for its own recorded department.
    const r = await one(ref, `
      select count(*) total,
             count(*) filter (where sr.status in ('queued','running','ok')
                                and coalesce(fn_org_agent_resolve(sr.actor), fn_org_role_resolve(sr.actor)) is null) live_unowned,
             count(*) filter (where sr.status not in ('queued','running','ok')
                                and coalesce(fn_org_agent_resolve(sr.actor), fn_org_role_resolve(sr.actor)) is null) inert_unowned
        from workflow_step_run sr`);
    assert.ok(Number(r.total) > 0, 'no step runs exist at all, so this proves nothing');
    assert.equal(Number(r.live_unowned), 0,
      `${r.live_unowned} queued/running/ok step run(s) are addressed to an actor that resolves to `
      + 'nobody - that work can never be picked up');
  });

  test(`${name}: a new step run CANNOT be queued to an identity nobody models`, async () => {
    // Zero live rows cannot tell a working guard from an idle table. Force it.
    const r = await post(ref, `do $$
declare v_run uuid;
begin
  select id into v_run from workflow_run limit 1;
  if v_run is null then raise exception 'PROBE SKIP no workflow_run to attach to'; end if;
  insert into workflow_step_run (workflow_run_id, step_no, actor, status)
  values (v_run, 9999, 'Director', 'queued');
  raise exception 'GUARD DID NOT FIRE';
end $$;`);
    if (/PROBE SKIP/.test(r.text)) return;
    assert.doesNotMatch(r.text, /GUARD DID NOT FIRE/,
      'a step run was queued with actor "Director", which resolves to no employee');
    assert.match(r.text, /resolves to no employee/i, `unexpected refusal text: ${r.text}`);
  });

  test(`${name}: no active role has zero workflow callers`, async () => {
    // A role named by no step, no routine, no cron, no executor and no tool grant is a row, not a
    // job. Measured over workflow_step and employee_workflow here; the full seven-surface census
    // is scripts/agents/role_caller_census.mjs.
    const rows = await q(ref, `
      select r.role_id from org_role r
       where r.runtime_mode <> 'knowledge_overlay' and r.status = 'active'
         and not exists (select 1 from workflow_step s
                          where coalesce(fn_org_agent_resolve(s.actor_role), fn_org_role_resolve(s.actor_role))
                                = r.runtime_agent_key)
         and not exists (select 1 from employee_workflow w where w.agent_key = r.runtime_agent_key)
       order by 1`);
    assert.deepEqual(rows.map((x) => x.role_id), [],
      'roles no workflow calls: ' + rows.map((x) => x.role_id).join(', '));
  });

  test(`${name}: every workflow has exactly one accountable owner`, async () => {
    // employee_task is the deliberate exception and the reason is in its name: it is the generic
    // per-employee task loop, so every employee owns their own instance of it. Everywhere else,
    // two owners means the next reader has to guess which one is accountable.
    const rows = await q(ref, `
      select workflow_key, count(*) owners, string_agg(agent_key, ' ') who
        from employee_workflow
       where role_in_workflow = 'owner' and workflow_key <> 'employee_task'
       group by 1 having count(*) <> 1 order by 1`);
    assert.deepEqual(rows, [],
      'workflows with more or fewer than one accountable owner: '
      + rows.map((r) => `${r.workflow_key}=${r.owners} (${r.who})`).join('; '));
  });

  test(`${name}: every active role has tools, knowledge, authority, forbidden decisions and a KPI`, async () => {
    // FOUNDER-APPROVED DEFERRALS ARE SUBTRACTED BY NAME, NOT WAVED THROUGH BY LOOSENING THE RULE.
    //
    // 18 AUG 2026. This counted 1 active role with no_tools and failed. The role is
    // product_ux_designer, and its four gaps — no_tools, no_knowledge, no_authority, no_kpi — are
    // recorded verbatim in the founder-approved Phase A baseline (org_phase_baseline where
    // phase='A', deferred[]), whose own note says: "The four deferred items are runtime-readiness
    // for product_ux_designer; they are NOT Phase A defects and must not be hidden or marked
    // complete." fn_phase_a_baseline_drift() is 0. The test simply did not know the baseline
    // existed, so an approved deferral read as a defect on every run.
    //
    // The exclusion is per (rule, role) from that baseline — never a blanket allowance, never a
    // hard-coded role name here. Adding an entry to that list needs `set local
    // app.phase_a_change_reason` and a real change request, so this cannot be used to wave through
    // a new gap. And the deferred items are PRINTED below, so subtracting them is not hiding them.
    const r = await one(ref, `
      with deferred as (select * from public.fn_org_role_deferred())
      select
        count(*) filter (where coalesce(array_length(tools,1),0) = 0
          and not exists (select 1 from deferred d where d.rule='no_tools' and d.role_id=org_role.role_id))     no_tools,
        count(*) filter (where coalesce(array_length(knowledge_scopes,1),0) = 0
          and not exists (select 1 from deferred d where d.rule='no_knowledge' and d.role_id=org_role.role_id)) no_knowledge,
        count(*) filter (where coalesce(array_length(forbidden_decisions,1),0) = 0)                             no_forbidden,
        count(*) filter (where authority_level is null
          and not exists (select 1 from deferred d where d.rule='no_authority' and d.role_id=org_role.role_id)) no_authority,
        count(*) filter (where not exists (select 1 from employee_kpi k
                                            where k.agent_key = org_role.runtime_agent_key and k.active)
          and not exists (select 1 from deferred d where d.rule='no_kpi' and d.role_id=org_role.role_id))       no_kpi
      from org_role where runtime_mode <> 'knowledge_overlay' and status = 'active'`);
    const [def] = await q(ref, 'select coalesce(string_agg(token, \'; \' order by token), \'(none)\') t '
      + 'from public.fn_org_role_deferred()');
    console.log(`      founder-approved deferrals, excluded and still owed: ${def.t}`);
    for (const [k, v] of Object.entries(r)) assert.equal(Number(v), 0, `${v} active roles have ${k}`);
  });

  test(`${name}: the 86 category overlays stay on demand - none has a runtime agent`, async () => {
    const r = await one(ref, `
      select count(*) overlays, count(runtime_agent_key) with_runtime_agent
        from org_role where runtime_mode = 'knowledge_overlay' and role_id like 'category_overlay_%'`);
    assert.equal(Number(r.overlays), 86, 'the overlay count has moved from 86');
    assert.equal(Number(r.with_runtime_agent), 0,
      'a category overlay has been given a runtime agent - it is now a permanent employee');
  });

  test(`${name}: the four broad specialists cannot stand in for a category overlay`, async () => {
    const rows = await q(ref, `
      select role_id, runtime_mode, array_to_string(forbidden_decisions,' | ') fd
        from org_role where role_id in ('spec_mep','spec_construction','spec_fitout','spec_industrial')
        order by role_id`);
    assert.equal(rows.length, 4, 'one of the four broad technical specialists is missing');
    for (const r of rows) {
      assert.equal(r.runtime_mode, 'on_demand_specialist',
        `${r.role_id} is ${r.runtime_mode}; a broad specialist must run only when the workflow needs it`);
      assert.match(r.fd, /duplicating a category question bank/i,
        `${r.role_id} is not forbidden from duplicating an overlay's question bank`);
      assert.match(r.fd, /replacing the category specialist/i,
        `${r.role_id} is not forbidden from replacing the category specialist`);
      assert.match(r.fd, /dispatch/i, `${r.role_id} is not forbidden from dispatching`);
    }
  });

  test(`${name}: the creator of an artifact cannot be its final approver`, async () => {
    const r = await one(ref, `
      select
        (select array_to_string(tools,' ') from org_role where role_id = 'visual_design')            vd_tools,
        (select array_to_string(forbidden_decisions,' | ') from org_role where role_id='visual_design') vd_forbidden,
        (select authority_level from org_role where role_id = 'visual_design')                       vd_authority,
        (select authority_level from org_role where role_id = 'test_automation_engineer')            ta_authority,
        (select array_to_string(owned_decisions,' | ') from org_role where role_id='test_automation_engineer') ta_owned,
        (select array_to_string(owned_decisions,' | ') from org_role where role_id='quality_and_release_director') qa_owned`);
    assert.doesNotMatch(r.vd_tools, /artifact\.review/,
      'the Visual Design Specialist holds the artifact.review tool - it can approve its own rendered work');
    assert.match(r.vd_forbidden, /approving the rendered artifact it produced/i,
      'the Visual Design Specialist is not forbidden from approving its own artifact');
    assert.equal(r.vd_authority, 'advisory', 'the Visual Design Specialist holds more than advisory authority');
    assert.equal(r.ta_authority, 'execute_low',
      'the Test Automation Engineer still holds stop authority - it can veto a release on its own evidence');
    assert.doesNotMatch(r.ta_owned, /blocking a release/i,
      'the Test Automation Engineer still owns "blocking a release"; that is the QA director\'s decision');
    assert.match(r.qa_owned, /release go\/no-go/i,
      'the QA & Release Management Director no longer owns release go/no-go');
  });

  test(`${name}: the six reviewer scopes do not overlap`, async () => {
    // Each reviewer must forbid what the others own. Checked as a matrix rather than by reading
    // the prose: an overlap is two reviewers owning the same decision text.
    const rows = await q(ref, `
      select role_id, array_to_string(owned_decisions,' | ') owned, array_to_string(forbidden_decisions,' | ') forbidden
        from org_role
       where role_id in ('model_evaluator','ai_quality_reviewer','quality_and_release_director',
                         'knowledge_validator','compliance_and_privacy_officer',
                         'marketplace_content_privacy_reviewer')
       order by role_id`);
    assert.equal(rows.length, 6, 'one of the six named reviewer scopes does not exist');
    for (const r of rows) {
      assert.ok(r.owned && r.owned.length > 10, `${r.role_id} owns nothing specific`);
      assert.ok(r.forbidden && r.forbidden.length > 10, `${r.role_id} forbids nothing`);
      assert.match(r.forbidden, /that is the|- that is|under any alias|it authored|it produced|it validates|it evaluates|it rules on/i,
        `${r.role_id} does not name another reviewer's territory as out of scope`);
    }
    // release go/no-go is owned by exactly one of them.
    const owners = rows.filter((r) => /release go\/no-go/i.test(r.owned)).map((r) => r.role_id);
    assert.deepEqual(owners, ['quality_and_release_director'],
      `release go/no-go is owned by ${owners.length} reviewers: ${owners.join(', ')}`);
  });

  test(`${name}: no role may OWN a founder-reserved decision, and the guard fires`, async () => {
    const held = await q(ref, `
      select r.role_id, d.decision_key
        from org_role r, founder_reserved_decision d, unnest(d.match_any) m(needle)
       where position(m.needle in lower(array_to_string(r.owned_decisions,' | '))) > 0`);
    assert.deepEqual(held, [], 'a role owns a founder-reserved decision: ' + JSON.stringify(held));

    // Forced to fire: a new branch returning zero proves nothing.
    const r = await post(ref, `do $$
begin
  update org_role set owned_decisions = array['set the reveal fee percentage'] where role_id = 'ceo';
  raise exception 'GUARD DID NOT FIRE';
end $$;`);
    assert.doesNotMatch(r.text, /GUARD DID NOT FIRE/,
      'the AI CEO was allowed to own the reveal fee - the founder-reserved guard is not enforcing');
    assert.match(r.text, /founder-reserved decision/i, `unexpected refusal text: ${r.text}`);
  });

  test(`${name}: the founder settings channel exposes no reserved commercial decision`, async () => {
    // EXISTING_BETTER_KEEP, verified rather than asserted: fn_founder_apply_setting only accepts
    // keys fn_founder_settings() returns, and none of them is a reserved commercial item.
    const rows = await q(ref, `
      select s.setting_key from fn_founder_settings() s, founder_reserved_decision d, unnest(d.match_any) m(needle)
       where position(m.needle in lower(s.setting_key)) > 0
          or position(m.needle in lower(coalesce(s.description,''))) > 0`);
    assert.deepEqual(rows, [],
      'a founder-reserved decision is changeable from the settings channel: ' + JSON.stringify(rows));
  });

  test(`${name}: UAE tax responsibility is explicit and is an overlay, not a new employee`, async () => {
    const r = await one(ref, `
      select
        (select responsibilities from org_role where role_id = 'financial_controller')       fc,
        (select array_to_string(knowledge_scopes,' ') from org_role where role_id='financial_controller') fc_ks,
        (select runtime_mode from org_role where role_id = 'tax_overlay_uae')                overlay_mode,
        (select runtime_agent_key from org_role where role_id = 'tax_overlay_uae')           overlay_agent,
        (select count(*) from org_agents where active)                                       active_agents`);
    assert.match(r.fc, /UAE tax is within approved scope/i,
      'the Financial Controller\'s scope does not mention UAE tax');
    for (const w of ['VAT', 'corporate', 'revenue recognition', 'filing calendar', 'taxable-supply']) {
      assert.match(r.fc, new RegExp(w, 'i'), `the Financial Controller's scope omits ${w}`);
    }
    assert.match(r.fc_ks, /tax_uae/, 'the Financial Controller has no UAE tax knowledge scope');
    assert.equal(r.overlay_mode, 'knowledge_overlay', 'the UAE tax capability is not an overlay');
    assert.equal(r.overlay_agent, null,
      'the UAE tax overlay has a runtime agent - it has become another persistent employee');
    // 6 SEP 2026: the headcount this guards is the Phase A frozen one, not a literal from before the
    // 3 Sep 2026 re-carve (PACR-004 took the company from 90 to 54 active employees under the freeze
    // guard). The point stands — the tax capability is an overlay and adds nobody — so the count is
    // compared with what org_agents held at the freeze, read from the same table the guard protects.
    assert.equal(Number(r.active_agents), 54,
      `the active employee count moved to ${r.active_agents}; the tax capability was supposed to add none (54 since PACR-004)`);
  });

  // -------------------------------------------------------------------------------------------
  // the thirteen scenarios
  // -------------------------------------------------------------------------------------------
  for (const s of SCENARIOS) {
    test(`${name}: workflow ${s.n} - ${s.name}`, async () => {
      const steps = await q(ref, `
        select step_no, actor_role,
               coalesce(fn_org_agent_resolve(actor_role), fn_org_role_resolve(actor_role)) resolved
          from workflow_step where workflow_key = ${lit(s.workflow)} order by step_no`);
      assert.ok(steps.length, `${s.workflow} has no steps`);

      // Each named owner appears, resolves, and appears in the founder's order.
      let previous = -1;
      for (const owner of s.owners) {
        const canon = await one(ref, `select coalesce(fn_org_agent_resolve(${lit(owner)}),
                                                      fn_org_role_resolve(${lit(owner)})) k`);
        assert.ok(canon.k, `${owner} resolves to nobody`);
        const at = steps.findIndex((st) => st.resolved === canon.k && st.step_no > previous);
        assert.ok(at >= 0,
          `${s.workflow} has no step owned by ${owner} after step ${previous} - the founder's chain `
          + `puts it there. Steps present: ` + steps.map((x) => `${x.step_no}:${x.resolved}`).join(' '));
        previous = steps[at].step_no;
      }

      // No step in the chain is owned by an overlay: an overlay has no runtime agent and cannot be
      // accountable for anything. This is how "domain specialist" came to own supplier selection.
      const overlayOwned = await q(ref, `
        select s.step_no, s.actor_role from workflow_step s join org_role r on r.role_id = s.actor_role
         where s.workflow_key = ${lit(s.workflow)} and r.runtime_mode = 'knowledge_overlay'`);
      assert.deepEqual(overlayOwned, [],
        `${s.workflow} has a step owned by a knowledge overlay: ` + JSON.stringify(overlayOwned));
    });
  }

  // -------------------------------------------------------------------------------------------
  // the two guards on the dispatch path, forced to fire
  // -------------------------------------------------------------------------------------------
  test(`${name}: an ineligible supplier is refused at assignment, and an eligible one is not`, async () => {
    // The instruction requires every supplier to be validated IMMEDIATELY BEFORE assignment, not
    // only at routing time. a00_unsafe_match_eligibility already does this and this proves it: the
    // refusal is silent (the trigger returns null, so PostgREST answers 201 with no row), which is
    // exactly why dispatch_inquiry now counts rows landed rather than absence of an error.
    const r = await post(ref, `do $$
declare v_bad bigint; v_ok bigint; v_inq uuid; v_bad_rows int; v_ok_rows int;
begin
  select id into v_bad from leads where coalesce(banned,false) or coalesce(matching_blocked,false)
     or coalesce(permanently_closed,false) or (license_expiry is not null and license_expiry < current_date) limit 1;
  select id into v_ok  from leads where not coalesce(banned,false) and not coalesce(matching_blocked,false)
     and not coalesce(permanently_closed,false) and (license_expiry is null or license_expiry >= current_date)
     and id not in (select supplier_id from inquiry_matches) limit 1;
  select id into v_inq from inquiries where rfq_ready limit 1;
  if v_bad is null or v_ok is null or v_inq is null then
    raise exception 'PROBE SKIP no fixture (bad=% ok=% inq=%)', v_bad, v_ok, v_inq;
  end if;
  begin insert into inquiry_matches (inquiry_id, supplier_id, similarity, match_reason, sent_at)
        values (v_inq, v_bad, 0.9, 'PROBE ineligible', now()); exception when others then null; end;
  select count(*) into v_bad_rows from inquiry_matches where inquiry_id=v_inq and supplier_id=v_bad;
  begin insert into inquiry_matches (inquiry_id, supplier_id, similarity, match_reason, sent_at)
        values (v_inq, v_ok, 0.9, 'PROBE eligible', now()); exception when others then null; end;
  select count(*) into v_ok_rows from inquiry_matches where inquiry_id=v_inq and supplier_id=v_ok;
  raise exception 'PROBE ineligible_landed=% eligible_landed=%', v_bad_rows, v_ok_rows;
end $$;`);
    if (/PROBE SKIP/.test(r.text)) {
      // Production carries no inquiries at all, so this fixture cannot exist there. Saying so is
      // the honest outcome; asserting a pass on absent data is how a check comes to mean nothing.
      assert.match(r.text, /PROBE SKIP/, r.text);
      return;
    }
    const m = /PROBE ineligible_landed=(\d+) eligible_landed=(\d+)/.exec(r.text);
    assert.ok(m, `probe produced no counts: ${r.text}`);
    assert.equal(m[1], '0', 'an ineligible supplier was assigned an inquiry');
    assert.equal(m[2], '1', 'an ELIGIBLE supplier was refused - the guard is refusing everything');
  });

  test(`${name}: the two money ledgers price a call identically`, async () => {
    // fn_llm_log carries its AED arithmetic inline; fn_usd_to_aed names the same peg for the
    // per-attempt ledger. Two pricing implementations drift, so this re-derives the ratio from
    // what fn_llm_log actually produces rather than trusting a constant. Run in an aborted
    // transaction so the probe row never lands in ai_cost_log.
    const r = await post(ref, `do $$
declare v_aed numeric; v_usd numeric; v_model text;
begin
  select model_used into v_model from ai_cost_log where cost_aed > 0 order by occurred_at desc limit 1;
  if v_model is null then raise exception 'PROBE SKIP no priced call to derive the ratio from'; end if;
  select fn_llm_log('probe',null,null,'general',v_model,'probe','medium',100000,10000,false,null,10,true) into v_aed;
  select fn_model_cost_usd(v_model, 100000, 10000, 0) into v_usd;
  raise exception 'PROBE ledger_ratio=% named_peg=%',
    round(v_aed / nullif(v_usd,0), 6), round(fn_usd_to_aed(), 6);
end $$;`);
    if (/PROBE SKIP/.test(r.text)) return;
    const m = /PROBE ledger_ratio=([\d.]+) named_peg=([\d.]+)/.exec(r.text);
    assert.ok(m, `probe produced no ratio: ${r.text}`);
    // Compared to three decimals, not exactly. fn_llm_log rounds the AED it returns, so the
    // derived ratio carries that rounding and an exact match would fail on noise rather than on
    // a real disagreement. Three decimals still catches any actual change of peg.
    const [ledger, peg] = [Number(m[1]), Number(m[2])];
    assert.ok(Math.abs(ledger - peg) < 0.001,
      `ai_cost_log prices a call at ${ledger} AED/USD and llm_attempt at ${peg} - the two ledgers `
      + 'disagree about what the same call cost');
  });

  test(`${name}: a model call records its tokens and its cost against the role`, () => {
    const src = readFileSync('supabase/functions/ai_gateway/index.ts', 'utf8');
    assert.match(src, /prompt_tokens: u\?\.prompt_tokens/,
      'the gateway records an attempt without its token usage again, so a retry on the fallback '
      + 'ladder costs real money that is attributable to nothing');
    assert.match(src, /recordAttempt\(m, true, Date\.now\(\) - attemptStartedAt, '', finishReason, j\?\.usage\)/,
      'the successful attempt is recorded without passing the usage block it has in scope');
  });

  test(`${name}: dispatch counts rows that landed, not the absence of an error`, () => {
    const src = readFileSync('supabase/functions/dispatch_inquiry/index.ts', 'utf8');
    assert.match(src, /\.select\('id'\)/,
      'the inquiry_matches insert does not select back what landed; a supplier the eligibility '
      + 'guard silently refused would be counted as notified and the RFQ would never be retried');
    assert.match(src, /excluded\.push/,
      'dispatch_inquiry records no exclusion ledger - "why did this supplier not get it" is the '
      + 'question the operator exists to answer');
    assert.match(src, /const OWNER_ROLE = 'spec_commercial'/,
      'dispatch_inquiry no longer names its accountable role');
    assert.doesNotMatch(src, /agent: 'operations_ai'/,
      'the coverage gap is attributed to operations_ai again, which resolves to the Operations '
      + 'Director - a different department from the work');
  });
}
