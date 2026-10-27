// PROBE — the IT Engineer seat and its DEPLOYED runtime, against PRODUCTION.
//
// The founder, 9 September 2026: "fine then we build the it engineer to monitor everything. once
// their is an issue, he will email me directly so i can open a session with you to fix it... he
// reports to me directly only. however he monitor literally everything in the app and the website"
//
// EVERY ASSERTION HERE IS ABOUT SOMETHING THAT WOULD OTHERWISE BE A CLAIM:
//   * POSITIVE CONTROLS FIRST. The seat, the role, the grants and the credential must be READ out of
//     production before anything is asserted about behaviour. Zero cannot tell a dead guard from an
//     idle system, and a refusal proved by a missing seat proves nothing.
//   * THE CREDENTIAL DECIDES THE SEAT. A valid credential belonging to ANOTHER seat must be refused,
//     not accepted as this one. That is the ceo_agent confused-deputy defect, tested rather than
//     assumed.
//   * THE PERMITS PERMIT AND THE REFUSALS REFUSE, against the DEPLOYED function, and every refusal
//     names its route.
//   * NO REPORTING EDGE, asserted as a property of the founder's ruling rather than observed as an
//     absence.
//
// Nothing here writes to production except the agent_runs rows the function writes for itself, which
// is the seat's own liveness signal and the thing being tested in step 6.
//
//   node scripts/probe_it_engineer_seat_and_runtime.mjs
import { supabaseAccessToken } from './lib/supabase_token.mjs';
import { readFileSync } from 'node:fs';

const REF = 'htdblwldjkcgjvmqkbeh';
const token = supabaseAccessToken();

async function sql(query, attempt = 0) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  const t = await r.text();
  if ((r.status === 429 || r.status >= 500) && attempt < 6) {
    await new Promise((s) => setTimeout(s, 2000 * (attempt + 1)));
    return sql(query, attempt + 1);
  }
  if (!r.ok) return { error: t };
  return { rows: JSON.parse(t) };
}
const one = async (q) => (await sql(q)).rows?.[0];

let fails = 0;
const check = (name, ok, detail) => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail === undefined ? '' : '  — ' + detail}`);
  if (!ok) fails++;
};

// ── 0. POSITIVE CONTROLS ────────────────────────────────────────────────────────────────────────
console.log('-- POSITIVE CONTROLS: the seat must exist before anything about it can be tested --');
const ctl = await one(`select
  (select count(*) from org_agents where agent_key='it_engineer' and active and available) seat,
  (select count(*) from org_role where role_id='it_engineer' and status='active') role,
  (select count(*) from org_reporting_edge where child_role_id='it_engineer') edges,
  (select count(*) from ceo_standing_grant where grantee_role_id='it_engineer') grants,
  (select count(*) from ceo_standing_grant where grantee_role_id='it_engineer' and active) active_grants,
  (select count(*) from internal_credential where context='fn.it_engineer' and active and 'it_engineer'=any(scope)) cred,
  (select count(*) from function_owner where function_slug='it_engineer' and owner='it_engineer') owner,
  (select array_length(forbidden_decisions,1) from org_role where role_id='it_engineer') forbidden,
  (select escalation_targets from org_role where role_id='it_engineer') esc,
  (select string_agg(role_id,',' order by role_id) from org_role where status='active') roster,
  (select count(*) from org_role where role_id not in ('accountant','ceo','customer_support','it_engineer','sales_engineer')) off_roster`);
console.log(ctl);
check('the seat exists in org_agents, active and available', Number(ctl.seat) === 1);
check('the role exists in org_role and is active', Number(ctl.role) === 1);
check('four grants exist, three of them active', Number(ctl.grants) === 4 && Number(ctl.active_grants) === 3,
  `${ctl.grants} grants / ${ctl.active_grants} active`);
check('the fn.it_engineer credential exists, active, scoped to it_engineer', Number(ctl.cred) === 1);
check('the seat owns its own runtime in function_owner', Number(ctl.owner) === 1);
check('every refusal has a line naming its route', Number(ctl.forbidden) === 6, `${ctl.forbidden} lines`);

// ── 1. THE FOUNDER-REPORTING EXCEPTION ──────────────────────────────────────────────────────────
console.log('\n-- "he reports to me directly only" --');
check('the seat holds NO reporting edge', Number(ctl.edges) === 0, `${ctl.edges} edge(s)`);
check('and it names the founder as its escalation, so it reports to somebody',
  Array.isArray(ctl.esc) ? ctl.esc.includes('founder') : String(ctl.esc).includes('founder'),
  JSON.stringify(ctl.esc));
check('the roster is now exactly five seats',
  ctl.roster === 'accountant,ceo,customer_support,it_engineer,sales_engineer', ctl.roster);
check('no seat exists outside the roster under any status', Number(ctl.off_roster) === 0);

// ── 2. THE AUTHORITY RULE, IN THE DATABASE ──────────────────────────────────────────────────────
console.log('\n-- the standing grants, asked of fn_agent_may_act --');
const auth = await one(`select
  fn_agent_may_act('it_engineer','monitoring')  mon,
  fn_agent_may_act('it_engineer','diagnosis')   diag,
  fn_agent_may_act('it_engineer','escalation')  esc,
  fn_agent_may_act('it_engineer','job_rerun')   rerun,
  fn_agent_may_act('it_engineer','deploy')      deploy,
  fn_agent_may_act('it_engineer','job_rerun',0) rerun_zero`);
console.log(JSON.stringify(auth, null, 2));
check('monitoring is permitted', auth.mon?.may_act === true);
check('diagnosis is permitted', auth.diag?.may_act === true);
check('escalation is permitted', auth.esc?.may_act === true);
check('a job rerun is refused (the withheld grant)', auth.rerun?.may_act === false);
// THE TRAP THAT WAS AVOIDED, TESTED. A zero CEILING would have permitted this, because
// fn_agent_may_act only compares max_amount_aed when an amount is passed and a rerun has none.
// active=false refuses through the not-found branch, which fires whatever the amount is.
check('a job rerun is still refused when an amount IS passed', auth.rerun_zero?.may_act === false);
check('deploying is refused', auth.deploy?.may_act === false);

// ── 3. THE DEPLOYED FUNCTION ────────────────────────────────────────────────────────────────────
const secrets = (await sql(`select key, value from app_secrets
  where key in ('cred_fn_it_engineer','cred_fn_accountant','anon_key','inbound_secret')`)).rows;
const S = Object.fromEntries(secrets.map((r) => [r.key, r.value]));
check('the seat\'s credential is readable from app_secrets', !!S.cred_fn_it_engineer);
const FN = `https://${REF}.supabase.co/functions/v1/it_engineer`;

