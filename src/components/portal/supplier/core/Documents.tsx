// @ts-nocheck
'use client';
import { useEffect, useRef, useState } from 'react';
import DocActions from '../../DocActions';
import { srvMsg, srvText } from '../serverCopy';
import { call, REASONING_TIMEOUT_MS, tooBigToRead, sizeMb } from '../api';
import { panelErrorText } from '../PanelState';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import { Ltr } from '@/lib/Ltr';
import { wentExpired, fmtDate, FilePick } from './helpers';
import { uploadDirect, fileToB64 } from './upload';
import { t } from './copy';
import { S } from './styles';
import { expiredLicenceNote, licenceHasExpired, licenceBeingRead, LICENCE_BEING_READ_NOTE } from '../licenceExpiry';

// VERIFIED BADGES (backlog T3): what customers see on this supplier's anonymised quotes, and what is
// still needed to earn each. English only — suppliers read English (28 Sep 2026).
function VerifiedBadges({ b }) {
  const rows = [
    { key: 'licence_verified', label: 'Licence verified' },
    { key: 'documents_complete', label: 'Documents complete' },
  ];
  return <Card className="qd-panel p-5" dir="ltr" lang="en">
    <div className={S.h2}>Your badges</div>
    <div className={cn(S.sub, 'mt-1')}>Customers see these on your quotes. Your company name stays hidden until they reveal you.</div>
    <ul className="mt-3 space-y-2">
      {rows.map((r) => {
        const on = !!b[r.key]; const need = (b.to_earn && b.to_earn[r.key]) || [];
        return <li key={r.key} className="flex items-start gap-2">
          <Badge variant={on ? 'ok' : 'outline'}>{on ? 'Earned' : 'Not yet'}</Badge>
          <div><div className="text-[14px] font-semibold">{r.label}</div>
            {!on && need.length > 0 && <ul className={cn(S.sub, 'list-disc ps-4')}>{need.map((n) => <li key={n}>{n}</li>)}</ul>}</div>
        </li>;
      })}
    </ul>
  </Card>;
}
function Documents({ token, lang, onSaved = null, onExpired = null }) {
  const [data, setData] = useState(null); const [busy, setBusy] = useState('');
  // On a failed read `data.documents` was undefined and every row vanished: a supplier whose licence
  // is on file was shown an empty checklist (SP-C-08). A failure keeps `data` null and `loadErr` says so.
  const [loadErr, setLoadErr] = useState('');
  const load = () => call('supplier_portal', { action: 'documents' }, token).then((j) => {
    if (wentExpired(j, onExpired)) return j;
    if (j && j.ok) { setData(j); setLoadErr(''); } else setLoadErr((j && (j.code || j.error)) || 'load_failed');
    return j;
  });
  // ONE READ AFTER EVERY WRITE (audit 21 Sep 2026, finding 16): save_documents, remove_document and
  // set_expiry answer with the fresh list, so the card, the counter and the unlock panel are painted
  // from the row as it is NOW. A second `documents` round trip used to race the write.
  const take = (j) => { if (j && Array.isArray(j.documents)) setData({ ok: true, documents: j.documents, expiries: j.expiries || [], summary: j.summary }); else load(); };
  useEffect(() => { load(); }, [token]);
  // READ AFTER THE ANSWER (19 Oct 2026): while the list says a profile or catalogue is still being read, ask again
  // every 5 seconds (for at most 10 minutes) so the tab refreshes to the result by itself.
  const readingNow = !!(data && Array.isArray(data.reading) && data.reading.length);
  const polls = useRef(0);
  useEffect(() => {
    if (!readingNow) { polls.current = 0; return; }
    if (polls.current >= 120) return;
    const id = setTimeout(() => { polls.current += 1; load(); }, 5000);
    return () => clearTimeout(id);
  }, [readingNow, data]);
  // `err` is a string or, for an Arabic per-file failure, a small JSX fragment; it is only rendered.
  const [err, setErr] = useState('');
  // What the server READ off each uploaded file (instruction 524): the expiry it found, or that it
  // could not find one. Shown to the supplier to confirm; never written for them unconfirmed.
  const [reads, setReads] = useState({});
  // The server reports per-file failures now. Previously a failed storage write was swallowed and
  // the kind still came back as saved, so a supplier could be told their licence was on file when
  // nothing had been written. Surface it instead of reloading over the top of it.
  const upload = async (kind, file, expiry) => {
    setErr('');
    // A file read before the answer is refused here above MAX_READ_BYTES, before it is sent (supplier/api.ts).
    if (kind !== 'profile' && kind !== 'catalogs' && tooBigToRead(file)) { setErr(srvText(lang, 'file_too_large_read', { mb: sizeMb(file) })); return; }
    setBusy(kind);
    let item;
    if (kind === 'profile' || kind === 'catalogs') {
      const d = await uploadDirect(kind === 'profile' ? 'profile' : 'catalogue', file, token);
      if (d.error) { setBusy(''); setErr(srvMsg(lang, d.error, srvText(lang, 'direct_upload_failed'))); return; }
      item = { kind, path: d.path, filename: d.filename, mime: d.mime, expiry };
    } else item = { kind, original_b64: await fileToB64(file), filename: file.name, mime: file.type, expiry };
    // A LICENCE OR CERTIFICATE IS READ BEFORE THE ANSWER (28 Oct 2026, sales_engineer; production document walk e8d1e4b5):
    // a phone photo of a licence answered in 18,019 ms (the model's read, ~9-16 s), two seconds inside the 20 s every
    // other call keeps. A slower read was cut off and the supplier told the save failed while the file was on record.
    const j = await call('supplier_portal', { action: 'save_documents', items: [item] }, token, { timeoutMs: REASONING_TIMEOUT_MS });
    setBusy('');
    if (j && j.read) setReads((o) => ({ ...o, ...j.read }));
    const failed = (j && j.failed) || [];
    // The server's per-file reasons are English sentences; an Arabic page says the same thing in Arabic.
    // The Arabic sentence used to REPLACE the reason, so an Arabic supplier never learned why (audit 15 Sep
    // 2026). The server's specific reason is kept after it, isolated left-to-right.
    if (failed.length) { const why = failed.map((f) => f.reason).filter(Boolean).join('; '); setErr(lang === 'ar' ? <>تعذّر حفظ الملف. يُرجى رفع نسخة PDF أو صورة واضحة للمستند كاملًا، ثم المحاولة مرة أخرى.{why ? <> السبب: <Ltr>{why}</Ltr></> : null}</> : 'Upload failed: ' + why); }
    else if (j && (j.error || j._http)) setErr(srvMsg(lang, j, lang === 'ar' ? 'تعذّر حفظ الملف. يُرجى المحاولة مرة أخرى.' : 'We could not save that file. Please try again.'));
    take(j);
    if (j && j.ok && onSaved) onSaved();
  };
  // REMOVE hides, never destroys; the server refuses a sealed record with a sentence in this language.
  const remove = async (kind, path) => {
    setErr('');
    const j = await call('supplier_portal', { action: 'remove_document', kind, path, lang }, token);
    if (j && j.ok) { setReads((o) => { const n = { ...o }; delete n[kind]; return n; }); take(j); if (onSaved) onSaved(); return { ok: true }; }
    return { ok: false, message: (j && j.message) || srvMsg(lang, j, lang === 'ar' ? 'تعذّرت الإزالة. يُرجى المحاولة مرة أخرى.' : 'Could not remove. Please try again.') };
  };
  // The supplier confirms (or corrects) the date the document was read to say.
  const confirmExpiry = async (kind, expiry) => {
    setErr('');
    const j = await call('supplier_portal', { action: 'set_expiry', kind, expiry }, token);
    if (j && j.ok) { setReads((o) => { const n = { ...o }; delete n[kind]; return n; }); take(j); if (onSaved) onSaved(); return true; }
    setErr(srvMsg(lang, j, lang === 'ar' ? 'تعذّر حفظ التاريخ.' : 'Could not save the date.')); return false;
  };
  if (!data && loadErr) return <Card role="alert" className="qd-panel p-5"><div className={S.h2}>{t(lang, 'something_wrong')}</div><div className={S.sub}>{panelErrorText(lang === 'ar' ? 'ar' : 'en', loadErr)}</div><Button className="mt-3" onClick={load}>{t(lang, 'bill_retry')}</Button></Card>;
  if (!data) return <Card className="qd-panel p-5" aria-busy="true">{t(lang, 'loading_docs')}</Card>;
  // Order comes from the server (DOC_ORDER) so adding a document type needs no change here.
  const allDocs = data.documents || [];
  // Count only what is actually shown. The server still returns vat, and counting it would report
  // "2/8 on file" against a list of seven — a completeness bar that can never fill.
  const shownKeys = new Set(DOC_GROUPS.flatMap((g) => g.keys));
  const docs = allDocs.filter((d) => shownKeys.has(d.key));
  const sum = { on_file: docs.filter((d) => d.status !== 'missing').length, total: docs.length };
  const attention = docs.filter((d) => d.status === 'expired' || d.status === 'expiring');
  const missingReq = docs.filter((d) => d.required && d.status === 'missing');
  return <div className={S.list}>
    <Card className="qd-panel p-5">
      <div className="flex justify-between items-start gap-3 flex-wrap">
        <div>
          <div className={S.h2}>{t(lang, 'docs_h')}</div>
          <div className={cn(S.sub, 'mt-1')}>{lang === 'ar'
            ? 'الرخصة التجارية والملف التعريفي للشركة مطلوبان للتسجيل، ويجب أن تبقى الرخصة سارية لتستمر الطلبات في الوصول إليكم. وكل ما عدا ذلك اختياري.'
            : 'Your trade licence and company profile are required to register, and the licence must stay valid to keep receiving requests. Everything else is optional.'}</div>
        </div>
        <div className="text-end shrink-0">
          <div className="text-[22px] font-extrabold text-foreground leading-none"><Ltr>{sum.on_file ?? 0}<span className="text-muted-foreground text-[15px]">/{sum.total ?? docs.length}</span></Ltr></div>
          <div className={S.sub}>{lang === 'ar' ? 'على الملف' : 'on file'}</div>
        </div>
      </div>
      {/* Completeness bar — one glance at how far off "complete" they are. */}
      <div className="mt-3 h-2 rounded-full bg-secondary/60 overflow-hidden" role="progressbar"
           aria-valuenow={sum.on_file ?? 0} aria-valuemin={0} aria-valuemax={sum.total ?? docs.length}
           aria-label={lang === 'ar' ? 'اكتمال المستندات' : 'Document completeness'}>
        <div className="h-full bg-primary transition-[width] duration-700 motion-reduce:transition-none"
             style={{ width: (sum.total ? Math.round(100 * (sum.on_file || 0) / sum.total) : 0) + '%' }} />
      </div>
      {(!!missingReq.length || !!attention.length) && <div className="flex gap-2 flex-wrap mt-3">
        {!!missingReq.length && <Badge variant="destructive">{missingReq.length} {lang === 'ar' ? 'مطلوب ومفقود' : (missingReq.length === 1 ? 'required document missing' : 'required documents missing')}</Badge>}
        {!!attention.length && <Badge variant="warn">{attention.length} {lang === 'ar' ? 'بحاجة إلى انتباه' : 'needs attention'}</Badge>}
      </div>}
      {readingNow && <div className={cn(S.sub, 'mt-3')} role="status">{srvText(lang, 'documents_reading_now')}</div>}
      {err && <div className={cn(S.err, 'mt-3')}>{err}</div>}
    </Card>
    {data.badges && <VerifiedBadges b={data.badges} />}
    {DOC_GROUPS.map((g) => {
      const rows = g.keys.map((k) => docs.find((d) => d.key === k)).filter(Boolean);
      if (!rows.length) return null;
      return <div key={g.id} className={S.section}>
        <div className="px-1 pt-2 pb-1">
          <div className="text-[12px] font-bold tracking-[.04em] uppercase text-muted-foreground/90">{g.title(lang)}</div>
          {g.note && <div className={cn(S.sub, 'mt-1')}>{g.note(lang)}</div>}
        </div>
        <div className={S.list}>
          {rows.map((d) => <DocRow key={d.key + '|' + (d.path || '') + '|' + (d.expiry || '')} d={d} lang={lang} busy={busy === d.key} onUpload={upload} onRemove={remove} onConfirmExpiry={confirmExpiry} read={reads[d.key] || null} />)}
        </div>
      </div>;
    })}
  </div>;
}
// Grouped by what each document actually gates, because eight identical "Not uploaded" badges in one
// list reads as eight blockers. Only the first group can stop a supplier being verified; the second is
// framed by what it UNLOCKS rather than as an unmet requirement.
//
// VAT is deliberately absent: their TRN is already read off the trade licence automatically, so the VAT
// certificate was asking for something we had. The backend still supports the type; this removes the ask.
// Bank details are absent EVERYWHERE since 21 Sep 2026 (founder instruction 527): money moves both directions
// through Stripe — customers pay us, and a supplier settling a due pays us the same way — so the estate
// never holds a supplier's bank details. The IBAN document type and the bank columns were removed.
const DOC_GROUPS = [
  // Required = the documents in the mandatory six (supabase/functions/_shared/supplier_registration.ts
  // REQUIRED_DOC_KEYS). Catalogues were in this group while the server marked only the licence
  // required; they are optional, and now sit with the other optional documents.
  { id: 'required', keys: ['license', 'profile'],
    title: (l) => (l === 'ar' ? 'مطلوب للتحقق' : 'Required to get verified'),
    note: (l) => (l === 'ar'
      ? 'الرخصة التجارية والملف التعريفي للشركة، ونستخلص منهما نشاطكم لنحدد الطلبات التي نرسلها إليكم.'
      : 'Your trade licence and company profile. We read these to work out what work to send you.') },
  { id: 'optional', keys: ['catalogs', 'insurance', 'iso', 'manufacturer', 'egr'],
    title: (l) => (l === 'ar' ? 'اختياري — للحصول على مطابقات أكثر' : 'Optional — get matched to more work'),
    note: (l) => (l === 'ar'
      ? 'لا يُشترط أيٌّ منها للتحقق، لكن كل مستند تضيفونه يفتح لكم طلبات إضافية؛ فبعض العملاء يشترطون التأمين، وخطاب الوكالة يتيح لنا مطابقتكم عندما يطلب العميل علامة تجارية بعينها.'
      : 'None of these are needed to be verified. Each one you add opens up more requests — some customers require insurance, and a dealer letter lets us match you when a customer names a brand you carry.') },
];
// Every document type is editable here. The trade licence and company profile used to be
// deliberately read-only (editable={d.key !== 'license' && d.key !== 'profile'}), and the only
// licence upload in the product lived in ProfileForm, which renders solely while the account has
// no company yet. An established supplier whose licence expired therefore had nowhere to replace
// it — while receiving alerts telling them to do exactly that. Now that expiry suspends matching,
// that dead end would have been an account they could not reopen.
// Storage paths are prefixed with an epoch stamp to keep uploads unique, so the filename the
// server falls back to reads as "1784642799037_catalogue-vrf-2026.pdf". Only license and egr
// have a dedicated name column; everything else shows the path tail. Strip the stamp for
// display so the supplier sees the name they actually uploaded.
const cleanName = (n) => String(n || '').replace(/^\d{10,}_/, '');
// What the server read off the file, said back to the supplier (instruction 524). Three shapes:
// the licence's date (written from the licence, shown as a fact); a certificate's date (shown with
// Confirm, and a box to correct it — nothing is written until they do); or that nothing could be
// read, said plainly, in which case the date box below is how the supplier tells us.
function ExpiryRead({ read, lang, label, onConfirm }) {
  const ar = lang === 'ar';
  const [val, setVal] = useState(read && read.expiry ? read.expiry : ''); const [busy, setBusy] = useState(false);
  if (!read) return null;
  // our reader has not finished (#1909, licence_being_read): ours to do, so nothing is asked of the supplier (11 Nov 2026)
  if (licenceBeingRead(read)) return <div className={cn(S.sub, 'mt-2')} role="status" data-testid="licence-being-read">{LICENCE_BEING_READ_NOTE}</div>;
  // a file that is not a licence, named by what the model is sure it is (founder ruling 1668): suppliers read English (ruling 1008)
  if (read.wrong_document) return <div className={cn(S.sub, 'mt-2 font-semibold text-destructive')} role="alert" data-testid="licence-wrong-document">{read.message}</div>;
  if (read.unread) return <div className={cn(S.sub, 'mt-2')} role="status">{ar
    ? `تعذّرت قراءة تاريخ الانتهاء من هذا الملف تلقائيًا (${read.kind === 'license' ? 'يُرجى رفع نسخة PDF واضحة من الرخصة كاملة' : 'يُرجى إدخاله أدناه وسنحفظه'}).`
    : `We could not read the expiry date from this file automatically${read.kind === 'license' ? ' — please upload a clear PDF of the full licence' : ' — enter it below and we will save it'}.`}</div>;
  // An expired licence is said where it is read (11 Nov 2026, registration certification finding 6; ../licenceExpiry.ts).
  if (read.kind === 'license' && licenceHasExpired(read.expiry)) return <div className={cn(S.sub, 'mt-2 font-semibold text-destructive')} role="alert" data-testid="licence-expired">{expiredLicenceNote(read.expiry)}</div>;
  if (!read.needs_confirm) return <div className={cn(S.sub, 'mt-2')} role="status">{ar ? 'قرأنا من المستند: ينتهي في ' : 'Read from the document: expires '}<Ltr>{fmtDate(read.expiry, lang)}</Ltr>{read.source === 'ai' ? (ar ? ' (قراءة آلية)' : ' (machine-read)') : ''}</div>;
  const save = async (v) => { setBusy(true); await onConfirm(read.kind, v); setBusy(false); };
  return <div className="mt-2 flex flex-wrap items-center gap-2" role="status">
    <span className={S.sub}>{ar ? 'قرأنا من المستند: ينتهي في ' : 'We read from the document: expires '}<Ltr>{fmtDate(read.expiry, lang)}</Ltr>{read.typed && read.typed !== read.expiry ? (ar ? ` (أدخلتم ${read.typed})` : ` (you typed ${read.typed})`) : ''} — {ar ? 'هل هذا صحيح؟' : 'is that right?'}</span>
    <Button size="sm" disabled={busy} onClick={() => save(read.expiry)}>{ar ? 'تأكيد' : 'Confirm'}</Button>
    <Input type="date" dir="ltr" className="w-auto" value={val} onChange={(e) => setVal(e.target.value)} aria-label={(ar ? 'تصحيح تاريخ انتهاء ' : 'Correct the expiry date for ') + label} />
    <Button size="sm" variant="outline" disabled={busy || !val || val === read.expiry} onClick={() => save(val)}>{ar ? 'حفظ التصحيح' : 'Save correction'}</Button>
  </div>;
}
function DocRow({ d, busy, onUpload, onRemove, onConfirmExpiry, read, lang }) {
  const [exp, setExp] = useState(d.expiry || ''); const [file, setFile] = useState(null);
  const ar = lang === 'ar';
  const label = ({ license: t(lang, 'h_trade'), profile: t(lang, 'doc_profile'), catalogs: t(lang, 'catalogues'), iso: t(lang, 'doc_iso'), insurance: t(lang, 'doc_insurance'), manufacturer: t(lang, 'doc_manufacturer'), egr: t(lang, 'doc_egr') })[d.key] || d.label;
  // Status is computed server-side so the badge, the alerts and the suspension job cannot disagree.
  const ST = {
    expired:  { t: ar ? 'منتهية' : 'Expired',      v: 'destructive' },
    expiring: { t: ar ? 'تنتهي قريبًا' : 'Expiring soon', v: 'warn' },
    valid:    { t: ar ? 'سارية' : 'Valid',          v: 'ok' },
    on_file:  { t: ar ? 'على الملف' : 'On file',    v: 'secondary' },
    unread:   { t: 'Could not be read', v: 'destructive' },
    being_read: { t: 'Being read', v: 'secondary' },   // our reader has not finished (supplier_portal/lib/documents.ts)
    missing:  { t: ar ? 'مفقود' : 'Not uploaded',   v: d.required ? 'destructive' : 'secondary' },
  };
  const st = ST[d.status] || null;
  const isCat = d.key === 'catalogs';
  const items = Array.isArray(d.items) ? d.items : [];
  return <Card className="qd-panel p-5">
    <div className="flex justify-between items-start gap-3 flex-wrap">
      <div className="min-w-[240px] flex-1">
        <div className="flex items-center gap-2 flex-wrap">
          <b className="text-foreground">{label}</b>
          {d.required && <Badge variant="secondary">{ar ? 'مطلوب' : 'Required'}</Badge>}
          {st && <Badge variant={st.v}>{st.t}</Badge>}
        </div>
        <div className={cn(S.sub, 'mt-1')}>{srvText(lang, d.hint_code, {}, d.hint)}</div>
        {/* What is actually on file, by name, so they can tell whether the right file went up. */}
        {!isCat && d.path && <div className={cn(S.sub, 'mt-1.5')}>
          <bdi className="text-foreground/80">{cleanName(d.name) || (ar ? 'ملف' : 'File')}</bdi>
          {d.expiry ? <> · {ar ? 'تنتهي ' : 'expires '}<Ltr>{fmtDate(d.expiry, lang)}</Ltr></> : null}
        </div>}
        {/* The four actions every document offers (instruction 524): View / Download / Replace / Remove.
            Replace re-runs the reading and keeps the previous version; Remove hides, never destroys, and
            the server refuses it on a mandatory document of an approved supplier, in this language. */}
        {/* ONE HOME PER SUBJECT (finding 17): a certificate filed under Supporting documents counts here
            too. It is managed where it was filed, so this row says so instead of offering a Remove that
            would find nothing in this slot. */}
        {!isCat && d.path && d.source === 'supporting' && <div className={cn(S.sub, 'mt-1.5')} role="note">{ar ? 'مرفوع ضمن «المستندات الداعمة» — يُدار من هناك.' : 'Filed under Supporting documents — manage it there.'}</div>}
        {!isCat && d.path && d.source !== 'supporting' && <DocActions lang={lang} name={cleanName(d.name)} url={d.url} versions={d.versions || 0} className="mt-2"
          onReplace={(f) => onUpload(d.key, f, '')} onRemove={() => onRemove(d.key)} />}
        {isCat && (items.length
          ? <ul className="mt-1.5 flex flex-col gap-2">{items.map((c, i) => <li key={c.path || i} className={S.sub}>
              <bdi className="text-foreground/80">{cleanName(c.name)}</bdi>
              <DocActions lang={lang} name={cleanName(c.name)} url={c.url} className="mt-1"
                onReplace={async (f) => { const r = await onRemove('catalogs', c.path); if (r && r.ok === false) throw new Error(r.message); await onUpload('catalogs', f, ''); }}
                onRemove={() => onRemove('catalogs', c.path)} />
            </li>)}</ul>
          : <div className={cn(S.sub, 'mt-1.5')}>{t(lang, 'not_uploaded')}</div>)}
        {!isCat && !d.path && <div className={cn(S.sub, 'mt-1.5')}>{t(lang, 'not_uploaded')}</div>}
        {d.status === 'being_read' && !read && <div className={cn(S.sub, 'mt-2')} role="status">{LICENCE_BEING_READ_NOTE}</div>}
        {d.wrong_document_message && !read && <div className={cn(S.sub, 'mt-2 font-semibold text-destructive')} role="alert" data-testid="licence-wrong-document">{d.wrong_document_message}</div>}
        {d.status === 'unread' && !read && !d.wrong_document_message && <div className={cn(S.sub, 'mt-2 text-danger-fg')} role="status">We could not read this licence. Please use Replace to upload a clear PDF, or a sharp photo of the whole page.</div>}
        <ExpiryRead read={read} lang={lang} label={label} onConfirm={onConfirmExpiry} />
      </div>
      {/* First upload (nothing on file) or another catalogue. A file on record is replaced from its own row above. */}
      {/* max-w-full (28 Oct 2026, 390 px production walk): as a shrink-0 flex item this row took its one-line width
          (Attach file + date + Upload, ~390 px) inside a ~318 px card, so Upload sat off-screen on Insurance, ISO and
          the dealer letter, and the whole page scrolled sideways. Bounded by the card, it wraps. */}
      {(!d.path || isCat) && <div className="flex gap-2 items-center flex-wrap shrink-0 max-w-full">
        <FilePick lang={lang} onPick={setFile} />
        {file && <span className={cn(S.sub, 'max-w-[180px] truncate')}>{file.name}</span>}
        {/* Not for the trade licence: its expiry is read off the licence itself and save_documents
            refuses a typed one (the #86 gate), so a date box there was a control that could only fail.
            For the others the box is optional now: the date is read off the file first (instruction 524). */}
        {d.has_expiry && d.key !== 'license' && <Input type="date" dir="ltr" className="w-auto" value={exp}
          onChange={(e) => setExp(e.target.value)} aria-label={(ar ? 'تاريخ انتهاء ' : 'Expiry date for ') + label} />}
        <Button size="sm" disabled={busy || !file} onClick={() => { onUpload(d.key, file, d.key === 'license' ? '' : exp); setFile(null); }}>
          {busy ? t(lang, 'uploading') : t(lang, 'upload')}
        </Button>
      </div>}
      {/* A certificate on file whose date is missing or wrong: the same box, without a new file. */}
      {d.path && !isCat && d.has_expiry && d.key !== 'license' && !read && <div className="flex gap-2 items-center flex-wrap shrink-0 max-w-full">
        <Input type="date" dir="ltr" className="w-auto" value={exp} onChange={(e) => setExp(e.target.value)} aria-label={(ar ? 'تاريخ انتهاء ' : 'Expiry date for ') + label} />
        <Button size="sm" variant="outline" disabled={busy || !exp || exp === (d.expiry || '')} onClick={() => onConfirmExpiry(d.key, exp)}>{ar ? 'حفظ التاريخ' : 'Save date'}</Button>
      </div>}
    </div>
  </Card>;
}
export { Documents };
