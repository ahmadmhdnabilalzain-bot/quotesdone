// A PARTNER SERVICE IS MATCHED KNOWINGLY (12 Nov 2026, sales_engineer; founder ruling 1647; analysis services/REPORT.md
// 3.7, slice 5). scripts/sql/a_partner_service_is_matched_knowingly.sql gives fn_match_capability a partner_hits column,
// orders a supplier whose every named-service hit is through a partner after the own-team ones, and names it in `why`.
// What fails if that breaks:
//   * the SQL: the shared column stops being idempotent with the slice 4 file; the changed result type is created
//     without its revoke (CREATE grants EXECUTE to PUBLIC); the own-team-first order or the why segment goes      -> static
//   * the customer is told: a customer-facing surface prints partner_hits, or a reason with the partner segment reaches
//     inquiry_matches.match_reason (read by the customer after reveal) or discovery's answer                       -> static
//   * on production, rolled back, demo suppliers only: own team first even when outscored, the limit drops the partner
//     supplier first, an unconfirmed partner key matches nothing, a request naming no service is untouched          -> probe
//
//   node --test scripts/checks/a_partner_service_is_matched_knowingly.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname, relative } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const sqlCode = (s) => s.replace(/--.*$/gm, '');
const tsCode = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:'"`])\/\/.*$/gm, '$1');
const NAME = 'a_partner_service_is_matched_knowingly';
const FILE = `scripts/sql/${NAME}.sql`;
const PROBE = `scripts/sql/${NAME}_probe.sql`;
const SIG = 'public.fn_match_capability(text[], text, text[], text[], text, numeric, text, integer, text[])';

test('the SQL: an idempotent shared column, a changed result type closed again, own team first, the partner named', () => {
  const s = sqlCode(R(FILE));
  assert.match(s, /alter table public\.supplier_capabilities add column if not exists services_partner text\[\] not null default '\{\}';/);
  assert.ok(s.indexOf(`drop function if exists ${SIG};`) >= 0, 'the old result type is not dropped');
  assert.ok(s.indexOf(`revoke execute on function ${SIG} from public, anon, authenticated;`) > s.indexOf('create function public.fn_match_capability('),
    'CREATE grants EXECUTE to PUBLIC and no revoke follows it');
  assert.match(s, new RegExp(`grant execute on function ${SIG.replace(/[()[\]]/g, '\\$&')} to service_role;`));
  assert.match(s, /via_implication text\[\], partner_hits text\[\]\)/, 'partner_hits is not the last output column');
  assert.match(s, /order by \(cardinality\(r\.service_hits\) > 0 and cardinality\(r\.partner_hits\) = cardinality\(r\.service_hits\)\), r\.score_v desc/,
    'own team is no longer ordered first');
  assert.match(s, /'through a partner: ' \|\| array_to_string\(r\.partner_hits, ', '\)/);
  // the gate is the earlier one: the partner services are not subtracted from what admits him
  assert.match(s, /public\.fn_services_effective\(c\.services, c\.trades, c\.services_removed\) end as eff_services/);
  assert.match(s, /or cardinality\(c\.service_hits\) > 0\s+or \(c\.never_asked and c\.direct\)/, 'the service gate changed');
});

// Every edge function that calls the matcher, and what it does with its rows.
const callers = () => {
  const out = [];
  const walk = (d) => { for (const n of readdirSync(d)) { const p = join(d, n); if (statSync(p).isDirectory()) walk(p);
    else if (/\.ts$/.test(n) && !/\.test\.ts$/.test(n) && /rpc\('fn_match_capability'/.test(readFileSync(p, 'utf8'))) out.push(relative(ROOT, p)); } };
  walk(join(ROOT, 'supabase/functions'));
  return out.sort();
};

test('no customer-facing surface prints partner_hits or the partner segment of why', () => {
  const found = callers();
  assert.deepEqual(found, ['supabase/functions/customer_api/actions/discovery.ts', 'supabase/functions/inquiry_intake/supplier_count.ts',
    'supabase/functions/public_site/index.ts', 'supabase/functions/sales_engineer/actions/operator.ts'],
    'a caller of fn_match_capability was added or moved: decide here what it may print');
  for (const f of found) assert.doesNotMatch(tsCode(R(f)), /\.partner_hits\b/, `${f} reads partner_hits directly (only _shared/partner_match.ts may)`);
  // the two that read why: the sales engineer stores it as match_reason, discovery returns it to a customer
  assert.match(tsCode(R('supabase/functions/sales_engineer/actions/operator.ts')), /reason: withoutPartnerWhy\(r\.why\)\.slice\(0, 400\),/);
  assert.match(tsCode(R('supabase/functions/customer_api/actions/discovery.ts')), /why: scrubIdentity\(withoutPartnerWhy\(r\.why\) \|\| null,/);
  for (const f of ['supabase/functions/inquiry_intake/supplier_count.ts', 'supabase/functions/public_site/index.ts']) {
    assert.doesNotMatch(tsCode(R(f)), /\.why\b/, `${f} now prints the matcher's why`);
  }
  // customer_api invites from the sales engineer's answer: it stores the reason stripped again and never copies through_partner
  const m = tsCode(R('supabase/functions/customer_api/lib/matching.ts'));
  assert.match(m, /match_reason: withoutPartnerWhy\(f\.reason\)\.slice\(0, 400\)/);
  assert.doesNotMatch(m, /through_partner/);
  // the customer's request view reads match_reason, written only by the two writers above and by the widening sweep,
  // which names no service (8 arguments), so the matcher can report no partner hit to it
  assert.match(R('supabase/functions/customer_api/actions/inquiry_lifecycle.ts'), /match_reason: revealed \?/);
  assert.match(R('supabase/schema/full_schema/08_functions_fn_p_to_fn_r.sql'),
    /from public\.fn_match_capability\(v_codes, v_need, '\{\}'::text\[\], '\{\}'::text\[\], r\.scope_type, v_value, r\.emirate, 100000\) m/,
    'the widening sweep now names services: strip the partner segment from its match_reason');
});

test('the invitation rule is applied where the match is decided', () => {
  const s = tsCode(R('supabase/functions/sales_engineer/actions/operator.ts'));
  assert.match(s, /const picked = invitedUnderPartnerRule\(aboveFloor, serviceKeys\);/);
  assert.match(s, /partner_held_back: partnerHeldBack/);
});

test('the change is pending until the release applies it, and the probe is never applied', () => {
  const notes = pendingNotes();
  const inManifest = R('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim()).includes(FILE);
  assert.ok(inManifest || notes.has(FILE), 'the change is neither applied (MANIFEST) nor pending');
  assert.match(notes.get(PROBE) || '', /^A PROBE\b/, 'the probe must carry a probe note so it is never applied');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production, rolled back, demo suppliers only: own team first, the partner supplier last and named', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const pre = pendingNotes().has(FILE) ? R(FILE) + '\n' : '';
  let verdict = null;
  try { await replaySql(pre + R(PROBE), { label: PROBE }); } catch (e) {
    const m = String(e.body ?? e.message ?? e).match(/CHK<<([\s\S]*?)>>/);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.body ?? e.message ?? e).slice(0, 800));
    verdict = m[1].replace(/\\"/g, '"');
  }
  assert.ok(verdict, 'the probe committed instead of rolling back');
  assert.match(verdict, /"verdict": "PROBE OK"/, verdict);
});
