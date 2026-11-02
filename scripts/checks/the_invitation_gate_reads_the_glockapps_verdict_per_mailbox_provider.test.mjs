// THE INVITATION GATE READS THE GLOCKAPPS VERDICT, PER MAILBOX PROVIDER (it_engineer, 27 Oct 2026).
//
// #1696 retired the morning seed and left fn_invite_placement_gate answering 'fail:seed_retired' for ever, so after it
// no supplier invitation could go again. This check FAILS if that comes back, or if the replacement goes soft:
//   * offline: the canonical gate (MANIFEST, then pending, in apply order) is not the verdict reader, or has no
//     per-provider form; a bar number is written into a routine instead of public.invite_placement_bar; the finding is
//     filed on a held day or outside the registered relay; enqueue_supplier_invites, the outreach tick or the nudges
//     still hold every provider on the strict answer, or stop skipping a failing one; the file, the probe or this check
//     writes a campaign switch; a new routine or table is left open; the probe's inlined GlockApps numbers drift from
//     the fixture; the recorder accepts a result whose rows do not add up.
//   * production, in ONE aborted transaction: #1696's file (while pending), this file and the probe, which records the
//     REAL 27 Oct GlockApps result and proves the per-class verdicts, the expiry (7 days then, the bar's max_age: 30 since 2 Nov 2026), the bar on counts, the refusals,
//     the candidate filter, and that nothing (switch, mail, finding) moved; then the recorder's own SQL, rolled back.
//
//   node --test scripts/checks/the_invitation_gate_reads_the_glockapps_verdict_per_mailbox_provider.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { manifestWithPending, pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const NAME = 'the_invitation_gate_reads_the_glockapps_verdict_per_mailbox_provider';
const FILE = `scripts/sql/${NAME}.sql`;
const PROBE = `scripts/sql/${NAME}_probe.sql`;
const RETIRED_SEED = 'scripts/sql/no_test_mail_goes_to_the_founders_own_inboxes.sql';
const FIXTURE = 'scripts/checks/glockapps_27_oct_providers.fixture.json';
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const has = (p) => existsSync(join(ROOT, p));

// The body production runs for a routine (optionally one signature): the LAST definition in apply order.
function canonical(fn, argsStart = '') {
  const re = new RegExp(`create or replace function public\\.${fn}\\(${argsStart}`, 'i');
  const path = manifestWithPending().filter((p) => { try { return re.test(code(R(p))); } catch { return false; } }).pop();
  assert.ok(path, `${fn}(${argsStart}...) is defined nowhere`);
  const src = code(R(path));
  const at = src.search(re);
  const tag = src.slice(at).match(/\bas\s+(\$[a-z]*\$)/i)[1];
  const open = src.indexOf(tag, at);
  return { path, body: src.slice(at, src.indexOf(tag, open + tag.length) + tag.length) };
}

