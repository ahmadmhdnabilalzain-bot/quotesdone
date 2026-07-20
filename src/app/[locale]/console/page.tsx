import OsxShell from '@/components/osx/OsxShell';
export const dynamic = 'force-dynamic';
export const metadata = { title: 'QuotesDone Console', robots: { index: false, follow: false } };
export default function ConsolePage() { return <OsxShell />; }
