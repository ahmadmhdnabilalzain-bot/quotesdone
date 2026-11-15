// customer_question_kit: the one way a plain-wording entry is written (customer_questions_*.ts). Positional so that a table of
// ~1,500 entries stays readable: q(english, arabic, [example en, ar]?, [alternative en, ar]?, [[option en, ar], ...]?).
// The example is introduced here ("For example:" / "مثلًا:"), so an entry never repeats the lead-in.
// ARABIC REGISTER (native review of 15 Nov 2026, sales_engineer Arabic editor): the customer is addressed in the formal plural
// (هل تريدون، لديكم، أرسلوا، أخبرونا) — the register of scripts/checks/every_arabic_message_is_written_not_translated.test.mjs —
// because the customer may be a household, a facility manager or a company; an option is the customer's own voice (نعم، سأرسله).
// "Not sure? ..." reads «إن لم تكونوا متأكدين ف...» and "No idea? ..." «إن لم تعرفوا ف...»; trade words are the ones UAE customers
// say, in Arabic letters (سبليت، ممبرين، شتر، ميزانين، بمواصفات خليجية). customer_questions.test.ts holds the register.
import type { CustomerQuestion } from './customer_questions.ts';

type Pair = readonly [en: string, ar: string];
export const q = (en: string, ar: string, eg?: Pair | null, alt?: Pair | null, options?: readonly Pair[] | null): CustomerQuestion => ({
  en, ar,
  ...(eg ? { eg_en: `For example: ${eg[0]}`, eg_ar: `مثلًا: ${eg[1]}` } : {}),
  ...(alt ? { alt_en: alt[0], alt_ar: alt[1] } : {}),
  ...(options?.length ? { options } : {}),
});

/** The two alternatives that fit most "do you know this?" specs. */
export const SUPPLIER_ADVISES: Pair = ['If you are not sure, the supplier will advise.', 'إن لم تكونوا متأكدين فسيقترح المورّد المناسب.'];
export const PHOTO_OF_LABEL: Pair = ['A photo of the label or the existing one also works.', 'صورة الملصق أو القطعة الحالية تكفي أيضًا.'];
export const SITE_VISIT: Pair = ['If you cannot measure, the supplier can visit and measure on site.', 'إن لم تستطيعوا القياس فيمكن للمورّد زيارة الموقع وقياسه.'];
export const DRAWING_OR_PHOTOS: Pair = ['A drawing, or photos of the place, also works.', 'مخطط أو صور للمكان تكفي أيضًا.'];
export const PICTURE_OF_IDEA: Pair = ['A picture of what you like also works.', 'صورة لما يعجبكم تكفي أيضًا.'];
export const YES_NO: readonly Pair[] = [['Yes', 'نعم'], ['No', 'لا']];
export const NO_PREFERENCE: readonly Pair[] = [['No preference', 'لا تفضيل']];
export const SUPPLY_OR_INSTALL: readonly Pair[] = [['Supply only', 'توريد فقط'], ['Supply and install', 'توريد وتركيب']];
