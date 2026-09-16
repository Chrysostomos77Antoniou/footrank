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
const TELEGRAM_BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN");
const TELEGRAM_CHAT_ID = Deno.env.get("TELEGRAM_CHAT_ID");

/// Reject events older than this to blunt replay attempts (Stripe's own
/// recommended tolerance).
const TOLERANCE_SECONDS = 300;

function formatAmount(cents: number, currency: string): string {
  const symbol = currency?.toLowerCase() === "eur" ? "\u20ac" : "";
  return symbol
    ? `${symbol}${(cents / 100).toFixed(2)}`
    : `${(cents / 100).toFixed(2)} ${String(currency).toUpperCase()}`;
}


/// Posts a "both teams paid" summary straight to Telegram.
///
/// Deliberately NOT routed through the mission-control app. That deployment is
/// disabled on Vercel -- it answers 402 DEPLOYMENT_DISABLED -- which is what
/// silently killed the existing fixture-confirmed message even though the
/// database was posting correctly. Talking to api.telegram.org directly drops
/// that dependency, so this keeps working regardless of mission-control.
///
/// Sends plain text rather than Markdown on purpose: a team name containing
/// *, _ or [ would make Telegram reject a Markdown message outright, and a
/// delivered plain message beats a bold one that 400s.
///
/// Never throws. The money has already moved and the rows are already correct,
/// so a Telegram outage must not push the webhook into a non-2xx and make
/// Stripe retry a payment that is fully recorded.
async function sendMatchPaidTelegram(
  supa: ReturnType<typeof createClient>,
  matchId: string,
): Promise<void> {
  if (!TELEGRAM_BOT_TOKEN || !TELEGRAM_CHAT_ID) {
    console.log("Telegram not configured (TELEGRAM_BOT_TOKEN/CHAT_ID unset); skipping");
    return;
  }
  try {
    const { data: match } = await supa
      .from("matches")
      .select(
        "city, scheduled_at, match_type, format, " +
          "home_team:home_team_id(name), away_team:away_team_id(name), " +
          "suggested_court:suggested_court_id(name, address)",
      )
      .eq("id", matchId)
      .maybeSingle();
    if (!match) return;

    const { data: payments } = await supa
      .from("match_payments")
      .select("amount_cents, currency")
      .eq("match_id", matchId)
      .eq("status", "succeeded");

    const rows = payments ?? [];
    const total = rows.reduce(
      (sum: number, p: { amount_cents?: number }) => sum + (p.amount_cents ?? 0),
      0,
    );
    const currency = rows[0]?.currency ?? "eur";

    // Cyprus local time -- the fixture is in Cyprus and so is whoever reads this.
    const kickoff = new Date(match.scheduled_at as string).toLocaleString("en-GB", {
      weekday: "short",
      day: "numeric",
      month: "short",
      hour: "2-digit",
      minute: "2-digit",
      timeZone: "Asia/Nicosia",
    });

    const court = (match.suggested_court as { name?: string } | null)?.name;
    const home = (match.home_team as { name?: string } | null)?.name ?? "Home";
    const away = (match.away_team as { name?: string } | null)?.name ?? "Away";

    const text = [
      "\u2705 Both teams paid",
      "",
      `${home} vs ${away}`,
      `\ud83d\uddd3 ${kickoff}`,
      `\ud83d\udccd ${court ? court + ", " : ""}${match.city}`,
      `\ud83d\udcb6 ${formatAmount(total, currency)} collected (${rows.length} of 2 teams)`,
      `${match.match_type} \u00b7 ${match.format}`,
    ].join("\n");

    const res = await fetch(
      `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ chat_id: TELEGRAM_CHAT_ID, text }),
      },
    );
    if (!res.ok) {
      console.error("Telegram sendMessage failed:", res.status, await res.text());
    }
  } catch (e) {
    console.error("Telegram send threw:", e);
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
          await sendMatchPaidTelegram(supa, matchId);
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
