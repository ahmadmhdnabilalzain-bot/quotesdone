// The fixed English words of the customer/supplier email frame (templates.email_customer /
// email_supplier and send_outbox's fallback), in Arabic, with the page set right-to-left.
// Measured 14 Sep 2026: the two DB wrappers carry exactly "Dubai, UAE" and "Dubai DET E-Trader
// Licence" as English text; the fallback adds the listing sentence and the unsubscribe line.
// 21 Sep 2026 (founder instruction 586): the frame speaks the formal plural of UAE business
// correspondence, as the bodies do, and the signature line takes the Arabic comma.
// Tested in _shared/email_language.test.ts and send_outbox/supplier_mail.test.ts.
import { UNSUBSCRIBE_MAILBOX } from '../_shared/unsubscribe_mailbox.ts';
export function arabicFrame(html: string): string {
  return html
    .replace(/<html(\s|>)/i, '<html dir="rtl" lang="ar"$1')
    .split(`>Unsubscribe</a> &middot; or email ${UNSUBSCRIBE_MAILBOX} to be removed.`).join(`>إلغاء الاشتراك</a> &middot; أو مراسلة ${UNSUBSCRIBE_MAILBOX} لإزالة عنوانكم من القائمة.`)
    // 22 Sep 2026 (DL-06): the corrected footer, and the old one kept until the DB template carries
    // the new words — for the minutes between this deploy and that apply, a supplier wrapper still
    // says "Dubai DET E-Trader Licence", and an untranslated English line in an Arabic mail is worse
    // than a line whose wording the next apply corrects.
    .split('DET Trader Licence No. 1633275').join('رخصة تاجر رقم 1633275 – دائرة الاقتصاد والسياحة في دبي')
    .split('TDRA NOL-26-100000665').join('خطاب عدم ممانعة هيئة تنظيم الاتصالات والحكومة الرقمية NOL-26-100000665')
    .split('Dubai DET E-Trader Licence').join('رخصة تاجر إلكتروني - دائرة الاقتصاد والسياحة في دبي')
    .split('Dubai, UAE').join('دبي، الإمارات العربية المتحدة')
    .split(', QuotesDone</div>').join('، QuotesDone</div>')
    .split("You're receiving this because your business is publicly listed and may match clients sourcing on QuotesDone.").join('تصلكم هذه الرسالة لأن نشاطكم التجاري مُدرَج علنًا وقد يتوافق مع طلبات عملاء يبحثون عن موردين على QuotesDone.');
}
