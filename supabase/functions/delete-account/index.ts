// Deletes the caller's own account.
//
// AUTHORIZATION: the caller must present their own valid JWT; the Auth Admin
// API call at the end only ever targets that same uid, never one supplied by
// the client.
//
// This replaces the account-deletion flow that used to run entirely inside
// public.delete_my_account(), which ended with a raw `DELETE FROM
// auth.users`. That bypassed GoTrue's own deletion path (refresh-token
// revocation, auth.sessions/auth.identities/auth.mfa_factors cleanup, and any
// configured `user.deleted` webhooks). Now: the RPC does only the
// public-schema cleanup (tombstone record, soft-disband owned teams, etc.)
// and this function finishes the job through supabase.auth.admin.deleteUser,
// which is the supported way to remove a user through GoTrue.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "unauthorized" }, 401);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
    const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
    const uid = userData?.user?.id;
    if (userErr || !uid) return json({ error: "unauthorized" }, 401);

    // Run the public-schema cleanup as the calling user, so auth.uid()
    // resolves to them inside the RPC (it is SECURITY DEFINER but still
    // reads auth.uid() from the caller's JWT claims).
    const asUser = createClient(SUPABASE_URL, SERVICE_ROLE, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    });
    const { error: rpcErr } = await asUser.rpc("delete_my_account");
    if (rpcErr) {
      console.error("delete_my_account RPC failed:", rpcErr.message);
      return json({ error: "cleanup_failed" }, 500);
    }

    // Now remove the actual auth.users row (and everything GoTrue itself
    // manages: sessions, refresh tokens, identities, MFA factors) through the
    // Admin API rather than raw SQL.
    const { error: delErr } = await admin.auth.admin.deleteUser(uid);
    if (delErr) {
      console.error("auth.admin.deleteUser failed:", delErr.message);
      return json({ error: "delete_failed" }, 500);
    }

    return json({ ok: true });
  } catch (e) {
    console.error("delete-account threw:", e);
    return json({ error: "internal_error" }, 500);
  }
});
