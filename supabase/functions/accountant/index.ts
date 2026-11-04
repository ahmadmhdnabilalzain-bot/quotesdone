// accountant — the Accountant seat's runtime. The company's FOURTH agent.
//
// WHY IT EXISTS. The founder, 9 September 2026: "now what we need to build is the accountant agent.
// tasks: any financial thing on the platform including refunds. reports to CEO. collects expenses
// from the email expenses@mail.quotesdone.com. create weekly report as pdf and share it with me and
// the CEO. takes approval from CEO on refunds and Meta ads expenses."
//
// NO MODEL CALL, ANYWHERE IN HERE, and every action below was chosen so that is not a limitation.
// All 8 routes in llm_route_health are held under the founder's own hold and
// fn_kernel_paid_provider_gate denies GLOBALLY while any route is held. Bookkeeping is the one seat
// where that costs nothing at all: a ledger balance is arithmetic over source rows, a grant answer
// is a database decision, and a refund this seat may not approve is a routing fact. There is no
// judgement in any of it, which is why none is faked.
//
// THE CREDENTIAL DECIDES THE SEAT, NOT THE CALLER. ceo_agent shipped on 8 Sep reading `body.as` and
// believing it, which let any holder of an in-scope credential present as the CEO — a real
// confused-deputy defect, fixed the same day. This file never reads a seat name off the payload.
//
// WHAT IS DELIBERATELY ABSENT, so nobody mistakes silence for capability: this function does not
// render the weekly report. Naming an absence here is cheaper than discovering later that a zero meant
// "nothing was collected" when it meant "nothing collects".
//
// 14 SEP 2026 — THE SEAT PAYS WHAT THE CEO APPROVED. The founder: "approval from CEO, execution from
// the accountant always whenever it's related to money", and "anything related to payment is under
// the accountant agent". execute_refunds sends to Stripe exactly the refunds whose CEO approval passed
// the process checklist (refunds.refund_decision_id; the z05 guard refuses anything else), stated at
// the amount the customer paid, and the Stripe fixes the CEO's mismatch playbook hands this seat. It
// holds every ordinary refund while the CEO's circuit breaker is on. resilience_ping calls it under
// this seat's own credential.
//
// 9 SEP 2026 — THE SEAT NOW READS ITS OWN MAILBOX. The founder: "once he access the email, let him
// send me a report of all what we spent since day 1 by trailing the whole inbox and that would be a
// test. also such tasks dont require LLM i believe and it can be built in code." He is right, and
// this is that, in code:
//
//   expense_sweep — walks the WHOLE of Resend's inbound history (GET /emails/inbound, paged),
//     keeps the messages addressed to expenses@mail.quotesdone.com, applies the SAME sender
//     allowlist the live webhook applies, and books what it can read through the SAME key
//     (expense_entries.source_msg_id = 'resend:<email_id>'), so the sweep and resend_inbound can
//     never book the same receipt twice. A message it cannot read is HELD and NAMED — never
//     guessed, never zeroed, never estimated.
//   spend_report  — the since-day-1 report over what was booked, with the coverage of the last
//     sweep quoted from agent_runs so a total can be seen to be complete or seen to be short.
//
// WHY THE SWEEP HAD TO EXIST AT ALL (measured 9 Sep 2026): the Resend RECEIVING ROUTE for
// expenses@mail.quotesdone.com does not exist — only info@, supplier@ and docs@mail are wired — so
// the live webhook was never going to be handed this mail. Resend kept the messages anyway. The
// history is the only path by which the founder's own spend can reach the ledger.
import { readEveryAttachment, envGatewayVision } from '../_shared/read_every_attachment.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
// The sweep runs the SAME code the live webhook runs. Nothing about reading a receipt is
// reimplemented here: receipt_parse reads the text, pdf_text reads the PDF's text layer,
// attachment.ts sanitises by magic bytes, safe_url refuses an SSRF target, and the ledger posting
// is fn_expense_post_to_gl. This file only walks the history and hands each message to them.
import { parseAmount, parseReceipt } from '../_shared/receipt_parse.ts';
import { defaultDeps } from '../_shared/think.ts';
import { documentKind, readingOf, reasonBankLines, receiptVendor, type ExpenseMail } from '../_shared/reasoned_books.ts';
import { pdfText } from '../_shared/pdf_text.ts';
import { sanitizeUpload, SAFE_UPLOAD } from '../_shared/attachment.ts';
// MALWARE WATCH, 9 Sep 2026 — see _shared/malware.ts. The historical sweep pulls attachments out of
// a mailbox anybody can send to, so the same verdict applies here as on the live inbound path.
import { sanitizeAndScan } from '../_shared/malware.ts';
import { safeFetch } from '../_shared/safe_url.ts';
// A receipt whose email carried no vendor file gets a PDF PRINT of the email, not a .html blob.
import { emailPrintPdf } from '../_shared/email_print.ts';
import { observe } from '../_shared/observe.ts';
import { decideJudgement, recallCases } from '../_shared/case_recall.ts';
import { confirmRefundOutcome, refundIdempotencyKey, refundKey, stripeRefund } from '../_shared/stripe_refund.ts';
import { isDemoEmail } from '../_shared/demo_identity.ts';
// 14 Sep 2026 — the duties (founder: "yea add them all", "yea add them"). Nothing is re-implemented:
// the charge audit uses the #616 formula itself, the statement reader and the dispute form are pure
// modules with their own tests.
import { revealChargeFor, absorbedStripeCost } from '../_shared/reveal_fee.ts';
import { readStatement } from '../_shared/bank_statement_parse.ts';
import { statementRowText, takeInStatement } from '../_shared/bank_statement_intake.ts';
import { draftDisputes } from '../_shared/dispute_draft.ts';
import { type InboundItem, type MailboxMessage, mailboxMessages, registerRowsFor } from '../_shared/expense_mailbox.ts';
// 3 Nov 2026 — a paid reveal with no sale is found and recorded within the hour (action 'reveal_reconcile').
import { recordRevealSale } from '../_shared/reveal_sale.ts';
import { clampDays, reportable, sweepReveals, type Mode } from '../_shared/reveal_reconcile.ts';
import { timedFetch } from '../_shared/timed_fetch.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const J = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });

async function sec(k: string): Promise<string | undefined> {
  const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle();
  return data?.value as string | undefined;
}

