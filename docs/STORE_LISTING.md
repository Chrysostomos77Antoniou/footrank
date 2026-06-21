# FootRank — Store Listing Kit

Copy/paste material for Google Play Console and Apple App Store Connect.
Replace the privacy URL once GitHub Pages is enabled.

---

## App name
**FootRank**

## Subtitle / short description (Play: 80 chars max)
Rank up, find 5-a-side matches, and climb the football leaderboard.

## Promotional text (Apple, 170 chars)
Create your team, get matched with opponents in your city, log results, and
watch your Pitch Power rating rise. The fair way to play competitive 5-a-side.

## Full description
**FootRank turns your casual 5-a-side games into a real competitive ladder.**

Create a profile, build or join a team, and get matched against teams in your
city at a similar level. Play the match, agree the result, and watch your
ranking move.

**Features**
- ⚽ **Smart matchmaking** — find opponents in the same city, around the same
  time, at a similar rating.
- 🏆 **Pitch Power (PWR) rankings** — climb the player and team leaderboards.
- 👥 **Teams** — create a squad, invite players with a code, manage your roster.
- 📊 **Win/Loss records** — every team's form, front and centre.
- 🤝 **Fair results** — both captains confirm the score; a trust-based system
  resolves disputes.
- 🔔 **Match reminders & notifications.**
- 🔐 **Easy sign-in** with Google, Apple, or email.

Whether you're chasing the top of the table or just want fair, organised games,
FootRank keeps every match competitive.

## Keywords (Apple, 100 chars, comma-separated)
football,soccer,5-a-side,matchmaking,ranking,elo,team,league,futsal,sports,amateur,fixtures

## Category
- Primary: **Sports**
- Secondary (Play): **Health & Fitness** (optional)

## Content rating
- No objectionable content → expect **Everyone / 3+**.
- Play: complete the IARC questionnaire (no violence, gambling, etc.).
- Apple: **4+**.

## Privacy
- Privacy Policy URL: `https://chrysostomos77antoniou.github.io/footrank/privacy.html`
- Data collected: name, email, profile photo, city, gameplay stats.
- Used for: app functionality (account, matchmaking, rankings). Not sold.
- Provide an in-app **account deletion** path (planned) + email
  tomisapoelcity@gmail.com for deletion requests.

## Support
- Support email: tomisapoelcity@gmail.com

---

## Required visual assets (you must produce these)
### Google Play
- App icon: 512×512 PNG (you have the green FootRank icon).
- Feature graphic: 1024×500 PNG.
- Phone screenshots: 2–8, min 320px, 16:9 or 9:16 (e.g. Login, Home,
  Rankings, Matches, Team, Profile).

### Apple App Store
- App icon: 1024×1024 PNG (no alpha).
- iPhone 6.7" screenshots: 1290×2796 (3–10).
- iPhone 6.5" screenshots: 1242×2688.

> Tip: capture screenshots from the release build on your phone
> (Home, Rankings, Matches with WON/LOST badges, Team page, Profile).

---

## Pre-submission checklist
- [ ] App ID set to `com.footballcy.footrank` ✅ (done)
- [ ] Release signed with upload keystore ✅ (done — back up the .jks!)
- [ ] Privacy Policy live (enable GitHub Pages)
- [ ] Remove mock/test data from the database
- [ ] In-app account deletion path
- [ ] Firebase: register `com.footballcy.footrank` + new google-services.json
      (for push notifications)
- [ ] Supabase Pro: leaked-password protection, auth rate limits + CAPTCHA,
      spend cap
- [ ] Screenshots + feature graphic
- [ ] Content rating questionnaire
- [ ] Build the AAB: `flutter build appbundle --release`
      → android/app/outputs/bundle/release/app-release.aab
