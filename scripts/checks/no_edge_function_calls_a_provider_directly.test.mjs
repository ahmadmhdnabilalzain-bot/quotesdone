// EVERY PAID-INFERENCE CALL GOES THROUGH THE GATEWAY, OR THIS TEST NAMES THE ONE THAT DOES NOT.
//
//   node --test scripts/checks/no_edge_function_calls_a_provider_directly.test.mjs
//
// PD-PROV-004 sat as a PERMANENT_EXEMPTION with the reason "the subject is outside the database:
// it is a CI repository scan over supabase/functions". That is true of the SUBJECT and it was never
// a reason not to test -- it is a description of the test that had not been written. The nearest
// existing check, scripts/checks/llm_gateway_credential.test.mjs, asserts about
// supabase/functions/_shared/llm.ts and its importers, which is the GATEWAY MODULE. Nothing
// anywhere refused a function that skipped it.
//
// WHAT THE SCAN FOUND WHEN IT WAS FIRST RUN, 24 Aug 2026 -- and this is a real finding, not a
// clean sheet:
//
//   ai_gateway      INFERENCE   the gateway itself; this is the door
//   resend_inbound  INFERENCE   POSTs openrouter.ai/api/v1/chat/completions directly, with the
//                               reason in its own comment: "NOT migrated to ai_gateway: this call
//                               attaches image content ... and the gateway does not proxy image
//                               payloads yet"
//   designer        INFERENCE   POSTs api.openai.com/v1/images/generations directly. K12 gated it
//                               after the 16 Aug audit found it ungated, because a search for
//                               "openrouter" never reached a different host -- but gated is not
//                               the same as routed through the gateway
//   ai_health       METADATA    GETs /api/v1/key -- a liveness probe, not inference, and it already
//                               consults the hold before calling
//   cost_snapshot   METADATA    GETs /api/v1/credits -- the billing balance, not inference, gated
//                               on paidOk
//
// So TWO functions perform paid inference through a direct provider client. Both are gated, so
// under the founder's hold neither spends; the architectural control -- all inference through one
// door -- is nonetheless not enforced by anything. That is the finding, and it is recorded rather
// than smoothed over.
//
// THE REGISTER IS A RATCHET, NOT AN AMNESTY. Each of the five is named below with its kind and the
// reason it is there. A SIXTH file, or a change of kind on an existing one -- METADATA becoming
// INFERENCE -- turns this red. That is the shape this estate uses for a known, owned, disclosed
// exception (scripts/checks/kernel-boards.json), and it is the only shape that lets a real finding
// be carried without it silently becoming the new normal.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = 'supabase/functions';

// Hosts that serve PAID INFERENCE. A host that only serves metadata still counts as a direct
// provider client -- it is classified, not excused.
const HOSTS = [
  'openrouter.ai', 'api.openai.com', 'api.anthropic.com',
  'generativelanguage.googleapis.com', 'api.mistral.ai', 'api.cohere.ai',
  'api.groq.com', 'api.deepseek.com', 'api.together.xyz', 'api.x.ai',
];

// Paths that mean INFERENCE rather than metadata. Anything not on this list that still reaches a
// provider host in a fetch() is classified INFERENCE too -- unknown is treated as the dangerous
// case, never as the safe one.
const METADATA_PATHS = ['/api/v1/key', '/api/v1/credits', '/api/v1/models'];

