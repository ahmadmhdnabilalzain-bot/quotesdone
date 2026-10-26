// Customer portal §22 Orders module, over supabase/functions/procurement_api (action 'orders').
//
//   <OrdersList token={token} lang={lang} onOpenRfq={openRfq} />
//     token      string   customer Supabase JWT (required)
//     lang       'en'|'ar'          default 'en'
//     onOpenRfq  (inquiryId) => void   optional; fires with po_orders.inquiry_id
//     className  string             optional
//
// It fetches on mount, renders its own loading, error and empty states, and refetches when `token`
// or `lang` changes.
//
// 14 SEP 2026 — THE APPROVALS HALF OF THIS FOLDER WAS REMOVED. Founder: "i think its better just to
// remove the approvals tab. cause even if a company signed up, we don't wanna interfere in their
// approvals process and they are treated like normal individuals". ApprovalChain.tsx, its types and
// its copy are gone, and so are the database objects behind them
// (scripts/sql/a_company_buys_like_an_individual_so_the_approval_chain_is_dropped.sql). The folder
// keeps its name only because Orders lives here and Orders was explicitly not part of that decision;
// renaming it would have touched every in-flight branch that edits OrdersList.
export { OrdersList, type OrdersListProps } from './OrdersList';

// The typed procurement_api client and the order derivations, exported so the portal can reuse them
// rather than re-deriving an order's value a second way and disagreeing.
export { call, type ApiResult } from './api';
export {
  fmtDate, money, numOrNull, orderValue, receivedPct,
  type CustomerOrder, type Lang, type OrderLine,
} from './model';
