// deno test supabase/functions/_shared/it_duties_19_to_24.test.ts
// The pure halves of the IT engineer's duty 19-24 readings: what "opens" means for a restored file, what a
// table export's rows are, how Vercel's FOCUS charges are summed, and what a blocklist answer means.
import { sumFocusCharges } from './it_duty_readings.ts';
import { opensAs, rowsOf } from './it_restore_drill.ts';
import { dnsblVerdict } from './it_scheduled_readings.ts';

const eq = (a: unknown, b: unknown, m: string) => {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${m}: ${JSON.stringify(a)} != ${JSON.stringify(b)}`);
};
const bytes = (s: string) => new TextEncoder().encode(s);

Deno.test('a restored file opens only when its bytes say so', () => {
  eq(opensAs('a.pdf', bytes('%PDF-1.7\n...\n%%EOF\n')), true, 'pdf');
  eq(opensAs('a.pdf', bytes('%PDF-1.7\ntruncated')), false, 'a truncated pdf does not open');
  eq(opensAs('a.pdf', bytes('<html>error</html>')), false, 'an error page saved as .pdf does not open');
  eq(opensAs('p.json', bytes('[{"id":1}]')), true, 'json');
  eq(opensAs('p.json', bytes('[{"id":')), false, 'broken json');
  eq(opensAs('x.bin', new Uint8Array(0)), false, 'empty');
});

Deno.test('a table export is a list of rows, bare or wrapped', () => {
  eq(rowsOf([{ id: 1 }]), [{ id: 1 }], 'bare');
  eq(rowsOf({ rows: [{ id: 2 }] }), [{ id: 2 }], 'rows');
  eq(rowsOf({ data: [] }), [], 'data');
  eq(rowsOf({ table: 'x' }), null, 'not rows');
});

Deno.test('Vercel FOCUS charges are summed line by line; a line with no cost is counted, not guessed', () => {
  const r = sumFocusCharges('{"BilledCost":1.25,"BillingCurrency":"USD"}\n\n{"BilledCost":"2.5"}\nnot json\n{"BilledCost":null}\n');
  eq(r, { total: 3.75, currency: 'USD', lines: 2, unreadable: 2 }, 'sum');
  eq(sumFocusCharges(''), { total: 0, currency: null, lines: 0, unreadable: 0 }, 'empty month');
});

Deno.test('a blocklist refusal is never a listing and never clean', () => {
  eq(dnsblVerdict('dbl.spamhaus.org', []), 'clean', 'NXDOMAIN');
  eq(dnsblVerdict('dbl.spamhaus.org', ['127.0.1.2']), 'listed', 'spamhaus spam domain');
  eq(dnsblVerdict('dbl.spamhaus.org', ['127.255.255.254']), 'refused', 'spamhaus refuses public resolvers');
  eq(dnsblVerdict('dbl.spamhaus.org', ['127.0.1.255']), 'refused', 'spamhaus refuses the query type');
  eq(dnsblVerdict('multi.uribl.com', ['127.0.0.1']), 'refused', 'uribl answers a refused resolver with 127.0.0.1');
  eq(dnsblVerdict('multi.uribl.com', ['127.0.0.2']), 'listed', 'uribl black');
  eq(dnsblVerdict('multi.surbl.org', ['127.0.0.1']), 'refused', 'surbl refusal');
  eq(dnsblVerdict('multi.surbl.org', ['10.0.0.1']), 'refused', 'an answer outside 127/8 means nothing');
});
