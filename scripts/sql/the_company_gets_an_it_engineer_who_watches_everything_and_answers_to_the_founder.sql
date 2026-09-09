-- THE COMPANY GETS AN IT ENGINEER, AND HE IS THE ONE SEAT WITH NO LINE TO THE CEO.
--
-- The founder, 9 September 2026, verbatim: "fine then we build the it engineer to monitor
-- everything. once their is an issue, he will email me directly so i can open a session with you to
-- fix it. about his knowledge, you have to keep him really capable of such tasks. he reports to me
-- directly only. however he monitor literally everything in the app and the website"
--
-- This is the FIFTH seat. Measured on production before this file was written (2026-09-09 06:41 UTC):
-- org_agents 4 active (accountant, ceo, customer_support, sales_engineer); org_role 4, all active;
-- org_reporting_edge 3, every one terminating at 'ceo'; org_departments 0.
--
-- ─────────────────────────────────────────────────────────────────────────────────────────────────
-- WHY THIS SEAT HAS NO ROW IN org_reporting_edge, AND WHY THAT IS THE FOUNDER'S SENTENCE AND NOT AN
-- OVERSIGHT.
--
-- "he reports to me directly only."
--
-- org_reporting_edge.child_role_id and .parent_role_id are BOTH foreign keys to public.org_role, and
-- there is a not-self check. So the only way to write "reports to the founder" as an edge would be to
-- insert a role row called 'founder' and point at it. THE FOUNDER IS NOT A ROLE. He is a human being
-- who owns the company; org_role is the register of the AI seats the company runs. Creating a
-- 'founder' role to satisfy a foreign key would put a person into the org chart to make a constraint
-- happy, and every routine that walks the chart -- fn_support_report_to_ceo, the reporting queues,
-- fn_agent_may_act's CEO route -- would then treat him as an addressable seat with a runtime. That is
-- how "addressed to an identity nobody models" gets built on purpose.
--
-- So the absence of an edge IS the statement, and it is made explicit in three places rather than
-- left to be inferred from a missing row:
--   1. org_role.escalation_targets = {founder}  -- a descriptive text[], not a foreign key
--   2. org_role.handoff_targets    = {}         -- it hands work to no seat; there is no line to the CEO
--   3. the closing assertion in this file FAILS if an edge for 'it_engineer' ever appears
-- and it is asserted by name in scripts/checks/support_acceptance_group_org_and_channels.mjs
-- (scenario the_it_engineer_reports_to_the_founder_and_has_no_edge), so a later change that quietly
-- edges this seat under the CEO breaks a named test instead of passing silently.
--
-- WHAT THAT MEANS FOR ESCALATION, said plainly. Every other seat escalates INTO the company: an
-- uncovered action becomes a CEO decision. This one escalates OUT of it -- to the founder's mail, so
-- that he opens a session and the repair is made by a human with the code in front of him. That is
-- his own description of the loop and it is the whole reason the seat exists.
--
-- ─────────────────────────────────────────────────────────────────────────────────────────────────
-- THE AUTHORITY. It diagnoses and it escalates. It does not ship.
--
-- GRANTED (active):
--   it.monitoring  -- read anything: tables, views, logs, health rows, incidents, cron history, the
--                     edge estate, the website's own surfaces. Reading changes nothing.
--   it.diagnosis   -- record what it found: an incident, a severity, a suspected cause bound to the
--                     rows that evidence it. Writing its OWN findings is not touching production.
--   it.escalation  -- raise the alert that reaches the founder directly, through the founder mail
--                     policy. This is the action the founder asked for by name.
--
-- REGISTERED AND WITHHELD (active = false) -- it.job_rerun. This is the one judgement call in the
-- file, so the reasoning is written down rather than implied by a missing row.
--
--   The case FOR granting it: re-running a scheduled job that has just failed is not shipping code
--   and not changing configuration. It is doing what the scheduler was already going to do. A real
--   IT engineer reruns a failed backup rather than emailing about it, and this repository's own rule
--   is that an agent which only notifies is not doing its job.
--
--   The case AGAINST, which wins today: a rerun is only safe if the job is IDEMPOTENT, and NOTHING
--   IN THIS DATABASE RECORDS THAT FACT. public.cron_registry holds 230 rows and exactly four columns
--   -- jobname, human_name, category, purpose -- and not one of them says whether running a job twice
--   inside one cadence is harmless. Several registered jobs are messaging jobs; re-running one of
--   those is a second message to a real person. A grant whose limit_note says "only idempotent jobs"
--   over a set no query can compute is a limit that can never fire -- authority in the table and no
--   guard behind it, which is the exact shape this estate has been bitten by before.
--
--   So the row EXISTS, carrying the ruling, and it is INACTIVE. fn_agent_may_act filters on `active`,
--   so 'job_rerun' falls into its not-found branch and is refused on every call -- a refusal that
--   fires unconditionally, not one waiting on an amount. It is turned on by one UPDATE in the same
--   change that teaches cron_registry which jobs may be re-run, and not before.
--
--   NOTE ON WHY IT IS NOT A ZERO-CEILING GRANT. The accountant's refund and Meta-ads reservations use
--   max_amount_aed = 0, and that is right for them because a refund always carries an amount.
--   fn_agent_may_act only compares a ceiling when p_amount_aed IS NOT NULL. A rerun has no amount, so
--   a zero-ceiling grant here would PERMIT every call -- a guard that cannot fire, dressed as a limit.
--
-- NEVER GRANTED, and recorded in org_role.forbidden_decisions rather than as a fake grant: deploying
-- an edge function, editing code, changing production configuration or secrets, applying a schema
-- change, and mutating business data. Each line is TAGGED with the action class it refuses and then
-- names its route in words, and the runtime (supabase/functions/it_engineer/index.ts) looks the line
-- up by that tag when it refuses -- so there is one copy of the policy and the TypeScript holds none
-- of it, and the lookup is an exact match rather than a guess at the prose.
--
-- ORDER OF OPERATIONS, forced by the constraints and learned on the last three seats:
--   1 function_owner_owner_ck widened  (it refuses an unknown owner)
--   2 org_agents                       (org_role.runtime_agent_key is an FK to it)
--   3 org_role                         (ceo_standing_grant.grantee_role_id is an FK to it)
--   4 grants, credential, owner row
--   5 NO org_reporting_edge. Deliberately. See above.
--
-- NO ROUTINE IS CREATED HERE, so there is no SECURITY DEFINER function and no
-- `revoke execute ... from public` to pair with one.
--
--   node scripts/apply_sql.mjs scripts/sql/the_company_gets_an_it_engineer_who_watches_everything_and_answers_to_the_founder.sql --apply --ddl

