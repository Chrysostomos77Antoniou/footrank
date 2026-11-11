// Sends a push notification (FCM HTTP v1) to every device of one user.
//
// Called only by the database: the push_notification() trigger on
// public.notifications posts here with the internal secret in x-push-secret
// (vault `push_secret` = function secret PUSH_SECRET). Deployed with
// verify_jwt = false; the constant-time secret check below is the gate.
//
// Input: { user_id, title, body, type?, reference_id? }

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SA_JSON = Deno.env.get("FCM_SERVICE_ACCOUNT");
const PUSH_SECRET = Deno.env.get("PUSH_SECRET");

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

/// Constant-time string comparison.
function safeEqual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  }
  return diff === 0;
}

function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const bin = atob(body);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf.buffer;
}

async function getAccessToken(sa: { client_email: string; private_key: string }): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const toSign = `${header}.${claim}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(toSign)),
  );
  const jwt = `${toSign}.${b64url(sig)}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const data = await res.json();
  if (!data.access_token) throw new Error("FCM OAuth failed");
  return data.access_token as string;
}

Deno.serve(async (req) => {
  try {
    const presented = req.headers.get("x-push-secret") ?? "";
    if (!PUSH_SECRET || !safeEqual(presented, PUSH_SECRET)) {
      return json({ error: "unauthorized" }, 401);
    }
    if (!SA_JSON) return json({ error: "not_configured" }, 500);

    const sa = JSON.parse(SA_JSON);
    const { user_id, title, body, type, reference_id } = await req.json();
    if (!user_id || typeof user_id !== "string") {
      return json({ error: "user_id required" }, 400);
    }

    const supa = createClient(SUPABASE_URL, SERVICE_ROLE);
    const { data: tokens } = await supa.from("fcm_tokens").select("token").eq("user_id", user_id);
    if (!tokens || tokens.length === 0) return json({ sent: 0, reason: "no tokens" });

    const dataPayload: Record<string, string> = {};
    if (type != null) dataPayload.type = String(type);
    if (reference_id != null) dataPayload.reference_id = String(reference_id);

    const accessToken = await getAccessToken(sa);
    const projectId = sa.project_id;
    let sent = 0;
    const logRows: Record<string, unknown>[] = [];

    for (const { token } of tokens) {
      const r = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: "POST",
          headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            message: {
              token,
              notification: { title: title ?? "FootRank", body: body ?? "" },
              data: dataPayload,
              android: { priority: "high" },
            },
          }),
        },
      );
      if (r.ok) {
        sent++;
        logRows.push({ user_id, token_prefix: token.slice(0, 12), ok: true, http_status: r.status, error_text: null });
      } else {
        // Keep the FCM error code (it tells a bad token from a credential
        // problem); logs are purged after 30 days.
        const errText = (await r.text()).slice(0, 1000);
        logRows.push({ user_id, token_prefix: token.slice(0, 12), ok: false, http_status: r.status, error_text: errText });
        if (r.status === 404 || /UNREGISTERED|INVALID_ARGUMENT|NOT_FOUND/i.test(errText)) {
          await supa.from("fcm_tokens").delete().eq("user_id", user_id).eq("token", token);
        }
      }
    }

    if (logRows.length > 0) await supa.from("push_send_log").insert(logRows);
    return json({ sent, attempted: tokens.length });
  } catch (e) {
    console.error("send-push failed:", e);
    return json({ error: "internal_error" }, 500);
  }
});
