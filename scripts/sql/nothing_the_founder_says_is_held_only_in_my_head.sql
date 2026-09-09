-- NOTHING THE FOUNDER SAYS IS HELD ONLY IN MY HEAD.
--
-- He asked, 9 September 2026: "Are you treating my conversations as, like, strict comments or
-- you're just, like, reading them and ignoring? Because if I say something is missing or it was...
-- need to be built or fixed or whatever, you cannot ignore. I'm assuming literally everything I say
-- is done."
--
-- The honest answer was: binding in intent, but tracked nowhere. I was holding a two-hour list of
-- instructions in working memory and walking down it. That is precisely the wrong way to hold
-- something the founder assumes is already done, and it fails in the way every untracked list
-- fails — silently, and only visibly much later.
--
-- The estate already had a table shaped for this and it does not fit: public.founder_directive has
-- columns setting_key / old_value / new_value, so it models "he changed a setting", not "he told me
-- to build something". It holds 0 rows and nothing reads it. Rather than bend it, this adds the
-- thing that was actually missing.
--
-- WHY A TABLE AND NOT A DISCIPLINE. A promise to be careful is worth nothing on the next reset.
-- A row survives, and an open row can be counted, listed, and put in front of him without either
-- of us remembering it.
--
-- THE RULE THIS ENCODES: every instruction is open until something PROVES it closed. `evidence` is
-- not a description of the work — it is the measurement, the file, or the routine that shows the
-- instruction is satisfied. An instruction closed with no evidence is still open.

create table if not exists public.founder_instruction (
  id            bigserial primary key,
  said_at       timestamptz not null,
  -- his own words, verbatim. Paraphrase is where instructions quietly change meaning.
  instruction   text        not null,
  -- what it touches, so a seat can find the ones that concern it
  subject       text,
  status        text        not null default 'open'
                check (status in ('open','done','deferred_by_founder','superseded','refused')),
  -- WHAT PROVES IT. A file, a routine, a measurement. Never a sentence about intent.
  evidence      text,
  closed_at     timestamptz,
  -- if it is not done, the honest reason, so "open" is never mistaken for "forgotten"
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
comment on table public.founder_instruction is
  'Every instruction the founder gives, verbatim, with what proves it closed. Exists because on 9 Sep 2026 he asked whether his instructions were being treated as binding and the honest answer was "yes, but tracked only in my head". An instruction is open until evidence closes it.';

create index if not exists founder_instruction_open_idx
  on public.founder_instruction (said_at) where status = 'open';

alter table public.founder_instruction enable row level security;
revoke all on public.founder_instruction from anon, authenticated;

-- Closing requires evidence. This is the whole point of the table, so it is a constraint and not a
-- convention: a status of 'done' with an empty evidence column is the exact failure being fixed.
create or replace function public.fn_founder_instruction_needs_evidence()
returns trigger language plpgsql as $fn$
begin
  if new.status = 'done' and coalesce(btrim(new.evidence), '') = '' then
    raise exception 'instruction % cannot be marked done with no evidence. Name the file, routine or measurement that proves it.', new.id;
  end if;
  if new.status <> 'open' and new.closed_at is null then new.closed_at := now(); end if;
  new.updated_at := now();
  return new;
end $fn$;

drop trigger if exists a10_founder_instruction_needs_evidence on public.founder_instruction;
create trigger a10_founder_instruction_needs_evidence
  before insert or update on public.founder_instruction
  for each row execute function public.fn_founder_instruction_needs_evidence();

-- What is still owed him, newest first.
create or replace function public.fn_founder_open_instructions()
returns jsonb language sql stable security definer set search_path to 'public' as $fn$
  select jsonb_build_object(
    'open', count(*) filter (where status = 'open'),
    'done', count(*) filter (where status = 'done'),
    'deferred_by_him', count(*) filter (where status = 'deferred_by_founder'),
    'items', coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'said_at', said_at, 'subject', subject,
        'instruction', instruction, 'note', note)
      order by said_at) filter (where status = 'open'), '[]'::jsonb))
  from public.founder_instruction;
$fn$;
revoke execute on function public.fn_founder_open_instructions() from public;

-- ── THE BACKFILL: everything he said on 9 Sep 2026, in his words, with its true state ────────────
insert into public.founder_instruction (said_at, instruction, subject, status, evidence, note) values