begin;

-- 1. THE OWNER CHECK ADMITS THE FIFTH SEAT. Widened, never dropped.
alter table public.function_owner drop constraint if exists function_owner_owner_ck;
alter table public.function_owner add constraint function_owner_owner_ck
  check (owner = any (array['ceo','customer_support','sales_engineer','accountant','it_engineer','website']));

-- 2. THE AGENT. department stays NULL; there are none and there will be none.
insert into public.org_agents (agent_key, role, kind, active, title, seniority, routing_tier,
                               max_open_tasks, available)
values (
  'it_engineer',
  'IT Engineer AI -- monitors literally everything in the app and the website, diagnoses what it '
  'finds, and emails the founder directly. Reports to the founder only; there is no line to the CEO.',
  'brain',
  true,
  'IT Engineer',
  'specialist',
  'reviewer_auditor',
  40,
  true
)
on conflict (agent_key) do update
  set role = excluded.role, active = excluded.active, title = excluded.title,
      seniority = excluded.seniority, routing_tier = excluded.routing_tier,
      max_open_tasks = excluded.max_open_tasks, available = excluded.available;

-- 3. THE ROLE. responsibilities and activation_conditions are NOT NULL with no default.
--    manager_role_id stays NULL -- the same statement the missing edge makes, in the other table.
insert into public.org_role (
  role_id, display_name, runtime_mode, runtime_agent_key, authority_level,
  responsibilities, activation_conditions, owned_decisions, forbidden_decisions,
  handoff_targets, escalation_targets, manager_role_id
)
values (
  'it_engineer',
  'IT Engineer',
  'event_driven_operator',
  'it_engineer',
  'execute_low',
  'Watch everything the company runs -- the database, the edge functions, the scheduled jobs, the '
  'agent runtimes, the message and mail outboxes, the payment path, the storage buckets, the '
  'customer and supplier portals and the public website -- and be the first to know when any of it '
  'stops behaving. Diagnose what broke and say what the evidence is, row by row. Then email the '
  'founder directly so he can open a session and have it fixed. It never repairs production itself: '
  'it does not deploy, does not edit code, does not change configuration or secrets, and does not '
  'alter business data. A finding it cannot evidence is reported as unknown, never as healthy.',
  'A health check fails; a scheduled job stops running or starts failing; an edge function errors or '
  'stops answering; an agent runtime goes silent; a queue stops draining; a page or portal stops '
  'responding; an error rate, a latency or a backlog moves outside its normal band; a security or '
  'credential signal fires.',
  array[
    'what the estate is doing right now, and whether a number is a measurement or an unknown',
    'whether an observation is an incident, and at what severity',
    'what the suspected cause is, and which rows evidence it',
    'when the founder is emailed directly'
  ],
  -- EVERY LINE IS TAGGED WITH THE ACTION CLASS IT REFUSES, in square brackets at the start.
  -- That tag is what the runtime matches on, and it is here rather than in the TypeScript so the
  -- policy has exactly one home. The first draft had no tag and the runtime matched the class name
  -- against the prose as a substring; 'job_rerun' does not appear in "RE-RUNNING A SCHEDULED JOB",
  -- so that refusal came back with route null while every other one worked -- a heuristic that
  -- looked right on the case it was written against. An exact tag cannot half-match.
  array[
    '[deploy] DEPLOYING AN EDGE FUNCTION OR ANY CODE -- the route is the founder: he opens a session and the change is made and deployed there.',
    '[code_change] EDITING CODE OR APPLYING A SCHEMA CHANGE -- the route is the founder: he opens a session; this seat supplies the diagnosis it goes in with.',
    '[production_config] CHANGING PRODUCTION CONFIGURATION, ENVIRONMENT OR SECRETS -- the route is the founder: he opens a session. Rotation stays with the credential rotation that already runs on a schedule.',
    '[data_mutation] MUTATING BUSINESS DATA TO MAKE A SYMPTOM DISAPPEAR -- the route is the founder: a symptom edited away is an outage converted into confidence.',
    '[job_rerun] RE-RUNNING A SCHEDULED JOB -- withheld today, not forbidden in principle: the grant it.job_rerun exists and is inactive because cron_registry records no idempotency fact. The route is the founder until that register can bound it.',
    '[ceo_direction] REPORTING TO, OR TAKING DIRECTION FROM, THE CEO -- the founder ruled on 9 Sep 2026 that this seat reports to him directly only.'
  ],
  array[]::text[],
  array['founder'],
  null
)
on conflict (role_id) do update
  set display_name = excluded.display_name, runtime_mode = excluded.runtime_mode,
      runtime_agent_key = excluded.runtime_agent_key, authority_level = excluded.authority_level,
      responsibilities = excluded.responsibilities,
      activation_conditions = excluded.activation_conditions,
      owned_decisions = excluded.owned_decisions,
      forbidden_decisions = excluded.forbidden_decisions,
      handoff_targets = excluded.handoff_targets,
      escalation_targets = excluded.escalation_targets,
      manager_role_id = excluded.manager_role_id;

