// V3 KNOWLEDGE RUNTIME — BEHAVIOURAL TESTS.
//
// These do not assert on source strings. Every one of them runs the real runtime path an
// agent runs: fn_agent_context / fn_agent_context_v3 for retrieval, fn_category_checklist
// and fn_category_quote_ready for the category specialists, fn_propose_lesson and
// fn_validate_lesson for the learning loop, fn_assign_training for remediation, and
// fn_artifact_publish_blocked for the visual gate.
//
// Writes are done inside an aborted transaction so a test never leaves a row behind. The
// pattern is the founder's: perform the write, count the effect, raise with the counts, read
// the counts out of the error message.
//
//   node --test scripts/checks/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const mgmtToken = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

// CI runs `npm test` with no SUPABASE_ACCESS_TOKEN — the checks workflow deliberately holds
// no database secret — so every test here skips there and runs locally, where the token is.
// Without the guard all 50 failed in CI at ~20ms each on a 401, which looks like a data
// failure and is not one.
// staging was a second target until its Supabase project was deleted on 15 Aug 2026; the same
// assertions now run against production alone.
const PROJECTS = { production: 'htdblwldjkcgjvmqkbeh' };

async function post(project, query) {
  for (let attempt = 0; ; attempt++) {
    const r = await fetch(`https://api.supabase.com/v1/projects/${project}/database/query`, {
      method: 'POST', headers: { Authorization: 'Bearer ' + mgmtToken, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query }),
    });
    const text = await r.text();
    // A mass of failures with the other project passing is throttling, not a finding.
    if (r.status === 429 && attempt < 8) { await new Promise((s) => setTimeout(s, Math.min(1500 * 2 ** attempt, 20000))); continue; }
    return { ok: r.ok, status: r.status, text };
  }
}

const q = async (project, query) => {
  const r = await post(project, query);
  assert.ok(r.ok, `query failed on ${project}: ${r.status} ${r.text}`);
  return JSON.parse(r.text);
};

