// The single Telegram path for database-triggered match alerts.
//
// WHY THIS EXISTS: confirm_fixture() and accept_match_proposal() used to post to
// the mission-control app on Vercel, which turned that webhook into a Telegram
// message. That app is disabled -- it answers 402 DEPLOYMENT_DISABLED -- so the
// alerts silently stopped even though the database was posting correctly. This
// function talks to api.telegram.org directly, removing Vercel from the path.
//
// The database cannot call Telegram itself: the bot token lives in Edge Function
// secrets, which Postgres cannot read. So the DB calls here with the service-role
// key (which it does hold, in the vault) and this function holds the Telegram
// credentials. verify_jwt = true keeps it service-role only.
//
// Input: { match_id: uuid, kind?: "fixture_confirmed" }
//
// Always returns 200 with a report: a caller must never fail because an alert
// could not be delivered -- the match is confirmed either way.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN");
const CHAT_ID = Deno.env.get("TELEGRAM_CHAT_ID");

const ok = (body: unknown) =>
  new Response(JSON.stringify(body), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });

/// Name + phone for a team's captain, so whoever reads the alert can ring them
/// without opening the app. Mirrors what the mission-control payload carried.
async function captain(
  supa: ReturnType<typeof createClient>,
  teamId: string | null | undefined,
): Promise<string> {
  if (!teamId) return "-";
  const { data: team } = await supa
    .from("teams")
    .select("captain_id")
    .eq("id", teamId)
    .maybeSingle();
  const id = team?.captain_id as string | undefined;
  if (!id) return "-";
  const { data: user } = await supa
    .from("users")
    .select("name")
    .eq("id", id)
    .maybeSingle();
  const { data: contact } = await supa
    .from("user_contacts")
    .select("phone")
    .eq("user_id", id)
    .maybeSingle();
  const name = (user?.name as string | undefined) ?? "Captain";
  const phone = contact?.phone as string | undefined;
  return phone ? `${name} (${phone})` : name;
}

Deno.serve(async (req) => {
  if (!TOKEN || !CHAT_ID) {
    console.log("Telegram not configured; skipping");
    return ok({ sent: false, reason: "telegram not configured" });
  }

  try {
    const { match_id } = await req.json().catch(() => ({}));
    if (!match_id) return ok({ sent: false, reason: "match_id required" });

    const supa = createClient(SUPABASE_URL, SERVICE_ROLE);

    const { data: m } = await supa
      .from("matches")
      .select(
        "city, scheduled_at, match_type, format, home_team_id, away_team_id, " +
          "home_team:home_team_id(name), away_team:away_team_id(name), " +
          "suggested_court:suggested_court_id(name, address, phone)",
      )
      .eq("id", match_id)
      .maybeSingle();
    if (!m) return ok({ sent: false, reason: "match not found" });

    // Cyprus local time -- the fixture is in Cyprus and so is the reader.
    const kickoff = new Date(m.scheduled_at as string).toLocaleString("en-GB", {
      weekday: "short",
      day: "numeric",
      month: "short",
      hour: "2-digit",
      minute: "2-digit",
      timeZone: "Asia/Nicosia",
    });

    const court = m.suggested_court as
      | { name?: string; address?: string; phone?: string }
      | null;
    const home = (m.home_team as { name?: string } | null)?.name ?? "Home";
    const away = (m.away_team as { name?: string } | null)?.name ?? "Away";

    // Plain text, not Markdown: a team name containing * or _ would make
    // Telegram reject the whole message, and a delivered plain message beats a
    // bold one that 400s.
    const lines = [
      "⚽ Match confirmed",
      "",
      `${home} vs ${away}`,
      `📅 ${kickoff}`,
      `📍 ${court?.name ? court.name + ", " : ""}${m.city}`,
    ];
    if (court?.address) lines.push(`   ${court.address}`);
    if (court?.phone) lines.push(`   ☎ Court: ${court.phone}`);
    lines.push("");
    lines.push(`Home captain: ${await captain(supa, m.home_team_id as string)}`);
    lines.push(`Away captain: ${await captain(supa, m.away_team_id as string)}`);
    lines.push("");
    lines.push(`${m.match_type} · ${m.format}`);

    const res = await fetch(`https://api.telegram.org/bot${TOKEN}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ chat_id: CHAT_ID, text: lines.join("\n") }),
    });
    const body = await res.text();
    if (!res.ok) console.error("Telegram sendMessage failed:", res.status, body);
    return ok({ sent: res.ok, status: res.status });
  } catch (e) {
    console.error("notify-telegram threw:", e);
    return ok({ sent: false, error: String(e) });
  }
});
