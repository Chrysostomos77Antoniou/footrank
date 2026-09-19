// Creates (or resumes) the EUR2 platform-fee PaymentIntent for one team on a
// confirmed match, and returns its client_secret for the app's Stripe
// PaymentSheet.
//
// AUTHORIZATION: the caller must be the *captain* of one of the two teams in
// the match. We verify the JWT in-code rather than relying only on the
// platform's verify_jwt setting, so the check can't be lost by a redeploy with
// the wrong flag.
//
// The amount is computed HERE, never accepted from the client -- otherwise a
// captain could pay 1 cent. It comes from MATCH_FEE_CENTS (default 200).
//
// Pitch rental is not part of this charge; see the match_payments migration.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY");
const FEE_CENTS = Number(Deno.env.get("MATCH_FEE_CENTS") ?? "200");
const CURRENCY = Deno.env.get("MATCH_FEE_CURRENCY") ?? "eur";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

/// Tells notify-telegram to send the single, combined "match confirmed & fee
/// paid" alert. Mirrors stripe-webhook's helper of the same name: that's the
/// normal path this fires from, but when a live webhook delivery gets
/// rejected (e.g. a mismatched STRIPE_WEBHOOK_SECRET) the reconcile branch
/// below is what actually flips a match to "paid" -- and until this existed,
/// that path fixed the payment record but never told Telegram, so a match
/// could reach paid_at="paid" and no one ever heard about it.
///
/// Never throws: the row is already correct by the time this runs, so a
/// Telegram outage must not turn into an error surfaced to the captain who
/// just confirmed their payment went through.
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

/// A PaymentIntent in one of these states can still be completed by the app,
/// so an interrupted attempt is resumed rather than duplicated.
const RESUMABLE = new Set([
  "requires_payment_method",
  "requires_confirmation",
  "requires_action",
  "processing",
]);

