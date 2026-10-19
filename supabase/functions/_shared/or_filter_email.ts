// A value interpolated into a PostgREST or() filter must not carry filter syntax (, . ( ) " :),
// or a sender could add a condition of their own (e.g. "x,claimed_by.not.is.null") and select a
// lead that is not theirs. Seat: it_engineer, CWE-943 audit 19 Oct 2026. Returns '' when unsafe.
export const orSafeEmail = (s: string) => (/^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$/.test(s) && !/[,()":]/.test(s) ? s : '');
export const orSafeDomain = (s: string) => (/^[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$/.test(s) ? s : '');
