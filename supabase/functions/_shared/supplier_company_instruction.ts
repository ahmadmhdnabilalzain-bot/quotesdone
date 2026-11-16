// supplier_company_instruction.ts - THE COMPANY'S OWN ASKS, BY E-MAIL OR WHATSAPP (customer_support + sales_engineer, 16 Nov 2026;
// agent SUPPLIER_W2; SUPPLIER holes 5, 6, 10, 12). The model reading is supplier_instruction.ts's (one call per message, the kinds
// job_question, close_account, close_confirm, close_cancel, customer_silent, paid_leads); this file applies what it read, each
// through one routine of a_supplier_company_has_members_asks_on_any_channel_and_can_leave.sql, and returns plain facts for the
// channel's reply model. Code checks only references (a request must be one of HIS) and who may act.
//   * job_question: filed as one rfq_clarification row (job_question.ts), the same row the portal files; the sales engineer reads it.
//   * close_account: PROPOSED with what the law keeps; closed only on his "yes" (close_confirm), by the owner; written confirmation.
//   * customer_silent: one nudge to a customer who revealed him, kept as evidence for the refund ladder.
//   * paid_leads: recorded as a demand signal the CEO reads; he is told plainly that nobody can pay to rank or for exclusivity.
//   * refer_company (W3_PEOPLE, 16 Nov 2026; SUPPLIER #11): his company's own referral link (fn_supplier_referral_link, approved
//     companies only). HE sends it to whom he knows; we write to nobody, so it is consented mail, never cold mail from us.
//   * owner_left (W3_PEOPLE, 16 Nov 2026; wave-3 item 4): a member whose owner has left asks to take the company over. It opens the
//     case the sales engineer decides (fn_supplier_ownership_claim_open; sales_engineer/lib/ownership_claim.ts); the owner is told
//     at once and keeps three days. The owner himself opens nothing.
// prevented by: _shared/supplier_company_instruction.test.ts
import type { Channel, Facts, Outcome, Reading } from './supplier_instruction.ts';
import { fileJobQuestion } from './job_question.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;
export const COMPANY_KINDS = new Set(['job_question', 'close_account', 'close_confirm', 'close_cancel', 'customer_silent', 'paid_leads',
  'refer_company', 'owner_left']);
const plain = (s: string) => s.replace(/\s+/g, ' ').trim();
const ref = (rfq: unknown, id: string) => (rfq != null && String(rfq) !== '' ? 'RFQ-' + String(rfq).replace(/^RFQ-/i, '') : 'request ' + id.slice(0, 8));

/** The company's facts the reader needs: revealed requests, a waiting closure, live quotations, the owner's address. */
export async function companyFacts(admin: Admin, supplierId: number): Promise<Pick<Facts, 'revealed' | 'closure' | 'live_quotes' | 'owner_email'>> {
  // a failed read leaves these facts empty; it never costs him the instruction he wrote
  try { return await readCompanyFacts(admin, supplierId); } catch (_e) { return { revealed: [], closure: null, live_quotes: 0, owner_email: null }; }
}
async function readCompanyFacts(admin: Admin, supplierId: number): Promise<Pick<Facts, 'revealed' | 'closure' | 'live_quotes' | 'owner_email'>> {
  const soft = <T>(p: PromiseLike<{ data: T | null }>, empty: T) => Promise.resolve(p).then((r) => r.data ?? empty, () => empty);
  const [tx, cl, live, lead] = await Promise.all([
    soft(admin.from('transactions').select('inquiry_id').eq('supplier_id', supplierId).not('revealed_at', 'is', null).order('revealed_at', { ascending: false }).limit(10), [] as { inquiry_id: string }[]),
    soft(admin.from('supplier_account_closure').select('id,quotes').eq('lead_id', supplierId).eq('state', 'proposed').order('proposed_at', { ascending: false }).limit(1).maybeSingle(), null as { id: number; quotes: 'withdraw' | 'keep' } | null),
    soft(admin.rpc('fn_supplier_live_quotes', { p_supplier: supplierId }), [] as unknown[]),
    soft(admin.from('leads').select('claimed_by').eq('id', supplierId).maybeSingle(), null as { claimed_by: string | null } | null),
  ]);
  const ids = [...new Set((tx ?? []).map((t) => String(t.inquiry_id)).filter(Boolean))];
  const inq = ids.length ? await soft(admin.from('inquiries').select('id,rfq_no').in('id', ids), [] as { id: string; rfq_no: unknown }[]) : [];
  return {
    revealed: (inq ?? []).map((i) => ({ inquiry_id: String(i.id), ref: ref(i.rfq_no, String(i.id)) })),
    closure: cl ? { id: Number(cl.id), quotes: cl.quotes === 'keep' ? 'keep' : 'withdraw' } : null,
    live_quotes: Array.isArray(live) ? live.length : 0,
    owner_email: lead?.claimed_by ?? null,
  };
}

