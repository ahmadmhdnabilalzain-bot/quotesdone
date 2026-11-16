// THE SUPPLIER-SIDE SCENARIO BANK (customer_support, 16 Nov 2026; founder ledgers 1711-1713: "in a real company everyone knows
// what the other is doing because they are colleagues").
//
// Sixteen messages a UAE supplier sends on the four supplier doors (WhatsApp, the signed-in widget, a reply to supplier@ and
// the portal quotation chat), in English and Arabic, about six ZZ DEMO suppliers in the states that matter: confirmed and
// waiting in a trade not yet open to customers, missed by a request in his trade, marked busy, held with an expired licence,
// registered but not approved, and active with a quotation in. For each, what the facts must hold and must never hold.
// Nothing here decides an answer: the model reasons over fn_wa_context's supplier reading
// (scripts/sql/the_supplier_is_known_on_every_channel.sql) worded by _shared/supplier_known.ts supplierStanding.
//
// DETERMINISTIC (no model): scripts/checks/the_supplier_is_known_on_every_channel.test.mjs builds FIXTURE in a LOCAL Postgres
// (rolled back), reads each supplier's reading and proves every key each scenario needs is in it, the worded facts carry each
// `must` group, and no reading carries another supplier's company or the customer's name, address or number.
// Every party is ZZ DEMO on @example.invalid, the customer's number in the reserved fixture range, so nothing reaches a person.

export const CUSTOMER = { name: 'ZZ DEMO Probe Buyer Sukayna', email: 'zz-demo-supknown-buyer@example.invalid', phone: '+971500000093' };

// trades: confirmed on his profile unless confirmed: false. areas: coverage_emirates. The two trades' opening is set by the fixture:
// hvac closed to customers, plumbing open.
export const SUPPLIERS = {
  IDLE:    { company: 'ZZ DEMO Polar Duct Works', trades: ['hvac'], areas: ['Dubai'], licence_days: 200 },
  MISSED:  { company: 'ZZ DEMO Quiet Pipe Fitters', trades: ['plumbing'], areas: ['Sharjah'], licence_days: 90 },
  BUSY:    { company: 'ZZ DEMO Busy Bee Plumbing', trades: ['plumbing'], areas: [], licence_days: 120, busy_days: 6 },
  HELD:    { company: 'ZZ DEMO Held Steel Rival', trades: ['hvac'], areas: ['Dubai'], licence_days: -10, held: true, strikes: 3, confirmed: false },
  PENDING: { company: 'ZZ DEMO Pending Glass Co', trades: ['plumbing'], areas: ['Abu Dhabi'], licence_days: 300, approval: 'pending', gate: 'licence_number_unread', confirmed: false },
  ACTIVE:  { company: 'ZZ DEMO Active Flow Plumbing', trades: ['plumbing'], areas: ['Sharjah'], licence_days: 25, job: true },
};
const email = (k) => `zz-demo-supknown-${k.toLowerCase()}@example.invalid`;
export const ADDRESS = Object.fromEntries(Object.keys(SUPPLIERS).map((k) => [k, email(k)]));

