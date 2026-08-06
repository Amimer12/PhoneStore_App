# Admin password reset — Edge Functions

Two functions, called only by `AuthService` in the Flutter app:

- `admin-request-reset` — generates a 6-digit code, stores its hash via the
  `admin_create_reset_code` SQL function, sends it over WhatsApp (name + code).
- `admin-confirm-reset` — verifies the code + sets the new password via the
  `admin_reset_password` SQL function.

The WhatsApp template (`whatsapp_template`, category Utility) takes two
variables in this exact order: `{{1}}` = admin's name, `{{2}}` = the code.

## 1. Install the Supabase CLI (skip if you already have it)

Check first:
```bash
supabase --version
```
If that fails:

- **macOS**: `brew install supabase/tap/supabase`
- **Windows**: `scoop bucket add supabase https://github.com/supabase/scoop-bucket.git` then `scoop install supabase`
- **Linux**: `brew install supabase/tap/supabase` (Homebrew works on Linux too), or download the `.deb`/`.rpm` from https://github.com/supabase/cli/releases

## 2. Log in and link this project

From your project's root folder (the one containing `lib/`, or wherever you
put the `supabase/` folder from this zip):

```bash
supabase login
```
This opens a browser to authorize the CLI once.

```bash
supabase link --project-ref <your-project-ref>
```
Find `<your-project-ref>` in your Supabase project's dashboard URL:
`https://supabase.com/dashboard/project/<your-project-ref>`.

## 3. Make sure the function files are in the right place

This zip's structure is already correct — just make sure, after unzipping,
you have:
```
supabase/
  functions/
    _shared/
      cors.ts
      whatsapp.ts
    admin-request-reset/
      index.ts
    admin-confirm-reset/
      index.ts
```
right at your project root (same level as `pubspec.yaml`, not inside `lib/`).
If you already have a `supabase/` folder from `supabase init`, just merge
the `functions/` subfolder in — don't overwrite `config.toml` if one exists.

## 4. One-time WhatsApp setup (Meta side) — you've already done this

Recap of what you now have, for reference:
- A WhatsApp Business app with a Phone Number ID
- A permanent System User access token
- An approved Utility-category template (`whatsapp_template`) with two body
  variables: name, then code

## 5. Set the secrets (server-side only — never in the Flutter .env)

```bash
supabase secrets set WHATSAPP_TOKEN=EAAG...your-permanent-token
supabase secrets set WHATSAPP_PHONE_NUMBER_ID=1226970007170476
supabase secrets set WHATSAPP_SENDER_NUMBER=+213xxxxxxxxx
supabase secrets set WHATSAPP_TEMPLATE_NAME=whatsapp_template
supabase secrets set WHATSAPP_TEMPLATE_LANG=fr
supabase secrets set WHATSAPP_ADMIN_NAME="Karim"
supabase secrets set ADMIN_PHONE_NUMBER=+213559630016
```

Notes on each:
- `WHATSAPP_TEMPLATE_LANG` must exactly match what the template page shows
  (`fr` if it says French, `en_US` if English — not just `en`).
- `WHATSAPP_ADMIN_NAME` fills `{{1}}` — the person's name shown in the
  message. Change it later anytime with the same command, no redeploy needed.
- `ADMIN_PHONE_NUMBER` fills the recipient — same story, one command to change.
- `WHATSAPP_SENDER_NUMBER` is just for logs/error messages, doesn't affect
  the actual send (that's controlled by `WHATSAPP_PHONE_NUMBER_ID`).

You can confirm what's set (values are hidden) with:
```bash
supabase secrets list
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` don't need to be set manually
— Supabase injects them automatically into every Edge Function's environment.

## 6. Run the SQL migrations first

Both functions call Postgres RPCs (`admin_create_reset_code`,
`admin_reset_password`) that only exist after the migrations in
`/migrations` have been run (in particular `6_password_and_roles_FIXED.sql`),
and those RPCs are granted to `service_role` only — run the SQL before
deploying the functions, or the first reset attempt will fail with a
"function does not exist" / permission error.

## 7. Deploy

```bash
supabase functions deploy admin-request-reset
supabase functions deploy admin-confirm-reset
```
Each command uploads that one function (plus the shared `_shared/` files it
imports) and prints a URL like:
```
https://<your-project-ref>.supabase.co/functions/v1/admin-request-reset
```

## 8. Enable Anonymous Sign-Ins (easy to forget, breaks everything if skipped)

Supabase Dashboard → **Authentication → Providers → Anonymous Sign-Ins → On**.
Without this, `signInAnonymously()` in the app fails and neither worker nor
admin can log in at all.

## 9. Test before touching the Flutter app

```bash
curl -i -X POST https://pmewcpruorkocdafvzqh.supabase.co/functions/v1/admin-request-reset \
  -H "Authorization: Bearer <your anon key>"
```
Expected: `{"success":true}` and a WhatsApp message arrives with the name
and a 6-digit code. Then:
```bash
curl -i -X POST https://pmewcpruorkocdafvzqh.supabase.co/functions/v1/admin-confirm-reset \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBtZXdjcHJ1b3Jrb2NkYWZ2enFoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ4OTgyNDMsImV4cCI6MjEwMDQ3NDI0M30.yqFvtZylKYFVgEQcqeaxu-7ff3Rb5ha1dCb2T3-78No" \
  -H "Content-Type: application/json" \
  -d '{"code":"089866","new_password":"adminadmin"}'
```
Expected: `{"success":true}`.

If either fails, the response body's error message will point at exactly
which secret, RPC, or permission is off — paste it back if unsure.

## 10. Redeploying after a code change

Any time you edit `whatsapp.ts`, `cors.ts`, or either `index.ts`, redeploy
the function(s) that use it:
```bash
supabase functions deploy admin-request-reset
supabase functions deploy admin-confirm-reset
```
Secrets do NOT need to be re-set after a code change — they persist on the
project independently of deployments.
