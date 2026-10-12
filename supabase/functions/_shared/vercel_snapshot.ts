// The daily read-only snapshot of the Vercel project's configuration (it_engineer, 12 Oct 2026; the
// founder: "fix it" for the backup workflow). The code is in GitHub and the routes/crons in vercel.json,
// but the project settings and the env var NAMES were backed up nowhere. This keeps, every day:
// domains, env var names per environment, crons, framework and build settings. NEVER a secret value:
// the env list is requested without decrypt, and every value field is dropped here again regardless.

// deno-lint-ignore no-explicit-any
type J = any;
export type EnvName = { key: string; targets: string[]; type: string };
export type Snapshot = { taken_at: string; project: Record<string, unknown>; domains: { name: string; verified: boolean; redirect: string | null; git_branch: string | null }[];
  env: EnvName[]; crons: unknown };

const BUILD_KEYS = ['name', 'id', 'framework', 'nodeVersion', 'buildCommand', 'devCommand', 'installCommand', 'outputDirectory',
  'rootDirectory', 'serverlessFunctionRegion', 'directoryListing', 'gitForkProtection', 'skipGitConnectDuringLink', 'autoExposeSystemEnvs',
  'sourceFilesOutsideRootDirectory', 'publicSource', 'commandForIgnoringBuildStep', 'speedInsights', 'webAnalytics'];

export function snapshot(project: J, domains: J, env: J, takenAt: string): Snapshot {
  const p: Record<string, unknown> = {};
  for (const k of BUILD_KEYS) if (project?.[k] !== undefined) p[k] = project[k];
  if (project?.link) p.git = { type: project.link.type, repo: project.link.repo ?? project.link.repoName ?? null, productionBranch: project.link.productionBranch ?? null };
  return {
    taken_at: takenAt,
    project: p,
    domains: (domains?.domains ?? []).map((d: J) => ({ name: String(d.name), verified: !!d.verified, redirect: d.redirect ?? null, git_branch: d.gitBranch ?? null }))
      .sort((a: { name: string }, b: { name: string }) => a.name.localeCompare(b.name)),
    // key, targets and type ONLY: the value is never copied, decrypted or not
    env: (env?.envs ?? []).map((e: J) => ({ key: String(e.key), targets: [...(Array.isArray(e.target) ? e.target : [e.target])].filter(Boolean).map(String).sort(), type: String(e.type ?? '') }))
      .sort((a: EnvName, b: EnvName) => a.key.localeCompare(b.key) || a.targets.join().localeCompare(b.targets.join())),
    crons: project?.crons ?? null,
  };
}

// Where each env var's VALUE can be recovered from if Vercel lost it. A NEXT_PUBLIC_ value and the
// Supabase URL are public facts; Vercel's own system vars are set by Vercel; a value whose name (any case)
// is an app_secrets key is held in the database; a provider-issued key can be issued again by its provider.
const VERCEL_SYSTEM = /^(VERCEL|VERCEL_[A-Z_]+|CI|NODE_ENV)$/;
const PROVIDER: [RegExp, string][] = [
  // the Vercel-Supabase integration writes these from the Supabase project, and re-syncs them on reconnect
  [/^(NEXT_PUBLIC_)?SUPABASE_[A-Z_]+$|^POSTGRES_[A-Z_]+$/, 'Supabase project (the Vercel-Supabase integration re-syncs it)'],
  [/^STRIPE_/, 'Stripe dashboard'], [/^RESEND_/, 'Resend dashboard'], [/^TWILIO_/, 'Twilio console'],
  [/^SENTRY_/, 'Sentry'], [/^GOOGLE_|^GA_|^GTM_/, 'Google'],
];
export type Coverage = { key: string; source: string | null };
export function envCoverage(needed: string[], env: EnvName[], secretKeys: string[]) {
  const inVercel = new Set(env.map((e) => e.key));
  const secrets = new Set(secretKeys.map((k) => k.toLowerCase()));
  const sourceOf = (k: string): string | null => {
    if (k.startsWith('NEXT_PUBLIC_') && !/KEY|SECRET|TOKEN/.test(k)) return 'public value (the site and the repository)';
    if (VERCEL_SYSTEM.test(k)) return 'set by Vercel';
    if (secrets.has(k.toLowerCase())) return 'app_secrets.' + k.toLowerCase();
    for (const [re, p] of PROVIDER) if (re.test(k)) return p;
    return null;
  };
  const names = [...new Set([...needed, ...inVercel])].sort();
  return {
    missing_in_vercel: needed.filter((k) => !inVercel.has(k) && !VERCEL_SYSTEM.test(k)).sort(),
    no_recoverable_source: names.filter((k) => !sourceOf(k)),
    sources: names.map((k) => ({ key: k, source: sourceOf(k) })) as Coverage[],
  };
}
