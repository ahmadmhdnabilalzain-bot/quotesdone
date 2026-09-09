-- AN AGENT CAN ATTACH A DOCUMENT TO THE MAIL IT SENDS.
--
-- The founder, 9 Sep 2026: "create weekly report as pdf and share it with me and the CEO", and then
-- "i want the agent to do that cause we wanna test him". Measured the same day, before writing this:
--
--   public.notifications          19 columns. NOT ONE of them can carry a document.
--   supabase/functions/send_outbox  214 lines. The Resend payload is built as
--                                 { from, to, reply_to, subject, html } and the word "attachment"
--                                 does not appear anywhere in the file.
--
-- So on the morning of 9 Sep the whole estate could not email anybody a file. Every agent that
-- produces a document -- the accountant's weekly financial report, the compliance archive's signed
-- T&C, any future statement -- could only ever send a LINK to it. A signed link is not the document:
-- it expires (the accountant's is seven days), it breaks if the object is moved, and it is useless
-- to a founder reading mail on a phone away from his session.
--
-- This file adds the carriage and nothing else. It does not decide what any agent attaches; it makes
-- attaching possible and refuses the shapes that would be dangerous.
--
-- WHY A REFERENCE AND NOT THE BYTES. attachments holds {bucket, path, filename} and send_outbox
-- fetches the object from storage at send time. Putting base64 in notifications would put a 90 KB
-- PDF -- soon a 5 MB one -- inside a row that a poller selects forty at a time every two minutes.
-- The document already lives in storage under its own retention; the mail should point at it, not
-- copy it.
--
-- WHY A TRIGGER THAT RAISES, NOT A SILENT DROP. The BEFORE INSERT trigger a10_notifications_
-- founder_mail_policy returns NULL for an unregistered kind, so the row is silently not inserted.
-- That is right for a policy decision -- the mail was not meant to be sent. It is exactly wrong for
-- a malformed attachment: the agent DID mean to send it, and a silent drop would leave the seat
-- believing it delivered a report that never existed. a20 raises, so the caller learns.
--
-- WHAT IS REFUSED, and why each one:
--   * a bucket outside the allow-list  -- an attachment is read with the service role, so an
--     unconstrained path is a file-read primitive. Only buckets that hold agent-produced documents
--     are allowed. 'signed-terms', 'quote-files', 'supplier-docs' and every public bucket are NOT
--     on it: those hold other parties' documents, and mailing one to a founder address on the
--     strength of a jsonb field is not a thing this table should be able to express.
--   * '..' anywhere in the path      -- path traversal.
--   * a filename outside [A-Za-z0-9 ._-] -- a filename crosses into a MIME header and a recipient's
--     filesystem. Refuse quotes, newlines, semicolons and slashes rather than escape them.
--   * more than 5 attachments        -- a covering email, not a bulk transfer.
-- Size is NOT checked here: this row holds no bytes, so the row cannot know. send_outbox enforces
-- the byte ceiling at send time, where the size is a fact rather than a claim.

alter table public.notifications
  add column if not exists attachments jsonb;

comment on column public.notifications.attachments is
  'Documents to attach, as a jsonb array of {bucket, path, filename} references -- never the bytes. '
  'send_outbox downloads each object with the service role at send time, base64-encodes it into the '
  'Resend attachments field, and FAILS THE ROW if any one of them cannot be read, so a covering '
  'email never goes out without the document it describes. Validated by a20_notifications_'
  'attachment_policy, which raises rather than dropping the row. Added 9 Sep 2026: before it, no '
  'agent in the estate could email a file to anyone.';

create or replace function public.fn_notification_attachment_policy()
returns trigger language plpgsql set search_path to 'public','pg_temp' as $function$
declare
  v_a jsonb; v_bucket text; v_path text; v_file text; v_n int;
begin
  if new.attachments is null then return new; end if;

  if jsonb_typeof(new.attachments) <> 'array' then
    raise exception 'notifications.attachments must be a jsonb ARRAY of {bucket, path, filename}, got %',
      jsonb_typeof(new.attachments);
  end if;

  v_n := jsonb_array_length(new.attachments);
  if v_n = 0 then
    -- An empty array is the caller saying "attach nothing", which is what NULL means. Normalise it
    -- so send_outbox has one shape to read and cannot tell the two apart.
    new.attachments := null;
    return new;
  end if;
  if v_n > 5 then
    raise exception 'notifications.attachments holds % entries; a covering email carries at most 5', v_n;
  end if;

  for v_a in select jsonb_array_elements(new.attachments) loop
    v_bucket := v_a->>'bucket'; v_path := v_a->>'path'; v_file := v_a->>'filename';

    if v_bucket is null or v_path is null or v_file is null then
      raise exception 'each attachment needs bucket, path and filename; got %', v_a::text;
    end if;

    -- The allow-list. Every bucket here holds documents THIS COMPANY generated for itself.
    if v_bucket not in ('finance-reports','finance-docs','agent-docs','reports','compliance-docs') then
      raise exception 'attachment bucket % is not attachable. Allowed: finance-reports, finance-docs, agent-docs, reports, compliance-docs', v_bucket;
    end if;

    if v_path = '' or v_path like '%..%' then
      raise exception 'attachment path % is refused (empty, or contains "..")', v_path;
    end if;

    if v_file !~ '^[A-Za-z0-9 ._-]{1,120}$' then
      raise exception 'attachment filename % is refused: only letters, digits, space, dot, underscore and hyphen, up to 120 characters', v_file;
    end if;
  end loop;

  return new;
end;
$function$;

comment on function public.fn_notification_attachment_policy() is
  'Validates notifications.attachments on write. RAISES on a malformed or unsafe reference rather '
  'than dropping the row the way the founder-mail policy does: a bad attachment means the sending '
  'agent made a mistake it must learn about, not that the mail was unwanted. Enforces the bucket '
  'allow-list (an attachment is read with the service role, so an open path would be a file-read '
  'primitive), refuses path traversal and refuses filenames carrying characters that cross into a '
  'MIME header. Byte size is deliberately NOT checked here -- the row holds no bytes; send_outbox '
  'enforces the ceiling at send time where the size is a fact.';

drop trigger if exists a20_notifications_attachment_policy on public.notifications;
create trigger a20_notifications_attachment_policy
  before insert or update of attachments on public.notifications
  for each row execute function public.fn_notification_attachment_policy();

-- CLOSING ASSERTION. Proves the column exists, the trigger is attached and firing, that a good
-- reference passes, and that each refusal actually refuses. Everything is done inside this
-- transaction's own savepoints and nothing survives.
do $do$
declare
  v_col int; v_trg int; v_ok boolean;
  v_good jsonb := '[{"bucket":"finance-reports","path":"2026/w37/report.pdf","filename":"Weekly_Financial_Report.pdf"}]'::jsonb;
  v_id bigint;
begin
  select count(*) into v_col from information_schema.columns
   where table_schema='public' and table_name='notifications' and column_name='attachments';
  if v_col <> 1 then raise exception 'attachments column missing'; end if;

  select count(*) into v_trg from pg_trigger
   where tgrelid = 'public.notifications'::regclass and tgname = 'a20_notifications_attachment_policy'
     and not tgisinternal;
  if v_trg <> 1 then raise exception 'a20_notifications_attachment_policy not attached'; end if;

  -- POSITIVE CONTROL FIRST. If a well-formed reference cannot be written, every refusal below is
  -- meaningless -- a trigger that rejects everything would "pass" all four negative cases.
  insert into public.notifications(type, kind, to_email, to_role, channel, subject, body, attachments)
  values ('zz_demo_attachment_probe', 'founder_brief', 'probe@example.invalid', 'admin', 'email',
          'ZZ DEMO attachment carriage probe', 'probe', v_good)
  returning id into v_id;
  if v_id is null then
    raise exception 'POSITIVE CONTROL FAILED: a well-formed attachment reference was not written';
  end if;

  -- Now each refusal. Any one of these succeeding is a hole.
  begin
    v_ok := false;
    insert into public.notifications(type, kind, to_email, to_role, channel, subject, body, attachments)
    values ('zz_demo_attachment_probe','founder_brief','probe@example.invalid','admin','email','x','x',
            '[{"bucket":"signed-terms","path":"a.pdf","filename":"a.pdf"}]'::jsonb);
    v_ok := true;
  exception when others then null; end;
  if v_ok then raise exception 'HOLE: a bucket outside the allow-list was accepted'; end if;

  begin
    v_ok := false;
    insert into public.notifications(type, kind, to_email, to_role, channel, subject, body, attachments)
    values ('zz_demo_attachment_probe','founder_brief','probe@example.invalid','admin','email','x','x',
            '[{"bucket":"reports","path":"../../etc/passwd","filename":"a.pdf"}]'::jsonb);
    v_ok := true;
  exception when others then null; end;
  if v_ok then raise exception 'HOLE: a traversal path was accepted'; end if;

  begin
    v_ok := false;
    insert into public.notifications(type, kind, to_email, to_role, channel, subject, body, attachments)
    values ('zz_demo_attachment_probe','founder_brief','probe@example.invalid','admin','email','x','x',
            '[{"bucket":"reports","path":"a.pdf","filename":"a\";rm -rf /.pdf"}]'::jsonb);
    v_ok := true;
  exception when others then null; end;
  if v_ok then raise exception 'HOLE: a filename carrying quote and semicolon was accepted'; end if;

  begin
    v_ok := false;
    insert into public.notifications(type, kind, to_email, to_role, channel, subject, body, attachments)
    values ('zz_demo_attachment_probe','founder_brief','probe@example.invalid','admin','email','x','x',
            '{"bucket":"reports"}'::jsonb);
    v_ok := true;
  exception when others then null; end;
  if v_ok then raise exception 'HOLE: a non-array attachments value was accepted'; end if;

  delete from public.notifications where type = 'zz_demo_attachment_probe';
  if exists (select 1 from public.notifications where type = 'zz_demo_attachment_probe') then
    raise exception 'probe rows were not cleaned up';
  end if;

  raise notice 'attachment carriage: column present, trigger firing, 1 positive control written, 4 refusals held, 0 probe rows left';
end
$do$;
