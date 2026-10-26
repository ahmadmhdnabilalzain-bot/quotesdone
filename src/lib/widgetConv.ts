// THE WEBSITE-WIDGET CHAT ID IN THIS BROWSER (customer_support, founder ruling 1255; review of #1438).
// ChatWidget keeps the visitor's chat id under this key; the portal presents it once after sign-in so the chat is adopted
// into the account. The id is kept when the move fails (the next mount retries), so it MUST be dropped on sign-out:
// otherwise a different customer signing in later on the same browser would adopt the previous visitor's chat.
// prevented by: supabase/functions/_shared/chat_history.test.ts ("A signs out, B signs in on the same browser")
export const WIDGET_CONV_KEY = 'qd-chat-conv';
type Store = Pick<Storage, 'getItem' | 'removeItem'>;
const local = (): Store | null => { try { return localStorage; } catch (_e) { return null; } };
export const readWidgetConv = (s: Store | null = local()): string => { try { return s?.getItem(WIDGET_CONV_KEY) || ''; } catch (_e) { return ''; } };
export const forgetWidgetConv = (s: Store | null = local()): void => { try { s?.removeItem(WIDGET_CONV_KEY); } catch (_e) { /* storage blocked */ } };
