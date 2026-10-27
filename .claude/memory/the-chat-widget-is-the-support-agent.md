---
name: the-chat-widget-is-the-support-agent
description: "The home-page chat widget IS the customer_support agent, and his knowledge is to be combined into one body rather than left split across the old departments' tables"
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-08T01:41:21.454Z
---

Founder, 8 Sep 2026: **"the chat widget on home screen belongs to customer support agent. so combine
the knowledge for him."**

Two rulings in one sentence:

1. **Identity.** The public home-page chat widget (edge function `site_assistant`) is not a separate
   thing from the customer_support agent — it is his front door. WhatsApp (`wa_inbound`) is the same
   agent on another channel. The signed-in customer/supplier assistant is a LATER, DIFFERENT agent
   (his words, earlier the same day). See [[the-ceo-seat-has-tools-but-no-runtime]].
2. **Knowledge is consolidated, not scattered.** The corpus was built for ten departments and sits in
   several tables (`agent_knowledge`, `ops_knowledge`, `dept_library`, plus pack and exam artefacts).
   The support agent is to retrieve from ONE combined body. Do not preserve the department split just
   because the rows carry a `dept` column.

The risk to watch when consolidating or deleting here: a knowledge table dropped or left out does not
break the widget visibly — it just makes the agent worse at answering, silently. That is the failure
mode to check for BEFORE acting, not after. Related: [[a-mention-is-not-a-reference]].
