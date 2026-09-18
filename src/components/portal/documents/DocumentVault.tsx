'use client';
// SPEC §14 Document Intelligence Vault — the customer's surface over supabase/functions/customer_documents.
//
// "Not file storage. AI-powered." The spec's own worked example is a question and an answer:
//
//     Customer asks: "Find warranty documents for HVAC."
//     AI: Found: Warranty Contract / Supplier: ABC HVAC / Expiry: 2031 / Coverage: Full system
//
// So the ask box and the three-field answer are the requirement, and they are what this file leads
// with. The search runs over the EXTRACTION, not the filename — customer_documents ranks
// doc_extract's text, specifications, certifications and brands and widens through the customer's
// own RFQs — so a question can be a question rather than a substring of a file name.
//
// WHAT THIS FILE WILL NOT DO
// - It will not print an expiry the document does not state. `expiry_date === null` renders as
//   "Not stated on the document", never as a rounded year, and `expiry_source` names where a real
//   one came from. Same for `covers`.
// - It will not name a supplier the customer has not paid to reveal. `supplier === null` with
//   `supplier_revealed === false` renders as "Revealed when you unlock this quote", which is a
//   different sentence from "the document names no supplier" — and they are different facts.
// - It will not claim documents were found. Every empty state prints the endpoint's own
//   `empty_reason`/`note`, which says WHY the list is empty. The worst defect this portal has
//   shipped was an empty state that read the same whether or not anything had happened.
// - The kind filters are built from the `kinds` the endpoint actually returned, not from the six
//   kinds §14 names. A chip for a kind holding nothing is a promise the vault has not kept.
import * as React from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';
import {
  askDocuments, getDocument, documentsApi,
  type Lang, type VaultDocument, type VaultListResponse, type VaultSearchResponse,
} from './api';

// ---- words ------------------------------------------------------------------------------------
const EN = {
  title: 'Document vault',
  sub: 'Every drawing you upload, every quotation file a supplier sends you, and the licences and certificates of suppliers you have revealed — searchable by what is inside them, not just by file name.',
  ask_label: 'Ask your documents a question',
  ask_ph: 'e.g. Find warranty documents for HVAC',
  ask: 'Ask',
  asking: 'Searching…',
  clear: 'Clear',
  all_kinds: 'All',
  loading: 'Loading your vault…',
  retry: 'Retry',
  answer_h: 'Answer',
  matched_text: 'matched on what the document says',
  matched_related: 'matched through a linked request',
  f_supplier: 'Supplier',
  f_expiry: 'Expiry',
  f_coverage: 'Coverage',
  no_expiry: 'Not stated on the document',
  no_coverage: 'Not stated on the document',
  sup_locked: 'Revealed when you unlock this quote',
  sup_none: 'Your own upload',
  sup_unnamed: 'Not named on the document',
  from_field: 'from',
  src_inquiry: 'Filed against your request',
  src_quote: 'Sent with a quotation',
  src_supplier: 'From a supplier you revealed',
  not_extracted: 'Not read yet',
  extracting: 'Being read',
  open: 'Open file',
  opening: 'Preparing…',
  filed: 'Filed',
  specs: 'Specifications',
  certs: 'Certificates',
  brands: 'Brands',
  err_session: 'Your session has expired. Please sign in again.',
  err_unavailable: 'The vault is not available on this deployment. Nothing was read.',
  err_load: 'Could not load your vault.',
  err_open: 'Could not open that file.',
  empty_no_customer: 'This sign-in has no customer account on QuotesDone yet, so there are no documents to show.',
  empty_generic: 'Nothing has been filed to your vault yet.',
  kinds: {
    quotation: 'Quotations', quote: 'Quotations', contract: 'Contracts', invoice: 'Invoices',
    certificate: 'Certificates', drawing: 'Drawings', purchase_order: 'Purchase orders',
    licence: 'Licences', license: 'Licences', boq: 'Bills of quantities', warranty: 'Warranties',
  } as Record<string, string>,
  // Extraction keys an expiry/coverage came out of, shown as "from <source>".
  sources: { document: 'the document', filename: 'the file name', summary: 'the summary' } as Record<string, string>,
};

