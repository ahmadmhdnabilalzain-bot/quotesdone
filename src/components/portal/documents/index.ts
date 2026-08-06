// SPEC §14 Document Intelligence Vault, over supabase/functions/customer_documents.
//
// Mount:
//   <DocumentVault token={token} lang={lang} />          the whole vault: ask box, kind filters, rows
//
// or render one document anywhere (the Communication Center does):
//   <DocumentRow doc={doc} token={token} lang={lang} />
//
// Props:
//   token       string   the customer's Supabase JWT — the same one CustomerPortal already holds
//   lang        'en'|'ar'  default 'en'
//   refreshKey  number   change it to force a refetch after something files a new document
//   className   string
//
// The endpoint serves exactly three actions — list, search (alias: ask) and get (alias: download).
// `documentsApi` is exported so a caller can reach them without a second copy of the fetch.
export { DocumentVault, DocumentRow, kindLabel, type DocumentVaultProps, type DocumentRowProps } from './DocumentVault';
export {
  documentsApi, listDocuments, askDocuments, getDocument,
  type Lang, type VaultDocument, type VaultSource, type MatchReason, type EmptyReason,
  type VaultListResponse, type VaultSearchResponse, type VaultGetResponse, type VaultResult,
} from './api';
