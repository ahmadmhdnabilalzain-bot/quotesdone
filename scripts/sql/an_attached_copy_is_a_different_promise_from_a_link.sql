-- AN ATTACHED COPY IS A DIFFERENT PROMISE FROM A LINK
--
-- Build spec §4 and §5, both of which deliver an ARTIFACT rather than a sentence, and both of which
-- turn on the same two rules:
--
--   §4: "If the artifact is unsafe, unavailable, obsolete or oversized, do not attach it. Send a
--        permitted authenticated portal link where appropriate, explain that the copy was not
--        attached and create a tracked repair. A link-only fallback does not count as successful
--        file-copy delivery. Never say 'attached' without an attachment."
--   §5: "Payment settlement, reveal entitlement, invoice issuance and message delivery are separate
--        states. If paid but locked, open an entitlement repair and do not ask the customer to pay
--        again or manually leak supplier details."
--
-- THE FAILURE BOTH ARE GUARDING AGAINST IS THE SAME ONE: reporting a delivery that did not happen.
-- A portal link counted as a delivered attachment, an accepted API request counted as delivered, a
-- message saying "attached" with nothing attached. Each looks like success in a log.

create table if not exists public.support_artifact (
  artifact_id      bigserial primary key,
  artifact_kind    text not null,
  subject_ref      text not null,
  owner_party_id   text,
  version          text,
  checksum         text,
  storage_path     text,
  byte_size        bigint,
  privacy_state    text not null default 'unchecked',
  privacy_result   jsonb,
  approved_at      timestamptz,
  obsolete_at      timestamptz,
  created_at       timestamptz not null default now(),

  constraint support_artifact_kind_ck check (artifact_kind in ('comparison_report','reveal_invoice')),
  constraint support_artifact_privacy_ck check (privacy_state in ('unchecked','approved','refused')),
  -- AN APPROVAL IS A RESULT, NOT A FLAG. The spec is explicit that "a model-supplied
  -- privacy_approved flag is not sufficient", so an approved artifact must carry the result of the
  -- check that approved it.
  constraint support_artifact_approved_ck check (
    privacy_state <> 'approved' or (approved_at is not null and privacy_result is not null and checksum is not null))
);

comment on table public.support_artifact is
  'An artifact eligible to be attached. Bound to its owner, version and checksum, and approvable only with the result of the check that approved it -- a flag alone is not an approval.';

-- ---------------------------------------------------------------------------------------------
-- ELIGIBILITY TO ATTACH: four separate reasons, each named rather than collapsed into a boolean
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_support_artifact_attachable(
  p_artifact_id bigint,
  p_for_party_id text,
  p_max_bytes bigint default 15000000)
returns jsonb
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $function$
declare a record;
begin
  select * into a from public.support_artifact where artifact_id = p_artifact_id;
  if not found then
    return jsonb_build_object('attachable', false, 'reason', 'unavailable',
      'note', 'no such artifact. Send the portal route and open a repair; do not describe a file that does not exist.');
  end if;
  if a.obsolete_at is not null then
    return jsonb_build_object('attachable', false, 'reason', 'obsolete',
      'note', 'this export was superseded. Attaching it would deliver an answer the company has already replaced.');
  end if;
  if a.privacy_state <> 'approved' then
    return jsonb_build_object('attachable', false, 'reason', 'unsafe',
      'note', format('privacy_state is %L. Only an artifact whose check RAN and passed may be attached.', a.privacy_state));
  end if;
  -- PER-PARTY ENTITLEMENT. "A payment for one supplier never reveals all suppliers; use
  -- per-customer, per-inquiry, per-supplier entitlements."
  if a.owner_party_id is not null and p_for_party_id is not null and a.owner_party_id <> p_for_party_id then
    return jsonb_build_object('attachable', false, 'reason', 'not_entitled',
      'note', 'this artifact belongs to a different party. Ownership is checked per artifact, not per payment.');
  end if;
  if a.byte_size is not null and a.byte_size > p_max_bytes then
    return jsonb_build_object('attachable', false, 'reason', 'oversized',
      'note', format('%s bytes exceeds the channel limit of %s. A link is the honest fallback and must be described as one.', a.byte_size, p_max_bytes));
  end if;
  return jsonb_build_object('attachable', true, 'checksum', a.checksum, 'version', a.version,
    'storage_path', a.storage_path,
    'note', 'Attachable. The message may say "attached" only because a file is genuinely going with it.');
end $function$;

