import { setRequestLocale } from 'next-intl/server';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { ComplaintStatus } from '@/components/ComplaintStatus';
import { buildMeta } from '@/lib/seo';

export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  const ar = locale === 'ar';
  return buildMeta({ locale, path: '/complaints/status',
    title: ar ? 'حالة الشكوى' : 'Complaint status',
    description: ar
      ? 'تابع حالة شكواك برقم التذكرة: تم الاستلام، قيد المراجعة، الرد النهائي.'
      : 'Track your complaint by ticket number: acknowledged, in review, final response.' });
}

export default async function Page(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  setRequestLocale(locale);
  return (<><SiteHeader /><ComplaintStatus /><SiteFooter /></>);
}