-- 4. NO REPORTING EDGE. There is deliberately no insert into public.org_reporting_edge here.
--    The closing assertion below fails if one ever appears.

-- 5. THE STANDING GRANTS. issued_by is CHECK-constrained to 'ceo' -- that column names the ISSUER of
--    the standing authority, which is the company's decision seat, and it does not create a reporting
--    line. The founder set this seat's boundaries; the CEO's grant register is where every seat's
--    authority is written, and putting this seat outside it would leave its authority nowhere.
insert into public.ceo_standing_grant
  (grant_key, grantee_role_id, action_class, scope_note, limit_note, max_amount_aed, issued_by, active)
values
  ('it.monitoring', 'it_engineer', 'monitoring',
   'Read anything the company runs, without exception: every table and view in public, the health and '
   'incident records, scheduled-job history, edge-function logs and responses, agent run history, the '
   'message, mail and notification outboxes, the payment path, storage buckets, and the public '
   'website and both portals as an anonymous visitor sees them. "Monitor literally everything in the '
   'app and the website" -- the founder, 9 Sep 2026.',
   'Read-only. A reading it cannot take is reported as unknown; it is never defaulted to zero and '
   'never reported as healthy. A zero must always carry the window it was measured over, because a '
   'dead probe and a quiet system both print 0.',
   null, 'ceo', true),

  ('it.diagnosis', 'it_engineer', 'diagnosis',
   'Turn an observation into a diagnosis and record it: open and update an incident of its own, set a '
   'severity, name the suspected cause, and bind that cause to the rows that evidence it. Writing its '
   'own findings is the whole of this grant.',
   'It may write ONLY its own records -- incidents, findings and its own agent_runs rows. A diagnosis '
   'that cannot be bound to evidence is recorded as unconfirmed, never asserted. It may not touch the '
   'subject it is diagnosing.',
   null, 'ceo', true),

  ('it.escalation', 'it_engineer', 'escalation',
   'Email the founder directly when something is wrong. "Once their is an issue, he will email me '
   'directly so i can open a session with you to fix it" -- the founder, 9 Sep 2026. This is the only '
   'seat whose escalation leaves the company rather than landing on the CEO, and it is the reason the '
   'seat exists.',
   'Routed through public.founder_mail_policy like every other founder-facing mail, so the founder can '
   'silence a class without silencing the seat. An alert must name what was measured, over what '
   'window, and what is NOT known -- an alert that cannot be acted on wastes the session it triggers.',
   null, 'ceo', true),

  -- REGISTERED AND WITHHELD. The reasoning is in this file's header, at length, because a row that
  -- is off for a reason and a row nobody got round to look identical in the table.
  ('it.job_rerun', 'it_engineer', 'job_rerun',
   'Re-run a scheduled job that has just failed -- the one remediation worth considering for a seat '
   'that may not deploy, may not edit code and may not change configuration, because it causes only '
   'what the scheduler was already going to cause.',
   'INACTIVE as of 9 Sep 2026, and inactive is the whole ruling. public.cron_registry (230 rows: '
   'jobname, human_name, category, purpose) records NO idempotency fact about any job, and several '
   'registered jobs send real messages to real people, so "only idempotent jobs" would be a limit no '
   'query could enforce. fn_agent_may_act filters on active, so job_rerun falls into its not-found '
   'branch and is refused on every call. A zero ceiling was rejected deliberately: a rerun carries no '
   'amount, and fn_agent_may_act only compares a ceiling when an amount is passed, so a zero-ceiling '
   'grant would permit every call. Turn this on in the same change that teaches cron_registry which '
   'jobs may be re-run -- not before.',
   null, 'ceo', false)
