// inquiry_intake/customer_record.ts — the intake chat reads the customer's whole record, as every other door does (sales_engineer,
// 16 Nov 2026; founder ledgers 1711-1713: "everyone knows what the other is doing because they are colleagues in the same company";
// audit SP/audit/WHO_KNOWS_WHAT.md item 1).
//
// MEASURED (READ, origin/main 55489dde7): the intake was the ONE customer door with no loadCaseContext / recordCaseExchange and no
// read of his earlier requests. A customer who complained on WhatsApp that request 1 got no quotes opened request 2, and the
// intake could promise "quotes within 24 hours" blind to the complaint, and that promise went into no record, so WhatsApp could
// not keep it. Now each turn reads, beside the trade reads it already starts together (turn_clock.ts):
//   * his earlier requests: fn_customer_inquiry_facts, the one reading WhatsApp and the widget give (status, quotes due by, late);
//   * the promises still open on his cases: fn_person_open_promises (every_door_and_the_ceo_read_the_same_case.sql);
//   * his case: loadCaseContext (_shared/case_context.ts), channel 'portal', seat 'sales_engineer', exactly as the portal chat;
// and after the reply that was really given, recordCaseExchange writes the exchange (and any promise in it) onto his case,
// never awaited. The three reads run together and each is cut at CASE_READ_MS: the turn never waits longer than that for them,
// and in practice not at all, because they are started before the trade's checklist, questions, field knowledge and state, and
// read only when the prompt is built (the test measures both). A read that fails or is late is simply absent: the record block
// is then empty and the turn is exactly what it was. The record is for the model to know, never to fill this request's checklist:
// the never-ask-twice rule and asked_keys stay this conversation's (handle.ts rules 2, 11 and 18 are unchanged).
// prevented by: inquiry_intake/the_intake_reads_his_whole_record.test.ts
import { CASE_READ_MS, loadCaseContext, recordCaseExchange, type CaseTurn } from '../_shared/case_context.ts';
import { caseBlock } from '../_shared/support_case_memory.ts';
import type { ThinkDeps } from '../_shared/think.ts';

// deno-lint-ignore no-explicit-any
type Row = Record<string, any>;
export interface CustomerRecord {
  requests: Row[];
  promises: Row[];
  kase: CaseTurn<unknown> | null;
  /** how long the reads took, start to the last one answering or being cut (ms) */
  ms: number;
}
export const EMPTY_RECORD: CustomerRecord = { requests: [], promises: [], kase: null, ms: 0 };

/** One read, cut at `ms`: its rows, or [] when it fails, errors or is late. */
function bounded(p: () => PromiseLike<{ data?: unknown; error?: unknown }>, ms: number): Promise<Row[]> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const late = new Promise<Row[]>((r) => { timer = setTimeout(() => r([]), ms); });
  const read = Promise.resolve().then(p).then(({ data, error }) => (!error && Array.isArray(data) ? data as Row[] : []), () => []);
  return Promise.race([read, late]).finally(() => clearTimeout(timer));
}

/** STARTED EARLY, READ LATE: the three reads begin together; the promise settles within readMs (default CASE_READ_MS). */
export function readCustomerRecord(deps: ThinkDeps, o: {
  customerId: string | null; email: string; message: string; past: readonly unknown[]; lang: 'en' | 'ar'; dedupeKey: string; readMs?: number;
}): Promise<CustomerRecord> {
  const t0 = performance.now();
  const ms = o.readMs ?? CASE_READ_MS;
  if (!o.customerId && !/@/.test(o.email)) return Promise.resolve(EMPTY_RECORD);
  const requests = o.customerId ? bounded(() => deps.rpc('fn_customer_inquiry_facts', { p_customer: o.customerId, p_limit: 10 }), ms) : Promise.resolve([]);
  const promises = bounded(() => deps.rpc('fn_person_open_promises', { p_party_kind: 'customer', p_party_id: o.customerId, p_email: o.email,
    p_phone: null, p_limit: 10 }), ms);
  const kase = loadCaseContext(deps, { channel: 'portal', seat: 'sales_engineer', audience: 'customer', message: o.message || '(they sent a file)',
    partyId: o.customerId, email: o.email, lang: o.lang, dedupeKey: o.dedupeKey, sys: '', past: [...o.past], readMs: ms })
    .catch(() => null) as Promise<CaseTurn<unknown> | null>;
  return Promise.all([requests, promises, kase]).then(([r, p, k]) => ({ requests: r, promises: p, kase: k, ms: Math.round(performance.now() - t0) }));
}

