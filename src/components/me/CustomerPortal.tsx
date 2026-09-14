// @ts-nocheck
'use client';
import { useEffect, useState, useRef } from 'react';
import { createClient } from '@supabase/supabase-js';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Seal, Kicker } from '@/components/ui/sealed';
import { cn } from '@/lib/utils';
import { categoryLabel } from '@/lib/categoryLabel';
import { durationLabel } from '@/lib/durationLabel';
import { statusLabel as projectStatusLabel } from '@/components/portal/projects/strings';
// Spec §22 modules that were written and never mounted. Each renders ONLY fields the endpoint it
// names already returns; see the header comment in each file for the field-by-field provenance.
import { ProjectsModule } from '@/components/portal/projects';
// recharts is the heaviest thing on /me and this chart sits below the fold, so it loads on its own
// after the portal is on screen (website audit 14 Sep 2026: 1.37 MB portal first load).
import dynamic from 'next/dynamic';
const SpendingIntelligence = dynamic(() => import('@/components/portal/intelligence/SpendingIntelligence').then((m) => m.SpendingIntelligence), { ssr: false });
import { SupplierRelationshipCard, DiscoveryReachPanel } from '@/components/portal/suppliers/SupplierRelationship';
// The five surfaces the module agents exported and nothing mounted. Each fetches its own endpoint
// and owns its own empty state; the portal supplies only the token, the language and — where the
// surface can use them — rows it already holds, so nothing is fetched twice.
import { SpatialModule } from '@/components/portal/spatial';
import { DocumentVault } from '@/components/portal/documents';
import { CommunicationCenter } from '@/components/portal/comms';
import { ApprovalChain, OrdersList } from '@/components/portal/approvals';
import { PredictiveIntelligence, NegotiationAssistant } from '@/components/portal/predict';
// §2 the Company Digital Twin, §9 Supplier Discovery and §17 Customer AI Memory. fn_twin,
// v_digital_twin, customer_score and customer_preference were all built and read only by os_api —
// the staff console — so the customer could not see their own profile or correct it.
import { CompanyTwin, SupplierDiscovery, CustomerMemory, DecisionSupport } from '@/components/portal/twin';
// THE SHELL. The portal was a stack of cards under ten grey pills; this is the application frame
// the founder asked for — persistent grouped sidebar, a top bar whose widest element is the
// assistant, a mobile tab bar, and the assistant docked in the layout rather than floating in a
// corner. See the header of PortalShell.tsx for what was on the screen before and why.
import { PortalShell, StatTile, StatusPill, rfqState } from './PortalShell';
import { FileText, MessageSquareQuote, BellRing, KeyRound, Plus, X, Sparkles, Upload, Scale, ArrowRight, ChevronDown, Lock, Check } from 'lucide-react';
// expires_at / expired were served on every quote and never shown. The branch that phrases them
// decides whether a customer pays a reveal fee on a lapsed price, so it lives in a file that can be
// executed — see quoteExpiry.test.mjs — rather than inline in this one.
import { expiryOf } from './quoteExpiry';
// Website audit 14 Sep 2026: the intake composer, the pre-reveal Q&A, the Reveal Guarantee and the
// in-page confirm each live in their own file under src/components/me; this file wires them in.
import { NewRequest } from './NewRequest';
import { Clarifications } from './Clarifications';
import { RevealGuarantee } from './RevealGuarantee';
import { QuoteBadges } from '@/components/QuoteBadges';
import { useConfirm } from './ConfirmDialog';
import { motion, useReducedMotion } from 'motion/react';

