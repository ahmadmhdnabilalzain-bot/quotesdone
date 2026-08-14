// IDENTITY RESOLUTION COVERAGE — inventory and guard, in one file.
//
// Section 2 of the organisation-runtime closure brief asks for two things: an inventory of every
// routine that accepts an agent/actor/assignee/reviewer/manager/role/employee identifier, and a
// guard that fails whenever a NEW relevant routine bypasses the canonical resolver.
//
// WHY THIS MATTERS, measured rather than asserted. On 14 Aug 2026 fn_pick_reviewer compared the
// author to the department head as a raw string. All ten department heads carry aliases, so an
// author passed as "Finance Director" was not equal to "cfo", the self-review guard did not fire,
// and the function returned the author as its own reviewer — in all ten departments. The resolver
// that would have caught it, fn_org_agent_resolve, already existed and was simply never called.
//
// So the property this file protects is NOT "the resolver exists". It is "every routine that
// COMPARES an identity resolves it first". A routine that merely stores an identity it was given
// is not at risk; a routine that tests one for equality is, because an alias is a different string
// for the same employee.
//
//   node scripts/checks/org_identity_coverage.mjs            # guard: fails on a new offender
//   node scripts/checks/org_identity_coverage.mjs --write    # also regenerate the CSV
//
// CI runs npm test with no SUPABASE_ACCESS_TOKEN. This skips there rather than failing on a 401
// that reads like a data failure and is not one.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

if (!token) {
  console.log('SKIP org_identity_coverage: no SUPABASE_ACCESS_TOKEN (expected in CI)');
  process.exit(0);
}

const PROD = 'htdblwldjkcgjvmqkbeh';
const BASELINE = 'scripts/checks/org_identity_coverage_baseline.json';
const CSV = 'docs/agents/IDENTITY_RESOLUTION_COVERAGE.csv';
const WRITE = process.argv.includes('--write');

// The identity parameters. p_by / p_owner / p_author are included deliberately: an approver
// recorded as "decided_by" is an identity, and comparing it to an author is exactly the check
// that the 182 historical self-approvals needed.
const IDENT_PARAM = `p_(agent|actor|assignee|reviewer|manager|role|employee|author|owner|by|addressee)`;
const RESOLVERS = `fn_org_agent_resolve|fn_org_role_resolve|fn_dept_canonical|fn_resolve_cat_agent|fn_dept_scope`;

const QUERY = `
with f as (
  select p.oid, p.proname,
         pg_get_function_arguments(p.oid) as args,
         pg_get_functiondef(p.oid)        as def,
         l.lanname                        as lang,
         p.prosecdef                      as security_definer
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_language  l on l.oid = p.prolang
   where n.nspname = 'public' and p.prokind = 'f'
     and pg_get_function_arguments(p.oid) ~ '${IDENT_PARAM}'
)
select proname, args, lang, security_definer,
       (select string_agg(distinct m[1], ' ')
          from regexp_matches(args, '(${IDENT_PARAM}[a-z_]*)', 'g') m) as identity_params,
       (def ~ '${RESOLVERS}')                                          as resolves,
       -- the risk test: does the body COMPARE an identity parameter, or filter a table by one?
       (def ~ '(=|<>|is distinct from)\\s*${IDENT_PARAM}[a-z_]*'
        or def ~ '(agent_key|actor|assignee[a-z_]*|owner[a-z_]*|author[a-z_]*|reviewer[a-z_]*)\\s*=\\s*p_') as compares_identity,
       -- does it write a new row carrying the identity? new writes must use the canonical id.
       (def ~ 'insert\\s+into')                                        as writes
  from f
 order by proname, args`;

const r = await fetch(`https://api.supabase.com/v1/projects/${PROD}/database/query`, {
  method: 'POST',
  headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
  body: JSON.stringify({ query: QUERY }),
});
if (!r.ok) { console.error(`query failed: ${r.status} ${await r.text()}`); process.exit(1); }
const rows = await r.json();

