// @ts-nocheck
'use client';
import { useDeferredValue, useEffect, useRef, useState } from 'react';
// 14 Sep 2026: the row-#5 intelligence panels are no longer top-level tabs; ./supplier/Insights loads
// the ones whose routine has something to show, each on demand.
import SupplierSettings from '../SupplierSettings';
import SupplierDocumentImpact from '../SupplierDocumentImpact';
import SupplierCommandPalette from '../SupplierCommandPalette';
import GetMatched from '../GetMatched';
import ProfileScore from '../ProfileScore';
import Insights, { INSIGHT_PANELS } from '../Insights';
// Inquiries received and Quotations submitted (founder, 15 Sep 2026) — the conversation with the sales engineer.
import { InquiriesTab } from '../InquiriesTab';
import { QuotationsTab } from '../QuotationsTab';
import SupplierMailbox from '../SupplierMailbox';
import SupplierSupportingDocuments from '../SupplierSupportingDocuments';
import { ws } from '../workspaceCopy';
import ServicesTab, { type ServicesStatus } from '../ServicesTab';
import { Kicker } from '@/components/ui/sealed';
import { srvText } from '../serverCopy';
import { call } from '../api';
import { warmTabs } from '../tabPrefetch';
import { take } from '@/components/me/prefetch';
import { WhatsAppChoice } from '../../WhatsAppChoice';
import { waNeedsPrompt } from '../../whatsappChoiceText';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { useDelayedFlag } from '@/components/ui/busy';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';
import { Ltr } from '@/lib/Ltr';
import { DASH_KEY, ME_KEY, fetchDashboard, fetchMe } from './session';
import { readsMeNow } from '@/lib/supplierRegistrationReads';
import { arDaysLeft, wentExpired, fmtDate } from './helpers';
import { BillingPanel } from './Billing';
import { t } from './copy';
import { S } from './styles';
import { MAIN_TABS, ACCOUNT_TABS, TAB_ALIAS } from './tabs';
import { needsReaccept, ReacceptTerms } from './Agreement';
import { NotificationBell, AccountMenu } from './HeaderMenus';
import { QuoteForm } from './QuoteForm';
import { Documents } from './Documents';
import { Projects } from './Projects';
import { ProfilePanel, Onboarding } from './Onboarding';
import { registrationReceived, RECEIVED, NOT_APPROVED, SUPPORT_EMAIL, rejectedLines } from '../registrationReceived';

