// WHY A SIGN-UP EMAIL IS REFUSED BEFORE A CODE IS SENT (customer-portal audit 21 Sep 2026, item 26).
//
// Both portals accepted `x@example.invalid` and answered "code sent" — the address is unreachable by
// construction (RFC 2606 / RFC 6761 reserve these names so no mail can ever be delivered to them), so
// the customer waited on a code that could not arrive. The shape check both portals already had is
// kept; the reserved-domain check is added beside it, in one file both import, so the two doorways
// cannot drift. Tested in signupEmail.test.mjs.
//
// Returns null when the address may be used, otherwise the portalText key that says why.
const RESERVED_TLDS = new Set(['invalid', 'test', 'example', 'localhost', 'local', 'internal']);
const RESERVED_DOMAINS = new Set(['example.com', 'example.net', 'example.org']);

export function signupEmailProblem(value: unknown): null | 'signup_email_only' | 'signup_email_reserved' {
  const v = String(value ?? '').trim().toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v)) return 'signup_email_only';
  const domain = v.slice(v.lastIndexOf('@') + 1);
  const tld = domain.slice(domain.lastIndexOf('.') + 1);
  const reservedDomain = [...RESERVED_DOMAINS].some((d) => domain === d || domain.endsWith('.' + d));
  if (RESERVED_TLDS.has(tld) || reservedDomain) return 'signup_email_reserved';
  return null;
}