const AR: typeof EN = {
  title: 'خزانة المستندات',
  sub: 'كل رسم ترفعه، وكل ملف عرض سعر يرسله لك مورّد، ورخص وشهادات المورّدين الذين كشفت عنهم — قابلة للبحث بما بداخلها، لا باسم الملف فقط.',
  ask_label: 'اسأل مستنداتك',
  ask_ph: 'مثال: ابحث عن مستندات الضمان لأنظمة التكييف',
  ask: 'اسأل',
  asking: 'جارٍ البحث…',
  clear: 'مسح',
  all_kinds: 'الكل',
  loading: 'جارٍ تحميل خزانتك…',
  retry: 'إعادة المحاولة',
  answer_h: 'الإجابة',
  matched_text: 'مطابقة بما ورد في المستند',
  matched_related: 'مطابقة عبر طلب مرتبط',
  f_supplier: 'المورّد',
  f_expiry: 'تاريخ الانتهاء',
  f_coverage: 'نطاق التغطية',
  no_expiry: 'غير مذكور في المستند',
  no_coverage: 'غير مذكور في المستند',
  sup_locked: 'يُكشف عند فتح هذا العرض',
  sup_none: 'من رفعك أنت',
  sup_unnamed: 'غير مذكور في المستند',
  from_field: 'من',
  src_inquiry: 'مُرفق بطلبك',
  src_quote: 'مُرسل مع عرض سعر',
  src_supplier: 'من مورّد كشفت عنه',
  not_extracted: 'لم تتم قراءته بعد',
  extracting: 'قيد القراءة',
  open: 'فتح الملف',
  opening: 'جارٍ التحضير…',
  filed: 'أُرشِف',
  specs: 'المواصفات',
  certs: 'الشهادات',
  brands: 'العلامات',
  err_session: 'انتهت جلستك. يُرجى تسجيل الدخول من جديد.',
  err_unavailable: 'الخزانة غير متاحة على هذه النسخة. لم تتم أي قراءة.',
  err_load: 'تعذّر تحميل خزانتك.',
  err_open: 'تعذّر فتح هذا الملف.',
  empty_no_customer: 'لا يوجد حساب عميل مرتبط بتسجيل الدخول هذا، لذلك لا توجد مستندات لعرضها.',
  empty_generic: 'لم يُؤرشف أي مستند في خزانتك بعد.',
  kinds: {
    quotation: 'عروض الأسعار', quote: 'عروض الأسعار', contract: 'العقود', invoice: 'الفواتير',
    certificate: 'الشهادات', drawing: 'الرسومات', purchase_order: 'أوامر الشراء',
    licence: 'الرخص', license: 'الرخص', boq: 'جداول الكميات', warranty: 'الضمانات',
  },
  sources: { document: 'المستند', filename: 'اسم الملف', summary: 'الملخص' },
};

const W = (lang: Lang) => (lang === 'ar' ? AR : EN);

/** A kind we have a word for, else the raw kind made readable. Never a kind we made up. */
export function kindLabel(kind: string, lang: Lang = 'en'): string {
  const w = W(lang);
  return w.kinds[kind] || String(kind || '').replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase());
}

function errText(lang: Lang, code: string): string {
  const w = W(lang);
  if (code === 'Not signed in' || code === 'unauthorized') return w.err_session;
  if (code === 'documents_unavailable') return w.err_unavailable;
  return w.err_load;
}

const fmtDate = (iso: string | null, lang: Lang) => {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', { year: 'numeric', month: 'short', day: 'numeric' });
};

// ---- one field of the spec's answer -------------------------------------------------------------
/** Label + value, where a MISSING value is a sentence saying it is missing, not a blank or a guess.
 *  `source` is the extraction key the value came out of, shown only when there IS a value — it is
 *  provenance for a real figure, and printing it under "not stated" would suggest one exists. */
function Field({ label, value, missing, source, fromWord, sourceWords }: {
  label: string; value: string | null; missing: string; source?: string | null; fromWord?: string; sourceWords?: Record<string, string>;
}) {
  const has = !!value;
  return (
    <div className="min-w-0">
      <div className="text-[10.5px] font-semibold uppercase tracking-wide text-muted-foreground">{label}</div>
      <div className={cn('mt-0.5 text-[13px] font-semibold leading-snug break-words', has ? 'text-foreground' : 'text-muted-foreground font-normal italic')}>
        {has ? value : missing}
      </div>
      {has && source ? <div className="text-[10.5px] text-muted-foreground">{fromWord} {sourceWords?.[source] || source.replace(/_/g, ' ')}</div> : null}
    </div>
  );
}

