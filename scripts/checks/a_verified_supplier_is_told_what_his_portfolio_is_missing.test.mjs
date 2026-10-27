// A VERIFIED SUPPLIER IS TOLD WHAT HIS PORTFOLIO IS MISSING (23 Sep 2026, sales_engineer detects,
// customer_support delivers; founder instruction 858).
//
// Founder instruction 857 made silence cost something: a supplier who did not tick a service has not
// confirmed he does it, so he does not receive inquiries naming it. Most suppliers never open the
// Services tab. Instruction 858 is what makes 857 safe: three working days after a supplier is
// verified, the sales engineer checks his portfolio and, if something is missing, customer_support
// tells him on email and WhatsApp what is missing and how to fill it — once, and not at all if he
// already did it.
//
// What fails if that breaks:
//   * the duty falls off the seat clock, or the WhatsApp leg loses its template     -> static tests
//   * the reminder goes early, goes twice, goes to a supplier who completed it, counts a weekend,
//     or reaches a real address                                                     -> the live probe
//     (scripts/sql/a_verified_supplier_is_told_what_his_portfolio_is_missing_probe.sql: a rolled-back
//     rehearsal on ZZ DEMO / @example.invalid fixtures, zero residue, one verdict row)
//
//   node --test scripts/checks/a_verified_supplier_is_told_what_his_portfolio_is_missing.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';
import { seatWorkFixtures } from '../lib/seat_work_fixtures.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => (existsSync(join(ROOT, p)) ? readFileSync(join(ROOT, p), 'utf8') : '');
const FILE = 'scripts/sql/a_verified_supplier_is_told_what_his_portfolio_is_missing.sql';
const CHANGE = R(FILE);
const PROBE = R('scripts/sql/a_verified_supplier_is_told_what_his_portfolio_is_missing_probe.sql');
const WA = R('supabase/functions/send_whatsapp/index.ts');
const MANIFEST = R('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim()).filter((l) => l.endsWith('.sql'));

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

// The canonical definition is the one in the file listed LAST in MANIFEST.txt.
function canonicalBody(fn) {
  const re = new RegExp(`create or replace function public\\.${fn}\\(`, 'i');
  const owner = [...MANIFEST].reverse().find((f) => re.test(R(f)));
  assert.ok(owner, `no file in MANIFEST defines ${fn}`);
  const src = R(owner);
  return { owner, body: src.slice(src.search(re)).split('$fn$')[1] || '' };
}

test('the reminder is a duty on the seat clock, owned by sales_engineer', () => {
  const { owner, body } = canonicalBody('fn_seat_clocks_tick');
  assert.match(body, /public\.fn_supplier_portfolio_reminder_tick\(/, `the canonical fn_seat_clocks_tick (${owner}) does not run the portfolio reminder`);
  assert.match(CHANGE, /fn_supplier_portfolio_reminder_tick[\s\S]*fn_add_working_days\(/, 'the due date is not counted in working days by the estate helper');
});

test('sales_engineer hands off to customer_support, who answers, and only sales_engineer closes', () => {
  assert.match(CHANGE, /'supplier\.portfolio_incomplete',\s*'sales_engineer',\s*'customer_support'/, 'the handoff kind is not registered sales_engineer -> customer_support');
  assert.match(CHANGE, /'fn_customer_support_reminds_supplier_of_portfolio',\s*null,\s*true/, 'the conversation is not originator-closed');
  assert.match(CHANGE, /set_config\('qd\.handoff_closer', 'sales_engineer', true\)/, 'sales_engineer never closes its own handoff');
  assert.match(CHANGE, /fn_customer_support_takes_delivery\(/, 'the message does not go through customer_support\'s delivery door');
});

test('the WhatsApp leg rides the supplier account-notice template', () => {
  assert.match(WA, /'supplier_portfolio_incomplete'[^\n]*return 'supplier_account_notice'/, 'send_whatsapp has no template for supplier_portfolio_incomplete, so the twin would be skipped as unmapped');
});

test('the message is written in English and in formal Arabic', () => {
  const at = CHANGE.indexOf('create or replace function public.fn_supplier_portfolio_reminder_compose(');
  assert.ok(at > 0, 'no composer');
  const body = CHANGE.slice(at).split('$fn$')[1] || '';
  assert.match(body, /تحية طيبة وبعد/, 'the Arabic is not in the formal register');
  assert.match(body, /وتفضلوا بقبول فائق الاحترام والتقدير/, 'the Arabic letter has no formal close');
  assert.match(body, /Services tab/, 'the English guide does not say where to click');
});

// THE LOGIC, NOT THE FILES (review of #869). While the live matcher still reaches a supplier who ticked
// nothing in a trade (fn_match_capability's silent_in arm, removed by #868), telling him "requests in this
// trade do not reach you" is false, so that gap must not be raised. And a word the reasoning has read as a service
// is not "unmatched": he is told which service it is. The first version of the gap reader failed both.
// Since #888 (B5, "no word matching anywhere") a word names a service only through a REASONED
// supplier_own_word_reading row, never through an alias: until it is read, it stays his own word (29 Sep 2026).
test('live: no trade gap while the matcher still reaches silent suppliers; a reasoned word names its service', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const r = await sql(`
    create temp table if not exists zz_gap_logic (v text) on commit drop;
    do $t$
    declare v_id bigint; g jsonb; f text := ''; v_silent boolean;
    begin
      v_silent := position('silent_in' in pg_get_functiondef('public.fn_match_capability(text[],text,text[],text[],text,numeric,text,integer,text[])'::regprocedure)) > 0;
      begin
        insert into public.leads (company_name, email) values ('ZZ DEMO gap logic', 'zz.gaplogic@example.invalid') returning id into v_id;
        insert into public.supplier_capabilities (supplier_id, trades, roles, services, confirmed_at)
          values (v_id, '{painting}', '{contractor}', array['الدهانات'], now());
        g := public.fn_supplier_portfolio_gaps(v_id);
        if v_silent and g @> '[{"code":"trade_without_service"}]' then f := f || 'a trade gap was raised while the live matcher still reaches silent suppliers; '; end if;
        if not v_silent and not g @> '[{"code":"trade_without_service"}]' then f := f || 'no trade gap once the matcher reads ticks; '; end if;
        if coalesce(g::text like '%painting.interior%', false) then f := f || 'an unread word was given a service by its spelling: ' || g::text || '; '; end if;
        insert into public.supplier_own_word_reading (supplier_id, word, service_key, status, reasoned_at)
          values (v_id, 'الدهانات', 'painting.interior', 'reasoned', now());
        g := public.fn_supplier_portfolio_gaps(v_id);
        if not coalesce(g::text like '%painting.interior%', false) then f := f || 'the reasoned word «الدهانات» was not told its service (painting.interior): ' || coalesce(g::text, 'null') || '; '; end if;
        raise exception 'zz_done';
      exception when others then if sqlerrm <> 'zz_done' then f := f || 'raised: ' || sqlerrm; end if;
      end;
      insert into zz_gap_logic values (case when f = '' then 'OK' else f end);
    end $t$;
    select v from zz_gap_logic;`, { retry: false });
  assert.equal(String(r?.[0]?.v), 'OK');
});

test('send_whatsapp re-reads the portfolio before this reminder leaves', () => {
  assert.match(WA, /supplier_portfolio_incomplete'\)\s*\{\s*const g = await portfolioGate\(/, 'a WhatsApp copy can leave after the supplier completed his portfolio');
  const GATE = R('supabase/functions/send_whatsapp/portfolio_gate.ts');
  assert.match(GATE, /fn_supplier_portfolio_reminder_still_due/, 'the gate does not ask the database');
  assert.match(GATE, /if \(r\.data === true\) return \{ action: 'send' \}/, 'only an explicit "still due" may send');
  assert.ok(WA.indexOf('portfolioGate(') > WA.indexOf('heldStale++; continue;'), 'the re-check must follow the staleness bar, or a held row never expires');
});

test('the rolled-back rehearsal on production answers PROBE OK', { skip: SKIP }, async () => {
  assert.ok(PROBE, 'no probe file');
  const { sql } = await import('../lib/db.mjs');
  // Ruling 1199 (#1479, demo_activity_files_no_seat_task_or_handoff.sql) files no handoff for a ZZ DEMO
  // supplier; this rehearsal proves the sales_engineer -> customer_support handoff on one, so it switches
  // that guard off for its own rolled-back transaction (scripts/lib/seat_work_fixtures.mjs).
  const r = await replaySql(seatWorkFixtures() + '\n;\n' + PROBE, { retry: false, rows: true });
  const verdict = String(r?.[0]?.verdict ?? JSON.stringify(r));
  console.log(verdict);
  assert.match(verdict, /^PROBE OK/, verdict);
});
