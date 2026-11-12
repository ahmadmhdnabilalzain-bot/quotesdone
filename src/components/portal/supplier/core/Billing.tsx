// @ts-nocheck
'use client';
import { useEffect, useRef, useState } from 'react';
import DocActions from '../../DocActions';
import { srvMsg } from '../serverCopy';
import { call } from '../api';
import { firstRead } from '../tabPrefetch';
// THE ONE MONEY FORMATTER (audit 22 Sep 2026, SP-I-10): ./supplier/money.ts. The local `aed(n)` that
// stood here printed "AED 1,200" on /ar too, while the quotation tabs printed "1,200 د.إ" for the
// same figure.
import { aed } from '../money';
import { openDocument } from '@/lib/openDocument';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
// The one loading system (src/components/ui/busy.tsx): 150ms before anything shows, 300ms once it does.
import { useBusy } from '@/components/ui/busy';
import { cn } from '@/lib/utils';
import { Ltr } from '@/lib/Ltr';
import { wentExpired, fmtDate } from './helpers';
import { t } from './copy';
import { S } from './styles';

// STRIPE CAME BACK AND THE PAGE SAID NOTHING (audit 2026-09-14). supplier_pay and pay_registration
// return the supplier to /portal?dues_paid=… or ?registration_paid=…, and nothing read either query
// string — the only confirmation was an email. Dashboard now reads them once, strips them from the URL,
// opens Billing and shows this receipt. It says what is true at that moment: Stripe has the payment;
// the balance changes only when stripe_webhook confirms it, which is the one writer of "paid".
// Disputing a charge, in the portal's own dialog (walk of 12 Nov 2026, S10). English only (ruling 1008).
const DISPUTE = {
  open: 'Dispute this charge', title: 'Dispute this charge', lead: 'Tell us what is wrong with it. We check it against the payment record and write back to you.',
  reason: 'What is wrong with this charge?', send: 'Send my query', sending: 'Sending your query…', cancel: 'Cancel', close: 'Close',
  need_reason: 'Please say what is wrong with the charge.', failed: 'Your query was not sent. Please try again.',
  sent: 'We have your query. We are checking the charge against the payment record and will write back to you.',
} as const;
function ReceiptBanner({ receipt, lang }) {
  const ar = lang === 'ar';
  const reg = receipt.kind === 'registration';
  return (
    <div role="status" className="qd-panel flex items-start gap-3 border-primary/40 p-4">
      <span aria-hidden className="mt-0.5 grid h-7 w-7 shrink-0 place-items-center rounded-full bg-primary text-primary-foreground text-sm font-bold">✓</span>
      <div>
        <div className="text-[14px] font-bold text-foreground">{ar ? (reg ? 'تم استلام رسوم الاشتراك' : 'تم استلام الدفعة') : (reg ? 'Subscription payment received' : 'Payment received')}</div>
        <div className={S.sub}>{ar
          ? 'استلمت Stripe دفعتكم وسترسل إليكم الفاتورة بالبريد الإلكتروني، ويُحدَّث رصيدكم هنا فور تأكيد Stripe لنا، وعادةً خلال دقيقة.'
          : 'Stripe has your payment and will email you the invoice. Your balance here updates as soon as Stripe confirms it to us, usually within a minute.'}</div>
        <div className="mt-1 text-[11px] text-muted-foreground" dir="ltr">{(ar ? 'مرجع ' : 'Ref ') + '…' + String(receipt.ref || '').slice(-8)}</div>
      </div>
    </div>
  );
}
// The onboarding copy promises "free for the first 1,000 suppliers, then AED 1,000 per year" (the
// founder's 6 Sep ruling: the fee starts with the registration after the free count, no calendar
// date). pay_registration already answers from fn_supplier_registration_state and creates a Stripe
// Checkout only when a fee is actually due — and had NO caller in src/, so the promise had no button.
// This is that button. For an exempt or not-yet-due supplier it only reads, and says why.
function RegistrationFeeCard({ token, lang, base }) {
  const ar = lang === 'ar';
  const [busy, setBusy] = useState(false); const [res, setRes] = useState(null);
  const check = async () => {
    setBusy(true); setRes(null);
    // Payments are the accountant's (founder, 14 Sep 2026): the registration checkout lives in supplier_pay.
    const j = await call('supplier_pay', { action: 'registration', return_url: base() }, token);
    if (j && j.ok && j.url) { window.location.href = j.url; return; }
    setBusy(false);
    setRes({ ok: !!(j && j.ok), text: srvMsg(lang, j, t(lang, 'err_generic')) });
  };
  return (
    <Card className="qd-panel p-5">
      {/* The name the signed agreement uses — see the note on the receipts row (SP-I-08). */}
      <div className={S.h2}>{ar ? 'رسوم الاشتراك السنوية' : 'Annual subscription fee'}</div>
      <div className={cn(S.sub, 'mt-1')}>{ar
        ? 'التسجيل مجاني بصفة دائمة لأول 1,000 مورّد، واعتبارًا من التسجيل رقم 1,001 تكون الرسوم 1,000 درهم سنويًا. إن كانت عليكم رسوم مستحقة فستنتقلون مباشرة إلى صفحة الدفع الآمنة في Stripe، وإلا فسنوضح لكم السبب.'
        : 'Registration is permanently free for the first 1,000 suppliers; from the 1,001st registration it is AED 1,000 per year. If a fee is due you go straight to Stripe’s secure checkout; if not, we tell you why.'}</div>
      <Button className="mt-3" variant="outline" disabled={busy} onClick={check}>{busy ? (ar ? 'جارٍ التحقق…' : 'Checking…') : (ar ? 'التحقق من رسوم الاشتراك' : 'Check my subscription fee')}</Button>
      {res && <div role="status" className={cn('mt-2 text-[13px]', res.ok ? 'text-primary' : 'text-danger-fg')}>{res.text}</div>}
    </Card>
  );
}
function BillingPanel({ token, lang, receipt, onExpired }) {
  const [st, setSt] = useState({ loading: true, dues: [], total: 0, err: '' });
  const [busy, setBusy] = useState(false);
  // Stripe returns to base + '/portal', so an Arabic supplier comes back to /ar/portal.
  const base = () => window.location.origin + (lang === 'ar' ? '/ar' : '');
  const first = useRef(true);
  const load = async () => {
    setSt((s) => ({ ...s, loading: true, err: '' }));
    const f = first.current; first.current = false;
    const j = await (f ? firstRead(token, 'sup_tab:billing') : call('supplier_pay', { action: 'list' }, token));
    if (j && j.ok) { setSt({ loading: false, dues: j.dues || [], total: Number(j.total_owed || 0), err: '' }); return; }
    // "Nothing to pay" and "we could not read your balance" must never look the same to someone who
    // owes money and is accruing interest on it (SP-C-08).
    if (wentExpired(j, onExpired, (c) => setSt({ loading: false, dues: [], total: 0, err: c }))) return;
    setSt({ loading: false, dues: [], total: 0, err: (j && (j.code || j.error)) || 'load_err' });
  };
  useEffect(() => { load(); }, [token]);
  // A disputed charge goes to the sales engineer, who has the accountant check it against the payment
  // record; the answer arrives by email from customer_support.
  // It said NOTHING between the prompt and the alert (18 Sep 2026) — on a slow line the supplier had
  // no way to tell a sent dispute from an ignored press, and could send the same one twice. useBusy
  // closes the double-press window from ms 0 and carries the ring after 150ms.
  // THE PORTAL'S OWN DIALOG, NOT THE BROWSER'S (walk of 12 Nov 2026, S10; founder ruling 1645): the reason was asked in
  // window.prompt (a one-line system box) and the answer given in window.alert. Now a dialog with a full reason box (16 px on a
  // phone), Send that turns while it sends and cannot be pressed twice, and the answer said in the dialog in plain words.
  // English only (ruling 1008).
  const disp = useBusy();
  const [disputeOf, setDisputeOf] = useState(null); const [reason, setReason] = useState(''); const [disputeAns, setDisputeAns] = useState(null);
  const openDispute = (dueId) => { setDisputeOf(dueId); setReason(''); setDisputeAns(null); };
  const dispute = async () => {
    const dueId = disputeOf; const why = reason.trim();
    if (!why) { setDisputeAns({ ok: false, m: DISPUTE.need_reason }); return; }
    const j = await disp.run('d' + dueId, () => call('supplier_api', { action: 'dispute_charge', due_id: dueId, reason: why }, token));
    setDisputeAns(j && j.ok ? { ok: true, m: DISPUTE.sent } : { ok: false, m: DISPUTE.failed });
  };
  const pay = async () => {
    setBusy(true);
    const j = await call('supplier_pay', { action: 'checkout', return_url: base() }, token);
    if (j && j.ok && j.url) { window.location.href = j.url; return; }
    setBusy(false);
    setSt((s) => ({ ...s, err: 'checkout_err' }));
  };
  let dues;
  if (st.loading) dues = <Card className="qd-panel p-5">{t(lang, 'loading_dash')}</Card>;
  else if (st.err) dues = <Card className="qd-panel p-5"><div className={S.h2}>{t(lang, 'something_wrong')}</div><div className={S.sub}>{t(lang, 'bill_err')}</div><Button className="mt-3" onClick={load}>{t(lang, 'bill_retry')}</Button></Card>;
  else if (!st.dues.length) dues = <Card className="qd-panel p-5"><div className={S.h2}>{t(lang, 'bill_title')}</div><div className={S.sub}>{t(lang, 'bill_none')}</div></Card>;
  else dues = (
    <Card className="qd-panel p-5">
      <div className={S.h2}>{t(lang, 'bill_title')}</div>
      <div className="flex flex-col gap-2 my-3">
        {st.dues.map((d) => (
          // ONE ROW THAT FITS A PHONE (walk of 12 Nov 2026, S9): at 360 px "Due ..." and "Dispute this charge" were crushed into a 42 px
          // column, one word per line. Under 640 px the due date and the dispute button go under the amount, full width.
          <div key={d.id} className="flex flex-col gap-1 border-b border-border pb-2 text-[13.5px] sm:flex-row sm:items-center sm:justify-between" data-testid="bill-due-row">
            <div>
              <div className="font-semibold tabular-nums"><Ltr>{aed(lang, d.amount)}</Ltr></div>
              {/* A part that is zero is not shown: three lines reading AED 0 say nothing and hide the one
                  that is not. `interest` already carries the fine, as supplier_pay adds them together. */}
              <div className={S.sub}>{[
                ['bill_refund', d.refunded_fee], ['bill_admin', d.admin_fee], ['bill_interest', d.interest],
              ].filter(([, v]) => Number(v) > 0).map(([k, v], i) => (
                <span key={k}>{i ? ' · ' : ''}{t(lang, k)} <Ltr>{aed(lang, v)}</Ltr></span>
              ))}</div>
            </div>
            {/* text-end, not text-right: on /ar the column sits on the left and this pinned it right. */}
            <div className="flex flex-wrap items-center gap-x-3 sm:block sm:shrink-0 sm:text-end">
              <div className={S.sub}>{d.due_date ? <>{t(lang, 'bill_due')} <Ltr>{fmtDate(d.due_date, lang)}</Ltr></> : ''}</div>
              <button type="button" data-testid="bill-dispute" disabled={disp.pending}
                className="inline-flex min-h-11 items-center gap-1.5 whitespace-nowrap text-[13px] pointer-coarse:text-[14px] underline text-muted-foreground disabled:opacity-60" onClick={() => openDispute(d.id)}>
                {DISPUTE.open}
              </button>
            </div>
          </div>
        ))}
      </div>
      <Dialog open={disputeOf != null} onOpenChange={(o) => { if (!o && !disp.busy) setDisputeOf(null); }}>
        <DialogContent data-testid="bill-dispute-dialog" onInteractOutside={(e) => { if (disp.busy) e.preventDefault(); }}>
          <DialogHeader><DialogTitle>{DISPUTE.title}</DialogTitle><DialogDescription>{DISPUTE.lead}</DialogDescription></DialogHeader>
          {disputeAns && disputeAns.ok
            ? <p role="status" className="text-[15px] font-semibold text-primary">{disputeAns.m}</p>
            : <label className="block"><span className="mb-1 block text-[13px] font-semibold text-muted-foreground">{DISPUTE.reason}</span>
                <textarea rows={4} maxLength={1000} value={reason} disabled={disp.busy} onChange={(e) => { setReason(e.target.value); setDisputeAns(null); }}
                  className="flex w-full resize-y rounded-md border border-input bg-transparent px-3 py-2.5 text-[15px] pointer-coarse:text-[16px] text-foreground placeholder:text-muted-foreground focus-visible:outline-hidden focus-visible:ring-1 focus-visible:ring-ring" /></label>}
          {disputeAns && !disputeAns.ok ? <p role="alert" className="text-[14px] font-semibold text-danger-fg">{disputeAns.m}</p> : null}
          <DialogFooter>
            {disputeAns && disputeAns.ok
              ? <Button onClick={() => setDisputeOf(null)}>{DISPUTE.close}</Button>
              : <><Button variant="outline" disabled={disp.busy} onClick={() => setDisputeOf(null)}>{DISPUTE.cancel}</Button>
                  <Button data-testid="bill-dispute-send" busy={disp.busy} disabled={disp.pending} onClick={dispute}>{disp.busy ? DISPUTE.sending : DISPUTE.send}</Button></>}
          </DialogFooter>
        </DialogContent>
      </Dialog>
      <div className="flex justify-between items-center mt-3 flex-wrap gap-3">
        <div>
          <div className={S.sub}>{t(lang, 'bill_total')}</div>
          <div className="text-[20px] font-extrabold text-foreground tabular-nums"><Ltr>{aed(lang, st.total)}</Ltr></div>
        </div>
        <Button onClick={pay} disabled={busy}>{busy ? t(lang, 'bill_paying') : t(lang, 'bill_pay')}</Button>
      </div>
      <div className={cn(S.sub, 'mt-3')}>{t(lang, 'bill_secure')}</div>
    </Card>
  );
  return <div className={S.list}>{receipt ? <ReceiptBanner receipt={receipt} lang={lang} /> : null}{dues}<Receipts token={token} lang={lang} onExpired={onExpired} /><RegistrationFeeCard token={token} lang={lang} base={base} /></div>;
}
// A supplier's own document as PDF (supplier_api receipt_pdf, 15 Sep 2026), through the same popup-safe
// door the customer's quotation uses (src/lib/openDocument.ts). English only: an Arabic-copy link sat
// beside it until 13 Oct 2026 (founder ruling 1008; scripts/checks/nothing_a_supplier_reads_can_be_arabic.test.mjs).
function PdfLink({ fetchPdf }) {
  const [busy, setBusy] = useState(false); const [msg, setMsg] = useState('');
  const open = async (e) => {
    e.stopPropagation(); setBusy(true); setMsg('');
    const ok = await openDocument('en', async () => { const j = await fetchPdf(); return j && j.ok && j.url ? j.url : null; });
    setBusy(false); if (!ok) setMsg('The document could not be prepared. Please try again.');
  };
  return (<span className="inline-flex flex-wrap items-center gap-x-3 gap-y-1">
    <button type="button" className="inline-flex min-h-11 items-center text-primary font-semibold text-[12.5px] focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring" disabled={busy} onClick={open}>{busy ? 'Preparing…' : 'Download PDF'}</button>
    {msg ? <span role="alert" className="text-[12px] text-danger-fg">{msg}</span> : null}
  </span>);
}
// Receipts for the dues this supplier has paid (supplier_api receipts). Nothing paid, nothing shown.
//
// ONE FEE, ONE NAME (audit 22 Sep 2026, SP-I-08). The row below called it the "Annual listing fee"
// and the card further down the same tab called it the "Yearly registration fee" — two names in
// English and three in Arabic for the single fee of clause 6. The signed Supplier Agreement v12
// (src/content/legal.json, key "supplier-agreement"; clause 2 defines it, clause 6 sets it) calls
// it the Subscription Fee, and that is the name every surface uses now. "Registration" in clause
// 6's heading is the act of registering — free for the first 1,000 — not the fee's name.
function Receipts({ token, lang, onExpired }) {
  const ar = lang === 'ar';
  const [list, setList] = useState([]);
  // An expired token answered 401 and this rendered null — "you have paid nothing" (SP-C-08).
  useEffect(() => { let live = true; call('supplier_api', { action: 'receipts' }, token).then((j) => { if (!live) return; if (wentExpired(j, onExpired)) return; setList((j && j.ok && j.receipts) || []); }).catch(() => {}); return () => { live = false; }; }, [token]);
  if (!list.length) return null;
  return (
    <Card className="qd-panel p-5">
      <div className={S.h2}>{ar ? 'إيصالات الدفع' : 'Payment receipts'}</div>
      <ul className="mt-3 flex flex-col gap-2">{list.map((r) => (
        <li key={(r.kind || 'dues') + ':' + (r.id ?? r.paid_at)} className="flex flex-wrap items-center justify-between gap-2 border-b border-border pb-2 text-[13.5px]">
          <span>{r.kind === 'registration' ? (ar ? 'رسوم الاشتراك السنوية · ' : 'Annual subscription fee · ') : ''}<Ltr className="font-semibold tabular-nums">{aed(lang, r.total)}</Ltr> · <Ltr>{fmtDate(r.paid_at, lang)}</Ltr></span>
          {/* A paid receipt is sealed: View / Download work, Replace / Remove say why not (instruction 524). */}
          <span className="inline-flex flex-wrap items-center gap-3">
            <DocActions lang={lang} name={'receipt-' + (r.id ?? 'registration') + '.pdf'} sealed="paid_invoice"
              getUrl={async () => { const j = await call('supplier_api', { action: 'receipt_pdf', kind: r.kind, due_id: r.id, lang: 'en' }, token); return j && j.ok && j.url ? j.url : null; }} />
            {/* OUR invoice for the same payment (audit 22 Sep 2026, finding 2): Stripe issues none. */}
            <span className="text-[12px] text-muted-foreground">{ar ? 'الفاتورة:' : 'Invoice:'}</span>
            <PdfLink fetchPdf={() => call('supplier_api', { action: 'receipt_pdf', doc: 'invoice', kind: r.kind, due_id: r.id, lang: 'en' }, token)} />
          </span>
        </li>))}</ul>
    </Card>
  );
}
export { BillingPanel };