const SUPA_URL = Deno.env.get('SUPABASE_URL')!;
// The founder confirmed this address on 9 Sep 2026: the accountant "collects expenses from the
// email expenses@mail.quotesdone.com". The same literal resend_inbound uses.
const EXPENSE_MAILBOX = 'expenses@mail.quotesdone.com';
// deno-lint-ignore no-explicit-any
function stripHtml(x: unknown) { return String(x || '').replace(/<style[\s\S]*?<\/style>/gi, ' ').replace(/<script[\s\S]*?<\/script>/gi, ' ').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&#36;/g, '$').replace(/\s+/g, ' ').trim(); }
// deno-lint-ignore no-explicit-any
function pickBody(d: any) { const t = d?.text || d?.plain || d?.['body-plain'] || d?.['stripped-text'] || ''; const h = d?.html || d?.['body-html'] || ''; const b = String(t || ''); return b || (h ? stripHtml(h) : ''); }
const dbxSafe = (x: string) => String(x || '').replace(/[\\/:*?"<>|\r\n\t]+/g, ' ').replace(/\s+/g, ' ').trim();

// THE ONLY CREDENTIAL THAT IS THIS SEAT. An unrecognised context is refused rather than defaulted,
// and there is no service-caller list because nothing calls this function yet — an empty allowance
// is the honest starting point, and widening it later is a decision somebody has to write down.
const SEAT_BY_CREDENTIAL: Record<string, 'accountant'> = {
  'fn.accountant': 'accountant',
};

type Caller = { kind: 'accountant' | 'founder' } | null;

async function whoami(req: Request, body: Record<string, unknown>): Promise<Caller> {
  if (body?.__secret) {
    const r = await requireInternal(admin, String(body.__secret), 'accountant');
    // ok-but-unrecognised is NOT a fallback to the seat. It is a refusal.
    if (r.ok) return SEAT_BY_CREDENTIAL[r.context] ? { kind: 'accountant' } : null;
  }
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  if (!jwt) return null;
  const { data } = await admin.auth.getUser(jwt).catch(() => ({ data: { user: null } } as never));
  const email = String((data as { user?: { email?: string } })?.user?.email || '').toLowerCase();
  if (!email) return null;
  const allow = (await sec('admin_emails') || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
  return allow.includes(email) ? { kind: 'founder' } : null;
}

// EVERY CALL LEAVES A ROW. fn_agents_board LEFT JOINs agent_runs on agent = agent_key, so a seat
// that never writes one renders with runs24 = 0 — indistinguishable from a seat that is down. This
// is the only measurable liveness signal the estate has. Best-effort: attribution must never fail
// the call it is attributing.
// Embedding is FREE and in-region — Supabase.ai's gte-small, 384-dim, not a paid OpenRouter route.
// It runs before any gate because it costs nothing and because a seat that cannot embed cannot
// search its own knowledge. Returns null on failure so fn_accountant_assist can fall back to its
// lexical bar rather than the call dying.
// deno-lint-ignore no-explicit-any
let _emb: any = null;
async function embed(text: string): Promise<string | null> {
  try {
    // deno-lint-ignore no-explicit-any
    if (_emb === null) _emb = new (globalThis as any).Supabase.ai.Session('gte-small');
    const v = await _emb.run(String(text).slice(0, 1200), { mean_pool: true, normalize: true }) as number[];
    return '[' + v.join(',') + ']';
  } catch (_e) { return null; }
}

async function run(action: string, status: string, counts: Record<string, unknown>, note?: string) {
  try {
    await admin.from('agent_runs').insert({
      agent: 'accountant',
      status,
      started_at: new Date().toISOString(),
      finished_at: new Date().toISOString(),
      counts: { action, ...counts },
      note: note ?? null,
    });
  } catch { /* an unwritten log must not turn a good answer into a 500 */ }
}

// A refund sent to Stripe at a STATED amount, idempotent on a key this seat chooses, against the exact
// payment it reverses (a checkout-session reference is resolved to its payment intent first).
// deno-lint-ignore no-explicit-any

// THREE DIFFERENT FACTS PRINT AS THE CHARACTER 0 ON THIS DATABASE, and the accountant grant says so
// in its own words: "An unmeasurable figure is reported as unknown, never estimated and never
// defaulted to zero." So a book is read as:
//
//   true_zero  — the table was read, it holds no rows, and the window it holds no rows over is
//                stated. This is a measurement, and it is the answer for gl_journal, expenses and
//                ap_bills today.
//   measured   — the table was read and holds rows, with the observed date window.
//   unknown    — the table could not be read (absent, or the read errored). The count is null, NOT
//                0, because "we could not look" and "we looked and found nothing" are different
//                facts and only one of them is evidence.
//
// The window is the OBSERVED extent of the date column, not a requested filter: nothing here
// filters by date, so claiming a 30-day window would be describing a query that was never run.
async function book(table: string, dateCol: string | null): Promise<Record<string, unknown>> {
  const { count, error } = await admin.from(table).select('*', { count: 'exact', head: true });
  if (error) {
    return { table, basis: 'unknown', rows: null, window: null, reason: error.message };
  }
  const rows = count ?? 0;
  if (!dateCol) return { table, basis: rows ? 'measured' : 'true_zero', rows, window: null };
  if (!rows) {
    return {
      table, basis: 'true_zero', rows: 0,
      window: { column: dateCol, from: null, to: null, note: 'no rows at all, so the window is the whole table and it is empty' },
    };
  }
  const [lo, hi] = await Promise.all([
    admin.from(table).select(dateCol).order(dateCol, { ascending: true }).limit(1).maybeSingle(),
    admin.from(table).select(dateCol).order(dateCol, { ascending: false }).limit(1).maybeSingle(),
  ]);
  // The column is chosen at runtime, so postgrest-js types the row as a union it cannot narrow.
  // deno-lint-ignore no-explicit-any
  const pick = (r: any) => (r?.data ? (r.data as Record<string, unknown>)[dateCol] ?? null : null);
  return { table, basis: 'measured', rows, window: { column: dateCol, from: pick(lo), to: pick(hi) } };
}

Deno.serve(observe('accountant', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const caller = await whoami(req, body);
    if (!caller) return J({ error: 'unauthorized' }, 401);

    const action = String(body.action || '').trim();

    // ── HEALTH ─────────────────────────────────────────────────────────────────────────────────
    // Is the seat seated, what does it hold, and what state are the books in. Readiness measured,
    // not asserted: edge_health_probe exists with 0 rows and nothing writes it, so an authenticated
    // round-trip returning this object is the honest liveness signal.
    if (action === 'health') {
      const [agent, grants, edge, owner, routes, journal, expenses] = await Promise.all([
        admin.from('org_agents').select('agent_key,active,available,title,manager_key').eq('agent_key', 'accountant').maybeSingle(),
        admin.from('ceo_standing_grant').select('grant_key,action_class,max_amount_aed,active').eq('grantee_role_id', 'accountant'),
        admin.from('org_reporting_edge').select('parent_role_id').eq('child_role_id', 'accountant').maybeSingle(),
        admin.from('function_owner').select('function_slug').eq('owner', 'accountant'),
        admin.from('llm_route_health').select('model_id,open_until'),
        book('gl_journal', 'entry_date'),
        book('expenses', 'expense_date'),
      ]);

      const held = (routes.data || []).filter((r: { open_until: string | null }) =>
        r.open_until && new Date(r.open_until) > new Date());

      await run('health', 'ok', { grants: (grants.data || []).length, owns: (owner.data || []).length });
      return J({
        ok: true,
        seat: 'accountant',
        caller: caller.kind,
        seated: agent.data?.active === true && agent.data?.available === true,
        reports_to: edge.data?.parent_role_id ?? null,
        grants: (grants.data || []).map((g: { grant_key: string; action_class: string; max_amount_aed: number | null; active: boolean }) =>
          ({ grant: g.grant_key, class: g.action_class, ceiling_aed: g.max_amount_aed, active: g.active })),
        owns_functions: (owner.data || []).map((r: { function_slug: string }) => r.function_slug).sort(),
        ledger_state: { gl_journal: journal, expenses },
        // Reported because it is true of every seat, not because this one is waiting on it. Nothing
        // in this runtime needs a model.
        model_calls_available: held.length === 0,
        model_hold: held.length
          ? { routes_held: held.length, until: held[0].open_until,
              note: 'fn_kernel_paid_provider_gate denies globally while any route is held. No action in this function calls a model, so nothing here is blocked by it.' }
          : null,
      });
    }

    // ── DOCUMENT ───────────────────────────────────────────────────────────────────────────────
    // THE OS'S WAY FROM AN EXPENSE ROW TO SOMETHING IT CAN OPEN. The founder, 9 Sep 2026: "later
    // when we build the OS i wanna be able to click any record and see the actual invoice or receipt
    // or email print pdf if none exist".
    //
    // receipt-files is a PRIVATE bucket, so a path is not a link — it has to be signed. That signing
    // needs the service role, which no browser may hold, and Postgres cannot mint one (there is no
    // pgjwt in this project; `sign` in pg_catalog is the arithmetic sign function). So the door is
    // here, and it is a door rather than a directory: the caller names an ENTRY, never a path, and
    // fn_expense_document decides what that entry's document is. A caller who could name its own
    // path could read any object in the bucket.
    //
    // A row with no document is answered, not 404'd: ok:false with `state` and the reason in words,
    // so the OS can render "no document" instead of a broken link. `action: 'documents'` lists the
    // whole book's coverage in one call for the same reason.
    if (action === 'document' || action === 'documents') {
      if (action === 'documents') {
        const { data: cov } = await admin.rpc('fn_expense_document_coverage');
        const { data: rows } = await admin.from('v_expense_documents')
          .select('id,vendor,charged_on,amount,currency,source_channel,document_state,doc_kind,doc_name,doc_note')
          .order('id');
        await run('documents', 'ok', (cov || {}) as Record<string, unknown>);
        return J({ ok: true, seat: 'accountant', coverage: cov, entries: rows || [],
          basis: 'public.v_expense_documents, read at call time. document_state is vendor_document, '
            + 'email_print, unclassified or missing — never inferred from a filename.' });
      }
      const entryId = Number(body.entry_id);
      if (!Number.isFinite(entryId) || entryId <= 0) return J({ ok: false, error: 'entry_id is required' }, 400);
      const { data: doc, error: docErr } = await admin.rpc('fn_expense_document', { p_entry_id: entryId });
      if (docErr) return J({ ok: false, error: docErr.message }, 500);
      const d0 = (doc || {}) as Record<string, unknown>;
      if (d0.ok !== true) { await run('document', 'ok', { entry_id: entryId, state: d0.state }); return J({ ok: false, ...d0 }); }
      const ttl = Math.min(Math.max(Number(body.expires_in) || 3600, 60), 7 * 24 * 3600);
      const { data: signed, error: sErr } = await admin.storage
        .from(String(d0.bucket)).createSignedUrl(String(d0.path), ttl);
      if (sErr || !signed?.signedUrl) {
        // A path that will not sign is a path pointing at nothing. Say that, rather than handing
        // back a dead link — a broken document is worse than a declared absence.
        await run('document', 'error', { entry_id: entryId, path: d0.path },
          'expense #' + entryId + ' names a document that could not be signed: ' + String(sErr?.message || 'no url returned')
          + '. The object is missing from receipt-files or the path is wrong.');
        return J({ ok: false, ...d0, state: 'object_unreachable',
          reason: 'The record names a document but the object could not be signed: ' + String(sErr?.message || 'no url returned') }, 502);
      }
      await run('document', 'ok', { entry_id: entryId, kind: d0.kind });
      return J({ ok: true, ...d0, url: signed.signedUrl, expires_in: ttl });
    }

    // ── THE SAME DOOR, FOR A REFUND (9 Sep 2026) ───────────────────────────────────────────────
    // The founder: "when a refund is issued, it's issued against that exact invoice reference ...
    // which also should be available with the accountant and the CEO as a PDF as it is from Stripe."
    // finance-docs is private, so the path has to be signed, and signing needs the service role
    // that no browser may hold. Identical shape to the expense door above and for the same reason:
    // the caller names a REFUND, never a path — a caller who could name its own path could read any
    // object in finance-docs.
    //
    // A refund with no stored file is ANSWERED, not 404'd. `state` distinguishes three real things:
    // 'reference_only' (Stripe's own hosted receipt for the payment is known but has not been
    // fetched into the bucket), 'missing' (nothing at all), and a doc_kind (a file is held). The
    // reply also carries `stripe_binding`, which says whether the refund names the exact Stripe
    // payment of the transaction it reverses.
    if (action === 'refund_document' || action === 'refund_documents') {
      if (action === 'refund_documents') {
        const { data: cov } = await admin.rpc('fn_refund_document_coverage');
        const { data: rows } = await admin.from('v_refund_documents')
          .select('id,transaction_id,status,amount_fils,currency,stripe_payment_intent,stripe_refund_id,stripe_binding,document_state,doc_kind,doc_name,doc_note')
          .order('id');
        await run('refund_documents', 'ok', (cov || {}) as Record<string, unknown>);
        return J({ ok: true, seat: 'accountant', coverage: cov, refunds: rows || [],
          basis: 'public.v_refund_documents, read at call time. document_state is the doc_kind, '
            + '\'unclassified\', \'reference_only\' or \'missing\' — never inferred from a filename. '
            + 'stripe_binding is measured against transactions.payment_ref, never asserted.' });
      }
      const refundId = Number(body.refund_id);
      if (!Number.isFinite(refundId) || refundId <= 0) return J({ ok: false, error: 'refund_id is required' }, 400);
      const { data: doc, error: docErr } = await admin.rpc('fn_refund_document', { p_refund_id: refundId });
      if (docErr) return J({ ok: false, error: docErr.message }, 500);
      const r0 = (doc || {}) as Record<string, unknown>;
      if (r0.ok !== true) { await run('refund_document', 'ok', { refund_id: refundId, state: r0.state }); return J({ ok: false, ...r0 }); }
      const rTtl = Math.min(Math.max(Number(body.expires_in) || 3600, 60), 7 * 24 * 3600);
      const { data: rSigned, error: rErr } = await admin.storage
        .from(String(r0.bucket)).createSignedUrl(String(r0.path), rTtl);
      if (rErr || !rSigned?.signedUrl) {
        // A path that will not sign is a path pointing at nothing. Say so rather than hand back a
        // dead link — a broken document is worse than a declared absence.
        await run('refund_document', 'error', { refund_id: refundId, path: r0.path },
          'refund #' + refundId + ' names a document that could not be signed: ' + String(rErr?.message || 'no url returned')
          + '. The object is missing from finance-docs or the path is wrong.');
        return J({ ok: false, ...r0, state: 'object_unreachable',
          reason: 'The record names a document but the object could not be signed: ' + String(rErr?.message || 'no url returned') }, 502);
      }
      await run('refund_document', 'ok', { refund_id: refundId, kind: r0.kind });
      return J({ ok: true, ...r0, url: rSigned.signedUrl, expires_in: rTtl });
    }

    // ── THE SAME DOOR, FOR THE REVENUE SIDE (9 Sep 2026) ───────────────────────────────────────
    // The founder, instruction 28: "stripe automatically generates an invoice as far as i know, our
    // accountant need to retrieve that and be connected, then add it to his records."
    //
    // Retrieval is stripe_webhook's job and the record is public.transactions; THIS is the part
    // where the accountant can actually open what was filed. Without it the invoices would be a
    // finished capability with no entry point - stored, mirrored to Dropbox, and unreachable from
    // the seat whose books cite them.
    //
    // Identical shape to the expense and refund doors above, for the identical reason: finance-docs
    // is private, signing needs the service role no browser may hold, and the caller names a SALE
    // rather than a path. A sale with no stored file is ANSWERED, not 404'd - 'reference_only' says
    // Stripe issued the invoice and the PDF has not been fetched, which is a different fact from
    // 'missing', which is a different fact again from a reveal that was never charged.
    if (action === 'revenue_document' || action === 'revenue_documents') {
      if (action === 'revenue_documents') {
        const { data: cov } = await admin.rpc('fn_revenue_document_coverage');
        const { data: rows } = await admin.from('v_revenue_documents')
          .select('id,quote_id,revealed_at,fee_status,reveal_fee,payment_ref,stripe_invoice_id,stripe_invoice_number,stripe_invoice_status,stripe_invoice_total_fils,stripe_invoice_currency,invoice_agrees_with_fee,document_state,doc_kind,doc_name,doc_note')
          .eq('fee_was_taken', true).order('revealed_at');
        await run('revenue_documents', 'ok', (cov || {}) as Record<string, unknown>);
        return J({ ok: true, seat: 'accountant', coverage: cov, sales: rows || [],
          basis: 'public.v_revenue_documents, read at call time, restricted to sales that actually '
            + 'took a fee. document_state is the doc_kind, \'unclassified\', \'reference_only\' '
            + '(Stripe issued the invoice, the PDF is not in finance-docs) or \'missing\'. '
            + 'invoice_agrees_with_fee compares Stripe\'s own total against reveal_fee rather than '
            + 'assuming they match.' });
      }
      const txId = String(body.transaction_id || '').trim();
      if (!txId) return J({ ok: false, error: 'transaction_id is required' }, 400);
      const { data: doc, error: docErr } = await admin.rpc('fn_revenue_document', { p_transaction_id: txId });
      if (docErr) return J({ ok: false, error: docErr.message }, 500);
      const t0 = (doc || {}) as Record<string, unknown>;
      if (t0.ok !== true) { await run('revenue_document', 'ok', { transaction_id: txId, state: t0.state }); return J({ ok: false, ...t0 }); }
      const tTtl = Math.min(Math.max(Number(body.expires_in) || 3600, 60), 7 * 24 * 3600);
      const { data: tSigned, error: tErr } = await admin.storage
        .from(String(t0.bucket)).createSignedUrl(String(t0.path), tTtl);
      if (tErr || !tSigned?.signedUrl) {
        // A path that will not sign is a path pointing at nothing. Say so rather than hand back a
        // dead link — a broken document is worse than a declared absence.
        await run('revenue_document', 'error', { transaction_id: txId, path: t0.path },
          'sale ' + txId + ' names an invoice that could not be signed: ' + String(tErr?.message || 'no url returned')
          + '. The object is missing from finance-docs or the path is wrong.');
        return J({ ok: false, ...t0, state: 'object_unreachable',
          reason: 'The record names a document but the object could not be signed: ' + String(tErr?.message || 'no url returned') }, 502);
      }
      await run('revenue_document', 'ok', { transaction_id: txId, kind: t0.kind });
      return J({ ok: true, ...t0, url: tSigned.signedUrl, expires_in: tTtl });
    }

    // ── GRANTS ─────────────────────────────────────────────────────────────────────────────────
    // What may this seat do RIGHT NOW, answered by the database at call time — active state, expiry
    // and the amount ceiling are all evaluated inside fn_agent_may_act, so a revoked grant cannot be
    // used from a cached answer and a ceiling cannot be read past. An uncovered class routes to the
    // CEO and says so; it never routes to the founder.
    if (action === 'grants') {
      const cls = String(body.action_class || '').trim();
      if (cls) {
        const { data, error } = await admin.rpc('fn_agent_may_act', {
          p_grantee_role_id: 'accountant', p_action_class: cls,
          p_amount_aed: body.amount_aed ?? null,
        });
        if (error) return J({ ok: false, refused: error.message }, 400);
        await run('grants', 'ok', { action_class: cls, amount_aed: body.amount_aed ?? null });
        return J({ ok: true, action_class: cls, ...(data as Record<string, unknown>) });
      }
      const { data } = await admin.from('ceo_standing_grant')
        .select('grant_key,action_class,scope_note,limit_note,max_amount_aed,active,expires_at')
        .eq('grantee_role_id', 'accountant').order('grant_key');
      await run('grants', 'ok', { listed: (data || []).length });
      return J({ ok: true, grants: data || [] });
    }

    // ── LEDGER ─────────────────────────────────────────────────────────────────────────────────
    // Read the books. Four tables, each with its own basis and window — see `book()` above for why
    // a true zero and an unknown must never both print as 0.
    //
    // gl_accounts has no date column: it is the chart of accounts, a catalogue rather than a
    // record of events, so it has a count and honestly no window at all.
    if (action === 'ledger') {
      const books = await Promise.all([
        book('gl_accounts', null),
        book('gl_journal', 'entry_date'),
        book('expenses', 'expense_date'),
        book('ap_bills', 'bill_date'),
      ]);
      const byName = Object.fromEntries(books.map((b) => [String(b.table), b]));
      const unknown = books.filter((b) => b.basis === 'unknown').map((b) => b.table);

      await run('ledger', 'ok', {
        gl_accounts: byName.gl_accounts.rows, gl_journal: byName.gl_journal.rows,
        expenses: byName.expenses.rows, ap_bills: byName.ap_bills.rows,
        unreadable: unknown.length,
      });
      return J({
        ok: true,
        seat: 'accountant',
        caller: caller.kind,
        books: byName,
        unreadable: unknown,
        // Said plainly, because an empty expenses table invites exactly the wrong inference.
        basis: 'Row counts and observed date windows read directly from the four ledger tables at call time. No figure is estimated, no missing figure is defaulted to zero, and no date filter was applied — a window shown here is the observed extent of the data, not a reporting period.',
        note: 'An empty expenses table today means nothing has been filed, NOT that the expenses@mail.quotesdone.com inbox was read and found empty: no handler collects that mailbox yet, so nothing has ever attempted to fill it.',
      });
    }

    // ── REFUND_REQUEST ─────────────────────────────────────────────────────────────────────────
    // "takes approval from CEO on refunds." (founder, 9 September 2026)
    //
    // THE SEAT PREPARES; THE CEO DECIDES. This is not a policy this file implements by declining —
    // it is a policy the DATABASE enforces and this file obeys. accountant.refund_decision carries
    // max_amount_aed = 0, so fn_agent_may_act refuses EVERY refund amount and names the route
    // 'ceo_case_decision'. That refusal is not swallowed and it is not an error: it is the
    // instruction, and it is turned into a real decision request.
    //
    // fn_ceo_request_decision IS REUSED RATHER THAN REPLACED. It already refuses without BOTH a
    // recommendation and evidence, and its refusal text is better than anything invented here, so
    // this handler does not pre-validate either one — it passes them down and returns whatever the
    // database says, verbatim. A second path to the CEO would be a second set of rules to keep in
    // step, and the one that drifted would be this one.
    if (action === 'refund_request') {
      const amount = Number(body.amount_aed);
      if (!Number.isFinite(amount) || amount <= 0) {
        return J({ error: 'amount_aed_required', note: 'A refund with no amount cannot be put to a ceiling, so it cannot be routed either.' }, 400);
      }

      const { data: mayRaw, error: mayErr } = await admin.rpc('fn_agent_may_act', {
        p_grantee_role_id: 'accountant', p_action_class: 'refund', p_amount_aed: amount,
      });
      if (mayErr) {
        await run('refund_request', 'error', { amount_aed: amount }, mayErr.message);
        return J({ ok: false, error: 'grant_check_failed', detail: mayErr.message }, 503);
      }
      const may = (mayRaw || {}) as Record<string, unknown>;

      // THE BRANCH THAT DOES NOT FIRE TODAY, and is here anyway rather than assumed away. Measured
      // 9 Sep 2026: fn_agent_may_act('accountant','refund',1) refuses with route
      // 'ceo_case_decision'. If a future ceiling ever permitted an amount, this seat still would
      // not execute the refund — refunds_api does that, after a decision — so it says exactly that
      // instead of quietly doing nothing or, worse, claiming a refund happened.
      if (may.may_act === true) {
        await run('refund_request', 'ok', { amount_aed: amount, routed: false });
        return J({
          ok: true, seat: 'accountant', routed_to_ceo: false, ...may,
          note: 'The standing grant admitted this amount, so no CEO decision was requested. This function still does not execute refunds; execution lives in refunds_api.',
        });
      }

      // THE EVIDENCE IS ASSEMBLED, NOT ASSERTED. Every field below is either something the caller
      // supplied or something just measured; nothing is inferred. If the caller supplied no
      // evidence of its own the object is still non-empty, which is deliberate: the refusal
      // fn_ceo_request_decision owes a caller is about a MISSING RECOMMENDATION, and burying that
      // behind an empty-evidence refusal would hide the more useful of the two.
      const evidence = {
        amount_aed: amount,
        currency: String(body.currency || 'AED'),
        transaction_id: body.transaction_id ?? null,
        refund_id: body.refund_id ?? null,
        customer_reason: body.reason ?? null,
        // THE REFUSAL VERBATIM, NOT A RESHAPED COPY OF IT. Measured 9 Sep 2026: on a refusal
        // fn_agent_may_act returns {may_act, reason, route} and NOTHING ELSE — `grant` and `limit`
        // exist only on the permit path. An earlier draft named those two keys anyway and recorded
        // grant: null, ceiling_aed: null into the CEO's evidence, which reads as "there is no grant
        // and no ceiling" when the truth is that the refusal does not carry them. Spreading what
        // the database actually returned cannot invent a field it did not send.
        grant_refusal: { ...may },
        prepared_by: 'accountant',
        prepared_at: new Date().toISOString(),
        ...(body.evidence && typeof body.evidence === 'object' ? body.evidence as Record<string, unknown> : {}),
      };

      const caseId = Number(body.case_id);
      const { data: reqRaw, error: reqErr } = await admin.rpc('fn_ceo_request_decision', {
        p_case_id: Number.isFinite(caseId) && caseId > 0 ? caseId : null,
        p_subject: String(body.subject || `Refund of AED ${amount} needs a CEO decision`),
        p_evidence: evidence,
        p_recommendation: String(body.recommendation ?? ''),
        p_idempotency_key: String(body.idempotency_key || `accountant-refund-${body.transaction_id ?? body.refund_id ?? amount}`),
      });
      if (reqErr) {
        await run('refund_request', 'error', { amount_aed: amount }, reqErr.message);
        return J({ ok: false, error: 'decision_request_failed', detail: reqErr.message }, 503);
      }

      const decision = (reqRaw || {}) as Record<string, unknown>;
      // The database's own refusal, returned verbatim and with its own status. It is not an
      // internal error and it is not reshaped into one.
      if (decision.ok !== true) {
        await run('refund_request', 'refused', { amount_aed: amount }, String(decision.reason || 'refused'));
        return J({ ok: false, seat: 'accountant', routed_to_ceo: false, refused_by: 'fn_ceo_request_decision', ...decision }, 400);
      }

      await run('refund_request', 'ok', {
        amount_aed: amount, routed: true,
        report_id: (decision.report as Record<string, unknown> | undefined)?.report_id ?? null,
      });
      return J({
        ok: true,
        seat: 'accountant',
        routed_to_ceo: true,
        amount_aed: amount,
        grant_refusal: evidence.grant_refusal,
        decision_request: decision,
        basis: 'fn_agent_may_act refused this amount against accountant.refund_decision (ceiling 0, the founder\'s ruling rather than a limit awaiting a number) and named the route ceo_case_decision. fn_ceo_request_decision then opened the decision with the evidence and the recommendation. No refund was executed and no case was closed: the CEO receiving it is not the CEO deciding it.',
      });
    }

    // THE KNOWLEDGE HAD NO ENTRY POINT. 113 accountant records were authored, embedded and proved
    // to answer 35 of 35 questions — and nothing could reach them: fn_accountant_assist was granted
    // to nobody and called from nowhere, so the seat that owns the money could not consult its own
    // corpus. A finished capability with no entry point is indistinguishable from an absent one.
    //
    // NO MODEL RUNS HERE. The embedding is gte-small in-region (free, not a paid route), and the
    // answer is ASSEMBLED FROM CITED RECORDS, never generated. That is deliberate for a finance
    // seat: an invented VAT rate reads exactly like a correct one. If nothing clears the floor the
    // seat says so and hands off, rather than improvising an answer about somebody's tax position.
    if (action === 'assist') {
      const question = String(body.question || body.message || '').trim();
      if (!question) return J({ error: 'question_required' }, 400);

      const vec = await embed(question);
      // Past cases before the answer (23 Sep 2026): refunds, classifications, and what other seats
      // finalised on the same subject. Returned as evidence beside the knowledge.
      const memory = await recallCases(admin, { seat: 'accountant', path: 'assist', situation: question, embedding: vec, otherSeats: true });
      const { data, error } = await admin.rpc('fn_accountant_assist', {
        p_text: question,
        p_embedding: vec,
        p_min_similarity: Number(body.min_similarity ?? 0.86),
        p_min_rank: Number(body.min_rank ?? 0.05),
        p_k: Number(body.k ?? 5),
        p_min_overlap: Number(body.min_overlap ?? 0.60),
      });
      if (error) {
        await run('assist', 'error', {}, error.message);
        return J({ ok: false, error: 'retrieval_failed', detail: error.message }, 503);
      }

      const r = (data || {}) as Record<string, unknown>;
      const recs = (r.records || []) as Array<Record<string, unknown>>;
      // Each passage names the record it came from AND what kind of claim it is. A finance answer
      // that does not say whether it is quoting general method, this company's own ruling, or the
      // shape of an obligation whose figures must be read from the FTA is a worse answer than one
      // that does — the corpus deliberately holds no rates, and the reply must not hide that.
      const reply = r.answered === true
        ? recs.map((x) =>
            String(x.title || '(untitled)') + '\n' +
            '[' + String(x.doc_key ?? x.id ?? 'record') +
            (x.epistemic_status ? ' · ' + String(x.epistemic_status) : '') + ']\n' +
            String(x.content)).join('\n\n')
        : String(r.handoff || 'I do not have that in my knowledge, and I will not guess at a figure. This needs to be resolved from the Federal Tax Authority\'s current publication or put to the CEO.');

      await run('assist', 'ok', {
        answered: r.answered === true,
        cited: Array.isArray(r.cited) ? r.cited.length : 0,
        refusal: r.refusal ?? null,
      });

      return J({
        ok: true,
        seat: 'accountant',
        answered: r.answered === true,
        reply,
        precedent: memory,
        cited: r.cited ?? [],
        refusal: r.refusal ?? null,
        basis: 'Retrieved from accountant_knowledge and assembled from the cited records. No model generated this text, and the corpus deliberately holds no tax rate, threshold or deadline — those are read from the Federal Tax Authority for the period concerned.',
      });
    }

    // ── EXECUTE_REFUNDS ────────────────────────────────────────────────────────────────────────
    // (1) Every refund the CEO approved and nobody has sent: to Stripe at refunds.amount_fils (which
    //     a00 holds equal to what the customer paid), then recorded through fn_refund_settle -- the
    //     webhook's own settler -- so the charge, the two messages and the CEO's re-verification follow
    //     from the one door. Held entirely while the CEO's breaker is on.
    // (2) The Stripe fixes the mismatch playbook handed this seat (refund the difference, retry once,
    //     cancel a duplicate). These run while paused: they ARE the fix.
    if (action === 'execute_refunds') {
      const { data: paused } = await admin.rpc('fn_refunds_paused');
      // THE KEY FOLLOWS THE PAYER (14 Sep 2026). Until today one stripe_secret_key (LIVE) was read here
      // and used for every refund and every fix, test payments included. Each payment is now refunded
      // with the key of the mode it was made in, and a payer this seat cannot identify is refused
      // rather than guessed (_shared/stripe_refund.ts reads the payment back and checks livemode).
      const deps = { secret: sec };
      const payerIsDemo = async (customerId: unknown, paymentRef?: unknown, stripeRefundId?: unknown): Promise<boolean | null> => {
        let cid = customerId ? String(customerId) : '';
        if (!cid && paymentRef) cid = String((await admin.from('transactions').select('customer_id').eq('payment_ref', String(paymentRef)).maybeSingle()).data?.customer_id || '');
        if (!cid && stripeRefundId) cid = String((await admin.from('refunds').select('customer_id').eq('stripe_refund_id', String(stripeRefundId)).maybeSingle()).data?.customer_id || '');
        if (!cid) return null;
        const { data: c } = await admin.from('customers').select('email').eq('id', cid).maybeSingle();
        return c ? isDemoEmail(c.email) : null;
      };
      // One refund only, when named (the e2e harness drives a single ZZ DEMO case this way and must
      // never sweep anyone else's approved refund along with it).
      const onlyRefund = body.refund_id != null ? Number(body.refund_id) : null;
      const results: Array<Record<string, unknown>> = [];
      const settle = (refund: Record<string, unknown>, pi: string) => admin.rpc('fn_refund_settle', {
        p_stripe_refund_id: String(refund.id), p_status: String(refund.status || 'processing'),
        p_amount_fils: Number(refund.amount || 0) || null, p_payment_intent: pi, p_amount_source: 'stripe_api',
      });

      if (paused !== true) {
        let aq = admin.from('refunds')
          .select('id,transaction_id,customer_id,supplier_lead_id,amount_fils,stripe_payment_intent,refund_decision_id,status')
          .not('refund_decision_id', 'is', null).in('status', ['requested', 'approved']).is('stripe_refund_id', null);
        if (onlyRefund != null) aq = aq.eq('id', onlyRefund);
        const { data: approved } = await aq.limit(20);
        for (const r of approved || []) {
          // Before Stripe, because afterwards the money is gone: the refunds guard refuses 'processing'
          // before the transaction's refund_deadline, and a refund paid but unrecordable is the worst case.
          const { data: tr } = await admin.from('transactions').select('refund_deadline').eq('id', r.transaction_id).maybeSingle();
          if (tr?.refund_deadline && Date.now() < new Date(tr.refund_deadline).getTime()) {
            results.push({ refund_id: r.id, error: 'refund_window_not_yet_open', decision_after: tr.refund_deadline }); continue;
          }
          // THE ONE DECISION (29 Sep 2026): a CEO-decided refund still 'requested' is approved here through
          // fn_refund_decide, which runs the second-seat check. The database refuses paying it from 'requested'
          // (z04_refund_approval_is_the_one_decision), so this is asked before Stripe, never after.
          if (r.status === 'requested') {
            const { data: dec, error: decErr } = await admin.rpc('fn_refund_decide', { p_refund_id: r.id, p_approve: true, p_decided_by: 'ceo' });
            if (decErr || dec?.ok !== true) { results.push({ refund_id: r.id, error: 'not_approved', decide: decErr?.message ?? dec }); continue; }
          }
          // THE SCREEN BEFORE MONEY MOVES (29 Sep 2026, founder ledger 1018). A high-severity fraud flag on the
          // customer or the supplier holds the refund for review: nothing is sent, nobody is banned, and
          // customer_support tells the customer. Fail closed: a screen that cannot answer sends nothing either.
          const { data: scr, error: scrErr } = await admin.rpc('fn_accountant_money_screen', {
            p_move: 'refund', p_ref: String(r.id), p_customer: r.customer_id ?? null, p_supplier: r.supplier_lead_id ?? null });
          if (scrErr) { results.push({ refund_id: r.id, error: 'money_screen_failed: ' + String(scrErr.message || scrErr).slice(0, 300) }); continue; }
          if (scr?.hold === true) { results.push({ refund_id: r.id, held: 'fraud_review', hold_id: scr.hold_id }); continue; }
          const demo = await payerIsDemo(r.customer_id, r.stripe_payment_intent);
          if (demo === null) { results.push({ refund_id: r.id, error: 'payer_unknown: the Stripe mode of this payment cannot be known, nothing sent' }); continue; }
          const res = await stripeRefund(deps, { demoPayer: demo, ref: String(r.stripe_payment_intent || ''), amountFils: Number(r.amount_fils), idem: refundIdempotencyKey(String(r.transaction_id)),
            metadata: { refund_id: String(r.id), transaction_id: String(r.transaction_id || ''), approved_by: 'ceo' } });
          if (!res.ok) { results.push({ refund_id: r.id, error: res.error }); continue; }
          await admin.from('refunds').update({ status: 'processing', stripe_refund_id: String(res.refund.id) }).eq('id', r.id).is('stripe_refund_id', null);
          await settle(res.refund, res.pi);
          results.push({ refund_id: r.id, stripe_refund_id: res.refund.id, status: res.refund.status, mode: res.mode });
        }
      }

      // A single named refund (the harness) never picks up anyone's incident fixes.
      const { data: fixes } = onlyRefund != null ? { data: [] } : await admin.from('agent_actions').select('id,detail')
        .eq('kind', 'handoff').eq('agent', 'accountant').eq('status', 'pending').filter('detail->>type', 'eq', 'incident.fix').limit(20);
      for (const f of fixes || []) {
        const d = (f.detail || {}) as Record<string, unknown>;
        const firstRefundId = Array.isArray(d.refund_ids) ? (d.refund_ids as string[])[0] : undefined;
        const demo = await payerIsDemo(null, d.payment_ref, firstRefundId);
        if (demo === null) {
          await admin.rpc('fn_accountant_incident_fix_failed', { p_id: f.id, p_reason: 'the paying customer is not on record, so the Stripe mode of the payment cannot be known; nothing was sent' });
          results.push({ fix: f.id, error: 'payer_unknown' }); continue;
        }
        if (d.fix === 'refund_difference' || d.fix === 'retry_refund') {
          // ONE RAIL FOR THE PLAYBOOK TOO (PR #640 re-review, 14 Sep 2026). Until today these sent a
          // refund to Stripe under 'qd_incident_<fix>' and only recorded it afterwards; fn_refund_settle
          // then filed the top-up as an external row with no transaction, outside every per-payment
          // guard. Now the money is RESERVED on public.refunds first, through every guard on the table
          // (the window, the CEO decision, and a01's cap: never more than the customer paid), and only
          // then sent, under a key rooted in the transaction. A refusal releases the reservation.
          const txId = String(d.transaction_id || '');
          const failFix = async (why: string) => { await admin.rpc('fn_accountant_incident_fix_failed', { p_id: f.id, p_reason: why.slice(0, 500) }); results.push({ fix: f.id, error: why }); };
          let rowId = 0, amount = 0, idem = '';
          if (d.fix === 'refund_difference') {
            const { data: rv, error: rvErr } = await admin.rpc('fn_accountant_reserves_topup',
              { p_transaction_id: txId, p_amount_fils: Number(d.amount_fils || 0), p_fix_id: f.id });
            if (rvErr || !rv?.ok) { await failFix(rvErr?.message || String(rv?.reason || 'the top-up could not be reserved')); continue; }
            rowId = Number(rv.refund_id); amount = Number(rv.amount_fils); idem = refundIdempotencyKey(txId, 'topup' + rowId);
          } else {
            rowId = Number(d.refund_id);
            const { data: rr, error: rrErr } = await admin.from('refunds').update({ status: 'processing' })
              .eq('id', rowId).eq('status', 'failed').select('amount_fils').maybeSingle();
            if (rrErr || !rr) { await failFix(rrErr?.message || 'refund #' + rowId + ' is not a failed refund that can be retried'); continue; }
            amount = Number(rr.amount_fils); idem = refundIdempotencyKey(txId, 'retry' + f.id);
          }
          const res = await stripeRefund(deps, { demoPayer: demo, ref: String(d.payment_ref || ''), amountFils: amount, idem,
            metadata: { incident_id: String(d.incident_id || ''), fix: String(d.fix), refund_id: String(rowId) } });
          // deno-lint-ignore no-explicit-any
          let sent: { refund: any; pi: string };
          if (res.ok) sent = { refund: res.refund, pi: res.pi };
          else {
            // NEVER RELEASE BLIND (re-review): a timeout or a 5xx may have moved the money. Stripe is
            // asked what exists under our key first; only a confirmed refusal releases the reservation.
            const out = await confirmRefundOutcome(deps, { demoPayer: demo, ref: String(d.payment_ref || ''), idem }, res);
            if (out.outcome === 'hold') {
              // Reservation kept and the fix left pending: the next run resends under the SAME key, so
              // Stripe returns the original refund if it exists and creates it once if it does not.
              results.push({ fix: f.id, refund_id: rowId, held: true, error: out.error }); continue;
            }
            if (out.outcome === 'release') {
              await admin.from('refunds').update({ status: d.fix === 'retry_refund' ? 'failed' : 'cancelled', failure_reason: out.error.slice(0, 500) })
                .eq('id', rowId).eq('status', d.fix === 'retry_refund' ? 'processing' : 'requested');
              await failFix(out.error); continue;
            }
            sent = { refund: out.refund, pi: out.pi };
          }
          await admin.from('refunds').update({ status: 'processing', stripe_refund_id: String(sent.refund.id) }).eq('id', rowId);
          // Recorded first, so the re-verification the completion triggers already sees this money.
          await settle(sent.refund, sent.pi);
          await admin.rpc('fn_seat_handoff_complete', { p_id: f.id, p_evidence: { stripe_refund_id: sent.refund.id, amount_fils: sent.refund.amount, status: sent.refund.status } });
          results.push({ fix: f.id, stripe_refund_id: sent.refund.id });
        } else if (d.fix === 'cancel_duplicate') {
          const ids = Array.isArray(d.refund_ids) ? (d.refund_ids as string[]).slice(1) : [];
          const k = await refundKey(deps, demo);
          if (!k.ok) { await admin.rpc('fn_accountant_incident_fix_failed', { p_id: f.id, p_reason: k.error }); results.push({ fix: f.id, error: k.error }); continue; }
          let cancelled = 0; let lastErr = '';
          for (const rid of ids) {
            const cr = await fetch('https://api.stripe.com/v1/refunds/' + encodeURIComponent(rid) + '/cancel',
              { method: 'POST', headers: { Authorization: 'Bearer ' + k.sk } });
            const cj = await cr.json().catch(() => ({}));
            if (cr.ok) cancelled++; else lastErr = String(cj?.error?.message || cr.status);
          }
          if (ids.length && cancelled === ids.length) await admin.rpc('fn_seat_handoff_complete', { p_id: f.id, p_evidence: { cancelled: ids } });
          else await admin.rpc('fn_accountant_incident_fix_failed', { p_id: f.id, p_reason: 'Stripe would not cancel the duplicate: ' + (lastErr || 'nothing to cancel') });
          results.push({ fix: f.id, cancelled, of: ids.length });
        }
      }
      await run('execute_refunds', 'ok', { executed: results.length, paused: paused === true });
      return J({ ok: true, seat: 'accountant', paused: paused === true, results });
    }

    // ── HANDOFFS ───────────────────────────────────────────────────────────────────────────────
    // What the sales engineer and the CEO handed this seat and it has not closed, and the door to
    // close one with evidence (a remediation that needed a person, a Stripe fix done by hand).
    if (action === 'handoffs') {
      const { data } = await admin.from('agent_actions').select('id,status,title,detail,evidence,created_at')
        .eq('kind', 'handoff').eq('agent', 'accountant').neq('status', 'done').order('id').limit(100);
      return J({ ok: true, seat: 'accountant', open: data || [] });
    }
    if (action === 'complete_handoff') {
      const { data: h } = await admin.from('agent_actions').select('id,agent').eq('id', Number(body.id)).eq('kind', 'handoff').maybeSingle();
      if (!h || h.agent !== 'accountant') return J({ error: 'not_this_seats_handoff' }, 404);
      const { data, error } = await admin.rpc('fn_seat_handoff_complete', { p_id: Number(body.id), p_evidence: body.evidence ?? {} });
      if (error) return J({ ok: false, error: error.message }, 400);
      await run('complete_handoff', 'ok', { handoff_id: Number(body.id) });
      return J(data);
    }

    // ── EXPENSE_SWEEP ──────────────────────────────────────────────────────────────────────────
    // THE HISTORICAL SWEEP. Deterministic end to end: not one model call on this path.
    //
    // It is IDEMPOTENT on the same key the live webhook uses. expense_entries.source_msg_id is
    // 'resend:<email_id>' and carries a plain unique index, and the lookup below is UNFILTERED BY
    // STATUS — a row holding the key wins outright whatever state it is in, which is the
    // fn_agent_action_work_sweep trap avoided (a status-filtered guard over a unique key says "go
    // ahead", the insert then violates the index, and the work is lost with no record of why).
    // Run it twice and the second run books nothing; run it against a mailbox the webhook has
    // already drained and it books nothing either.
    //
    // NOTHING IS EVER GUESSED. A message whose amount cannot be read is archived, recorded as an
    // inbound_messages row, and handed to this seat as a task by fn_receipt_hand_to_bookkeeper,
    // with the reason in words. It is never booked at zero, never estimated from a sibling receipt,
    // and never quietly dropped — spend_report counts it as HELD so the total says it is short.
    if (action === 'expense_sweep') {
      const rkey = await sec('resend_api_key');
      if (!rkey) {
        await run('expense_sweep', 'error', {}, 'app_secrets.resend_api_key is unreadable, so the mailbox history could not be listed. Nothing was swept.');
        return J({ ok: false, error: 'resend_api_key_unavailable' }, 503);
      }
      const dryRun = body.dry_run === true;
      const maxPages = Math.min(Number(body.max_pages) || 20, 50);

      // THE ALLOWLIST IS THE WEBHOOK'S, READ FROM THE SAME PLACE. Widening it here would create a
      // second policy to keep in step with resend_inbound, and the one that drifted would be this.
      const adminList = String(await sec('admin_emails') || 'management@quotesdone.com').toLowerCase().split(',').map((x) => x.trim()).filter(Boolean);
      const fwdList = String(await sec('expense_forwarders') || '').toLowerCase().split(',').map((x) => x.trim()).filter(Boolean);
      const allowed = new Set([...adminList, ...fwdList]);

      const R = (u: string) => fetch(u, { headers: { Authorization: 'Bearer ' + rkey } });

      // 1. THE WHOLE HISTORY, PAGED. `has_more` is Resend's own answer, not an inference from a
      //    short page; the loop stops on it, and pages_capped says so when the cap stopped it instead.
      const history: Record<string, unknown>[] = [];
      let after: string | null = null; let pages = 0; let capped = false; let listError = '';
      for (;;) {
        const u = new URL('https://api.resend.com/emails/inbound');
        u.searchParams.set('limit', '100');
        if (after) u.searchParams.set('after', after);
        const r = await R(u.toString());
        // deno-lint-ignore no-explicit-any
        const j: any = await r.json().catch(() => ({}));
        pages++;
        if (!r.ok) { listError = 'HTTP ' + r.status + ' ' + JSON.stringify(j).slice(0, 200); break; }
        const items = (j.data || j.items || []) as Record<string, unknown>[];
        history.push(...items);
        if (!j.has_more || !items.length) break;
        after = String(items[items.length - 1].id);
        if (pages >= maxPages) { capped = true; break; }
      }
      if (listError && !history.length) {
        await run('expense_sweep', 'error', { pages }, 'the Resend inbound history could not be listed (' + listError + '). Nothing was swept, and no total may be read as complete.');
        return J({ ok: false, error: 'history_unreadable', detail: listError }, 502);
      }

      const toList = (v: unknown): string[] => (Array.isArray(v) ? v : [v]).map((x) => String(x || '').toLowerCase().trim()).filter(Boolean);
      // body.email_id narrows the sweep to ONE message (reprocessing a single email after a fix).
      const only = String(body.email_id || '').trim();
      const mine = history.filter((m) => toList(m.to).some((a) => a === EXPENSE_MAILBOX || a.split('@')[0] === 'expenses'))
        .filter((m) => !only || String(m.id) === only);

      // The reasoning's context, once per sweep: the vendors and register the books carry, and the renewals.
      const booksDeps = defaultDeps(admin, 'accountant');
      const { data: booksCtx } = await admin.rpc('fn_accountant_reading_context');
      const booksVendors: string[] = Array.isArray(booksCtx?.vendors) ? booksCtx.vendors : [];
      const booksRegister = Array.isArray(booksCtx?.register) ? booksCtx.register : [];
      const booksRenewals = Array.isArray(booksCtx?.renewals) ? booksCtx.renewals : [];

      const results: Record<string, unknown>[] = [];
      let booked = 0, already = 0, held = 0, refused = 0, failed = 0;

      for (const h of mine) {
        const emailId = String(h.id || '');
        const msgKey = 'resend:' + emailId;
        const from = String(h.from || '').toLowerCase().trim();
        const to = toList(h.to)[0] || EXPENSE_MAILBOX;
        const subject = String(h.subject || '').slice(0, 300);
        const seenAt = String(h.created_at || '');
        const say = (verdict: string, extra: Record<string, unknown> = {}) =>
          results.push({ email_id: emailId, received_at: seenAt, from, subject, verdict, ...extra });

        // ALREADY BOOKED wins before anything else is fetched. Unfiltered by status, deliberately.
        const { data: prior } = await admin.from('expense_entries')
          .select('id,vendor,amount,currency,charged_on,doc_path').eq('source_msg_id', msgKey).limit(1);
        if (prior && prior.length) {
          already++;
          say('already_booked', { entry_id: prior[0].id, vendor: prior[0].vendor, amount: prior[0].amount, currency: prior[0].currency, charged_on: prior[0].charged_on });
          continue;
        }

        // THE SENDER GATE, BEFORE ANY EXTRACTION. Same rule, same source, same reason as the
        // webhook: mail to the expenses mailbox from someone who is not a permitted forwarder is a
        // decision somebody should see, not silence — so it is RECORDED and handed over, not dropped.
        if (!allowed.has(from)) {
          refused++;
          if (!dryRun) {
            const { data: refusedRow } = await admin.from('inbound_messages').insert({
              from_email: from, to_email: to, subject,
              body: '[REFUSED — sender is not on app_secrets.expense_forwarders] found by the accountant historical sweep; nothing was booked and no document was stored. Resend inbound id ' + emailId,
              attachments_count: 0, matched_existing: false, needs_review: true,
            }).select('id').maybeSingle();
            if (refusedRow?.id) {
              await admin.rpc('fn_receipt_hand_to_bookkeeper', { p_inbound_id: refusedRow.id, p_review_ids: [], p_reason: ('Historical sweep: mail to ' + to + ' from ' + from + ' on ' + seenAt + ' was REFUSED because that address is not on app_secrets.expense_forwarders. Nothing was booked. Decide whether this sender should be added; if it is a company expense, add them and re-run the sweep.').slice(0, 600) });
            }
          }
          say('refused_sender_not_allowlisted');
          continue;
        }

        // 2. THE MESSAGE ITSELF. The list endpoint carries no body, so the full message is fetched
        //    for its text and its attachments.
        const fr = await R('https://api.resend.com/emails/inbound/' + emailId);
        if (!fr.ok) {
          failed++;
          say('unreadable_message', { detail: 'GET /emails/inbound/' + emailId + ' returned HTTP ' + fr.status });
          continue;
        }
        // deno-lint-ignore no-explicit-any
        const fj: any = await fr.json().catch(() => ({}));
        // deno-lint-ignore no-explicit-any
        const d: any = fj.data || fj;
        const text = String(pickBody(d) || '').slice(0, 8000);

        // 3. THE DOCUMENT. Fetched through safeFetch (the download URL comes out of a response
        //    body, and this runs on the service-role network), sanitised by magic bytes, and read
        //    with pdf_text — which returns '' rather than glyph noise, so a scanned receipt is
        //    honestly unreadable instead of confidently wrong.
        const atts: Record<string, unknown>[] = Array.isArray(d.attachments) ? d.attachments : (Array.isArray(h.attachments) ? h.attachments as Record<string, unknown>[] : []);
        let att: { bytes: Uint8Array; name: string; mime: string; ext: string } | null = null;
        const fileNotes: string[] = [];
        // A BANK STATEMENT IS NOT A RECEIPT (14 Sep 2026, duty 1). It is read into bank_statement_line
        // for the payout reconciliation and never booked as an expense. A CSV export (the .csv extension is a
        // file-format fact) is read as text only (it is parsed, not stored) and used only if the message is
        // REASONED to be a statement; the PDF goes through the same sanitiser as any receipt.
        let csvText = '';
        for (const a of atts.slice(0, 8)) {
          const fn = String(a.filename || a.name || '');
          const mm = String(a.content_type || a.contentType || '');
          if (/\.csv$/i.test(fn) && !csvText) {
            const car = await R('https://api.resend.com/emails/inbound/' + emailId + '/attachments/' + a.id);
            // deno-lint-ignore no-explicit-any
            const caj: any = car.ok ? await car.json().catch(() => ({})) : {};
            const curl = String((caj.data || caj).download_url || (caj.data || caj).url || '');
            const cgot = curl ? await safeFetch(curl, { timeoutMs: 15_000, maxBytes: 5 * 1024 * 1024 }) : null;
            if (cgot && cgot.ok) csvText = new TextDecoder().decode(cgot.bytes);
            else fileNotes.push(fn + ': statement CSV could not be fetched');
            continue;
          }
          if (!(/pdf|^image\//i.test(mm) || /\.(pdf|jpe?g|png|webp)$/i.test(fn))) continue;
          const ar = await R('https://api.resend.com/emails/inbound/' + emailId + '/attachments/' + a.id);
          if (!ar.ok) { fileNotes.push(fn + ': attachment endpoint returned HTTP ' + ar.status); continue; }
          // deno-lint-ignore no-explicit-any
          const aj: any = await ar.json().catch(() => ({}));
          const ao = aj.data || aj;
          const url = String(ao.download_url || ao.url || '');
          if (!url) { fileNotes.push(fn + ': no download url'); continue; }
          const got = await safeFetch(url, { timeoutMs: 15_000, maxBytes: 25 * 1024 * 1024 });
          if (!got.ok) { fileNotes.push(fn + ': ' + got.error + ' ' + String(got.detail || '')); continue; }
          const sc = await sanitizeAndScan({ input: got.bytes, declaredMime: mm, filename: fn, allow: SAFE_UPLOAD,
                                             scan: { source: 'accountant.receipt_sweep', subject: String(from || ''), filename: fn, bucket: 'receipt-files' } });
          if (!sc.ok) { fileNotes.push(fn + ': refused (' + sc.body.error + ': ' + sc.body.detail + ')'); continue; }
          const san = sc.result;
          fileNotes.push(fn + ': ' + san.bytes.length + ' bytes');
          att = { bytes: san.bytes, name: fn || ('receipt.' + san.ext), mime: san.mime, ext: san.ext };
          if (san.mime === 'application/pdf') break;   // the PDF is the receipt; an image is a fallback
        }
        let docText = '';
        let readNote = '';
        if (att && att.mime === 'application/pdf') {
          docText = await pdfText(att.bytes);
          if (!docText) readNote = 'The attached PDF carries no text layer we can trust — scanned, or a font we cannot map — so nothing was read from the file. ';
        } else if (att) {
          readNote = 'The receipt is an image, which has no text layer. ';
        }
        // RULING 1177 (12 Oct 2026): a scanned PDF or a photographed receipt is READ by the vision model (_shared/
        // read_every_attachment: one more asking, the gateway's second model). Held only when both askings fail.
        if (att && !docText) {
          const seen = await readEveryAttachment(att.bytes, att.name, att.mime, envGatewayVision());
          if (seen.status === 'read') { docText = seen.text.slice(0, 8000); readNote = ''; }
          else readNote += 'The vision model could not read it either (' + String(seen.reason || 'no answer').slice(0, 80) + '), so it is held for a clearer copy. ';
        }
        // THE STATEMENT'S TABLE NEEDS ITS ROWS (14 Sep 2026). Measured on the founder's real Mashreq
        // e-statement: pdf_text returns '' for it (its Arabic captions are glyph noise, correctly refused by
        // looksLikeText), and its filename and forwarder name no bank. The positioned reader rebuilds the rows;
        // that text is used ONLY to recognise and read a statement — a receipt keeps pdf_text's guard.
        // One recogniser and one intake for this sweep AND the live webhook (_shared/bank_statement_intake.ts).
        // WHAT IS IT (23 Sep 2026, founder_instruction 886-903): reasoned over the envelope, the note and the
        // document's rows (_shared/reasoned_books.ts documentKind), never a word test. Held: not booked, held.
        const rowText = att && att.mime === 'application/pdf' ? await statementRowText(att) : '';
        const mail: ExpenseMail = { emailId, from, to, subject, text, docText: [rowText || docText, csvText.slice(0, 2000)].filter(Boolean).join('\n').slice(0, 4000),
          filenames: atts.map((a) => String(a.filename || a.name || '')), mailbox: 'expenses', providerEmailId: emailId, dryRun };
        const kind = (await documentKind(booksDeps, mail, booksRenewals, booksRegister)).value;
        if (kind === 'bank_statement') {
          const stIn = await takeInStatement(admin, {
            from, subject, filenames: mail.filenames,
            pdf: att && att.mime === 'application/pdf' ? att : null, csvText, docText, rowText, readNote,
            sourceRef: msgKey, archivePath: 'bank/' + seenAt.slice(0, 10) + '/' + emailId, dryRun });
          say(stIn.error ? 'bank_statement_failed' : 'bank_statement', { ...stIn, files: fileNotes });
          continue;
        }
        // Waiting for reasoning: the accountant's queue owns it (expense_kind:<email id>) and replays this sweep for it.
        // Nothing is recorded or handed over twice meanwhile, however often the sweep runs.
        if (kind === null) { held++; say('awaiting_reasoning', { files: fileNotes }); continue; }
        else if (kind === 'other') readNote += "Reasoned: this is not a document of the company's own spending. ";
        // The PDF text is APPENDED, so the forwarded "From:" header still names the original vendor
        // and a figure in the covering note still wins over one in the file.
        const parseBody = docText ? (text + '\n' + docText) : text;

        // Who issued it and how often it bills are REASONED; the figures are parsed. No amount: no model call.
        const reading = kind ? readingOf(kind) : null;
        let det: ReturnType<typeof parseReceipt> = null;
        if (reading && (parseAmount(parseBody) || parseAmount(subject))) {
          const vendor = (await receiptVendor(booksDeps, { ...mail, docText: docText.slice(0, 4000) }, booksVendors)).value;
          if (vendor) det = parseReceipt({ subject, body: parseBody, vendor, period: reading.period });
          else { held++; say('awaiting_reasoning', { files: fileNotes }); continue; }
        } else if (reading) {
          readNote += 'No amount could be read beside a currency mark. ';
        }

        // 4a. HELD. Named, archived, owned. Never a number.
        if (!det) {
          held++;
          const why = readNote + 'It is NOT booked and NOT estimated.';
          if (dryRun) { say('held', { reason: why, files: fileNotes }); continue; }
          let heldPath: string | null = null;
          if (att) {
            const hp = 'held/' + seenAt.slice(0, 10) + '/' + Date.now() + '_' + (subject || 'receipt').replace(/[^A-Za-z0-9._-]/g, '_').slice(0, 60) + '.' + att.ext;
            const up = await admin.storage.from('receipt-files').upload(hp, att.bytes, { contentType: att.mime, upsert: true });
            if (!up.error) heldPath = hp;
          }
          const { data: heldRow } = await admin.from('inbound_messages').insert({
            from_email: from, to_email: to, subject,
            body: '[HELD — nothing booked: ' + readNote.slice(0, 200) + '] accountant historical sweep, Resend inbound id ' + emailId + (heldPath ? ', document: receipt-files/' + heldPath : ' (no readable attachment)') + '\n\n' + text.slice(0, 8000),
            attachments_count: heldPath ? 1 : 0, matched_existing: false, needs_review: true,
          }).select('id').maybeSingle();
          if (heldRow?.id) {
            await admin.rpc('fn_receipt_hand_to_bookkeeper', { p_inbound_id: heldRow.id, p_review_ids: [], p_reason: (why + (heldPath ? ' The document is archived at receipt-files/' + heldPath + '. Read it, then book the expense in expense_entries with source_msg_id ' + msgKey + ' and post it with fn_expense_post_to_gl.' : ' No attachment could be read, so ask for a re-forward.')).slice(0, 600) });
          }
          say('held', { reason: why, document: heldPath, files: fileNotes, inbound_id: heldRow?.id ?? null });
          continue;
        }

        // 4b. BOOKED.
        const vendor = String(det.vendor).slice(0, 120);
        const amount = Number(det.amount);
        const currency = String(det.currency).toUpperCase().replace(/[^A-Z]/g, '').slice(0, 3) || 'USD';
        const charged = det.date;
        const cad = det.period === 'annual' ? 'annual' : (det.period === 'one_off' ? 'one_off' : 'monthly');
        const recurring = det.recurring;
        const vatAmt = det.vat !== null && det.vat > 0 && det.vat < amount ? det.vat : null;
        const trn = /^\d{15}$/.test(String(det.trn || '')) ? String(det.trn) : null;

        if (dryRun) {
          booked++;
          say('would_book', { vendor, amount, currency, charged_on: charged, period: cad, vat: vatAmt, trn, basis: det.basis, files: fileNotes });
          continue;
        }

        // The evidence, archived where the accountant looks for it. A booking is NOT blocked by a
        // failed archive — an expense with no document is a VAT-record gap, an unbooked expense is
        // a hole in the accounts — but the failure is said out loud rather than swallowed.
        // 9 SEP 2026 — AND IT IS A DOCUMENT, NOT A .HTML BLOB. The founder: "i wanna be able to
        // click any record and see the actual invoice or receipt or email print pdf if none exist".
        // The vendor's own attachment is the document when there is one; when there is not, the
        // email is PRINTED TO PDF rather than dumped as raw HTML, and doc_kind records which of the
        // two this row holds so the OS never has to infer provenance from a filename. The HTML
        // upload survives only as the fallback-of-the-fallback: a pdf_native outage must degrade
        // the document, never lose the email.
        let docPath: string | null = null; let upErr = '';
        let docName = att ? att.name : 'receipt.html';
        let docType = att ? att.mime : 'text/html';
        let docKind: 'vendor_document' | 'email_print' = att ? 'vendor_document' : 'email_print';
        let docNote: string | null = att
          ? "The vendor's own file, taken off the source email (Resend inbound " + emailId + ').'
          : null;
        let printBytes: Uint8Array | null = null;
        if (!att) {
          const printed = await emailPrintPdf(admin, SUPA_URL, {
            entryId: null, vendor, amount, currency, chargedOn: charged,
            sourceMsgId: msgKey, subject, from, to, date: seenAt,
            text, html: String(d.html || ''), attachmentNames: [],
          });
          if (printed.ok) {
            docPath = printed.path;            // pdf_native NAMED this path; used exactly as returned
            docName = printed.name; docType = 'application/pdf';
            docNote = 'The source email carried no vendor file, so this is a PDF print of the email itself.';
          } else {
            const html = String(d.html || text || subject);
            printBytes = new TextEncoder().encode('<meta charset="utf-8"><pre style="font:14px/1.5 monospace;white-space:pre-wrap">' + html.replace(/</g, '&lt;') + '</pre>');
            docNote = 'The source email carried no vendor file, and the email could not be printed to PDF ('
              + printed.reason + '), so the message body is archived as HTML instead.';
          }
        }
        const uploadBytes = att ? att.bytes : printBytes;
        const ext = att ? att.ext : 'html';
        if (uploadBytes && !docPath) {
          for (let attempt = 1; attempt <= 3 && !docPath; attempt++) {
            const rp = 'receipts/' + charged + '/' + Date.now() + '_' + vendor.replace(/[^A-Za-z0-9._-]/g, '_') + '.' + ext;
            try {
              const up = await admin.storage.from('receipt-files').upload(rp, uploadBytes, { contentType: docType, upsert: true });
              if (!up.error) docPath = rp; else upErr = String(up.error.message || '').slice(0, 150);
            } catch (e) { upErr = String((e as Error)?.message || e).slice(0, 150); }
            if (!docPath && attempt < 3) await new Promise((r) => setTimeout(r, 400 * attempt));
          }
        }

        // HOW WAS A RECEIPT LIKE THIS CLASSIFIED BEFORE? (23 Sep 2026.) By meaning, this seat's own
        // finalised classifications only. A precedent that was CORRECTED (re-classified by hand) wins
        // over the default rule, and the entry says which case it followed.
        const situation = `vendor ${vendor} | ${currency} ${amount} | ${subject}`;
        const memory = await recallCases(admin, { seat: 'accountant', path: 'expense_classification', caseKind: 'expense_classification',
          otherSeats: false, situation, embedding: await embed(situation) });
        const precedentCase = memory.cases.find((c) => c.finalised && c.correction && c.outcome);
        const category = precedentCase?.outcome ?? (recurring ? 'Subscription' : 'Usage');
        const { data: insRow } = await admin.from('expense_entries')
          .upsert({
            vendor, category, amount, currency, charged_on: charged,
            note: ('accountant historical sweep of the expenses mailbox: ' + subject + ' [' + det.basis + (docText ? ' src=pdf_text' : '')
              + (precedentCase ? ' precedent=#' + precedentCase.case_id : '') + ']').slice(0, 300),
            source: 'receipt', doc_path: docPath, doc_name: docName.slice(0, 180), doc_content_type: docType,
            doc_kind: docPath ? docKind : null, doc_note: docPath ? docNote : null,
            source_msg_id: msgKey, vat_amount: vatAmt, vendor_trn: trn, read_as: reading?.readAs ?? null, renews_item: reading?.renewsItem ?? null,
          }, { onConflict: 'source_msg_id', ignoreDuplicates: true })
          .select('id').maybeSingle();
        let entryId: number | null = (insRow?.id as number | undefined) ?? null;
        if (!entryId) {
          // a concurrent webhook delivery won the unique key between the lookup and this insert;
          // read its row rather than inventing a second expense
          const { data: won } = await admin.from('expense_entries').select('id').eq('source_msg_id', msgKey).limit(1);
          entryId = (won?.[0]?.id as number | undefined) ?? null;
        }
        if (!entryId) { failed++; say('book_failed', { vendor, amount, currency, charged_on: charged }); continue; }
        // The classification's judgement names the corrected precedent it followed (or none), in the trace
        // rather than only in the note text.
        await decideJudgement(admin, memory, `expense ${entryId} classified ${category}`, precedentCase ? [precedentCase.case_id] : []);

        // THE LEDGER. Nothing calls fn_gl_sync_business on a schedule, so the entry is posted here
        // under source='expense'/source_ref — the same key the bulk routine uses, so neither can
        // double-post the other. A currency with no rate is NOT booked at 1:1: the routine returns
        // null and raises a founder_alert, and this sweep reports the null rather than hiding it.
        const { data: jid, error: glErr } = await admin.rpc('fn_expense_post_to_gl', { p_entry_id: entryId });
        if (docPath) {
          // doc_backups is the Sales Engineer's existing filing contract and dropbox_backup reads
          // it by status, not by entity; dedupe_key makes a re-sweep a no-op.
          await admin.from('doc_backups').insert({
            entity: 'expense', entity_id: String(entryId), doc_type: 'Receipt',
            bucket: 'receipt-files', path: docPath, file_name: docName.slice(0, 180),
            dropbox_path: '/QuotesDone Backup/Finance/Receipts/' + charged.slice(0, 7) + '/' + dbxSafe(vendor) + ' ' + charged + ' - ' + dbxSafe(docName),
            source: 'storage', dedupe_key: 'E:' + entryId + ':receipt:' + docPath,
          });
        }
        if (recurring) {
          const erow = { vendor, category: 'Subscription', description: subject.slice(0, 300), amount, currency, cadence: cad, expense_date: charged, active: true, source: 'email_forward', confidence: 'medium', note: 'from the accountant historical sweep of the expenses mailbox' };
          // The register row is the SAME vendor (identity of the reasoned name), never a LIKE pattern (instr 890).
          const ex0 = await registerRowsFor(admin, vendor);
          // The register holds the CURRENT schedule, so only a LATER receipt may move it. The
          // history arrives newest-first, so without this an August receipt would overwrite September.
          if (ex0 && ex0.length) { if (!ex0[0].expense_date || String(ex0[0].expense_date) <= charged) await admin.from('expenses').update(erow).eq('id', ex0[0].id); }
          else await admin.from('expenses').insert(erow);
        }
        await admin.from('inbound_messages').insert({
          from_email: from, to_email: to, subject,
          body: '[expense ' + (recurring ? 'subscription' : 'one-off') + '] ' + vendor + ' ' + amount + ' ' + currency + ' on ' + charged + (docPath ? ' +' + ext : '') + ' — accountant historical sweep, Resend inbound id ' + emailId,
          attachments_count: docPath ? 1 : 0, matched_existing: false, needs_review: false,
        });
        booked++;
        say('booked', {
          entry_id: entryId, vendor, amount, currency, charged_on: charged, period: cad,
          vat: vatAmt, trn, gl_journal: (jid as number | null) ?? null,
          gl_error: glErr ? String(glErr.message).slice(0, 200) : null,
          document: docPath, document_error: docPath ? null : upErr, basis: det.basis, files: fileNotes,
        });
      }

      const counts = {
        history_messages: history.length, to_expense_mailbox: mine.length,
        booked, already_booked: already, held, refused, failed,
        pages, pages_capped: capped, list_error: listError || null, dry_run: dryRun,
      };
      // agent_runs IS the coverage record spend_report quotes. Without it the report could say how
      // much was booked but not how much was LOOKED AT, and a total nobody can bound is not a total.
      await run('expense_sweep', (failed || listError) ? 'error' : 'ok', counts,
        'Swept the Resend inbound history: ' + history.length + ' messages in total, ' + mine.length + ' addressed to ' + EXPENSE_MAILBOX + '. Booked ' + booked + ', already booked ' + already + ', held ' + held + ', refused ' + refused + ', failed ' + failed + '.' + (capped ? ' PAGING WAS CAPPED, so the history may be incomplete.' : '') + (listError ? ' Listing error: ' + listError : ''));

      return J({
        ok: true, seat: 'accountant', caller: caller.kind, mailbox: EXPENSE_MAILBOX, ...counts, messages: results,
        // body.email_id that matched no message to the mailbox is said, so a replay never reads "delivered" for nothing
        found: only ? mine.length > 0 : undefined,
        basis: 'What each message is and who issued it were reasoned (supabase/functions/_shared/reasoned_books.ts, through think()); every figure was read from the message by supabase/functions/_shared/receipt_parse.ts and, where a PDF carried a text layer, supabase/functions/_shared/pdf_text.ts. A message whose meaning waits for reasoning, or whose amount could not be read, is counted as held and named in `messages`; it is never booked at zero and never estimated.',
      });
    }
    // ── SPEND_REPORT ───────────────────────────────────────────────────────────────────────────
    // "let him send me a report of all what we spent since day 1 by trailing the whole inbox"
    // (the founder, 9 Sep 2026).
    //
    // THE SEAT SENDS IT, NOT A SESSION. He asked for this as a TEST of the agent, so the document
    // is rendered by the seat's own credential and the mail is inserted by the seat's own database
    // routine into the lane registered to owner_role 'accountant'. Nothing here is carried by hand.
    //
    // WHAT THE NUMBERS ARE. fn_accountant_spend_report reads expense_entries — nothing else — and
    // states the coverage of the last sweep from agent_runs beside the total, so the total can be
    // seen either to be complete or to be short. A held receipt is a NAMED LINE on the report, not
    // an omission and not a zero. The AED column converts USD at gl_settings.usd_to_aed and refuses
    // any other currency rather than booking it at 1:1; both are printed on the document.
    //
    // DELIVERY IS OPT-IN (`deliver: true`). A report renders without arming a send, so the document
    // can be produced and read before anyone is mailed.
    if (action === 'spend_report') {
      const { data: repRaw, error: repErr } = await admin.rpc('fn_accountant_spend_report', {
        p_as_of: typeof body.as_of === 'string' ? body.as_of : null,
      });
      if (repErr) {
        await run('spend_report', 'error', {}, 'fn_accountant_spend_report failed: ' + repErr.message);
        return J({ ok: false, error: 'report_unavailable', detail: repErr.message }, 503);
      }
      const rep = (repRaw || {}) as Record<string, unknown>;

      // ── THE DOCUMENT LINKS ───────────────────────────────────────────────────────────────────
      // The founder, 9 Sep 2026: "can the pdf have clickable links for the actual invoices or
      // receipts or at least a pdf print of the email".
      //
      // fn_accountant_spend_report marks every cell it wants clickable as
      // {text, link_entry: <expense id>}. It cannot do more than MARK it: receipt-files is a private
      // bucket, a URL into it must be signed with the service role, and there is no pgjwt in this
      // project. So the resolution happens here, in the one place that holds the key — one read of
      // v_expense_documents and ONE batch signing call, not forty-five round trips.
      //
      // LIFETIME, DECIDED DELIBERATELY. The signed URL is the CONVENIENCE; the record number printed
      // in the first column of every row is the PERMANENT handle. A year is long enough that the
      // founder is not chasing dead links next quarter, and short enough that a leaked copy of this
      // report is not a standing grant over the whole receipt archive. The exact expiry date is
      // printed on the document under the table — a link whose death date is unstated is a link that
      // gets discovered dead — together with the two routines that turn a record number back into a
      // fresh one. The full reasoning, including the two options not taken, is in the header of
      // scripts/sql/the_spend_report_links_every_line_to_the_document_behind_it.sql.
      const LINK_TTL = 365 * 24 * 3600;
      const linkExpiry = new Date(Date.now() + LINK_TTL * 1000);
      let linksResolved = 0, linksUnavailable = 0, linkErr: string | null = null;
      const blocks = rep.blocks;
      const wanted = new Set<number>();
      const collect = (v: unknown): void => {
        if (Array.isArray(v)) { for (const x of v) collect(x); return; }
        if (v && typeof v === 'object') {
          const o = v as Record<string, unknown>;
          if (typeof o.link_entry === 'number') wanted.add(o.link_entry);
          for (const x of Object.values(o)) collect(x);
        }
      };
      collect(blocks);
      const urlFor = new Map<number, string>();
      if (wanted.size) {
        try {
          const { data: docRows, error: dErr } = await admin.from('v_expense_documents')
            .select('id,doc_bucket,doc_path').in('id', [...wanted]);
          if (dErr) throw new Error(dErr.message);
          const withDoc = (docRows || []).filter((r: Record<string, unknown>) => !!r.doc_path);
          if (withDoc.length) {
            const bucket = String(withDoc[0].doc_bucket || 'receipt-files');
            const { data: signed, error: sErr } = await admin.storage.from(bucket)
              .createSignedUrls(withDoc.map((r: Record<string, unknown>) => String(r.doc_path)), LINK_TTL);
            if (sErr) throw new Error(sErr.message);
            const byPath = new Map((signed || []).map((s: Record<string, unknown>) => [String(s.path), s.signedUrl as string | null]));
            for (const r of withDoc) { const u = byPath.get(String(r.doc_path)); if (u) urlFor.set(Number(r.id), u); }
          }
        } catch (e) { linkErr = String((e as Error)?.message || e); }
      }
      // A mark that could not be signed LOSES its link and says so in the cell. The founder's own
      // condition for this document: a row that cannot be opened must read as such, never as a link
      // that goes nowhere.
      const resolveLinks = (v: unknown): void => {
        if (Array.isArray(v)) { for (const x of v) resolveLinks(x); return; }
        if (v && typeof v === 'object') {
          const o = v as Record<string, unknown>;
          if (typeof o.link_entry === 'number') {
            const u = urlFor.get(o.link_entry);
            if (u) { o.link = u; linksResolved++; }
            else { o.text = String(o.text ?? '') + ' (link unavailable)'; linksUnavailable++; }
            delete o.link_entry;
          }
          for (const x of Object.values(o)) resolveLinks(x);
        }
      };
      resolveLinks(blocks);
      if (Array.isArray(blocks) && wanted.size) {
        blocks.push({ t: 'note', text: linksResolved + ' link(s) above were signed on '
          + new Date().toISOString().slice(0, 10) + ' and stop working after '
          + linkExpiry.toISOString().slice(0, 10) + '. After that date the Record number in the first '
          + 'column is still the way to the document: public.fn_expense_document(<record>) names the '
          + 'bucket and the object, and this seat returns a fresh link for it on request. '
          + (linksUnavailable ? linksUnavailable + ' line(s) could not be signed and say so in the row. ' : '')
          + (linkErr ? 'The signing call reported: ' + linkErr + '. ' : '')
          + 'Nothing in this report stops being useful when the links expire.' });
      }

      const secret = await sec('cred_fn_accountant');
      // glyphs_dropped is carried through because ok:true alone cannot tell a correct document from
      // one rendered on the WinAnsi fallback with characters missing from a money line. It should
      // always be 0 here — strict_glyphs below makes pdf_native refuse rather than degrade — and
      // reporting the measured number is cheaper than trusting that it did.
      let pdf: { bucket: string | null; path: string | null; url: string | null; bytes: number | null; glyphs_dropped: number | null; links: number | null } =
        { bucket: null, path: null, url: null, bytes: null, glyphs_dropped: null, links: null };
      let pdfErr: string | null = null;
      if (!secret) {
        pdfErr = 'app_secrets.cred_fn_accountant is unreadable, so this seat could not authenticate to pdf_native.';
      } else {
        try {
          const r = await fetch(SUPA_URL + '/functions/v1/pdf_native', {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              __secret: secret, title: String(rep.subject || 'Spend since day one'), blocks: rep.blocks,
              bucket: 'finance-reports', folder: 'accountant/spend',
              name: String(rep.doc_name || 'QuotesDone_Spend_Since_Day_One'),
              // strict_glyphs, because this is a financial statement: a character the font cannot
              // draw would otherwise vanish from a money line and the document would still say ok.
              options: { letterhead: true, strict_glyphs: true },
            }), signal: AbortSignal.timeout(55000),
          });
          const j = await r.json().catch(() => null);
          // THE PATH pdf_native RETURNS IS THE ONLY PATH. It names its own object (bucket + a
          // timestamped folder key); supplying one here and hoping they agree is how an attachment
          // reference comes to point at nothing.
          // `links` is what pdf_native ACTUALLY wrote as /Annot /Link dictionaries. Carried through
          // because "the seat resolved 45 links" and "the document has 45 clickable links" are two
          // different facts, and only the second one is the founder's request.
          if (r.ok && j?.ok && j?.path) pdf = { bucket: String(j.bucket || 'finance-reports'), path: String(j.path), url: j.url ?? null, bytes: j.bytes ?? null, glyphs_dropped: j.glyphs_dropped ?? null, links: j.links ?? null };
          else pdfErr = 'pdf_native ' + r.status + ': ' + JSON.stringify(j ?? {}).slice(0, 400);
        } catch (e) { pdfErr = 'pdf_native unreachable: ' + String((e as Error)?.message || e); }
      }

      let delivery: Record<string, unknown> | null = null;
      if (body.deliver === true) {
        if (!pdf.path) {
          delivery = { ok: false, reason: 'not delivered: the PDF did not render, and the founder asked for the report AS a document. ' + (pdfErr || '') };
        } else {
          const { data: delRaw, error: delErr } = await admin.rpc('fn_accountant_spend_report_deliver', {
            p_bucket: pdf.bucket, p_path: pdf.path, p_url: pdf.url, p_bytes: pdf.bytes,
            p_as_of: String(rep.as_of || ''), p_subject: String(rep.subject || ''), p_body: String(rep.body || ''),
          });
          delivery = delErr ? { ok: false, reason: 'fn_accountant_spend_report_deliver raised: ' + delErr.message } : (delRaw as Record<string, unknown>);
        }
      }

      await run('spend_report', pdfErr ? 'error' : 'ok', {
        as_of: rep.as_of ?? null, entries: (rep.figures as Record<string, unknown> | undefined)?.entries ?? null,
        pdf_path: pdf.path, delivered: delivery?.ok === true,
        links_in_pdf: pdf.links, links_resolved: linksResolved, links_unavailable: linksUnavailable,
      }, pdfErr ?? undefined);

      return J({
        ok: true, seat: 'accountant', caller: caller.kind,
        report: rep, pdf, pdf_error: pdfErr, delivery,
        links: { resolved: linksResolved, unavailable: linksUnavailable, in_pdf: pdf.links,
                 expires_at: linkExpiry.toISOString(), ttl_seconds: LINK_TTL, error: linkErr,
                 basis: 'Each Evidence cell the report marked with an expense id was signed against '
                   + 'the private receipt-files bucket. A cell that could not be signed prints '
                   + '"(link unavailable)" instead of a dead link, and every row carries the expense '
                   + 'record number, which does not expire.' },
        delivery_armed: body.deliver === true,
        note: body.deliver === true ? null : 'The document was rendered and stored. No mail was inserted: pass deliver:true to send it from this seat.',
      });
    }
    // ── DUTIES (14 Sep 2026) ───────────────────────────────────────────────────────────────────
    // The founder: "yea add them all" and "yea add them". resilience_ping calls this every tick under
    // the seat's credential; fn_accountant_duties_due lets it run at most once in 55 minutes. This
    // action takes only the readings the database cannot take — Stripe's payouts and the balance
    // transactions behind each new one, Stripe's own fee and tax transactions, disputes, and the charge
    // audit computed with the #616 formula — and hands them to fn_accountant_duties, which decides.
    // Then it answers every dispute that is waiting and renders any closed month's PDF and CSV.
    // A reading that could not be taken is passed as 'unreadable' with its reason, never as empty.
    if (action === 'duties') {
      const { data: due } = await admin.rpc('fn_accountant_duties_due');
      if (due !== true && body.force !== true) return J({ ok: true, seat: 'accountant', skipped: 'the duties ran within the last 55 minutes' });
      const since = Math.floor(Date.now() / 1000) - 45 * 86400;
      // deno-lint-ignore no-explicit-any
      const S = async (key: string, path: string): Promise<{ ok: boolean; status: number; j: any }> => {
        const r = await fetch('https://api.stripe.com/v1/' + path, { headers: { Authorization: 'Bearer ' + key } });
        return { ok: r.ok, status: r.status, j: await r.json().catch(() => ({})) };
      };
      const keys = { live: await sec('stripe_secret_key'), test: await sec('stripe_secret_key_test') };
      const stripe: Record<string, unknown> = {};
      for (const mode of ['live', 'test'] as const) {
        const key = keys[mode];
        if (!key) { stripe[mode] = { basis: 'not_configured', reason: 'app_secrets holds no Stripe ' + mode + ' key' }; continue; }
        try {
          const po = await S(key, 'payouts?limit=100&created[gte]=' + since);
          if (!po.ok) throw new Error('GET /v1/payouts returned HTTP ' + po.status);
          const { data: known } = await admin.from('stripe_payout').select('id').not('txn_count', 'is', null);
          const have = new Set((known || []).map((r: { id: string }) => r.id));
          const payouts: Record<string, unknown>[] = [];
          for (const p of (po.j.data || []) as Record<string, unknown>[]) {
            const row: Record<string, unknown> = { ...p };
            // Stripe lists a payout's balance transactions only for automatic payouts.
            if (!have.has(String(p.id)) && p.automatic === true && p.status === 'paid') {
              let n = 0, net = 0, after = '';
              for (let page = 0; page < 20; page++) {
                const bt = await S(key, 'balance_transactions?payout=' + p.id + '&limit=100' + (after ? '&starting_after=' + after : ''));
                if (!bt.ok) break;
                const items = (bt.j.data || []) as Record<string, unknown>[];
                for (const t of items) if (t.type !== 'payout') { n++; net += Number(t.net || 0); }
                if (!bt.j.has_more || !items.length) { row.txn_count = n; row.txn_net = net; break; }
                after = String(items[items.length - 1].id);
              }
            }
            payouts.push(row);
          }
          const feeBts: unknown[] = [];
          for (const type of ['stripe_fee', 'tax']) {
            const f = await S(key, 'balance_transactions?type=' + type + '&limit=100&created[gte]=' + since);
            if (!f.ok) throw new Error('GET /v1/balance_transactions?type=' + type + ' returned HTTP ' + f.status);
            feeBts.push(...(f.j.data || []));
          }
          const dp = await S(key, 'disputes?limit=100&created[gte]=' + since);
          if (!dp.ok) throw new Error('GET /v1/disputes returned HTTP ' + dp.status);
          stripe[mode] = { basis: 'measured', payouts, fee_bts: feeBts, disputes: dp.j.data || [] };
        } catch (e) { stripe[mode] = { basis: 'unreadable', reason: String((e as Error)?.message || e) }; }
      }

      // THE CHARGE AUDIT (duty 10): expected from revealChargeFor, actual from the balance transaction.
      let chargeAudit: Record<string, unknown>[] | null = [];
      const { data: cands, error: cErr } = await admin.rpc('fn_accountant_charge_audit_candidates', { p_limit: 200 });
      if (cErr) chargeAudit = null;
      for (const c of (cands || []) as Record<string, unknown>[]) {
        let got: { ok: boolean; status: number; j: Record<string, any> } | null = null;
        for (const k of [keys.live, keys.test]) {
          if (!k) continue;
          const r = await S(k, 'payment_intents/' + encodeURIComponent(String(c.payment_ref)) + '?expand[]=latest_charge.balance_transaction');
          if (r.ok) { got = r; break; }
        }
        const pi = got?.j; const bt = pi?.latest_charge?.balance_transaction;
        if (!pi || !bt || typeof bt.amount !== 'number') continue;   // not auditable yet; re-tried next run
        const basis = pi.metadata?.fee_basis === 'domestic' ? 'domestic' : 'international';
        const exp = revealChargeFor(Number(c.quote_amount), Number(c.rate), basis);
        const actualTotal = bt.amount / 100;
        chargeAudit!.push({
          transaction_id: c.transaction_id, livemode: pi.livemode === true, basis,
          quote_amount: Number(c.quote_amount), rate: Number(c.rate),
          expected_total: exp.total_charged, expected_processing: exp.processing_fee,
          actual_total: actualTotal, actual_fee_fils: bt.fee,
          // No shortfall exists any more: the buyer pays the 3% only and QuotesDone absorbs Stripe (24 Sep 2026).
          // diff_aed (actual - expected) > 0 is the finding that matters: a buyer charged more than the 3%.
          evidence: { absorbed_stripe_cost_aed: absorbedStripeCost({ total_charged: actualTotal, actual_card_fee_fils: Number(bt.fee) }), payment_intent: pi.id, balance_transaction: bt.id, currency: bt.currency, fee_details: bt.fee_details,
                      basis_source: pi.metadata?.fee_basis ? 'payment metadata' : 'no fee_basis on the payment: the Checkout Session flow prices at the international basis' },
        });
      }

      // WHAT EACH NEW STATEMENT LINE IS, reasoned before the duties book it (decision point sql.accountant_bank_lines):
      // a line not yet reasoned has kind NULL and every booking routine skips it; under the hold it waits in the queue.
      const bankLines = await reasonBankLines(defaultDeps(admin, 'accountant'));
      const { data: out, error: dErr } = await admin.rpc('fn_accountant_duties', { p_r: { stripe, charge_audit: chargeAudit, bank_lines: bankLines } });
      if (dErr) { await run('duties', 'error', {}, 'fn_accountant_duties raised: ' + dErr.message); return J({ ok: false, error: dErr.message }, 500); }

      // DISPUTES (duty 7). SUBMITTING IS FINAL — Stripe takes one submission — so it happens in two steps
      // (review of #645): (1) the evidence is SAVED at Stripe as a draft (submit=false) the moment it is
      // assembled, and the CEO gets a review item; (2) it is submitted only when
      // fn_accountant_disputes_to_submit names a trigger: the CEO's approval, or his silence at T-24h.
      const answered: Record<string, unknown>[] = [];
      answered.push(...await draftDisputes(admin, keys));   // _shared/dispute_draft.ts; stripe_webhook runs it on charge.dispute.created too
      const { data: toSubmit } = await admin.rpc('fn_accountant_disputes_to_submit');
      for (const s of (toSubmit || []) as Record<string, any>[]) {
        const key = s.livemode ? keys.live : keys.test;
        if (!key || !s.trigger) continue;
        // The evidence is already saved on the dispute; this call only submits it.
        const r = await fetch('https://api.stripe.com/v1/disputes/' + encodeURIComponent(String(s.dispute)), {
          method: 'POST', headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({ submit: 'true', 'metadata[submit_trigger]': String(s.trigger) }).toString(),
        });
        const j = await r.json().catch(() => ({}));
        await admin.rpc('fn_accountant_dispute_submitted', { p_id: s.dispute, p_ok: r.ok,
          p_response: r.ok ? { id: j.id, status: j.status } : null,
          p_error: r.ok ? null : 'HTTP ' + r.status + ': ' + String(j?.error?.message || '').slice(0, 300),
          p_trigger: String(s.trigger) });
        answered.push({ dispute: s.dispute, submitted: r.ok, trigger: s.trigger });
      }

      // RENDER EVERY CLOSED MONTH THAT HAS NO DOCUMENT YET (duty 8): PDF and CSV, English.
      const rendered: Record<string, unknown>[] = [];
      const { data: pend } = await admin.from('accountant_month_close').select('month').is('rendered_at', null).order('month').limit(3);
      const cred = await sec('cred_fn_accountant');
      for (const p of (pend || []) as { month: string }[]) {
        const { data: doc, error: docErr } = await admin.rpc('fn_accountant_month_close_document', { p_month: p.month });
        if (docErr || !doc) { rendered.push({ month: p.month, error: docErr?.message || 'no document' }); continue; }
        const dd = doc as Record<string, any>;
        const folder = 'accountant/close/' + dd.month;
        const csvPath = folder + '/' + dd.name + '.csv';
        const cu = await admin.storage.from('finance-reports').upload(csvPath, new Blob([String(dd.csv)], { type: 'text/csv' }), { upsert: true });
        let pdfPath: string | null = null; let perr = '';
        if (cred) {
          try {
            const r = await fetch(SUPA_URL + '/functions/v1/pdf_native', { method: 'POST', headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ __secret: cred, title: dd.title, blocks: dd.blocks, bucket: 'finance-reports', folder, name: dd.name,
                                     options: { letterhead: true, strict_glyphs: true } }), signal: AbortSignal.timeout(55000) });
            const j = await r.json().catch(() => null);
            if (r.ok && j?.ok && j?.path) pdfPath = String(j.path); else perr = 'pdf_native ' + r.status;
          } catch (e) { perr = String((e as Error)?.message || e); }
        } else perr = 'cred_fn_accountant unreadable';
        if (pdfPath && !cu.error) {
          await admin.rpc('fn_accountant_month_close_attach', { p_month: p.month, p_bucket: 'finance-reports', p_pdf_path: pdfPath, p_csv_path: csvPath });
          rendered.push({ month: dd.month, pdf: pdfPath, csv: csvPath });
        } else rendered.push({ month: dd.month, error: perr || cu.error?.message });
      }

      // THE FOUNDER'S CLOSE PACK (instruction 1009, upgrade 8): one short PDF per built pack, then
      // fn_accountant_founder_close_pack_attach sends it through fn_notify_founder. A render failure is
      // recorded on the pack and retried next tick; the day-5 miss is reported by the SQL duty.
      const { data: packs } = await admin.from('accountant_founder_close_pack').select('month').is('rendered_at', null).order('month').limit(2);
      for (const p of (packs || []) as { month: string }[]) {
        const { data: doc, error: docErr } = await admin.rpc('fn_accountant_founder_close_pack_document', { p_month: p.month });
        if (docErr || !doc) { rendered.push({ close_pack: p.month, error: docErr?.message || 'no document' }); continue; }
        const dd = doc as Record<string, any>;
        let pdfPath: string | null = null; let perr = '';
        if (cred) {
          try {
            const r = await fetch(SUPA_URL + '/functions/v1/pdf_native', { method: 'POST', headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ __secret: cred, title: dd.title, blocks: dd.blocks, bucket: 'finance-reports',
                                     folder: 'accountant/close-pack/' + dd.month, name: dd.name,
                                     options: { letterhead: true, strict_glyphs: true } }), signal: AbortSignal.timeout(55000) });
            const j = await r.json().catch(() => null);
            if (r.ok && j?.ok && j?.path) pdfPath = String(j.path); else perr = 'pdf_native ' + r.status;
          } catch (e) { perr = String((e as Error)?.message || e); }
        } else perr = 'cred_fn_accountant unreadable';
        const { data: sent, error: aErr } = await admin.rpc('fn_accountant_founder_close_pack_attach',
          { p_month: p.month, p_bucket: 'finance-reports', p_pdf_path: pdfPath, p_error: perr || null });
        rendered.push({ close_pack: dd.month, pdf: pdfPath, sent, error: aErr?.message || perr || undefined });
      }

      // FILE THE YEAR-END PACK WHEN IT FALLS DUE (duty 4 of the five further duties, 14 Sep 2026): seven CSVs
      // from the books into the private backups bucket; the attach queues them for Dropbox, and the
      // it_engineer's backup loop verifies each one arrived.
      const yearEnd: Record<string, unknown>[] = [];
      const { data: yDue } = await admin.rpc('fn_accountant_year_end_pack_due');
      if (yDue) {
        const { data: ydoc, error: yErr } = await admin.rpc('fn_accountant_year_end_pack_document', { p_year: yDue });
        if (yErr || !ydoc) yearEnd.push({ year: yDue, error: yErr?.message || 'no document' });
        else {
          const yd = ydoc as { year: number; folder: string; files: { name: string; csv: string }[] };
          const files: { name: string; bucket: string; path: string }[] = [];
          let yFail = '';
          for (const f of yd.files) {
            const p = yd.folder + '/' + f.name;
            const up = await admin.storage.from('backups').upload(p, new Blob([f.csv], { type: 'text/csv' }), { upsert: true });
            if (up.error) { yFail = f.name + ': ' + up.error.message; break; }
            files.push({ name: f.name, bucket: 'backups', path: p });
          }
          if (!yFail) {
            const { error: aErr } = await admin.rpc('fn_accountant_year_end_pack_attach', { p_year: yd.year, p_files: files });
            if (aErr) yFail = aErr.message;
          }
          yearEnd.push(yFail ? { year: yd.year, error: yFail } : { year: yd.year, files: files.length });
        }
      }

      // IS THE EXPENSES MAILBOX QUIET, OR IS THE INTAKE SILENT? (ledger 983, 24 Sep 2026, GAPS Accountant 1.)
      // One page of Resend's inbound list, newest first, the last 14 days; the verdict and findings are SQL's.
      let mailbox: unknown = null;
      {
        const rkey = await sec('resend_api_key');
        let listErr: string | null = rkey ? null : 'app_secrets.resend_api_key is unreadable';
        let msgs: MailboxMessage[] = [];
        if (rkey) {
          // The list covers every mailbox, newest first: page until a page reaches past the window, at most 10.
          const since = Date.now() - 14 * 86400000;
          try {
            let after = ''; let pages = 0;
            for (;;) {
              const r = await fetch('https://api.resend.com/emails/inbound?limit=100' + (after ? '&after=' + encodeURIComponent(after) : ''),
                { headers: { Authorization: 'Bearer ' + rkey }, signal: AbortSignal.timeout(15000) });
              // deno-lint-ignore no-explicit-any
              const j: any = await r.json().catch(() => ({}));
              if (!r.ok) { listErr = 'HTTP ' + r.status; break; }
              const items = (j.data || j.items || []) as InboundItem[];
              msgs.push(...mailboxMessages(items, EXPENSE_MAILBOX, since));
              pages++;
              const oldest = Date.parse(String(items[items.length - 1]?.created_at || ''));
              if (!j.has_more || !items.length || (Number.isFinite(oldest) && oldest < since)) break;
              if (pages >= 10) { listErr = 'more than 1,000 inbound messages in 14 days; the list was not read to the end of the window'; break; }
              after = String(items[items.length - 1].id);
            }
          } catch (e) { listErr = String((e as Error)?.message || e).slice(0, 200); }
        }
        const { data: mb, error: mbErr } = await admin.rpc('fn_accountant_mailbox_check_record', { p_messages: msgs, p_list_error: listErr });
        mailbox = mbErr ? { error: mbErr.message } : mb;
      }

      await run('duties', 'ok', { mailbox: (mailbox as Record<string, unknown>)?.verdict ?? null, bank_lines: bankLines, disputes_answered: answered.length, months_rendered: rendered.length, year_end: yearEnd.length,
        stripe_live: (stripe.live as Record<string, unknown>)?.basis, stripe_test: (stripe.test as Record<string, unknown>)?.basis });
      return J({ ok: true, seat: 'accountant', result: out, mailbox, disputes_answered: answered, months_rendered: rendered, year_end: yearEnd });
    }

    // ── REVEAL_RECONCILE: a paid reveal with no sale is found and recorded (3 Nov 2026) ───────────
    // The seat duty accountant.reveal_reconcile (scripts/sql/a_paid_reveal_with_no_sale_is_found_and_recorded_within_the_hour.sql)
    // calls this every hour with its run id. The sweep is _shared/reveal_reconcile.ts: Stripe's paid reveal invoices
    // and PaymentIntents of the last N days against transactions, each one missing recorded through recordRevealSale.
    // Both keys are swept. A test-mode payment is recorded only when its quote belongs to a demo account (the rule
    // stripe_webhook's testEventIsDemo applies); any other is outcome 'test_mode_not_demo', a finding, never a ledger row.
    if (action === 'reveal_reconcile') {
      const runId = Number.isSafeInteger(Number(body.run_id)) && Number(body.run_id) > 0 ? Number(body.run_id) : null;
      const days = clampDays(body.days ?? 30);
      const keys: Record<Mode, string | undefined> = { live: await sec('stripe_secret_key'), test: await sec('stripe_secret_key_test') };
      // deno-lint-ignore no-explicit-any
      const S = async (mode: Mode, path: string): Promise<any | null> => {
        try {
          const r = await timedFetch('https://api.stripe.com/v1/' + path, { headers: { Authorization: 'Bearer ' + keys[mode] } });
          return r.ok ? await r.json().catch(() => null) : null;
        } catch (_e) { return null; }
      };
      const modes = (['live', 'test'] as Mode[]).filter((m) => keys[m]);
      let swept;
      try {
        swept = await sweepReveals({
          modes,
          list: async (mode, path) => { const j = await S(mode, path); return j && Array.isArray(j.data) ? { data: j.data, has_more: j.has_more === true } : null; },
          invoicePayment: async (mode, id) => {
            const j = await S(mode, 'invoice_payments?invoice=' + encodeURIComponent(id));
            const list = ((j?.data || []) as { status?: string; payment?: { payment_intent?: unknown } }[]).filter((x) => x?.payment?.payment_intent);
            const p = (list.find((x) => x.status === 'paid') || list[0])?.payment?.payment_intent as string | { id: string } | undefined;
            return p ? String(typeof p === 'string' ? p : p.id) : null;
          },
          readPayment: async (mode, pi) => {
            const j = await S(mode, 'payment_intents/' + encodeURIComponent(pi) + '?expand[]=latest_charge.balance_transaction');
            if (!j?.id) return null;
            const bt = j.latest_charge?.balance_transaction;
            return { status: String(j.status), amount_received: Number(j.amount_received || 0), amount_refunded: Number(j.latest_charge?.amount_refunded || 0),
              fee_fils: typeof bt?.fee === 'number' ? bt.fee : null, fee_details: bt?.fee_details ?? null };
          },
          findTransactions: async (q) => {
            const cols = 'id,quote_id,payment_ref,stripe_invoice_id';
            // 100 ids a request: a 30-day window of every paid reveal would otherwise be one URL of many kilobytes.
            const chunks = (xs: string[]) => Array.from({ length: Math.ceil(xs.length / 100) }, (_, i) => xs.slice(i * 100, i * 100 + 100));
            const parts = [];
            for (const [col, ids] of [['stripe_invoice_id', q.invoices], ['payment_ref', q.refs], ['quote_id', q.quotes]] as const) {
              for (const part of chunks(ids)) parts.push(await admin.from('transactions').select(cols).in(col, part));
            }
            const bad = parts.find((p) => p.error);
            // An unread book is not an empty book: recording against it could write a second sale.
            if (bad?.error) throw new Error('transactions could not be read: ' + bad.error.message);
            const seen = new Map<string, { id: string; quote_id: string | null; payment_ref: string | null; stripe_invoice_id: string | null }>();
            for (const p of parts) for (const t of (p.data || []) as { id: string; quote_id: string | null; payment_ref: string | null; stripe_invoice_id: string | null }[]) seen.set(String(t.id), { ...t, id: String(t.id) });
            return [...seen.values()];
          },
          isDemoQuote: async (quoteId) => {
            const { data: q } = await admin.from('quotes').select('inquiry_id').eq('id', quoteId).maybeSingle();
            if (!q?.inquiry_id) return false;
            const { data } = await admin.rpc('fn_inquiry_is_demo', { p_inquiry: q.inquiry_id });
            return data === true;
          },
          record: (a) => recordRevealSale(admin, a),
          // What Stripe kept, write-once, exactly as stripe_webhook's recordStripeFee: fn_gl_sync_business books it to 6100.
          recordFee: async (txId, feeFils, details) => {
            await admin.from('transactions').update({ stripe_fee_fils: feeFils, stripe_fee_details: details }).eq('id', txId).is('stripe_fee_fils', null);
          },
        }, { days, nowSec: Math.floor(Date.now() / 1000), maxPages: 5, maxRecords: 25, maxAttempts: 50, graceSeconds: 900 });
      } catch (e) {
        const msg = String((e as Error)?.message || e).slice(0, 300);
        await admin.rpc('fn_accountant_reveal_reconcile_record', { p_run_id: runId, p_r: { days, error: msg, modes: {}, outcomes: [] } });
        await run('reveal_reconcile', 'error', { run_id: runId }, 'the reveal sweep stopped: ' + msg);
        return J({ ok: false, error: msg }, 500);
      }
      for (const m of ['live', 'test'] as Mode[]) if (!keys[m]) swept.modes[m] = { basis: 'not_configured', invoices: 0, payment_intents: 0, truncated: false, reason: 'app_secrets holds no Stripe ' + m + ' key' };
      const { data: out, error: rErr } = await admin.rpc('fn_accountant_reveal_reconcile_record', { p_run_id: runId,
        p_r: { days, modes: swept.modes, checked: swept.checked, too_recent: swept.too_recent, outcomes: reportable(swept.outcomes) } });
      const tally: Record<string, number> = {};
      for (const o of swept.outcomes) tally[o.outcome] = (tally[o.outcome] || 0) + 1;
      await run('reveal_reconcile', rErr ? 'error' : 'ok', { run_id: runId, days, checked: swept.checked, ...tally },
        rErr ? 'fn_accountant_reveal_reconcile_record raised: ' + rErr.message : undefined);
      // The result names counts and ids only: this endpoint answers every caller holding the seat's credential.
      return rErr ? J({ ok: false, error: rErr.message, outcomes: tally }, 500) : J({ ok: true, seat: 'accountant', outcomes: tally, result: out });
    }

    // ── BANK_STATEMENT: a statement handed in directly (CSV export or text) ───────────────────────
    if (action === 'bank_statement') {
      const src = String(body.source_ref || '').trim();
      if (!src) return J({ ok: false, error: 'source_ref is required' }, 400);
      const st = readStatement(String(body.csv || body.text || ''));
      const lines = st.lines;
      // A statement that prints its closing balance and adds up supplies closing_balance_aed / balance_on
      // itself (#659's field names) unless the caller gave them. One that does not add up supplies none.
      if (!st.problem && st.closing_balance_aed !== null && (body.closing_balance_aed === undefined || body.closing_balance_aed === null)) {
        body.closing_balance_aed = st.closing_balance_aed;
        body.balance_on = body.balance_on ?? st.period_to;
      }
      const { data, error } = await admin.rpc('fn_accountant_bank_statement_ingest', {
        p_account: String(body.account || 'mashreq'), p_source_ref: src,
        p_statement_month: body.month ?? (st.period_from ? st.period_from.slice(0, 8) + '01' : null),
        p_lines: lines, p_doc_path: null,
        p_note: st.problem ? 'handed in, and it does not add up, so none of it was booked: ' + st.problem
              : lines.length ? null : 'handed in, and no line could be read without guessing a sign' });
      if (error) return J({ ok: false, error: error.message }, 400);
      // The closing balance the statement prints (duty 1 of the five further duties): the CEO's cash and
      // runway read it. Only as printed, never worked out from the lines.
      let balance: unknown = null;
      if (body.closing_balance_aed !== undefined && body.closing_balance_aed !== null) {
        const { data: b, error: bErr } = await admin.rpc('fn_accountant_bank_balance_record', {
          p_source_ref: src, p_balance_aed: Number(body.closing_balance_aed), p_on: body.balance_on ?? null });
        if (bErr) return J({ ok: false, error: bErr.message, lines: lines.length }, 400);
        balance = b;
      }
      await run('bank_statement', 'ok', { lines: lines.length, closing_balance: balance !== null });
      return J({ ok: true, ...(data as Record<string, unknown>), closing_balance: balance });
    }

    // ── The two outcomes only a person can record ─────────────────────────────────────────────────
    if (action === 'filing_outcome') {
      const { data, error } = await admin.rpc('fn_accountant_record_filing_outcome', {
        p_due_id: Number(body.due_id), p_outcome: String(body.outcome || ''), p_reference: body.reference ?? null });
      if (error) return J({ ok: false, error: error.message }, 400);
      await run('filing_outcome', 'ok', { due_id: Number(body.due_id) });
      return J(data);
    }
    // What happened in court on a supplier charge (duty 3 of the five further duties): filed, order_issued,
    // order_served, grievance_filed, recovered or withdrawn, on the day it happened.
    if (action === 'court_step') {
      const { data, error } = await admin.rpc('fn_accountant_record_court_step', {
        p_due_id: Number(body.due_id), p_step: String(body.step || ''), p_on: body.on ?? null, p_reference: body.reference ?? null });
      if (error) return J({ ok: false, error: error.message }, 400);
      await run('court_step', 'ok', { due_id: Number(body.due_id), step: String(body.step || '') });
      return J(data);
    }
    if (action === 'charge_resolve') {
      const { data, error } = await admin.rpc('fn_accountant_charge_audit_resolve', {
        p_transaction_id: String(body.transaction_id || ''), p_resolution: String(body.resolution || '') });
      if (error) return J({ ok: false, error: error.message }, 400);
      await run('charge_resolve', 'ok', { transaction_id: String(body.transaction_id || '') });
      return J(data);
    }

    // The document doors were missing from this list until 9 Sep 2026, which made them unreachable
    // to anyone who asked the function what it could do rather than reading its source.
    return J({ error: 'unknown_action', action, actions: ['health', 'grants', 'ledger', 'refund_request', 'expense_sweep', 'spend_report', 'assist', 'document', 'documents', 'refund_document', 'refund_documents', 'revenue_document', 'revenue_documents', 'execute_refunds', 'handoffs', 'complete_handoff', 'duties', 'bank_statement', 'filing_outcome', 'court_step', 'charge_resolve'] }, 400);
  } catch (e) {
    await run('error', 'error', {}, String((e as Error).message || e));
    return J({ error: String((e as Error).message || e) }, 500);
  }
}));
