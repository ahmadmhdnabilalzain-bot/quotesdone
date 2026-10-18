-- Assigned: customer_support (homepage widget) + sales_engineer (portal chat). 18 Oct 2026.
--
-- THE CHAT FORGOT THE CONVERSATION. Founder, portal, 14 Oct 2026 20:17-20:23 Dubai (assistant_logs 3694-3699): he
-- asked for a 2 m x 1.2 m custom wardrobe; one turn later the reply asked again for "the wardrobe width and height",
-- and by the fifth turn it said "I can't see its earlier details here". sales_engineer never read the history the
-- portal sent, and the widget kept only the browser's last 6 messages. Founder ruling 18 Oct: no turn limit, every turn
-- stored, the whole conversation given to the model.
--
-- assistant_logs already holds every widget and portal turn (message + reply) and is kept with the conversations
-- (fn_conversation_record). What it lacked was the key that says which conversation a turn belongs to, so nothing could
-- read a conversation back. conv_id is that key (founder ruling 1255, 19 Oct: the agent can't lose the chat):
--   v-<visitor id>        a website visitor; the id lives in the browser's localStorage, so it survives a closed browser;
--   a-c-<customer id>     a signed-in customer, the same conversation in the portal and on the widget, the account taken
--                         from the verified session, never the request body.
-- Signing up adopts the visitor's rows into the account (conv_id rewritten, no row deleted). _shared/chat_history.ts.
--
-- 309 rows (344 kB) on 18 Oct, so the index is built in place. No routine is created; RLS on the table is unchanged.
alter table public.assistant_logs add column if not exists conv_id text;
comment on column public.assistant_logs.conv_id is
  'The conversation this turn belongs to (v-<visitor id> before sign-up, a-c-<customer id> after; ruling 1255). _shared/chat_history.ts loadTranscript reads every turn of it back, oldest first, for the model.';
create index if not exists assistant_logs_conv_id_id on public.assistant_logs (conv_id, id) where conv_id is not null;
