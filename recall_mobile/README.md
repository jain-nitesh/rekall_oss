# ReKall Mobile

Flutter app for ReKall — save anything from your phone, AI organizes it, semantic search finds it later.

Works with both **ReKall Cloud** (hosted, no setup) and **self-hosted** backends.

---

## Architecture

```
ReKall_mobile/lib/
├── config/
│   └── environment.dart        # API base URL resolution (debug / release / dart-define)
├── models/                     # Plain Dart data classes (JSON serializable)
├── providers/                  # Riverpod state providers
├── router/
│   └── app_router.dart         # GoRouter + redirect logic (auth guard, server-config guard)
├── screens/                    # UI — one folder per feature
│   ├── auth/                   # Email + OAuth sign-in screens
│   ├── brain/                  # Chat, entity detail, wiki pages
│   ├── capture/                # In-app camera / media capture
│   ├── collections/            # Create, list, explore collections
│   ├── connections/            # AI-discovered connections and clusters
│   ├── content/                # Detail view for a saved item
│   ├── home/                   # Memory feed (main tab)
│   ├── onboarding/             # First-launch carousel + server selection
│   ├── profile/                # Settings, notifications, bookmarks import
│   ├── search/                 # Full-text + semantic search
│   └── spaces/                 # Shared spaces — create, join, explore
├── services/                   # Platform / external integrations
│   ├── api_service.dart        # Dio HTTP client — all backend calls
│   ├── analytics_service.dart  # Firebase Analytics
│   ├── apple_auth_service.dart # Sign in with Apple
│   ├── background_sync_service.dart  # WorkManager background jobs
│   ├── fcm_service.dart        # Firebase Cloud Messaging (push notifications)
│   ├── google_auth_service.dart
│   ├── pending_shares_service.dart   # Queue for shares received while offline
│   ├── share_handler_service.dart    # receive_sharing_intent stream adapter
│   ├── shared_storage_service.dart   # App Group storage for iOS Share Extension
│   └── source_app_detector.dart      # Detects which app the share came from
├── utils/
│   ├── constants.dart
│   ├── haptics.dart
│   ├── static_data.dart
│   ├── theme.dart              # Light + dark MaterialTheme
│   └── toast_helper.dart
└── widgets/                    # Reusable UI components
```

### State Management

[Riverpod](https://riverpod.dev/) (`flutter_riverpod`). Every piece of app state lives in a `Provider`, `StateNotifierProvider`, or `AsyncNotifierProvider` under `lib/providers/`.

Key providers:

| Provider | Purpose |
|----------|---------|
| `authProvider` | Current auth status + user session |
| `serverConfigProvider` | Persisted server URL (Cloud vs self-hosted) |
| `contentProvider` | Feed items — optimistic adds, dedup, background sync |
| `searchProvider` | Full-text + semantic search results |
| `brainProvider` | Chat conversation state |

### Navigation

[GoRouter](https://pub.dev/packages/go_router) (`go_router`). Routes are declared in `router/app_router.dart`. A `_RouterNotifier` (ChangeNotifier) listens to `authProvider` and `serverConfigProvider` and triggers GoRouter redirects when either changes — no router rebuild needed.

**Redirect logic:**

```
/splash     → always allow (loading screen)
/invite/:id → always allow (universal link handled before auth check)
unauthenticated + no server config  → /onboarding
unauthenticated + server config set → /auth
authenticated + on auth screen      → /  (redirect to home)
```

### Share Extension (iOS)

The iOS Share Extension (`ios/ShareExtension/`) captures content from any app and writes it to an **App Group** shared container (`SharedStorageService`). On the next app foreground event, `processPendingSharesImmediately()` drains the queue and uploads to the backend.

Android uses `receive_sharing_intent` which delivers shares via a stream directly to the running app.

### Deep Links / Universal Links

| Scheme | Example | Purpose |
|--------|---------|---------|
| `rekall://invite/TOKEN` | Custom URL scheme | Space invitations (fallback) |
| `https://YOUR_BACKEND/invite/TOKEN` | Universal link | Space invitations (preferred) |
| `https://YOUR_BACKEND/auth/magic/TOKEN` | Magic link | Passwordless email login |

---

## Getting Started

### Prerequisites

- Flutter SDK >= 3.10
- Dart SDK >= 3.0
- Android Studio or Xcode (for device/simulator)
- A running ReKall backend (see root `README.md`)

### Install dependencies

```bash
cd Recall_mobile
flutter pub get
```

### Run (debug)

```bash
# Default: connects to https://YOUR_BACKEND/api 
flutter run

# Override backend URL (e.g. local dev server)
flutter run --dart-define=API_URL=http://192.168.1.100:8000/api
```

### Release build

```bash
# Android APK
flutter build apk --release

# iOS
flutter build ios --release
```

---

## Key Dependencies

| Package | Purpose |
|---------|---------|
| `flutter_riverpod` | State management |
| `go_router` | Declarative navigation |
| `dio` | HTTP client |
| `shared_preferences` | Key-value persistence |
| `flutter_secure_storage` | Secure token storage |
| `receive_sharing_intent` | Android/iOS share sheet integration |
| `google_sign_in` | Google OAuth |
| `sign_in_with_apple` | Apple Sign-In |
| `firebase_messaging` | Push notifications (FCM) |
| `firebase_analytics` | Usage analytics |
| `camera` / `image_picker` | Media capture |
| `workmanager` | Background sync jobs |
| `app_links` | Deep link / universal link handling |
| `google_fonts` | Typography |

---

## Environment & Config

API URL resolution order (`config/environment.dart`):

1. `--dart-define=API_URL=...` — highest priority, overrides everything
2. Release build (`dart.vm.product == true`) → `https://YOUR_BACKEND/api`
3. Debug build → `https://YOUR_BACKEND/api` (or your `_laptopWifiIp` if set)

The server URL chosen by the user on first launch (Cloud vs self-hosted) is persisted via `serverConfigProvider` and overrides the compile-time default at runtime.

---

## First Launch Flow

```
Splash → Onboarding carousel → Server selection
  ├─ ReKall Cloud  → /auth (Google / Apple / email)
  └─ Self-hosted   → Enter backend URL → /auth (email only)
                                           ↓
                                        Home (memory feed)
```

To reset and return to server selection: **Settings → Switch server** clears the stored server config and auth token, returning to the onboarding carousel.

---

## Testing

```bash
flutter test
```

Unit tests live in `test/`. The project uses `mocktail` for mocking.
