# Morning steps: two read-only connections for the daily inbox check

This is the only step left before the supplier invitations can start. Each morning, before the batch, the system
sends one test copy of the invitation to your Gmail and your Outlook and reads which folder it landed in. Today it
cannot read either inbox, so it holds every batch. These two connections give it read-only access to those two
mailboxes and nothing else.

You will never copy or paste a token. Two values (the Microsoft app's ID and secret) are pasted into one
table. Everything else is done by clicking links.

Time needed: about 15 minutes.

---

## Part 1: Gmail (ahmadmhdnabilalzain@gmail.com)

### 1a. Prepare the Google app (one time)

1. Open https://console.cloud.google.com/apis/credentials and select the project that contains the OAuth client
   whose ID starts with **171885262684-edh7n9h2636** (the one the YouTube connection uses).
2. Click that OAuth 2.0 client ID. Under **Authorised redirect URIs**, click **+ Add URI** and paste:
   `https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/oauth_connect/callback`
   Then click **Save**.
3. Open https://console.cloud.google.com/apis/library/gmail.googleapis.com and click **Enable**. If it says
   "Manage", it is already on.
4. Open https://console.cloud.google.com/apis/credentials/consent (OAuth consent screen):
   - **Data access / Scopes** → **Add or remove scopes** → add `https://www.googleapis.com/auth/gmail.readonly` → **Update** → **Save**.
   - **Audience / Publishing status** must say **In production**. If it says "Testing", click **Publish app**.
     In Testing, the connection stops after 7 days. An unverified app is fine for your own account.

### 1b. Connect (one click)

5. Signed in to Chrome as **ahmadmhdnabilalzain@gmail.com**, open:
   https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/oauth_connect/start?provider=gmail_seed
6. Choose that Gmail account. If Google shows "Google hasn't verified this app", click **Advanced** → **Go to
   … (unsafe)**. It is your own app. Then click **Continue** / **Allow** for "Read your email".
7. The page must say **Connected: Gmail seed inbox ✓**.
   This stores `gmail_seed_refresh_token` by itself. Nothing to paste.

---

## Part 2: Outlook (management@doratajewelries.com)

### 2a. Create the Microsoft app (one time)

1. Open https://entra.microsoft.com and sign in as an admin of **doratajewelries.com**.
2. Go to **Applications → App registrations → + New registration**.
   - Name: `QuotesDone inbox check`
   - Supported account types: **Accounts in this organizational directory only (Single tenant)**
   - Redirect URI: platform **Web**, value
     `https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/oauth_connect/callback`
   - Click **Register**.
3. On the app's **Overview** page, copy two values. You will paste them in step 2b:
   - **Application (client) ID**
   - **Directory (tenant) ID**
4. Go to **Certificates & secrets → Client secrets → + New client secret**. Description `inbox check`,
   expiry **24 months** → **Add**. Copy the **Value** column now. It is shown only once.
5. Go to **API permissions → + Add a permission → Microsoft Graph → Delegated permissions**. Tick **Mail.Read**,
   **User.Read** and **offline_access** → **Add permissions**. Then click **Grant admin consent for doratajewelries** → **Yes**.

### 2b. Store the three values (one time)

6. Open https://supabase.com/dashboard/project/htdblwldjkcgjvmqkbeh/editor and open the table **app_secrets**.
7. Click **Insert → Insert row** three times, one row per value:

   | key | value |
   |---|---|
   | `ms_graph_client_id` | the Application (client) ID from step 3 |
   | `ms_graph_tenant_id` | the Directory (tenant) ID from step 3 |
   | `ms_graph_client_secret` | the secret Value from step 4 |

   Click **Save** after each row.

### 2c. Connect (one click)

8. Signed in as **management@doratajewelries.com**, open:
   https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/oauth_connect/start?provider=ms_graph_seed
9. Accept the permissions. The page must say **Connected: Outlook seed inbox ✓**.
   This stores `ms_graph_seed_refresh_token` by itself.

---

## When both pages say Connected

Tell Claude: **"both seed inboxes connected"**. Claude then:
- confirms both connections are stored. Each "Connected" page already proved it can read that mailbox, because it
  checks the account through Gmail / Microsoft before storing anything;
- switches sending on (`invite_enabled` and `supplier_outreach_golive`). That same morning the system sends the
  test copy to both inboxes and reads where it landed. The batch goes only if that reading succeeds. If it fails,
  the batch is held and nothing is sent.
- **Timing:** the test copy is only sent between 08:30 and 11:30 Dubai on a working day. If both pages say
  Connected and Claude switches on before **11:30 Dubai**, today's 20 invitations go out between about 12:00 and
  17:00 Dubai. Later than that, the first batch is the next working day.

If either page shows an error instead of "Connected", copy the error sentence (it never contains a secret) and send it to Claude.
