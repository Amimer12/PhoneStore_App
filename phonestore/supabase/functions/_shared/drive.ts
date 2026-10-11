// _shared/drive.ts
//
// Minimal Google Drive v3 client for the monthly-archive function: just
// enough to authenticate as YOU (via a stored OAuth refresh token — see
// below), find-or-create a "<year>" subfolder inside a fixed root folder,
// and upload one .xlsx file into it.
//
// Why not a service account: a plain (non-Workspace) service account has
// ZERO Drive storage quota of its own — Google attributes any file it
// creates to the service account itself, which has 0 bytes to give, so
// every upload fails with "storageQuotaExceeded". Workspace's "Shared
// Drives" fix this (pooled org storage), but a personal Gmail account
// doesn't have that. Authenticating as your own real account sidesteps
// the problem entirely: the file is created by you, in your own storage,
// same as if you'd dragged it into Drive by hand.
//
// Setup (one-time, outside this code):
//   1. Google Cloud Console → APIs & Services → Credentials → Create
//      Credentials → OAuth client ID → Application type: Desktop app.
//      This gives you a Client ID and Client Secret (no key file this
//      time — just two short strings).
//   2. Get a refresh token for your OWN Google account (the one that
//      owns/can see the archive folder) using Google's OAuth Playground
//      (https://developers.google.com/oauthplayground):
//        - Gear icon (top right) → check "Use your own OAuth
//          credentials" → paste in your Client ID and Client Secret.
//        - In the scopes list on the left, enter
//          https://www.googleapis.com/auth/drive.file → Authorize APIs.
//        - Sign in with your own Google account, approve.
//        - Click "Exchange authorization code for tokens" → copy the
//          Refresh token shown. Refresh tokens don't expire on their own
//          (only if revoked), so this is a one-time step.
//   3. Create the root archive folder in your own Drive as normal — no
//      sharing step needed this time, since we're acting as you, not a
//      separate service-account identity.
//   4. Store four Supabase Edge Function secrets:
//        supabase secrets set GDRIVE_OAUTH_CLIENT_ID='<from step 1>'
//        supabase secrets set GDRIVE_OAUTH_CLIENT_SECRET='<from step 1>'
//        supabase secrets set GDRIVE_OAUTH_REFRESH_TOKEN='<from step 2>'
//        supabase secrets set GDRIVE_ARCHIVE_FOLDER_ID='<folder id from step 3>'
//      (GDRIVE_SERVICE_ACCOUNT_JSON is no longer used — safe to delete.)

/** Exchanges the stored refresh token for a short-lived Drive-scoped access token. */
async function getAccessToken(clientId: string, clientSecret: string, refreshToken: string): Promise<string> {
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'refresh_token',
      client_id: clientId,
      client_secret: clientSecret,
      refresh_token: refreshToken,
    }),
  });
  if (!res.ok) throw new Error(`Google token refresh failed: ${res.status} ${await res.text()}`);
  const json = await res.json();
  return json.access_token as string;
}

async function findFolder(token: string, name: string, parentId: string): Promise<string | null> {
  const q = encodeURIComponent(
    `name = '${name.replace(/'/g, "\\'")}' and '${parentId}' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false`,
  );
  const res = await fetch(`https://www.googleapis.com/drive/v3/files?q=${q}&fields=files(id,name)`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) throw new Error(`Drive folder lookup failed: ${res.status} ${await res.text()}`);
  const json = await res.json();
  return json.files?.[0]?.id ?? null;
}

async function createFolder(token: string, name: string, parentId: string): Promise<string> {
  const res = await fetch('https://www.googleapis.com/drive/v3/files?fields=id', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, mimeType: 'application/vnd.google-apps.folder', parents: [parentId] }),
  });
  if (!res.ok) throw new Error(`Drive folder create failed: ${res.status} ${await res.text()}`);
  const json = await res.json();
  return json.id as string;
}

/** Returns the id of "<rootFolderId>/<year>", creating it if it doesn't exist yet. */
export async function ensureYearFolder(token: string, rootFolderId: string, year: number): Promise<string> {
  const name = String(year);
  const existing = await findFolder(token, name, rootFolderId);
  if (existing) return existing;
  return createFolder(token, name, rootFolderId);
}

/**
 * Uploads (or overwrites, if a file with the same name already exists in
 * that folder — re-running the same month is then safe/idempotent)
 * an .xlsx into [folderId], named [fileName].
 */
export async function uploadXlsx(
  token: string,
  folderId: string,
  fileName: string,
  bytes: Uint8Array,
): Promise<{ id: string; webViewLink: string }> {
  const existingId = await findFileId(token, fileName, folderId);

  const metadata = existingId ? {} : { name: fileName, parents: [folderId] };
  const boundary = 'phonestore-archive-boundary';
  const metaPart =
    `--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify(metadata)}\r\n`;
  const filePartHeader =
    `--${boundary}\r\nContent-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\r\n\r\n`;
  const closing = `\r\n--${boundary}--`;

  const body = new Blob([metaPart, filePartHeader, bytes, closing]);

  const url = existingId
    ? `https://www.googleapis.com/upload/drive/v3/files/${existingId}?uploadType=multipart&fields=id,webViewLink`
    : `https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink`;

  const res = await fetch(url, {
    method: existingId ? 'PATCH' : 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': `multipart/related; boundary=${boundary}` },
    body,
  });
  if (!res.ok) throw new Error(`Drive upload failed: ${res.status} ${await res.text()}`);
  return res.json();
}

async function findFileId(token: string, name: string, parentId: string): Promise<string | null> {
  const q = encodeURIComponent(
    `name = '${name.replace(/'/g, "\\'")}' and '${parentId}' in parents and trashed = false`,
  );
  const res = await fetch(`https://www.googleapis.com/drive/v3/files?q=${q}&fields=files(id)`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) throw new Error(`Drive file lookup failed: ${res.status} ${await res.text()}`);
  const json = await res.json();
  return json.files?.[0]?.id ?? null;
}

export async function driveAccessToken(): Promise<string> {
  const clientId = Deno.env.get('GDRIVE_OAUTH_CLIENT_ID');
  const clientSecret = Deno.env.get('GDRIVE_OAUTH_CLIENT_SECRET');
  const refreshToken = Deno.env.get('GDRIVE_OAUTH_REFRESH_TOKEN');
  if (!clientId) throw new Error('Missing GDRIVE_OAUTH_CLIENT_ID secret');
  if (!clientSecret) throw new Error('Missing GDRIVE_OAUTH_CLIENT_SECRET secret');
  if (!refreshToken) throw new Error('Missing GDRIVE_OAUTH_REFRESH_TOKEN secret');
  return getAccessToken(clientId, clientSecret, refreshToken);
}
