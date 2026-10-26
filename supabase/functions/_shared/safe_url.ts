// SSRF guard — shared. RECOVERED, then STRENGTHENED (9 Sep 2026).
//
// PROVENANCE. unsafeUrl() was written for reg_fetch on 3 Sep 2026 (8ab537d), repaired on 4 Sep
// after `scripts/checks/reg_fetch_refuses_private_addresses.mjs` proved both of its regexes had
// lost their backslashes in a heredoc — the IPv4 match was /^(d+).(d+).(d+).(d+)$/, which matches
// the literal letter d, so 127.0.0.1 and 169.254.169.254 were never 'private_address' and the guard
// could not fire on any numeric address. reg_fetch was deleted on 8 Sep (182308b) and took the only
// copy of the guard with it, leaving resend_inbound fetching an attachment URL out of a request body
// with no scheme check, no host check, no timeout and no size cap. This file is the guard, recovered
// from 182308b^ and moved here so the next fetch site does not have to write its own.
//
// WHAT THE RECOVERED FUNCTION ACTUALLY CHECKED, and where it was short:
//   it had        http/https only; localhost/.local/.internal/0.0.0.0; a dotted-quad IPv4 match
//                 against 10/8, 127/8, 0/8, 172.16-31, 192.168/16, 169.254/16, 100.64/10; and an
//                 IPv6 test for ::1, ::, fc.., fd.., fe80...
//   it was short  on IPv4-MAPPED IPv6 (`::ffff:127.0.0.1`, `::ffff:7f00:1` — a loopback address
//                 written as v6, which the v6 branch's four string prefixes do not match), on
//                 IPv4 ranges that are not RFC1918 but are still not the public internet
//                 (multicast 224/4, reserved 240/4, benchmark 198.18/15, IETF protocol 192.0.0/24),
//                 and on the other conventional internal suffixes (.home.arpa, .lan, .corp,
//                 .intranet, .private).
//
// It matches on the PARSED hostname, not on the raw string, which is what makes the dotted-quad
// test sufficient for the integer, octal and hex spellings of an address: the WHATWG URL parser
// normalises `http://2130706433/`, `http://0x7f000001/` and `http://0177.0.0.1/` to the hostname
// `127.0.0.1` before this function ever sees them. safe_url.test.ts asserts that, rather than
// assuming it.
//
// STATED RESIDUAL, not hidden: a PUBLIC hostname that RESOLVES to a private address (DNS rebinding)
// is not caught. Deno does not expose the resolved IP to the caller, so there is nothing here to
// check it against. safeFetch() narrows it by judging EVERY redirect hop before requesting it — a public
// host cannot bounce the fetch into a private one — but a rebinding DNS record still gets through.

