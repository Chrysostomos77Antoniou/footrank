# Supabase (schema + Edge Functions)

Until now the FootRank database and Edge Functions were managed directly in the
Supabase dashboard and were not version-controlled. This directory starts
tracking them. It is **not** a full dump of the existing schema — the tables,
RLS policies and RPCs that predate it still live only in the project. New
changes should land here as migrations.

Project ref: `yspccychuwvlrjgioqss` (region `eu-central-1`, Postgres 17).

## Layout

```
migrations/    timestamped SQL, applied in order
functions/     Deno Edge Functions, one directory per function
config.toml    per-function settings (crucially verify_jwt)
```

## Payments (match fee)

FootRank charges a **€2 platform fee per team** on a confirmed match, paid by
that team's captain — €4 per match total. The **pitch rental is not handled by
the app**: teams settle that with the venue directly, in cash, as they always
have.

That is a deliberate choice. Routing the pitch money through FootRank would
require Stripe Connect, a KYC'd connected account per venue, payout runs, and
would put us in escrow/PSD2 territory — for money that isn't ours. Fee-only
means everything landing in the Stripe account is revenue, so there is nobody to
pay out to.

**Do not describe a paid match as a reserved pitch.** We do not own venue
inventory and cannot guarantee a slot.

### Pieces

| Piece | What it does |
|---|---|
| `match_payments` table | One row per (match, team); the only writer is the service role |
| `matches.payment_status` | Derived `unpaid` / `awaiting_payment` / `paid`, advisory only |
| `recalc_match_payment_status(uuid)` | Single source of truth for that derived value; service_role only |
| `create-match-payment` | Captain-called; creates/resumes a PaymentIntent, returns `client_secret` |
| `stripe-webhook` | The **only** thing that may mark a fee `succeeded` |

Payment is currently **additive and non-enforcing**: nothing blocks an unpaid
match from being played, scored or rated. Gating on payment is a separate
decision.

### Required secrets

Set these on the project (Dashboard → Edge Functions → Secrets, or
`supabase secrets set`). The functions are inert until they exist —
`create-match-payment` returns 500 without a key, and `stripe-webhook` refuses
to trust any event without a signing secret.

| Secret | Where it comes from |
|---|---|
| `STRIPE_SECRET_KEY` | Stripe Dashboard → Developers → API keys (`sk_test_…` first) |
| `STRIPE_WEBHOOK_SECRET` | Shown when you create the webhook endpoint (`whsec_…`) |
| `MATCH_FEE_CENTS` | Optional, defaults to `200` (€2). Change the fee here, not in code |
| `MATCH_FEE_CURRENCY` | Optional, defaults to `eur` |

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically.

The app additionally needs the Stripe **publishable** key, passed at build time
like the Supabase config (`--dart-define=STRIPE_PUBLISHABLE_KEY=pk_…`). Never
put a secret key in the client.

### Stripe dashboard setup

1. Create the webhook endpoint pointing at:
   `https://yspccychuwvlrjgioqss.supabase.co/functions/v1/stripe-webhook`
2. Subscribe it to exactly these events:
   - `payment_intent.succeeded`
   - `payment_intent.payment_failed`
   - `charge.refunded`
   - `charge.dispute.created`
3. Copy the signing secret into `STRIPE_WEBHOOK_SECRET`.

### ⚠️ verify_jwt on stripe-webhook

`stripe-webhook` **must** run with `verify_jwt = false`. Stripe cannot send a
Supabase JWT, so with it on, Supabase's gateway returns 401 before the handler
runs and every event silently fails. `config.toml` pins this for CLI deploys,
but a function deployed through the Management API defaults to `true` — check
Dashboard → Edge Functions → `stripe-webhook` → Details and turn JWT
verification **off** after any such deploy.

Turning it off does not make the endpoint open: the function verifies Stripe's
HMAC signature (with a 5-minute replay tolerance) and rejects anything
unsigned.

### Deploying

```bash
supabase functions deploy create-match-payment
supabase functions deploy stripe-webhook   # honours config.toml
supabase db push                           # applies migrations/
```

### Testing before going live

Use `sk_test_…` keys and Stripe's test cards. Worth exercising specifically:

- `4242 4242 4242 4242` — success; check the row flips to `succeeded` and, once
  both teams pay, `matches.payment_status` becomes `paid`.
- `4000 0000 0000 0002` — decline; row should go `failed` with a
  `failure_reason`, and the captain should be able to retry.
- `4000 0027 6000 3184` — 3DS/SCA challenge (mandatory in the EU under PSD2).
- Use the Stripe CLI (`stripe listen`) or resend an event twice to confirm the
  webhook is idempotent — a replay must not change an already-`succeeded` row.
- Refund a test payment and confirm `payment_status` drops back to
  `awaiting_payment`.