function Chips({ label, items }: { label: string; items: string[] }) {
  if (!items || !items.length) return null;
  return (
    <div className="flex flex-wrap items-center gap-1.5">
      <span className="text-[10.5px] font-semibold uppercase tracking-wide text-muted-foreground">{label}</span>
      {items.slice(0, 8).map((s, i) => (
        <span key={i} className="rounded-full border border-border bg-secondary/40 px-2 py-0.5 text-[11px] text-foreground">{s}</span>
      ))}
    </div>
  );
}

// ---- one document -------------------------------------------------------------------------------
export interface DocumentRowProps {
  doc: VaultDocument;
  token: string;
  lang?: Lang;
  /** Hides the "matched through a linked request" note where every row matched the same way. */
  showMatch?: boolean;
  className?: string;
}

/**
 * One vault row, carrying the three fields §14 names — supplier, expiry, coverage — and saying
 * plainly when the document does not carry one. Exported because the Communication Center renders
 * the same row against a conversation; two components describing one document two ways is how a
 * portal starts disagreeing with itself.
 */
export function DocumentRow({ doc, token, lang = 'en', showMatch = false, className }: DocumentRowProps) {
  const w = W(lang);
  const [busy, setBusy] = React.useState(false);
  const [err, setErr] = React.useState('');

  // The tab is opened INSIDE the click, then pointed at the signed URL when it arrives. Opened after
  // the await, Safari and Firefox treat it as an unrequested popup and block it, so "Open file"
  // did nothing visible on those browsers.
  const openFile = async () => {
    setBusy(true); setErr('');
    const win = window.open('', '_blank');
    if (win) win.opener = null;
    const res = await getDocument(token, doc.id);
    setBusy(false);
    const url = res.ok ? res.data.document?.file_url : null;
    if (!url) { if (win) win.close(); setErr(w.err_open); return; }
    if (win) win.location.href = url; else window.open(url, '_blank', 'noopener,noreferrer');
  };

  // THREE DIFFERENT ABSENCES, THREE DIFFERENT SENTENCES. "not revealed yet" is not the same fact as
  // "you uploaded this yourself", and neither is "the document names nobody" — collapsing them is
  // how an empty state ends up reading the same whether or not anything happened.
  const supplierValue = doc.supplier;
  const supplierMissing = doc.source === 'quote' && !doc.supplier_revealed ? w.sup_locked
    : doc.source === 'inquiry' ? w.sup_none
    : w.sup_unnamed;
  const srcLabel = doc.source === 'quote' ? w.src_quote : doc.source === 'supplier' ? w.src_supplier : w.src_inquiry;

  return (
    <Card className={cn('p-4', className)}>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <Badge variant="secondary">{kindLabel(doc.kind, lang)}</Badge>
            {!doc.extracted ? (
              <span className="text-[11px] text-muted-foreground">
                {doc.extraction_status === 'done' ? w.not_extracted : w.extracting}
              </span>
            ) : null}
          </div>
          <div className="mt-1.5 break-all text-[14px] font-bold leading-snug text-foreground">
            {doc.file_name || kindLabel(doc.kind, lang)}
          </div>
          <div className="mt-0.5 text-[11.5px] text-muted-foreground">
            {srcLabel}
            {fmtDate(doc.created_at, lang) ? ` · ${w.filed} ${fmtDate(doc.created_at, lang)}` : ''}
            {showMatch && doc.match_reason === 'related_request' ? ` · ${w.matched_related}` : ''}
            {showMatch && doc.match_reason === 'text' ? ` · ${w.matched_text}` : ''}
          </div>
        </div>
        <Button type="button" variant="outline" size="sm" disabled={busy} onClick={openFile}>
          {busy ? w.opening : w.open}
        </Button>
      </div>

      {/* An invoice has no supplier, expiry or coverage to report; three "not stated" lines under it
          would read as missing data. It is the accountant's filed Stripe invoice (14 Sep 2026). */}
      {doc.kind === 'invoice' ? null : <div className="mt-3 grid gap-3 border-t border-border pt-3 sm:grid-cols-3">
        <Field label={w.f_supplier} value={supplierValue} missing={supplierMissing} />
        <Field label={w.f_expiry} value={fmtDate(doc.expiry_date, lang)} missing={w.no_expiry} source={doc.expiry_source} fromWord={w.from_field} sourceWords={w.sources} />
        <Field label={w.f_coverage} value={doc.covers} missing={w.no_coverage} source={doc.covers_source} fromWord={w.from_field} sourceWords={w.sources} />
      </div>}

      {doc.summary ? <p className="mt-3 text-[12.5px] leading-relaxed text-muted-foreground">{doc.summary}</p> : null}

      {(doc.specifications?.length || doc.certifications?.length || doc.brands?.length) ? (
        <div className="mt-3 space-y-1.5">
          <Chips label={w.specs} items={doc.specifications} />
          <Chips label={w.certs} items={doc.certifications} />
          <Chips label={w.brands} items={doc.brands} />
        </div>
      ) : null}

      {err ? <div role="alert" className="mt-2 text-[12px] text-destructive">{err}</div> : null}
    </Card>
  );
}

