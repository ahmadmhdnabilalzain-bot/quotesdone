// SHOULD THIS STRING BE FORCED LEFT-TO-RIGHT?
//
// The predicate behind <Ltr> (src/lib/Ltr.tsx), split out here as plain TypeScript with no JSX so
// it can be unit-tested directly — ltrDirection.test.mjs. The component is a one-line wrapper over
// it; there is one rule and one place that holds it.
//
// THE RULE. Force `dir="ltr"` only for a string that is GENUINELY left-to-right — a number, an
// amount, a job number, an ID, a phone number, an e-mail, a URL. NEVER for a localised date or any
// text carrying right-to-left script. A localised Arabic date ("18 سبتمبر 2026") laid out as an LTR
// paragraph is reordered by the bidi algorithm and reads backwards; that was the defect, measured at
// eleven call sites on 17 Sep 2026, and the supplier licence chip showed "سبتمبر 2027 18".
//
// WHY NOT JUST `dir="auto"` EVERYWHERE. `dir="auto"` takes its base direction from the first STRONG
// directional character. Digits and punctuation are bidi-neutral (EN/AN class, not strong), so a
// string of nothing but digits and separators — "+971 50 931 9355", "AED 12,500" — has no strong
// character at all and inherits the page's RTL, which lays its groups out right-to-left. Those need
// the force. So the test is "does this carry strong RTL script", not "does this look Arabic".
//
// THE DIGITS ARE NOT STRONG, AND THAT IS THE TRAP. Arabic-Indic digits (U+0660–0669) and their
// Extended form (U+06F0–06F9) sit INSIDE the Arabic block U+0600–06FF, so a naive block test calls
// "+٩٧١ ٥٠ ٩٣١ ٩٣٥٥" right-to-left and sends the one string shape the force exists for down the
// `auto` path, where it scrambles. They are AN/EN class and carry no direction, so they — and the
// Arabic thousands/decimal separators and a stray BOM, all neutrals in RTL blocks — are removed
// before the test. Latin digits render correctly in Arabic today (toLocaleDateString('ar-AE')
// returns "18 سبتمبر 2026", measured), so this is a latent trap rather than a live bug; it becomes
// live the moment a locale, a `-u-nu-arab` numbering system or a stored phone number uses them.

// Arabic, Arabic Supplement/Extended, Syriac, Thaana, Hebrew, and the Arabic Presentation Forms —
// the RTL blocks a QuotesDone string can plausibly contain.
const RTL = /[֐-׿؀-ۿ܀-ݏݐ-ݿ߀-߿ހ-޿ࢠ-ࣿיִ-﷿ﹰ-﻿]/;

// Characters that live in those blocks but carry NO direction of their own: Arabic-Indic digits,
// Extended Arabic-Indic digits, the Arabic decimal/thousands separators and percent/permille signs,
// the end-of-ayah and number marks, and the zero-width no-break space (BOM), which is in FE70–FEFF
// and would otherwise flip the branch for a filename someone pasted with one on the front.
const NEUTRAL_IN_RTL_BLOCKS = /[٠-٩۰-۹٫٬٪۝؀-؅﻿]/g;

/** True when the string carries strong right-to-left script — so it must NOT be forced to LTR. */
export const isRtlText = (s: string): boolean => RTL.test(s.replace(NEUTRAL_IN_RTL_BLOCKS, ''));

/** The `dir` a <bdi> should carry for this text. `auto` lets the first strong character decide. */
export const dirFor = (s: string): 'ltr' | 'auto' => (isRtlText(s) ? 'auto' : 'ltr');
