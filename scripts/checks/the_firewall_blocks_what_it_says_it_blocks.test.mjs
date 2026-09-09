// THE FIREWALL BLOCKS WHAT IT SAYS IT BLOCKS.
//
// The founder, 9 Sep 2026: "Firewall in logging mode. I don't know. I mean, how can this benefit me?
// What do you want me to do about it? Is there something fixable in that? And if it's fixable how
// and why it wasn't done, and is there any extra cost on that?"
//
// It was fixable, it cost nothing, and it is now done: the six unambiguous attack classes were
// switched from `log` to `deny` on 9 Sep 2026 (config waf_l2KzGOM8qEy5, version 13 -> 19).
//
// WHY THIS CHECK EXISTS RATHER THAN JUST THE CHANGE. The firewall lives in Vercel's dashboard and
// has NO representation in this repository. Nothing would notice if a ruleset were switched back to
// log, or turned off, by anyone with dashboard access. A security control that can be silently
// reverted is a control you cannot rely on, so the expected posture is asserted here.
//
// WHY SIX AND NOT ELEVEN. sqli, rce, lfi, rfi, php and java match specific, unambiguous attack
// shapes — a request that trips them is not a customer. The other five (xss, gen, ma, sd, sf) are
// broader heuristics that false-positive on ordinary rich text and search queries, and a firewall
// that blocks a real buyer is worse than one that watches. They stay on `log` DELIBERATELY, and
// this check asserts that too, so "we turned everything on" can never quietly become the story.
//
// A NOTE ON HOW THIS WAS NEARLY GOT WRONG. The first read of this config looked for a key called
// `managedRules` and found nothing, which would have been reported as "the firewall has no rules at
// all". The rulesets live under `crs`. That is the third instance in one day of reading a value
// without checking it was the value being asked for; the check below asserts the key exists rather
// than treating an empty result as an answer.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

const MUST_DENY = ['sqli', 'rce', 'lfi', 'rfi', 'php', 'java'];
const MUST_LOG  = ['xss', 'gen', 'ma', 'sd', 'sf'];

async function firewall() {
  const rows = await sql(`select key, value from public.app_secrets where key like 'vercel%'`);
  const s = Object.fromEntries(rows.map((r) => [r.key, r.value]));
  const qs = `?projectId=${s.vercel_project_id}` + (s.vercel_team_id ? `&teamId=${s.vercel_team_id}` : '');
  const r = await fetch('https://api.vercel.com/v1/security/firewall/config' + qs,
    { headers: { Authorization: 'Bearer ' + s.vercel_token } });
  assert.equal(r.status, 200, `the firewall config could not be read (HTTP ${r.status})`);
  return (await r.json()).active;
}

test('the firewall is switched on at all', { skip: SKIP }, async () => {
  const a = await firewall();
  assert.equal(a.firewallEnabled, true, 'the Vercel firewall is disabled');
});

test('the rulesets are where this check thinks they are', { skip: SKIP }, async () => {
  const a = await firewall();
  // POSITIVE CONTROL for the check itself. An empty `crs` would make every assertion below vacuous,
  // which is exactly how "no managed rules" was nearly reported as a finding.
  assert.ok(a.crs && typeof a.crs === 'object', 'the config has no `crs` key — the shape changed and this check is now blind');
  assert.ok(Object.keys(a.crs).length >= 11,
    `expected at least 11 rulesets, found ${Object.keys(a.crs).length} — a count this low means they were removed or moved`);
});

test('the six unambiguous attack classes are BLOCKED, not merely watched', { skip: SKIP }, async () => {
  const a = await firewall();
  const wrong = MUST_DENY.filter((k) => a.crs?.[k]?.action !== 'deny' || a.crs?.[k]?.active !== true);
  assert.deepEqual(wrong, [],
    `these should deny and do not: ${wrong.map((k) => `${k}=${a.crs?.[k]?.action ?? 'absent'}`).join(', ')}. `
    + 'Someone reverted the firewall, or a ruleset was turned off.');
});

test('the heuristic rulesets stay on log, so a real buyer is never blocked by a false positive', { skip: SKIP }, async () => {
  const a = await firewall();
  const wrong = MUST_LOG.filter((k) => a.crs?.[k]?.action !== 'log');
  assert.deepEqual(wrong, [],
    `these were meant to stay on log and are now ${wrong.map((k) => `${k}=${a.crs?.[k]?.action}`).join(', ')}. `
    + 'If that was deliberate, change MUST_LOG here and say why — do not leave the check disagreeing with production.');
});

test('the website still serves with blocking on', { skip: SKIP }, async () => {
  for (const path of ['/en', '/en/faq', '/en/portal']) {
    const r = await fetch('https://www.quotesdone.com' + path, { redirect: 'follow' });
    assert.equal(r.status, 200, `${path} returned ${r.status} with the firewall blocking`);
  }
});
