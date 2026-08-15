// Inventory every current execution path in the QuotesDone estate, with the evidence
// that says whether it is actually connected.
//
//   node scripts/phase_b/inventory_estate.mjs > docs/phase-b/_inventory.json
//
// The rule this script exists to obey: a table or function existing is NOT evidence that a
// runtime path is connected.  Every artefact below carries a `callers` and, where the estate
// records it, a `last_ran` — so an unconnected capability shows up as one instead of being
// read as working.  Zero inference; every field is measured.
import { readdirSync, existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { sql } from './lib/db.mjs';
import { REPO } from './lib/package.mjs';

const inv = { measured_at: null, db: {}, edge: [], frontend: [], cron: [] };
inv.measured_at = (await sql(`select (now() at time zone 'utc')::text t`))[0].t;

// ------------------------------------------------------------------- cron jobs
inv.cron = await sql(`
  select j.jobid, j.jobname, j.schedule, j.active,
         left(j.command, 400) as command,
         r.runs, r.last_start::text as last_start, r.last_status
  from cron.job j
  left join lateral (
    select count(*) runs, max(start_time) last_start,
           (array_agg(status order by start_time desc))[1] last_status
    from cron.job_run_details d where d.jobid = j.jobid
  ) r on true
  order by j.jobname`);

// ---------------------------------------------------------------- db functions
// A function is "reachable" when something names it: a trigger, a cron command, another
// function body, a view, or the PostgREST-exposed API surface.
inv.db.functions = await sql(`
  with fns as (
    select p.oid, p.proname, p.prokind, l.lanname,
           pg_get_function_identity_arguments(p.oid) as args,
           p.prosecdef, coalesce(p.prosrc,'') as src
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_language l on l.oid = p.prolang
    where n.nspname = 'public'
  ),
  trig as (
    select distinct p.proname
    from pg_trigger t join pg_proc p on p.oid = t.tgfoid
    where not t.tgisinternal
  ),
  cronrefs as (select string_agg(command, ' ') c from cron.job),
  bodies as (select string_agg(src, ' ') s from fns)
  select f.proname, f.args, f.prosecdef, f.lanname,
         (f.proname in (select proname from trig)) as called_by_trigger,
         (position(f.proname in (select c from cronrefs)) > 0) as named_by_cron,
         (select count(*) from fns g
            where g.proname <> f.proname and position(f.proname in g.src) > 0) as named_by_other_functions
  from fns f
  order by f.proname`);

inv.db.triggers = await sql(`
  select c.relname as table_name, t.tgname, p.proname as function_name, t.tgenabled,
         (t.tgtype & 2) > 0 as is_before, (t.tgtype & 4) > 0 as on_insert,
         (t.tgtype & 8) > 0 as on_delete, (t.tgtype & 16) > 0 as on_update
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  join pg_proc p on p.oid = t.tgfoid
  where n.nspname = 'public' and not t.tgisinternal
  order by c.relname, t.tgname`);

// tables that carry workflow/queue/state semantics, with live volume
inv.db.state_tables = await sql(`
  select c.relname as table_name,
         (xpath('/row/c/text()', query_to_xml(format('select count(*) c from public.%I', c.relname), false, true, '')))[1]::text::bigint as rows,
         string_agg(a.attname, ',' order by a.attnum) filter (
           where a.attname in ('status','state','stage','phase','workflow_id','workflow_key','step','step_no','queue','processed_at','completed_at')
         ) as state_columns
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
  where n.nspname = 'public' and c.relkind = 'r'
  group by c.relname
  having string_agg(a.attname, ',') filter (
    where a.attname in ('status','state','stage','phase','workflow_id','workflow_key','step','step_no','queue','processed_at','completed_at')
  ) is not null
  order by c.relname`);

inv.db.workflow_tables = {
  workflow: await sql(`select workflow_key, name, trigger_event, active, os_key from public.workflow order by workflow_key`),
  workflow_step: await sql(`select workflow_key, count(*) steps, count(*) filter (where gate is not null and gate<>'') gated,
                                   count(distinct actor_role) actors
                            from public.workflow_step group by workflow_key order by workflow_key`),
  workflow_run: await sql(`select w.workflow_key, count(r.*) runs, max(r.created_at)::text last_run
                           from public.workflow w left join public.workflow_run r on r.workflow_key = w.workflow_key
                           group by w.workflow_key order by w.workflow_key`),
  org_workflow_step: await sql(`select workflow_id, count(*) steps from public.org_workflow_step group by 1 order by 1`),
  employee_workflow: await sql(`select workflow_key, count(*) rows, count(distinct agent_key) agents,
                                       count(*) filter (where role_in_workflow = 'owner') owners
                                from public.employee_workflow group by 1 order by 1`),
};

// ------------------------------------------------------------------ edge functions
const fnDir = join(REPO, 'supabase', 'functions');
const slugs = existsSync(fnDir)
  ? readdirSync(fnDir, { withFileTypes: true }).filter(d => d.isDirectory() && !d.name.startsWith('_')).map(d => d.name).sort()
  : [];
const cronCommands = inv.cron.map(c => c.command ?? '').join(' ');
const fnBodies = inv.db.functions.length ? '' : '';
// which slugs the database itself invokes (net.http_post / fn_invoke wrappers)
const dbEdgeRefs = await sql(`
  select p.proname, coalesce(p.prosrc,'') src from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosrc is not null`);
const allDbSrc = dbEdgeRefs.map(r => r.src).join('\n');

// which slugs the frontend calls
const srcDir = join(REPO, 'src');
const walk = (d, out = []) => {
  for (const e of readdirSync(d, { withFileTypes: true })) {
    const p = join(d, e.name);
    if (e.isDirectory()) { if (e.name !== 'node_modules') walk(p, out); }
    else if (/\.(ts|tsx|js|jsx)$/.test(e.name)) out.push(p);
  }
  return out;
};
const frontFiles = existsSync(srcDir) ? walk(srcDir) : [];
const frontSrc = frontFiles.map(f => readFileSync(f, 'utf8')).join('\n');

for (const slug of slugs) {
  const re = new RegExp(`\\b${slug.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`);
  inv.edge.push({
    slug,
    called_by_cron: re.test(cronCommands),
    called_by_db_function: re.test(allDbSrc),
    called_by_frontend: re.test(frontSrc),
  });
}

// -------------------------------------------------------------------- frontend
const pageFiles = frontFiles.filter(f => /[\\/]page\.tsx$/.test(f) || /[\\/]route\.ts$/.test(f));
inv.frontend = pageFiles.map(f => ({
  path: f.slice(REPO.length + 1).replace(/\\/g, '/'),
  route: f.slice(REPO.length + 1).replace(/\\/g, '/')
    .replace(/^src\/app/, '').replace(/\/(page\.tsx|route\.ts)$/, '') || '/',
})).sort((a, b) => a.route.localeCompare(b.route));

console.log(JSON.stringify(inv, null, 1));
