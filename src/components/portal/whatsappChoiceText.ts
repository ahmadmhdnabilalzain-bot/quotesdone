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
  // The eleven codes PR #858 added to kyc (review 22 Sep 2026). They were stabilised on the server
  // without being added here, so waErrorKey stopped matching and all eleven read as err_generic —
  // "something went wrong" for a wrong code, an expired code, a spent code and a suppressed address
  // alike, which is worse than the raw English they replaced.
  //
  // WHY THE WORDS ARE HERE AND NOT SHARED. supplier/serverCopy.ts already holds EN/AR for these, and
  // routing waErrorText through its srvText would be the smaller change — but serverCopy.ts imports
  // '@/lib/durationLabel', and WhatsAppChoice.test.mjs imports THIS file into bare node, where the
  // "@/" alias is ERR_MODULE_NOT_FOUND (measured 22 Sep 2026, node v24.16 — the same constraint
  // workspaceCopy.ts documents at its own AR_COUNTED table). Importing serverCopy here would break
  // every test in this file, so the wording is repeated and kept word-for-word identical to
  // serverCopy.ts's entries of the same name — except where the Arabic would have to carry Latin
  // script, which this file's test forbids: `bad_mobile` names the country code instead of the
  // «05X XXX XXXX» pattern, and `email_suppressed` says "support" instead of printing an address.
  err_enter_name: 'Please enter your name.',
  err_bad_mobile: 'Enter a valid UAE mobile number, including the country code, for example +971.',
  err_email_suppressed: 'We cannot email this address — it is on our do-not-send list because mail to it bounced or was unsubscribed. Please contact support and we will restore it.',
  err_enter_code: 'Enter the 6-digit code.',
  err_too_many_attempts: 'Too many attempts. Please request a new code.',
  err_resend_too_soon: 'A code is on its way. Please wait a few seconds before asking for another.',
  err_code_expired: 'That code has expired. Please request a new one.',
  err_code_burned: 'Too many incorrect attempts. Please request a new code.',
  err_sms_unavailable: 'SMS is not configured. Please contact us.',
  err_sms_rate_limited: 'Too many SMS codes were requested for this number in the last hour. Please wait and request a new one.',
  err_sms_send_failed: 'Could not send the code. Please try again in a minute.',
  err_unexpected_error: 'Something unexpected went wrong. Please try again.',
  err_generic: 'Something went wrong. Please try again.',
};
export type WaKey = keyof typeof EN;

