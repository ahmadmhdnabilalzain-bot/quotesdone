// @ts-nocheck
'use client';
import { useEffect, useState, useRef } from 'react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { cn } from '@/lib/utils';
import { categoryLabel } from '@/lib/categoryLabel';
import { statusLabel as projectStatusLabel } from '@/components/portal/projects/strings';
// The NegotiationAssistant accordion that sat on every quote card was removed 21 Sep 2026 — the
// founder took negotiations out of both portals (instruction 526).
// §2 the Company Digital Twin, §9 Supplier Discovery and §17 Customer AI Memory. fn_twin,
// v_digital_twin, customer_score and customer_preference were all built and read only by os_api —
// the staff console — so the customer could not see their own profile or correct it.
// SupplierDiscovery and CustomerMemory render only inside the profile tab (id === 'profile', ~line
// 1541) and are deferred. CompanyTwin and DecisionSupport are NOT deferred: independent review (14
// Sep 2026) found both also render on the default 'home' overview — every signed-in customer's
// landing screen, whenever `!onlyRequests` (~line 737 DecisionSupport, ~line 747 CompanyTwin, gated
// additionally on `ov.twin`) — so they are on the initial /me paint, not behind a tab click. A
// dynamic import there added a chunk fetch with no loading fallback, popping DecisionSupport (the
// screen's own call to action) in late and shifting the request list under it. Imported statically,
// same as before this PR.
import { CompanyTwin, DecisionSupport } from '@/components/portal/twin';
import { PortalShell, StatTile } from '../PortalShell';
import { FileText, MessageSquareQuote, BellRing, KeyRound, Plus, X, Sparkles, Upload, Scale, ArrowRight, Check } from 'lucide-react';
import { parseQuoteLink, resolveQuoteLink } from '@/lib/portalLink';
import { ConciergeSteps } from '../ConciergeSteps';
import { WhatsAppChoice } from '@/components/portal/WhatsAppChoice';
import { waNeedsPrompt } from '@/components/portal/whatsappChoiceText';
import * as M from 'motion/react-m';
import { useReducedMotion } from 'motion/react';
import { take } from '../prefetch';
import { t, tf, errText, emirateName } from '../portalText';
import { call } from '../api';
import { aed, greetingOf, stateOf } from '../format';
import { S } from '../styles';
import { SpendingIntelligence, NewRequest } from './lazyModules';
import { MODULES, ModuleWindow } from './ModuleWindow';
import { InquiryCard } from '../requests/InquiryCard';

