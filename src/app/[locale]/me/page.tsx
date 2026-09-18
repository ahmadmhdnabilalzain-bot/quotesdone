import { appShellMeta } from '@/lib/seo';
import { CustomerPortal } from '@/components/me/CustomerPortal';
import { BootPrefetch } from '@/components/me/BootPrefetch';

// The portal is a signed-in shell: nothing on it belongs in a search index, and on /ar it was
// indexed under an English title (website audit 14 Sep 2026). appShellMeta is the platform's one
// definition of a signed-in shell's metadata — localised title, noindex — shared with /portal.
export async function generateMetadata(p: { params: Promise<{ locale: string }> }) {
  return appShellMeta((await p.params).locale, 'me');
}

// BootPrefetch FIRST, and deliberately: it is an inline script whose whole value is running before
// the portal's client bundle has downloaded. See its header for the measurement.
export default function MePage() { return <><BootPrefetch /><CustomerPortal /></>; }
