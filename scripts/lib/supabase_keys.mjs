// WHICH PROJECT API KEY A SCRIPT USES (it_engineer, 27 Oct 2026).
//
// The legacy anon and service_role keys are JWTs signed with the project's HS256 secret, and that secret
// leaked (docs/reports/security/SECURITY_HARDENING_27_OCT.md, item 3). The way out is to stop sending them,
// watch the gateway logs show zero HS256 traffic for 24 to 48 h, then disable the legacy keys and revoke the
// HS256 signing key. Measured 27 Oct 2026: about 15,000 of the ~17,700 HS256 requests a day came from the
// cloud sessions' scripts, each of which read `GET /v1/projects/{ref}/api-keys?reveal=true` and took the
// entry NAMED 'service_role' or 'anon'.
//
// Every script now asks this one function instead. It takes the new key of the same power:
//   'secret'      -> the `secret` key named 'default' (any other secret key if there is no 'default')
//   'publishable' -> the `publishable` key named 'default' (likewise). The 'quotesdone2' publishable key
//                    ("gpt test", 29 Jul 2026) is never preferred: it is due to be revoked after the move.
// and falls back to the legacy key ('service_role' / 'anon') ONLY when the project lists no new key. That
// fallback is temporary: remove it in the PR that follows 24 to 48 h of zero HS256 traffic.
//
// Proved against production on 27 Oct 2026 (values never printed): the secret key reads app_secrets and
// storage as service_role did; the publishable key is refused on app_secrets, passes auth health, and both
// reach a verify_jwt=true function (customer_api answered its own 401, not the gateway's).
//
// A masked key (listed without ?reveal=true, e.g. 'sb_secret_abcd••••') is never returned: it would fail
// every request with a 401 that names nothing. Checked by scripts/lib/supabase_keys.test.mjs.
//
// NOR IS THE LEGACY KEY WHEN THE NEW ONE IS LISTED BUT MASKED (independent review of #1655, 27 Oct 2026). Without
// ?reveal=true the Management API lists the legacy service_role JWT in full and the new secret key masked
// (measured by digest on production: the un-revealed 'secret' pick was the legacy service_role key). The fallback
// would then hand a caller that forgot ?reveal=true the leaked HS256 key, silently, and the gateway watch would be
// the first to notice. A new key of the asked power being listed at all means the fallback does not apply: the
// answer is '' and the caller fails on its own missing key, by name. A key marked disabled is never returned.

const NEW_TYPE = { secret: 'secret', publishable: 'publishable' };
const LEGACY_NAME = { secret: 'service_role', publishable: 'anon' };
const USABLE = /^(sb_(secret|publishable)_[A-Za-z0-9_-]+|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)$/;

/**
 * The api_key a script should use, from a `GET /v1/projects/{ref}/api-keys?reveal=true` answer.
 * @param {unknown} keys the parsed answer (anything that is not an array yields '')
 * @param {'secret'|'publishable'} kind
 * @returns {string} the key, or '' when the answer holds none of that power
 */
export function pickApiKey(keys, kind) {
  if (!(kind in NEW_TYPE)) throw new Error(`pickApiKey: kind must be 'secret' or 'publishable', not ${String(kind)}`);
  const listed = Array.isArray(keys) ? keys.filter((k) => k && typeof k.api_key === 'string' && k.disabled !== true) : [];
  const list = listed.filter((k) => USABLE.test(k.api_key));
  const fresh = list.filter((k) => k.type === NEW_TYPE[kind]);
  const newKeyListed = listed.some((k) => k.type === NEW_TYPE[kind]);   // masked or not
  const chosen = fresh.find((k) => k.name === 'default') ?? fresh[0]
    ?? (newKeyListed ? undefined : list.find((k) => k.name === LEGACY_NAME[kind]));   // TEMPORARY legacy fallback; see the header
  return chosen?.api_key ?? '';
}

/** Both keys a script normally needs, by their old names so a call site changes in one line. */
export function projectKeys(keys) {
  return { ANON: pickApiKey(keys, 'publishable'), SERVICE: pickApiKey(keys, 'secret') };
}
