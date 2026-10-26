// SPEC §16 Communication Center, over supabase/functions/messages_api + customer_documents.
//
// Mount:
//   <CommunicationCenter token={token} lang={lang} onOpenRfq={(id) => …} />
//
// Props:
//   token       string                 the customer's Supabase JWT — the one CustomerPortal holds
//   lang        'en'|'ar'              default 'en'
//   onOpenRfq   (inquiryId) => void    optional; makes the request name on a conversation clickable
//   refreshKey  number                 change it to force a refetch
//   className   string
//
// It replaces the Messages/Thread pair in CustomerPortal.tsx: same four messages_api actions, plus
// the documents that belong to each conversation and an explicit statement of which channels the
// inbox does and does not carry. See the header of CommunicationCenter.tsx for what the backend
// serves (chat, documents, RFQ, supplier) and what it does not (WhatsApp, email, calls, project).
export { CommunicationCenter, type CommunicationCenterProps } from './CommunicationCenter';

// The messages_api client, exported so nothing needs a second copy of the fetch or the shapes.
export {
  messagesApi, listThreads, openThread, sendMessage, requestChat,
  type Lang, type ChatStatus, type ThreadSummary, type ThreadsResponse, type ChatMessage,
  type ThreadResponse, type SendResponse, type RequestChatResponse, type CommsResult,
} from './api';

// The document->conversation rule, and its counter. Pure, and exercised by link.test.mjs.
export {
  linkDocuments, documentCount, threadKey,
  type LinkableThread, type LinkableDoc, type ThreadDocuments, type LinkResult,
} from './link';
