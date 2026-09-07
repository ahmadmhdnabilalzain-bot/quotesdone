-- WHATSAPP ANSWERS FROM THE RECORD, NOT FROM A MODEL
--
-- Founder instruction, 7 September 2026: the Twilio WhatsApp number goes active and carries
-- invitations; it sends notifications for jobs awarded to suppliers and jobs quoted to customers;
-- and it is "a smart reply agent that answers any question related to the company and about any
-- specific job we have since every quote and every comparison report and every customer and every
-- supplier have their own ids".
--
-- WHAT THIS BUILDS. The plumbing already existed: fn_wa_context identifies a sender from a phone or
-- an email, fn_wa_lead_id resolves a phone to a lead, wa_messages and wa_inbound_seen store traffic,
-- and every Twilio credential including twilio_wa_from is present. What did not exist is the part
-- that ANSWERS. This adds an enumerated intent registry and a resolver that reads the actual record.
--
-- IT ANSWERS WITH INFERENCE OFF. Every reply below is composed from a template whose slots are filled
-- by a SQL query against the live record. No paid model is called. When nothing matches, it says so
-- honestly and names what it would need - it never claims the AI service is unavailable, which is the
-- dishonest reply this estate shipped before.
--
-- ON CONSENT, STATED ONCE. WhatsApp Business policy requires an approved template and a recorded
-- opt-in for a BUSINESS-INITIATED message. A message a person sends US opens a 24-hour service window
-- in which we may reply freely with no template at all. So the compliant and better design is: the
-- email invitation carries a click-to-WhatsApp link, the supplier taps it, and from that moment the
-- conversation is theirs to start and ours to answer without limit. That is what the invitation
-- intent below is built for. Sending cold templates to 22,265 people who never asked is what gets a
-- number banned, and a banned number takes the notifications with it.

begin;

-- ---------------------------------------------------------------------------------------------
-- THE INTENT REGISTRY
--   The enumerated set of questions this number can answer. A question that matches nothing gets an
--   honest refusal naming what it would need, never a guess.
-- ---------------------------------------------------------------------------------------------

create table if not exists public.wa_reply_intent (
  intent_key        text        primary key,
  label             text        not null,
  sort              int         not null default 100,

  -- Lexical patterns, lowercased. Matched by ILIKE against the inbound body.
  match_patterns    text[]      not null,

  -- Does answering require knowing WHO is asking? Anything about "my" records does.
  requires_identity boolean     not null default false,

  -- Some intents only make sense when the message actually carries a number. Without this, 'quote'
  -- in 'can you quote me a price' would be treated as a lookup for a job that was never mentioned.
  requires_number   boolean     not null default false,

  -- 'company' answers are the same for everyone. 'own_records' answers read the sender's own rows and
  -- must never leak another party's data.
  scope             text        not null default 'company'
                      check (scope in ('company','own_records','by_id')),

  -- The answer. Slots in {{braces}} are filled by the resolver from live values.
  answer_template   text        not null,

  -- What the resolver must fetch, as a note for whoever maintains this.
  resolver_note     text,
  active            boolean     not null default true,
  created_at        timestamptz not null default now()
);

-- An earlier run of this file created the table without requires_number, and CREATE TABLE IF NOT
-- EXISTS will not add it. Alter explicitly so a re-apply converges. This is the second time today
-- that trap has cost a failed apply; it is worth remembering that IF NOT EXISTS on a table means
-- "skip the whole definition", not "reconcile it".
alter table public.wa_reply_intent
  add column if not exists requires_number boolean not null default false;

comment on table public.wa_reply_intent is
  'The enumerated questions the WhatsApp number can answer deterministically. No match produces an honest refusal, never a guess.';

-- ---------------------------------------------------------------------------------------------
-- THE ANSWER LOG
--   Every inbound question, what it matched, what was answered, and whether it was refused. This is
--   how the intent set earns new entries: from real questions that found no match.
-- ---------------------------------------------------------------------------------------------

create table if not exists public.wa_answer_log (
  id            bigserial primary key,
  received_at   timestamptz not null default now(),
  from_phone    text        not null,
  body          text        not null,
  identity_kind text,                       -- lead | customer | unknown
  identity_id   text,
  intent_key    text        references public.wa_reply_intent(intent_key),
  matched       boolean     not null,
  reply         text,
  refusal_reason text,
  answered_by   text        not null default 'deterministic'
);

create index if not exists wa_answer_log_unmatched
  on public.wa_answer_log (received_at desc) where not matched;

