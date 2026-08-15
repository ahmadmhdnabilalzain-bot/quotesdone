// Phase C Stage C1 — measure every current runtime component in the estate.
//
//   node scripts/phase_c/inventory.mjs        # writes docs/phase-c/_inventory.json
//
// It writes the file itself rather than relying on shell redirection: PowerShell's `>`
// prepends a UTF-8 BOM, which JSON.parse refuses.
//
// Phase B measured the same estate with a coarser vocabulary.  This re-measures rather
// than re-reads, because the Phase C classification turns on facts Phase B did not
// record per component: whether the component MUTATES state, what actually calls it,
// and whether it has ever executed.
//
// The rule: existence is not connection.  Every artefact below carries its callers and,
// where the estate records one, its run history — so an unconnected capability appears
// as unconnected instead of being read as working.
import { readdirSync, existsSync, readFileSync, statSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { sql } from './lib/db.mjs';
import { REPO } from './lib/package.mjs';

const FN_DIR = join(REPO, 'supabase', 'functions');

function walk(dir, exts, out = []) {
  if (!existsSync(dir)) return out;
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (['node_modules', '.next', 'dist', '.git'].includes(e.name)) continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, exts, out);
    else if (exts.some(x => e.name.endsWith(x)) && statSync(p).size < 4_000_000) out.push(p);
  }
  return out;
}
const rel = f => f.slice(REPO.length + 1).replace(/\\/g, '/');

const inv = { measured_at: (await sql(`select (now() at time zone 'utc')::text t`))[0].t };

// ------------------------------------------------------------------------- cron jobs
inv.cron = await sql(`
  select j.jobid, j.jobname, j.schedule, j.active, left(j.command, 600) as command,
         coalesce(r.runs, 0) as runs, r.last_start::text as last_start, r.last_status
  from cron.job j
  left join lateral (
    select count(*) runs, max(start_time) last_start,
           (array_agg(status order by start_time desc))[1] last_status
    from cron.job_run_details d where d.jobid = j.jobid
  ) r on true
  order by j.jobname`);

// Source text of everything outside the database that could name a routine.  Read here
// because the routine inventory below needs it: a routine reached only through PostgREST
// (`.rpc('fn_x')` from an edge function or the frontend) has a caller, and counting it as
// orphaned would have invented 400-odd findings that are not there.
const frontFilesEarly = walk(join(REPO, 'src'), ['.ts', '.tsx', '.js', '.jsx', '.mjs'])
  .map(f => ({ f: rel(f), t: readFileSync(f, 'utf8') }));
const edgeFilesEarly = walk(FN_DIR, ['.ts']).map(f => ({ f: rel(f), t: readFileSync(f, 'utf8') }));
const outsideSrc = [...frontFilesEarly, ...edgeFilesEarly].map(x => x.t).join('\n');

// ------------------------------------------------------------------- database routines
// prokind: f=function, p=procedure, a=aggregate, w=window.  provolatile: v=VOLATILE, which
// is the only class that may write, so it is the first cut at "mutates state".
inv.db_functions = await sql(`
  with fns as (
    select p.oid, p.proname, p.provolatile, p.prosecdef, l.lanname,
           pg_get_function_identity_arguments(p.oid) as args, coalesce(p.prosrc,'') as src
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_language l on l.oid = p.prolang
    where n.nspname = 'public' and p.prokind in ('f','p')
  ),
  trig as (select distinct p.proname from pg_trigger t join pg_proc p on p.oid = t.tgfoid where not t.tgisinternal),
  cronsrc as (select coalesce(string_agg(command, ' '), '') c from cron.job)
  select f.proname, f.args, f.prosecdef, f.lanname, f.provolatile,
         (f.proname in (select proname from trig)) as called_by_trigger,
         (position(f.proname in (select c from cronsrc)) > 0) as named_by_cron,
         (select count(*) from fns g where g.oid <> f.oid and position(f.proname in g.src) > 0) as named_by_other_functions,
         (f.src ~* '\\m(insert|update|delete|truncate|create|drop|alter)\\M') as writes_sql,
         (f.src ~* 'net\\.http_post|functions/v1/') as calls_edge
  from fns f order by f.proname`);

// The RPC/PostgREST caller, measured rather than assumed.  The forms this estate uses:
//   .rpc('fn_x'  |  /rest/v1/rpc/fn_x  |  'fn_x' as a bare quoted identifier in a helper
for (const f of inv.db_functions) {
  const s = f.proname.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const res = [
    new RegExp(`\\.rpc\\(\\s*['"\`]${s}['"\`]`),
    new RegExp(`rpc/${s}(?![\\w])`),
    new RegExp(`['"\`]${s}['"\`]`),
  ];
  f.named_by_edge_or_frontend = res.some(r => r.test(outsideSrc));
}

inv.db_triggers = await sql(`
  select c.relname as table_name, t.tgname, p.proname as function_name, t.tgenabled,
         (t.tgtype & 2) > 0 as is_before, (t.tgtype & 4) > 0 as on_insert,
         (t.tgtype & 8) > 0 as on_delete, (t.tgtype & 16) > 0 as on_update
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  join pg_proc p on p.oid = t.tgfoid
  where n.nspname = 'public' and not t.tgisinternal
  order by c.relname, t.tgname`);

