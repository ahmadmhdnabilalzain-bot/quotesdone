-- EVERY SCHEDULED STEP AND DUTY NAMES THE SEAT THAT OWNS IT.
--
-- Assigned: it_engineer. 22 Sep 2026. Founder, 7 Sep 2026: "no job or task without an agent".
--
-- ══ MEASURED, read-only against htdblwldjkcgjvmqkbeh, 22 Sep 2026 ═══════════════════════════
--   public.resilience_step      34 rows, columns step/every/budget_ms/place/rank/note/… — NO owner.
--   public.it_duty_schedule     12 rows, columns duty/every/note — NO owner.
--   public.org_agents            6 active seats; responsibilities filled for 'ceo' ONLY, and
--                                customer_support carries role = null and title = null although it
--                                answers the website widget, the WhatsApp channel and inbound mail.
-- So the scheduler ran 46 recurring jobs and the register could not say who owns a single one of
-- them except by reading each note by hand (SEATS-11). A job with no named seat is the founder's
-- 7 Sep rule broken in the one place the whole company's clock lives.
--
-- ══ WHAT THIS FILE CHANGES ═══════════════════════════════════════════════════════════════════
--   1. resilience_step.owner_seat and it_duty_schedule.owner_seat, both NOT NULL after the fill,
--      both FK to public.org_agents(agent_key) — a seat that does not exist cannot own a job, and a
--      seat cannot be deleted while it still owns one.
--   2. Every row filled. The owner is taken from the step's OWN note where the note names a seat
--      ("ceo: the four seat clocks", "marketing: publishes due posts", "sales_engineer: the daily
--      supplier invitation batch", "customer_support: once a day a test bounce"), and otherwise
--      from the routine the step calls. The mapping is written out row by row below so the next
--      reader can check it against the notes rather than trust it.
--   3. org_agents.responsibilities for all six seats, and customer_support's role and title.
--   4. scripts/checks/every_scheduled_job_names_a_live_seat.mjs fails when any step or duty names a
--      seat that is not active, or when a seat has no responsibilities.
--
--   node scripts/apply_sql.mjs scripts/sql/every_scheduled_step_and_duty_names_the_seat_that_owns_it.sql --apply --ddl

-- ── 1. the columns ───────────────────────────────────────────────────────────────────────────
alter table public.resilience_step   add column if not exists owner_seat text;
alter table public.it_duty_schedule  add column if not exists owner_seat text;

-- ── 2. the fill. Each line is the seat the step's own note or routine names. ─────────────────
update public.resilience_step set owner_seat = m.seat from (values
  -- the accountant's money work
  ('accountantDuties','accountant'), ('refunds','accountant'), ('weekly','accountant'),
  ('vat','accountant'),
  ('ladder','accountant'),          -- "refund chases must be written before the outbox drain"
  -- the CEO's own cadence
  ('ceoPlan','ceo'), ('ceoDecisions','ceo'), ('ceoWeekly','ceo'), ('digest','ceo'),
  ('orgtasks','ceo'),
  ('seatClocks','ceo'),             -- note: "ceo: the four seat clocks (fn_seat_clocks_tick)"
  -- customer support owns delivery to people
  ('outbox','customer_support'), ('whatsapp','customer_support'), ('ratings','customer_support'),
  ('deliveryCanary','customer_support'),   -- note: "customer_support: once a day a test bounce"
  ('archive','customer_support'),   -- every conversation message gets its PDF (founder, 14 Sep)
  -- the sales engineer owns the supplier and the offer
  ('specoffer','sales_engineer'),   -- note: "a supplier is waiting on the spec offer"
  ('supplierOutreach','sales_engineer'),   -- note: "sales_engineer: the daily supplier invitation batch"
  -- the marketing seat
  ('marketing','marketing'), ('marketingChannels','marketing'), ('marketingOutreach','marketing'),
  -- the IT engineer keeps the estate alive
  ('it','it_engineer'), ('itdetect','it_engineer'), ('itduties','it_engineer'),
  ('itlater','it_engineer'), ('itscheduled','it_engineer'), ('backup','it_engineer'),
  ('backupPrune','it_engineer'), ('backupVerify','it_engineer'), ('dropboxHealth','it_engineer'),
  ('tableExport','it_engineer'), ('orphans','it_engineer'), ('openrouter','it_engineer'),
  ('launchpath','it_engineer')
) as m(step, seat) where public.resilience_step.step = m.step;

-- Every duty in it_duty_schedule is a duty of the IT engineer's own hourly round (fn_it_scheduled_due
-- reads this table and fn_it_duty_settle answers each one as the IT engineer): access, backup_gap,
-- db_health, otp, restore, restore_table, rotation, sender, spend, supplier_docs, usage,
-- whatsapp_delivery. Each raises a finding that is HANDED to the owning seat — the duty itself is
-- the IT engineer's, which is what this column records.
update public.it_duty_schedule set owner_seat = 'it_engineer' where owner_seat is null;

