// SPEC FILE #2, components 1-9 — Purpose, Mission, Objectives, Responsibilities, the Employee
// Object, Knowledge, Inputs, Outputs, Workflows. 30 requirements.
//
// Every check asks the same three questions and refuses to merge them:
//   1. does the mechanism EXIST?   2. is it POPULATED / does it RUN?   3. does anything READ it?
//
// This section is where the nine "built, populated, read by nothing" failures live, so presence is
// never sufficient evidence. Where a requirement says an attribute must reach an employee, the
// check reads fn_agent_context's ACTUAL OUTPUT and looks for the value stored in the table — not
// for a hard-coded heading, which would pass even if the column were empty. Where a requirement is
// satisfied today the check returns true: none of these can only fail.
//
// SQL NOTE: qd_guard refuses any read whose text contains a bare write keyword, so no statement
// below may contain one, even inside a string literal.

// One employee per OS, picked deterministically. "Does this reach the employees?" is a claim about
// all ten Operating Systems; asking cfo alone would prove it for Finance and assume the rest.
//
// HARDENED 6 Aug 2026 — both of these joined os_department/org_agents with NO active filter on
// operating_system, while every comparison they feed is against ACTIVE_OS. A staffed INACTIVE OS
// therefore counted on the left of `= ACTIVE_OS` and could substitute for an unstaffed active one.
// Inert on production today (10 operating_system rows, all active, all staffed) and repaired
// anyway: a denominator that is only correct because a column happens to be uniform is not a
// measurement, and deactivating one OS is a one-row write.
const ONE_PER_OS = `(select distinct on (d.os_key) d.os_key, a.agent_key
     from public.os_department d
     join public.operating_system o on o.os_key = d.os_key and coalesce(o.active,true)
     join public.org_agents a on a.department = d.dept_key and a.active
    order by d.os_key, a.agent_key)`;
const OS_WITH_STAFF = `(select count(distinct d.os_key) from public.os_department d
     join public.operating_system o on o.os_key = d.os_key and coalesce(o.active,true)
     join public.org_agents a on a.department = d.dept_key and a.active)`;
const ACTIVE_OS = `(select count(*) from public.operating_system where coalesce(active,true))`;

// Every active OS satisfies <cond>, an expression over the operating_system row `o`. Written as a
// per-row NOT EXISTS because "every OS" is a universal: `count(distinct os_key) = ACTIVE_OS` is
// satisfied by ten keys that are not the ten ACTIVE keys, and says nothing about which OS is missing.
const EVERY_ACTIVE_OS = (cond) => `(select count(*) from public.operating_system o
     where coalesce(o.active,true) and not (${cond})) = 0`;
const MISSING_ACTIVE_OS = (cond) => `coalesce((select string_agg(o.os_key, ', ' order by o.os_key)
     from public.operating_system o where coalesce(o.active,true) and not (${cond})), 'none')`;

// The assembled prompt of one employee per OS, computed once per statement.
const PROMPTS = `(select z.os_key, z.agent_key, public.fn_agent_context(z.agent_key, 20000) as t
     from ${ONE_PER_OS} z)`;

// How many of those employees' prompts satisfy <cond>, an expression over c.t / c.agent_key.
// Used wherever a requirement says "each employee" — asking cfo alone proves it for Finance and
// assumes the other nine, which is the shortcut four checks in this file used to take.
const PROMPT_ALL = (cond) => `(select count(*) from ${PROMPTS} c where ${cond})`;

// How many OSes have an employee whose assembled prompt literally contains <expr>, an expression
// over the operating_system row `o`. The value comes from the table, so a passing count means the
// stored attribute travelled into the prompt.
//
// FIXED 6 Aug 2026 — this used `like '%'||(expr)||'%'`, which puts TABLE CONTENT on the pattern
// side of LIKE, where `_`, `%` and `\` are metacharacters. 35 of 72 os_responsibility values carry
// `_` (brand, business_development, revenue_growth, ...), so the aggregated needle for every OS was
// a wildcard pattern, not the literal string this file's header promises. `_` matches any single
// character, so a prompt that rendered the value TRANSFORMED would still have matched —
// fn_agent_context does exactly that elsewhere (`replace(e.escalation_rule->>'when','_',' ')`).
// The error was one-directional: it could only ever manufacture a MET. position() takes a literal.
// The coalesce guard is the second half of the fix: position('' in t) returns 1, so an OS with no
// value to deliver would otherwise score as having delivered it. Re-measured after the change —
// all ten OS still match on charter, mission, objective and responsibilities, so no verdict moved.
const REACHED = (expr) => `(select count(*) from ${PROMPTS} c
     join public.operating_system o on o.os_key = c.os_key
    where coalesce((${expr}),'') <> '' and position((${expr}) in c.t) > 0)`;

const reachCheck = (expr) => `select ${REACHED(expr)} = ${OS_WITH_STAFF}`;
const reachEv = (expr, what) =>
  `select ${REACHED(expr)}::text||' of '||${OS_WITH_STAFF}::text||' OS: ${what}'`;

// A reader that is not a writer. The harness's READERS() self-excludes only a proc whose NAME
// equals the object's name — which never fires for a real table, because no routine is called
// org_tasks — so a table's own engine, the function that INSERTs or UPDATEs it, counted as its
// reader. This excludes by write SHAPE rather than by a name list, so a writer added later is
// excluded too. (The write keywords are split so qd_guard does not refuse the read.)
//
// APPLIED EVERYWHERE 6 Aug 2026. This helper existed and was wired to exactly two tables
// (workflow_run, event_delivery) while ten other reader legs still called READERS(). None of them
// manufactured a MET on that day — measured non-writer readers: org_tasks 16, agent_actions 36,
// company_event 8, decision_log 8, kb_revisions 4, employee_authority 3, employee_kpi 10,
// os_review 3, os_department 7, os_knowledge_domain 3 — but none of them COULD have failed the way
// this file's own rule demands, and a rule applied to two of twelve cases is a comment.
//
// Two further corrections in the same pass:
//  * count(DISTINCT p.proname). pg_proc holds one row per OVERLOAD, and fn_agent_context has two
//    on production — (text,int) and (text,int,text) — so every reader count that included it was
//    inflated by one. A table whose only reader is a two-overload function scored 2.
//  * a TRIGGER FUNCTION attached to the table is not a consumer of it. trg_declog_immutable reads
//    decision_log only to refuse a write to decision_log; counting it as a reader is the writer
//    problem wearing a different hat. Excluded by pg_trigger, not by name.
const W = `('(ins'||'ert|upd'||'ate|del'||'ete)\\s+(into\\s+|from\\s+)?"?(public"?\\.)?"?`;
const NON_WRITER_READERS = (t, alsoExclude = []) => `(
    (select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> '${t}'
        ${alsoExclude.length ? `and p.proname not in (${alsoExclude.map(n => `'${n}'`).join(',')})` : ''}
        and pg_get_functiondef(p.oid) ~* '\\y${t}\\y'
        and pg_get_functiondef(p.oid) !~* (${W}${t}\\y'))
        and not exists (select 1 from pg_trigger tg
                         where tg.tgfoid = p.oid and tg.tgrelid = to_regclass('public.${t}')))
  + (select count(*) from pg_views v where v.schemaname='public' and v.definition ~* '\\y${t}\\y'))`;

// A routine that is reached by an ACTIVE cron job. A proc nobody calls is not a reader, and
// cron.job.active is the weakest form of "runs" this file accepts anywhere.
const ON_ACTIVE_CRON = `exists (select 1 from cron.job j
     where j.active and j.command ~* ('\\y'||p.proname||'\\y'))`;

