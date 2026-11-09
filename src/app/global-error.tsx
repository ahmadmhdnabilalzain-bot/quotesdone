'use client';

// THE LAST RESORT (launch-readiness audit, 9 Nov 2026). Next.js renders this only when the root layout
// itself throws — src/app/[locale]/error.tsx cannot catch that, because it renders inside the layout
// that failed. It replaces the whole document, so it carries its own <html> and <body>, uses no site
// CSS and no fonts (either may be what broke), and is bilingual on one page because the locale
// cannot be trusted at this point. Server errors are reported by src/instrumentation.ts.
export default function GlobalError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  const wrap: React.CSSProperties = { margin: 0, minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', background: '#0A1720', color: '#E8EEF2', fontFamily: 'system-ui, -apple-system, "Segoe UI", Tahoma, sans-serif' };
  const btn: React.CSSProperties = { marginTop: 16, padding: '8px 16px', borderRadius: 8, border: 0, background: '#2BB5A6', color: '#0A1720', fontWeight: 600, cursor: 'pointer' };
  return (
    <html lang="en">
      <body style={wrap}>
        <main style={{ maxWidth: 560, padding: 24 }}>
          <h1 style={{ fontSize: 24, margin: 0 }}>Something went wrong.</h1>
          <p style={{ opacity: 0.8 }}>It is our fault, not yours. Please try again.</p>
          <h2 dir="rtl" lang="ar" style={{ fontSize: 22, margin: '24px 0 0' }}>حدث خطأ.</h2>
          <p dir="rtl" lang="ar" style={{ opacity: 0.8 }}>نعتذر عن ذلك، فالخلل من جهتنا. يُرجى إعادة المحاولة.</p>
          <button type="button" onClick={() => reset()} style={btn}>Try again · إعادة المحاولة</button>
          {error.digest ? <p style={{ marginTop: 16, fontFamily: 'monospace', fontSize: 12, opacity: 0.6 }}>Reference: {error.digest}</p> : null}
        </main>
      </body>
    </html>
  );
}
