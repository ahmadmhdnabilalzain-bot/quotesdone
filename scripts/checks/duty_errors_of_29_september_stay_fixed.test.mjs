// THE DUTY ERRORS OF 29 SEPTEMBER STAY FIXED (it_engineer, 29 Sep 2026). Each test replays a measured cause.
//  1. kyc error budget: all 12 over-budget kyc runs in 30 days were accept_terms waiting 2.9-12 s on the signed-PDF
//     render (server errors 0). The answer must not wait on compliance_archive.
//  2. incident 508: resilience_ping's launch-path probe hit supplier_portal unauthenticated every hour and its 401
//     counted as a stranger's. The probe presents its credential; supplier_portal marks the refusal only on a
//     credential fn_internal_auth accepts, never on a bare header.
//  3. wa_templates_watch: "nothing queued" was the founder mail policy routing the notice, logged as an error on
//     every run (19 on 29 Sep), next to a call to a routine that does not exist.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');

test('kyc accept_terms answers before the certificate is rendered', () => {
  const s = read('supabase/functions/kyc/index.ts');
  const acc = s.slice(s.indexOf("if (action === 'accept_terms')"), s.indexOf("await logRun('error', { action }, 'unknown_action')"));
  const render = acc.indexOf('/compliance_archive');
  assert.ok(render > 0, 'accept_terms no longer issues the certificate at all');
  const certify = acc.indexOf('const certify = (async () => {');
  assert.ok(certify > 0 && certify < render, 'the compliance_archive render is not inside the background block');
  assert.match(acc, /rt\.waitUntil\(certify\)/, 'the render is awaited on the request path');
  assert.ok(!/await timedFetch\(`\$\{FN\}\/compliance_archive`/.test(acc.slice(0, certify)), 'a render is awaited before the answer');
});

test('supplier_portal marks the probe from a verified credential only', () => {
  const pc = read('supabase/functions/_shared/probe_caller.ts');
  assert.match(pc, /const auth = await requireInternal\(admin, secret, fnName\);\s*return auth\.ok \? \{ caller: 'fixture', fixture: 1/);
  const sp = read('supabase/functions/supplier_portal/index.ts');
  assert.match(sp, /if \(!who\.ok\) return annotate\(J\(refusalBody\(who\), who\.status\), await probeCaller\(admin, req, 'supplier_portal'\)\);/);
  const lp = read('supabase/functions/_shared/launch_path.ts');
  assert.match(lp, /id: 'api:supplier_portal', url: fnUrl\('supplier_portal'\), init: withProbe\(/);
  const rp = read('supabase/functions/resilience_ping/index.ts');
  assert.match(rp, /probeLaunchPath\([^\n]*sec\('cred_fn_resilience_ping'\)/, 'resilience_ping does not hand the probe its credential');
});

test('wa_templates_watch does not log a policy-routed founder notice as a failure', () => {
  const s = read('supabase/functions/wa_templates_watch/index.ts');
  assert.ok(!/rpc\('cron_unschedule/.test(s), 'calls a routine that does not exist');
  assert.match(s, /const notifErr = rawNotifErr && !\(notifData\?\.length && notifData\.every\(\(d\) => !d\.error\)\) \? rawNotifErr : null;/);
});
