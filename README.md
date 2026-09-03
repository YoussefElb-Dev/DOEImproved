# DOEImproved

A commercial-grade, dark-glassmorphism student portal for **NYC Public Schools** — connects to TeachHub via in-app SSO WebView, captures the authenticated session, and renders a live grade dashboard with **What-If** grade projections.

## Features

- **SSO Login** — embedded WebView loads `https://teachhub.schools.nyc`, detects the authenticated redirect, captures session cookies, and persists them with `flutter_secure_storage`
- **GPA Dashboard** — glassmorphism hero card with GPA, glowing term-change badge, class rank & credits
- **Course Feed** — per-course tile with semantic grade color, glow, current %, and distance to next grade boundary
- **What-If Slider** — recalculates category-weighted averages in real time as you drag hypothetical scores
- **Course Detail** — category breakdown with progress bars, assignment list, per-category What-If sliders
- **Fully themed** — OLED `#0D0F12` background, Inter typography via `google_fonts`, grade colors A `#00F5A0` / B `#00D2FF` / C `#FFB800` / D–F `#FF4B4B`

## Stack

| Concern | Package |
|---|---|
| State | `flutter_riverpod` |
| Typography | `google_fonts` (Inter) |
| Secure storage | `flutter_secure_storage` |
| Auth WebView | `webview_flutter` |

## Project structure

```
lib/
├── main.dart                       # app entry + AuthGate (SSO → dashboard)
├── models/grade_models.dart        # StudentProfile, Course, GradeCategory, Assignment
├── core/theme/app_theme.dart       # colors, GlassContainer, ThemeData
├── services/
│   ├── auth_webview_service.dart   # WebView SSO + cookie capture + secure session
│   └── calculator_service.dart     # weighted averages, What-If, requiredScore()
├── controllers/grade_controllers.dart
├── storage/
│   ├── mock_data.dart              # realistic mock student + 4 courses
│   └── state_providers.dart        # Riverpod providers + sync pulse
├── views/
│   ├── dashboard_screen.dart       # header, GPA hero, course feed
│   └── widgets/                    # gpa_hero_card, course_card, what_if_slider
test/
├── calculator_service_test.dart    # unit tests for the grade math
└── widget_test.dart
```

## Getting started

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

## Notes

- The dashboard prepopulates with mock data from `lib/storage/mock_data.dart` while session-based grade parsing is a next step.
- `document.cookie` in the WebView only sees non-HttpOnly cookies; for the full TeachHub session you'll harvest cookies natively via the platform `WebViewCookieManager` channel on the authenticated redirect — the capture hook is in `AuthWebViewService._handlePageFinished`.

> For personal/educational use. Not affiliated with NYC Public Schools.