/** The address that acts: the member himself, else the company's owner (an owner's own mailbox or his confirmed number). */
const actorOf = (f: Facts) => String(f.sender?.email || f.owner_email || '').toLowerCase();

export async function applyCompanyInstruction(admin: Admin, f: Facts, r: Reading, channel: Channel): Promise<Outcome> {
  const sid = f.supplier_id;
  const rpc = async (fn: string, args: Record<string, unknown>) => {
    const { data, error } = await admin.rpc(fn, args);
    return error ? { ok: false, code: 'unavailable' } as Record<string, unknown> : (data ?? {}) as Record<string, unknown>;
  };
  if (r.kind === 'job_question') {
    const open = f.requests.filter((x) => !x.declined);
    const target = r.request ? f.requests.find((x) => x.ref === r.request) : open.length === 1 ? open[0] : null;
    if (!target) return { kind: r.kind, done: false, facts: plain(`He asked a question about a job but did not say which, and ${open.length} are open: ${open.slice(0, 8).map((x) => x.ref).join(', ') || 'none'}. Ask him which request (by its reference); nothing was filed yet.`) };
    const filed = await fileJobQuestion(admin, { supplierId: sid, inquiryId: target.inquiry_id, text: String(r.question || '').trim(), source: channel === 'portal' ? 'portal' : channel, askedBy: f.sender?.email ?? f.owner_email ?? null });
    if (!filed.ok) {
      const why: Record<string, string> = { too_many_questions: 'He already asked five questions on it today; ask him to wait until tomorrow or put them in one message.', inquiry_closed: `${target.ref} is closed, so no question can be filed on it.`, text_required: 'The question could not be read once contact details were removed; ask him to write it again without phone numbers or links.' };
      return { kind: r.kind, done: false, facts: plain(why[filed.code] ?? `His question on ${target.ref} could not be filed just now; tell him a colleague will file it.`), detail: { code: filed.code } };
    }
    return { kind: r.kind, done: true, detail: { id: filed.id, inquiry_id: target.inquiry_id }, facts: plain(`Filed: his question on ${target.ref} ("${String(r.question || '').slice(0, 200)}"). Our sales engineer reads it against the request first; what the request already answers is answered for every invited supplier without naming him, and anything else goes to the customer, who is reminded once. He will get the answer by e-mail and in his portal. Do not answer the question yourself in this reply.`) };
  }
  if (r.kind === 'close_account') {
    const live = Number(f.live_quotes ?? 0);
    if (live > 0 && r.keep_quotes == null) {
      return { kind: r.kind, done: false, facts: plain(`He asked to close his account. He has ${live} quotation${live === 1 ? '' : 's'} still with customers: ask him whether to WITHDRAW them or KEEP them (a customer may still reveal him on a kept one, and he is bound by it). Nothing was changed yet.`) };
    }
    const d = await rpc('fn_supplier_close_propose', { p_lead: sid, p_actor: actorOf(f), p_channel: channel, p_quotes: r.keep_quotes ? 'keep' : 'withdraw', p_reason: r.reason });
    if (!d.ok) return { kind: r.kind, done: false, facts: d.code === 'already_closed' ? 'His account is already closed. To come back he signs in and presses "Reopen my account".' : 'His request to close the account could not be prepared just now; tell him a colleague will follow up. Nothing was changed.', detail: d };
    const law = (d.law ?? {}) as { kept_until?: string; law?: string };
    return { kind: r.kind, done: true, detail: d, facts: plain(`Prepared, NOT yet done: close his account${live ? `, ${r.keep_quotes ? 'keeping' : 'withdrawing'} his ${live} quotation${live === 1 ? '' : 's'} with customers` : ''}. Closing stops all new job requests. Tell him truthfully that tax law requires us to keep his quotations and transactions, and that we keep his company record and messages for disputes, until ${law.kept_until ?? 'five years after his last activity'} (${law.law ?? 'Cabinet Decision 74/2023, Art. 3; UAE PDPL'}), used for nothing else, and that he can ask for a copy of his data. Ask him to reply "yes" to close it, or "no" to keep the account. Nothing changes until he confirms.`) };
  }
  if (r.kind === 'close_confirm' || r.kind === 'close_cancel') {
    if (!f.closure) return { kind: 'none', done: false, facts: '' };
    const d = await rpc('fn_supplier_close_decide', { p_lead: sid, p_actor: actorOf(f), p_decision: r.kind === 'close_cancel' ? 'cancel' : 'confirm' });
    if (r.kind === 'close_cancel') return { kind: r.kind, done: !!d.ok, facts: d.ok ? 'Kept: his account stays open, as he asked. Nothing was changed.' : 'His answer could not be recorded just now; his account is unchanged.' };
    if (!d.ok) return { kind: r.kind, done: false, facts: 'The closure did not go through; his account is unchanged. A colleague will complete it and confirm in writing.', detail: d };
    return { kind: r.kind, done: true, detail: d, facts: plain(`Done: his account is closed. No new job requests will reach him.${Number(d.withdrawn) ? ` ${d.withdrawn} quotation(s) were withdrawn.` : ''}${Number(d.kept) ? ` ${d.kept} quotation(s) stay with customers, as he chose.` : ''}${Number(d.revealed_open) ? ` ${d.revealed_open} customer(s) who already paid to see his details keep that right; he should still answer them.` : ''} The law keeps his records until ${d.kept_until} (${d.law}); a written confirmation was e-mailed to the owner. He can reopen from his portal.`) };
  }
  if (r.kind === 'customer_silent') {
    const list = f.revealed ?? [];
    const target = r.request ? list.find((x) => x.ref === r.request) : list.length === 1 ? list[0] : null;
    if (!target) return { kind: r.kind, done: false, facts: list.length ? `Ask him which revealed request the customer is not answering on: ${list.map((x) => x.ref).join(', ')}. Nothing was sent yet.` : 'No customer has revealed him yet, so there is no customer to remind. Nothing was sent.' };
    const d = await rpc('fn_supplier_customer_not_answering', { p_lead: sid, p_actor: actorOf(f), p_inquiry: target.inquiry_id, p_channel: channel, p_note: r.reason });
    if (!d.ok) return { kind: r.kind, done: false, facts: String(d.error || 'The reminder could not be sent just now; a colleague will follow up.'), detail: d };
    return { kind: r.kind, done: true, detail: d, facts: d.already ? `The customer on ${target.ref} was already reminded once; we do not remind twice. What he reported is on record if a refund is ever claimed.` : `Done: we reminded the customer on ${target.ref} once, by e-mail, that he is trying to reach them, and recorded his report (it counts if the customer later claims he never made contact).` };
  }
  if (r.kind === 'paid_leads') {
    await rpc('fn_supplier_demand_signal_record', { p_lead: sid, p_channel: channel, p_asked_for: r.asked_for || 'more requests', p_trade: r.trade, p_size: r.size, p_words: r.reason });
    return { kind: r.kind, done: true, facts: 'His offer was passed to management as interest. Tell him plainly and politely: on QuotesDone nobody can pay to rank higher, to get more requests or to be the only supplier on a request; every matched supplier receives the request and the customer chooses. Quoting fast and completely, and keeping his trades and areas accurate, is what wins work. Promise nothing else.' };
  }
  if (r.kind === 'refer_company') {
    const d = await rpc('fn_supplier_referral_link', { p_lead: sid });
    if (!d.ok) return { kind: r.kind, done: false, facts: d.code === 'not_approved' ? 'A referral link is given once the company is approved on QuotesDone. Tell him so, and that he can ask again then. Nothing else is promised.' : 'His referral link could not be read just now; tell him a colleague will send it.', detail: d };
    const n = Number(d.registered ?? 0);
    return { kind: r.kind, done: true, detail: d, facts: plain(`His company's own referral link is ${d.url} . Give it to him exactly. He sends it to companies he knows in his trade; we do not write to them ourselves. When one registers through it, it is recorded that his company referred it (${n} compan${n === 1 ? 'y has' : 'ies have'} so far). Registration is free, and nobody can pay to rank higher or for more requests.`) };
  }
  if (r.kind === 'owner_left') {
    if ((f.sender?.role ?? 'owner') === 'owner') return { kind: r.kind, done: false, facts: 'He is already the owner of this company on QuotesDone, so there is nothing to take over. If a colleague has left, he can remove him in Settings, Team; to hand the company to someone else he uses Settings, Team, Hand over. Nothing was changed.' };
    const d = await rpc('fn_supplier_ownership_claim_open', { p_lead: sid, p_actor: actorOf(f), p_reason: r.reason ?? 'the owner has left the company', p_channel: channel });
    if (!d.ok) return { kind: r.kind, done: false, facts: String(d.error || 'His request could not be recorded just now; tell him a colleague will follow up. Nothing was changed.'), detail: d };
    if (d.state === 'approved_waiting') return { kind: r.kind, done: true, detail: d, facts: plain(`His request is already approved: the company passes to him on ${d.effective_at ?? 'the date we wrote'} unless the owner keeps it before then. Nothing else is needed from him.`) };
    return { kind: r.kind, done: true, detail: d, facts: plain(`${d.already ? 'Added to his open request' : 'Recorded his request'} to take over the company because the owner has left. Our sales engineer reads the company's record and decides within two working days, and may ask him for proof (for example the trade licence page that names the manager). The owner has been told at the addresses we hold and can keep the company; if it is approved, the hand-over still waits three days for him. Nothing changes until then.`) };
  }
  return { kind: 'none', done: false, facts: '' };
}