export default async function ({ req }) {
  // ---- Component 1: Purpose -------------------------------------------------------------------
  // charter+mandate were 10/10 populated and exposed only by v_operating_manual, which had no
  // reader of its own. The check therefore ignores the table's row count as proof of anything.
  await req('comp', 'comp-01-purpose', 'Every OS states why it exists (Purpose)',
    `select (select count(*) from public.operating_system
              where coalesce(active,true) and coalesce(charter,'') <> '' and coalesce(mandate,'') <> '')
            = ${ACTIVE_OS}
       and ${REACHED('left(o.charter,200)')} = ${OS_WITH_STAFF}`,
    reachEv('left(o.charter,200)', 'employee prompt carries the stored charter'));

  await req('comp', 'comp-02-mission', 'Every OS has a one-sentence Mission',
    `select (select count(*) from public.operating_system
              where coalesce(active,true) and coalesce(mission,'') <> '') = ${ACTIVE_OS}
       and ${REACHED('left(o.mission,200)')} = ${OS_WITH_STAFF}`,
    reachEv('left(o.mission,200)', 'employee prompt carries the stored mission'));

  // ---- Component 2: Objectives ----------------------------------------------------------------
  // Five horizons for every OS, and the horizon label must survive into the prompt: an objective
  // without its horizon is a slogan, which is precisely how 50 rows sat unread.
  await req('comp', 'comp-03-objectives', 'Objectives at strategic/annual/quarterly/weekly/daily horizons',
    `select (select count(*) from public.operating_system os2
              where coalesce(os2.active,true)
                and (select count(distinct horizon) from public.os_objective j
                      where j.os_key = os2.os_key) = 5) = ${ACTIVE_OS}
       and ${REACHED(`select 'strategic: '||y.objective from public.os_objective y
                        where y.os_key = o.os_key and y.horizon='strategic'
                          and coalesce(y.active,true) limit 1`)} = ${OS_WITH_STAFF}`,
    reachEv(`select 'strategic: '||y.objective from public.os_objective y
               where y.os_key = o.os_key and y.horizon='strategic'
                 and coalesce(y.active,true) limit 1`,
      'employee prompt carries the horizon-labelled objective'));

  // A measure that is prose ('gl_journal', 'os_review health') cannot produce an actual value, so
  // nothing can ever say whether an objective was met. The mechanism required is a computable
  // measure plus a routine that resolves it — employee_kpi.measure_sql is the working precedent.
  //
  // The column list alone is NOT the test. measure_sql/actual_value/measured_at were added to
  // os_objective while this section was being written and left empty on all 50 rows, and an earlier
  // draft of this check passed anyway: fn_agent_context happens to contain the string
  // 'actual_value' for goal_period, which has nothing to do with objectives. Populated rows are
  // the only thing that distinguishes a measure from a column definition.
  //
  // HARDENED 6 Aug 2026, three defects:
  //  (a) The equality compared measure_sql over ALL objectives against the count of ACTIVE ones, so
  //      an inactive objective carrying a measure offset an active one that lacked it. Both sides
  //      now filter `active`, the way the sibling comp-05-kpis already did.
  //  (b) The stated requirement is "a computable measure PLUS a routine that resolves it", and the
  //      SQL never looked for the routine. It now requires a live resolver: a public routine other
  //      than os_objective's own name that names os_objective AND measure_sql AND is reached by an
  //      ACTIVE cron job. (fn_os_objective_measure, cron os_objective_measure_daily '20 3 * * *'.)
  //  (c) `actual_value is not null > 0` let ONE hand-set value on one of 50 objectives score
  //      "objectives carry a computable measure". It is now a coverage ratio written as a
  //      multiplication — `2 * resolved >= active` — because bigint division silently makes
  //      `resolved >= active/2` vacuous at low volume, plus freshness against the clock so a
  //      resolver that stopped running fails instead of coasting on old values.
  //
  // HARDENED AGAIN 6 Aug 2026 — the check confirmed the number was WRITTEN and never asked who
  // READS it, which is the one question this whole file exists to ask. Measured at the time: the
  // only routines naming os_objective were fn_agent_context and the resolver (its writer), and the
  // only view exposing it was v_operating_manual, which has no reader of its own — so 46 of 50
  // objectives were being resolved to a number daily and consumed by nothing.
  //
  // fn_agent_context's TAIL block does read it — `# YOUR OS OBJECTIVES, MEASURED`, appended after
  // layer 4, rendering `<horizon>: <objective> — reads <actual_value> (measured <date>)`. The gap
  // was in the SCORER, not in the system: nothing asserted that block. It is asserted now, and
  // asserted on the VALUE rather than on the heading — the heading renders `no value` when
  // actual_value is null, so matching it would pass with all 50 unresolved. The needle is the
  // stored number itself, for one employee per OS. Measured after the change: 10 of 10.
  const OBJ_RESOLVER = `(select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
       where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> 'os_objective'
         and pg_get_functiondef(p.oid) ~* '\\yos_objective\\y'
         and pg_get_functiondef(p.oid) ~* '\\ymeasure_sql\\y'
         and ${ON_ACTIVE_CRON})`;
  const OBJ_VALUE_REACHED = `(select count(*) from ${PROMPTS} c
       where exists (select 1 from public.os_objective y
                      where y.os_key = c.os_key and coalesce(y.active,true)
                        and y.actual_value is not null
                        and position(y.horizon||': '||y.objective||' — reads '||y.actual_value::text
                                     in c.t) > 0))`;
  await req('comp', 'comp-03-objectives-measured', 'Objectives carry a computable measure, not prose',
    `select (select count(*) from public.os_objective where coalesce(active,true) and coalesce(measure_sql,'') <> '')
            = (select count(*) from public.os_objective where coalesce(active,true))
       and (select count(*) from public.os_objective where coalesce(active,true)) > 0
       and ${OBJ_RESOLVER} > 0
       and (select count(*) from public.os_objective where coalesce(active,true)
             and measured_at > now() - interval '8 days')
           = (select count(*) from public.os_objective where coalesce(active,true))
       and 2 * (select count(*) from public.os_objective where coalesce(active,true) and actual_value is not null)
           >= (select count(*) from public.os_objective where coalesce(active,true))
       and ${OBJ_VALUE_REACHED} = ${OS_WITH_STAFF}`,
    `select (select count(*) from public.os_objective where coalesce(active,true) and coalesce(measure_sql,'') <> '')::text
       ||' of '||(select count(*)::text from public.os_objective where coalesce(active,true))
       ||' ACTIVE objectives carry a computable measure, '
       ||(select count(*) from public.os_objective where coalesce(active,true) and actual_value is not null)::text
       ||' resolved to an actual value, last measured '
       ||coalesce((select max(measured_at)::date::text from public.os_objective),'never')
       ||'; live resolvers on an active cron: '||coalesce((select string_agg(distinct p.proname,', ')
            from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
           where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> 'os_objective'
             and pg_get_functiondef(p.oid) ~* '\\yos_objective\\y'
             and pg_get_functiondef(p.oid) ~* '\\ymeasure_sql\\y'
             and ${ON_ACTIVE_CRON}),'none')
       ||'; '||${OBJ_VALUE_REACHED}::text||' of '||${OS_WITH_STAFF}::text
       ||' OS have the resolved NUMBER (not the heading) in an employee''s prompt'`);

  // ---- Component 4: Responsibilities -----------------------------------------------------------
  // The population leg was `count(distinct os_key) from os_responsibility = ACTIVE_OS`, which is
  // satisfied by ten os_keys that are not the ten ACTIVE ones. Per-active-OS NOT EXISTS instead.
  const RESP_COND = `exists (select 1 from public.os_responsibility r where r.os_key = o.os_key)`;
  await req('comp', 'comp-04-responsibilities', 'Responsibilities replace departments as the ownership unit',
    `select ${EVERY_ACTIVE_OS(RESP_COND)}
       and ${REACHED(`select string_agg(x.responsibility, ', ' order by x.responsibility)
                        from (select responsibility from public.os_responsibility
                               where os_key = o.os_key order by responsibility limit 12) x`)} = ${OS_WITH_STAFF}`,
    `select ${REACHED(`select string_agg(x.responsibility, ', ' order by x.responsibility)
               from (select responsibility from public.os_responsibility
                      where os_key = o.os_key order by responsibility limit 12) x`)}::text
       ||' of '||${OS_WITH_STAFF}::text||' OS: employee prompt lists what their OS owns; '
       ||'active OS with NO responsibility row: '||${MISSING_ACTIVE_OS(RESP_COND)}`);

  // "No other OS can own these" must be structural, not a convention. A PK on responsibility alone
  // makes a second owner unrepresentable; a composite PK would not.
  await req('comp', 'comp-04-exclusivity', '"No other OS can own these" is enforced structurally',
    `select (select pg_get_constraintdef(oid) from pg_constraint
              where conrelid='public.os_responsibility'::regclass and contype='p')
            = 'PRIMARY KEY (responsibility)'
       and (select count(*) = count(distinct responsibility) from public.os_responsibility)`,
    `select coalesce((select pg_get_constraintdef(oid) from pg_constraint
       where conrelid='public.os_responsibility'::regclass and contype='p'),'no primary key')
       ||' over '||(select count(*)::text from public.os_responsibility)||' rows'`);

  // ---- Component 5: the Employee Object --------------------------------------------------------
  const LINK_COND = `exists (select 1 from public.os_department d
       join public.org_agents a on a.department = d.dept_key and a.active
      where d.os_key = o.os_key)`;
  await req('comp', 'comp-05-linkage', 'os_department links each OS to real org_agents rows',
    `select ${EVERY_ACTIVE_OS(LINK_COND)}
       and ${OS_WITH_STAFF} = ${ACTIVE_OS}
       and ${NON_WRITER_READERS('os_department')} > 0`,
    `select ${OS_WITH_STAFF}::text||' of '||${ACTIVE_OS}::text||' OS reach active staff (missing: '
       ||${MISSING_ACTIVE_OS(LINK_COND)}||'); '
       ||(select count(*)::text from public.org_agents a
            join public.os_department d on d.dept_key = a.department where a.active)
       ||' staffed employees; '||${NON_WRITER_READERS('os_department')}::text||' non-writer reader(s)'`);

  // The prompt leg was `fn_agent_context('cfo',...)` here and in the three checks below — one agent
  // standing in for "each employee", in the file that builds ONE_PER_OS specifically to refuse that.
  // All four now run over one employee per OS and compare against OS_WITH_STAFF.
  await req('comp', 'comp-05-role', 'Each employee has a Role that reaches a prompt',
    `select (select count(*) from public.org_agents where active and coalesce(role,'') <> '')
            = (select count(*) from public.org_agents where active)
       and ${PROMPT_ALL(`exists (select 1 from public.org_agents a
                where a.agent_key = c.agent_key and coalesce(a.role,'') <> ''
                  and position(a.role in c.t) > 0)`)} = ${OS_WITH_STAFF}`,
    `select (select count(*) filter (where coalesce(role,'') = '') from public.org_agents where active)::text
       ||' of '||(select count(*)::text from public.org_agents where active)
       ||' active employees have no role text; '
       ||${PROMPT_ALL(`exists (select 1 from public.org_agents a
                where a.agent_key = c.agent_key and coalesce(a.role,'') <> ''
                  and position(a.role in c.t) > 0)`)}::text
       ||' of '||${OS_WITH_STAFF}::text||' OS carry their own role text into the prompt'`);

  // Authority must be personal, not inferred: the dispatcher used to hand out 'autonomous' itself.
  // HARDENED 6 Aug 2026 — the needle was '# YOUR AUTHORITY', and fn_agent_context emits that heading
  // in BOTH branches: '# YOUR AUTHORITY (granted to you personally)' and '# YOUR AUTHORITY
  // (delegated to <dept>, no personal grant on file)'. So the prompt leg scored identically whether
  // the grant was personal or inherited from org_authority — the one distinction the check exists to
  // make. It now matches the personal-grant variant only, for one employee per OS. Measured after
  // the change: 10 of 10.
  await req('comp', 'comp-05-authority', 'Each employee has Authority that reaches a prompt',
    `select (select count(*) from public.org_agents a where a.active
              and not exists (select 1 from public.employee_authority e where e.agent_key = a.agent_key)) = 0
       and ${PROMPT_ALL(`c.t like '%# YOUR AUTHORITY (granted to you personally)%'`)} = ${OS_WITH_STAFF}
       and ${NON_WRITER_READERS('employee_authority')} > 0`,
    `select (select count(*) from public.org_agents a where a.active
              and not exists (select 1 from public.employee_authority e where e.agent_key = a.agent_key))::text
       ||' active employees with no personal authority row; '
       ||(select count(*)::text from public.employee_authority)||' rows; '
       ||${PROMPT_ALL(`c.t like '%# YOUR AUTHORITY (granted to you personally)%'`)}::text
       ||' of '||${OS_WITH_STAFF}::text||' OS see a PERSONAL authority block, not a delegated one; '
       ||${NON_WRITER_READERS('employee_authority')}::text||' non-writer reader(s)'`);

  // HARDENED 6 Aug 2026 — "Each employee has KPIs" was scored by a global
  // `(count from employee_kpi where active) > 0`: one active KPI anywhere in the company satisfied
  // it and an employee with none was invisible. comp-05-authority and comp-05-escalation both carry
  // a per-employee not-exists; this one now does too.
  //
  // HARDENED AGAIN 6 Aug — the delivery leg matched the static heading '# YOUR KPIs' against a file
  // header that promises the opposite ("not for a hard-coded heading, which would pass even if the
  // column were empty"). fn_agent_context guards that heading with `if v_line is not null`, and the
  // population leg above already asserts v_line is non-null for every active employee, so the
  // delivery leg proved only that the block survived truncation — never that a KPI arrived. It now
  // matches the employee's OWN stored kpi text. Measured after the change: 10 of 10.
  const KPI_TEXT_REACHED = PROMPT_ALL(`exists (select 1 from public.employee_kpi k
                where k.agent_key = c.agent_key and k.active
                  and coalesce(k.kpi,'') <> '' and position(k.kpi in c.t) > 0)`);
  await req('comp', 'comp-05-kpis', 'Each employee has KPIs that reach a prompt',
    `select (select count(*) from public.employee_kpi where active and coalesce(measure_sql,'') <> '')
            = (select count(*) from public.employee_kpi where active)
       and (select count(*) from public.org_agents a where a.active
             and not exists (select 1 from public.employee_kpi e
                              where e.agent_key = a.agent_key and e.active)) = 0
       and ${KPI_TEXT_REACHED} = ${OS_WITH_STAFF}
       and ${NON_WRITER_READERS('employee_kpi')} > 0`,
    `select (select count(*)::text from public.employee_kpi where active)||' active KPIs, '
       ||(select count(*)::text from public.employee_kpi where active and coalesce(measure_sql,'') <> '')
       ||' with measure_sql; '
       ||(select count(*) from public.org_agents a where a.active
           and not exists (select 1 from public.employee_kpi e
                            where e.agent_key = a.agent_key and e.active))::text
       ||' active employees with NO active KPI; '
       ||${KPI_TEXT_REACHED}::text||' of '||${OS_WITH_STAFF}::text
       ||' OS carry their own stored KPI text into the prompt; '
       ||${NON_WRITER_READERS('employee_kpi')}::text||' non-writer reader(s)'`);

  // TIGHTENED 6 Aug 2026, and the old assertion is quoted below because it was wrong in an
  // instructive way. It resolved fn_agent_context's OWN WHERE clause, dept-mate fallback included,
  // and asked whether each employee reaches at least one profession row. That accepts the fallback
  // as satisfying "each employee has Knowledge" — and the fallback is precisely what hid the gap:
  // 52 of 66 employees had NO profession knowledge of their own and were being handed a colleague's,
  // so the Accounts Payable Specialist was reading the CFO's expertise and the block always
  // rendered. Measuring the function's behaviour is not the same as measuring the requirement.
  //
  //   old: ... or (a.department is not null and not exists (<no own rows>) and k.agent_key in
  //              (select b.agent_key from org_agents b where b.department = a.department ...))
  //
  // Personal is the claim the spec makes ("Each employee has ... Knowledge"), so personal is what
  // is asserted. The 52 were backfilled in scripts/sql/agent_knowledge_profession_backfill.sql; the
  // fallback stays in the function as a safety net for a newly hired employee, which is what a
  // fallback is for.
  // HARDENED 6 Aug 2026 — the check above confirmed POPULATION and never asked whether anything
  // reaches a prompt, in a requirement whose name ends "that reaches a prompt". It re-implemented
  // fn_agent_context's WHERE clause and counted employees for whom it yields a row; every
  // neighbouring check (comp-01..04) uses the prompt itself. Measured, the two are not the same
  // claim: rows matched vs '## ' topics actually rendered in the LAYER 2 block were cfo 17 -> 3,
  // ap_specialist 25 -> 4, compliance_mgr 22 -> 4. fn_agent_context drops pieces silently at
  //   if length(out)+length(piece) <= own_cap + 2200 then out := out||piece; end if;
  // so most matched rows never arrive. Demanding that ALL of them render would be unsatisfiable by
  // construction — the cap is deliberate — so the delivery leg asserts what the requirement
  // actually says: at least one of the employee's OWN knowledge topics appears verbatim in their
  // own prompt, for one employee per OS. Measured after the change: 10 of 10.
  await req('comp', 'comp-05-knowledge', 'Each employee has Knowledge that reaches a prompt',
    `select (select count(*) from public.org_agents a where a.active
              and not exists (
                select 1 from public.agent_knowledge k
                 where k.agent_key = a.agent_key
                   and coalesce(k.layer,'profession') in ('profession','state'))) = 0
       and ${PROMPT_ALL(`exists (select 1 from public.agent_knowledge k
                where k.agent_key = c.agent_key
                  and coalesce(k.layer,'profession') in ('profession','state')
                  and coalesce(k.topic,'') <> '' and position(k.topic in c.t) > 0)`)} = ${OS_WITH_STAFF}`,
    `select ${PROMPT_ALL(`exists (select 1 from public.agent_knowledge k
                where k.agent_key = c.agent_key
                  and coalesce(k.layer,'profession') in ('profession','state')
                  and coalesce(k.topic,'') <> '' and position(k.topic in c.t) > 0)`)}::text
       ||' of '||${OS_WITH_STAFF}::text||' OS have an employee whose OWN knowledge topic renders in '
       ||'their OWN prompt; '
       ||(select count(*) from public.org_agents a where a.active
              and exists (select 1 from public.agent_knowledge k
                           where k.agent_key = a.agent_key
                             and coalesce(k.layer,'profession') in ('profession','state')))::text
       ||' of '||(select count(*)::text from public.org_agents where active)
       ||' employees have knowledge of their own; '
       ||(select count(*) from public.org_agents a where a.active
           and not exists (select 1 from public.agent_knowledge k
                            where coalesce(k.layer,'profession') in ('profession','state')
                              and (k.agent_key = a.agent_key
                                   or k.agent_key in (select b.agent_key from public.org_agents b
                                                       where b.active and b.department = a.department
                                                         and b.agent_key <> a.agent_key))))::text
       ||' reach NO profession knowledge even after the dept-mate fallback'`);

  // Decision rights are only rights if something refuses. Both gate functions must read the grant.
  //
  // HARDENED 6 Aug 2026, two defects, both of which this file had already fixed elsewhere and then
  // repeated here verbatim.
  //  (a) The population leg was `(count from employee_authority where action_class<>'' and
  //      max_tier<>'') > 0` — ONE row out of 285 satisfying a requirement whose text is "EACH
  //      employee". Its two siblings written for the same component, comp-05-authority and
  //      comp-05-kpis, both carry a per-employee NOT EXISTS. So does this one now.
  //  (b) The delivery leg matched '%Anything not on that list is GATED%'. In the deployed
  //      fn_agent_context that sentence is emitted AFTER the if/else, guarded only by
  //      `if v_line is not null`, so it renders identically under
  //      '# YOUR AUTHORITY (granted to you personally)' and under
  //      '# YOUR AUTHORITY (delegated to <dept>, no personal grant on file)' — where v_line comes
  //      from org_authority, not employee_authority. That is exactly what comp-05-authority was
  //      hardened against 90 lines above. It now requires the personal heading AND the employee's
  //      OWN grant rendered as fn_agent_context renders it, `<action_class> -> <max_tier>`, so a
  //      department grant that happens to read the same cannot stand in for a personal one.
  //      Measured after the change: 10 of 10, 0 active employees without a usable grant.
  const RIGHTS_REACHED = PROMPT_ALL(`c.t like '%# YOUR AUTHORITY (granted to you personally)%'
              and exists (select 1 from public.employee_authority e
                           where e.agent_key = c.agent_key
                             and coalesce(e.action_class,'') <> '' and coalesce(e.max_tier,'') <> ''
                             and position(e.action_class||' -> '||e.max_tier in c.t) > 0)`);
  await req('comp', 'comp-05-decision-rights', 'Each employee has Decision Rights, enforced at runtime',
    `select (select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
              where ns.nspname='public' and p.proname in ('fn_decision_gate','fn_check_spend')
                and pg_get_functiondef(p.oid) ~* '\\yemployee_authority\\y') = 2
       and (select count(*) from public.org_agents a where a.active
             and not exists (select 1 from public.employee_authority e
                              where e.agent_key = a.agent_key
                                and coalesce(e.action_class,'') <> ''
                                and coalesce(e.max_tier,'') <> '')) = 0
       and ${RIGHTS_REACHED} = ${OS_WITH_STAFF}`,
    `select coalesce((select string_agg(distinct p.proname, ', ')
       from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
       where ns.nspname='public' and p.proname in ('fn_decision_gate','fn_check_spend')
         and pg_get_functiondef(p.oid) ~* '\\yemployee_authority\\y'),'no gate reads it')
       ||' enforce '||(select count(*)::text from public.employee_authority)||' authority rows; '
       ||(select count(*) from public.org_agents a where a.active
           and not exists (select 1 from public.employee_authority e
                            where e.agent_key = a.agent_key
                              and coalesce(e.action_class,'') <> ''
                              and coalesce(e.max_tier,'') <> ''))::text
       ||' of '||(select count(*)::text from public.org_agents where active)
       ||' active employees have NO usable employee_authority row; '||${RIGHTS_REACHED}::text
       ||' of '||${OS_WITH_STAFF}::text
       ||' OS see their OWN action_class -> max_tier text under the PERSONAL heading'`);

  // 1,206 escalation rules existed on ops_knowledge and their only reader, fn_kb_retrieve, had no
  // caller anywhere. Existence of the column is therefore worthless evidence; the prompt is the test.
  // escalation_rule is jsonb and non-null on all 3,959 records, but only 1,206 carry the
  // {when, action} pair the prompt actually renders — counting non-nulls would score 3,959.
  //
  // HARDENED 6 Aug 2026 — the delivery leg matched the static heading 'WHEN TO ESCALATE', and this
  // is the sharpest possible place to have done that: escalation_rule is the ONE requirement whose
  // content fn_agent_context TRANSFORMS on the way out —
  // `replace(escalation_rule->>'when','_',' ')` — and the transformation is the very reason the
  // REACHED comment above gives for matching literals rather than patterns. The needle is now the
  // rule as rendered, underscores replaced, for one employee per OS. Measured: 10 of 10.
  const ESC_RULE_REACHED = PROMPT_ALL(`exists (
                select 1 from public.org_agents a
                  join public.ops_knowledge o on o.dept_key = a.department
                 where a.agent_key = c.agent_key
                   and o.escalation_rule ? 'when' and o.escalation_rule ? 'action'
                   and position('- when '||replace(o.escalation_rule->>'when','_',' ')
                                ||' -> '||replace(o.escalation_rule->>'action','_',' ')
                                in c.t) > 0)`);
  await req('comp', 'comp-05-escalation', 'Each employee has Escalation Rules that reach them',
    `select (select count(*) from public.org_agents a where a.active
              and not exists (select 1 from public.ops_knowledge o
                               where o.dept_key = a.department
                                 and o.escalation_rule->>'when' is not null
                                 and o.escalation_rule->>'action' is not null)) = 0
       and (select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
             where ns.nspname='public' and p.proname='fn_agent_context'
               and pg_get_functiondef(p.oid) ~* '\\yescalation_rule\\y') > 0
       and ${ESC_RULE_REACHED} = ${OS_WITH_STAFF}`,
    `select (select count(*) filter (where escalation_rule->>'when' is not null
                                       and escalation_rule->>'action' is not null)
              from public.ops_knowledge)::text
       ||' renderable rules of '||(select count(*)::text from public.ops_knowledge)||' records; '
       ||(select count(*) from public.org_agents a where a.active
           and exists (select 1 from public.ops_knowledge o
                        where o.dept_key = a.department
                          and o.escalation_rule->>'when' is not null
                          and o.escalation_rule->>'action' is not null))::text
       ||' of '||(select count(*)::text from public.org_agents where active)
       ||' employees in a department that has one; '||${ESC_RULE_REACHED}::text
       ||' of '||${OS_WITH_STAFF}::text||' OS have a stored rule rendered VERBATIM in the prompt'`);

  // ---- Component 6: Knowledge ------------------------------------------------------------------
  await req('comp', 'comp-06-knowledge-independent', 'Every OS has independent knowledge',
    `select ${EVERY_ACTIVE_OS(`exists (select 1 from public.os_knowledge_domain k
                where k.os_key = o.os_key and k.ownership='owns')`)}
       and ${NON_WRITER_READERS('os_knowledge_domain')} > 0`,
    `select 'active OS with no OWNED knowledge domain: '
       ||${MISSING_ACTIVE_OS(`exists (select 1 from public.os_knowledge_domain k
                where k.os_key = o.os_key and k.ownership='owns')`)}||'; '
       ||(select count(*)::text from public.os_knowledge_domain)||' rows, '
       ||(select count(*)::text from public.os_knowledge_domain where ownership='owns')||' owned; '
       ||${NON_WRITER_READERS('os_knowledge_domain')}::text||' non-writer reader(s)'`);

  // "Leadership does not duplicate Finance's knowledge, it queries it" needs a routine that takes an
  // os_key and resolves the owner — and that routine needs a caller, or it is fn_kb_retrieve again.
  //
  // HARDENED 6 Aug 2026, two defects.
  //  (a) The caller leg counted any proc whose body MENTIONS the name, plus any cron.job row with
  //      no `j.active` filter. A routine called only by another orphan routine passed — the
  //      fn_kb_retrieve failure moved up one level, which is not a fix. A call site is
  //      `name(`, not the name; both sibling liveness tests in this file (OBJ_RESOLVER,
  //      HS_LIVE_READERS) already require an ACTIVE cron. Both corrections applied.
  //  (b) The evidence string_agg'd EVERY proc that merely mentions os_knowledge_domain — measured
  //      fn_agent_context, fn_knowledge_gaps, fn_os_knowledge_query — while dropping both filters
  //      the verdict applies (the os_key argument, and the caller). A printed MET therefore did not
  //      prove the claim. The evidence now computes the qualifying set with the verdict's own
  //      filters and names each resolver's callers. Measured: fn_os_knowledge_query(p_os_key text,
  //      p_topic text) <- fn_agent_context.
  const XOS_QUALIFIES = `p.prokind in ('f','p')
          and pg_get_functiondef(p.oid) ~* '\\yos_knowledge_domain\\y'
          and pg_get_function_identity_arguments(p.oid) ~* 'os_key'
          and ((select count(distinct q.proname) from pg_proc q join pg_namespace m on m.oid=q.pronamespace
                 where m.nspname='public' and q.prokind in ('f','p') and q.proname <> p.proname
                   and pg_get_functiondef(q.oid) ~* ('\\y'||p.proname||'\\s*\\('))
             + (select count(*) from cron.job j
                 where j.active and j.command ~* ('\\y'||p.proname||'\\s*\\('))) > 0`;
  await req('comp', 'comp-06-cross-os-query', 'Leadership does not duplicate knowledge; it queries the owning OS',
    `select exists (select 1 from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
        where ns.nspname='public' and ${XOS_QUALIFIES})`,
    `select coalesce((select string_agg(distinct p.proname||'('||pg_get_function_identity_arguments(p.oid)||') <- '
         ||coalesce((select string_agg(distinct q.proname, '+') from pg_proc q join pg_namespace m on m.oid=q.pronamespace
                      where m.nspname='public' and q.prokind in ('f','p') and q.proname <> p.proname
                        and pg_get_functiondef(q.oid) ~* ('\\y'||p.proname||'\\s*\\(')),'no caller')
         ||coalesce(' + active cron '||(select string_agg(j.jobname,'/') from cron.job j
              where j.active and j.command ~* ('\\y'||p.proname||'\\s*\\(')), ''), ', ')
       from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
       where ns.nspname='public' and ${XOS_QUALIFIES}),
       'no CALLED routine takes an os_key and resolves os_knowledge_domain')`);

  // ---- Component 7: Inputs ---------------------------------------------------------------------
  // The bus itself works. The requirement is that EVERY OS is on it, which is a different claim.
  //
  // REAL SYSTEM GAP, FOUND AND FIXED 6 Aug 2026. This scored MET on two legs that could not see the
  // failure: leg 1 counted OSes holding a subscription ROW with active=true (a flag, not traffic),
  // and leg 2 was a single global `(deliveries in 7d) > 0`. Measured underneath it: 470 deliveries
  // in 7 days across only EIGHT distinct os_key. finance and legal_gov had never received one, ever
  // — finance with 5 active employees and 4 active subscriptions, legal_gov with 4 and 4 — because
  // every event type they subscribed to (invoice.received, budget.exceeded, invoice.flagged,
  // regulation.changed) has never been emitted. event_delivery has carried an os_key column the
  // whole time and this check ignored it.
  //
  // The scorer now measures per active OS, as a NOT EXISTS, from event_delivery.os_key. The system
  // was fixed to match in scripts/sql/os_inputs_reach_every_os.sql: finance subscribes to
  // kpi.missed and legal_gov to security.event — both flowing, both genuinely theirs — with the
  // matching os_interface declarations, and the backlog was dispatched. Re-measured afterwards:
  // 10 of 10 OSes have deliveries, finance 18, legal_gov 12.
  //
  // 30 days per OS, 7 days for the bus: a low-traffic OS may legitimately be quiet for a week
  // (marketplace took 1 delivery in the last 7 days), but a month of silence on a declared input is
  // the thing this requirement is about. Both windows are copied from siblings in this file.
  const OS_RECEIVES = `exists (select 1 from public.event_delivery d
       where d.os_key = o.os_key and d.delivered_at > now() - interval '30 days')`;
  await req('comp', 'comp-07-inputs', 'Every OS receives events (Inputs)',
    `select ${EVERY_ACTIVE_OS(`exists (select 1 from public.os_department d
              join public.org_agents a on a.department = d.dept_key and a.active
              join public.event_subscription s on s.agent_key = a.agent_key and s.active
             where d.os_key = o.os_key)`)}
       and ${EVERY_ACTIVE_OS(OS_RECEIVES)}
       and (select count(*) from public.event_delivery where delivered_at > now() - interval '7 days') > 0`,
    `select (select count(distinct d.os_key) from public.os_department d
              join public.org_agents a on a.department = d.dept_key and a.active
              join public.event_subscription s on s.agent_key = a.agent_key and s.active)::text
       ||' of '||${ACTIVE_OS}::text||' OS have an active subscriber; '
       ||(select count(distinct os_key)::text from public.event_delivery
           where delivered_at > now() - interval '30 days')
       ||' distinct os_key actually received an event in 30d (active OS receiving NOTHING: '
       ||${MISSING_ACTIVE_OS(OS_RECEIVES)}||'); '
       ||(select count(*)::text from public.event_delivery where delivered_at > now() - interval '7 days')
       ||' deliveries in 7d'`);

  // A declared input that no event ever carries is documentation, not an interface. os_interface
  // grew a `planned` flag, so a kind may honestly be marked not-yet-live instead of firing.
  //
  // HARDENED 6 Aug 2026 — as written the whole requirement was satisfiable by flipping a boolean:
  // `planned=true` on every failing kind scored "Declared inputs correspond to events that actually
  // flow" MET with no event ever flowing, and nothing bounded how many rows the flag could excuse or
  // required it ever to be withdrawn. A flag is not traffic. Four bounds, all measurable:
  //   1. the set is non-empty — the old form scored MET over zero declared inputs;
  //   2. every NOT-planned active input has actually carried an event (unchanged, the real test);
  //   3. every planned row states WHY in planned_reason — an unexplained flag is a green button;
  //   4. the excuse expires: a planned kind whose events already flow is a defect, and at least one
  //      non-planned input must be flowing, so the entire declaration cannot be excused at once.
  // HARDENED AGAIN 6 Aug 2026, two residual defects.
  //  (a) NO COVERAGE. The only bound on the flag was "at least ONE non-planned input is flowing",
  //      so 16 of 17 declarations could be excused at once and 6 of 17 flowing — 35% — scored
  //      "declared inputs correspond to events that actually flow" MET. The bound is now per active
  //      OS, written as a NOT EXISTS: every active OS must hold at least one input declaration that
  //      is not marked planned and has actually carried an event. An OS cannot excuse its whole
  //      declaration. Measured before the fix: 5 of 10 OSes had one (evolution, intelligence,
  //      knowledge, leadership, operations); commercial, marketplace and technology were RECEIVING
  //      events through subscriptions they had never declared, and finance and legal_gov were
  //      receiving nothing at all. Those five declarations were added in
  //      scripts/sql/os_inputs_reach_every_os.sql — declaring what already flows, not inventing
  //      traffic. Re-measured: 22 active inputs, 11 planned, 11 flowing, 10 of 10 OSes covered.
  //  (b) THE EXPIRY WAS ENFORCED BY NOTHING. The comment above claimed "the excuse expires" while
  //      os_interface had no planned_since/planned_until at all — leg 4 only forbids a planned kind
  //      whose events already flow, which is a consistency check, not an expiry. The two columns
  //      now exist, every planned row carries them, a CHECK constraint makes an undated excuse
  //      unrepresentable, and this check fails a planned row whose planned_until has passed. A
  //      renewal is then a decision somebody has to take again, which is the point.
  const IFACE_IN = `from public.os_interface i where i.direction='input' and coalesce(i.active,true)`;
  const OS_DECLARES_FLOWING = `exists (select 1 from public.os_interface i
       where i.os_key = o.os_key and i.direction='input' and coalesce(i.active,true)
         and not coalesce(i.planned,false)
         and exists (select 1 from public.company_event e where e.event_type = i.kind))`;
  await req('comp', 'comp-07-inputs-coverage', 'Declared inputs correspond to events that actually flow',
    `select (select count(*) ${IFACE_IN}) > 0
       and (select count(*) ${IFACE_IN} and not coalesce(i.planned,false)
               and not exists (select 1 from public.company_event e where e.event_type = i.kind)) = 0
       and (select count(*) ${IFACE_IN} and coalesce(i.planned,false)
               and coalesce(i.planned_reason,'') = '') = 0
       and (select count(*) ${IFACE_IN} and coalesce(i.planned,false)
               and exists (select 1 from public.company_event e where e.event_type = i.kind)) = 0
       and (select count(*) ${IFACE_IN} and coalesce(i.planned,false)
               and (i.planned_until is null or i.planned_until <= now())) = 0
       and ${EVERY_ACTIVE_OS(OS_DECLARES_FLOWING)}`,
    `select (select count(*) ${IFACE_IN} and not coalesce(i.planned,false)
                and not exists (select 1 from public.company_event e where e.event_type = i.kind))::text
       ||' of '||(select count(*)::text ${IFACE_IN})
       ||' active declared input kinds have never appeared in company_event; '
       ||(select count(*)::text ${IFACE_IN} and coalesce(i.planned,false))
       ||' are marked planned ('
       ||(select count(*)::text ${IFACE_IN} and coalesce(i.planned,false)
             and coalesce(i.planned_reason,'') = '')
       ||' with no reason, '
       ||(select count(*)::text ${IFACE_IN} and coalesce(i.planned,false)
             and (i.planned_until is null or i.planned_until <= now()))
       ||' undated or expired, next expiry '
       ||coalesce((select min(i.planned_until)::date::text ${IFACE_IN} and coalesce(i.planned,false)),'n/a')
       ||', '
       ||(select count(*)::text ${IFACE_IN} and coalesce(i.planned,false)
             and exists (select 1 from public.company_event e where e.event_type = i.kind))
       ||' whose events already flow); '
       ||(select count(*)::text ${IFACE_IN} and not coalesce(i.planned,false)
             and exists (select 1 from public.company_event e where e.event_type = i.kind))
       ||' live kinds actually flowing; active OS with NO flowing declared input: '
       ||${MISSING_ACTIVE_OS(OS_DECLARES_FLOWING)}`);

  // ---- Component 8: Outputs --------------------------------------------------------------------
  // HARDENED 6 Aug 2026 — three of these eight outputs (tasks, approvals, recommendations) were
  // bare `> 0` existence tests with no recency bound and no coverage ratio, so one seed row made
  // each output permanently MET however long the output had since stopped. The other five in this
  // same block already bounded recency (decisions 7d, reports 21d, alerts 7d, knowledge-updates
  // 30d); those windows are what is used here. agent_actions.decided_at was the sharpest case: it
  // last moved on 2026-08-02 and could never have moved again without the check noticing.
  // Measured after the change: 290 dispatcher tasks in 7d, 64 approvals decided in 7d,
  // 73 recommendations in 30d of which 62 are decided.
  await req('comp', 'comp-08-out-tasks', 'Output: Tasks',
    `select (select count(*) from public.org_tasks) > 0
       and (select count(*) from public.org_tasks where decided_by='fn_event_dispatch'
             and created_at > now() - interval '7 days') > 0
       and ${NON_WRITER_READERS('org_tasks')} > 0`,
    `select (select count(*)::text from public.org_tasks)||' tasks, '
       ||(select count(*)::text from public.org_tasks where decided_by='fn_event_dispatch')
       ||' authored by the dispatcher ('
       ||(select count(*)::text from public.org_tasks where decided_by='fn_event_dispatch'
           and created_at > now() - interval '7 days')||' in 7d, last '
       ||coalesce((select max(created_at)::date::text from public.org_tasks
                    where decided_by='fn_event_dispatch'),'never')
       ||'); '||${NON_WRITER_READERS('org_tasks')}::text||' non-writer reader(s)'`);

  // Coverage and freshness were decoupled: `count(distinct os_key) = ACTIVE_OS` over ALL TIME plus
  // ONE review anywhere in 21 days, so nine of ten OSes could go permanently stale on a MET.
  // Both are now the same per-active-OS clause. Measured: 0 active OS without a review in 21d.
  const OS_REVIEWED_21D = `exists (select 1 from public.os_review r
       where r.os_key = o.os_key and r.created_at > now() - interval '21 days')`;
  await req('comp', 'comp-08-out-reports', 'Output: Reports',
    `select ${EVERY_ACTIVE_OS(OS_REVIEWED_21D)}
       and ${NON_WRITER_READERS('os_review')} > 0`,
    `select (select count(*)::text from public.os_review)||' reviews over '
       ||(select count(distinct os_key)::text from public.os_review)||' OS, last '
       ||coalesce((select max(created_at)::date::text from public.os_review),'never')
       ||'; active OS with NO review in 21d: '||${MISSING_ACTIVE_OS(OS_REVIEWED_21D)}||'; '
       ||${NON_WRITER_READERS('os_review')}::text||' non-writer reader(s)'`);

  await req('comp', 'comp-08-out-decisions', 'Output: Decisions',
    `select (select count(*) from public.decision_log) > 0
       and (select max(created_at) from public.decision_log) > now() - interval '7 days'
       and ${NON_WRITER_READERS('decision_log')} > 0`,
    `select (select count(*)::text from public.decision_log)||' decisions, last '
       ||coalesce((select max(created_at)::date::text from public.decision_log),'never')||'; '
       ||${NON_WRITER_READERS('decision_log')}::text||' non-writer reader(s); os_key on decision_log: '
       ||(select exists (select 1 from information_schema.columns where table_schema='public'
            and table_name='decision_log' and column_name='os_key'))::text`);

  await req('comp', 'comp-08-out-approvals', 'Output: Approvals',
    `select (select count(*) from public.agent_actions) > 0
       and (select count(*) from public.agent_actions
             where decided_at > now() - interval '7 days') > 0
       and ${NON_WRITER_READERS('agent_actions')} > 0`,
    `select (select count(*)::text from public.agent_actions)||' actions, '
       ||(select count(*)::text from public.agent_actions where decided_at is not null)||' decided ('
       ||(select count(*)::text from public.agent_actions where decided_at > now() - interval '7 days')
       ||' in 7d, last '||coalesce((select max(decided_at)::date::text from public.agent_actions),'never')
       ||'), '||(select count(*)::text from public.org_tasks where needs_founder and status <> 'done')
       ||' open founder approvals; '||${NON_WRITER_READERS('agent_actions')}::text||' non-writer reader(s)'`);

  // A recommendation nobody rules on is a note. The decided leg is a majority, not a `> 0`:
  // bigint division would make `decided >= total/2` vacuous at low volume, so it is a multiplication
  // — the same form comp-03-objectives-measured uses. Measured: 62 of 73 in 30d.
  const REC_30D = `from public.org_tasks where action_class='recommend'
             and created_at > now() - interval '30 days'`;
  await req('comp', 'comp-08-out-recommendations', 'Output: Recommendations',
    `select (select count(*) ${REC_30D}) > 0
       and 2 * (select count(*) ${REC_30D} and decided_by is not null) >= (select count(*) ${REC_30D})
       and ${NON_WRITER_READERS('org_tasks')} > 0`,
    `select (select count(*)::text from public.org_tasks where action_class='recommend')
       ||' recommendations ever, '||(select count(*)::text ${REC_30D})||' in 30d of which '
       ||(select count(*)::text ${REC_30D} and decided_by is not null)||' are decided, over '
       ||(select count(distinct dept_key)::text from public.org_tasks where action_class='recommend')
       ||' departments; '||${NON_WRITER_READERS('org_tasks')}::text||' non-writer reader(s) of org_tasks'`);

  // An alert nobody raised is not an output. fn_emit_metric_alerts is the only emitter and it has
  // no scheduler, so this asks whether an alert has actually fired recently.
  await req('comp', 'comp-08-out-alerts', 'Output: Alerts',
    `select (select count(*) from public.company_event
              where event_type in ('kpi.missed','goal.at_risk','metric.alert','health.degraded',
                                   'sla.breached','budget.exceeded','incident.opened')
                and occurred_at > now() - interval '7 days') > 0
       and ${NON_WRITER_READERS('company_event')} > 0`,
    `select 'last alert-class event '
       ||coalesce((select max(occurred_at)::date::text from public.company_event
                    where event_type in ('kpi.missed','goal.at_risk','metric.alert','health.degraded',
                                         'sla.breached','budget.exceeded','incident.opened')),'never')
       ||'; '||(select count(*)::text from public.company_event
                 where event_type in ('kpi.missed','goal.at_risk','metric.alert','health.degraded',
                                      'sla.breached','budget.exceeded','incident.opened'))
       ||' ever; fn_emit_metric_alerts schedulers: '
       ||(select count(*)::text from cron.job where command ~* '\\yfn_emit_metric_alerts\\y')`);

  // HARDENED 6 Aug 2026, two defects.
  //  (a) THE EVIDENCE ASSERTED A RELATIONSHIP NOTHING COMPUTED. It ended
  //      `(count from cron.job where active and command ~* fn_os_review) || ' active cron(s)
  //      consuming it'` — a count of crons running fn_os_review, captioned as consumption of
  //      v_os_scoreboard, while the verdict's two legs were independent and nothing tied them. True
  //      on production only by coincidence. The reader leg now requires ONE routine that both names
  //      v_os_scoreboard and is reached by an active cron, which is the claim itself.
  //  (b) The population leg was a bare `(count from employee_kpi where active) > 0` for a
  //      requirement that reads "Output: KPIs" across ten OSes. The output IS the scoreboard, so
  //      the coverage is measured on the scoreboard: every active OS resolves a row carrying at
  //      least one KPI, and none of those KPIs is unmeasurable. Measured: 10 of 10 OSes,
  //      0 unmeasurable, reader fn_os_review on cron os_review_weekly.
  const SB_LIVE_READERS = `(select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
       where ns.nspname='public' and p.prokind in ('f','p')
         and pg_get_functiondef(p.oid) ~* '\\yv_os_scoreboard\\y' and ${ON_ACTIVE_CRON})`;
  const SB_COVERS = `exists (select 1 from public.v_os_scoreboard s
       where s.os_key = o.os_key and s.kpis > 0 and coalesce(s.kpis_unmeasurable,0) = 0)`;
  await req('comp', 'comp-08-out-kpis', 'Output: KPIs',
    `select (select count(*) from pg_views where schemaname='public' and viewname='v_os_scoreboard') = 1
       and ${EVERY_ACTIVE_OS(SB_COVERS)}
       and ${SB_LIVE_READERS} > 0`,
    `select (select count(*)::text from public.employee_kpi where active)||' active KPIs; '
       ||'active OS whose scoreboard row is empty or unmeasurable: '||${MISSING_ACTIVE_OS(SB_COVERS)}
       ||'; v_os_scoreboard reader(s) reached by an ACTIVE cron: '
       ||coalesce((select string_agg(distinct p.proname||' ('||(select string_agg(j.jobname,'/')
              from cron.job j where j.active and j.command ~* ('\\y'||p.proname||'\\y'))||')', ', ')
            from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
           where ns.nspname='public' and p.prokind in ('f','p')
             and pg_get_functiondef(p.oid) ~* '\\yv_os_scoreboard\\y' and ${ON_ACTIVE_CRON}),'NONE')`);

  await req('comp', 'comp-08-out-knowledge-updates', 'Output: Knowledge Updates',
    `select (select count(*) from public.kb_revisions where created_at > now() - interval '30 days') > 0
       and ${NON_WRITER_READERS('kb_revisions')} > 0`,
    `select (select count(*)::text from public.kb_revisions where created_at > now() - interval '30 days')
       ||' revisions in 30d, last '
       ||coalesce((select max(created_at)::date::text from public.kb_revisions),'never')||'; '
       ||${NON_WRITER_READERS('kb_revisions')}::text||' non-writer reader(s); knowledge.updated events: '
       ||(select count(*)::text from public.company_event where event_type='knowledge.updated')`);

  // ---- Component 9: Workflows ------------------------------------------------------------------
  await req('comp', 'comp-09-workflows', 'Every OS contains workflows',
    `select (select count(distinct os_key) from public.workflow where active) = ${ACTIVE_OS}
       and (select count(*) from public.workflow where active and coalesce(trigger_event,'') <> '')
           = (select count(*) from public.workflow where active)
       and (select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
             where ns.nspname='public' and p.prokind in ('f','p')
               and pg_get_functiondef(p.oid) ~* 'from\\s+workflow\\y') > 0`,
    `select (select count(*)::text from public.workflow)||' workflows over '
       ||(select count(distinct os_key)::text from public.workflow)||' OS; '
       ||(select count(*)::text from public.workflow w
           where exists (select 1 from public.company_event e where e.event_type = w.trigger_event))
       ||' trigger_events have ever fired; routines selecting from workflow: '
       ||(select count(*)::text from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
           where ns.nspname='public' and p.prokind in ('f','p')
             and pg_get_functiondef(p.oid) ~* 'from\\s+workflow\\y')`);

  // 117 steps across 14 workflows and not one run: the table is a diagram, not an engine.
  //
  // HARDENED 6 Aug 2026 — this was `(count from workflow_run) > 0 and READERS('workflow_run') > 0`:
  // ONE row scored fourteen workflows and 117 steps, with no recency bound, no per-workflow
  // coverage, and no requirement that workflow_step_run hold anything even though the evidence
  // printed that number. Worse, READERS() would have counted the engine's own INSERT as the read —
  // the built-populated-unread failure this file exists to catch, wearing the engine's name.
  // Now: runs are recent; every active workflow whose trigger_event has ACTUALLY fired has a run
  // (coverage over the eligible population, not over the wish list — a workflow whose trigger has
  // never occurred cannot have run, and failing it would be a history test, not a capability test);
  // every run is tracked by at least one step run; and the reader must not be the writer.
  // fn_workflow_start_due is named as well as write-shape-excluded: it selects workflow_run only to
  // drive the engine forward, which is part of running the workflow, not a consumer of the record.
  // Measured today: 37 runs / 235 step runs in 7d, 4 of 4 eligible workflows covered, 10 of 14
  // active workflows have a trigger_event that has never fired, 0 runs without a step run,
  // 1 non-writer reader (fn_agent_context).
  const WR_READERS = NON_WRITER_READERS('workflow_run',
    ['fn_workflow_start', 'fn_workflow_start_due', 'fn_workflow_step_done']);
  await req('comp', 'comp-09-workflow-execution', 'Workflows execute and are tracked',
    `select (select count(*) from public.workflow_run
              where started_at > now() - interval '7 days') > 0
       and (select count(*) from public.workflow w where coalesce(w.active,true)
             and exists (select 1 from public.company_event e where e.event_type = w.trigger_event)
             and not exists (select 1 from public.workflow_run r
                              where r.workflow_key = w.workflow_key)) = 0
       and (select count(*) from public.workflow w where coalesce(w.active,true)
             and exists (select 1 from public.company_event e where e.event_type = w.trigger_event)) > 0
       and (select count(*) from public.workflow_run r
             where not exists (select 1 from public.workflow_step_run s
                                where s.workflow_run_id = r.id)) = 0
       and ${WR_READERS} > 0`,
    `select (select count(*)::text from public.workflow_run)||' run(s) ('
       ||(select count(*)::text from public.workflow_run where started_at > now() - interval '7 days')
       ||' in 7d), '||(select count(*)::text from public.workflow_step_run)||' step run(s); '
       ||(select count(*) from public.workflow w where coalesce(w.active,true)
           and exists (select 1 from public.company_event e where e.event_type = w.trigger_event)
           and exists (select 1 from public.workflow_run r where r.workflow_key = w.workflow_key))::text
       ||' of '||(select count(*) from public.workflow w where coalesce(w.active,true)
                   and exists (select 1 from public.company_event e
                                where e.event_type = w.trigger_event))::text
       ||' active workflows whose trigger has ever fired have a run ('
       ||(select count(*) from public.workflow w where coalesce(w.active,true)
           and not exists (select 1 from public.company_event e where e.event_type = w.trigger_event))::text
       ||' of '||(select count(*)::text from public.workflow where coalesce(active,true))
       ||' active workflows have a trigger_event that has never fired); '
       ||(select count(*) from public.workflow_run r where not exists
            (select 1 from public.workflow_step_run s where s.workflow_run_id = r.id))::text
       ||' run(s) with no step run; '||${WR_READERS}::text
       ||' non-writer reader(s) of workflow_run'`);

  // ---- The OS layer must reach the people who serve it -----------------------------------------
  // fn_agent_context is the sole prompt assembler. This asks whether the OS block survives the
  // 6,200-character employee section for every staffed OS, not just for the one agent tested first.
  //
  // REAL DEFECT, REPAIRED 6 Aug 2026. The check matched '%YOUR OPERATING SYSTEM%' — a HARD-CODED
  // HEADING, which this file's own header explicitly forbids ("not for a hard-coded heading, which
  // would pass even if the column were empty"). fn_agent_context emits that heading from
  // `'# YOUR OPERATING SYSTEM — '||coalesce(r.name, r.os_key)` the moment an employee's department
  // maps to an active OS, while every attribute after it is individually wrapped in
  // `case when r.<x> is not null then … else '' end`. So the requirement "OS-layer ATTRIBUTES reach
  // the employees who serve that OS" scored MET with charter, mission, mandate, responsibilities
  // and objectives ALL NULL. It tested that the OS names itself.
  //
  // All five attributes are now asserted, each as the stored value rendered exactly as
  // fn_agent_context renders it (`left(charter,300)`, `left(mission,240)`, `left(mandate,240)`, the
  // 12-row responsibility aggregate, the horizon-labelled objective). mandate is the one this file
  // asserted NOWHERE else — comp-01 checks charter, comp-02 mission, comp-04 responsibilities,
  // comp-03 objectives — so deleting one line from fn_agent_context would have left every check
  // green with a populated, unread column. Measured after the change: 10 of 10 on all five.
  const OS_ATTRS = [
    ['left(o.charter,300)', 'purpose'],
    ['left(o.mission,240)', 'mission'],
    ['left(o.mandate,240)', 'mandate'],
    [`(select string_agg(x.responsibility, ', ' order by x.responsibility)
         from (select responsibility from public.os_responsibility where os_key = o.os_key
                order by responsibility limit 12) x)`, 'responsibilities'],
    [`(select y.horizon||': '||y.objective from public.os_objective y
        where y.os_key = o.os_key and coalesce(y.active,true)
        order by case y.horizon when 'strategic' then 1 when 'annual' then 2
                                when 'quarterly' then 3 when 'weekly' then 4 else 5 end limit 1)`,
      'objectives'],
  ];
  await req('comp', 'os-layer-prompt-reach', 'OS-layer attributes reach the employees who serve that OS',
    `select (select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
              where ns.nspname='public' and p.proname='fn_agent_context'
                and pg_get_functiondef(p.oid) ~* '\\yoperating_system\\y') > 0
       and (select count(*) from ${ONE_PER_OS} z
             where public.fn_agent_context(z.agent_key, 20000) like '%YOUR OPERATING SYSTEM%')
           = ${OS_WITH_STAFF}
       ${OS_ATTRS.map(([e]) => `and ${REACHED(e)} = ${OS_WITH_STAFF}`).join('\n       ')}`,
    `select ${OS_WITH_STAFF}::text||' staffed OS; attributes that actually travel: '
       ||${OS_ATTRS.map(([e, w]) => `'${w} '||${REACHED(e)}::text`).join(`||', '||`)}
       ||' (each of '||${OS_WITH_STAFF}::text||')'`);

  // ---- The cross-OS contract closes ------------------------------------------------------------
  // Dispatch ends at one task per subscriber. The contract requires the loop to come back: results
  // recorded per delivery, consolidated, and a re-prioritisation emitted from them.
  //
  // HARDENED 6 Aug 2026 — a claim about a LOOP was scored by three bare `> 0` existence tests with
  // no time window and no consumer: one delivery with a result, one with a closed_at, and one
  // priority.updated event EVER. A single seed row made "the loop closes" permanently MET however
  // long the loop had since been stopped. Sibling checks in this same file already bound recency
  // (comp-08-out-decisions 7 days, comp-08-out-reports 21), so those windows are what is used here.
  // A fourth leg is added because the loop is only closed if the re-prioritisation REACHES someone:
  // the priority.updated event must have been delivered to a subscriber, which is the strictness
  // cross_os.mjs applies to the same CEO claim. And a fifth: event_delivery must have a reader that
  // does not write it — fn_event_dispatch and fn_event_consolidate are the writers.
  // Measured today: 58 deliveries with a result / 58 closed (last close 2026-08-06 03:50), 9
  // priority.updated in 7d, 9 of them delivered, 1 non-writer reader (fn_task_lesson).
  await req('comp', 'contract-consolidation', 'Chief of Staff consolidates, CEO re-prioritises, the loop closes',
    `select (select count(*) from public.event_delivery
              where result is not null and delivered_at > now() - interval '21 days') > 0
       and (select count(*) from public.event_delivery
             where closed_at > now() - interval '21 days') > 0
       and (select count(*) from public.company_event
             where event_type='priority.updated'
               and occurred_at > now() - interval '7 days') > 0
       and (select count(*) from public.event_delivery d
             join public.company_event e on e.id = d.event_id
            where e.event_type='priority.updated'
              and e.occurred_at > now() - interval '7 days') > 0
       and ${NON_WRITER_READERS('event_delivery')} > 0`,
    `select (select count(*)::text from public.event_delivery)||' deliveries, '
       ||(select count(*)::text from public.event_delivery
           where result is not null and delivered_at > now() - interval '21 days')
       ||' with a result in 21d, '
       ||(select count(*)::text from public.event_delivery where closed_at > now() - interval '21 days')
       ||' closed in 21d (last '
       ||coalesce((select max(closed_at)::date::text from public.event_delivery),'never')||'); '
       ||(select count(*)::text from public.company_event where event_type='priority.updated'
           and occurred_at > now() - interval '7 days')
       ||' priority.updated in 7d of '
       ||(select count(*)::text from public.company_event where event_type='priority.updated')
       ||' ever, '
       ||(select count(*)::text from public.event_delivery d join public.company_event e on e.id=d.event_id
           where e.event_type='priority.updated' and e.occurred_at > now() - interval '7 days')
       ||' delivered to a subscriber; '||${NON_WRITER_READERS('event_delivery')}::text
       ||' non-writer reader(s) of event_delivery'`);

  // ---- Component 16 head: per-OS health score --------------------------------------------------
  // fn_os_review computes green/amber/red per OS; the question this file asks is whether the number
  // then goes anywhere.
  //
  // REPAIRED 6 Aug 2026, two defects.
  //
  // (1) MANUFACTURED MET. The reader leg was `READERS('health_score') > 0`, which returned exactly 1
  //     on production, and that 1 was fn_os_review — the function that POPULATES the column. The
  //     harness's READERS(t) helper is built for TABLE names: its self-exclusion is
  //     `p.proname <> '<t>'`, so passing a COLUMN name makes the exclusion inert and lets the
  //     statement that writes the column count as a read of it. The sibling section refuted this
  //     check with the same fact in the same run (components_14_17.mjs excludes fn_os_review by name
  //     and scored seven figures MISSING on '0 live reader(s)'). The reader is now required to be a
  //     routine OTHER than fn_os_review, which names the figure alongside an OS-level source
  //     (os_review or operating_system, so an unrelated 'health_score' mention cannot qualify), and
  //     which is reachable from an ACTIVE cron job — a proc nobody calls is not a reader.
  //     Two population legs replace the single one: the column on every active OS, AND the figure
  //     inside the latest os_review period for every active OS, with that period fresh against the
  //     CLOCK rather than against itself (`max(period) = max(period)` is the freshness bug in
  //     the_ten_oses.mjs and is not repeated here).
  //     Measured after the change: 10 of 10 columns, 10 of 10 metrics in period 2026-W32 written
  //     07:09 today, live reader fn_os_health_brief (cron os_health_brief_weekly '50 4 * * 1'),
  //     which reads os_review.metrics->>'health_score' into the owning employee's agent_memory.
  //
  // (2) DUPLICATE REQUIREMENT ID. This was registered as 'comp-16-health-score', the same id
  //     components_14_17.mjs:261 uses for 'Each OS reports a Health Score that is read'. The runner
  //     keys both --only= and its NOT-MET listing on the id, so the 110-row scorecard held two rows
  //     a reader could not tell apart — including these two, which disagreed about whether the
  //     writer counts as a reader. Renamed to comp-16-health-score-column: this row owns
  //     operating_system.health_score, the sibling owns the os_review.health figure.
  // (3) HARDENED AGAIN 6 Aug 2026, two soft spots in the population legs.
  //     `max(period)` is a LEXICOGRAPHIC max over a TEXT column — correct today only because ISO
  //     weeks happen to be zero-padded ('2026-W31','2026-W32') — and the freshness leg
  //     `max(created_at) from os_review > now()-8d` was taken over the WHOLE table rather than over
  //     the rows of the period being scored, so one review filed under an older period satisfied
  //     freshness for an arbitrarily stale current period. The scored period is now the period of
  //     the most RECENTLY WRITTEN row, and freshness is measured on that period's own rows, so the
  //     two legs can no longer disagree about which week they are talking about. Measured after the
  //     change: period 2026-W32, 10 of 10, written today.
  const LATEST_PERIOD = `(select r2.period from public.os_review r2
       order by r2.created_at desc nulls last limit 1)`;
  const HS_LIVE_READERS = `(select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
       where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> 'fn_os_review'
         and pg_get_functiondef(p.oid) ~* '\\yhealth_score\\y'
         and pg_get_functiondef(p.oid) ~* '\\y(os_review|operating_system)\\y'
         and ${ON_ACTIVE_CRON})`;
  await req('comp', 'comp-16-health-score-column', 'Per-OS health score is computed and read',
    `select (select count(*) from public.operating_system
              where coalesce(active,true) and health_score is not null) = ${ACTIVE_OS}
       and ${EVERY_ACTIVE_OS(`exists (select 1 from public.os_review r
                where r.os_key = o.os_key and r.period = ${LATEST_PERIOD}
                  and coalesce(r.metrics->>'health_score','') <> '')`)}
       and (select max(r.created_at) from public.os_review r
             where r.period = ${LATEST_PERIOD}) > now() - interval '8 days'
       and ${HS_LIVE_READERS} > 0`,
    `select (select count(*)::text from public.operating_system
              where coalesce(active,true) and health_score is not null)
       ||' of '||${ACTIVE_OS}::text||' OS carry a health_score column; latest period '
       ||coalesce(${LATEST_PERIOD},'none')||' written '
       ||coalesce((select max(r.created_at)::date::text from public.os_review r
                    where r.period = ${LATEST_PERIOD}),'never')
       ||', active OS with NO health_score figure in it: '
       ||${MISSING_ACTIVE_OS(`exists (select 1 from public.os_review r
                where r.os_key = o.os_key and r.period = ${LATEST_PERIOD}
                  and coalesce(r.metrics->>'health_score','') <> '')`)}
       ||'; live reader(s) other than the writer fn_os_review: '
       ||coalesce((select string_agg(distinct p.proname,', ') from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
            where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> 'fn_os_review'
              and pg_get_functiondef(p.oid) ~* '\\yhealth_score\\y'
              and pg_get_functiondef(p.oid) ~* '\\y(os_review|operating_system)\\y'
              and ${ON_ACTIVE_CRON}),'NONE')`);
}
