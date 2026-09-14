import { appShellMeta } from '@/lib/seo';
import { CustomerPortal } from '@/components/me/CustomerPortal';

// The portal is a signed-in shell: nothing on it belongs in a search index, and on /ar it was
// indexed under an English title (website audit 14 Sep 2026). appShellMeta is the platform's one
// definition of a signed-in shell's metadata — localised title, noindex — shared with /portal.
export async function generateMetadata(p: { params: Promise<{ locale: string }> }) {
  return appShellMeta((await p.params).locale, 'me');
}

export default function MePage() { return <CustomerPortal />; }
