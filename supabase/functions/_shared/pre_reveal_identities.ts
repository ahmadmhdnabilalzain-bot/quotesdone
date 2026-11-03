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
// A NAME IS 2+ WORDS (review of #1836, measured on production leads): one-word names and suffix-stripped cores were
// "EMIRATES", "Signage", "CENTRAL", "FUTURE", "LIBERTY", "RELIANCE", and a reply saying "all seven emirates" or "your
// signage job" was refused on every rewrite once such a supplier was matched. A single-word party is still covered by
// its e-mail and its own web domain.
const twoWords = (v: string) => v.split(' ').length >= 2;
// A HOST MANY PARTIES SHARE NAMES NONE OF THEM: leads.website is wa.me for 3,282 leads, facebook.com for 25,
// sites.google.com for 6, drive.google.com for 4, emirates.net.ae for 7 (production, 3 Nov 2026).
const PLATFORM = /(?:^|\.)(?:wa\.me|whatsapp\.com|facebook\.com|fb\.com|fb\.me|instagram\.com|linkedin\.com|linktr\.ee|google\.com|goo\.gl|g\.page|youtube\.com|youtu\.be|tiktok\.com|twitter\.com|x\.com|emirates\.net\.ae|eim\.ae|wixsite\.com|business\.site|bit\.ly)$/i;
const hostOf = (w: unknown) => String(w ?? '').trim().replace(/^https?:\/\//i, '').replace(/^www\./i, '').split(/[/?#]/)[0].toLowerCase();

/** The words a reply must not carry for these counterpart rows: a person's or a company's name of 2+ words, the company
 *  name without its legal suffix when that is still 2+ words, each e-mail, and each web domain that is the party's own
 *  (not a platform, and not shared by two of these rows). */
export function identityTerms(rows: Record<string, unknown>[]): string[] {
  const out = new Set<string>();
  const hosts = rows.map((r) => hostOf(r.website));
  for (const r of rows) {
    for (const k of ['full_name', 'company_name', 'contact_name', 'signatory_name']) {
      const v = String(r[k] ?? '').trim().replace(/\s+/g, ' ');
      if (v.length < 3 || !twoWords(v)) continue;
      out.add(v);
      const core = v.replace(LEGAL, ' ').replace(/\s+/g, ' ').trim();
      if (core !== v && twoWords(core)) out.add(core);
    }
    const email = String(r.email ?? '').trim();
    if (email.includes('@')) out.add(email);
    const host = hostOf(r.website);
    if (host.includes('.') && !PLATFORM.test(host) && hosts.filter((h) => h === host).length === 1) out.add(host);
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