// FORMAL PLURAL THROUGHOUT (audit 22 Sep 2026, SP-I-05). Every Arabic line here addressed one
// person informally — «رقمك»، «وثّق»، «اختر»، «حاول مرة أخرى» — while the rest of the portal
// addresses a company in the formal plural (كم). A supplier read «رقمك على WhatsApp» on the same
// screen as «رقم جوالكم الموثّق». Commands are verbal nouns after يُرجى, which is how the register
// in every_arabic_message_is_written_not_translated.test.mjs states a UI instruction.
const AR: Record<WaKey, string> = {
  q_title: 'هل هذا الرقم على WhatsApp؟',
  q_mobile_pre: 'هل الرقم ',
  q_mobile_post: ' هو رقمكم على WhatsApp أيضًا؟',
  q_sub: 'يمكننا موافاتكم بالمستجدات عبر WhatsApp إلى جانب البريد الإلكتروني، ويبقى بريدكم الإلكتروني وسيلة تسجيل الدخول.',
  mobile_label: 'رقم جوالكم الموثّق:',
  opt_same: 'نعم',
  opt_other: 'لا، رقمنا على WhatsApp مختلف',
  opt_none: 'لا نستخدم WhatsApp',
  continue: 'متابعة',
  saving: 'جارٍ الحفظ…',
  other_label: 'رقمكم على WhatsApp',
  other_ph: '+971 50 123 4567',
  send_code: 'إرسال الرمز',
  sending: 'جارٍ الإرسال…',
  code_sent: 'أرسلنا رمزًا من 6 أرقام إلى هذا الرقم عبر WhatsApp.',
  code_sent_sms: 'لا يمكن إيصال رموزنا عبر WhatsApp بعد، لذا أرسلنا الرمز المكوّن من 6 أرقام برسالة نصية إلى هذا الرقم.',
  code_label: 'رمز التحقق',
  verify: 'تأكيد',
  verifying: 'جارٍ التحقق…',
  change_number: 'استخدام رقم آخر',
  unavailable_h: 'التحقق عبر WhatsApp غير متاح بعد',
  unavailable_body: 'سنتواصل معكم في الوقت الحالي عبر البريد الإلكتروني والرسائل النصية، ويمكنكم توثيق هذا الرقم لاحقًا من الإعدادات.',
  later: 'التذكير لاحقًا',
  row_label: 'WhatsApp',
  cur_same: 'نفس رقم الجوال',
  cur_other: 'رقم WhatsApp موثّق',
  cur_pending: 'لم يُوثَّق الرقم بعد، لذا لا يُستخدم',
  cur_none: 'لا نستخدم WhatsApp',
  cur_unset: 'لا توجد إجابة بعد',
  change: 'تغيير',
  cancel: 'إلغاء',
  keep_note: 'يبقى رقمكم الحالي معتمدًا إلى أن يُوثَّق الرقم الجديد.',
  saved: 'تم الحفظ.',
  err_mobile_not_verified: 'يُرجى توثيق رقم جوالكم أولًا.',
  err_bad_opt: 'يُرجى اختيار إحدى الإجابات الثلاث.',
  err_bad_phone: 'لا يبدو هذا رقم جوال صحيحًا. يُرجى إضافة رمز الدولة، مثل ‎+971.',
  err_rate_limited: 'طُلب عدد كبير من الرموز. يُرجى الانتظار بضع دقائق ثم المحاولة مرة أخرى.',
  err_wrong_code: 'الرمز غير صحيح. يُرجى مراجعة رسالة WhatsApp والمحاولة مرة أخرى.',
  err_whatsapp_unavailable: 'التحقق عبر WhatsApp غير متاح بعد.',
  err_save_failed: 'تعذّر حفظ إجابتكم. يُرجى المحاولة مرة أخرى.',
  err_send_failed: 'تعذّر إرسال رمز WhatsApp. يُرجى المحاولة بعد قليل.',
  err_fixture_number: 'هذا رقم اختبار محجوز. لا يُرسَل إليه أي رمز، لذا لا يمكن التحقق منه.',
  err_email_not_sent: 'تعذّر إرسال الرمز عبر البريد الإلكتروني الآن. يُرجى المحاولة مرة أخرى بعد دقيقة.',
  // The eleven codes PR #858 added to kyc — see the English table above for why they are repeated
  // here rather than read from supplier/serverCopy.ts.
  err_enter_name: 'يُرجى إدخال اسمكم.',
  err_bad_mobile: 'يُرجى إدخال رقم جوال إماراتي صحيح مع رمز الدولة، مثل ‎+971.',
  err_email_suppressed: 'لا يمكننا الإرسال إلى هذا البريد الإلكتروني لأنه مُدرَج في قائمة عدم الإرسال بعد ارتداد رسائل سابقة أو إلغاء الاشتراك. يُرجى التواصل مع فريق الدعم لإعادة تفعيله.',
  err_enter_code: 'يُرجى إدخال الرمز المكوّن من ستة أرقام.',
  err_too_many_attempts: 'تجاوزتم عدد المحاولات المسموح به. يُرجى طلب رمز جديد.',
  err_resend_too_soon: 'الرمز في طريقه إليكم. يُرجى الانتظار بضع ثوانٍ قبل طلب رمز آخر.',
  err_code_expired: 'انتهت صلاحية هذا الرمز. يُرجى طلب رمز جديد.',
  err_code_burned: 'تكرّر إدخال رمز غير صحيح فلم يعد صالحًا. يُرجى طلب رمز جديد.',
  err_sms_unavailable: 'خدمة الرسائل النصية غير مهيّأة حاليًا. يُرجى التواصل معنا.',
  err_sms_rate_limited: 'طُلب عدد كبير من رموز الرسائل النصية لهذا الرقم خلال الساعة الماضية. يُرجى الانتظار قليلًا ثم طلب رمز جديد.',
  err_sms_send_failed: 'تعذّر إرسال الرمز. يُرجى المحاولة بعد دقيقة.',
  err_unexpected_error: 'حدث خطأ غير متوقع. يُرجى المحاولة مرة أخرى.',
  err_generic: 'حدث خطأ. يُرجى المحاولة مرة أخرى.',
};

