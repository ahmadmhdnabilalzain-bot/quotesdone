// THE REVEAL INVOICE IS THE ACCOUNTANT'S, AND THE SALES ENGINEER TELLS THE CUSTOMER (14 Sep 2026).
//
// Founder, 14 Sep 2026: "anything related to payment is under the accountant agent. and the
// accountant need to be in communication back and forth with the sales agent."
//
// Against production, inside ONE aborted transaction (skipped without a management token): a ZZ DEMO
// customer (@example.invalid) pays, the Stripe invoice is attached through the one door
// (fn_transaction_attach_invoice), and the test asserts that
//   - the edge functions on the money path are owned by the accountant in public.function_owner;
//   - the invoice is filed ONCE into the customer's Documents (kind 'invoice'), even on a replay;
//   - exactly one handoff reaches the sales engineer, from the accountant, and is closed by it;
//   - the customer's "invoice ready" message is queued once, and never names the accountant;
//   - invoice.issued is on company_event with actor 'accountant'.
// The block ends in RAISE, so every row it wrote is rolled back; the counts travel in the message.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const REF = 'htdblwldjkcgjvmqkbeh';
function token() {
  if (process.env.SUPABASE_ACCESS_TOKEN) return process.env.SUPABASE_ACCESS_TOKEN.trim();
  const p = join(homedir(), '.supabase', 'access-token');
  return existsSync(p) ? readFileSync(p, 'utf8').trim() : '';
}

const PROBE = String.raw`
do $probe$
declare
  c uuid; i uuid; q uuid; t uuid; l bigint;
  v_path text := 'invoices/stripe/2026-09-14/in_zzdemoprobe_ZZDEMO-0001.pdf';
  v_inv jsonb := '{"id":"in_zzdemoprobe","number":"ZZDEMO-0001","status":"paid","total":31322,"currency":"aed","invoice_pdf":"https://pay.stripe.com/invoice/zzdemo/pdf","hosted_invoice_url":"https://invoice.stripe.com/i/zzdemo"}';
  r1 jsonb; r2 jsonb; out jsonb;
begin
  insert into public.customers (full_name, email, locale)
  values ('ZZ DEMO Invoice Buyer', 'zz.demo.invoice.probe@example.invalid', 'en') returning id into c;
  insert into public.leads (company_name, email)
  values ('ZZ DEMO — Invoice Probe Supplier', 'zz.demo.invoice.supplier@example.invalid') returning id into l;
  insert into public.inquiries (customer_id, summary) values (c, 'ZZ DEMO invoice probe') returning id into i;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount) values (i, l, 10000) returning id into q;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, app_fee,
    processing_fee, total_charged, customer_price, paid_by, payment_ref, fee_status, revealed_at)
  values (q, i, l, c, 10000, 300, 300, 13.22, 313.22, 10000, 'customer', 'pi_zzdemoprobe', 'paid', now())
  returning id into t;

  r1 := public.fn_transaction_attach_invoice(t, v_inv, v_path, 'ZZDEMO-0001.pdf', 'application/pdf');
  r2 := public.fn_transaction_attach_invoice(t, v_inv, v_path, 'ZZDEMO-0001.pdf', 'application/pdf'); -- replay

  out := jsonb_build_object(
    'attach1', r1->'ok', 'attach2', r2->'ok',
    'owners', (select jsonb_object_agg(function_slug, owner) from public.function_owner
                where function_slug in ('stripe_checkout','stripe_webhook','stripe_confirm','reveal_invoice')),
    'documents', (select count(*) from public.documents where bucket = 'finance-docs' and path = v_path and kind = 'invoice'
                    and ref_table = 'inquiries' and ref_id = i::text),
    'handoffs', (select jsonb_agg(jsonb_build_object('agent', agent, 'status', status, 'from', detail->>'from', 'decided_by', decided_by))
                   from public.agent_actions where kind = 'handoff' and detail->>'transaction_id' = t::text
                    -- the invoice handoff only: a paid reveal also starts the seats' own handoffs
                    -- (reveal.paid and its deliveries, payments_are_the_accountant_and_the_seats_close_every_refund_together.sql)
                    and detail->>'subject' = 'reveal_invoice'),
    -- one email notice and its WhatsApp twin (ledger 1535, #1846: every confirmation goes on both; the twin is 'skipped'
    -- with its reason while the number is unconfirmed)
    'ready_msgs', (select count(*) from public.notifications where type = 'invoice_ready' and coalesce(channel, 'email') = 'email'
                     and to_email = 'zz.demo.invoice.probe@example.invalid'),
    'ready_twins', (select count(*) from public.notifications where type = 'invoice_ready' and channel = 'whatsapp'
                     and to_email = 'zz.demo.invoice.probe@example.invalid'),
    'ready_names_accountant', (select count(*) from public.notifications where type = 'invoice_ready'
                                 and to_email = 'zz.demo.invoice.probe@example.invalid' and (subject || body) ilike '%accountant%'),
    'events', (select jsonb_agg(actor) from public.company_event where event_type = 'invoice.issued' and entity_id = t::text),
    'stored_fields', (select jsonb_build_object('inv', stripe_invoice_id, 'pdf', stripe_invoice_pdf_url is not null,
                        'hosted', stripe_invoice_hosted_url is not null, 'total_charged', total_charged)
                        from public.transactions where id = t));
  raise exception 'CHK<<%>>', out;
end $probe$;`;

test('the reveal invoice is filed by the accountant and handed to the sales engineer, once', { skip: !token() && 'no management token' }, async () => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST', headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: PROBE }),
  });
  const text = await r.text();
  const m = text.match(/CHK<<(.*?)>>/s);
  assert.ok(m, 'probe did not reach its report: ' + text.slice(0, 600));
  const out = JSON.parse(m[1].replace(/\\"/g, '"'));
  assert.deepEqual(out.owners, { stripe_checkout: 'accountant', stripe_webhook: 'accountant', stripe_confirm: 'accountant', reveal_invoice: 'accountant' });
  assert.equal(out.attach1, true);
  assert.equal(out.attach2, true);
  assert.equal(out.documents, 1, 'filed once into Documents, replay included');
  assert.deepEqual(out.handoffs, [{ agent: 'sales_engineer', status: 'done', from: 'accountant', decided_by: 'sales_engineer' }]);
  assert.equal(out.ready_msgs, 1, 'one invoice_ready email');
  assert.equal(out.ready_twins, 1, 'one invoice_ready WhatsApp twin (ledger 1535)');
  assert.equal(out.ready_names_accountant, 0, 'the customer never hears the accountant');
  assert.deepEqual(out.events, ['accountant']);
  assert.deepEqual(out.stored_fields, { inv: 'in_zzdemoprobe', pdf: true, hosted: true, total_charged: 313.22 });
});
