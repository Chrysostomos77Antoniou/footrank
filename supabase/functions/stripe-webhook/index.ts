// Stripe -> FootRank webhook. This is the ONLY thing allowed to mark a fee as
// paid: the app never reports its own payment state (a client that could would
// be able to play for free).
//
// Must be deployed with verify_jwt = false -- Stripe cannot send a Supabase
// JWT. Authentication is instead the Stripe-Signature header, verified below
// with STRIPE_WEBHOOK_SECRET. An unverified request is rejected outright.
//
// Every handler is idempotent and forward-only: Stripe retries on any non-2xx
// and can deliver events out of order, so a late 'pending' must never overwrite
// a 'succeeded'.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const WEBHOOK_SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET");

/// Reject events older than this to blunt replay attempts (Stripe's own
/// recommended tolerance).
const TOLERANCE_SECONDS = 300;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function hmacSha256Hex(secret: string, payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload)),
  );
  return Array.from(sig).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/// Verifies Stripe's `t=...,v1=...` signature header against the raw body.
/// Returns the parsed event, or null if the signature doesn't check out.
async function verify(rawBody: string, header: string | null, secret: string) {
  if (!header) return null;

  let timestamp = "";
  const candidates: string[] = [];
  for (const part of header.split(",")) {
    const [k, v] = part.split("=", 2);
    if (k?.trim() === "t") timestamp = v?.trim() ?? "";
    // Stripe may send several v1 signatures during a secret rotation.
    if (k?.trim() === "v1" && v) candidates.push(v.trim());
  }
  if (!timestamp || candidates.length === 0) return null;

  const age = Math.abs(Math.floor(Date.now() / 1000) - Number(timestamp));
  if (!Number.isFinite(age) || age > TOLERANCE_SECONDS) return null;

  const expected = await hmacSha256Hex(secret, `${timestamp}.${rawBody}`);
  if (!candidates.some((c) => timingSafeEqual(c, expected))) return null;

  try {
    return JSON.parse(rawBody);
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  if (!WEBHOOK_SECRET) {
    console.error("STRIPE_WEBHOOK_SECRET not set -- refusing to trust any event");
    return json({ error: "webhook not configured" }, 500);
  }

  // Must read the raw text: re-serializing the JSON would change the bytes and
  // invalidate the signature.
  const rawBody = await req.text();
  const event = await verify(rawBody, req.headers.get("Stripe-Signature"), WEBHOOK_SECRET);
  if (!event) return json({ error: "invalid signature" }, 400);

  const supa = createClient(SUPABASE_URL, SERVICE_ROLE);

  try {
    switch (event.type) {
      case "payment_intent.succeeded": {
        const pi = event.data.object;
        // Forward-only, and scoped by payment-intent id so a replay is a no-op.
        const { data: rows, error } = await supa
          .from("match_payments")
          .update({
            status: "succeeded",
            paid_at: new Date().toISOString(),
            failure_reason: null,
          })
          .eq("stripe_payment_intent_id", pi.id)
          .neq("status", "refunded")
          .select("match_id");
        if (error) throw error;

        const matchId = rows?.[0]?.match_id ?? pi.metadata?.match_id;
        if (matchId) {
          await supa.rpc("recalc_match_payment_status", { p_match_id: matchId });
        }
        break;
      }

      case "payment_intent.payment_failed": {
        const pi = event.data.object;
        const reason = pi.last_payment_error?.message ??
          pi.last_payment_error?.code ?? "card declined";
        // Only a still-pending row may go to failed -- never downgrade a
        // succeeded one on a late-arriving failure for an earlier attempt.
        const { error } = await supa
          .from("match_payments")
          .update({ status: "failed", failure_reason: String(reason).slice(0, 500) })
          .eq("stripe_payment_intent_id", pi.id)
          .eq("status", "pending");
        if (error) throw error;
        break;
      }

      case "charge.refunded": {
        const charge = event.data.object;
        const piId = charge.payment_intent;
        if (!piId) break;
        const { data: rows, error } = await supa
          .from("match_payments")
          .update({ status: "refunded", refunded_at: new Date().toISOString() })
          .eq("stripe_payment_intent_id", piId)
          .select("match_id");
        if (error) throw error;

        const matchId = rows?.[0]?.match_id;
        if (matchId) {
          await supa.rpc("recalc_match_payment_status", { p_match_id: matchId });
        }
        break;
      }

      case "charge.dispute.created": {
        // A chargeback costs far more than the €2 fee, so it needs a human.
        // Recorded rather than auto-actioned: refunding or re-charging on a
        // dispute is a judgement call, not something a webhook should decide.
        const dispute = event.data.object;
        await supa.from("activity_log").insert({
          agent: "stripe-webhook",
          action: "dispute_created",
          detail: JSON.stringify({
            payment_intent: dispute.payment_intent,
            amount: dispute.amount,
            reason: dispute.reason,
            status: dispute.status,
          }),
        });
        console.error("Stripe dispute opened:", dispute.payment_intent, dispute.reason);
        break;
      }

      default:
        // Unhandled types still get a 200 so Stripe stops retrying them.
        break;
    }

    return json({ received: true });
  } catch (e) {
    // Non-2xx makes Stripe retry with backoff, which is what we want for a
    // transient DB error.
    console.error("stripe-webhook failed:", event?.type, e);
    return json({ error: String(e) }, 500);
  }
});
