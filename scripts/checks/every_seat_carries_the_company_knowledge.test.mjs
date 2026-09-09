// EVERY SEAT CARRIES THE COMPANY KNOWLEDGE — and it is READ, not written into a routine.
//
// Founder ruling, 9 September 2026, verbatim: "the company knowledge is literally connected to every
// seat automatically. Any seat that we made, the company knowledge should be there. Otherwise, those
// agents wouldn't know where they work or what they do or what is our company about."
//
// It was FALSE when he said it. fn_it_engineer_assist and fn_ceo_context existed and nothing called
// them; the it_engineer edge function called one routine (fn_agent_may_act) and ceo_agent one
// (fn_ceo_command_submit); only the accountant and the sales engineer retrieved anything at all, and
// neither carried a word about what the company IS. public.fn_company_context() is the one company
// block now, and all five seat routines pin it on every return path including the refusals.
//
// WHAT THIS CHECK REFUSES TO ACCEPT AS A PASS.
//   * A seat routine that drops the block. That is the whole point.
//   * A block that is missing a fact. Each required fact is asserted by its own live value, read from
//     the table beside the assertion, so a block that quietly loses the licence expiry fails.
//   * A block that is HARDCODED. This is the positive control, and it is the reason the check writes
//     at all: inside a transaction that is always rolled back, the licence number and the reveal rate
//     are changed to values that exist nowhere in the estate, fn_company_context() is called again,
//     and the block must carry the probe values. A routine with the real figures typed into it passes
//     every other assertion in this file and fails this one.
//   * A routine that returns the company block and nothing else. Each seat is asked for its OWN
//     retrieval half in the same call, so the block cannot be used to hide a broken seat.
//
// EVERY SEAT CALL RUNS INSIDE AN ABORTED TRANSACTION. fn_sales_assist and fn_accountant_assist are
// VOLATILE — the sales one records a knowledge gap and can open a task when it cites nothing — so a
// check that simply called them would leave a trail of fictional gaps behind every CI run.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

// THE CI CHECKS JOB HAS NO MANAGEMENT TOKEN. Every test here reads production; without a token they
// would not fail meaningfully, they would fail on the connection and say nothing about whether the
// seats carry the company knowledge. The estate's convention is to SKIP and say so loudly, so a green
// CI run never reads as "verified against production" when it was not.
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

// The five seats and the routine each one's runtime retrieves through, with a query that the seat's
// own corpus can actually answer — a refusal is a legitimate answer here, but a call that errors is
// not, and the `ok`/`records` assertions below are what stop the company block masking a dead seat.
const SEATS = [
  { seat: 'ceo',              call: "public.fn_ceo_context('company strategy and priorities', 4000, 3)" },
  { seat: 'customer_support', call: "public.fn_support_context('how do refunds work', 4000, 3)" },
  // fn_sales_assist takes two arguments without defaults — the text AND the embedding — so it is
  // called with an explicit null vector. The other two default everything after the text.
  { seat: 'sales_engineer',   call: "public.fn_sales_assist('supplier verification requirements'::text, null::vector)" },
  { seat: 'accountant',       call: "public.fn_accountant_assist('how is an expense booked'::text)" },
  { seat: 'it_engineer',      call: "public.fn_it_engineer_assist('how are credentials rotated'::text)" },
];

// The estate's aborted-transaction idiom: do the work, carry the answer out on the exception message,
// and let the rollback undo everything. Nothing this file runs can commit.
const PROBE = /CHK<<([\s\S]*)>>CHK/;
async function probe(body) {
  try {
    await sql(`do $probe$\nbegin\n${body}\nend $probe$;`);
  } catch (e) {
    // db.mjs throws the raw HTTP body, so the payload arrives BACKSLASH-ESCAPED inside it. Parsing
    // the body first and taking .message is what turns \" back into " — pulling the regex straight
    // off the outer string yields JSON that fails on its first key, which cost a run to work out.
    let msg = String(e?.message || e);
    const brace = msg.indexOf('{');
    if (brace >= 0) {
      try { msg = JSON.parse(msg.slice(brace))?.message ?? msg; } catch { /* not an HTTP body */ }
    }
    const m = PROBE.exec(msg);
    if (m) return JSON.parse(m[1]);
    throw new Error('probe did not report: ' + msg.slice(0, 400));
  }
  throw new Error('probe committed instead of rolling back — it must end in a raise');
}

