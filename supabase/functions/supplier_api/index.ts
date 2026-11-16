// supplier_api — the supplier portal's endpoint. This file is the door: CORS preflight, keep-warm, the three
// internal doors (spec_arabic_finish, docs_reread, email_quote / email_quote_read), sign-in, the sanctions refusal, the body, then dispatch.
// Every action lives in ./actions/<group>.ts and the helpers they share in ./lib/ and ./context.ts.
//
// `handle` stays here because a few actions run this same function in-process with the caller's own session
// (the quotation review, the supplier's PDFs, safeInquiryOf below). They receive it, and safeInquiryOf, in the
// request context rather than importing this file, so no module imports the entry point.
//
// Split from one 2,116-line file on 9 Nov 2026 (it_engineer) as a pure move: every statement is the one that
// was here, byte for byte. Checks that read this function as text read the whole folder through
// scripts/lib/function_sources.mjs functionSource('supplier_api').
import { observe } from '../_shared/observe.ts';
import { siteCors } from '../_shared/site_origins.ts';
import { afterResponse, readStoredDocsLater, rereadTogether, stuckReads } from '../_shared/supplier_docs_later.ts';
import { requireInternal } from '../_shared/internal_auth.ts';
import { safeInquiry } from './quote_review_actions.ts';
import { SANCTIONED_REFUSAL, sanctionedEmail } from '../_shared/sanctioned.ts';
import { type ActionCtx, J, admin, cors, failed } from './context.ts';
import { atTheDoor, warmOnly } from './lib/door.ts';
import { arabicFinish } from './lib/arabic_quotation.ts';
import { emailedQuotationThread, quoteReviewChatActions } from './actions/quote_review_chat.ts';
import { accountActions } from './actions/account.ts';
import { capabilityActions } from './actions/capabilities.ts';
import { documentActions } from './actions/documents.ts';
import { profileActions } from './actions/profile.ts';
import { inboxActions } from './actions/inbox.ts';
import { printActions } from './actions/prints.ts';
import { askQuoteExtract, quoteActions } from './actions/quotes.ts';
import { notForMeActions } from './actions/not_for_me.ts';
import { emailQuote, emailQuoteRead } from './email_quote.ts';

// The action groups, in the order their first action appeared in the old single if-chain. Each group is that
// chain's own `if (…)` blocks, moved verbatim, and answers undefined when none of its actions is asked. The
// quotation review's REVIEW_ACTIONS stay first, as they were; every other condition is a distinct string equality,
// and the four-document print block (quote_pdf | inquiry_pdf | receipts | receipt_pdf) stays one unit.
const ACTION_GROUPS: readonly ((c: ActionCtx) => Promise<Response | undefined>)[] = [
  quoteReviewChatActions, accountActions, capabilityActions, documentActions, profileActions, inboxActions, printActions,
  quoteActions, notForMeActions,
];

// THE JOB AS THE REVIEW MAY READ IT. `inbox` run in-process with the caller's own session is the one
// door onto an inquiry a supplier is allowed through: it is scoped to inquiry_matches, it applies the
// scrubbers and the reveal gate, and it withholds a BOQ or a brief it cannot prove clean. The quotation
// review reads the job through it in the chat, and now reads it through it at submit_quote and
// spec_approve too, so the three cannot disagree about what the supplier was pricing.
async function safeInquiryOf(req: Request, jwt: string, inquiryId: string) {
  const r = await handle(new Request(req.url, { method: 'POST', headers: { Authorization: 'Bearer ' + jwt, 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'inbox', inquiry_id: inquiryId }) }));
  const j = await r.json().catch(() => ({}));
  // deno-lint-ignore no-explicit-any
  const row = (j.inquiries || []).find((x: any) => String(x.id) === inquiryId);
  return row ? safeInquiry(row) : null;
}

