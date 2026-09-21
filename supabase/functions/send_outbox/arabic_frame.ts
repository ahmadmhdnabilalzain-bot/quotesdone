// The fixed English words of the customer/supplier email frame (templates.email_customer /
// email_supplier and send_outbox's fallback), in Arabic, with the page set right-to-left.
// Measured 14 Sep 2026: the two DB wrappers carry exactly "Dubai, UAE" and "Dubai DET E-Trader
// Licence" as English text; the fallback adds the listing sentence and the unsubscribe line.
// 21 Sep 2026 (founder instruction 586): the frame speaks the formal plural of UAE business
// correspondence, as the bodies do, and the signature line takes the Arabic comma.
// Tested in _shared/email_language.test.ts and send_outbox/supplier_mail.test.ts.
export function arabicFrame(html: string): string {
  return html
    .replace(/<html(\s|>)/i, '<html dir="rtl" lang="ar"$1')
    .split('>Unsubscribe</a> &middot; or reply to this email to be removed.').join('>إلغاء الاشتراك</a> &middot; أو الرد على هذه الرسالة لإزالة عنوانكم من القائمة.')
    .split('Dubai DET E-Trader Licence').join('رخصة تاجر إلكتروني - دائرة الاقتصاد والسياحة في دبي')
    .split('Dubai, UAE').join('دبي، الإمارات العربية المتحدة')
    .split(', QuotesDone</div>').join('، QuotesDone</div>')
    .split("You're receiving this because your business is publicly listed and may match clients sourcing on QuotesDone.").join('تصلكم هذه الرسالة لأن نشاطكم التجاري مُدرَج علنًا وقد يتوافق مع طلبات عملاء يبحثون عن موردين على QuotesDone.');
}