const clip = (s: unknown, n: number) => String(s ?? '').replace(/\s+/g, ' ').trim().slice(0, n);
const day = (s: unknown) => { const t = Date.parse(String(s ?? '')); return Number.isFinite(t) ? new Date(t).toISOString().slice(0, 16).replace('T', ' ') + ' UTC' : ''; };

/** What the interview model reads under THIS TURN. Empty when the record holds nothing: a first-time customer's prompt is unchanged. */
export function recordBlock(rec: CustomerRecord | null): string {
  if (!rec) return '';
  const lines: string[] = [];
  if (rec.requests.length) {
    lines.push('HIS EARLIER REQUESTS (newest first):');
    for (const r of rec.requests.slice(0, 10)) {
      const late = r.late === true ? ' LATE: quotes were due by ' + day(r.quotes_due_by) + ' and fewer than ' + (r.quotes_wanted ?? 3) + ' arrived.' : '';
      const chase = r.chase && typeof r.chase === 'object' ? ' He already asked us to chase it (' + clip(r.chase.state, 20) + ').' : '';
      lines.push('- ' + clip(r.ref || String(r.id ?? '').slice(0, 8), 24) + ' ' + clip(r.category, 40) + (r.emirate ? ', ' + clip(r.emirate, 30) : '') + ': '
        + clip(r.status_meaning || r.status, 80) + '; quotes received ' + Number(r.quotes_received ?? 0) + '.' + late + chase);
    }
  }
  if (rec.promises.length) {
    lines.push('PROMISES WE MADE HIM THAT ARE STILL OPEN:');
    for (const p of rec.promises.slice(0, 10)) {
      lines.push('- ' + clip(p.what, 160) + ' (due ' + day(p.due_at) + ', ' + clip(p.owner_seat, 30) + ', case ' + clip(p.case_ref, 20) + ')' + (p.overdue === true ? ' OVERDUE' : ''));
    }
  }
  const m = rec.kase?.memory;
  if (m && m.ref && String(m.summaryText ?? '').trim()) lines.push(caseBlock(m));
  // his open escalations and the founder's availability (escalation_clock.ts, read by loadCaseContext beside the case; '' when none)
  if (String(rec.kase?.standing ?? '').trim()) lines.push(String(rec.kase!.standing).trim());
  if (!lines.length) return '';
  return ['THIS CUSTOMER\'S RECORD WITH US (read from our records on every channel: WhatsApp, e-mail, the portal; for you to know, not to recite):', ...lines,
    'HOW TO USE THIS RECORD: (a) This conversation is its own request: never fill its checklist, brief.details, already_provided or asked_keys from an earlier request or the case unless he says in this conversation that it is the same job; ask what this request still needs, never what this conversation already answered. '
    + '(b) When he raises an earlier request, a complaint or a promise, answer it in one short sentence from this record (its reference and where it stands, that our team has it), then carry on with this request. '
    + '(c) While an earlier request is LATE or a promise is OVERDUE, never promise him a time for quotes on this request, and never repeat a promise this record shows we have not kept. '
    + '(d) Never name a supplier or a price this record does not show.'].join('\n');
}

/** After the reply that was really given: the exchange onto his case. Never awaited by the turn; returns the work for a test. */
export function recordIntakeExchange(deps: ThinkDeps, rec: CustomerRecord | null, o: { theirMessage: string; ourReply: string; intakeId: string; turnId: string | null }) {
  if (!rec?.kase) return null;
  return recordCaseExchange(deps, rec.kase, { theirMessage: o.theirMessage, ourReply: o.ourReply,
    subject: { channel: 'request_chat', intake_id: o.intakeId, ...(o.turnId ? { turn_id: o.turnId } : {}) } });
}