// The customer portal is the page a paying customer uses. Its Supabase target was an inline
// fallback to the production ref, so an unconfigured preview signed real customers in against the
// LIVE database. supaEnv resolves it once and warns on fallback; see the note there.
import { SUPA_URL as URL, SUPA_ANON as ANON, SUPA_FN as FN } from '@/lib/supaEnv';
const SB = createClient(URL, ANON, { auth: { persistSession: true, autoRefreshToken: true, storageKey: 'qd-cust-auth' } });
// A TOKEN READ FROM localStorage IS NOT A TOKEN THAT STILL WORKS. It is restored synchronously on
// mount while the Supabase client refreshes asynchronously, so for the first moment after a page
// has been left open past the 60-minute expiry the portal holds a JWT that every endpoint will
// answer 401 to. The retry-then-refresh path recovers and the customer sees nothing, but it spends
// a round trip and prints a red error on a healthy page - and a console with routine errors in it
// is one where a real error is easy to miss. Cheaper to read the `exp` we already have.
// Sixty seconds of slack so a token about to die mid-flight is treated as already dead.
const tokenAlive = (t) => {
  if (!t) return false;
  try { return (JSON.parse(atob(String(t).split('.')[1])).exp || 0) > (Date.now() / 1000) + 60; }
  catch (_e) { return true; } // unparseable: let the endpoint be the judge, do not lock anyone out
};
async function call(path, body, token) { const r = await fetch(FN + '/' + path, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (token || ANON) }, body: JSON.stringify(body) }); return r.json(); }
// The five reads the dashboard makes on its first render, started beside the kyc gate rather than
// behind it — see prefetch.ts for the measurement. Keys are what Dashboard and DecisionSupport take.
import { warm, take, drop } from './prefetch';
const warmDashboard = (tk, lang) => {
  warm(tk, 'inq', () => call('customer_api', { action: 'my_inquiries' }, tk));
  warm(tk, 'ov', () => call('customer_portal', { action: 'overview', lang }, tk));
  warm(tk, 'pd', () => call('project_api', { action: 'dashboard' }, tk));
  warm(tk, 'threads', () => call('messages_api', { action: 'threads' }, tk));
  warm(tk, 'decision_support', () => call('customer_portal', { action: 'decision_support', lang }, tk));
};
function initLang(){ try{ if(typeof window==='undefined') return 'en'; const ls=localStorage.getItem('qd-lang'); if(ls) return ls; const m=document.cookie.match(/(?:^|; )NEXT_LOCALE=([^;]+)/); if(m && String(m[1]).startsWith('ar')) return 'ar'; }catch(_e){} return 'en'; }
import { t, tf, errText, emirateName } from './portalText';
// The account rule itself, not a copy: the same function customer_api create_inquiry gates on.
import { accountMissing } from '../../../supabase/functions/_shared/account_rule';
import { BrandMark } from '@/components/BrandMark';
// Wrapped in LRI…PDI so "AED 36,900" keeps its order inside an Arabic sentence.
const aed = (n) => '⁦AED ' + Number(n || 0).toLocaleString('en-AE', { maximumFractionDigits: 0 }) + '⁩';
// The hour is the CUSTOMER'S, not the server's: the portal renders client-side only (the shell
// returns null until mounted), so a customer opening it at 07:00 in Dubai is not greeted with the
// deployment region's afternoon. Arabic uses مساء from midday onward, which is why it has two
// branches where English has three.
const greetingOf = (lang) => { const h = new Date().getHours(); if (lang === 'ar') return h < 12 ? 'صباح الخير' : 'مساء الخير'; return h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening'; };
// SPEC §8 names five RFQ stages. Each is read off a fact this component already holds, and none of
// them is asserted from the clock:
//   created  — the row exists, so it is always reached
//   sent     — anything past intake has been dispatched to suppliers
//   quotes   — at least one quote has landed
//   analysis — at least TWO, which is the exact condition under which quote_compare runs and the
//              comparison card mounts on this same request. Below two there is nothing to analyse
//              and the stage must not claim there is.
//   award    — a supplier is hired, or the request is completed
// The server's recorded pipeline_stage wins wherever it speaks — see stateOf below.
const RFQ_STAGES = {
  en: ['Created', 'Sent', 'Quotes received', 'AI analysis', 'Awarded'],
  ar: ['أُنشئ', 'أُرسل', 'وردت العروض', 'تحليل ذكي', 'تم التعاقد'],
};
const rfqStageIdx = (inq, quotes) => {
  if (inq && (inq.status === 'completed' || inq.hired_supplier_id || inq.pipeline_stage === 'won')) return 4;
  const n = (quotes || []).length;
  if (n >= 2) return 3;
  if (n >= 1) return 2;
  return String(inq && inq.status) === 'draft' ? 0 : 1;
};
// §8 THE SERVER'S STAGE, WHERE IT HAS ONE (website audit 14 Sep 2026). my_inquiries serves
// pipeline_stage and every pill, rail and whose-move count ignored it and guessed from
// quotes.length, so a request the lifecycle had cancelled could still read "Matching". The stages
// the lifecycle SQL writes are 'revealed', 'won' and 'cancelled' (scripts/sql and full_schema.sql);
// those decide. Anything else, or null — every production row on 14 Sep, as there are no inquiries
// yet — falls back to the derivation, so no stage is ever invented.
const stateOf = (inq, quotes) => {
  const ps = String((inq && inq.pipeline_stage) || '');
  if (ps === 'cancelled' || ps === 'lost' || ps === 'closed') return 'closed';
  if (ps === 'revealed' || ps === 'won') return 'revealed';
  return rfqState(inq, quotes);
};
// Pre-reveal labels are served as 'Supplier A'; the letter is the identity-free part.
const supLabel = (label, lang) => (lang === 'ar' ? String(label || '').replace(/^Supplier\b/, 'المورّد') : label);
// Pre-reveal, customer_api returns a coarse rating BAND ('4.5+', '4.0-4.5', ...) instead of a number.
// Bands are looked up here first so a banded string is never handed to Number() (which yields NaN).
const RATING_BANDS = { '4.5+': 4.75, '4.0-4.5': 4.25, '3.5-4.0': 3.75, 'below 3.5': 3.0 };
// Returns null — not a number — when the supplier has no QuotesDone rating (founder, 9 Sep 2026:
// "google review shouldnt be counted"; the Google fallback that used to fill this in is gone, so
// every supplier is unrated until a customer rates one). The value score drops the rating term and
// rescales the remaining weights: an absent rating must be ABSENT from the weighting, never a 0
// that ranks a good supplier last, and never a 60 that flatters a genuinely poor one.
const ratingScoreOf = (r) => { if (r == null) return null; const b = RATING_BANDS[String(r).trim()]; if (b != null) return Math.round((b / 5) * 100); const n = Number(r); return Number.isFinite(n) ? Math.round((n / 5) * 100) : null; };
const EMIRATES = ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Ras Al Khaimah', 'Umm Al Quwain', 'Fujairah'];

const S = {
  center: 'grid place-items-center min-h-[70vh] p-5',
  h1: 'text-xl font-extrabold text-foreground',
  h2: 'text-[15px] font-bold text-foreground',
  sub: 'text-[13px] leading-relaxed text-muted-foreground',
  hint: 'text-xs text-muted-foreground my-2 leading-relaxed',
  err: 'text-[13px] text-danger-fg mt-2',
  note: 'rounded-lg border border-primary/35 bg-primary/10 text-primary px-3.5 py-2.5 mb-3.5 text-[13px] font-semibold',
  wrap: 'max-w-[1040px] mx-auto p-[22px]',
  frow: 'flex gap-2.5 flex-wrap mt-2.5',
  tabsWrap: 'inline-flex flex-wrap gap-1.5 rounded-xl bg-secondary/40 p-1',
  tab: 'rounded-md px-3.5 py-2 text-[13px] font-semibold text-muted-foreground cursor-pointer border-0 bg-transparent',
  tabOn: 'bg-primary/15 text-primary',
  list: 'flex flex-col gap-3',
  field: 'mt-3 flex h-[42px] w-full rounded-md border border-input bg-transparent px-3 text-sm text-foreground placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring',
  area: 'mt-3 flex w-full rounded-md border border-input bg-transparent px-3 py-2.5 text-sm text-foreground placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring resize-y',
  fileInput: 'text-sm text-muted-foreground file:mr-3 file:rounded-md file:border-0 file:bg-secondary file:px-3 file:py-1.5 file:text-sm file:font-medium file:text-secondary-foreground hover:file:bg-secondary/80',
};

export function CustomerPortal() {
  const [lang, setLangState] = useState('en');
  const [token, setToken] = useState('');
  const [phase, setPhase] = useState('login');
  const [mounted, setMounted] = useState(false);
  // SPEC §21 asks for dark mode as an OPTION. The portal was served under html{color-scheme:dark}
  // with no light branch anywhere in globals.css, so "dark" was a decision made FOR the customer and
  // there was nothing to switch to. The light palette is a data-theme branch on .osx (globals.css);
  // this is the control that sets it, and the choice is remembered per device.
  const [theme, setTheme] = useState('dark');
  useEffect(() => {
    setMounted(true);
    try { const th = localStorage.getItem('qd-theme'); if (th === 'light' || th === 'dark') setTheme(th); } catch (_e) {}
    try { const l = initLang(); if (l !== 'en') setLangState(l); } catch (_e) {}
    try { const tk = localStorage.getItem('qd-cust-token'); if (tk) { setToken(tk); setPhase('app'); } } catch (_e) {}
    SB.auth.getSession().then(({ data }) => { const ss = data.session; if (ss && ss.access_token) { setToken(ss.access_token); try { localStorage.setItem('qd-cust-token', ss.access_token); if (ss.refresh_token) localStorage.setItem('qd-cust-refresh', ss.refresh_token); } catch (_e) {} setPhase('app'); } }).catch(() => {});
    // THE PORTAL SIGNED PEOPLE OUT EVERY HOUR WHILE HOLDING A VALID REFRESH TOKEN (13 Aug 2026).
    //
    // A Supabase access token lives 60 minutes. This client is created with autoRefreshToken:true
    // and the refresh token is stored, so supabase-js WAS quietly minting a fresh one on schedule —
    // and nothing here listened. `call()` sends the `token` state captured at mount, so at the
    // 60-minute mark every request began returning 401 and Authed showed "Your session has expired.
    // Please sign in again." to a customer whose session had not expired at all. Found by leaving
    // the portal open for an hour while clicking through it.
    //
    // One listener. TOKEN_REFRESHED carries the new access token; SIGNED_OUT carries null and must
    // NOT be mistaken for a refresh failure, so the phase is only ever moved forward here.
    let sub;
    try {
      sub = SB.auth.onAuthStateChange((_evt, ss) => {
        const at = ss && ss.access_token;
        if (!at) return;
        setToken(at);
        try { localStorage.setItem('qd-cust-token', at); if (ss.refresh_token) localStorage.setItem('qd-cust-refresh', ss.refresh_token); } catch (_e) {}
      });
    } catch (_e) {}
    return () => { try { sub && sub.data && sub.data.subscription && sub.data.subscription.unsubscribe(); } catch (_e) {} };
  }, []);
  const setLang = (l) => { try { localStorage.setItem('qd-lang', l); } catch (_e) {} setLangState(l); };

  // THE DOCUMENT ITSELF NEVER LEARNED IT HAD SWITCHED LANGUAGE (13 Aug 2026). Measured in the
  // browser with the portal fully in Arabic: document.documentElement.dir was "ltr" and .lang was
  // "en". Every panel sets dir="rtl" on its own <section>, which is why the SCREENSHOT looks
  // correct and hid this - but the root element is what a screen reader reads to choose a voice
  // and pronunciation rules, so an Arabic portal was being announced as English. It is also what
  // the browser uses for hyphenation, quotation marks, and the direction of anything that does not
  // carry a dir of its own. The panels keep their local dir; this sets the thing above them.
  useEffect(() => {
    if (typeof document === 'undefined') return;
    document.documentElement.lang = lang === 'ar' ? 'ar' : 'en';
    document.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr';
  }, [lang]);
  const swapTheme = () => { const next = theme === 'dark' ? 'light' : 'dark'; try { localStorage.setItem('qd-theme', next); } catch (_e) {} setTheme(next); };
  // THE STORED PROFILE LOCALE. customers.locale has existed all along and the portal could not
  // honour it: my_inquiries did not serve it (fixed 5 Aug 2026) and this component decided language
  // from localStorage['qd-lang'] and the NEXT_LOCALE cookie alone. An Arabic customer who set their
  // language once got English on every new device, and the Arabic journey exercised a code path the
  // portal could never reach.
  //
  // PRECEDENCE MATTERS: an explicit choice on THIS device wins. setLang writes qd-lang, so if that
  // key exists the customer has chosen, and a profile field must not override a preference they set
  // seconds ago. Only when they have chosen nothing here does the stored locale apply.
  const onServedLocale = (l) => {
    if (l !== 'ar' && l !== 'en') return;
    try { if (localStorage.getItem('qd-lang')) return; } catch (_e) { return; }
    setLangState(l);
  };
  const onAuth = (access, refresh) => { try { localStorage.setItem('qd-cust-token', access || ''); if (refresh) localStorage.setItem('qd-cust-refresh', refresh); } catch (_e) {} setToken(access || ''); setPhase('app'); if (access) { try { SB.auth.setSession({ access_token: access, refresh_token: refresh || '' }).catch(() => {}); } catch (_e) {} } };
  const doSignOut = () => { try { localStorage.removeItem('qd-cust-token'); localStorage.removeItem('qd-cust-refresh'); } catch (_e) {} setToken(''); setPhase('login'); try { SB.auth.signOut().catch(() => {}); } catch (_e) {} };
  const rtl = lang === 'ar';
  if (!mounted) return null;
  // THE STRIP IS FOR THE DOORWAY, NOT THE HOUSE. Signing in and completing a profile are two
  // single-card screens with no navigation to render; the marketing-style bar is right there and
  // wrong the moment the customer is actually inside, which is where PortalShell takes over.
  const strip = (<header className="sticky top-0 z-10 flex items-center justify-between gap-3 px-4 py-3 sm:px-5 bg-background/95 border-b border-border shadow-e1">
    <a className="flex min-w-0 items-center gap-2 font-head text-base font-semibold tracking-snug text-foreground no-underline" href="/"><BrandMark className="h-8 w-8 shrink-0" /><span className="truncate">QuotesDone <span className="hidden font-mono text-label uppercase tracking-caps text-primary sm:inline">{t(lang, 'brand_sub')}</span></span></a>
    <div className="flex gap-2 items-center">
      <Button asChild variant="outline" size="sm"><a href="/">{t(lang, 'home')}</a></Button>
      <Button variant="outline" size="sm" onClick={() => setLang(rtl ? 'en' : 'ar')}>{rtl ? 'EN' : 'عربي'}</Button>
      <Button variant="outline" size="sm" onClick={swapTheme} aria-label={theme === 'dark' ? t(lang, 'theme_light') : t(lang, 'theme_dark')} title={theme === 'dark' ? t(lang, 'theme_light') : t(lang, 'theme_dark')}>{theme === 'dark' ? '☀' : '☾'}</Button>
      {phase === 'app' && <Button variant="outline" size="sm" onClick={doSignOut}>{t(lang, 'signout')}</Button>}
    </div>
  </header>);
  return (<div dir={rtl ? 'rtl' : 'ltr'} data-theme={theme} className="osx min-h-screen bg-background text-foreground">
    {!mounted ? <>{strip}<div className={S.center}>{t(lang, 'loading')}</div></> : (<>
      {/* The signed-in shell carries its own <main>; the doorway screens need one too (audit 14 Sep). */}
      {phase === 'login' && <>{strip}<main><Login onAuth={onAuth} lang={lang} /></main></>}
      {phase === 'app' && <Authed token={token} lang={lang} strip={strip} theme={theme} onSwapTheme={swapTheme} onSetLang={setLang} onSignOut={doSignOut} onServedLocale={onServedLocale} />}
    </>)}
  </div>);
}
// THE DOORWAY GOT THE SAME TREATMENT AS THE HOUSE.
//
// Signing in and finishing a profile were a single 400px card floating in the middle of an
// otherwise empty dark page — the same "extremely basic" the founder described about the portal
// behind it, on the screen a customer sees FIRST. This is the standard two-column product sign-in:
// the promise on one side, the form on the other, and on a phone just the form, because a phone
// has no room for a column of reassurance above the field you came to type in.
//
// The three lines are the product's actual terms, not marketing filler — free to post, anonymous
// until you choose, 3% only on a reveal. A customer deciding whether to sign up is deciding about
// exactly those three facts.
function AuthShell({ lang, children }) {
  const rtl = lang === 'ar';
  const points = ['auth_p1', 'auth_p2', 'auth_p3'];
  return (
    <div className="mx-auto grid w-full max-w-[1080px] items-center gap-10 px-4 py-10 sm:px-5 md:min-h-[76vh] md:grid-cols-[1.05fr_minmax(380px,420px)] md:py-16">
      <div className="hidden md:block">
        <Kicker>{t(lang, 'auth_kicker')}</Kicker>
        <h2 className="mt-5 font-head text-h2 text-foreground">{t(lang, 'auth_h')}</h2>
        <p className="mt-4 max-w-[46ch] text-lead text-muted-foreground">{t(lang, 'auth_sub')}</p>
        {/* The promise, under the brand's own redaction bar: it seals and unseals on a loop. */}
        <p className="mt-6 font-head text-[17px] font-semibold tracking-snug text-foreground"><Seal loop className="max-w-full">{t(lang, 'auth_seal')}</Seal></p>
        <ol className="qd-stagger reveal-stagger mt-8 flex flex-col divide-y divide-border border-y border-border">
          {points.map((k, i) => (
            <li key={k} className="flex items-start gap-4 py-3.5">
              <span className="tabular mt-0.5 w-6 shrink-0 font-mono text-label text-primary">{String(i + 1).padStart(2, '0')}</span>
              <span className="text-copy leading-relaxed text-foreground/90">{t(lang, k)}</span>
              <Check className="ms-auto mt-0.5 h-4 w-4 shrink-0 text-primary" aria-hidden />
            </li>
          ))}
        </ol>
      </div>
      <div className="w-full justify-self-center md:justify-self-end">{children}</div>
    </div>
  );
}
function Login({ onAuth, lang }) {
  const [mode, setMode] = useState('signin'); const [step, setStep] = useState('id'); const [id, setId] = useState(''); const [code, setCode] = useState(''); const [ident, setIdent] = useState(''); const [msg, setMsg] = useState(''); const [busy, setBusy] = useState(false);
  const isSignup = mode === 'signup';
  const looksEmail = (v) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(v || '').trim());
  const send = async () => { const v = id.trim(); if (!v) return; if (isSignup && !looksEmail(v)) { setMsg(t(lang, 'signup_email_only')); return; } setBusy(true); setMsg('');
    try { const g = await call('role_guard', { user_kind: 'customer', identifier: v }); if (g && g.conflict === 'supplier') { setBusy(false); setMsg(t(lang, 'conflict_supplier')); return; } } catch (_e) {}
    let j; try { j = await call('login_otp', { action: 'send', user_kind: 'customer', identifier: v, allow_signup: isSignup }); } catch (_e) { setBusy(false); setMsg(t(lang, 'err_code_send')); return; } setBusy(false); if (j && j.ok) { setIdent(j.identifier || v); setStep('code'); } else setMsg(errText(j, lang, 'err_code_send')); };
  const verify = async () => { if (!code.trim()) return; setBusy(true); setMsg(''); let j; try { j = await call('login_otp', { action: 'verify', user_kind: 'customer', identifier: ident, code: code.trim() }); } catch (_e) { setBusy(false); setMsg(t(lang, 'err_incorrect')); return; } if (!j || !j.ok || !j.access_token) { setBusy(false); setMsg(errText(j, lang, 'err_incorrect')); return; } setBusy(false); onAuth(j.access_token, j.refresh_token); };
  const swap = (m) => { setMode(m); setStep('id'); setMsg(''); setCode(''); };
  return (<AuthShell lang={lang}><Card className="relative w-full overflow-hidden p-6 shadow-e3 sm:p-8">
    <span aria-hidden className="absolute inset-x-10 top-0 h-px bg-gradient-to-r from-transparent via-primary/80 to-transparent" />
    <div className="mb-5 md:hidden"><Kicker>{t(lang, 'auth_kicker')}</Kicker></div>
    <div className={cn(S.tabsWrap, 'mb-5 w-full rounded-btn border border-border bg-secondary/40')} role="tablist">
      <button role="tab" aria-selected={!isSignup} className={cn(S.tab, 'flex-1 transition-colors', !isSignup && cn(S.tabOn, 'shadow-e1'))} onClick={() => swap('signin')}>{t(lang, 'tab_signin')}</button>
      <button role="tab" aria-selected={isSignup} className={cn(S.tab, 'flex-1 transition-colors', isSignup && cn(S.tabOn, 'shadow-e1'))} onClick={() => swap('signup')}>{t(lang, 'tab_signup')}</button>
    </div>
    <h1 className="font-head text-[22px] font-semibold tracking-snug text-foreground">{isSignup ? t(lang, 'create_account_title') : t(lang, 'welcome_back')}</h1>
    <div className={cn(S.sub, 'mt-1.5')}>{isSignup ? t(lang, 'signup_sub') : t(lang, 'signin_sub')}</div>
    {step === 'id' ? (<><Input className="mt-5 h-12 text-copy" aria-label={isSignup ? t(lang, 'email_address') : t(lang, 'email_or_mobile')} autoComplete={isSignup ? 'email' : 'username'} placeholder={isSignup ? t(lang, 'email_address') : t(lang, 'email_or_mobile')} value={id} onChange={(e) => setId(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && send()} /><Button size="lg" className="w-full mt-3" disabled={busy} onClick={send}>{busy ? t(lang, 'sending') : (isSignup ? t(lang, 'create_my_account') : t(lang, 'send_code'))}</Button></>)
      : (<><Input className="mt-5 h-12 text-center font-mono text-[18px] tracking-[0.3em]" aria-label={t(lang, 'code_label')} inputMode="numeric" autoComplete="one-time-code" placeholder={t(lang, 'code_placeholder')} value={code} onChange={(e) => setCode(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && verify()} /><div className={S.hint}>{t(lang, 'junk_note')}</div><Button size="lg" className="w-full mt-3" disabled={busy} onClick={verify}>{busy ? t(lang, 'verifying') : (isSignup ? t(lang, 'verify_continue') : t(lang, 'verify_signin'))}</Button><Button variant="link" className="mt-2 px-0 h-auto" onClick={() => { setStep('id'); setCode(''); setMsg(''); }}>{t(lang, 'use_diff')}</Button></>)}
    {msg && <div className={S.err}>{msg}</div>}
  </Card></AuthShell>);
}
function Authed({ token, lang, strip, theme, onSwapTheme, onSetLang, onSignOut, onServedLocale }) {
  const [k, setK] = useState(null); const [err, setErr] = useState('');
  // A 401 IS A QUESTION BEFORE IT IS A VERDICT. The stored access token can be an hour old — the
  // page may have been restored from localStorage long after it was minted — and the refresh token
  // beside it is still good. Ask for a new session ONCE before telling somebody their session has
  // expired; the auth listener in CustomerPortal picks the new token up from there. If the refresh
  // also fails, the session really is over and the message is true.
  const load = (retried) => {
    setErr('');
    call('kyc', { action: 'state' }, token).then(async (j) => {
      if (j && j.error === 'unauthorized') {
        if (retried) { setErr('unauth'); return; }
        try {
          const rt = localStorage.getItem('qd-cust-refresh') || '';
          const { data } = await SB.auth.refreshSession(rt ? { refresh_token: rt } : undefined);
          if (data && data.session && data.session.access_token) return; // the listener re-renders with the new token
        } catch (_e) {}
        setErr('unauth');
        return;
      }
      setK(j || {});
    }).catch(() => setErr('net'));
  };
  // DO NOT ASK AN AUTHENTICATED ENDPOINT WHO WE ARE BEFORE WE HAVE A TOKEN. This ran on the first
  // render, when `token` is still '' because it is read from localStorage and from
  // SB.auth.getSession() inside an effect that has not resolved yet. Measured on a signed-in
  // customer: two 401s against /kyc in the console on every load, before the real call succeeded.
  // Wrong in three ways - it spends a round trip per mount, it puts a red error in the console of
  // a working page so a real one is easy to miss, and it burns the one refresh attempt the
  // `retried` flag exists to protect. The effect re-runs when the token arrives, so waiting is free.
  // Wait for a token, and for a token that has not already expired. SB.auth refreshes on its own
  // and the auth listener re-renders with the new one, so this costs nothing but the 401.
  useEffect(() => { if (tokenAlive(token)) { warmDashboard(token, lang); load(); } }, [token]);
  if (err === 'unauth') return <>{strip}<div className={S.center}><Card className="w-full max-w-[400px] p-5"><div className={S.sub}>{t(lang, 'session_expired')}</div><Button className="w-full mt-3" onClick={onSignOut}>{t(lang, 'tab_signin')}</Button></Card></div></>;
  if (err) return <>{strip}<div className={S.center}><Card className="w-full max-w-[400px] p-5"><div className={S.sub}>{t(lang, 'load_failed')}</div>{/* () => load(), not load: a click handler passes the MouseEvent as the first argument, which
        would arrive as `retried` and skip the one refresh attempt this retry exists to make. */}
    <Button className="w-full mt-3" onClick={() => load()}>{t(lang, 'retry')}</Button></Card></div></>;
  if (!k) return <>{strip}<div className={S.center}>{t(lang, 'loading')}</div></>;
  const complete = k.full_name && k.dob && k.phone_verified && k.email_verified && k.terms_signed;
  if (!complete) return <>{strip}<main><ProfileGate token={token} lang={lang} theme={theme} onDone={() => load()} /></main></>;
  return <Dashboard token={token} lang={lang} theme={theme} onSwapTheme={onSwapTheme} onSetLang={onSetLang} onSignOut={onSignOut} onServedLocale={onServedLocale} />;
}
// Under 18 on today's UTC date, from the YYYY-MM-DD a date input produces. Mirrors
// supabase/functions/_shared/account_rule.ts, which is the authority; this only shows the message early.
function isUnder18(d) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(d || '')); if (!m) return false;
  const t = new Date(); let a = t.getUTCFullYear() - +m[1]; const mo = t.getUTCMonth() + 1, dd = t.getUTCDate();
  if (mo < +m[2] || (mo === +m[2] && dd < +m[3])) a--;
  return a >= 0 && a < 18;
}
function ProfileGate({ token, lang, theme, onDone }) {
  const [st, setSt] = useState(null);
  const [full_name, setFullName] = useState(''); const [phone, setPhone] = useState(''); const [dob, setDob] = useState('');
  const [emCode, setEmCode] = useState(''); const [smsCode, setSmsCode] = useState(''); const [sentSms, setSentSms] = useState(false); const [sentEmail, setSentEmail] = useState(false);
  const [terms, setTerms] = useState(false); const [busy, setBusy] = useState(''); const [msg, setMsg] = useState('');
  const load = () => call('kyc', { action: 'state' }, token).then((j) => { setSt(j); setFullName((x) => x || j.full_name || ''); setPhone((x) => x || j.phone || ''); setDob((x) => x || j.dob || ''); }).catch(() => setMsg(t(lang, 'load_failed')));
  useEffect(() => { drop(); load(); }, []);
  if (!st) return <div className={S.center}>{t(lang, 'loading')}</div>;
  const saveProfile = async () => { if (!dob) { setMsg(t(lang, 'err_dob_required')); return; } if (isUnder18(dob)) { setMsg(t(lang, 'err_under_18')); return; } setBusy('save'); setMsg(''); const j = await call('kyc', { action: 'save_customer', full_name, phone, dob }, token); setBusy(''); if (j && j.ok) load(); else setMsg(errText(j, lang, 'load_failed')); };
  // sentSms carries the CHANNEL, not a boolean: kyc falls back to a voice call when the number is a
  // landline, and telling someone to check their junk folder for a code that is being read down the
  // phone is the wrong instruction.
  const sendSms = async () => { if (!phone) { setMsg(t(lang, 'enter_mobile_first')); return; } setBusy('sms'); setMsg(''); const j = await call('kyc', { action: 'send_sms', phone }, token); setBusy(''); if (j && j.ok) setSentSms(j.channel || 'sms'); else setMsg(errText(j, lang, 'err_code_send')); };
  const verifySms = async () => { setBusy('vsms'); setMsg(''); const j = await call('kyc', { action: 'verify_sms', phone, code: smsCode }, token); setBusy(''); if (j && j.ok) load(); else setMsg(errText(j, lang, 'err_incorrect')); };
  const sendEmailCode = async () => { setBusy('em'); setMsg(''); const j = await call('kyc', { action: 'send_email' }, token); setBusy(''); if (j && j.ok) setSentEmail(true); else setMsg(errText(j, lang, 'err_code_send')); };
  const verifyEmail = async () => { setBusy('vem'); setMsg(''); const j = await call('kyc', { action: 'verify_email', code: emCode }, token); setBusy(''); if (j && j.ok) load(); else setMsg(errText(j, lang, 'err_incorrect')); };
  const acceptTerms = async () => { if (!terms) { setMsg(t(lang, 'must_accept')); return; } setBusy('terms'); setMsg(''); const j = await call('kyc', { action: 'accept_terms' }, token); setBusy(''); if (j && j.ok) { onDone(); } else setMsg(errText(j, lang, 'load_failed')); };
  // DOB IS REQUIRED AGAIN (founder's account rule, 14 Sep 2026: name, date of birth with under-18
  // rejected, OTP-verified mobile/email, Terms). The 6 Sep change made it optional because a customer
  // without one was silently stuck; the fix for silence is a message, not dropping the field. kyc now
  // answers dob_required / under_18 / dob_invalid in words (errText), the under-18 line shows the moment
  // the date is entered, and `complete`, kyc accept_terms and create_inquiry all require it.
  const profileDone = st.full_name && st.phone && st.dob;
  return (<AuthShell lang={lang}><Card className="w-full p-6 sm:p-7">
    <h1 className="font-head text-[20px] font-extrabold tracking-tight text-foreground">{t(lang, 'gate_title')}</h1>
    <div className={cn(S.sub, 'mt-1.5')}>{t(lang, 'gate_sub')}</div>
    <Input className="mt-3" aria-label={t(lang, 'full_name')} autoComplete="name" placeholder={t(lang, 'full_name')} value={full_name} onChange={(e) => setFullName(e.target.value)} />
    <Input className="mt-3" aria-label={t(lang, 'acct_phone')} type="tel" dir="ltr" inputMode="tel" autoComplete="tel" placeholder={t(lang, 'mobile_ph')} value={phone} onChange={(e) => setPhone(e.target.value)} />
    <label htmlFor="qd-dob" className={cn(S.sub, 'mt-3 mb-1 block')}>{t(lang, 'dob_label')}</label>
    {/* The native date picker follows the customer's chosen theme; it was pinned dark (audit 14 Sep). */}
    <Input id="qd-dob" type="date" className="mt-0" style={{ colorScheme: theme === 'light' ? 'light' : 'dark' }} value={dob} required aria-invalid={isUnder18(dob) || undefined} onChange={(e) => setDob(e.target.value)} />
    {isUnder18(dob) && <div className={S.err} role="alert">{t(lang, 'err_under_18')}</div>}
    {/* Always available, not only while the profile is incomplete: the number typed at signup is the
        one the code is sent to, and once all three fields were filled the only way to correct a wrong
        number was to verify it first - which is impossible if it is the wrong number. */}
    <Button className="w-full mt-3" disabled={busy === 'save'} onClick={saveProfile}>{busy === 'save' ? t(lang, 'saving') : t(lang, 'save_details')}</Button>
    {profileDone && <>
      <div className={cn(S.h2, 'mt-4')}>{t(lang, 'verify_mobile')} {st.phone_verified ? <span className="text-primary text-[12px] font-bold ml-1.5">{t(lang, 'verified')}</span> : null}</div>
      {!st.phone_verified && (!sentSms ? <Button size="sm" className="mt-3" disabled={busy === 'sms'} onClick={sendSms}>{busy === 'sms' ? t(lang, 'sending') : t(lang, 'send_sms')}</Button>
        : <><div className={S.hint}>{t(lang, sentSms === 'call' ? 'call_note' : 'junk_note')}</div><div className={S.frow}><Input aria-label={t(lang, 'code_label')} inputMode="numeric" autoComplete="one-time-code" placeholder={t(lang, 'code_placeholder')} value={smsCode} onChange={(e) => setSmsCode(e.target.value)} /><Button size="sm" disabled={busy === 'vsms'} onClick={verifySms}>{t(lang, 'verify')}</Button></div><Button variant="link" className="mt-1 px-0 h-auto" onClick={() => { setSentSms(false); setSmsCode(''); }}>{t(lang, 'use_diff_number')}</Button></>)}
      <div className={cn(S.h2, 'mt-4')}>{t(lang, 'verify_email_h')} {st.email_verified ? <span className="text-primary text-[12px] font-bold ml-1.5">{t(lang, 'verified')}</span> : null}</div>
      {!st.email_verified && (!sentEmail ? <Button size="sm" className="mt-3" disabled={busy === 'em'} onClick={sendEmailCode}>{busy === 'em' ? t(lang, 'sending') : t(lang, 'send_email_code')}</Button>
        : <><div className={S.hint}>{t(lang, 'junk_note')}</div><div className={S.frow}><Input aria-label={t(lang, 'code_label')} inputMode="numeric" placeholder={t(lang, 'code_placeholder')} value={emCode} onChange={(e) => setEmCode(e.target.value)} /><Button size="sm" disabled={busy === 'vem'} onClick={verifyEmail}>{t(lang, 'verify')}</Button></div></>)}
      {st.phone_verified && st.email_verified && <>
        <label className="flex gap-2 items-center mt-4 text-[13px] text-muted-foreground"><input type="checkbox" checked={terms} onChange={(e) => setTerms(e.target.checked)} /> {t(lang, 'accept_pre')}<a href="/terms" target="_blank" rel="noopener" className="text-primary font-semibold">{t(lang, 'terms_link')}</a>{t(lang, 'accept_post')}</label>
        <Button className="w-full mt-3" disabled={busy === 'terms'} onClick={acceptTerms}>{busy === 'terms' ? t(lang, 'finishing') : t(lang, 'finish_continue')}</Button>
      </>}
    </>}
    {msg && <div className={S.err}>{msg}</div>}
  </Card></AuthShell>);
}
function Dashboard({ token, lang, theme, onSwapTheme, onSetLang, onSignOut, onServedLocale }) {
  const [ov, setOv] = useState(null); const [data, setData] = useState(null); const [err, setErr] = useState(''); const [note, setNote] = useState(''); const [showNew, setShowNew] = useState(false);
  // WHY THIS IS NO LONGER A `view`. Messages and Projects were whole-surface early returns: opening
  // either REPLACED the dashboard, which is the full-page navigation §21 asks the portal not to
  // have — and it also stranded the intake assistant, because a branch that returns before the
  // assistant's mount can never render it. Every module now opens in a window OVER the dashboard,
  // so the KPIs, the alerts and the assistant stay mounted underneath and no module needs a
  // "back to requests" button to undo a navigation that never happened.
  const [view, setView] = useState('');
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
  const loadInq = (first) => get(first, 'inq', 'customer_api', { action: 'my_inquiries' }).then((j) => {
    setData(j);
    if (j && j.locale && onServedLocale) onServedLocale(j.locale);
  });
  const loadOv = (first) => get(first, 'ov', 'customer_portal', { action: 'overview', lang }).then((j) => { if (j && j.ok) setOv(j); else setErr(j ? errText(j, lang, 'load_failed') : ''); });
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
  // OPEN THIS REQUEST. Projects, the Project room, the supply-chain map, Messages, Approvals, Orders,
  // the alerts and "Help me decide" all hand the portal an inquiry id and asked it to open that
  // request — and every one of them was wired to onClose, which threw the id away and landed the
  // customer on the Overview. This is the one target they all call: My requests, filters cleared so
  // the row cannot be hidden, and that request's card opened and scrolled to (InquiryCard).
  const [focusInq, setFocusInq] = useState('');
  const [focusProject, setFocusProject] = useState('');
  const [pickFile, setPickFile] = useState(false);
  const openRfq = (id) => { setFocusInq(id ? String(id) : ''); setBallFilter('all'); setQtext(''); setView('requests'); };
  const openProject = (id) => { setFocusProject(id ? String(id) : ''); setView('projects'); };
  const openNew = (withFile) => { setPickFile(!!withFile); setShowNew(true); setView('home'); };
  // Where an alert goes is decided by what it is about: a request it names, the approvals it counts,
  // the need it forecasts. Kinds without a subject of their own (price moves, lead times) are about
  // the requests list as a whole.
  const onAlert = (a) => {
    if (a && a.inquiry_id) return openRfq(a.inquiry_id);
    if (a && a.kind === 'approval_due') return setView('approvals');
    if (a && a.kind === 'forecast_need') return openNew(false);
    return openRfq('');
  };
  useEffect(() => {
    loadOv(true);
    loadInq(true);
    loadPd(true);
    loadUnread(true);
    const qs = new URLSearchParams(location.search);
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
          const extra = [d.category, d.emirate].filter(Boolean).join(', ');
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
  const booting = !ov && !data;
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
    approvals: () => setView('approvals'),
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
        <Button size="sm" className="shrink-0 gap-1.5" onClick={() => setShowNew((v) => !v)}>
          {/* The label flips to "Close" but the icon did not, so the open intake carried a button
              reading "+ Close" - a plus sign on the control that dismisses the thing. */}
          {showNew ? <X className="h-4 w-4" aria-hidden /> : <Plus className="h-4 w-4" aria-hidden />}
          {showNew ? t(lang, 'close') : t(lang, 'new_request')}
        </Button>
      </div>
    </section>

    {note && <div className={S.note}>{note}</div>}
    {receipt && <ReceiptNote receipt={receipt} inqs={inqs} lang={lang} onClose={() => setReceipt(null)} />}
    {/* llm_available comes from customer_portal's overview (llm_route_health): it hides the mic
        while transcription is held. Drawings and BOQs are read server-side and are never gated. */}
    {/* An incomplete account is a place to go, not a dead end: create_inquiry answers
        account_incomplete (with `missing`), and the Account page lists exactly what is missing. */}
    {showNew && <div className="mb-5"><NewRequest token={token} lang={lang} pickFile={pickFile}
      call={async (p, b, tk) => { const r = await call(p, b, tk); if (r && r.error === 'account_incomplete') setView('account'); return r; }} llmAvailable={ov ? ov.llm_available : null} initialText={draft}
      onDone={() => { setShowNew(false); setPickFile(false); setDraft(''); refresh(); setNote(t(lang, 'request_sent')); }} onCancel={() => { setShowNew(false); setPickFile(false); setDraft(''); }} /></div>}

    {/* The severity marker was a 4px border-l — which is both a well-worn generated-UI tell and,
        more to the point here, LEFT: in Arabic it lands on the wrong edge of the card. A tinted
        glyph carries the same three levels, on the correct side, in both directions. */}
    {/* Each alert opens what it is about (onAlert): "2 quotes to review on HVAC" was a box you could
        read and not act on, and the request it named was somewhere further down the page. */}
    {ov && !!(ov.alerts || []).length && <div className="mb-5 flex flex-col gap-2">{ov.alerts.map((a, i) => (
      <button key={i} type="button" onClick={() => onAlert(a)} className="flex w-full items-start gap-3 rounded-xl border border-border bg-card px-4 py-3 text-start transition-colors hover:border-primary/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
        <span className={cn('mt-0.5 grid h-7 w-7 shrink-0 place-items-center rounded-lg',
          a.severity === 'high' ? 'bg-danger/15 text-danger' : a.severity === 'medium' ? 'bg-warn/15 text-warn-fg' : 'bg-primary/15 text-primary')}>
          <BellRing className="h-3.5 w-3.5" aria-hidden />
        </span>
        <span className="min-w-0 flex-1"><b className="block text-[13.5px] text-foreground">{a.title}</b>
          <span className="block text-xs leading-relaxed text-muted-foreground">{a.detail}</span></span>
        <ArrowRight className={cn('mt-1 h-3.5 w-3.5 shrink-0 text-muted-foreground', rtl && 'rotate-180')} aria-hidden />
      </button>))}</div>}

    {!onlyRequests && (ov ? (
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
        categories they actually buy, their approval chain, and how much of that profile we hold.
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
              className="cursor-pointer p-3.5 transition-colors duration-200 hover:border-primary/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
              <div className="flex justify-between items-center gap-2"><b className="text-[13.5px] text-foreground">{p.name}</b><span className={S.sub}>{projectStatusLabel(lang, p.status)}</span></div>
              <div className={cn(S.sub, 'mt-1')}>{openN + ' / ' + totalN + ' ' + t(lang, 'rfqs_open_of')}{' · '}{(Number(p.supplier_count) || 0) + ' ' + t(lang, 'suppliers_engaged')}</div>
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
              className={cn('inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-[12.5px] font-semibold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
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
    {booting ? (
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
        <WhatHappensNext lang={lang} />
      </Card>
    ) : (filtered && !shown.length) ? <Card className="mt-3 p-5"><div className={S.sub}>{t(lang, needle ? 'no_search_match' : 'ball_none_you')}</div></Card>
      : filtered ? <div className={cn(S.list, 'mt-3')}>{shown.map((i) => <InquiryCard key={i.id} inq={i} token={token} lang={lang} onChange={refresh} terms={data && data.guarantee_terms} focusQuote={focusQuote} focusInq={focusInq} />)}</div>
      // The overview shows the five most recent and links to the full list; My requests shows all.
      // Mapped then sliced, rather than sliced then mapped, so this stays the dashboard's list over
      // `inqs` — the thing the entry-not-login-dashboard leg reads to tell a workspace carrying live
      // work from a page of figures and links. Ten rows at most; the extra map costs nothing.
      : <div className={cn(S.list, 'mt-3')}>{inqs.map((i) => <InquiryCard key={i.id} inq={i} token={token} lang={lang} onChange={refresh} terms={data && data.guarantee_terms} focusQuote={focusQuote} focusInq={focusInq} />).slice(0, onlyRequests ? undefined : 5)}</div>}
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
    out.push(ar ? `أي عرض من العروض الـ${n} على طلب ${label(i)} ينبغي أن أختار؟`
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
function WhatHappensNext({ lang }) {
  const steps = ['next_1', 'next_2', 'next_3', 'next_4'];
  return (
    <div className="mx-auto mt-6 max-w-[62ch] border-t border-border pt-5 text-start">
      <div className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">{t(lang, 'next_h')}</div>
      <ol className="mt-2.5 space-y-2.5">
        {steps.map((k, n) => (
          <li key={k} className="flex gap-3">
            <span className="mt-0.5 grid h-5 w-5 shrink-0 place-items-center rounded-full bg-primary/12 text-[11px] font-bold text-primary tabular-nums">{n + 1}</span>
            <span className="min-w-0 text-[13px] leading-relaxed text-muted-foreground">{t(lang, k)}</span>
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
            className={cn('group flex items-center gap-3 rounded-xl border border-border bg-card/60 px-3.5 py-3 text-start transition-[border-color,transform] duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
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
function InquiryCard({ inq, token, onChange, lang, terms, focusQuote, focusInq }) {
  if (inq.is_combined && Array.isArray(inq.children)) { return (<Card id={'inq-' + inq.id} className="p-4 mb-3.5 border-primary/30"><div className="flex items-center gap-2 flex-wrap mb-1"><span className="text-[11px] font-semibold px-2 py-0.5 rounded-full bg-primary/10 text-primary">{lang === 'ar' ? 'مشروع متعدد التخصصات' : 'Combined project'}</span><span className={S.sub}>{lang === 'ar' ? (inq.children.length + ' طلب منفصل لموردين متخصصين') : (inq.children.length + ' separate requests to specialist suppliers')}</span></div>{inq.summary ? <div className={cn(S.sub, 'mb-2')}>{inq.summary}</div> : null}<div className="space-y-2.5">{inq.children.map((c) => <InquiryCard key={c.id} inq={c} token={token} onChange={onChange} lang={lang} terms={terms} focusQuote={focusQuote} focusInq={focusInq} />)}</div></Card>); }
  // Opened by the quote a payment was for (focusQuote) or by any control that asked to open THIS
  // request by id (focusInq — Dashboard's openRfq). The id is the same inquiries.id every caller holds.
  const hasFocus = (!!focusQuote && (inq.quotes || []).some((q) => q.id === focusQuote)) || (!!focusInq && String(inq.id) === String(focusInq));
  const [open, setOpen] = useState(hasFocus);
  const cardRef = useRef(null);
  useEffect(() => {
    if (!hasFocus) return;
    setOpen(true);
    try { cardRef.current && cardRef.current.scrollIntoView({ behavior: 'smooth', block: 'start' }); } catch (_e) {}
  }, [hasFocus]);
  const [canceling, setCanceling] = useState(false);
  const [editing, setEditing] = useState(false);
  const [eSummary, setESummary] = useState(inq.summary || '');
  const [eBudget, setEBudget] = useState(inq.budget || '');
  const [eEmirate, setEEmirate] = useState(inq.emirate || '');
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState('');
  const [dialog, ask] = useConfirm(lang);
  const quotes = (inq.quotes || []).slice().sort((a, b) => (a.price || 0) - (b.price || 0));
  const concluded = ['completed', 'closed', 'cancelled'].includes(String(inq.status));
  const anyRevealed = quotes.some((qq) => qq.revealed);
  const vmap = (() => { const m = {}; if (!quotes.length) return m; const ps = quotes.map((q) => Number(q.price) || 0).filter((p) => p > 0); const minP = ps.length ? Math.min(...ps) : 0, maxP = ps.length ? Math.max(...ps) : 0; for (const q of quotes) { const p = Number(q.price) || 0; const priceScore = (!p || maxP === minP) ? 70 : Math.round(100 - ((p - minP) / (maxP - minP)) * 55); const ratingScore = ratingScoreOf(q.rating); const compScore = Math.min(100, 50 + (q.scope ? 20 : 0) + (q.warranty ? 10 : 0) + (q.lead_time ? 10 : 0) + (q.verified ? 10 : 0)); m[q.id] = ratingScore == null ? Math.round((priceScore * 0.5 + compScore * 0.2) / 0.7) : Math.round(priceScore * 0.5 + ratingScore * 0.3 + compScore * 0.2); } return m; })();
  const bestId = quotes.length ? quotes.slice().sort((a, b) => (vmap[b.id] || 0) - (vmap[a.id] || 0))[0].id : null;
  const stepIdx = rfqStageIdx(inq, quotes);
  // window.confirm was an English-only browser box (audit 14 Sep 2026); useConfirm is in-page and bilingual.
  const doCancel = async (e) => { e.stopPropagation(); if (canceling) return; if (!(await ask(t(lang, 'rc_cancel_confirm'), { title: t(lang, 'rc_cancel'), confirm: t(lang, 'rc_cancel'), danger: true }))) return; setCanceling(true); setErr(''); try { const j = await call('customer_api', { action: 'cancel_inquiry', inquiry_id: inq.id }, token); if (j && j.ok) { onChange(); } else { setErr(errText(j, lang, 'rc_cancel_fail')); setCanceling(false); } } catch (_e) { setErr(t(lang, 'rc_cancel_fail')); setCanceling(false); } };
  const saveEdit = async () => { setSaving(true); setErr(''); try { const j = await call('customer_api', { action: 'edit_inquiry', inquiry_id: inq.id, patch: { summary: eSummary, budget: eBudget || null, emirate: eEmirate || null } }, token); if (j && j.ok) { setEditing(false); onChange(); } else { setErr(errText(j, lang, 'rc_save_fail')); } } catch (_e) { setErr(t(lang, 'rc_save_fail')); } setSaving(false); };
  return (<Card ref={cardRef} id={'inq-' + inq.id} className={cn('scroll-mt-20 p-4 shadow-e1 transition-[border-color,box-shadow] duration-300 hover:border-primary/30 hover:shadow-e2 sm:p-5', open && 'border-primary/25 shadow-e2')}>{dialog}
    {/* A11Y (5 Aug 2026): role+tabIndex+onKeyDown rather than a <button>, because this wraps <div>
        children and <div> inside <button> is an invalid content model. */}
    <div className="flex justify-between items-center gap-2.5 cursor-pointer rounded-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" onClick={() => setOpen(!open)}
      role="button" tabIndex={0} aria-expanded={open}
      onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); setOpen(!open); } }}>
      <div className="min-w-0">
        <div className="flex flex-wrap items-center gap-2">
          <StatusPill state={stateOf(inq, quotes)} t={(k) => t(lang, k)} />
          <b className="font-head text-[15px] font-semibold tracking-snug">{inq.category ? categoryLabel(inq.category, lang) : t(lang, 'rc_request')}</b>
          {inq.rfq_no ? <span className="tabular rounded-chip border border-border bg-secondary/40 px-1.5 py-0.5 font-mono text-label text-muted-foreground">{inq.rfq_no}</span> : null}
        </div>
        {/* Emirate and the quote count stay separate spans: the Row #4 blueprint asserts each. */}
        <div className={cn(S.sub, 'mt-1 flex flex-wrap items-center gap-x-1.5')}>
          {inq.emirate ? <span>{emirateName(inq.emirate, lang)}</span> : null}
          {inq.emirate ? <span aria-hidden className="text-muted-foreground/40">·</span> : null}
          <span>{quotes.length} {t(lang, quotes.length === 1 ? 'rc_quote_one' : 'rc_quote_many')}</span>
          {(inq.boq && inq.boq.boq) ? <><span aria-hidden className="text-muted-foreground/40">·</span><span>{inq.boq.boq.length} {t(lang, 'rc_lines')}</span></> : null}
          {inq.editable ? <><span aria-hidden className="text-muted-foreground/40">·</span><span>{tf(lang, 'rc_editable', { m: inq.edit_minutes_left })}</span></> : null}
        </div>
      </div>
      <div className="flex shrink-0 items-center gap-1 text-primary font-semibold text-[13px]">
        <span className="hidden sm:inline">{open ? t(lang, 'rc_hide') : t(lang, 'rc_open')}</span>
        <ChevronDown className={cn('h-4 w-4 transition-transform duration-300', open && 'rotate-180')} aria-hidden />
      </div>
    </div>
    {inq.summary && !editing && <div className={cn(S.sub, 'mt-1.5')}>{inq.summary}</div>}
    {editing && <div className="mt-2">
      <label className="sr-only" htmlFor={'qd-edit-' + inq.id}>{t(lang, 'rc_describe')}</label>
      <textarea id={'qd-edit-' + inq.id} className={S.area} rows={3} value={eSummary} onChange={(e) => setESummary(e.target.value)} placeholder={t(lang, 'rc_describe')} />
      <div className={S.frow}>
        {/* Theme tokens, not the hard-coded navy this select carried into the light theme. */}
        <select className={cn(S.field, 'bg-background')} aria-label={t(lang, 'rc_emirate_opt')} value={eEmirate} onChange={(e) => setEEmirate(e.target.value)}><option value="">{t(lang, 'rc_emirate_opt')}</option>{EMIRATES.map((em) => <option key={em} value={em}>{emirateName(em, lang)}</option>)}</select>
        <Input aria-label={t(lang, 'rc_budget_opt')} placeholder={t(lang, 'rc_budget_opt')} value={eBudget} onChange={(e) => setEBudget(e.target.value)} />
      </div>
      <div className="flex gap-2.5 flex-wrap items-center mt-2.5">
        <Button disabled={saving} onClick={(e) => { e.stopPropagation(); saveEdit(); }}>{saving ? t(lang, 'rc_saving') : t(lang, 'rc_save')}</Button>
        <Button variant="link" className="px-0 h-auto" onClick={(e) => { e.stopPropagation(); setEditing(false); setErr(''); }}>{t(lang, 'rc_cancel_edit')}</Button>
      </div>
    </div>}
    {!concluded && !anyRevealed && !editing && <div className="flex gap-2.5 flex-wrap items-center mt-2">
      {inq.editable && <Button variant="link" className="px-0 h-auto" onClick={(e) => { e.stopPropagation(); setESummary(inq.summary || ''); setEBudget(inq.budget || ''); setEEmirate(inq.emirate || ''); setEditing(true); }}>{t(lang, 'rc_edit')}</Button>}
      <Button variant="link" className="px-0 h-auto text-danger" disabled={canceling} onClick={doCancel}>{canceling ? t(lang, 'rc_cancelling') : t(lang, 'rc_cancel')}</Button>
    </div>}
    {err && <div className={S.err} role="alert">{err}</div>}
    <Journey idx={stepIdx} lang={lang} matched={inq.matched_suppliers} />
    {open && <div className="mt-3 border-t border-border pt-3 flex flex-col gap-3">
      <Timeline inq={inq} quotes={quotes} anyRevealed={anyRevealed} lang={lang} />
      <QuoteSpread quotes={quotes} lang={lang} />
      {/* Questions and additions. The customer's follow-up reaches the RFQ (customer_api rfq_note)
          and suppliers' pre-reveal questions can be answered (messages_api clarify_*). Replaces
          RfqAssistant, whose inquiry_intake call ignored inquiry_id (audit 14 Sep 2026, BROKEN). */}
      <Clarifications inq={inq} token={token} lang={lang} call={call} />
      <DetailFacts inq={inq} lang={lang} />
      {quotes.length >= 2 && <Comparison inqId={inq.id} token={token} lang={lang} />}
      {/* reached===0 is its own outcome here, never encouragement: matched_suppliers says which. */}
      <DiscoveryReachPanel inquiry={inq} lang={lang === 'ar' ? 'ar' : 'en'} />
      {quotes.length > 0
        // THE LEVELLED FRAME. Every quote the request received — not a shortlist — side by side on the
        // same columns, then each one in full with its own reveal. Identities stay sealed until paid.
        ? <section className="overflow-hidden rounded-card border border-border bg-card shadow-e1" aria-label={tf(lang, 'rc_quotes_received', { n: quotes.length })}>
            <div className="flex h-10 items-center gap-2.5 border-b border-border bg-secondary/40 px-3.5">
              <span className="hidden gap-1.5 sm:flex" aria-hidden><i className="h-2 w-2 rounded-full bg-primary/25" /><i className="h-2 w-2 rounded-full bg-primary/25" /><i className="h-2 w-2 rounded-full bg-primary/25" /></span>
              <div className="min-w-0 truncate font-mono text-label text-foreground">{tf(lang, 'rc_quotes_received', { n: quotes.length })}</div>
              <Badge variant={anyRevealed ? 'revealed' : 'sealed'} dot className={cn('ms-auto shrink-0', anyRevealed && '!text-accent')}>{t(lang, anyRevealed ? 'lv_open' : 'lv_sealed')}</Badge>
            </div>
            <LevelledRows quotes={quotes} vmap={vmap} bestId={bestId} lang={lang} />
            <div className="flex flex-col gap-2.5 border-t border-border p-2.5 sm:p-3">{quotes.map((q) => <QuoteCard key={q.id} q={q} token={token} lang={lang} concluded={concluded} onChange={onChange} vscore={vmap[q.id]} best={q.id === bestId} hired={inq.hired_supplier_id} terms={terms} focus={q.id === focusQuote} />)}</div>
          </section>
        : null}
    </div>}
  </Card>);
}

// The comparison rows: one qd-row per quote over the same five columns, the best-value row lit teal,
// a term the supplier did not state flagged in warn. Real fields only — nothing here is sample data.
function LevelledRows({ quotes, vmap, bestId, lang }) {
  const cols = 'minmax(128px,1.3fr) minmax(96px,1fr) repeat(2,minmax(88px,1fr)) minmax(64px,.6fr)';
  const miss = <span className="text-warn-fg">⚠ {t(lang, 'lv_missing')}</span>;
  return (
    <div className="overflow-x-auto">
      <div className="min-w-[540px]" role="table" aria-label={tf(lang, 'rc_quotes_received', { n: quotes.length })}>
        <div className="qd-row bg-secondary/25 font-mono text-label uppercase tracking-caps text-muted-foreground" style={{ gridTemplateColumns: cols }} role="row">
          <span role="columnheader">{t(lang, 'lv_supplier')}</span><span role="columnheader" className="text-end">{t(lang, 'lv_price')}</span>
          <span role="columnheader">{t(lang, 'q_lead')}</span><span role="columnheader">{t(lang, 'q_warranty')}</span><span role="columnheader" className="text-end">{t(lang, 'q_value')}</span>
        </div>
        <div className="qd-stagger reveal-stagger">
          {quotes.map((q) => {
            const best = q.id === bestId;
            return (
              <div key={q.id} className={cn('qd-row', best && 'qd-row-best')} style={{ gridTemplateColumns: cols }} role="row">
                <span role="cell" className="flex min-w-0 flex-col gap-1">
                  <span className="truncate font-medium text-foreground">{supLabel(q.label, lang)}</span>
                  {q.revealed
                    ? (q.supplier_name ? <Seal open className="qd-revealed !text-accent max-w-full truncate text-label">{q.supplier_name}</Seal> : null)
                    : <span aria-hidden className="leading-none"><Seal className="text-label">{'••••••••••'}</Seal></span>}
                </span>
                <span role="cell" className={cn('tabular text-end font-mono', best ? 'font-semibold text-primary' : 'text-foreground')}>{Number(q.price) > 0 ? aed(q.price) : miss}</span>
                <span role="cell" className="min-w-0 truncate text-muted-foreground">{q.lead_time || miss}</span>
                <span role="cell" className="min-w-0 truncate text-muted-foreground">{q.warranty ? durationLabel(q.warranty, lang) : miss}</span>
                <span role="cell" className={cn('tabular text-end font-mono', best ? 'text-primary' : 'text-muted-foreground')}>{vmap[q.id] != null ? vmap[q.id] : '—'}</span>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
// The revealed name arrives sealed and the bar slides off in gold — once, on the reveal itself.
function OpenSeal({ play, children }) {
  const [open, setOpen] = useState(!play);
  useEffect(() => { if (open) return; const id = setTimeout(() => setOpen(true), 80); return () => clearTimeout(id); }, []);
  return <Seal open={open} className="qd-revealed !text-accent max-w-full">{children}</Seal>;
}

function QuotePdfLink({ q, token, lang }) {
  const [busy, setBusy] = useState(false); const [msg, setMsg] = useState('');
  const open = async (e) => { e.stopPropagation(); setBusy(true); setMsg(''); const j = await call('customer_api', { action: 'quote_pdf', quote_id: q.id, lang }, token); setBusy(false); if (j && j.ok && j.url) { window.open(j.url, '_blank', 'noopener'); } else setMsg(errText(j, lang, 'q_pdf_fail')); };
  return (<><button className="text-primary font-semibold text-[12.5px]" disabled={busy} onClick={open}>{busy ? (lang === 'ar' ? 'جارٍ التحضير…' : 'Preparing…') : (lang === 'ar' ? '📄 عرض السعر (PDF)' : '📄 View quote (PDF)')}</button>{msg ? <span className={cn(S.sub, 'ml-2 text-danger')}>{msg}</span> : null}</>);
}
function Timeline({ inq, quotes, anyRevealed, lang }) {
  const steps = lang === 'ar' ? RFQ_STAGES.ar : RFQ_STAGES.en;
  const idx = rfqStageIdx(inq, quotes);
  const fmt = (d) => { try { return new Date(d).toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }); } catch (_e) { return ''; } };
  return (<div className="rounded-lg border border-border bg-secondary/20 p-3">
    {inq.created_at ? <div className={cn(S.sub, 'mb-2')}>{(lang === 'ar' ? 'أُنشئ في ' : 'Created ') + fmt(inq.created_at)}</div> : null}
    <div className="flex items-center gap-1.5 flex-wrap text-[11px]">{steps.map((sname, si) => (<span key={sname} className={cn('flex items-center gap-1', si <= idx ? 'text-primary font-semibold' : 'text-muted-foreground/60')}>{si > 0 ? <span className="text-muted-foreground/40">›</span> : null}<span className={cn('inline-block w-2 h-2 rounded-full', si <= idx ? 'bg-primary' : 'bg-muted-foreground/30')} />{sname}</span>))}</div>
  </div>);
}
function DetailFacts({ inq, lang }) {
  const rows = [];
  if (inq.budget) rows.push([lang === 'ar' ? 'الميزانية' : 'Budget', String(inq.budget)]);
  if (Array.isArray(inq.trades) && inq.trades.length) rows.push([lang === 'ar' ? 'التخصصات' : 'Trades', inq.trades.join(', ')]);
  if (inq.boq && inq.boq.boq && inq.boq.boq.length) rows.push([lang === 'ar' ? 'عدد البنود' : 'Line items', String(inq.boq.boq.length)]);
  const sp = inq.spec && typeof inq.spec === 'object' ? inq.spec : null;
  if (sp) for (const k of Object.keys(sp)) { const v = sp[k]; if (v && typeof v === 'string' && k !== 'plausibility' && k !== 'provenance') rows.push([k.replace(/_/g, ' '), v]); }
  // How confident the reader was about the BOQ it pulled off the customer's drawing. The customer
  // is the only person who can tell us it read the drawing wrong, and they were never shown it.
  const conf = Number(inq.boq_confidence);
  if (Number.isFinite(conf) && inq.boq && inq.boq.boq) rows.push([lang === 'ar' ? 'دقة قراءة الرسم' : 'Drawing read confidence', Math.round(conf <= 1 ? conf * 100 : conf) + '%']);
  // my_inquiries signs a URL to the customer's OWN uploaded drawing on every call. Nothing read it,
  // so the one person entitled to that file could not open it — only the suppliers could.
  const drawing = inq.drawing_file_url
    ? (<div className="mt-1.5"><a href={inq.drawing_file_url} target="_blank" rel="noopener" className="text-primary font-semibold text-[12.5px]">{lang === 'ar' ? '📐 افتح الرسم الذي رفعته' : '📐 Open the drawing you uploaded'}{inq.drawing_file_name ? ' (' + inq.drawing_file_name + ')' : ''}</a></div>)
    : null;
  if (!rows.length && !drawing) return null;
  return (<div className="rounded-lg border border-border bg-secondary/20 p-3"><div className={cn(S.sub, 'font-semibold mb-1.5 text-foreground')}>{lang === 'ar' ? 'تفاصيل الطلب' : 'Request details'}</div><div className="grid grid-cols-1 sm:grid-cols-2 gap-x-3 gap-y-1">{rows.slice(0, 14).map((r, i) => (<div key={i} className={S.sub}><span className="capitalize text-muted-foreground">{r[0]}: </span><span className="text-foreground">{r[1]}</span></div>))}</div>{drawing}</div>);
}
// A CODE IS NOT A SENTENCE. `note` is written by quote_compare FOR the customer ("not enough quotes
// to compare yet") and is rendered as-is. `error` is written for us — and quote_compare's own catch
// is `J({ error: String(e.message) }, 500)`, so an unhandled Postgres or Deno message would be
// rendered as the whole card. MEASURED 13 Aug 2026 on a real request screen: a card containing the
// single word `not_found`, between "Trades: hvac" and "Your request reached 9 suppliers".
const compareErrText = (code, lang) => {
  const c = String(code || '');
  if (c === 'ai_unavailable') return lang === 'ar'
    ? 'خدمة المقارنة غير متاحة مؤقتًا. عروضك محفوظة — يمكنك مقارنتها بنفسك أدناه والمحاولة لاحقًا.'
    : 'The comparison service is briefly unavailable. Your quotes are safe — you can still compare them yourself below, and this will fill in when it returns.';
  if (c === 'unauthorized') return lang === 'ar' ? 'انتهت جلستك. يُرجى تسجيل الدخول من جديد.' : 'Your session has expired. Please sign in again.';
  if (c === 'not_your_inquiry') return lang === 'ar' ? 'هذا الطلب ليس ضمن طلباتك.' : 'That request is not on your account.';
  return lang === 'ar'
    ? 'تعذّر إعداد تقرير المقارنة. عروضك لم تتأثر — يُرجى المحاولة مرة أخرى.'
    : 'We could not prepare the comparison report. Your quotes are unaffected — please try again.';
};
function Comparison({ inqId, token, lang }) {
  const reduce = useReducedMotion();
  const [a, setA] = useState(null); const [busy, setBusy] = useState(true); const [note, setNote] = useState(''); const [code, setCode] = useState('');
  // quote_compare answers degraded:true, with analysis.disclaimer, when no model answered — the
  // only path under the hold. The card was titled "Expert comparison report" regardless (audit
  // 14 Sep 2026), so a rules-only ranking now says it is one, in both languages.
  const [degraded, setDegraded] = useState(false);
  useEffect(() => { let on = true; setBusy(true); setCode(''); call('quote_compare', { inquiry_id: inqId, lang }, token).then((j) => { if (!on) return; setBusy(false); if (j && j.ok && j.analysis) { setA(j.analysis); setDegraded(!!j.degraded || !!j.analysis.disclaimer); } else if (j && j.note) setNote(j.note); else if (j && j.error) { setCode(String(j.error)); setNote(compareErrText(j.error, lang)); } else setNote(''); }).catch(() => { if (on) { setBusy(false); } }); return () => { on = false; }; }, [inqId, lang]);
  const arr = (x) => Array.isArray(x) ? x : [];
  if (busy) return (<div className="qd-panel p-3.5" aria-busy="true"><div className={cn(S.sub, 'text-primary')}>{t(lang, 'cmp_preparing')}</div><div className="mt-2 flex flex-col gap-1.5" aria-hidden><span className="redact redact-bar" style={{ width: '72%' }} /><span className="redact redact-bar" style={{ width: '48%' }} /><span className="redact redact-bar" style={{ width: '60%' }} /></div></div>);
  if (!a) return note ? (<div className="rounded-lg border border-border bg-secondary/20 p-3" title={code || undefined}><div className={S.sub}>{note}</div></div>) : null;
  return (<motion.div initial={reduce ? false : { opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: reduce ? 0 : 0.3 }} className="qd-panel p-3.5">
    <div className="mb-1 flex flex-wrap items-center gap-2">
      <div className={cn(S.sub, 'font-bold text-primary')}>{t(lang, degraded ? 'cmp_title_rules' : 'cmp_title') + (a.trade ? ' · ' + a.trade : '')}</div>
      {degraded ? <span className="rounded-full border border-warn/40 bg-warn/10 px-2 py-0.5 text-[10.5px] font-semibold text-warn-fg">{t(lang, 'cmp_badge_rules')}</span> : null}
    </div>
    {degraded && a.disclaimer ? <div className={cn(S.sub, 'mb-1.5')}>{a.disclaimer}</div> : null}
    {a.bottom_line ? <div className={cn(S.sub, 'text-foreground font-semibold mb-1.5')}>{a.bottom_line}</div> : null}
    {a.overview ? <div className={cn(S.sub, 'mb-2')}>{a.overview}</div> : null}
    {arr(a.top3).length ? <div className="mb-2"><div className={cn(S.sub, 'font-semibold text-foreground')}>{t(lang, 'cmp_top')}</div>{arr(a.top3).map((r, i) => (<div key={i} className={cn(S.sub, 'mt-0.5')}><span className="text-primary font-semibold">#{r.rank} {supLabel(r.label, lang)}</span> — {r.why}{r.tradeoff ? (' (' + t(lang, 'cmp_catch') + ': ' + r.tradeoff + ')') : ''}</div>))}</div> : null}
    {arr(a.quotes).map((q, i) => (<div key={i} className="mt-2 border-t border-border/60 pt-2"><div className={cn(S.sub, 'font-semibold text-foreground')}>{supLabel(q.label, lang)}{q.price != null ? (' — ' + aed(q.price)) : ''}</div>
      {/* §10 per-dimension scores, relative to the other shortlisted quotes; unstated scores 1. */}
      {(q.price_score != null || q.delivery_score != null || q.quality_score != null) ? (
        <div className="mt-1 flex flex-wrap gap-x-3 gap-y-0.5" title={q.score_reason || ''}>
          {[[t(lang, 'cmp_price'), q.price_score], [t(lang, 'cmp_delivery'), q.delivery_score], [t(lang, 'cmp_quality'), q.quality_score]]
            .filter(([, v]) => v != null)
            .map(([label, v]) => (
              <span key={String(label)} className={S.sub}>
                <span className="text-muted-foreground">{label}: </span>
                <span className="text-foreground" aria-label={v + ' ' + t(lang, 'cmp_of5')}>{'★'.repeat(Math.max(0, Math.min(5, Number(v) || 0)))}{'☆'.repeat(Math.max(0, 5 - Math.max(0, Math.min(5, Number(v) || 0))))}</span>
              </span>
            ))}
        </div>
      ) : null}
      {q.score_reason ? <div className={cn(S.sub, 'text-muted-foreground')}>{q.score_reason}</div> : null}
      {q.getting ? <div className={S.sub}>{q.getting}</div> : null}{arr(q.missing_from_request).length ? <div className={cn(S.sub, 'text-warn-fg')}>{t(lang, 'cmp_missing') + arr(q.missing_from_request).join('; ')}</div> : null}{arr(q.spec_deviation).length ? <div className={cn(S.sub, 'text-warn-fg')}>{t(lang, 'cmp_dev') + arr(q.spec_deviation).join('; ')}</div> : null}{arr(q.flags).length ? <div className={cn(S.sub, 'text-danger')}>{arr(q.flags).join('; ')}</div> : null}</div>))}
    {arr(a.watch_outs).length ? <div className={cn(S.sub, 'text-danger mt-2')}>{t(lang, 'cmp_watch') + arr(a.watch_outs).join(' · ')}</div> : null}
    {a.advice ? <div className={cn(S.sub, 'mt-2 text-foreground')}>{a.advice}</div> : null}
    {/* §10 EXPORT: customer_api compare_pdf, ownership-checked; the document goes to the meeting. */}
    <ExportComparison inqId={inqId} token={token} lang={lang} />
    <div className={cn(S.sub, 'mt-2 text-muted-foreground/70 text-[11px]')}>{t(lang, 'cmp_guidance')}</div>
  </motion.div>);
}
// The download owns a failure the report must survive: a PDF that cannot be built must not blank
// the analysis the customer is reading.
function ExportComparison({ inqId, token, lang }) {
  const [busy, setBusy] = useState(false); const [err, setErr] = useState('');
  const go = async () => {
    setBusy(true); setErr('');
    try {
      const j = await call('customer_api', { action: 'compare_pdf', inquiry_id: inqId, lang }, token);
      const url = j && (j.url || j.pdf_url || j.file_url);
      if (url) window.open(url, '_blank', 'noopener');
      else setErr(errText(j, lang, 'cmp_save_fail'));
    } catch (_e) {
      setErr(t(lang, 'cmp_save_fail'));
    } finally { setBusy(false); }
  };
  // W10: the same side-by-side rows as the PDF, as a spreadsheet. The server sends the text with a
  // UTF-8 BOM so Excel opens Arabic headers correctly; the browser only wraps it in a file.
  const csv = async () => {
    setBusy(true); setErr('');
    try {
      const j = await call('customer_api', { action: 'compare_csv', inquiry_id: inqId, lang }, token);
      if (j && j.ok && typeof j.csv === 'string') {
        const a = document.createElement('a');
        // window.URL: this module imports SUPA_URL under the name URL.
        a.href = window.URL.createObjectURL(new Blob([j.csv], { type: 'text/csv;charset=utf-8' }));
        a.download = j.filename || 'comparison.csv'; a.click();
        setTimeout(() => window.URL.revokeObjectURL(a.href), 4000);
      } else setErr(errText(j, lang, 'cmp_csv_fail'));
    } catch (_e) {
      setErr(t(lang, 'cmp_csv_fail'));
    } finally { setBusy(false); }
  };
  return (<div className="mt-2">
    <div className="flex flex-wrap gap-2">
      <Button size="sm" variant="secondary" disabled={busy} onClick={go}>{busy ? t(lang, 'cmp_saving') : t(lang, 'cmp_save')}</Button>
      <Button size="sm" variant="outline" disabled={busy} onClick={csv}>{t(lang, 'cmp_csv')}</Button>
    </div>
    {err ? <div className={cn(S.err, 'mt-1')} role="alert">{err}</div> : null}
  </div>);
}
function QuoteCard({ q, token, concluded, onChange, vscore, best, lang, hired, terms, focus }) {
  const [state, setState] = useState(q.revealed ? 'revealed' : 'idle'); const [contact, setContact] = useState(null); const [busy, setBusy] = useState(false); const [msg, setMsg] = useState('');
  const [dialog, ask] = useConfirm(lang);
  const [negOpen, setNegOpen] = useState(false);
  const reduce = useReducedMotion();
  // THE REVEAL MOMENT: the redaction bar lifts off the supplier the first time the customer sees
  // them — in this session, or on the return from Stripe (focus). Once; a later visit is plain.
  const [justRevealed, setJustRevealed] = useState(!!focus && !!q.revealed);
  // Warn, do not block: an expired price is still a supplier worth contacting.
  const exp = expiryOf(q, lang);
  const w = terms && terms.window_days, c = terms && terms.chase_after_days;
  const unlock = (r) => { if (!r) return; setContact({ supplier: r.supplier, file_url: r.original_file_url, file_name: r.original_file_name }); setState('revealed'); setJustRevealed(true); };
  const reveal = async () => {
    setBusy(true); setMsg('');
    const r = await call('customer_api', { action: 'reveal', quote_id: q.id }, token).catch(() => null);
    if (!r || r.error) { setBusy(false); setMsg(errText(r, lang)); return; }
    if (r.already_revealed) { unlock(r); setBusy(false); return; }
    setBusy(false);
    const fee = aed(r.reveal_fee ?? q.reveal_fee);
    // The Reveal Guarantee is shown at the moment of payment, not only as a line under the button.
    const go = await ask(tf(lang, 'q_confirm_body', { fee, price: aed(q.price) }), { title: t(lang, 'q_confirm_title'), confirm: t(lang, 'q_confirm_pay'), reveal: true, children: <RevealGuarantee lang={lang} fee={fee} terms={terms} compact /> });
    if (!go) return;
    setBusy(true);
    // /ar/me for an Arabic customer, so the Stripe return lands in their language; stripe_checkout
    // keeps any path that already ends in /me.
    const cr = await call('stripe_checkout', { quote_id: q.id, return_url: location.origin + (lang === 'ar' ? '/ar/me' : '/me') }, token).catch(() => null);
    if (cr && cr.already_revealed) { unlock(await call('customer_api', { action: 'reveal', quote_id: q.id }, token).catch(() => null)); setBusy(false); return; }
    if (cr && cr.url) { location.href = cr.url; return; }
    // stripe_checkout answers {error:'stripe_not_configured'} at HTTP 200; errText says it in words.
    setBusy(false); setMsg(errText(cr, lang, 'q_checkout_fail'));
  };
  const showContactData = async () => { const r = await call('customer_api', { action: 'reveal', quote_id: q.id }, token).catch(() => null); if (r && r.supplier) setContact({ supplier: r.supplier, file_url: r.original_file_url, file_name: r.original_file_name }); };
  useEffect(() => { if (state === 'revealed' && !contact) showContactData(); }, [state]);
  const revealed = state === 'revealed';
  return (<div className={cn('rounded-card border p-3.5 transition-colors duration-500 sm:p-4', revealed ? 'border-accent/40 bg-accent/[0.04]' : best ? 'border-primary/35 bg-primary/[0.03]' : 'border-border bg-secondary/15')}>{dialog}
    <div className="flex items-center justify-between gap-3">
      <div className="min-w-0"><b className="font-head font-semibold tracking-snug">{supLabel(q.label, lang)}</b>{!revealed ? <span aria-hidden className="ms-2 inline-block align-middle leading-none"><Seal className="text-[11px]">{'••••••••••'}</Seal></span> : null}{best ? <span className="ms-1.5 rounded-chip border border-primary/30 bg-primary/12 px-1.5 py-0.5 align-middle font-mono text-[10px] font-semibold text-primary">{t(lang, 'q_best')}</span> : null}{q.verified ? <span className="text-[11px] font-bold text-primary"> ✓ {t(lang, 'q_verified')}</span> : null}{q.rating != null ? <span className="text-[12px] font-semibold text-accent"> ★ {q.rating}{q.rating_count != null ? ' (' + q.rating_count + ')' : ''}</span> : <span className="text-[11px] text-muted-foreground" title={t(lang, 'q_unrated_tip')}> {t(lang, 'q_unrated')}</span>}</div>
      <div className="shrink-0 text-end"><div className="tabular font-mono text-[18px] font-semibold text-foreground">{aed(q.price)}</div>{vscore != null ? <div className="tabular font-mono text-[10.5px] text-muted-foreground" title={t(lang, 'q_value_tip')}>{t(lang, 'q_value')} {vscore}/100</div> : null}</div>
    </div>
    <div className="mt-0.5 text-[11.5px] text-muted-foreground">{[q.lead_time ? t(lang, 'q_lead') + ': ' + q.lead_time : '', q.warranty ? t(lang, 'q_warranty') + ': ' + durationLabel(q.warranty, lang) : '', q.payment_terms ? t(lang, 'q_terms') + ': ' + q.payment_terms : '', q.win_rate != null ? t(lang, 'q_win') + ' ' + Math.round(q.win_rate) + '%' : ''].filter(Boolean).join(' · ')}</div>
    {/* W9: anonymous facts about the supplier, served per quote; each badge hides when its value is absent. */}
    {q.badges ? <div className="mt-1.5"><QuoteBadges f={q.badges} /></div> : null}
    {q.scope && <div className={cn(S.sub, 'mt-1')}>{q.scope}</div>}
    {q.notes &&<div className={cn(S.sub, 'mt-1')}>{t(lang, 'q_note') + q.notes}</div>}
    {/* What the price does NOT cover is the part that turns a cheap quote into an expensive job. */}
    {q.exclusions && <div className={cn(S.sub, 'mt-1 text-warn-fg')}>{t(lang, 'q_excl') + q.exclusions}</div>}
    {q.conditions && <div className={cn(S.sub, 'mt-1')}>{t(lang, 'q_cond') + q.conditions}</div>}
    {exp && (exp.tone === 'ok'
      ? <div className={cn(S.sub, 'mt-1')}>{exp.text}{q.validity ? (' · ' + t(lang, 'q_validity') + q.validity) : ''}</div>
      : <div className={cn('mt-1.5 rounded-md border px-3 py-2 text-[11.5px]', exp.tone === 'expired' ? 'border-danger/30 bg-danger/10 text-danger-fg' : 'border-warn/30 bg-warn/10 text-warn-fg')} role={exp.tone === 'expired' ? 'alert' : undefined}>{exp.text}</div>)}
    {!exp && q.validity && <div className={cn(S.sub, 'mt-1')}>{t(lang, 'q_validity') + q.validity}</div>}
    {/* match_reason is omitted by the API until reveal, because it can name the company. */}
    {q.match_reason && <div className={cn(S.sub, 'mt-1')}>{t(lang, 'q_why') + q.match_reason}</div>}
    <div className="mt-1.5"><QuotePdfLink q={q} token={token} lang={lang} /></div>
    <div className="mt-2"><SupplierRelationshipCard quote={q} token={token} lang={lang === 'ar' ? 'ar' : 'en'} /></div>
    {/* Behind a disclosure: mounted on every quote card, it fired one negotiation_assistant call
        per quote on every open request, for guidance most customers never looked at. */}
    <div className="mt-2">
      <button type="button" aria-expanded={negOpen} onClick={() => setNegOpen((v) => !v)} className="text-[12.5px] font-semibold text-primary">
        {t(lang, negOpen ? 'q_neg_hide' : 'q_neg_show')}
      </button>
      {negOpen ? <div className="mt-2"><NegotiationAssistant token={token} quoteId={q.id} lang={lang === 'ar' ? 'ar' : 'en'} /></div> : null}
    </div>
    {revealed ? (contact
        ? <RevealMoment play={justRevealed && !reduce}><Contact play={justRevealed && !reduce} c={contact} q={q} token={token} onChange={onChange} lang={lang} terms={terms} won={hired != null && q.supplier_ref != null && Number(hired) === Number(q.supplier_ref)} /></RevealMoment>
        : <div className={cn(S.sub, 'mt-2 flex items-center gap-2')}><span className="redact redact-bar" aria-hidden />{t(lang, 'q_loading_contact')}</div>)
      : (<div className="mt-3 flex flex-col items-stretch gap-2.5 border-t border-border pt-3 sm:flex-row sm:items-center sm:justify-between">
          {/* Stacked below sm: beside the button the fee sentence was squeezed to 1-2 words a line at 375px. */}
          <div className={cn(S.sub, 'min-w-0 sm:flex-1')}>{w && c ? tf(lang, 'q_fee_line', { fee: aed(q.reveal_fee), w, c }) : aed(q.reveal_fee)}</div>
          {/* Gold: the one action in the product that unseals an identity. */}
          <Button variant="reveal" disabled={busy || concluded} onClick={reveal}><Lock aria-hidden />{busy ? t(lang, 'q_wait') : t(lang, 'q_reveal')}</Button>
        </div>)}
    {msg && <div className={S.err} role="alert">{msg}</div>}
  </div>);
}
// The redaction bar is the brand's mark for withheld data, so the reveal is that bar lifting away.
function RevealMoment({ play, children }) {
  if (!play) return children;
  return (<div className="relative">
    <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.55, ease: [0.2, 0.8, 0.2, 1] }}>{children}</motion.div>
    <motion.span aria-hidden className="redact pointer-events-none absolute inset-x-3 top-5 !block h-5" style={{ transformOrigin: 'right center' }}
      initial={{ scaleX: 1, opacity: 1 }} animate={{ scaleX: 0, opacity: 0 }} transition={{ duration: 0.75, delay: 0.1, ease: [0.7, 0, 0.3, 1] }} />
  </div>);
}

function Contact({ c, q, token, onChange, lang, won, terms, play = false }) {
  const s = c.supplier || {};
  const [rating, setRating] = useState(0); const [rated, setRated] = useState(!!(q && q.rated)); const [done, setDone] = useState('');
  const [dialog, ask] = useConfirm(lang);
  const g = terms || {};
  const rate = async (n) => { setRating(n); const j = await call('customer_api', { action: 'rate_supplier', quote_id: q.id, rating: n }, token).catch(() => null); if (j && j.ok) { setRated(true); setDone(t(lang, 'c_thanks')); } else setDone(errText(j, lang, 'c_rate_fail')); };
  const refund = async () => { if (!(await ask(tf(lang, 'c_refund_confirm', { c: g.chase_after_days, w: g.window_days, bmin: g.bank_min_days, bmax: g.bank_max_days }), { title: t(lang, 'c_refund'), confirm: t(lang, 'c_refund') }))) return; const j = await call('customer_api', { action: 'request_refund', quote_id: q.id }, token).catch(() => null); setDone(j && j.ok ? t(lang, 'c_refund_ok') + (j.refund_ref ? ' ' + tf(lang, 'c_refund_ref', { r: j.refund_ref }) : '') : errText(j, lang, 'c_refund_fail')); };
  // D4: the refund case and the chief executive's decision reference, from the refunds row itself.
  const gq = q.guarantee || {};
  const hire = async () => { if (!(await ask(t(lang, 'c_hire_confirm'), { title: t(lang, 'c_hire'), confirm: t(lang, 'c_hire') }))) return; const j = await call('customer_api', { action: 'complete_inquiry', quote_id: q.id }, token).catch(() => null); if (j && j.ok) { setDone(t(lang, 'c_hired')); onChange && onChange(); } else setDone(errText(j, lang, 'c_update_fail')); };
  const date = (d) => new Date(d).toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
  return (<div className="mt-2.5 flex flex-col gap-2.5">{dialog}
    <div className="rounded-card border border-accent/35 bg-accent/[0.06] p-3.5">
      <div className="flex flex-wrap items-center gap-2"><Badge variant="revealed" dot className="!text-accent font-mono uppercase tracking-caps">{t(lang, 'q_unlocked')}</Badge><div className="min-w-0 font-head text-[16px] font-semibold tracking-snug"><OpenSeal play={play}>{s.company_name || t(lang, 'c_supplier')}</OpenSeal></div></div>
      {q && q.revealed_at ? <div className={cn(S.sub, 'mt-0.5')}>{tf(lang, 'c_revealed_on', { d: date(q.revealed_at) })}</div> : null}
      {won ? <div className="mt-0.5 text-[12px] font-bold text-primary">🏆 {t(lang, 'c_hired_badge')}</div> : null}
      <div className={cn(S.sub, 'mt-0.5')}>{tf(lang, 'c_paid', { fee: aed(q.reveal_fee) })}</div>
      <div className="mt-1.5 flex flex-wrap gap-3.5">
        {s.phone && <a href={'tel:' + s.phone} className="font-semibold text-primary">📞 <bdi dir="ltr">{s.phone}</bdi></a>}
        {s.whatsapp && <a href={'https://wa.me/' + String(s.whatsapp).replace(/[^0-9]/g, '')} target="_blank" rel="noopener" className="font-semibold text-primary">WhatsApp</a>}
        {s.email && <a href={'mailto:' + s.email} className="font-semibold text-primary">✉ <bdi dir="ltr">{s.email}</bdi></a>}
        {s.website && <a href={/^https?:/.test(s.website) ? s.website : 'https://' + s.website} target="_blank" rel="noopener" className="font-semibold text-primary">{t(lang, 'c_website')}</a>}
      </div>
      {c.file_url && <div className="mt-1.5"><a href={c.file_url} target="_blank" rel="noopener" className="font-semibold text-primary">{t(lang, 'c_download')}{c.file_name ? <> (<bdi>{c.file_name}</bdi>)</> : null}</a></div>}
      <div className="mt-2.5 flex flex-wrap items-center gap-4">
        {/* A11Y (5 Aug 2026): real buttons carrying their value, in a labelled group. */}
        {!rated ? <span role="group" aria-label={t(lang, 'c_rate_group')} className="text-lg tracking-widest text-muted-foreground/50">{[1, 2, 3, 4, 5].map((n) => <button key={n} type="button" onClick={() => rate(n)} aria-label={tf(lang, 'c_rate_n', { n })} className={cn('cursor-pointer border-0 bg-transparent p-0 leading-none', n <= rating && 'text-amber-400')}>★</button>)}</span> : <span className={S.sub}>{t(lang, 'c_rated')}</span>}
        <Button variant="link" className="h-auto px-0" onClick={hire}>{t(lang, 'c_hire')}</Button>
        <Button variant="link" className="h-auto px-0" onClick={refund}>{t(lang, 'c_refund')}</Button>
      </div>
      {done && <div className={cn(S.sub, 'mt-1.5 text-primary')} role="status">{done}</div>}
      {gq.refund_ref ? <div className={cn(S.sub, 'mt-1.5')}>{tf(lang, 'c_refund_ref', { r: gq.refund_ref })}{' · '}{gq.decision_ref ? tf(lang, 'c_decision_ref', { d: gq.decision_ref }) : t(lang, 'c_decision_wait')}</div> : null}
    </div>
    {/* The clock on the customer's own reveal. Hidden once the fee can no longer be refunded
        (hired or rated), because a running clock on a promise that no longer applies misleads. */}
    {q.guarantee && !won && !rated ? <RevealGuarantee lang={lang} fee={aed(q.reveal_fee)} terms={terms} facts={q.guarantee} compact /> : null}
  </div>);
}

// THE STRIPE RETURN, ON SCREEN. A payment used to end on a one-line note (or, when cancelled, on
// nothing at all); this states what was paid and that the guarantee clock started, or that nothing
// was charged.
function ReceiptNote({ receipt, inqs, lang, onClose }) {
  const reduce = useReducedMotion();
  const all = inqs.flatMap((i) => [i, ...(i.children || [])]);
  const q = receipt.quoteId ? all.flatMap((i) => i.quotes || []).find((x) => x.id === receipt.quoteId) : null;
  const paid = receipt.kind === 'paid';
  return (<motion.div role="status" initial={reduce ? false : { opacity: 0, y: -8, scale: 0.98 }} animate={{ opacity: 1, y: 0, scale: 1 }} transition={{ duration: reduce ? 0 : 0.35, ease: [0.2, 0.8, 0.2, 1] }}
    className="qd-panel mb-5 flex items-start gap-3 p-4">
    <motion.span initial={reduce ? false : { scale: 0.4, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} transition={{ type: 'spring', stiffness: 380, damping: 18, delay: reduce ? 0 : 0.12 }}
      className={cn('grid h-9 w-9 shrink-0 place-items-center rounded-full', paid ? 'bg-primary/20 text-primary' : 'bg-secondary text-muted-foreground')}>
      {paid ? <Check className="h-4 w-4" aria-hidden /> : <X className="h-4 w-4" aria-hidden />}
    </motion.span>
    <div className="min-w-0 flex-1">
      {paid
        ? <><div className="font-head text-[15px] font-bold text-foreground">{t(lang, 'rcpt_title')}</div><p className="mt-0.5 text-[13px] text-muted-foreground">{q ? tf(lang, 'rcpt_body', { fee: aed(q.reveal_fee) }) : t(lang, 'payment_confirmed')}</p></>
        : <p className="text-[13px] text-foreground">{t(lang, 'rcpt_cancelled')}</p>}
    </div>
    <button type="button" onClick={onClose} aria-label={t(lang, 'close')} className="text-muted-foreground hover:text-foreground"><X className="h-4 w-4" aria-hidden /></button>
  </motion.div>);
}
// The §22 module list, in the order a customer meets them. The Messages/Thread pair that used to
// live in this file is gone: CommunicationCenter serves the same four messages_api actions and adds
// the documents that belong to each conversation plus an explicit statement of which channels the
// inbox does and does not carry, so keeping both would have been two inboxes disagreeing.
const MODULES = [
  ['projects', 'projects'], ['spatial', 'mod_spatial'], ['documents', 'mod_documents'],
  ['messages', 'messages'], ['approvals', 'mod_approvals'], ['orders', 'mod_orders'],
  ['predict', 'mod_predict'], ['profile', 'mod_profile'], ['account', 'mod_account'],
];
// A MODULE IS A PAGE NOW, NOT A POP-UP.
//
// These opened as a Dialog over the dashboard, and the reason was sound at the time: navigating to
// a module used to REPLACE the whole screen, which unmounted the KPIs and stranded the intake
// assistant, so a window that floated above kept them alive underneath.
//
// The shell removes that constraint. The sidebar, the top bar and the assistant persist across
// every destination, so a module can own the main region without unmounting anything the customer
// needs — and a sidebar item that opens a modal is the tell that a screen is a dashboard wearing an
// application's clothes. Nothing here fetches: each surface still owns its endpoint, its loading
// state and its empty state.
function ModuleWindow({ id, onClose, onOpenRfq, projectId, token, lang, inqs, onChanged, twin }) {
  const l2 = lang === 'ar' ? 'ar' : 'en';
  const rtl = lang === 'ar';
  const entry = MODULES.find((m) => m[0] === id);
  if (!entry) return null;
  return (<section className="mx-auto w-full max-w-[1240px] px-4 py-5 sm:px-6">
    <div className="mb-4 flex items-center gap-3">
      <button type="button" onClick={onClose}
        className="grid h-9 w-9 shrink-0 place-items-center rounded-xl border border-border text-muted-foreground transition-colors hover:bg-secondary/50 hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        aria-label={t(lang, 'nav_overview')}>
        <ArrowRight className={cn('h-4 w-4', !rtl && 'rotate-180')} aria-hidden />
      </button>
      <h1 className="font-head text-[20px] font-extrabold tracking-tight text-foreground">{t(lang, entry[1])}</h1>
    </div>
    <div className="flex flex-col gap-3">
      {/* onOpenRfq is Dashboard's openRfq: each of these hands back an inquiries.id and that request
          opens. It was onClose, which discarded the id and showed the Overview. */}
      {/* linkableRfqs: requests not already in a project. Offering all of them let "Link" silently
          move a request out of another project (project_api link overwrites inquiries.project_id). */}
      {id === 'projects' && <ProjectsModule token={token} lang={l2} initialProjectId={projectId || undefined} linkableRfqs={inqs.filter((i) => !i.project_id).map((i) => ({ id: i.id, summary: i.summary, category: i.category }))} onOpenRfq={onOpenRfq} onChanged={onChanged} />}
      {id === 'spatial' && <SpatialModule token={token} lang={l2} inquiries={inqs} onOpenRfq={onOpenRfq} />}
      {id === 'documents' && <DocumentVault token={token} lang={l2} />}
      {id === 'messages' && <CommunicationCenter token={token} lang={l2} onOpenRfq={onOpenRfq} />}
      {id === 'approvals' && <ApprovalChain token={token} lang={l2} onOpenRfq={onOpenRfq} />}
      {id === 'orders' && <OrdersList token={token} lang={l2} onOpenRfq={onOpenRfq} />}
      {id === 'predict' && <PredictiveIntelligence token={token} lang={l2} />}
      {/* §2 the twin, §9 discovery and §17 the memory — three surfaces whose backends were complete
          and whose only reader was os_api, the staff console. They share one window because they
          are one subject: what the system knows about this customer and what it does with it.

          WHY A "COMPANY PROFILE" WAS ON A BUYER'S SCREEN, AND WHY IT IS NOW A BUYING PROFILE
          (13 Aug 2026, asked directly by the founder: "A customer is a person buying a service. A
          company profile is a supplier concept — trade licence, products, services, catalogues. On
          a customer's screen it is at best noise and at worst asking for personal or business data
          we have no reason to hold. My instinct is: take it out.")

          The instinct was right about the LABEL and wrong about the PANEL, and the difference is
          worth writing down because the label is what he saw. Opened at 1280 signed in as a real
          customer, every field on this window is measured:

            CompanyTwin        read-only. industry, live projects, suppliers this customer has PAID
                               to reveal, the categories they actually buy, their approval chain.
                               No input of any kind. Nothing writes customers.industry from any
                               customer surface - grepped customer_api and kyc, no writer exists.
            SupplierDiscovery  a text box for trades + an emirate, running the same matcher a real
                               request would. That is a buyer's tool.
            CustomerMemory     standing preferences (supplier locality, payment terms, certification)
                               that are applied to future RFQs.

          There is no trade licence, no catalogue, no products, no services and no company-identity
          field anywhere on it — it asks for nothing and holds nothing we were not already given by
          the customer's own buying. What it had was a supplier-side name imported onto a buyer's
          screen, which is exactly what it read as. So: renamed, not removed. Deleting it would have
          thrown away the standing preferences that shape every future RFQ and the matcher preview,
          to fix a word. */}
      {id === 'profile' && <div className="flex flex-col gap-3">
        <CompanyTwin twin={twin} lang={l2} />
        <SupplierDiscovery token={token} lang={l2} />
        <CustomerMemory token={token} lang={l2} />
      </div>}
      {id === 'account' && <AccountSettings token={token} lang={lang} onChanged={onChanged} />}
    </div>
  </section>);
}
// customer_api action='me' has served the customer's own row since the portal was written and no
// file in src/ ever called it — the account the customer holds was the one thing they could not
// look at. It is read-only on purpose: there is no endpoint that writes a preference back to the
// profile, so this states which choices are device-local rather than implying they were saved.
// AN ACCOUNT SCREEN YOU COULD NOT CHANGE ANYTHING ON.
//
// This was read-only and said so honestly — "We have no settings endpoint that writes them back to
// your profile yet, so nothing here is saved to your account." The honesty was right and the
// situation was not: customers.locale has been READ for months (my_inquiries serves it, the portal
// applies it on a new device) and nothing has ever written it, so an Arabic customer re-chose their
// language on every device forever. customer_api gained a narrow set_locale for exactly this.
//
// Name and mobile go through kyc save_customer, which is the routine that already validates them —
// and which now clears phone_verified when the number changes. That is the reason the mobile field
// carries a warning rather than a quiet save: the next load will ask them to verify the new number,
// and being told that before they press the button is the difference between a feature and a trap.
function AccountSettings({ token, lang, onChanged }) {
  const [me, setMe] = useState(null); const [err, setErr] = useState('');
  const [name, setName] = useState(''); const [phone, setPhone] = useState(''); const [dob, setDob] = useState('');
  const [busy, setBusy] = useState(''); const [msg, setMsg] = useState('');
  const load = () => call('customer_api', { action: 'me' }, token)
    .then((j) => { if (j && j.customer) { setMe(j.customer); setName(j.customer.full_name || ''); setPhone(j.customer.phone || ''); setDob(String(j.customer.date_of_birth || '').slice(0, 10)); } else setErr(t(lang, 'acct_failed')); })
    .catch(() => setErr(t(lang, 'acct_failed')));
  // DO NOT ASK AN AUTHENTICATED ENDPOINT WHO WE ARE BEFORE WE HAVE A TOKEN. This ran on the first
  // render, when `token` is still '' because it is read from localStorage and from
  // SB.auth.getSession() inside an effect that has not resolved yet. Measured on a signed-in
  // customer: two 401s against /kyc in the console on every load, before the real call succeeded.
  // Wrong in three ways - it spends a round trip per mount, it puts a red error in the console of
  // a working page so a real one is easy to miss, and it burns the one refresh attempt the
  // `retried` flag exists to protect. The effect re-runs when the token arrives, so waiting is free.
  // Wait for a token, and for a token that has not already expired. SB.auth refreshes on its own
  // and the auth listener re-renders with the new one, so this costs nothing but the 401.
  useEffect(() => { if (tokenAlive(token)) load(); }, [token]);
  if (err) return <div className={S.err}>{err}</div>;
  if (!me) return <div className={S.sub}>{t(lang, 'loading')}</div>;
  const since = me.created_at ? new Date(me.created_at).toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) : '';
  const digits = (v) => String(v || '').replace(/\D/g, '');
  const phoneChanged = digits(phone) !== digits(me.phone);
  const dobChanged = dob !== String(me.date_of_birth || '').slice(0, 10);
  const dirty = (name || '') !== (me.full_name || '') || phoneChanged || dobChanged;
  // Same rule create_inquiry applies, plus the reachable mobile it also requires.
  const missing = accountMissing(me);
  if (!digits(me.phone)) missing.push('mobile_number');
  // A badge belongs to the channel that was verified, and a number that is not there is not verified.
  const phoneOk = !!me.phone_verified && !!digits(me.phone);
  const badge = (ok) => <span className={ok ? 'text-primary font-bold' : ''}>{t(lang, ok ? 'verified' : 'acct_unverified')}</span>;
  const saveProfile = async () => {
    if (isUnder18(dob)) { setMsg(t(lang, 'err_under_18')); return; }
    setBusy('save'); setMsg('');
    // kyc save_customer already validates dob (dob_required / dob_invalid / under_18, answered by errText).
    const j = await call('kyc', { action: 'save_customer', full_name: name, phone, dob: dob || me.date_of_birth || '' }, token);
    setBusy('');
    if (j && j.ok) { setMsg(t(lang, j.phone_reverify_required ? 'acct_reverify' : 'acct_saved')); load(); if (onChanged) onChanged(); }
    else setMsg(errText(j, lang, 'acct_failed'));
  };
  const saveLocale = async (loc) => {
    setBusy('loc'); setMsg('');
    const j = await call('customer_api', { action: 'set_locale', locale: loc }, token);
    setBusy('');
    if (j && j.ok) { setMsg(t(lang, 'acct_saved')); load(); } else setMsg(errText(j, lang, 'acct_failed'));
  };
  const Row = ({ label, children }) => (
    <div className="grid gap-1 sm:grid-cols-[190px_1fr] sm:items-center sm:gap-3">
      <div className="text-[12.5px] font-medium text-muted-foreground">{label}</div>
      <div className="min-w-0">{children}</div>
    </div>
  );
  return (<div className="flex flex-col gap-4">
    <p className={S.sub}>{t(lang, 'acct_sub')}</p>
    {missing.length ? <Card className="p-4 border-warn-fg/40" role="status">
      <div className="text-[13.5px] font-semibold text-warn-fg">{t(lang, 'acct_incomplete_h')}</div>
      <ul className="mt-1.5 list-disc ps-5 text-[13px] text-foreground">{missing.map((m) => <li key={m}>{t(lang, 'acct_miss_' + m)}</li>)}</ul>
    </Card> : null}
    <Card className="flex flex-col gap-3.5 p-4">
      <Row label={t(lang, 'acct_name')}><Input aria-label={t(lang, 'acct_name')} autoComplete="name" value={name} onChange={(e) => setName(e.target.value)} /></Row>
      <Row label={t(lang, 'acct_phone')}>
        <Input aria-label={t(lang, 'acct_phone')} type="tel" dir="ltr" autoComplete="tel" value={phone} onChange={(e) => setPhone(e.target.value)} inputMode="tel" />
        <div className={cn('mt-1 text-[11.5px]', phoneChanged ? 'text-warn-fg' : 'text-muted-foreground')}>
          {phoneChanged ? t(lang, 'acct_phone_warn') : badge(phoneOk)}
        </div>
      </Row>
      <Row label={t(lang, 'acct_email')}>
        {/* Isolated so a Latin address does not scramble inside an Arabic line. */}
        <div className="text-[13px] text-foreground"><bdi dir="ltr">{me.email || '—'}</bdi></div>
        <div className="mt-1 text-[11.5px] text-muted-foreground">{badge(!!me.email_verified && !!me.email)}</div>
      </Row>
      <Row label={t(lang, 'acct_dob')}>
        <Input type="date" aria-label={t(lang, 'acct_dob')} autoComplete="bday" value={dob} aria-invalid={isUnder18(dob) || undefined} onChange={(e) => setDob(e.target.value)} />
        {isUnder18(dob) && <div className={S.err} role="alert">{t(lang, 'err_under_18')}</div>}
      </Row>
      <Row label={t(lang, 'acct_locale')}>
        <div className="flex flex-wrap gap-2">
          {[['en', 'English'], ['ar', 'العربية']].map(([code, labelText]) => (
            <Button key={code} type="button" size="sm" variant={me.locale === code ? 'default' : 'outline'}
              disabled={busy === 'loc' || me.locale === code} onClick={() => saveLocale(code)}>{labelText}</Button>
          ))}
        </div>
      </Row>
      <Row label={t(lang, 'acct_since')}><div className="text-[13px] text-foreground">{since || '—'}</div></Row>
      <div className="flex flex-wrap items-center gap-3 border-t border-border pt-3.5">
        <Button size="sm" disabled={!dirty || busy === 'save'} onClick={saveProfile}>{busy === 'save' ? t(lang, 'saving') : t(lang, 'save_details')}</Button>
        {msg ? <span className="text-[12.5px] text-muted-foreground">{msg}</span> : null}
      </div>
    </Card>
    <p className={S.hint}>{t(lang, 'acct_device_note')}</p>
  </div>);
}

// THE REQUEST'S OWN JOURNEY. What stood here was five words separated by chevrons with 1.5px dots —
// technically a stepper, visually a sentence. The stage a request is at is the single thing a
// customer opening the portal wants to know, so it gets a rail: completed segments filled, the
// current one pulsing, the rest quiet. `matched` is substituted into the third label when the
// server knows the number, because "Matched to 8 suppliers" is a fact and "Matched" is a mood.
//
// Horizontal on a desktop, and the labels drop to a single current-stage line under 640px rather
// than wrapping into three lines of chevrons on a phone.
const JOURNEY = ['jr_described', 'jr_structured', 'jr_matched', 'jr_quotes', 'jr_compare', 'jr_reveal'];
function Journey({ idx, lang, matched }) {
  // rfqStageIdx returns 0..4 over five RFQ stages; the journey the founder asked for has six, with
  // "structured" split out of "sent". Map rather than invent: a stage must never be claimed.
  const step = [0, 2, 3, 4, 5][Math.max(0, Math.min(4, Number(idx) || 0))];
  const label = (k, i) => (i === 2 && Number(matched) > 0)
    ? (lang === 'ar' ? ('مطابقة مع ' + matched + ' مورّد') : ('Matched to ' + matched + ' suppliers'))
    : t(lang, k);
  return (
    <div className="mt-3">
      {/* The kit Stepper laid flat: a node per stage (done filled, current lit, next hollow) joined
          by a rail, so a request reads as a position on a track rather than a bar of pills. */}
      <div className="flex items-center" aria-hidden>
        {JOURNEY.map((k, i) => (
          <div key={k} className={cn('flex min-w-0 items-center', i < JOURNEY.length - 1 && 'flex-1')}>
            <span className={cn('grid h-2.5 w-2.5 shrink-0 place-items-center rounded-full border transition-colors duration-500',
              i < step ? 'border-primary bg-primary' : i === step ? 'border-primary bg-primary/25 shadow-glow-teal motion-safe:animate-pulse' : 'border-border bg-card')} />
            {i < JOURNEY.length - 1 ? <span className={cn('h-px flex-1 transition-colors duration-500', i < step ? 'bg-primary' : 'bg-border')} /> : null}
          </div>
        ))}
      </div>
      <div className="mt-1.5 hidden items-center justify-between gap-2 sm:flex">
        {JOURNEY.map((k, i) => (
          <span key={k} className={cn('min-w-0 flex-1 truncate font-mono text-[10.5px]',
            i < step ? 'text-muted-foreground' : i === step ? 'font-semibold text-primary' : 'text-muted-foreground/50',
            i === 0 ? 'text-start' : i === JOURNEY.length - 1 ? 'text-end' : 'text-center')}>{label(k, i)}</span>
        ))}
      </div>
      <div className="mt-1.5 text-[11.5px] font-semibold text-primary sm:hidden">{label(JOURNEY[step], step)}</div>
    </div>
  );
}

// THE QUOTE SPREAD, IN BOTH STATES — and this is the one rule no amount of design may break.
//
// PRE-REVEAL: a count and a band rounded to the nearest 1,000. NOT five bars. A chart that plots
// each quote as its own bar before the customer has paid to reveal is exactly the picture that
// destroys what the marketplace sells, even when every bar is labelled "Supplier A" — the shape of
// the market is the thing being bought.
// POST-REVEAL: everything, because they have bought it. Lowest highlighted.
//
// The rounding is done HERE and also in SQL (fn_wa_context) for the conversational channel. This
// component is given the same prices the rest of the card already holds and chooses not to draw
// them; the SQL path is given a band and could not draw them if it wanted to.
function QuoteSpread({ quotes, lang }) {
  const priced = (quotes || []).filter((q) => Number(q.price) > 0);
  if (!priced.length) return null;
  const anyRevealed = priced.some((q) => q.revealed);
  const vals = priced.map((q) => Number(q.price));
  const lo = Math.min(...vals), hi = Math.max(...vals);
  const roundK = (n) => Math.round(n / 1000) * 1000;
  return (
    <div className="rounded-lg border border-border bg-secondary/20 p-3.5">
      <div className="flex items-center justify-between gap-2">
        <b className="text-[13px] text-foreground">{t(lang, 'spread_title')}</b>
        {!anyRevealed ? (
          <span className="inline-flex items-center gap-1.5 rounded-full border border-border bg-card px-2 py-1 text-[11px] font-medium text-muted-foreground">
            <Lock className="h-3 w-3" aria-hidden />{t(lang, 'spread_locked')}
          </span>
        ) : null}
      </div>
      {!anyRevealed ? (
        <>
          <div className="mt-2.5 text-[15px] font-bold text-foreground">
            {priced.length + ' ' + t(lang, 'spread_pre') + ' ' + aed(roundK(vals.reduce((a, b) => a + b, 0) / vals.length))}
          </div>
          {/* One band. Not one bar per quote. */}
          <div className="mt-2 h-2.5 overflow-hidden rounded-full bg-secondary/70">
            <div className="h-full w-1/2 rounded-full bg-gradient-to-r from-primary/35 via-primary/70 to-primary/35 motion-safe:transition-[width] motion-safe:duration-700" style={{ marginInlineStart: '25%' }} />
          </div>
        </>
      ) : (
        <div className="mt-2.5 flex flex-col gap-1.5">
          {priced.slice().sort((a, b) => Number(a.price) - Number(b.price)).map((q, i) => {
            const pct = hi === lo ? 100 : Math.max(12, Math.round(((Number(q.price) - lo) / (hi - lo)) * 70) + 30);
            return (
              <div key={q.id} className="flex items-center gap-2">
                <span className="w-[104px] shrink-0 truncate text-[11.5px] text-muted-foreground">{q.supplier_name || q.label}</span>
                <span className="h-2.5 flex-1 overflow-hidden rounded-full bg-secondary/70">
                  <span className={cn('block h-full rounded-full motion-safe:transition-[width] motion-safe:duration-700', i === 0 ? 'bg-primary' : 'bg-primary/45')} style={{ width: pct + '%' }} />
                </span>
                <span className={cn('w-[92px] shrink-0 text-end text-[11.5px] tabular-nums', i === 0 ? 'font-bold text-primary' : 'text-foreground')}>{aed(q.price)}</span>
                {i === 0 ? <Check className="h-3.5 w-3.5 shrink-0 text-primary" aria-hidden /> : <span className="w-3.5 shrink-0" />}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