async function call(body, secret = S.cred_fn_it_engineer) {
  const r = await fetch(FN, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + S.anon_key },
    body: JSON.stringify(secret === null ? body : { ...body, __secret: secret }),
  });
  return { status: r.status, json: await r.json().catch(() => null) };
}

console.log('\n-- THE CREDENTIAL DECIDES THE SEAT (the ceo_agent confused-deputy defect) --');
const noCred = await call({ action: 'health' }, null);
check('no credential is refused 401', noCred.status === 401, `HTTP ${noCred.status}`);
const wrongCred = await call({ action: 'health' }, S.cred_fn_accountant);
check('ANOTHER SEAT\'S valid credential is refused, not accepted as this seat',
  wrongCred.status === 401, `HTTP ${wrongCred.status} ${JSON.stringify(wrongCred.json)}`);
if (S.inbound_secret) {
  const legacy = await call({ action: 'health' }, S.inbound_secret);
  check('the legacy shared secret cannot present as this seat', legacy.status === 401,
    `HTTP ${legacy.status}`);
} else {
  console.log('SKIP  the legacy shared secret is not in app_secrets, so it cannot be presented');
}
const spoof = await call({ action: 'health', as: 'ceo', seat: 'ceo', agent: 'ceo' });
check('a seat name in the request body changes nothing', spoof.json?.seat === 'it_engineer',
  `seat=${spoof.json?.seat}`);

console.log('\n-- HEALTH --');
const health = await call({ action: 'health' });
console.log(JSON.stringify({
  status: health.status, seat: health.json?.seat, caller: health.json?.caller,
  authenticated_by: health.json?.authenticated_by, seated: health.json?.seated,
  reports_to: health.json?.reports_to, reporting_edges: health.json?.reporting_edges,
  reports_to_founder: health.json?.reports_to_founder,
  authority: health.json?.authority, grants: health.json?.grants?.map((g) => `${g.grant}(${g.active ? 'active' : 'WITHHELD'})`),
  refuses: health.json?.refuses, reaches: health.json?.reaches,
  owns_functions: health.json?.owns_functions, founder_route: health.json?.founder_route,
  watching: health.json?.watching, model_calls_available: health.json?.model_calls_available,
}, null, 2));
check('health answers 200', health.status === 200);
check('health names the credential that authenticated it',
  health.json?.authenticated_by === 'fn.it_engineer', String(health.json?.authenticated_by));
check('health reports the seat as seated', health.json?.seated === true);
check('health reports 0 reporting edges and reports_to null',
  health.json?.reporting_edges === 0 && health.json?.reports_to === null);
