// Cron-driven sweep: cancels a confirmed match whose fee(s) are still unpaid
// once kickoff is within MATCH_FEE_DEADLINE_MINUTES (30 minutes, chosen by the
// user). Invoked by pg_cron ("payment-deadline-sweep", every 5 minutes) via
// net.http_post -- there is no user session, so auth is a shared secret rather
// than a Supabase JWT. Deployed with verify_jwt = false for the same reason
// stripe-webhook is: the caller cannot present a user JWT.
//
// AUTHORIZATION: the incoming Authorization: Bearer <token> header must match
// PAYMENT_SWEEP_SECRET exactly (set manually in Edge Function secrets to the
// same value as the `payment_sweep_cron_token` Vault secret the cron job's
// SQL reads). Anything else is rejected outright -- this function can cancel
// matches and dock ELO, so it must never be reachable by an end-user client.
//
// For each overdue match, auto_cancel_unpaid_match() does the DB-side work:
// it turns whichever side already paid into a CREDIT for that team's next
// match (issue_match_fee_credits) -- the money is not refunded to the card --
// deletes the match, applies the ELO penalty for a one-sided non-payer,
// reopens the paying side(s) and notifies both captains. That RPC is locked to
// service_role, which is exactly what this function authenticates as.
//
// A fee waived by a promo code or covered by a credit (status 'waived')
// counts as settled: that team is never cancelled or penalised for not paying.
//
// One match failing (a transient DB error) must never abort the sweep for
// every other match, so each match is wrapped in its own try/catch.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SWEEP_SECRET = Deno.env.get("PAYMENT_SWEEP_SECRET");
const DEADLINE_MINUTES = Number(
  Deno.env.get("MATCH_FEE_DEADLINE_MINUTES") ?? "30",
);

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

type PaymentRow = {
  team_id: string;
  status: string;
};

/// A fee is settled when it was paid through Stripe or waived (promo/credit).
const isSettled = (p?: PaymentRow) =>
  p?.status === "succeeded" || p?.status === "waived";

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

    if (!SWEEP_SECRET) {
      console.error("PAYMENT_SWEEP_SECRET not set -- refusing to run");
      return json({ error: "sweep not configured" }, 500);
    }
    const authHeader = req.headers.get("Authorization") ?? "";
    const presented = authHeader.replace(/^Bearer\s+/i, "");
    if (!presented || !timingSafeEqual(presented, SWEEP_SECRET)) {
      console.error("payment-deadline-sweep: rejected -- bad or missing bearer token");
      return json({ error: "unauthorized" }, 401);
    }

    const supa = createClient(SUPABASE_URL, SERVICE_ROLE);

    const { data: enabled, error: flagErr } = await supa.rpc("config_flag", {
      p_key: "match_fee_enabled",
      p_default: false,
    });
    if (flagErr) throw flagErr;
    if (!enabled) return json({ ok: true, swept: 0, reason: "match_fee_enabled is off" });

    const deadline = new Date(Date.now() + DEADLINE_MINUTES * 60_000).toISOString();

    const { data: matches, error: matchesErr } = await supa
      .from("matches")
      .select("id, home_team_id, away_team_id, scheduled_at")
      .eq("status", "confirmed")
      .neq("payment_status", "paid")
      .lte("scheduled_at", deadline);
    if (matchesErr) throw matchesErr;

    const rows = matches ?? [];
    const results: Array<{ match_id: string; ok: boolean; detail?: string }> = [];

    for (const m of rows) {
      const matchId = m.id as string;
      try {
        const { data: payments, error: paymentsErr } = await supa
          .from("match_payments")
          .select("team_id, status")
          .eq("match_id", matchId);
        if (paymentsErr) throw paymentsErr;

        const byTeam = new Map<string, PaymentRow>();
        for (const p of (payments ?? []) as PaymentRow[]) byTeam.set(p.team_id, p);

        const homePaid = isSettled(byTeam.get(m.home_team_id as string));
        const awayPaid = isSettled(byTeam.get(m.away_team_id as string));

        if (homePaid && awayPaid) {
          // Already settled since the query ran (e.g. the second payment's
          // webhook landed a moment ago) -- nothing to cancel.
          results.push({ match_id: matchId, ok: true, detail: "already paid, skipped" });
          continue;
        }

        const { data: cancelResult, error: cancelErr } = await supa.rpc(
          "auto_cancel_unpaid_match",
          { p_match_id: matchId, p_home_paid: homePaid, p_away_paid: awayPaid },
        );
        if (cancelErr) throw cancelErr;

        results.push({ match_id: matchId, ok: true, detail: JSON.stringify(cancelResult) });
      } catch (e) {
        console.error("payment-deadline-sweep: match failed:", matchId, e);
        results.push({ match_id: matchId, ok: false, detail: String(e) });
      }
    }

    return json({ ok: true, swept: rows.length, results });
  } catch (e) {
    console.error("payment-deadline-sweep failed:", e);
    return json({ error: String(e) }, 500);
  }
});
