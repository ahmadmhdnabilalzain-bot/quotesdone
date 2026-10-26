'use client';
// SPEC §17 — CUSTOMER AI MEMORY: SEE, **AND CORRECT**.
//
// "The system remembers: customer always prefers local suppliers, 60-day payment terms,
// ISO-certified companies. Future RFQs automatically consider this."
//
// WHAT WAS MEASURED (production, 7 Aug 2026): customer_preference, fn_customer_preference_learn and
// the learning trigger on inquiries were all green at 9/9, and the store had ZERO customer-authed
// readers — its only consumer was os_api, the staff console. The system was remembering things
// about the customer that the customer could neither see nor deny.
//
// TWO HALVES, KEPT VISIBLY APART. `inferred` is what we deduced from their past requests;
// `stated` is what they typed. They are never merged on screen, because a customer correcting an
// inference has to be able to see which of the two they are looking at. fn_customer_preference_learn
// merges stated OVER inferred and never lets an inference overwrite a typed answer — this surface
// just makes that visible.
import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';
import { SUPA_ANON, SUPA_FN } from '@/lib/supaEnv';

const L = (lang: string, en: string, ar: string) => (lang === 'ar' ? ar : en);
const S = {
  label: 'text-[11px] uppercase tracking-wide text-muted-foreground',
  sub: 'text-[12.5px] text-muted-foreground',
  err: 'text-[12.5px] text-destructive',
};

// The three the spec itself names. They are the FORM, not the STORE — anything already stated is
// rendered whatever its key, so a preference added later does not become invisible here.
const FIELDS = [
  ['supplier_locality', 'Supplier locality', 'موقع المورّد', 'local'],
  ['payment_terms', 'Payment terms', 'شروط الدفع', '60 days'],
  ['certification', 'Certification required', 'الشهادات المطلوبة', 'ISO'],
] as const;

const post = async (token: string, body: Record<string, unknown>) => {
  const r = await fetch(`${SUPA_FN}/customer_api`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token || SUPA_ANON}` },
    body: JSON.stringify(body),
  });
  return (await r.json().catch(() => null)) as Record<string, any> | null;
};

export function CustomerMemory({ token, lang = 'en' }: { token: string; lang?: string }) {
  const [stated, setStated] = useState<Record<string, string>>({});
  const [inferred, setInferred] = useState<Record<string, unknown>>({});
  const [updatedAt, setUpdatedAt] = useState<string | null>(null);
  const [err, setErr] = useState('');
  const [saved, setSaved] = useState('');
  const [busy, setBusy] = useState(false);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    let on = true;
    post(token, { action: 'preferences' })
      .then((j) => {
        if (!on) return;
        if (!j || j.error) { setErr(L(lang, 'Could not read what we remember.', 'تعذّرت قراءة ما نتذكّره.')); setLoaded(true); return; }
        const s = (j.stated || {}) as Record<string, unknown>;
        setStated(Object.fromEntries(Object.entries(s).map(([k, v]) => [k, String(v ?? '')])));
        setInferred((j.inferred || {}) as Record<string, unknown>);
        setUpdatedAt(j.updated_at || null);
        setLoaded(true);
      })
      .catch(() => { if (on) { setErr(L(lang, 'Could not read what we remember.', 'تعذّرت قراءة ما نتذكّره.')); setLoaded(true); } });
    return () => { on = false; };
  }, [token, lang]);

  const save = async () => {
    setBusy(true); setErr(''); setSaved('');
    const j = await post(token, { action: 'save_preferences', stated });
    setBusy(false);
    if (!j || j.error) { setErr(String(j?.error || L(lang, 'Could not save.', 'تعذّر الحفظ.'))); return; }
    setUpdatedAt(j.updated_at || null);
    setSaved(L(lang, 'Saved. Future requests use this.', 'تم الحفظ، وستُطبَّق على طلباتك القادمة.'));
  };

  const inferredRows = Object.entries(inferred).filter(([, v]) => v != null && String(v) !== '' && String(v) !== '[]');

  return (
    <Card className="p-3.5">
      <div className={S.label}>{L(lang, 'What we remember about you', 'ما نتذكّره عنك')}</div>
      <div className={cn(S.sub, 'mt-1')}>
        {L(lang, 'Learned from your past requests, and used automatically on new ones. Anything you type below overrides it.',
                 'مستخلَص من طلباتك السابقة ويُطبَّق تلقائيًا على الطلبات الجديدة، وما تكتبه أدناه يتقدّم عليه.')}
      </div>

      {err ? <div className={cn(S.err, 'mt-2')}>{err}</div> : null}
      {!loaded ? <div className={cn(S.sub, 'mt-2')}>{L(lang, 'Loading…', 'جارٍ التحميل…')}</div> : null}

      {loaded && inferredRows.length ? (
        <div className="mt-2.5">
          <div className={S.label}>{L(lang, 'Learned', 'مستخلَص')}</div>
          <div className="mt-1 flex flex-wrap gap-1.5">
            {inferredRows.map(([k, v]) => (
              <span key={k} className="rounded-full border border-border bg-secondary/25 px-2 py-0.5 text-[12px] text-foreground">
                {k.replace(/_/g, ' ')}: <span className="text-muted-foreground">{Array.isArray(v) ? (v as unknown[]).join(', ') : String(v)}</span>
              </span>
            ))}
          </div>
        </div>
      ) : loaded && !err ? (
        // customer_preference held zero rows on 14 Sep 2026, so this is every customer's state.
        <div className={cn(S.sub, 'mt-2.5')}>
          {L(lang, 'Nothing learned yet. This fills in from your requests.', 'لم نستخلص شيئًا بعد، وستتكوّن هذه المعلومات من طلباتك.')}
        </div>
      ) : null}

      {loaded ? (
        <div className="mt-3">
          <div className={S.label}>{L(lang, 'Your standing preferences', 'تفضيلاتك الثابتة')}</div>
          <div className="mt-1.5 grid grid-cols-1 gap-2 sm:grid-cols-3">
            {FIELDS.map(([key, en, arLabel, ph]) => (
              <label key={key} className="min-w-0">
                <span className={S.sub}>{L(lang, en, arLabel)}</span>
                <Input value={stated[key] ?? ''} placeholder={ph}
                       onChange={(e) => setStated((s) => ({ ...s, [key]: e.target.value }))}
                       className="mt-0.5" />
              </label>
            ))}
          </div>
          <div className="mt-2 flex items-center gap-2">
            <Button onClick={save} disabled={busy}>{busy ? L(lang, 'Saving…', 'جارٍ الحفظ…') : L(lang, 'Save', 'حفظ')}</Button>
            {saved ? <span className={S.sub}>{saved}</span> : null}
            {updatedAt ? <span className={cn(S.sub, 'ms-auto')}>{L(lang, 'Updated', 'آخر تحديث')} {new Date(updatedAt).toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB')}</span> : null}
          </div>
        </div>
      ) : null}
    </Card>
  );
}
