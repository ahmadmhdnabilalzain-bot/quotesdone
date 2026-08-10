// STAGING'S anon ROLE COULD EXECUTE 520 SECURITY DEFINER FUNCTIONS. PRODUCTION'S CAN EXECUTE 56.
//
// A SECURITY DEFINER function runs as its owner, so an anon grant on one is a hole punched straight
// through RLS. Staging is not "only staging": it is the surface this estate rehearses production on,
// and a rehearsal surface with 464 extra holes cannot rehearse production's posture -- every drill
// that should have failed closed there would have passed.
//
// Production is the reference, per role, and the operation is subtractive only: staging loses
// EXECUTE on every SECURITY DEFINER function that production does not grant. Nothing is granted that
// was not already granted, so this cannot open anything.
//
//   node scripts/sql/staging_grant_parity.mjs [--apply]
//
// Without --apply it prints the counts and changes nothing.
import { readFileSync } from 'node:fs';

const PROD = 'htdblwldjkcgjvmqkbeh', STG = 'pglpqrhvozwepymcuunn';
const APPLY = process.argv.includes('--apply');
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

async function q(ref, sql, attempt = 0) {
  try {
    const r = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
      method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: sql }), signal: AbortSignal.timeout(180000) });
    const b = await r.text();
    if (!r.ok) throw new Error(ref + ' ' + r.status + ': ' + b.slice(0, 300));
    return JSON.parse(b);
  } catch (e) {
    if (attempt < 3) { await new Promise(s => setTimeout(s, 2000 * 2 ** attempt)); return q(ref, sql, attempt + 1); }
    throw e;
  }
}

const listed = (role) => `select p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' as sig
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.prosecdef and has_function_privilege('${role}', p.oid, 'EXECUTE')`;

const lit = (s) => "'" + s.replace(/'/g, "''") + "'";

// THE GRANT IS FROM PUBLIC, NOT FROM anon. `revoke ... from anon` is a silent no-op against a
// privilege held through PUBLIC, and the first run of this script proved it: 464 revokes executed
// and the count did not move. Staging's rows read `=X/postgres | postgres=X | service_role=X` -- the
// leading `=X` IS the PUBLIC grant that CREATE FUNCTION hands out. Production's read
// `postgres=X | service_role=X` on all 499: PUBLIC revoked, service_role granted EXPLICITLY.
// So revoking PUBLIC on staging lands on production's exact ACL shape, and service_role -- which is
// what every edge function and pg_net call authenticates as -- keeps EXECUTE through its own grant.
const keepAnon = new Set((await q(PROD, listed('anon'))).map(r => r.sig));
const keepAuth = new Set((await q(PROD, listed('authenticated'))).map(r => r.sig));
const stgAll = (await q(STG, `select p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' as sig
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.prosecdef
     and (has_function_privilege('anon', p.oid, 'EXECUTE')
       or has_function_privilege('authenticated', p.oid, 'EXECUTE'))`)).map(r => r.sig);
const strip = stgAll.filter(s => !keepAnon.has(s) && !keepAuth.has(s));

console.log(`production grants anon ${keepAnon.size} / authenticated ${keepAuth.size}`);
console.log(`staging reachable by either: ${stgAll.length}; to revoke from PUBLIC: ${strip.length}`);

if (strip.length && APPLY) {
  for (let i = 0; i < strip.length; i += 60) {
    await q(STG, `do $$
declare s text;
begin
  foreach s in array array[${strip.slice(i, i + 60).map(lit).join(',')}] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', s);
  end loop;
end $$;`);
    process.stdout.write(`  revoked ${Math.min(i + 60, strip.length)}/${strip.length}\r`);
  }
  console.log();
}
if (strip.length) {
  for (const role of ['anon', 'authenticated']) {
    const after = (await q(STG, listed(role))).length;
    const want = role === 'anon' ? keepAnon.size : keepAuth.size;
    console.log(`  ${role}: staging ${after}, production ${want}` + (after === want ? '  MATCHED' : '  STILL DIVERGENT'));
  }
  const svc = (await q(STG, `select count(*) as n from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.prosecdef and has_function_privilege('service_role', p.oid, 'EXECUTE')`))[0].n;
  console.log(`  service_role still executes ${svc} of them (this is what the edge functions use)`);
}
