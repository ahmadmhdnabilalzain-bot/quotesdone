'use client';
import { photoToDataUrl } from '@/lib/chatPhoto';
import { useEffect, useRef, useState } from 'react';
import { usePathname } from 'next/navigation';
import { useLocale } from 'next-intl';
import { lookForStoredAnswer, noVerdict, readReply } from '@/lib/portalReply';

// Was an inline `process.env.NEXT_PUBLIC_SUPABASE_URL || '<production ref>'`, which meant a
// preview deployment missing the variable pointed the public chat widget at the LIVE database
// with no warning anywhere. supaEnv resolves it once and warns when it falls back.
import { SUPA_ANON as ANON, fnUrl } from '@/lib/supaEnv';
const FN = fnUrl('site_assistant');

// signup: the server's sign-up button (site_assistant/visitor_scope.ts, founder ruling 18 Oct 2026). A visitor who is
// not signed up is guided to register; the button is on every reply the server sends them.
type Msg = { role: 'user' | 'assistant'; content: string; signup?: { url: string; label: string } };

const T = {
  en: { title: 'QuotesDone Assistant', sub: 'Powered by the Smart Engine', open: 'Ask QuotesDone', close: 'Close',
        ph: 'Ask about QuotesDone…', send: 'Send', thinking: 'Typing…', late: 'Still working on your answer…',
        greet: 'Hi! Ask me what QuotesDone is, how it works, what it costs or why you can trust it. Ready to send a job? Sign up free and our sales engineer takes it from there. Try one of these:',
        chips: ['How does QuotesDone work?', 'Is it free for customers?', 'How do you keep my details private?'],
        err: 'Sorry — something went wrong. Please try again, or email management@quotesdone.com.',
        photo: 'Photo', photoAdd: 'Add a photo or drawing', photoOn: 'Photo attached', photoOnly: '(photo)' },
  ar: { title: 'مساعد QuotesDone', sub: 'مدعوم بالمحرك الذكي', open: 'اسأل QuotesDone', close: 'إغلاق',
        ph: 'اسأل عن QuotesDone…', send: 'إرسال', thinking: 'يكتب…', late: 'ما زلتُ أعمل على إجابتك…',
        greet: 'مرحباً! اسألني ما هي QuotesDone وكيف تعمل وما تكلفتها ولماذا يمكنك الوثوق بها. لديك طلب؟ سجّل مجانًا وسيتابع معك مهندس المبيعات لدينا. جرّب أحد هذه الأسئلة:',
        chips: ['كيف تعمل QuotesDone؟', 'هل الخدمة مجانية للعملاء؟', 'كيف تحافظون على سرية بياناتي؟'],
        err: 'عذراً، حدث خطأ. يُرجى المحاولة مرة أخرى أو مراسلتنا على management@quotesdone.com.',
        photo: 'صورة', photoAdd: 'أرفق صورة أو مخططًا', photoOn: 'تم إرفاق الصورة', photoOnly: '(صورة)' }
};

