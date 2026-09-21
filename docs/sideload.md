# Installing Farmable on test phones

`apps/mobile` is now a Flutter project. This authentication change provides the
native Android and iOS runners required by issues #4 and #16, but it does not
claim physical-device camera, microphone, location, AR, or model verification.

## Configure the API

The API base URL is public build configuration, never a secret. Supply a
phone-reachable HTTPS URL without credentials, query parameters, or fragments:

```bash
flutter run --dart-define=API_BASE_URL=https://api.example
```

The Android emulator may use `http://10.0.2.2:8000`; cleartext networking is
restricted to that emulator loopback address. A physical phone cannot use
`localhost` or `10.0.2.2` to reach a developer computer.

## Android

```bash
cd apps/mobile
flutter pub get
flutter build apk --release --dart-define=API_BASE_URL=https://api.example
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

The `mobile` workflow also publishes `farmable-android-apk`. Real-device
camera/model verification remains part of issues #4 and #16.

## iOS

On a Mac with Xcode and an Apple development team configured:

```bash
cd apps/mobile
flutter pub get
flutter run --release --dart-define=API_BASE_URL=https://api.example
```

CI performs an unsigned iOS compile and publishes the resulting `Runner.app` as
`farmable-ios-unsigned`. Signing, installation on the demo iPhone, and the
seven-day free-development-certificate lifecycle remain issue #4 acceptance
work and must not be inferred from the unsigned CI build.

## Current device proof

The committed Maestro flow verifies account creation, phone and email fake OTP
checks, and reopening the verified local session after the API is stopped. It
does not stand in for physical-device permission, sensor, or model benchmarks.
