// customer_api — the buyer's endpoint. This file is the door: CORS preflight, keep-warm, the internal
// compare_arabic_finish replay, sign-in, the customer row, the ban, the terms re-acceptance closure, then
// dispatch. Every action lives in ./actions/<group>.ts and the helpers they share in ./lib/ and ./context.ts.
//
// Split from one 2,516-line file on 9 Nov 2026 (it_engineer) as a pure move: every statement is the one that
// was here, byte for byte. Checks that read this function as text read the whole folder through
// scripts/lib/function_sources.mjs functionSource('customer_api').
import { observe } from '../_shared/observe.ts';
import { clientIp } from '../_shared/supplier_terms.ts';
import { timedFetch } from '../_shared/timed_fetch.ts';
import { customerTermsRecord } from '../_shared/customer_terms.ts';
import { siteCors } from '../_shared/site_origins.ts';
import { requireInternal } from '../_shared/internal_auth.ts';
import { ackThenWork } from '../_shared/async_webhook.ts';
import { finishCompareArabic } from './compare_arabic.ts';
import { type ActionCtx, CORS, J, SERVICE, SUPABASE_URL, admin, getSecret } from './context.ts';
import { buildQuotePdf, compareFinishIO } from './lib/pdfs.ts';
import { DOOR_SCOPES, quotationForBackup } from './lib/quotation_for_backup.ts';
import { accountActions } from './actions/account.ts';
import { documentActions } from './actions/documents.ts';
import { inquiryCreateActions } from './actions/inquiry_create.ts';
import { inquiryLifecycleActions } from './actions/inquiry_lifecycle.ts';
import { reportActions } from './actions/reports.ts';
import { revealActions } from './actions/reveal.ts';
import { reviewActions } from './actions/reviews.ts';
import { discoveryActions } from './actions/discovery.ts';

// The action groups, in the order their first action appeared in the old single if-chain. Each group is that
// chain's own `if (action === …)` blocks, moved verbatim, and answers undefined when none of its actions is asked.
// The conditions are distinct string equalities, so no two groups can claim one action; the one hand-over between
// actions (repeat_inquiry → create_inquiry) stays inside inquiry_create.ts, in its original order.
const ACTION_GROUPS: readonly ((c: ActionCtx) => Promise<Response | undefined>)[] = [
  accountActions, documentActions, inquiryCreateActions, inquiryLifecycleActions, reportActions, revealActions, reviewActions, discoveryActions,
];

