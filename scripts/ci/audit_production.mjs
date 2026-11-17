#!/usr/bin/env node
// NO HIGH OR CRITICAL ADVISORY IN A PRODUCTION DEPENDENCY, EXCEPT ONE THAT HAS NO FIX YET, NAMED, AND FOR A WHILE ONLY
// (17 Nov 2026, it_engineer). The local gate's `audit` step ran `npm audit --omit=dev --audit-level=high`. On 17 Nov
// GHSA-fc5q-39xc-vjpf (picomatch ReDoS) covered every published picomatch (<=4.0.7), so every gate failed with no
// upgrade possible. This runs the same audit and lets through only an advisory listed in scripts/ci/audit_exceptions.json,
// and only while (a) the entry has not expired and (b) no patched version exists. Anything else HIGH or CRITICAL fails.
// Prevented by: scripts/ci/audit_production.test.mjs
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const HIGH = new Set(['high', 'critical']);

/** The verdict for one audit report: the findings that fail the gate (empty = pass). Pure, for the test. */
export function auditFindings(report, exceptions, today, newestOf) {
  const out = [];
  const byKey = new Map(exceptions.map((e) => [`${e.advisory}|${e.package}`, e]));
  const used = new Set();
  for (const [name, v] of Object.entries(report.vulnerabilities ?? {})) {
    for (const via of v.via ?? []) {
      if (typeof via !== 'object' || !HIGH.has(String(via.severity))) continue;   // a string `via` is a dependent, reported under its own name
      const id = String(via.url ?? '').split('/').pop();
      const ex = byKey.get(`${id}|${name}`);
      if (!ex) { out.push(`${name}: ${id} (${via.severity}) ${via.title ?? ''}`.trim()); continue; }
      // the exception covers the named route only: every install of the package must sit under one of `via`
      const nodes = (v.nodes ?? []).map(String);
      const offRoute = nodes.filter((n) => !(ex.via ?? []).some((p) => n.includes(`node_modules/${p}/`)));
      if (!nodes.length || offRoute.length) { out.push(`${name}: ${id} (${via.severity}) reached outside the excused route ${JSON.stringify(ex.via ?? [])}: ${offRoute.join(', ') || 'no install path reported'}`); continue; }
      used.add(`${id}|${name}`);
      if (String(ex.expires) < today) out.push(`${name}: ${id} - the exception expired on ${ex.expires}; upgrade or decide again`);
      const newest = newestOf(name);
      if (newest && !coversNewest(String(via.range ?? ''), newest)) out.push(`${name}: ${id} - ${newest} is outside the affected range ${via.range}: a fix exists, upgrade and delete the exception`);
    }
  }
  for (const e of exceptions) if (!used.has(`${e.advisory}|${e.package}`)) out.push(`${e.package}: ${e.advisory} is no longer reported - delete its exception`);
  return out;
}

/** True when an advisory range of the forms "<=X", "<X", "*" or "A - B" covers version v. Unknown forms count as covering. */
export function coversNewest(range, v) {
  const cmp = (a, b) => { const x = a.split('.').map(Number), y = b.split('.').map(Number); for (let i = 0; i < 3; i++) { if ((x[i] ?? 0) !== (y[i] ?? 0)) return (x[i] ?? 0) - (y[i] ?? 0); } return 0; };
  const r = range.trim();
  if (!r || r === '*') return true;
  let m;
  if ((m = r.match(/^<=\s*([\d.]+)$/))) return cmp(v, m[1]) <= 0;
  if ((m = r.match(/^<\s*([\d.]+)$/))) return cmp(v, m[1]) < 0;
  if ((m = r.match(/^([\d.]+)\s*-\s*([\d.]+)$/))) return cmp(v, m[1]) >= 0 && cmp(v, m[2]) <= 0;
  return true;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const run = (args) => { try { return execFileSync('npm', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }); } catch (e) { return e.stdout ?? ''; } };
  let report;
  try { report = JSON.parse(run(['audit', '--omit=dev', '--json'])); } catch { report = null; }
  // fail closed: no report (registry or network failure) is never a pass
  if (!report || report.error || !report.metadata) { console.error('npm audit produced no report: ' + JSON.stringify(report?.error ?? {}).slice(0, 300)); process.exit(1); }
  const { exceptions } = JSON.parse(readFileSync(new URL('./audit_exceptions.json', import.meta.url), 'utf8'));
  const newestOf = (pkg) => { const t = run(['view', pkg, 'version']).trim(); return /^\d+\.\d+\.\d+$/.test(t) ? t : null; };
  const findings = auditFindings(report, exceptions, new Date().toISOString().slice(0, 10), newestOf);
  if (findings.length) { console.error(findings.join('\n')); process.exit(1); }
  console.log(`no HIGH or CRITICAL advisory in a production dependency (${exceptions.length} named exception(s) with no fix yet: ${exceptions.map((e) => `${e.advisory} until ${e.expires}`).join(', ')})`);
}