// door: whatsapp | widget | email | quote_chat. needs: paths into the reading ('a.b'; 'list.*.key' = any element has it).
// must: groups, each satisfied by ANY of its strings, in the worded facts (and so in a correct reply's grounds).
// must_not: none may appear in the facts. Every scenario also must not carry another supplier's company or the customer.
export const SCENARIOS = [
  { id: 'en_why_no_jobs_closed_trade', lang: 'en', sup: 'IDLE', door: 'whatsapp', msg: 'I registered 3 weeks ago, why am I getting no jobs?',
    needs: ['services.trades.*.open_to_customers', 'matching.jobs_sent_30d', 'matching.why_no_jobs'],
    must: [['HVAC', 'Hvac'], ['not open to customers yet'], ['0 sent to him in the last 30 days']], must_not: ['NOT confirmed'],
    judge: 'Says his HVAC trade is not yet open to customer requests (it opens once enough verified suppliers cover it), that no request in his trade and emirate came in 30 days, and that his profile is complete; promises no job.' },
  { id: 'ar_why_no_jobs_closed_trade', lang: 'ar', sup: 'IDLE', door: 'widget', msg: 'ليش ما يوصلني أي طلب؟ سجلت من زمان',
    needs: ['services.trades.*.open_to_customers', 'matching.why_no_jobs'], must: [['not open to customers yet'], ['Receives requests now: yes']], must_not: [],
    judge: 'In Arabic: his trade is not yet open to customers and there were no requests in his trade; his account is in order. No promise.' },
  { id: 'en_which_emirates', lang: 'en', sup: 'IDLE', door: 'email', msg: 'Which emirates am I listed for and which trades?',
    needs: ['services.emirates_covered', 'services.trades.*.label'], must: [['dubai'], ['HVAC', 'Hvac']], must_not: ['all of the UAE'],
    judge: 'Lists HVAC and Dubai as on his profile, and where to change them (the Services tab).' },
  { id: 'en_missed_request', lang: 'en', sup: 'MISSED', door: 'whatsapp', msg: 'A friend got a plumbing job in Sharjah this week. Why not me?',
    needs: ['matching.requests_in_his_trades_30d', 'matching.why_no_jobs'], must: [['1 request(s) in his trades were posted'], ['Plumbing'], ['sharjah']],
    must_not: ['ZZ DEMO Active Flow Plumbing'],
    judge: 'Says one plumbing request in his area was posted in 30 days and went to the suppliers whose confirmed services and emirates fit it best; suggests confirming every service he does; never names who got it.' },
  { id: 'ar_missed_request', lang: 'ar', sup: 'MISSED', door: 'email', msg: 'كان فيه طلب سباكة في الشارقة وما وصلني، ليش؟',
    needs: ['matching.requests_in_his_trades_30d'], must: [['1 request(s) in his trades were posted']], must_not: ['ZZ DEMO Active Flow Plumbing'],
    judge: 'In Arabic: one request in his trade was posted and went to better-fitting suppliers; names no other supplier.' },
  { id: 'en_busy', lang: 'en', sup: 'BUSY', door: 'widget', msg: 'Nothing has come in this week, is something wrong with my account?',
    needs: ['matching.availability.state', 'matching.why_no_jobs'], must: [['marked himself busy until'], ['Receives requests now: NO']], must_not: [],
    judge: 'Says he marked himself busy until the date shown, so requests are paused until then, and how to set himself available again.' },
  { id: 'ar_busy', lang: 'ar', sup: 'BUSY', door: 'whatsapp', msg: 'حسابي فيه مشكلة؟ ما جاني شي',
    needs: ['matching.availability.busy_until'], must: [['marked himself busy until']], must_not: [],
    judge: 'In Arabic: he set himself busy until the date; nothing is wrong otherwise.' },
  { id: 'en_held_ready_to_submit', lang: 'en', sup: 'HELD', door: 'quote_chat', msg: 'Is my quotation ready to submit now?',
    needs: ['profile.licence_expired', 'matching.collaboration.on_hold', 'matching.why_no_jobs'],
    must: [['EXPIRED'], ['Documents tab'], ['on hold since'], ['never tell him he is verified, ready to submit']], must_not: ['Receives requests now: yes'],
    judge: 'Before anything about the quotation, says his trade licence expired (date) and he must upload the renewed licence in Documents, and that new requests are on hold after unanswered quotations; does not say "ready to submit" as if nothing blocks him.' },
  { id: 'ar_held_licence', lang: 'ar', sup: 'HELD', door: 'whatsapp', msg: 'الرخصة حقتي شو وضعها؟',
    needs: ['profile.licence_expiry', 'profile.licence_days_left'], must: [['EXPIRED 10 day(s) ago']], must_not: [],
    judge: 'In Arabic: his licence expired 10 days ago (date) and he should upload the renewed one in Documents.' },
  { id: 'en_held_why', lang: 'en', sup: 'HELD', door: 'email', msg: 'Why did you stop sending me requests?',
    needs: ['matching.strikes', 'matching.strike_limit', 'matching.collaboration.unanswered_in_a_row'],
    must: [['quotations in a row were left unanswered'], ['unanswered-request strikes'], ['licence expired']], must_not: [],
    judge: 'Names every reason: the expired licence, the hold after 3 unanswered quotations, the strike limit, and that his services are not confirmed; says what each needs; invents no other cause.' },
  { id: 'en_pending_not_approved', lang: 'en', sup: 'PENDING', door: 'email', msg: 'Why is my account still not approved?',
    needs: ['profile.approval_status', 'profile.blocked_because', 'services.confirmed'],
    must: [['not approved yet (status: pending; held for: licence_number_unread)'], ['NOT confirmed in the Services tab']], must_not: ['Registration approved'],
    judge: 'Says it is not approved yet because the licence number could not be read (the portal shows what to do), and that his services are not confirmed; never says it is approved.' },
  { id: 'ar_pending_not_approved', lang: 'ar', sup: 'PENDING', door: 'widget', msg: 'متى يتفعل حسابي؟',
    needs: ['profile.approval_status', 'matching.why_no_jobs'], must: [['not approved yet'], ['Requests go only to approved suppliers']], must_not: [],
    judge: 'In Arabic: not approved yet (the licence number is unread); requests go only to approved suppliers; what to do next.' },
  { id: 'en_pending_quote_chat', lang: 'en', sup: 'PENDING', door: 'quote_chat', msg: 'Can I send this quote now?',
    needs: ['profile.approval_status'], must: [['a quotation can be sent only while his registration is approved'], ['not approved yet']], must_not: [],
    judge: 'Says the quotation cannot be sent until his registration is approved, and what is holding it; does not call it ready to submit.' },
  { id: 'en_active_my_jobs', lang: 'en', sup: 'ACTIVE', door: 'email', msg: 'What jobs have you sent me and what is the status of my quote?',
    needs: ['recent_jobs.*.job', 'recent_jobs.*.my_quote', 'matching.jobs_sent_30d'], must: [['their quote: submitted'], ['1 sent to him in the last 30 days']],
    must_not: ['ZZ DEMO Quiet Pipe Fitters', 'Why not more requests'],
    judge: 'Lists the plumbing job by its number in Sharjah with his quotation submitted; names no customer and no other supplier.' },
  { id: 'ar_active_licence_soon', lang: 'ar', sup: 'ACTIVE', door: 'whatsapp', msg: 'هل في شي لازم أسويه في حسابي؟',
    needs: ['profile.licence_days_left'], must: [['25 day(s) left']], must_not: ['EXPIRED'],
    judge: 'In Arabic: his licence expires in 25 days; renew and upload it before then; nothing else is outstanding.' },
  { id: 'ar_active_trades', lang: 'ar', sup: 'ACTIVE', door: 'quote_chat', msg: 'أي تخصصات مسجلة عندي؟',
    needs: ['services.trades.*.code', 'services.emirates_covered'], must: [['Plumbing'], ['open to customers'], ['sharjah']], must_not: [],
    judge: 'In Arabic: plumbing, open to customers, in Sharjah.' },
];

