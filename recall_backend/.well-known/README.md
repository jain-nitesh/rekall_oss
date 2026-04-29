# .well-known Configuration Files

This directory contains configuration files for Universal Links (iOS) and App Links (Android).

## Apple App Site Association (iOS Universal Links)

**File:** `apple-app-site-association` (no extension)

**What you need to do:**
1. Get your Apple Team ID from https://developer.apple.com/account
2. Replace `YOUR_TEAM_ID` in the file with your actual Team ID
3. The bundle ID `com.recall.recallMobile` is already correct

**How to find your Team ID:**
- Log into Apple Developer Console
- Go to Account → Membership
- Your Team ID is shown there (10-character alphanumeric string)

---

## Android Asset Links (Android App Links)

**File:** `assetlinks.json`

**What you need to do:**
1. Get the SHA256 fingerprint of your app's signing certificate
2. Replace `REPLACE_WITH_YOUR_RELEASE_SHA256_FINGERPRINT` with your actual fingerprint

**How to get the SHA256 fingerprint:**

For **debug builds** (development):
```bash
cd recall_mobile/android
./gradlew signingReport
```
or
```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

For **release builds** (production):
```bash
keytool -list -v -keystore /path/to/your/release.keystore -alias your_alias_name
```

Copy the SHA256 fingerprint

**Note:** You'll need separate entries for debug and release builds if you want both to work.

---

## Testing

After deploying these files to your backend at `YOUR_BACKEND/.well-known/`:

**Test iOS Universal Links:**
```bash
curl YOUR_BACKEND/.well-known/apple-app-site-association
```

**Test Android App Links:**
```bash
curl YOUR_BACKEND/.well-known/assetlinks.json
```

**Verify iOS Universal Links:**
- Use Apple's validator: https://search.developer.apple.com/appsearch-validation-tool/
- Enter your domain: `YOUR_BACKEND_DOMAIN`

**Verify Android App Links:**
- Use Google's validator: https://developers.google.com/digital-asset-links/tools/generator
- Test with: `adb shell am start -a android.intent.action.VIEW -d "YOUR_BACKEND/invite/test-token"`
