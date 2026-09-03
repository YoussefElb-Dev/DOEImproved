# DOEImproved

A dark-glassmorphism student portal companion for **NYC Public Schools**. It signs in
through TeachHub SSO in an in-app WebView, captures the authenticated session, and
renders live grades, schedule, upcoming work and transcript — with **What-If** grade
projections on top.

> Student-built. **Not affiliated with the NYC DOE.** There is no DOEImproved server:
> your session lives in the iOS keychain on your device, and the app talks only to
> `teachhub.schools.nyc`.

## Features

- **SSO login** — embedded WebView loads `https://teachhub.schools.nyc`, and the
  captured session is **validated against the dashboard** before it is accepted, so a
  half-finished login is never mistaken for a successful one
- **Native cookie bridge** — the SSO session cookies are `HttpOnly` and therefore
  invisible to `document.cookie`. A platform channel (`doe_improved/cookies`) reads the
  real WebView cookie jar on both platforms: `WKHTTPCookieStore` on iOS,
  `CookieManager` on Android. Without this, live data cannot work at all.
- **One sync, five sections** — dashboard, course details, schedule, transcript and
  upcoming work are pulled together into a single `PortalSnapshot`, so every tab agrees
  on the same data and the same timestamp
- **Real-time refresh** — pull-to-refresh on every tab, a manual refresh button, an
  automatic re-pull every 5 minutes, and a refresh when the app returns to the
  foreground
- **Honest states** — a `LIVE` / `DEMO` pill and a last-synced stamp, an explicit banner
  when sample data is showing, a partial-outage banner when one section fails, and a
  bounce back to sign-in when the portal rejects the session
- **GPA dashboard** — animated count-up, progress ring, credit-weighted GPA recomputed
  from the transcript, class rank and credits
- **Course detail** — category breakdown with weighted bars, assignment history with
  status colours, and a live What-If slider per category
- **Schedule** — an "in class / up next" card with a period progress bar, and the day's
  periods with the current one highlighted
- **Work & transcript** — assignments bucketed into Overdue / Due today / This week /
  Later, and a transcript grouped by term with a per-term GPA

## Stack

| Concern | Package |
|---|---|
| State | `flutter_riverpod` (`AsyncNotifier`) |
| Auth WebView | `webview_flutter` |
| Session storage | `flutter_secure_storage` (iOS keychain) |
| HTTP + parsing | `http`, `html` |
| Typography | `google_fonts` (Inter) |
| Preferences / files | `shared_preferences`, `path_provider`, `file_picker` |

## Project structure

```
lib/
├── main.dart                          # entry + AuthGate (SSO ↔ dashboard) + splash
├── core/theme/app_theme.dart          # colours, GlassContainer, Skeleton, StatusPill
├── models/
│   ├── grade_models.dart              # StudentProfile, Course, GradeCategory, Assignment
│   ├── schedule_models.dart           # ScheduleEntry, DaySchedule, TranscriptRecord, WorkItem
│   └── portal_snapshot.dart           # one consistent view of everything + LIVE/DEMO
├── services/
│   ├── auth_webview_service.dart      # SSO flow, cookie capture, session validation
│   ├── native_cookie_bridge.dart      # doe_improved/cookies platform channel
│   ├── grade_data_service.dart        # HTTP + timeouts + auth-expiry detection
│   ├── grade_parser.dart              # HTML → typed models
│   ├── portal_repository.dart         # one sync, concurrent sections, partial failure
│   └── calculator_service.dart        # weighted averages + What-If projections
├── storage/
│   ├── state_providers.dart           # providers, refresh, auto-refresh, lifecycle
│   ├── settings_store.dart            # profile photo persistence
│   └── mock_*.dart                    # sample data for DEMO mode
└── views/                             # root_shell + grades / schedule / work / settings

ios_native/Runner/                     # hand-written iOS sources applied over the
                                       # generated Xcode project in CI
```

## Building

`ios/` is **not** committed — CI runs `flutter create` to generate the Xcode project,
then copies `ios_native/Runner/` over it. This keeps a 20k-line `project.pbxproj` out of
the repo while still shipping hand-written native code. The build fails loudly if the
overlay does not apply.

```bash
flutter pub get
flutter test
flutter analyze
```

To build locally on a Mac:

```bash
flutter create --platforms ios --project-name doe_improved --org com.doeimproved .
cp ios_native/Runner/AppDelegate.swift ios/Runner/AppDelegate.swift
cp ios_native/Runner/Info.plist ios/Runner/Info.plist
flutter build ios --release --no-codesign
```

### CI

`.github/workflows/build-ipa.yml` builds an **unsigned** IPA on `macos-14` for every
push to `main`, every PR, and on demand via *Run workflow*. It analyzes, runs the test
suite, verifies the bundle identifier is `com.doeimproved.doeImproved`, then uploads
`DOEImproved-unsigned` as a build artifact.

The IPA is unsigned: install it with a sideloading tool that re-signs
(AltStore, Sideloadly), or re-sign it yourself.