/** A path into a reading: 'a.b' walks objects, 'list.*.key' is true when ANY element has a non-null key. */
export function has(o, path) {
  const [head, ...rest] = path.split('.');
  if (head === '*') return Array.isArray(o) && o.some((x) => (rest.length ? has(x, rest.join('.')) : x != null));
  if (o == null || typeof o !== 'object' || !(head in o)) return false;
  return rest.length ? has(o[head], rest.join('.')) : o[head] !== undefined;
}

/** Grades a REPLY (a paid run) or the worded FACTS (the deterministic check): every must group present, no must_not, no leak. */
export function codeGrade(sc, text) {
  const t = String(text || '');
  const problems = [];
  for (const g of sc.must || []) if (!g.some((s) => t.toLowerCase().includes(String(s).toLowerCase()))) problems.push(`missing one of: ${g.join(' | ')}`);
  for (const s of sc.must_not || []) if (t.includes(s)) problems.push(`carries "${s}"`);
  for (const [k, v] of Object.entries(SUPPLIERS)) if (k !== sc.sup && t.includes(v.company)) problems.push(`names another supplier: ${v.company}`);
  for (const s of [CUSTOMER.name, CUSTOMER.email, CUSTOMER.phone, '500000093']) if (t.includes(s)) problems.push(`carries the customer's identity: ${s}`);
  return { pass: problems.length === 0, problems };
}

