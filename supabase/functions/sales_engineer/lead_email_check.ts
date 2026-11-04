// THE LEAD EMAIL CHECK (2 Nov 2026, sales_engineer, ledger 1449). No paid verifier: syntax, typo domains, the local-part
// rules the campaign already holds, and DNS. A lead is invited only with a stored 'verified' verdict for its current
// address (fn_supplier_invite_eligible; public.lead_email_check holds the verdict).
//
// MEASURED, 2 Nov: 7 of 52 real sends bounced and all 7 were on domains with a real MX, so this stops dead domains and
// typos and CANNOT see a mailbox missing on a live domain. The order of invitations answers that part:
// fn_supplier_invite_candidates sends proven mailboxes first (1 bounce of 22 'verified'), then unproven role addresses
// (0 of 2), then unproven named ones (5 of 16), then free mail.
import { FREE_MAIL, mxRecord, type MxRecord } from '../_shared/mail_domain.ts';

export type Mailbox = 'named' | 'role' | 'free';
export type Verdict = { verdict: 'verified' | 'rejected' | 'retry'; reason: string; mailbox: Mailbox | null };

// fn_supplier_invite_eligible's refused local parts and fn_supplier_invite_candidates' role list, as they stand.
const REFUSED_LOCAL = /^(careers?|jobs?|hr|recruit(ment|ing)?|cv|webmaster|hostmaster|mailer-daemon|privacy|legal|newsletters?|unsubscribe|donotreply)$/;
const ROLE_LOCAL = /^(info|sales|admin|contact|enquiry|enquiries|inquiry|office|mail|support|hello|marketing|general|accounts|reception)$/;
const PROVIDERS = ['gmail', 'yahoo', 'hotmail', 'outlook'];
// Real TLDs starting "com" (IANA); anything else there is a slip of "com" (.comm, .comna).
const COM_TLDS = new Set(['com', 'comcast', 'commbank', 'community', 'company', 'compare', 'computer', 'comsec']);
const TLD_SLIPS = new Set(['coin', 'con', 'cmo', 'ocm', 'cpm', 'vom', 'xom', 'cim', 'coom', 'cm0', 'couk']);

/** Edit distance is at most 1, an adjacent swap counting as one edit. */
function nearlySame(a: string, b: string): boolean {
  if (a === b) return true;
  if (Math.abs(a.length - b.length) > 1) return false;
  let i = 0;
  while (i < Math.min(a.length, b.length) && a[i] === b[i]) i++;
  if (a.length === b.length) {
    return a.slice(i + 1) === b.slice(i + 1) || (a[i] === b[i + 1] && a[i + 1] === b[i] && a.slice(i + 2) === b.slice(i + 2));
  }
  return a.length > b.length ? a.slice(i + 1) === b.slice(i) : a.slice(i) === b.slice(i + 1);
}

/** Why a domain is a slip of the keyboard (yahoo.coin, gmial.com, x.comm, yahoo.comname.ae), or null. */
export function typoDomain(domain: string): string | null {
  const labels = domain.split('.');
  const tld = labels[labels.length - 1];
  if (TLD_SLIPS.has(tld) || (tld.startsWith('com') && !COM_TLDS.has(tld))) return `.${tld} is a slip of a real ending`;
  const first = labels[0];
  if (PROVIDERS.includes(first) && labels[1]?.startsWith('com') && labels[1] !== 'com') return `${first}.com ran into the next word`;
  if (!FREE_MAIL.test(domain) && first !== 'email') {
    const near = PROVIDERS.find((p) => nearlySame(first, p));
    if (near) return `${first} is a slip of ${near}`;
  }
  return null;
}

/** Everything decided without the network. Null means only DNS is left to ask. */
export function judgeWithoutDns(email: string, emailVerified: string | null): Verdict | null {
  const e = email.toLowerCase().trim();
  const m = e.match(/^([a-z0-9._%+-]+)@([a-z0-9.-]+\.[a-z]{2,})$/);
  if (!m) return { verdict: 'rejected', reason: 'not a valid address shape', mailbox: null };
  const [, local, domain] = m;
  if (/\.(png|jpe?g|gif|webp|svg)$/.test(domain) || /example\.|sentry|wixpress/.test(domain)) {
    return { verdict: 'rejected', reason: 'not a mail domain', mailbox: null };
  }
  const typo = typoDomain(domain);
  if (typo) return { verdict: 'rejected', reason: 'typo domain: ' + typo, mailbox: null };
  if (REFUSED_LOCAL.test(local)) return { verdict: 'rejected', reason: 'a mailbox whose reader is not the business', mailbox: null };
  if (emailVerified === 'not_found') return { verdict: 'rejected', reason: 'an earlier verifier found no such mailbox', mailbox: null };
  return null;
}

