// WHICH OPEN PULL REQUESTS HAVE BEEN LEFT ALONE (it_engineer, 10 Nov 2026). PURE: no fetch, no clock, no secret.
//
// MEASURED 10 Nov 2026: 15 pull requests opened by Claude sessions between ~20 Oct and 9 Nov were left open and nobody
// noticed for days. Some carried SQL that was never applied, and founder rulings of 5-9 Nov never reached
// public.founder_instruction. They were found by hand. The duty open_pull_requests (it_duty_readings.ts reads GitHub,
// fn_it_open_pull_requests_record decides what to raise) is the guard; this file is its stale-PR decision, kept pure so
// the boundary can be tested without GitHub.
//
// THE RULE (the task of 10 Nov 2026):
//   - dependabot's pull requests are never counted: they are opened by the thousand and merged by their own rules;
//   - a pull request is STALE when it has had no commit and no update for MORE than 48 hours. GitHub's updated_at moves on
//     a push, a comment, a review and a label, so "no commit or update" is read from updated_at alone; exactly 48 hours
//     is not stale (a boundary pinned by the test);
//   - a stale pull request is flagged touches_sql when its diff touches scripts/sql/ (SQL waiting to be applied). When its
//     files could not be read the flag is null, never false: "could not look" must not read as "no SQL".
export const STALE_PR_HOURS = 48;
export const SQL_PREFIX = 'scripts/sql/';

export type OpenPr = {
  number: number; title: string; html_url?: string; draft?: boolean;
  created_at: string; updated_at: string;
  user?: { login?: string; type?: string } | null;
  head?: { ref?: string } | null;
};

export type StalePr = {
  number: number; title: string; url: string | null; author: string; draft: boolean;
  created_at: string; updated_at: string; age_hours: number; idle_hours: number;
  /** true: the diff touches scripts/sql/; false: it does not; null: the files could not be read */
  touches_sql: boolean | null; sql_files: string[];
};

/** dependabot opens these itself: by author, or by the branch it always names dependabot/... */
export function isDependabot(pr: Pick<OpenPr, 'user' | 'head'>): boolean {
  const login = String(pr.user?.login ?? '').toLowerCase();
  return login === 'dependabot[bot]' || login === 'dependabot' || String(pr.head?.ref ?? '').startsWith('dependabot/');
}

const hoursBetween = (from: string, to: number): number => (to - Date.parse(from)) / 3_600_000;

/** The pull requests idle for more than `staleAfterHours`, dependabot's excluded. A date that does not parse is skipped. */
export function staleCandidates(prs: OpenPr[], now: number, staleAfterHours = STALE_PR_HOURS): OpenPr[] {
  return prs.filter((p) => !isDependabot(p)
    && Number.isFinite(Date.parse(p.updated_at)) && hoursBetween(p.updated_at, now) > staleAfterHours);
}

/** The paths of a diff that sit under scripts/sql/ (the .sql files and their pending notes alike). */
export function sqlPaths(files: string[]): string[] {
  return files.filter((f) => f.startsWith(SQL_PREFIX));
}

/**
 * The stale list, each with its age, idle time and SQL flag. `filesByNumber[n]` is the changed paths of pull request n,
 * or absent/null when GitHub would not say; the flag is then null.
 */
export function stalePullRequests(
  prs: OpenPr[], now: number, filesByNumber: Record<number, string[] | null | undefined> = {}, staleAfterHours = STALE_PR_HOURS,
): StalePr[] {
  const round = (h: number) => Math.round(h * 10) / 10;
  return staleCandidates(prs, now, staleAfterHours)
    .map((p) => {
      const files = filesByNumber[p.number];
      const sql = Array.isArray(files) ? sqlPaths(files) : [];
      return {
        number: p.number, title: String(p.title ?? '').slice(0, 300), url: p.html_url ?? null,
        author: String(p.user?.login ?? 'unknown'), draft: p.draft === true,
        created_at: p.created_at, updated_at: p.updated_at,
        age_hours: round(hoursBetween(p.created_at, now)), idle_hours: round(hoursBetween(p.updated_at, now)),
        touches_sql: Array.isArray(files) ? sql.length > 0 : null, sql_files: sql.slice(0, 5),
      };
    })
    .sort((a, b) => b.idle_hours - a.idle_hours || a.number - b.number);
}
