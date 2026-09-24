// Guards for the Gmail Postmaster reading (it_engineer, 24 Sep 2026). A missing Postmaster number must read as
// "no data", never as 0; the 0.1% / 0.3% / LOW-BAD thresholds decide the finding and the pause; the digest line
// says exactly what was measured.
//   deno test supabase/functions/_shared/it_postmaster_readings.test.ts
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import {
  digestLine, finish, judge, NO_DATA, parseTrafficStats, POSTMASTER_SCOPE, SPAM_FINDING_RATIO, SPAM_PAUSE_RATIO,
  runPostmasterStep, statsDay, takePostmasterReading, trafficStatsUrl,
} from './it_postmaster_readings.ts';

const D = 'quotesdone.com';
const day = (ymd: string, extra: Record<string, unknown> = {}) => ({ name: `domains/${D}/trafficStats/${ymd}`, ...extra });

Deno.test('statsDay reads the date out of the resource name', () => {
  assertEquals(statsDay(`domains/${D}/trafficStats/20260922`), '2026-09-22');
  assertEquals(statsDay('garbage'), null);
});

Deno.test('present data: the newest day wins and every field is read', () => {
  const m = parseTrafficStats(D, { trafficStats: [
    day('20260920', { userReportedSpamRatio: 0.5 }),
    day('20260922', { userReportedSpamRatio: 0.0005, userReportedSpamRatioLowerBound: 0.0002, userReportedSpamRatioUpperBound: 0.0009,
                      domainReputation: 'HIGH', spfSuccessRatio: 1, dkimSuccessRatio: 0.998, dmarcSuccessRatio: 1 }),
  ] });
  assertEquals(m.basis, 'measured');
  assertEquals(m.stats_day, '2026-09-22');
  assertEquals([m.spam_ratio, m.spam_lower, m.spam_upper], [0.0005, 0.0002, 0.0009]);
  assertEquals(m.reputation, 'HIGH');
  assertEquals([m.spf, m.dkim, m.dmarc], [1, 0.998, 1]);
  const r = finish(m);
  assertEquals(r.verdict, { finding: false, pause: false, reasons: [] });
  assertEquals(r.line, 'Gmail Postmaster quotesdone.com 2026-09-22: spam 0.05% (0.02%-0.09%), reputation HIGH, SPF 100.0%, DKIM 99.8%, DMARC 100.0%');
});

Deno.test('a single /trafficStats/{day} object parses the same way', () => {
  assertEquals(parseTrafficStats(D, day('20260921', { domainReputation: 'MEDIUM' })).reputation, 'MEDIUM');
});

Deno.test('missing data: an empty list is no_data, never zero', () => {
  for (const body of [{}, { trafficStats: [] }, null]) {
    const r = finish(parseTrafficStats(D, body));
    assertEquals(r.basis, 'no_data');
    assertEquals(r.spam_ratio, null);
    assertEquals(r.reason, NO_DATA);
    assertEquals(r.verdict.finding, false);
    assertEquals(r.line, `Gmail Postmaster ${D}: ${NO_DATA}`);
    assert(!/0(\.0+)?%/.test(r.line), 'a no-data line must not print a percentage');
  }
});

Deno.test('below threshold: a day row with none of the numbers is no_data', () => {
  const r = finish(parseTrafficStats(D, { trafficStats: [day('20260922', { outboundEncryptionRatio: 1 })] }));
  assertEquals(r.basis, 'no_data');
  assertEquals(r.stats_day, '2026-09-22');
  assertEquals([r.spam_ratio, r.spf, r.dkim, r.dmarc], [null, null, null, null]);
  assertStringIncludes(r.line, NO_DATA);
});

// Google omits zero-valued fields. On a published day, an omitted ratio is a measured 0 (review of PR #961).
Deno.test('published day, spam ratio omitted: a measured 0% spam rate, not "no data"', () => {
  const p = finish(parseTrafficStats(D, { trafficStats: [day('20260922', { domainReputation: 'HIGH', spfSuccessRatio: 1, dkimSuccessRatio: 1, dmarcSuccessRatio: 1 })] }));
  assertEquals(p.basis, 'measured');
  assertEquals(p.spam_ratio, 0);
  assertEquals([p.spam_lower, p.spam_upper], [null, null], 'an absent bound is not invented');
  assertStringIncludes(p.line, 'spam 0.00%, reputation HIGH');
  assertEquals(p.verdict.finding, false);
});

Deno.test('published day, auth ratios omitted: a measured 0% SPF/DKIM/DMARC is shown, not hidden', () => {
  const p = finish(parseTrafficStats(D, { trafficStats: [day('20260922', { domainReputation: 'REPUTATION_CATEGORY_UNSPECIFIED', spfSuccessRatio: 1 })] }));
  assertEquals(p.basis, 'measured');
  assertEquals(p.reputation, null, 'an absent reputation is not a category');
  assertEquals([p.spf, p.dkim, p.dmarc], [1, 0, 0]);
  assertStringIncludes(p.line, 'spam 0.00%, reputation no data, SPF 100.0%, DKIM 0.0%, DMARC 0.0%');
  assert(!p.line.includes('DKIM no data'));
});