-- ---- DONE, each with the thing that proves it ----
('2026-09-09 16:10+00', 'the customer support agent contacts the supplier; if there is no response within the refund limit days he sends it to the CEO, the CEO checks those records and confirms, then the accountant issues the refund. Approval from CEO, execution from the accountant always whenever it is related to money.',
 'refunds', 'done',
 'scripts/sql/a_refund_is_proved_by_silence_approved_by_the_ceo_and_paid_by_the_accountant.sql — supplier_response_watch + fn_refund_nonresponse_eligibility + trigger z10_refund_nonresponse_needs_silence. Proven on production across five branches including the supplier-replied case.', null),

('2026-09-09 16:10+00', 'the accountant is supposed to generate the penalty for the supplier: three percent back plus two fifty AED admin fee plus nine percent annual interest on the amount.',
 'refunds', 'done',
 'fn_supplier_nonresponse_penalty. AED 100,000 job refunded 30 days ago = 3000 recover + 250 admin + 24.04 interest = 3274.04. Rates read from pricing_config, never typed.', null),

('2026-09-09 16:10+00', 'That is old data from the old structure, which should have been deleted. Whatever we made so far in the past two days need to be in production, and no old history should be effective.',
 'data hygiene', 'done',
 'scripts/sql/the_old_company_stops_showing_up_in_the_new_ones_numbers.sql — exec_reports open 7 -> 0, onboarding 16 -> 0, proposals 62 -> 0, decisions 11 -> 0, incidents -> 0, demo customer deleted, 59 mail routes re-owned.', null),

('2026-09-09 16:40+00', 'you did that twice. There must be something wrong in the way you read that you repeated the mistake twice. That is what you need to fix.',
 'my own reading', 'done',
 'scripts/sql/a_number_carries_its_meaning_and_a_record_proves_it_is_real.sql — v_openrouter_position names account balance vs key cap and states which binds; fn_customer_is_substantiated scores on evidence of realness, proven against a row identical to the one that fooled me.', null),

('2026-09-09 16:40+00', 'no login exists for the CEO. If it is something fixable, then what are you waiting for?',
 'ceo', 'done',
 'fn.ceo_agent credential minted; ceo_agent deployed. Proven over HTTP: inbox 200 as the CEO, decide without the credential 401.', null),

('2026-09-09 16:40+00', 'Inbox does not read the tray. You need to also build that properly.',
 'ceo', 'done',
 'ceo_agent action=inbox now reads support_ceo_report via fn_support_open_reports; action=accept wired to fn_ceo_accept_support_report. Proven: the accountant''s weekly reports 138 and 140 are visible to the seat.', null),

('2026-09-09 16:40+00', 'One approval unlimited refunds. That is horrible. Every refund is connected to a Stripe invoice and it is issued against that exact reference. It has an ID.',
 'refunds', 'done',
 'scripts/sql/a_refund_names_the_one_approval_and_the_one_stripe_payment_it_reverses.sql — subject_id now compared; a borrowed approval is refused while a legitimate one passes.', null),

('2026-09-09 16:40+00', 'Firewall in logging mode. Is there something fixable in that, how, and is there any extra cost?',
 'security', 'done',
 'Six unambiguous attack classes switched log -> deny on config waf_l2KzGOM8qEy5 (v13 -> v19). No extra cost. scripts/checks/the_firewall_blocks_what_it_says_it_blocks.test.mjs fails if reverted. Site verified 200 after.', null),

-- ---- STILL OPEN. Every one of these he has said and I have not finished. ----
('2026-09-09 16:10+00', 'For the accountant, he is already connected to Stripe, so the total revenue can be received from there. And then the threshold, which is the three hundred seventy five, that is when he notifies the CEO that we are supposed to register over that.',
 'accountant', 'open', null,
 'Not started. Needs: revenue recognised from Stripe into the ledger, and a routine watching the AED 375k VAT threshold that reports to the CEO when it is crossed.'),

('2026-09-09 16:10+00', 'The CEO report should be about the whole company, and that is why everyone reports to him. His report should be extremely organized more than anybody else. He should also be suggesting ideas and improvements to the company, like how Elon Musk does it for Tesla.',
 'ceo', 'open', null,
 'Not started, and this is the one he actually reads every week. The daily digest fired for the first time today at 20:00 Dubai and was delivered, but it is a digest, not the organised whole-company weekly report with analysis and proposals.'),

('2026-09-09 16:10+00', 'The company knowledge is literally connected to every seat automatically. Any seat that we made, the company knowledge should be there.',
 'knowledge', 'open', null,
 'Built and applied but not yet proven end to end: scripts/sql/every_seat_carries_the_company_knowledge.sql. Two seats still have no runtime call to their own knowledge. Stays open until each of the five is measured carrying it.'),

