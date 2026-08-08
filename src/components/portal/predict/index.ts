// Customer portal §20 (AI Predictive Intelligence) over supabase/functions/customer_intelligence,
// and §15 (AI Negotiation Assistant) over supabase/functions/negotiation_assistant.
//
// Mount either, independently — neither owns navigation and neither needs the other:
//
//   <PredictiveIntelligence token={token} lang={lang} horizonDays={365} />
//     token        string     customer Supabase JWT (required)
//     lang         'en'|'ar'  default 'en'
//     horizonDays  number     default 365; fn_customer_forecast accepts 1..1095
//     className    string     optional
//
//   <NegotiationAssistant token={token} quoteId={quoteId} lang={lang} />
//     token      string        customer Supabase JWT (required)
//     quoteId    string|null   public.quotes.id on one of THIS customer's RFQs; null/omitted
//                              renders the "open a quote to compare it" prompt instead of fetching
//     lang       'en'|'ar'     default 'en'
//     className  string        optional
//
// Both fetch on mount, both render their own loading, error and empty states, and both refetch when
// their inputs change. Production holds zero inquiries and zero quotes, so today the forecast
// answers basis='no_history' and the guidance answers band='insufficient_data' — each renders the
// routine's own sentence explaining which absence is true, and neither draws a figure.
export { PredictiveIntelligence, type PredictiveIntelligenceProps } from './PredictiveIntelligence';
export { NegotiationAssistant, type NegotiationAssistantProps } from './NegotiationAssistant';

// The typed clients and the derivations the two surfaces share, exported so the portal can reuse
// them rather than deciding a second way whether a market benchmark exists and disagreeing.
export { call, type ApiResult } from './api';
export { Empty, Field } from './parts';
export {
  aed, fmtDate, marketComparison, numOrNull, projection, urgency,
  type Forecast, type ForecastCategory, type Lang, type MarketComparison, type Negotiation,
  type Prediction, type Projection, type Urgency,
} from './model';
