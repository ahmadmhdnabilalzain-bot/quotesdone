// Weekly dependency advisories for the IT engineer (public.fn_it_dependency_ingest): `npm audit` for
// the Next.js app, and OSV for every npm: and jsr: import the edge functions pin. No code is changed;
// a finding goes to the seat that owns the importing function, a high/critical one to the CEO seat, and
// none reaches the founder (ruling 1254). Run by .github/workflows/it-weekly-readings.yml.
//
//   node scripts/it/report_dependency_audit.mjs
import { execSync } from 'node:child_process';
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { sql, lit, PROJECT_REF } from '../lib/db.mjs';

const advisories = [];

// 1. The app: npm audit exits non-zero when it finds something, so its output is read either way.
let audit;
try { audit = JSON.parse(execSync('npm audit --json --omit=dev', { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] })); }
catch (e) { audit = JSON.parse(e.stdout || '{}'); }
for (const [name, v] of Object.entries(audit.vulnerabilities ?? {})) {
  const via = (v.via ?? []).filter((x) => typeof x === 'object');
  advisories.push({ ecosystem: 'app', package: name, severity: v.severity,
    id: via[0]?.source ? String(via[0].source) : via[0]?.url ?? null, title: via[0]?.title ?? 'see npm audit', function: 'website' });
}

// 2. Edge functions: every pinned npm:/jsr: specifier in their source, asked of OSV by version.
const FN = 'supabase/functions';
const owners = Object.fromEntries((await sql('select function_slug, owner from public.function_owner')).map((r) => [r.function_slug, r.owner]));
// IT-C15: only what is DEPLOYED is triaged. A function in the repository that is not deployed cannot be exploited
// through us; it is counted, not audited. If the list cannot be read, every function is audited (never fewer).
const fnList = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/functions`,
  { headers: { Authorization: `Bearer ${process.env.SUPABASE_ACCESS_TOKEN ?? ''}` } }).then((r) => (r.ok ? r.json() : null)).catch(() => null);
const deployed = Array.isArray(fnList) ? new Set(fnList.map((f) => f.slug)) : null;
let notDeployed = 0;
const pins = new Map();
for (const dir of readdirSync(FN)) {
  const f = join(FN, dir, 'index.ts');
  if (!existsSync(f)) continue;
  if (deployed && !deployed.has(dir)) { notDeployed += 1; continue; }
  for (const m of readFileSync(f, 'utf8').matchAll(/['"](npm|jsr):(@?[\w./-]+?)@(\d[\w.+-]*)['"/]/g)) {
    const key = `${m[1]}:${m[2]}@${m[3]}`;
    if (!pins.has(key)) pins.set(key, { eco: m[1], name: m[2], version: m[3], fns: new Set() });
    pins.get(key).fns.add(dir);
  }
}
const queries = [...pins.values()].filter((p) => p.eco === 'npm').map((p) => ({ package: { name: p.name, ecosystem: 'npm' }, version: p.version }));
if (queries.length) {
  const r = await fetch('https://api.osv.dev/v1/querybatch', { method: 'POST', body: JSON.stringify({ queries }) });
  const j = await r.json();
  const npmPins = [...pins.values()].filter((p) => p.eco === 'npm');
  (j.results ?? []).forEach((res, i) => {
    for (const v of res.vulns ?? []) {
      const p = npmPins[i];
      const fn = [...p.fns][0];
      advisories.push({ ecosystem: 'edge', package: `${p.name}@${p.version}`, id: v.id, title: v.summary ?? v.id, deployed: true,
        cve: (v.aliases ?? []).find((a) => a.startsWith('CVE-')) ?? null,
        severity: String(v.database_specific?.severity ?? 'moderate').toLowerCase(), function: fn, owner_seat: owners[fn] ?? 'ceo' });
    }
  });
}
// EPSS (FIRST.org): the probability the CVE is exploited in the next 30 days. 0.1+ makes a moderate one a security finding.
const cves = [...new Set(advisories.map((a) => a.cve).filter(Boolean))];
if (cves.length) {
  const e = await fetch(`https://api.first.org/data/v1/epss?cve=${cves.join(',')}`).then((r) => (r.ok ? r.json() : null)).catch(() => null);
  const epss = Object.fromEntries((e?.data ?? []).map((x) => [x.cve, Number(x.epss)]));
  for (const a of advisories) if (a.cve && a.cve in epss) a.epss = epss[a.cve];
}

// jsr has no OSV feed; its pins are counted so "no advisory" is never read as "checked".
const jsrPins = [...pins.values()].filter((p) => p.eco === 'jsr').length;

const [r] = await sql(`select public.fn_it_dependency_ingest(${lit(JSON.stringify({ advisories, jsr_pins_unchecked: jsrPins, functions_not_deployed: notDeployed, deployed_list_read: !!deployed }))}::jsonb) r`);
console.log(`dependency audit: ${advisories.length} advisories (${pins.size - jsrPins} npm pins checked, ${jsrPins} jsr pins with no advisory feed) ->`, JSON.stringify(r.r));
