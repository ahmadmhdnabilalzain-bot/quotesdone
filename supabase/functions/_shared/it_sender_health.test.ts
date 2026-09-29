// Duty 10 (sender health): the DMARC aggregate reading counts the messages that failed DMARC.
// Prevented by: this test - a report whose rows fail both DKIM and SPF must be counted as failed,
// or fn_it_duties_scheduled could never raise duty:sender:dmarc_fail_rate.
import { assertEquals } from 'jsr:@std/assert@1';
import { dmarcAggregate } from './it_scheduled_readings.ts';

const rec = (n: number, dkim: string, spf: string) =>
  `<record><row><source_ip>192.0.2.1</source_ip><count>${n}</count><policy_evaluated><disposition>none</disposition>` +
  `<dkim>${dkim}</dkim><spf>${spf}</spf></policy_evaluated></row></record>`;

Deno.test('a DMARC report with failing rows is counted as failed', () => {
  const xml = `<feedback><report_metadata><org_name>google.com</org_name></report_metadata>${rec(990, 'pass', 'fail')}${rec(10, 'fail', 'fail')}</feedback>`;
  assertEquals(dmarcAggregate(xml), { messages: 1000, failed: 10, org: 'google.com' });
});

Deno.test('an SPF pass alone passes DMARC; an empty report counts nothing', () => {
  assertEquals(dmarcAggregate(`<feedback>${rec(5, 'fail', 'pass')}</feedback>`).failed, 0);
  assertEquals(dmarcAggregate('<feedback></feedback>'), { messages: 0, failed: 0, org: null });
});
