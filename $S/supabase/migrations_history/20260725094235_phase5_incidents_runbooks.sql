-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260725094235   name: phase5_incidents_runbooks
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


-- Phase 5 Epic F: incident capture, escalation, and a runbook library.
CREATE TABLE IF NOT EXISTS public.os_incidents (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title       text NOT NULL,
  kind        text NOT NULL DEFAULT 'other',
  severity    text NOT NULL DEFAULT 'medium',
  status      text NOT NULL DEFAULT 'open',
  detail      jsonb NOT NULL DEFAULT '{}'::jsonb,
  opened_by   text,
  opened_at   timestamptz NOT NULL DEFAULT now(),
  resolved_by text,
  resolved_at timestamptz,
  resolution  text
);
ALTER TABLE public.os_incidents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.os_incidents FROM anon, authenticated;

CREATE TABLE IF NOT EXISTS public.os_runbooks (
  slug        text PRIMARY KEY,
  title       text NOT NULL,
  category    text NOT NULL DEFAULT 'General',
  when_to_use text NOT NULL DEFAULT '',
  steps       text NOT NULL DEFAULT '',
  sort        int NOT NULL DEFAULT 100
);
ALTER TABLE public.os_runbooks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.os_runbooks FROM anon, authenticated;

INSERT INTO public.os_runbooks (slug, title, category, when_to_use, steps, sort) VALUES
('payment-not-recorded','A customer paid but it was not recorded','Money','A System Health error says "PAID BUT NOT RECORDED", or a supplier/customer says they paid but the platform still shows them as owing.',
 '1) Open System Health → Money reconciliation and note the mismatch. 2) Check the Audit log and stripe_webhook run notes for the payment reference. 3) The money is safely with Stripe. 4) Use Get help below to open an incident with the payment reference — a developer reconciles it against the Stripe dashboard. Do not ask the customer to pay again.',10),
('supplier-cant-register','A supplier cannot complete registration or pay the fee','Suppliers','A supplier reports they cannot register, pay the AED registration fee, or are blocked from quoting.',
 '1) Confirm in Suppliers whether their record shows registration_status. 2) Check email/SMS switches in Settings are on. 3) If they paid but still show unpaid, follow "A customer paid but it was not recorded". 4) Otherwise open an incident with the supplier name/email.',20),
('site-down','The public website is down or not loading','Site','Customers report the site is unreachable, or you see errors on the live site.',
 '1) Open Content and try Publish to trigger a fresh deploy. 2) Check System Health for failing jobs. 3) If still down, open a HIGH-severity incident — this is a hosting/deploy issue for a developer. Suppliers and existing data are safe in the meantime.',30),
('agent-bad-content','An AI agent posted or drafted something wrong or off-brand','Marketing','Marketing or an agent produced content that is incorrect, off-brand, or should not go out.',
 '1) In Settings → Kill-switches, turn OFF Marketing GO-LIVE to stop further posts. 2) In Automation, pause the relevant marketing job. 3) Fix or delete the content in Content. 4) Re-enable when safe. Open an incident only if it already went public.',40),
('cron-failing','A scheduled job keeps failing','Operations','System Health shows one or more failing scheduled jobs.',
 '1) Open Automation and find the job (status = failed). 2) Read its last message. 3) Try Run now once. 4) If it keeps failing, Pause it and open an incident with the job name and the error message.',50),
('email-not-sending','Emails or SMS are not going out','Messaging','Customers/suppliers are not receiving expected emails or texts.',
 '1) In Settings, confirm Email sending / SMS sending are ON and not over a daily cap. 2) Check System Health for messaging errors. 3) If switches are on and it still fails, open an incident (likely an email/SMS provider issue).',60),
('quote-gate-wrong','The quote gate is too strict or too lenient','Catalogue','Suppliers complain the gate rejects good quotes, or bad quotes are getting through.',
 '1) Open Categories and select the category. 2) Use "Test the gate" with a real sample quote to see which checks fail. 3) Adjust the checks (loosen/tighten the pattern, or toggle must-have). 4) Re-test until correct. No developer needed.',70),
('refund-stuck','A refund is stuck or disputed','Money','A refund is pending too long or a customer disputes a charge.',
 '1) Open Refunds and review the request. 2) Resolve it there if it is a normal case. 3) For a Stripe dispute/chargeback, open an incident with the payment reference for a developer to handle in Stripe.',80),
