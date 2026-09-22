// META AND SOCIAL ARE HELD FOR THE MARKETING SEAT -- no other seat's code touches their credentials.
//
// Founder rule 641, 22 Sep 2026: Meta, ads and social are wired to no agent until the marketing seat
// exists. Recorded once in public.company_policy_decision 'meta_and_social_held_for_marketing'
// (scripts/sql/the_founder_hears_from_it_once_a_day.sql).
//
// MEASURED (22 Sep 2026, before this change): one live agent use of the Meta token -- the IT engineer's
// expiry duty (supabase/functions/_shared/it_duty_readings.ts) sent it to Meta's debug_token endpoint on
// every due run -- and the accountant's hourly duties ran fn_accountant_ad_spend_tick. Both are unwired in
// this change. Three live routines read only whether the token is SET: fn_ads_autospend_state is the
// ads autopilot's own (marketing), and the other two are PRESENCE_ONLY below.
//
// FAILS when any code outside the marketing seat names a held credential or Meta's Graph host:
//   * every non-test file under supabase/functions and src;
//   * every routine's canonical SQL body (the last file in scripts/sql/MANIFEST.txt that defines it);
//   * with a token, every routine live in production (catches a routine applied from outside the repo).
// The marketing seat's code, when it exists, lives in supabase/functions/marketing/ and in routines named
// fn_marketing_*, fn_ads_* or fn_ad_*; that is the only place a reference is allowed.
//
//   node --test scripts/checks/meta_and_social_are_held_for_the_marketing_seat.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
// The key names are assembled, not written whole, so this file does not match its own scan.
const HELD = new RegExp(['meta_' + 'access_token', 'meta_' + 'ad_account_id', 'postiz_' + 'api_key', 'postiz_' + 'publish_key',
  'postiz_' + 'integrations', 'graph\\.' + 'facebook\\.com'].join('|'));
const MARKETING_ROUTINE = /^fn_(marketing|ads?)_/;   // fn_ad_decision_*, fn_ad_spend_*: the ads autopilot
const MARKETING_DIR = ['supabase', 'functions', 'marketing'].join(sep);
const MARKETING_CODE = /^supabase\/functions\/(marketing[a-z_]*\/|_shared\/marketing[a-z_]*\.ts$)/;
// Frozen. Each reads only whether the key is set, to show "connected" / "awaiting token" on a report.
const PRESENCE_ONLY = new Set(['fn_company_snapshot', 'fn_ws_marketing']);

function* walk(dir) {
  if (!existsSync(dir)) return;
  for (const e of readdirSync(dir)) {
    if (e === 'node_modules' || e.startsWith('.')) continue;
    const p = join(dir, e);
    if (statSync(p).isDirectory()) yield* walk(p);
    else if (/\.(ts|tsx|js|mjs)$/.test(e) && !/\.test\.[a-z]+$/.test(e)) yield p;
  }
}

export function codeOffenders(repo = REPO) {
  const out = [];
  for (const root of [join(repo, 'supabase', 'functions'), join(repo, 'src')]) {
    for (const p of walk(root)) {
      const rel = relative(repo, p);
      if (rel.startsWith(MARKETING_DIR + sep)) continue;
      // The seat's code by NAME, like its routines (fn_marketing_*): an edge function or a shared module
      // whose own name starts with marketing (marketing_channels/, _shared/marketing_channels.ts). PR #834.
      if (MARKETING_CODE.test(rel.split(sep).join('/'))) continue;
      if (HELD.test(readFileSync(p, 'utf8'))) out.push(rel);
    }
  }
  return out;
}

export function routineOffenders(bodies) {
  return [...bodies].filter(([n, b]) => HELD.test(b) && !MARKETING_ROUTINE.test(n) && !PRESENCE_ONLY.has(n)).map(([n]) => n).sort();
}

function canonicalBodies() {
  const manifest = readFileSync(join(REPO, 'scripts', 'sql', 'MANIFEST.txt'), 'utf8')
    .split(/\r?\n/).map((l) => l.trim()).filter((l) => l.endsWith('.sql') && !l.startsWith('#'));
  const out = new Map();
  for (const f of manifest) {
    const p = join(REPO, f);
    if (!existsSync(p)) continue;
    const src = readFileSync(p, 'utf8');
    const heads = [...src.matchAll(/create\s+or\s+replace\s+function\s+public\.(\w+)\s*\(/gi)];
    heads.forEach((m, i) => {
      // The body only: from the head to the closing of its own dollar tag ($fn$, $$, ...), so a comment
      // or an insert further down the file is not read as part of the routine.
      const b = src.slice(m.index, heads[i + 1]?.index ?? src.length);
      const open = b.match(/\bas\s+(\$\w*\$)/i);
      const end = open ? b.indexOf(open[1], open.index + open[0].length) : -1;
      out.set(m[1].toLowerCase(), end < 0 ? b : b.slice(0, end));
    });
  }
  return out;
}

test('no edge function or app code outside the marketing seat names a held Meta or Postiz credential', () => {
  const bad = codeOffenders();
  assert.deepEqual(bad, [], `rule 641: these files reach a credential held for the marketing seat:\n${bad.join('\n')}`);
});

test('no routine outside the marketing seat names a held credential', () => {
  const bad = routineOffenders(canonicalBodies());
  assert.deepEqual(bad, [], `rule 641: these routines reach a credential held for the marketing seat: ${bad.join(', ')}`);
});

test('the gate fails a seat that reaches for the token, and lets the marketing seat and presence reads through', () => {
  const k = 'meta_' + 'access_token';
  const bad = routineOffenders(new Map([
    ['fn_it_zz_demo_reads_meta', `select value from app_secrets where key = '${k}'`],
    ['fn_ads_zz_demo', `select value from app_secrets where key = '${k}'`],
    ['fn_company_snapshot', `exists (select 1 from app_secrets where key = '${k}')`],
    ['fn_zz_demo_quiet', 'select 1'],
  ]));
  assert.deepEqual(bad, ['fn_it_zz_demo_reads_meta']);
});

test('the IT expiry duty no longer reads the Meta token', () => {
  const src = readFileSync(join(REPO, 'supabase', 'functions', '_shared', 'it_duty_readings.ts'), 'utf8');
  assert.doesNotMatch(src, HELD);
  assert.doesNotMatch(src, /debug_token\?/);
});

test("the accountant's hourly duties no longer run the ad-spend tick", () => {
  const b = canonicalBodies().get('fn_accountant_duties');
  assert.ok(b, 'fn_accountant_duties is defined by no file in MANIFEST.txt');
  assert.doesNotMatch(b, /fn_accountant_ad_spend_tick\s*\(/);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production: no live routine outside the marketing seat names a held credential', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`select p.proname, p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                           where n.nspname = 'public' and p.prosrc ~ '${HELD.source.replace(/'/g, "''")}'`);
  const bad = routineOffenders(new Map(rows.map((r) => [r.proname, r.prosrc])));
  assert.deepEqual(bad, [], `rule 641, production: ${bad.join(', ')}`);
  const held = await sql(`select 1 from public.company_policy_decision where decision_key = 'meta_and_social_held_for_marketing'`);
  if (!held.length) console.log('# company_policy_decision row not present yet: the_founder_hears_from_it_once_a_day.sql is not applied');
});