-- ── 3. nothing may be left unowned, and the owner must be a seat that exists ─────────────────
do $$
declare v_step text; v_duty text;
begin
  select string_agg(step, ', ') into v_step from public.resilience_step where owner_seat is null;
  if v_step is not null then
    raise exception 'resilience_step rows with no owner_seat: % — add them to the fill above rather than defaulting them to a seat', v_step;
  end if;
  select string_agg(duty, ', ') into v_duty from public.it_duty_schedule where owner_seat is null;
  if v_duty is not null then raise exception 'it_duty_schedule rows with no owner_seat: %', v_duty; end if;
end $$;

alter table public.resilience_step  alter column owner_seat set not null;
alter table public.it_duty_schedule alter column owner_seat set not null;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'resilience_step_owner_seat_fk') then
    alter table public.resilience_step add constraint resilience_step_owner_seat_fk
      foreign key (owner_seat) references public.org_agents(agent_key);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'it_duty_schedule_owner_seat_fk') then
    alter table public.it_duty_schedule add constraint it_duty_schedule_owner_seat_fk
      foreign key (owner_seat) references public.org_agents(agent_key);
  end if;
end $$;

comment on column public.resilience_step.owner_seat  is 'The seat that owns this scheduled step (org_agents.agent_key). Founder, 7 Sep 2026: no job or task without an agent.';
comment on column public.it_duty_schedule.owner_seat is 'The seat that owns this duty (org_agents.agent_key). Every row is it_engineer: this table is the IT engineer''s own hourly round.';

-- ── 4. the register says what each seat is responsible for ───────────────────────────────────
-- ceo already has its responsibilities (the daily plan programme) and is left exactly as it is.
update public.org_agents set
  role  = coalesce(role, 'Customer Support AI -- the company''s voice to every person who writes in: the website chat widget, inbound email, the WhatsApp channel and every complaint, and the seat that delivers what the other seats ask to be sent.'),
  title = coalesce(title, 'Customer Support')
 where agent_key = 'customer_support';

update public.org_agents set responsibilities = v.resp from (values
  ('customer_support', 'Answers every person who writes in — the website widget, inbound email, WhatsApp — from company knowledge, never inventing a number or a promise. Owns the outbox: every notification another seat raises is delivered by this seat (delivery.request), and every delivery.result is reported back to the seat that asked. Owns complaints and their deadlines, the ratings request three weeks after a reveal, the daily delivery canary, the conversation archive and the founder''s 19:00 Dubai IT digest. Escalates to the CEO, never to the founder. Scheduled work: resilience_step outbox, whatsapp, ratings, deliveryCanary, archive.'),
  ('sales_engineer',   'Owns the inquiry from intake to dispatch: the brief, the technical scope, the per-line specs, matching, the top three and the safe (anonymised) dispatch. Owns the supplier side of the funnel — invitation batches, registration reminders, the mandatory six, document review and capability — and speaks as the sales engineer in both portals. Never moves money and never sends on its own account: money goes to the accountant, delivery goes to customer support. Scheduled work: resilience_step specoffer, supplierOutreach.'),
  ('accountant',       'Owns every financial matter: bookkeeping from the expenses mailbox and the Mashreq statements, the month close, refunds inside the guarded approval path, the reveal and non-response charges, renewal budgets, ad-spend booking and the VAT threshold watch. Approvals belong to the CEO; this seat prepares, books and proves. Scheduled work: resilience_step accountantDuties, refunds, ladder, weekly, vat.'),
  ('it_engineer',      'Monitors everything in the app and on the website, diagnoses what it finds, hands each fault to the seat that owns it and re-verifies before closing. Owns the detection tick and its findings, the duty round in it_duty_schedule, the backups (queue, prune, verify, Dropbox health), the table export, credential rotation, the OpenRouter meter and the launch-path probe. Reports to the CEO; the founder is emailed only for a new bug no seat could fix. Scheduled work: resilience_step it, itdetect, itduties, itlater, itscheduled, backup, backupPrune, backupVerify, dropboxHealth, tableExport, orphans, openrouter, launchpath.'),
  ('marketing',        'Owns SEO, social, digital and business development: publishes and schedules the posts the founder approved, answers the company''s social inbox from company knowledge, watches the analytics, collects ad spend for the accountant and reports the picture to the CEO. Publishes for real only while marketing_golive is true. Scheduled work: resilience_step marketing, marketingChannels, marketingOutreach.')
) as v(k, resp) where public.org_agents.agent_key = v.k;

do $$
declare v_missing text;
begin
  select string_agg(agent_key, ', ') into v_missing from public.org_agents
   where active and coalesce(btrim(responsibilities), '') = '';
  if v_missing is not null then raise exception 'active seats with no responsibilities: %', v_missing; end if;
end $$;
