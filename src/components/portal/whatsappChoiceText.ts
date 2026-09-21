// whatsappChoiceText.ts — the words and the decisions of the "Is this number on WhatsApp?" question.
//
// FOUNDER, 14 Sep 2026: "what if the customer has whatsapp on another phone number, maybe we should
// confirm this point through the sign up". After the mobile is verified, customers AND suppliers are
// asked, with three answers: yes this number / no, a different number / I don't use WhatsApp. A
// different number is verified by a code sent over WhatsApp itself; an unverified number is never used.
// Email stays the identity — nothing here signs anybody in.
//
// Kept apart from WhatsAppChoice.tsx so node --test can import it (node strips types from .ts, it
// cannot compile JSX). The component holds no copy and no rules of its own; this file does.
// The Arabic carries no English words: only the brand names QuotesDone and WhatsApp stay in Latin
// script, and whatsappChoiceText.test asserts it.

export type WaLang = 'en' | 'ar';
export type WaOpt = 'same' | 'other' | 'none';
export type WaMode = 'signup' | 'prompt' | 'settings';
// What kyc action='state' serves under `whatsapp` (contract with the kyc edge function, 14 Sep 2026).
export type WaState = { opt: WaOpt | null; phone: string | null; verified: boolean; asked: boolean };

const EN = {
  q_title: 'Is this number on WhatsApp?',
  // Sign-up and the dashboard card name the number (founder, 15 Sep 2026): "Is <mobile> also your
  // WhatsApp number?". Two halves around the number, so the Arabic needs no Latin placeholder.
  q_mobile_pre: 'Is ',
  q_mobile_post: ' also your WhatsApp number?',
  q_sub: 'We can send your updates on WhatsApp as well as by email. Your email stays how you sign in.',
  mobile_label: 'Your verified mobile:',
  opt_same: 'Yes',
  opt_other: 'No, my WhatsApp is a different number',
  opt_none: 'I do not use WhatsApp',
  continue: 'Continue',
  saving: 'Saving…',
  other_label: 'Your WhatsApp number',
  other_ph: '+971 50 123 4567',
  send_code: 'Send code',
  sending: 'Sending…',
  code_sent: 'We sent a 6-digit code to this number on WhatsApp.',
  // Said whenever the code did not travel on WhatsApp — Verify refused it, or delivered by SMS itself.
  code_sent_sms: 'WhatsApp cannot deliver our codes yet, so we sent the 6-digit code by SMS to this number.',
  code_label: 'Verification code',
  verify: 'Verify',
  verifying: 'Verifying…',
  change_number: 'Use a different number',
  unavailable_h: 'WhatsApp verification is not available yet',
  unavailable_body: 'We will use email and SMS meanwhile. You can verify this number later in Settings.',
  later: 'Ask me later',
  row_label: 'WhatsApp',
  cur_same: 'Same as your mobile',
  cur_other: 'Verified WhatsApp number',
  cur_pending: 'Number not verified yet, so it is not used',
  cur_none: 'Not using WhatsApp',
  cur_unset: 'Not answered yet',
  change: 'Change',
  cancel: 'Cancel',
  keep_note: 'Your current number stays in use until the new one is verified.',
  saved: 'Saved.',
  err_mobile_not_verified: 'Verify your mobile number first.',
  err_bad_opt: 'Choose one of the three answers.',
  err_bad_phone: 'That does not look like a mobile number. Include the country code, for example +971.',
  err_rate_limited: 'Too many codes were requested. Wait a few minutes and try again.',
  err_wrong_code: 'That code is not correct. Check the WhatsApp message and try again.',
  err_whatsapp_unavailable: 'WhatsApp verification is not available yet.',
  err_save_failed: 'Your answer could not be saved. Please try again.',
  err_send_failed: 'The WhatsApp code could not be sent. Please try again in a moment.',
  err_fixture_number: 'This is a reserved test number. No code is ever sent to it, so none can be checked.',
  err_email_not_sent: 'We could not send the code by email just now. Please try again in a minute.',
  err_generic: 'Something went wrong. Please try again.',
};
export type WaKey = keyof typeof EN;