export const WA_TEXT: Record<WaLang, Record<WaKey, string>> = { en: EN, ar: AR };
export const waText = (lang: WaLang, k: WaKey): string => (WA_TEXT[lang] || EN)[k] || EN[k];

// Every refusal code the kyc contract names. A code not in this list reads as the generic line rather
// than as a raw code on screen.
// Audit 21 Sep 2026, finding 31: kyc refuses a reserved fixture mobile with code `fixture_number`
// (_shared/demo_identity.ts FIXTURE_REFUSAL); it was missing here, so the reason read as "Something went
// wrong". WhatsAppChoice.test.mjs now reads every code kyc can answer and fails on one missing here.
// Review 22 Sep 2026: PR #858 stabilised eleven more kyc codes (enter_name … unexpected_error) and
// did not extend this list, so every one of them fell through to err_generic. They are here now, and
// the last test in WhatsAppChoice.test.mjs re-reads kyc so the next addition cannot slip the same way.
export const WA_ERROR_CODES = ['mobile_not_verified', 'bad_opt', 'bad_phone', 'rate_limited', 'wrong_code', 'whatsapp_unavailable', 'save_failed', 'send_failed', 'fixture_number', 'email_not_sent', 'enter_name', 'bad_mobile', 'email_suppressed', 'enter_code', 'too_many_attempts', 'code_expired', 'code_burned', 'sms_unavailable', 'sms_rate_limited', 'sms_send_failed', 'unexpected_error', 'resend_too_soon'] as const;

export function waErrorKey(j: any): WaKey {
  const c = j && (j.code || j.error);
  return (WA_ERROR_CODES as readonly string[]).includes(c) ? (('err_' + c) as WaKey) : 'err_generic';
}
export const waErrorText = (lang: WaLang, j: any): string => waText(lang, waErrorKey(j));

// send_code answers whatsapp_unavailable (in `error` per the contract; `code` accepted too) when the
// WhatsApp sender is not live. That is not the person's mistake, so it is not shown as an error:
// the flow says so plainly and lets signup continue.
export const waUnavailable = (j: any): boolean => !!j && (j.error === 'whatsapp_unavailable' || j.code === 'whatsapp_unavailable');

// The sign-up step is finished only when the server holds an answer (founder, 15 Sep 2026: "Sign-up
// cannot complete until this is answered"). There is no skip: a different number whose WhatsApp code
// cannot be delivered gets it by SMS instead (kyc whatsapp_send_code), so every path can finish.
export const waSignupSettled = (wa: WaState | null | undefined): boolean => !!(wa && wa.opt);

// The one-time dashboard card: only for an account that FINISHED sign-up (terms signed) and was never
// asked — i.e. accounts made before the question was part of sign-up. A new account cannot finish
// without answering, so it never sees the card; one still mid-registration sees the sign-up step instead.
export const waNeedsPrompt = (k: any): boolean => !!k && k.terms_signed === true && !!k.whatsapp && k.whatsapp.asked === false;

// The code went by SMS whenever kyc says a channel other than WhatsApp carried it.
export const waSentBySms = (j: any): boolean => !!j && !!j.channel && j.channel !== 'whatsapp';

// What Settings says the state is. A different number that is not verified is NOT shown as the
// WhatsApp number, because it is never used.
export function waCurrentKey(wa: WaState | null | undefined): WaKey {
  if (!wa || !wa.opt) return 'cur_unset';
  if (wa.opt === 'same') return 'cur_same';
  if (wa.opt === 'none') return 'cur_none';
  return wa.verified && wa.phone ? 'cur_other' : 'cur_pending';
}
