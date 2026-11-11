# Deploys the hardened edge functions to the LIVE FootRank project.
# Run from the repo root in PowerShell:   .\tool\deploy-functions-live.ps1
# The first run opens a browser to log in to Supabase.
#
# Order matters: deploy these BEFORE running
# supabase/migrations/20261111190000_security_hardening.sql, because that
# migration removes the service-role key the old notify-telegram relied on.
$ErrorActionPreference = "Stop"
$ref = "yspccychuwvlrjgioqss"

npx --yes supabase@latest login
npx --yes supabase@latest functions deploy notify-telegram --project-ref $ref --no-verify-jwt
npx --yes supabase@latest functions deploy send-push       --project-ref $ref --no-verify-jwt
npx --yes supabase@latest functions deploy delete-account  --project-ref $ref
npx --yes supabase@latest functions deploy telegram-test   --project-ref $ref --no-verify-jwt
Write-Host "All four functions deployed. Now run the security migration in the SQL editor."
