// Duty 10 (sender health): the DMARC aggregate reading counts the messages that failed DMARC.
// Prevented by: this test - a report whose rows fail both DKIM and SPF must be counted as failed,
// or fn_it_duties_scheduled could never raise duty:sender:dmarc_fail_rate.
import { assertEquals } from 'jsr:@std/assert@1';
import { dmarcAggregate, dmarcSources, mergeDmarcSources } from './it_scheduled_readings.ts';

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

// Ledger 1526 (19 Nov 2026): a shared SPF include may be removed only when no source that sends as us depends on it.
// Prevented by: these tests - a source whose DMARC pass rests on SPF alone is named, per IP, across reports.
// Addresses are RFC 5737 documentation ranges; nothing here is a real sender.
const src = (ip: string, n: number, dkim: string, spf: string, from = 'quotesdone.com') =>
  `<record><row><source_ip>${ip}</source_ip><count>${n}</count><policy_evaluated><disposition>none</disposition>` +
  `<dkim>${dkim}</dkim><spf>${spf}</spf></policy_evaluated></row><identifiers><header_from>${from}</header_from></identifiers></record>`;

Deno.test('each source IP is named with its DKIM and SPF result, and an SPF-only pass is flagged', () => {
  const xml = `<feedback>${src('192.0.2.10', 40, 'pass', 'pass')}${src('198.51.100.7', 3, 'fail', 'pass')}${src('203.0.113.9', 2, 'fail', 'fail')}</feedback>`;
  assertEquals(dmarcSources(xml), [
    { ip: '192.0.2.10', messages: 40, dkim: 'pass', spf: 'pass', header_from: 'quotesdone.com', spf_only: false },
    { ip: '198.51.100.7', messages: 3, dkim: 'fail', spf: 'pass', header_from: 'quotesdone.com', spf_only: true },
    { ip: '203.0.113.9', messages: 2, dkim: 'fail', spf: 'fail', header_from: 'quotesdone.com', spf_only: false },
  ]);
});

Deno.test('rows from many reports fold per IP, largest first, and the SPF-only total is the sum of those sources', () => {
  const a = dmarcSources(`<feedback>${src('192.0.2.10', 40, 'pass', 'pass')}${src('198.51.100.7', 3, 'fail', 'pass')}</feedback>`);
  const b = dmarcSources(`<feedback>${src('192.0.2.10', 10, 'pass', 'fail')}${src('198.51.100.7', 2, 'fail', 'pass')}</feedback>`);
  const m = mergeDmarcSources([...a, ...b]);
  assertEquals(m.sources.map((s) => [s.ip, s.messages, s.spf_only]), [['192.0.2.10', 50, false], ['198.51.100.7', 5, true]]);
  assertEquals(m.sources[0].spf, 'fail'); // a failing row is never hidden behind a passing one for the same IP
  assertEquals([m.spf_only_messages, m.spf_only_ips], [5, ['198.51.100.7']]);
});

Deno.test('a report with no records names no source; a list is capped at the top N', () => {
  assertEquals(mergeDmarcSources(dmarcSources('<feedback></feedback>')), { sources: [], spf_only_messages: 0, spf_only_ips: [] });
  const many = Array.from({ length: 25 }, (_, i) => src(`192.0.2.${i + 1}`, i + 1, 'pass', 'pass')).join('');
  const m = mergeDmarcSources(dmarcSources(`<feedback>${many}</feedback>`), 20);
  assertEquals([m.sources.length, m.sources[0].ip, m.sources[19].messages], [20, '192.0.2.25', 6]);
});
