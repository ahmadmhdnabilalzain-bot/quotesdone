'use client';
import { useEffect, useRef, useState } from 'react';
import { usePathname } from 'next/navigation';
import { useLocale } from 'next-intl';

// Was an inline `process.env.NEXT_PUBLIC_SUPABASE_URL || '<production ref>'`, which meant a
// preview deployment missing the variable pointed the public chat widget at the LIVE database
// with no warning anywhere. supaEnv resolves it once and warns when it falls back.
import { SUPA_ANON as ANON, SUPA_FN } from '@/lib/supaEnv';
const FN = `${SUPA_FN}/site_assistant`;

type Msg = { role: 'user' | 'assistant'; content: string };

const T = {
  en: { title: 'QuotesDone Assistant', sub: 'Powered by the Smart Engine', open: 'Ask QuotesDone', close: 'Close',
        ph: 'Ask about QuotesDone…', send: 'Send', thinking: 'Typing…',
        greet: 'Hi! I can help with how QuotesDone works, fees, posting a job, or joining as a supplier. What would you like to know?',
        err: 'Sorry — something went wrong. Please try again, or email management@quotesdone.com.' },
  ar: { title: 'مساعد QuotesDone', sub: 'مدعوم بالمحرك الذكي', open: 'اسأل QuotesDone', close: 'إغلاق',
        ph: 'اسأل عن QuotesDone…', send: 'إرسال', thinking: 'يكتب…',
        greet: 'مرحباً! يمكنني مساعدتك في معرفة كيفية عمل QuotesDone، الرسوم، طلب عروض الأسعار، أو الانضمام كمورد. كيف أستطيع مساعدتك؟',
        err: 'عذراً، حدث خطأ. يرجى المحاولة مرة أخرى أو مراسلتنا على management@quotesdone.com.' }
};

// Render text safely: escape, then linkify emails / URLs / internal paths.
// Each link is wrapped in <bdi> so it stays readable inside Arabic (right-to-left) text.
function render(text: string) {
  const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  let h = esc(text);
  h = h.replace(/(https?:\/\/[^\s<]+)/g, (m) => `<bdi><a href="${m}" target="_blank" rel="noopener noreferrer" style="color:#2DD4BF;font-weight:600">${m}</a></bdi>`);
  h = h.replace(/([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/g, (m) => `<bdi><a href="mailto:${m}" style="color:#2DD4BF;font-weight:600">${m}</a></bdi>`);
  h = h.replace(/(^|[\s(])(\/(?:contact|app|suppliers|faq|services|blog|about)\/?)/g, (_m, p, path) => `${p}<bdi><a href="${path}" style="color:#2DD4BF;font-weight:600">${path}</a></bdi>`);
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
  const boxRef = useRef<HTMLDivElement | null>(null);
  const inpRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => { if (boxRef.current) boxRef.current.scrollTop = boxRef.current.scrollHeight; }, [msgs, busy, open]);
  useEffect(() => { if (open) { if (!msgs.length) setMsgs([{ role: 'assistant', content: t.greet }]); setTimeout(() => inpRef.current?.focus(), 60); } }, [open]);

  // Never show the public assistant inside the internal OS console.
  if (/(^|\/)os(\/|$)/.test(pathname)) return null;

  const send = async () => {
    const m = val.trim();
    if (!m || busy) return;
    setVal('');
    const next = [...msgs, { role: 'user' as const, content: m }];
    setMsgs(next); setBusy(true);
    try {
      const r = await fetch(FN, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', apikey: ANON, Authorization: `Bearer ${ANON}` },
        body: JSON.stringify({ message: m, history: next.slice(-6), path: pathname })
      });
      const j = await r.json();
      setMsgs([...next, { role: 'assistant', content: (j && j.reply) || t.err }]);
    } catch (_e) {
      setMsgs([...next, { role: 'assistant', content: t.err }]);
    } finally { setBusy(false); }
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
              <div key={i} dir="auto" style={bubble(m.role)} dangerouslySetInnerHTML={{ __html: render(m.content) }} />
            ))}
            {busy && <div dir="auto" style={{ ...bubble('assistant'), opacity: .7, fontStyle: 'italic' }}>{t.thinking}</div>}
          </div>
          <div style={{ display: 'flex', gap: 8, padding: 12, borderTop: '1px solid rgba(255,255,255,.10)' }}>
            <input ref={inpRef} dir="auto" value={val} onChange={(e) => setVal(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter') send(); }} placeholder={t.ph} aria-label={t.ph}
              style={{ flex: 1, minWidth: 0, background: 'rgba(255,255,255,.05)', border: '1px solid rgba(255,255,255,.14)',
                color: '#EAF4F2', borderRadius: 10, padding: '10px 12px', font: 'inherit', fontSize: 14, textAlign: 'start' }} />
            <button onClick={send} disabled={busy}
              style={{ background: 'linear-gradient(135deg,#14B8A6,#0B8276)', color: '#04222b', border: 0, borderRadius: 10,
                padding: '0 15px', fontWeight: 700, cursor: busy ? 'default' : 'pointer', opacity: busy ? .6 : 1 }}>{t.send}</button>
          </div>
        </div>
      )}
      <button onClick={() => setOpen(!open)} aria-label={open ? t.close : t.open}
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
