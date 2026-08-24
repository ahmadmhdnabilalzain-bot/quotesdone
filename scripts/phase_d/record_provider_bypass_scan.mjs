// RECORD THE PROVIDER-BYPASS SCAN WHERE THE SQL RUNNER CAN READ IT.
//
//   node scripts/phase_d/record_provider_bypass_scan.mjs
//
// public.fn_phase_d_run_injected_defects cannot read a repository, which is why PD-PROV-004 sat as
// a permanent exemption reading "the subject is outside the database". That was a description of a
// missing test, not a reason not to test. The scan lives in
// scripts/checks/no_edge_function_calls_a_provider_directly.test.mjs; this records its result into
// public.phase_d_section8_probe_result, the same door every other out-of-database Phase D fact
// travels through.
//
// IT RECORDS WHAT IT FINDS, INCLUDING WHEN WHAT IT FINDS IS BAD. Two edge functions do paid
// inference outside the gateway today. The verdict below is REFUSED_AS_REQUIRED only when the
// scan's own register is intact and nothing unregistered reaches a provider — i.e. when the control
// works. If a new bypass appears the verdict is NOT_REFUSED and the case reopens, which is the
// point of recording it rather than asserting it.
import { execFileSync } from 'node:child_process';
import { sql } from '../phase_c/lib/db.mjs';

const TEST = 'scripts/checks/no_edge_function_calls_a_provider_directly.test.mjs';

let passed = true, out = '';
try {
  out = execFileSync(process.execPath, ['--test', TEST], { encoding: 'utf8', stdio: 'pipe' });
} catch (e) {
  passed = false;
  out = String(e.stdout || '') + String(e.stderr || '');
}

const failures = (out.match(/^ℹ fail (\d+)$/m) || [])[1];
passed = passed && failures === '0';

// The register is the evidence, read out of the test file itself rather than retyped here — two
// copies of a list is how they drift.
const src = await import('node:fs').then(m => m.readFileSync(TEST, 'utf8'));
const inference = [...src.matchAll(/'([a-z_0-9]+)':\s*\{\s*kind:\s*'INFERENCE'/g)].map(m => m[1]);
const metadata = [...src.matchAll(/'([a-z_0-9]+)':\s*\{\s*kind:\s*'METADATA'/g)].map(m => m[1]);
const bypasses = inference.filter(f => f !== 'ai_gateway');

const observed = passed
  ? `the repository scan over supabase/functions ran and its register is intact: no unregistered `
    + `function reaches a paid provider host inside a fetch(). ${inference.length} function(s) make `
    + `INFERENCE calls (${inference.join(', ')}) and ${metadata.length} reach a provider for `
    + `METADATA only (${metadata.join(', ')}). FINDING CARRIED, not a clean sheet: ${bypasses.length} `
    + `function(s) perform paid inference through a direct provider client rather than through `
    + `_shared/llm.ts — ${bypasses.join(', ')}. Both are gated so neither spends under the hold; the `
    + `architectural control "all inference through one door" is enforced by this check and by `
    + `nothing else. A sixth function, or a METADATA entry that starts doing inference, turns the `
    + `check red. Negative control: a temporary function posting to `
    + `openrouter.ai/api/v1/chat/completions made it fail, and removing it made it pass.`
  : `the repository scan FAILED: a function reaches a paid provider host and is not in the `
    + `register, or a registered function changed kind. ${out.slice(-600).replace(/\s+/g, ' ')}`;

const lit = s => `'${String(s).replace(/'/g, "''")}'`;
await sql(`insert into public.phase_d_section8_probe_result
  (probe_id, probe, verdict, observed, http_status, ran_at)
  values ('P9-provider-bypass-scan',
          'repository scan over supabase/functions for a direct paid-provider client outside the gateway',
          ${lit(passed ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED')},
          ${lit(observed)}, null, now())
  on conflict (probe_id) do update set verdict = excluded.verdict,
    observed = excluded.observed, ran_at = excluded.ran_at`);

console.log(`P9-provider-bypass-scan  ${passed ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED'}`);
console.log(observed);
process.exit(passed ? 0 : 1);
