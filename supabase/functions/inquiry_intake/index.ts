import { siteCors } from '../_shared/site_origins.ts';
// inquiry_intake — conversational intake agent. Detects category, asks category-specific clarifying
// questions (driven by category_specs checklists + AI), rejects junk, and emits a supplier-ready
// structured brief with a readiness score. Also detects multiple trades, urgency, budget/timeline
// plausibility, and per-field provenance. Persists drafts in inquiry_intake; logs to ai_qa_log.
// Once the category is known, the matching category_agents specialist takes over the conversation.
// COST: prompt caching (cache_control ephemeral) on the system prompt — multi-turn chats bill it at ~10% on repeat turns.
import { observe } from '../_shared/observe.ts';
import { handle } from './handle.ts';

Deno.serve(siteCors(observe('inquiry_intake', handle)));
