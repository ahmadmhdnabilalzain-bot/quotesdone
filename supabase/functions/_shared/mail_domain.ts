// What DNS says about a mail domain, over DNS-over-HTTPS, and which domains are public mailbox providers. Moved out of
// marketing/lead_sourcing.ts (2 Nov 2026, sales_engineer, ledger 1449) so the sales engineer's lead check asks the same
// question without loading the crawler's npm dependencies. Kinds are those of public.email_domain_mx.
import { timedFetch } from './timed_fetch.ts';

export const FREE_MAIL = /^(gmail|googlemail|yahoo|ymail|hotmail|outlook|live|msn|icloud|me|aol|proton|protonmail|gmx|mail|yandex|zoho)\.[a-z.]+$/i;

type Dns = { Status: number; Answer?: Array<{ type?: number; data?: string }> };
export type MxRecord = { kind: 'mx' | 'a_implicit' | 'nxdomain' | 'no_records' | 'error'; hosts: string[] };

/** MX (or implicit A, RFC 5321 5.1). A timeout or SERVFAIL is 'error': a missing measurement, never a verdict. */
export async function mxRecord(domain: string, fetcher: typeof fetch = (u, i) => timedFetch(String(u), i, 8000)): Promise<MxRecord> {
  const q = async (type: string) => {
    const r = await fetcher(`https://cloudflare-dns.com/dns-query?name=${encodeURIComponent(domain)}&type=${type}`,
      { headers: { accept: 'application/dns-json' } });
    return r.ok ? await r.json() as Dns : null;
  };
  try {
    const mx = await q('MX');
    if (!mx) return { kind: 'error', hosts: [] };
    if (mx.Status === 3) return { kind: 'nxdomain', hosts: [] };
    if (mx.Status !== 0) return { kind: 'error', hosts: [] };
    // Only MX answers count (a CNAME can precede them). "0 ." is RFC 7505's null MX: this domain takes no mail.
    const rows = (mx.Answer ?? []).filter((a) => a.type === undefined || a.type === 15).map((a) => String(a.data ?? '').trim().split(/\s+/));
    if (rows.length === 1 && rows[0][1] === '.') return { kind: 'no_records', hosts: [] };
    if (rows.length) {
      return { kind: 'mx', hosts: rows.sort((a, b) => Number(a[0]) - Number(b[0])).slice(0, 4).map((r) => String(r[1] ?? '').replace(/\.$/, '').toLowerCase()) };
    }
    const a = await q('A');
    if (!a) return { kind: 'error', hosts: [] };
    return a.Answer?.length ? { kind: 'a_implicit', hosts: [] } : { kind: 'no_records', hosts: [] };
  } catch { return { kind: 'error', hosts: [] }; }
}

export async function mxKind(domain: string): Promise<string> {
  return (await mxRecord(domain)).kind;
}
