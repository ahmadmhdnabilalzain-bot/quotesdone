// For every edge function slug, find what actually invokes it.
//
// A bare substring search is not evidence: "auth_api" appears in prose, in comments and in
// unrelated identifiers.  This looks for the four forms an invocation actually takes in this
// estate, so an unconnected function shows up as unconnected instead of being assumed live.
import { readdirSync, existsSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { sql } from './lib/db.mjs';
import { REPO } from './lib/package.mjs';

const FN_DIR = join(REPO, 'supabase', 'functions');
const slugs = readdirSync(FN_DIR, { withFileTypes: true })
  .filter(d => d.isDirectory() && !d.name.startsWith('_')).map(d => d.name).sort();

function walk(dir, exts, out = []) {
  if (!existsSync(dir)) return out;
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (e.name === 'node_modules' || e.name === '.next' || e.name === 'dist') continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, exts, out);
    else if (exts.some(x => e.name.endsWith(x)) && statSync(p).size < 4_000_000) out.push(p);
  }
  return out;
}

const front = walk(join(REPO, 'src'), ['.ts', '.tsx', '.js', '.jsx', '.mjs'])
  .map(f => ({ f: f.slice(REPO.length + 1).replace(/\\/g, '/'), t: readFileSync(f, 'utf8') }));
const edgeSrc = walk(FN_DIR, ['.ts'])
  .map(f => ({ f: f.slice(REPO.length + 1).replace(/\\/g, '/'), t: readFileSync(f, 'utf8') }));
const dbFns = await sql(`select proname, coalesce(prosrc,'') src from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and prosrc is not null`);
const cronJobs = await sql(`select jobname, active, command,
  (select count(*) from cron.job_run_details d where d.jobid=j.jobid) runs,
  (select max(start_time)::text from cron.job_run_details d where d.jobid=j.jobid) last_start
  from cron.job j order by jobname`);

// The invocation forms this estate actually uses.
const forms = slug => [
  new RegExp(`functions/v1/${slug}(?![\\w-])`),           // direct URL, frontend + net.http_post
  new RegExp(`\\.invoke\\(\\s*['"\`]${slug}['"\`]`),      // supabase-js client
  new RegExp(`callEdge\\(\\s*['"\`]${slug}['"\`]`),       // repo helper
  new RegExp(`['"\`]${slug}['"\`]\\s*,\\s*\\{`),          // helper(slug, {...})
];

const out = [];
for (const slug of slugs) {
  const res = forms(slug);
  const hit = txt => res.some(r => r.test(txt));
  const ownDir = `supabase/functions/${slug}/`;
  const frontendCallers = front.filter(x => hit(x.t)).map(x => x.f);
  const edgeCallers = edgeSrc.filter(x => !x.f.startsWith(ownDir) && hit(x.t)).map(x => x.f);
  const dbCallers = dbFns.filter(x => hit(x.src)).map(x => x.proname);
  const cronCallers = cronJobs.filter(x => hit(x.command ?? '')).map(x => x.jobname);
  out.push({
    slug,
    frontend: frontendCallers, edge: edgeCallers, db: dbCallers, cron: cronCallers,
    callers: frontendCallers.length + edgeCallers.length + dbCallers.length + cronCallers.length,
  });
}

const orphans = out.filter(o => o.callers === 0);
console.log(JSON.stringify({
  total: slugs.length,
  with_caller: out.length - orphans.length,
  without_caller: orphans.length,
  cron: { total: cronJobs.length, active: cronJobs.filter(c => c.active).length,
          never_ran: cronJobs.filter(c => Number(c.runs) === 0).map(c => c.jobname) },
  functions: out,
}, null, 1));