test('the company block is complete, untruncated and carries every required fact', { skip: SKIP }, async () => {
  const [row] = await sql(`select public.fn_company_context() c,
      (select license_no  from public.company_registration order by recorded_at desc nulls last limit 1) lic,
      (select to_char(expires_on,'DD Mon YYYY') from public.company_registration order by recorded_at desc nulls last limit 1) exp,
      (select to_char(vat_threshold_aed,'FM999,999,999') from public.company_registration order by recorded_at desc nulls last limit 1) vat,
      (select round(coalesce(standard_reveal_rate,0.03)*100,2)::text from public.pricing_config order by id limit 1) pct,
      (select coalesce(supplier_free_count,1000)::text from public.pricing_config order by id limit 1) freen,
      (select supplier_reg_fee::text from public.pricing_config order by id limit 1) fee`);
  const c = typeof row.c === 'string' ? JSON.parse(row.c) : row.c;

  assert.equal(c.complete, true, `the block reports missing facts: ${JSON.stringify(c.missing)}`);
  assert.equal(c.truncated, false, 'the block was cut by its character budget — raise the default');
  assert.ok(c.block.length > 4000, `the block is only ${c.block.length} characters — something dropped out`);

  // Each fact is asserted against the value read from the table in the SAME query, so this cannot
  // drift into a list of literals that agree with each other and with nothing live.
  const must = [
    ['the DET licence number',        row.lic],
    ['the licence expiry',            row.exp],
    ['the VAT threshold',             row.vat],
    ['the reveal rate',               row.pct + '%'],
    ['the supplier free count',       row.freen],
    ['the supplier registration fee', 'AED ' + row.fee],
  ];
  for (const [what, value] of must) {
    assert.ok(c.block.includes(value), `${what} (${value}) is not in the company block`);
  }
  for (const marker of ['TOP-3', 'ANTI-CIRCUMVENTION', 'REVEAL FEE', 'NOT registered',
                        '## 5. THE SEATS', 'STANDING DECISIONS', 'AIMING AT']) {
    assert.ok(c.block.includes(marker), `the company block has lost its "${marker}" section`);
  }
  for (const seat of SEATS.map(s => s.seat)) {
    assert.ok(c.block.includes(seat), `seat ${seat} is not named in the company block`);
  }
});

test('the public block carries the published facts and withholds the internal ones', { skip: SKIP }, async () => {
  // customer_support runs on site_assistant, the widget a stranger talks to on the home page. It must
  // be grounded in the same LIVE figures as the internal seats -- and must not be carrying the
  // founder's standing decisions, the seat list or the revenue targets one polite question away from
  // anybody. Both halves are asserted here: withholding alone would pass if the block were empty.
  const [row] = await sql(`select public.fn_company_context(16000,'public') p,
      (select license_no from public.company_registration order by recorded_at desc nulls last limit 1) lic`);
  const p = typeof row.p === 'string' ? JSON.parse(row.p) : row.p;

  assert.equal(p.audience, 'public');
  assert.equal(p.complete, true, `the public block reports missing facts: ${JSON.stringify(p.missing)}`);
  for (const marker of [row.lic, 'REVEAL FEE', 'TOP-3', 'ANTI-CIRCUMVENTION', 'NOT registered']) {
    assert.ok(p.block.includes(marker), `the public block has lost "${marker}" — it is published, not internal`);
  }
  for (const secret of ['STANDING DECISIONS', 'AIMING AT', 'it_engineer', 'accountant', 'REVENUE_AED_1M']) {
    assert.ok(!p.block.includes(secret),
      `LEAK: the public company block contains "${secret}", which is internal and reaches the home page widget`);
  }
});