async function stripe(
  path: string,
  init: { method: "GET" | "POST"; body?: URLSearchParams; idempotencyKey?: string },
) {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
  };
  if (init.body) headers["Content-Type"] = "application/x-www-form-urlencoded";
  if (init.idempotencyKey) headers["Idempotency-Key"] = init.idempotencyKey;

  const res = await fetch(`https://api.stripe.com/v1/${path}`, {
    method: init.method,
    headers,
    body: init.body,
  });
  const data = await res.json();
  if (!res.ok) {
    throw new Error(
      `Stripe ${path} failed (${res.status}): ${data?.error?.message ?? JSON.stringify(data)}`,
    );
  }
  return data;
}

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
    if (!STRIPE_SECRET_KEY) return json({ error: "STRIPE_SECRET_KEY not set" }, 500);
    if (!Number.isInteger(FEE_CENTS) || FEE_CENTS <= 0) {
      return json({ error: "MATCH_FEE_CENTS misconfigured" }, 500);
    }

    // --- Authenticate the caller -------------------------------------------
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "unauthorized" }, 401);

    const supa = createClient(SUPABASE_URL, SERVICE_ROLE);
    const { data: userData, error: userErr } = await supa.auth.getUser(jwt);
    const uid = userData?.user?.id;
    if (userErr || !uid) return json({ error: "unauthorized" }, 401);
    // Stripe emails its own receipt to this address, which is the captain's
    // proof of payment. We deliberately don't build our own invoice: Stripe's
    // receipt is the authoritative record and needs no maintenance.
    const receiptEmail = userData?.user?.email ?? undefined;

    // --- Rate limit + validate input ----------------------------------------
    // Caps Stripe API cost/abuse from a captain double-tapping or a script
    // hammering this endpoint (idempotency already prevents duplicate
    // *charges*, but each call still costs a Stripe API round trip).
    const { data: allowed } = await supa.rpc("check_rate_limit", {
      p_key: `create-match-payment:${uid}`,
      p_max_count: 10,
      p_window_seconds: 60,
    });
    if (!allowed) {
      await supa.rpc("log_security_alert", {
        p_source: "create-match-payment",
        p_severity: "warning",
        p_detail: { reason: "rate_limit_exceeded", uid },
      }).catch(() => {});
      return json({ error: "rate_limited" }, 429);
    }

    const { match_id } = await req.json().catch(() => ({}));
    if (!match_id || typeof match_id !== "string" ||
        !/^[0-9a-f-]{36}$/i.test(match_id)) {
      return json({ error: "match_id required" }, 400);
    }

    // --- Load the match and work out which side the caller captains --------
    const { data: match, error: matchErr } = await supa
      .from("matches")
      .select("id, status, scheduled_at, home_team_id, away_team_id")
      .eq("id", match_id)
      .maybeSingle();
    if (matchErr) throw matchErr;
    if (!match) return json({ error: "match not found" }, 404);

    // Only a fixture both captains have agreed to is payable: 'pending' isn't
    // agreed yet, and completed/cancelled matches must never take new money.
    if (match.status !== "confirmed") {
      return json({ error: "match_not_payable", status: match.status }, 409);
    }

    const { data: captainedTeams, error: teamErr } = await supa
      .from("teams")
      .select("id")
      .eq("captain_id", uid)
      .in("id", [match.home_team_id, match.away_team_id]);
    if (teamErr) throw teamErr;

    const teamId = captainedTeams?.[0]?.id as string | undefined;
    if (!teamId) {
      // A non-captain trying to pay for someone else's match is either a
      // confused client or an IDOR probe (manipulated match_id) -- worth a
      // record either way.
      await supa.rpc("log_security_alert", {
        p_source: "create-match-payment",
        p_severity: "warning",
        p_detail: { reason: "not_a_captain_of_this_match", uid, match_id },
      }).catch(() => {});
      return json({ error: "not_a_captain_of_this_match" }, 403);
    }

    // --- Resume an in-flight attempt rather than double-charging -----------
    const { data: existing, error: existingErr } = await supa
      .from("match_payments")
      .select("id, status, stripe_payment_intent_id, amount_cents")
      .eq("match_id", match_id)
      .eq("team_id", teamId)
      .maybeSingle();
    if (existingErr) throw existingErr;

    if (existing?.status === "succeeded") {
      return json({ already_paid: true, amount_cents: existing.amount_cents });
    }

    if (existing?.stripe_payment_intent_id) {
      const pi = await stripe(`payment_intents/${existing.stripe_payment_intent_id}`, {
        method: "GET",
      });
      if (RESUMABLE.has(pi.status)) {
        return json({
          client_secret: pi.client_secret,
          payment_intent_id: pi.id,
          amount_cents: pi.amount,
          currency: pi.currency,
          resumed: true,
        });
      }
      // Stripe says it already succeeded but our row didn't catch the webhook
      // (e.g. a live webhook delivery that failed signature verification --
      // check stripe-webhook's logs if this keeps happening). Reconcile now
      // instead of charging the captain twice, and -- same as the webhook
      // path -- tell Telegram if this is the payment that completes the pair.
      if (pi.status === "succeeded") {
        await supa
          .from("match_payments")
          .update({ status: "succeeded", paid_at: new Date().toISOString() })
          .eq("id", existing.id);
        const { data: recalced } = await supa.rpc("recalc_match_payment_status", {
          p_match_id: match_id,
        });
        if (recalced === "paid") {
          await notifyTelegramBothPaid(match_id);
        }
        return json({ already_paid: true, amount_cents: pi.amount, reconciled: true });
      }
      // Anything else (canceled, or a decline we recorded as failed) falls
      // through and gets a brand-new PaymentIntent below.
    }

    // --- Create a fresh PaymentIntent -------------------------------------
    const body = new URLSearchParams({
      amount: String(FEE_CENTS),
      currency: CURRENCY,
      "automatic_payment_methods[enabled]": "true",
      description: `FootRank match fee (match ${match_id})`,
      "metadata[match_id]": match_id,
      "metadata[team_id]": teamId,
      "metadata[captain_id]": uid,
    });
    if (receiptEmail) body.set("receipt_email", receiptEmail);

    // Scoped to this row's current attempt so a double-tap collapses into one
    // PaymentIntent, while a genuine retry after a decline still gets a new one.
    const attemptKey = existing?.stripe_payment_intent_id ?? "first";
    const pi = await stripe("payment_intents", {
      method: "POST",
      body,
      idempotencyKey: `footrank:fee:${match_id}:${teamId}:${attemptKey}`,
    });

    const { error: upsertErr } = await supa.from("match_payments").upsert(
      {
        match_id,
        team_id: teamId,
        captain_id: uid,
        amount_cents: FEE_CENTS,
        currency: CURRENCY,
        stripe_payment_intent_id: pi.id,
        status: "pending",
        failure_reason: null,
      },
      { onConflict: "match_id,team_id" },
    );
    if (upsertErr) throw upsertErr;

    await supa.rpc("recalc_match_payment_status", { p_match_id: match_id });

    return json({
      client_secret: pi.client_secret,
      payment_intent_id: pi.id,
      amount_cents: FEE_CENTS,
      currency: CURRENCY,
    });
  } catch (e) {
    console.error("create-match-payment failed:", e);
    return json({ error: String(e) }, 500);
  }
});