// Named so the quotation review can run this same function in-process with the caller's own session.
const handle = async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  // KEEP-WARM (resilience_ping; 28 Sep 2026 it_engineer, supplier journey). No auth, no DB: the isolate is
  // what needs exercising. See warmPortal() in resilience_ping/index.ts.
  if (req.headers.get('x-qd-warm') === '1') return new Response(null, { status: 204 });
  let actionName = '';   // named in the cause of a throw (context.ts failed), 13 Nov 2026
  try {
    // The one internal door, before any session is asked for: the replay of a held Arabic translation.
    const peek = await req.clone().json().catch(() => ({}));
    // The portal's preflight warm: 204 before any session or database read (./lib/door.ts warmOnly).
    if (warmOnly(peek)) return new Response(null, { status: 204, headers: cors });
    if (peek?.__secret && peek.action === 'spec_arabic_finish') {
      const auth = await requireInternal(admin, String(peek.__secret), 'supplier_api');
      if (!auth.ok) return J({ error: 'forbidden' }, 403);
      return await arabicFinish(String(peek.quote_id || ''));
    }
    // THE SWEEP'S ONE RE-READ (19 Oct 2026, sales_engineer; _shared/supplier_docs_later.ts): resilience_ping asks every run;
    // a profile or catalogue still 'reading' 10 minutes on is read once more after this answer, marked retry, so a second
    // stall is left to fn_supplier_doc_reading_escalate (30 minutes, to the sales engineer). Gated again on its stored bytes.
    if (peek?.__secret && peek.action === 'docs_reread') {
      const auth = await requireInternal(admin, String(peek.__secret), 'supplier_api');
      if (!auth.ok) return J({ error: 'forbidden' }, 403);
      const stuck = await stuckReads(admin);
      // AND A LICENCE OUR READER FAILED ON (10 Nov 2026, customer_support; _shared/licence_read_state.ts). The database
      // hands out the due ones (licence_read_state 'ours_failed', backing off 10 min x 2^tries, at most 8 tries) and counts
      // the try as it does; each is read again by process_docs itself, the one licence reader, as the account that owns it.
      const { data: lics, error: licErr } = await admin.rpc('fn_supplier_licence_reread_claim', { p_limit: 3 });
      if (licErr) console.error(JSON.stringify({ at: 'supplier_api.docs_reread.licences', error: licErr.message }));
      const licences = ((lics ?? []) as { lead_id: number; claimed_by: string; license_doc_path: string }[]).filter((x) => x.claimed_by && x.license_doc_path);
      const job = (async () => {
        for (const s of stuck) {
          if (s.docs.length) await readStoredDocsLater(admin, s.supplier_id, s.docs, { retry: true });
          // the model could not be asked when these were read: asked again from their kept text (ruling 1627)
          if (s.again.length) await rereadTogether(admin, s.supplier_id, s.again);
        }
        for (const l of licences) {
          const body = { action: 'process_docs', license: { path: l.license_doc_path } };
          try { await documentActions({ email: String(l.claimed_by).toLowerCase(), body, action: body.action } as unknown as ActionCtx); }
          catch (e) { console.error(JSON.stringify({ at: 'supplier_api.docs_reread.licence', supplier: l.lead_id, error: String((e as Error)?.message || e) })); }
        }
      })();
      const w = afterResponse(job, 'supplier_api.docs_reread'); if (w) await w;
      return J({ ok: true, rereading: stuck.map((s) => ({ supplier_id: s.supplier_id, docs: s.docs.length, again: s.again.length })),
                 licences_rereading: licences.map((l) => l.lead_id) });
    }
    // A QUOTATION BY E-MAIL (10 Nov 2026, customer_support; 12 Nov 2026, sales_engineer, LLM-first audit A2): resend_inbound
    // asks email_quote_read what the MODEL reads in each candidate, then hands a quotation for one of his requests to
    // email_quote, which places it in his quotation thread for him to confirm (./email_quote.ts says why and how).
    if (peek?.__secret && (peek.action === 'email_quote' || peek.action === 'email_quote_read')) {
      const auth = await requireInternal(admin, String(peek.__secret), 'supplier_api');
      if (!auth.ok) return J({ error: 'forbidden' }, 403);
      const deps = {
        lead: async (id: number) => (await admin.from('leads').select('id,claimed_by,company_name').eq('id', id).maybeSingle()).data ?? null,
        sanctioned: (e: string) => sanctionedEmail(admin, e), inboxActions, safeInquiry, extract: askQuoteExtract, review: emailedQuotationThread };
      return J(peek.action === 'email_quote_read' ? await emailQuoteRead(peek, deps) : await emailQuote(peek, deps));
    }
    const jwt = (req.headers.get('Authorization') || '').replace('Bearer ', '');
    // A SANCTIONED PARTY CANNOT ACT (founder instruction 516, 18 Sep 2026). Above the action
    // switch, before the body is even read, because this function serves forty-odd actions and a
    // per-action guard is a list somebody will one day add to without reading. Asked of
    // public.sanctions_ban and NOT of leads.banned: a supplier banned for unpaid dues must keep
    // reaching supplier_pay to clear it.
    // The ban read leaves beside the sign-in check for the address the token names, and is used only for the address getUser
    // verified (15 Nov 2026: one round trip fewer on every action; ./lib/door.ts says why it decides exactly what it did).
    const door = await atTheDoor(jwt, { getUser: async (t) => (await admin.auth.getUser(t)).data.user, sanctioned: (e) => sanctionedEmail(admin, e) });
    if (door.kind === 'unauthorized') return J({ error: 'unauthorized' }, 401);
    if (door.kind === 'sanctioned') return J(SANCTIONED_REFUSAL, 403);
    const { user, email } = door;
    const body = await req.json().catch(() => ({})); const action = body.action; actionName = String(action ?? '').slice(0, 40);
    const ctx: ActionCtx = { req, jwt, user, email, body, action, handle, safeInquiryOf };
    for (const group of ACTION_GROUPS) {
      // awaited inside the try, so an action that throws still reaches the catch below
      const answer = await group(ctx);
      if (answer) return answer;
    }
    return J({ error: 'unknown action' }, 400);
  } catch (e) {
    return failed(actionName ? `unhandled in ${actionName}` : 'unhandled', e);
  }
};
Deno.serve(siteCors(observe('supplier_api', handle)));