test('POSITIVE CONTROL: the block is read from the tables, not written into the routine', { skip: SKIP }, async () => {
  // If fn_company_context carried the figures as literals it would satisfy every other test in this
  // file. This changes the source rows to values that appear nowhere in the estate and requires the
  // block to change with them. The transaction always aborts, so production is untouched.
  const out = await probe(`
    declare v_before jsonb; v_after jsonb;
    begin
      v_before := public.fn_company_context();
      update public.company_registration set license_no = 'ZZ-DEMO-LICENCE-90210', expires_on = date '2099-12-31';
      -- pricing_config_no_discount_no_cap_ck requires the promotional rate to equal the standard one,
      -- which is the constraint that makes "no discount, ever" true rather than merely written down.
      -- The probe moves both together; it is testing where the block READS from, not the guard.
      update public.pricing_config set standard_reveal_rate = 0.077, promo_reveal_rate = 0.077;
      v_after := public.fn_company_context();
      raise exception 'CHK<<%>>CHK', jsonb_build_object(
        'before_has_probe', (v_before->>'block') like '%ZZ-DEMO-LICENCE-90210%',
        'after_has_probe',  (v_after->>'block')  like '%ZZ-DEMO-LICENCE-90210%',
        'after_has_rate',   (v_after->>'block')  like '%7.70%',
        'after_has_expiry', (v_after->>'block')  like '%31 Dec 2099%',
        'fingerprint_moved', (v_before->>'fingerprint') is distinct from (v_after->>'fingerprint'))::text;
    end;`);

  assert.equal(out.before_has_probe, false, 'the probe value was already in the block — the probe proves nothing');
  assert.equal(out.after_has_probe, true,
    'HARDCODED: the licence number in the company block did not follow company_registration');
  assert.equal(out.after_has_rate, true,
    'HARDCODED: the reveal rate in the company block did not follow pricing_config');
  assert.equal(out.after_has_expiry, true,
    'HARDCODED: the licence expiry in the company block did not follow company_registration');
  assert.equal(out.fingerprint_moved, true, 'the fingerprint did not move when the company facts did');

  const [{ n }] = await sql(`select count(*) n from public.company_registration where license_no = 'ZZ-DEMO-LICENCE-90210'`);
  assert.equal(Number(n), 0, 'the probe did not roll back — a demo licence number is live in production');
});

for (const { seat, call } of SEATS) {
  test(`the ${seat} seat carries the company block on its own retrieval call`, { skip: SKIP }, async () => {
    const out = await probe(`
      declare v jsonb; v_c jsonb;
      begin
        v   := ${call};
        v_c := public.fn_company_context();
        raise exception 'CHK<<%>>CHK', jsonb_build_object(
          'has_company',   v ? 'company',
          'block_len',     length(coalesce(v->'company'->>'block','')),
          'same_block',    (v->'company'->>'fingerprint') is not distinct from (v_c->>'fingerprint'),
          'complete',      coalesce((v->'company'->>'complete')::boolean, false),
          -- the seat's OWN half, so the block cannot stand in for a dead seat
          'seat_answered', (v ? 'records') or (v ? 'advisory_records'),
          'seat_ok',       coalesce(v->>'ok', 'n/a'),
          'keys',          (select jsonb_agg(k order by k) from jsonb_object_keys(v) k))::text;
      end;`);

    assert.equal(out.has_company, true,
      `the ${seat} seat's routine returned no "company" key. It returned: ${JSON.stringify(out.keys)}. `
      + 'The founder ruled on 9 Sep 2026 that every seat carries the company knowledge automatically.');
    assert.ok(out.block_len > 4000,
      `the ${seat} seat's company block is only ${out.block_len} characters`);
    assert.equal(out.same_block, true,
      `the ${seat} seat carries a DIFFERENT company block from fn_company_context() — there must be one body, not a copy`);
    assert.equal(out.complete, true, `the ${seat} seat's company block reports missing facts`);
    assert.equal(out.seat_answered, true,
      `the ${seat} seat's routine returned the company block but none of its own retrieval — `
      + 'a company block must never be able to mask a broken seat');
  });
}

test('the five seats on record are exactly the five this check covers', { skip: SKIP }, async () => {
  // A sixth seat added without a company block would otherwise pass silently: every seat this file
  // knows about would still carry it. The founder's ruling is about ANY seat the company makes.
  const rows = await sql(`select agent_key from public.org_agents where active order by agent_key`);
  const live = rows.map(r => r.agent_key).sort();
  const covered = SEATS.map(s => s.seat).sort();
  assert.deepEqual(live, covered,
    'org_agents does not match the seats this check covers. A new seat must be given the company '
    + 'block (public.fn_company_context()) and added to SEATS in this file before it can pass.');
});