// The register: file -> { kind, why }. Nothing else may reach a provider host.
const REGISTER = {
  'ai_gateway': { kind: 'INFERENCE', why: 'the gateway itself — this is the single door every other function is supposed to use' },
  'resend_inbound': { kind: 'INFERENCE', why: 'DISCLOSED BYPASS: posts chat/completions directly because the gateway does not proxy image payloads yet (its own comment says so). Gated by the zero-cost check; still not routed through _shared/llm.ts' },
  'designer': { kind: 'INFERENCE', why: 'DISCLOSED BYPASS: posts api.openai.com image generations directly. K12 gated it on 16 Aug after it was found calling a paid provider with no gate at all, because a grep for "openrouter" could not see a different host. Gated is not routed' },
  'ai_health': { kind: 'METADATA', why: 'GETs /api/v1/key as a liveness probe — metadata, not inference — and consults the provider hold before calling' },
  'cost_snapshot': { kind: 'METADATA', why: 'GETs /api/v1/credits for the billing balance — metadata, not inference — gated on paidOk' },
};

function walk(dir) {
  const out = [];
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    if (statSync(p).isDirectory()) out.push(...walk(p));
    else if (/\.(ts|js|tsx|mjs)$/.test(e)) out.push(p);
  }
  return out;
}

// A HOST NAMED IN A COMMENT OR A MESSAGE BODY IS NOT A CALL. cost_snapshot puts
// "Top up at https://openrouter.ai/credits" into an alert a human reads; designer's comment
// explains why a grep for "openrouter" missed it. Counting those as bypasses would make the check
// cry wolf, and a check nobody believes is worse than no check. Only a host inside a fetch() call
// counts.
function callsIn(src) {
  const hits = [];
  const re = /fetch\s*\(\s*[`'"]([^`'"]+)[`'"]/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    const url = m[1];
    const host = HOSTS.find(h => url.includes(h));
    if (!host) continue;
    const metadata = METADATA_PATHS.some(p => url.includes(p));
    hits.push({ url, host, kind: metadata ? 'METADATA' : 'INFERENCE' });
  }
  return hits;
}

test('no edge function reaches a paid provider except the gateway and the disclosed bypasses', () => {
  const found = new Map();   // function name -> Set of kinds
  for (const file of walk(ROOT)) {
    const fn = file.split(/[\\/]/)[2];      // supabase/functions/<name>/...
    const hits = callsIn(readFileSync(file, 'utf8'));
    if (!hits.length) continue;
    if (!found.has(fn)) found.set(fn, new Set());
    for (const h of hits) found.get(fn).add(h.kind);
  }

  const problems = [];
  for (const [fn, kinds] of found) {
    const reg = REGISTER[fn];
    if (!reg) {
      problems.push(`${fn} reaches a paid provider host directly and is NOT in the register. `
        + `Route it through supabase/functions/_shared/llm.ts, or add it here with the reason it `
        + `cannot be — a bypass nobody wrote down is the one that spends money quietly.`);
      continue;
    }
    // A METADATA entry that starts doing inference is a change of kind and must be re-decided.
    if (kinds.has('INFERENCE') && reg.kind !== 'INFERENCE') {
      problems.push(`${fn} is registered ${reg.kind} but now makes an INFERENCE call. `
        + `That is a different fact from the one that was approved.`);
    }
  }
  for (const fn of Object.keys(REGISTER)) {
    if (!found.has(fn)) {
      problems.push(`${fn} is in the register but no longer reaches a provider host. `
        + `Remove it — a register entry for a bypass that no longer exists is a reason nobody re-read.`);
    }
  }

  assert.deepEqual(problems, [], '\n  ' + problems.join('\n  ') + '\n');
});

test('the two disclosed inference bypasses are still exactly two, and still disclosed', () => {
  const inference = Object.entries(REGISTER)
    .filter(([fn, r]) => r.kind === 'INFERENCE' && fn !== 'ai_gateway')
    .map(([fn]) => fn).sort();
  // THE RATCHET. This is the number the founder is owed: how many paid-inference calls do not go
  // through the one door. It is 2, both disclosed, both gated. A third is a regression even if it
  // is added to the register above.
  assert.deepEqual(inference, ['designer', 'resend_inbound'],
    'the set of edge functions doing paid inference outside the gateway changed. That is an '
    + 'architectural change, not a refactor: say so out loud and record why.');
});