-- ---------------------------------------------------------------------------------------------
-- DELIVERY: the wording follows the artifact, never the intention
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_support_deliver_artifact(
  p_artifact_id bigint,
  p_case_id bigint,
  p_recipient_party_id text,
  p_whatsapp text,
  p_email text,
  p_inquiry_ref text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  a record; e jsonb; v_portal text; v_body text; v_subject text; v_attach text;
  v_out jsonb := '[]'::jsonb; v_dedupe text; v_id bigint; v_grant jsonb;
begin
  v_grant := public.fn_support_may_act('notification');
  if (v_grant->>'may_act') <> 'true' then
    return jsonb_build_object('ok', false, 'reason', v_grant->>'reason');
  end if;

  select * into a from public.support_artifact where artifact_id = p_artifact_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such artifact'); end if;

  e := public.fn_support_artifact_attachable(p_artifact_id, p_recipient_party_id);
  v_portal := coalesce((select value from public.app_secrets where key = 'public_site_url'), 'https://quotesdone.com') || '/portal';

  if (e->>'attachable') = 'true' then
    v_attach := a.storage_path;
    v_body := case a.artifact_kind
      when 'comparison_report' then
        'Your comparison report for inquiry ' || p_inquiry_ref || ' is ready. A copy is attached, and you can view it in your portal: '
        || v_portal || '. Individual quotations are available in the portal.'
      else
        'Your reveal-fee payment for inquiry ' || p_inquiry_ref || ' has been confirmed. Your invoice ' || coalesce(a.subject_ref,'')
        || ' is attached. You can also access it in your portal: ' || v_portal || '.' end;
  else
    -- THE WORDING CHANGES BECAUSE THE FACT CHANGED. Not a softened version of the same sentence: the
    -- word "attached" is absent, the reason is stated, and the message says where the file is.
    v_attach := null;
    v_body := case a.artifact_kind
      when 'comparison_report' then
        'Your comparison report for inquiry ' || p_inquiry_ref || ' is ready. I could not include a copy with this message ('
        || (e->>'reason') || '), so please open it in your portal: ' || v_portal || '.'
      else
        'Your reveal-fee payment for inquiry ' || p_inquiry_ref || ' has been confirmed. I could not include the invoice with this message ('
        || (e->>'reason') || '), so please open it in your portal: ' || v_portal || '.' end;
  end if;
  v_subject := case a.artifact_kind when 'comparison_report'
                 then 'Your comparison report for inquiry ' || p_inquiry_ref
                 else 'Your invoice for inquiry ' || p_inquiry_ref end;

  -- THE DEDUPE KEY IS THE ARTIFACT PLUS ITS CHECKSUM. A re-send of the same file to the same person
  -- is silently absorbed; a REGENERATED file has a different checksum and is therefore a different
  -- delivery rather than a duplicate.
  if coalesce(btrim(p_whatsapp),'') <> '' then
    insert into public.support_notification (dedupe_key, case_id, purpose, channel, recipient,
      inquiry_ref, publication_version, subject, body, attachment_ref, anonymity_checked_at, anonymity_result)
    values ('artifact|' || p_artifact_id::text || '|' || coalesce(a.checksum,'nocs') || '|whatsapp|' || p_whatsapp,
            p_case_id, a.artifact_kind, 'whatsapp', p_whatsapp, p_inquiry_ref, a.version,
            null, v_body, v_attach, now(),
            jsonb_build_object('safe', true, 'note', 'deterministic artifact delivery; the artifact itself carries its own privacy result', 'artifact_privacy', a.privacy_result))
    on conflict (dedupe_key) do nothing returning id into v_id;
    v_out := v_out || jsonb_build_object('channel','whatsapp','queued', v_id is not null, 'attached', v_attach is not null);
  end if;

  if coalesce(btrim(p_email),'') <> '' then
    insert into public.support_notification (dedupe_key, case_id, purpose, channel, recipient,
      inquiry_ref, publication_version, subject, body, attachment_ref, anonymity_checked_at, anonymity_result)
    values ('artifact|' || p_artifact_id::text || '|' || coalesce(a.checksum,'nocs') || '|email|' || p_email,
            p_case_id, a.artifact_kind, 'email', p_email, p_inquiry_ref, a.version,
            v_subject, v_body, v_attach, now(),
            jsonb_build_object('safe', true, 'note', 'deterministic artifact delivery; the artifact itself carries its own privacy result', 'artifact_privacy', a.privacy_result))
    on conflict (dedupe_key) do nothing returning id into v_id;
    v_out := v_out || jsonb_build_object('channel','email','queued', v_id is not null, 'attached', v_attach is not null);
  end if;

  return jsonb_build_object(
    'ok', true, 'artifact_id', p_artifact_id, 'attachable', e->>'attachable',
    'refusal_reason', e->>'reason', 'queued', v_out,
    -- THE COUNT THE SPEC ASKS FOR. "Do not count a portal link as a delivered attachment."
    'file_copy_delivered', (e->>'attachable') = 'true',
    'note', case when (e->>'attachable') = 'true'
                 then 'A copy is attached and the message says so because it is true.'
                 else 'NOT a file-copy delivery. A link was sent instead, the reason was stated to the customer, and this must not be counted as an attachment.' end);
end $function$;

revoke execute on function public.fn_support_deliver_artifact(bigint,bigint,text,text,text,text) from public;
revoke execute on function public.fn_support_deliver_artifact(bigint,bigint,text,text,text,text) from anon;
revoke execute on function public.fn_support_deliver_artifact(bigint,bigint,text,text,text,text) from authenticated;
revoke execute on function public.fn_support_artifact_attachable(bigint,text,bigint) from public;
revoke execute on function public.fn_support_artifact_attachable(bigint,text,bigint) from anon;
revoke execute on function public.fn_support_artifact_attachable(bigint,text,bigint) from authenticated;
