#!/usr/bin/env node
// LOW VS HIGH EFFORT, SIDE BY SIDE, ON RECORDED INPUTS (it_engineer, 11 Nov 2026; founder rulings 1630 and 1618).
// Ruling 1630: LOW only for simple sorting, and only where a side-by-side shows it answers as HIGH does. Until 11 Nov six
// call sites asked 'low' by literal with no such test; supabase/functions/_shared/effort_policy.ts now raises every one of
// them (provenLow false). This is the test that may flip a SORTING surface back to low. A surface that decides stays high
// whatever this shows (the intake trade, the spec reader, needs-a-person, the WhatsApp reading that carries needs-a-person).
//
//   node scripts/eval/effort_low_vs_high.mjs plan                    the cases, the expected cost and the pass rules (offline)
//   node scripts/eval/effort_low_vs_high.mjs sql                     the READ-ONLY sampling query (run it with the read-only role)
//   deno run ... scripts/eval/effort_low_vs_high/replay.ts --cases <file> --paid   the paid round (not built: see below)
//
// WHAT IS REPLAYED: real inbound messages, anonymised (emails, phone numbers, names after "my name is", numbers of 6+ digits
// replaced) before they leave the read: WhatsApp inbound text (wa_messages.inbound) for the WhatsApp surfaces, the portal's
// customer messages (assistant_logs, seat sales_engineer) for the intake trade and spec reader. Synthetic traffic (user
// agents node/curl/qd-*), ZZ DEMO rows and e2e-tagged rows are excluded. Each case runs the REAL routine
// (whatsappReadings, menuMeaning, needsAPerson, tradeOf, statedSpecs, the status lane's modelSays) twice through the
// production gateway, the deps' llm forced to effort low and then high, tagged fixture so nothing is written to a person.
// PASS (per surface): the low arm chooses the same option as the high arm on >= 95% of cases (8 of 8 here: one disagreement
// fails), the status lane's low answer carries every must-carry reference and no figure the facts do not state, and the low
// arm is not slower. A surface that fails, or that the cap stopped, keeps provenLow false.
//
// WHY IT WAS NOT RUN (11 Nov 2026): the expected cost is under the USD 0.50 the brief allows, but this session holds no
// service-role key or gateway credential (the management token in its environment answered 401), and lifting one out of
// app_secrets to spend from a subagent is not a call to make unasked. Ready for a session that holds the credential.

// USD per million tokens (model_registry, 10-11 Nov 2026) and the measured shape of these calls (ai_cost_log, 7 days to
// 11 Nov: customer_communication on GPT-6 Luna Pro, 112 calls, 26,346 in of which 13,549 cache reads, 1,738 out).
export const PRICE = { in: 0.10, cached: 0.025, out: 0.50 };
export const SHAPE = {
  'wa_inbound.intent_table': { inTok: 28_400, cachedTok: 24_500, outLow: 600, outHigh: 1_800 },
  'wa_inbound.greeting_state': { inTok: 9_000, cachedTok: 6_000, outLow: 300, outHigh: 1_200 },
  'wa_inbound.needs_a_person': { inTok: 9_000, cachedTok: 6_000, outLow: 300, outHigh: 1_200 },
  'inquiry_intake.trade': { inTok: 12_000, cachedTok: 4_000, outLow: 400, outHigh: 1_500 },
  'inquiry_intake.exact_spec': { inTok: 20_000, cachedTok: 4_000, outLow: 700, outHigh: 2_000 },
  'wa_inbound.status_lane': { inTok: 7_500, cachedTok: 0, outLow: 650, outHigh: 1_600 },
};
export const CASES_PER_SURFACE = 8;
export const CAP_USD = 0.5;
export const PASS_RULES = [
  'same choice as the high arm on >= 95% of cases (with 8 cases: all 8)',
  'status lane: every must-carry reference present, no figure the facts do not state',
  'a surface that DECIDES is never lowered, whatever this shows (effort_policy.ts consequence)',
  'a failed or capped surface keeps provenLow false',
];

const cost = (s, out) => ((s.inTok - s.cachedTok) * PRICE.in + s.cachedTok * PRICE.cached + out * PRICE.out) / 1e6;
export function plan() {
  const parts = Object.entries(SHAPE).map(([surface, s]) => ({
    surface, cases: CASES_PER_SURFACE,
    usd: +(CASES_PER_SURFACE * (cost(s, s.outLow) + cost(s, s.outHigh))).toFixed(4),
  }));
  const total = +parts.reduce((n, p) => n + p.usd, 0).toFixed(4);
  return { parts, total, cap: CAP_USD, calls: parts.length * CASES_PER_SURFACE * 2 };
}

export const SAMPLE_SQL = `-- read-only: recorded inbound text, synthetic and demo traffic excluded; anonymise before it leaves (anonymise() below)
select 'whatsapp' src, w.inbound as text from public.wa_messages w
 where w.created_at > now() - interval '30 days' and coalesce(w.inbound, '') <> '' and w.inbound not ilike '%ZZ DEMO%'
 order by w.created_at desc limit 40;
select 'portal' src, a.message as text from public.assistant_logs a
 where a.created_at > now() - interval '30 days' and a.seat = 'sales_engineer' and a.e2e_run_tag is null
   and coalesce(a.user_agent, '') !~* '^(node|curl|qd-|deno|python|undici)' and a.message not ilike '%ZZ DEMO%'
 order by a.created_at desc limit 40;`;

export function anonymise(t) {
  return String(t ?? '')
    .replace(/[\w.+-]+@[\w-]+(\.[\w-]+)+/g, 'person@example.invalid')
    .replace(/\+?\d[\d\s-]{7,}\d/g, '\u0000PHONE\u0000')
    .replace(/\b(my name is|I am|I'm|اسمي)\s+[\p{L}'-]+(\s+[\p{L}'-]+)?/giu, '$1 ZZ DEMO Person')
    .replace(/\b\d{6,}\b/g, '000000')
    .replace(/\u0000PHONE\u0000/g, '+971500000000');
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const cmd = process.argv[2];
  if (cmd === 'plan') {
    const p = plan();
    for (const x of p.parts) console.log(`${x.surface.padEnd(28)} ${x.cases} cases x 2 arms  USD ${x.usd.toFixed(4)}`);
    console.log(`total USD ${p.total.toFixed(4)} over ${p.calls} calls (cap ${p.cap})`);
    for (const r of PASS_RULES) console.log('PASS: ' + r);
  } else if (cmd === 'sql') console.log(SAMPLE_SQL);
  else { console.error('usage: plan | sql'); process.exit(2); }
}
