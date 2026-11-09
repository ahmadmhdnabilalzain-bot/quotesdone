// @ts-nocheck
'use client';
import { cn } from '@/lib/utils';
import { CompanyTwin } from '@/components/portal/twin';
import { ArrowRight } from 'lucide-react';
import { t } from '../portalText';
import { ProjectsModule, SpatialModule, DocumentVault, CommunicationCenter, OrdersList, PredictiveIntelligence, SupplierDiscovery, CustomerMemory } from './lazyModules';
import { AccountSettings } from './AccountSettings';

// The §22 module list, in the order a customer meets them. The Messages/Thread pair that used to
// live in this file is gone: CommunicationCenter serves the same four messages_api actions and adds
// the documents that belong to each conversation plus an explicit statement of which channels the
// inbox does and does not carry, so keeping both would have been two inboxes disagreeing.
const MODULES = [
  ['projects', 'projects'], ['spatial', 'mod_spatial'], ['documents', 'mod_documents'],
  ['messages', 'messages'], ['orders', 'mod_orders'],
  ['predict', 'mod_predict'], ['profile', 'mod_profile'], ['account', 'mod_account'],
];
// A MODULE IS A PAGE NOW, NOT A POP-UP.
//
// These opened as a Dialog over the dashboard, and the reason was sound at the time: navigating to
// a module used to REPLACE the whole screen, which unmounted the KPIs and stranded the intake
// assistant, so a window that floated above kept them alive underneath.
//
// The shell removes that constraint. The sidebar, the top bar and the assistant persist across
// every destination, so a module can own the main region without unmounting anything the customer
// needs — and a sidebar item that opens a modal is the tell that a screen is a dashboard wearing an
// application's clothes. Nothing here fetches: each surface still owns its endpoint, its loading
// state and its empty state.
function ModuleWindow({ id, onClose, onOpenRfq, projectId, token, lang, inqs, onChanged, twin }) {
  const l2 = lang === 'ar' ? 'ar' : 'en';
  const rtl = lang === 'ar';
  const entry = MODULES.find((m) => m[0] === id);
  if (!entry) return null;
  return (<section className="mx-auto w-full max-w-[1240px] px-4 py-5 sm:px-6">
    <div className="mb-4 flex items-center gap-3">
      <button type="button" onClick={onClose}
        className="grid h-9 w-9 shrink-0 place-items-center rounded-xl border border-border text-muted-foreground transition-colors hover:bg-secondary/50 hover:text-foreground focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring"
        aria-label={t(lang, 'nav_overview')}>
        <ArrowRight className={cn('h-4 w-4', !rtl && 'rotate-180')} aria-hidden />
      </button>
      <h1 className="font-head text-[20px] font-extrabold tracking-tight text-foreground">{t(lang, entry[1])}</h1>
    </div>
    <div className="flex flex-col gap-3">
      {/* onOpenRfq is Dashboard's openRfq: each of these hands back an inquiries.id and that request
          opens. It was onClose, which discarded the id and showed the Overview. */}
      {/* linkableRfqs: requests not already in a project. Offering all of them let "Link" silently
          move a request out of another project (project_api link overwrites inquiries.project_id). */}
      {id === 'projects' && <ProjectsModule token={token} lang={l2} initialProjectId={projectId || undefined} linkableRfqs={inqs.filter((i) => !i.project_id).map((i) => ({ id: i.id, summary: i.summary, category: i.category }))} onOpenRfq={onOpenRfq} onChanged={onChanged} />}
      {id === 'spatial' && <SpatialModule token={token} lang={l2} inquiries={inqs} onOpenRfq={onOpenRfq} />}
      {id === 'documents' && <DocumentVault token={token} lang={l2} />}
      {id === 'messages' && <CommunicationCenter token={token} lang={l2} onOpenRfq={onOpenRfq} />}
      {id === 'orders' && <OrdersList token={token} lang={l2} onOpenRfq={onOpenRfq} />}
      {id === 'predict' && <PredictiveIntelligence token={token} lang={l2} />}
      {/* §2 the twin, §9 discovery and §17 the memory — three surfaces whose backends were complete
          and whose only reader was os_api, the staff console. They share one window because they
          are one subject: what the system knows about this customer and what it does with it.

          WHY A "COMPANY PROFILE" WAS ON A BUYER'S SCREEN, AND WHY IT IS NOW A BUYING PROFILE
          (13 Aug 2026, asked directly by the founder: "A customer is a person buying a service. A
          company profile is a supplier concept — trade licence, products, services, catalogues. On
          a customer's screen it is at best noise and at worst asking for personal or business data
          we have no reason to hold. My instinct is: take it out.")

          The instinct was right about the LABEL and wrong about the PANEL, and the difference is
          worth writing down because the label is what he saw. Opened at 1280 signed in as a real
          customer, every field on this window is measured:

            CompanyTwin        read-only. industry, live projects, suppliers this customer has PAID
                               to reveal, the categories they actually buy.
                               No input of any kind. Nothing writes customers.industry from any
                               customer surface - grepped customer_api and kyc, no writer exists.
            SupplierDiscovery  a text box for trades + an emirate, running the same matcher a real
                               request would. That is a buyer's tool.
            CustomerMemory     standing preferences (supplier locality, payment terms, certification)
                               that are applied to future RFQs.

          There is no trade licence, no catalogue, no products, no services and no company-identity
          field anywhere on it — it asks for nothing and holds nothing we were not already given by
          the customer's own buying. What it had was a supplier-side name imported onto a buyer's
          screen, which is exactly what it read as. So: renamed, not removed. Deleting it would have
          thrown away the standing preferences that shape every future RFQ and the matcher preview,
          to fix a word. */}
      {id === 'profile' && <div className="flex flex-col gap-3">
        <CompanyTwin twin={twin} lang={l2} />
        <SupplierDiscovery token={token} lang={l2} />
        <CustomerMemory token={token} lang={l2} />
      </div>}
      {id === 'account' && <AccountSettings token={token} lang={lang} onChanged={onChanged} />}
    </div>
  </section>);
}
export { MODULES, ModuleWindow };
