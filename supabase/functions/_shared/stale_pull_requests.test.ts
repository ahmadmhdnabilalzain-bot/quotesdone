// The stale-pull-request decision (10 Nov 2026): dependabot excluded, the 48 hour boundary, the SQL-touching flag.
import { assertEquals } from 'jsr:@std/assert@1';
import { isDependabot, type OpenPr, STALE_PR_HOURS, stalePullRequests, staleCandidates } from './stale_pull_requests.ts';

const NOW = Date.parse('2026-11-10T12:00:00Z');
const ago = (h: number) => new Date(NOW - h * 3_600_000).toISOString();
const pr = (number: number, idleH: number, extra: Partial<OpenPr> = {}): OpenPr => ({
  number, title: 'it_engineer: PR ' + number, html_url: 'https://github.com/x/y/pull/' + number,
  created_at: ago(idleH + 24), updated_at: ago(idleH), user: { login: 'a-session', type: 'User' }, head: { ref: 'it_engineer/x' }, ...extra,
});

Deno.test('the threshold is 48 hours', () => assertEquals(STALE_PR_HOURS, 48));

Deno.test('dependabot is excluded by author and by branch, however old', () => {
  const bot = pr(1, 400, { user: { login: 'dependabot[bot]', type: 'Bot' } });
  const byBranch = pr(2, 400, { user: { login: 'someone', type: 'User' }, head: { ref: 'dependabot/npm_and_yarn/x' } });
  assertEquals(isDependabot(bot), true);
  assertEquals(isDependabot(byBranch), true);
  assertEquals(isDependabot(pr(3, 1)), false);
  assertEquals(stalePullRequests([bot, byBranch, pr(3, 400)], NOW).map((p) => p.number), [3]);
});

Deno.test('48 hours exactly is not stale; one minute more is', () => {
  assertEquals(staleCandidates([pr(10, 48)], NOW).length, 0);
  assertEquals(staleCandidates([pr(11, 48 + 1 / 60)], NOW).map((p) => p.number), [11]);
  assertEquals(staleCandidates([pr(12, 47.9)], NOW).length, 0);
});

Deno.test('an update date that does not parse is skipped, never raised', () => {
  assertEquals(staleCandidates([pr(20, 100, { updated_at: 'not a date' })], NOW).length, 0);
});

Deno.test('the SQL flag: true when the diff touches scripts/sql, false when it does not, null when the files were not read', () => {
  const r = stalePullRequests([pr(30, 100), pr(31, 100), pr(32, 100)], NOW, {
    30: ['src/a.ts', 'scripts/sql/pending/x.txt', 'scripts/sql/x.sql'],
    31: ['src/a.ts', 'docs/scripts/sql/not_this.md'],
    32: null,
  });
  const by = (n: number) => r.find((p) => p.number === n)!;
  assertEquals(by(30).touches_sql, true);
  assertEquals(by(30).sql_files, ['scripts/sql/pending/x.txt', 'scripts/sql/x.sql']);
  assertEquals(by(31).touches_sql, false);
  assertEquals(by(32).touches_sql, null);
});

Deno.test('each stale pull request carries its number, title, age and idle time, longest idle first', () => {
  const r = stalePullRequests([pr(40, 60), pr(41, 500)], NOW, {});
  assertEquals(r.map((p) => p.number), [41, 40]);
  assertEquals(r[0].idle_hours, 500);
  assertEquals(r[0].age_hours, 524);
  assertEquals(r[0].title, 'it_engineer: PR 41');
  assertEquals(r[0].url, 'https://github.com/x/y/pull/41');
});