function Dashboard({ token, lang, onExpired, noCompanyYet = false }) {
  const ar = lang === 'ar';
  const [ov, setOv] = useState(null); const [tab, setTab] = useState('services'); const [err, setErr] = useState('');
  const [panel, setPanel] = useState(null); const [receipt, setReceipt] = useState(null);
  // Which record a card opened: an RFQ by inquiry id (from Quotes), a chat by inquiry id (from Projects).
  const [focusRfq, setFocusRfq] = useState(null);
  // The one-time WhatsApp question for suppliers registered before it existed (founder, 14 Sep 2026).
  // Holds the kyc state while the card is due, null otherwise. It never blocks a tab.
  const [waPrompt, setWaPrompt] = useState(null);
  useEffect(() => { call('kyc', { action: 'state' }, token).then((k) => { if (waNeedsPrompt(k)) setWaPrompt(k); }).catch(() => {}); }, [token]);
  // Which agreement version this supplier accepted, against the live one (supplier_api me). Read beside the dashboard, never after it.
  // undefined = not answered yet; null = the account has no company (the same answer as the dashboard's no_company, whichever
  // lands first opens the registration); false = could not be read (the workspace does not wait on it); else the supplier.
  // The code answer said there is no company yet (SupplierPortal noCompanyYet): start from that, so the registration opens at once.
  const [meRead, setMe] = useState(noCompanyYet ? null : undefined);
  const me = meRead || null;
  const firstMe = useRef(true);   // the first read takes the one warmSupplier started with the token
  const loadMe = () => { const first = firstMe.current; firstMe.current = false; return (first ? take(token, ME_KEY, () => fetchMe(token)) : fetchMe(token)).then((j) => { if (wentExpired(j, onExpired)) { setMe((m) => (m === undefined ? false : m)); return; } if (j && 'supplier' in j) setMe(j.supplier || null); else setMe((m) => (m === undefined ? false : m)); }).catch(() => setMe((m) => (m === undefined ? false : m))); };
  // Sign-in said there is no company yet: `me` would only say so again (it ran into "Create company", registration certification
  // free round 6). It is read once the dashboard names a supplier, which also corrects a wrong hint (src/lib/supplierRegistrationReads.ts).
  useEffect(() => { if (readsMeNow({ noCompanyYet, dashboardAnswered: !!ov })) loadMe(); }, [token, ov?.supplier]); // read again after every save so the profile score is current
  // AN INVITED SUPPLIER IS GUIDED THROUGH THE SAME REGISTRATION (11 Nov 2026, customer_support; registration certification finding 7).
  // Verify on an invitation claims the listed company, so the dashboard never answered no_company and he landed in the workspace:
  // "Pending", profile score 0/100, and registration finished in three places (Documents, then Profile in the Account menu, then
  // Services). Any company that has not submitted its registration now opens the registration form the public door opens; Submit
  // leads to the workspace and its Services tab, as it does there. The same holds for a public registrant who reloads before Submit.
  // Prevented by: scripts/checks/an_invited_supplier_is_guided_through_the_registration_form.test.mjs.
  // Decided from the dashboard's own card (supplier_portal supplierCard.registration_submitted), so the workspace waits on no second
  // read; from `me` when that answer lands first, or when the deployed dashboard does not carry the field yet.
  const [regLater, setRegLater] = useState(false);
  const fromOv = ov && ov.supplier && typeof ov.supplier.registration_submitted === 'boolean' ? (ov.supplier.approval_status !== 'approved' && !ov.supplier.registration_submitted) : null;
  const fromMe = me ? (me.approval_status !== 'approved' && !me.registration_submitted_at) : null;
  const registering = !regLater && (fromOv ?? fromMe) === true;
  const registered = () => { setErr(''); setOv(null); setMe(undefined); load(); };   // the new dashboard answer re-reads me (the effect above)
  // ONE call (supplier_portal `dashboard`): stats, alerts, eligibility, document impact and the bell's
  // counts. It was three, the second wave starting only after the first rendered. `first` takes the
  // request warmSupplier started with the token; every later load asks fresh.
  // Only the latest request may write: an older answer arriving late must not overwrite a newer one.
  const seq = useRef(0);
  const onSvcStatus = (s: ServicesStatus) => {
    const p = svcPrev.current; svcPrev.current = s; setSvc(s);
    if (p && ((p.reading && !s.reading) || s.confirmedAt !== p.confirmedAt)) load(false, true);
  };
  // busy-exempt: the affordance is the absence of `ov` — the dashboard renders its aria-busy
  // redaction-bar card until this resolves, and resolves into `err` on failure. A second flag here
  // would be a second source of truth for the same state. (docs/CONVENTIONS_LOADING.md)
  // `quiet`: a background re-read (the reading landed, a Confirm) never replaces the workspace with "Something went wrong" when it
  // fails; the card keeps its last true state (review of the land-on-your-step branch, blocker 2).
  const load = async (first = false, quiet = false) => { const n = ++seq.current; const j = await (first ? take(token, DASH_KEY, () => fetchDashboard(token)) : fetchDashboard(token)); if (n !== seq.current) return; if (j && j.ok) setOv(j); else if (j && j._http === 401 && onExpired) onExpired(); else if (!quiet) setErr((j && (j.code || j.error)) || 'load_err'); };
  useEffect(() => { load(true); }, [token]);
  // WHAT THE SERVICES TAB KNOWS (ServicesTab onStatus; 12 Nov 2026, paid certification J9/J10). The card follows it, and the
  // dashboard's own status is read again when the reading lands and after each Confirm, so the header and the card say what is
  // true then (checking, or approved).
  const [svc, setSvc] = useState<ServicesStatus | null>(null);
  const svcPrev = useRef<ServicesStatus | null>(null);
  // WHILE HE IS ON ANOTHER TAB the Services tab is unmounted and stops asking; the "reading" card would keep saying so after the
  // reading finished (review, item 6). Away from that tab, while his documents are being read, the reading is asked every 10 s;
  // when it has finished the card and the dashboard are brought up to date: one quiet dashboard read.
  useEffect(() => {
    if (!svc || svc.confirmed || !svc.reading || tab === 'services') return;
    let n = 0;
    const id = setInterval(async () => {
      if (++n > 60) { clearInterval(id); return; }
      const j = await call('supplier_api', { action: 'services_state' }, token).catch(() => null);
      if (!j || !j.ok) return;
      const reading = !!(j.capability?.source_docs?.docs || []).some((x) => x && x.kind === 'profile' && x.status === 'reading');
      if (reading) return;
      clearInterval(id);
      const waiting = !j.confirmed && ((j.proposed_services || []).length > 0 || (j.questions || []).some((q) => q && (q.status === 'open' || q.status === 'answered')) || (j.checklist || []).length > 0);
      const next = { ...svc, confirmed: !!j.confirmed, reading: false, waiting };
      svcPrev.current = next; setSvc(next); load(false, true);
    }, 10000);
    return () => clearInterval(id);
  }, [svc, tab, token]); // oxlint-disable-line react-hooks/exhaustive-deps
  // THE AGREEMENT IS BEING SIGNED (10 Nov 2026): the certificate lands within seconds, or the minute sweep re-signs it after 5
  // minutes (fn_sales_engineer_resigns_unsigned_agreements). The header says so and reads the dashboard again every 15 s for up
  // to 10 minutes, so the supplier sees Approved without reloading.
  const signing = !!(ov && ov.supplier && ov.supplier.agreement_signing);
  useEffect(() => { if (!signing) return; let n = 0; const id = setInterval(() => { if (++n > 40) clearInterval(id); else load(); }, 15000); return () => clearInterval(id); }, [signing, token]);
  // Once the dashboard has rendered, the Messages, Billing and Settings tabs' first reads start in the
  // background (supplier/tabPrefetch.ts), so pressing a tab takes an answer already on its way.
  const dashReady = !!ov;
  useEffect(() => { if (!dashReady || !token) return; const id = setTimeout(() => warmTabs(token), 300); return () => clearTimeout(id); }, [dashReady, token]);
  // On leaving Messages only the bell's counts are read again (two reads, not the whole dashboard), so
  // the badge drops once the thread was read.
  const prevTab = useRef(tab);
  useEffect(() => {
    if (prevTab.current === 'messages' && tab !== 'messages') {
      const n = seq.current;
      call('supplier_portal', { action: 'notifications' }, token).then((j) => { if (j && j.ok && n === seq.current) setOv((o) => (o ? { ...o, notifications: j.notifications } : o)); }).catch(() => {});
    }
    prevTab.current = tab;
  }, [tab, token]);
  useEffect(() => {
    // Stripe's return (see ReceiptBanner). Read once, then removed so a reload does not re-announce it.
    try {
      const q = new URLSearchParams(window.location.search);
      const d = q.get('dues_paid'); const r = q.get('registration_paid');
      if (d || r) {
        setReceipt({ kind: d ? 'dues' : 'registration', ref: String(d || r) }); setTab('billing');
        q.delete('dues_paid'); q.delete('registration_paid');
        const s = q.toString(); window.history.replaceState(null, '', window.location.pathname + (s ? '?' + s : ''));
      }
    } catch (_e) {}
  }, []);
  // THE SWITCH WINDOW (18 Sep 2026). Pressing a tab said nothing at all on this side, while the
  // customer's tabs get a ModuleLoading skeleton. Each supplier tab owns its own fetch, so the parent
  // cannot see a child's data arrive — but it CAN see what the press costs: useDeferredValue keeps the
  // panel already on screen while the new tab renders at low priority, and `switching` is exactly that
  // render, which on a phone is the whole of a heavy tab's mount. The redaction bars sit ABOVE the
  // still-mounted old panel rather than replacing it — replacing it would unmount the child and restart
  // the very fetch being waited on — and appear only past 150ms (busy.tsx rule 1), so a light tab
  // never flashes them.
  const shownTab = useDeferredValue(tab);
  const switching = shownTab !== tab;
  const switchBars = useDelayedFlag(switching);
  // Every panel's goTo(...) lands here. Old tab keys still resolve: 'inbox' is the RFQs list, and the
  // intelligence keys open their panel inside Insights.
  const go = (k) => {
    if (MAIN_TABS.includes(k) || ACCOUNT_TABS.includes(k)) { setTab(k); return; }
    if (TAB_ALIAS[k]) { setTab(TAB_ALIAS[k]); return; }
    if (INSIGHT_PANELS.includes(k)) { setPanel(k); setTab('insights'); return; }
    setTab('services');
  };
  // the tab row's edges: whether more tabs lie beyond either end (the fade), and the current tab kept in view
  const tabRow = useRef<HTMLDivElement | null>(null);
  const [tabMore, setTabMore] = useState({ start: false, end: false });
  const tabEdge = () => { const r = tabRow.current; if (!r) return; const x = Math.abs(r.scrollLeft); setTabMore({ start: x > 2, end: x + r.clientWidth < r.scrollWidth - 2 }); };
  useEffect(() => {
    const r = tabRow.current; if (!r) return;
    const b = r.querySelector('[aria-current="page"]') as HTMLElement | null;
    if (b && r.scrollWidth > r.clientWidth) { const left = b.offsetLeft - r.offsetLeft; if (left < r.scrollLeft || left + b.offsetWidth > r.scrollLeft + r.clientWidth) r.scrollTo({ left: Math.max(0, left - 16) }); }
    tabEdge();
  }, [tab, !!ov]); // oxlint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { const on = () => tabEdge(); window.addEventListener('resize', on); return () => window.removeEventListener('resize', on); }, []);
  if (err === 'no_company') return <Onboarding token={token} lang={lang} onExpired={onExpired} initial={meRead === false ? undefined : meRead} onDone={registered} />;
  if (meRead === null) return <Onboarding token={token} lang={lang} onExpired={onExpired} initial={null} onDone={registered} />;   // me said "no company" before the dashboard did
  // "Finish registering … We already hold your company listing" is said to a company that began as a listing we hold (an invitation,
  // a directory row): never to one that registered itself and reloaded before Submit (12 Nov 2026, browser walk finding M23). The
  // dashboard (supplier_portal supplierCard.listed) and `me` (leads.source) both say which, so whichever lands first gives the same
  // wording and nothing flips under him; unknown (an older deployment) keeps the old wording.
  const listed = ov && ov.supplier && typeof ov.supplier.listed === 'boolean' ? ov.supplier.listed : !(me && me.listed === false);
  if (registering && !needsReaccept(me)) return <Onboarding token={token} lang={lang} onExpired={onExpired} initial={me || undefined} invited={listed} onSkip={() => setRegLater(true)} onVerified={() => load(false, true)} onDone={registered} />;
  if (err) return <div className={S.center}><Card className="qd-panel max-w-[460px] p-5"><div className={S.h2}>{t(lang, 'something_wrong')}</div><div className={S.sub}>{t(lang, 'err_generic')}</div><Button className="mt-3" onClick={() => { setErr(''); load(); }}>{t(lang, 'bill_retry')}</Button></Card></div>;
  if (needsReaccept(me)) return <ReacceptTerms token={token} lang={lang} me={me} onDone={() => setMe({ ...me, accepted_terms_version: me.terms_current })} />;
  // THE FIRST PAINT HAS THE WORKSPACE'S SHAPE (12 Nov 2026, browser walk finding M15): a line centred in 70vh was replaced by the
  // workspace, so nothing he saw stayed where it was. The heading row, the name, the badge line and the tab strip are drawn at their
  // own heights, so the workspace lands where the outline was.
  if (!ov || (meRead === undefined && fromOv === null)) return <WorkspaceOutline lang={lang} />;
  const unread = (ov.notifications && ov.notifications.unread_messages) || 0;
  const TAB = { services: ws(lang, 'tab_services'), rfqs: ws(lang, 'tab_rfqs'), quotes: ws(lang, 'tab_quotes'), messages: ws(lang, 'tab_messages'), documents: ws(lang, 'tab_documents'), insights: ws(lang, 'tab_insights'), profile: ws(lang, 'acct_profile'), billing: ws(lang, 'acct_billing'), settings: ws(lang, 'acct_settings') };
  const signingOnly = !!ov.supplier.agreement_signing && ov.supplier.licence_gate_reason === 'reg_terms' && ov.supplier.approval_status !== 'approved';
  // H9: what the "Registration received" card says, decided for every state in ../registrationReceived.ts.
  const scopeOpen = ((ov.eligibility && ov.eligibility.blocking) || []).some((b) => b && b.code === 'scope_unconfirmed');
  const receivedCard = registrationReceived({ approvalStatus: ov.supplier.approval_status, reason: ov.supplier.licence_gate_reason, signingOnly, scopeOpen, services: svc,
    submitted: ov.supplier.registration_submitted === true || !!(me && me.registration_submitted_at) });
  const svcFirst = scopeOpen || (svc?.confirmedAt ?? 0) > 0;
  // WHILE HIS DOCUMENTS ARE READ the services step is still the one left (the card says they will appear below): the hold line
  // "services unconfirmed" stood above the card for the reading and vanished the moment the list landed, so the whole tab jumped up
  // under his finger as he reached for it (stub walk at 390x844, 12 Nov 2026: one shift of 0.144 at the list's arrival).
  const servicesLeft = !!receivedCard && (receivedCard.kind === 'services' || (receivedCard.kind === 'reading' && ov.supplier.licence_gate_reason === 'services_unconfirmed'));
  const stBadge = (() => {
    // AUDIT 6.5(d): action_required is NOT pending — a clock is running that ends in rejection.
    const st = ov.supplier.approval_status;
    // Only the agreement is outstanding and it is being signed: nothing is asked of the supplier, so no red badge and no clock.
    if (signingOnly) return <Badge variant="warn">{t(lang, 'agreement_signing')}</Badge>;
    if (st === 'action_required') {
      const due = ov.supplier.exception_due_at ? new Date(ov.supplier.exception_due_at) : null;
      const days = due ? Math.ceil((due.getTime() - Date.now()) / 864e5) : null;
      const when = days === null ? '' : (days <= 0 ? ' · ' + t(lang, 'ar_overdue') : ' · ' + (lang === 'ar' ? arDaysLeft(days) : days + ' ' + t(lang, 'ar_days_left')));
      return <Badge variant="destructive">{t(lang, 'action_required') + when}</Badge>;
    }
    // 12 Nov 2026 (review walk): a rejected company read "Pending". It reads what it is; English only (ruling 1008).
    if (st === 'rejected') return <Badge variant="destructive">Not approved</Badge>;
    return <Badge variant={st === 'approved' ? 'ok' : 'warn'}>{st === 'approved' ? t(lang, 'approved') : t(lang, 'pending')}</Badge>;
  })();
  return (
    <div className={S.wrap}>
      {waPrompt && <div className="mb-5"><WhatsAppChoice token={token} lang={lang} mode="prompt" current={waPrompt.whatsapp} mobile={waPrompt.phone} onDone={() => setWaPrompt(null)} /></div>}
      <div className="mb-5 flex flex-col gap-3">
        <div>
          {/* The two menus' panels are placed against THIS row (relative; HeaderMenus.tsx PANEL), and the row wraps at 200 % zoom
              with the menus kept to the end (ms-auto), so neither panel can start off the screen. */}
          <div className="flex flex-wrap items-center justify-between gap-3"><Kicker>{t(lang, 'brand_sub')}</Kicker><div className="relative ms-auto flex items-center gap-2"><NotificationBell ov={ov} lang={lang} go={go} /><AccountMenu tab={tab} labels={TAB} lang={lang} go={go} /></div></div>
          <h1 dir="auto" className="mt-2.5 font-head text-[24px] sm:text-[30px] font-semibold tracking-snug text-foreground">{ov.supplier.company_name}</h1>
          {/* M13 (12 Nov 2026, browser walk): ruling 1176 renames the company to the name its trade licence prints, at Submit; the
              walk typed "…Walk Resume Trading LLC" and was headed "…Marina Steel Trading DMCC" with no word on screen. */}
          {ov.supplier.name_from_licence ? <p data-testid="name-from-licence" className="mt-1 text-[14px] text-muted-foreground">{NAME_FROM_LICENCE}</p> : null}
          <div className="flex items-center gap-2 mt-1.5 flex-wrap">
            {stBadge}
            {/* A LICENCE HOLD IS SAID ON SCREEN (13 Oct 2026, ruling 1230 walk, it_engineer). Since ruling 1177 an unread licence
                is held as PENDING (licence_unreadable / _expiry_unread / _number_unread), and the reason showed only for
                action_required: a held supplier saw 'Pending' and 'Trade licence: on file' and never learned a clearer copy
                was needed. Prevented by scripts/checks/a_held_supplier_is_never_told_nothing_is_needed.test.mjs. */}
            {/* RED IS FOR WHAT IS WRONG (12 Nov 2026, browser walk finding H9). Only action_required, a clock that ends in rejection,
                is red; a hold he can clear is said in the warning colour; the one step left after Submit (services_unconfirmed) is
                not a hold line at all but the "Registration received" card below, which said nine red lines on every tab. */}
            {/* oxlint-disable-next-line unicorn/prefer-string-starts-ends-with -- this exact shape is pinned by scripts/checks/a_held_supplier_is_never_told_nothing_is_needed.test.mjs */}
            {!signingOnly && (ov.supplier.approval_status === 'action_required' || (ov.supplier.approval_status === 'pending' && /^licence_/.test(String(ov.supplier.licence_gate_reason || ''))) || (ov.supplier.approval_status === 'pending' && ov.supplier.licence_gate_reason === 'services_unconfirmed')) && !servicesLeft && ov.supplier.licence_gate_reason
              ? <span className={cn('basis-full text-[14px] font-medium leading-relaxed', ov.supplier.approval_status === 'action_required' ? 'text-destructive' : 'text-warn')}>{sentence(t(lang, 'ar_why') + ': ' + srvText(lang, ov.supplier.licence_gate_reason, {}, ov.supplier.licence_gate_reason))}</span> : null}
            {ov.supplier.license_expiry ? (() => { const days = Math.round((new Date(ov.supplier.license_expiry) - new Date()) / 864e5); const v = days < 0 ? 'destructive' : days <= 30 ? 'warn' : 'secondary'; return <Badge variant={v}>{(days < 0 ? t(lang, 'lic_expired') : t(lang, 'lic_expires')) + ' · '}<Ltr>{fmtDate(ov.supplier.license_expiry, lang)}</Ltr></Badge>; })() : null}
          </div>
        </div>
        {receivedCard ? <RegistrationReceived card={receivedCard} onServices={tab === 'services' ? null : () => go('services')} /> : null}
        {ov.supplier.approval_status === 'rejected' ? <RegistrationNotApproved lines={rejectedLines({ missing: ov.supplier.rejected_missing, reason: ov.supplier.licence_gate_reason }, (c) => srvText(lang, c, {}, ''))} /> : null}
        {/* ONE ROW ON A PHONE (12 Nov 2026, customer_support; founder ruling 1645, paid certification J10: six tabs wrapped over three
            rows, ~170 px, above the step he had to do). Every name stays text (founder ruling 84 of 14 Sep 2026: text, not logos); below
            sm the row scrolls sideways, the current tab is scrolled into view, and a fade at the edge shows that more tabs follow until
            the end is reached. From sm up it wraps as before. Every control is at least 44 px tall. */}
        <nav aria-label={t(lang, 'main_nav')} className="relative">
          <div ref={tabRow} onScroll={tabEdge} data-testid="main-tabs" className={cn('qd-tabs flex flex-nowrap gap-1 overflow-x-auto p-1.5 [scrollbar-width:none] sm:flex-wrap sm:overflow-visible [&::-webkit-scrollbar]:hidden')}>
            {MAIN_TABS.map((k) => <button key={k} type="button" data-nav-id={k} aria-current={tab === k ? 'page' : undefined} className={cn(S.tab, 'min-h-11 whitespace-nowrap focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring', tab === k && S.tabOn)} onClick={() => setTab(k)} onFocus={(e) => { try { e.currentTarget.scrollIntoView({ inline: 'nearest', block: 'nearest' }); } catch (_e) { /* old browser */ } }}>{k === 'rfqs' ? TAB.rfqs + (ov.active_matches ? ' (' + ov.active_matches + ')' : '') : k === 'messages' && unread ? <>{TAB[k]} <span className="ms-1 rounded-full bg-primary px-1.5 py-0.5 text-[10px] font-bold text-primary-foreground tabular-nums">{unread}</span><span className="sr-only">{ar ? ' رسائل غير مقروءة' : ' unread'}</span></> : TAB[k]}</button>)}
          </div>
          {tabMore.end ? <span aria-hidden className="pointer-events-none absolute inset-y-px inset-e-px w-10 rounded-e-[inherit] bg-linear-to-l from-navy-deep to-transparent sm:hidden rtl:bg-linear-to-r" /> : null}
          {tabMore.start ? <span aria-hidden className="pointer-events-none absolute inset-y-px inset-s-px w-10 rounded-s-[inherit] bg-linear-to-r from-navy-deep to-transparent sm:hidden rtl:bg-linear-to-l" /> : null}
        </nav>
      </div>
      <SupplierCommandPalette tabs={[...MAIN_TABS, ...ACCOUNT_TABS]} labels={TAB} onGo={go} lang={lang} />
      {/* aria-busy sits on the INCOMING skeleton, not on the wrapper: the previous tab under it
          is still valid, rendered content, and marking it busy tells assistive tech to ignore
          something that is not stale. The status node is what announces the switch. */}
      {/* THE SWITCH BARS FLOAT, THEY DO NOT PUSH (12 Nov 2026, browser walk finding M15: CLS 0.46 and 0.55 opening Insights on a
          phone). They were inserted above the outgoing panel, so that panel dropped by their height and rose again a moment later:
          the page jumped twice under his thumb. They now lie over the top of the outgoing panel (absolute), which stays put. */}
      <div className="relative">
      <span className="sr-only" role="status" aria-live="polite">{switching ? (ar ? "جارٍ التحميل" : "Loading") : ""}</span>
      {switchBars && <Card aria-busy className="qd-panel absolute inset-x-0 top-0 z-10 bg-popover! p-5"><Skeleton className="w-1/3" /><Skeleton className="mt-3" /><Skeleton className="mt-2 w-2/3" /></Card>}
      {/* THE STEP HE MUST DO COMES FIRST (12 Nov 2026, customer_support; founder ruling 1645, paid certification J10 at 390 px: the
          services step began ~1,150 px down, under a 580 px Profile score card whose first row sent him to the tab he was on). For a
          supplier who has not confirmed his services (the eligibility's scope_unconfirmed, known at first paint, so nothing moves),
          ServicesTab is directly under the tabs and the score card follows it without its "Confirm your services" row, drawn once the
          tab has loaded (before that it sat on screen and was pushed down: CLS 0.20-0.33 in the shell walk). A confirmed
          supplier keeps the score first. ONE ServicesTab, keyed, in one place (review, blocker 1): two blocks for the two orders made
          React throw the step away when Confirm turned scope_unconfirmed off; the note vanished and the score card landed under his
          thumb. The order is fixed for this visit once he has confirmed in it (svcFirst).
          Prevented by: scripts/checks/the_supplier_lands_on_the_step_he_must_do.test.mjs. */}
      {shownTab === 'services' && <>{svcFirst ? null : <ProfileScore me={me} eligibility={ov.eligibility || null} go={go} />}<ServicesTab key="svc" token={token} lang={lang} goTo={go} onStatus={onSvcStatus} />{svcFirst && svc ? <div className="mt-4"><ProfileScore me={me} eligibility={ov.eligibility || null} go={go} hide={['scope']} /></div> : null}</>}
      {/* THE TAB THAT IS ON ITS WAY OUT MUST NOT EAT THE FOCUS THE NEXT ONE WAS SENT (18 Sep 2026).
          `focusRfq` is one token that BOTH tabs read and BOTH clear through onFocused. That was fine
          while the panels rendered on `tab`, because setFocusRfq(id) and setTab(...) commit together
          and the old panel is gone in the same render. Since #736 they render on `shownTab`, a
          useDeferredValue of `tab` — so after "Send your quotation to the sales engineer" runs
          setFocusRfq(id); setTab('quotes'), InquiriesTab is STILL MOUNTED for at least one commit,
          now holding the new focus. Its own focus effect fires, opens that inquiry again, and calls
          onFocused() — which clears focusRfq. QuotationsTab then mounts with focus=null and opens
          nothing, so the supplier lands on a list of collapsed jobs instead of the review
          conversation they just asked for. Measured on production 18 Sep 2026: it failed in all four
          matrices (en/ar x desktop/phone) of scripts/e2e/supplier_quote_review.mjs, every one of them
          timing out waiting for the sales engineer's first line, with the capture showing the
          Quotations submitted list and every job shut. Same shape in the other direction
          (openInquiry, quotes -> rfqs).
          The guard is `switching`: while shownTab has not caught up with tab, the panel on screen is
          the OUTGOING one and the focus is not addressed to it, so it may act on it but may not
          consume it. One condition, both directions, and nothing about the deferred render changes. */}
      {shownTab === 'rfqs' && <InquiriesTab token={token} lang={lang} focus={focusRfq} onFocused={() => { if (!switching) setFocusRfq(null); }} onQuote={(id) => { setFocusRfq(id); setTab('quotes'); }}
        renderQuoteForm={(inq, done, o) => <QuoteForm key={o?.newOption ? 'new' : 'edit'} inquiry={inq} token={token} lang={lang} onDone={done} newOption={!!o?.newOption} />} />}
      {shownTab === 'quotes' && <QuotationsTab token={token} lang={lang} focus={focusRfq} onFocused={() => { if (!switching) setFocusRfq(null); }} openInquiry={(id) => { setFocusRfq(id); setTab('rfqs'); }} />}
      {/* Messages holds the revealed jobs (Projects) above the conversations, behind the reveal gate. */}
      {shownTab === 'messages' && <SupplierMailbox token={token} lang={lang} goTo={go}
        jobs={(open) => <Projects token={token} lang={lang} openChat={open} onExpired={onExpired} />} />}
      {/* The registration checklist heads Documents, next to the uploads it asks for; after an upload the
          dashboard is read again so the checklist and document impact reflect the new file. */}
      {shownTab === 'documents' && <>
        <GetMatched token={token} lang={lang} go={go} initial={ov.eligibility || null} />
        <div className="mb-4"><SupplierDocumentImpact token={token} lang={lang} goTo={go} initial={ov.document_impact || null} /></div>
        <Documents token={token} lang={lang} onSaved={load} onExpired={onExpired} />
        <div className="mt-4"><SupplierSupportingDocuments token={token} lang={lang} /></div>
      </>}
      {shownTab === 'insights' && <Insights token={token} lang={lang} goTo={go} initial={panel} />}
      {shownTab === 'profile' && <ProfilePanel token={token} lang={lang} initial={me} onSaved={load} onExpired={onExpired} onVerified={() => load(false, true)} />}
      {shownTab === 'billing' && <BillingPanel token={token} lang={lang} receipt={receipt} onExpired={onExpired} />}
      {shownTab === 'settings' && <SupplierSettings token={token} lang={lang} />}
      </div>
    </div>
  );
}
// H9 (12 Nov 2026, customer_support; founder ruling 1645, browser walk). After Submit nothing said "received", and a nine-line red
// paragraph headed every tab. One calm card, in the panel's own colours, with one button to the one step left. The step has ONE
// name everywhere a supplier reads it: "Confirm your services" (GetMatched, profileScore, verified_badges, serverCopy).
// English only (ruling 1008). Prevented by: scripts/checks/the_supplier_is_told_his_registration_was_received.test.mjs.
const CONFIRM_SERVICES = 'Confirm your services';
const NAME_FROM_LICENCE = 'Your company name is shown as it is printed on your trade licence.';
const sentence = (x: string) => { const v = String(x || '').trim(); return v && !/[.!?]$/.test(v) ? v + '.' : v; };
function RegistrationReceived({ card, onServices }) {
  const services = card.kind === 'services';
  return (
    <section data-testid="registration-received" aria-labelledby="qd-received-h" className="qd-panel flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5">
      <div className="min-w-0">
        <h2 id="qd-received-h" className="font-head text-[17px] font-semibold text-foreground">{RECEIVED}</h2>
        <p className="mt-1 text-[15px] leading-relaxed text-muted-foreground">{card.text(!onServices)}</p>
      </div>
      {services && onServices ? <Button className="shrink-0 self-start sm:self-center" onClick={onServices}>{CONFIRM_SERVICES}</Button> : null}
    </section>
  );
}
function RegistrationNotApproved({ lines }) {
  // The address is a mailto link in the sentence: 44 px tall for a thumb (review note b: it was 19 px) by vertical padding that a
  // negative margin takes back, so the line looks exactly as before.
  const mail = (line) => line.includes(SUPPORT_EMAIL)
    ? <>{line.split(SUPPORT_EMAIL)[0]}<a className="qd-link -my-3 inline-block py-3 font-semibold text-primary underline underline-offset-2" href={'mailto:' + SUPPORT_EMAIL}>{SUPPORT_EMAIL}</a>{line.split(SUPPORT_EMAIL)[1]}</>
    : line;
  return (
    <section data-testid="registration-not-approved" aria-labelledby="qd-rejected-h" className="qd-panel flex flex-col gap-2 p-4 sm:p-5">
      <h2 id="qd-rejected-h" className="font-head text-[17px] font-semibold text-foreground">{NOT_APPROVED}</h2>
      {lines.map((l) => <p key={l} className="text-[15px] leading-relaxed text-muted-foreground">{mail(l)}</p>)}
    </section>
  );
}
// M15: the workspace's outline while its first read is on its way (the heading row, the name, the badge line, the tab strip).
function WorkspaceOutline({ lang }) {
  return (
    <div className={S.wrap} aria-busy="true">
      <output className="sr-only">{t(lang, 'loading_dash')}</output>
      <div aria-hidden className="mb-5 flex flex-col gap-3">
        <div className="flex min-h-11 items-center justify-between gap-3"><Skeleton className="h-3 w-36" /><Skeleton className="h-11 w-36" /></div>
        <Skeleton className="mt-2.5 h-8 w-3/4 sm:h-9" />
        <Skeleton className="mt-1.5 h-6 w-40" />
        <Skeleton className="h-[148px] w-full sm:h-[60px]" />
      </div>
    </div>
  );
}
export { Dashboard };
