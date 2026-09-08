-- EVERY FUNCTION THAT SURVIVES NAMES ITS OWNER
--
-- The founder, 8 September 2026, on being told three functions were being kept: "when you say
-- keep. are you linking those 3 to the customer support cause anyway those belong to him yea?"
--
-- The right question, and it exposed a gap in how I was applying his own rule. "Keep" is not
-- "owned". A function that survives a deletion sweep because somebody judged it useful is in
-- exactly the orphan state the sweep existed to end -- it just has a friendlier label. 69 functions
-- were deleted across three waves for belonging to nobody; leaving the survivors implicitly owned
-- would recreate the same condition on the first day somebody adds a new one.
--
-- So ownership is written down, and a function with no owner becomes visible instead of assumed.
--
-- THE THREE HE ASKED ABOUT ARE HIS SEAT'S, and they are recorded as such rather than merely spared:
--   email_cron           flushes the outbox on a schedule -- how support's mail actually leaves
--   wa_template_setup    manages the WhatsApp template the licence-expiry notice needs
--   wa_templates_watch   polls Twilio for approval and opens the channel when it lands
--
-- WEBSITE IS AN OWNER HERE, AND IT IS NOT AN AGENT. The founder drew that line himself -- "if they
-- belong to the website then leave them" -- and it is a real category: the sign-in flow, the
-- payment webhooks and the public pages are the product, not a seat's job. Recording them under
-- 'website' keeps the distinction legible instead of pretending an agent owns them, which is the
-- kind of tidy fiction that makes the next audit wrong.
--
-- The OS surfaces are recorded under 'website' too, with a note: the founder said the OS is being
-- fully rebuilt, so these are the outgoing implementation and their owner will change when the
-- seat that runs the OS exists.

create table if not exists public.function_owner (
  function_slug text primary key,
  owner         text not null,
  note          text not null,
  recorded_at   timestamptz not null default now(),

  -- An owner is one of the two seats that exist, or the product itself. There is deliberately no
  -- 'unassigned' value: a function with no owner must fail to be recorded, not be recorded as
  -- unowned, because an 'unassigned' row is how an orphan becomes permanent paperwork.
  constraint function_owner_owner_ck check (owner in ('ceo', 'customer_support', 'website')),
  constraint function_owner_note_ck check (btrim(note) <> '')
);

comment on table public.function_owner is
  'Which seat or surface owns each deployed edge function. The founder''s rule of 8 Sep 2026 is that anything belonging to neither the CEO, the customer-support agent nor the website does not exist; this is where that rule becomes checkable rather than remembered. There is no unassigned owner on purpose.';

