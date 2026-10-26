// A database function that hard-codes the production project ref will call production from wherever
// it is installed.
//
// 3-4 Aug 2026. The staging branch `staging-launch-repair` (ref jmufplujtmnikxplrano) was built by
// replaying production's migrations. It inherited ELEVEN active cron jobs that reach production:
// five naming the production URL directly, and six more calling database functions that hard-code it
// (run_auto_deploy, run_site_autodeploy, qd_reveal_nudges, fn_ai_trainer, fn_run_vt,
// run_doc_reminders, run_licence_reminders, run_pending_digest).
//
// `wa_flush` hit production's send_whatsapp every two minutes for eighteen hours - 546 refusals - and
// `site_autodeploy` called production's deploy path EVERY MINUTE, while production's own copies of
// both were deliberately disabled by the Phase 0 hold. It failed only because staging's inbound_secret
// happens to differ from production's. That is a coincidence, not a control: staging was built from
// production's migration set, and had the secret matched it would have been sending real WhatsApp
// messages to real customers and deploying the real site.
//
// staging-rebuild-log.md (D6) spotted this for two TRIGGERS and rewrote their URLs. It did not spot
// the crons, and it recommended a lint rule that was never built. This is that rule.
//
// IT IS A RATCHET, NOT A BAN. The ref appears in 49 already-applied migrations, which are immutable,
// and in 7 edge functions that would each need a considered change. Freezing the debt where it stands
// is honest and enforceable; demanding a 32-file rewrite in one go would be neither, and a guard
// nobody can satisfy gets deleted.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, relative } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SUPA = join(root, 'supabase');
const REF = 'htdblwldjkcgjvmqkbeh';

// Counted 4 Aug 2026. These may go DOWN. They may not go up.
const CEILING = { migrations: 51, functions: 7 };

function count(dir) {
  let n = 0;
  const walk = (d) => {
    for (const e of readdirSync(d, { withFileTypes: true })) {
      const p = join(d, e.name);
      if (e.isDirectory()) { walk(p); continue; }
      if (!/\.(sql|ts)$/.test(e.name)) continue;
      if (statSync(p).size > 8 * 1024 * 1024) continue;
      n += (readFileSync(p, 'utf8').match(new RegExp(REF, 'g')) || []).length;
    }
  };
  walk(dir);
  return n;
}

test('no new migration hard-codes the production project ref', () => {
  const n = count(join(SUPA, 'migrations'));
  assert.ok(n <= CEILING.migrations,
    'migrations now contain ' + n + ' hard-coded production refs, up from the ' + CEILING.migrations + ' frozen on ' +
    '4 Aug 2026. A migration carrying the production URL calls production from whatever database it is replayed ' +
    'into - that is how a staging branch spent eighteen hours calling production\'s send_whatsapp and deploy path. ' +
    'Build the URL from a setting or an env var instead. If you have genuinely removed some, lower the ceiling.');
});

test('no new edge function hard-codes the production project ref', () => {
  const n = count(join(SUPA, 'functions'));
  assert.ok(n <= CEILING.functions,
    'supabase/functions now contain ' + n + ' hard-coded production refs, up from ' + CEILING.functions + '. Every ' +
    'other function derives its base URL from Deno.env.get("SUPABASE_URL"), which is correct in every environment; ' +
    'a literal ref is correct in exactly one and silently wrong in all the others.');
});

test('the ceiling is a debt marker, and the debt is named', () => {
  // A ratchet with no path out is just a ratchet. This keeps the remaining count visible so it can be
  // driven down deliberately rather than discovered again by an incident.
  const m = count(join(SUPA, 'migrations'));
  const f = count(join(SUPA, 'functions'));
  assert.ok(m + f > 0,
    'no hard-coded refs remain anywhere - delete this guard and the ceiling with it, the debt is paid.');
  assert.ok(CEILING.migrations >= m && CEILING.functions >= f,
    'the recorded ceiling (' + CEILING.migrations + '/' + CEILING.functions + ') is below the real count (' +
    m + '/' + f + '), so this guard is asserting something already false.');
});
