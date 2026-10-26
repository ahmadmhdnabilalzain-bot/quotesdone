'use client';
// "Get quotes for this" — pre-fills the category through the same /me?draft=1 hand-off BriefBox uses.
// /me ignores a draft whose text is empty, so the tile hands over a sentence in the visitor's
// language built from its own trade name (messages cats.draft: "I need {trade} work").
import { useTransition } from 'react';
import { useRouter } from '@/i18n/routing';
import { saveDraft } from '@/lib/publicSite';
import { Spinner, useDelayedFlag } from '@/components/ui/busy';
import { startRouteProgress } from '@/components/ui/route-progress';

export function GetQuotesFor({ category, label, draft }: { category: string; label: string; draft: string }) {
  const router = useRouter();
  // /me is one of the two heaviest client bundles on the site; this jump was silent until it landed.
  const [pending, start] = useTransition();
  const shown = useDelayedFlag(pending);
  return (
    <button
      type="button"
      disabled={pending}
      aria-busy={shown || undefined}
      onClick={() => {
        saveDraft({ text: draft, category, emirate: null });
        startRouteProgress();
        start(() => router.push('/me?draft=1'));
      }}
      className="inline-flex items-center gap-1.5 text-[13px] font-semibold text-teal-light underline-offset-4 hover:underline disabled:cursor-progress"
    >
      {label} {shown ? <Spinner /> : <span aria-hidden className="inline-block rtl:rotate-180">&rarr;</span>}
    </button>
  );
}