/** null when the URL is safe to fetch; otherwise a short reason code, suitable for a log. */
export function unsafeUrl(u: string): string | null {
  let p: URL;
  try { p = new URL(u); } catch { return 'invalid_url'; }
  if (p.protocol !== 'http:' && p.protocol !== 'https:') return 'scheme_not_http';

  const h = p.hostname.toLowerCase().replace(/^\[|\]$/g, '');
  if (!h) return 'invalid_url';

  if (h === 'localhost' || h === '0.0.0.0' ||
      /\.(localhost|local|internal|intranet|lan|corp|private|home\.arpa)$/.test(h)) return 'internal_host';

  // IPv4-mapped IPv6 written with a dotted tail: ::ffff:127.0.0.1 — a loopback address that the
  // v6 prefix tests below do not see. Unwrap it and judge it as the v4 address it is.
  const mapped = h.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
  const v4 = mapped ? mapped[1] : h;

  const m = v4.match(/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
  if (m) {
    const a = Number(m[1]), b = Number(m[2]), c = Number(m[3]);
    if (a === 10 || a === 127 || a === 0                     // loopback, this-network
        || (a === 172 && b >= 16 && b <= 31)                 // RFC1918
        || (a === 192 && b === 168)                          // RFC1918
        || (a === 169 && b === 254)                          // link-local, incl. 169.254.169.254
        || (a === 100 && b >= 64 && b <= 127)                // CGNAT
        || (a === 192 && b === 0 && c === 0)                 // IETF protocol assignments
        || (a === 198 && (b === 18 || b === 19))             // benchmarking
        || a >= 224) return 'private_address';               // multicast 224/4 + reserved 240/4
  }

  if (h.includes(':')) {
    // ::ffff:7f00:1 — the same mapped address in hex. Judge the low 32 bits as v4.
    const hexMapped = h.match(/^::ffff:([0-9a-f]{1,4}):([0-9a-f]{1,4})$/);
    if (hexMapped) {
      const hi = parseInt(hexMapped[1], 16), lo = parseInt(hexMapped[2], 16);
      const a = hi >> 8, b = hi & 0xff;
      if (a === 10 || a === 127 || a === 0 || (a === 172 && b >= 16 && b <= 31) ||
          (a === 192 && b === 168) || (a === 169 && b === 254) ||
          (a === 100 && b >= 64 && b <= 127) || a >= 224) return 'private_address';
      void lo;
    }
    if (h === '::1' || h === '::' ||
        h.startsWith('fc') || h.startsWith('fd') ||          // unique local
        h.startsWith('fe8') || h.startsWith('fe9') ||        // link-local fe80::/10
        h.startsWith('fea') || h.startsWith('feb')) return 'private_address';
  }

  return null;
}

export interface SafeFetchOptions {
  /** Abort the request after this many ms. Default 15s. */
  timeoutMs?: number;
  /** Refuse a response body larger than this. Default 25 MB, matching the storage buckets. */
  maxBytes?: number;
  headers?: HeadersInit;
  /** Test seam: the fetch to use. Default globalThis.fetch. */
  fetchImpl?: typeof fetch;
}

export type SafeFetchResult =
  | { ok: true; bytes: Uint8Array; contentType: string; finalUrl: string }
  | { ok: false; error: string; detail: string };

/**
 * fetch() for a URL this process did not choose. Refuses the target up front, re-checks the FINAL
 * url after redirects, aborts on a timeout, and stops reading at a byte ceiling instead of buffering
 * whatever the far end decides to send. Never throws.
 *
 * The size cap is enforced while STREAMING, not by measuring arrayBuffer() afterwards: a server that
 * answers a 25 MB cap with a 4 GB body would otherwise exhaust the isolate before the check ran.
 */
export async function safeFetch(url: string, opts: SafeFetchOptions = {}): Promise<SafeFetchResult> {
  const timeoutMs = opts.timeoutMs ?? 15_000;
  const maxBytes = opts.maxBytes ?? 25 * 1024 * 1024;

  const bad = unsafeUrl(url);
  if (bad) return { ok: false, error: 'url_refused', detail: bad };

  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), timeoutMs);
  try {
    // Redirects are followed BY HAND, each hop judged before it is requested (CWE-918 audit, 19 Oct 2026).
    // redirect:'follow' only let us judge the FINAL url, so public -> 169.254.169.254 -> public had already
    // sent the GET to the internal hop (a blind SSRF) by the time the final url was checked.
    let cur = url, r: Response;
    for (let hop = 0; ; hop++) {
      r = await (opts.fetchImpl ?? fetch)(cur, { redirect: 'manual', signal: ac.signal, headers: opts.headers });
      const loc = r.status >= 300 && r.status < 400 ? r.headers.get('location') : null;
      if (!loc) break;
      try { await r.body?.cancel(); } catch { /* nothing to cancel */ }
      if (hop >= 5) return { ok: false, error: 'too_many_redirects', detail: 'more than 5 redirects' };
      let next: string;
      try { next = new URL(loc, cur).toString(); } catch { return { ok: false, error: 'url_refused_after_redirect', detail: 'invalid_url' }; }
      const badHop = unsafeUrl(next);
      if (badHop) return { ok: false, error: 'url_refused_after_redirect', detail: badHop };
      cur = next;
    }
    if (!r.ok) { try { await r.body?.cancel(); } catch { /* nothing to cancel */ } return { ok: false, error: 'http_' + r.status, detail: 'the target answered ' + r.status }; }

    // A declared Content-Length over the cap is refused before a single byte is read.
    const declared = Number(r.headers.get('content-length') || 0);
    if (declared > maxBytes) { try { await r.body?.cancel(); } catch { /* nothing to cancel */ } return { ok: false, error: 'too_large', detail: declared + ' bytes declared, cap is ' + maxBytes }; }

    const chunks: Uint8Array[] = [];
    let total = 0;
    const reader = r.body?.getReader();
    if (reader) {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        total += value.length;
        if (total > maxBytes) { try { await reader.cancel(); } catch { /* nothing to cancel */ } return { ok: false, error: 'too_large', detail: 'the body passed the ' + maxBytes + ' byte cap while streaming' }; }
        chunks.push(value);
      }
    }
    const bytes = new Uint8Array(total);
    let o = 0; for (const c of chunks) { bytes.set(c, o); o += c.length; }
    return { ok: true, bytes, contentType: (r.headers.get('content-type') || '').toLowerCase(), finalUrl: cur };
  } catch (e) {
    const msg = String((e as Error)?.message || e);
    return { ok: false, error: ac.signal.aborted ? 'timeout' : 'fetch_failed', detail: msg.slice(0, 160) };
  } finally {
    clearTimeout(timer);
  }
}