('data-looks-wrong','The numbers or data look wrong','Data','A report, count, or figure looks clearly incorrect.',
 '1) Cross-check in System Health (payments/ledger) and the relevant module. 2) Note exactly which figure and where. 3) Open an incident describing the expected vs shown value — do not change data manually.',90),
('integration-disconnected','A connected service stopped working','Integrations','Stripe, WhatsApp, email, Dropbox, or another integration appears disconnected.',
 '1) Check System Health and the Audit log for the failing service. 2) Integration keys are managed outside the OS for security. 3) Open a HIGH-severity incident naming the service — a developer re-authenticates it.',100)
ON CONFLICT (slug) DO UPDATE SET title=excluded.title, category=excluded.category, when_to_use=excluded.when_to_use, steps=excluded.steps, sort=excluded.sort;

-- List runbooks.
CREATE OR REPLACE FUNCTION public.fn_os_runbooks()
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  select coalesce(jsonb_agg(jsonb_build_object('slug',slug,'title',title,'category',category,'when_to_use',when_to_use,'steps',steps) order by sort, title), '[]'::jsonb)
  from public.os_runbooks;
$$;
REVOKE ALL ON FUNCTION public.fn_os_runbooks() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_os_runbooks() TO service_role;

-- Open an incident and notify the founder (best-effort).
CREATE OR REPLACE FUNCTION public.fn_os_incident_open(p_title text, p_kind text, p_severity text, p_detail jsonb, p_actor text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE nid bigint;
BEGIN
  IF coalesce(p_title,'')='' THEN RETURN jsonb_build_object('ok',false,'error','title_required'); END IF;
  INSERT INTO public.os_incidents(title, kind, severity, detail, opened_by)
  VALUES (p_title, coalesce(nullif(p_kind,''),'other'), coalesce(nullif(p_severity,''),'medium'), coalesce(p_detail,'{}'::jsonb), coalesce(p_actor,'os'))
  RETURNING id INTO nid;
  INSERT INTO public.os_audit_log(actor,action,entity,entity_id,detail,ok)
  VALUES (coalesce(p_actor,'os'),'incident_open','incident',nid::text,jsonb_build_object('title',p_title,'severity',p_severity),true);
  BEGIN
    PERFORM net.http_post(
      url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/alert_founder',
      headers := jsonb_build_object('Content-Type','application/json'),
      body := jsonb_build_object('__secret',(select value from public.app_secrets where key='inbound_secret'),
                                 'event','OS incident #'||nid||' ('||coalesce(p_severity,'medium')||'): '||p_title,
                                 'detail',left(coalesce(p_detail->>'description',''),300),'level','action')
    );
  EXCEPTION WHEN others THEN /* notification is best-effort */ END;
  RETURN jsonb_build_object('ok',true,'id',nid);
END $$;
REVOKE ALL ON FUNCTION public.fn_os_incident_open(text,text,text,jsonb,text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_os_incident_open(text,text,text,jsonb,text) TO service_role;

-- List incidents (optionally by status).
CREATE OR REPLACE FUNCTION public.fn_os_incident_list(p_status text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'title',title,'kind',kind,'severity',severity,'status',status,
    'description',detail->>'description','opened_by',opened_by,'opened_at',opened_at,
    'resolved_at',resolved_at,'resolution',resolution) order by (status='open') desc, opened_at desc), '[]'::jsonb)
  from public.os_incidents
  where p_status is null or p_status='' or status = p_status;
$$;
REVOKE ALL ON FUNCTION public.fn_os_incident_list(text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_os_incident_list(text) TO service_role;

-- Resolve an incident.
CREATE OR REPLACE FUNCTION public.fn_os_incident_resolve(p_id bigint, p_resolution text, p_actor text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.os_incidents SET status='resolved', resolved_by=coalesce(p_actor,'os'), resolved_at=now(), resolution=nullif(p_resolution,'')
  WHERE id=p_id AND status <> 'resolved';
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','not_found_or_already_resolved'); END IF;
  INSERT INTO public.os_audit_log(actor,action,entity,entity_id,detail,ok)
  VALUES (coalesce(p_actor,'os'),'incident_resolve','incident',p_id::text,jsonb_build_object('resolution',p_resolution),true);
  RETURN jsonb_build_object('ok',true);
END $$;
REVOKE ALL ON FUNCTION public.fn_os_incident_resolve(bigint,text,text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_os_incident_resolve(bigint,text,text) TO service_role;

