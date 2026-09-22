// A FAILED NO-EXACT-SPEC CHECK BACKS OFF INSTEAD OF RETRYING EVERY TICK (it_engineer, 22 Sep 2026,
// founder instruction 705). The recurrence check for scripts/sql/a_failed_spec_check_backs_off_instead_of
// _retrying_every_tick.sql and the sweep in supabase/functions/sales_engineer/index.ts.
//
// Two halves:
//   REPOSITORY  the sweep asks quote_compare for technical_only (no model) and reports every failure to
//               fn_spec_offer_failed; quote_compare answers technical_only before any model call. FAILS if
//               the sweep goes back to the full comparison or to retrying silently.
//   PRODUCTION  inside ONE transaction that raises at the end, so nothing survives: a ZZ DEMO customer
//               (@example.invalid, reserved number) and an inquiry that is a sweep candidate; a failure
//               takes it out of the sweep for 15 minutes, then 30; after the fifth it never comes back and
//               sales_engineer holds one finding for it. Skipped without a management token.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');

test('the sweep never asks for the paid comparison and never retries silently', () => {
  const se = read('supabase/functions/sales_engineer/index.ts');
  const sweep = se.slice(se.indexOf('async function specOfferSweep'), se.indexOf("const { data: due, error: dErr }"));
  assert.ok(sweep.length > 200, 'specOfferSweep not found');
  assert.match(sweep, /functions\/v1\/quote_compare[\s\S]*technical_only: true/, 'the sweep must ask quote_compare for technical_only');
  assert.match(sweep, /fn_spec_offer_failed/, 'every failure must be counted by fn_spec_offer_failed');
  assert.doesNotMatch(sweep, /out\.errors\.push\(`\$\{c\.inquiry_id\}/, 'a candidate failure pushed to errors without being counted is the retry-every-tick bug');
  const qc = read('supabase/functions/quote_compare/index.ts');
  const tOnly = qc.indexOf('body.technical_only === true');
  assert.ok(tOnly > 0 && tOnly < qc.indexOf("'/functions/v1/ai_gateway'"), 'technical_only must be answered before the gateway call');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

export const PROBE = String.raw`
do $probe$
declare
  r jsonb := '{}'::jsonb; v_cust uuid; v_lead bigint; v_rfq int; v_a uuid; f jsonb; k int;
  cand text := 'select exists (select 1 from public.fn_spec_offer_candidates(100) c where c.inquiry_id = $1)';
  v_in boolean;
begin
  select l.id into v_lead from public.leads l where l.company_name ilike 'ZZ DEMO%' order by l.id limit 1;
  if v_lead is null then raise exception 'PROBE<<{"skipped":"no ZZ DEMO lead to stand in as the invited supplier"}>>'; end if;
  insert into public.customers (full_name, email, phone, phone_verified, email_verified, locale)
  values ('ZZ DEMO spec backoff probe', 'zz-demo-specbackoff-probe@example.invalid', '+971500000093', true, true, 'en') returning id into v_cust;
  if not (select is_demo from public.customers where id = v_cust) then raise exception 'PROBE<<{"skipped":"the fixture customer is not recognised as demo; refusing to continue"}>>'; end if;
  select coalesce(max(rfq_no), 0) + 900000 into v_rfq from public.inquiries;
  insert into public.inquiries (customer_id, category, summary, status, rfq_no) values (v_cust, 'glass', 'ZZ DEMO spec backoff probe', 'sent', v_rfq) returning id into v_a;
  insert into public.inquiry_matches (inquiry_id, supplier_id, sent_at) values (v_a, v_lead, now());
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status, source) values (v_a, v_lead, 1000, 'submitted', 'form');

  execute cand into v_in using v_a; r := r || jsonb_build_object('candidate_before', v_in);
  f := public.fn_spec_offer_failed(v_a, 'ZZ DEMO probe: quote_compare HTTP 500');
  execute cand into v_in using v_a;
  r := r || jsonb_build_object('first', f - 'next_attempt_at', 'candidate_after_first_failure', v_in,
    'first_wait_min', round(extract(epoch from ((f ->> 'next_attempt_at')::timestamptz - now())) / 60));
  update public.inquiries set spec_offer_next_attempt_at = now() - interval '1 second' where id = v_a;
  execute cand into v_in using v_a; r := r || jsonb_build_object('candidate_when_due', v_in);
  f := public.fn_spec_offer_failed(v_a, 'ZZ DEMO probe: quote_compare HTTP 500');
  r := r || jsonb_build_object('second_wait_min', round(extract(epoch from ((f ->> 'next_attempt_at')::timestamptz - now())) / 60));
  for k in 3..5 loop
    update public.inquiries set spec_offer_next_attempt_at = now() - interval '1 second' where id = v_a;
    f := public.fn_spec_offer_failed(v_a, 'ZZ DEMO probe: quote_compare HTTP 500');
  end loop;
  r := r || jsonb_build_object('fifth', f - 'next_attempt_at');
  update public.inquiries set spec_offer_next_attempt_at = now() - interval '1 second' where id = v_a;
  execute cand into v_in using v_a; r := r || jsonb_build_object('candidate_after_last', v_in);
  perform public.fn_spec_offer_failed(v_a, 'ZZ DEMO probe: a sixth failure');
  r := r || jsonb_build_object('findings', (select count(*) from public.it_engineer_finding where issue_key = 'monitor:spec_offer_check_failed:' || v_a),
    'finding_owner', (select evidence ->> 'owner_seat' from public.it_engineer_finding where issue_key = 'monitor:spec_offer_check_failed:' || v_a),
    'checked_at_untouched', (select spec_offer_checked_at is null from public.inquiries where id = v_a));
  raise exception 'PROBE<<%>>', r::text;
end $probe$;`;

test('production: a failure backs off, doubles, and after the last attempt goes to sales_engineer, on demo data', { skip: SKIP }, async (t) => {
  const { sql } = await import('../lib/db.mjs');
  const [live] = await sql(`select to_regprocedure('public.fn_spec_offer_failed(uuid,text)') is not null as applied`);
  if (!live.applied) { t.skip('a_failed_spec_check_backs_off_instead_of_retrying_every_tick.sql is not applied yet'); return; }
  let out = null;
  const parse = (s) => { try { return JSON.parse(s); } catch { return JSON.parse(s.replace(/\\\\/g, '\\').replace(/\\"/g, '"')); } };
  try { await sql(PROBE); } catch (e) { const m = String(e.message || e).match(/PROBE<<([\s\S]*)>>/); if (!m) throw e; out = parse(m[1]); }
  assert.ok(out, 'the probe did not report');
  if (out.skipped) { t.skip(out.skipped); return; }
  assert.equal(out.candidate_before, true, 'the demo inquiry is a sweep candidate');
  assert.deepEqual(out.first, { ok: true, attempts: 1, handed_to_seat: false });
  assert.equal(out.candidate_after_first_failure, false, 'a failed check is NOT handed back on the next tick');
  assert.equal(out.first_wait_min, 15);
  assert.equal(out.candidate_when_due, true, 'it comes back once its next attempt is due');
  assert.equal(out.second_wait_min, 30, 'the wait doubles');
  assert.deepEqual(out.fifth, { ok: true, attempts: 5, handed_to_seat: true });
  assert.equal(out.candidate_after_last, false, 'after the last attempt the sweep never picks it again');
  assert.equal(out.findings, 1, 'one finding per inquiry, however many failures');
  assert.equal(out.finding_owner, 'sales_engineer');
  assert.equal(out.checked_at_untouched, true, 'a failure is not a check');
});