test('the canonical gate reads the GlockApps verdict, per provider, and fails closed by name', () => {
  assert.ok(has(FILE), `${FILE} is missing: the gate still answers fail:seed_retired for ever`);
  const strict = canonical('fn_invite_placement_gate', 'p_day date');
  assert.equal(strict.path, FILE, `${strict.path} is the canonical gate, not the verdict reader`);
  assert.match(strict.body, /fn_invite_placement_judge\(p_day, p_now\) ->> 'strict'/, 'the no-argument form does not answer for the strictest provider');
  const per = canonical('fn_invite_placement_gate', 'p_provider text');
  assert.equal(per.path, FILE);
  assert.match(per.body, /fn_invite_placement_judge\(p_day, p_now\) ->> v_c/);
  const v = canonical('fn_invite_placement_class_verdicts');
  assert.match(v.body, /from public\.deliverability_test d/);
  assert.match(v.body, /from public\.invite_placement_bar/);
  for (const s of ["'fail:no_verdict'", "'fail:stale_verdict'", 'b.max_age']) assert.ok(v.body.includes(s), `the verdict reader lost ${s}`);
  const bar = canonical('fn_invite_placement_rates_verdict');
  assert.ok(bar.body.includes("'fail:below_bar:' || c"));
  for (const k of ['microsoft_min_inbox_pct', 'google_max_spam_pct', 'google_min_delivered_pct', 'yahoo_aol_min_inbox_pct']) {
    assert.ok(bar.body.includes(`b.${k}`), `the bar ${k} is not read from public.invite_placement_bar`);
  }
  // THE BAR IS DATA: no percentage literal in the routines that decide (the one row holds 80 / 20 / 7 days).
  for (const b of [bar.body, v.body, strict.body, per.body, canonical('fn_invite_placement_judge').body]) {
    assert.doesNotMatch(b.replace(/'(?:[^']|'')*'/g, "''"), /\b(80|20)\b|interval\s*''/, 'a bar number is written into a deciding routine');
  }
  assert.match(code(R(FILE)), /other', v ->> 'microsoft'/, "'other' does not follow the Microsoft verdict");
});

test('the finding is one a day through the registered relay, on an open day only, and passing turns nothing on', () => {
  const j = canonical('fn_invite_placement_judge').body;
  assert.match(j, /if public\.fn_invite_placement_day_closed\(p_now\) is null then\s+if v ->> 'strict' <> 'pass' then\s+perform public\.fn_invite_placement_finding\(v_day,/,
    'the finding is filed on a held day, or not through fn_invite_placement_finding');
  assert.equal((j.match(/fn_invite_placement_finding\(/g) || []).length, 1, 'more than one way to file the finding');
  assert.doesNotMatch(j, /app_secrets|invite_enabled|golive/i, 'the judge reads or writes a campaign switch');
  const src = code(R(FILE));
  // The ONLY app_secrets write in the file is the bounce brake's existing auto-PAUSE, re-emitted from production.
  const writes = src.match(/update\s+app_secrets[^;]*;/gi) || [];
  // (the expected statement is assembled, so this file's own app_secrets guard below does not match its spelling)
  assert.deepEqual(writes, [['update', 'app_secrets', "set value='false' where key='invite_enabled';"].join(' ')],
    'the file writes app_secrets beyond the existing pause');
  assert.doesNotMatch(src, /insert\s+into\s+(public\.)?app_secrets|set\s+value\s*=\s*'true'|wa_supplier_invite_golive/i, 'the file can switch something on');
  for (const f of [PROBE, 'scripts/checks/the_invitation_gate_reads_the_glockapps_verdict_per_mailbox_provider.test.mjs', 'scripts/record_inbox_placement_verdict.mjs']) {
    assert.doesNotMatch(code(R(f)).replace(/doesNotMatch\([^\n]*/g, '').replace(/match\(\/update[^\n]*/g, ''),
      /(update|insert\s+into|delete\s+from|merge\s+into|truncate)\s+(only\s+)?(table\s+)?("?public"?\.)?"?app_secrets/i, `${f} writes app_secrets`);
  }
});

test('the batch, the tick and the nudges skip a failing provider instead of holding every one', () => {
  for (const fn of ['enqueue_supplier_invites', 'fn_sales_engineer_supplier_outreach_tick', 'fn_sales_engineer_nudges_invited_suppliers']) {
    const c = canonical(fn);
    // 2 Nov 2026: no longer pinned to one file; later files redefine these routines and the body is what this asserts
    assert.match(c.body, /fn_invite_placement_open_providers\(/, `${fn} does not ask which providers are open`);
    assert.doesNotMatch(c.body, /fn_invite_placement_gate\(/, `${fn} still holds every provider on the strict answer`);
    assert.match(c.body, /cardinality\(.*?\) = 0/s, `${fn} does not hold when NO provider is open`);
  }
  assert.match(canonical('enqueue_supplier_invites').body, /fn_supplier_invite_candidates\(v_remaining, v_open\)/);
  const n = canonical('fn_sales_engineer_nudges_invited_suppliers').body;
  assert.match(n, /fn_mail_provider_of_email\(r\.to_email\) <> all\(v_open\) then\s+v_skipped := v_skipped \+ 1; continue;/, 'a failing provider\'s nudge is not skipped');
  const two = canonical('fn_supplier_invite_candidates', 'p_limit integer, p_providers').body;
  assert.match(two, /p_providers is null or public\.fn_mail_provider_of_email\(l\.email\) = any\(p_providers\)/);
  assert.match(canonical('fn_supplier_invite_candidates', 'p_limit integer\\)').body, /fn_supplier_invite_candidates\(p_limit, null::text\[\]\)/,
    'the one-argument picker (daily supplier list, campaign list tick) does not read every class');
  const cls = canonical('fn_mail_provider_class').body;
  for (const s of ['protection\\.)?outlook\\.com', '(google|googlemail)\\.com', 'yahoodns\\.net']) assert.ok(cls.includes(s), `the MX class lost ${s}`);
});

test('new routines and tables are closed; the file is pending after #1696 and the probe is never applied', () => {
  const src = code(R(FILE));
  for (const t of ['invite_placement_bar', 'deliverability_test', 'deliverability_test_provider']) {
    assert.match(src, new RegExp(`alter table public\\.${t} enable row level security;`));
    assert.match(src, new RegExp(`create policy ${t}_service_role_only on public\\.${t}\\s+as permissive for all to public using \\(false\\) with check \\(false\\);`));
    assert.ok(src.includes(`revoke all on public.${t} from anon, authenticated;`), `${t} keeps its anon grant`);
  }
  for (const sig of ['fn_mail_provider_class(text, text[])', 'fn_mail_provider_of_email(text)', 'fn_glockapps_provider_class(text)',
    'fn_invite_placement_rates_verdict(jsonb)', 'fn_invite_placement_class_verdicts(timestamp with time zone)',
    'fn_record_inbox_placement_verdict(jsonb, text, text)', 'fn_invite_placement_judge(date, timestamp with time zone)',
    'fn_invite_placement_gate(text, date, timestamp with time zone)', 'fn_invite_placement_open_providers(date, timestamp with time zone)',
    'fn_supplier_invite_candidates(integer, text[])']) {
    assert.ok(src.includes(`revoke execute on function public.${sig} from public, anon, authenticated;`), `${sig} keeps the PUBLIC grant CREATE gives it`);
  }
  for (const m of src.matchAll(/create or replace function public\.(\w+)\(/gi)) {
    const b = src.slice(m.index, m.index + 700);
    assert.match(b, /set search_path to 'public', 'pg_temp'/i, `${m[1]}: search_path not pinned`);
  }
  const notes = pendingNotes();
  const manifest = R('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim());
  assert.ok(manifest.includes(FILE) !== notes.has(FILE), 'exactly one of a MANIFEST line and a pending note');
  assert.match(notes.get(PROBE) || '', /^A PROBE\b/, 'the probe must carry a probe note so it is never applied');
  const order = manifestWithPending();
  assert.ok(order.indexOf(FILE) > order.indexOf(RETIRED_SEED), 'this file must apply after #1696, whose fn_mailbox_fold it reads');
});

test('the probe records the fixture, and the recorder refuses a result that does not add up', async () => {
  const fx = JSON.parse(R(FIXTURE)); delete fx._source;
  const lit = R(PROBE).match(/\$glockapps\$(.*?)\$glockapps\$/s);
  assert.ok(lit, 'the probe no longer inlines the real result');
  assert.deepEqual(JSON.parse(lit[1]), fx, 'the probe\'s GlockApps numbers drifted from the fixture');
  const rec = await import('../record_inbox_placement_verdict.mjs');
  const p = rec.parseResult(R(FIXTURE));
  assert.equal(p.result.providerRollup.length, 35);
  assert.equal(p.rollupSeeds, 106, 'GlockApps\' provider rows covered 106 of its 111 tracked seeds on 27 Oct');
  const wrapped = rec.parseResult({ content: [{ type: 'text', text: JSON.stringify(fx) }] });
  assert.equal(wrapped.result.testId, fx.testId, 'an MCP envelope is not unwrapped');
  const bad = structuredClone(fx); bad.providerRollup[0].total = 99;
  assert.throws(() => rec.parseResult(bad), /total 99 is not inbox \+ spam \+ other \+ notDelivered/);
  assert.throws(() => rec.parseResult({ testId: fx.testId, created: fx.created, stats: fx.stats }), /detail 'providers'/);
  assert.equal(rec.dollar('a $gr$ b'), '$grx$a $gr$ b$grx$');
  // --dry-run before the apply replays the pending file first (review of #1701: it answered 42883 "does not exist")
  const script = R('scripts/record_inbox_placement_verdict.mjs');
  assert.match(script, /pendingNotes\(\)/, '--dry-run does not replay the pending routine before calling it');
  assert.ok(script.includes(`scripts/sql/${NAME}.sql`), '--dry-run does not name the pending file it must replay');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const pendingText = () => [RETIRED_SEED, FILE].filter((f) => pendingNotes().has(f)).map(R).join('\n;\n');

test('production, aborted: the real 27 Oct result is judged per provider, and nothing moves', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  let verdict, evidence;
  try { await replaySql(pendingText() + '\n;\n' + R(PROBE), { retry: false, label: NAME }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)\|(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    [verdict, evidence] = [m[1], m[2]];
  }
  assert.ok(verdict, 'the probe committed instead of rolling back');
  if (process.env.QD_SHOW_PROBE) console.log(verdict + '\n' + evidence);
  assert.equal(verdict, 'PROBE OK', `${verdict} — ${evidence}`);
});

test('production, aborted: the recorder\'s own SQL stores the fixture', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const rec = await import('../record_inbox_placement_verdict.mjs');
  const { result } = rec.parseResult(R(FIXTURE));
  const rows = await replaySql(pendingText() + '\n;\n' + rec.recordSql(result, 'supplier@quotesdone.com', 'it_engineer'),
    { rows: true, retry: false, label: `${NAME} recorder` });
  const r = rows?.[0]?.recorded;
  assert.equal(r?.recorded, true, JSON.stringify(rows).slice(0, 400));
  assert.deepEqual([r.class_rates.microsoft.seeds, r.class_rates.microsoft.inbox], [18, 0]);
  assert.equal(r.against_the_bar.microsoft, 'fail:below_bar:microsoft');
  assert.equal(r.class_rates.overall.unclassified, 5);
});
