// THE ONE-TIME CODE EMAIL, in the person's registered language (14 Sep 2026, agent: customer_support).
// login_otp (sign-in) and kyc (email confirmation) each carried a near-identical copy of this; one
// builder now serves both, and code_email.test.ts proves the Arabic version carries no English.
const LOGO = 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/icon_192.png';

const COPY = {
  signin: {
    en: { subject: 'Your QuotesDone sign-in code', title: 'Your sign-in code', lead: 'Enter this code to sign in to QuotesDone. It expires in 10 minutes.', ignore: "If you didn't request this, you can ignore this email.", foot: 'QuotesDone Technologies · Dubai, UAE' },
    ar: { subject: 'رمز تسجيل الدخول إلى QuotesDone', title: 'رمز تسجيل الدخول', lead: 'يُرجى إدخال هذا الرمز لتسجيل الدخول إلى QuotesDone، علمًا بأن صلاحيته تنتهي خلال 10 دقائق.', ignore: 'إن لم تطلبوا هذا الرمز، يُرجى تجاهل هذه الرسالة.', foot: 'QuotesDone · دبي، الإمارات العربية المتحدة' },
  },
  confirm: {
    en: { subject: 'Confirm your QuotesDone email', title: 'Confirm your email', lead: 'Enter this code to confirm your email on QuotesDone. It expires in 10 minutes.', ignore: '', foot: '' },
    ar: { subject: 'تأكيد بريدكم الإلكتروني لدى QuotesDone', title: 'تأكيد البريد الإلكتروني', lead: 'يُرجى إدخال هذا الرمز لتأكيد بريدكم الإلكتروني لدى QuotesDone، علمًا بأن صلاحيته تنتهي خلال 10 دقائق.', ignore: '', foot: '' },
  },
} as const;

export function codeEmail(purpose: 'signin' | 'confirm', code: string, ar: boolean): { subject: string; html: string } {
  const c = COPY[purpose][ar ? 'ar' : 'en'];
  const html = `<div dir="${ar ? 'rtl' : 'ltr'}" lang="${ar ? 'ar' : 'en'}" style="font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;max-width:480px;margin:0 auto;color:#1f2937">`
    + `<div style="text-align:center;padding:18px 0"><img src="${LOGO}" width="44" height="44" alt="QuotesDone"></div>`
    + `<div style="background:#fff;border:1px solid #eef0f2;border-radius:14px;padding:26px;text-align:center">`
    + `<h1 style="font-size:19px;color:#111827;margin:0 0 8px">${c.title}</h1>`
    + `<p style="font-size:14px;color:#6b7280;margin:0 0 16px">${c.lead}</p>`
    // 22 Sep 2026 (DL-09): #0d9488 on #f0fdfa is the retired teal, in nothing else the company sends.
    // The code block now uses the brand ink on the brand tint, and the font stack is the one every
    // other email uses (Arial first: Segoe UI renders Arabic digits and letters unevenly in Outlook).
    + `<div dir="ltr" style="font-family:Arial,Tahoma,Helvetica,sans-serif;font-size:34px;font-weight:800;letter-spacing:8px;color:#0C2330;background:#EAF4F2;border-radius:12px;padding:14px 0">${code}</div>`
    + (c.ignore ? `<p style="font-size:12px;color:#9aa1ab;margin-top:16px">${c.ignore}</p>` : '')
    + `</div>`
    + (c.foot ? `<p style="text-align:center;font-size:11px;color:#9aa1ab;margin-top:14px">${c.foot}</p>` : '')
    + `</div>`;
  return { subject: c.subject, html };
}
