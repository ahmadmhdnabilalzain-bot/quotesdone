// Why a Dropbox call failed, as one of six classes (it_engineer, 15 Sep 2026).
//
// The founder, 14 Sep 2026 (founder_instruction 208): backups may fail only for a provider-side
// cause, never an internal one. So the daily health probe names the class, and
// fn_it_dropbox_health_record decides how loud it is:
//   auth             the stored authorisation was refused (401, a refresh that failed, a missing scope)
//   quota            the account is full (insufficient_space / over_quota)
//   rate_limit       Dropbox asked us to slow down (429, too_many_requests / too_many_write_operations)
//   provider_outage  Dropbox answered 5xx
//   network          no answer at all (fetch failed, reset, timeout)
//   internal         everything else: ours to fix
// The error strings are the ones dropbox.ts, upload.ts and index.ts throw: '<endpoint> <status> <body>',
// '<endpoint> network <reason> after N tries', 'no_dropbox_auth', or a thrown fetch/abort error.
export type FailureClass = 'auth' | 'quota' | 'rate_limit' | 'provider_outage' | 'network' | 'internal';

export function classifyDropboxFailure(error: string | null | undefined): FailureClass {
  const e = String(error ?? '');
  // the status only counts where the thrower put it: right after the endpoint name
  const status = Number(e.match(/^[\w/]+ (\d{3})\b(?! of )/)?.[1] ?? 0);
  if (/insufficient_space|over_quota|insufficient_quota/i.test(e)) return 'quota';
  if (status === 401 || /no_dropbox_auth|invalid_access_token|expired_access_token|invalid_grant|missing_scope/i.test(e)) return 'auth';
  if (status === 429 || /too_many_requests|too_many_write_operations/i.test(e)) return 'rate_limit';
  if (status >= 500 && status <= 599) return 'provider_outage';
  if (/^[\w/]+ network |fetch failed|ECONNRESET|connection (reset|refused|closed)|error sending request|dns error|TimeoutError|timed out|signal has been aborted/i.test(e)) return 'network';
  return 'internal';
}
