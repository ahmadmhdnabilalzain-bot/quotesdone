// A SUPPLIER ASKING "WHY DO I GET NO JOBS?" IS ANSWERED FROM HIS TRADES (customer_support, 16 Nov 2026; founder ledgers
// 1711-1713, who-knows-what audit item 5). fn_wa_context's supplier branch had no trade, service or emirate, so WhatsApp could
// not say why nothing reached him. Since the_supplier_is_known_on_every_channel.sql it carries them and matching.why_no_jobs,
// and compose.ts words them as the e-mail reply and the quotation chat do (_shared/supplier_known.ts supplierStanding).
// Run: deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/wa_inbound/a_supplier_asking_why_no_jobs_is_answered_from_his_trades.test.ts
import { assert } from 'jsr:@std/assert@1';
import { composeSituation } from './compose.ts';

const MINE = { scope: 'supplier', known: true, company: 'ZZ DEMO Polar Duct Works',
  profile: { approval_status: 'approved', verified: true, trade_licence_no: 'ZZ-DEMO-1001', licence_expiry: '2027-06-04', licence_expired: false, licence_days_left: 200 },
  services: { confirmed: true, trades: [{ code: 'hvac', label: 'HVAC', open_to_customers: false }], trades_excluded: [], services: ['Split AC installation'], emirates_covered: ['dubai'] },
  matching: { receives_requests_now: true, jobs_sent_30d: 0, requests_in_his_trades_30d: 0, collaboration: { unanswered_in_a_row: 0, on_hold: false },
    why_no_jobs: [{ code: 'trades_not_open_to_customers', says: 'None of his trades is open to customers yet: a trade opens for customer requests once enough verified suppliers cover it.' },
      { code: 'no_requests_in_his_trades', says: 'No customer posted a request in his trades and emirates in the last 30 days.' }] },
  recent_jobs: [] };
const turn = (audience: string, mine: unknown) => ({ audience, known: { name: 'ZZ DEMO Polar Duct Works', approved: true },
  prefetch: { timeline: Promise.resolve({ data: null }), mine: Promise.resolve({ data: mine }), company: Promise.resolve({ data: null }),
    faq: Promise.resolve({ ctx: '', ids: [] }) } }) as never;

Deno.test('WhatsApp: the supplier\'s trades, emirates, jobs in 30 days and why not more reach the reply\'s facts, in words', async () => {
  const { situation, lean } = await composeSituation(turn('supplier', MINE), null);
  for (const f of [situation, lean]) {
    for (const s of ['HVAC (not open to customers yet)', 'Emirates he covers: dubai', '0 sent to him in the last 30 days', 'Why not more requests',
      'None of his trades is open to customers yet', 'No customer posted a request in his trades']) assert(f.includes(s), `missing "${s}"`);
  }
});

Deno.test('WhatsApp: a customer\'s record gets no supplier words', async () => {
  const { situation } = await composeSituation(turn('customer', { scope: 'customer', known: true, inquiries: [] }), null);
  assert(!situation.includes('Why not more requests') && !situation.includes('HIS OWN ACCOUNT, AS EVERY CHANNEL READS IT'));
});
