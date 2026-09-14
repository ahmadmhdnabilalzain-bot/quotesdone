// Weekly dependency advisories for the IT engineer (public.fn_it_dependency_ingest): `npm audit` for
// the Next.js app, and OSV for every npm: and jsr: import the edge functions pin. No code is changed;
// a finding goes to the seat that owns the importing function, and only high/critical reach the
// founder. Run by .github/workflows/it-dependency-audit.yml.
//
//   node scripts/it/report_dependency_audit.mjs
import { execSync } from 'node:child_process';
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { sql, lit } from '../lib/db.mjs';

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
const pins = new Map();
for (const dir of readdirSync(FN)) {
  const f = join(FN, dir, 'index.ts');
  if (!existsSync(f)) continue;
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
      advisories.push({ ecosystem: 'edge', package: `${p.name}@${p.version}`, id: v.id, title: v.summary ?? v.id,
        severity: String(v.database_specific?.severity ?? 'moderate').toLowerCase(), function: fn, owner_seat: owners[fn] ?? 'ceo' });
    }
  });
}
// jsr has no OSV feed; its pins are counted so "no advisory" is never read as "checked".
const jsrPins = [...pins.values()].filter((p) => p.eco === 'jsr').length;

const [r] = await sql(`select public.fn_it_dependency_ingest(${lit(JSON.stringify({ advisories, jsr_pins_unchecked: jsrPins }))}::jsonb) r`);
console.log(`dependency audit: ${advisories.length} advisories (${pins.size - jsrPins} npm pins checked, ${jsrPins} jsr pins with no advisory feed) ->`, JSON.stringify(r.r));