Deno.serve(siteCors(observe('customer_api', async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  // KEEP-WARM (resilience_ping, 14 Sep 2026). No auth, no DB, before anything else: the isolate is
  // what needs exercising, not a real answer. See the header of resilience_ping/index.ts.
  if (req.headers.get('x-qd-warm') === '1') return new Response(null, { status: 204 });
  try {
    // THE REPLAY'S ONE DOOR IN (compare_arabic.ts): a held Arabic comparison report whose lines now all exist is
    // rendered and sent to its customer. Internal credential only (fn.resilience_ping, scope customer_api). The work
    // runs after the answer, so the replay's tick never waits on a render. Only a caller presenting the service key
    // (which passes the gateway; __secret decides the caller) has its body read twice: a customer's upload is not.
    const bearer = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const peek = bearer === SERVICE ? await req.clone().json().catch(() => ({})) : null;
    if (peek?.__secret && peek.action === 'compare_arabic_finish') {
      const ok = await requireInternal(admin, String(peek.__secret), 'customer_api');
      if (!ok.ok) return J({ error: 'forbidden' }, 403);
      const iid = String(peek.inquiry_id || '');
      if (!iid) return J({ error: 'bad_request' }, 400);
      return ackThenWork(J({ ok: true, accepted: iid }, 202), async () => {
        const r = await finishCompareArabic(compareFinishIO(), iid);
        console.log(JSON.stringify({ at: 'customer_api.compare_arabic_finish', inquiry_id: iid, ...r }));
      }, 'customer_api.compare_arabic_finish');
    }
    // THE RE-MATCH'S DOOR IN (lib/rematch.ts, 10 Nov 2026): resilience_ping's specoffer step asks again for every request
    // the matcher did not answer whose next try has come. Same internal credential as the replay above. Answered when done:
    // at most `limit` requests, each one matcher call (two tries) and its supplier e-mails.
    if (peek?.__secret && peek.action === 'rematch_waiting') {
      const ok = await requireInternal(admin, String(peek.__secret), 'customer_api');
      if (!ok.ok) return J({ error: 'forbidden' }, 403);
      const { rematchWaiting } = await import('./lib/rematch.ts');
      const { liveRematchIO } = await import('./lib/rematch_io.ts');
      const res = await rematchWaiting(liveRematchIO(), new Date(), Math.max(1, Math.min(10, Number(peek.limit) || 5)));
      return J({ ok: res.errors.length === 0, ...res, ...(res.errors.length ? { error: res.errors.slice(0, 3).join(' | ') } : {}) });
    }
    // THE DROPBOX BACKUP'S DOOR IN (ruling 1680, 13 Nov 2026): a supplier's folder holds, for every job he quoted, "a quotation ... as
    // per our template, the one that we shared with the customer"; the customer's request folder holds his own copy. Rendered here by
    // buildQuotePdf, the code behind the portal's download, stored in backups/generated/ and NOT recorded in quote_pdf_cache (that cache
    // is the customer's own downloads and counts against his hourly limit). The supplier's copy carries the request as the supplier
    // inbox shows it before a reveal (lib/quotation_for_backup.ts). DOOR-ONLY SCOPE (review of #1997, D2): the backup credential holds
    // 'customer_api.quotation_for_backup' and nothing that opens the two doors above. A draft or withdrawn quote is refused.
    if (peek?.__secret && peek.action === 'quotation_for_backup') {
      const ok = await requireInternal(admin, String(peek.__secret), DOOR_SCOPES.quotation_for_backup);
      if (!ok.ok) return J({ error: 'forbidden' }, 403);
      const r = await quotationForBackup(String(peek.quote_id || ''), peek.lang === 'ar' ? 'ar' : 'en', {
        load: async (id) => {
          const { data: q } = await admin.from('quotes').select('*').eq('id', id).maybeSingle();
          if (!q) return null;
          const { data: inq } = await admin.from('inquiries').select('id,rfq_no,customer_id,project_id,category,summary,spec,emirate,boq').eq('id', q.inquiry_id).maybeSingle();
          if (!inq) return null;
          // the buyer and project as the inbox reads them; an error reading either is a buyer we could not read (everything withheld)
          const { data: c, error: ec } = await admin.from('customers').select('full_name,email,phone').eq('id', inq.customer_id).maybeSingle();
          const { data: p, error: ep } = inq.project_id ? await admin.from('projects').select('name').eq('id', inq.project_id).maybeSingle() : { data: null, error: null };
          const { data: tx } = await admin.from('transactions').select('id').eq('quote_id', String(q.id)).limit(1).maybeSingle();
          return { q, inq, buyer: ec || ep || !c ? null : { ...c, project: p?.name ?? null }, revealed: !!tx };
        },
        build: buildQuotePdf,
      }, peek.side === 'customer' ? 'customer' : 'supplier');
      return J(r.body, r.status);
    }
    const auth = req.headers.get('Authorization') || ''; const jwt = auth.replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'Not signed in' }, 401);
    const email = user.email.toLowerCase();
    // THIS ENDPOINT USED TO MANUFACTURE A CUSTOMER ACCOUNT FOR WHOEVER CALLED IT (13 Aug 2026).
    //
    //     if (!cust) { await admin.from('customers').insert({ email }) ... }
    //
    // Any authenticated identity that touched customer_api became a customer. Measured: the
    // duplicate management@quotesdone.com row was retired at 20:30 and a NEW one appeared at
    // 21:01:05 with a different id, full_name null and phone null - the exact shape of
    // insert({ email }), and this is the only line in the estate that writes it. The admin address
    // is admin_emails[0]; it is not a buyer, and a buyer account under it is what made the identity
    // defect read as "the account screen shows the wrong e-mail" in the first place.
    //
    // It is also redundant on the legitimate path: login_otp's email branch already inserts the
    // customers row when a real customer verifies their code (the 12 Aug fix - a first-time
    // customer had no row to UPDATE, so email_verified stayed false and every RFQ was refused).
    // A customer JWT can only come from mintSession there, so by the time anyone reaches this line
    // with a genuine buyer session the row exists. What was left was the case this must NOT serve:
    // staff and admin sessions silently acquiring buyer accounts.
    //
    // Refusing matches what stripe_checkout and stripe_confirm already answer on the same
    // condition ('No customer profile', 403) rather than inventing a new vocabulary for it.
    const { data: cust } = await admin.from('customers').select('*').eq('email', email).maybeSingle();
    if (!cust) return J({ error: 'No customer profile', hint: 'This signed-in identity has no customer account. Customer accounts are created when a buyer verifies their sign-in code, not by reading this endpoint.' }, 403);
    let body = await req.json().catch(() => ({})); let action = String(body.action || '');
    // BANNED CUSTOMER (27 Jul 2026). messages_api auto-bans a buyer who pushes contact details
    // off-platform (it writes customers.banned = true) but customer_api never read that column,
    // so the ban only ever closed the chat: the same person could still post RFQs, reveal
    // suppliers, request refunds and rate them from the main buyer surface. Every mutating
    // action is refused now. 'me' and 'my_inquiries' stay open on purpose so the person can
    // still see their own account state and existing requests rather than hitting a dead wall.
    const MUTATING = ['create_inquiry', 'repeat_inquiry', 'edit_inquiry', 'reveal', 'request_refund', 'rate_supplier', 'decision_reason', 'add_review_photos', 'complete_inquiry', 'cancel_inquiry', 'rfq_note', 'add_missing_specs'];
    if (cust?.banned === true && MUTATING.includes(action)) return J({ error: 'Your account is suspended. Please contact support@quotesdone.com if you believe this is a mistake.' }, 403);

    // RE-ACCEPTANCE OF A NEW TERMS VERSION (6 Oct 2026, release review of #1240). Recorded the same way as sign-up
    // (_shared/customer_terms.ts: version, time, IP, SHA of the pinned text) and the signed certificate re-issued.
    const recordTermsAcceptance = async (): Promise<boolean> => {
      const rec = await customerTermsRecord(getSecret, clientIp(req));
      if (!rec || !cust?.id) return false;
      const { tos_sha256, ...base } = rec;
      const { error } = await admin.from('customers').update(base).eq('id', cust.id);
      if (error) return false;
      // A separate write, so a database without the column yet cannot fail the acceptance itself.
      await admin.from('customers').update({ tos_sha256 }).eq('id', cust.id).then(() => null, () => null);
      try {
        const s = await getSecret('cred_fn_customer_api');
        timedFetch(`${SUPABASE_URL}/functions/v1/compliance_archive`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify({ __secret: s, action: 'sign', kind: 'customer', email }) }).catch(() => { /* best effort */ });
      } catch (_e) { /* never blocks the customer */ }
      return true;
    };
    const ctx: ActionCtx = { req, body, action, user, email, cust, recordTermsAcceptance };
    for (const group of ACTION_GROUPS) {
      // awaited inside the try, so an action that throws still reaches the catch below
      const answer = await group(ctx);
      if (answer) return answer;
    }

    return J({ error: 'Unknown action' }, 400);
  } catch (e) {
    return J({ error: String((e as Error)?.message || e) }, 500);
  }
})));