// ---- the vault -----------------------------------------------------------------------------------
export interface DocumentVaultProps {
  /** Customer Supabase JWT — the same token CustomerPortal already holds. */
  token: string;
  lang?: Lang;
  /** Change this to force a refetch after something files a new document. */
  refreshKey?: number;
  className?: string;
}

export function DocumentVault({ token, lang = 'en', refreshKey = 0, className }: DocumentVaultProps) {
  const w = W(lang);
  const [res, setRes] = React.useState<VaultListResponse | VaultSearchResponse | null>(null);
  const [kinds, setKinds] = React.useState<string[]>([]);
  const [kind, setKind] = React.useState<string | null>(null);
  const [q, setQ] = React.useState('');
  const [asked, setAsked] = React.useState('');
  const [busy, setBusy] = React.useState(false);
  const [err, setErr] = React.useState('');
  const [reloads, setReloads] = React.useState(0);

  // The plain list. Its `kinds` are the vault's real taxonomy and are kept across a filtered
  // refetch, so filtering to Drawings does not make every other chip vanish.
  React.useEffect(() => {
    let live = true;
    if (asked) return;
    setRes(null); setErr('');
    // The request is written out here rather than hidden behind listDocuments(): the endpoint and
    // the action belong beside the component that renders the answer, so "which surface asks for
    // the vault, and with what" is one grep rather than a hop through a helper. Same reason
    // approvals/api.ts names its function as a literal instead of interpolating it into a URL.
    documentsApi<VaultListResponse>(token, { action: 'documents', kind: kind || null, limit: 100 }).then((r) => {
      if (!live) return;
      if (!r.ok) { setErr(errText(lang, r.error)); setRes(null); return; }
      setRes(r.data);
      if (!kind && Array.isArray(r.data.kinds)) setKinds(r.data.kinds);
    });
    return () => { live = false; };
  }, [token, lang, kind, refreshKey, reloads, asked]);

  const ask = async (e?: React.FormEvent, k: string | null = kind) => {
    e?.preventDefault();
    const text = q.trim();
    if (!text) return;
    setBusy(true); setErr(''); setRes(null);
    const r = await askDocuments(token, text, k);
    setBusy(false);
    if (!r.ok) { setErr(errText(lang, r.error)); setAsked(text); return; }
    setAsked(text);
    setRes(r.data);
  };

  const clear = () => { setAsked(''); setQ(''); setRes(null); setReloads((n) => n + 1); };
  // A kind chip filters whichever view is on screen. While a question was active the list effect
  // exits early, so a chip lit up and the answers did not change; it now re-asks under that kind.
  const pickKind = (k: string | null) => { setKind(k); if (asked) void ask(undefined, k); };

  // The two ways this list is in flight: the question (`busy`) and the plain refetch, which clears
  // `res` and already renders the skeleton cards below.
  const reloading = busy || (!res && !err);

  const docs = res?.documents || [];
  const answer = (res as VaultSearchResponse | null)?.answer || null;
  const matched = (res as VaultSearchResponse | null)?.matched_by;

  return (
    <section className={cn('flex flex-col gap-4', className)} dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      <header>
        <h2 className="text-xl font-extrabold text-foreground">{w.title}</h2>
        <p className="mt-1 max-w-3xl text-[13px] leading-relaxed text-muted-foreground">{w.sub}</p>
      </header>

      {/* §14's worked example is a QUESTION. This is the control that asks it. */}
      <form onSubmit={ask} className="flex flex-wrap items-center gap-2">
        <label htmlFor="qd-doc-ask" className="sr-only">{w.ask_label}</label>
        <input
          id="qd-doc-ask"
          type="search"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder={w.ask_ph}
          className="min-w-0 flex-1 rounded-lg border border-border bg-secondary/40 px-3.5 py-2 text-[13.5px] text-foreground outline-none placeholder:text-muted-foreground focus:border-primary/60"
        />
        <Button type="submit" disabled={busy || !q.trim()}>{busy ? w.asking : w.ask}</Button>
        {asked ? <Button type="button" variant="ghost" onClick={clear}>{w.clear}</Button> : null}
      </form>

      {/* Kind filters, from what the vault actually holds. */}
      {kinds.length > 1 ? (
        <div className="flex flex-wrap gap-1.5" aria-busy={reloading || undefined}>
          {/* Disabled while the list behind them is refetching: a chip took the click, lit up, and
              accepted three more before the first answer landed. The bars below are the indicator. */}
          <button type="button" onClick={() => pickKind(null)} disabled={reloading}
            className={cn('rounded-full border px-3 py-1 text-[12px] transition-colors disabled:opacity-60',
              reloading && 'cursor-progress',
              kind === null ? 'border-primary bg-primary/15 font-semibold text-primary' : 'border-border text-muted-foreground hover:text-foreground')}>
            {w.all_kinds}
          </button>
          {kinds.map((k) => (
            <button key={k} type="button" onClick={() => pickKind(k)} disabled={reloading}
              className={cn('rounded-full border px-3 py-1 text-[12px] transition-colors disabled:opacity-60',
                reloading && 'cursor-progress',
                kind === k ? 'border-primary bg-primary/15 font-semibold text-primary' : 'border-border text-muted-foreground hover:text-foreground')}>
              {kindLabel(k, lang)}
            </button>
          ))}
        </div>
      ) : null}

      {err ? (
        <Card className="p-4">
          <div role="alert" className="text-[13px] font-semibold text-destructive">{err}</div>
          {/* Retry repeats what failed: after a failed question the list effect is parked (asked is
              set), so bumping reloads alone did nothing and the error stayed. */}
          <Button type="button" variant="outline" size="sm" className="mt-2.5" onClick={() => { setErr(''); if (asked) void ask(); else setReloads((n) => n + 1); }}>
            {w.retry}
          </Button>
        </Card>
      ) : null}

      {/* THE ANSWER. Composed server-side out of the row's own fields, so a missing expiry is
          reported as missing there too — this surface does not re-phrase it into a claim. */}
      {asked && !err && answer && answer.length ? (
        <Card className="border-primary/35 bg-primary/5 p-4">
          <div className="text-[11px] font-semibold uppercase tracking-wide text-primary">{w.answer_h}</div>
          <ul className="mt-1.5 space-y-1">
            {answer.map((line, i) => (
              <li key={i} className="text-[13.5px] font-semibold leading-snug text-foreground">{line}</li>
            ))}
          </ul>
          {matched ? (
            <div className="mt-2 text-[11.5px] text-muted-foreground">
              {matched.extraction_text} {w.matched_text} · {matched.related_request} {w.matched_related}
            </div>
          ) : null}
        </Card>
      ) : null}

      {!res && !err ? (
        <div className="grid gap-3" aria-hidden="true">
          {[0, 1, 2].map((i) => <Skeleton key={i} className="h-[152px] w-full rounded-lg" />)}
        </div>
      ) : null}

      {/* EMPTY. The endpoint always says WHY, and its sentence is printed verbatim.
          THE HEADING IS THE FALLBACK, NOT A COMPANION. res.note already OPENS with the same
          sentence this heading holds, so rendering both printed "Nothing has been filed to your
          vault yet." twice in a row - once bold, then again as the first words of the paragraph
          under it. The server sentence is the fuller one and the one this component is documented
          to print verbatim, so it wins; the local string is shown only when there is no note. */}
      {res && !docs.length ? (
        <Card className="p-5">
          {res.note
            ? <p className="text-[13px] leading-relaxed text-muted-foreground">{res.note}</p>
            : <div className="text-[15px] font-bold text-foreground">
                {res.empty_reason === 'no_customer_record' ? w.empty_no_customer : w.empty_generic}
              </div>}
        </Card>
      ) : null}

      {docs.length ? (
        <div className="grid gap-3">
          {docs.map((d) => <DocumentRow key={d.id} doc={d} token={token} lang={lang} showMatch={!!asked} />)}
        </div>
      ) : null}
    </section>
  );
}
