// _shared/drive.ts
//
// Minimal Google Drive v3 client for the monthly-archive function: just
// enough to authenticate as a service account, find-or-create a "<year>"
// subfolder inside a fixed root folder, and upload one .xlsx file into it.
//
// Setup (one-time, outside this code):
//   1. Google Cloud Console → create a project (or reuse one) → APIs &
//      Services → Credentials → Create a Service Account → Keys → Add key
//      (JSON). Enable the "Google Drive API" for that project.
//   2. In Google Drive, create the root archive folder (e.g.
//      "PhoneStore Archives"), open its sharing settings, and share it
//      with the service account's email (looks like
//      xxxx@yyyy.iam.gserviceaccount.com) as Editor. The service account
//      has NO storage of its own — it can only write into folders a real
//      human has explicitly shared with it.
//   3. Copy that folder's id from its URL
//      (drive.google.com/drive/folders/<THIS_PART>).
//   4. Store two Supabase Edge Function secrets:
//        supabase secrets set GDRIVE_SERVICE_ACCOUNT_JSON='<paste the whole downloaded JSON>'
//        supabase secrets set GDRIVE_ARCHIVE_FOLDER_ID='<folder id from step 3>'

interface ServiceAccountKey {
  client_email: string;
  private_key: string;
}

/** Base64url-encode, no padding — what JWT wants. */
function b64url(bytes: ArrayBuffer | string): string {
  const raw = typeof bytes === 'string' ? new TextEncoder().encode(bytes) : new Uint8Array(bytes);
  let str = '';
  for (const b of raw) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const clean = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const der = Uint8Array.from(atob(clean), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    'pkcs8',
    der.buffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

/** Exchanges the service-account key for a short-lived Drive-scoped access token (JWT bearer grant, RFC 7523). */
async function getAccessToken(key: ServiceAccountKey): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claims = {
    iss: key.client_email,
    scope: 'https://www.googleapis.com/auth/drive.file',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claims))}`;
  const cryptoKey = await importPrivateKey(key.private_key);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, new TextEncoder().encode(unsigned));
  const jwt = `${unsigned}.${b64url(sig)}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error(`Google token exchange failed: ${res.status} ${await res.text()}`);
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
  const raw = Deno.env.get('GDRIVE_SERVICE_ACCOUNT_JSON');
  if (!raw) throw new Error('Missing GDRIVE_SERVICE_ACCOUNT_JSON secret');
  const key = JSON.parse(raw) as ServiceAccountKey;
  return getAccessToken(key);
}
