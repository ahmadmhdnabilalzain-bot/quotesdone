import { setRequestLocale } from 'next-intl/server';
import { LegalDoc, metaFor } from '@/components/LegalDoc';
import { RevealGuarantee } from '@/components/me/RevealGuarantee';
import { SUPA_ANON, SUPA_FN } from '@/lib/supaEnv';

export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  return metaFor('refund-policy', locale);
}

// W4 (website audit, 14 Sep 2026): the guarantee ladder above the policy text, terms only — no fee
// (there is no quote on this page) and no clock. The working days come from pricing_config through
// public_site 'guarantee_terms', revalidated hourly; if that read fails the panel is simply absent
// and the policy text below still states the terms in full.
async function guaranteeTerms() {
  try {
    const r = await fetch(`${SUPA_FN}/public_site`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: SUPA_ANON, Authorization: `Bearer ${SUPA_ANON}` },
      body: JSON.stringify({ action: 'guarantee_terms' }),
      next: { revalidate: 3600 },
    });
    const j = await r.json();
    return j && j.ok ? j.terms : null;
  } catch { return null; }
}

export default async function Page(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  setRequestLocale(locale);
  const terms = await guaranteeTerms();
  const lang = locale === 'ar' ? 'ar' : 'en';
  return <LegalDoc slug="refund-policy" locale={locale} lead={terms ? <RevealGuarantee lang={lang} fee={null} terms={terms} /> : null} />;
}
