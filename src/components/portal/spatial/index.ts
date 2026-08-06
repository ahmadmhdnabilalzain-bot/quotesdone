// Spec §6 (3D Project Visualization) and §19 (Project Room + Supply Chain Map).
//
// MOUNT ONE THING:
//
//   import { SpatialModule } from '@/components/portal/spatial';
//
//   <SpatialModule
//     token={token}                              // required — the customer's access token
//     lang={lang === 'ar' ? 'ar' : 'en'}         // optional, default 'en'
//     projectId={someProjectId}                  // optional — omit and the customer picks
//     inquiries={inqs}                           // optional but WANTED: the my_inquiries rows the
//                                                //   portal already holds (id + quotes[]). Without
//                                                //   them the room says quote counts are not
//                                                //   loaded rather than implying zero quotes.
//     onOpenRfq={(id) => { /* open that request */ }}
//   />
//
// It renders <ProjectRoom> (the 3D model, its legend, the per-band block list and the click-through
// panel) and <SupplyChainMap> (one animated stage track per real order), and fetches project_api
// detail, procurement_api orders and customer_documents list itself.
//
// Or mount the two surfaces yourself and feed them:
//   <ProjectRoom project rfqs orders documents inquiries lang onOpenRfq />
//   <SupplyChainMap orders lang onOpenRfq />
//
// THE RENDERER: `three` (MIT), dynamically imported inside ProjectRoom's effect so it lands in its
// own async chunk and never enters the main bundle. The reasoning — including why the supplied
// mlightcad/cad-viewer was not used, and the GPL-3.0 problem with its bundled DWG parser — is at
// the top of ProjectRoom.tsx.
export { SpatialModule, type SpatialModuleProps } from './SpatialModule';
export { ProjectRoom, type ProjectRoomProps } from './ProjectRoom';
export { SupplyChainMap, type SupplyChainMapProps } from './SupplyChainMap';

// The typed clients and the pure derivations, exported so nothing re-derives "delivered" a second
// way and disagrees with the block that is already on screen.
export { fetchProjectDetail, fetchProjectList, fetchOrders, fetchDocuments, type ApiResult } from './api';
export {
  buildModel, chainLegs, stageOf, receivedFraction, levelsFromMeta, docsForRfq,
  elapsedPct, fmtDate, money, NO_INQUIRIES, STAGE_COLOR, STAGE_LABEL, CHAIN_LABEL,
  type Lang, type PackageStage, type ChainStage, type ChainLeg,
  type SpatialModel, type SpatialLevel, type SpatialPackage,
  type SpatialProject, type SpatialRfq, type CustomerOrder, type OrderLine,
  type VaultDoc, type PortalInquiry,
} from './model';
