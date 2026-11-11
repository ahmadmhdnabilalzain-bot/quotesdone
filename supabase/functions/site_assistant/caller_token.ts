// CAN THIS BEARER TOKEN BE A SIGNED-IN USER'S SESSION? (it_engineer, 11 Nov 2026, load test round 2, ruling 1622)
//
// site_assistant's identify() promised in its comment to check the role claim before calling auth.getUser, "which saves a
// network round trip on every anonymous message, which is most of them". It only checked the length (>= 40), and the
// publishable key the widget sends for an anonymous visitor is longer than that, so every anonymous turn made an
// /auth/v1/user round trip that could only fail. Measured: 132 /auth/v1/user calls in the 02:42-02:46 UTC load run for
// ~133 widget turns, on the worker whose CPU budget the run exhausted (HTTP 546).
//
// This is a FILTER, never a verification: a token that passes still goes to auth.getUser, which verifies the signature.
// Only tokens that cannot be a user session are dropped before the call: not three dot-separated parts (the
// sb_publishable_ / sb_secret_ keys), an unreadable payload, or a payload whose role is not 'authenticated' (the legacy
// anon and service_role keys). A forged token that claims 'authenticated' is still sent to getUser and refused there.
// prevented by: site_assistant/caller_token.test.ts

export function mayBeUserSession(token: string): boolean {
  const parts = String(token || '').split('.');
  if (parts.length !== 3 || !parts[1]) return false;
  try {
    const b64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const payload = JSON.parse(atob(b64 + '='.repeat((4 - (b64.length % 4)) % 4)));
    return payload?.role === 'authenticated';
  } catch (_e) { return false; }
}