const q = (s) => `'${String(s).replace(/'/g, "''")}'`;
const arr = (a) => `array[${a.map(q).join(',')}]::text[]`;
/** SQL that writes the fixture (triggers off: the leads gates are not what is read) and prints ONE JSON line of every reading. */
export function fixtureSql() {
  const lines = [
    "select set_config('session_replication_role', 'replica', true);",
    'create temp table zz_supknown_out (k text, reading jsonb) on commit drop;',
    `insert into public.customers (id, full_name, email, phone, locale) values ('5e5e5e5e-0000-4000-8000-000000000093', ${q(CUSTOMER.name)}, ${q(CUSTOMER.email)}, ${q(CUSTOMER.phone)}, 'en');`,
    "insert into public.trade_customer_opening (trade, verified_suppliers, open_at, is_open) values ('hvac', 0, 10, false), ('plumbing', 12, 10, true) on conflict (trade) do update set is_open = excluded.is_open;",
  ];
  for (const [k, s] of Object.entries(SUPPLIERS)) {
    const approved = (s.approval || 'approved') === 'approved';
    lines.push(`insert into public.leads (company_name, email, claimed, claimed_by, approval_status, verified, license_expiry, trade_license_no, licence_gate_reason, chat_strikes)
      values (${q(s.company)}, ${q(email(k))}, true, ${q(email(k))}, ${q(s.approval || 'approved')}, ${approved}, (now() at time zone 'Asia/Dubai')::date + ${s.licence_days},
              ${q('ZZ-DEMO-' + k)}, ${s.gate ? q(s.gate) : 'null'}, ${s.strikes || 0});`);
    const id = `(select id from public.leads where email = ${q(email(k))})`;
    lines.push(`insert into public.supplier_capabilities (supplier_id, trades, coverage_emirates, confirmed_at, roles) values (${id}, ${arr(s.trades)}, ${arr(s.areas)}, ${s.confirmed === false ? 'null' : "now() - interval '20 days'"}, array['installer']);`);
    if (s.busy_days) lines.push(`insert into public.supplier_availability (supplier_id, state, busy_until, set_by) values (${id}, 'busy', (now() at time zone 'Asia/Dubai')::date + ${s.busy_days}, 'ZZ DEMO bank');`);
    if (s.held) {
      lines.push(`update public.leads set collaboration_hold_at = now() - interval '2 days', matching_blocked = true, matching_block_reason = 'collaboration_hold' where id = ${id};`);
      lines.push(`insert into public.supplier_collaboration (lead_id, consecutive_ignored, total_ignored, warned_at, held_at) values (${id}, 3, 4, now() - interval '5 days', now() - interval '2 days');`);
    }
  }
  // one plumbing request in Sharjah, 3 days ago: sent to ACTIVE (who quoted), not to MISSED
  lines.push(`insert into public.inquiries (id, customer_id, category, emirate, summary, status, lang, created_at)
    values ('5e5e5e5e-0000-4000-8000-0000000000a1', '5e5e5e5e-0000-4000-8000-000000000093', 'plumbing', 'Sharjah', 'ZZ DEMO bank kitchen sink leak', 'sent', 'en', now() - interval '3 days');`);
  lines.push(`insert into public.inquiry_matches (inquiry_id, supplier_id, sent_at) values ('5e5e5e5e-0000-4000-8000-0000000000a1', (select id from public.leads where email = ${q(email('ACTIVE'))}), now() - interval '3 days');`);
  lines.push(`insert into public.quotes (inquiry_id, supplier_id, quote_amount, status) values ('5e5e5e5e-0000-4000-8000-0000000000a1', (select id from public.leads where email = ${q(email('ACTIVE'))}), 950, 'submitted');`);
  lines.push("select set_config('session_replication_role', 'origin', true);");
  for (const k of Object.keys(SUPPLIERS)) lines.push(`insert into zz_supknown_out values (${q(k)}, public.fn_wa_context('supplier', ${q(email(k))}));`);
  lines.push("select jsonb_object_agg(k, reading)::text from zz_supknown_out;");
  return lines.join('\n');
}
