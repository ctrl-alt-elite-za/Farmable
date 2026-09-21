# Farmable Flutter mobile app

This is the Flutter replacement for the retired Expo client. It currently implements only the issue #9 authentication/session flow: sign-up, sequential phone/email verification, password login and restoring a previously valid secure local session while offline.

```bash
cd apps/mobile
flutter pub get
flutter test
flutter analyze
flutter run
```

Set `--dart-define=API_BASE_URL=https://your-api.example` for a device-reachable API URL. The default is `http://10.0.2.2:8000` for an Android emulator.

`assets/models/` is intentionally a handoff location for issue #16. `VisionService` is a swappable interface only: this client does not bundle, invoke or claim support for a vision model yet.