on conflict (grant_key) do update
  set scope_note = excluded.scope_note, limit_note = excluded.limit_note,
      max_amount_aed = excluded.max_amount_aed, active = excluded.active;

-- 6. THE SCOPED CREDENTIAL. The value is generated here and never leaves the database.
--    THE SCOPE NAMES ONLY WHAT THIS CREDENTIAL MAY CALL, and today that is exactly one function --
--    the seat's own runtime. It calls nothing else, so nothing else is in the scope; an empty
--    allowance widened later is a decision somebody has to write down, which is the point.
do $mint$
declare v_secret text;
begin
  if exists (select 1 from public.internal_credential where context = 'fn.it_engineer') then
    raise notice 'fn.it_engineer already exists -- left untouched';
    return;
  end if;
  v_secret := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.internal_credential (context, label, secret_hash, scope, is_legacy, active)
  values ('fn.it_engineer',
          'The IT Engineer seat -- monitoring, diagnosis and direct escalation to the founder',
          public.fn_internal_credential_hash(v_secret),
          array['it_engineer'], false, true);
  insert into public.app_secrets (key, value)
  values ('cred_fn_it_engineer', v_secret)
  on conflict (key) do update set value = excluded.value;
end
$mint$;

-- 7. THE OWNER ROW FOR THE SEAT'S OWN RUNTIME, registered BEFORE the deploy so the registry is never
--    behind the estate. Same order as accountant, sales_engineer and ceo_agent.
insert into public.function_owner (function_slug, owner, note)
values ('it_engineer', 'it_engineer',
        'The IT Engineer seat''s own runtime. The founder, 9 Sep 2026: "we build the it engineer to '
        'monitor everything. once their is an issue, he will email me directly so i can open a '
        'session with you to fix it... he reports to me directly only. however he monitor literally '
        'everything in the app and the website." Deterministic only, and no model is called. The '
        'credential decides the seat: fn.it_engineer, never a name read off the request body. It '
        'diagnoses and escalates; it does not deploy, edit code or change production configuration, '
        'and each of those refusals names the founder as the route, read out of '
        'org_role.forbidden_decisions rather than hardcoded.')
