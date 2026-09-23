// EVERY SEAT RECALLS ITS PAST CASES BEFORE IT DECIDES.
//
// The regression check for scripts/sql/every_seat_remembers_its_cases_and_recalls_them_by_meaning.sql
// and supabase/functions/_shared/case_recall.ts. The founder, 23 Sep 2026: a seat that meets a case like
// one it handled before must remember "we did that before — what did we do, was it finalised?", for
// every seat, by meaning and never by word matching.
//
// TWO HALVES.
//   1. OFFLINE. Every seat decision path named below calls recallCases for its own seat and path, and
//      the call comes BEFORE the step that decides. Every seat has a write-back trigger in the SQL.
//      Delete a call, or move it after the decision, and this fails.
//   2. AGAINST PRODUCTION, in a transaction that always raises (nothing commits; if the objects are not
//      applied yet the SQL file itself runs inside the same aborted transaction). Case A — a ZZ DEMO
//      customer, named, with an e-mail and a phone — is handled and finalised. Case B, the same need in
//      other words from a different customer, recalls A with its outcome, from another seat, with no
//      name, e-mail, phone or source pointer in what comes back. An unrelated case recalls nothing above
//      the floor. The floor bites (raised to 0.99, B recalls nothing). And the trigger path is real: a
//      ZZ DEMO IT finding closed with a fix becomes a finalised case carrying the fix as its lesson, and
//      reopening it writes the correction back as a lesson.
//   Vectors come from ai_gateway {action:'embed'} — gte-small, free, not OpenRouter.
//
//   node --test scripts/checks/every_seat_recalls_before_it_decides.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const SQL_FILE = 'scripts/sql/every_seat_remembers_its_cases_and_recalls_them_by_meaning.sql';

// file, seat, path, and the text of the step that decides — the recall must come before it.
export const DECISION_PATHS = [
  ['supabase/functions/sales_engineer/index.ts', 'sales_engineer', 'assist', "admin.rpc('fn_sales_assist'"],
  ['supabase/functions/sales_engineer/index.ts', 'sales_engineer', 'match', "admin.rpc('fn_match_capability'"],
  ['supabase/functions/sales_engineer/index.ts', 'sales_engineer', 'spec_offer', "admin.rpc('fn_spec_offer_open'"],
  ['supabase/functions/site_assistant/index.ts', 'customer_support', 'reply', 'const sys = `You are the QuotesDone website assistant.'],
  ['supabase/functions/ceo_agent/index.ts', 'ceo', 'decide', "admin.from('ceo_approval').insert("],
  ['supabase/functions/ceo_agent/index.ts', 'ceo', 'judgement', 'await llm('],
  ['supabase/functions/accountant/index.ts', 'accountant', 'assist', "admin.rpc('fn_accountant_assist'"],
  ['supabase/functions/accountant/index.ts', 'accountant', 'expense_classification', "admin.from('expense_entries')\n          .upsert("],
  ['supabase/functions/it_engineer/index.ts', 'it_engineer', 'assist', "return J({ ok: true, seat: 'it_engineer', ...r"],
  ['supabase/functions/it_engineer/index.ts', 'it_engineer', 'triage', "return J({ ok: true, seat: 'it_engineer', issue_key"],
  ['supabase/functions/marketing/index.ts', 'marketing', 'assist', 'return error ? J('],
  ['supabase/functions/marketing_social_inbox/index.ts', 'marketing', 'social_reply', 'const d = decide(ev.text'],
  ['supabase/functions/marketing_channels/index.ts', 'marketing', 'plan', "admin.rpc('fn_marketing_campaign_hash'"],
];
export const SEATS = ['ceo', 'customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing'];

/** Index of the recallCases( call for this seat and path, or -1. */
function recallAt(src, seat, path) {
  let i = -1;
  while ((i = src.indexOf('recallCases(', i + 1)) !== -1) {
    const w = src.slice(i, i + 500);
    if (w.includes(`seat: '${seat}'`) && w.includes(`path: '${path}'`)) return i;
  }
  return -1;
}

test('every seat decision path recalls its past cases before it decides', () => {
  const missing = [];
  for (const [file, seat, path, decides] of DECISION_PATHS) {
    const src = read(file);
    const at = recallAt(src, seat, path);
    if (at === -1) { missing.push(`${file}: no recallCases for ${seat}/${path}`); continue; }
    const d = src.indexOf(decides, at);
    if (d === -1) missing.push(`${file}: ${seat}/${path} recalls AFTER the step that decides (or that step moved): ${decides.split('\n')[0]}`);
  }
  assert.deepEqual(missing, [], missing.join('\n'));
  // Every seat is covered by at least one path.
  assert.deepEqual(SEATS.filter((s) => !DECISION_PATHS.some((p) => p[1] === s)), []);
});