Deno.test('thresholds: 0.1% files a finding, 0.3% pauses, LOW and BAD pause', () => {
  const m = (spam: number | null, reputation: string | null = 'HIGH') =>
    parseTrafficStats(D, { trafficStats: [day('20260922', { userReportedSpamRatio: spam ?? undefined, domainReputation: reputation ?? undefined, spfSuccessRatio: 1 })] });
  assertEquals(SPAM_FINDING_RATIO, 0.001);
  assertEquals(SPAM_PAUSE_RATIO, 0.003);
  assertEquals(judge(m(0.00099)), { finding: false, pause: false, reasons: [] });
  assertEquals(judge(m(null)).finding, false, 'an omitted (zero) spam rate files nothing');
  assertEquals(judge(m(0.001)).finding, true);
  assertEquals(judge(m(0.001)).pause, false);
  assertEquals(judge(m(0.0029)).pause, false);
  assertEquals(judge(m(0.003)).pause, true);
  assertEquals(judge(m(null, 'MEDIUM')), { finding: false, pause: false, reasons: [] });   // spam omitted = 0%
  for (const bad of ['LOW', 'BAD']) {
    const v = judge(m(0, bad));
    assertEquals([v.finding, v.pause], [true, true]);
    assertStringIncludes(v.reasons.join(' '), bad);
  }
  assertStringIncludes(finish(m(0.004)).line, '; invitations paused');
  assertStringIncludes(finish(m(0.0015)).line, '; finding filed');
  // no data never pauses and never files
  assertEquals(judge(parseTrafficStats(D, {})), { finding: false, pause: false, reasons: [] });
});

Deno.test('unavailable: the reason is the line, and nothing is judged', () => {
  const r = finish({ domain: D, basis: 'unavailable', stats_day: null, spam_ratio: null, spam_lower: null, spam_upper: null,
    reputation: null, spf: null, dkim: null, dmarc: null, reason: 'no token' });
  assertEquals(r.line, `Gmail Postmaster ${D}: not read (no token)`);
  assertEquals(digestLine(r, r.verdict), r.line);
  assertEquals(r.verdict.pause, false);
});

Deno.test('the fetch: v1 trafficStats with a 7-day window, and a missing refresh token is unavailable without a call', async () => {
  const url = trafficStatsUrl(D, new Date('2026-09-24T10:00:00Z'));
  assert(url.startsWith('https://gmailpostmastertools.googleapis.com/v1/domains/quotesdone.com/trafficStats?'));
  assertStringIncludes(url, 'startDate.year=2026&startDate.month=9&startDate.day=17');
  assertStringIncludes(url, 'endDate.year=2026&endDate.month=9&endDate.day=25');
  assertEquals(POSTMASTER_SCOPE, 'https://www.googleapis.com/auth/postmaster.readonly');

  let calls = 0;
  const none = await takePostmasterReading(async () => { calls++; return new Response('{}'); }, async () => undefined);
  assertEquals(calls, 0);
  assertEquals(none.basis, 'unavailable');
  assertStringIncludes(String(none.reason), 'google_postmaster_refresh_token');

  const seen: string[] = [];
  const f = async (u: string) => {
    seen.push(u);
    if (u.startsWith('https://oauth2.googleapis.com/token')) return new Response(JSON.stringify({ access_token: 'x', expires_in: 3600 }));
    return new Response(JSON.stringify({ trafficStats: [day('20260922', { userReportedSpamRatio: 0.004, domainReputation: 'HIGH' })] }));
  };
  const got = await takePostmasterReading(f, async (k) => 'v-' + k, new Date('2026-09-24T10:00:00Z'));
  assertEquals(seen.length, 2);
  assertEquals(got.basis, 'measured');
  assertEquals(got.verdict.pause, true);

  const denied = await takePostmasterReading(async (u: string) => u.includes('oauth2')
    ? new Response(JSON.stringify({ access_token: 'x' })) : new Response(JSON.stringify({ error: { message: 'no access' } }), { status: 403 }),
    async (k) => 'v-' + k);
  assertEquals(denied.basis, 'unavailable');
  assertStringIncludes(String(denied.reason), '403');
});

// Deploy order (review of PR #961): resilience_ping deploys on merge, the SQL may still be pending.
Deno.test('the step: a missing routine or table is "skipped: schema not applied", never a failure', async () => {
  const reading = finish(parseTrafficStats(D, { trafficStats: [day('20260922', { domainReputation: 'HIGH' })] }));
  const read = async () => reading;
  const ok = (data: unknown) => ({ data, error: null });
  const err = (code: string) => ({ data: null, error: { code, message: 'ZZ ' + code } });
  for (const code of ['42883', '42P01', 'PGRST202', 'PGRST205']) {
    const out = await runPostmasterStep(async (fn) => fn === 'fn_it_scheduled_due' ? ok(['postmaster']) : err(code), read);
    assertEquals(out.skipped, 'schema not applied', code);
    assertEquals(out.code, code);
  }
  // not yet scheduled (schedule row not applied): not due, and Postmaster is never called
  let reads = 0;
  assertEquals(await runPostmasterStep(async () => ok(['sender']), async () => { reads++; return reading; }), { due: false });
  assertEquals(reads, 0);
  // applied: the record answers
  assertEquals(await runPostmasterStep(async (fn) => fn === 'fn_it_scheduled_due' ? ok(['postmaster']) : ok({ paused: false }), read),
    { due: true, basis: 'measured', finding: false, paused: false });
  // any other error is a real failure, thrown for step() to record
  let thrown = '';
  try { await runPostmasterStep(async (fn) => fn === 'fn_it_scheduled_due' ? ok(['postmaster']) : err('23514'), read); }
  catch (e) { thrown = String((e as Error).message); }
  assertStringIncludes(thrown, 'fn_it_postmaster_record');
});