// Render text safely: escape, then linkify emails / URLs / internal paths.
// Each link is wrapped in <bdi> so it stays readable inside Arabic (right-to-left) text.
//
// EXPORTED because the portal now has an assistant surface of its own and a second copy of this
// would be a second copy of the bidi rule. Half the UAE market reads the Arabic; an email address
// or a +971 number rendered without isolation scrambles inside an RTL paragraph, and a rule that
// exists twice is a rule that will be applied once.
export function render(text: string) {
  const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  let h = esc(text);
  h = h.replace(/(https?:\/\/[^\s<]+)/g, (m) => `<bdi><a href="${m}" target="_blank" rel="noopener noreferrer" style="color:#2DD4BF;font-weight:600">${m}</a></bdi>`);
  h = h.replace(/([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/g, (m) => `<bdi><a href="mailto:${m}" style="color:#2DD4BF;font-weight:600">${m}</a></bdi>`);
  h = h.replace(/(^|[\s(])(\/(?:ar\/me|contact|me|portal|supplier|faq|services|blog|about)\/?)(?![\w-])/g, (_m, p, path) => `${p}<bdi><a href="${path}" style="color:#2DD4BF;font-weight:600">${path}</a></bdi>`);
  h = h.replace(/(\+?\d[\d\s\-()]{6,}\d)/g, (m) => `<bdi>${m}</bdi>`);
  return h.replace(/\n/g, '<br>');
}

export function ChatWidget() {
  const locale = useLocale();
  const pathname = usePathname() || '';
  const rtl = locale === 'ar';
  const t = (T as any)[rtl ? 'ar' : 'en'] as typeof T.en;
  const [open, setOpen] = useState(false);
  const [msgs, setMsgs] = useState<Msg[]>([]);
  const [val, setVal] = useState('');
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState('');
  // A PHOTO OR DRAWING (founder ruling 1200): resized in the browser to at most 1280 px as a JPEG, so it stays under
  // the server's cap (_shared/chat_images.ts), and sent with the next message. One at a time.
  const [photo, setPhoto] = useState('');
  const fileRef = useRef<HTMLInputElement | null>(null);
  const pickPhoto = async (f: File | undefined) => { const d = await photoToDataUrl(f); if (d) setPhoto(d); };
  const boxRef = useRef<HTMLDivElement | null>(null);
  const inpRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => { if (boxRef.current) boxRef.current.scrollTop = boxRef.current.scrollHeight; }, [msgs, busy, open]);
  useEffect(() => { if (open) { if (!msgs.length) setMsgs([{ role: 'assistant', content: t.greet }]); restore(); setTimeout(() => inpRef.current?.focus(), 60); } }, [open]);

  // ONE CONVERSATION THAT IS NEVER LOST (founder ruling 1255). Its id lives in localStorage, so a reload, a closed browser
  // or a return days later finds it; site_assistant stores every turn under it and the chat is redrawn from the database
  // (action 'history'), never from this tab's memory. Signing up carries it into the portal (PortalShell sends it as
  // widget_conv). site_assistant also keys its per-visitor ceiling on this id (website audit, "Where the smart shows").
  const conv = useRef('');
  useEffect(() => {
    try {
      // only a full random UUID v4 is ever used (the server refuses anything weaker); no crypto.randomUUID, no id
      const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
      const kept = localStorage.getItem('qd-chat-conv') || '';
      conv.current = UUID_V4.test(kept) ? kept : (typeof crypto !== 'undefined' && crypto.randomUUID ? crypto.randomUUID() : '');
      if (conv.current) localStorage.setItem('qd-chat-conv', conv.current); else localStorage.removeItem('qd-chat-conv');
    } catch (_e) { conv.current = ''; }
  }, []);
  // redrawn when the chat is opened (not on every page view): only a visitor who has one gets turns back
  // restored is set only once the server ANSWERED: a history call that failed (a network blip, a 5xx) used to be marked done,
  // so the chat stayed a bare greeting for the rest of the visit although the server held every turn (2 Nov 2026).
  const restored = useRef(false);
  const restoring = useRef(false);
  const readHistory = async (): Promise<Msg[] | null> => {
    if (!conv.current) return null;
    const r = await fetch(FN, { method: 'POST', headers: { 'Content-Type': 'application/json', apikey: ANON, Authorization: `Bearer ${ANON}` },
      body: JSON.stringify({ action: 'history', conv: conv.current }) });
    const j = r.ok ? await r.json() : null;
    return Array.isArray(j?.turns) ? j.turns : null;
  };
  const restore = () => {
    if (restored.current || restoring.current || !conv.current) return; restoring.current = true;
    readHistory().then((turns) => {
      if (turns === null) return;   // not answered: asked again the next time the chat opens
      restored.current = true;
      if (turns.length) setMsgs((m) => (m.length > 1 ? m : [{ role: 'assistant', content: t.greet }, ...turns]));
    }).catch(() => { /* the next turn still reads the whole conversation on the server */ }).finally(() => { restoring.current = false; });
  };

  // On a phone the launcher sat over the hero's demonstration card. Below 640px it waits for the
  // first scroll; on wider screens it is there from the start.
  const [shown, setShown] = useState(false);
  useEffect(() => {
    const check = () => { if (window.innerWidth >= 640 || window.scrollY > 240) setShown(true); };
    check();
    window.addEventListener('scroll', check, { passive: true });
    window.addEventListener('resize', check);
    return () => { window.removeEventListener('scroll', check); window.removeEventListener('resize', check); };
  }, []);

  // Never show the public assistant inside a signed-in surface. The OS console has its own copilot,
  // /me has one docked in the portal shell, and /portal carries the supplier portal's own assistant —
  // two assistants on one screen is worse than either alone. /supplier is now the public supplier
  // LANDING page, so the widget stays there.
  if (/(^|\/)(os|me|portal|supplier-app)(\/|$)/.test(pathname)) return null;

  const send = async (preset?: string) => {
    const m = (preset ?? val).trim() || (photo ? t.photoOnly : '');
    if (!m || busy) return;
    const images = photo ? [photo] : [];
    setPhoto('');
    setVal('');
    const next = [...msgs, { role: 'user' as const, content: m }];
    setMsgs(next); setBusy(true);
    const show = (content: string, signup?: Msg['signup']) => setMsgs([...next, { role: 'assistant', content, ...(signup ? { signup } : {}) }]);
    try {
      const r = await fetch(FN, {
        method: 'POST',
        // THE ANSWER STREAMS (12 Oct 2026, _shared/stream_reply.ts): a status line at once, then the finished,
        // checked reply a few words at a time. A server that does not stream answers JSON, read below as before.
        headers: { 'Content-Type': 'application/json', Accept: 'application/x-ndjson, application/json', apikey: ANON, Authorization: `Bearer ${ANON}` },
        // lang WAS NEVER SENT until 9 Sep 2026, so site_assistant resolved uiLang to 'en' on every
        // request and its entire Arabic branch -- the one that names the portal buttons in Arabic --
        // was unreachable code. useLocale() already knows; the value simply never left the browser.
        // history is only a first-turn fallback: site_assistant stores every turn and reads the whole conversation back by conv
        body: JSON.stringify({ message: m, lang: locale, history: next.slice(-40), path: pathname, conv: conv.current, ...(images.length ? { images } : {}) })
      });
      // THE PORTAL'S READER (src/lib/portalReply.ts), not a second copy of it (2 Nov 2026): only the approved text is kept,
      // a reset clears what was shown, and a cut stream or a 504 page reads as "no reply yet" instead of throwing, which
      // used to print the error line over a half-written answer (the cut stream showed `text` as if it were the reply).
      const j = await readReply(r, { status: setStatus, text: (s) => show(s) });
      const signup = (j.done?.signup as Msg['signup']) || undefined;
      // past the visitor cap with the model up but no line it wrote passing the guard, the server sends no text
      // (founder_instruction 1339): the sign-up button alone is shown, never the error line.
      const capOnly = j.done?.visitor_cap === true && !!signup;
      let reply = j.reply;
      // THE ANSWER THAT NEVER ARRIVED IS LOOKED FOR (2 Nov 2026). The server stores every turn under the conversation even
      // when the connection drops, so the chat reads it back from the history for up to 45 s before it says anything went
      // wrong, exactly as the portal does; the error line is for a turn that has no stored answer either.
      if (!reply && !capOnly && noVerdict(j) && conv.current) {
        setStatus(t.late);
        reply = await lookForStoredAnswer(readHistory, m, { waitMs: 45_000, everyMs: 5_000 });
      }
      show(reply || (capOnly ? '' : t.err), signup);
    } catch (_e) {
      show(t.err);
    } finally { setBusy(false); setStatus(''); }
  };

  const side = rtl ? { left: 18 } : { right: 18 };
  const bubble = (role: string) => ({
    maxWidth: '86%', padding: '9px 12px', borderRadius: 12, fontSize: 14, lineHeight: 1.55,
    whiteSpace: 'pre-wrap' as const, unicodeBidi: 'plaintext' as any, textAlign: 'start' as any, wordBreak: 'break-word' as const,
    alignSelf: role === 'user' ? 'flex-end' : 'flex-start',
    background: role === 'user' ? 'linear-gradient(135deg,#14B8A6,#0B8276)' : 'rgba(255,255,255,.06)',
    color: role === 'user' ? '#04222b' : '#EAF4F2',
    border: role === 'user' ? '0' : '1px solid rgba(255,255,255,.10)'
  });

  return (
    <div dir={rtl ? 'rtl' : 'ltr'} style={{ position: 'fixed', bottom: 18, ...side, zIndex: 50 }}>
      {open && (
        <div role="dialog" aria-label={t.title}
          style={{ width: 'min(370px, calc(100vw - 36px))', height: 'min(520px, calc(100vh - 120px))',
            display: 'flex', flexDirection: 'column', marginBottom: 12, overflow: 'hidden',
            background: 'rgba(5,18,26,.98)', border: '1px solid rgba(255,255,255,.14)', borderRadius: 16,
            boxShadow: '0 30px 70px -30px rgba(0,0,0,.85)', backdropFilter: 'blur(10px)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '13px 15px', background: '#0C2330', borderBottom: '1px solid rgba(255,255,255,.10)' }}>
            <span style={{ width: 8, height: 8, borderRadius: 999, background: '#2DD4BF', flex: '0 0 auto' }} />
            <div style={{ minWidth: 0 }}>
              <div style={{ fontWeight: 800, fontSize: 14, color: '#fff' }}>{t.title}</div>
              <div style={{ fontSize: 11, color: '#9DB2B2' }}>{t.sub}</div>
            </div>
            <button onClick={() => setOpen(false)} aria-label={t.close}
              style={{ marginInlineStart: 'auto', background: 'transparent', border: 0, color: '#9DB2B2', fontSize: 22, lineHeight: 1, cursor: 'pointer', padding: '0 4px' }}>&times;</button>
          </div>
          <div ref={boxRef} style={{ flex: 1, overflowY: 'auto', padding: 14, display: 'flex', flexDirection: 'column', gap: 9 }}>
            {msgs.map((m, i) => (
              <div key={i} style={{ display: 'contents' }}>
                {m.content && <div dir="auto" style={bubble(m.role)} dangerouslySetInnerHTML={{ __html: render(m.content) }} />}
                {m.signup && /^\/[a-z/]*$/.test(m.signup.url) && (
                  <a href={m.signup.url} dir="auto"
                    style={{ alignSelf: 'flex-start', background: 'linear-gradient(135deg,#2DD4BF,#14B8A6)', color: '#04222b', fontWeight: 800,
                      fontSize: 13.5, borderRadius: 10, padding: '8px 14px', textDecoration: 'none' }}>{m.signup.label}</a>
                )}
              </div>
            ))}
            {msgs.length === 1 && !busy && (
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
                {t.chips.map((c) => (
                  <button key={c} type="button" dir="auto" onClick={() => send(c)}
                    style={{ background: 'rgba(45,212,191,.08)', border: '1px solid rgba(45,212,191,.35)', color: '#6EE7D4',
                      borderRadius: 999, padding: '6px 11px', fontSize: 12.5, cursor: 'pointer', textAlign: 'start' }}>
                    {c}
                  </button>
                ))}
              </div>
            )}
            {busy && msgs[msgs.length - 1]?.role === 'user' && <div dir="auto" style={{ ...bubble('assistant'), opacity: .7, fontStyle: 'italic' }}>{status || t.thinking}</div>}
          </div>
          <div style={{ display: 'flex', gap: 8, padding: 12, borderTop: '1px solid rgba(255,255,255,.10)' }}>
            <input ref={fileRef} type="file" accept="image/*" hidden onChange={(e) => { pickPhoto(e.target.files?.[0]); e.target.value = ''; }} />
            <button type="button" onClick={() => fileRef.current?.click()} aria-label={t.photoAdd} title={photo ? t.photoOn : t.photoAdd} disabled={busy}
              style={{ background: photo ? 'rgba(45,212,191,.25)' : 'rgba(255,255,255,.05)', border: '1px solid rgba(255,255,255,.14)', color: '#EAF4F2',
                borderRadius: 10, padding: '0 10px', fontSize: 12.5, cursor: busy ? 'default' : 'pointer' }}>{photo ? t.photoOn : t.photo}</button>
            <input ref={inpRef} dir="auto" value={val} onChange={(e) => setVal(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter') send(); }} placeholder={t.ph} aria-label={t.ph}
              style={{ flex: 1, minWidth: 0, background: 'rgba(255,255,255,.05)', border: '1px solid rgba(255,255,255,.14)',
                color: '#EAF4F2', borderRadius: 10, padding: '10px 12px', font: 'inherit', fontSize: 14, textAlign: 'start' }} />
            <button onClick={() => send()} disabled={busy}
              style={{ background: 'linear-gradient(135deg,#14B8A6,#0B8276)', color: '#04222b', border: 0, borderRadius: 10,
                padding: '0 15px', fontWeight: 700, cursor: busy ? 'default' : 'pointer', opacity: busy ? .6 : 1 }}>{t.send}</button>
          </div>
        </div>
      )}
      <button onClick={() => setOpen(!open)} aria-label={open ? t.close : t.open} hidden={!shown && !open}
        style={{ width: 54, height: 54, borderRadius: 999, border: 0, cursor: 'pointer',
          marginInlineStart: rtl ? 0 : 'auto', display: 'flex', alignItems: 'center', justifyContent: 'center',
          background: 'linear-gradient(135deg,#2DD4BF,#14B8A6)', boxShadow: '0 14px 34px -12px rgba(45,212,191,.75)' }}>
        <svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#04222b" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          {open ? <path d="M18 6 L6 18 M6 6 l12 12" />
                : <path d="M21 11.5a8.38 8.38 0 0 1-8.5 8.5 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7A8.38 8.38 0 0 1 4 11.5 8.5 8.5 0 0 1 21 11.5z" />}
        </svg>
      </button>
    </div>
  );
}