insert into public.function_owner (function_slug, owner, note) values
 -- THE CUSTOMER SUPPORT AGENT ------------------------------------------------------------------
 ('wa_inbound',         'customer_support', 'WhatsApp channel: inbound messages, media and the 24-hour service window.'),
 ('site_assistant',     'customer_support', 'The public chat widget on the website home page. The founder''s scope, 8 Sep: this is the support agent; the signed-in assistant is a later seat.'),
 ('email_triage',       'customer_support', 'Sorts inbound mail into what it is and who it is from.'),
 ('inbound_email',      'customer_support', 'Reads an inbound email into a structured intake and matches the sender to a lead.'),
 ('resend_inbound',     'customer_support', 'The provider webhook that delivers inbound mail to the intake.'),
 ('license_extract',    'customer_support', 'Reads a trade licence: the document work its standing grant covers on all three channels.'),
 ('extract_text',       'customer_support', 'Pulls text out of an attached document so the intake can read it.'),
 ('transcribe',         'customer_support', 'Voice notes. WhatsApp is a spoken channel as often as a written one.'),
 ('ai_gateway',         'customer_support', 'The routing and spend gate every model call passes through. Support cannot answer without it.'),
 ('send_outbox',        'customer_support', 'Flushes queued email through Resend, with retry, suppression and the branded templates.'),
 ('send_whatsapp',      'customer_support', 'Sends on the WhatsApp channel.'),
 ('email_cron',         'customer_support', 'Runs the outbox flush on a schedule and watches domain verification. How support''s mail actually leaves the building.'),
 ('wa_template_setup',  'customer_support', 'Manages the WhatsApp Content template the licence-expiry notice needs.'),
 ('wa_templates_watch', 'customer_support', 'Polls Twilio for template approval and opens the channel when it lands.'),
 ('wa_optin_set',       'customer_support', 'Records a recipient''s WhatsApp opt-in -- the consent the channel is currently blocked on.'),

 -- THE WEBSITE ---------------------------------------------------------------------------------
 ('home',               'website', 'Public page.'),
 ('home-ar',            'website', 'Public page, Arabic.'),
 ('about',              'website', 'Public page.'),
 ('faq',                'website', 'Public page.'),
 ('legal',              'website', 'Public page: terms and policies.'),
 ('i18n_get',           'website', 'Serves translated strings to the site.'),
 ('public_stats',       'website', 'The public numbers shown on the marketing pages.'),
 ('contact_submit',     'website', 'The contact form.'),
 ('claim_lookup',       'website', 'Lets a supplier find their own listing to claim.'),
 ('unsubscribe',        'website', 'One-click unsubscribe, required by RFC 8058 for the mail we send.'),
 ('login_otp',          'website', 'Sign-in by one-time code.'),
 ('mobile_otp',         'website', 'Sign-in by mobile.'),
 ('voice_otp',          'website', 'Sign-in code delivered by call, for a handset that cannot take SMS.'),
 ('voice_otp_capture',  'website', 'Captures the spoken code.'),
 ('auth_api',           'website', 'Session and account endpoints.'),
 ('role_guard',         'website', 'Decides what a signed-in identity may see.'),
 ('sup_dob',            'website', 'Supplier identity check during onboarding.'),
 ('portal',             'website', 'The portal shell.'),
 ('customer_portal',    'website', 'The signed-in customer surface.'),
 ('customer_documents', 'website', 'A customer''s own documents.'),
 ('customer_intelligence','website','Customer-facing insight panels.'),
 ('procurement_api',    'website', 'The procurement surface the app calls.'),
 ('project_api',        'website', 'The project surface the app calls.'),
 ('negotiation_assistant','website','In-portal negotiation help.'),
 ('supplier_ack',       'website', 'A supplier acknowledging an invitation.'),
 ('rfq_flag',           'website', 'Flags a problem on an RFQ from the portal.'),
 ('kyc',                'website', 'Identity and business verification during onboarding.'),
 ('stripe_checkout',    'website', 'Takes the reveal fee.'),
 ('stripe_confirm',     'website', 'Confirms a payment.'),
 ('stripe_webhook',     'website', 'Stripe posts here. Not called by us; required by them.'),
 ('stripe_setup',       'website', 'Where the founder saves live Stripe keys.'),
 ('stripe_setup_page',  'website', 'The page that does it.'),
 ('supplier_pay',       'website', 'Supplier-side payment.'),
 ('refunds_api',        'website', 'The refund surface the portal calls.'),
 ('refund_flow',        'website', 'The refund state machine behind it.'),
 ('reveal_invoice',     'website', 'Issues the invoice for a paid reveal.'),
 ('quote_pdf',          'website', 'Renders a quotation.'),
 ('report_pdf',         'website', 'Renders a comparison report.'),
 ('report_body',        'website', 'Builds the report content.'),
 ('make_pdf',           'website', 'Generic PDF rendering the site uses.'),
 ('make_xlsx',          'website', 'Generic spreadsheet export.'),
 ('pdf_native',         'website', 'Native PDF parsing.'),
 ('send_sms',           'website', 'SMS for sign-in codes and alerts.'),
 ('resend_webhook',     'website', 'Delivery and bounce events from Resend.'),
 ('resilience_ping',    'website', 'Liveness signal the site''s status surface reads.'),
 -- The OS. Recorded under 'website' because it is a surface rather than a seat, and flagged
 -- because the founder said on 8 Sep that the OS is being fully rebuilt: this is the outgoing
 -- implementation and its owner changes when the seat that runs it exists.
 ('os_api',             'website', 'OS dashboard data. OUTGOING: the founder is rebuilding the OS.'),
 ('os_health',          'website', 'OS dashboard health panel. OUTGOING.'),
 ('os_incidents',       'website', 'OS dashboard incidents panel. OUTGOING.'),
 ('os_ops',             'website', 'OS dashboard operations panel. OUTGOING.'),
 ('os_settings',        'website', 'OS dashboard settings. OUTGOING.'),
 ('os_catalog',         'website', 'OS dashboard catalogue. OUTGOING.'),
 ('os_automation',      'website', 'OS dashboard automation panel. OUTGOING.'),
 ('agent_learnings_report','website','A report the OS dashboard generates. OUTGOING.')
on conflict (function_slug) do update
  set owner = excluded.owner, note = excluded.note, recorded_at = now();