// An offender is a routine that COMPARES an identity without resolving it first. Those are the
// ones an alias silently breaks; a routine that only stores what it was handed is not at risk.
const offenders = rows.filter((x) => x.compares_identity && !x.resolves).map((x) => x.proname);
const uniqOffenders = [...new Set(offenders)].sort();

if (WRITE) {
  const esc = (v) => {
    const s = v === null || v === undefined ? '' : String(v);
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const head = [
    'routine', 'identity_params', 'language', 'security_definer',
    'resolves_canonically', 'compares_identity', 'performs_writes',
    'risk', 'verdict',
  ];
  const body = rows.map((x) => {
    const risk = x.compares_identity && !x.resolves ? 'alias_breaks_comparison'
      : x.compares_identity ? 'comparison_resolved'
        : x.writes ? 'stores_identity_only' : 'reads_only';
    const verdict = x.compares_identity && !x.resolves ? 'MUST RESOLVE'
      : x.resolves ? 'OK - resolves' : 'OK - no identity comparison';
    return [x.proname, x.identity_params, x.lang, x.security_definer,
      x.resolves, x.compares_identity, x.writes, risk, verdict].map(esc).join(',');
  });
  writeFileSync(CSV, head.join(',') + '\n' + body.join('\n') + '\n');
  console.log(`wrote ${CSV} (${rows.length} routines)`);
}

const baseline = existsSync(BASELINE)
  ? JSON.parse(readFileSync(BASELINE, 'utf8'))
  : { known_unresolved: [], note: '' };

const known = new Set(baseline.known_unresolved);
const added = uniqOffenders.filter((n) => !known.has(n));
const fixed = [...known].filter((n) => !uniqOffenders.includes(n));

console.log(`routines taking an identity : ${rows.length}`);
console.log(`resolve canonically         : ${rows.filter((x) => x.resolves).length}`);
console.log(`compare an identity         : ${rows.filter((x) => x.compares_identity).length}`);
console.log(`  of those, unresolved      : ${uniqOffenders.length}  (baseline ${known.size})`);

if (fixed.length) {
  console.log(`\n${fixed.length} routine(s) now resolve that did not before:`);
  for (const n of fixed) console.log(`  + ${n}`);
  console.log('Remove them from the baseline so the count can only go down:');
  console.log(`  node scripts/checks/org_identity_coverage.mjs --rebaseline`);
}

// process.exit() with the fetch keep-alive socket still open trips a libuv assertion on Windows
// and the shell then reports 127, which reads like "node not found" rather than "check failed".
// Setting exitCode and letting the process end naturally gives CI the real 0/1.
const done = (code) => { process.exitCode = code; };

if (process.argv.includes('--rebaseline')) {
  writeFileSync(BASELINE, JSON.stringify({
    note: 'Routines that compare an identity parameter without resolving it first. This list may '
        + 'only ever SHRINK. A new name here means a new routine can be defeated by an alias - see '
        + 'the header of scripts/checks/org_identity_coverage.mjs for the measured example.',
    measured_at: new Date().toISOString().slice(0, 10),
    known_unresolved: uniqOffenders,
  }, null, 2) + '\n');
  console.log(`rebaselined ${BASELINE} at ${uniqOffenders.length} routine(s)`);
  done(0);
} else if (added.length) {
  console.error(`\nFAIL: ${added.length} routine(s) compare an identity without resolving it and are`);
  console.error('not in the baseline. An alias for the same employee is a different string, so the');
  console.error('comparison below is defeated by spelling — this is how fn_pick_reviewer returned');
  console.error('the author as its own reviewer in all ten departments.');
  for (const n of added) console.error(`  - public.${n}()`);
  console.error('\nFix: resolve the parameter once at the top of the routine, e.g.');
  console.error("  p_author := coalesce(public.fn_org_agent_resolve(p_author), p_author);");
  console.error('Every downstream comparison then reads the canonical identity.');
  done(1);
} else {
  console.log('\nOK: no new routine compares an identity without resolving it.');
  done(0);
}