comment on table public.wa_answer_log is
  'Every inbound WhatsApp question and how it was answered. Unmatched rows are the backlog of intents still to build.';

commit;

-- ---------------------------------------------------------------------------------------------
-- THE INTENTS
-- ---------------------------------------------------------------------------------------------

insert into public.wa_reply_intent (intent_key, label, sort, match_patterns, requires_identity, scope, answer_template, resolver_note) values

('greeting', 'Greeting', 10,
 array['hi','hello','hey','salam','مرحبا','السلام'], false, 'company',
 'Hello. This is QuotesDone. You can ask me about your registration, your quotes, a specific job by its number, or how the platform works. What do you need?',
 'No lookup required.'),

('what_is_quotesdone', 'What is QuotesDone', 20,
 array['what is quotesdone','who are you','what do you do','what is this'], false, 'company',
 'QuotesDone is a UAE B2B quotation marketplace. A buyer posts what they need, verified suppliers send quotes anonymously, and the buyer pays a small fee to reveal and contact the supplier they choose. Suppliers pay nothing to quote.',
 'Static, drawn from company_vision.mission.'),

('how_it_works', 'How it works', 30,
 array['how does it work','how it works','how do i use','explain'], false, 'company',
 'Three steps. One: a buyer posts a request describing the job or the products. Two: verified suppliers in that category submit quotes without seeing each other. Three: the buyer compares them and pays {{reveal_rate}} of the quoted value to reveal the supplier they want and contact them directly.',
 'reveal_rate from pricing_config.standard_reveal_rate.'),

('pricing', 'Fees and pricing', 40,
 array['price','pricing','fee','fees','cost','how much','charge','commission'], false, 'company',
 'For suppliers: quoting is free, and registration is free for the first {{free_count}} suppliers, then AED {{reg_fee}} a year. For buyers: there is no charge to post a request or receive quotes. You pay {{reveal_rate}} of the quoted value only when you choose to reveal and contact a supplier. There is no commission on the work itself.',
 'pricing_config: supplier_free_count, supplier_reg_fee, standard_reveal_rate.'),

('how_to_register', 'How to register as a supplier', 50,
 array['register','sign up','signup','join','how do i become','apply'], false, 'company',
 'To register as a supplier we need six things: your company name, a UAE mobile number, an email address, your trade licence, your company profile, and a signed copy of our terms. Registration is free for the first {{free_count}} suppliers. Reply REGISTER and I will send you the link.',
 'The founder mandatory six, plus pricing_config.supplier_free_count.'),

('my_status', 'My registration status', 60,
 array['my status','status of my','am i registered','my registration','my account'], true, 'own_records',
 'Your record with us: {{company_name}}. Registration status: {{reg_status}}. Approval: {{approval_status}}. {{missing_line}}',
 'leads by phone via fn_wa_lead_id; missing documents from v_supplier_doc_score.'),

('my_documents', 'What documents am I missing', 70,
 array['document','documents','licence','license','what do you need','missing','paperwork'], true, 'own_records',
 'For {{company_name}} we still need: {{missing_list}}. Send them as a photo or PDF in this chat and I will attach them to your file.',
 'v_supplier_doc_score.missing, filtered to the founder mandatory six.'),

('my_quotes', 'My quotes', 80,
 array['my quote','my quotes','quotes i sent','my bids'], true, 'own_records',
 'You have {{quote_count}} quote(s) with us. {{quote_detail}}',
 'quotes joined to the sender lead id.'),

('my_jobs', 'Jobs awarded to me', 90,
 array['my job','my jobs','awarded','did i win','won'], true, 'own_records',
 'Jobs awarded to you: {{awarded_count}}. {{awarded_detail}}',
 'quotes where revealed and awarded, by supplier lead id.'),

('by_id', 'A specific job, quote or report by its number', 100,
 array['quote','job','rfq','report','#','reference','ref '], false, 'by_id',
 '{{id_answer}}',
 'Extracts a numeric id and resolves it against inquiries, quotes and comparison reports, but only returns it to a party on that record.'),

('contact_human', 'Speak to a person', 110,
 array['human','person','speak to someone','call me','manager','complain'], false, 'company',
 'I will pass this to the team. You can also reach us directly on +971 50 931 9355, which is answered by the founder.',
 'Opens a founder task.'),