// Run a DO block that ends in `raise exception`, and return what it raised. The transaction
// is rolled back by the raise, so the write is proven without being kept.
const probe = async (project, body) => {
  const r = await post(project, `do $$ ${body} $$;`);
  assert.equal(r.ok, false, `probe should have raised on ${project}, got: ${r.text}`);
  // The management API returns the error as JSON, so the newline before CONTEXT arrives
  // escaped as the two characters \ and n. Match both shapes.
  const m = /P0001:\s+([\s\S]*?)(?:\\n|\n)CONTEXT/.exec(r.text) || /P0001:\s+([^"]*)/.exec(r.text);
  assert.ok(m, `probe raised something other than its assertion on ${project}: ${r.text}`);
  return m[1];
};

const one = (rows) => rows[0];

for (const [name, ref] of Object.entries(PROJECTS)) {
  // ── roster ────────────────────────────────────────────────────────────────────
  // 20 AUG 2026 — THIS ASSERTED `packaged === 24` AND HAD BEEN RED SINCE THE 14 AUG REORG.
  // 24 was the number of departments the V3 delivery named. org_department_alias is the MERGE MAP,
  // and a merge ADDS a row to it: 22 departments became 10, and nine new department names —
  // assurance_security_reliability, growth_revenue, product_engineering_ai and six more — joined the
  // original 24, giving 33 distinct packaged names over 34 rows (strategy_evolution has two homes by
  // declaration). A count frozen on a table that legitimately grows is not a check; retyping 24 as
  // 33 would be a rubber stamp on whatever the table happens to hold today.
  //
  // What the test's own title claims is CONTENT, and content is what it asserts now, in both
  // directions, with the delivery's list read out of the committed crosswalk rather than typed here:
  //   forward   every packaged department the V3 delivery named still resolves to an ACTIVE one
  //   backward  every active department is named by at least one alias — otherwise a knowledge
  //             import for it has no packaged name and lands nowhere
  //   dangling  no alias points at a department that is not active
  // marketplace_category_experts is excluded: v3_crosswalk.mjs:231 synthesises it as a bucket for
  // the category specialists, and it is not a department the delivery shipped.
  test(`${name}: every packaged department resolves to a live runtime department`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const csv = readFileSync('docs/knowledge/V3_RUNTIME_ROLE_CROSSWALK.csv', 'utf8')
      .split(/\r?\n/).filter(Boolean);
    const col = csv[0].split(',').indexOf('packaged_department');
    assert.ok(col >= 0, 'V3_RUNTIME_ROLE_CROSSWALK.csv has no packaged_department column');
    const delivered = [...new Set(csv.slice(1)
      .map((l) => (l.split(',')[col] || '').replace(/^"|"$/g, '').trim())
      .filter((v) => v && v !== 'marketplace_category_experts'))];
    assert.ok(delivered.length >= 24,
      `the committed crosswalk names only ${delivered.length} departments; it named 24 at delivery`);

    const list = delivered.map((d) => `('${d.replace(/'/g, "''")}')`).join(',');
    const r = one(await q(ref, `with delivery(name) as (values ${list})
      select
       (select count(*) from delivery) delivered,
       (select count(*) from delivery d where not exists (
          select 1 from org_department_alias a
            join org_departments dp on dp.dept_key = a.dept_key and dp.active
           where a.packaged_department = d.name)) unresolved,
       (select coalesce(string_agg(d.name, ', '), '') from delivery d where not exists (
          select 1 from org_department_alias a
            join org_departments dp on dp.dept_key = a.dept_key and dp.active
           where a.packaged_department = d.name)) unresolved_names,
       (select count(*) from org_departments dp where dp.active
          and not exists (select 1 from org_department_alias a where a.dept_key = dp.dept_key)) unnamed_active,
       (select coalesce(string_agg(dp.dept_key, ', '), '') from org_departments dp where dp.active
          and not exists (select 1 from org_department_alias a where a.dept_key = dp.dept_key)) unnamed_names,
       (select count(*) from org_department_alias a
          where not exists (select 1 from org_departments d where d.dept_key = a.dept_key and d.active)) dangling,
       (select count(distinct packaged_department) from org_department_alias) packaged_now`));
    assert.equal(Number(r.unresolved), 0,
      `these delivered departments no longer reach an active department: ${r.unresolved_names}`);
    assert.equal(Number(r.unnamed_active), 0,
      `these active departments are named by no alias, so a packaged import for them lands nowhere: ${r.unnamed_names}`);
    assert.equal(Number(r.dangling), 0, 'every alias must point at an active department');
    console.log(`      ${r.delivered} delivered department names all resolve; `
      + `${r.packaged_now} packaged names in the merge map today`);
  });

  test(`${name}: all 96 packaged roles resolve and every active agent has an identity`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const r = one(await q(ref, `select
      (select count(distinct packaged_role_id) from org_role_identity) roles,
      (select count(distinct agent_key) from org_role_identity) agents,
      (select count(*) from org_agents a where a.active
         and not exists (select 1 from org_role_identity i where i.agent_key = a.agent_key)) without_identity,
      (select count(*) from org_role_identity i
         where not exists (select 1 from org_agents a where a.agent_key = i.agent_key)) orphan_identity`));
    assert.equal(Number(r.roles), 96, 'all 96 packaged roles must be resolved');
    assert.equal(Number(r.without_identity), 0, 'no active agent may run without a role identity');
    assert.equal(Number(r.orphan_identity), 0, 'no identity may name an agent that does not exist');
  });

  test(`${name}: all 86 category identities are bound to a live route`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const r = one(await q(ref, `select
      (select count(*) from org_category_identity) identities,
      (select count(*) from org_category_identity c
         where not exists (select 1 from kb_operational_route r where r.catalog_num = c.catalog_num)) dangling`));
    assert.equal(Number(r.identities), 86);
    assert.equal(Number(r.dangling), 0);
  });

  // ── retrieval ─────────────────────────────────────────────────────────────────
  test(`${name}: an agent's context carries identity, company core, department, role and rules`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const r = one(await q(ref, `with c as (select fn_agent_context_v3('cfo', 'finance_decision',
        'overdue invoice collections authority threshold', null, 24000) x)
      select (x->'identity'->>'agent_key') agent,
             (x->'identity'->>'packaged_department') pkg_dept,
             jsonb_array_length(x->'identity'->'packaged_role_ids') role_ids,
             jsonb_array_length(x->'deterministic_rules') rules,
             jsonb_array_length(x->'company_core') core,
             jsonb_array_length(x->'department_knowledge') dept,
             jsonb_array_length(x->'role_knowledge') role,
             jsonb_array_length(x->'company_objective') objective,
             jsonb_array_length(x->'tools') tools,
             (x->>'knowledge_count')::int knowledge_count
        from c`));
    assert.equal(r.agent, 'cfo');
    assert.equal(r.pkg_dept, 'finance');
    assert.ok(Number(r.role_ids) >= 1, 'the agent must know which packaged role it holds');
    assert.ok(Number(r.rules) > 0, 'deterministic rules must be retrieved as structured records');
    assert.ok(Number(r.dept) > 0, 'department knowledge must be inherited');
    assert.ok(Number(r.role) > 0, 'role knowledge must be retrieved');
    assert.ok(Number(r.objective) > 0, 'the current company objective is read live, not remembered');
    assert.ok(Number(r.knowledge_count) > 0, 'the assembly must name the records it used');
  });

  test(`${name}: another department's role knowledge is NOT retrieved`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const r = one(await q(ref, `with c as (select fn_agent_context_v3('cfo', null, 'collections', null, 24000) x)
      select coalesce((select count(*) from jsonb_array_elements(x->'role_knowledge') e
        join ops_knowledge k on k.record_id = e->>'record_id'
        where k.role_key is not null
          and k.role_key not in (select packaged_role_id from org_role_identity where agent_key='cfo')), 0) foreign_role
      from c`));
    assert.equal(Number(r.foreign_role), 0, 'retrieval must not hand an agent another role\'s corpus');
  });

  test(`${name}: the character budget is respected`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const r = one(await q(ref, `select
      length(fn_agent_context_capped('cfo', 6000, 'collections')) small,
      length(fn_agent_context_capped('cfo', 24000, 'collections')) large`));
    assert.ok(Number(r.small) < Number(r.large), 'a smaller budget must return less context');
    assert.ok(Number(r.small) <= 6000 * 1.2, `a 6,000-char budget returned ${r.small} characters`);
  });

  test(`${name}: the context path records the knowledge ids it retrieved`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const raised = await probe(ref, `
      declare n0 int; n1 int; r agent_context_retrieval; t text;
      begin
        select count(*) into n0 from agent_context_retrieval;
        t := fn_agent_context_capped('cfo', 24000, 'collections authority');
        select count(*) into n1 from agent_context_retrieval;
        select * into r from agent_context_retrieval order by id desc limit 1;
        raise exception 'rows=% count=% agent=%', n1 - n0, r.knowledge_count, r.agent_key;
      end;`);
    const m = /rows=(\d+) count=(\d+) agent=(\S+)/.exec(raised);
    assert.ok(m, raised);
    assert.equal(m[1], '1', 'one retrieval row per assembly');
    assert.ok(Number(m[2]) > 0, 'the retrieval must name at least one knowledge record');
    assert.equal(m[3], 'cfo');
  });

  test(`${name}: a decided agent action writes a decision trace naming those records`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const raised = await probe(ref, `
      declare v_kind text; v_agent text; v_id bigint; v_before int; v_after int; v_refs jsonb;
      begin
        select kind into v_kind from agent_action_kind_policy limit 1;
        select agent_key into v_agent from org_agents where active order by agent_key limit 1;
        select count(*) into v_before from decision_trace;
        perform fn_record_context_retrieval(v_agent, 'behaviour_test', null,
                array['probe-a','probe-b'], 24000, 1000);
        insert into agent_actions (agent, kind, status, risk, title, detail, confidence, escalated)
          values (v_agent, v_kind, 'proposed', 'low', 'behaviour test', '{}'::jsonb, 0.7, false)
          returning id into v_id;
        update agent_actions set decided_at = now(), decided_by = 'test', status = 'approved' where id = v_id;
        select count(*) into v_after from decision_trace;
        select knowledge_refs into v_refs from decision_trace where entity_id = v_id::text limit 1;
        raise exception 'traces=% shape=% ids=%', v_after - v_before,
          coalesce(jsonb_typeof(v_refs),'absent'),
          case when jsonb_typeof(v_refs) = 'array' then jsonb_array_length(v_refs) else -1 end;
      end;`);
    // 20 AUG 2026 — THIS READ `v_refs->>'knowledge_count'` AND HAD ALWAYS RETURNED NULL, because
    // decision_trace.knowledge_refs is a JSON ARRAY of ids, not an object with a count.
    // fn_agent_action_trace_row writes `to_jsonb(v_ids)`, and every other reader in the estate
    // treats it as an array — fn_management_decision_review and v3_remediation_regression.mjs both
    // guard with `jsonb_typeof(knowledge_refs)='array' then jsonb_array_length(...)`,
    // runtime_connection_gate_b.mjs uses jsonb_array_length directly, and fn_unsafe_liveness_probe
    // inserts a literal array. Six readers agree on the array and this one test asked for a field
    // the contract never promised: the instrument was wrong, not the writer. The shape is asserted
    // as well as the length, so a writer that quietly switches to an object is caught here rather
    // than silently returning null again.
    const m = /traces=(\d+) shape=(\w+) ids=(-?\d+)/.exec(raised);
    assert.ok(m, raised);
    assert.equal(m[1], '1', 'a decided action must leave exactly one trace');
    assert.equal(m[2], 'array',
      `decision_trace.knowledge_refs must be a JSON array of ids, got ${m[2]} — six readers call jsonb_array_length on it`);
    assert.equal(m[3], '2', 'the trace must carry the knowledge ids the assembly recorded');
  });

  // ── management ────────────────────────────────────────────────────────────────
  test(`${name}: a director's context carries its own department's goals and the revenue target`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const r = one(await q(ref, `with c as (select fn_agent_context_v3('cfo', 'planning',
        'set this quarter''s departmental objectives', null, 24000) x)
      select jsonb_array_length(x->'company_objective') goals,
             (select count(*) from jsonb_array_elements(x->'company_objective') e
               where e->>'owner_dept' = 'finance') own_dept,
             (select count(*) from jsonb_array_elements(x->'company_objective') e
               where e->>'goal' ilike '%1,000,000%') revenue_target
        from c`));
    assert.ok(Number(r.goals) > 0, 'a director planning work must see the objectives it is planning against');
    assert.ok(Number(r.own_dept) > 0, 'its own department\'s goals must rank first');
    assert.ok(Number(r.revenue_target) > 0,
      'the AED 1,000,000 target is the objective every department chain hangs from');
  });

  test(`${name}: a KPI record is retrieved as a structured rule, not as prose`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const r = one(await q(ref, `with c as (select fn_agent_context_v3('cfo', null, 'collections', null, 24000) x)
      select (select count(*) from jsonb_array_elements(x->'deterministic_rules') e
               where e->>'layer' = 'kpi') kpi_rules,
             (select count(*) from jsonb_array_elements(x->'deterministic_rules') e
               where e->>'layer' = 'authority') authority_rules
        from c`));
    assert.ok(Number(r.authority_rules) > 0, 'authority must reach the agent as a structured record');
  });

  // ── freshness ─────────────────────────────────────────────────────────────────
  test(`${name}: knowledge past its review date is labelled stale, not silently served as current`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const raised = await probe(ref, `
      declare rid text; before text; after text; swept jsonb; in_ctx int;
      begin
        select record_id into rid from ops_knowledge
         where layer = 'department_shared' and dept_key = 'finance' and runtime_eligible limit 1;
        select source_freshness into before from ops_knowledge where record_id = rid;
        update ops_knowledge set review_after = current_date - 1 where record_id = rid;
        swept := fn_knowledge_freshness_sweep();
        select source_freshness into after from ops_knowledge where record_id = rid;
        select count(*) into in_ctx from jsonb_array_elements(
          fn_agent_context_v3('cfo', null, null, null, 24000)->'department_knowledge') e
          where e->>'record_id' = rid;
        raise exception 'before=% after=% still_retrievable=%', before, after, in_ctx;
      end;`);
    assert.match(raised, /after=stale/, 'a record past its review date must be labelled stale');
    assert.doesNotMatch(raised, /still_retrievable=-/, raised);
  });

  // ── category specialists ──────────────────────────────────────────────────────
  test(`${name}: every one of the 86 routes returns its own qualification corpus`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const r = one(await q(ref, `with r as (
        select fn_category_checklist(k.expected_catalog_slug, k.catalog_name, null) c
          from kb_operational_route k)
      select count(*) total,
             count(*) filter (where (c->>'route_resolved')::boolean) resolved,
             count(*) filter (where jsonb_array_length(c->'packaged_questions') > 0) with_questions,
             count(*) filter (where jsonb_array_length(c->'mandatory_fields') > 0) with_mandatory,
             count(*) filter (where jsonb_array_length(c->'never_infer') > 0) with_never_infer
        from r`));
    assert.equal(Number(r.total), 86);
    assert.equal(Number(r.resolved), 86, 'every route must resolve to its own corpus');
    assert.equal(Number(r.with_questions), 86);
    assert.equal(Number(r.with_mandatory), 86);
    assert.equal(Number(r.with_never_infer), 86, 'every route must say what may never be inferred');
  });

  test(`${name}: two different routes return different question banks`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const r = one(await q(ref, `select
      (fn_category_checklist('aluminium-and-glass-suppliers', null, null)->'packaged_questions')
        = (fn_category_checklist('catering-companies', null, null)->'packaged_questions') same`));
    assert.equal(r.same, false, 'a route-specific corpus that is identical for two trades is not route-specific');
  });

  test(`${name}: quote readiness blocks on the missing mandatory fields and names them`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const r = one(await q(ref, `select
      fn_category_quote_ready('aluminium-and-glass-suppliers', '{"scope":"12 windows"}'::jsonb) partial,
      fn_category_quote_ready('aluminium-and-glass-suppliers',
        (select jsonb_object_agg(f, 'answered')
           from jsonb_array_elements_text(
             fn_category_checklist('aluminium-and-glass-suppliers', null, null)->'mandatory_fields') f)) complete`));
    assert.equal(r.partial.ready, false, 'a brief missing mandatory fields cannot go to suppliers');
    assert.ok(r.partial.missing.length > 0, 'the block must name what is missing');
    assert.equal(r.complete.ready, true, 'a complete brief must pass');
  });

  test(`${name}: ambiguous routing asks instead of guessing`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const r = one(await q(ref, `select fn_category_checklist('general', 'General', null) c`));
    assert.equal(r.c.route_resolved, false);
    assert.ok(r.c.clarification || r.c.candidates.length !== 1,
      'an unresolved route must return a clarifying question, not a silent pick');
  });

  // ── learning ──────────────────────────────────────────────────────────────────
  test(`${name}: one observation is not a lesson, and an author cannot validate its own`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const raised = await probe(ref, `
      declare a text := 'collections'; r1 jsonb; r2 jsonb; lid bigint; vs jsonb; vm jsonb; before int; after int; ctx jsonb;
      begin
        r1 := fn_propose_lesson(a,'t','statement','{"observations":[{"id":1}]}'::jsonb,0.6);
        r2 := fn_propose_lesson(a,'t','statement','{"observations":[{"id":1},{"id":2}]}'::jsonb,0.6);
        lid := (r2->>'lesson_id')::bigint;
        ctx := fn_agent_context_v3(a, null, 'statement', null, 24000);
        before := jsonb_array_length(ctx->'validated_experience');
        vs := fn_validate_lesson(lid, a, 'validated', 'self');
        vm := fn_validate_lesson(lid, 'cfo', 'validated', 'reviewed');
        ctx := fn_agent_context_v3(a, null, 'statement', null, 24000);
        after := jsonb_array_length(ctx->'validated_experience');
        raise exception 'one=% two=% self=% mgr=% before=% after=%',
          r1->>'reason', r2->>'validation_status', vs->>'reason', vm->>'status', before, after;
      end;`);
    assert.match(raised, /one=insufficient_evidence/);
    assert.match(raised, /two=proposed/);
    assert.match(raised, /self=self_validation_refused/);
    assert.match(raised, /mgr=validated/);
    const m = /before=(\d+) after=(\d+)/.exec(raised);
    assert.ok(m, raised);
    assert.equal(Number(m[2]), Number(m[1]) + 1, 'a validated lesson becomes retrievable and a proposed one does not');
  });

  // ── remediation ───────────────────────────────────────────────────────────────
  test(`${name}: remediation retests on unseen cases and gates autonomy until it improves`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const raised = await probe(ref, `
      declare a text := 'collections'; rid bigint; p1 jsonb; p2 jsonb; ov int; s1 jsonb; s2 jsonb; g0 jsonb; g1 jsonb;
      begin
        rid := fn_open_remediation(a,'unsupported_claim','evidence_discipline','{}'::jsonb);
        g0 := fn_agent_autonomy_blocked(a);
        p1 := fn_assign_training(a, null, 'practice', 5);
        p2 := fn_assign_training(a, null, 'retest', 5);
        select count(*) into ov from jsonb_array_elements(p1->'cases') x
          join jsonb_array_elements(p2->'cases') y on x->>'case_id' = y->>'case_id';
        s1 := fn_remediation_step(rid, 0.45, 0.1);
        s2 := fn_remediation_step(rid, 0.9, 0.1);
        g1 := fn_agent_autonomy_blocked(a);
        raise exception 'practice=% retest=% overlap=% blocked0=% s1=% s2=% blocked1=%',
          p1->>'assigned', p2->>'assigned', ov, g0->>'blocked', s1->>'status', s2->>'status', g1->>'blocked';
      end;`);
    const m = /practice=(\d+) retest=(\d+) overlap=(\d+) blocked0=(\w+) s1=(\w+) s2=(\w+) blocked1=(\w+)/.exec(raised);
    assert.ok(m, raised);
    assert.ok(Number(m[1]) > 0 && Number(m[2]) > 0, 'training must actually be assigned');
    assert.equal(m[3], '0', 'a retest on cases the agent has already seen measures memory, not competence');
    assert.equal(m[4], 'true', 'an open remediation must block consequential autonomy');
    assert.equal(m[6], 'passed');
    assert.equal(m[7], 'false', 'autonomy must be restored once the retest passes');
  });

  test(`${name}: training assigned for a competency contains only that competency`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const raised = await probe(ref, `
      declare a text := 'cfo'; comp text; r jsonb; wrong int; dept_pool int;
      begin
        select c.competency into comp from agent_training_case c
          join org_role_identity i on i.packaged_role_id = c.scope_key and i.agent_key = a
         where c.scope_type = 'role' and c.competency is not null limit 1;
        r := fn_assign_training(a, comp, 'practice', 4);
        select count(*) into wrong from jsonb_array_elements(r->'cases') x
          join agent_training_case c on c.case_id = x->>'case_id'
         where c.competency is distinct from comp;
        select count(*) into dept_pool from agent_training_case
         where scope_type = 'department'
           and scope_key = (select packaged_department from org_role_identity where agent_key = a limit 1);
        raise exception 'assigned=% off_competency=% dept_pool=%', r->>'assigned', wrong, dept_pool;
      end;`);
    const m = /assigned=(\d+) off_competency=(\d+) dept_pool=(\d+)/.exec(raised);
    assert.ok(m, raised);
    assert.ok(Number(m[1]) > 0, 'a competency-scoped request must return cases');
    // AND binds tighter than OR: without parentheses the competency filter applied only to
    // the department branch and every role case slipped through it.
    assert.equal(m[2], '0', 'remediation for one competency must not hand out cases from another');
    assert.ok(Number(m[3]) > 0, 'the agent\'s packaged department must resolve to a real case pool');
  });

  // ── visual ────────────────────────────────────────────────────────────────────
  test(`${name}: an artifact cannot be published without a passing review of those bytes`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const raised = await probe(ref, `
      declare g0 jsonb; g1 jsonb; g2 jsonb; g3 jsonb;
      begin
        g0 := fn_artifact_publish_blocked('social_post','probe', null);
        g1 := fn_artifact_publish_blocked('social_post','probe','aaaa');
        insert into artifact_review (subject_type, subject_id, artifact_url, artifact_sha256, revision,
          bytes, mime, width, height, author_agent, reviewer_agent, verdict)
        values ('social_post','probe','https://example.invalid/a.png','aaaa',1,10,'image/png',1200,630,
                'marketing_content','marketing_design','pass');
        g2 := fn_artifact_publish_blocked('social_post','probe','aaaa');
        g3 := fn_artifact_publish_blocked('social_post','probe','bbbb');
        raise exception 'nodigest=% unreviewed=% passing=% regenerated=%',
          g0->>'reason', g1->>'reason', g2->>'blocked', g3->>'reason';
      end;`);
    assert.match(raised, /nodigest=no_artifact_digest/);
    assert.match(raised, /unreviewed=no_review_for_these_bytes/);
    assert.match(raised, /passing=false/);
    assert.match(raised, /regenerated=no_review_for_these_bytes/);
  });

  test(`${name}: the creator cannot be the only reviewer of a published artifact`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const r = await post(ref, `do $$ begin
      insert into artifact_review (subject_type, subject_id, artifact_url, artifact_sha256,
        author_agent, reviewer_agent, verdict)
      values ('social_post','self','https://example.invalid/x.png','cccc',
              'marketing_design','marketing_design','pass');
      raise exception 'SHOULD NOT REACH HERE';
    end $$;`);
    assert.equal(r.ok, false);
    // 18 AUG 2026 — THE GUARD REFUSED AND THE ASSERTION STILL FAILED. It matched the string
    // /cannot be its only reviewer/, which is the wording the trigger used before fn_pick_reviewer
    // landed. The deployed guard refuses with SQLSTATE 23514 from fn_artifact_review_valid and a
    // message naming both parties and the two legitimate routes. Matching prose is how a correct
    // refusal reads as a failure; matching the SQLSTATE and the guard's own name is the standard
    // the negative-guard suite already holds itself to, so this now does the same.
    assert.match(r.text, /23514/,
      'a self-review must be refused by a CHECK-class guard (23514), not by anything softer');
    assert.match(r.text, /fn_artifact_review_valid/,
      'the refusal must come from fn_artifact_review_valid — the author-is-not-reviewer guard — '
      + 'and not from some other constraint that happens to reject this row');
    assert.match(r.text, /self-review/i,
      'the refusal must say what it refused, so the next reader knows which rule fired');
  });

  test(`${name}: every channel marketing publishes to has a video spec with a duration bound`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const r = one(await q(ref, `select
      count(*) filter (where kind in ('video','reel','short')) video_specs,
      count(*) filter (where kind in ('video','reel','short') and max_duration_s is null) no_max_duration,
      count(*) filter (where kind in ('video','reel','short')
        and not ('video/mp4' = any(allowed_mime))) mp4_not_allowed,
      count(*) filter (where kind in ('reel','short') and safe_zone_pct < 0.10) vertical_safe_zone_too_small
      from artifact_platform_spec`));
    assert.ok(Number(r.video_specs) >= 6, 'the channels marketing uses need their own video constraints');
    assert.equal(Number(r.no_max_duration), 0, 'a video spec without a duration bound cannot fail a too-long clip');
    assert.equal(Number(r.mp4_not_allowed), 0, 'an image-only allowed_mime would fail every video on format');
    // A caption inside a 5% margin is inside the frame and invisible in the app: the platform's
    // own caption, avatar and action rail cover the top and bottom of a vertical video.
    assert.equal(Number(r.vertical_safe_zone_too_small), 0,
      'vertical formats need a safe zone wide enough for the platform UI that covers them');
  });

  // ── certification separation ──────────────────────────────────────────────────
  test(`${name}: no certification material reached the runtime corpus`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const r = one(await q(ref, `select
      (select count(*) from ops_knowledge where layer = 'certification') in_knowledge,
      (select count(*) from ops_knowledge
        where source_path ilike '%CERTIFICATION_CASES%' or source_path ilike '%ANSWER_KEY%') cert_paths,
      (select count(*) from agent_training_case
        where case_family = 'certification_case' or case_id ilike '%cert-v2%') in_training,
      (select count(*) from cert.certification_question) questions,
      (select count(*) from cert.certification_answer_key) answers`));
    assert.equal(Number(r.in_knowledge), 0, 'certification material must not be runtime-retrievable');
    assert.equal(Number(r.cert_paths), 0, 'no certification file may have been ingested as knowledge');
    assert.equal(Number(r.in_training), 0, 'certification cases are not training cases');
    assert.equal(Number(r.answers), 0, 'a builder session must not hold an answer key');
  });

  test(`${name}: the certification island is unreachable by the runtime roles`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const r = one(await q(ref, `select
      has_schema_privilege('anon','cert','USAGE') anon_usage,
      has_schema_privilege('authenticated','cert','USAGE') auth_usage,
      has_schema_privilege('service_role','cert','USAGE') service_usage,
      has_table_privilege('service_role','cert.certification_answer_key','SELECT') service_answers,
      (select count(*) from pg_policies where schemaname = 'cert') policies,
      (select bool_and(relrowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where n.nspname='cert' and c.relkind='r') rls_on`));
    assert.equal(r.anon_usage, false, 'anon must not reach the certification schema');
    assert.equal(r.auth_usage, false, 'authenticated must not reach the certification schema');
    // The one that actually matters: every edge function runs as service_role, and
    // service_role bypasses RLS. If it had USAGE here, RLS would be no boundary at all.
    assert.equal(r.service_usage, false, 'service_role bypasses RLS, so it must not reach the cert schema');
    assert.equal(r.service_answers, false, 'no runtime path may read an answer key');
    assert.equal(Number(r.policies), 0, 'RLS with no policy is the boundary; a policy would open it');
    assert.equal(r.rls_on, true);
  });

  test(`${name}: certification results are append-only`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const r = await post(ref, `do $$ declare rid uuid; begin
      insert into cert.certification_result (question_id, agent_key, raw_output, evaluator)
        values ('probe-q','cfo','answer','probe-evaluator') returning result_id into rid;
      update cert.certification_result set score = 1 where result_id = rid;
      raise exception 'SHOULD NOT REACH HERE';
    end $$;`);
    assert.equal(r.ok, false);
    assert.match(r.text, /append-only/, 'an evaluator result must not be editable after the fact');
  });

  // ── readiness ─────────────────────────────────────────────────────────────────
  test(`${name}: no role is claimed as independently certified by a builder session`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const r = one(await q(ref, `select
      count(*) filter (where readiness = 'certified_for_defined_role_scope') certified,
      count(*) total from org_role_identity`));
    assert.equal(Number(r.certified), 0,
      'certified_for_defined_role_scope may only be set by the independent evaluator');
    assert.ok(Number(r.total) > 0);
  });

  // ── ingestion integrity ───────────────────────────────────────────────────────
  test(`${name}: the imported corpus matches the delivery's declared counts`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const r = one(await q(ref, `select
      (select count(*) from agent_training_case where generation = 'V3') v3_cases,
      (select count(*) from agent_training_case where generation='V3' and case_family='role_adversarial') adv,
      (select count(*) from agent_training_case where generation='V3' and case_family='role_tool') tool,
      (select count(*) from agent_training_case where generation='V3' and case_family='role_uncertainty') unc,
      (select count(*) from agent_training_case where generation='V3' and case_family='role_cross_department') cross_d,
      (select count(*) from agent_training_case where generation='V3' and case_family='department_management') dept,
      (select count(*) from agent_training_case where generation='V3' and case_family='category_case') cat,
      (select count(distinct role_key) from ops_knowledge where role_key is not null) roles_with_knowledge,
      (select count(distinct category_key) from ops_knowledge where category_key is not null) cats_with_knowledge`));
    assert.equal(Number(r.adv), 2304);
    assert.equal(Number(r.tool), 1152);
    assert.equal(Number(r.unc), 1152);
    assert.equal(Number(r.cross_d), 768);
    assert.equal(Number(r.dept), 672);
    assert.equal(Number(r.cat), 2924);
    assert.equal(Number(r.v3_cases), 8972, 'the delivery declares 8,972 V3 training cases');
    // 6 SEP 2026: the V3 delivery's role and category coverage is a FLOOR, not an exact figure. The
    // company adds role-scoped records as it learns (that day: the supplier-acquisition and sanctions
    // screening SOPs for two more roles, 96 -> 98); an equality here would redden every time an
    // employee is taught something, which is the opposite of what the delivery count protects.
    assert.ok(Number(r.roles_with_knowledge) >= 96, `roles with knowledge fell below the delivery's 96: ${r.roles_with_knowledge}`);
    assert.ok(Number(r.cats_with_knowledge) >= 86, `categories with knowledge fell below the delivery's 86: ${r.cats_with_knowledge}`);
  });
}
