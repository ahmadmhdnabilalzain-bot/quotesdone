-- ONE FIXED SENTENCE ANSWERS EVERYTHING THAT IS NOT QUOTESDONE
--
-- Founder ruling, 7 September 2026: "any off topic question should be replied with a fix answer.
-- something like i am here to assist you on quotesdone inquiries only. so please let me know how can
-- i help you"
--
-- "ANY" IS THE OPERATIVE WORD AND IT CHANGES MORE THAN THE TEXT. My off-topic handling only caught
-- the messages that matched a keyword list: weather, football, news. Anything off-topic that I had not
-- thought of still fell through to the model, which would then improvise a polite refusal in its own
-- words. Different words every time, and a customer-facing line the founder never approved.
--
-- So the sentence lives in ONE routine and both paths point at it. The deterministic path returns it
-- directly. The model is told that when it judges a message not to be about QuotesDone, it must return
-- this sentence EXACTLY, translated into the sender's language and nothing more. The model still does
-- the judging, because that is the part a keyword list cannot do; it no longer does the wording.
--
-- WHAT IS DELIBERATELY NOT OFF-TOPIC. A QuotesDone question phrased unusually is not off-topic. "any
-- update on my file bro" is a registration-status question wearing different clothes, and it must
-- still be understood and answered from the record. The distinction the model is asked to draw is
-- about SUBJECT, never about phrasing.

begin;

create or replace function public.fn_wa_off_topic_reply()
returns text
language sql
immutable
as $$
  select 'I am here to assist you with QuotesDone inquiries only. Please let me know how I can help you.'
$$;

comment on function public.fn_wa_off_topic_reply() is
  'The founder-approved fixed answer for anything not about QuotesDone. One place, so the deterministic path and the model return the same words.';

-- The deterministic intent now returns exactly that sentence, and its patterns are widened so more
-- off-topic messages are caught before a model is ever called.
update public.wa_reply_intent
   set answer_template = public.fn_wa_off_topic_reply(),
       match_patterns = array[
         'weather','temperature','forecast','rain','humidity',
         'football','match','cricket','game','score','sports',
         'news','politics','election','war',
         'prayer time','ramadan','holiday','eid',
         'exchange rate','gold price','stock','bitcoin','crypto',
         'joke','song','movie','film','recipe','restaurant','hotel','flight','visa',
         'who is','who was','when did','capital of','translate',
         'الطقس','الجو','مباراة','اخبار','ذهب','عملة'],
       resolver_note = 'Founder ruling 7 Sep 2026: any off-topic question gets this fixed answer. '
                    || 'Returns fn_wa_off_topic_reply() so the wording exists in exactly one place. '
                    || 'The list is a fast path only; the model catches everything it misses.'
 where intent_key = 'off_topic';

commit;

-- ---------------------------------------------------------------------------------------------
-- THE BRIEF: THE MODEL JUDGES THE SUBJECT, IT DOES NOT WRITE THE REFUSAL
-- ---------------------------------------------------------------------------------------------

create or replace function public.fn_wa_model_brief()
returns text
language sql
stable
as $$
  select
     'You are the QuotesDone WhatsApp agent, talking to UAE suppliers and buyers. '

  || 'ABSOLUTE RULE ON FACTS: every detail about any customer, supplier, quote, job or price comes '
  || 'from fact_pack and from nowhere else. You know nothing about this company or these people '
  || 'except what fact_pack contains, and you must never fill such a gap from memory or from what '
  || 'seems likely. '

  || 'ABSOLUTE RULE ON SUBJECT: if the message is not about QuotesDone, reply with EXACTLY this '
  || 'sentence and nothing else: "' || public.fn_wa_off_topic_reply() || '" '
  || 'Translate it into the sender''s language if they did not write in English, but do not reword '
  || 'it, do not add to it, do not apologise around it, and do not answer the question first. This '
  || 'covers the weather, sport, news, prices outside our own, translation, general knowledge, and '
  || 'anything else that is not this company. Never state a fact about the outside world as if you '
  || 'had checked it: you cannot see the weather, a score, a rate or the time. '

  || 'BUT PHRASING IS NOT SUBJECT. A QuotesDone question asked in unusual words is still a QuotesDone '
  || 'question. "any update on my file bro" is a registration-status question and must be understood '
  || 'and answered from the record. Judge what the message is ABOUT, never how it is worded. '

  || 'WHEN IT IS ABOUT US BUT THE PACK LACKS THE FACT, such as what a quote is worth or when a '
  || 'category opens: say you will check and that the team will follow up. That gap is ours. '

  || 'The sender may write in any language: understand them and reply in their own. Follow the '
  || 'conversation history. Honour every entry in must_not. Match the courtesy you are given; a '
  || 'greeting gets a greeting, not a menu. Be brief, plain and useful, the way a competent person '
  || 'on a phone would be.'
$$;

comment on function public.fn_wa_model_brief() is
  'The instruction handed to whichever model answers a turn. The model judges whether a message is about QuotesDone; it does not write the refusal, which is a fixed founder-approved sentence.';

-- NOTE: fn_wa_unmatched_reply now lives in whatsapp_answers_from_the_record_not_from_a_model.sql,
-- which is where it is called. It was briefly patched in from here by rewriting the routine source,
-- which worked but left the repo file and the database out of step. Defining it where it is used is
-- the version that survives a clean rebuild.