export function mailboxOf(email: string): Mailbox {
  const [local, domain] = email.toLowerCase().trim().split('@');
  return FREE_MAIL.test(domain) ? 'free' : ROLE_LOCAL.test(local) ? 'role' : 'named';
}

// AN MX THAT TAKES NO MAIL (2 Nov 2026). MEASURED: unibetonrm.com's only MX is ghs.google.com, Google's web-hosting front
// end, and the invitation died "5.4.316 connection refused". An MX naming only such a host, localhost or a bare IP is no MX.
// ponytail: a fixed list; resolve each MX host's A record if another kind of dead MX shows up in a bounce.
const NOT_A_MAIL_HOST = /^(ghs\.google\.com|ghs\.googlehosted\.com|localhost)$|^\d{1,3}(\.\d{1,3}){3}$/;

/** A cold invitation needs a measured MX (fn_supplier_invite_eligible, 22 Sep); a failed lookup decides nothing. */
export function judgeDns(email: string, kind: string, hosts: string[] = []): Verdict {
  const mailbox = mailboxOf(email);
  if (kind === 'mx' && hosts.length && hosts.every((h) => NOT_A_MAIL_HOST.test(h))) {
    return { verdict: 'rejected', reason: 'MX points only at a host that takes no mail: ' + hosts.join(', '), mailbox };
  }
  if (kind === 'mx') return { verdict: 'verified', reason: 'syntax, typo and role rules passed; domain has MX', mailbox };
  if (kind === 'error') return { verdict: 'retry', reason: 'the DNS lookup failed', mailbox };
  return { verdict: 'rejected', reason: 'domain has no MX: ' + kind, mailbox };
}

type Lead = { lead_id: number; email: string; email_verified: string | null; mx_kind: string | null; mx_hosts?: string[] | null };
type Rpc = (fn: string, args: Record<string, unknown>) => Promise<{ data: unknown; error: { message: string } | null }>;

export const BATCH_LEADS = 200;
export const DNS_PER_RUN = 40;      // about 2 s of network at 8 at once; the 546 CPU cap is what this stays far from
const DNS_AT_ONCE = 8;

/** One batch: read due leads, ask DNS for at most DNS_PER_RUN unknown domains, store what was decided. */
export async function leadEmailCheckBatch(rpc: Rpc, lookup: (d: string) => Promise<MxRecord> = (d) => mxRecord(d)) {
  const due = await rpc('fn_sales_engineer_email_check_batch', { p_limit: BATCH_LEADS });
  if (due.error) throw new Error(due.error.message);
  const leads = (due.data ?? []) as Lead[];
  const decided = new Map<number, Verdict>();
  const ask = new Map<string, Lead[]>();
  for (const l of leads) {
    const early = judgeWithoutDns(l.email, l.email_verified);
    if (early) decided.set(l.lead_id, early);
    else if (l.mx_kind) decided.set(l.lead_id, judgeDns(l.email, l.mx_kind, l.mx_hosts ?? []));
    else {
      const d = l.email.toLowerCase().trim().split('@')[1];
      ask.set(d, [...(ask.get(d) ?? []), l]);
    }
  }
  const domains = [...ask.keys()].slice(0, DNS_PER_RUN);
  const found: Array<{ domain: string; kind: string; hosts: string[] }> = [];
  for (let i = 0; i < domains.length; i += DNS_AT_ONCE) {
    await Promise.all(domains.slice(i, i + DNS_AT_ONCE).map(async (domain) => {
      const r = await lookup(domain);
      found.push({ domain, kind: r.kind, hosts: r.hosts });
      for (const l of ask.get(domain)!) decided.set(l.lead_id, judgeDns(l.email, r.kind, r.hosts));
    }));
  }
  // A lead whose domain waits for the next run gets no verdict, so it stays due and stays out of the invitations.
  const checks = leads.filter((l) => decided.has(l.lead_id)).map((l) => ({ lead_id: l.lead_id, email: l.email, mx_kind: l.mx_kind, ...decided.get(l.lead_id)! }));
  for (const c of checks) {
    const f = found.find((d) => d.domain === c.email.toLowerCase().trim().split('@')[1]);
    if (f) c.mx_kind = f.kind;
  }
  const saved = await rpc('fn_sales_engineer_records_email_checks', { p_checks: checks, p_domains: found });
  if (saved.error) throw new Error(saved.error.message);
  const tally = (v: string) => checks.filter((c) => c.verdict === v).length;
  return { leads: leads.length, domains_asked: found.length, verified: tally('verified'), rejected: tally('rejected'), retry: tally('retry') };
}