function Dashboard({ token, lang, theme, onSwapTheme, onSetLang, onSignOut, onServedLocale, kyc }) {
  // Only accounts that finished sign-up before the WhatsApp question was part of it are asked here,
  // once, without blocking anything; answering or "Ask me later" closes it for good.
  const [waAsk, setWaAsk] = useState(() => waNeedsPrompt(kyc));
  const [ov, setOv] = useState(null); const [data, setData] = useState(null); const [err, setErr] = useState(''); const [note, setNote] = useState(''); const [showNew, setShowNew] = useState(false); const [postedGuide, setPostedGuide] = useState(null);
  // WHY THIS IS NO LONGER A `view`. Messages and Projects were whole-surface early returns: opening
  // either REPLACED the dashboard, which is the full-page navigation §21 asks the portal not to
  // have — and it also stranded the intake chat, because a branch that returns before the
  // assistant's mount can never render it. Every module now opens in a window OVER the dashboard,
  // so the KPIs, the alerts and the assistant stay mounted underneath and no module needs a
  // "back to requests" button to undo a navigation that never happened.
  // THE SECTION LIVES IN THE URL HASH (audit 21 Sep 2026, item 25): a reload used to land on the
  // Overview whatever the customer had open, and there was no link to Account or Documents to share
  // or bookmark. /me#account opens Account; navigating writes the hash back with replaceState so the
  // history is not littered with one entry per click. Only names in MODULES/GO are honoured.
  const [view, setView] = useState(() => { try { const h = location.hash.replace(/^#/, ''); return /^[a-z_]+$/.test(h) ? h : ''; } catch (_e) { return ''; } });
  useEffect(() => { try { const want = view && view !== 'home' ? '#' + view : ''; if (location.hash !== want) history.replaceState(history.state, '', location.pathname + location.search + want); } catch (_e) {} }, [view]);
  const rtl = lang === 'ar';
  // THE UNREAD COUNT MOVED UP ONE LEVEL. It used to be fetched by a badge inside the module bar;
  // the sidebar and the mobile tab bar both need it now, and two components fetching the same
  // number is how two components come to disagree about it.
  const [unread, setUnread] = useState(0);
  const [pd, setPd] = useState(null); const [pdFailed, setPdFailed] = useState(false);
  const [qtext, setQtext] = useState('');
  const [ballFilter, setBallFilter] = useState('all');
  // receipt: the on-screen state after a Stripe return; draft: the homepage handoff; focusQuote:
  // the quote a payment was for, so its request opens by itself.
  const [receipt, setReceipt] = useState(null); const [draft, setDraft] = useState(''); const [focusQuote, setFocusQuote] = useState('');
  // my_inquiries carries the customer's stored locale (customer_api, 5 Aug 2026). This is the only
  // call the portal makes that has it — `me` serves it too, but the portal never calls `me`, which
  // is why the field was on the wire for months with nothing listening. The handler upstream
  // decides whether it applies; an explicit choice on this device still wins.
  // `first` takes the request Authed already started beside kyc (prefetch.ts); every later call —
  // tab focus, the minute timer, a refresh after a write — asks the server fresh.
  const get = (first, key, path, body) => (first ? take(token, key, () => call(path, body, token)) : call(path, body, token));
  // `posting` covers the gap between "Request sent" and my_inquiries answering with the new row.
  // Measured 17 Sep 2026: for 0.3–1.5 s after posting their FIRST request the customer was shown
  // "you have no requests — post your first request", because `data` still held the previous
  // (empty) answer while the refresh was in flight. `booting` only guarded the very first load.
  // `.finally` rather than a second `setPosting(false)` inside `.then`: a failed refresh must not
  // leave the skeleton up forever, and it does not swallow the rejection either.
  const [posting, setPosting] = useState(false);
  // my_inquiries answers { inquiries, locale, promo, guarantee_terms } — it has no `ok`, so the
  // list itself is what is tested. Storing anything else (a transport sentinel, an error body) puts
  // "post your first request" in front of a customer who has plenty (review of #853).
  // The language the overview on screen was built in (see the [lang] effect below).
  const langLoaded = useRef(lang);
  const loadInq = (first) => get(first, 'inq', 'customer_api', { action: 'my_inquiries' }).then((j) => {
    if (!j || !Array.isArray(j.inquiries)) { setErr(errText(j, lang, 'load_failed')); return; }
    setData(j); setErr('');
    // THE SERVED LOCALE IS NOT A LANGUAGE SWITCH (28 Sep 2026, it_engineer). customer_portal builds
    // the overview in customers.locale, the same value my_inquiries serves here, so adopting it must
    // not refetch the overview. It did: on /ar for an English-registered customer the [lang] effect
    // fired a second customer_portal:overview only after this answer landed — measured @846 ms
    // +601 ms, a serial round trip on top of the first paint. A switch the customer makes still
    // refetches: setLang saves customers.locale, and that lang differs from this one.
    if (j.locale === 'ar' || j.locale === 'en') langLoaded.current = j.locale;
    if (j.locale && onServedLocale) onServedLocale(j.locale);
  }).catch(() => setErr(t(lang, 'load_failed')))
    .finally(() => setPosting(false));
  // `err` was set here and rendered NOWHERE, loadOv had no .catch, and the four stat tiles fall back
  // to a pulsing skeleton while `ov` is null — so an overview that failed left a customer watching
  // four grey boxes for ever, with the reason held in a state variable nothing printed (audit
  // 22 Sep 2026, CP-07). Both paths now set the message, and the banner below renders it with Retry.
  const loadOv = (first) => get(first, 'ov', 'customer_portal', { action: 'overview', lang })
    .then((j) => { if (j && j.ok) { setOv(j); setErr(''); } else setErr(errText(j, lang, 'load_failed')); })
    .catch(() => setErr(t(lang, 'load_failed')));
  // THE ROLLUP THAT WAS COMPUTED AND THROWN AWAY. project_api action='dashboard' recomputes, on
  // every call, this customer's project_summary rows (each carrying rfq_count, rfq_open,
  // budget_total, timeline_pct and supplier_count) plus an avg_savings_pct measured across the
  // spread of quotes on their own RFQs — and no file in src/ has ever called it. The Command
  // Center the spec asks for in §1 and §4 is made of exactly these numbers.
  const loadPd = (first) => get(first, 'pd', 'project_api', { action: 'dashboard' })
    .then((j) => { if (j && j.ok && j.dashboard) setPd(j.dashboard); else setPdFailed(true); })
    .catch(() => setPdFailed(true));
  // Silent by design: a badge that cannot load must not put an error where a count goes, and the
  // inbox reports its own failure when the customer opens it.
  const loadUnread = (first) => get(first, 'threads', 'messages_api', { action: 'threads' })
    .then((j) => setUnread(((j && j.threads) || []).reduce((n, th) => n + (Number(th.unread) || 0), 0)))
    .catch(() => {});
  const refresh = () => { loadInq(); loadOv(); loadPd(); loadUnread(); };
  // OPEN THIS REQUEST. Projects, the Project room, the supply-chain map, Messages, Orders,
  // the alerts and "Help me decide" all hand the portal an inquiry id and asked it to open that
  // request — and every one of them was wired to onClose, which threw the id away and landed the
  // customer on the Overview. This is the one target they all call: My requests, filters cleared so
  // the row cannot be hidden, and that request's card opened and scrolled to (InquiryCard).
  const [focusInq, setFocusInq] = useState('');
  const [focusProject, setFocusProject] = useState('');
  const [pickFile, setPickFile] = useState(false);
  const openRfq = (id) => { setFocusInq(id ? String(id) : ''); setBallFilter('all'); setQtext(''); setView('requests'); };
  // THE DEEP LINK TO ONE QUOTE: /me?request=<inquiry_id>&quote=<quote_id> (src/lib/portalLink.ts),
  // printed on the comparison report and the quotation PDF. Sign-in is an in-page OTP, so the query
  // string is still there when this screen mounts after login. It is resolved only against this
  // customer's own my_inquiries answer — customer_api filters that by the signed-in customer — so an
  // id from another account finds nothing and the customer is told so, never shown anything else.
  const [deepLink, setDeepLink] = useState(null);
  const [linkQuote, setLinkQuote] = useState('');
  useEffect(() => {
    if (!deepLink || !data || !Array.isArray(data.inquiries)) return;
    const hit = resolveQuoteLink(data.inquiries, deepLink);
    setDeepLink(null);
    try { const qs = new URLSearchParams(location.search); qs.delete('request'); qs.delete('quote'); const rest = qs.toString(); history.replaceState({}, '', location.pathname + (rest ? '?' + rest : '')); } catch (_e) { /* the link is already consumed */ }
    if (!hit) { setNote(t(lang, 'link_not_yours')); return; }
    setLinkQuote(hit.quoteId); openRfq(hit.inquiryId);
  }, [deepLink, data]);
  const openProject = (id) => { setFocusProject(id ? String(id) : ''); setView('projects'); };
  const openNew = (withFile) => { setPickFile(!!withFile); setShowNew(true); setView('home'); };
  // Where an alert goes is decided by what it is about: a request it names, the need it forecasts.
  // Kinds without a subject of their own (price moves, lead times) are about the requests list as a
  // whole. (There is no approvals alert: the Approvals tab was removed on 14 Sep 2026 — a company
  // buys exactly like an individual, and nothing routes a purchase through anyone's sign-off.)
  const onAlert = (a) => {
    if (a && a.inquiry_id) return openRfq(a.inquiry_id);
    if (a && a.kind === 'forecast_need') return openNew(false);
    return openRfq('');
  };
  useEffect(() => {
    loadOv(true);
    loadInq(true);
    loadPd(true);
    loadUnread(true);
    const qs = new URLSearchParams(location.search);
    const dl = parseQuoteLink(location.search); if (dl) setDeepLink(dl);
    // /me?new=1 opens the new-request form: the link WhatsApp's "Request a quotation" sends
    // (customer_support, 22 Sep 2026, instruction 763 — it used to send customers to the supplier portal).
    if (qs.get('new') === '1') openNew(false);
    const sid = qs.get('session_id'); const revealQ = qs.get('reveal') || '';
    // Only drop session_id from the URL once the payment is confirmed — it is the customer's
    // only reference for retrying or chasing a payment that did not go through. A confirmed payment
    // becomes an on-screen receipt and opens the request it paid for; a cancelled checkout says
    // plainly that nothing was charged (audit 14 Sep 2026: money paths that end in silence read as
    // broken). stripe_checkout's cancel_url carries payment=cancelled for exactly this.
    if (sid) { call('stripe_confirm', { session_id: sid }, token).then((j) => { if (j && j.ok) { history.replaceState({}, '', location.pathname); setReceipt({ kind: 'paid', quoteId: revealQ }); setFocusQuote(revealQ); loadInq(); } else if (j && j.pending) { setNote(t(lang, 'payment_pending')); } else { setNote(t(lang, 'payment_failed')); } }).catch(() => setNote(t(lang, 'payment_failed'))); }
    else if (qs.get('payment') === 'cancelled') { history.replaceState({}, '', location.pathname); setReceipt({ kind: 'cancelled', quoteId: revealQ }); setFocusQuote(revealQ); }
    // THE HOMEPAGE DRAFT HANDOFF (contract with the homepage, 14 Sep 2026). The homepage stores
    // localStorage 'qd-draft-brief' = {text, category?, emirate?, ts} and links to /me?draft=1. This
    // screen mounts only after sign-in and the profile gate, so a draft under 24 hours old opens the
    // composer and is sent as its first message. The key is deleted before it is used, so a reload
    // can never post the same job twice; a malformed or stale draft is dropped, never sent.
    try {
      const raw = localStorage.getItem('qd-draft-brief');
      if (raw) {
        localStorage.removeItem('qd-draft-brief');
        const d = JSON.parse(raw);
        const ts = typeof (d && d.ts) === 'number' ? d.ts : Date.parse(String((d && d.ts) || ''));
        const text = String((d && d.text) || '').trim();
        if (text && Number.isFinite(ts) && Date.now() - ts < 24 * 3600e3) {
          // The homepage stores the raw category and emirate; an Arabic customer must not read
          // "(Marble, Dubai)" in the middle of their own Arabic brief (CP-I18N-03).
          const extra = [d.category && categoryLabel(d.category, lang), d.emirate && emirateName(d.emirate, lang)].filter(Boolean).join(lang === 'ar' ? '، ' : ', ');
          setDraft(extra ? text + ' (' + extra + ')' : text); setShowNew(true);
        }
      }
      if (qs.get('draft')) history.replaceState({}, '', location.pathname);
    } catch (_e) { /* a malformed draft is dropped, never sent */ }
  }, [token]);
  // QUOTES ARRIVE WHILE THE CUSTOMER IS LOOKING AT THE PAGE. Suppliers answer asynchronously and
  // nothing pushes that to the browser, so until now the only way to see a new quote was to reload
  // — on the one screen whose whole purpose is waiting for quotes. The tab-focus refetch is the
  // one that matters (a customer comes back to the tab after doing something else); the interval
  // is deliberately slow and only reloads the RFQ list, which is where a quote lands. Both are
  // skipped while the tab is hidden, so a backgrounded portal costs nothing.
  // The overview's alert cards and headline are written by the server in `lang`, so a language
  // switch must ask for them again (audit 21 Sep 2026, item 23: the cards stayed in the old language
  // until a full reload). Skipped on the first render — the boot effect above already loads them.
  useEffect(() => { if (langLoaded.current !== lang) { langLoaded.current = lang; loadOv(); } }, [lang]);
  useEffect(() => {
    const visible = () => typeof document === 'undefined' || document.visibilityState === 'visible';
    const onVis = () => { if (visible()) { loadInq(); loadOv(); } };
    document.addEventListener('visibilitychange', onVis);
    const iv = setInterval(() => { if (visible()) loadInq(); }, 60000);
    return () => { document.removeEventListener('visibilitychange', onVis); clearInterval(iv); };
  }, [token]);
  // THE SHELL MOUNTS FIRST AND THE CONTENT FILLS IN. This was an early return to a centred
  // "Loading your requests…" with no navigation at all, so the first thing a customer saw was a
  // blank page that then became a different page. The frame is knowable before the data is.
  const booting = !ov && !data && !err;
  const s = (ov && ov.stats) || {}; const inqs = (data && data.inquiries) || [];
  const alertsCount = Number((ov && ov.alerts_count) ?? ((ov && ov.alerts) || []).length) || 0;
  const projects = (pd && Array.isArray(pd.projects)) ? pd.projects : [];
  const savingsPct = pd ? pd.avg_savings_pct : null;
  // The filter is over the rows already on screen, so it costs no request and cannot disagree with
  // the list it filters. Matching is over the fields a customer would actually recall about their
  // own request — what it was for, where, and its reference.
  const needle = qtext.trim().toLowerCase();
  // Two facts the six old tiles could not state, both derived from rows already on screen:
  // how many requests are actually WAITING ON THE CUSTOMER (two or more quotes is the exact
  // condition under which a comparison exists to decide), and how many reveals they have paid for —
  // the only money a customer ever pays us, and the thing "Spend" was quietly standing in for.
  const awaiting = inqs.filter((i) => (i.quotes || []).length >= 2 && !(i.quotes || []).some((q) => q.revealed)).length;
  const reveals = inqs.filter((i) => (i.quotes || []).some((q) => q.revealed)).length;
  // ── WHOSE MOVE IS IT ──────────────────────────────────────────────────────────────────────────
  // "I wish I could see, on one screen, which of my requests is waiting on ME versus waiting on a
  // supplier." The portal already knew this per request — it is exactly what the lifecycle pill
  // says — but only one request at a time, and only if you read every rail on the page. The answer
  // is a partition of rfqState, so it costs no request and CANNOT disagree with the pill on the row
  // it summarises: same function, same input, one screen up.
  const ballOf = (i) => {
    const st = stateOf(i, i.quotes || []);
    if (st === 'closed') return 'done';
    if (st === 'revealed') return 'moving';          // you paid; you and the supplier are talking
    if (st === 'matching') return 'suppliers';       // posted, nobody has quoted yet
    return 'you';                                    // quoting / quotes_in — a decision is open
  };
  const ball = { you: 0, suppliers: 0, moving: 0, done: 0 };
  for (const i of inqs) ball[ballOf(i)] += 1;
  const liveCount = ball.you + ball.suppliers + ball.moving;
  // Both filters are over the rows already on screen, so they cost no request and cannot disagree
  // with the list they filter. Matching is over the fields a customer would actually recall about
  // their own request — what it was for, where, and its reference.
  const shown = inqs
    .filter((i) => ballFilter === 'all' || ballOf(i) === ballFilter)
    .filter((i) => !needle || [i.summary, i.category, i.emirate, i.status, i.rfq_no].some((f) => String(f || '').toLowerCase().includes(needle)));
  const filtered = ballFilter !== 'all' || !!needle;
  const onlyRequests = view === 'requests';
  // WHERE THIS PORTAL CAN GO, WRITTEN OUT.
  //
  // The module bar this replaced kept every destination as a literal for a stated reason: with the
  // buttons mapped from a config, "nothing — no grep, no reviewer, no route audit — can answer
  // 'where can this portal go' without executing it". Moving the navigation into the shell would
  // have lost exactly that, because the shell calls onView(item.id) with a variable. The table is
  // declared here instead, so the answer is still one grep of this file, and the shell stays a
  // shell. Order is irrelevant — the sidebar groups and ranks them.
  const GO = {
    home:      () => setView('home'),
    requests:  () => setView('requests'),
    projects:  () => setView('projects'),
    documents: () => setView('documents'),
    messages:  () => setView('messages'),
    orders:    () => setView('orders'),
    spatial:   () => setView('spatial'),
    predict:   () => setView('predict'),
    profile:   () => setView('profile'),
    account:   () => setView('account'),
  };
  // A sidebar click is a fresh destination: it must not re-open the request or project an earlier
  // click was aimed at.
  const navigate = (id) => { setFocusInq(''); setFocusProject(''); return GO[id] ? GO[id]() : setView('home'); };
  return (<PortalShell
    lang={lang} t={(k) => t(lang, k)} theme={theme} onSwapTheme={onSwapTheme} onSetLang={onSetLang}
    onSignOut={onSignOut} view={view} onView={navigate} token={token}
    customerName={(ov && ov.customer && ov.customer.name) || ''}
    unread={unread} alerts={alertsCount} alertList={(ov && ov.alerts) || []} onAlert={onAlert} order={ov && ov.layout && ov.layout.order}
    suggestions={assistantOffers(lang, inqs, ballOf)}
  >
  {MODULES.some((m) => m[0] === view) ? (
    <ModuleWindow id={view} onClose={() => navigate('home')} onOpenRfq={openRfq} projectId={focusProject} token={token} lang={lang} inqs={inqs} onChanged={refresh} twin={ov && ov.twin} />
  ) : (
  <div className="mx-auto w-full max-w-[1240px] px-4 py-5 sm:px-6">
    {/* THE WELCOME BAND. §1 asks the opening screen to greet by time of day AND company name; the
        hour is the CLIENT'S, because the server does not know which timezone the customer is in.
        THE DUPLICATE IS GONE: the attention count and ov.headline both rendered "Nothing needs your
        attention right now." one under the other, in two differently-styled boxes, on the screen he
        opened. The count is a number and belongs on a tile; the headline is the sentence. */}
    {/* EVERY DESTINATION SAYS WHERE YOU ARE. Clicking "My requests" used to leave the Overview's
        "Good morning, ahmad test" at the top of it — the greeting is the Overview's identity, and a
        page that borrows another page's title is a page you cannot tell you have arrived at. The
        module panes each carry their own h1; these two now do too. */}
    <section className="mb-5 overflow-hidden rounded-2xl border border-border bg-card/70 p-5 sm:p-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="min-w-0">
          <h1 className="font-head text-[24px] font-extrabold leading-tight tracking-tight text-foreground sm:text-[28px]">
            {/* Arabic uses its own comma (U+060C) and puts no space before it. */}
            {onlyRequests ? t(lang, 'nav_requests')
              : greetingOf(lang) + ((ov && ov.customer && ov.customer.name) ? ((lang === 'ar' ? '، ' : ', ') + ov.customer.name) : '')}
          </h1>
          {/* THE HEADLINE ANSWERS "WHOSE MOVE IS IT", because that is the question the customer
              opened the page with. ov.headline is written by customer_portal from the server's own
              stats and does not know this list: on the screen measured 13 Aug it read "Nothing
              needs your attention right now" directly above a tile saying one decision was
              awaiting the customer. A sentence derived from the rows on screen cannot contradict
              them. The server's headline is still shown when there are no requests to speak for. */}
          <p className="mt-1.5 max-w-[62ch] text-[13.5px] leading-relaxed text-muted-foreground">
            {onlyRequests
              ? (inqs.length + ' ' + t(lang, inqs.length === 1 ? 'req_one' : 'req_many'))
              : liveCount ? ballHeadline(lang, ball)
              : ((ov && ov.headline) || t(lang, 'welcome_sub'))}
          </p>
        </div>
        <Button size="sm" className="shrink-0 gap-1.5" onClick={() => { setShowNew((v) => !v); setPostedGuide(null); }}>
          {/* The label flips to "Close" but the icon did not, so the open intake carried a button
              reading "+ Close" - a plus sign on the control that dismisses the thing. */}
          {showNew ? <X className="h-4 w-4" aria-hidden /> : <Plus className="h-4 w-4" aria-hidden />}
          {showNew ? t(lang, 'close') : t(lang, 'new_request')}
        </Button>
      </div>
    </section>

    {note && <div className={S.note}>{note}</div>}
    {postedGuide && <div className="mb-3.5">
      <ConciergeSteps guide={postedGuide} held={postedGuide.held} lang={lang} title={t(lang, postedGuide.first_inquiry ? 'cg_posted' : postedGuide.held && postedGuide.held.finding_suppliers ? 'cg_finding_title' : 'cg_held')} />
      <Button variant="link" className="h-auto px-0" onClick={() => setPostedGuide(null)}>{t(lang, 'close')}</Button>
    </div>}
    {/* CP-07: the one place a failed overview or request list is reported, with the way out. */}
    {err && <div className="mb-3.5 flex flex-wrap items-center gap-3 rounded-xl border border-danger/30 bg-danger/10 px-4 py-3" role="alert">
      <span className="min-w-0 flex-1 text-[13px] text-danger-fg">{err}</span>
      <Button size="sm" variant="outline" onClick={() => { setErr(''); refresh(); }}>{t(lang, 'retry')}</Button>
    </div>}
    {waAsk && <div className="mb-3.5"><WhatsAppChoice token={token} lang={lang} mode="prompt" current={kyc.whatsapp} mobile={kyc.phone} onDone={() => setWaAsk(false)} /></div>}
    {receipt && <ReceiptNote receipt={receipt} inqs={inqs} lang={lang} onClose={() => setReceipt(null)} />}
    {/* llm_available comes from customer_portal's overview (llm_route_health): it hides the mic
        while transcription is held. Drawings and BOQs are read server-side and are never gated. */}
    {/* An incomplete account is a place to go, not a dead end: create_inquiry answers
        account_incomplete (with `missing`), and the Account page lists exactly what is missing. */}
    {showNew && <div className="mb-5"><NewRequest token={token} lang={lang} pickFile={pickFile}
      call={async (p, b, tk) => { const r = await call(p, b, tk); if (r && r.error === 'account_incomplete') setView('account'); return r; }} llmAvailable={ov ? ov.llm_available : null} initialText={draft}
      onDone={(r) => {
        // `call()` has no fetch timeout, so a connection that hangs rather than fails would leave
        // the skeleton up forever and hide both the list and its error. The ceiling puts the screen
        // back in the customer's hands after 10s.
        // ponytail: a fixed ceiling, because the fix belongs in call() — give it an AbortController
        // and this line goes away.
        setShowNew(false); setPickFile(false); setDraft(''); setPosting(true); setTimeout(() => setPosting(false), 10000); refresh();
        // The request just posted is opened by its stable id: a split opens its combined parent, which
        // lists one card per trade; the note says how many trades were sent separately.
        const n = r && Array.isArray(r.child_ids) ? r.child_ids.length : 0;
        setNote(r && r.none ? '' : n > 1 ? tf(lang, 'request_sent_split', { n }) : t(lang, 'request_sent'));
        // The first-request concierge (founder ledger 1018): a first request, or one held for its specs, gets the
        // steps and what is missing on screen as well as by e-mail.
        const g = r && r.concierge;
        setPostedGuide(g && (g.first_inquiry || (g.held && (g.held.held || g.held.finding_suppliers))) ? g : null);
        if (r && r.inquiry_id) openRfq(r.inquiry_id);
      }} onCancel={() => { setShowNew(false); setPickFile(false); setDraft(''); }} /></div>}

    {/* The severity marker was a 4px border-l — which is both a well-worn generated-UI tell and,
        more to the point here, LEFT: in Arabic it lands on the wrong edge of the card. A tinted
        glyph carries the same three levels, on the correct side, in both directions. */}
    {/* Each alert opens what it is about (onAlert): "2 quotes to review on HVAC" was a box you could
        read and not act on, and the request it named was somewhere further down the page. */}
    {ov && !!(ov.alerts || []).length && <div className="mb-5 flex flex-col gap-2">{ov.alerts.map((a, i) => (
      <button key={i} type="button" onClick={() => onAlert(a)} className="flex w-full items-start gap-3 rounded-xl border border-border bg-card px-4 py-3 text-start transition-colors hover:border-primary/40 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring">
        <span className={cn('mt-0.5 grid h-7 w-7 shrink-0 place-items-center rounded-lg',
          a.severity === 'high' ? 'bg-danger/15 text-danger' : a.severity === 'medium' ? 'bg-warn/15 text-warn-fg' : 'bg-primary/15 text-primary')}>
          <BellRing className="h-3.5 w-3.5" aria-hidden />
        </span>
        <span className="min-w-0 flex-1"><b className="block text-[13.5px] text-foreground">{a.title}</b>
          <span className="block text-xs leading-relaxed text-muted-foreground">{a.detail}</span></span>
        <ArrowRight className={cn('mt-1 h-3.5 w-3.5 shrink-0 text-muted-foreground', rtl && 'rotate-180')} aria-hidden />
      </button>))}</div>}

    {!onlyRequests && !err && (ov ? (
      <div className="mb-5 grid grid-cols-2 gap-3 lg:grid-cols-4">
        <StatTile icon={FileText} label={t(lang, 'k_open')} value={s.open_inquiries ?? 0} hint={t(lang, 'k_open_hint')} />
        <StatTile icon={MessageSquareQuote} label={t(lang, 'k_quotes')} value={s.quotes_received ?? 0} hint={t(lang, 'k_quotes_hint')} />
        <StatTile icon={BellRing} label={t(lang, 'k_awaiting')} value={awaiting} hint={t(lang, 'k_awaiting_hint')} tone={awaiting > 0 ? 'accent' : 'default'} />
        <StatTile icon={KeyRound} label={t(lang, 'k_reveals')} value={reveals} hint={t(lang, 'k_reveals_hint')} />
      </div>
    ) : (
      // A skeleton, not a spinner: the tiles are already four boxes, so show four boxes.
      <div className="mb-5 grid grid-cols-2 gap-3 lg:grid-cols-4" aria-hidden>
        {[0, 1, 2, 3].map((i) => <Card key={i} className="h-[104px] motion-safe:animate-pulse bg-secondary/25" />)}
      </div>
    ))}

    {/* Compare opens the request that HAS two quotes (the most recent one), not the list; Upload
        opens the composer with its file picker already open, not the composer alone. */}
    {!onlyRequests && <QuickActions lang={lang} onNew={() => openNew(false)} onUpload={() => openNew(true)}
      onCompare={() => { const c = inqs.flatMap((i) => [i, ...(i.children || [])]).find((i) => (i.quotes || []).length >= 2); openRfq(c ? c.id : ''); }}
      comparable={inqs.flatMap((i) => [i, ...(i.children || [])]).filter((i) => (i.quotes || []).length >= 2).length} />}
    {!onlyRequests && <div className="mb-5"><DecisionSupport token={token} lang={lang === 'ar' ? 'ar' : 'en'} onOpenRfq={openRfq} /></div>}
    {/* §2 THE PROFILE, ON THE ENTRY SCREEN. Six KPI tiles say what the customer has DONE; the twin
        says who they ARE — industry, live projects, the suppliers they keep coming back to, the
        categories they actually buy, and how much of that profile we hold.
        It is the same object the Company profile window opens, rendered from the overview payload
        the dashboard already has, so opening the portal costs no extra call. */}
    {/* ABOVE the twin, and above the request list, because it is the only thing on this screen
        that tells the customer what to DO. It renders nothing at all when there is nothing to
        recommend, nothing quiet and no category history, so it never occupies the best space on
        the page with an empty heading. */}
    {!onlyRequests && ov && ov.twin ? <div className="mb-5"><CompanyTwin twin={ov.twin} lang={lang === 'ar' ? 'ar' : 'en'} /></div> : null}
    {/* ── THE PROJECTS / FINANCIAL / SUPPLIER-NETWORK PANELS (§1, §4) ──────────────────────────
        Every figure below is nullable and every one of them says which absence is true rather than
        printing a zero that reads as a measurement. timeline_pct is null for a project with no
        target date, so no bar is drawn for it; supplier_count is a count and 0 is a real answer;
        avg_savings_pct is null until two quotes have landed on the same RFQ, and printing 0% there
        would tell a customer their price spread is zero when it is simply not yet known. */}
    {!onlyRequests && <>
    <div className={cn(S.h2, 'mt-[18px] mb-1')}>{t(lang, 'active_projects')}</div>
    {pdFailed ? <Card className="p-5"><div className={S.sub}>{t(lang, 'projects_failed')}</div></Card>
      : !pd ? <Card className="p-5"><div className={S.sub}>{t(lang, 'loading')}</div></Card>
      : !projects.length ? <Card className="p-5"><div className={S.sub}>{t(lang, 'no_projects')}<button className="text-primary font-semibold" onClick={() => setView('projects')}>{t(lang, 'open_module')}</button></div></Card>
      : (<>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-2.5">
          {projects.map((p) => {
            const openN = Number(p.rfq_open) || 0, totalN = Number(p.rfq_count) || 0;
            const budget = p.budget_total == null ? null : Number(p.budget_total);
            const timeline = p.timeline_pct == null ? null : Math.max(0, Math.min(100, Number(p.timeline_pct)));
            // The card opens THAT project's workspace (ProjectsModule initialProjectId, the same
            // project_summary.project_id ProjectList's own cards open by). It was a plain box.
            return (<Card key={p.project_id} role="button" tabIndex={0} aria-label={p.name}
              onClick={() => openProject(p.project_id)}
              onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openProject(p.project_id); } }}
              className="cursor-pointer p-3.5 transition-colors duration-200 hover:border-primary/40 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring">
              <div className="flex justify-between items-center gap-2"><b className="text-[13.5px] text-foreground">{p.name}</b><span className={S.sub}>{projectStatusLabel(lang, p.status)}</span></div>
              <div className={cn(S.sub, 'mt-1')}>{tf(lang, 'rfqs_open_line', { open: openN, total: totalN })}{' · '}{tf(lang, 'suppliers_engaged_line', { n: Number(p.supplier_count) || 0 })}</div>
              <div className={cn(S.sub, 'mt-0.5')}>{budget == null ? t(lang, 'no_budget_set') : (t(lang, 'budget_label') + ': ' + aed(budget))}</div>
              {timeline == null
                ? <div className={cn(S.sub, 'mt-1 text-muted-foreground/70')}>{t(lang, 'no_target_date')}</div>

                : (<div className="mt-1.5">
                    <div className="h-1.5 rounded-full bg-secondary/60 overflow-hidden"><div className="h-full rounded-full bg-primary transition-[width] duration-500" role="progressbar" aria-valuenow={Math.round(timeline)} aria-valuemin={0} aria-valuemax={100} style={{ width: Math.round(timeline) + '%' }} /></div>
                    <div className={cn(S.sub, 'mt-0.5')}>{Math.round(timeline) + '% ' + t(lang, 'timeline_progress')}</div>
                  </div>)}
            </Card>);
          })}
        </div>
        <div className={cn(S.sub, 'mt-2')}>{savingsPct == null ? t(lang, 'savings_unknown') : (t(lang, 'savings_potential') + ': ' + savingsPct + '%')}</div>
      </>)}
    </>}
    <div className="mb-2 mt-[22px] flex items-center justify-between gap-3">
      <h2 className="font-head text-[16px] font-bold tracking-tight text-foreground">{t(lang, 'your_requests')}</h2>
      {!onlyRequests && inqs.length > 3 ? (
        <button type="button" onClick={() => setView('requests')} className="inline-flex items-center gap-1 text-[12.5px] font-semibold text-primary">
          {t(lang, 'view_all')}<ArrowRight className={cn('h-3.5 w-3.5', rtl && 'rotate-180')} aria-hidden />
        </button>) : null}
    </div>
    {inqs.length > 0 && <input type="search" className={S.field} placeholder={t(lang, 'search_requests')} aria-label={t(lang, 'search_requests')} value={qtext} onChange={(e) => setQtext(e.target.value)} />}
    {/* The same partition as the headline, as a filter. A chip with a zero behind it is not
        rendered: a control that can only ever produce an empty list is a dead end with a number
        on it. Same reasoning as the disabled "Compare quotes" quick action. */}
    {inqs.length > 1 && (
      <div className="mt-2.5 flex flex-wrap gap-2" role="group" aria-label={t(lang, 'your_requests')}>
        {[['all', inqs.length], ['you', ball.you], ['suppliers', ball.suppliers], ['moving', ball.moving], ['done', ball.done]]
          .filter(([k, n]) => k === 'all' || n > 0)
          .map(([k, n]) => (
            <button key={k} type="button" onClick={() => setBallFilter(k)} aria-pressed={ballFilter === k}
              className={cn('inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-[12.5px] font-semibold transition-colors focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring',
                ballFilter === k ? 'border-primary/45 bg-primary/12 text-primary' : 'border-border bg-card/60 text-muted-foreground hover:border-primary/30 hover:text-foreground')}>
              {t(lang, 'ball_' + k)}
              <span className="tabular-nums opacity-70">{n}</span>
            </button>
          ))}
      </div>
    )}
    {/* THE EMPTY STATE THAT TELLS THEM WHAT HAPPENS NEXT. It was one grey sentence in a box; on a
        brand-new account — which is every account on day one — it was the main thing on the screen.
        A first-time customer needs to know what posting a request actually does before they do it. */}
    {booting || posting ? (
      <div className="mt-3 flex flex-col gap-3" aria-busy="true" aria-label={t(lang, 'loading_requests')}>
        {[0, 1, 2].map((i) => <Card key={i} className="h-[86px] motion-safe:animate-pulse bg-secondary/25" />)}
      </div>
    ) : !inqs.length ? (
      <Card className="mt-3 p-6 sm:p-8">
        <div className="mx-auto max-w-[54ch] text-center">
          <span className="mx-auto grid h-12 w-12 place-items-center rounded-2xl bg-primary/12 text-primary"><Sparkles className="h-5 w-5" aria-hidden /></span>
          <h3 className="mt-3 font-head text-[17px] font-bold text-foreground">{t(lang, 'empty_title')}</h3>
          <p className="mt-2 text-[13.5px] leading-relaxed text-muted-foreground">{t(lang, 'empty_body')}</p>
          <Button className="mt-4 gap-1.5" onClick={() => setShowNew(true)}><Plus className="h-4 w-4" aria-hidden />{t(lang, 'post_first')}</Button>
        </div>
        <WhatHappensNext lang={lang} terms={data && data.guarantee_terms} />
      </Card>
    ) : (filtered && !shown.length) ? <Card className="mt-3 p-5"><div className={S.sub}>{t(lang, needle ? 'no_search_match' : 'ball_none_you')}</div></Card>
      : filtered ? <div className={cn(S.list, 'mt-3')}>{shown.map((i) => <InquiryCard key={i.id} inq={i} token={token} lang={lang} onChange={refresh} terms={data && data.guarantee_terms} focusQuote={focusQuote} focusInq={focusInq} linkQuote={linkQuote} />)}</div>
      // The overview shows the five most recent and links to the full list; My requests shows all.
      // Mapped then sliced, rather than sliced then mapped, so this stays the dashboard's list over
      // `inqs` — the thing the entry-not-login-dashboard leg reads to tell a workspace carrying live
      // work from a page of figures and links. Ten rows at most; the extra map costs nothing.
      : <div className={cn(S.list, 'mt-3')}>{inqs.map((i) => <InquiryCard key={i.id} inq={i} token={token} lang={lang} onChange={refresh} terms={data && data.guarantee_terms} focusQuote={focusQuote} focusInq={focusInq} linkQuote={linkQuote} />).slice(0, onlyRequests ? undefined : 5)}</div>}
    {/* fn_customer_stats computes history_12m on EVERY overview call and nothing drew it; recharts
        and ui/chart.tsx were installed with no importers, so the customer product contained zero
        charts. Each chart states what is true when there is nothing to draw rather than rendering
        a flat line at zero, which reads as a real but quiet year. */}
    {/* null until my_inquiries answers: an empty array here read "You have no requests yet" while loading. */}
    {!onlyRequests && <div className="mt-5"><SpendingIntelligence stats={s} inquiries={data ? inqs : null} lang={lang === 'ar' ? 'ar' : 'en'} /></div>}
  </div>
  )}
  </PortalShell>);
}

// THE QUICK ACTIONS RAIL. Reference A carries a stack of icon+label rows; ours are the four things
// a procurement customer actually does. Every one is a real destination that already exists — a new
// request, the comparison inside a request, the drawing upload inside the intake, and the
// assistant. Nothing here is a placeholder.
// "I wish the assistant offered me the next thing instead of waiting to be asked."
//
// The panel opened with three constants — status / how many quotes / what next — shown identically
// to an account that has never posted anything and to one with three quotes sitting undecided. The
// first of those is unanswerable on a new account and the third is the only one that ever varies.
//
// These are built from the same rows the dashboard is already rendering, so the offer is about the
// customer's actual position, and it names the request rather than describing a category of
// request: "Which of the 3 quotes on my HVAC request should I choose?" is a question a procurement
// manager would type; "What is the status of my requests?" is a menu item. Capped at three — a list
// of offers long enough to need reading is a form.
function assistantOffers(lang, inqs, ballOf) {
  const ar = lang === 'ar';
  const out = [];
  const label = (i) => i.category || (ar ? 'طلبي' : 'my request');
  if (!inqs.length) {
    out.push(ar ? 'ماذا يحدث بعد أن أنشر طلبي؟' : 'What happens after I post a request?');
    out.push(ar ? 'كم يكلّفني كشف مورّد؟' : 'What does it cost me to reveal a supplier?');
    out.push(ar ? 'ما المعلومات التي يحتاجها المورّدون لتسعير عملي؟' : 'What do suppliers need to know to price my job?');
    return out;
  }
  const decide = inqs.filter((i) => ballOf(i) === 'you');
  const waiting = inqs.filter((i) => ballOf(i) === 'suppliers');
  const moving = inqs.filter((i) => ballOf(i) === 'moving');
  if (decide.length) {
    const i = decide[0]; const n = (i.quotes || []).length;
    out.push(ar ? `أيّ العروض الـ${n} على طلب ${label(i)} أختار؟`
                : `Which of the ${n} quotes on my ${label(i)} request should I choose?`);
    out.push(ar ? 'كم سيكلّفني كشف المورّد صاحب أقل سعر؟' : 'What would it cost me to reveal the cheapest supplier?');
  }
  if (waiting.length && out.length < 3) {
    const i = waiting[0];
    out.push(ar ? `لماذا لم يصلني عرض بعد على طلب ${label(i)}؟` : `Why has no one quoted my ${label(i)} request yet?`);
  }
  if (moving.length && out.length < 3) {
    out.push(ar ? 'ما الخطوة التالية مع المورّد الذي كشفته؟' : 'What happens next with the supplier I revealed?');
  }
  if (out.length < 3) out.push(t(lang, 'asst_s3'));
  return out.slice(0, 3);
}
// "I wish it told me what happens after I post, without me having to ask."
//
// The empty state said the first request "takes about a minute" and that posting and comparing are
// free. Both true, and neither answers the question a procurement manager is actually holding
// before they hand a job to a platform they have not used: who sees this, when do I hear back, and
// what does it cost me. The four steps are the product as it actually runs — the 3% and the 3
// working days are pricing_config.standard_reveal_rate and refund_window_working_days, the same
// two numbers customer_api charges on.
// CP-16 (22 Sep 2026): step 4 used to state 5 / 3 / 7-14 working days as typed English and Arabic.
// pricing_config had moved the refund window to 5 while the sentence said what it said, which is
// how a promise drifts from what is enforced. The terms now arrive with my_inquiries
// (guarantee_terms — the same object RevealGuarantee reads) and the refund sentence is omitted
// entirely when the server did not send them, rather than inventing a number.
function WhatHappensNext({ lang, terms }) {
  const w = terms && terms.window_days, c = terms && terms.chase_after_days;
  const bmin = terms && terms.bank_min_days, bmax = terms && terms.bank_max_days;
  const refund = w && c && bmin && bmax ? tf(lang, 'next_4_refund', { w, c, bmin, bmax }) : '';
  const steps = ['next_1', 'next_2', 'next_3', 'next_4'];
  return (
    <div className="mx-auto mt-6 max-w-[62ch] border-t border-border pt-5 text-start">
      <div className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">{t(lang, 'next_h')}</div>
      <ol className="mt-2.5 space-y-2.5">
        {steps.map((k, n) => (
          <li key={k} className="flex gap-3">
            <span className="mt-0.5 grid h-5 w-5 shrink-0 place-items-center rounded-full bg-primary/12 text-[11px] font-bold text-primary tabular-nums">{n + 1}</span>
            <span className="min-w-0 text-[13px] leading-relaxed text-muted-foreground">{t(lang, k)}{k === 'next_4' && refund ? ' ' + refund : ''}</span>
          </li>
        ))}
      </ol>
    </div>
  );
}
// The headline sentence for the whose-move split. Built from counts, never from a template with a
// zero in it: "0 requests are waiting on you" is a sentence no one should have to read.
function ballHeadline(lang, ball) {
  const parts = [];
  if (ball.you) parts.push(ball.you === 1 ? t(lang, 'hl_you_one') : ball.you + ' ' + t(lang, 'hl_you_many'));
  if (ball.suppliers) parts.push(ball.suppliers === 1 ? t(lang, 'hl_sup_one') : ball.suppliers + ' ' + t(lang, 'hl_sup_many'));
  if (ball.moving) parts.push(ball.moving === 1 ? t(lang, 'hl_mov_one') : ball.moving + ' ' + t(lang, 'hl_mov_many'));
  if (!parts.length) return t(lang, 'hl_all_quiet');
  if (!ball.you) return t(lang, 'hl_nothing');
  return parts.join(lang === 'ar' ? '، ' : ' · ') + '.';
}
function QuickActions({ lang, onNew, onUpload, onCompare, comparable }) {
  const rtl = lang === 'ar';
  // A BUTTON THAT CANNOT DO ITS JOB SHOULD SAY SO, NOT PRETEND. "Compare quotes" navigated to My
  // requests unconditionally, so on a new account — which is every account on day one — it landed
  // the customer on an empty list with nothing to compare and no explanation. Comparison needs a
  // request carrying at least TWO quotes; that is the same threshold quote_compare itself runs on.
  // Below it the control is disabled and carries the reason, rather than spending a click on a
  // dead end.
  const rows = [
    { icon: Plus, label: 'qa_new', run: onNew },
    { icon: Scale, label: 'qa_compare', run: onCompare, off: comparable === 0, why: 'qa_compare_off' },
    { icon: Upload, label: 'qa_upload', run: onUpload },
    // A BUTTON HAS TO DO SOMETHING WHERE THE FINGER IS. This focused #qd-ask and stopped there: on
    // the dashboard that put a caret in a field at the top of the page and changed nothing else,
    // and at 375 the top bar collapses the field to an icon, so "Ask the assistant" moved a caret
    // the customer could not see. Submitting the empty form is the shell's own path to opening the
    // panel (submitAsk: no text -> setAsstOpen(true)), so this reuses it rather than adding a
    // second way in that could disagree with the first.
    { icon: Sparkles, label: 'qa_ask', run: () => {
      const el = document.getElementById('qd-ask');
      if (!el) return;
      el.focus();
      const form = el.closest('form');
      if (form) form.requestSubmit();
    } },
  ];
  return (
    <section className="mb-5" aria-label={t(lang, 'quick_actions')}>
      <h2 className="mb-2 font-head text-[13px] font-bold uppercase tracking-[0.08em] text-muted-foreground/70">{t(lang, 'quick_actions')}</h2>
      {/* One column below 420px: at 375 a two-up grid truncated every label to "New req…". */}
      <div className="grid grid-cols-1 gap-2 min-[420px]:grid-cols-2 lg:grid-cols-4">
        {rows.map(({ icon: Icon, label, run, off, why }) => (
          <button key={label} type="button" onClick={run} disabled={!!off} title={off ? t(lang, why) : undefined}
            className={cn('group flex items-center gap-3 rounded-xl border border-border bg-card/60 px-3.5 py-3 text-start transition-[border-color,transform] duration-200 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring',
              off ? 'cursor-not-allowed opacity-55' : 'hover:border-primary/40 motion-safe:hover:-translate-y-0.5')}>
            <span className={cn('grid h-8 w-8 shrink-0 place-items-center rounded-lg', off ? 'bg-secondary/60 text-muted-foreground' : 'bg-primary/12 text-primary')}><Icon className="h-4 w-4" aria-hidden /></span>
            <span className="min-w-0 flex-1">
              <span className="block truncate text-[13px] font-semibold text-foreground">{t(lang, label)}</span>
              {off ? <span className="mt-0.5 block truncate text-[11px] text-muted-foreground">{t(lang, why)}</span> : null}
            </span>
            {!off ? <ArrowRight className={cn('h-3.5 w-3.5 shrink-0 text-muted-foreground transition-transform duration-200 group-hover:translate-x-0.5', rtl && 'rotate-180 group-hover:-translate-x-0.5')} aria-hidden /> : null}
          </button>
        ))}
      </div>
    </section>
  );
}

// THE STRIPE RETURN, ON SCREEN. A payment used to end on a one-line note (or, when cancelled, on
// nothing at all); this states what was paid and that the guarantee clock started, or that nothing
// was charged.
function ReceiptNote({ receipt, inqs, lang, onClose }) {
  const reduce = useReducedMotion();
  // 21 Sep 2026 (customer audit, finding 17): "Payment received" never went away. The amount is
  // stated on the request card too (c_paid), so the receipt leaves by itself after 15 seconds.
  // Armed once on mount: the parent passes a fresh arrow each render, and re-arming on every render would never let it fire.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { const id = setTimeout(onClose, 15000); return () => clearTimeout(id); }, []);
  const all = inqs.flatMap((i) => [i, ...(i.children || [])]);
  const q = receipt.quoteId ? all.flatMap((i) => i.quotes || []).find((x) => x.id === receipt.quoteId) : null;
  const paid = receipt.kind === 'paid';
  return (<M.div role="status" initial={reduce ? false : { opacity: 0, y: -8, scale: 0.98 }} animate={{ opacity: 1, y: 0, scale: 1 }} transition={{ duration: reduce ? 0 : 0.35, ease: [0.2, 0.8, 0.2, 1] }}
    className="qd-panel mb-5 flex items-start gap-3 p-4">
    <M.span initial={reduce ? false : { scale: 0.4, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} transition={{ type: 'spring', stiffness: 380, damping: 18, delay: reduce ? 0 : 0.12 }}
      className={cn('grid h-9 w-9 shrink-0 place-items-center rounded-full', paid ? 'bg-primary/20 text-primary' : 'bg-secondary text-muted-foreground')}>
      {paid ? <Check className="h-4 w-4" aria-hidden /> : <X className="h-4 w-4" aria-hidden />}
    </M.span>
    <div className="min-w-0 flex-1">
      {paid
        ? <><div className="font-head text-[15px] font-bold text-foreground">{t(lang, 'rcpt_title')}</div><p className="mt-0.5 text-[13px] text-muted-foreground">{q ? tf(lang, 'rcpt_body', { fee: aed(q.total_charged ?? q.reveal_fee) }) : t(lang, 'payment_confirmed')}</p></>
        : <p className="text-[13px] text-foreground">{t(lang, 'rcpt_cancelled')}</p>}
    </div>
    <button type="button" onClick={onClose} aria-label={t(lang, 'close')} className="text-muted-foreground hover:text-foreground"><X className="h-4 w-4" aria-hidden /></button>
  </M.div>);
}
export { Dashboard };