const AR: Record<WaKey, string> = {
  q_title: 'هل هذا الرقم على WhatsApp؟',
  q_mobile_pre: 'هل الرقم ',
  q_mobile_post: ' هو أيضًا رقم WhatsApp الخاص بك؟',
  q_sub: 'يمكننا إرسال تحديثاتك على WhatsApp إلى جانب البريد الإلكتروني. يبقى بريدك هو وسيلة الدخول.',
  mobile_label: 'رقم جوالك الموثّق:',
  opt_same: 'نعم',
  opt_other: 'لا، رقم WhatsApp الخاص بي مختلف',
  opt_none: 'لا أستخدم WhatsApp',
  continue: 'متابعة',
  saving: 'جارٍ الحفظ…',
  other_label: 'رقم WhatsApp الخاص بك',
  other_ph: '+971 50 123 4567',
  send_code: 'أرسل الرمز',
  sending: 'جارٍ الإرسال…',
  code_sent: 'أرسلنا رمزًا من ٦ أرقام إلى هذا الرقم على WhatsApp.',
  code_sent_sms: 'لا يستطيع WhatsApp إيصال رموزنا بعد، لذلك أرسلنا الرمز المكوّن من ٦ أرقام برسالة نصية إلى هذا الرقم.',
  code_label: 'رمز التحقق',
  verify: 'تحقّق',
  verifying: 'جارٍ التحقق…',
  change_number: 'استخدم رقمًا آخر',
  unavailable_h: 'التحقق عبر WhatsApp غير متاح بعد',
  unavailable_body: 'سنستخدم البريد الإلكتروني والرسائل النصية في الأثناء، ويمكنك توثيق هذا الرقم لاحقًا من الإعدادات.',
  later: 'اسألني لاحقًا',
  row_label: 'WhatsApp',
  cur_same: 'نفس رقم الجوال',
  cur_other: 'رقم WhatsApp موثّق',
  cur_pending: 'الرقم غير موثّق بعد، لذلك لا يُستخدم',
  cur_none: 'لا أستخدم WhatsApp',
  cur_unset: 'لم تتم الإجابة بعد',
  change: 'تغيير',
  cancel: 'إلغاء',
  keep_note: 'يبقى رقمك الحالي مستخدمًا حتى يتم توثيق الرقم الجديد.',
  saved: 'تم الحفظ.',
  err_mobile_not_verified: 'وثّق رقم جوالك أولًا.',
  err_bad_opt: 'اختر إحدى الإجابات الثلاث.',
  err_bad_phone: 'هذا لا يبدو رقم جوال. أضف رمز الدولة، مثل +971.',
  err_rate_limited: 'طُلبت رموز كثيرة. انتظر بضع دقائق ثم حاول مرة أخرى.',
  err_wrong_code: 'الرمز غير صحيح. راجع رسالة WhatsApp وحاول مرة أخرى.',
  err_whatsapp_unavailable: 'التحقق عبر WhatsApp غير متاح بعد.',
  err_save_failed: 'تعذّر حفظ إجابتك. يُرجى المحاولة مرة أخرى.',
  err_send_failed: 'تعذّر إرسال رمز WhatsApp. يُرجى المحاولة بعد قليل.',
  err_fixture_number: 'هذا رقم اختبار محجوز. لا يُرسَل إليه أي رمز، لذا لا يمكن التحقق منه.',
  err_email_not_sent: 'تعذّر إرسال الرمز عبر البريد الإلكتروني الآن. يُرجى المحاولة مرة أخرى بعد دقيقة.',
  err_generic: 'حدث خطأ. يُرجى المحاولة مرة أخرى.',
};

export const WA_TEXT: Record<WaLang, Record<WaKey, string>> = { en: EN, ar: AR };
export const waText = (lang: WaLang, k: WaKey): string => (WA_TEXT[lang] || EN)[k] || EN[k];

// Every refusal code the kyc contract names. A code not in this list reads as the generic line rather
// than as a raw code on screen.
// Audit 21 Sep 2026, finding 31: kyc refuses a reserved fixture mobile with code `fixture_number`
// (_shared/demo_identity.ts FIXTURE_REFUSAL); it was missing here, so the reason read as "Something went
// wrong". WhatsAppChoice.test.mjs now reads every code kyc can answer and fails on one missing here.
export const WA_ERROR_CODES = ['mobile_not_verified', 'bad_opt', 'bad_phone', 'rate_limited', 'wrong_code', 'whatsapp_unavailable', 'save_failed', 'send_failed', 'fixture_number', 'email_not_sent'] as const;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function waErrorKey(j: any): WaKey {
  const c = j && (j.code || j.error);
  return (WA_ERROR_CODES as readonly string[]).includes(c) ? (('err_' + c) as WaKey) : 'err_generic';
}
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const waErrorText = (lang: WaLang, j: any): string => waText(lang, waErrorKey(j));

// send_code answers whatsapp_unavailable (in `error` per the contract; `code` accepted too) when the
// WhatsApp sender is not live. That is not the person's mistake, so it is not shown as an error:
// the flow says so plainly and lets signup continue.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const waUnavailable = (j: any): boolean => !!j && (j.error === 'whatsapp_unavailable' || j.code === 'whatsapp_unavailable');

// The sign-up step is finished only when the server holds an answer (founder, 15 Sep 2026: "Sign-up
// cannot complete until this is answered"). There is no skip: a different number whose WhatsApp code
// cannot be delivered gets it by SMS instead (kyc whatsapp_send_code), so every path can finish.
export const waSignupSettled = (wa: WaState | null | undefined): boolean => !!(wa && wa.opt);

// The one-time dashboard card: only for an account that FINISHED sign-up (terms signed) and was never
// asked — i.e. accounts made before the question was part of sign-up. A new account cannot finish
// without answering, so it never sees the card; one still mid-registration sees the sign-up step instead.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const waNeedsPrompt = (k: any): boolean => !!k && k.terms_signed === true && !!k.whatsapp && k.whatsapp.asked === false;

// The code went by SMS whenever kyc says a channel other than WhatsApp carried it.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const waSentBySms = (j: any): boolean => !!j && !!j.channel && j.channel !== 'whatsapp';

// What Settings says the state is. A different number that is not verified is NOT shown as the
// WhatsApp number, because it is never used.
export function waCurrentKey(wa: WaState | null | undefined): WaKey {
  if (!wa || !wa.opt) return 'cur_unset';
  if (wa.opt === 'same') return 'cur_same';
  if (wa.opt === 'none') return 'cur_none';
  return wa.verified && wa.phone ? 'cur_other' : 'cur_pending';
}
