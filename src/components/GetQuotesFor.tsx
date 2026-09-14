'use client';
// "Get quotes for this" — pre-fills the category through the same /me?draft=1 hand-off BriefBox uses.
// /me ignores a draft whose text is empty, so the tile hands over a sentence in the visitor's
// language built from its own trade name (messages cats.draft: "I need {trade} work").
import { useRouter } from '@/i18n/routing';
import { saveDraft } from '@/lib/publicSite';

export function GetQuotesFor({ category, label, draft }: { category: string; label: string; draft: string }) {
  const router = useRouter();
  return (
    <button
      type="button"
      onClick={() => { saveDraft({ text: draft, category, emirate: null }); router.push('/me?draft=1'); }}
      className="text-[13px] font-semibold text-teal-light underline-offset-4 hover:underline"
    >
      {label} <span aria-hidden className="inline-block rtl:rotate-180">&rarr;</span>
    </button>
  );
}
