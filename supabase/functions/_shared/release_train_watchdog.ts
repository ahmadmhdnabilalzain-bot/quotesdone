// THE RELEASE TRAIN'S WATCHDOG (it_engineer, 4 Oct 2026, item 26). The train (.github/workflows/release-train.yml)
// runs on GitHub's cron, and GitHub drops scheduled runs on a busy hour; reviewed PRs then sit with nothing
// releasing them. resilience_ping looks once a beat: reviewed PRs waiting and no train run STARTED in 20
// minutes -> it dispatches the train itself, with the token the estate already holds (app_secrets.github_token,
// the one customer_api uses to dispatch cad-read-worker.yml).
//
// NEVER A DRY RUN BY MISTAKE. release-train.yml declares `dry_run` as a boolean input that DEFAULTS TO TRUE, so a
// dispatch that omits it is a dry run that releases nothing and still counts as "a run started". The payload
// always names it, as the string 'false' (the dispatch API takes input values as strings; the workflow reads
// `inputs.dry_run`, which GitHub types back to the boolean false). release_train_watchdog.test.ts asserts it.
export const REPO = 'ahmadmhdnabilalzain-bot/quotesdone';
export const TRAIN_WORKFLOW = 'release-train.yml';
export const TRAIN_LABEL = 'review-approved';          // the label scripts/it/release_train.mjs releases on
export const BLOCKING_LABELS = ['hold', 'release-failed', 'needs-seat'];
export const STALL_MS = 20 * 60_000;

export function dispatchPayload() {
  return { ref: 'main', inputs: { dry_run: 'false' } } as const;
}

type Pr = { draft?: boolean; labels?: { name: string }[] };
/** PRs the train would consider: reviewed, not draft, not held. */
export function waitingForTrain(prs: Pr[]): number {
  return prs.filter((p) => {
    const names = (p.labels || []).map((l) => l.name);
    return !p.draft && names.includes(TRAIN_LABEL) && !names.some((n) => BLOCKING_LABELS.includes(n));
  }).length;
}

export function shouldDispatch(waiting: number, lastRunCreatedAt: string | null, now = Date.now()): boolean {
  if (waiting <= 0) return false;
  const t = lastRunCreatedAt ? Date.parse(lastRunCreatedAt) : NaN;
  return Number.isNaN(t) || now - t >= STALL_MS;
}

type Fetch = typeof fetch;
export async function watchTrain(fetchFn: Fetch, sec: (k: string) => Promise<string>, now = Date.now()) {
  const token = await sec('github_token');
  if (!token) return { ok: false, error: 'app_secrets.github_token is empty: the train watchdog cannot look' };
  const headers = { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'User-Agent': 'quotesdone-resilience-ping' };
  const api = `https://api.github.com/repos/${REPO}`;
  const pr = await fetchFn(`${api}/pulls?state=open&base=main&per_page=100`, { headers, signal: AbortSignal.timeout(10_000) });
  if (!pr.ok) return { ok: false, error: `GitHub pulls answered ${pr.status}` };
  const waiting = waitingForTrain(await pr.json());
  if (!waiting) return { ok: true, waiting, dispatched: false };
  const rr = await fetchFn(`${api}/actions/workflows/${TRAIN_WORKFLOW}/runs?per_page=1`, { headers, signal: AbortSignal.timeout(10_000) });
  if (!rr.ok) return { ok: false, error: `GitHub workflow runs answered ${rr.status}` };
  const last = ((await rr.json())?.workflow_runs?.[0]?.created_at as string | undefined) ?? null;
  if (!shouldDispatch(waiting, last, now)) return { ok: true, waiting, last_run: last, dispatched: false };
  const d = await fetchFn(`${api}/actions/workflows/${TRAIN_WORKFLOW}/dispatches`, {
    method: 'POST', headers, body: JSON.stringify(dispatchPayload()), signal: AbortSignal.timeout(10_000) });
  if (d.status !== 204) return { ok: false, error: `release train dispatch answered ${d.status}` };
  return { ok: true, waiting, last_run: last, dispatched: true };
}
