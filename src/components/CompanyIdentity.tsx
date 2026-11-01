import company from '@/content/company.json';

// One identity block, rendered from src/content/company.json in the footer and on the contact, privacy
// and about pages, so the legal name, licence, register number, the two phone numbers and the working
// week can never disagree between pages or languages (website audit, 14 Sep 2026: two unexplained phone
// numbers and a Sun–Thu contact week against a Mon–Fri refund clock).
// No hooks, so it renders inside both server and client components.
type Loc = 'en' | 'ar';
const C = company;

export function CompanyIdentity({ locale, variant = 'card', rights }: { locale: string; variant?: 'card' | 'footer'; rights?: string }) {
  const l: Loc = locale === 'ar' ? 'ar' : 'en';
  const licence = <>{C.licence[l]} <bdi dir="ltr">{C.licence_no}</bdi></>;
  const phone = <a href={'https://wa.me/' + C.phone.tel.replace('+', '')} dir="ltr">{C.phone.number}</a>;
  const licencePhone = <a href={'tel:' + C.licence_phone.tel} dir="ltr">{C.licence_phone.number}</a>;
  const email = <a href={'mailto:' + C.email} dir="ltr">{C.email}</a>;

  if (variant === 'footer') {
    return (
      <div className="space-y-1.5">
        <p>
          © {new Date().getFullYear()} {C.legal_name} · {C.form[l]} · {licence} · {C.city[l]}
          {rights ? <> · {rights}</> : null}
        </p>
        <p>
          {C.licence_class[l]} · {phone} · {email} · {C.working_days[l]}
        </p>
      </div>
    );
  }

  const row = (k: string, v: React.ReactNode) => (
    <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', padding: '6px 0', borderTop: '1px solid var(--line, rgba(255,255,255,.08))' }}>
      <dt style={{ minWidth: 150, opacity: 0.7 }}>{k}</dt>
      <dd style={{ margin: 0, flex: 1 }}>{v}</dd>
    </div>
  );
  return (
    <section
      aria-labelledby="qd-company"
      dir={l === 'ar' ? 'rtl' : 'ltr'}
      style={{ maxWidth: 880, margin: '28px auto', padding: '18px 20px', border: '1px solid var(--line2, rgba(255,255,255,.14))', borderRadius: 14, fontSize: 14, lineHeight: 1.6 }}
    >
      <h2 id="qd-company" style={{ fontSize: 17, margin: '0 0 10px' }}>{C.heading[l]}</h2>
      <p style={{ margin: '0 0 10px', opacity: 0.85 }}>{C.licence_class[l]}</p>
      <dl style={{ margin: 0 }}>
        {row(C.legal_name, C.form[l])}
        {row(l === 'ar' ? 'الرخصة' : 'Licence', licence)}
        {row(C.address_label[l], C.city[l])}
        {row(C.phone.label[l], <>{phone} <span style={{ opacity: 0.7 }}>· {C.licence_phone.label[l]}: {licencePhone}</span></>)}
        {row(C.email_label[l], email)}
        {row(C.hours_label[l], <>{C.hours[l]}. {C.working_days[l]}</>)}
      </dl>
    </section>
  );
}
