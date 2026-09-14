'use client';
// "Get quotes for this" — pre-fills the category through the same /me?draft=1 hand-off BriefBox uses.
import { useRouter } from '@/i18n/routing';
import { saveDraft } from '@/lib/publicSite';

export function GetQuotesFor({ category, label }: { category: string; label: string }) {
  const router = useRouter();
  return (
    <button
      type="button"
      onClick={() => { saveDraft({ text: '', category, emirate: null }); router.push('/me?draft=1'); }}
      className="text-[13px] font-semibold text-teal-light underline-offset-4 hover:underline"
    >
      {label} <span aria-hidden className="inline-block rtl:rotate-180">&rarr;</span>
    </button>
  );
}
