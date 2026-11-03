// THE OTHER PARTY'S IDENTITY BEFORE A REVEAL (it_engineer, 3 Nov 2026, release qualification). replyProblems
// (ai_reply.ts) takes a `forbidden` list, and no production reply passed one: a model that had read a counterpart's name
// anywhere (a chat turn, a pasted e-mail, a quotation) could write it, and only the e-mail, phone and licence patterns
// stood in the way. This lists, for ONE party, the counterpart names, e-mails and web domains on every job not yet
// revealed between them; the reply gates refuse a draft that carries one. A failed read gives [] (the pattern checks
// still run), never a thrown turn.
// prevented by: _shared/pre_reveal_identities.test.ts
type Res = { data: Record<string, unknown>[] | null; error: unknown };
// deno-lint-ignore no-explicit-any
type Db = { from(t: string): any };
export type Party = { leadId: number } | { customerId: string };

const LEGAL = /\b(?:l\.?\s?l\.?\s?c\.?|fz-?llc|fzc|fze|trading|contracting|establishment|est\.?|general|co\.?|company|group)\b/gi;
// ponytail: 150 ids per .in() list keeps the PostgREST URL short (uuids are 36 characters); a party with more jobs has
// 150 of them read. Paging is the upgrade if a party ever passes that.
const CAP = 150;
const NAMES_A_PARTY = (v: string, person: boolean) => v.split(/\s+/).length >= 2 || (!person && v.length >= 6);

/** The words a reply must not carry for these counterpart rows: a person's name when it is a full name (a bare "Ahmed"
 *  would refuse every reply to another Ahmed, review of #1836), a company name when it names something (2+ words or 6+
 *  letters), the company name without its legal suffix on the same rule, each e-mail, and each web domain. */
export function identityTerms(rows: Record<string, unknown>[]): string[] {
  const out = new Set<string>();
  for (const r of rows) {
    for (const k of ['full_name', 'company_name', 'contact_name', 'signatory_name']) {
      const v = String(r[k] ?? '').trim().replace(/\s+/g, ' ');
      if (v.length < 3 || !NAMES_A_PARTY(v, k !== 'company_name')) continue;
      out.add(v);
      const core = v.replace(LEGAL, ' ').replace(/\s+/g, ' ').trim();
      if (core !== v && (core.split(' ').length >= 2 || core.length >= 6)) out.add(core);
    }
    const email = String(r.email ?? '').trim();
    if (email.includes('@')) out.add(email);
    const host = String(r.website ?? '').trim().replace(/^https?:\/\//i, '').replace(/^www\./i, '').split(/[/?#]/)[0];
    if (host.includes('.')) out.add(host);
  }
  return [...out];
}

const col = (res: Res, k: string) => [...new Set((res.data ?? []).map((r) => r[k]).filter((v) => v != null).map(String))];

/** The counterpart identities `party` may not be told before a reveal. */
export async function preRevealIdentities(db: Db, party: Party): Promise<string[]> {
  try {
    if ('leadId' in party) {
      const id = party.leadId;
      const [q, m, rev] = await Promise.all([
        db.from('quotes').select('inquiry_id').eq('supplier_id', id).limit(CAP),
        db.from('inquiry_matches').select('inquiry_id').eq('supplier_id', id).limit(CAP),
        db.from('transactions').select('customer_id').eq('supplier_id', id).not('revealed_at', 'is', null).limit(CAP),
      ]) as Res[];
      const inq = [...new Set([...col(q, 'inquiry_id'), ...col(m, 'inquiry_id')])].slice(0, CAP);
      if (!inq.length) return [];
      const owners = col(await db.from('inquiries').select('customer_id').in('id', inq) as Res, 'customer_id');
      const revealed = new Set(col(rev, 'customer_id'));
      const hidden = owners.filter((c) => !revealed.has(c));
      if (!hidden.length) return [];
      return identityTerms((await db.from('customers').select('full_name,email').in('id', hidden) as Res).data ?? []);
    }
    const id = party.customerId;
    const [own, rev] = await Promise.all([
      db.from('inquiries').select('id').eq('customer_id', id).limit(CAP),
      db.from('transactions').select('supplier_id').eq('customer_id', id).not('revealed_at', 'is', null).limit(CAP),
    ]) as Res[];
    const inq = col(own, 'id');
    if (!inq.length) return [];
    const [q, m] = await Promise.all([
      db.from('quotes').select('supplier_id').in('inquiry_id', inq).limit(CAP),
      db.from('inquiry_matches').select('supplier_id').in('inquiry_id', inq).limit(CAP),
    ]) as Res[];
    const revealed = new Set(col(rev, 'supplier_id'));
    const hidden = [...new Set([...col(q, 'supplier_id'), ...col(m, 'supplier_id')])].filter((s) => !revealed.has(s)).slice(0, CAP);
    if (!hidden.length) return [];
    return identityTerms((await db.from('leads').select('company_name,contact_name,signatory_name,email,website').in('id', hidden) as Res).data ?? []);
  } catch (_e) {
    return [];
  }
}