inv.state_tables = await sql(`
  select c.relname as table_name, coalesce(s.n_live_tup, 0) as approx_rows,
         string_agg(a.attname, ',' order by a.attnum) filter (
           where a.attname in ('status','state','stage','phase','workflow_id','workflow_key',
                               'step','step_no','queue','processed_at','completed_at','delivered_at')
         ) as state_columns
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
  left join pg_stat_user_tables s on s.relid = c.oid
  where n.nspname = 'public' and c.relkind = 'r'
  group by c.relname, s.n_live_tup
  having string_agg(a.attname, ',') filter (
    where a.attname in ('status','state','stage','phase','workflow_id','workflow_key',
                        'step','step_no','queue','processed_at','completed_at','delivered_at')
  ) is not null
  order by c.relname`);

inv.runtime_workflows = await sql(`
  select w.workflow_key, w.name, w.trigger_event, w.active,
         (select count(*) from public.workflow_step s where s.workflow_key = w.workflow_key) as steps,
         (select count(*) from public.workflow_run r where r.workflow_key = w.workflow_key) as runs,
         (select max(created_at)::text from public.workflow_run r where r.workflow_key = w.workflow_key) as last_run
  from public.workflow w order by w.workflow_key`);

inv.event_subscriptions = await sql(`select * from public.event_subscription order by 1`);
inv.executors = await sql(`select action_class, kind, target, active, advisory_safe, risk_tier,
                                  reversible, idempotency_strategy, timeout_seconds, max_attempts,
                                  notifies_human, unattended_ok, department, owner_os
                           from public.org_action_executor order by action_class`);

// --------------------------------------------------------------------- edge functions
const slugs = readdirSync(FN_DIR, { withFileTypes: true })
  .filter(d => d.isDirectory() && !d.name.startsWith('_')).map(d => d.name).sort();

const frontFiles = frontFilesEarly;
const edgeFiles = edgeFilesEarly;
const dbSrc = inv.db_functions.length
  ? await sql(`select proname, coalesce(prosrc,'') src from pg_proc p
               join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and prosrc is not null`)
  : [];

// The four invocation forms this estate actually uses.  A bare substring match is not
// evidence: slugs appear in prose, in comments and inside unrelated identifiers.
const forms = slug => {
  const s = slug.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return [
    new RegExp(`functions/v1/${s}(?![\\w-])`),
    new RegExp(`\\.invoke\\(\\s*['"\`]${s}['"\`]`),
    new RegExp(`callEdge\\(\\s*['"\`]${s}['"\`]`),
    new RegExp(`['"\`]${s}['"\`]\\s*,\\s*\\{`),
  ];
};
// An external entry surface: something outside the estate can reach it without a caller
// in repo/db/cron.  verify_jwt=false plus a webhook/public/oauth shape.
const cfgPath = join(REPO, 'supabase', 'config.toml');
const cfg = existsSync(cfgPath) ? readFileSync(cfgPath, 'utf8') : '';
const noJwt = new Set([...cfg.matchAll(/\[functions\.([a-z0-9_]+)\][^[]*?verify_jwt\s*=\s*false/gi)].map(m => m[1]));

inv.edge = [];
for (const slug of slugs) {
  const res = forms(slug);
  const hit = txt => res.some(r => r.test(txt));
  const own = `supabase/functions/${slug}/`;
  const src = edgeFiles.filter(x => x.f.startsWith(own)).map(x => x.t).join('\n');
  const frontend = frontFiles.filter(x => hit(x.t)).map(x => x.f);
  const edge = edgeFiles.filter(x => !x.f.startsWith(own) && hit(x.t)).map(x => x.f);
  const db = dbSrc.filter(x => hit(x.src)).map(x => x.proname);
  const cron = inv.cron.filter(x => hit(x.command ?? '')).map(x => x.jobname);
  inv.edge.push({
    slug,
    bytes: src.length,
    frontend, edge, db, cron,
    callers: frontend.length + edge.length + db.length + cron.length,
    verify_jwt_false: noJwt.has(slug),
    // does it write?  a service-role client plus a write verb, or an RPC to a volatile routine
    mutates: /\.(insert|update|upsert|delete)\(|\.rpc\(/.test(src),
    external_surface: /webhook|stripe|twilio|oauth|callback|public|sitemap|robots|whatsapp|inbound/i.test(slug),
  });
}

// -------------------------------------------------------------------------- frontend
const pages = frontFiles.filter(x => /\/(page|route)\.tsx?$/.test(x.f));
inv.frontend = pages.map(x => ({
  path: x.f,
  route: x.f.replace(/^src\/app/, '').replace(/\/(page\.tsx|route\.ts|route\.tsx)$/, '') || '/',
  is_api: /^src\/app\/api\//.test(x.f),
  // a routed mutation: the page or handler reaches a side-effecting boundary
  mutates: /\.(insert|update|upsert|delete)\(|\.rpc\(|functions\/v1\//.test(x.t),
})).sort((a, b) => a.route.localeCompare(b.route));

const outDir = join(REPO, 'docs', 'phase-c');
mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, '_inventory.json'), JSON.stringify(inv, null, 1), 'utf8');
console.error(`wrote docs/phase-c/_inventory.json  (${inv.edge.length} edge, ${inv.cron.length} cron, `
  + `${inv.db_functions.length} routines, ${inv.db_triggers.length} triggers, ${inv.frontend.length} routes)`);