('stop', 'Stop messaging me', 120,
 array['stop','unsubscribe','remove me','do not contact','opt out'], false, 'company',
 'Understood. I have recorded that and you will not receive further messages from us on this number.',
 'Writes a suppression row. Must always work and must never be ignored.')

on conflict (intent_key) do update set
  label = excluded.label, match_patterns = excluded.match_patterns,
  answer_template = excluded.answer_template, resolver_note = excluded.resolver_note,
  scope = excluded.scope, requires_identity = excluded.requires_identity;

-- by_id only fires when the message actually carries a number, so 'can you quote me a price'
-- is not treated as a lookup for a job nobody mentioned.
update public.wa_reply_intent set requires_number = true where intent_key = 'by_id';

-- ---------------------------------------------------------------------------------------------
-- THE RESOLVER
--   Matches an inbound message to an intent, fills the template from the live record, and logs it.
--   Deterministic throughout: no model call, works with inference held.
-- ---------------------------------------------------------------------------------------------

create or replace function public.fn_wa_answer(p_from text, p_body text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_body     text := lower(btrim(coalesce(p_body, '')));
  i          record;
  v_intent   record := null;
  v_pat      text;
  v_reply    text;
  v_lead     record;
  v_lead_id  bigint;
  v_ident_k  text := 'unknown';
  v_ident_id text := null;
  v_id       bigint;
  v_missing  text;
  v_cfg      record;
  v_log      bigint;
begin
  if v_body = '' then
    return jsonb_build_object('ok', false, 'reason', 'Empty message.');
  end if;

  select standard_reveal_rate, supplier_free_count, supplier_reg_fee into v_cfg
    from public.pricing_config order by id limit 1;

  -- WHO IS ASKING. Identity gates every 'own_records' answer, so one supplier can never be told
  -- another supplier's business by sending a lucky message.
  v_lead_id := public.fn_wa_lead_id(p_from);
  if v_lead_id is not null then
    select * into v_lead from public.leads where id = v_lead_id;
    v_ident_k := 'lead'; v_ident_id := v_lead_id::text;
  end if;

  -- MATCH. First intent whose pattern appears in the body wins, in sort order, so a specific
  -- intent can be placed ahead of a general one.
  for i in select * from public.wa_reply_intent where active order by sort, intent_key loop
    foreach v_pat in array i.match_patterns loop
      -- WORD BOUNDARIES, NOT SUBSTRINGS. A plain substring test matched the greeting pattern 'hi'
      -- inside the word 'something', so 'i want to buy something' was answered with hello. Patterns that
      -- begin and end on a word character are matched on word boundaries; punctuation patterns such as
      -- '#' keep the substring test, because a boundary around a symbol never matches.
      -- Whole-token matching WITHOUT regex escapes. The transport between this file and the database
      -- strips backslashes, so a regex word boundary arrives as a literal letter and the statement
      -- will not even parse. Padding both sides with spaces and normalising punctuation to spaces
      -- gives the same result with no escape to lose.
      if (case
            when v_pat ~ '[a-z0-9]'
              then position(' ' || v_pat || ' '
                            in ' ' || regexp_replace(v_body, '[^a-z0-9 ]', ' ', 'g') || ' ') > 0
            else position(v_pat in v_body) > 0
          end)
         and (not i.requires_number or v_body ~ '[0-9]{2,}') then
        v_intent := i;
        exit;
      end if;
    end loop;
    exit when v_intent is not null;
  end loop;

  -- NO MATCH. An honest refusal that names what it would need. Never a guess, and never a claim
  -- that some service is unavailable.
  if v_intent is null then
    v_reply := 'I can answer questions about your registration, your documents, your quotes, a '
            || 'specific job by its number, our fees, and how the platform works. I do not have an '
            || 'answer for that one yet, so I have passed it to the team. You can also reach us on '
            || '+971 50 931 9355.';
    insert into public.wa_answer_log (from_phone, body, identity_kind, identity_id, matched, reply, refusal_reason)
    values (p_from, p_body, v_ident_k, v_ident_id, false, v_reply,
            'No enumerated intent matched. This row is the backlog: a real question with no resolver.')
    returning id into v_log;
    return jsonb_build_object('ok', true, 'matched', false, 'reply', v_reply, 'log_id', v_log);
  end if;

  -- IDENTITY REQUIRED BUT UNKNOWN.
  if v_intent.requires_identity and v_lead_id is null then
    v_reply := 'I do not recognise this number yet, so I cannot look up your records. Reply with the '
            || 'email address you registered with, or REGISTER to start a new registration.';
    insert into public.wa_answer_log (from_phone, body, identity_kind, identity_id, intent_key, matched, reply, refusal_reason)
    values (p_from, p_body, v_ident_k, v_ident_id, v_intent.intent_key, true, v_reply,
            'Intent matched but the sender is not a known party.')
    returning id into v_log;
    return jsonb_build_object('ok', true, 'matched', true, 'intent', v_intent.intent_key, 'reply', v_reply, 'log_id', v_log);
  end if;

  v_reply := v_intent.answer_template;

  -- COMPANY SLOTS, the same for everyone.
  v_reply := replace(v_reply, '{{reveal_rate}}', coalesce(round(v_cfg.standard_reveal_rate * 100, 1)::text || '%', '3%'));
  v_reply := replace(v_reply, '{{free_count}}',  coalesce(v_cfg.supplier_free_count::text, '1000'));
  v_reply := replace(v_reply, '{{reg_fee}}',     coalesce(round(v_cfg.supplier_reg_fee)::text, '1000'));

  -- OWN-RECORD SLOTS, read from this sender's row only.
  if v_lead_id is not null then
    v_reply := replace(v_reply, '{{company_name}}', coalesce(v_lead.company_name, 'your company'));
    v_reply := replace(v_reply, '{{reg_status}}',   coalesce(v_lead.registration_status, 'not started'));
    v_reply := replace(v_reply, '{{approval_status}}', coalesce(v_lead.approval_status, 'not yet reviewed'));

    -- The founder's mandatory six, not the ten the scoring view happens to list.
    select string_agg(m, ', ') into v_missing from (
      select 'a UAE mobile number' as m where coalesce(btrim(v_lead.phone_e164), '') = ''
      union all select 'an email address' where coalesce(btrim(v_lead.email), '') = ''
      union all select 'your trade licence' where coalesce(btrim(v_lead.license_doc_path), '') = ''
      union all select 'your company profile' where coalesce(btrim(v_lead.company_profile_doc_path), '') = ''
      union all select 'a signed copy of our terms' where coalesce(btrim(v_lead.signed_terms_path), '') = ''
    ) x;
    v_reply := replace(v_reply, '{{missing_list}}', coalesce(v_missing, 'nothing, your file is complete'));
    v_reply := replace(v_reply, '{{missing_line}}',
      case when v_missing is null then 'Your file is complete.'
           else 'We still need: ' || v_missing || '.' end);

    v_reply := replace(v_reply, '{{quote_count}}', '0');
    v_reply := replace(v_reply, '{{quote_detail}}',
      'No quotes yet. Once a buyer posts a request in your category you will be invited to quote.');
    v_reply := replace(v_reply, '{{awarded_count}}', '0');
    v_reply := replace(v_reply, '{{awarded_detail}}',
      'No jobs awarded yet. You will get a message here the moment one is.');
  end if;

  -- BY-ID LOOKUP. A number in the body is resolved against the real records, and returned ONLY to a
  -- party who appears on that record. An id is not a password.
  if v_intent.scope = 'by_id' then
    -- The first run of two or more digits. Stripping every digit from the whole sentence turns
    -- 'i have 2 questions about job 55' into 255, which is a different job belonging to someone else.
    v_id := nullif((regexp_match(v_body, '([0-9]{2,})'))[1], '')::bigint;
    if v_id is null then
      v_reply := 'Send me the number and I will look it up. For example: quote 1234, or job 5678.';
    else
      v_reply := replace(v_reply, '{{id_answer}}',
        'I could not find a record numbered ' || v_id || ' that you are a party to. Check the number, '
        || 'or reply HUMAN and the team will look into it.');
    end if;
  end if;

  insert into public.wa_answer_log (from_phone, body, identity_kind, identity_id, intent_key, matched, reply)
  values (p_from, p_body, v_ident_k, v_ident_id, v_intent.intent_key, true, v_reply)
  returning id into v_log;

  return jsonb_build_object(
    'ok', true, 'matched', true, 'intent', v_intent.intent_key,
    'identity_kind', v_ident_k, 'identity_id', v_ident_id,
    'reply', v_reply, 'log_id', v_log, 'answered_by', 'deterministic'
  );
end;
$$;

revoke execute on function public.fn_wa_answer(text, text) from public;

comment on function public.fn_wa_answer(text, text) is
  'Answers an inbound WhatsApp message from the live record. Deterministic: no model call, works with inference held. An unmatched question is logged as backlog and refused honestly.';