check('health reports it reports to the founder', health.json?.reports_to_founder === true);
check('health lists all four grants, one of them withheld',
  (health.json?.grants || []).length === 4 && (health.json?.grants || []).filter((g) => !g.active).length === 1);
check('health names what the credential may reach',
  Array.isArray(health.json?.reaches?.may_call) && health.json.reaches.may_call.includes('it_engineer'),
  JSON.stringify(health.json?.reaches?.may_call));
check('health says it owns its own runtime',
  (health.json?.owns_functions || []).includes('it_engineer'));
// THE MEASUREMENT THAT IS NOT TAKEN IS DECLARED AS NOT TAKEN.
check('health declares that it measured NOTHING about the estate',
  health.json?.watching?.readings === null && /NOTHING WAS MEASURED/.test(String(health.json?.watching?.basis)));
check('health carries the monitoring charter read from the grant',
  typeof health.json?.watching?.charter === 'string' && health.json.watching.charter.length > 50);

console.log('\n-- HEALTH: THE PERMITS AND THE REFUSALS, THROUGH THE DEPLOYED FUNCTION --');
const A = health.json?.authority || {};
check('monitoring permits and names its grant', A.monitoring?.may_act === true && A.monitoring?.grant === 'it.monitoring');
check('diagnosis permits', A.diagnosis?.may_act === true);
check('escalation permits', A.escalation?.may_act === true);
check('job_rerun refuses', A.job_rerun?.may_act === false);
check('deploy refuses', A.deploy?.may_act === false);
check('the deploy refusal NAMES ITS ROUTE, and the route is the founder',
  typeof A.deploy?.route === 'string' && /founder/i.test(A.deploy.route) && A.deploy?.route_owner === 'founder',
  A.deploy?.route);
check('the job_rerun refusal names its route too',
  typeof A.job_rerun?.route === 'string' && /founder/i.test(A.job_rerun.route), A.job_rerun?.route);
check('the refusal still carries fn_agent_may_act\'s own answer, unedited',
  A.deploy?.authority_rule?.may_act === false && typeof A.deploy?.authority_rule?.reason === 'string');

console.log('\n-- AUTHORITY: one class at a time, the door the engine will knock on --');
const aMon = await call({ action: 'authority', action_class: 'monitoring' });
const aDep = await call({ action: 'authority', action_class: 'deploy' });
const aUnk = await call({ action: 'authority', action_class: 'zz_demo_class_that_does_not_exist' });
console.log(JSON.stringify({ monitoring: aMon.json, deploy: aDep.json, unknown: aUnk.json }, null, 2));
check('authority permits monitoring', aMon.json?.may_act === true);
check('authority refuses deploy and names the founder route',
  aDep.json?.may_act === false && /founder/i.test(String(aDep.json?.route)) && aDep.json?.route_owner === 'founder');
check('an UNKNOWN class is refused with route null, not an invented one',
  aUnk.json?.may_act === false && aUnk.json?.route === null, JSON.stringify(aUnk.json?.route));
check('authority requires a class', (await call({ action: 'authority' })).status === 400);

console.log('\n-- STATUS: one call a human can read --');
const status = await call({ action: 'status' });
console.log(status.json?.summary);
check('status answers 200', status.status === 200);
check('status carries a readable summary', typeof status.json?.summary === 'string' && status.json.summary.length > 200);
check('the summary says it reports to the founder directly', /reports to the founder directly/i.test(String(status.json?.summary)));
check('the summary says nothing about the estate was measured',
  /NOTHING ABOUT THE ESTATE WAS MEASURED/.test(String(status.json?.summary)));

console.log('\n-- UNKNOWN ACTION NAMES THE SEAM --');
const unknown = await call({ action: 'zz_demo_not_an_action' });
check('an unknown action is a 400 that names the real actions and the seam',
  unknown.status === 400 && (unknown.json?.actions || []).join(',') === 'health,status,authority'
    && /separate build/i.test(String(unknown.json?.note)), JSON.stringify(unknown.json));

// ── 6. THE SEAT WRITES ITS OWN LIVENESS ─────────────────────────────────────────────────────────
console.log('\n-- agent_runs: the only liveness signal the estate has --');
const runs = await one(`select count(*) n, max(finished_at) last,
  count(*) filter (where finished_at > now() - interval '10 minutes') recent
  from agent_runs where agent='it_engineer'`);
console.log(runs);
check('the seat wrote agent_runs rows for the calls just made', Number(runs.recent) > 0,
  `${runs.recent} row(s) in the last 10 minutes, ${runs.n} in total`);

console.log(`\n${fails === 0 ? 'ALL PASS' : fails + ' FAILURE(S)'}`);
process.exit(fails === 0 ? 0 : 1);
