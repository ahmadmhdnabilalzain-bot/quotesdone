// PARITY, MEASURED. "Both projects" is a claim this estate makes constantly and had never counted.
// Fetches the object inventory from production and staging and prints ONLY the difference, so the
// output is the drift rather than a wall of names.
//
//   node scripts/checks/project_parity.mjs
//
// Exits non-zero when anything diverges, so it can be a check rather than a report.
import { readFileSync, existsSync } from 'node:fs';

const PROD = 'htdblwldjkcgjvmqkbeh', STG = 'pglpqrhvozwepymcuunn';
// Env first so this runs in CI, where the local file does not exist and an ENOENT would look like a
// broken check rather than a missing credential.
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync('C:/Users/Opera/.supabase/access-token')
      ? readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')
      : '')).trim();
if (!token) { console.error('SUPABASE_ACCESS_TOKEN is not set and no local access token was found.'); process.exit(2); }

async function q(ref, sql, attempt = 0) {
  try {
    const r = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
      method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: sql }), signal: AbortSignal.timeout(120000) });
    const b = await r.text();
    if (!r.ok) throw new Error(r.status + ': ' + b.slice(0, 200));
    return JSON.parse(b);
  } catch (e) {
    if (attempt < 3) { await new Promise(s => setTimeout(s, 2000 * 2 ** attempt)); return q(ref, sql, attempt + 1); }
    throw e;
  }
}

const EXCLUDED_CRONS = JSON.parse(
  readFileSync(new URL('./staging_cron_exclusions.json', import.meta.url), 'utf8')).jobs;

const DIMENSIONS = [
  ['table', `select table_name as k from information_schema.tables
               where table_schema='public' and table_type='BASE TABLE'`],
  ['function', `select p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' as k
                  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                 where n.nspname='public' and p.prokind in ('f','p')`],
  ['trigger', `select c.relname||'.'||t.tgname as k
                 from pg_trigger t join pg_class c on c.oid=t.tgrelid
                 join pg_namespace n on n.oid=c.relnamespace
                where n.nspname='public' and not t.tgisinternal`],
  ['cron job', `select jobname as k from cron.job where active`],
  ['table WITHOUT rls', `select c.relname as k from pg_class c join pg_namespace n on n.oid=c.relnamespace
                           where n.nspname='public' and c.relkind='r' and not c.relrowsecurity`],
  ['anon-executable SECURITY DEFINER', `select p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' as k
                 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                where n.nspname='public' and p.prosecdef and has_function_privilege('anon',p.oid,'EXECUTE')`],
];

// Edge functions are not in the database, so they need the management API rather than a query.
// Compared on name + verify_jwt + status together: a function that exists on both but requires a JWT
// on one and not the other is a divergence that a name-only list would call parity.
async function edgeFns(ref, attempt = 0) {
  try {
    const r = await fetch(`https://api.supabase.com/v1/projects/${ref}/functions`, {
      headers: { Authorization: 'Bearer ' + token }, signal: AbortSignal.timeout(60000) });
    if (!r.ok) throw new Error(ref + ' ' + r.status);
    return (await r.json()).map(f => `${f.slug} [jwt=${f.verify_jwt} ${f.status}]`);
  } catch (e) {
    if (attempt < 3) { await new Promise(s => setTimeout(s, 2000 * 2 ** attempt)); return edgeFns(ref, attempt + 1); }
    throw e;
  }
}

let drift = 0;
{
  const [a, b] = await Promise.all([edgeFns(PROD), edgeFns(STG)]);
  const P = new Set(a), S = new Set(b);
  const onlyProd = [...P].filter(x => !S.has(x)).sort();
  const onlyStg = [...S].filter(x => !P.has(x)).sort();
  const head = `${'edge function'.padEnd(34)} prod ${String(P.size).padStart(4)}   staging ${String(S.size).padStart(4)}`;
  if (!onlyProd.length && !onlyStg.length) console.log(head + '   IN SYNC');
  else {
    drift += onlyProd.length + onlyStg.length;
    console.log(head + `   DRIFT  +${onlyProd.length} prod-only / +${onlyStg.length} staging-only`);
    const show = (tag, xs) => xs.length && console.log(
      `    ${tag}: ` + (xs.length > 25 ? xs.slice(0, 25).join(', ') + `, … and ${xs.length - 25} more` : xs.join(', ')));
    show('prod only', onlyProd); show('staging only', onlyStg);
  }
}

