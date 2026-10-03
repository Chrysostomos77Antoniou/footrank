# Android release (Google Play)

## 1. Build the signed AAB (GitHub Actions)

The bundle must be signed with your **upload key**. That key never goes in git:
it is stored as GitHub secrets and the workflow builds with it.

### One-time: create the upload key
Skip this if you have ALREADY uploaded a build to Play: you must keep using that
same key. Otherwise (first upload ever), run on any computer with Java:

```bash
keytool -genkeypair -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias upload
base64 -w0 upload-keystore.jks    # macOS: base64 -i upload-keystore.jks
```

**Back up `upload-keystore.jks` and its passwords somewhere safe (password
manager + offline copy).** Play App Signing lets Google reset a lost upload key,
but it takes days.

### One-time: add repository secrets
GitHub → repo → Settings → Secrets and variables → Actions → New repository secret

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | output of the `base64` command above |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | `upload` (or your alias) |
| `ANDROID_KEY_PASSWORD` | key password |
| `SUPABASE_URL` | `https://yspccychuwvlrjgioqss.supabase.co` |
| `SUPABASE_ANON_KEY` | Supabase → Project Settings → API → anon / publishable key |
| `STRIPE_PUBLISHABLE_KEY` | **optional**, see "Payments" below |

### Every release
1. Bump the version in `pubspec.yaml` (`version: 1.1.1+NNN`). `NNN` becomes the
   Play `versionCode`: it must be higher than every upload before it.
2. GitHub → Actions → **Android release (signed AAB)** → Run workflow.
3. Download the `footrank-release-aab` artifact, unzip, upload `app-release.aab`
   in Play Console. Keep `footrank-dart-symbols` (stack-trace de-obfuscation).

A release build refuses to run without a real signing key, by design.

## 2. Payments on Android: decide before you ship
The €2 match fee is charged with Stripe. Google Play requires **Play Billing**
for digital goods and services, and a platform/facilitation fee can be judged
digital. If you leave `STRIPE_PUBLISHABLE_KEY` unset, the app hides all payment
UI (the existing kill switch), so Android ships without it. That is the safe
default until you have checked Google's payments policy for your case. Also note
the WELCOME promo already waives the fee until 15 Nov 2026.

## 3. Play Console checklist

**Release**
- [ ] New accounts: a *personal* developer account created after Nov 2023 needs
      a **closed test with 12+ testers opted in for 14 continuous days** before
      "Apply for production access". An open test (your screenshot) is optional.
- [ ] Play App Signing: accept (default).

**Store listing** (text is in `docs/STORE_LISTING.md`)
- [ ] App name, short description (max 80), full description
- [ ] App icon 512×512: `assets/branding/app_icon_512.png`
- [ ] Feature graphic 1024×500: `assets/branding/feature_graphic.png`
- [ ] 2–8 phone screenshots (see `docs/SCREENSHOTS_PLAN.md`)
- [ ] Category Sports; contact email; privacy policy URL
      `https://chrysostomos77antoniou.github.io/footrank/privacy.html`

**App content**
- [ ] **App access**: login is required → give Play a reviewer test account
      (email + password) and say a Cyprus mobile number is needed at sign-up.
      Create a dedicated reviewer account for this.
- [ ] **Account deletion**: in-app (Profile → Delete Account) and a web URL:
      `https://chrysostomos77antoniou.github.io/footrank/support.html`
- [ ] Ads: **No**. Target audience: 13+ (not designed for children).
- [ ] Content rating (IARC questionnaire): no violence/gambling/UGC chat → Everyone
- [ ] News app: No. Government app: No. Health: No.

**Data safety form** (answers match the app today)
- Collected: name, email, user IDs, **phone number** (required at sign-up: the
  listing doc says optional, the app makes it required), photos (avatar/logo),
  approximate location (city typed by the user), app activity (matches, ratings),
  crash logs/diagnostics, device ID (push token), purchase info (only if
  payments are enabled).
- Shared with third parties: Stripe (payments), Firebase (push, crash reports),
  Supabase (hosting/database), and Telegram (a captain's name and phone are posted
  to an internal alert chat when a match is confirmed). Disclose or stop doing it.
- Encrypted in transit: **Yes**. Users can request deletion: **Yes**.
- Data sold: **No**.

## 4. Before the first upload
- [ ] CI is green on `master` (it builds a release APK with R8 on every push).
- [ ] Test the release build on a real Android phone: sign-in, push
      notification, create team, Google sign-in (create an Android OAuth client for
      `com.footballcy.footrank` in Google Cloud Console with the SHA-1 from Play Console → Setup → App signing; `google-services.json` currently has none).