('2026-09-09 16:10+00', 'Arabic is needed for everyone, and you need to work on that as well.',
 'knowledge', 'open', null,
 'In progress: scripts/sql/arabic_reaches_the_same_answer_as_english.sql applied, not yet in the manifest, and the widget and tokeniser edits are not deployed.'),

('2026-09-09 16:10+00', 'Every seat for us needs to be equal to a real human operating in a company with twenty years of experience at least, with much stronger reasoning and judgment. The numbers are way too low for every seat.',
 'knowledge', 'open', null,
 'Not started. I owe him a definition of what a 20-year UAE professional actually holds, per seat, before generating volume. Adding rows of the same shape will not close this.'),

('2026-09-09 16:10+00', 'The general reference library, you need to organize it in a way that it is ingested properly, not just like a text. You need to do it with keywords. It has to be like a brain.',
 'knowledge', 'open', null,
 'Not started. 2.5 million of 2.69 million reference records are unindexed and the indexing job stopped 2 days ago.'),

('2026-09-09 16:10+00', 'Those knowledge gaps, you need to fill them properly — no pricing at all.',
 'knowledge', 'open', null,
 'Not started. Not one of the 1,136 sales knowledge records mentions AED; the table the pricing model reads has never had a writer.'),

('2026-09-09 16:10+00', 'The website chat widget is basically the customer support agent, they are not two different things. Once someone is registered then it is the sales engineer. We have discussed this before. You need to check what happened yesterday and then update accordingly.',
 'customer_support', 'open', null,
 'Not started. I described them as separable in the audit, which contradicts his ruling.'),

('2026-09-09 16:10+00', 'Escalate to human, that is something that does not exist. We do not have escalation to human. The IT agent is the only one who reports to me directly.',
 'customer_support', 'open', null,
 'Not started. Support still logs an "escalated" flag that notifies nobody, and I reported its absence as a gap when it is deliberate.'),

('2026-09-09 16:40+00', 'Every polite refusal is invisible to IT. It seems like there is something wrong there, and you need to fix it.',
 'it_engineer', 'open', null,
 'Not started. 4xx responses are recorded as warnings and excluded from the failure rate, so customer sign-in refused 119 of 125 attempts today and the detector reads 0.00.'),

('2026-09-09 16:10+00', 'Collection definitely goes to the accountant.',
 'accountant', 'open', null,
 'Not started. One line on the accountant''s responsibilities; nothing to collect yet, but the ownership should be recorded now.'),

-- ---- HE DEFERRED THESE HIMSELF. Recorded so they are not re-raised as gaps. ----
('2026-09-09 16:10+00', 'Later on we will build the legal agent who will have UAE law fully in his knowledge as it is, not summary, and he does not have a keyword search — he has logic, brain and reasoning. He should be stronger than any lawyer in the UAE.',
 'legal', 'deferred_by_founder', null, 'His words: "later on". Do not raise as a gap.'),

('2026-09-09 16:10+00', 'I cannot connect him to the bank. There is no API. All I can do is monthly share the statement as a PDF.',
 'accountant', 'deferred_by_founder', null, 'A bank API is impossible, not missing. What is needed is a PDF statement import — open, but not a defect.'),

('2026-09-09 16:10+00', 'We never need an HR. It is a fully automated company with no real human involvement. There is no product manager. Procurement — we do not buy material.',
 'org', 'refused', null, 'Correctly refused: I proposed these from a generic checklist rather than from his company. Struck.')
on conflict do nothing;

do $do$
declare v jsonb; v_done int; v_open int;
begin
  v := public.fn_founder_open_instructions();
  v_done := (v->>'done')::int; v_open := (v->>'open')::int;
  if v_done = 0 or v_open = 0 then
    raise exception 'the backfill is one-sided (% done, % open) — a ledger that shows only wins is not a ledger', v_done, v_open;
  end if;

  -- The evidence rule must actually bite.
  begin
    update public.founder_instruction set status = 'done', evidence = '   ' where id = (select min(id) from public.founder_instruction where status = 'open');
    raise exception 'an instruction was closed with blank evidence — the guard does not work';
  exception when others then
    if sqlerrm not like '%cannot be marked done with no evidence%' then raise; end if;
  end;

  raise notice 'FOUNDER INSTRUCTION LEDGER LIVE. % done (each naming what proves it), % still open, % deferred by him. Nothing he said today is held only in my head.',
    v_done, v_open, (v->>'deferred_by_him')::int;
end
$do$;
