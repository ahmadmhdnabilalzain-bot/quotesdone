// Customer portal §12 (Purchase Approval System) and the §22 Orders module, over
// supabase/functions/procurement_api.
//
// Mount either, independently — neither owns navigation and neither needs the other:
//
//   <ApprovalChain token={token} lang={lang} onOpenRfq={openRfq} />
//     token      string   customer Supabase JWT (required)
//     lang       'en'|'ar'          default 'en'
//     onOpenRfq  (inquiryId) => void   optional; shows "Open the awarded RFQ" on a request
//     className  string             optional
//
//   <OrdersList token={token} lang={lang} onOpenRfq={openRfq} />
//     same four props; onOpenRfq fires with po_orders.inquiry_id
//
// Both fetch on mount, both render their own loading, error and empty states, and both refetch when
// `token` or `lang` changes. Production has zero organizations, zero policies, zero approval
// requests and zero orders, so both render an empty state today — three different ones for
// approvals, because "no organisation", "no policy" and "nothing has needed approval yet" are three
// different facts.
export { ApprovalChain, type ApprovalChainProps } from './ApprovalChain';
export { OrdersList, type OrdersListProps } from './OrdersList';

// The typed procurement_api client and the derivations the two surfaces share, exported so the
// portal can reuse them rather than re-deriving an order's value a second way and disagreeing.
export { call, type ApiResult } from './api';
export {
  canDecide, chainProgress, fmtDate, money, numOrNull, orderValue, receivedPct, STEP_STATUSES,
  type ApprovalPolicy, type ApprovalRequest, type ApprovalStep, type ApprovalsPayload,
  type ChainProgress, type CustomerOrder, type Lang, type OrderLine, type Organization,
  type StepStatus,
} from './model';