test('every seat writes its cases back, and recall is by meaning (a vector), never by words', () => {
  const sql = read(SQL_FILE);
  for (const seat of SEATS) {
    assert.match(sql, new RegExp(`fn_case_remember\\('${seat}'`), `${seat} has no write-back mapping`);
  }
  assert.equal((sql.match(/create trigger z90_case_memory/g) || []).length >= 12, true, 'a write-back trigger went missing');
  const recall = sql.slice(sql.indexOf('create or replace function public.fn_case_recall'), sql.indexOf('THE EMBED QUEUE'));
  assert.match(recall, /embedding <=> p_embedding/, 'fn_case_recall no longer ranks by the vector');
  assert.doesNotMatch(recall, /ilike|to_tsvector|plainto_tsquery|similarity\(/, 'fn_case_recall grew a word-matching route');
  const ts = read('supabase/functions/_shared/case_recall.ts');
  assert.match(ts, /embedLine/, 'case_recall.ts no longer embeds with gte-small');
  // No model route: the only network call is the recall RPC (a task class would mean a paid model).
  assert.doesNotMatch(ts, /task_?[cC]lass|functions\/v1\//);
});

// ── against production ──────────────────────────────────────────────────────────────────────────────
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

test('a reworded case from another customer recalls the finalised one, masked; an unrelated one recalls nothing',
  { skip: SKIP, timeout: 180_000 }, async () => {
  const { sql, PROJECT_REF } = await import('../lib/db.mjs');
  const secret = (await sql(`select value from public.app_secrets where key = 'cred_fn_ai'`))[0]?.value;
  assert.ok(secret, 'no cred_fn_ai in app_secrets');
  const embed = async (text) => {
    const r = await fetch(`https://${PROJECT_REF}.supabase.co/functions/v1/ai_gateway`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ __secret: secret, fn: 'check_case_recall', action: 'embed', text }) });
    const j = await r.json();
    assert.ok(j?.embedding, 'ai_gateway returned no embedding');
    return typeof j.embedding === 'string' ? j.embedding : JSON.stringify(j.embedding);
  };
  const A = 'ZZ DEMO customer Khalid Zzdemo (khalid.zzdemo@example.invalid, +971 50 000 1234) needs 40 split AC units supplied and installed for a two-floor office in Dubai Marina, quotes within a week';
  const B = 'We are looking for someone to supply and fit about forty wall-mounted air conditioners in our new office across two floors';
  const C = 'A recipe for baking sourdough bread at home with a long cold fermentation';
  const live = (await sql(`select to_regclass('public.seat_case_memory') is not null as ok`))[0].ok;
  const q = (s) => "'" + String(s).replace(/'/g, "''") + "'";
  const run = async (body) => {
    try { await sql((live ? '' : read(SQL_FILE) + '\n') + body, { retry: false }); }
    catch (e) {
      const m = String(e.message).match(/CHK<<(.*?)>>/s);
      if (!m) throw e;
      return JSON.parse(m[1].replace(/\\"/g, '"'));
    }
    throw new Error('the probe committed instead of rolling back');
  };
  // What is embedded in production is the MASKED situation (the tick embeds seat_case_memory.situation),
  // so the probe embeds exactly that, read back from fn_case_mask, never the raw text.
  const masked = (await run(`do $p$ begin raise exception 'CHK<<%>>', jsonb_build_object('s',
    public.fn_case_mask(${q(A)}, array['Khalid Zzdemo', 'khalid.zzdemo@example.invalid', '+971 50 000 1234']))::text; end $p$;`)).s;
  const [vA, vB, vC] = [await embed(masked), await embed(B), await embed(C)];

  const probe = `
do $p$
declare v_a bigint; v_cust uuid; v_sc text; v_r jsonb; v_c jsonb; v_hi jsonb; v_it jsonb; v_re jsonb; v_miss int;
begin
  select count(*) into v_miss from public.seat_case_memory_miss;
  -- Case A: handled by sales_engineer and finalised as won.
  v_a := public.fn_case_remember('sales_engineer', 'inquiry', 'zz_demo_check', 'case-a', 'hvac',
    ${q(A)}, 'matched 3 HVAC suppliers; quote accepted', null, 'won: supplier hired', true,
    array['Khalid Zzdemo', 'khalid.zzdemo@example.invalid', '+971 50 000 1234'], now(), null);
  perform public.fn_case_embed_write(v_a, ${q(vA)}::vector(384), (select md5(situation) from public.seat_case_memory where id = v_a));
  -- Case B asked of customer_support: another seat, other words, a different customer.
  v_r := public.fn_case_recall('customer_support', ${q(vB)}::vector(384), 'hvac', 5);
  v_c := public.fn_case_recall('customer_support', ${q(vC)}::vector(384), null, 5);
  v_hi := public.fn_case_recall('customer_support', ${q(vB)}::vector(384), 'hvac', 5, null, true, 0.99);
  -- The trigger path: a ZZ DEMO IT finding closed with a fix, then reopened.
  insert into public.it_engineer_finding (issue_key, title, where_it_is, blast, affected, evidence, ruled_out, undetermined, raised_by)
  values ('zz_demo_check:case_memory', 'ZZ DEMO the outbox stopped draining', 'ZZ DEMO send_outbox', 'internal', 0, '{}'::jsonb, '{}', '{}', 'it_engineer');
  update public.it_engineer_finding set closed_at = now(), close_note = 'ZZ DEMO restarted the drain' where issue_key = 'zz_demo_check:case_memory';
  select jsonb_build_object('finalised', finalised, 'lessons', to_jsonb(lessons)) into v_it
    from public.seat_case_memory where source_table = 'it_engineer_finding' and source_id = 'zz_demo_check:case_memory';
  update public.it_engineer_finding set closed_at = null where issue_key = 'zz_demo_check:case_memory';
  select jsonb_build_object('correction', correction, 'by', corrected_by, 'lessons', to_jsonb(lessons)) into v_re
    from public.seat_case_memory where source_table = 'it_engineer_finding' and source_id = 'zz_demo_check:case_memory';
  -- A mapping, not a hand-built call: a support case whose SUBJECT names its customer in free text
  -- must be masked from the customer row its party_id points at.
  insert into public.customers (full_name, email, phone)   -- is_demo is generated from the example.invalid address
  values ('Khalid Zzdemo', 'khalid.zzdemo@example.invalid', '+971500001234') returning id into v_cust;
  insert into public.support_case (case_ref, party_kind, party_id, subject)
  values ('ZZDEMO-CHECK-CASE-MEMORY', 'customer', v_cust::text,
          'ZZ DEMO Khalid asked why his AC quote was late; Khalid Zzdemo wants a call on +971500001234 or khalid.zzdemo@example.invalid');
  select situation into v_sc from public.seat_case_memory
   where source_table = 'support_case'
     and source_id = (select case_id::text from public.support_case where case_ref = 'ZZDEMO-CHECK-CASE-MEMORY');
  raise exception 'CHK<<%>>', jsonb_build_object('a', v_a, 'recall', v_r, 'unrelated', v_c, 'high_floor', v_hi,
    'support_situation', v_sc,
    'it', v_it, 'reopened', v_re,
    'a_row', (select jsonb_build_object('embedded', embedding is not null, 'situation', situation,
                     'sim_b', round((1 - (embedding <=> ${q(vB)}::vector(384)))::numeric, 3))
                from public.seat_case_memory where id = v_a),
    'new_misses', (select count(*) from public.seat_case_memory_miss) - v_miss)::text;
end $p$;`;
  const r = await run(probe);

  const hit = (r.recall.cases || []).find((c) => c.case_id === r.a);
  assert.ok(hit, `case B did not recall case A: ${JSON.stringify(r.recall).slice(0, 400)} — case A: ${JSON.stringify(r.a_row)}`);
  assert.equal(hit.finalised, true);
  assert.match(hit.outcome, /won/);
  assert.equal(hit.source, null, 'another seat was handed the source pointer');
  const text = JSON.stringify(hit);
  for (const leak of ['Khalid', 'Zzdemo', 'example.invalid', '000 1234', '0001234']) {
    assert.equal(text.includes(leak), false, `identity leaked through recall: ${leak}`);
  }
  assert.ok(r.support_situation, 'a support case did not become a case row');
  for (const leak of ['Khalid', 'Zzdemo', 'example.invalid', '500001234']) {
    assert.equal(r.support_situation.includes(leak), false, `a support case kept its customer's identity (${leak}): ${r.support_situation}`);
  }
  assert.deepEqual(r.unrelated.cases, [], `an unrelated case recalled something above the floor: ${JSON.stringify(r.unrelated.cases).slice(0, 300)}`);
  assert.deepEqual(r.high_floor.cases, [], 'the floor does not bite');
  assert.equal(r.it.finalised, true, 'a closed IT finding did not become a finalised case');
  assert.ok(r.it.lessons.some((l) => /restarted the drain/.test(l)), 'the fix did not become a lesson');
  assert.equal(r.reopened.by, 'it_engineer');
  assert.ok(r.reopened.lessons.some((l) => /did not hold/.test(l)), 'reopening did not become a lesson');
  assert.equal(r.new_misses, 0, 'a write-back failed inside the probe');
});