for (const [label, sql] of DIMENSIONS) {
  const [a, b] = await Promise.all([q(PROD, sql), q(STG, sql)]);
  const P = new Set(a.map(r => r.k)), S = new Set(b.map(r => r.k));
  // Crons are the one dimension where full parity is WRONG, so the exclusions are written down
  // rather than tolerated silently. A production cron missing from staging and missing from the
  // file is unintended drift and still fails.
  const excluded = label === 'cron job' ? new Set(EXCLUDED_CRONS) : new Set();
  const onlyProd = [...P].filter(x => !S.has(x) && !excluded.has(x)).sort();
  const onlyStg = [...S].filter(x => !P.has(x)).sort();
  const note = excluded.size ? `   (${[...excluded].filter(x => P.has(x) && !S.has(x)).length} excluded by decision)` : '';
  const head = `${label.padEnd(34)} prod ${String(P.size).padStart(4)}   staging ${String(S.size).padStart(4)}`;
  if (!onlyProd.length && !onlyStg.length) { console.log(head + '   IN SYNC' + note); continue; }
  drift += onlyProd.length + onlyStg.length;
  console.log(head + `   DRIFT  +${onlyProd.length} prod-only / +${onlyStg.length} staging-only`);
  const show = (tag, xs) => xs.length && console.log(
    `    ${tag}: ` + (xs.length > 25 ? xs.slice(0, 25).join(', ') + `, … and ${xs.length - 25} more` : xs.join(', ')));
  show('prod only', onlyProd);
  show('staging only', onlyStg);
}
// POPULATION, BECAUSE SHAPE PARITY IS NOT BEHAVIOUR PARITY (11 Aug 2026).
//
// This check reported BOTH PROJECTS IN SYNC on 418 = 418 tables while staging held 255 empty
// tables against production's 96, board_advisor 0 against 7, and workflow_run 7 against 198. Every
// object existed on both sides and almost nothing behaved the same. A rehearsal run on staging
// would have proved very little, and the line above would still have said IN SYNC.
//
// Deliberately NOT a drift failure. Staging is expected to hold different data, so failing on it
// would make the check permanently red and therefore ignored. It fails nothing and it is printed
// every time, so the sentence "in sync" can never again be read as "behaves the same".
const POP_SQL = `select count(*)::int total,
       count(*) filter (where n = 0)::int empty
  from (select (xpath('/row/c/text()',
                query_to_xml('select count(*) c from public.'||quote_ident(c.relname), false, true, '')
               ))[1]::text::bigint n
          from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
         where ns.nspname = 'public' and c.relkind = 'r') z`;
let popNote = '';
try {
  const [pp, ps] = await Promise.all([q(PROD, POP_SQL), q(STG, POP_SQL)]);
  const P = pp[0], S = ps[0];
  console.log(`${'table WITH rows'.padEnd(34)} prod ${String(P.total - P.empty).padStart(4)}   `
    + `staging ${String(S.total - S.empty).padStart(4)}   `
    + `POPULATION (not compared — staging data differs by design)`);
  console.log(`${'table EMPTY'.padEnd(34)} prod ${String(P.empty).padStart(4)}   `
    + `staging ${String(S.empty).padStart(4)}`
    + (S.empty > P.empty ? `   staging has ${S.empty - P.empty} more empty table(s) than production` : ''));
  popNote = ` (shape only — ${P.empty} empty table(s) on prod, ${S.empty} on staging)`;
} catch (e) {
  // A population read that fails must not turn a green shape check red, but it must not be silent
  // either: an unreported failure here is exactly the blind spot this block exists to close.
  console.log(`${'table population'.padEnd(34)} COULD NOT MEASURE: ${String(e.message || e).slice(0, 90)}`);
  popNote = ' (shape only — population NOT measured this run)';
}

console.log(drift ? `\nTOTAL DRIFT: ${drift} object(s)` : `\nBOTH PROJECTS IN SYNC${popNote}`);
process.exit(drift ? 1 : 0);