on conflict (function_slug) do update
  set owner = excluded.owner, note = excluded.note;

-- 8. THE CLOSING ASSERTION.
do $check$
declare
  v_agent int; v_role int; v_edge int; v_grants int; v_active_grants int; v_cred int; v_owner int;
  v_names text; v_off_roster int; v_bad_edges int;
  v_mon jsonb; v_diag jsonb; v_esc jsonb; v_rerun jsonb; v_deploy jsonb;
  v_support jsonb; v_refund jsonb; v_esc_targets text[]; v_forbidden int;
  v_untagged int; v_tagged int;
begin
  select count(*) into v_agent  from public.org_agents where agent_key = 'it_engineer' and active;
  select count(*) into v_role   from public.org_role   where role_id   = 'it_engineer' and status = 'active';
  select count(*) into v_edge   from public.org_reporting_edge where child_role_id = 'it_engineer';
  select count(*) into v_grants from public.ceo_standing_grant where grantee_role_id = 'it_engineer';
  select count(*) into v_active_grants from public.ceo_standing_grant
    where grantee_role_id = 'it_engineer' and active;
  select count(*) into v_cred   from public.internal_credential
    where context = 'fn.it_engineer' and active and 'it_engineer' = any(scope);
  select count(*) into v_owner  from public.function_owner
    where function_slug = 'it_engineer' and owner = 'it_engineer';
  select escalation_targets, array_length(forbidden_decisions, 1)
    into v_esc_targets, v_forbidden from public.org_role where role_id = 'it_engineer';

  if v_agent <> 1 or v_role <> 1 or v_grants <> 4 or v_active_grants <> 3
     or v_cred <> 1 or v_owner <> 1 then
    raise exception 'SEAT NOT ESTABLISHED: agent=% role=% grants=% active_grants=% cred=% owner=%',
      v_agent, v_role, v_grants, v_active_grants, v_cred, v_owner;
  end if;

  -- THE FOUNDER-REPORTING EXCEPTION, ASSERTED RATHER THAN LEFT AS A MISSING ROW. "He reports to me
  -- directly only." An edge appearing here later is a silent reorganisation, so it fails loudly.
  if v_edge <> 0 then
    raise exception 'THE IT ENGINEER WAS EDGED INTO THE ORG CHART: % edge(s) exist for it_engineer, expected 0. The founder ruled on 9 Sep 2026 that this seat reports to him directly only.', v_edge;
  end if;
  if not ('founder' = any(coalesce(v_esc_targets, array[]::text[]))) then
    raise exception 'THE SEAT HAS NO EDGE AND NAMES NO ESCALATION EITHER: escalation_targets=%. That is not "reports to the founder", it is a seat that reports to nobody.', v_esc_targets;
  end if;
  if coalesce(v_forbidden, 0) < 6 then
    raise exception 'THE REFUSALS DO NOT NAME THEIR ROUTES: forbidden_decisions holds % line(s), expected 6. The runtime reads its refusal routes out of this column.', coalesce(v_forbidden, 0);
  end if;
  -- EVERY LINE MUST CARRY ITS CLASS TAG, and the two classes the runtime asks about by name must be
  -- among them. Without this, a line edited into untagged prose would silently start returning route
  -- null -- which is exactly the defect the probe caught on the first run of this file.
  select count(*) into v_untagged from public.org_role, unnest(forbidden_decisions) f
   where role_id = 'it_engineer' and f !~ '^\[[a-z_]+\] ';
  if v_untagged <> 0 then
    raise exception 'A REFUSAL LINE CARRIES NO CLASS TAG: % line(s) do not start with [class]. The runtime looks a route up by that tag and would return null for them.', v_untagged;
  end if;
  select count(*) into v_tagged from public.org_role, unnest(forbidden_decisions) f
   where role_id = 'it_engineer' and (f like '[deploy]%' or f like '[job_rerun]%');
  if v_tagged <> 2 then
    raise exception 'THE TWO CLASSES THE RUNTIME ASKS ABOUT BY NAME ARE NOT BOTH TAGGED: found %, expected [deploy] and [job_rerun]', v_tagged;
  end if;

  -- WHAT IT MAY DO MUST WORK, or the seat is seated and blind.
  v_mon  := public.fn_agent_may_act('it_engineer', 'monitoring');
  v_diag := public.fn_agent_may_act('it_engineer', 'diagnosis');
  v_esc  := public.fn_agent_may_act('it_engineer', 'escalation');
  if (v_mon ->> 'may_act')::boolean is distinct from true
     or (v_diag ->> 'may_act')::boolean is distinct from true
     or (v_esc ->> 'may_act')::boolean is distinct from true then
    raise exception 'THE IT ENGINEER CANNOT WATCH, DIAGNOSE OR ESCALATE: monitoring=% diagnosis=% escalation=%',
      v_mon, v_diag, v_esc;
  end if;

  -- AND WHAT IT MAY NOT DO MUST REFUSE, at no amount at all -- which is the case a zero ceiling
  -- would have missed. Both the withheld grant and a class with no grant are checked, because they
  -- refuse through different branches of fn_agent_may_act and only one of them has a row.
  v_rerun  := public.fn_agent_may_act('it_engineer', 'job_rerun');
  v_deploy := public.fn_agent_may_act('it_engineer', 'deploy');
  if (v_rerun ->> 'may_act')::boolean is distinct from false then
    raise exception 'AN INACTIVE GRANT PERMITTED A JOB RERUN: %', v_rerun;
  end if;
  if (v_deploy ->> 'may_act')::boolean is distinct from false then
    raise exception 'THE IT ENGINEER WAS PERMITTED TO DEPLOY: %', v_deploy;
  end if;

  -- THE ROSTER IS NOW FIVE, AND EVERY EDGE STILL TERMINATES AT THE CEO. Asserted here as well as in
  -- the acceptance check, so an apply that quietly grew a sixth seat or bent an edge fails at apply
  -- time rather than at the next check run.
  select string_agg(role_id, ',' order by role_id) into v_names
    from public.org_role where status = 'active';
  select count(*) into v_off_roster from public.org_role
   where role_id not in ('accountant','ceo','customer_support','it_engineer','sales_engineer');
  select (select count(*) from public.org_reporting_edge
           where parent_role_id <> 'ceo'
              or child_role_id not in ('accountant','customer_support','sales_engineer'))
       + (select count(*) - count(distinct child_role_id) from public.org_reporting_edge)
    into v_bad_edges;
  if v_names is distinct from 'accountant,ceo,customer_support,it_engineer,sales_engineer'
     or v_off_roster <> 0 or v_bad_edges <> 0 then
    raise exception 'THE ROSTER IS NOT THE FIVE AUTHORISED SEATS: names=% off_roster=% bad_edges=%',
      v_names, v_off_roster, v_bad_edges;
  end if;

  -- THE OTHER SEATS ARE UNTOUCHED. A new seat that quietly moved somebody else's authority is a
  -- reorganisation, not an addition.
  v_support := public.fn_support_may_act('conversation');
  v_refund  := public.fn_agent_may_act('accountant', 'refund', 1);
  if (v_support ->> 'may_act')::boolean is distinct from true then
    raise exception 'SUPPORT REGRESSED: %', v_support;
  end if;
  if (v_refund ->> 'may_act')::boolean is distinct from false
     or (v_refund ->> 'route') is distinct from 'ceo_case_decision' then
    raise exception 'THE ACCOUNTANT''S REFUND ROUTE REGRESSED: %', v_refund;
  end if;

  raise notice 'it_engineer seated: 1 agent, 1 active role, 0 reporting edges (reports to the founder), 4 grants (3 active + job_rerun withheld), % forbidden decisions each naming its route, 1 credential, 1 owner row. Roster is now %.', v_forbidden, v_names;
end
$check$;

commit;
