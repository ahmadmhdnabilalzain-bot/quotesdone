import type { Metadata } from 'next';
import { redirect } from 'next/navigation';
import { AdminTwoStep } from '@/components/admin/AdminTwoStep';

// THE ADMIN SIGN-IN SURFACE (security checklist audit 10 Nov 2026, open item 1; it_engineer).
//
// The OS console that used to hold the admin sign-in was removed on 8 Sep 2026 (#536, "anything related to OS can be
// removed"). Since then an admin session came from login_otp's `user_kind: 'admin'` with no screen of its own, and the
// ten admin doors accepted it on the e-mail alone. They now require a two-step (aal2) session and send an admin to
// THIS page to get one: e-mail code first, then the 6-digit code from an authenticator app, enrolled here the first
// time. It is a sign-in page only — no console, no data, no actions.
//
// English only, on purpose: it is used by the founder alone, never by a customer or a supplier, and the OS screens it
// replaces were English only. /ar/admin is sent to /admin rather than rendering an Arabic shell around English text.
// Not indexed (robots here and the X-Robots-Tag header from next.config.mjs), and nothing on the site links to it.
export const metadata: Metadata = {
  title: 'Admin sign-in · QuotesDone',
  description: 'Two-step sign-in for QuotesDone administrators.',
  robots: { index: false, follow: false },
};

export default async function AdminPage(p: { params: Promise<{ locale: string }> }) {
  if ((await p.params).locale === 'ar') redirect('/admin');
  return <AdminTwoStep />;
}
