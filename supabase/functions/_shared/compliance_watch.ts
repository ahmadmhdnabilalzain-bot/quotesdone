// THE COMPLIANCE SOURCES ARE FETCHED AGAIN (it_engineer, OPS_LOOPS, 16 Nov 2026; hole H6 of the COO hunt).
//
// MEASURED (production, read-only SELECT, 16 Nov 2026): all 17 active public.compliance_sources (Dubai Municipality, DEWA,
// RTA, Trakhees, SIRA, DHA, TDRA, ...) were last checked on 10 Aug 2026. The watcher that checked them was deleted with the
// pre-7-Sep estate; since then fn_ceo_register_review re-issues the CEO a directive per source every month that no code can
// meet (nothing writes last_checked_at), 18 of them already escalated and re-issued twice.
//
// WHAT THIS DOES (one step of the it_engineer's later duties, due once a day by it_duty_schedule 'compliance_watch'):
//   fn_compliance_sources_due names up to N active sources not checked in 30 days, oldest first, and the hosts every
//   registered source lives on (THE ALLOWLIST: only those hosts, never a host a page redirects to). Each is fetched through
//   safeFetch (_shared/safe_url.ts: the SSRF guard, every redirect hop judged, a timeout and a byte ceiling), its readable
//   text taken (scripts and styles removed, tags dropped, whitespace collapsed; a PDF is signed on its bytes), and the result
//   recorded by fn_compliance_sources_record. Postgres decides the rest: the same signature stamps the source checked; a new
//   one is checked AND asked of the CEO seat's model, which states what changed and which seat it affects
//   (ceo.compliance_change), and the change is routed there. A fetch that fails is not a check: it is recorded, and a
//   source failing three days running is an it_engineer finding (fn_compliance_watch_settle).
// No model is called here and no person is written to.
// prevented by: _shared/compliance_watch.test.ts
import { safeFetch } from './safe_url.ts';

export const COMPLIANCE_PER_RUN = 6;
export const COMPLIANCE_MAX_BYTES = 3 * 1024 * 1024;
export const COMPLIANCE_EXCERPT = 6000;

type Rpc = (fn: string, args?: Record<string, unknown>) => Promise<unknown>;
export interface DueSource { id: number; authority: string; topic: string; url: string }
export interface Due { sources: DueSource[]; allowed_hosts: string[] }
export interface Reading { id: number; ok: boolean; error?: string; signature?: string; excerpt?: string; final_url?: string; bytes?: number; content_type?: string | null }

/** A host is allowed when it IS a registered source's host, or that host without its leading "www.". */
export function hostAllowed(url: string, allowed: string[]): boolean {
  let h: string;
  try { h = new URL(url).hostname.toLowerCase(); } catch { return false; }
  const set = new Set(allowed.map((a) => a.toLowerCase()).flatMap((a) => [a, a.replace(/^www\./, ''), 'www.' + a.replace(/^www\./, '')]));
  return set.has(h);
}

/** The readable text of a page: scripts, styles and tags removed, entities for spaces decoded, whitespace collapsed. */
export function readableText(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<noscript[\s\S]*?<\/noscript>/gi, ' ')
    .replace(/<!--[\s\S]*?-->/g, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;|&#160;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/\s+/g, ' ')
    .trim();
}

async function sha256Hex(data: Uint8Array): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', new Uint8Array(data));
  return Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** Fetch one source and read it. Never throws: a failure is a Reading with ok false and its reason. */
export async function readSource(s: DueSource, allowed: string[], fetchImpl?: typeof fetch): Promise<Reading> {
  if (!hostAllowed(s.url, allowed)) return { id: s.id, ok: false, error: 'host_not_allowlisted' };
  // every request, redirect hops included, goes only to an allowlisted host: safeFetch requests each hop through this
  const base = fetchImpl ?? fetch;
  const guarded = ((input: string | URL | Request, init?: RequestInit) => {
    const u = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
    if (!hostAllowed(u, allowed)) return Promise.reject(new Error('host_not_allowlisted: ' + u.slice(0, 120)));
    return base(input, init);
  }) as typeof fetch;
  const r = await safeFetch(s.url, { timeoutMs: 15_000, maxBytes: COMPLIANCE_MAX_BYTES, fetchImpl: guarded,
    headers: { 'user-agent': 'QuotesDone compliance check (+https://quotesdone.com)', accept: 'text/html,application/pdf;q=0.9,*/*;q=0.5' } });
  if (!r.ok) return { id: s.id, ok: false, error: (r.error + ': ' + r.detail).slice(0, 300) };
  if (!hostAllowed(r.finalUrl, allowed)) return { id: s.id, ok: false, error: 'redirected_off_allowlist: ' + (() => { try { return new URL(r.finalUrl).hostname; } catch { return '?'; } })() };
  const ct = (r.contentType || '').toLowerCase();
  const isText = ct.includes('html') || ct.includes('text') || ct.includes('xml') || ct === '';
  const text = isText ? readableText(new TextDecoder('utf-8', { fatal: false }).decode(r.bytes)) : '';
  if (isText && text.length < 40) return { id: s.id, ok: false, error: 'empty_page: ' + text.length + ' readable characters' };
  const signature = 'v2:' + await sha256Hex(isText ? new TextEncoder().encode(text) : r.bytes);
  return { id: s.id, ok: true, signature, excerpt: isText ? text.slice(0, COMPLIANCE_EXCERPT) : '(a ' + ct + ' document of ' + r.bytes.length + ' bytes)',
    final_url: r.finalUrl, bytes: r.bytes.length, content_type: ct || null };
}

/** The daily step: the due sources, read one at a time, each recorded; then the settle. */
export async function runComplianceWatch(rpc: Rpc, opts: { fetchImpl?: typeof fetch; perRun?: number } = {}): Promise<Record<string, unknown>> {
  const due = ((await rpc('fn_compliance_sources_due', { p_limit: opts.perRun ?? COMPLIANCE_PER_RUN })) ?? { sources: [], allowed_hosts: [] }) as Due;
  const counts = { fetched: 0, failed: 0, changed_or_new: 0, unchanged: 0 };
  for (const s of due.sources ?? []) {
    const reading = await readSource(s, due.allowed_hosts ?? [], opts.fetchImpl);
    const out = (await rpc('fn_compliance_sources_record', { p: reading })) as { outcome?: string } | null;
    if (!reading.ok) counts.failed++;
    else { counts.fetched++; if (out?.outcome === 'unchanged') counts.unchanged++; else counts.changed_or_new++; }
  }
  const settled = await rpc('fn_compliance_watch_settle', { p_counts: counts });
  return { due: (due.sources ?? []).length, ...counts, settled };
}
