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

function formatAmount(cents: number, currency: string): string {
  const symbol = currency?.toLowerCase() === "eur" ? "€" : "";
  return symbol
    ? `${symbol}${(cents / 100).toFixed(2)}`
    : `${(cents / 100).toFixed(2)} ${String(currency).toUpperCase()}`;
}

/// Tells notify-telegram to send the single, combined "match confirmed & fee
/// paid" alert. This is the ONLY Telegram path now -- confirm_fixture() and
/// accept_match_proposal() no longer send an alert at confirmation time, so
/// captains get exactly one Telegram message per match, once both fees are in,
/// instead of the old confirm-time + paid-time pair.
///
/// Never throws. The money has already moved and the rows are already correct,
/// so a Telegram outage must not push the webhook into a non-2xx and make
/// Stripe retry a payment that is fully recorded.
async function notifyTelegramBothPaid(matchId: string): Promise<void> {
  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/notify-telegram`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${SERVICE_ROLE}`,
      },
      body: JSON.stringify({ match_id: matchId, kind: "both_paid" }),
    });
    if (!res.ok) {
      console.error("notify-telegram call failed:", res.status, await res.text());
    }
  } catch (e) {
    console.error("notify-telegram call threw:", e);
  }
}

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

/// A short, irreversible fingerprint of the configured secret -- never the
/// secret itself -- so a failed verification's logs can show "the secret
/// Deno.env has right now hashes to X" without ever printing anything
/// recoverable. Comparing this value before/after re-pasting the secret in
/// the dashboard is the fastest way to confirm an edit actually took effect.
async function fingerprint(secret: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(secret));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, 12);
}

/// Verifies Stripe's `t=...,v1=...` signature header against the raw body.
/// Returns the parsed event, or null if the signature doesn't check out.
///
/// On failure this logs WHY (missing header, stale timestamp, or a mismatch)
/// plus a fingerprint of the secret actually loaded -- every failure used to
/// come back as an opaque 400 with nothing in the logs to diagnose, which is
/// exactly what let a wrong STRIPE_WEBHOOK_SECRET silently reject 100% of
/// deliveries for a live test session before anyone noticed.
async function verify(rawBody: string, header: string | null, secret: string) {
  if (!header) {
    console.error("stripe-webhook: rejected -- no Stripe-Signature header on request");
    return null;
  }

  let timestamp = "";
  const candidates: string[] = [];
  for (const part of header.split(",")) {
    const [k, v] = part.split("=", 2);
    if (k?.trim() === "t") timestamp = v?.trim() ?? "";
    // Stripe may send several v1 signatures during a secret rotation.
    if (k?.trim() === "v1" && v) candidates.push(v.trim());
  }
  if (!timestamp || candidates.length === 0) {
    console.error(
      "stripe-webhook: rejected -- signature header missing t= or v1=",
      { hasTimestamp: Boolean(timestamp), v1Count: candidates.length },
    );
    return null;
  }

  const age = Math.abs(Math.floor(Date.now() / 1000) - Number(timestamp));
  if (!Number.isFinite(age) || age > TOLERANCE_SECONDS) {
    console.error("stripe-webhook: rejected -- event outside tolerance window", {
      ageSeconds: age,
      toleranceSeconds: TOLERANCE_SECONDS,
    });
    return null;
  }

  const expected = await hmacSha256Hex(secret, `${timestamp}.${rawBody}`);
  if (!candidates.some((c) => timingSafeEqual(c, expected))) {
    console.error(
      "stripe-webhook: rejected -- signature mismatch. STRIPE_WEBHOOK_SECRET almost " +
        "certainly doesn't match this endpoint's signing secret in the Stripe dashboard " +
        "(Developers > Webhooks > this endpoint > reveal signing secret). Configured-secret " +
        "fingerprint (not the secret itself, just to tell 'changed' from 'same value again'):",
      await fingerprint(secret),
    );
    return null;
  }

  try {
    return JSON.parse(rawBody);
  } catch {
    console.error("stripe-webhook: rejected -- signature verified but body is not valid JSON");
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
        // Only a row that has NOT already succeeded may transition, so a
        // redelivery matches nothing and returns no rows. That is what makes
        // the receipt notification below exactly-once rather than once per
        // delivery attempt.
        const { data: rows, error } = await supa
          .from("match_payments")
          .update({
            status: "succeeded",
            paid_at: new Date().toISOString(),
            failure_reason: null,
          })
          .eq("stripe_payment_intent_id", pi.id)
          .in("status", ["pending", "failed"])
          .select("match_id, captain_id, amount_cents, currency");
        if (error) throw error;

        const row = rows?.[0];
        const matchId = row?.match_id ?? pi.metadata?.match_id;
        // The RPC returns the match's new derived status, so the "both teams
        // paid" moment is detected here rather than re-queried.
        let matchPaymentStatus: string | null = null;
        if (matchId) {
          const { data: recalced } = await supa.rpc("recalc_match_payment_status", {
            p_match_id: matchId,
          });
          matchPaymentStatus = (recalced as string | null) ?? null;
        }

        // In-app confirmation + push, so the captain has proof inside the app
        // and not only in Stripe's receipt email. Inserting into notifications
        // is what fires the push (see the trg_push_notification trigger).
        if (row?.captain_id) {
          const amount = formatAmount(row.amount_cents ?? 200, row.currency ?? "eur");
          const { error: notifyErr } = await supa.from("notifications").insert({
            user_id: row.captain_id,
            type: "fee_paid",
            title: "Match fee paid",
            body: `${amount} received for your team. A receipt has been emailed to you.`,
            reference_id: matchId ?? null,
          });
          // A missing receipt notification must never fail the webhook: the
          // money moved and the row is correct, so returning non-2xx here would
          // make Stripe retry a payment that is already fully recorded.
          if (notifyErr) console.error("fee_paid notification failed:", notifyErr);
        }

        // `row` is only set when THIS delivery actually transitioned a payment,
        // so a Stripe redelivery cannot re-announce a match that was already
        // announced -- the second fee is what flips the match to 'paid', and
        // only one delivery can do that.
        if (row && matchId && matchPaymentStatus === "paid") {
          await notifyTelegramBothPaid(matchId);
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
        // A chargeback costs far more than the EUR2 fee, so it needs a human.
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
