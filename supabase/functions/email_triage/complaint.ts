// A COMPLAINT BY E-MAIL ENTERS THE REGISTER (customer_support, 16 Nov 2026; COO hole H2). Until now email_triage read a mail as
// `complaint` (its triage model's category) and only replied. Two model readings say it now, both already made for every
// answered mail, never a word list: the needs-a-person reading's `complaint` choice (same call, reasoned_decisions.ts) and the
// triage model's category. Either opens the ticket once for this mail (source key email:<inbound id>), linked to the sender by
// the address the mail came from and, for a supplier, its lead.
// prevented by: email_triage/complaint.test.ts
import { registerComplaint, type ComplaintReport, type Ticket } from '../_shared/complaint_register.ts';
import type { ThinkDeps } from '../_shared/think.ts';

type MailLike = { id: number; from_email: string | null; subject: string | null; body: string | null; lead_id?: number | null };

/** The sender's bare address, lower case ('' when there is none). */
export const bareAddress = (from: unknown): string => {
  const s = String(from ?? '').toLowerCase();
  return (s.match(/<([^<>\s"]+@[^<>\s"]+)>/) || s.match(/([^<>\s"]+@[^<>\s"]+)/) || [])[1] || '';
};

export function mailComplaint(m: MailLike, audience: 'customer' | 'supplier', lang: 'en' | 'ar') {
  const email = bareAddress(m.from_email);
  const text = [String(m.subject ?? '').trim(), String(m.body ?? '').trim()].filter(Boolean).join('\n\n');
  const report: Omit<ComplaintReport, 'message' | 'reading'> & { message: string } = {
    channel: 'email', sourceKey: 'email:' + m.id, email: email || null, message: text,
    ...(audience === 'supplier' && m.lead_id ? { partyKind: 'supplier' as const, partyId: String(m.lead_id) } : {}),
    lang, fixture: /@example\.invalid$/i.test(email),
  };
  return {
    report,
    /** The ticket: the reading's own, else the triage model's `complaint` category opens it. null when neither says complaint. */
    async ticket(deps: Pick<ThinkDeps, 'rpc'>, person: { complaint?: boolean; ticket?: Ticket | null }, triage: { category: string; summary: string } | null): Promise<Ticket | null> {
      if (person.ticket) return person.ticket;
      if (!(person.complaint === true || triage?.category === 'complaint')) return null;
      const r = await registerComplaint((fn, args) => deps.rpc(fn, args), { ...report,
        reading: triage?.category === 'complaint' ? 'the triage model read it as a complaint: ' + String(triage.summary ?? '').slice(0, 400) : 'read as a complaint (email_triage.needs_a_person)' });
      return r.ticket ?? null;
    },
  };
}
