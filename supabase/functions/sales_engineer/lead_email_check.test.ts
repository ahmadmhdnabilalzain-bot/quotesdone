// deno test --no-check --node-modules-dir=none supabase/functions/sales_engineer/lead_email_check.test.ts
import { assertEquals, assert } from 'jsr:@std/assert@1';
import { DNS_PER_RUN, judgeDns, judgeWithoutDns, leadEmailCheckBatch, mailboxOf, typoDomain } from './lead_email_check.ts';
import { mxRecord } from '../_shared/mail_domain.ts';

Deno.test('the typo domains measured on production are caught', () => {
  for (const d of ['yahoo.coin', 'jpl.coin', 'rishabh.coin', 'gmai.com', 'gmial.com', 'gamil.com', 'gmal.com', 'yaho.com', 'hotmial.com',
    'yahoo.comna', 'yahoo.couk', 'rockfordtechnical.comm', 'yahoo.comabetaeim.ae', 'yahoo.comanasalbanooshfire.com']) {
    assert(typoDomain(d), d + ' should be a typo');
  }
});

Deno.test('a real domain is never called a typo', () => {
  for (const d of ['gmail.com', 'yahoo.com', 'yahoo.co.uk', 'yahoo.com.sg', 'ymail.com', 'mail.com', 'email.com', 'hotmail.com', 'outlook.com',
    'emirates.net.ae', 'acme.company', 'acme.community', 'acme.com', 'etisalat.ae', 'almoe.om', 'gulf.co', 'compass.com', 'a.compass.ae']) {
    assertEquals(typoDomain(d), null, d);
  }
});

Deno.test('known-bad addresses are rejected before DNS; a good one reaches DNS', () => {
  for (const [e, ev] of [['info@yahoo.coin', null], ['not an address', null], ['a@b', null], ['careers@acme.ae', null], ['hr@acme.ae', null],
    ['logo@2x.png', null], ['x@sentry.io', null], ['sales@acme.ae', 'not_found']] as Array<[string, string | null]>) {
    assertEquals(judgeWithoutDns(e, ev)?.verdict, 'rejected', e);
  }
  assertEquals(judgeWithoutDns('sales@acme.ae', 'verified'), null);
});

Deno.test('only a measured MX verifies; a failed lookup decides nothing', () => {
  assertEquals(judgeDns('sales@acme.ae', 'mx').verdict, 'verified');
  for (const k of ['nxdomain', 'no_records', 'a_implicit']) assertEquals(judgeDns('sales@acme.ae', k).verdict, 'rejected', k);
  assertEquals(judgeDns('sales@acme.ae', 'error').verdict, 'retry');
});

Deno.test('mailbox class: free mail, role, named', () => {
  assertEquals(mailboxOf('sales@gmail.com'), 'free');
  assertEquals(mailboxOf('Sales@acme.ae'), 'role');
  assertEquals(mailboxOf('ali@acme.ae'), 'named');
});

const dns = (...replies: unknown[]) => {
  let i = 0;
  return (async () => new Response(JSON.stringify(replies[i++]))) as unknown as typeof fetch;
};

Deno.test('DNS answers map to the kinds; SERVFAIL and a null MX are not mistaken', async () => {
  assertEquals(await mxRecord('a.ae', dns({ Status: 0, Answer: [{ type: 15, data: '20 b.mx.' }, { type: 15, data: '10 A.mx.' }] })), { kind: 'mx', hosts: ['a.mx', 'b.mx'] });
  assertEquals((await mxRecord('a.ae', dns({ Status: 3 }))).kind, 'nxdomain');
  assertEquals((await mxRecord('a.ae', dns({ Status: 2 }))).kind, 'error');
  assertEquals((await mxRecord('a.ae', dns({ Status: 0, Answer: [{ type: 15, data: '0 .' }] }))).kind, 'no_records');
  assertEquals((await mxRecord('a.ae', dns({ Status: 0 }, { Status: 0, Answer: [{ data: '1.2.3.4' }] }))).kind, 'a_implicit');
  assertEquals((await mxRecord('a.ae', dns({ Status: 0 }, { Status: 0 }))).kind, 'no_records');
  assertEquals((await mxRecord('a.ae', (async () => { throw new Error('timeout'); }) as unknown as typeof fetch)).kind, 'error');
});

Deno.test('one batch stays inside its DNS budget, and a lead left over gets no verdict', async () => {
  const leads = Array.from({ length: DNS_PER_RUN + 5 }, (_, i) => ({ lead_id: i + 1, email: `a@d${i}.ae`, email_verified: null, mx_kind: null }));
  leads.push({ lead_id: 900, email: 'b@known.ae', email_verified: null, mx_kind: 'mx' }, { lead_id: 901, email: 'c@yahoo.coin', email_verified: null, mx_kind: null });
  let stored: { p_checks: Array<{ lead_id: number; verdict: string }>; p_domains: unknown[] } | null = null;
  let asked = 0;
  const rpc = async (fn: string, args: Record<string, unknown>) => {
    if (fn === 'fn_sales_engineer_email_check_batch') return { data: leads, error: null };
    stored = args as never;
    return { data: {}, error: null };
  };
  const r = await leadEmailCheckBatch(rpc, async () => { asked++; return { kind: 'mx', hosts: ['m.x'] }; });
  assertEquals(asked, DNS_PER_RUN);
  assertEquals(r.domains_asked, DNS_PER_RUN);
  const s = stored as unknown as { p_checks: Array<{ lead_id: number; verdict: string }> };
  assertEquals(s.p_checks.length, DNS_PER_RUN + 2);
  assertEquals(s.p_checks.find((c) => c.lead_id === 901)?.verdict, 'rejected');
  assertEquals(s.p_checks.find((c) => c.lead_id === 900)?.verdict, 'verified');
  assert(!s.p_checks.some((c) => c.lead_id === DNS_PER_RUN + 5), 'a lead whose domain was not asked has no verdict');
});
